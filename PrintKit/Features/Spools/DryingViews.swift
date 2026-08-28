import SwiftUI
import SwiftData
import ActivityKit

/// Start and manage filament drying sessions.
struct DryingStartView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var spools: [Spool]

    var prefilledSpool: Spool? = nil

    @State private var spool: Spool?
    @State private var dryerName = "Dryer 1"
    @State private var targetTemp = 65.0
    @State private var plannedHours = 6.0
    @State private var notes = ""

    private var material: FilamentMaterial? {
        guard let spool else { return nil }
        return MaterialLibrary.shared.material(for: spool.materialID)
    }

    var body: some View {
        Form {
            Section("Spool") {
                Picker("Spool", selection: $spool) {
                    Text("Select…").tag(Spool?.none)
                    ForEach(spools.filter { !$0.isArchived }) { Text($0.displayName).tag(Spool?.some($0)) }
                }
                .onChange(of: spool) { _, new in
                    if let material = new.flatMap({ MaterialLibrary.shared.material(for: $0.materialID) }) {
                        targetTemp = Double(material.dryTemp)
                        plannedHours = Double(material.dryHours)
                    }
                }
                if let material {
                    HStack {
                        Text("Reference for \(material.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        SourceTag(source: .reference)
                    }
                    Text("\(material.dryTemp) °C for \(material.dryHours)h — manufacturer instructions take precedence over this reference guidance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Session") {
                TextField("Dryer", text: $dryerName)
                Stepper(value: $targetTemp, in: 35...120, step: 5) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text("\(Int(targetTemp)) °C").monospacedDigit()
                    }
                }
                Stepper(value: $plannedHours, in: 1...24, step: 1) {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text("\(Int(plannedHours))h").monospacedDigit()
                    }
                }
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...4)
            }
        }
        .navigationTitle("Start Drying")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Start") { startSession() }
                    .disabled(spool == nil)
            }
        }
        .onAppear {
            if spool == nil { spool = prefilledSpool }
            if let material { targetTemp = Double(material.dryTemp); plannedHours = Double(material.dryHours) }
        }
    }

    private func startSession() {
        guard let spool else { return }
        let session = DryingSession()
        session.spool = spool
        session.materialID = spool.materialID
        session.dryerName = dryerName
        session.targetTempC = targetTemp
        session.plannedMinutes = plannedHours * 60
        session.startedAt = Date()
        session.notes = notes
        context.insert(session)
        try? context.save()

        NotificationService.scheduleDryingCompletion(session: session, spoolName: spool.displayName)
        DryingLiveActivityController.start(session: session, spoolName: spool.displayName)
        Haptics.success()
        dismiss()
    }
}

/// Live, ticking row for an active drying session.
struct DryingSessionRow: View {
    let session: DryingSession
    @Environment(\.modelContext) private var context

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            HStack(spacing: PK.Spacing.md) {
                Image(systemName: "humidity.fill")
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.spool?.displayName ?? "Spool")
                        .font(.subheadline.weight(.medium))
                    Text("\(Int(session.targetTempC)) °C · \(session.dryerName)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(session.plannedEnd, style: .timer)
                        .font(.subheadline.monospacedDigit())
                    Text("remaining")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Button("Done") {
                    session.completedAt = timeline.date
                    session.spool?.lastDriedDate = timeline.date
                    NotificationService.cancelDryingCompletion(sessionID: session.id)
                    DryingLiveActivityController.stop(sessionID: session.id)
                    Haptics.success()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(PK.Spacing.md)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: PK.Radius.card))
        }
    }
}

/// Live Activity controller for the Lock Screen / Dynamic Island drying timer.
enum DryingLiveActivityController {
    static func start(session: DryingSession, spoolName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = DryingActivityAttributes(sessionID: session.id.uuidString, spoolName: spoolName)
        let state = DryingActivityAttributes.ContentState(
            endDate: session.plannedEnd,
            targetTempC: session.targetTempC
        )
        _ = try? Activity<DryingActivityAttributes>.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: session.plannedEnd),
            pushType: nil
        )
    }

    static func stop(sessionID: UUID) {
        Task {
            for activity in Activity<DryingActivityAttributes>.activities
            where activity.attributes.sessionID == sessionID.uuidString {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
