import SwiftUI
import SwiftData

/// "What Should I Print This With?" — requirement selection with priority
/// weights, ranked results with reasons and tradeoffs.
struct MaterialAssistantView: View {
    @Query private var spools: [Spool]
    @State private var weights: [PrintRequirement: Int] = [:]

    private var results: [MaterialRecommendation] {
        MaterialAdvisor.rank(requirements: weights)
    }

    var body: some View {
        List {
            Section("Requirements (tap to cycle: off · nice · important · critical)") {
                ChipFlowLayout {
                    ForEach(PrintRequirement.allCases) { requirement in
                        RequirementChip(requirement: requirement, level: weights[requirement] ?? 0) {
                            let current = weights[requirement] ?? 0
                            weights[requirement] = (current + 1) % 4
                            if weights[requirement] == 0 { weights.removeValue(forKey: requirement) }
                        }
                    }
                }
            }

            if !results.isEmpty {
                Section("Ranked Materials") {
                    ForEach(Array(results.prefix(8).enumerated()), id: \.element.id) { index, recommendation in
                        NavigationLink {
                            RecommendationDetailView(recommendation: recommendation, inventorySpools: inventory(matching: recommendation.material))
                        } label: {
                            HStack(spacing: PK.Spacing.md) {
                                Text("\(index + 1)")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recommendation.material.name)
                                        .font(.subheadline.weight(.medium))
                                    Text(recommendation.reasons.first ?? recommendation.material.tagline)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Text(String(format: "%.0f", recommendation.score))
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                + Text(" /100").font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } else {
                Section {
                    Text("Choose one or more requirements and 3DPrintKit ranks every reference material with reasons and tradeoffs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Print This With…")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func inventory(matching material: FilamentMaterial) -> [Spool] {
        spools.filter { $0.materialID == material.id && !$0.isArchived && $0.currentWeightG > 0 }
    }
}

struct RequirementChip: View {
    let requirement: PrintRequirement
    let level: Int
    let action: () -> Void

    private var label: String {
        switch level {
        case 1: return "\(requirement.displayName) ·"
        case 2: return "\(requirement.displayName) ••"
        case 3: return "\(requirement.displayName) •••"
        default: return requirement.displayName
        }
    }

    var body: some View {
        SelectableChip(title: label, isSelected: level > 0, action: action)
            .accessibilityLabel("\(requirement.displayName), priority \(["off", "nice to have", "important", "critical"][level])")
    }
}

struct RecommendationDetailView: View {
    let recommendation: MaterialRecommendation
    let inventorySpools: [Spool]

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Match score")
                    Spacer()
                    Text(String(format: "%.0f/100", recommendation.score))
                        .font(.headline.monospacedDigit())
                }
            }

            if !recommendation.reasons.isEmpty {
                Section("Best match because") {
                    ForEach(recommendation.reasons, id: \.self) { reason in
                        Label(reason, systemImage: "checkmark.circle")
                            .font(.subheadline)
                    }
                }
            }

            if !recommendation.tradeoffs.isEmpty {
                Section("Tradeoffs") {
                    ForEach(recommendation.tradeoffs, id: \.self) { tradeoff in
                        Label(tradeoff, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if !inventorySpools.isEmpty {
                Section("You Have This in Stock") {
                    ForEach(inventorySpools) { spool in
                        NavigationLink { SpoolDetailView(spool: spool) } label: {
                            SpoolRowView(spool: spool)
                        }
                    }
                }
            }

            Section {
                NavigationLink {
                    MaterialDetailView(material: recommendation.material)
                } label: {
                    Label("Full \(recommendation.material.name) Reference", systemImage: "book")
                }
            }
        }
        .navigationTitle(recommendation.material.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "What can I use instead?" — mechanical/thermal similarity ranking.
struct SubstitutionView: View {
    @State private var baseID = "asa"

    private var substitutes: [MaterialSubstitution] {
        MaterialAdvisor.substitutes(for: baseID)
    }

    private var baseName: String {
        MaterialLibrary.shared.material(for: baseID)?.name ?? baseID
    }

    var body: some View {
        List {
            Section("Out of…") {
                Picker("Material", selection: $baseID) {
                    ForEach(MaterialLibrary.shared.materials) { Text($0.name).tag($0.id) }
                }
            }
            Section("Potential substitutes for \(baseName)") {
                ForEach(Array(substitutes.prefix(6).enumerated()), id: \.element.id) { index, sub in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(index + 1). \(sub.material.name)")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(String(format: "%.0f%% similar", sub.score))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ForEach(sub.changes, id: \.self) { change in
                            Text(change)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Substitution")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Printers × materials compatibility matrix.
struct CompatibilityMatrixView: View {
    @Query private var printers: [PrinterDevice]

    var body: some View {
        List {
            if printers.isEmpty {
                PKEmptyState(symbol: "printer",
                             title: "No Printers Yet",
                             message: "Add a printer in the Garage to see material compatibility.")
            }
            ForEach(printers) { printer in
                Section(printer.displayName) {
                    ForEach(MaterialLibrary.shared.materials) { material in
                        let result = CompatibilityEngine.evaluate(printer: printer, material: material)
                        NavigationLink {
                            CompatibilityDetailView(printer: printer, material: material, result: result)
                        } label: {
                            HStack {
                                Text(material.name).font(.subheadline)
                                Spacer()
                                StatusBadge(status: result.level.pkStatus, text: result.level.rawValue)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Compatibility")
    }
}

struct CompatibilityDetailView: View {
    let printer: PrinterDevice
    let material: FilamentMaterial
    let result: CompatibilityResult

    var body: some View {
        List {
            Section {
                HStack {
                    StatusBadge(status: result.level.pkStatus, text: result.level.rawValue)
                }
            }
            Section("Why") {
                ForEach(result.reasons, id: \.self) { reason in
                    Text(reason).font(.subheadline)
                }
            }
        }
        .navigationTitle("\(printer.displayName) · \(material.name)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
