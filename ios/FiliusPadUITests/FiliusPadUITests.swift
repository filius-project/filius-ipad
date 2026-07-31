import XCTest

final class FiliusPadUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchesEditorScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.otherElements["java.mainMenu"].waitForExistence(timeout: 5))
        let canvases = app.otherElements.matching(identifier: "canvas.surface")
        XCTAssertEqual(canvases.count, 1, "Canvas accessibility anchor must be unique")
        XCTAssertTrue(canvases.firstMatch.exists)
        XCTAssertTrue(app.staticTexts["debug.activeTool"].exists)
        XCTAssertTrue(app.staticTexts["debug.zoomScale"].exists)
    }
    func testGuidedTourCanBeRerunFromSettingsAndSkipped() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.otherElements["java.mainMenu"].waitForExistence(timeout: 5))
        app.buttons["java.menu.overflow"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 3))
        app.buttons["Settings"].tap()

        XCTAssertTrue(app.otherElements["productShell.settings.sheet"].waitForExistence(timeout: 5))
        let guidedTourButton = app.buttons["productShell.settings.guidedTour"]
        for _ in 0..<4 where !guidedTourButton.exists || !guidedTourButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(guidedTourButton.exists)
        guidedTourButton.tap()
        XCTAssertTrue(app.otherElements["guidedTour.sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["guidedTour.skip"].exists)
        app.buttons["guidedTour.skip"].tap()
        XCTAssertFalse(app.otherElements["guidedTour.sheet"].exists)
    }

    func testRegularToolbarUsesAccessibleIconButtons() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertEqual(app.buttons["java.menu.new"].label, "New")
        XCTAssertEqual(app.buttons["java.menu.open"].label, "Open")
        XCTAssertEqual(app.buttons["java.menu.save"].label, "Save")
        XCTAssertEqual(app.buttons["runtime.control.stop"].label, "Design mode")
        XCTAssertEqual(app.buttons["runtime.control.start"].label, "Simulation mode")
        XCTAssertFalse(app.staticTexts["New"].exists)
        XCTAssertFalse(app.staticTexts["Design mode"].exists)
    }

}
