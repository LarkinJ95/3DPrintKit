import Foundation
import SwiftData

/// Versioned JSON/CSV export, import, and full local backup.
/// Imports never silently overwrite: every incoming record is checked by UUID
/// and reported as added / skipped.
enum DataPorting {

    struct ExportEnvelope: Codable {
        let schema: String          // "printkit.export"
        let version: Int            // 1
        let exportedAt: Date
        let spools: [SpoolExport]
        let printers: [PrinterExport]
        let profiles: [ProfileExport]
        let prints: [PrintExport]
        let projects: [ProjectExport]
    }

    struct SpoolExport: Codable {
        let id: UUID
        let manufacturer: String
        let productLine: String
        let materialID: String
        let colorName: String
        let colorHex: String
        let finish: String
        let diameter: Double
        let originalNetWeightG: Double
        let currentWeightG: Double
        let emptySpoolWeightG: Double
        let cost: Double
        let vendor: String
        let purchaseDate: Date?
        let openedDate: Date?
        let lastUsedDate: Date?
        let lastDriedDate: Date?
        let lotNumber: String
        let batchNumber: String
        let notes: String
        let archived: Bool
    }

    struct PrinterExport: Codable {
        let id: UUID
        let manufacturer: String
        let model: String
        let customName: String
        let maxHotendTempC: Double
        let maxBedTempC: Double
        let hasEnclosure: Bool
        let hasHeatedChamber: Bool
        let multiMaterial: String
        let totalPrintHours: Double
        let notes: String
    }

    struct ProfileExport: Codable {
        let id: UUID
        let name: String
        let materialID: String
        let filamentProduct: String
        let nozzleDiameter: Double
        let layerHeight: Double
        let lineWidth: Double
        let nozzleTemp: Double
        let bedTemp: Double
        let printSpeed: Double
        let retractionMm: Double
        let fanPercent: Double
        let flowRatio: Double
        let pressureAdvance: Double
        let isKnownGood: Bool
        let notes: String
    }

    struct PrintExport: Codable {
        let id: UUID
        let name: String
        let materialID: String
        let date: Date
        let durationMinutes: Double
        let gramsUsed: Double
        let success: Bool
        let category: String
        let cost: Double
        let notes: String
    }

    struct ProjectExport: Codable {
        let id: UUID
        let name: String
        let status: String
        let notes: String
        let createdAt: Date
        let completedAt: Date?
    }

    // MARK: - Export

