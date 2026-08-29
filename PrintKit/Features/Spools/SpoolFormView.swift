import SwiftUI
import SwiftData

/// Add / edit a spool. UUID identity is generated client-side so the record
/// is stable across NFC, QR, and (later) cloud sync.
struct SpoolFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StorageLocation.name) private var locations: [StorageLocation]

    let spool: Spool?

    @State private var manufacturer = ""
    @State private var productLine = ""
    @State private var materialID = "pla"
    @State private var colorName = ""
    @State private var colorHex = "#808080"
    @State private var finish = SpoolFinish.standard
    @State private var diameter = 1.75
    @State private var originalWeight = 1000.0
    @State private var currentWeight = 1000.0
    @State private var emptySpoolWeight = 140.0
    @State private var cost = 0.0
    @State private var vendor = ""
    @State private var purchaseDate = Date()
    @State private var hasPurchaseDate = false
    @State private var openedDate = Date()
    @State private var isOpened = false
    @State private var lotNumber = ""
    @State private var batchNumber = ""
    @State private var lotFlagged = false
    @State private var lotNotes = ""
    @State private var location: StorageLocation?
    @State private var amsSlotLabel = ""
    @State private var notes = ""
    @State private var isFavorite = false
    @State private var showColorPicker = false

    private var selectedColor: Color { Color(hex: colorHex) ?? .gray }

    var body: some View {
        Form {
            Section("Filament") {
                TextField("Manufacturer", text: $manufacturer)
                TextField("Product line", text: $productLine)
                Picker("Material", selection: $materialID) {
                    ForEach(MaterialLibrary.shared.materials) { material in
                        Text(material.name).tag(material.id)
                    }
                }
                Picker("Finish", selection: $finish) {
                    ForEach(SpoolFinish.allCases) { Text($0.displayName).tag($0) }
                }
                TextField("Color name", text: $colorName)
                HStack {
                    Text("Color")
                    Spacer()
                    Circle()
                        .fill(selectedColor)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Color(.separator)))
                    ColorPicker("", selection: Binding(
                        get: { selectedColor },
                        set: { colorHex = hexString(from: colorHex, color: $0) }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }
                Picker("Diameter", selection: $diameter) {
                    Text("1.75 mm").tag(1.75)
                    Text("2.85 mm").tag(2.85)
                }
            }

            Section("Weight") {
                Stepper(value: $originalWeight, in: 100...5000, step: 50) {
                    HStack {
                        Text("Original net")
                        Spacer()
                        Text(Format.grams(originalWeight)).monospacedDigit()
                    }
                }
                PKNumericField(label: "Current weight", value: $currentWeight, unit: "g")
                PKNumericField(label: "Empty spool", value: $emptySpoolWeight, unit: "g")
            }

            Section("Purchase") {
                PKNumericField(label: "Cost", value: $cost,
                               unit: AppSettings.shared.currencyCode, placeholder: "0.00")
                TextField("Vendor", text: $vendor)
                Toggle("Record purchase date", isOn: $hasPurchaseDate)
                if hasPurchaseDate {
                    DatePicker("Purchased", selection: $purchaseDate, displayedComponents: .date)
                }
                Toggle("Opened", isOn: $isOpened)
                if isOpened {
                    DatePicker("Opened", selection: $openedDate, displayedComponents: .date)
                }
            }

            Section("Lot / Batch") {
                TextField("Lot number", text: $lotNumber)
                TextField("Batch number", text: $batchNumber)
                Toggle("Flag this lot for quality concerns", isOn: $lotFlagged)
                if lotFlagged {
                    TextField("What's wrong with this lot?", text: $lotNotes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }

            Section("Storage") {
                Picker("Location", selection: $location) {
                    Text("None").tag(StorageLocation?.none)
                    ForEach(locations) { Text($0.name).tag(StorageLocation?.some($0)) }
                }
                TextField("AMS/MMU slot (e.g. AMS 1 · A2)", text: $amsSlotLabel)
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
            }

            Section {
                Toggle("Favorite", isOn: $isFavorite)
            }
        }
        .navigationTitle(spool == nil ? "Add Spool" : "Edit Spool")
        .pkDismissableKeyboard()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
        .onAppear(perform: loadIfEditing)
    }

    private func hexString(from old: String, color: Color) -> String {
        guard let components = UIColor(color).cgColor.components, components.count >= 3 else { return old }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func loadIfEditing() {
        guard let spool else {
            materialID = AppSettings.shared.defaultMaterialID
            diameter = AppSettings.shared.defaultDiameter
            originalWeight = AppSettings.shared.defaultSpoolGrams
            currentWeight = AppSettings.shared.defaultSpoolGrams
            return
        }
        manufacturer = spool.manufacturer
        productLine = spool.productLine
        materialID = spool.materialID
        colorName = spool.colorName
        colorHex = spool.colorHex
        finish = spool.finish
        diameter = spool.diameter
        originalWeight = spool.originalNetWeightG
        currentWeight = spool.currentWeightG
        emptySpoolWeight = spool.emptySpoolWeightG
        cost = spool.cost
        vendor = spool.vendor
        hasPurchaseDate = spool.purchaseDate != nil
        purchaseDate = spool.purchaseDate ?? Date()
        isOpened = spool.openedDate != nil
        openedDate = spool.openedDate ?? Date()
        lotNumber = spool.lotNumber
        batchNumber = spool.batchNumber
        lotFlagged = spool.lotFlagged
        lotNotes = spool.lotNotes
        location = spool.storageLocation
        amsSlotLabel = spool.amsSlotLabel
        notes = spool.notes
        isFavorite = spool.isFavorite
    }

    private func save() {
        let target = spool ?? Spool()
        target.manufacturer = manufacturer.trimmingCharacters(in: .whitespaces)
        target.productLine = productLine.trimmingCharacters(in: .whitespaces)
        target.materialID = materialID
        target.colorName = colorName.trimmingCharacters(in: .whitespaces)
        target.colorHex = colorHex
        target.finish = finish
        target.diameter = diameter
        target.originalNetWeightG = originalWeight
        target.currentWeightG = min(currentWeight, originalWeight)
        target.emptySpoolWeightG = emptySpoolWeight
        target.cost = cost
        target.vendor = vendor
        target.purchaseDate = hasPurchaseDate ? purchaseDate : nil
        target.openedDate = isOpened ? openedDate : nil
        target.lotNumber = lotNumber
        target.batchNumber = batchNumber
        target.lotFlagged = lotFlagged
        target.lotNotes = lotNotes
        target.storageLocation = location
        target.amsSlotLabel = amsSlotLabel
        target.notes = notes
        target.isFavorite = isFavorite

        if spool == nil {
            context.insert(target)
            SyncEngine.shared.enqueueSpool(target, kind: .create)
        } else {
            SyncEngine.shared.enqueueSpool(target, kind: .update)
        }
        Haptics.success()
        dismiss()
    }
}
