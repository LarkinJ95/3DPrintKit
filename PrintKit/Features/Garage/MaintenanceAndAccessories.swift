import SwiftUI
import SwiftData

// MARK: - Maintenance

struct MaintenanceTaskRow: View {
    @Bindable var task: MaintenanceTask
    let printer: PrinterDevice

    private var due: Bool { task.isDue(printerHours: printer.totalPrintHours) }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.subheadline.weight(.medium))
                Text(task.dueDescription(printerHours: printer.totalPrintHours))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if due {
                StatusBadge(status: .attention, text: "Due")
            }
            Button("Done") {
                task.lastCompleted = Date()
                task.hoursAtLastCompletion = printer.totalPrintHours
                Haptics.success()
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
        .swipeActions(edge: .leading) {
            Button("Complete") {
                task.lastCompleted = Date()
                task.hoursAtLastCompletion = printer.totalPrintHours
                Haptics.success()
            }
            .tint(.green)
        }
    }
}

struct MaintenanceListView: View {
    @Query private var printers: [PrinterDevice]
    @Query(sort: \MaintenanceLog.date, order: .reverse) private var logs: [MaintenanceLog]
    @State private var showLogForm = false

    var body: some View {
        List {
            Section("Due & Scheduled") {
                ForEach(printers) { printer in
                    if let tasks = printer.maintenanceTasks, !tasks.isEmpty {
                        DisclosureGroup(printer.displayName) {
                            ForEach(tasks) { task in
                                MaintenanceTaskRow(task: task, printer: printer)
                            }
                        }
                    }
                }
                if printers.isEmpty {
                    Text("Add a printer first.").foregroundStyle(.secondary)
                }
            }
            Section("History") {
                ForEach(logs.prefix(30)) { log in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(log.title).font(.subheadline)
                        Text("\(log.printer?.displayName ?? "—") · \(Format.dateTime(log.date))")
                            .font(.caption).foregroundStyle(.secondary)
                        if !log.notes.isEmpty {
                            Text(log.notes).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Maintenance")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showLogForm = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showLogForm) {
            NavigationStack { MaintenanceLogFormView() }
        }
    }
}

struct MaintenanceTaskFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let printer: PrinterDevice

    static let suggestions = [
        "Clean build plate", "Lubricate rails", "Lubricate lead screws", "Inspect belts",
        "Check belt tension", "Clean fans", "Inspect extruder gears", "Inspect PTFE",
        "Inspect nozzle", "Replace nozzle", "Inspect wiring", "Clean machine",
        "Check fasteners", "Clean carbon rods", "Check filters", "Check enclosure", "Firmware review"
    ]

    @State private var title = ""
    @State private var intervalDays = 30
    @State private var useDays = true
    @State private var intervalHours = 100.0
    @State private var useHours = false

    var body: some View {
        Form {
            Section("Task") {
                TextField("Title", text: $title)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PK.Spacing.sm) {
                        ForEach(Self.suggestions, id: \.self) { suggestion in
                            SelectableChip(title: suggestion, isSelected: title == suggestion) { title = suggestion }
                        }
                    }
                }
            }
            Section("Schedule") {
                Toggle("Every N days", isOn: $useDays)
                if useDays {
                    Stepper("Every \(intervalDays) days", value: $intervalDays, in: 1...365)
                }
                Toggle("Every N print hours", isOn: $useHours)
                if useHours {
                    Stepper("Every \(Int(intervalHours)) h", value: $intervalHours, in: 10...2000, step: 10)
                }
            }
        }
        .navigationTitle("New Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let task = MaintenanceTask()
                    task.printer = printer
                    task.title = title
                    task.intervalDays = useDays ? intervalDays : 0
                    task.intervalPrintHours = useHours ? intervalHours : 0
                    task.hoursAtLastCompletion = printer.totalPrintHours
                    context.insert(task)
                    Haptics.success()
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || (!useDays && !useHours))
            }
        }
    }
}

struct MaintenanceLogFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var printers: [PrinterDevice]

    @State private var printer: PrinterDevice?
    @State private var title = ""
    @State private var notes = ""

    var body: some View {
        Form {
            Picker("Printer", selection: $printer) {
                Text("Select…").tag(PrinterDevice?.none)
                ForEach(printers) { Text($0.displayName).tag(PrinterDevice?.some($0)) }
            }
            TextField("What was done", text: $title)
            TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...4)
        }
        .navigationTitle("Log Maintenance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let log = MaintenanceLog()
                    log.printer = printer
                    log.title = title
                    log.printerHoursAtService = printer?.totalPrintHours ?? 0
                    log.notes = notes
                    context.insert(log)
                    Haptics.success()
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

// MARK: - Accessories

struct AccessoryListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AccessoryItem.name) private var items: [AccessoryItem]
    @State private var showAdd = false

    var body: some View {
        List {
            if items.isEmpty {
                PKEmptyState(symbol: "shippingbox",
                             title: "No Accessories Tracked",
                             message: "Track spare nozzles, PTFE, belts, and consumables with minimum stock levels.",
                             actionTitle: "Add Accessory") { showAdd = true }
            }
            let reorder = items.filter(\.needsReorder)
            if !reorder.isEmpty {
                Section("Reorder") {
                    ForEach(reorder) { item in
                        AccessoryRow(item: item)
                    }
                }
            }
            Section("All Items") {
                ForEach(items) { item in
                    AccessoryRow(item: item)
                }
                .onDelete { indexSet in
                    for index in indexSet { context.delete(items[index]) }
                }
            }
        }
        .navigationTitle("Accessories")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { NavigationStack { AccessoryFormView() } }
    }
}

struct AccessoryRow: View {
    @Bindable var item: AccessoryItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.subheadline.weight(.medium))
                Text("\(item.category.displayName)\(item.location.isEmpty ? "" : " · " + item.location)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if item.needsReorder {
                StatusBadge(status: .attention, text: "Reorder")
            }
            Stepper("", value: $item.quantity, in: 0...999)
                .labelsHidden()
            Text("\(item.quantity)")
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 24, alignment: .trailing)
        }
    }
}

struct AccessoryFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = AccessoryCategory.other
    @State private var quantity = 1
    @State private var minimumStock = 0
    @State private var location = ""

    var body: some View {
        Form {
            TextField("Name", text: $name)
            Picker("Category", selection: $category) {
                ForEach(AccessoryCategory.allCases) { Text($0.displayName).tag($0) }
            }
            Stepper("Quantity \(quantity)", value: $quantity, in: 0...999)
            Stepper("Minimum stock \(minimumStock)", value: $minimumStock, in: 0...50)
            TextField("Storage location", text: $location)
        }
        .navigationTitle("Add Accessory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let item = AccessoryItem()
                    item.name = name
                    item.category = category
                    item.quantity = quantity
                    item.minimumStock = minimumStock
                    item.location = location
                    context.insert(item)
                    Haptics.success()
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
