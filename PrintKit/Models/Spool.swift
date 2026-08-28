import Foundation
import SwiftData
import SwiftUI

enum SpoolFinish: String, Codable, CaseIterable, Identifiable {
    case standard, matte, gloss, silk, metallic, transparent, translucent, marble, wood, glitter, glow, carbonFiber = "carbon-fiber"
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .matte: return "Matte"
        case .gloss: return "Gloss"
        case .silk: return "Silk"
        case .metallic: return "Metallic"
        case .transparent: return "Transparent"
        case .translucent: return "Translucent"
        case .marble: return "Marble"
        case .wood: return "Wood"
        case .glitter: return "Glitter"
        case .glow: return "Glow"
        case .carbonFiber: return "Carbon-Fiber Look"
        }
    }
}

enum SpoolStatus: String, CaseIterable {
    case ready = "Ready"
    case needsDrying = "Needs Drying"
    case drying = "Drying"
    case low = "Low"
    case empty = "Empty"
    case archived = "Archived"
    case unknown = "Unknown"

    var status: PKStatus {
        switch self {
        case .ready: return .ready
        case .needsDrying: return .attention
        case .drying: return .info
        case .low: return .attention
        case .empty: return .error
        case .archived, .unknown: return .inactive
        }
    }
}

@Model
final class Spool {
    var id: UUID = UUID()
    var manufacturer: String = ""
    var productLine: String = ""
    var materialID: String = "pla"
    var colorName: String = ""
    var colorHex: String = "#808080"
    var finishRaw: String = SpoolFinish.standard.rawValue
    var diameter: Double = 1.75
    var originalNetWeightG: Double = 1000
    var currentWeightG: Double = 1000
    var emptySpoolWeightG: Double = 140
    var cost: Double = 0
    var vendor: String = ""
    var purchaseDate: Date?
    var openedDate: Date?
    var lastUsedDate: Date?
    var lastDriedDate: Date?
    var lotNumber: String = ""
    var batchNumber: String = ""
    var lotFlagged: Bool = false
    var lotNotes: String = ""
    var notes: String = ""
    @Attribute(.externalStorage) var photoDatas: [Data] = []
    var nfcTagWritten: Bool = false
    var isFavorite: Bool = false
    var isArchived: Bool = false
    var storageLocation: StorageLocation?
    var amsSlotLabel: String = ""     // e.g. "AMS 1 · Slot A2" (manual)
    var personalProfileNotes: String = ""

    init() {}

    var finish: SpoolFinish {
        get { SpoolFinish(rawValue: finishRaw) ?? .standard }
        set { finishRaw = newValue.rawValue }
    }

    var displayName: String {
        let brand = manufacturer.isEmpty ? "" : manufacturer + " "
        let product = productLine.isEmpty ? materialID.uppercased() : productLine
        return colorName.isEmpty ? "\(brand)\(product)" : "\(brand)\(product) · \(colorName)"
    }

    var color: Color { Color(hex: colorHex) ?? .gray }

    var remainingFraction: Double {
        guard originalNetWeightG > 0 else { return 0 }
        return min(max(currentWeightG / originalNetWeightG, 0), 1)
    }

    var remainingPercent: Double { remainingFraction * 100 }

    var costPerKg: Double? {
        guard originalNetWeightG > 0, cost > 0 else { return nil }
        return cost / (originalNetWeightG / 1000)
    }

    func estimatedLengthMeters(density: Double) -> Double {
        FilamentMath.gramsToMeters(currentWeightG, diameterMM: diameter, densityGcm3: density)
    }

    func status(lowThresholdG: Double = AppSettings.shared.lowSpoolThresholdGrams,
                dryingActive: Bool = false) -> SpoolStatus {
        if isArchived { return .archived }
        if dryingActive { return .drying }
        if currentWeightG <= 0.5 { return .empty }
        if needsDrying { return .needsDrying }
        if currentWeightG <= lowThresholdG { return .low }
        return .ready
    }

