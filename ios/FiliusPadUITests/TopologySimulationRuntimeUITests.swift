import CoreGraphics
import XCTest

final class TopologySimulationRuntimeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launch()

        _ = requireElement(app.buttons["runtime.control.start"], named: "runtime.control.start")
        _ = requireElement(app.buttons["runtime.control.stop"], named: "runtime.control.stop")
        _ = requireElement(app.staticTexts["debug.simulationPhase"], named: "debug.simulationPhase")
        _ = requireElement(app.staticTexts["debug.simulationTick"], named: "debug.simulationTick")
        _ = requireElement(app.staticTexts["debug.lastRuntimeEvent"], named: "debug.lastRuntimeEvent")
        _ = requireElement(app.staticTexts["debug.lastRuntimeRoute"], named: "debug.lastRuntimeRoute")
        _ = requireElement(app.staticTexts["debug.lastRuntimeFault"], named: "debug.lastRuntimeFault")
        _ = requireElement(app.staticTexts["debug.lastPingEvent"], named: "debug.lastPingEvent")
        _ = requireElement(app.staticTexts["debug.lastPingFault"], named: "debug.lastPingFault")
    }

    override func tearDownWithError() throws {
        if testRun?.failureCount ?? 0 > 0, let app {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "Failure screenshot"
            screenshot.lifetime = .keepAlways
            add(screenshot)

            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Failure accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        app?.terminate()
        app = nil
    }

    func testRuntimeStartStopAdvancesAndFreezesTick() {
        assertDiagnosticEquals("debug.simulationPhase", expected: "Simulation phase: stopped")
        XCTAssertTrue(requireElement(app.buttons["runtime.control.start"], named: "runtime.control.start").isEnabled)
        XCTAssertFalse(requireElement(app.buttons["runtime.control.stop"], named: "runtime.control.stop").isEnabled)

        let baselineTick = simulationTickValue()

        tapButton("runtime.control.start")
        assertDiagnosticEquals("debug.simulationPhase", expected: "Simulation phase: running")
        XCTAssertFalse(requireElement(app.buttons["runtime.control.start"], named: "runtime.control.start").isEnabled)
        XCTAssertTrue(requireElement(app.buttons["runtime.control.stop"], named: "runtime.control.stop").isEnabled)

        let advancedTick = waitForTickAdvance(from: baselineTick, timeout: 3)
        XCTAssertGreaterThan(advancedTick, baselineTick, "Expected simulation tick to advance while running")

        tapButton("runtime.control.stop")
        assertDiagnosticEquals("debug.simulationPhase", expected: "Simulation phase: stopped")
        XCTAssertTrue(requireElement(app.buttons["runtime.control.start"], named: "runtime.control.start").isEnabled)
        XCTAssertFalse(requireElement(app.buttons["runtime.control.stop"], named: "runtime.control.stop").isEnabled)

        let stoppedTick = simulationTickValue()
        XCTAssertGreaterThanOrEqual(stoppedTick, advancedTick)
        XCTAssertTrue(
            waitForTickToRemainStable(from: stoppedTick, duration: 0.6),
            "Stopping should freeze tick progression"
        )

        XCTAssertTrue(
            label(for: "debug.lastRuntimeEvent").contains("simulationStopped"),
            "Expected runtime event diagnostics to expose simulationStopped after stop"
        )
    }

    func testRuntimeControlsRemainCoherentAcrossInvalidAndRapidTransitions() {
        assertDiagnosticEquals("debug.simulationPhase", expected: "Simulation phase: stopped")
        XCTAssertFalse(requireElement(app.buttons["runtime.control.stop"], named: "runtime.control.stop").isEnabled)

        let initialTick = simulationTickValue()
        XCTAssertTrue(
            waitForTickToRemainStable(from: initialTick, duration: 0.4),
            "Tick must not advance while stopped"
        )

        var previousTick = initialTick

        for _ in 0..<3 {
            tapButton("runtime.control.start")
            assertDiagnosticEquals("debug.simulationPhase", expected: "Simulation phase: running")

            let progressedTick = waitForTickAdvance(from: previousTick, timeout: 2)
            XCTAssertGreaterThan(progressedTick, previousTick)

            tapButton("runtime.control.stop")
            assertDiagnosticEquals("debug.simulationPhase", expected: "Simulation phase: stopped")

            let stoppedTick = simulationTickValue()
            XCTAssertTrue(
                waitForTickToRemainStable(from: stoppedTick, duration: 0.3),
                "Tick must remain frozen after each stop"
            )

            previousTick = stoppedTick
            XCTAssertTrue(requireElement(app.buttons["runtime.control.start"], named: "runtime.control.start").isEnabled)
            XCTAssertFalse(requireElement(app.buttons["runtime.control.stop"], named: "runtime.control.stop").isEnabled)
        }
    }

    func testRunningTapOpensRuntimeDeviceSheetAndReportsMalformedPingDiagnostics() {
        openRuntimeDeviceSheetForSinglePC(ip: "192.168.0.10", subnet: "255.255.255.0")

        XCTAssertFalse(
            app.textFields["runtime.device.command"].exists,
            "Command text field must stay hidden until CMD shell is launched"
        )

        ensureCommandPromptInstalled()
        replaceTextField("runtime.device.command", with: "ping")
        tapButton("runtime.device.execute")

        waitForDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "pingRejectedMalformedCommand", timeout: 3)
        assertDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "pingRejectedMalformedCommand")
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "malformedPingCommand")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "none")
        assertDiagnosticContains("debug.lastPingEvent", expectedSubstring: "pingRejectedMalformedCommand")
        assertDiagnosticContains("debug.lastPingFault", expectedSubstring: "malformedPingCommand")
        assertAnyConsoleLineContains("Ping failed: malformedPingCommand")

        closeRuntimeDeviceSheet()
    }

    func testMalformedAndUnsupportedRuntimeCommandsExposeDeterministicFaultDiagnostics() {
        openRuntimeDeviceSheetForSinglePC(ip: "192.168.0.10", subnet: "255.255.255.0")
        ensureCommandPromptInstalled()

        replaceTextField("runtime.device.command", with: "route")
        tapButton("runtime.device.execute")

        waitForDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "routeRejectedMalformedCommand", timeout: 3)
        assertDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "routeRejectedMalformedCommand")
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "malformedRouteCommand")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "none")
        assertAnyConsoleLineContains("Route failed: malformedRouteCommand")

        replaceTextField("runtime.device.command", with: "rmdir")
        tapButton("runtime.device.execute")

        waitForDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "unsupportedRuntimeCommandFilesystem", timeout: 3)
        assertDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "family=filesystem")
        assertDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "token=rmdir")
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "unsupportedRuntimeCommandFilesystem")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "none")
        assertAnyConsoleLineContains("Command failed: unsupportedRuntimeCommandFilesystem")

        closeRuntimeDeviceSheet()
    }

    func testMissingDNSConfigurationShowsDeterministicRuntimeFaultWithoutRoutePayload() {
        openRuntimeDeviceSheetForSinglePC(ip: "192.168.0.10", subnet: "255.255.255.0")
        ensureCommandPromptInstalled()

        replaceTextField("runtime.device.command", with: "host unresolved.school.local")
        tapButton("runtime.device.execute")

        waitForDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "dnsServerMissing", timeout: 3)
        assertDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "command=host")
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "dnsServerMissing")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "none")
        assertAnyConsoleLineContains("Host lookup failed: dnsServerMissing")

        replaceTextField("runtime.device.command", with: "nslookup unresolved.school.local")
        tapButton("runtime.device.execute")

        waitForDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "dnsServerMissing", timeout: 3)
        assertDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "command=nslookup")
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "dnsServerMissing")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "none")
        assertAnyConsoleLineContains("Host lookup failed: dnsServerMissing")

        closeRuntimeDeviceSheet()
    }

    // MARK: - Helpers

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

    private func tapButton(_ identifier: String) {
        let button: XCUIElement
        if identifier.hasPrefix("runtime.device.") {
            button = revealRuntimeSheetElement(app.buttons.matching(identifier: identifier).firstMatch, named: identifier, towardTop: false)
        } else if identifier == "design.configuration.open" {
            let identified = app.buttons.matching(identifier: identifier).firstMatch
            button = identified.waitForExistence(timeout: 2)
                ? identified
                : requireElement(app.buttons["Configure"], named: identifier)
        } else {
            button = requireElement(app.buttons.matching(identifier: identifier).firstMatch, named: identifier)
        }
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

    private func replaceTextField(_ identifier: String, with text: String) {
        let field = requireElement(app.textFields[identifier], named: identifier)
        field.tap()

        if let currentValue = field.value as? String, !currentValue.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count))
        }

        field.typeText(text)
    }

    private func ensureCommandPromptInstalled() {
        let commandField = app.textFields["runtime.device.command"]
        if commandField.exists {
            _ = revealRuntimeSheetElement(commandField, named: "runtime.device.command", towardTop: false)
            return
        }

        // Starting the simulation seeds CMD on PC-class devices. Scroll back to the desktop
        // before deciding that its launch icon is absent; off-screen SwiftUI grid items may not
        // appear in the accessibility tree until their section is visible.
        let installerButton = revealRuntimeSheetElement(
            app.buttons["runtime.device.install.open"],
            named: "runtime.device.install.open",
            towardTop: true,
            requiresSafeViewport: true
        )
        let launchButton = app.buttons["runtime.device.launch.commandPrompt"]
        if !launchButton.exists {
            installerButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            tapRuntimeSheetButton("runtime.device.install.commandPrompt", towardTop: false)
        }

        let revealedLaunchButton = revealRuntimeSheetElement(
            launchButton,
            named: "runtime.device.launch.commandPrompt",
            towardTop: true,
            requiresSafeViewport: true
        )
        revealedLaunchButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        waitForDiagnosticContains("debug.openedRuntimeProgram", expectedSubstring: "commandPrompt", timeout: 4)
        _ = revealRuntimeSheetElement(commandField, named: "runtime.device.command", towardTop: false)
    }

    private func tapRuntimeSheetButton(_ identifier: String, towardTop: Bool) {
        let button = revealRuntimeSheetElement(
            app.buttons.matching(identifier: identifier).firstMatch,
            named: identifier,
            towardTop: towardTop,
            requiresSafeViewport: true
        )
        XCTAssertTrue(button.isEnabled, "Button '\(identifier)' must be enabled before tapping")
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @discardableResult
    private func revealRuntimeSheetElement(
        _ element: XCUIElement,
        named identifier: String,
        towardTop: Bool,
        requiresSafeViewport: Bool = false,
        maximumSwipes: Int = 10
    ) -> XCUIElement {
        if runtimeSheetElementIsReady(element, requiresSafeViewport: requiresSafeViewport) { return element }
        for _ in 0..<maximumSwipes where !runtimeSheetElementIsReady(
            element,
            requiresSafeViewport: requiresSafeViewport
        ) {
            scrollRuntimeSheet(toward: element, fallbackTowardTop: towardTop)
        }
        XCTAssertTrue(element.exists, "Runtime device sheet never exposed '\(identifier)'")
        XCTAssertTrue(element.isHittable, "Runtime device sheet control '\(identifier)' never became hittable")
        if requiresSafeViewport {
            XCTAssertTrue(
                runtimeSheetElementIsReady(element, requiresSafeViewport: true),
                "Runtime device sheet control '\(identifier)' remained clipped by the navigation bar or sheet edge"
            )
        }
        return element
    }

    private func runtimeSheetElementIsReady(_ element: XCUIElement, requiresSafeViewport: Bool) -> Bool {
        guard element.exists, element.isHittable else { return false }
        guard requiresSafeViewport else { return true }

        let viewport = runtimeSheetViewport(for: runtimeSheetGestureSurface())
        let frame = element.frame
        return frame.height > 0
            && frame.minY >= viewport.minY
            && frame.maxY <= viewport.maxY
    }

    private func runtimeSheetViewport(for surface: XCUIElement) -> CGRect {
        let frame = surface.frame
        return CGRect(
            x: frame.minX + 8,
            y: frame.minY + 72,
            width: max(0, frame.width - 16),
            height: max(0, frame.height - 96)
        )
    }

    private func runtimeSheetGestureSurface() -> XCUIElement {
        let identified = app.scrollViews.matching(identifier: "runtime.device.scroll").firstMatch
        if identified.exists { return identified }

        let modalScrollViews = app.scrollViews.allElementsBoundByIndex.filter {
            $0.exists && $0.frame.width > 300 && $0.frame.height > 200
        }
        return modalScrollViews.max {
            ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
        } ?? app.otherElements.matching(identifier: "runtime.device.sheet").firstMatch
    }

    private func scrollRuntimeSheet(toward element: XCUIElement, fallbackTowardTop: Bool) {
        let surface = runtimeSheetGestureSurface()
        let viewport = runtimeSheetViewport(for: surface)

        if element.exists {
            if element.frame.minY < viewport.minY {
                dragRuntimeSheet(surface, upward: false)
                return
            }
            if element.frame.maxY > viewport.maxY {
                dragRuntimeSheet(surface, upward: true)
                return
            }
        }

        dragRuntimeSheet(surface, upward: !fallbackTowardTop)
    }

    private func dragRuntimeSheet(_ surface: XCUIElement, upward: Bool) {
        let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.68 : 0.32))
        let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.38 : 0.62))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func requireRuntimeDeviceSheetOpen(timeout: TimeInterval = 5) {
        let sheet = requireElement(
            app.otherElements["runtime.device.sheet"],
            named: "runtime.device.sheet",
            timeout: timeout
        )
        XCTAssertGreaterThan(
            sheet.frame.height,
            500,
            "Runtime device sheet must open at the large detent so scrolling is deterministic"
        )
    }

    private func openRuntimeDeviceSheetForSinglePC(ip: String, subnet: String) {
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.35, dy: 0.35))

        tapButton("design.configuration.open")
        replaceValidatedDesignField("design.configuration.ip", with: ip)
        replaceValidatedDesignField("design.configuration.mask", with: subnet)
        tapButton("design.configuration.save")
        tapButton("design.configuration.close")

        tapButton("runtime.control.start")
        assertDiagnosticEquals("debug.simulationPhase", expected: "Simulation phase: running")

        tapCanvas(at: CGVector(dx: 0.35, dy: 0.35))
        requireRuntimeDeviceSheetOpen()

        XCTAssertFalse(app.textFields["runtime.device.ip"].exists)
        XCTAssertFalse(app.textFields["runtime.device.subnet"].exists)
        tapRuntimeSheetButton("runtime.workspace.network", towardTop: false)
        _ = requireElement(
            app.otherElements["runtime.workspace.network.info"],
            named: "runtime.workspace.network.info"
        )
        assertRuntimeNetworkRow("runtime.workspace.network.ip", contains: ip)
        assertRuntimeNetworkRow("runtime.workspace.network.subnet", contains: subnet)
    }

    private func assertRuntimeNetworkRow(_ identifier: String, contains expected: String) {
        let row = requireElement(
            app.descendants(matching: .any).matching(identifier: identifier).firstMatch,
            named: identifier
        )
        let renderedValue = "\(row.label) \(row.value ?? "")"
        XCTAssertTrue(
            renderedValue.contains(expected),
            "Expected '\(identifier)' to contain '\(expected)' but found '\(renderedValue)'"
        )
    }

    private func replaceValidatedDesignField(_ identifier: String, with text: String) {
        let field = requireElement(app.textFields[identifier], named: identifier)
        // Direct coordinate taps avoid XCTest's unreliable AX scroll-to-visible action
        // for fields already visible inside the regular-width configuration inspector.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 64))
        field.typeText(text)
    }

    private func closeRuntimeDeviceSheet() {
        tapButton("runtime.device.close")
        let sheet = app.otherElements["runtime.device.sheet"]
        let deadline = Date().addingTimeInterval(3)

        while Date() < deadline {
            if !sheet.exists {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Runtime sheet should close after tapping Done")
    }

    private func assertDiagnosticEquals(_ identifier: String, expected: String) {
        XCTAssertEqual(label(for: identifier), expected)
    }

    private func assertDiagnosticContains(_ identifier: String, expectedSubstring: String) {
        XCTAssertTrue(
            label(for: identifier).contains(expectedSubstring),
            "Expected '\(identifier)' to contain '\(expectedSubstring)' but found '\(label(for: identifier))'"
        )
    }

    private func label(for identifier: String) -> String {
        let element = requireElement(app.staticTexts[identifier], named: identifier)
        return element.label
    }

    private func simulationTickValue() -> UInt64 {
        let labelText = label(for: "debug.simulationTick")
            .replacingOccurrences(of: "Simulation tick: ", with: "")
        return UInt64(labelText) ?? 0
    }

    private func waitForTickAdvance(from baseline: UInt64, timeout: TimeInterval) -> UInt64 {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let current = simulationTickValue()
            if current > baseline {
                return current
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return simulationTickValue()
    }

    private func waitForTickToRemainStable(from baseline: UInt64, duration: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(duration)

        while Date() < deadline {
            if simulationTickValue() != baseline {
                return false
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return true
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

    private func assertAnyConsoleLineContains(_ expectedText: String) {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "runtime.device.console.line.")
        let lines = app.staticTexts.matching(predicate)

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            for index in 0..<lines.count {
                let line = lines.element(boundBy: index)
                if line.exists, line.label.contains(expectedText) {
                    return
                }
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Expected runtime console to contain '\(expectedText)'")
    }
}
