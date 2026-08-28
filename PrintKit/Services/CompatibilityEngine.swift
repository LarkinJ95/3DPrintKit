import Foundation

enum CompatibilityLevel: String {
    case compatible = "Compatible"
    case withModification = "Compatible with Modification"
    case notRecommended = "Not Recommended"

    var pkStatus: PKStatus {
        switch self {
        case .compatible: return .ready
        case .withModification: return .attention
        case .notRecommended: return .error
        }
    }
}

struct CompatibilityResult {
    let level: CompatibilityLevel
    let reasons: [String]
}

/// Printer ↔ material compatibility matrix logic.
enum CompatibilityEngine {

    static func evaluate(printer: PrinterDevice, material: FilamentMaterial) -> CompatibilityResult {
        var blockers: [String] = []
        var modifications: [String] = []
        var positives: [String] = []

        // Hotend temperature
        if printer.maxHotendTempC >= Double(material.nozzleMax) {
            positives.append("Hotend covers \(material.nozzleRangeText)")
        } else if printer.maxHotendTempC >= Double(material.nozzleMin) {
            modifications.append("Hotend tops out at \(Int(printer.maxHotendTempC)) °C — print at the low end of \(material.nozzleRangeText), slower")
        } else {
            blockers.append("Needs ≥ \(material.nozzleMin) °C hotend; printer maxes at \(Int(printer.maxHotendTempC)) °C")
        }

        // Bed temperature
        if material.bedMax > 0 {
            if printer.maxBedTempC >= Double(material.bedMax) {
                positives.append("Bed covers \(material.bedRangeText)")
            } else if printer.maxBedTempC >= Double(material.bedMin) {
                modifications.append("Bed maxes at \(Int(printer.maxBedTempC)) °C; adhesion promoter recommended")
            } else {
                blockers.append("Needs \(material.bedRangeText) bed; printer reaches \(Int(printer.maxBedTempC)) °C")
            }
        }

        // Chamber / enclosure
        switch material.chamber {
        case .required where !printer.hasEnclosure && !printer.hasHeatedChamber:
            blockers.append("Requires enclosure or heated chamber")
        case .recommended where !printer.hasEnclosure:
            modifications.append("Enclosure recommended — add one or accept warping")
        default:
            positives.append("Chamber: \(material.chamber.displayName.lowercased())")
        }

        // Nozzle / abrasiveness
        if material.hardenedNozzleRequired {
            if let nozzle = printer.currentNozzle {
                if nozzle.material.abrasiveSafe {
                    positives.append("\(nozzle.material.displayName) nozzle handles abrasives")
                } else {
                    modifications.append("Swap \(nozzle.material.displayName.lowercased()) nozzle for hardened steel / carbide")
                }
            } else {
                modifications.append("Abrasive — install a hardened nozzle")
            }
        }

        // Extrusion path for flexibles
        if material.flexibility >= 4 {
            switch printer.extruder {
            case .bowden:
                modifications.append("Flexible filament in a Bowden system — print slowly (15–25 mm/s), minimal retraction")
            case .direct:
                positives.append("Direct drive handles flexibles")
            }
            if printer.multiMaterial != .none {
                modifications.append("Flexibles frequently jam AMS/MMU feed paths — load externally")
            }
        }

        // Filament diameter
        if abs(printer.filamentDiameter - 1.75) > 0.01 {
            modifications.append("Confirm the spool is \(String(format: "%.2f", printer.filamentDiameter)) mm")
        }

        if !blockers.isEmpty {
            return CompatibilityResult(level: .notRecommended, reasons: blockers + modifications)
        }
        if !modifications.isEmpty {
            return CompatibilityResult(level: .withModification, reasons: modifications + positives)
        }
        return CompatibilityResult(level: .compatible, reasons: positives)
    }
}
