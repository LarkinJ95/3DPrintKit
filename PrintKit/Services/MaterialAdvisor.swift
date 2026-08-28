import Foundation

/// Requirements for the "What Should I Print This With?" assistant.
enum PrintRequirement: String, CaseIterable, Identifiable {
    case outdoorUse, highHeat, maxStrength, maxToughness, impactResistance
    case flexible, chemicalResistance, waterResistance, uvResistance
    case foodContactResearch, easyPrinting, lowWarping, transparent
    case functionalPrototype, mechanicalComponent, automotive, decorative
    case enclosurePart, flexibleGasket, snapFit, wearComponent

    var id: String { rawValue }

    var displayName: String {
        rawValue.camelCasedToWords().capitalized
    }
}

struct MaterialRecommendation: Identifiable {
    let material: FilamentMaterial
    let score: Double
    let reasons: [String]
    let tradeoffs: [String]

    var id: String { material.id }
}

struct MaterialSubstitution: Identifiable {
    let material: FilamentMaterial
    let score: Double
    let changes: [String]

    var id: String { material.id }
}

/// Deterministic, explainable material ranking. Scores are transparent:
/// every recommendation lists exactly which requirement drove it.
enum MaterialAdvisor {

    /// Rank all materials against the selected requirements.
    static func rank(requirements: [PrintRequirement: Int],
                     materials: [FilamentMaterial] = MaterialLibrary.shared.materials) -> [MaterialRecommendation] {
        let active = requirements.filter { $0.value > 0 }
        guard !active.isEmpty else { return [] }

        return materials.map { material in
            var score = 0.0
            var maxPossible = 0.0
            var reasons: [String] = []
            var tradeoffs: [String] = []

            for (requirement, weight) in active {
                let w = Double(weight)
                maxPossible += w * 5
                let (points, reason, tradeoff) = evaluate(material, for: requirement)
                score += w * Double(points)
                if let reason { reasons.append(reason) }
                if let tradeoff { tradeoffs.append(tradeoff) }
            }

            let normalized = maxPossible > 0 ? score / maxPossible : 0
            return MaterialRecommendation(
                material: material,
                score: (normalized * 100).rounded() / 10,
                reasons: Array(reasons.prefix(4)),
                tradeoffs: Array(tradeoffs.prefix(3))
            )
        }
        .sorted { $0.score > $1.score }
    }

