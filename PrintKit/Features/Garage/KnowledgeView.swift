import SwiftUI
import SwiftData

/// Personal printing knowledge layer: aggregates what *you* have learned —
/// known-good settings, recorded success rates, solved failures, and personal
/// material notes. Everything here is derived from your own data and labeled
/// as personal, never blended silently into reference data.
struct KnowledgeView: View {
    @Query private var profiles: [SlicerProfile]
    @Query private var records: [PrintRecord]
    @Query private var failures: [FailureReport]
    @Query private var overrides: [MaterialOverride]

    private var knownGood: [SlicerProfile] {
        profiles.filter { $0.isKnownGood }.sorted { ($0.recordedSuccessRate ?? 0) > ($1.recordedSuccessRate ?? 0) }
    }

    private var solvedFailures: [FailureReport] {
        failures.filter { !$0.finalSolution.isEmpty }.sorted { $0.date > $1.date }
    }

    private var notedOverrides: [MaterialOverride] {
        overrides.filter { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Personal success rate per material, computed only from logged prints.
    private var materialStats: [(material: FilamentMaterial, success: Int, total: Int)] {
        var tally: [String: (success: Int, total: Int)] = [:]
        for record in records where !record.materialID.isEmpty {
            var entry = tally[record.materialID] ?? (0, 0)
            entry.total += 1
            if record.success { entry.success += 1 }
            tally[record.materialID] = entry
        }
        return tally.compactMap { key, value in
            guard let material = MaterialLibrary.shared.material(for: key), value.total >= 3 else { return nil }
            return (material, value.success, value.total)
        }
        .sorted { Double($0.success) / Double($0.total) > Double($1.success) / Double($1.total) }
    }

    var body: some View {
        List {
            Section {
                Label("Everything on this page comes from your own prints, profiles, and notes — personal data, not reference values.",
                      systemImage: "person.crop.circle.badge.checkmark")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)

            Section("Known-Good Settings") {
                if knownGood.isEmpty {
                    Text("Mark a slicer profile as Known Good after a proven print and it will appear here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(knownGood) { profile in
                    NavigationLink { ProfileDetailView(profile: profile) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(profile.name).font(.subheadline.weight(.medium))
                                Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.green)
                            }
                            Text([
                                MaterialLibrary.shared.material(for: profile.materialID)?.name,
                                "\(Int(profile.nozzleTemp)) °C",
                                profile.recordedSuccessRate.map { Format.percent($0 * 100) + " success" }
                            ].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("Your Success Rates by Material") {
                if materialStats.isEmpty {
                    Text("Log at least 3 prints with the same material to see your personal success rate.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(materialStats, id: \.material.id) { stat in
                    HStack {
                        Text(stat.material.name).font(.subheadline)
                        Spacer()
                        RatingBar(value: Int((Double(stat.success) / Double(stat.total) * 5).rounded()))
                        Text("\(stat.success)/\(stat.total)")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(stat.material.name): \(stat.success) of \(stat.total) prints succeeded")
                }
            }

            Section("Fixes That Worked") {
                if solvedFailures.isEmpty {
                    Text("Solved failures from your journal appear here as a searchable personal knowledge base.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(solvedFailures.prefix(10)) { report in
                    NavigationLink { FailureReportDetailView(report: report) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(report.category.isEmpty ? "Failure" : report.category)
                                .font(.subheadline.weight(.medium))
                            Text(report.finalSolution)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("Your Material Notes") {
                if notedOverrides.isEmpty {
                    Text("Add personal notes to any material (Material → Personal Results) and they will be collected here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(notedOverrides) { override in
                    if let material = MaterialLibrary.shared.material(for: override.materialID) {
                        NavigationLink { MaterialDetailView(material: material) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(material.name).font(.subheadline.weight(.medium))
                                Text(override.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .navigationTitle("Personal Knowledge")
    }
}
