import CoreGraphics
import XCTest

final class TopologyRuntimePingWorkflowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launch()

        _ = canvasSurfaceElement(timeout: 8)
    }

    func testPingSucceedsForReachableConfiguredPeerInRunningSimulation() {
        seedReachableTwoPcTopology()

        tapButton("runtime.control.start")
        assertDiagnosticContains("debug.simulationPhase", expectedSubstring: "running")

        openRuntimeDevice(at: CGVector(dx: 0.25, dy: 0.30))
        executeCommand("ping 192.168.10.11")

        waitForDiagnosticContains("debug.lastPingEvent", expectedSubstring: "pingSucceeded", timeout: 3)
        assertDiagnosticContains("debug.lastPingEvent", expectedSubstring: "pingSucceeded")
        assertDiagnosticContains("debug.lastPingFault", expectedSubstring: "none")
        assertAnyConsoleLineContains("64 bytes from 192.168.10.11: icmp_seq=1")
    }

    func testPingFailurePathReportsDeterministicUnknownTargetDiagnostics() {
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.35, dy: 0.35))
        configureSelectedDesignDevice(
            ip: "192.168.20.10",
            subnet: "255.255.255.0"
        )

        tapButton("runtime.control.start")
        assertDiagnosticContains("debug.simulationPhase", expectedSubstring: "running")

        openRuntimeDevice(at: CGVector(dx: 0.35, dy: 0.35))
        executeCommand("ping 192.168.20.250")

        assertDiagnosticContains("debug.lastPingEvent", expectedSubstring: "pingRejectedUnknownTarget")
        assertDiagnosticContains("debug.lastPingFault", expectedSubstring: "pingTargetUnknown")
        assertAnyConsoleLineContains("Ping failed: pingTargetUnknown")
    }

    func testTraceCommandPublishesPathAwareRuntimeDiagnostics() {
        seedReachableTwoPcTopology()

        tapButton("runtime.control.start")
        assertDiagnosticContains("debug.simulationPhase", expectedSubstring: "running")

        openRuntimeDevice(at: CGVector(dx: 0.25, dy: 0.30))
        executeCommand("trace 192.168.10.11")

        waitForDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "traceSucceeded", timeout: 3)
        assertDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "traceSucceeded")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "command=trace")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "targetIP=192.168.10.11")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "hops=2")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "latencyMs=10")
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "none")

        assertAnyConsoleLineContains("Trace to 192.168.10.11 succeeded (hops=2, latencyMs=10)")
        assertAnyConsoleLineContains("Path: ")
    }

    func testRouteCommandPublishesPathAwareRuntimeDiagnostics() {
        seedReachableTwoPcTopology()

        tapButton("runtime.control.start")
        assertDiagnosticContains("debug.simulationPhase", expectedSubstring: "running")

        openRuntimeDevice(at: CGVector(dx: 0.25, dy: 0.30))
        executeCommand("route 192.168.10.11")

        waitForDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "routeSucceeded", timeout: 3)
        assertDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "routeSucceeded")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "command=route")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "targetIP=192.168.10.11")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "hops=2")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "latencyMs=10")
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "none")

        assertAnyConsoleLineContains("Route to 192.168.10.11 succeeded (hops=2, latencyMs=10)")
        assertAnyConsoleLineContains("Route path: ")
    }

    func testHelpCommandPublishesRuntimeDiagnosticsAndConsoleCatalog() {
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.35, dy: 0.35))

        tapButton("runtime.control.start")
        assertDiagnosticContains("debug.simulationPhase", expectedSubstring: "running")

        openRuntimeDevice(at: CGVector(dx: 0.35, dy: 0.35))
        executeCommand("help")

        waitForDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "runtimeHelpDisplayed", timeout: 3)
        assertDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "runtimeHelpDisplayed")
        assertDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "command=help")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "none")
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "none")

        assertAnyConsoleLineContains("CMD help:")
        let helpHint = requireElement(
            app.descendants(matching: .any).matching(identifier: "runtime.device.command.help").firstMatch,
            named: "runtime.device.command.help"
        )
        XCTAssertTrue(
            helpHint.label.contains("help"),
            "The terminal start screen must point users to the help command"
        )
        assertAnyConsoleLineContains("ping <target-ipv4|hostname>")
        assertAnyConsoleLineContains("CMD filesystem commands share the persistent per-device virtual filesystem.")
    }

    func testHostAndNslookupCommandsPublishDeterministicResolveDiagnostics() {
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.35, dy: 0.35))

        tapButton("runtime.control.start")
        assertDiagnosticContains("debug.simulationPhase", expectedSubstring: "running")

        openRuntimeDevice(at: CGVector(dx: 0.35, dy: 0.35))
        executeCommand("dns add api.school.local 10.2.0.44")

        waitForDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "dnsServerNotInstalled", timeout: 3)
        assertDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "dnsServerRejectedInvalidConfiguration")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "none")
        assertAnyConsoleLineContains("DNS failed: dnsServerNotInstalled")

        executeCommand("host api.school.local")
        waitForDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "dnsServerMissing", timeout: 3)
        assertDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "command=host")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "none")
        assertAnyConsoleLineContains("Host lookup failed: dnsServerMissing")

        executeCommand("nslookup api.school.local")
        waitForDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "dnsServerMissing", timeout: 3)
        assertDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "command=nslookup")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "none")
        assertAnyConsoleLineContains("Host lookup failed: dnsServerMissing")
    }

    // MARK: - Helpers

    private func runtimeSheetGestureSurface() -> XCUIElement {
        let modalScrollViews = app.scrollViews.allElementsBoundByIndex.filter {
            $0.exists && $0.frame.width > 300 && $0.frame.height > 200
        }
        return modalScrollViews.max {
            ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
        } ?? app.otherElements.matching(identifier: "runtime.device.sheet").firstMatch
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
        case "palette.tool.select":
            return "Select"
        case "palette.tool.place.pc":
            return "PC"
        case "palette.tool.place.switch":
            return "Switch"
        case "palette.tool.connect":
            return "Connect"
        case "runtime.control.start":
            return "Aktionsmodus"
        case "design.configuration.open":
            return "Configure"
        case "runtime.device.execute":
            return "Run"
        case "runtime.device.close":
            return "Done"
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
        case "debug.nodeCount":
            return "Nodes:"
        case "debug.linkCount":
            return "Links:"
        case "debug.simulationPhase":
            return "Simulation phase:"
        case "debug.lastRuntimeEvent":
            return "Last runtime event:"
        case "debug.lastRuntimeRoute":
            return "Last runtime route:"
        case "debug.lastRuntimeFault":
            return "Last runtime fault:"
        case "debug.lastPingEvent":
            return "Last ping event:"
        case "debug.lastPingFault":
            return "Last ping fault:"
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
        if identifier.hasPrefix("palette.") {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return
        }

        button.tap()
    }

    @discardableResult
    private func canvasSurfaceElement(timeout: TimeInterval = 5) -> XCUIElement {
        let canvas = app.otherElements.matching(identifier: "canvas.surface").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: timeout), "Missing required accessibility identifier 'canvas.surface'")
        return canvas
    }

    private func tapCanvas(at normalizedOffset: CGVector) {
        guard normalizedOffset.dx.isFinite, normalizedOffset.dy.isFinite else {
            XCTFail("Canvas tap received non-finite offset: \(normalizedOffset)")
            return
        }

        let clampedOffset = CGVector(
            dx: min(max(normalizedOffset.dx, 0.02), 0.98),
            dy: min(max(normalizedOffset.dy, 0.02), 0.98)
        )

        _ = canvasSurfaceElement(timeout: 8)

        guard let interactionFrame = canvasInteractionFrame(timeout: 3) else {
            XCTFail("Canvas interaction frame never became finite before tap")
            return
        }

        let target = CGVector(
            dx: interactionFrame.minX + (interactionFrame.width * clampedOffset.dx),
            dy: interactionFrame.minY + (interactionFrame.height * clampedOffset.dy)
        )

        guard target.dx.isFinite, target.dy.isFinite else {
            XCTFail("Canvas tap resolved to non-finite screen target: \(target)")
            return
        }

        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(target)
            .tap()
    }

    private func canvasInteractionFrame(timeout: TimeInterval) -> CGRect? {
        let deadline = Date().addingTimeInterval(timeout)
        let canvas = canvasSurfaceElement(timeout: timeout)

        while Date() < deadline {
            let frame = canvas.frame
            if frame.minX.isFinite,
               frame.minY.isFinite,
               frame.width.isFinite,
               frame.height.isFinite,
               frame.width > 40,
               frame.height > 40 {
                return frame
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        // XCUITest can transiently report CGRect.null for the transparent SwiftUI
        // accessibility anchor even while the editor is visible and interactive.
        // Reconstruct the canvas from the app window and the fixed Java-parity chrome
        // dimensions instead of failing an otherwise valid interaction.
        let windowFrame = app.windows.firstMatch.frame
        guard windowFrame.minX.isFinite,
              windowFrame.minY.isFinite,
              windowFrame.width.isFinite,
              windowFrame.height.isFinite,
              windowFrame.width > 200,
              windowFrame.height > 200 else {
            return nil
        }

        let paletteWidth: CGFloat = 152
        let mainMenuHeight: CGFloat = 63
        let configurationStripHeight: CGFloat = 76
        let fallbackFrame = CGRect(
            x: windowFrame.minX + paletteWidth,
            y: windowFrame.minY + mainMenuHeight,
            width: windowFrame.width - paletteWidth,
            height: windowFrame.height - mainMenuHeight - configurationStripHeight
        )

        guard fallbackFrame.width > 40, fallbackFrame.height > 40 else {
            return nil
        }
        return fallbackFrame
    }

    private func openRuntimeDevice(at normalizedOffset: CGVector) {
        tapCanvas(at: normalizedOffset)
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

        let openedDiagnostic = label(for: "debug.openedRuntimeDevice")
        guard let openedDeviceID = firstUUID(in: openedDiagnostic) else {
            XCTFail("Opening runtime device should populate debug.openedRuntimeDevice, found '\(openedDiagnostic)'")
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

    private func closeRuntimeDeviceSheet() {
        let sheet = app.otherElements["runtime.device.sheet"]
        tapButton("runtime.device.close")
        waitForElementToDisappear(sheet, timeout: 3, identifier: "runtime.device.sheet")
        waitForDiagnosticContains("debug.openedRuntimeDevice", expectedSubstring: "none", timeout: 3)
        assertDiagnosticContains("debug.openedRuntimeDevice", expectedSubstring: "none")
    }

    private func configureSelectedDesignDevice(ip: String, subnet: String) {
        tapButton("design.configuration.open")
        replaceValidatedDesignField("design.configuration.ip", with: ip)
        replaceValidatedDesignField("design.configuration.mask", with: subnet)
        tapButton("design.configuration.save")
        tapButton("design.configuration.close")
    }

    private func replaceValidatedDesignField(_ identifier: String, with text: String) {
        let field = requireElement(app.textFields[identifier], named: identifier)
        // Direct coordinate taps avoid XCTest's unreliable AX scroll-to-visible action
        // for fields already visible inside the regular-width configuration inspector.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 64))
        field.typeText(text)
    }

    private func executeCommand(_ command: String) {
        ensureCommandPromptInstalled()
        replaceTextField("runtime.device.command", with: command)
        tapButton("runtime.device.execute")
    }

    private func ensureCommandPromptInstalled() {
        let commandField = app.textFields["runtime.device.command"]
        if commandField.exists {
            _ = revealRuntimeSheetElement(
                commandField,
                named: "runtime.device.command",
                towardTop: false
            )
            return
        }

        let installerButton = app.buttons["runtime.device.install.open"]
        _ = revealRuntimeSheetElement(
            installerButton,
            named: "runtime.device.install.open",
            towardTop: true
        )

        let launchButton = app.buttons["runtime.device.launch.commandPrompt"]
        if !launchButton.exists {
            tapButton("runtime.device.install.open")
            let installButton = revealRuntimeSheetElement(
                app.buttons["runtime.device.install.commandPrompt"],
                named: "runtime.device.install.commandPrompt",
                towardTop: false
            )
            installButton.tap()
        }

        _ = revealRuntimeSheetElement(
            launchButton,
            named: "runtime.device.launch.commandPrompt",
            towardTop: true
        )
        launchButton.tap()
        waitForDiagnosticContains(
            "debug.openedRuntimeProgram",
            expectedSubstring: "commandPrompt",
            timeout: 4
        )
        _ = revealRuntimeSheetElement(
            commandField,
            named: "runtime.device.command",
            towardTop: false
        )
    }

    @discardableResult
    private func revealRuntimeSheetElement(
        _ element: XCUIElement,
        named identifier: String,
        towardTop: Bool,
        maximumSwipes: Int = 6
    ) -> XCUIElement {
        if element.exists, element.isHittable {
            return element
        }

        for _ in 0..<maximumSwipes where !element.exists || !element.isHittable {
            if towardTop {
                runtimeSheetGestureSurface().swipeDown()
            } else {
                runtimeSheetGestureSurface().swipeUp()
            }
        }

        XCTAssertTrue(element.exists, "Runtime device sheet never exposed '\(identifier)' after bounded scrolling")
        XCTAssertTrue(element.isHittable, "Runtime device sheet control '\(identifier)' never became hittable")
        return element
    }

    private func replaceTextField(_ identifier: String, with text: String) {
        let field = requireElement(app.textFields[identifier], named: identifier)
        field.tap()

        if let currentValue = field.value as? String, !currentValue.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count))
        }

        field.typeText(text)
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

    private func seedReachableTwoPcTopology() {
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.25, dy: 0.30))
        configureSelectedDesignDevice(ip: "192.168.10.10", subnet: "255.255.255.0")

        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.70, dy: 0.30))
        configureSelectedDesignDevice(ip: "192.168.10.11", subnet: "255.255.255.0")

        tapButton("palette.tool.place.switch")
        tapCanvas(at: CGVector(dx: 0.48, dy: 0.62))

        waitForDiagnosticContains("debug.nodeCount", expectedSubstring: "Nodes: 3", timeout: 3)

        connectNodes(
            from: CGVector(dx: 0.25, dy: 0.30),
            to: CGVector(dx: 0.48, dy: 0.62),
            expectedLinkCount: 1
        )

        connectNodes(
            from: CGVector(dx: 0.70, dy: 0.30),
            to: CGVector(dx: 0.48, dy: 0.62),
            expectedLinkCount: 2
        )
    }

    private func connectNodes(
        from source: CGVector,
        to destination: CGVector,
        expectedLinkCount: Int
    ) {
        tapButton("palette.tool.select")
        tapButton("palette.tool.connect")

        tapCanvas(at: source)
        selectFirstAvailableConnectionPort()

        tapCanvas(at: destination)
        selectFirstAvailableConnectionPort()

        waitForDiagnosticContains(
            "debug.linkCount",
            expectedSubstring: "Links: \(expectedLinkCount)",
            timeout: 3
        )
        assertDiagnosticContains("debug.linkCount", expectedSubstring: "Links: \(expectedLinkCount)")
    }

    private func selectFirstAvailableConnectionPort() {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "connection.port.")
        let portButton = app.buttons.matching(predicate).firstMatch
        _ = requireElement(portButton, named: "connection.port.*")
        XCTAssertTrue(portButton.isEnabled, "Connection port picker must expose an enabled port")
        portButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        waitForElementToDisappear(portButton, timeout: 5, identifier: "connection.port.*")
    }

    private func firstUUID(in label: String) -> UUID? {
        label
            .split { $0.isWhitespace }
            .lazy
            .compactMap { UUID(uuidString: String($0)) }
            .first
    }
}
