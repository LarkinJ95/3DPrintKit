import Foundation
import SwiftData

enum ExtruderType: String, Codable, CaseIterable, Identifiable {
    case direct, bowden
    var id: String { rawValue }
    var displayName: String { self == .direct ? "Direct Drive" : "Bowden" }
}

enum MultiMaterialSystem: String, Codable, CaseIterable, Identifiable {
    case none, bambuAMS, bambuAMSLite, prusaMMU, generic
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .bambuAMS: return "Bambu AMS"
        case .bambuAMSLite: return "Bambu AMS Lite"
        case .prusaMMU: return "Prusa MMU"
        case .generic: return "Generic Multi-Material"
        }
    }
}

enum NozzleMaterial: String, Codable, CaseIterable, Identifiable {
    case brass, hardenedSteel, stainlessSteel, tungstenCarbide, ruby, highFlow
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .brass: return "Brass"
        case .hardenedSteel: return "Hardened Steel"
        case .stainlessSteel: return "Stainless Steel"
        case .tungstenCarbide: return "Tungsten Carbide"
        case .ruby: return "Ruby Tip"
        case .highFlow: return "High-Flow"
        }
    }

    /// True when the nozzle resists abrasive filaments (CF/GF/metal/glow).
    var abrasiveSafe: Bool {
        switch self {
        case .hardenedSteel, .tungstenCarbide, .ruby: return true
        case .brass, .stainlessSteel, .highFlow: return false
        }
    }
}

enum PlateType: String, Codable, CaseIterable, Identifiable {
    case smoothPEI, texturedPEI, glass, engineering, garolite, buildtakStyle, custom
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smoothPEI: return "Smooth PEI"
        case .texturedPEI: return "Textured PEI"
        case .glass: return "Glass"
        case .engineering: return "Engineering Surface"
        case .garolite: return "Garolite / G10"
        case .buildtakStyle: return "BuildTak-Style"
        case .custom: return "Custom"
        }
    }
}

enum PlateCondition: String, Codable, CaseIterable, Identifiable {
    case excellent, good, worn, replace
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

@Model
final class PrinterDevice {
    var id: UUID = UUID()
    var manufacturer: String = ""
    var model: String = ""
    var customName: String = ""
    var serialNumber: String = ""
    var firmware: String = ""
    var buildVolumeX: Double = 220
    var buildVolumeY: Double = 220
    var buildVolumeZ: Double = 250
    var maxHotendTempC: Double = 260
    var maxBedTempC: Double = 100
    var hasHeatedChamber: Bool = false
    var maxChamberTempC: Double = 0
    var extruderRaw: String = ExtruderType.direct.rawValue
    var filamentDiameter: Double = 1.75
    var hasEnclosure: Bool = false
    var amsRaw: String = MultiMaterialSystem.none.rawValue
    var amsSlotCount: Int = 0
    var notes: String = ""
    var photoData: Data?
    var totalPrintHours: Double = 0

    @Relationship(inverse: \NozzleRecord.printer) var nozzles: [NozzleRecord]? = []
    @Relationship(inverse: \BuildPlate.printer) var plates: [BuildPlate]? = []
    @Relationship(inverse: \MaintenanceTask.printer) var maintenanceTasks: [MaintenanceTask]? = []

    init() {}

    var displayName: String {
        if !customName.isEmpty { return customName }
        return [manufacturer, model].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var extruder: ExtruderType {
        get { ExtruderType(rawValue: extruderRaw) ?? .direct }
        set { extruderRaw = newValue.rawValue }
    }

    var multiMaterial: MultiMaterialSystem {
        get { MultiMaterialSystem(rawValue: amsRaw) ?? .none }
        set { amsRaw = newValue.rawValue }
    }

    var currentNozzle: NozzleRecord? {
        nozzles?.first(where: { $0.isInstalled })
    }
}

@Model
final class NozzleRecord {
    var id: UUID = UUID()
    var printer: PrinterDevice?
    var diameter: Double = 0.4
    var materialRaw: String = NozzleMaterial.brass.rawValue
    var brand: String = ""
    var installedDate: Date?
    var printHours: Double = 0
    var abrasiveHours: Double = 0
    var isInstalled: Bool = false
    var inspectionNotes: String = ""

    init() {}