    /// Points 0...5 with a human-readable justification.
    private static func evaluate(_ m: FilamentMaterial, for req: PrintRequirement) -> (Int, String?, String?) {
        switch req {
        case .outdoorUse:
            return (m.outdoor, m.outdoor >= 4 ? "Strong outdoor durability (UV + weather)" : nil,
                    m.outdoor <= 2 ? "Poor outdoor durability" : nil)
        case .highHeat:
            return (m.heatResistance, m.heatResistance >= 4 ? "High heat resistance" : nil,
                    m.heatResistance <= 2 ? "Softens at moderate temperatures" : nil)
        case .maxStrength:
            return (m.strength, m.strength >= 4 ? "High tensile strength" : nil, nil)
        case .maxToughness:
            return (m.toughness, m.toughness >= 4 ? "Very tough, resists cracking" : nil, nil)
        case .impactResistance:
            return (m.impact, m.impact >= 4 ? "Excellent impact resistance" : nil, nil)
        case .flexible:
            return (m.flexibility, m.flexibility >= 4 ? "Highly flexible" : nil,
                    m.flexibility >= 4 ? "Requires slower printing and careful retraction" : nil)
        case .chemicalResistance:
            return (m.chemicalResistance, m.chemicalResistance >= 4 ? "Resists many chemicals" : nil, nil)
        case .waterResistance:
            return (m.waterResistance, m.waterResistance >= 4 ? "Good moisture resistance" : nil, nil)
        case .uvResistance:
            return (m.uvResistance, m.uvResistance >= 4 ? "Excellent UV stability" : nil, nil)
        case .foodContactResearch:
            // No consumer FDM print is certified food-safe; provide research-relevant signal only.
            let points = m.id == "petg" || m.id == "pet" || m.id == "pp" || m.id == "pla" ? 3 : 1
            return (points, points >= 3 ? "Base resin commonly discussed in food-contact research" : nil,
                    "No FDM print is certified food-safe; layer lines harbor bacteria — research required")
        case .easyPrinting:
            return (m.ease, m.ease >= 4 ? "Beginner-friendly" : nil,
                    m.ease <= 2 ? "Demanding print conditions" : nil)
        case .lowWarping:
            return (m.warpResistance, m.warpResistance >= 4 ? "Minimal warping" : nil,
                    m.warpResistance <= 2 ? "Warps readily without an enclosure" : nil)
        case .transparent:
            return (m.translucent ? 5 : 0, m.translucent ? "Available in transparent/translucent forms" : nil, nil)
        case .functionalPrototype:
            return ((m.ease + m.strength) / 2, m.ease >= 4 ? "Fast, forgiving iteration" : nil, nil)
        case .mechanicalComponent:
            return ((m.strength + m.stiffness + m.creepResistance) / 3,
                    m.stiffness >= 4 ? "Rigid and dimensionally stable" : nil,
                    m.creepResistance <= 2 ? "Creeps under sustained load" : nil)
        case .automotive:
            return ((m.heatResistance + m.uvResistance + m.chemicalResistance) / 3,
                    m.heatResistance >= 4 ? "Tolerates cabin temperatures" : nil,
                    m.heatResistance <= 2 ? "Deforms in a hot car" : nil)
        case .decorative:
            return (m.surfaceQuality, m.surfaceQuality >= 4 ? "Attractive surface finish" : nil, nil)
        case .enclosurePart:
            return ((m.stiffness + m.warpResistance) / 2,
                    m.warpResistance >= 4 ? "Holds shape on large flat panels" : nil, nil)
        case .flexibleGasket:
            return (m.flexibility >= 4 ? 5 : m.flexibility,
                    m.flexibility >= 4 ? "Compresses and seals" : nil, nil)
        case .snapFit:
            return ((m.toughness + m.flexibility) / 2,
                    m.toughness >= 4 ? "Survives repeated flexing" : nil,
                    m.toughness <= 2 ? "Brittle — snap features may crack" : nil)
        case .wearComponent:
            return ((m.toughness + (m.id == "pom" ? 5 : m.strength)) / 2,
                    m.id == "pom" ? "Low-friction acetal, classic wear material" : nil, nil)
        }
    }

    // MARK: - Substitution

    /// Rank substitutes for a material using mechanical/thermal similarity.
    static func substitutes(for materialID: String,
                            materials: [FilamentMaterial] = MaterialLibrary.shared.materials) -> [MaterialSubstitution] {
        guard let base = materials.first(where: { $0.id == materialID }) else { return [] }
        return materials
            .filter { $0.id != base.id }
            .map { candidate in
                let traits: [MaterialTrait] = [.strength, .toughness, .stiffness, .impact, .flexibility,
                                               .heatResistance, .uvResistance, .chemicalResistance,
                                               .waterResistance, .ease]
                var diff = 0
                for trait in traits {
                    diff += abs(base.rating(for: trait) - candidate.rating(for: trait))
                }
                let tempPenalty = abs(base.nozzleMax - candidate.nozzleMax) / 20
                let similarity = max(0, 100 - diff * 3 - tempPenalty)

                var changes: [String] = []
                for trait in traits where abs(base.rating(for: trait) - candidate.rating(for: trait)) >= 2 {
                    let direction = candidate.rating(for: trait) > base.rating(for: trait) ? "higher" : "lower"
                    changes.append("\(trait.displayName): \(direction) than \(base.name)")
                }
                if candidate.ease > base.ease { changes.append("Easier to print") }
                if candidate.ease < base.ease { changes.append("Harder to print") }
                if candidate.chamber != base.chamber {
                    changes.append("Chamber: \(candidate.chamber.displayName.lowercased()) (was \(base.chamber.displayName.lowercased()))")
                }
                return MaterialSubstitution(material: candidate, score: Double(similarity), changes: Array(changes.prefix(4)))
            }
            .sorted { $0.score > $1.score }
    }
}