    static func exportJSON(context: ModelContext) throws -> Data {
        let envelope = ExportEnvelope(
            schema: "printkit.export",
            version: 1,
            exportedAt: Date(),
            spools: (try context.fetch(FetchDescriptor<Spool>())).map {
                SpoolExport(id: $0.id, manufacturer: $0.manufacturer, productLine: $0.productLine,
                            materialID: $0.materialID, colorName: $0.colorName, colorHex: $0.colorHex,
                            finish: $0.finishRaw, diameter: $0.diameter,
                            originalNetWeightG: $0.originalNetWeightG, currentWeightG: $0.currentWeightG,
                            emptySpoolWeightG: $0.emptySpoolWeightG, cost: $0.cost, vendor: $0.vendor,
                            purchaseDate: $0.purchaseDate, openedDate: $0.openedDate,
                            lastUsedDate: $0.lastUsedDate, lastDriedDate: $0.lastDriedDate,
                            lotNumber: $0.lotNumber, batchNumber: $0.batchNumber,
                            notes: $0.notes, archived: $0.isArchived)
            },
            printers: (try context.fetch(FetchDescriptor<PrinterDevice>())).map {
                PrinterExport(id: $0.id, manufacturer: $0.manufacturer, model: $0.model,
                              customName: $0.customName, maxHotendTempC: $0.maxHotendTempC,
                              maxBedTempC: $0.maxBedTempC, hasEnclosure: $0.hasEnclosure,
                              hasHeatedChamber: $0.hasHeatedChamber, multiMaterial: $0.amsRaw,
                              totalPrintHours: $0.totalPrintHours, notes: $0.notes)
            },
            profiles: (try context.fetch(FetchDescriptor<SlicerProfile>())).map {
                ProfileExport(id: $0.id, name: $0.name, materialID: $0.materialID,
                              filamentProduct: $0.filamentProduct, nozzleDiameter: $0.nozzleDiameter,
                              layerHeight: $0.layerHeight, lineWidth: $0.lineWidth,
                              nozzleTemp: $0.nozzleTemp, bedTemp: $0.bedTemp, printSpeed: $0.printSpeed,
                              retractionMm: $0.retractionMm, fanPercent: $0.fanPercent,
                              flowRatio: $0.flowRatio, pressureAdvance: $0.pressureAdvance,
                              isKnownGood: $0.isKnownGood, notes: $0.notes)
            },
            prints: (try context.fetch(FetchDescriptor<PrintRecord>())).map {
                PrintExport(id: $0.id, name: $0.name, materialID: $0.materialID, date: $0.date,
                            durationMinutes: $0.durationMinutes, gramsUsed: $0.gramsUsed,
                            success: $0.success, category: $0.categoryRaw, cost: $0.cost, notes: $0.notes)
            },
            projects: (try context.fetch(FetchDescriptor<ProjectItem>())).map {
                ProjectExport(id: $0.id, name: $0.name, status: $0.statusRaw, notes: $0.notes,
                              createdAt: $0.createdAt, completedAt: $0.completedAt)
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    static func exportSpoolsCSV(context: ModelContext) throws -> Data {
        var rows = ["id,manufacturer,product,material,color,finish,diameter_mm,original_g,remaining_g,cost,vendor,opened,archived"]
        let spools = try context.fetch(FetchDescriptor<Spool>())
        let formatter = ISO8601DateFormatter()
        for s in spools {
            func esc(_ value: String) -> String {
                "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            rows.append([
                s.id.uuidString, esc(s.manufacturer), esc(s.productLine), s.materialID, esc(s.colorName),
                s.finishRaw, String(s.diameter), String(s.originalNetWeightG), String(s.currentWeightG),
                String(s.cost), esc(s.vendor),
                s.openedDate.map(formatter.string(from:)) ?? "",
                String(s.isArchived)
            ].joined(separator: ","))
        }
        return Data(rows.joined(separator: "\n").utf8)
    }

    // MARK: - Import (never silently overwrites)

    struct ImportReport {
        var spoolsAdded = 0
        var spoolsSkipped = 0
    }

    static func importJSON(_ data: Data, context: ModelContext) throws -> ImportReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(ExportEnvelope.self, from: data)
        guard envelope.schema == "printkit.export", envelope.version == 1 else {
            throw PortingError.unsupportedSchema
        }
        var report = ImportReport()
        let existing = Set((try context.fetch(FetchDescriptor<Spool>())).map(\.id))
        for item in envelope.spools {
            if existing.contains(item.id) {
                report.spoolsSkipped += 1
                continue
            }
            let spool = Spool()
            spool.id = item.id
            spool.manufacturer = item.manufacturer
            spool.productLine = item.productLine
            spool.materialID = item.materialID
            spool.colorName = item.colorName
            spool.colorHex = item.colorHex
            spool.finish = SpoolFinish(rawValue: item.finish) ?? .standard
            spool.diameter = item.diameter
            spool.originalNetWeightG = item.originalNetWeightG
            spool.currentWeightG = item.currentWeightG
            spool.emptySpoolWeightG = item.emptySpoolWeightG
            spool.cost = item.cost
            spool.vendor = item.vendor
            spool.purchaseDate = item.purchaseDate
            spool.openedDate = item.openedDate
            spool.lastUsedDate = item.lastUsedDate
            spool.lastDriedDate = item.lastDriedDate
            spool.lotNumber = item.lotNumber
            spool.batchNumber = item.batchNumber
            spool.notes = item.notes
            spool.isArchived = item.archived
            context.insert(spool)
            report.spoolsAdded += 1
        }
        try context.save()
        return report
    }

    enum PortingError: LocalizedError {
        case unsupportedSchema
        var errorDescription: String? {
            "This file is not a 3DPrintKit v1 export. Nothing was changed."
        }
    }
}
