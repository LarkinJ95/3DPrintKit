import XCTest
import SwiftData
@testable import PrintKit

@MainActor
final class ModelTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: SchemaV1.schema, configurations: config)
    }

    func testSpoolRemainingFraction() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let spool = Spool()
        spool.originalNetWeightG = 1000
        spool.currentWeightG = 742
        context.insert(spool)

        XCTAssertEqual(spool.remainingFraction, 0.742, accuracy: 0.001)
        XCTAssertEqual(spool.costPerKg ?? 0, 0, accuracy: 0.001) // cost unset -> 0
        spool.cost = 24.99
        XCTAssertEqual(spool.costPerKg ?? 0, 24.99, accuracy: 0.001)
    }

    func testSpoolDisplayName() throws {
        let spool = Spool()
        spool.manufacturer = "Polymaker"
        spool.productLine = "PolyTerra"
        spool.colorName = "Charcoal"
        XCTAssertTrue(spool.displayName.contains("Polymaker"))
        XCTAssertTrue(spool.displayName.contains("Charcoal"))
    }

    func testSpoolEstimatedLength() throws {
        let spool = Spool()
        spool.materialID = "pla"   // density 1.24
        spool.diameter = 1.75
        spool.currentWeightG = 1000
        XCTAssertEqual(spool.estimatedLengthMeters, 335, accuracy: 5)
    }

    func testDryingSessionLifecycle() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = DryingSession()
        session.plannedMinutes = 360
        context.insert(session)

        XCTAssertTrue(session.isActive)
        XCTAssertGreaterThan(session.remainingInterval, 0)
        session.completedAt = Date()
        XCTAssertFalse(session.isActive)
        XCTAssertNotNil(session.actualMinutes)
    }

    func testMaintenanceDueDetection() throws {
        let task = MaintenanceTask()
        task.intervalPrintHours = 100
        // No completions yet -> due when printer has >= 100 h.
        XCTAssertTrue(task.isDue(printerHours: 150))
        XCTAssertFalse(task.isDue(printerHours: 50))
    }

    func testSeederCreatesStorageLocations() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        DataSeeder.seedIfNeeded(context: context)
        let locations = try context.fetch(FetchDescriptor<StorageLocation>())
        XCTAssertGreaterThanOrEqual(locations.count, 1)
    }

    func testMaterialOverrideDoesNotMutateReference() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let override = MaterialOverride()
        override.materialID = "petg"
        override.nozzleMin = 250
        context.insert(override)

        let reference = MaterialLibrary.shared.material(for: "petg")
        let effective = MaterialLibrary.shared.effectiveValues(materialID: "petg", override: override)
        XCTAssertNotEqual(reference?.nozzleMin, effective.nozzleMin)
        XCTAssertEqual(effective.nozzleMin, 250)
    }
}
