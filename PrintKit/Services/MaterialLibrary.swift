import Foundation

/// Offline reference library of filament materials.
/// Loads the bundled seed JSON once and serves lookups. Personal overrides
/// (MaterialOverride) are applied at read time and never mutate the seed.
final class MaterialLibrary {
    static let shared = MaterialLibrary()

    private(set) var materials: [FilamentMaterial] = []
    private var byID: [String: FilamentMaterial] = [:]

    private init() {
        load()
    }

    private struct SeedFile: Codable {
        let schema: String
        let version: Int
        let source: String
        let materials: [FilamentMaterial]
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "materials", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let seed = try? JSONDecoder().decode(SeedFile.self, from: data) else {
            materials = []
            return
        }
        materials = seed.materials.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        byID = Dictionary(uniqueKeysWithValues: materials.map { ($0.id, $0) })
    }

    func material(for id: String) -> FilamentMaterial? {
        byID[id]
    }

    func search(_ query: String) -> [FilamentMaterial] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return materials }
        return materials.filter {
            $0.name.lowercased().contains(q) ||
            $0.family.lowercased().contains(q) ||
            $0.tagline.lowercased().contains(q)
        }
    }

    /// Effective printing values for a material, with personal overrides applied.
    func effectiveValues(for materialID: String, override: MaterialOverride?) -> (nozzle: ClosedRange<Int>, bed: ClosedRange<Int>, dryTemp: Int, dryHours: Int)? {
        guard let material = material(for: materialID) else { return nil }
        let nozzle = (override?.nozzleMin ?? material.nozzleMin)...(override?.nozzleMax ?? material.nozzleMax)
        let bed = (override?.bedMin ?? material.bedMin)...(override?.bedMax ?? material.bedMax)
        return (nozzle, bed, override?.dryTemp ?? material.dryTemp, override?.dryHours ?? material.dryHours)
    }
}
