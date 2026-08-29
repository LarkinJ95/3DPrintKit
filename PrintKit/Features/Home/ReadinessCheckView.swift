import SwiftUI
import SwiftData

/// Print Readiness — the pre-flight check combining printer, spool, profile,
/// plate, nozzle, and the intended job.
struct ReadinessCheckView: View {
    @Environment(\.modelContext) private var context
    @Query private var printers: [PrinterDevice]
    @Query private var spools: [Spool]
    @Query private var profiles: [SlicerProfile]
    @Query private var sessions: [DryingSession]

    @State private var printer: PrinterDevice?
    @State private var spool: Spool?
    @State private var profile: SlicerProfile?
    @State private var plate: BuildPlate?
    @State private var nozzle: NozzleRecord?
    @State private var requiredGrams: Double = 0
    @State private var usesAMS = false
    @State private var supportMaterialID: String?

    private var result: ReadinessResult? {
        guard printer != nil || spool != nil else { return nil }
        let maintenanceDue = printer.flatMap { p in
            (p.maintenanceTasks ?? []).filter { $0.isDue(printerHours: p.totalPrintHours) }.count
        } ?? 0
        let dryingActive = sessions.contains { $0.isActive && $0.spool?.id == spool?.id }
        return ReadinessEngine.evaluate(.init(
            printer: printer, spool: spool, profile: profile, plate: plate,
            nozzle: nozzle, requiredGrams: requiredGrams,
            dryingActive: dryingActive, maintenanceDueCount: maintenanceDue,
            usesAMS: usesAMS, supportMaterialID: supportMaterialID
        ))
    }

    var body: some View {
        Form {
            Section("Setup") {
                Picker("Printer", selection: $printer) {
                    Text("Select…").tag(PrinterDevice?.none)
                    ForEach(printers) { Text($0.displayName).tag(PrinterDevice?.some($0)) }
                }
                .onChange(of: printer) { _, new in
                    nozzle = new?.currentNozzle
                    plate = new?.plates?.first
                }
                Picker("Spool", selection: $spool) {
                    Text("Select…").tag(Spool?.none)
                    ForEach(spools.filter { !$0.isArchived }) { Text($0.displayName).tag(Spool?.some($0)) }
                }
                Picker("Slicer Profile", selection: $profile) {
                    Text("None").tag(SlicerProfile?.none)
                    ForEach(profiles) { Text($0.name).tag(SlicerProfile?.some($0)) }
                }
                if let printer, !(printer.plates ?? []).isEmpty {
                    Picker("Build Plate", selection: $plate) {
                        Text("None").tag(BuildPlate?.none)
                        ForEach(printer.plates ?? []) { Text($0.displayName).tag(BuildPlate?.some($0)) }
                    }
                }
                if let printer, !(printer.nozzles ?? []).isEmpty {
                    Picker("Nozzle", selection: $nozzle) {
                        Text("Current").tag(NozzleRecord?.none)
                        ForEach(printer.nozzles ?? []) { Text($0.displayName).tag(NozzleRecord?.some($0)) }
                    }
                }
            }

            Section("Intended Print") {
                PKNumericField(label: "Filament required", value: $requiredGrams, unit: "g")
                Toggle("Uses AMS / MMU", isOn: $usesAMS)
                Picker("Support Material", selection: $supportMaterialID) {
                    Text("Same material / none").tag(String?.none)
                    ForEach(MaterialLibrary.shared.materials.filter { $0.family == "Support" }) {
                        Text($0.name).tag(String?.some($0.id))
                    }
                }
            }

            if let result {
                Section {
                    HStack(spacing: PK.Spacing.md) {
                        Image(systemName: result.isReady ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .font(.largeTitle)
                            .foregroundStyle(result.isReady ? Color.green : Color.orange)
                            .accessibilityHidden(true)
                        Text(result.headline)
                            .font(.title2.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }

                Section("Checks") {
                    ForEach(result.checks) { check in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: check.status.pkStatus.systemImage)
                                    .foregroundStyle(check.status.pkStatus.color)
                                Text(check.title).font(.subheadline.weight(.medium))
                                Spacer()
                                Text(check.status == .passed ? "Passed" : check.status == .warning ? "Warning" : "Failed")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(check.status.pkStatus.color)
                            }
                            Text(check.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(check.title): \(check.status.rawValue). \(check.detail)")
                    }
                }
            }
        }
        .navigationTitle("Print Readiness")
        .pkDismissableKeyboard()
        .navigationBarTitleDisplayMode(.inline)
    }
}
