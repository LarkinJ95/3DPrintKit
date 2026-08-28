import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Project list

struct ProjectListView: View {
    @Query(sort: \ProjectItem.createdAt, order: .reverse) private var projects: [ProjectItem]
    @State private var showAdd = false
    @State private var filter: ProjectStatus?

    private var filtered: [ProjectItem] {
        guard let filter else { return projects }
        return projects.filter { $0.status == filter }
    }

    var body: some View {
        List {
            if !projects.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: PK.Spacing.sm) {
                            SelectableChip(title: "All", isSelected: filter == nil) { filter = nil }
                            ForEach(ProjectStatus.allCases) { status in
                                SelectableChip(title: status.displayName, isSelected: filter == status) {
                                    filter = (filter == status) ? nil : status
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }

            if filtered.isEmpty {
                PKEmptyState(symbol: "folder",
                             title: filter == nil ? "No Projects Yet" : "No \(filter!.displayName) Projects",
                             message: "Group prints, parts, and hardware into a project with its own bill of materials and cost roll-up.",
                             actionTitle: "New Project") { showAdd = true }
            }

            ForEach(filtered) { project in
                NavigationLink { ProjectDetailView(project: project) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(project.name).font(.subheadline.weight(.medium))
                            Spacer()
                            StatusBadge(status: statusBadge(project.status), text: project.status.displayName)
                        }
                        HStack(spacing: 8) {
                            let bomCount = (project.bomItems ?? []).count
                            let printCount = (project.prints ?? []).count
                            Text("\(bomCount) BOM item\(bomCount == 1 ? "" : "s") · \(printCount) print\(printCount == 1 ? "" : "s")")
                            Spacer()
                            if project.totalCost > 0 {
                                Text(Format.currency(project.totalCost))
                                    .font(.caption.monospacedDigit())
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("Projects")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { NavigationStack { ProjectFormView(project: nil) } }
    }

    private func statusBadge(_ status: ProjectStatus) -> PKStatus {
        switch status {
        case .planned: return .info
        case .inProgress: return .attention
        case .completed: return .ready
        case .archived: return .inactive
        }
    }

    @Environment(\.modelContext) private var context

    private func delete(at offsets: IndexSet) {
        // Deleting a project never deletes print history;
        // prints simply lose their (optional) project association.
        for index in offsets { context.delete(filtered[index]) }
    }
}

// MARK: - Project form

struct ProjectFormView: View {
    let project: ProjectItem?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var printers: [PrinterDevice]
    @Query private var profiles: [SlicerProfile]

    @State private var name = ""
    @State private var notes = ""
    @State private var status: ProjectStatus = .planned
    @State private var printer: PrinterDevice?
    @State private var profile: SlicerProfile?

    var body: some View {
        Form {
            Section("Project") {
                TextField("Name", text: $name)
                Picker("Status", selection: $status) {
                    ForEach(ProjectStatus.allCases) { Text($0.displayName).tag($0) }
                }
            }
            Section("Defaults") {
                Picker("Printer", selection: $printer) {
                    Text("None").tag(PrinterDevice?.none)
                    ForEach(printers) { Text($0.displayName).tag(PrinterDevice?.some($0)) }
                }
                Picker("Slicer Profile", selection: $profile) {
                    Text("None").tag(SlicerProfile?.none)
                    ForEach(profiles) { Text($0.name).tag(SlicerProfile?.some($0)) }
                }
            }
            Section("Notes") {
                TextEditor(text: $notes).frame(minHeight: 90)
            }
        }
        .navigationTitle(project == nil ? "New Project" : "Edit Project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            guard let project else { return }
            name = project.name
            notes = project.notes
            status = project.status
            printer = project.printer
            profile = project.profile
        }
    }

    private func save() {
        if let project {
            project.name = name
            project.notes = notes
            if project.status != status {
                project.status = status
                project.completedAt = (status == .completed) ? Date() : nil
            }
            project.printer = printer
            project.profile = profile
        } else {
            let item = ProjectItem()
            item.name = name
            item.notes = notes
            item.status = status
            item.printer = printer
            item.profile = profile
            context.insert(item)
        }
        dismiss()
    }
}

// MARK: - Project detail

struct ProjectDetailView: View {
    @Bindable var project: ProjectItem
    @Environment(\.modelContext) private var context
    @State private var showEdit = false
    @State private var showAddBOM = false
    @State private var editingBOM: BOMItem?

    private var bomItems: [BOMItem] { (project.bomItems ?? []).sorted { $0.name < $1.name } }
    private var prints: [PrintRecord] { (project.prints ?? []).sorted { $0.date > $1.date } }
    private var bomCost: Double { bomItems.reduce(0) { $0 + $1.totalCost } }
    private var printCost: Double { prints.reduce(0) { $0 + $1.cost } }
    private var printedGrams: Double { prints.filter { $0.success }.reduce(0) { $0 + $1.gramsUsed } }

    var body: some View {
        List {
            Section {
                HStack(spacing: PK.Spacing.sm) {
                    StatusBadge(status: badge, text: project.status.displayName)
                    Spacer()
                    if project.status != .completed {
                        Button(project.status == .planned ? "Start" : "Mark Complete") { advanceStatus() }
                            .font(.subheadline.weight(.medium))
                    }
                }
                if let completed = project.completedAt {
                    KeyValueRow(key: "Completed", value: Format.date(completed))
                }
                if let printer = project.printer { KeyValueRow(key: "Printer", value: printer.displayName) }
                if let profile = project.profile { KeyValueRow(key: "Profile", value: profile.name) }
            }

            Section("Cost Roll-Up") {
                MetricView(label: "Total project cost", value: Format.currency(project.totalCost))
                KeyValueRow(key: "Bill of materials", value: Format.currency(bomCost))
                KeyValueRow(key: "Logged prints", value: Format.currency(printCost))
                if printedGrams > 0 {
                    KeyValueRow(key: "Filament printed", value: Format.grams(printedGrams))
                }
            }

            Section {
                if bomItems.isEmpty {
                    Text("No BOM items yet. Add printed parts, hardware, electronics — everything the project needs.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(bomItems) { item in
                    Button { editingBOM = item } label: {
                        BOMListRow(item: item, icon: icon(for: item.category), summary: bomSummary(for: item))
                    }
                    .tint(.primary)
                }
                .onDelete(perform: deleteBOM)
            } header: {
                HStack {
                    Text("Bill of Materials")
                    Spacer()
                    Button { showAddBOM = true } label: { Image(systemName: "plus.circle.fill") }
                        .accessibilityLabel("Add BOM item")
                }
            }

            Section("Prints") {
                if prints.isEmpty {
                    Text("No prints logged for this project yet. Log a print and choose this project to see it here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(prints) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(record.name.isEmpty ? "Print" : record.name).font(.subheadline)
                            Text(Format.dateTime(record.date)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusBadge(status: record.success ? .ready : .error,
                                    text: record.success ? "OK" : "Failed")
                        Text(Format.grams(record.gramsUsed))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }

            if !project.notes.isEmpty {
                Section("Notes") { Text(project.notes).font(.subheadline) }
            }

            Section("Photos") {
                PhotoStripView(photoDatas: $project.photoDatas)
            }
        }
        .navigationTitle(project.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Edit") { showEdit = true } }
        }
        .sheet(isPresented: $showEdit) { NavigationStack { ProjectFormView(project: project) } }
        .sheet(isPresented: $showAddBOM) { NavigationStack { BOMItemFormView(project: project, item: nil) } }
        .sheet(item: $editingBOM) { item in NavigationStack { BOMItemFormView(project: project, item: item) } }
    }

    private func bomSummary(for item: BOMItem) -> String {
        var summary = "\(item.category.displayName) · qty \(String(format: "%g", item.quantity))"
        if item.grams > 0 {
            summary += " · \(Format.grams(item.grams))"
        }
        return summary
    }

    private var badge: PKStatus {
        switch project.status {
        case .planned: return .info
        case .inProgress: return .attention
        case .completed: return .ready
        case .archived: return .inactive
        }
    }

    private func advanceStatus() {
        switch project.status {
        case .planned: project.status = .inProgress
        case .inProgress:
            project.status = .completed
            project.completedAt = Date()
        default: break
        }
    }

    private func icon(for category: BOMCategory) -> String {
        switch category {
        case .printedPart: return "cube"
        case .filament: return "circle.dashed"
        case .screw: return "screwdriver"
        case .nut: return "hexagon"
        case .bearing: return "circle.circle"
        case .magnet: return "bolt.ring"
        case .insert: return "cylinder"
        case .electronics: return "cpu"
        case .adhesive: return "drop"
        case .hardware: return "wrench"
        case .other: return "shippingbox"
        }
    }

    private func deleteBOM(at offsets: IndexSet) {
        for index in offsets { context.delete(bomItems[index]) }
    }
}

private struct BOMListRow: View {
    let item: BOMItem
    let icon: String
    let summary: String

    var body: some View {
        HStack(spacing: PK.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.subheadline)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if item.isPrinted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Printed")
            }
            if item.totalCost > 0 {
                Text(Format.currency(item.totalCost))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - BOM item form

struct BOMItemFormView: View {
    let project: ProjectItem
    let item: BOMItem?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var spools: [Spool]

    @State private var name = ""
    @State private var category: BOMCategory = .other
    @State private var quantity: Double = 1
    @State private var unitCost: Double = 0
    @State private var grams: Double = 0
    @State private var spool: Spool?
    @State private var isPrinted = false

    var body: some View {
        Form {
            Section("Item") {
                TextField("Name", text: $name)
                Picker("Category", selection: $category) {
                    ForEach(BOMCategory.allCases) { Text($0.displayName).tag($0) }
                }
            }
            Section("Quantity & Cost") {
                Stepper("Qty: \(quantity, specifier: "%g")", value: $quantity, in: 0...9999, step: 1)
                HStack {
                    Text("Unit cost")
                    Spacer()
                    TextField("0.00", value: $unitCost, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
                }
            }
            if category == .printedPart || category == .filament {
                Section("Filament") {
                    HStack {
                        Text("Estimated grams")
                        Spacer()
                        TextField("0", value: $grams, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
                    }
                    Picker("Source spool", selection: $spool) {
                        Text("Any").tag(Spool?.none)
                        ForEach(spools.filter { !$0.isArchived }) { Text($0.displayName).tag(Spool?.some($0)) }
                    }
                    if category == .printedPart {
                        Toggle("Already printed", isOn: $isPrinted)
                    }
                }
            }
        }
        .navigationTitle(item == nil ? "Add BOM Item" : "Edit BOM Item")
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
            category = item.category
            quantity = item.quantity
            unitCost = item.unitCost
            grams = item.grams
            spool = item.spool
            isPrinted = item.isPrinted
        }
    }

    private func save() {
        let target: BOMItem
        if let item { target = item } else {
            target = BOMItem()
            target.project = project
            context.insert(target)
        }
        target.name = name
        target.category = category
        target.quantity = quantity
        target.unitCost = unitCost
        target.grams = grams
        target.spool = spool
        target.isPrinted = isPrinted
        dismiss()
    }
}
