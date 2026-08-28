import XCTest
@testable import PrintKit

final class FilamentMathTests: XCTestCase {

    func testGramsToMetersRoundTrip() {
        // 1 kg of 1.75 mm PLA (density 1.24) is roughly 335 m — a well-known
        // real-world figure. Round-trip must be lossless within tolerance.
        let meters = FilamentMath.gramsToMeters(1000, diameterMM: 1.75, densityGcm3: 1.24)
        XCTAssertEqual(meters, 335, accuracy: 5)
        let grams = FilamentMath.metersToGrams(meters, diameterMM: 1.75, densityGcm3: 1.24)
        XCTAssertEqual(grams, 1000, accuracy: 0.5)
    }

    func testVolumetricFlowAndMaxSpeed() {
        let flow = FilamentMath.volumetricFlow(lineWidthMM: 0.42, layerHeightMM: 0.2, speedMMs: 100)
        XCTAssertEqual(flow, 8.4, accuracy: 0.001)
        let speed = FilamentMath.maxSpeed(targetFlowMm3s: 8.4, lineWidthMM: 0.42, layerHeightMM: 0.2)
        XCTAssertEqual(speed, 100, accuracy: 0.001)
    }

    func testDepletionRespectsReserve() {
        // 500 g remaining, 100 g per print, 10% reserve on a 1000 g spool
        // -> reserve 100 g -> usable 400 g -> 4 prints.
        XCTAssertEqual(FilamentMath.depletionPrints(remainingG: 500, perPrintG: 100, reservePercent: 10, originalG: 1000), 4)
        // Below reserve: no prints.
        XCTAssertEqual(FilamentMath.depletionPrints(remainingG: 80, perPrintG: 100, reservePercent: 10, originalG: 1000), 0)
    }

    func testScaleCompensation() {
        let result = FilamentMath.scaleCompensation(designed: 100, measured: 99)
        XCTAssertEqual(result.error, -1, accuracy: 0.0001)
        XCTAssertEqual(result.scaleFactor, 100.0 / 99.0, accuracy: 0.0001)
    }

    func testHoleCompensation() {
        XCTAssertEqual(FilamentMath.holeCompensation(designedMM: 10, measuredMM: 9.6), 0.4, accuracy: 0.0001)
    }
}

final class CostEngineTests: XCTestCase {

    func testBasicFilamentCost() {
        var input = CostInput()
        input.filamentGrams = 100
        input.filamentPricePerSpool = 25
        input.spoolSizeGrams = 1000
        input.printerWatts = 0
        let result = CostEngine.calculate(input)
        XCTAssertEqual(result.filamentCost, 2.5, accuracy: 0.001)
        XCTAssertEqual(result.productionCost, 2.5, accuracy: 0.001)
    }

    func testMarkupAndMargin() {
        var input = CostInput()
        input.filamentGrams = 100
        input.filamentPricePerSpool = 20
        input.spoolSizeGrams = 1000
        input.printerWatts = 0
        input.markupPercent = 100
        let result = CostEngine.calculate(input)
        XCTAssertEqual(result.productionCost, 2.0, accuracy: 0.001)
        XCTAssertEqual(result.suggestedPrice, 4.0, accuracy: 0.001)
        XCTAssertEqual(result.grossMarginPercent, 50, accuracy: 0.1)
    }

    func testElectricityCost() {
        var input = CostInput()
        input.filamentGrams = 0
        input.printerWatts = 200
        input.printHours = 10
        input.electricityRatePerKWh = 0.30
        let result = CostEngine.calculate(input)
        XCTAssertEqual(result.electricityCost, 0.6, accuracy: 0.001)
    }
}

final class SpoolTagPayloadTests: XCTestCase {

    func testRoundTrip() throws {
        let id = UUID()
        let payload = SpoolTagPayload(schema: "printkit.spool", version: 1, spoolID: id,
                                      manufacturer: "Bambu Lab", material: "pla",
                                      product: "PLA Basic", color: "Gray", diameter: 1.75,
                                      originalWeight: 1000, remainingWeight: 742)
        let data = try payload.encode()
        let decoded = try XCTUnwrap(SpoolTagPayload.decode(data))
        XCTAssertEqual(decoded.spoolID, id)
        XCTAssertEqual(decoded.schema, "printkit.spool")
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.remainingWeight, 742)
    }

    func testQRStringRoundTrip() {
        let id = UUID()
        let payload = SpoolTagPayload(schema: "printkit.spool", version: 1, spoolID: id)
        XCTAssertEqual(SpoolTagPayload.decodeQR(payload.qrString), id)
        XCTAssertEqual(SpoolTagPayload.decodeQR(id.uuidString), id)
        XCTAssertNil(SpoolTagPayload.decodeQR("not-a-uuid"))
    }

    func testFutureVersionIsRejected() throws {
        let json = #"{"schema":"printkit.spool","version":99,"spoolID":"\#(UUID().uuidString)"}"#
        XCTAssertNil(SpoolTagPayload.decode(Data(json.utf8)))
    }
}

final class MaterialLibraryTests: XCTestCase {

    func testLibrarySeeds32Materials() {
        let library = MaterialLibrary.shared
        XCTAssertGreaterThanOrEqual(library.materials.count, 32)
    }

    func testEveryMaterialHasRequiredFields() {
        for material in MaterialLibrary.shared.materials {
            XCTAssertFalse(material.id.isEmpty)
            XCTAssertFalse(material.name.isEmpty)
            XCTAssertGreaterThan(material.density, 0)
            XCTAssertGreaterThan(material.nozzleMax, material.nozzleMin)
            XCTAssertGreaterThanOrEqual(material.strength, 1)
            XCTAssertLessThanOrEqual(material.strength, 5)
        }
    }

    func testSearch() {
        let results = MaterialLibrary.shared.search("petg")
        XCTAssertTrue(results.contains { $0.id == "petg" })
    }
}

final class ReadinessEngineTests: XCTestCase {

    func testMissingSpoolFails() {
        let context = ReadinessEngine.Context(
            printer: nil, spool: nil, material: nil, profile: nil,
            plate: nil, nozzle: nil, requiredGrams: 100,
            usesAMS: false, supportMaterialID: nil
        )
        let result = ReadinessEngine.evaluate(context)
        XCTAssertFalse(result.passed)
    }
}

final class MaterialAdvisorTests: XCTestCase {

    func testOutdoorRequirementRanksASAHigh() {
        let ranked = MaterialAdvisor.shared.rank(requirements: [.outdoorUse: 3])
        XCTAssertFalse(ranked.isEmpty)
        let topIDs = ranked.prefix(3).map { $0.material.id }
        XCTAssertTrue(topIDs.contains("asa") || topIDs.contains("petg"))
    }

    func testSubstitutionReturnsSimilarMaterials() {
        guard let petg = MaterialLibrary.shared.material(for: "petg") else {
            XCTFail("PETG missing from library")
            return
        }
        let substitutes = MaterialAdvisor.shared.substitutes(for: petg)
        XCTAssertFalse(substitutes.isEmpty)
        XCTAssertFalse(substitutes.contains { $0.material.id == "petg" })
    }
}
