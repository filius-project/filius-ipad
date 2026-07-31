import CoreGraphics
import Foundation
import XCTest

final class TopologyInfrastructureParityUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launch()

        _ = requireElement(app.otherElements["canvas.surface"], named: "canvas.surface", timeout: 8)
        _ = requireControl("palette.tool.place.router")
        _ = requireControl("palette.tool.place.gateway")
        _ = requireControl("runtime.control.start")
        _ = requireDiagnosticElement("debug.nodeCount")
        _ = requireDiagnosticElement("debug.simulationPhase")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testRouterAndGatewayPlacementExposeEvidenceBoundRuntimeSheets() {
        tapButton("palette.tool.place.router")
        tapCanvas(at: CGVector(dx: 0.32, dy: 0.38))
        waitForDiagnosticContains("debug.nodeCount", expectedSubstring: "1", timeout: 3)

        tapButton("palette.tool.place.gateway")
        tapCanvas(at: CGVector(dx: 0.68, dy: 0.38))
        waitForDiagnosticContains("debug.nodeCount", expectedSubstring: "2", timeout: 3)

        tapButton("runtime.control.start")
        waitForDiagnosticContains("debug.simulationPhase", expectedSubstring: "running", timeout: 3)

        tapCanvas(at: CGVector(dx: 0.32, dy: 0.38))
        _ = requireElement(app.otherElements["runtime.device.sheet"], named: "runtime.device.sheet")
        XCTAssertFalse(app.textFields["runtime.device.ip"].exists, "Router must not reuse the PC single-address form")
        assertTextFieldValue("runtime.device.router.interface.rt1.ip", equals: "192.168.0.10")
        assertTextFieldValue("runtime.device.router.interface.rt1.subnet", equals: "255.255.255.0")
        _ = revealRuntimeSheetElement(
            app.buttons.matching(identifier: "runtime.device.router.interface.rt1.save").firstMatch,
            named: "runtime.device.router.interface.rt1.save"
        )
        _ = revealRuntimeSheetElement(
            app.descendants(matching: .any).matching(identifier: "runtime.device.router.info").firstMatch,
            named: "runtime.device.router.info"
        )
        closeRuntimeDeviceSheet()

        tapCanvas(at: CGVector(dx: 0.68, dy: 0.38))
        _ = requireElement(app.otherElements["runtime.device.sheet"], named: "runtime.device.sheet")
        XCTAssertFalse(app.textFields["runtime.device.ip"].exists, "Gateway must not reuse the PC single-address form")
        assertTextFieldValue("runtime.device.gateway.interface.wan0.ip", equals: "42.0.0.10")
        assertTextFieldValue("runtime.device.gateway.interface.wan0.subnet", equals: "255.0.0.0")
        _ = revealRuntimeSheetElement(
            app.buttons.matching(identifier: "runtime.device.gateway.interface.wan0.save").firstMatch,
            named: "runtime.device.gateway.interface.wan0.save"
        )
        assertTextFieldValue("runtime.device.gateway.interface.lan0.ip", equals: "192.168.0.10")
        assertTextFieldValue("runtime.device.gateway.interface.lan0.subnet", equals: "255.255.255.0")
        _ = revealRuntimeSheetElement(
            app.buttons.matching(identifier: "runtime.device.gateway.interface.lan0.save").firstMatch,
            named: "runtime.device.gateway.interface.lan0.save"
        )
        _ = revealRuntimeSheetElement(
            app.descendants(matching: .any).matching(identifier: "runtime.device.gateway.info").firstMatch,
            named: "runtime.device.gateway.info"
        )
    }

    private func assertTextFieldValue(
        _ identifier: String,
        equals expectedValue: String,
        timeout: TimeInterval = 3
    ) {
        let field = revealRuntimeSheetElement(app.textFields.matching(identifier: identifier).firstMatch, named: identifier, timeout: timeout)
        XCTAssertEqual(field.value as? String, expectedValue, "Unexpected value for '\(identifier)'")
    }

    @discardableResult
    private func revealRuntimeSheetElement(
        _ element: XCUIElement,
        named identifier: String,
        timeout: TimeInterval = 10
    ) -> XCUIElement {
        if element.exists, element.isHittable { return element }
        let sheet = requireElement(app.otherElements["runtime.device.sheet"], named: "runtime.device.sheet")
        for _ in 0..<12 where !element.exists || !element.isHittable {
            sheet.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing required element '\(identifier)'")
        XCTAssertTrue(element.isHittable, "Runtime device sheet element '\(identifier)' never became hittable")
        return element
    }

    private func closeRuntimeDeviceSheet() {
        tapButton("runtime.device.close")
        let sheet = app.otherElements["runtime.device.sheet"]
        let predicate = NSPredicate(format: "exists == false")
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: sheet)], timeout: 3)
        XCTAssertEqual(result, .completed, "Timed out waiting for runtime.device.sheet to close")
    }

    private func tapCanvas(at normalizedOffset: CGVector) {
        let canvas = requireElement(app.otherElements["canvas.surface"], named: "canvas.surface")
        canvas.coordinate(withNormalizedOffset: normalizedOffset).tap()
    }

    private func tapButton(_ identifier: String) {
        let button = requireControl(identifier)
        XCTAssertTrue(button.isEnabled, "Button '\(identifier)' must be enabled before tapping")
        if identifier.hasPrefix("palette.") || identifier.hasPrefix("runtime.control.") {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return
        }
        XCTAssertTrue(button.isHittable, "Button '\(identifier)' must be hittable before tapping")
        button.tap()
    }

    @discardableResult
    private func requireControl(_ identifier: String, timeout: TimeInterval = 10) -> XCUIElement {
        let directButton = app.buttons.matching(identifier: identifier).firstMatch
        if directButton.waitForExistence(timeout: min(timeout, 2)) {
            return directButton
        }

        let direct = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        if direct.waitForExistence(timeout: timeout) {
            return direct
        }

        if let label = controlLabelFallback(for: identifier) {
            let fallback = app.buttons[label]
            if fallback.waitForExistence(timeout: 2) {
                return fallback
            }
        }

        XCTFail("Missing required accessibility identifier '\(identifier)'")
        return direct
    }

    @discardableResult
    private func requireDiagnosticElement(_ identifier: String, timeout: TimeInterval = 10) -> XCUIElement {
        let direct = app.staticTexts[identifier]
        if direct.waitForExistence(timeout: timeout) {
            return direct
        }

        let prefix: String
        switch identifier {
        case "debug.nodeCount": prefix = "Nodes:"
        case "debug.simulationPhase": prefix = "Simulation phase:"
        default: prefix = identifier
        }
        let fallback = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        if fallback.waitForExistence(timeout: 2) {
            return fallback
        }

        XCTFail("Missing required diagnostic '\(identifier)'")
        return direct
    }

    private func waitForDiagnosticContains(
        _ identifier: String,
        expectedSubstring: String,
        timeout: TimeInterval
    ) {
        let element = requireDiagnosticElement(identifier)
        let predicate = NSPredicate(format: "label CONTAINS %@", expectedSubstring)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Timed out waiting for '\(identifier)' predicate")
    }

    private func controlLabelFallback(for identifier: String) -> String? {
        switch identifier {
        case "palette.tool.place.router": return "Router"
        case "palette.tool.place.gateway": return "Gateway"
        case "runtime.control.start": return "Aktionsmodus"
        case "runtime.device.close": return "Done"
        default: return nil
        }
    }

    @discardableResult
    private func requireElement(_ element: XCUIElement, named name: String, timeout: TimeInterval = 10) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing required element '\(name)'")
        return element
    }
}
