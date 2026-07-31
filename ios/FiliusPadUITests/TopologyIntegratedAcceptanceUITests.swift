import CoreGraphics
import Foundation
import XCTest

final class TopologyIntegratedAcceptanceUITests: XCTestCase {
    private enum CanvasPoint {
        static let pc1 = CGVector(dx: 0.12, dy: 0.20)
        static let pc2 = CGVector(dx: 0.22, dy: 0.20)
        static let pc3 = CGVector(dx: 0.32, dy: 0.20)
        static let pc4 = CGVector(dx: 0.62, dy: 0.20)
        static let pc5 = CGVector(dx: 0.72, dy: 0.20)
        static let pc6 = CGVector(dx: 0.82, dy: 0.20)

        static let switch1 = CGVector(dx: 0.22, dy: 0.55)
        static let switch2 = CGVector(dx: 0.42, dy: 0.55)
        static let switch3 = CGVector(dx: 0.62, dy: 0.55)
        static let switch4 = CGVector(dx: 0.78, dy: 0.55)

        static let runtimeDepthPCs: [CGVector] = [
            CGVector(dx: 0.08, dy: 0.18),
            CGVector(dx: 0.16, dy: 0.18),
            CGVector(dx: 0.24, dy: 0.18),
            CGVector(dx: 0.32, dy: 0.18),
            CGVector(dx: 0.40, dy: 0.18),
            CGVector(dx: 0.48, dy: 0.18),
            CGVector(dx: 0.56, dy: 0.18),
            CGVector(dx: 0.64, dy: 0.18),
            CGVector(dx: 0.72, dy: 0.18),
            CGVector(dx: 0.80, dy: 0.18)
        ]

        static let runtimeDepthSwitches: [CGVector] = [
            CGVector(dx: 0.08, dy: 0.62),
            CGVector(dx: 0.16, dy: 0.62),
            CGVector(dx: 0.24, dy: 0.62),
            CGVector(dx: 0.32, dy: 0.62),
            CGVector(dx: 0.40, dy: 0.62),
            CGVector(dx: 0.48, dy: 0.62),
            CGVector(dx: 0.56, dy: 0.62),
            CGVector(dx: 0.64, dy: 0.62),
            CGVector(dx: 0.72, dy: 0.62),
            CGVector(dx: 0.80, dy: 0.62)
        ]
    }

    private var app: XCUIApplication!
    private var autosaveFileURLs: [URL] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil

