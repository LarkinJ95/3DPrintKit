import Foundation
import SwiftData

/// Seeds reference-adjacent defaults (storage locations) on first launch.
/// The filament *reference* database itself ships as bundled JSON
/// (Resources/materials.json) and loads via MaterialLibrary.
enum DataSeeder {

    private static let seededKey = "printkit.seeded.v1"

    static func seedIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }

        let defaults: [(String, StorageKind)] = [
            ("Dryer 1", .dryer),
            ("Dry Box", .dryBox),
            ("Cabinet", .cabinet),
            ("Shelf A", .shelf)
        ]
        for (name, kind) in defaults {
            let location = StorageLocation()
            location.name = name
            location.kind = kind
            context.insert(location)
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    /// Optional sample dataset so users can explore every surface.
    /// Loaded only on explicit user request from Settings.
    static func loadSampleData(context: ModelContext) {
        guard !AppSettings.shared.sampleDataLoaded else { return }

        let printer = PrinterDevice()
        printer.manufacturer = "Bambu Lab"
        printer.model = "X1 Carbon"
        printer.customName = "X1C"
        printer.maxHotendTempC = 300
        printer.maxBedTempC = 110
        printer.hasEnclosure = true
        printer.hasHeatedChamber = false
        printer.multiMaterial = .bambuAMS
        printer.amsSlotCount = 4
        printer.totalPrintHours = 412
        context.insert(printer)

        let nozzle = NozzleRecord()
        nozzle.printer = printer
        nozzle.diameter = 0.4
        nozzle.material = .hardenedSteel
        nozzle.brand = "Bambu"
        nozzle.installedDate = Date().addingTimeInterval(-90 * 86400)
        nozzle.printHours = 187
        nozzle.abrasiveHours = 34
        nozzle.isInstalled = true
        context.insert(nozzle)

        let plate = BuildPlate()
        plate.printer = printer
        plate.plateType = .texturedPEI
        plate.manufacturer = "Bambu Lab"
        plate.usageHours = 210
        plate.condition = .good
        context.insert(plate)

        let task = MaintenanceTask()
        task.printer = printer
        task.title = "Lubricate Z lead screws"
        task.intervalPrintHours = 200
        task.hoursAtLastCompletion = 250
        context.insert(task)

        let spool1 = Spool()
        spool1.manufacturer = "Polymaker"
        spool1.productLine = "PolyLite PETG"
        spool1.materialID = "petg"
        spool1.colorName = "Black"
        spool1.colorHex = "#1C1C1E"
        spool1.originalNetWeightG = 1000
        spool1.currentWeightG = 742
        spool1.cost = 21.99
        spool1.vendor = "Polymaker"
        spool1.openedDate = Date().addingTimeInterval(-12 * 86400)
        spool1.lastDriedDate = Date().addingTimeInterval(-5 * 86400)
        context.insert(spool1)

        let spool2 = Spool()
        spool2.manufacturer = "eSUN"
        spool2.productLine = "PLA+"
        spool2.materialID = "pla-plus"
        spool2.colorName = "Fire Engine Red"
        spool2.colorHex = "#C1272D"
        spool2.originalNetWeightG = 1000
        spool2.currentWeightG = 120
        spool2.cost = 17.49
        context.insert(spool2)

        let spool3 = Spool()
        spool3.manufacturer = "Polymaker"
        spool3.productLine = "PolyLite ASA"
        spool3.materialID = "asa"
        spool3.colorName = "White"
        spool3.colorHex = "#F2F2F7"
        spool3.originalNetWeightG = 1000
        spool3.currentWeightG = 640
        spool3.cost = 24.99
        spool3.openedDate = Date().addingTimeInterval(-40 * 86400)
        spool3.lastDriedDate = Date().addingTimeInterval(-32 * 86400)
        context.insert(spool3)

        let profile = SlicerProfile()
        profile.name = "PETG · X1C · 0.4 Hardened"
        profile.printer = printer
        profile.materialID = "petg"
        profile.filamentProduct = "PolyLite PETG"
        profile.nozzleTemp = 242
        profile.bedTemp = 80
        profile.fanPercent = 40
        profile.flowRatio = 0.96
        profile.printSpeed = 80
        profile.isKnownGood = true
        profile.successCount = 17
        profile.failureCount = 1
        profile.lastUsed = Date().addingTimeInterval(-2 * 86400)
        context.insert(profile)

        let record = PrintRecord()
        record.name = "Enclosure Bracket"
        record.printer = printer
        record.spool = spool1
        record.materialID = "petg"
        record.profile = profile
        record.date = Date().addingTimeInterval(-2 * 86400)
        record.durationMinutes = 214
        record.gramsUsed = 186
        record.cost = 4.86
        record.success = true
        context.insert(record)

        printer.totalPrintHours += 214.0 / 60.0

        AppSettings.shared.sampleDataLoaded = true
        try? context.save()
    }
}
