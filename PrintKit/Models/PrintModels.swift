import Foundation
import SwiftData

enum PrintOutcomeCategory: String, Codable, CaseIterable, Identifiable {
    case finalPart = "Final Part"
    case prototype = "Prototype"
    case supports = "Supports"
    case purge = "Purge"
    case failedPrint = "Failed Print"
    case calibration = "Calibration"
    case scrap = "Scrap"

    var id: String { rawValue }

    /// Waste categories count against true material efficiency.
    var isWaste: Bool {
        switch self {
        case .purge, .failedPrint, .scrap: return true
        case .finalPart, .prototype, .supports, .calibration: return false
        }
    }
}

@Model
final class PrintRecord {
    var id: UUID = UUID()
    var name: String = ""
    var printer: PrinterDevice?
    var spool: Spool?
    var materialID: String = ""
    var profile: SlicerProfile?
    var project: ProjectItem?
    var date: Date = Date()
    var durationMinutes: Double = 0
    var gramsUsed: Double = 0
    var success: Bool = true
    var categoryRaw: String = PrintOutcomeCategory.finalPart.rawValue
    var failureCategory: String = ""
    var cost: Double = 0
    var notes: String = ""
    var photoDatas: [Data] = []

    init() {}

    var category: PrintOutcomeCategory {
        get { PrintOutcomeCategory(rawValue: categoryRaw) ?? .finalPart }
        set { categoryRaw = newValue.rawValue }
    }
}

// MARK: - Projects

enum ProjectStatus: String, Codable, CaseIterable, Identifiable {
    case planned, inProgress, completed, archived
    var id: String { rawValue }
    var displayName: String { rawValue.camelCasedToWords().capitalized }
}

enum BOMCategory: String, Codable, CaseIterable, Identifiable {
    case printedPart, filament, screw, nut, bearing, magnet, insert, electronics, adhesive, hardware, other
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .printedPart: return "Printed Part"
        case .filament: return "Filament"
        case .screw: return "Screw"
        case .nut: return "Nut"
        case .bearing: return "Bearing"
        case .magnet: return "Magnet"
        case .insert: return "Heat-Set Insert"
        case .electronics: return "Electronics"
        case .adhesive: return "Adhesive"
        case .hardware: return "Purchased Hardware"
        case .other: return "Other"
        }
    }
}

@Model
final class ProjectItem {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    var statusRaw: String = ProjectStatus.planned.rawValue
    var createdAt: Date = Date()
    var completedAt: Date?
    var printer: PrinterDevice?
    var profile: SlicerProfile?
    var photoDatas: [Data] = []

    @Relationship(inverse: \BOMItem.project) var bomItems: [BOMItem]? = []
    @Relationship(inverse: \PrintRecord.project) var prints: [PrintRecord]? = []

    init() {}

    var status: ProjectStatus {
        get { ProjectStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }

    var totalCost: Double {
        let bom = (bomItems ?? []).reduce(0) { $0 + $1.totalCost }
        let printsCost = (prints ?? []).reduce(0) { $0 + $1.cost }
        return bom + printsCost
    }
}

@Model
final class BOMItem {
    var id: UUID = UUID()
    var project: ProjectItem?
    var name: String = ""
    var categoryRaw: String = BOMCategory.other.rawValue
    var quantity: Double = 1
    var unitCost: Double = 0
    var grams: Double = 0          // for printed parts / filament
    var spool: Spool?
    var isPrinted: Bool = false

    init() {}