        for fileURL in autosaveFileURLs {
            try? FileManager.default.removeItem(at: fileURL)
        }
        autosaveFileURLs.removeAll()
    }

    func testIntegratedClassroomFlowWithDiagnosticsAndRelaunchContinuity() {
        let autosaveURL = makeAutosaveURL()

        app = launchApp(
            autosaveURL: autosaveURL,
            clearExistingAutosave: true,
            additionalArguments: ["-ui-testing"]
        )

        seedTenNodeClassroomTopology()

        assertDiagnosticEquals("debug.nodeCount", expected: "Nodes: 10")
        assertDiagnosticEquals("debug.linkCount", expected: "Links: 9")

        tapButton("runtime.control.start")
        waitForDiagnosticContains("debug.simulationPhase", expectedSubstring: "running", timeout: 3)
        assertRuntimeControlState(startEnabled: false, stopEnabled: true)

        assertRuntimeControlsRemainResponsiveAtScale(scaleDescriptor: "~10-node")

        // Boundary condition: repeated runtime sheet open/close under ~10-node load.
        openRuntimeDevice(at: CanvasPoint.pc1)
        closeRuntimeDeviceSheet()
        openRuntimeDevice(at: CanvasPoint.pc2)
        closeRuntimeDeviceSheet()
        openRuntimeDevice(at: CanvasPoint.pc3)
        closeRuntimeDeviceSheet()

        openRuntimeDevice(at: CanvasPoint.pc1)

        executeCommand("ping 10.1.0.11")
        waitForDiagnosticContains("debug.lastPingEvent", expectedSubstring: "pingSucceeded", timeout: 3)
        assertDiagnosticContains("debug.lastPingFault", expectedSubstring: "none")
        assertAnyConsoleLineContains("64 bytes from 10.1.0.11: icmp_seq=1")

        // Negative test: invalid/unreachable target path must expose deterministic failure diagnostics.
        executeCommand("ping 10.1.0.250")
        waitForDiagnosticContains("debug.lastPingEvent", expectedSubstring: "pingRejectedUnknownTarget", timeout: 3)
        assertDiagnosticContains("debug.lastPingFault", expectedSubstring: "pingTargetUnknown")
        assertAnyConsoleLineContains("Ping failed: pingTargetUnknown")

        // Negative test: malformed command must expose deterministic malformed diagnostics.
        executeCommand("ping")
        waitForDiagnosticContains("debug.lastPingEvent", expectedSubstring: "pingRejectedMalformedCommand", timeout: 3)
        assertDiagnosticContains("debug.lastPingFault", expectedSubstring: "malformedPingCommand")
        assertAnyConsoleLineContains("Ping failed: malformedPingCommand")

        assertRuntimeConsoleCount(atLeast: 6)
        closeRuntimeDeviceSheet()

        waitForDiagnosticNotContaining("debug.lastPersistenceSaveAt", forbiddenSubstring: "none", timeout: 6)
        let lastPersistenceSaveMarker = label(for: "debug.lastPersistenceSaveAt")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: autosaveURL.path),
            "Autosave fixture path should exist after integrated edits and runtime configuration"
        )

        app.terminate()

        app = launchApp(
            autosaveURL: autosaveURL,
            clearExistingAutosave: false,
            additionalArguments: ["-ui-testing"]
        )

        assertDiagnosticEquals("debug.nodeCount", expected: "Nodes: 10")
        waitForDiagnosticNotContaining("debug.lastPersistenceLoadAt", forbiddenSubstring: "none", timeout: 4)
        assertDiagnosticContains("debug.lastPersistenceLoadAt", expectedSubstring: "T")
        assertDiagnosticContains("debug.lastPersistenceError", expectedSubstring: "none")
        assertDiagnosticContains("debug.lastPersistenceSaveAt", expectedSubstring: "T")
        let restoredPersistenceSaveMarker = label(for: "debug.lastPersistenceSaveAt")
        XCTAssertGreaterThanOrEqual(
            restoredPersistenceSaveMarker,
            lastPersistenceSaveMarker,
            "Relaunch should restore the latest autosave timestamp; the persisted save may finish after the pre-termination diagnostic is sampled"
        )

        tapButton("runtime.control.start")
        waitForDiagnosticContains("debug.simulationPhase", expectedSubstring: "running", timeout: 3)

        openRuntimeDevice(at: CanvasPoint.pc1)
        assertReadOnlyRuntimeNetworkInfo(ip: "10.1.0.10", subnet: "255.255.255.0")

        executeCommand("ping 10.1.0.11")
        waitForDiagnosticContains("debug.lastPingEvent", expectedSubstring: "pingSucceeded", timeout: 3)
        assertDiagnosticContains("debug.lastPingFault", expectedSubstring: "none")
        assertAnyConsoleLineContains("64 bytes from 10.1.0.11: icmp_seq=1")
        assertRuntimeConsoleCount(atLeast: 2)

        closeRuntimeDeviceSheet()
    }

    func testTwentyNodeRuntimeDepthTraceContractsRemainDeterministic() {
        let phaseTag = "[M002/S03/T03 tests]"
        let autosaveURL = makeAutosaveURL()

        app = launchApp(
            autosaveURL: autosaveURL,
            clearExistingAutosave: true,
            additionalArguments: ["-ui-testing"]
        )

        seedTwentyNodeRuntimeDepthTopology()

        let sourcePoint = CanvasPoint.runtimeDepthPCs[0]
        let targetPoint = CanvasPoint.runtimeDepthSwitches[0]

        XCTAssertEqual(label(for: "debug.nodeCount"), "Nodes: 20", "\(phaseTag) expected deterministic 20-node fixture")
        XCTAssertEqual(label(for: "debug.linkCount"), "Links: 19", "\(phaseTag) expected deterministic 19-link chain")

        tapButton("runtime.control.start")
        waitForDiagnosticContains("debug.simulationPhase", expectedSubstring: "running", timeout: 3)
        assertRuntimeControlState(startEnabled: false, stopEnabled: true)

        assertRuntimeControlsRemainResponsiveAtScale(scaleDescriptor: "~20-node")

        openRuntimeDevice(at: sourcePoint)
        executeCommand("trace 10.2.0.20")

        waitForDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "traceSucceeded", timeout: 3)
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "command=trace")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "targetIP=10.2.0.20")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "hops=19")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "latencyMs=78")
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "none")

        assertAnyConsoleLineContains("Trace to 10.2.0.20 succeeded (hops=19, latencyMs=78)")
        assertAnyConsoleLineContains("Path: ")
        assertRuntimeConsoleCount(atLeast: 3)

        closeRuntimeDeviceSheet()
    }

    // MARK: - Helpers

    @discardableResult
    private func launchApp(
        autosaveURL: URL,
        clearExistingAutosave: Bool,
        additionalArguments: [String]
    ) -> XCUIApplication {
        if clearExistingAutosave, FileManager.default.fileExists(atPath: autosaveURL.path) {
            try? FileManager.default.removeItem(at: autosaveURL)
        }

        if !autosaveFileURLs.contains(autosaveURL) {
            autosaveFileURLs.append(autosaveURL)
        }

        let launchedApp = XCUIApplication()
        launchedApp.launchArguments += additionalArguments
        launchedApp.launchEnvironment["FILIUSPAD_AUTOSAVE_FILE"] = autosaveURL.path
        launchedApp.launch()
        self.app = launchedApp

        _ = canvasSurfaceElement(timeout: 8)

        return launchedApp
    }

    private func seedTenNodeClassroomTopology() {
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CanvasPoint.pc1)
        configureSelectedDesignDevice(ip: "10.1.0.10", subnet: "255.255.255.0")
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CanvasPoint.pc2)
        configureSelectedDesignDevice(ip: "10.1.0.11", subnet: "255.255.255.0")
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CanvasPoint.pc3)
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CanvasPoint.pc4)
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CanvasPoint.pc5)
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CanvasPoint.pc6)

        tapButton("palette.tool.place.switch")
        tapCanvas(at: CanvasPoint.switch1)
        tapButton("palette.tool.place.switch")
        tapCanvas(at: CanvasPoint.switch2)
        tapButton("palette.tool.place.switch")
        tapCanvas(at: CanvasPoint.switch3)
        tapButton("palette.tool.place.switch")
        tapCanvas(at: CanvasPoint.switch4)

        connectNodes(from: CanvasPoint.pc1, to: CanvasPoint.switch1, expectedLinkCount: 1)
        connectNodes(from: CanvasPoint.pc2, to: CanvasPoint.switch1, expectedLinkCount: 2)
        connectNodes(from: CanvasPoint.pc3, to: CanvasPoint.switch1, expectedLinkCount: 3)
        connectNodes(from: CanvasPoint.pc4, to: CanvasPoint.switch4, expectedLinkCount: 4)
        connectNodes(from: CanvasPoint.pc5, to: CanvasPoint.switch4, expectedLinkCount: 5)
        connectNodes(from: CanvasPoint.pc6, to: CanvasPoint.switch4, expectedLinkCount: 6)
        connectNodes(from: CanvasPoint.switch1, to: CanvasPoint.switch2, expectedLinkCount: 7)
        connectNodes(from: CanvasPoint.switch2, to: CanvasPoint.switch3, expectedLinkCount: 8)
        connectNodes(from: CanvasPoint.switch3, to: CanvasPoint.switch4, expectedLinkCount: 9)
    }

    private func seedTwentyNodeRuntimeDepthTopology() {
        let sourcePoint = CanvasPoint.runtimeDepthPCs[0]
        let targetPoint = CanvasPoint.runtimeDepthSwitches[0]
        let topTransitPoints = Array(CanvasPoint.runtimeDepthPCs.dropFirst())
        let bottomTransitPoints = Array(CanvasPoint.runtimeDepthSwitches.dropFirst().reversed())
        let transitPoints = topTransitPoints + bottomTransitPoints
        let chainPoints = [sourcePoint] + transitPoints + [targetPoint]

        tapButton("palette.tool.place.pc")
        tapCanvas(at: sourcePoint)
        configureSelectedDesignDevice(ip: "10.2.0.10", subnet: "255.255.255.0")
        tapButton("palette.tool.place.pc")
        tapCanvas(at: targetPoint)
        configureSelectedDesignDevice(ip: "10.2.0.20", subnet: "255.255.255.0")

        for point in transitPoints {
            tapButton("palette.tool.place.switch")
            tapCanvas(at: point)
        }

        for index in 1..<chainPoints.count {
            connectNodes(
                from: chainPoints[index - 1],
                to: chainPoints[index],
                expectedLinkCount: index
            )
        }
    }

    private func assertRuntimeControlsRemainResponsiveAtScale(scaleDescriptor: String) {
        let runningTick = simulationTickValue()
        let advancedTick = waitForTickAdvance(from: runningTick, timeout: 2)
        XCTAssertGreaterThan(
            advancedTick,
            runningTick,
            "Simulation tick should advance while running at \(scaleDescriptor)"
        )

        tapButton("runtime.control.stop")
        waitForDiagnosticContains("debug.simulationPhase", expectedSubstring: "stopped", timeout: 3)
        assertRuntimeControlState(startEnabled: true, stopEnabled: false)

        let stoppedTick = simulationTickValue()
        pause(seconds: 0.5)
        XCTAssertEqual(simulationTickValue(), stoppedTick, "Simulation tick should remain frozen while stopped")

        tapButton("runtime.control.start")
        waitForDiagnosticContains("debug.simulationPhase", expectedSubstring: "running", timeout: 3)
        assertRuntimeControlState(startEnabled: false, stopEnabled: true)

        let resumedTick = waitForTickAdvance(from: stoppedTick, timeout: 2)
        XCTAssertGreaterThan(resumedTick, stoppedTick, "Simulation tick should resume after restarting runtime")
    }

    private func connectNodes(
        from source: CGVector,
        to destination: CGVector,
        expectedLinkCount: Int
    ) {
        tapButton("palette.tool.select")
        tapButton("palette.tool.connect")

        presentConnectionPortPicker(at: source)
        selectFirstAvailableConnectionPort()

        presentConnectionPortPicker(at: destination)
        selectFirstAvailableConnectionPort()

        waitForDiagnosticContains(
            "debug.linkCount",
            expectedSubstring: "Links: \(expectedLinkCount)",
            timeout: 3
        )
        assertDiagnosticEquals("debug.linkCount", expected: "Links: \(expectedLinkCount)")
    }

    private func presentConnectionPortPicker(at normalizedOffset: CGVector) {
        let picker = app.descendants(matching: .any)
            .matching(identifier: "connection.portPicker")
            .firstMatch

        // A newly dismissed SwiftUI sheet can briefly consume the next canvas tap. Retry the
        // idempotent node selection until the next port picker is actually presented.
        for _ in 0..<3 {
            tapCanvas(at: normalizedOffset)
            if picker.waitForExistence(timeout: 3) {
                return
            }
        }

        XCTFail("Connection port picker did not appear after tapping the node")
    }

    private func selectFirstAvailableConnectionPort() {
        let picker = requireElement(
            app.descendants(matching: .any)
                .matching(identifier: "connection.portPicker")
                .firstMatch,
            named: "connection.portPicker",
            timeout: 8
        )
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "connection.port.")
        let portButton = app.buttons.matching(predicate).firstMatch
        _ = requireElement(portButton, named: "connection.port.*", timeout: 8)
        XCTAssertTrue(portButton.isEnabled, "Connection port picker must expose an enabled port")
        portButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        waitForElementToDisappear(picker, timeout: 8, identifier: "connection.portPicker")
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

        guard let openedDeviceID = waitForDiagnosticUUID("debug.openedRuntimeDevice", timeout: timeout) else {
            XCTFail("Opening runtime device should populate debug.openedRuntimeDevice")
            return
        }
        guard let presentedDeviceID = firstUUID(in: sheetNodeID.label) else {
            XCTFail("Runtime device sheet node identifier did not contain a UUID: '\(sheetNodeID.label)'")
            return
        }

        XCTAssertTrue(sheet.exists, "Runtime device sheet must remain presented after diagnostics update")
        XCTAssertEqual(openedDeviceID, presentedDeviceID, "Runtime sheet and diagnostic device identifiers must agree")
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

        let ipField = requireElement(app.textFields["design.configuration.ip"], named: "design.configuration.ip")
        replaceValidatedDesignField(ipField, named: "design.configuration.ip", with: ip)
        let subnetField = requireElement(app.textFields["design.configuration.mask"], named: "design.configuration.mask")
        replaceValidatedDesignField(subnetField, named: "design.configuration.mask", with: subnet)

        tapButton("design.configuration.save")
        tapButton("design.configuration.close")
    }

    private func assertReadOnlyRuntimeNetworkInfo(ip: String, subnet: String) {
        XCTAssertFalse(app.textFields["runtime.device.ip"].exists)
        XCTAssertFalse(app.textFields["runtime.device.subnet"].exists)
        let networkButton = revealRuntimeSheetElement(
            app.buttons["runtime.workspace.network"],
            named: "runtime.workspace.network",
            towardTop: true
        )
        networkButton.tap()
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

    private func replaceValidatedDesignField(
        _ field: XCUIElement,
        named identifier: String,
        with text: String
    ) {
        XCTAssertTrue(field.exists, "Missing required accessibility identifier '\(identifier)'")
        // Direct coordinate taps avoid XCTest's unreliable AX scroll-to-visible action
        // for fields already visible inside the regular-width configuration inspector.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 64))
        field.typeText(text)
    }

    private func executeCommand(_ command: String) {
        ensureCommandPromptInstalled()
        let commandField = revealRuntimeSheetElement(
            app.textFields["runtime.device.command"],
            named: "runtime.device.command",
            towardTop: false
        )
        replaceTextField(commandField, named: "runtime.device.command", with: command)
        _ = revealRuntimeSheetElement(
            app.buttons["runtime.device.execute"],
            named: "runtime.device.execute",
            towardTop: false
        )
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
            installerButton.tap()
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

    private func assertRuntimeControlState(startEnabled: Bool, stopEnabled: Bool) {
        XCTAssertEqual(
            requireControl("runtime.control.start").isEnabled,
            startEnabled,
            "runtime.control.start enabled state mismatch"
        )
        XCTAssertEqual(
            requireControl("runtime.control.stop").isEnabled,
            stopEnabled,
            "runtime.control.stop enabled state mismatch"
        )
    }

    private func assertRuntimeConsoleCount(atLeast minimum: Int) {
        let count = diagnosticIntegerValue(
            for: "debug.runtimeConsoleCount",
            prefix: "Opened runtime console entries: "
        )

        XCTAssertNotNil(count, "Expected debug.runtimeConsoleCount to expose an integer payload")
        XCTAssertGreaterThanOrEqual(
            count ?? 0,
            minimum,
            "Expected debug.runtimeConsoleCount to be at least \(minimum)"
        )
    }

    private func assertAnyConsoleLineContains(_ expectedText: String) {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "runtime.device.console.line.")
        let lines = app.staticTexts.matching(predicate)
        let deadline = Date().addingTimeInterval(3)

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

    private func waitForDiagnosticUUID(_ identifier: String, timeout: TimeInterval) -> UUID? {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let value = firstUUID(in: label(for: identifier)) {
                return value
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return firstUUID(in: label(for: identifier))
    }

    private func waitForDiagnosticContains(
        _ identifier: String,
        expectedSubstring: String,
        timeout: TimeInterval
    ) {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if label(for: identifier).contains(expectedSubstring) {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Timed out waiting for \(identifier) to contain '\(expectedSubstring)'")
    }

    private func waitForDiagnosticNotContaining(
        _ identifier: String,
        forbiddenSubstring: String,
        timeout: TimeInterval
    ) {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if !label(for: identifier).contains(forbiddenSubstring) {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Timed out waiting for \(identifier) to stop containing '\(forbiddenSubstring)'")
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

    private func diagnosticIntegerValue(for identifier: String, prefix: String) -> Int? {
        let text = label(for: identifier)
        let suffix = text.replacingOccurrences(of: prefix, with: "")
        return Int(suffix)
    }

    private func pause(seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

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
        let directTimeout = min(timeout, 2)
        let directButton = app.buttons.matching(identifier: identifier).firstMatch
        if directButton.waitForExistence(timeout: directTimeout) {
            return directButton
        }

        let direct = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        if direct.waitForExistence(timeout: 1) {
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
        case "runtime.control.stop":
            return "Entwurfsmodus"
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
        case "debug.simulationTick":
            return "Simulation tick:"
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
        case "debug.runtimeConsoleCount":
            return "Opened runtime console entries:"
        case "debug.lastPersistenceSaveAt":
            return "Last persistence save:"
        case "debug.lastPersistenceLoadAt":
            return "Last persistence load:"
        case "debug.lastPersistenceError":
            return "Last persistence error:"
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
            // XCTest can transiently report an infinite frame for the transparent
            // accessibility overlay after relaunch; element-relative coordinates
            // still resolve correctly against the live canvas.
            canvasSurfaceElement().coordinate(withNormalizedOffset: clampedOffset).tap()
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

    private func replaceTextField(_ field: XCUIElement, named identifier: String, with text: String) {
        XCTAssertTrue(field.exists, "Missing required accessibility identifier '\(identifier)'")
        // Direct coordinate taps avoid XCTest's unreliable AX scroll-to-visible action
        // for fields already visible inside the regular-width configuration inspector.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        if let currentValue = field.value as? String, !currentValue.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count))
        }

        field.typeText(text)
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
        let element = requireDiagnosticElement(identifier)
        return element.label
    }

    private func firstUUID(in label: String) -> UUID? {
        label
            .split { $0.isWhitespace }
            .lazy
            .compactMap { UUID(uuidString: String($0)) }
            .first
    }

    private func makeAutosaveURL() -> URL {
        let filename = "TopologyIntegratedAcceptanceUITests-\(UUID().uuidString).json"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }
}
