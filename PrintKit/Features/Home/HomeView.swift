import SwiftUI
import SwiftData

/// Home dashboard — workshop status first, then whatever needs attention,
/// active sessions, and the machines and filament in play.
///
/// Built as a `List` so rows stay lazy, sections match the rest of the app,
/// and pull-to-refresh can drive the sync engine.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \Spool.lastUsedDate, order: .reverse) private var spools: [Spool]
    @Query private var dryingSessions: [DryingSession]
    @Query private var printers: [PrinterDevice]
    @Query(sort: \PrintRecord.date, order: .reverse) private var prints: [PrintRecord]
    @Query(sort: \PrintQueueItem.priority) private var queue: [PrintQueueItem]

    @State private var showSearch = false

    private var activeSpools: [Spool] { spools.filter { !$0.isArchived } }
    private var activeDrying: [DryingSession] { dryingSessions.filter(\.isActive) }
    private var lowSpools: [Spool] { activeSpools.filter { $0.status() == .low } }
    private var needsDryingSpools: [Spool] {
        activeSpools.filter { spool in
            spool.needsDrying && !activeDrying.contains { $0.spool?.id == spool.id }
        }
    }

    private var maintenanceDue: [(PrinterDevice, MaintenanceTask)] {
        printers.flatMap { printer in
            (printer.maintenanceTasks ?? [])
                .filter { $0.isDue(printerHours: printer.totalPrintHours) }
                .map { (printer, $0) }
        }
    }

    // MARK: Attention

    private struct AttentionItem: Identifiable {
        let id: String
        let status: PKStatus
        let symbol: String
        let title: String
        let detail: String
        let open: () -> Void
    }

    private var attentionItems: [AttentionItem] {
        var items: [AttentionItem] = []
        for spool in lowSpools {
            items.append(.init(id: "low-\(spool.id)", status: .attention, symbol: "arrow.down.circle",
                               title: "\(spool.displayName) is low",
                               detail: "\(Format.grams(spool.currentWeightG)) remaining") {
                router.selectedTab = .spools
                router.deepLinkSpoolID = spool.id
            })
        }
        for spool in needsDryingSpools {
            items.append(.init(id: "dry-\(spool.id)", status: .warning, symbol: "humidity",
                               title: "\(spool.displayName) needs drying",
                               detail: "Last dried \(Format.date(spool.lastDriedDate ?? spool.openedDate))") {
                router.selectedTab = .spools
                router.deepLinkSpoolID = spool.id
            })
        }
        for (printer, task) in maintenanceDue {
            items.append(.init(id: "task-\(task.id)", status: .attention, symbol: "screwdriver",
                               title: task.title,
                               detail: "\(printer.displayName) · \(task.dueDescription(printerHours: printer.totalPrintHours))") {
                router.selectedTab = .garage
            })
        }
        return items.sorted { $0.status.urgency < $1.status.urgency }
    }

    // MARK: Status summary

    private var statusHeadline: String {
        if let first = activeDrying.first {
            let remaining = max(first.remainingInterval / 60, 0)
            return "Drying completes in \(Format.duration(minutes: remaining))"
        }
        let count = attentionItems.count
        if count > 0 {
            return count == 1 ? "1 item needs attention" : "\(count) items need attention"
        }
        if activeSpools.isEmpty { return "Welcome to your workshop" }
        return "Everything is ready to print"
    }

    private var statusDetail: String {
        if !activeDrying.isEmpty {
            return activeDrying.count == 1
                ? (activeDrying.first?.spool?.displayName ?? "One spool drying")
                : "\(activeDrying.count) spools drying"
        }
        if attentionItems.isEmpty && !activeSpools.isEmpty {
            let grams = activeSpools.reduce(0) { $0 + $1.currentWeightG }
            return "\(activeSpools.count) spool\(activeSpools.count == 1 ? "" : "s") · \(Format.grams(grams)) on hand"
        }
        return "Review the item below"
    }

    private var statusLevel: PKStatus {
        if let worst = attentionItems.first?.status { return worst }
        if !activeDrying.isEmpty { return .info }
        return activeSpools.isEmpty ? .inactive : .ready
    }

    private var isNewWorkshop: Bool { spools.isEmpty && printers.isEmpty }

    var body: some View {
        Group {
            if isNewWorkshop {
                PKEmptyState(symbol: "shippingbox",
                             title: "Set Up Your Workshop",
                             message: "Add a printer and your first spool, and PrintKit will track filament, drying, maintenance, and print history for you.",
                             actionTitle: "Add a Spool") {
                    router.perform(.addSpool)
                }
            } else {
                dashboard
            }
        }
        .navigationTitle("3DPrintKit")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search")
            }
        }
        .sheet(isPresented: $showSearch) {
            SearchView()
        }
    }

    private var dashboard: some View {
        List {
            // MARK: Status + shortcuts
            Section {
                WorkshopStatusCard(status: statusLevel,
                                   headline: statusHeadline,
                                   detail: statusDetail)
                ShortcutRow()
            }
            .listRowInsets(EdgeInsets(top: PK.Spacing.sm, leading: PK.Spacing.lg,
                                      bottom: PK.Spacing.sm, trailing: PK.Spacing.lg))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            // MARK: Attention
            if !attentionItems.isEmpty {
                Section("Needs Attention") {
                    ForEach(attentionItems.prefix(5)) { item in
                        Button(action: item.open) {
                            AttentionRow(status: item.status, symbol: item.symbol,
                                         title: item.title, detail: item.detail)
                        }
                        .buttonStyle(.plain)
                    }
                    if attentionItems.count > 5 {
                        Text("and \(attentionItems.count - 5) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: Active drying
            if !activeDrying.isEmpty {
                Section("Drying Now") {
                    ForEach(activeDrying) { session in
                        DryingSessionRow(session: session)
                    }
                }
            }

            // MARK: Readiness
            Section {
                NavigationLink(value: PushDestination.readiness) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Print Readiness Check").font(.subheadline.weight(.medium))
                            Text("Verify printer, spool, nozzle, plate, and profile before a long print.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            // MARK: Printers
            if !printers.isEmpty {
                Section("Printers") {
                    ForEach(printers) { printer in
                        NavigationLink {
                            PrinterDetailView(printer: printer)
                        } label: {
                            PrinterStatusRow(printer: printer)
                        }
                    }
                }
            }

            // MARK: Recent spools
            if !activeSpools.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: PK.Spacing.md) {
                            ForEach(Array(activeSpools.prefix(8))) { spool in
                                NavigationLink {
                                    SpoolDetailView(spool: spool)
                                } label: {
                                    SpoolMiniCard(spool: spool)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, PK.Spacing.lg)
                        .padding(.vertical, PK.Spacing.xs)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    HStack {
                        Text("Recent Spools")
                        Spacer()
                        Button("All") { router.selectedTab = .spools }
                            .font(.caption.weight(.semibold))
                            .textCase(nil)
                    }
                }
            }

            // MARK: Print queue
            let openQueue = queue.filter { !$0.isDone }
            if !openQueue.isEmpty {
                Section("Print Queue") {
                    ForEach(openQueue.prefix(4)) { item in
                        QueuePreviewRow(item: item)
                    }
                }
            }

            // MARK: Recent prints
            if !prints.isEmpty {
                Section("Recent Prints") {
                    ForEach(prints.prefix(4)) { record in
                        RecentPrintRow(record: record)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await SyncEngine.shared.syncNow(context: context)
        }
    }
}

// MARK: - Status card

private struct WorkshopStatusCard: View {
    let status: PKStatus
    let headline: String
    let detail: String

    var body: some View {
        HStack(spacing: PK.Spacing.lg) {
            Image(systemName: status.systemImage)
                .font(.system(size: 34))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(status.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(PK.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: PK.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Workshop status. \(headline). \(detail)")
    }
}

// MARK: - Shortcut row

private struct ShortcutRow: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        HStack(spacing: PK.Spacing.sm) {
            ForEach(QuickAction.homeShortcuts) { action in
                Button {
                    router.perform(action)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: action.systemImage)
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                        Text(action.title)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .padding(.vertical, PK.Spacing.sm)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: PK.Radius.card))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.title)
            }
        }
    }
}

// MARK: - Rows

struct AttentionRow: View {
    let status: PKStatus
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: PK.Spacing.md) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(status.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: PK.Spacing.sm)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(status.label). \(title). \(detail)")
        .accessibilityAddTraits(.isButton)
    }
}

private struct QueuePreviewRow: View {
    let item: PrintQueueItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.subheadline.weight(.medium))
                Text("\(Format.duration(minutes: item.estimatedMinutes)) · \(Format.grams(item.gramsRequired))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: PK.Spacing.sm)
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

private struct RecentPrintRow: View {
    let record: PrintRecord

    var body: some View {
        HStack(spacing: PK.Spacing.md) {
            Image(systemName: record.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(record.success ? PK.StatusColor.ready : PK.StatusColor.error)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name.isEmpty ? "Print" : record.name).font(.subheadline)
                Text("\(Format.dateTime(record.date)) · \(Format.grams(record.gramsUsed))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.name), \(record.success ? "succeeded" : "failed"), \(Format.grams(record.gramsUsed))")
    }
}

struct SpoolMiniCard: View {
    let spool: Spool
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var cardWidth: CGFloat = 110
    @ScaledMetric(relativeTo: .caption) private var ringSize: CGFloat = 64

    var body: some View {
        VStack(spacing: PK.Spacing.sm) {
            SpoolRingView(fraction: spool.remainingFraction, filamentColor: spool.color, lineWidth: 8)
                .frame(width: ringSize, height: ringSize)
            Text(spool.displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                .multilineTextAlignment(.center)
            Text(Format.grams(spool.currentWeightG))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(width: cardWidth)
        .padding(.vertical, PK.Spacing.md)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: PK.Radius.card))
        .accessibilityElement(children: .combine)
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
            Spacer(minLength: PK.Spacing.sm)
            StatusBadge(status: dueCount > 0 ? .attention : .ready,
                        text: dueCount > 0 ? "\(dueCount) due" : "Ready")
        }
    }
}
