import SwiftUI
import SwiftData

// MARK: - Print queue

struct PrintQueueView: View {
    @Environment(\.modelContext) private var context
    @Query private var items: [PrintQueueItem]
    @State private var showAdd = false
    @State private var editing: PrintQueueItem?

    private var active: [PrintQueueItem] {
        items.filter { !$0.isDone }.sorted { $0.priority > $1.priority }
    }
    private var done: [PrintQueueItem] {
        items.filter(\.isDone).sorted { $0.priority > $1.priority }
    }

    var body: some View {
        List {
            if items.isEmpty {
                PKEmptyState(symbol: "list.number",
                             title: "Queue Is Empty",
                             message: "Plan upcoming prints here. 3DPrintKit checks filament sufficiency and printer conflicts for you.",
                             actionTitle: "Add to Queue") { showAdd = true }
            }

            if !active.isEmpty {
                Section("Up Next") {
                    ForEach(active) { item in
                        QueueRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture { editing = item }
                            .swipeActions(edge: .leading) {
                                Button { complete(item) } label: { Label("Done", systemImage: "checkmark") }
                                    .tint(.green)
                            }
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(active[i]) }
                    }
                }
            }

            if !done.isEmpty {
                Section("Completed") {
                    ForEach(done) { item in
                        QueueRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture { editing = item }
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(done[i]) }
                    }
                }
            }
        }
        .navigationTitle("Print Queue")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { NavigationStack { PrintQueueFormView(item: nil) } }
        .sheet(item: $editing) { item in NavigationStack { PrintQueueFormView(item: item) } }
    }

    private func complete(_ item: PrintQueueItem) {
        item.isDone = true
    }
}

private struct QueueRow: View {
    let item: PrintQueueItem

    /// True when the assigned spool cannot cover this job with the configured reserve.
    private var filamentWarning: String? {
        guard let spool = item.spool, item.gramsRequired > 0 else { return nil }
        let reserve = AppSettings.shared.reservePercent / 100 * spool.originalNetWeightG
        let usable = spool.currentWeightG - reserve
        if usable < item.gramsRequired {
            return "Needs \(Format.grams(item.gramsRequired)) but only \(Format.grams(max(usable, 0))) usable on \(spool.displayName)"
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: PK.Spacing.sm) {
                if item.priority > 0 {
                    Text("P\(item.priority)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .accessibilityLabel("Priority \(item.priority)")
                }
                Text(item.name).font(.subheadline.weight(.medium))
                    .strikethrough(item.isDone)
                Spacer()
                if item.isDone { StatusBadge(status: .inactive, text: "Done") }
            }
            HStack(spacing: 8) {
                if let printer = item.printer { Label(printer.displayName, systemImage: "printer") }
                if item.gramsRequired > 0 { Text(Format.grams(item.gramsRequired)) }
                if item.estimatedMinutes > 0 { Text(Format.duration(minutes: item.estimatedMinutes)) }
            }
            .font(.caption).foregroundStyle(.secondary)
            if let spool = item.spool {
                Label(spool.displayName, systemImage: "circle.dashed")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let warning = filamentWarning, !item.isDone {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Queue item form

struct PrintQueueFormView: View {
    let item: PrintQueueItem?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var printers: [PrinterDevice]
    @Query private var spools: [Spool]
    @Query private var projects: [ProjectItem]

    @State private var name = ""
    @State private var printer: PrinterDevice?
    @State private var spool: Spool?
    @State private var project: ProjectItem?
    @State private var estimatedMinutes: Double = 0
    @State private var gramsRequired: Double = 0
    @State private var priority: Int = 0
    @State private var notes = ""

    var body: some View {
        Form {
            Section("Job") {
                TextField("Name", text: $name)
                Picker("Project", selection: $project) {
                    Text("None").tag(ProjectItem?.none)
                    ForEach(projects.filter { $0.status != .archived }) { Text($0.name).tag(ProjectItem?.some($0)) }
                }
            }
            Section("Assignment") {
                Picker("Printer", selection: $printer) {
                    Text("Any").tag(PrinterDevice?.none)
                    ForEach(printers) { Text($0.displayName).tag(PrinterDevice?.some($0)) }
                }
                Picker("Spool", selection: $spool) {
                    Text("Unassigned").tag(Spool?.none)
                    ForEach(spools.filter { !$0.isArchived }) { Text($0.displayName).tag(Spool?.some($0)) }
                }
                Stepper("Priority: \(priority == 0 ? "Normal" : "P\(priority)")", value: $priority, in: 0...5)
            }
            Section("Estimates") {
                PKNumericField(label: "Filament needed", value: $gramsRequired, unit: "g")
                PKNumericField(label: "Estimated time", value: $estimatedMinutes, unit: "min")
            }
            Section("Notes") {
                TextEditor(text: $notes).frame(minHeight: 70)
            }
        }
        .navigationTitle(item == nil ? "Queue Print" : "Edit Queue Item")
        .pkDismissableKeyboard()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            guard let item else { return }
            name = item.name
            printer = item.printer
            spool = item.spool
            project = item.project
            estimatedMinutes = item.estimatedMinutes
            gramsRequired = item.gramsRequired
            priority = item.priority
            notes = item.notes
        }
    }

    private func save() {
        let target: PrintQueueItem
        if let item { target = item } else {
            target = PrintQueueItem()
            context.insert(target)
        }
        target.name = name
        target.printer = printer
        target.spool = spool
        target.project = project
        target.estimatedMinutes = estimatedMinutes
        target.gramsRequired = gramsRequired
        target.priority = priority
        target.notes = notes
        dismiss()
    }
}
