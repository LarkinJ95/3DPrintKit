import SwiftUI
import SwiftData

// MARK: - Storage locations

struct StorageListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StorageLocation.name) private var locations: [StorageLocation]
    @State private var showAdd = false

    var body: some View {
        List {
            ForEach(locations) { location in
                NavigationLink {
                    StorageDetailView(location: location)
                } label: {
                    Label {
                        HStack {
                            Text(location.name)
                            Spacer()
                            Text("\(location.spools?.count ?? 0) spools")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: location.kind.systemImage).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet { context.delete(locations[index]) }
            }
        }
        .navigationTitle("Storage")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack { StorageFormView() }
        }
    }
}

struct StorageFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind = StorageKind.other

    var body: some View {
        Form {
            TextField("Name (e.g. Bin A)", text: $name)
            Picker("Type", selection: $kind) {
                ForEach(StorageKind.allCases) { Text($0.displayName).tag($0) }
            }
        }
        .navigationTitle("New Location")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let location = StorageLocation()
                    location.name = name
                    location.kind = kind
                    context.insert(location)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

struct StorageDetailView: View {
    let location: StorageLocation
    @State private var showEnvironmentLog = false

    var body: some View {
        List {
            Section("Spools Here") {
                let spools = (location.spools ?? []).filter { !$0.isArchived }
                if spools.isEmpty {
                    Text("Empty.").foregroundStyle(.secondary)
                }
                ForEach(spools) { spool in
                    NavigationLink { SpoolDetailView(spool: spool) } label: {
                        SpoolRowView(spool: spool)
                    }
                }
            }
            Section {
                Button {
                    showEnvironmentLog = true
                } label: {
                    Label("Log Temperature / Humidity", systemImage: "thermometer.medium")
                }
            }
        }
        .navigationTitle(location.name)
        .sheet(isPresented: $showEnvironmentLog) {
            NavigationStack { EnvironmentLogFormView(location: location) }
        }
    }
}

struct EnvironmentLogFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let location: StorageLocation

    @State private var temperature = 22.0
    @State private var humidity = 40.0
    @State private var notes = ""

    var body: some View {
        Form {
            Section("Reading — \(location.name)") {
                Stepper(value: $temperature, in: -10...60, step: 0.5) {
                    HStack { Text("Temperature"); Spacer(); Text(Format.temperature(temperature)).monospacedDigit() }
                }
                Stepper(value: $humidity, in: 0...100, step: 1) {
                    HStack { Text("Humidity"); Spacer(); Text("\(Int(humidity))%").monospacedDigit() }
                }
                TextField("Notes", text: $notes)
            }
        }
        .navigationTitle("Environment Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let log = EnvironmentLog()
                    log.location = location
                    log.temperatureC = temperature
                    log.humidityPercent = humidity
                    log.notes = notes
                    context.insert(log)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - AMS / MMU management

struct AMSManageView: View {
    @Query private var printers: [PrinterDevice]
    @Environment(\.modelContext) private var context
    @Query private var spools: [Spool]

    private var amsPrinters: [PrinterDevice] {
        printers.filter { $0.multiMaterial != .none }
    }

    var body: some View {
        List {
            if amsPrinters.isEmpty {
                PKEmptyState(symbol: "square.grid.2x2",
                             title: "No Multi-Material Units",
                             message: "Add a printer with an AMS/MMU in the Garage to manage slots here.")
            }
            ForEach(amsPrinters) { printer in
                Section("\(printer.displayName) — \(printer.multiMaterial.displayName)") {
                    let slots = max(printer.amsSlotCount, 1)
                    ForEach(0..<slots, id: \.self) { index in
                        AMSSlotRow(printer: printer, slotIndex: index, spools: spools.filter { !$0.isArchived })
                    }
                }
            }
        }
        .navigationTitle("AMS / MMU")
    }
}

struct AMSSlotRow: View {
    let printer: PrinterDevice
    let slotIndex: Int
    let spools: [Spool]

    private var slotLabel: String { "\(printer.displayName) · \(slotLetter)" }
    private var slotLetter: String {
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]
        let letter = letters[min(slotIndex / 4, letters.count - 1)]
        return "\(letter)\(slotIndex % 4 + 1)"
    }

    private var assigned: Spool? {
        spools.first { $0.amsSlotLabel == slotLabel }
    }

    var body: some View {
        HStack(spacing: PK.Spacing.md) {
            RoundedRectangle(cornerRadius: 4)
                .fill(assigned?.color ?? Color(.systemFill))
                .frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(.separator)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Slot \(slotLetter)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let assigned {
                    Text(assigned.displayName).font(.subheadline.weight(.medium))
                    Text(Format.grams(assigned.currentWeightG) + " remaining")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Empty").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                Button("Clear Slot") { assigned?.amsSlotLabel = "" }
                if !spools.isEmpty {
                    Divider()
                    ForEach(spools) { spool in
                        Button(spool.displayName) {
                            // Remove any previous assignment of that slot/spool pairing.
                            if let existing = spools.first(where: { $0.amsSlotLabel == slotLabel }) {
                                existing.amsSlotLabel = ""
                            }
                            spool.amsSlotLabel = slotLabel
                        }
                    }
                }
            } label: {
                Text(assigned == nil ? "Assign" : "Change")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .accessibilityLabel("Slot \(slotLetter): \(assigned?.displayName ?? "empty")")
    }
}

// MARK: - Spool transfers (re-spooling)

struct TransferListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FilamentTransfer.date, order: .reverse) private var transfers: [FilamentTransfer]
    @State private var showAdd = false

    var body: some View {
        List {
            if transfers.isEmpty {
                PKEmptyState(symbol: "arrow.left.arrow.right",
                             title: "No Transfers",
                             message: "Record filament moved between spools so inventory weight stays accurate.",
                             actionTitle: "New Transfer") { showAdd = true }
            }
            ForEach(transfers) { transfer in
                HStack {
                    Image(systemName: "arrow.left.arrow.right").foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(transfer.sourceSpool?.displayName ?? "?") → \(transfer.destinationSpool?.displayName ?? "?")")
                            .font(.subheadline)
                        Text("\(Format.date(transfer.date)) · \(Format.grams(transfer.grams))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Transfers")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack { TransferFormView() }
        }
    }
}

struct TransferFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var spools: [Spool]

    @State private var source: Spool?
    @State private var destination: Spool?
    @State private var grams = 0.0
    @State private var notes = ""

    private var canSave: Bool {
        guard let source, let destination, source.id != destination.id else { return false }
        return grams > 0 && grams <= source.currentWeightG
    }

    var body: some View {
        Form {
            Picker("From spool", selection: $source) {
                Text("Select…").tag(Spool?.none)
                ForEach(spools.filter { !$0.isArchived && $0.currentWeightG > 0 }) {
                    Text("\($0.displayName) (\(Format.grams($0.currentWeightG)))").tag(Spool?.some($0))
                }
            }
            Picker("To spool", selection: $destination) {
                Text("Select…").tag(Spool?.none)
                ForEach(spools.filter { !$0.isArchived && $0.id != source?.id }) {
                    Text($0.displayName).tag(Spool?.some($0))
                }
            }
            HStack {
                Text("Grams to move")
                Spacer()
                TextField("0", value: $grams, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                Text("g").foregroundStyle(.secondary)
            }
            if let source, grams > source.currentWeightG {
                Label("Source spool only holds \(Format.grams(source.currentWeightG)).", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
            TextField("Notes", text: $notes)
        }
        .navigationTitle("New Transfer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Transfer") {
                    guard let source, let destination else { return }
                    source.currentWeightG -= grams
                    destination.currentWeightG += grams
                    let transfer = FilamentTransfer()
                    transfer.sourceSpool = source
                    transfer.destinationSpool = destination
                    transfer.grams = grams
                    transfer.notes = notes
                    context.insert(transfer)
                    SyncEngine.shared.enqueue(.init(id: UUID(), kind: .filamentDelta, entity: "spools",
                                                    recordID: source.id, payload: nil, deltaGrams: -grams, queuedAt: Date()))
                    SyncEngine.shared.enqueue(.init(id: UUID(), kind: .filamentDelta, entity: "spools",
                                                    recordID: destination.id, payload: nil, deltaGrams: grams, queuedAt: Date()))
                    Haptics.success()
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
    }
}

// MARK: - Remaining-spool matching ("I need 310 g of PETG")

struct SpoolMatchView: View {
    @Query private var spools: [Spool]
    @State private var materialID = "petg"
    @State private var neededGrams = 310.0
    @State private var colorFilter = ""
    @State private var brandFilter = ""

    private var matches: [Spool] {
        spools.filter { spool in
            guard !spool.isArchived, spool.materialID == materialID else { return false }
            guard spool.currentWeightG >= neededGrams else { return false }
            if !colorFilter.isEmpty, !spool.colorName.localizedCaseInsensitiveContains(colorFilter) { return false }
            if !brandFilter.isEmpty, !spool.manufacturer.localizedCaseInsensitiveContains(brandFilter) { return false }
            return true
        }
        .sorted { $0.currentWeightG > $1.currentWeightG }
    }

    var body: some View {
        List {
            Section("I need…") {
                HStack {
                    TextField("Grams", value: $neededGrams, format: .number)
                        .keyboardType(.decimalPad)
                        .frame(width: 90)
                    Text("g of").foregroundStyle(.secondary)
                    Picker("Material", selection: $materialID) {
                        ForEach(MaterialLibrary.shared.materials) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                }
                TextField("Color contains…", text: $colorFilter)
                TextField("Brand contains…", text: $brandFilter)
            }
            Section("Matching Spools (\(matches.count))") {
                if matches.isEmpty {
                    Text("No spool has enough filament for this job.")
                        .foregroundStyle(.secondary)
                }
                ForEach(matches) { spool in
                    NavigationLink { SpoolDetailView(spool: spool) } label: {
                        SpoolRowView(spool: spool)
                    }
                }
            }
        }
        .navigationTitle("Find Filament")
    }
}

// MARK: - Desiccant tracker

struct DesiccantListView: View {
    @Environment(\.modelContext) private var context
    @Query private var units: [DesiccantUnit]
    @State private var showAdd = false

    var body: some View {
        List {
            if units.isEmpty {
                PKEmptyState(symbol: "drop", title: "No Desiccant Tracked",
                             message: "Track silica gel in dry boxes and AMS units so regeneration doesn't get forgotten.",
                             actionTitle: "Add Desiccant") { showAdd = true }
            }
            ForEach(units) { unit in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(unit.containerName).font(.subheadline.weight(.medium))
                        Spacer()
                        StatusBadge(status: unit.regenerationDue ? .attention : .ready,
                                    text: unit.regenerationDue ? "Regenerate" : "OK")
                    }
                    Text("\(unit.desiccantType) · last regenerated \(Format.date(unit.lastRegenerated))")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Regenerated Today") {
                            unit.lastRegenerated = Date()
                            Haptics.success()
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        Button("Replaced") {
                            unit.lastReplaced = Date()
                            unit.lastRegenerated = Date()
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .padding(.vertical, 2)
            }
            .onDelete { indexSet in
                for index in indexSet { context.delete(units[index]) }
            }
        }
        .navigationTitle("Desiccant")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack { DesiccantFormView() }
        }
    }
}

struct DesiccantFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var containerName = ""
    @State private var type = "Silica gel (indicating)"
    @State private var remindEveryDays = 30

    var body: some View {
        Form {
            TextField("Container (e.g. Dry Box 1)", text: $containerName)
            TextField("Desiccant type", text: $type)
            Stepper("Remind every \(remindEveryDays) days", value: $remindEveryDays, in: 7...180, step: 7)
        }
        .navigationTitle("Add Desiccant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let unit = DesiccantUnit()
                    unit.containerName = containerName
                    unit.desiccantType = type
                    unit.remindEveryDays = remindEveryDays
                    unit.lastRegenerated = Date()
                    context.insert(unit)
                    dismiss()
                }
                .disabled(containerName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

// MARK: - Wishlist & purchases

struct WishlistView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WishlistItem.createdAt, order: .reverse) private var items: [WishlistItem]
    @State private var showAdd = false

    var body: some View {
        List {
            if items.isEmpty {
                PKEmptyState(symbol: "heart", title: "Wishlist Empty",
                             message: "Track materials and colors you want to try.",
                             actionTitle: "Add Item") { showAdd = true }
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text([item.manufacturer, item.product].filter { !$0.isEmpty }.joined(separator: " "))
                        .font(.subheadline.weight(.medium))
                    Text([
                        MaterialLibrary.shared.material(for: item.materialID)?.name ?? "",
                        item.colorName,
                        item.targetPrice.map { "target " + Format.currency($0) } ?? ""
                    ].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                    if !item.projectIdea.isEmpty {
                        Text(item.projectIdea).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet { context.delete(items[index]) }
            }
        }
        .navigationTitle("Wishlist")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { NavigationStack { WishlistFormView() } }
    }
}

struct WishlistFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var manufacturer = ""
    @State private var product = ""
    @State private var materialID = "pla"
    @State private var colorName = ""
    @State private var targetPrice: Double?
    @State private var projectIdea = ""

    var body: some View {
        Form {
            TextField("Manufacturer", text: $manufacturer)
            TextField("Product", text: $product)
            Picker("Material", selection: $materialID) {
                ForEach(MaterialLibrary.shared.materials) { Text($0.name).tag($0.id) }
            }
            TextField("Desired color", text: $colorName)
            TextField("Target price", value: $targetPrice, format: .number).keyboardType(.decimalPad)
            TextField("Project idea", text: $projectIdea, axis: .vertical).lineLimit(2...4)
        }
        .navigationTitle("Wishlist Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let item = WishlistItem()
                    item.manufacturer = manufacturer
                    item.product = product
                    item.materialID = materialID
                    item.colorName = colorName
                    item.targetPrice = targetPrice
                    item.projectIdea = projectIdea
                    context.insert(item)
                    dismiss()
                }
            }
        }
    }
}

struct PurchaseListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PurchaseRecord.date, order: .reverse) private var purchases: [PurchaseRecord]
    @Query private var spools: [Spool]
    @State private var showAdd = false

    private var averagePerKg: Double? {
        let priced = spools.compactMap(\.costPerKg)
        guard !priced.isEmpty else { return nil }
        return priced.reduce(0, +) / Double(priced.count)
    }

    var body: some View {
        List {
            if let averagePerKg {
                Section("Summary") {
                    KeyValueRow(key: "Average price", value: Format.currency(averagePerKg) + "/kg")
                    KeyValueRow(key: "Spools on record", value: "\(spools.count)")
                    KeyValueRow(key: "Total spent", value: Format.currency(spools.reduce(0) { $0 + $1.cost }))
                }
            }
            Section("Purchases") {
                if purchases.isEmpty {
                    Text("Purchases are recorded automatically from spool cost/vendor fields, or add manual records here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(purchases) { purchase in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(purchase.spool?.displayName ?? purchase.vendor)
                            .font(.subheadline.weight(.medium))
                        Text("\(purchase.vendor) · \(Format.currency(purchase.price)) × \(purchase.quantity) · \(Format.date(purchase.date))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet { context.delete(purchases[index]) }
                }
            }
        }
        .navigationTitle("Purchases")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { NavigationStack { PurchaseFormView() } }
    }
}

struct PurchaseFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var spools: [Spool]
    @State private var spool: Spool?
    @State private var vendor = ""
    @State private var price = 0.0
    @State private var shipping = 0.0
    @State private var quantity = 1
    @State private var date = Date()

    var body: some View {
        Form {
            Picker("Spool", selection: $spool) {
                Text("Unlinked").tag(Spool?.none)
                ForEach(spools) { Text($0.displayName).tag(Spool?.some($0)) }
            }
            TextField("Vendor", text: $vendor)
            HStack { Text("Price"); Spacer(); TextField("0.00", value: $price, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100) }
            HStack { Text("Shipping"); Spacer(); TextField("0.00", value: $shipping, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100) }
            Stepper("Quantity \(quantity)", value: $quantity, in: 1...50)
            DatePicker("Date", selection: $date, displayedComponents: .date)
        }
        .navigationTitle("Add Purchase")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let record = PurchaseRecord()
                    record.spool = spool
                    record.vendor = vendor
                    record.price = price
                    record.shipping = shipping
                    record.quantity = quantity
                    record.date = date
                    context.insert(record)
                    dismiss()
                }
            }
        }
    }
}
