import SwiftUI
import SwiftData

/// Full material reference with progressive disclosure. Reference values are
/// labeled; personal overrides live in MaterialOverride and are applied on top.
struct MaterialDetailView: View {
    let material: FilamentMaterial
    @Environment(\.modelContext) private var context
    @Query private var overrides: [MaterialOverride]
    @Query private var spools: [Spool]
    @Query private var prints: [PrintRecord]
    @State private var showOverrideEditor = false

    private var personalOverride: MaterialOverride? {
        overrides.first { $0.materialID == material.id }
    }

    private var inventorySpools: [Spool] {
        spools.filter { $0.materialID == material.id && !$0.isArchived }
    }

    private var personalPrints: [PrintRecord] {
        prints.filter { $0.materialID == material.id }
    }

    private var personalSuccessRate: Double? {
        guard !personalPrints.isEmpty else { return nil }
        return Double(personalPrints.filter(\.success).count) / Double(personalPrints.count)
    }

    var body: some View {
        List {
            // MARK: Header metrics
            Section {
                HStack(spacing: PK.Spacing.xl) {
                    MetricView(label: "Nozzle", value: effectiveNozzleText)
                    MetricView(label: "Bed", value: effectiveBedText)
                    MetricView(label: "Drying", value: "\(personalOverride?.dryTemp ?? material.dryTemp) °C")
                    MetricView(label: "Enclosure", value: material.enclosure.displayName)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                if personalOverride != nil {
                    HStack {
                        SourceTag(source: .personal)
                        Text("Personal overrides applied").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Edit") { showOverrideEditor = true }
                            .font(.caption)
                    }
                }
            }

            // MARK: Printing
            DisclosureGroup("Printing") {
                KeyValueRow(key: "Nozzle temperature", value: material.nozzleRangeText, source: .reference)
                KeyValueRow(key: "Bed temperature", value: material.bedRangeText, source: .reference)
                KeyValueRow(key: "Chamber", value: material.chamber.displayName)
                KeyValueRow(key: "Enclosure", value: material.enclosure.displayName)
                KeyValueRow(key: "Cooling fan", value: "≈ \(material.cooling)%")
                KeyValueRow(key: "Typical speed", value: "≈ \(material.typicalSpeed) mm/s")
                KeyValueRow(key: "Volumetric flow", value: String(format: "≈ %.0f mm³/s", material.maxFlow))
                KeyValueRow(key: "Retraction", value: material.retraction)
                KeyValueRow(key: "Bed surfaces", value: material.bedSurfaces.joined(separator: ", "))
                KeyValueRow(key: "Adhesion", value: material.adhesion)
                KeyValueRow(key: "Support pairing", value: material.supportMaterials.map { $0.uppercased() }.joined(separator: ", "))
                KeyValueRow(key: "Ventilation", value: ventilationText)
            }

            // MARK: Mechanical
            DisclosureGroup("Mechanical Properties") {
                RatingRow(label: "Strength", value: material.strength)
                RatingRow(label: "Toughness", value: material.toughness)
                RatingRow(label: "Stiffness", value: material.stiffness)
                RatingRow(label: "Impact resistance", value: material.impact)
                RatingRow(label: "Flexibility", value: material.flexibility)
                RatingRow(label: "Layer adhesion", value: material.layerAdhesion)
                RatingRow(label: "Creep resistance", value: material.creepResistance)
                RatingRow(label: "Dimensional stability", value: material.dimensionalStability)
            }

            // MARK: Environmental
            DisclosureGroup("Environmental") {
                RatingRow(label: "Heat resistance", value: material.heatResistance)
                RatingRow(label: "UV resistance", value: material.uvResistance)
                RatingRow(label: "Water resistance", value: material.waterResistance)
                RatingRow(label: "Chemical resistance", value: material.chemicalResistance)
                RatingRow(label: "Outdoor suitability", value: material.outdoor)
            }

            // MARK: Handling
            DisclosureGroup("Handling") {
                RatingRow(label: "Moisture sensitivity", value: material.hygroscopic)
                KeyValueRow(key: "Drying", value: "\(material.dryTemp) °C · \(material.dryHours)h", source: .reference)
                KeyValueRow(key: "Storage", value: material.storage)
                KeyValueRow(key: "Abrasive", value: material.abrasive ? "Yes" : "No")
                KeyValueRow(key: "Hardened nozzle", value: material.hardenedNozzleRequired ? "Required" : "Not required")
                KeyValueRow(key: "Odor", value: odorText)
            }

            // MARK: Difficulty
            DisclosureGroup("Printing Difficulty") {
                RatingRow(label: "Ease of printing", value: material.ease)
                RatingRow(label: "Warp resistance", value: material.warpResistance)
                RatingRow(label: "String resistance", value: material.stringResistance)
                RatingRow(label: "Surface finish", value: material.surfaceQuality)
                RatingRow(label: "Support removal", value: material.supportRemoval)
            }

            // MARK: Personal results
            Section {
                if let rate = personalSuccessRate {
                    HStack {
                        SourceTag(source: .personal)
                        Text("Your history")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    KeyValueRow(key: "Prints logged", value: "\(personalPrints.count)")
                    KeyValueRow(key: "Your success rate", value: Format.percent(rate * 100))
                    Text("Based on your own logged prints — not a universal fact.")
                        .font(.caption2).foregroundStyle(.tertiary)
                } else {
                    Text("No personal print history with this material yet.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } header: {
                Text("Personal Results")
            }

            // MARK: Your inventory
            if !inventorySpools.isEmpty {
                Section("In Your Inventory") {
                    ForEach(inventorySpools) { spool in
                        NavigationLink { SpoolDetailView(spool: spool) } label: {
                            SpoolRowView(spool: spool)
                        }
                    }
                }
            }

            Section {
                Button {
                    showOverrideEditor = true
                } label: {
                    Label(personalOverride == nil ? "Override Reference Values" : "Edit Overrides", systemImage: "slider.horizontal.3")
                }
            } footer: {
                Text("Reference values are general community-typical guidance, not laboratory measurements. Overrides are yours alone and never modify the reference database.")
                    .font(.caption)
            }
        }
        .navigationTitle(material.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showOverrideEditor) {
            NavigationStack { MaterialOverrideView(material: material, existing: personalOverride) }
        }
    }

    private var effectiveNozzleText: String {
        let min = personalOverride?.nozzleMin ?? material.nozzleMin
        let max = personalOverride?.nozzleMax ?? material.nozzleMax
        return "\(min)–\(max) °C"
    }

    private var effectiveBedText: String {
        let min = personalOverride?.bedMin ?? material.bedMin
        let max = personalOverride?.bedMax ?? material.bedMax
        return min == 0 ? "Off–\(max) °C" : "\(min)–\(max) °C"
    }

    private var ventilationText: String {
        switch material.ventilation {
        case 1: return "Minimal concern"
        case 2: return "Normal room ventilation"
        case 3: return "Ventilate the room"
        case 4: return "Good ventilation required"
        default: return "Strong ventilation / filtration required"
        }
    }

    private var odorText: String {
        switch material.odor {
        case 1: return "Little to none"
        case 2: return "Slight"
        case 3: return "Noticeable"
        default: return "Strong"
        }
    }
}

struct RatingRow: View {
    let label: String
    let value: Int

    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            RatingBar(value: value)
        }
    }
}

/// Per-material personal overrides.
struct MaterialOverrideView: View {
    let material: FilamentMaterial
    let existing: MaterialOverride?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var nozzleMin: Double = 0
    @State private var nozzleMax: Double = 0
    @State private var bedMin: Double = 0
    @State private var bedMax: Double = 0
    @State private var dryTemp: Double = 0
    @State private var dryHours: Double = 0
    @State private var notes = ""

    var body: some View {
        Form {
            Section("Your Tested Values — \(material.name)") {
                Stepper("Nozzle min \(Int(nozzleMin)) °C", value: $nozzleMin, in: 150...350, step: 5)
                Stepper("Nozzle max \(Int(nozzleMax)) °C", value: $nozzleMax, in: 150...350, step: 5)
                Stepper("Bed min \(Int(bedMin)) °C", value: $bedMin, in: 0...140, step: 5)
                Stepper("Bed max \(Int(bedMax)) °C", value: $bedMax, in: 0...140, step: 5)
                Stepper("Dry \(Int(dryTemp)) °C", value: $dryTemp, in: 35...120, step: 5)
                Stepper("Dry \(Int(dryHours))h", value: $dryHours, in: 1...24, step: 1)
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...4)
            }
            if existing != nil {
                Section {
                    Button("Remove Overrides", role: .destructive) {
                        if let existing { context.delete(existing) }
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("Overrides")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
        .onAppear {
            nozzleMin = Double(existing?.nozzleMin ?? material.nozzleMin)
            nozzleMax = Double(existing?.nozzleMax ?? material.nozzleMax)
            bedMin = Double(existing?.bedMin ?? material.bedMin)
            bedMax = Double(existing?.bedMax ?? material.bedMax)
            dryTemp = Double(existing?.dryTemp ?? material.dryTemp)
            dryHours = Double(existing?.dryHours ?? material.dryHours)
            notes = existing?.notes ?? ""
        }
    }

    private func save() {
        let override = existing ?? MaterialOverride()
        override.materialID = material.id
        override.nozzleMin = Int(nozzleMin)
        override.nozzleMax = Int(nozzleMax)
        override.bedMin = Int(bedMin)
        override.bedMax = Int(bedMax)
        override.dryTemp = Int(dryTemp)
        override.dryHours = Int(dryHours)
        override.notes = notes
        if existing == nil { context.insert(override) }
        Haptics.success()
        dismiss()
    }
}
