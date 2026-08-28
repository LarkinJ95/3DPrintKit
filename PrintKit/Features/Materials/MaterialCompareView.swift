import SwiftUI
import Charts

/// Side-by-side comparison of 2–5 materials with hideable traits,
/// comparison bars, and warnings — no spreadsheet wall.
struct MaterialCompareView: View {
    @State private var selectedIDs: [String] = []
    @State private var hiddenTraits: Set<MaterialTrait> = []
    @State private var showPicker = false

    private var selected: [FilamentMaterial] {
        selectedIDs.compactMap { MaterialLibrary.shared.material(for: $0) }
    }

    var body: some View {
        List {
            Section("Materials (\(selectedIDs.count)/5)") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PK.Spacing.sm) {
                        ForEach(selected) { material in
                            SelectableChip(title: material.name, isSelected: true) {
                                selectedIDs.removeAll { $0 == material.id }
                            }
                        }
                        if selectedIDs.count < 5 {
                            Button {
                                showPicker = true
                            } label: {
                                Label("Add", systemImage: "plus")
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: PK.Radius.chip))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            if selected.count >= 2 {
                Section("Ratings") {
                    ForEach(MaterialTrait.allCases.filter { !hiddenTraits.contains($0) }) { trait in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(trait.displayName).font(.subheadline.weight(.medium))
                                Spacer()
                                Button {
                                    hiddenTraits.insert(trait)
                                } label: {
                                    Image(systemName: "eye.slash")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Hide \(trait.displayName)")
                            }
                            ForEach(selected) { material in
                                HStack(spacing: PK.Spacing.sm) {
                                    Text(material.name)
                                        .font(.caption)
                                        .frame(width: 72, alignment: .leading)
                                        .lineLimit(1)
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color(.systemFill)).frame(height: 8)
                                            Capsule()
                                                .fill(Color.accentColor)
                                                .frame(width: geo.size.width * CGFloat(material.rating(for: trait)) / 5, height: 8)
                                        }
                                    }
                                    .frame(height: 8)
                                    Text("\(material.rating(for: trait))")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 16, alignment: .trailing)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(material.name) \(trait.displayName): \(material.rating(for: trait)) of 5")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if !hiddenTraits.isEmpty {
                        Button("Show Hidden Traits (\(hiddenTraits.count))") {
                            hiddenTraits.removeAll()
                        }
                        .font(.caption)
                    }
                }

                Section("Printing Requirements") {
                    ComparisonKeyRow(label: "Nozzle") { $0.nozzleRangeText }
                    ComparisonKeyRow(label: "Bed") { $0.bedRangeText }
                    ComparisonKeyRow(label: "Chamber") { $0.chamber.displayName }
                    ComparisonKeyRow(label: "Enclosure") { $0.enclosure.displayName }
                    ComparisonKeyRow(label: "Typical cost") { Format.currency($0.typicalCostPerKg) + "/kg" }
                }

                Section("Warnings") {
                    ForEach(selected) { material in
                        let warnings = warnings(for: material)
                        if !warnings.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(material.name).font(.subheadline.weight(.medium))
                                ForEach(warnings, id: \.self) { warning in
                                    Label(warning, systemImage: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section("Radar") {
                    Chart(selected) { material in
                        ForEach([MaterialTrait.strength, .toughness, .heatResistance, .ease, .outdoor], id: \.self) { trait in
                            BarMark(x: .value("Trait", trait.displayName),
                                    y: .value("Rating", material.rating(for: trait)))
                            .foregroundStyle(by: .value("Material", material.name))
                            .position(by: .value("Trait", trait.displayName))
                        }
                    }
                    .frame(height: 220)
                }
            } else {
                Section {
                    Text("Select at least two materials to compare.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Compare Materials")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                List(MaterialLibrary.shared.materials.filter { !selectedIDs.contains($0.id) }) { material in
                    Button(material.name) {
                        selectedIDs.append(material.id)
                        showPicker = false
                    }
                }
                .navigationTitle("Add Material")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showPicker = false } } }
            }
        }
    }

    @ViewBuilder
    private func ComparisonKeyRow(label: String, _ value: @escaping (FilamentMaterial) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            ForEach(selected) { material in
                HStack {
                    Text(material.name).font(.caption).frame(width: 72, alignment: .leading).lineLimit(1)
                    Text(value(material)).font(.caption.monospacedDigit())
                    Spacer()
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func warnings(for material: FilamentMaterial) -> [String] {
        var result: [String] = []
        if material.hardenedNozzleRequired { result.append("Requires hardened nozzle") }
        if material.chamber == .required { result.append("Requires heated chamber or enclosure") }
        if material.hygroscopic >= 4 { result.append("Very hygroscopic — dry before use") }
        if material.ventilation >= 4 { result.append("Strong ventilation required") }
        if material.warpResistance <= 2 { result.append("Prone to warping") }
        return result
    }
}
