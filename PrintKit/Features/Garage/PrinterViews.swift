import SwiftUI
import SwiftData

struct GarageHomeView: View {
    @Query private var printers: [PrinterDevice]
    @Environment(EntitlementService.self) private var entitlements
    @State private var upgrade = UpgradePrompt()
    @State private var showAddPrinter = false

    /// Free keeps one saved printer. Existing printers are never affected —
    /// only adding another is gated.
    private func addPrinter() {
        upgrade.attempt(entitlements.canCreate(.printers, existing: printers.count)) {
            showAddPrinter = true
        }
    }

    var body: some View {
        List {
            Section("Printers") {
                ForEach(printers) { printer in
                    NavigationLink { PrinterDetailView(printer: printer) } label: {
                        PrinterStatusRow(printer: printer)
                    }
                }
                Button { addPrinter() } label: {
                    HStack {
                        Label("Add Printer", systemImage: "plus.circle")
                        if case .limited = entitlements.quota(for: .printers) {
                            Spacer()
                            ProBadge()
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Section {
                NavigationLink(value: PushDestination.readiness) {
                    Label("Print Readiness Check", systemImage: "checkmark.shield")
                }
            }
            Section("Maintenance & Parts") {
                NavigationLink { MaintenanceListView() } label: { Label("Maintenance", systemImage: "screwdriver") }
                NavigationLink { AccessoryListView() } label: { Label("Accessories & Spares", systemImage: "shippingbox") }
                NavigationLink { ProfileListView() } label: { Label("Slicer Profiles", systemImage: "doc.text") }
            }
            Section("Records") {
                NavigationLink { PrintHistoryView() } label: { Label("Print History & Stats", systemImage: "clock.arrow.circlepath") }
                NavigationLink { ProjectListView() } label: { Label("Projects", systemImage: "folder") }
                NavigationLink { PrintQueueView() } label: { Label("Print Queue", systemImage: "list.number") }
                NavigationLink { FailureJournalView() } label: { Label("Failure Journal", systemImage: "exclamationmark.bubble") }
                NavigationLink { KnowledgeView() } label: { Label("Personal Knowledge", systemImage: "brain") }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Garage")
        .sheet(isPresented: $showAddPrinter) {
            NavigationStack { PrinterFormView(printer: nil) }
        }
        .upgradePrompt(upgrade)
    }
}

// MARK: - Printer detail & form

struct PrinterDetailView: View {
    @Bindable var printer: PrinterDevice
    @Query private var prints: [PrintRecord]

    private var printerPrints: [PrintRecord] {
        prints.filter { $0.printer?.id == printer.id }
    }

    private var dueTasks: [MaintenanceTask] {
        (printer.maintenanceTasks ?? []).filter { $0.isDue(printerHours: printer.totalPrintHours) }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: PK.Spacing.xl) {
                    MetricView(label: "Print hours", value: String(format: "%.0f", printer.totalPrintHours))
                    MetricView(label: "Prints", value: "\(printerPrints.count)")
                    MetricView(label: "Nozzle", value: printer.currentNozzle.map { String(format: "%.2g mm", $0.diameter) } ?? "—")
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                if !dueTasks.isEmpty {
                    StatusBadge(status: .attention, text: "\(dueTasks.count) maintenance task\(dueTasks.count == 1 ? "" : "s") due")
                }
            }

            Section("Hardware") {
                KeyValueRow(key: "Manufacturer", value: printer.manufacturer)
                KeyValueRow(key: "Model", value: printer.model)
                KeyValueRow(key: "Firmware", value: printer.firmware.isEmpty ? "—" : printer.firmware)
                KeyValueRow(key: "Build volume", value: String(format: "%.0f × %.0f × %.0f mm", printer.buildVolumeX, printer.buildVolumeY, printer.buildVolumeZ))
                KeyValueRow(key: "Max hotend", value: "\(Int(printer.maxHotendTempC)) °C")
                KeyValueRow(key: "Max bed", value: "\(Int(printer.maxBedTempC)) °C")
                KeyValueRow(key: "Chamber", value: printer.hasHeatedChamber ? "Heated, \(Int(printer.maxChamberTempC)) °C" : printer.hasEnclosure ? "Enclosed (unheated)" : "Open")
                KeyValueRow(key: "Extruder", value: printer.extruder.displayName)
                KeyValueRow(key: "Filament", value: String(format: "%.2f mm", printer.filamentDiameter))
                KeyValueRow(key: "Multi-material", value: printer.multiMaterial.displayName)
            }

            Section("Nozzles") {
                ForEach(printer.nozzles ?? []) { nozzle in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nozzle.displayName).font(.subheadline.weight(.medium))
                            Text("\(Int(nozzle.printHours)) h total · \(Int(nozzle.abrasiveHours)) h abrasive")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if nozzle.isInstalled {
                            StatusBadge(status: .info, text: "Installed")
                        }
                        if nozzle.abrasiveHours > 100 && !nozzle.material.abrasiveSafe {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityLabel("High abrasive wear on a non-hardened nozzle")
                        }
                    }
                }
                NavigationLink { NozzleFormView(printer: printer, nozzle: nil) } label: {
                    Label("Add Nozzle", systemImage: "plus")
                }
            }

            Section("Build Plates") {
                ForEach(printer.plates ?? []) { plate in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plate.displayName).font(.subheadline.weight(.medium))
                            Text("\(plate.condition.displayName) · \(Int(plate.usageHours)) h · cleaned \(Format.date(plate.lastCleaned))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Cleaned") {
                            plate.lastCleaned = Date()
                            Haptics.light()
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                NavigationLink { PlateFormView(printer: printer) } label: {
                    Label("Add Build Plate", systemImage: "plus")
                }
            }

            Section("Maintenance") {
                ForEach(printer.maintenanceTasks ?? []) { task in
                    MaintenanceTaskRow(task: task, printer: printer)
                }
                NavigationLink { MaintenanceTaskFormView(printer: printer) } label: {
                    Label("Add Maintenance Task", systemImage: "plus")
                }
            }

            Section {
                NavigationLink(value: PushDestination.readiness) {
                    Label("Run Readiness Check", systemImage: "checkmark.shield")
                }
            }
        }
        .navigationTitle(printer.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Edit") { PrinterFormView(printer: printer) }
            }
        }
    }
}

struct PrinterFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let printer: PrinterDevice?

    @State private var manufacturer = ""
    @State private var model = ""
    @State private var customName = ""
    @State private var serialNumber = ""
    @State private var firmware = ""
    @State private var buildX = 220.0
    @State private var buildY = 220.0
    @State private var buildZ = 250.0
    @State private var maxHotend = 260.0
    @State private var maxBed = 100.0
    @State private var hasEnclosure = false
    @State private var hasHeatedChamber = false
    @State private var maxChamber = 0.0
    @State private var extruder = ExtruderType.direct
    @State private var filamentDiameter = 1.75
    @State private var ams = MultiMaterialSystem.none
    @State private var amsSlots = 4
    @State private var notes = ""

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Manufacturer", text: $manufacturer)
                TextField("Model", text: $model)
                TextField("Custom name", text: $customName)
                TextField("Serial number", text: $serialNumber)
                TextField("Firmware", text: $firmware)
            }
            Section("Capabilities") {
                Stepper("Max hotend \(Int(maxHotend)) °C", value: $maxHotend, in: 180...500, step: 10)
                Stepper("Max bed \(Int(maxBed)) °C", value: $maxBed, in: 0...160, step: 5)
                Toggle("Enclosure", isOn: $hasEnclosure)
                Toggle("Heated chamber", isOn: $hasHeatedChamber)
                if hasHeatedChamber {
                    Stepper("Chamber max \(Int(maxChamber)) °C", value: $maxChamber, in: 0...100, step: 5)
                }
                Picker("Extruder", selection: $extruder) {
                    ForEach(ExtruderType.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Filament diameter", selection: $filamentDiameter) {
                    Text("1.75 mm").tag(1.75); Text("2.85 mm").tag(2.85)
                }
                Picker("Multi-material", selection: $ams) {
                    ForEach(MultiMaterialSystem.allCases) { Text($0.displayName).tag($0) }
                }
                if ams != .none {
                    Stepper("AMS slots: \(amsSlots)", value: $amsSlots, in: 1...16)
                }
            }
            Section("Build Volume (mm)") {
                PKNumericField(label: "X", value: $buildX, placeholder: "220")
                PKNumericField(label: "Y", value: $buildY, placeholder: "220")
                PKNumericField(label: "Z", value: $buildZ, placeholder: "250")
            }
            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
            }
        }
        .navigationTitle(printer == nil ? "Add Printer" : "Edit Printer")
        .pkDismissableKeyboard()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let printer else { return }
        manufacturer = printer.manufacturer
        model = printer.model
        customName = printer.customName
        serialNumber = printer.serialNumber
        firmware = printer.firmware
        buildX = printer.buildVolumeX
        buildY = printer.buildVolumeY
        buildZ = printer.buildVolumeZ
        maxHotend = printer.maxHotendTempC
        maxBed = printer.maxBedTempC
        hasEnclosure = printer.hasEnclosure
        hasHeatedChamber = printer.hasHeatedChamber
        maxChamber = printer.maxChamberTempC
        extruder = printer.extruder
        filamentDiameter = printer.filamentDiameter
        ams = printer.multiMaterial
        amsSlots = max(printer.amsSlotCount, 1)
        notes = printer.notes
    }

    private func save() {
        let target = printer ?? PrinterDevice()
        target.manufacturer = manufacturer
        target.model = model
        target.customName = customName
        target.serialNumber = serialNumber
        target.firmware = firmware
        target.buildVolumeX = buildX
        target.buildVolumeY = buildY
        target.buildVolumeZ = buildZ
        target.maxHotendTempC = maxHotend
        target.maxBedTempC = maxBed
        target.hasEnclosure = hasEnclosure
        target.hasHeatedChamber = hasHeatedChamber
        target.maxChamberTempC = maxChamber
        target.extruder = extruder
        target.filamentDiameter = filamentDiameter
        target.multiMaterial = ams
        target.amsSlotCount = ams == .none ? 0 : amsSlots
        target.notes = notes
        if printer == nil { context.insert(target) }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Nozzles & plates

struct NozzleFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let printer: PrinterDevice
    let nozzle: NozzleRecord?

    @State private var diameter = 0.4
    @State private var material = NozzleMaterial.brass
    @State private var brand = ""
    @State private var isInstalled = false

    var body: some View {
        Form {
            Picker("Diameter", selection: $diameter) {
                ForEach([0.2, 0.4, 0.6, 0.8, 1.0], id: \.self) { Text(String(format: "%.2g mm", $0)).tag($0) }
            }
            Picker("Material", selection: $material) {
                ForEach(NozzleMaterial.allCases) { Text($0.displayName).tag($0) }
            }
            if material.abrasiveSafe {
                Label("Safe for carbon-fiber, glass-fiber, metal, and glow filaments.", systemImage: "checkmark.shield")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Label("Will wear quickly with abrasive filaments.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            TextField("Brand", text: $brand)
            Toggle("Currently installed", isOn: $isInstalled)
        }
        .navigationTitle("Nozzle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let target = nozzle ?? NozzleRecord()
                    target.printer = printer
                    target.diameter = diameter
                    target.material = material
                    target.brand = brand
                    target.isInstalled = isInstalled
                    if isInstalled {
                        for other in printer.nozzles ?? [] where other.id != target.id {
                            other.isInstalled = false
                        }
                        target.installedDate = target.installedDate ?? Date()
                    }
                    if nozzle == nil { context.insert(target) }
                    Haptics.success()
                    dismiss()
                }
            }
        }
    }
}

struct PlateFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let printer: PrinterDevice

    @State private var plateType = PlateType.texturedPEI
    @State private var manufacturer = ""
    @State private var surface = ""
    @State private var condition = PlateCondition.good

    var body: some View {
        Form {
            Picker("Type", selection: $plateType) {
                ForEach(PlateType.allCases) { Text($0.displayName).tag($0) }
            }
            TextField("Manufacturer", text: $manufacturer)
            TextField("Surface notes", text: $surface)
            Picker("Condition", selection: $condition) {
                ForEach(PlateCondition.allCases) { Text($0.displayName).tag($0) }
            }
        }
        .navigationTitle("Build Plate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let plate = BuildPlate()
                    plate.printer = printer
                    plate.plateType = plateType
                    plate.manufacturer = manufacturer
                    plate.surface = surface
                    plate.condition = condition
                    context.insert(plate)
                    Haptics.success()
                    dismiss()
                }
            }
        }
    }
}