    var material: NozzleMaterial {
        get { NozzleMaterial(rawValue: materialRaw) ?? .brass }
        set { materialRaw = newValue.rawValue }
    }

    var displayName: String {
        String(format: "%.2g mm %@", diameter, material.displayName)
    }
}

@Model
final class BuildPlate {
    var id: UUID = UUID()
    var printer: PrinterDevice?
    var typeRaw: String = PlateType.texturedPEI.rawValue
    var manufacturer: String = ""
    var surface: String = ""
    var purchaseDate: Date?
    var usageHours: Double = 0
    var conditionRaw: String = PlateCondition.good.rawValue
    var lastCleaned: Date?
    /// Material IDs this plate is known to work well with (personal record).
    var compatibleMaterialIDs: [String] = []
    var notes: String = ""

    init() {}

    var plateType: PlateType {
        get { PlateType(rawValue: typeRaw) ?? .texturedPEI }
        set { typeRaw = newValue.rawValue }
    }

    var condition: PlateCondition {
        get { PlateCondition(rawValue: conditionRaw) ?? .good }
        set { conditionRaw = newValue.rawValue }
    }

    var displayName: String {
        manufacturer.isEmpty ? plateType.displayName : "\(manufacturer) \(plateType.displayName)"
    }
}

// MARK: - Accessories

enum AccessoryCategory: String, Codable, CaseIterable, Identifiable {
    case nozzle, hotend, heater, thermistor, ptfe, belt, extruderGear, buildPlate,
         adhesive, grease, filter, desiccant, fan, sensor, other
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nozzle: return "Nozzle"
        case .hotend: return "Hotend"
        case .heater: return "Heater"
        case .thermistor: return "Thermistor"
        case .ptfe: return "PTFE Tubing"
        case .belt: return "Belt"
        case .extruderGear: return "Extruder Gear"
        case .buildPlate: return "Build Plate"
        case .adhesive: return "Adhesive"
        case .grease: return "Grease"
        case .filter: return "Filter"
        case .desiccant: return "Desiccant"
        case .fan: return "Fan"
        case .sensor: return "Sensor"
        case .other: return "Other"
        }
    }
}

@Model
final class AccessoryItem {
    var id: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = AccessoryCategory.other.rawValue
    var quantity: Int = 1
    var minimumStock: Int = 0
    var location: String = ""
    var notes: String = ""

    init() {}

    var category: AccessoryCategory {
        get { AccessoryCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var needsReorder: Bool { quantity <= minimumStock }
}

// MARK: - Maintenance

@Model
final class MaintenanceTask {
    var id: UUID = UUID()
    var printer: PrinterDevice?
    var title: String = ""
    var intervalDays: Int = 0        // 0 = not calendar-scheduled
    var intervalPrintHours: Double = 0 // 0 = not hour-scheduled
    var lastCompleted: Date?
    var hoursAtLastCompletion: Double = 0
    var notes: String = ""

    init() {}

    func isDue(printerHours: Double) -> Bool {
        if intervalDays > 0 {
            guard let lastCompleted else { return true }
            if Date().timeIntervalSince(lastCompleted) > Double(intervalDays) * 86400 { return true }
        }
        if intervalPrintHours > 0 {
            if printerHours - hoursAtLastCompletion >= intervalPrintHours { return true }
        }
        return false
    }

    func dueDescription(printerHours: Double) -> String {
        var reasons: [String] = []
        if intervalDays > 0 {
            if let lastCompleted {
                let days = Int(Date().timeIntervalSince(lastCompleted) / 86400)
                reasons.append("\(days)d since last (every \(intervalDays)d)")
            } else {
                reasons.append("Never completed (every \(intervalDays)d)")
            }
        }
        if intervalPrintHours > 0 {
            let hours = printerHours - hoursAtLastCompletion
            reasons.append(String(format: "%.0fh of %0.fh interval used", hours, intervalPrintHours))
        }
        return reasons.joined(separator: " · ")
    }
}

@Model
final class MaintenanceLog {
    var id: UUID = UUID()
    var printer: PrinterDevice?
    var task: MaintenanceTask?
    var title: String = ""
    var date: Date = Date()
    var printerHoursAtService: Double = 0
    var notes: String = ""

    init() {}
}