    var category: BOMCategory {
        get { BOMCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var totalCost: Double { quantity * unitCost }
}

@Model
final class PrintQueueItem {
    var id: UUID = UUID()
    var name: String = ""
    var project: ProjectItem?
    var printer: PrinterDevice?
    var spool: Spool?
    var estimatedMinutes: Double = 0
    var gramsRequired: Double = 0
    var priority: Int = 0
    var isDone: Bool = false
    var notes: String = ""

    init() {}
}

// MARK: - Failure journal

@Model
final class FailureReport {
    var id: UUID = UUID()
    var printer: PrinterDevice?
    var spool: Spool?
    var profile: SlicerProfile?
    var date: Date = Date()
    var category: String = ""
    var suspectedCause: String = ""
    var attemptedFix: String = ""
    var finalSolution: String = ""
    var settingsSummary: String = ""   // temps / speeds snapshot, e.g. "242 °C · 0.4 nozzle · 80 mm/s"
    var notes: String = ""
    @Attribute(.externalStorage) var beforePhoto: Data?
    @Attribute(.externalStorage) var afterPhoto: Data?

    init() {}
}

// MARK: - Slicer profiles

@Model
final class SlicerProfile {
    var id: UUID = UUID()
    var name: String = ""
    var printer: PrinterDevice?
    var plate: BuildPlate?
    var nozzleDiameter: Double = 0.4
    var materialID: String = "pla"
    var filamentProduct: String = ""
    var layerHeight: Double = 0.2
    var lineWidth: Double = 0.42
    var nozzleTemp: Double = 210
    var bedTemp: Double = 60
    var chamberTemp: Double = 0
    var printSpeed: Double = 50
    var wallSpeed: Double = 0
    var infillSpeed: Double = 0
    var volumetricLimit: Double = 0
    var acceleration: Double = 0
    var retractionMm: Double = 0.8
    var fanPercent: Double = 100
    var flowRatio: Double = 1.0
    var pressureAdvance: Double = 0
    var usesSupports: Bool = false
    var bedSurface: String = ""
    var adhesive: String = ""
    var isKnownGood: Bool = false
    var isFavorite: Bool = false
    var successCount: Int = 0
    var failureCount: Int = 0
    var lastUsed: Date?
    var notes: String = ""

    init() {}

    var recordedSuccessRate: Double? {
        let total = successCount + failureCount
        guard total > 0 else { return nil }
        return Double(successCount) / Double(total)
    }
}

// MARK: - Calibration & dimensional

@Model
final class CalibrationRecord {
    var id: UUID = UUID()
    var typeKey: String = ""        // CalibrationGuide.id
    var printer: PrinterDevice?
    var materialID: String = ""
    var nozzleDiameter: Double = 0
    var profile: SlicerProfile?
    var date: Date = Date()
    var numericResult: Double?
    var resultSummary: String = ""
    var notes: String = ""

    init() {}
}

enum FitCategory: String, Codable, CaseIterable, Identifiable {
    case slipFit, snugFit, pressFit, interferenceFit, bearingFit, nutTrap, snapFit, slidingFit, hinge, thread
    var id: String { rawValue }

    var displayName: String {
        rawValue.camelCasedToWords().capitalized
    }
}

enum PartOrientation: String, Codable, CaseIterable, Identifiable {
    case horizontal, vertical, angled
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

@Model
final class ToleranceEntry {
    var id: UUID = UUID()
    var categoryRaw: String = FitCategory.snugFit.rawValue
    var clearanceMm: Double = 0.2
    var printer: PrinterDevice?
    var materialID: String = ""
    var nozzleDiameter: Double = 0.4
    var layerHeight: Double = 0.2
    var orientationRaw: String = PartOrientation.horizontal.rawValue
    var notes: String = ""
    var date: Date = Date()

    init() {}

    var category: FitCategory {
        get { FitCategory(rawValue: categoryRaw) ?? .snugFit }
        set { categoryRaw = newValue.rawValue }
    }

    var orientation: PartOrientation {
        get { PartOrientation(rawValue: orientationRaw) ?? .horizontal }
        set { orientationRaw = newValue.rawValue }
    }
}

@Model
final class FlowLimitRecord {
    var id: UUID = UUID()
    var printer: PrinterDevice?
    var hotendName: String = ""
    var nozzleDiameter: Double = 0.4
    var materialID: String = ""
    var maxFlowMm3s: Double = 0
    var date: Date = Date()
    var notes: String = ""

    init() {}
}

/// User overrides for reference material defaults. Personal data never
/// overwrites the reference library; it is applied on top at read time.
@Model
final class MaterialOverride {
    var id: UUID = UUID()
    var materialID: String = ""
    var nozzleMin: Int?
    var nozzleMax: Int?
    var bedMin: Int?
    var bedMax: Int?
    var dryTemp: Int?
    var dryHours: Int?
    var notes: String = ""

    init() {}
}

// MARK: - String helper

extension String {
    func camelCasedToWords() -> String {
        unicodeScalars.reduce(into: "") { result, scalar in
            if CharacterSet.uppercaseLetters.contains(scalar), !result.isEmpty {
                result.append(" ")
            }
            result.append(Character(scalar))
        }
    }
}
