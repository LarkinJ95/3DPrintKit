import XCTest

final class PrintKitUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testTabBarExists() throws {
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
        XCTAssertTrue(app.tabBars.buttons["Spools"].exists)
        XCTAssertTrue(app.tabBars.buttons["Materials"].exists)
        XCTAssertTrue(app.tabBars.buttons["Tools"].exists)
        XCTAssertTrue(app.tabBars.buttons["Garage"].exists)
    }

    func testNavigateToMaterials() throws {
        app.tabBars.buttons["Materials"].tap()
        XCTAssertTrue(app.navigationBars["Materials"].waitForExistence(timeout: 5))
    }

    func testNavigateToSpools() throws {
        app.tabBars.buttons["Spools"].tap()
        XCTAssertTrue(app.navigationBars["Spools"].waitForExistence(timeout: 5))
    }

    func testNavigateToGarage() throws {
        app.tabBars.buttons["Garage"].tap()
        XCTAssertTrue(app.navigationBars["Garage"].waitForExistence(timeout: 5))
    }

    func testNavigateToTools() throws {
        app.tabBars.buttons["Tools"].tap()
        XCTAssertTrue(app.navigationBars["Tools"].waitForExistence(timeout: 5))
    }

    func testMaterialDetailOpens() throws {
        app.tabBars.buttons["Materials"].tap()
        let firstCell = app.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
        firstCell.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
    }
}
