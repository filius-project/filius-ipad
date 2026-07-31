import CoreGraphics
import Foundation
import XCTest

final class TopologyRuntimeServiceAppParityUITests: XCTestCase {
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
        _ = requireDiagnosticElement("debug.lastRuntimeFault")
        _ = requireDiagnosticElement("debug.openedRuntimeDevice")
        _ = requireDiagnosticElement("debug.openedRuntimeProgram")
    }

    override func tearDownWithError() throws {
        retainFailureEvidence()
        app?.terminate()
        app = nil
    }

    private func retainFailureEvidence() {
        guard testRun?.failureCount ?? 0 > 0, let app else { return }

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Failure screenshot"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Failure accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    func testDNSServiceInstallLaunchUseAndClosePublishesDeterministicDiagnostics() {
        seedSinglePCRuntimeSheet(ip: "10.12.0.53", subnet: "255.255.255.0")
        installProgramIfNeeded(.dnsServer)
        launchProgram(.dnsServer)

        let shellIdentifier = "runtime.device.appShell.dnsServer"
        _ = requireElement(app.otherElements[shellIdentifier], named: shellIdentifier)

        tapButton("runtime.device.app.dns.lifecycle")
        waitForDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "dnsServerStarted", timeout: 4)
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "none")

        setTextField("runtime.device.app.dns.hostname", to: "service.lab")
        setTextField("runtime.device.app.dns.targetIP", to: "10.12.0.44")
        tapButton("runtime.device.app.dns.add")
        waitForDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "dnsRecordRegistered", timeout: 4)
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "none")

        setTextField("runtime.device.app.dns.lookupHost", to: "service.lab")
        tapButton("runtime.device.app.dns.resolve")
        waitForDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "dnsServerMissing", timeout: 4)
        assertDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "dnsResolveRejectedMissingServerConfiguration")

        setTextField("runtime.device.app.dns.hostname", to: "missing.lab")
        tapButton("runtime.device.app.dns.remove")
        waitForDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "dnsRecordRejectedUnknownHost", timeout: 4)
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "dnsUnknownHost")

        tapButton("runtime.device.app.dns.lifecycle")
        waitForDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "dnsServerStopped", timeout: 4)
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "none")

        closeRuntimeProgram(shellIdentifier)
        assertDiagnosticContains("debug.openedRuntimeProgram", expectedSubstring: "none")
    }

    func testDHCPServiceMalformedAndBoundaryFlowsRemainInspectable() {
        seedSinglePCRuntimeSheet()
        installProgramIfNeeded(.dhcpServer)
        launchProgram(.dhcpServer)

        let shellIdentifier = "runtime.device.appShell.dhcpServer"
        _ = requireElement(app.otherElements[shellIdentifier], named: shellIdentifier)

        // The DHCP server app exposes its lease/configuration action through the
        // dedicated configuration dialog. The old test targeted controls that
        // belonged to the pre-S04 placeholder shell and are no longer rendered.
        tapButton("runtime.device.app.dhcp.configure")
        _ = requireElement(
            app.descendants(matching: .any).matching(identifier: "runtime.device.dhcp.dialog").firstMatch,
            named: "runtime.device.dhcp.dialog"
        )
        setTextField("runtime.device.dhcp.dialog.lowerBound", to: "10.22.0.10")
        setTextField("runtime.device.dhcp.dialog.upperBound", to: "10.22.0.20")
        tapSwitch("runtime.device.dhcp.dialog.active")
        tapButton("runtime.device.dhcp.dialog")

        waitForDiagnosticContains(
            "debug.lastRuntimeEvent",
            expectedSubstring: "runtimeDHCPServerConfigurationSaved",
            timeout: 4
        )
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "none")
        XCTAssertTrue(
            app.staticTexts["runtime.device.app.dhcp.status"].label.contains("No active DHCP lease"),
            "DHCP server configuration should not fabricate a lease before a client requests one"
        )

        closeRuntimeProgram(shellIdentifier)
        assertDiagnosticContains("debug.openedRuntimeProgram", expectedSubstring: "none")
    }

    func testWebAndEchoLifecycleParitySupportsBoundaryAndQuickSwitchWorkflows() {
        seedSinglePCRuntimeSheet()
        installProgramIfNeeded(.webServer)
        installProgramIfNeeded(.echoServer)

        launchProgram(.webServer)
        let webShellIdentifier = "runtime.device.appShell.webServer"
        _ = requireElement(app.otherElements[webShellIdentifier], named: webShellIdentifier)

        setTextField("runtime.device.app.web.port", to: "70000")
        tapButton("runtime.device.app.web.start")
        waitForDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "webServerRejectedInvalidConfiguration", timeout: 4)
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "invalidWebServerPort")

        setTextField("runtime.device.app.web.port", to: "8080")
        tapButton("runtime.device.app.web.start")
        waitForDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "webServerStarted", timeout: 4)
        assertDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "port=8080")

        tapButton("runtime.device.app.web.start")
        waitForDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "webServerStartIgnoredAlreadyRunning", timeout: 4)

        tapButton("runtime.device.app.web.stop")
        waitForDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "webServerStopped", timeout: 4)

        tapButton("runtime.device.app.web.stop")
        waitForDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "webServerStopIgnoredAlreadyStopped", timeout: 4)
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "none")

        closeRuntimeProgram(webShellIdentifier)

        launchProgram(.echoServer)
        let echoShellIdentifier = "runtime.device.appShell.echoServer"
        _ = requireElement(app.otherElements[echoShellIdentifier], named: echoShellIdentifier)

        setTextField("runtime.device.app.echo.port", to: "7001")
        tapButton("runtime.device.app.echo.start")
        waitForDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "echoServerStarted", timeout: 4)
        assertDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "port=7001")

        tapButton("runtime.device.app.echo.start")
        waitForDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "echoServerStartIgnoredAlreadyRunning", timeout: 4)

        tapButton("runtime.device.app.echo.stop")
        waitForDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "echoServerStopped", timeout: 4)

        tapButton("runtime.device.app.echo.stop")
        waitForDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "echoServerStopIgnoredAlreadyStopped", timeout: 4)
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "none")

        closeRuntimeProgram(echoShellIdentifier)
        assertDiagnosticContains("debug.openedRuntimeProgram", expectedSubstring: "none")
    }

    func testServiceProgramLaunchRemainsDesktopGatedUntilInstallCompletes() {
        seedSinglePCRuntimeSheet()

        for program in TopologyRuntimeServiceProgramFixture.allCases {
            XCTAssertFalse(
                app.buttons["runtime.device.launch.\(program.rawValue)"].waitForExistence(timeout: 1),
                "\(program.rawValue) launch icon must remain hidden until install"
            )
        }

        installProgramIfNeeded(.dnsServer)
        _ = requireElement(app.buttons["runtime.device.launch.dnsServer"], named: "runtime.device.launch.dnsServer")
        assertDiagnosticContains("debug.openedRuntimeProgram", expectedSubstring: "none")
    }

    // MARK: - Helpers

    private func seedSinglePCRuntimeSheet(
        ip: String = "192.168.0.10",
        subnet: String = "255.255.255.0"
    ) {
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.40, dy: 0.35))
        configureSelectedDesignDevice(ip: ip, subnet: subnet)

        tapButton("runtime.control.start")
        waitForDiagnosticContains("debug.simulationPhase", expectedSubstring: "running", timeout: 4)

        tapCanvas(at: CGVector(dx: 0.40, dy: 0.35))
        requireRuntimeDeviceSheetOpen()
    }

    private func configureSelectedDesignDevice(ip: String, subnet: String) {
        tapButton("design.configuration.open")
        setTextField("design.configuration.ip", to: ip)
        setTextField("design.configuration.mask", to: subnet)
        tapButton("design.configuration.save")
        tapButton("design.configuration.close")
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

    private func installProgramIfNeeded(_ program: TopologyRuntimeServiceProgramFixture) {
        let launchIdentifier = "runtime.device.launch.\(program.rawValue)"
        let launchButton = app.buttons.matching(identifier: launchIdentifier).firstMatch
        if revealRuntimeSheetElementIfPresent(launchButton, towardTop: true) { return }

        // Installing one program leaves the installer expanded. Tapping the
        // desktop installer icon unconditionally would collapse it before the
        // next program is installed, making the next install action disappear.
        let installerSection = app.otherElements["runtime.device.installer"]
        if !installerSection.exists {
            tapRuntimeSheetButton("runtime.device.install.open", towardTop: true)
        }

        let installIdentifier = "runtime.device.install.\(program.rawValue)"
        tapRuntimeSheetButton(installIdentifier, towardTop: false)
        waitForDiagnosticContains(
            "debug.lastRuntimeEvent",
            expectedSubstring: "runtimeProgramInstalled",
            timeout: 4
        )
        _ = revealRuntimeSheetElement(launchButton, named: launchIdentifier, towardTop: true)
    }

    private func launchProgram(_ program: TopologyRuntimeServiceProgramFixture) {
        tapRuntimeSheetButton("runtime.device.launch.\(program.rawValue)", towardTop: true)
        waitForDiagnosticContains("debug.openedRuntimeProgram", expectedSubstring: program.rawValue, timeout: 4)
        _ = revealRuntimeSheetElement(
            app.otherElements["runtime.device.appShell.\(program.rawValue)"],
            named: "runtime.device.appShell.\(program.rawValue)",
            towardTop: false
        )
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

    private func revealRuntimeSheetElementIfPresent(_ element: XCUIElement, towardTop: Bool) -> Bool {
        guard element.exists else { return false }
        for _ in 0..<8 where !element.isHittable {
            scrollRuntimeSheet(toward: element, fallbackTowardTop: towardTop)
        }
        return element.exists
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

    private func setTextField(_ identifier: String, to value: String) {
        let query = app.textFields[identifier]
        let isDHCPDialogField = identifier.hasPrefix("runtime.device.dhcp.dialog.")
        let field = identifier.hasPrefix("runtime.device.") && !isDHCPDialogField
            ? revealRuntimeSheetElement(query, named: identifier, towardTop: false)
            : requireElement(query, named: identifier)
        if identifier.hasPrefix("design.configuration.") {
            // Direct coordinate taps avoid XCTest's unreliable AX scroll-to-visible action
            // for fields already visible inside the regular-width configuration inspector.
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else {
            field.tap()
        }

        // Validated SwiftUI fields expose a validation state (for example,
        // "valid"/"invalid") as their accessibility value rather than the
        // editable text. Send a bounded delete sequence instead of using that
        // state as a character count, otherwise stale/default text survives.
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 64))
        field.typeText(value)
        dismissKeyboardIfPresent()
    }

    private func dismissKeyboardIfPresent() {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }

        for label in ["Done", "Return", "Hide keyboard", "Hide Keyboard"] {
            let button = keyboard.buttons[label]
            if button.exists, button.isHittable {
                button.tap()
                return
            }
        }

        // iPad keyboard snapshots can briefly expose a zero-height keyboard whose
        // Return key exists but cannot complete an accessibility scroll action.
        // Move focus to the stable sheet chrome instead of tapping that stale key.
        let sheet = app.otherElements["runtime.device.sheet"]
        if sheet.exists {
            sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        }
    }

    private func waitForStaticTextContaining(_ substring: String, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let match = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", substring)).firstMatch
            if match.exists {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Timed out waiting for visible static text containing '\(substring)'")
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
        if direct.waitForExistence(timeout: min(timeout, 2)) {
            return direct
        }

        if let fallbackLabel = controlLabelFallback(for: identifier) {
            let fallback = app.buttons.matching(NSPredicate(format: "label == %@", fallbackLabel)).firstMatch
            if fallback.waitForExistence(timeout: 2) {
                return fallback
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
        case "design.configuration.open":
            return "Configure"
        case "runtime.device.install.open":
            return "Installer"
        case "runtime.device.app.close":
            return "Back to Desktop"
        case "runtime.device.launch.webServer":
            return "Web Server"
        case "runtime.device.launch.echoServer":
            return "Echo Server"
        case "runtime.device.launch.dnsServer":
            return "DNS Server"
        case "runtime.device.launch.dhcpServer":
            return "DHCP Server"
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
        case "debug.lastRuntimeFault":
            return "Last runtime fault:"
        case "debug.openedRuntimeProgram":
            return "Opened runtime program:"
        default:
            return nil
        }
    }

    private func tapSwitch(_ identifier: String) {
        let toggle = requireElement(app.switches[identifier], named: identifier)
        XCTAssertTrue(toggle.isEnabled, "Switch '\(identifier)' must be enabled before tapping")
        toggle.tap()
    }

    private func tapButton(_ identifier: String) {
        let button: XCUIElement
        let isDHCPDialogButton = identifier.hasPrefix("runtime.device.dhcp.dialog.")
        if identifier.hasPrefix("runtime.device.") && !isDHCPDialogButton {
            button = revealRuntimeSheetElement(app.buttons.matching(identifier: identifier).firstMatch, named: identifier, towardTop: false)
        } else {
            button = requireControl(identifier)
        }
        XCTAssertTrue(button.isEnabled, "Button '\(identifier)' must be enabled before tapping")
        if identifier.hasPrefix("palette.")
            || identifier.hasPrefix("runtime.control.")
            || identifier.hasPrefix("runtime.device.") {
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

    private func closeRuntimeProgram(_ shellIdentifier: String) {
        let shell = app.otherElements[shellIdentifier]

        // Dynamic SwiftUI sheet content can occasionally consume the first synthesized tap while
        // the app shell is settling after a dialog closes. Retry the idempotent close action, and
        // only continue once the shell has actually been removed from the accessibility tree.
        for _ in 0..<3 {
            if !shell.exists {
                return
            }

            let closeButton = app.buttons["runtime.device.app.close"]
            if closeButton.exists {
                tapRuntimeSheetButton("runtime.device.app.close", towardTop: true)
            }
            if waitForElementToDisappear(shell, timeout: 2) {
                return
            }
        }

        XCTFail("Timed out waiting for '\(shellIdentifier)' to disappear after closing the runtime app")
    }

    private func waitForElementToDisappear(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if !element.exists {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return !element.exists
    }
}

private enum TopologyRuntimeServiceProgramFixture: String, CaseIterable {
    case webServer
    case echoServer
    case dnsServer
    case dhcpServer
}
