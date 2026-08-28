import Foundation

/// Reference filament material loaded from the bundled `materials.json`.
///
/// All values are *general reference* data unless tagged otherwise and must
/// never be presented as exact laboratory measurements. Users can override
/// defaults per material via `MaterialOverride`.
struct FilamentMaterial: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let family: String
    let tagline: String
    let density: Double            // g/cm^3
    let typicalCostPerKg: Double   // USD, rough market reference

    // Printing
    let nozzleMin: Int
    let nozzleMax: Int
    let bedMin: Int
    let bedMax: Int
    let chamber: Requirement      // enclosure/chamber recommendation
    let enclosure: Requirement
    let cooling: Int               // typical fan %
    let typicalSpeed: Int          // mm/s
    let maxFlow: Double            // typical volumetric limit mm^3/s
    let retraction: String
    let bedSurfaces: [String]
    let adhesion: String
    let supportMaterials: [String]
    let ventilation: Int           // 1 little concern ... 5 strong ventilation needed
    let odor: Int                  // 1 none ... 5 strong

    // Handling
    let hygroscopic: Int           // 1 low ... 5 very hygroscopic
    let dryTemp: Int               // °C
    let dryHours: Int
    let storage: String
    let abrasive: Bool
    let hardenedNozzleRequired: Bool

    // Mechanical / environmental / difficulty ratings: 1 (low/poor) ... 5 (high/excellent).
    let strength: Int
    let toughness: Int
    let stiffness: Int
    let impact: Int
    let flexibility: Int
    let layerAdhesion: Int
    let creepResistance: Int
    let dimensionalStability: Int
    let heatResistance: Int
    let uvResistance: Int
    let waterResistance: Int
    let chemicalResistance: Int
    let outdoor: Int
    let warpResistance: Int        // 5 = virtually no warping
    let stringResistance: Int      // 5 = rarely strings
    let ease: Int                  // ease of printing
    let surfaceQuality: Int
    let supportRemoval: Int        // 5 = trivial removal
    let translucent: Bool

    enum Requirement: String, Codable, CaseIterable {
        case notRequired = "not-required"
        case optional = "optional"
        case recommended = "recommended"
        case required = "required"

        var displayName: String {
            switch self {
            case .notRequired: return "Not required"
            case .optional: return "Optional"
            case .recommended: return "Recommended"
            case .required: return "Required"
            }
        }
    }

    var nozzleRangeText: String { "\(nozzleMin)–\(nozzleMax) °C" }
    var bedRangeText: String { bedMin == 0 ? "Off–\(bedMax) °C" : "\(bedMin)–\(bedMax) °C" }

    func rating(for trait: MaterialTrait) -> Int {
        switch trait {
        case .strength: return strength
        case .toughness: return toughness
        case .stiffness: return stiffness
        case .impact: return impact
        case .flexibility: return flexibility
        case .heatResistance: return heatResistance
        case .uvResistance: return uvResistance
        case .waterResistance: return waterResistance
        case .chemicalResistance: return chemicalResistance
        case .creepResistance: return creepResistance
        case .dimensionalStability: return dimensionalStability
        case .warpResistance: return warpResistance
        case .ease: return ease
        case .outdoor: return outdoor
        case .surfaceQuality: return surfaceQuality
        case .layerAdhesion: return layerAdhesion
        }
    }
}

/// Comparable material traits used by comparison and the selection assistant.
enum MaterialTrait: String, CaseIterable, Identifiable {
    case strength, toughness, stiffness, impact, flexibility
    case heatResistance, uvResistance, waterResistance, chemicalResistance
    case creepResistance, dimensionalStability, warpResistance
    case ease, outdoor, surfaceQuality, layerAdhesion

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strength: return "Strength"
        case .toughness: return "Toughness"
        case .stiffness: return "Rigidity"
        case .impact: return "Impact Resistance"
        case .flexibility: return "Flexibility"
        case .heatResistance: return "Heat Resistance"
        case .uvResistance: return "UV Resistance"
        case .waterResistance: return "Water Resistance"
        case .chemicalResistance: return "Chemical Resistance"
        case .creepResistance: return "Creep Resistance"
        case .dimensionalStability: return "Dimensional Stability"
        case .warpResistance: return "Low Warping"
        case .ease: return "Ease of Printing"
        case .outdoor: return "Outdoor Suitability"
        case .surfaceQuality: return "Cosmetic Quality"
        case .layerAdhesion: return "Layer Adhesion"
        }
    }
}