    /// Heuristic: materials rated 4+ hygroscopic that were dried more than
    /// 21 days ago (or never dried after opening) are flagged for drying.
    var needsDrying: Bool {
        guard let material = MaterialLibrary.shared.material(for: materialID) else { return false }
        guard material.hygroscopic >= 4 else { return false }
        guard let reference = lastDriedDate ?? openedDate else { return false }
        return Date().timeIntervalSince(reference) > 21 * 24 * 3600
    }
}

// MARK: - Drying

@Model
final class DryingSession {
    var id: UUID = UUID()
    var spool: Spool?
    var materialID: String = ""
    var dryerName: String = ""
    var targetTempC: Double = 0
    var plannedMinutes: Double = 360
    var startedAt: Date = Date()
    var completedAt: Date?
    var notes: String = ""

    init() {}

    var isActive: Bool { completedAt == nil }
    var plannedEnd: Date { startedAt.addingTimeInterval(plannedMinutes * 60) }
    var remainingInterval: TimeInterval { plannedEnd.timeIntervalSince(Date()) }

    var actualMinutes: Double? {
        guard let completedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt) / 60
    }
}

// MARK: - Storage

enum StorageKind: String, Codable, CaseIterable, Identifiable {
    case dryer, ams, dryBox, cabinet, bin, shelf, vacuumBag, other
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dryer: return "Dryer"
        case .ams: return "AMS / MMU"
        case .dryBox: return "Dry Box"
        case .cabinet: return "Cabinet"
        case .bin: return "Bin"
        case .shelf: return "Shelf"
        case .vacuumBag: return "Vacuum Bag"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .dryer: return "humidity"
        case .ams: return "square.grid.2x2"
        case .dryBox: return "shippingbox"
        case .cabinet: return "cabinet"
        case .bin: return "archivebox"
        case .shelf: return "books.vertical"
        case .vacuumBag: return "bag"
        case .other: return "square.dashed"
        }
    }
}

@Model
final class StorageLocation {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = StorageKind.other.rawValue
    var notes: String = ""
    @Relationship(inverse: \Spool.storageLocation) var spools: [Spool]? = []

    init() {}

    var kind: StorageKind {
        get { StorageKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class FilamentTransfer {
    var id: UUID = UUID()
    var sourceSpool: Spool?
    var destinationSpool: Spool?
    var grams: Double = 0
    var date: Date = Date()
    var notes: String = ""

    init() {}
}

// MARK: - Desiccant

@Model
final class DesiccantUnit {
    var id: UUID = UUID()
    var containerName: String = ""
    var desiccantType: String = "Silica gel"
    var lastRegenerated: Date?
    var lastReplaced: Date?
    var humidityPercent: Double?
    var remindEveryDays: Int = 30
    var notes: String = ""

    init() {}

    var daysSinceRegenerated: Int? {
        guard let lastRegenerated else { return nil }
        return Int(Date().timeIntervalSince(lastRegenerated) / 86400)
    }

    var regenerationDue: Bool {
        guard let days = daysSinceRegenerated else { return true }
        return days >= remindEveryDays
    }
}

// MARK: - Environment logging (manual now; Bluetooth sensors later)

@Model
final class EnvironmentLog {
    var id: UUID = UUID()
    var location: StorageLocation?
    var temperatureC: Double = 0
    var humidityPercent: Double = 0
    var date: Date = Date()
    var notes: String = ""

    init() {}
}

// MARK: - Wishlist / purchases

@Model
final class WishlistItem {
    var id: UUID = UUID()
    var manufacturer: String = ""
    var product: String = ""
    var materialID: String = ""
    var colorName: String = ""
    var targetPrice: Double?
    var projectIdea: String = ""
    var createdAt: Date = Date()

    init() {}
}

@Model
final class PurchaseRecord {
    var id: UUID = UUID()
    var spool: Spool?
    var vendor: String = ""
    var price: Double = 0
    var shipping: Double = 0
    var quantity: Int = 1
    var date: Date = Date()
    var notes: String = ""

    init() {}
}
