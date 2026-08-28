import Foundation

enum ReadinessStatus: String {
    case passed, warning, failed

    var pkStatus: PKStatus {
        switch self {
        case .passed: return .ready
        case .warning: return .attention
        case .failed: return .error
        }
    }
}

struct ReadinessCheck: Identifiable {
    let id = UUID()
    let title: String
    let status: ReadinessStatus
    let detail: String
}

struct ReadinessResult {
    let checks: [ReadinessCheck]

    var isReady: Bool { !checks.contains { $0.status == .failed } }
    var failedCount: Int { checks.filter { $0.status == .failed }.count }
    var warningCount: Int { checks.filter { $0.status == .warning }.count }

    var headline: String {
        if isReady && warningCount == 0 { return "Ready to Print" }
        if isReady { return "Ready with \(warningCount) warning\(warningCount == 1 ? "" : "s")" }
        return "Attention Required"
    }
}

/// Evaluates whether a printer + spool + profile + plate + nozzle combination
/// is ready for an intended print. All checks explain themselves.
enum ReadinessEngine {

    struct Context {
        var printer: PrinterDevice?
        var spool: Spool?
        var profile: SlicerProfile?
        var plate: BuildPlate?
        var nozzle: NozzleRecord?
        var requiredGrams: Double = 0
        var reservePercent: Double = AppSettings.shared.reservePercent
        var dryingActive: Bool = false
        var maintenanceDueCount: Int = 0
        var usesAMS: Bool = false
        var supportMaterialID: String? = nil
    }

