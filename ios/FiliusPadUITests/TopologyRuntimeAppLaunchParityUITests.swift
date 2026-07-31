import CoreGraphics
import Foundation
import XCTest

final class TopologyRuntimeAppLaunchParityUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launch()

        _ = requireElement(app.otherElements["canvas.surface"], named: "canvas.surface", timeout: 8)
        _ = requireControl("palette.tool.place.pc")
        _ = requireControl("runtime.control.start")
        _ = requireDiagnosticElement("debug.lastRuntimeEvent")
        _ = requireDiagnosticElement("debug.openedRuntimeDevice")
        _ = requireDiagnosticElement("debug.openedRuntimeProgram")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testLaunchFromDesktopShowsSingleShellAndCloseReturnsToDesktop() {
        seedSinglePCRuntimeSheet()

        assertDiagnosticContains("debug.openedRuntimeProgram", expectedSubstring: "none")

        installProgramIfNeeded(.commandPrompt)

        tapRuntimeSheetButton("runtime.device.launch.commandPrompt", towardTop: true)
        waitForDiagnosticContains("debug.openedRuntimeProgram", expectedSubstring: "commandPrompt", timeout: 3)
        _ = revealRuntimeSheetElement(
            app.otherElements["runtime.device.appShell.commandPrompt"],
            named: "runtime.device.appShell.commandPrompt",
            towardTop: false
        )

        XCTAssertFalse(
            app.buttons["runtime.device.launch.commandPrompt"].exists,
            "Desktop launch controls must not remain stacked underneath the active app workspace"
        )
        assertSingleCommandPromptShellVisible()
        _ = requireElement(
            app.scrollViews["runtime.device.console.list"],
            named: "runtime.device.console.list"
        )
        _ = requireElement(
            app.staticTexts["runtime.device.command.prompt"],
            named: "runtime.device.command.prompt"
        )
        XCTAssertEqual(
            app.staticTexts["runtime.device.command.prompt"].label,
            "/>",
            "CMD must show the current virtual working directory as an authentic shell prompt"
        )

        tapRuntimeSheetButton("runtime.device.app.close", towardTop: true)
        waitForElementToDisappear(app.otherElements["runtime.device.appShell.commandPrompt"], timeout: 3, identifier: "runtime.device.appShell.commandPrompt")
        assertDiagnosticContains("debug.openedRuntimeProgram", expectedSubstring: "none")
        _ = revealRuntimeSheetElement(
            app.staticTexts["runtime.device.command.desktopHint"],
            named: "runtime.device.command.desktopHint",
            towardTop: false
        )
        XCTAssertFalse(
            app.textFields["runtime.device.command"].exists,
            "Command entry must disappear when returning to desktop"
        )
        XCTAssertFalse(
            app.buttons["runtime.device.execute"].exists,
            "Execute control must disappear when returning to desktop"
        )
    }

    func testExpandedInstallerLabelDoesNotExposeEncodingArtifacts() {
        seedSinglePCRuntimeSheet()

        let installerButton = revealRuntimeSheetElement(
            app.buttons.matching(identifier: "runtime.device.install.open").firstMatch,
            named: "runtime.device.install.open",
            towardTop: true
        )
        let installerLabel = installerButton.label
        XCTAssertFalse(
            installerLabel.contains("\u{00E2}"),
            "Installer label must not expose a mojibake suffix"
        )

        installerButton.tap()
        XCTAssertTrue(
            app.otherElements["runtime.device.installer"].waitForExistence(timeout: 2),
            "Tapping the Installer icon must still expand the installer section"
        )
        XCTAssertTrue(
            app.otherElements["runtime.workspace.window"].exists,
            "Software Manager must open as a foreground desktop window"
        )
        XCTAssertTrue(
            app.otherElements["runtime.workspace.taskbar"].exists,
            "The desktop taskbar must remain available while Software Manager is open"
        )
        XCTAssertTrue(
            app.buttons["runtime.workspace.applications"].exists,
            "Software Manager must preserve the Back to Desktop path"
        )
    }

    func testCommandEntryIsBlockedUntilCMDLaunchesFromDesktop() {
        seedSinglePCRuntimeSheet()
        installProgramIfNeeded(.commandPrompt)

        XCTAssertFalse(
            app.textFields["runtime.device.command"].waitForExistence(timeout: 1),
            "Command text field must stay hidden until CMD is launched from desktop"
        )
        XCTAssertFalse(
            app.buttons["runtime.device.execute"].waitForExistence(timeout: 1),
            "Execute button must stay hidden until CMD is launched from desktop"
        )

        _ = revealRuntimeSheetElement(
            app.staticTexts["runtime.device.command.desktopHint"],
            named: "runtime.device.command.desktopHint",
            towardTop: false
        )
        assertDiagnosticContains("debug.openedRuntimeProgram", expectedSubstring: "none")
    }

    // MARK: - Helpers

    private func seedSinglePCRuntimeSheet() {
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.40, dy: 0.35))

        tapButton("runtime.control.start")
        waitForDiagnosticContains("debug.simulationPhase", expectedSubstring: "running", timeout: 3)

        tapCanvas(at: CGVector(dx: 0.40, dy: 0.35))
        requireRuntimeDeviceSheetOpen()
    }

    private func requireRuntimeDeviceSheetOpen(timeout: TimeInterval = 5) {
        let sheet = requireElement(
            app.otherElements["runtime.device.sheet"],
            named: "runtime.device.sheet",
            timeout: timeout
        )
        _ = requireElement(
            app.staticTexts["runtime.device.sheet.title"],
            named: "runtime.device.sheet.title",
            timeout: timeout
        )
        let sheetNodeID = requireElement(
            app.staticTexts["runtime.device.sheet.nodeID"],
            named: "runtime.device.sheet.nodeID",
            timeout: timeout
        )
        _ = requireElement(
            app.buttons["runtime.device.close"],
            named: "runtime.device.close",
            timeout: timeout
        )

        guard let openedDeviceID = waitForDiagnosticUUID("debug.openedRuntimeDevice", timeout: timeout) else {
            return
        }
        guard let presentedDeviceID = firstUUID(in: sheetNodeID.label) else {
            XCTFail("Runtime device sheet node identifier did not contain a UUID: '\(sheetNodeID.label)'")
            return
        }

        XCTAssertTrue(sheet.exists, "Runtime device sheet must remain presented after its content becomes ready")
        XCTAssertEqual(
            presentedDeviceID,
            openedDeviceID,
            "Presented runtime device sheet must match debug.openedRuntimeDevice"
        )
    }

    private func installProgramIfNeeded(_ program: TopologyRuntimeProgramFixture) {
        let launchIdentifier = "runtime.device.launch.\(program.rawValue)"
        let launchButton = app.buttons.matching(identifier: launchIdentifier).firstMatch
        if revealRuntimeSheetElementIfPresent(launchButton, towardTop: true) {
            return
        }

        tapRuntimeSheetButton("runtime.device.install.open", towardTop: true)
        let installIdentifier = "runtime.device.install.\(program.rawValue)"
        tapRuntimeSheetButton(installIdentifier, towardTop: false)
        _ = revealRuntimeSheetElement(launchButton, named: launchIdentifier, towardTop: true)
        assertDiagnosticContains("debug.openedRuntimeProgram", expectedSubstring: "none")
    }

    private func tapRuntimeSheetButton(_ identifier: String, towardTop: Bool) {
        let button = revealRuntimeSheetElement(app.buttons.matching(identifier: identifier).firstMatch, named: identifier, towardTop: towardTop)
        XCTAssertTrue(button.isEnabled, "Button '\(identifier)' must be enabled before tapping")
        button.tap()
    }

    private func revealRuntimeSheetElementIfPresent(_ element: XCUIElement, towardTop: Bool) -> Bool {
        guard element.exists else { return false }
        for _ in 0..<6 where !element.isHittable {
            towardTop ? runtimeSheetGestureSurface().swipeDown() : runtimeSheetGestureSurface().swipeUp()
        }
        return element.exists
    }

    @discardableResult
    private func revealRuntimeSheetElement(
        _ element: XCUIElement,
        named identifier: String,
        towardTop: Bool,
        maximumSwipes: Int = 8
    ) -> XCUIElement {
        if element.exists, element.isHittable { return element }
        for _ in 0..<maximumSwipes where !element.exists || !element.isHittable {
            towardTop ? runtimeSheetGestureSurface().swipeDown() : runtimeSheetGestureSurface().swipeUp()
        }
        XCTAssertTrue(element.exists, "Runtime device sheet never exposed '\(identifier)'")
        XCTAssertTrue(element.isHittable, "Runtime device sheet control '\(identifier)' never became hittable")
        return element
    }

    private func runtimeSheetGestureSurface() -> XCUIElement {
        let modalScrollViews = app.scrollViews.allElementsBoundByIndex.filter {
            $0.exists && $0.frame.width > 300 && $0.frame.height > 200
        }
        return modalScrollViews.max {
            ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
        } ?? app.otherElements.matching(identifier: "runtime.device.sheet").firstMatch
    }

    private func assertSingleCommandPromptShellVisible() {
        let shells = app.otherElements.matching(identifier: "runtime.device.appShell.commandPrompt")
        XCTAssertEqual(shells.count, 1, "Only one CMD shell should be visible while focused")
        XCTAssertTrue(shells.element(boundBy: 0).exists, "CMD shell must remain visible")
    }

    @discardableResult
    private func requireElement(
        _ element: XCUIElement,
        named identifier: String,
        timeout: TimeInterval = 5
    ) -> XCUIElement {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Missing required accessibility identifier '\(identifier)'"
        )
        return element
    }

    @discardableResult
    private func requireControl(_ identifier: String, timeout: TimeInterval = 10) -> XCUIElement {
        if let control = locateControl(identifier, timeout: timeout) {
            return control
        }

        XCTFail("Missing required accessibility identifier '\(identifier)'")
        return app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func locateControl(_ identifier: String, timeout: TimeInterval) -> XCUIElement? {
        let directButton = app.buttons.matching(identifier: identifier).firstMatch
        if directButton.waitForExistence(timeout: min(timeout, 2)) {
            return directButton
        }

        let direct = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        let directTimeout = min(timeout, 2)
        if direct.waitForExistence(timeout: directTimeout) {
            return direct
        }

        if let fallbackLabel = controlLabelFallback(for: identifier) {
            let scopedPredicate = NSPredicate(
                format: "label == %@ AND identifier != %@",
                fallbackLabel,
                "palette.toolbar.content"
            )
            let scopedFallback = app.buttons.matching(scopedPredicate).firstMatch
            if scopedFallback.waitForExistence(timeout: 2) {
                return scopedFallback
            }

            let broadFallback = app.buttons.matching(NSPredicate(format: "label == %@", fallbackLabel)).firstMatch
            if broadFallback.waitForExistence(timeout: 1) {
                return broadFallback
            }
        }

        return nil
    }

    private func controlLabelFallback(for identifier: String) -> String? {
        switch identifier {
        case "palette.tool.place.pc":
            return "PC"
        case "runtime.control.start":
            return "Aktionsmodus"
        case "runtime.device.install.open":
            return "Installer"
        case "runtime.device.install.commandPrompt":
            return "Install"
        case "runtime.device.app.close":
            return "Back to Desktop"
        default:
            return nil
        }
    }

    @discardableResult
    private func requireDiagnosticElement(_ identifier: String, timeout: TimeInterval = 10) -> XCUIElement {
        let identified = app.staticTexts[identifier]
        if identified.waitForExistence(timeout: timeout) {
            return identified
        }

        if let prefix = diagnosticPrefixFallback(for: identifier) {
            let fallback = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
            if fallback.waitForExistence(timeout: 2) {
                return fallback
            }
        }

        XCTFail("Missing required accessibility identifier '\(identifier)'")
        return identified
    }

    private func diagnosticPrefixFallback(for identifier: String) -> String? {
        switch identifier {
        case "debug.simulationPhase":
            return "Simulation phase:"
        case "debug.lastRuntimeEvent":
            return "Last runtime event:"
        case "debug.openedRuntimeDevice":
            return "Opened runtime device:"
        case "debug.openedRuntimeProgram":
            return "Opened runtime program:"
        default:
            return nil
        }
    }

    private func tapButton(_ identifier: String) {
        let button = requireControl(identifier)
        XCTAssertTrue(button.isEnabled, "Button '\(identifier)' must be enabled before tapping")
        if identifier.hasPrefix("palette.") || identifier.hasPrefix("runtime.control.") {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return
        }

        button.tap()
    }

    private func tapCanvas(at normalizedOffset: CGVector) {
        let canvas = requireElement(app.otherElements["canvas.surface"], named: "canvas.surface")
        canvas.coordinate(withNormalizedOffset: normalizedOffset).tap()
    }

    private func assertDiagnosticContains(_ identifier: String, expectedSubstring: String) {
        XCTAssertTrue(
            label(for: identifier).contains(expectedSubstring),
            "Expected '\(identifier)' to contain '\(expectedSubstring)' but found '\(label(for: identifier))'"
        )
    }

    private func label(for identifier: String) -> String {
        let element = requireDiagnosticElement(identifier)
        return element.label
    }

    private func waitForDiagnosticUUID(_ identifier: String, timeout: TimeInterval) -> UUID? {
        let element = requireDiagnosticElement(identifier)
        let uuidPattern = "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
        let predicate = NSPredicate(format: "label MATCHES %@", ".*\(uuidPattern).*")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)

        guard result == .completed else {
            XCTFail("Timed out waiting for \(identifier) to publish a runtime device UUID; found '\(element.label)'")
            return nil
        }

        return firstUUID(in: element.label)
    }

    private func firstUUID(in label: String) -> UUID? {
        let uuidPattern = #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
        guard let range = label.range(of: uuidPattern, options: .regularExpression) else {
            return nil
        }

        return UUID(uuidString: String(label[range]))
    }

    private func waitForDiagnosticContains(_ identifier: String, expectedSubstring: String, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if label(for: identifier).contains(expectedSubstring) {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Timed out waiting for \(identifier) to contain '\(expectedSubstring)'")
    }

    private func waitForElementToDisappear(_ element: XCUIElement, timeout: TimeInterval, identifier: String) {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if !element.exists {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Timed out waiting for '\(identifier)' to disappear")
    }
}

private enum TopologyRuntimeProgramFixture: String {
    case commandPrompt
}
