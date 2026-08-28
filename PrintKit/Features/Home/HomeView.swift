import SwiftUI
import SwiftData

/// Home dashboard — contextual workshop status first, then attention items,
/// active sessions, and quick actions. Sections can be reordered in Settings.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \Spool.lastUsedDate, order: .reverse) private var spools: [Spool]
    @Query private var dryingSessions: [DryingSession]
    @Query private var printers: [PrinterDevice]
    @Query private var tasks: [MaintenanceTask]
    @Query(sort: \PrintRecord.date, order: .reverse) private var prints: [PrintRecord]
    @Query(sort: \ProjectItem.createdAt, order: .reverse) private var projects: [ProjectItem]
    @Query(sort: \PrintQueueItem.priority) private var queue: [PrintQueueItem]

    @State private var showCommandCenter = false

    private var activeSpools: [Spool] { spools.filter { !$0.isArchived } }
    private var activeDrying: [DryingSession] { dryingSessions.filter(\.isActive) }
    private var lowSpools: [Spool] { activeSpools.filter { $0.status() == .low } }
    private var needsDryingSpools: [Spool] {
        activeSpools.filter { spool in
            spool.needsDrying && !activeDrying.contains { $0.spool?.id == spool.id }
        }
    }

    private var maintenanceDue: [(PrinterDevice, MaintenanceTask)] {
        var result: [(PrinterDevice, MaintenanceTask)] = []
        for printer in printers {
            for task in printer.maintenanceTasks ?? [] where task.isDue(printerHours: printer.totalPrintHours) {
                result.append((printer, task))
            }
        }
        return result
    }

    private var statusHeadline: String {
        if !activeDrying.isEmpty {
            if let first = activeDrying.first {
                let remaining = max(first.remainingInterval / 60, 0)
                return "Drying completes in \(Format.duration(minutes: remaining))."
            }
        }
        var attention = lowSpools.count + needsDryingSpools.count
        attention += maintenanceDue.count
        if attention == 0 && !activeSpools.isEmpty { return "Everything is ready to print." }
        if attention == 0 { return "Welcome to your workshop." }
        return "\(attention) item\(attention == 1 ? "" : "s") need attention."
    }

    private var statusLevel: PKStatus {
        if !maintenanceDue.isEmpty || !needsDryingSpools.isEmpty { return .attention }
        if !lowSpools.isEmpty || !activeDrying.isEmpty { return .info }
        return .ready
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PK.Spacing.lg) {

                // MARK: Workshop status
                SectionCard {
                    HStack(spacing: PK.Spacing.md) {
                        Image(systemName: statusLevel.systemImage)
                            .font(.title2)
                            .foregroundStyle(statusLevel.color)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Workshop Status")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(statusHeadline)
                                .font(.headline)
                        }
                        Spacer()
                    }
                }

                // MARK: Attention items
                if !lowSpools.isEmpty || !needsDryingSpools.isEmpty || !maintenanceDue.isEmpty {
                    VStack(alignment: .leading, spacing: PK.Spacing.sm) {
                        Text("Attention Required")
                            .font(.headline)
                        ForEach(lowSpools) { spool in
                            AttentionRow(icon: "arrow.down.circle", tint: .orange,
                                         title: "\(spool.displayName) is low",
                                         detail: Format.grams(spool.currentWeightG) + " remaining") {
                                router.selectedTab = .spools
                                router.deepLinkSpoolID = spool.id
                            }
                        }
                        ForEach(needsDryingSpools) { spool in
                            AttentionRow(icon: "humidity", tint: .orange,
                                         title: "\(spool.displayName) needs drying",
                                         detail: "Last dried \(Format.date(spool.lastDriedDate ?? spool.openedDate))") {
                                router.selectedTab = .spools
                                router.deepLinkSpoolID = spool.id
                            }
                        }
                        ForEach(maintenanceDue, id: \.1.id) { printer, task in
                            AttentionRow(icon: "screwdriver", tint: .orange,
                                         title: "\(task.title) — \(printer.displayName)",
                                         detail: task.dueDescription(printerHours: printer.totalPrintHours)) {
                                router.selectedTab = .garage
                            }
                        }
                    }
                }

                // MARK: Active drying
                if !activeDrying.isEmpty {
                    VStack(alignment: .leading, spacing: PK.Spacing.sm) {
                        Text("Active Drying")
                            .font(.headline)
                        ForEach(activeDrying) { session in
                            DryingSessionRow(session: session)
                        }
                    }
                }

                // MARK: Print readiness shortcut
                SectionCard(title: "Print Readiness") {
                    Text("Check printer, spool, nozzle, plate, and profile before committing a spool to a long print.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        router.perform(.checkReadiness)
                    } label: {
                        Label("Run Readiness Check", systemImage: "checkmark.shield")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                // MARK: Printers
                if !printers.isEmpty {
                    VStack(alignment: .leading, spacing: PK.Spacing.sm) {
                        Text("Printers")
                            .font(.headline)
                        ForEach(printers) { printer in
                            NavigationLink {
                                PrinterDetailView(printer: printer)
                            } label: {
                                PrinterStatusRow(printer: printer)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // MARK: Recently used spools
                if !activeSpools.isEmpty {
                    VStack(alignment: .leading, spacing: PK.Spacing.sm) {
                        HStack {
                            Text("Recent Spools").font(.headline)
                            Spacer()
                            NavigationLink("All Spools") { SpoolListView() }
                                .font(.subheadline)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: PK.Spacing.md) {
                                ForEach(Array(activeSpools.prefix(6))) { spool in
                                    NavigationLink { SpoolDetailView(spool: spool) } label: {
                                        SpoolMiniCard(spool: spool)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                // MARK: Print queue
                let openQueue = queue.filter { !$0.isDone }
                if !openQueue.isEmpty {
                    VStack(alignment: .leading, spacing: PK.Spacing.sm) {
                        Text("Print Queue").font(.headline)
                        ForEach(openQueue.prefix(4)) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.subheadline.weight(.medium))
                                    Text("\(Format.duration(minutes: item.estimatedMinutes)) · \(Format.grams(item.gramsRequired))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let spool = item.spool {
                                    let ready = spool.currentWeightG >= item.gramsRequired
                                    StatusBadge(status: ready ? .ready : .error,
                                                text: ready ? "Filament OK" : "Short \(Format.grams(item.gramsRequired - spool.currentWeightG))")
                                } else {
                                    StatusBadge(status: .inactive, text: "No spool")
                                }
                            }
                        }
                    }
                }

                // MARK: Recent prints
                if !prints.isEmpty {
                    VStack(alignment: .leading, spacing: PK.Spacing.sm) {
                        Text("Recent Prints").font(.headline)
                        ForEach(prints.prefix(4)) { record in
                            HStack {
                                Image(systemName: record.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(record.success ? Color.green : Color.red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.name.isEmpty ? "Print" : record.name).font(.subheadline)
                                    Text("\(Format.dateTime(record.date)) · \(Format.grams(record.gramsUsed))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .accessibilityLabel("\(record.name), \(record.success ? "succeeded" : "failed"), \(Format.grams(record.gramsUsed))")
                        }
                    }
                }

                // MARK: Quick actions
                VStack(alignment: .leading, spacing: PK.Spacing.sm) {
                    Text("Quick Actions").font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: PK.Spacing.md) {
                        ForEach(QuickAction.allCases) { action in
                            Button {
                                router.perform(action)
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: action.systemImage)
                                        .font(.title3)
                                    Text(action.title)
                                        .font(.caption2)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, PK.Spacing.md)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: PK.Radius.card))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("3DPrintKit")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCommandCenter = true
                } label: {
                    Image(systemName: "command")
                }
                .accessibilityLabel("Command Center")
            }
        }
        .sheet(isPresented: $showCommandCenter) {
            CommandCenterView()
        }
    }
}

struct AttentionRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PK.Spacing.md) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(PK.Spacing.md)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: PK.Radius.card))
        }
        .buttonStyle(.plain)
    }
}

struct SpoolMiniCard: View {
    let spool: Spool
    var body: some View {
        VStack(spacing: PK.Spacing.sm) {
            SpoolRingView(fraction: spool.remainingFraction, filamentColor: spool.color, lineWidth: 8)
                .frame(width: 64, height: 64)
            Text(spool.displayName)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(Format.grams(spool.currentWeightG))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(width: 110)
        .padding(.vertical, PK.Spacing.sm)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: PK.Radius.card))
    }
}

struct PrinterStatusRow: View {
    let printer: PrinterDevice

    private var dueCount: Int {
        (printer.maintenanceTasks ?? []).filter { $0.isDue(printerHours: printer.totalPrintHours) }.count
    }

    var body: some View {
        HStack(spacing: PK.Spacing.md) {
            Image(systemName: "printer.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(printer.displayName).font(.subheadline.weight(.medium))
                Text("\(Int(printer.totalPrintHours)) h total · \(printer.currentNozzle?.displayName ?? "no nozzle recorded")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(status: dueCount > 0 ? .attention : .ready,
                        text: dueCount > 0 ? "\(dueCount) maintenance due" : "Ready")
        }
        .padding(PK.Spacing.md)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: PK.Radius.card))
    }
}