    static func evaluate(_ ctx: Context) -> ReadinessResult {
        var checks: [ReadinessCheck] = []
        let material = ctx.spool.flatMap { MaterialLibrary.shared.material(for: $0.materialID) }

        // 1. Enough filament
        if let spool = ctx.spool {
            if ctx.requiredGrams > 0 {
                let reserve = spool.originalNetWeightG * ctx.reservePercent / 100
                let usable = spool.currentWeightG - reserve
                if usable >= ctx.requiredGrams {
                    checks.append(.init(title: "Enough Filament", status: .passed,
                        detail: "\(Format.grams(spool.currentWeightG)) available, \(Format.grams(ctx.requiredGrams)) required, \(Format.grams(reserve)) reserve kept."))
                } else {
                    checks.append(.init(title: "Enough Filament", status: .failed,
                        detail: "Requires \(Format.grams(ctx.requiredGrams)) but only \(Format.grams(max(usable, 0))) usable after reserve. Assign another spool or reduce the job."))
                }
            } else {
                checks.append(.init(title: "Enough Filament", status: spool.currentWeightG > 0 ? .passed : .failed,
                    detail: spool.currentWeightG > 0
                        ? "\(Format.grams(spool.currentWeightG)) on spool; no job estimate entered."
                        : "Spool is empty."))
            }
        } else {
            checks.append(.init(title: "Filament Spool", status: .failed, detail: "No spool selected."))
        }

        // 2. Filament moisture / drying
        if let spool = ctx.spool, let material {
            if ctx.dryingActive {
                checks.append(.init(title: "Filament Dry", status: .warning,
                    detail: "This spool is currently in an active drying session."))
            } else if spool.needsDrying {
                checks.append(.init(title: "Filament Dry", status: .warning,
                    detail: "\(material.name) is moisture-sensitive and was last dried \(Format.date(spool.lastDriedDate ?? spool.openedDate)). Dry at \(material.dryTemp) °C for about \(material.dryHours)h (reference guidance — follow the manufacturer's instructions when available)."))
            } else {
                checks.append(.init(title: "Filament Dry", status: .passed,
                    detail: material.hygroscopic >= 4
                        ? "Dried \(Format.date(spool.lastDriedDate ?? spool.openedDate)); within the typical window for \(material.name)."
                        : "\(material.name) has low moisture sensitivity."))
            }
        }

        // 3–5. Temperature capabilities
        if let printer = ctx.printer, let material {
            if printer.maxHotendTempC >= Double(material.nozzleMax) {
                checks.append(.init(title: "Hotend Temperature", status: .passed,
                    detail: "Printer reaches \(Int(printer.maxHotendTempC)) °C; \(material.name) needs \(material.nozzleRangeText)."))
            } else if printer.maxHotendTempC >= Double(material.nozzleMin) {
                checks.append(.init(title: "Hotend Temperature", status: .warning,
                    detail: "Printer tops out at \(Int(printer.maxHotendTempC)) °C, inside but near the bottom of \(material.name)'s \(material.nozzleRangeText) range."))
            } else {
                checks.append(.init(title: "Hotend Temperature", status: .failed,
                    detail: "\(material.name) needs at least \(material.nozzleMin) °C; this hotend is limited to \(Int(printer.maxHotendTempC)) °C."))
            }

            if material.bedMax > 0 {
                if printer.maxBedTempC >= Double(material.bedMax) {
                    checks.append(.init(title: "Bed Temperature", status: .passed,
                        detail: "Bed reaches \(Int(printer.maxBedTempC)) °C; \(material.name) wants \(material.bedRangeText)."))
                } else if printer.maxBedTempC >= Double(material.bedMin) {
                    checks.append(.init(title: "Bed Temperature", status: .warning,
                        detail: "Bed limited to \(Int(printer.maxBedTempC)) °C; upper end of \(material.name)'s range is \(material.bedMax) °C."))
                } else {
                    checks.append(.init(title: "Bed Temperature", status: .failed,
                        detail: "\(material.name) needs a \(material.bedRangeText) bed; this printer reaches \(Int(printer.maxBedTempC)) °C."))
                }
            }

            // 6. Chamber / enclosure
            switch material.chamber {
            case .required where !printer.hasHeatedChamber && !printer.hasEnclosure:
                checks.append(.init(title: "Chamber / Enclosure", status: .failed,
                    detail: "\(material.name) generally requires an enclosed or heated chamber; this printer has neither."))
            case .required:
                checks.append(.init(title: "Chamber / Enclosure", status: .passed,
                    detail: "Enclosure available for \(material.name)."))
            case .recommended where !printer.hasEnclosure:
                checks.append(.init(title: "Chamber / Enclosure", status: .warning,
                    detail: "\(material.name) prints more reliably in an enclosure; expect more warping without one."))
            case .recommended:
                checks.append(.init(title: "Chamber / Enclosure", status: .passed, detail: "Enclosure available."))
            case .optional, .notRequired:
                checks.append(.init(title: "Chamber / Enclosure", status: .passed,
                    detail: "\(material.name): enclosure \(material.chamber.displayName.lowercased())."))
            }

            // 7. Filament diameter
            if let spool = ctx.spool, abs(spool.diameter - printer.filamentDiameter) > 0.01 {
                checks.append(.init(title: "Filament Diameter", status: .failed,
                    detail: "Spool is \(String(format: "%.2f", spool.diameter)) mm but this printer uses \(String(format: "%.2f", printer.filamentDiameter)) mm filament."))
            }

            // 8. AMS/MMU
            if ctx.usesAMS {
                if printer.multiMaterial == .none {
                    checks.append(.init(title: "AMS / MMU", status: .failed,
                        detail: "Job requires a multi-material unit; this printer has none configured."))
                } else if material.flexibility >= 4 {
                    checks.append(.init(title: "AMS / MMU", status: .warning,
                        detail: "\(material.name) is flexible and often jams in AMS/MMU feed paths; load externally if possible."))
                } else {
                    checks.append(.init(title: "AMS / MMU", status: .passed,
                        detail: "\(printer.multiMaterial.displayName) configured."))
                }
            }
        }

        // 9–10. Nozzle
        if let material {
            let nozzle = ctx.nozzle ?? ctx.printer?.currentNozzle
            if material.hardenedNozzleRequired {
                if let nozzle {
                    if nozzle.material.abrasiveSafe {
                        checks.append(.init(title: "Nozzle Compatibility", status: .passed,
                            detail: "\(nozzle.material.displayName) resists abrasive \(material.name)."))
                    } else {
                        checks.append(.init(title: "Nozzle Compatibility", status: .failed,
                            detail: "\(material.name) is abrasive and will quickly wear a \(nozzle.material.displayName.lowercased()) nozzle. Fit hardened steel, tungsten carbide, or ruby."))
                    }
                } else {
                    checks.append(.init(title: "Nozzle Compatibility", status: .warning,
                        detail: "\(material.name) is abrasive; no nozzle is recorded for this printer, so wear resistance can't be confirmed."))
                }
            } else if let nozzle {
                checks.append(.init(title: "Nozzle Compatibility", status: .passed,
                    detail: "\(nozzle.displayName); \(material.name) is not abrasive."))
            }
            if let nozzle, nozzle.diameter < 0.4, material.abrasive {
                checks.append(.init(title: "Nozzle Size", status: .warning,
                    detail: "Filled filaments clog more easily below 0.4 mm; consider a 0.4–0.6 mm nozzle."))
            }
        }

        // 11. Build plate
        if let plate = ctx.plate, let material {
            let plateToken = plate.plateType.rawValue.lowercased()
            let plateAliases: [PlateType: [String]] = [
                .smoothPEI: ["smooth-pei"], .texturedPEI: ["textured-pei"], .glass: ["glass"],
                .engineering: ["engineering"], .garolite: ["garolite"], .buildtakStyle: ["buildtak"], .custom: []
            ]
            let tokens = plateAliases[plate.plateType] ?? [plateToken]
            if tokens.contains(where: { material.bedSurfaces.contains($0) }) {
                checks.append(.init(title: "Build Plate", status: .passed,
                    detail: "\(plate.plateType.displayName) is a recommended surface for \(material.name). \(material.adhesion)"))
            } else {
                checks.append(.init(title: "Build Plate", status: .warning,
                    detail: "\(material.name) typically prefers \(material.bedSurfaces.joined(separator: ", ")); \(plate.plateType.displayName) may need adhesive or a surface swap. \(material.adhesion)"))
            }
        }

        // 12. Maintenance
        if ctx.maintenanceDueCount > 0 {
            checks.append(.init(title: "Maintenance", status: .warning,
                detail: "\(ctx.maintenanceDueCount) maintenance task\(ctx.maintenanceDueCount == 1 ? " is" : "s are") due on this printer."))
        } else if ctx.printer != nil {
            checks.append(.init(title: "Maintenance", status: .passed, detail: "No maintenance currently due."))
        }

        // 13. Known-good profile
        if let profile = ctx.profile {
            if profile.isKnownGood {
                let rate = profile.recordedSuccessRate.map { String(format: " · %.0f%% recorded success", $0 * 100) } ?? ""
                checks.append(.init(title: "Known-Good Profile", status: .passed,
                    detail: "“\(profile.name)” is marked Known Good\(rate)."))
            } else {
                checks.append(.init(title: "Known-Good Profile", status: .warning,
                    detail: "“\(profile.name)” is not marked Known Good yet."))
            }
        } else {
            checks.append(.init(title: "Known-Good Profile", status: .warning,
                detail: "No slicer profile selected; results depend on unverified settings."))
        }

        // 14. Support material compatibility
        if let supportID = ctx.supportMaterialID, let material {
            if material.supportMaterials.contains(supportID) {
                checks.append(.init(title: "Support Material", status: .passed,
                    detail: "\(supportID.uppercased()) is listed as compatible support for \(material.name)."))
            } else {
                checks.append(.init(title: "Support Material", status: .warning,
                    detail: "\(supportID.uppercased()) is not a listed support pairing for \(material.name) (typical: \(material.supportMaterials.joined(separator: ", ")))."))
            }
        }

        return ReadinessResult(checks: checks)
    }
}
