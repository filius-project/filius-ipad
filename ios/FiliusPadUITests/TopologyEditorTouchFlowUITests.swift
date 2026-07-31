import Foundation
import XCTest

final class TopologyEditorTouchFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        _ = requireElement(canvasElement(), named: "canvas.surface")
        _ = requireControl("palette.tool.select")
        _ = requireControl("palette.tool.connect")
        _ = requireControl("palette.tool.place.pc")
        _ = requireControl("palette.tool.place.switch")
    }

    func testFullTouchFlowMaintainsCoherentDiagnostics() {
        assertDiagnosticEquals("debug.nodeCount", expected: "Nodes: 0")
        assertDiagnosticEquals("debug.linkCount", expected: "Links: 0")
        assertDiagnosticEquals("debug.selectedNodeCount", expected: "Selected: 0")
        assertDiagnosticEquals("debug.lastValidationError", expected: "Last error: none")

        // Place first PC.
        tapButton("palette.tool.place.pc")
        XCTAssertEqual(label(for: "debug.lastInteractionMode"), "Last interaction mode: paletteTap:place:pc")
        tapCanvas(at: CGVector(dx: 0.25, dy: 0.30))
        XCTAssertEqual(label(for: "debug.lastInteractionMode"), "Last interaction mode: canvasTap:place:pc")
        assertDiagnosticEquals("debug.nodeCount", expected: "Nodes: 1")
        assertDiagnosticEquals("debug.selectedNodeCount", expected: "Selected: 1")
        assertDiagnosticEquals("debug.activeTool", expected: "Tool: Select")

        // Place second PC.
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.65, dy: 0.30))
        assertDiagnosticEquals("debug.nodeCount", expected: "Nodes: 2")
        assertDiagnosticEquals("debug.selectedNodeCount", expected: "Selected: 1")

        // Place switch endpoint.
        tapButton("palette.tool.place.switch")
        tapCanvas(at: CGVector(dx: 0.45, dy: 0.60))
        assertDiagnosticEquals("debug.nodeCount", expected: "Nodes: 3")

        // Negative/error path: connecting a PC to itself must surface the Java parity diagnostic.
        tapButton("palette.tool.connect")
        tapCanvas(at: CGVector(dx: 0.25, dy: 0.30))
        selectFirstAvailableConnectionPort()
        tapCanvas(at: CGVector(dx: 0.25, dy: 0.30))
        selectFirstAvailableConnectionPort()
        assertDiagnosticEquals("debug.lastValidationError", expected: "Last error: A device cannot connect to itself")
        assertDiagnosticEquals("debug.linkCount", expected: "Links: 0")

        // A rejected completion retains the pending source, so a valid switch target completes it.
        tapCanvas(at: CGVector(dx: 0.45, dy: 0.60))
        selectFirstAvailableConnectionPort()
        assertDiagnosticEquals("debug.lastValidationError", expected: "Last error: none")
        assertDiagnosticEquals("debug.linkCount", expected: "Links: 1")
        assertDiagnosticEquals("debug.selectedNodeCount", expected: "Selected: 2")

        // Drag one node directly while the completed link still has both endpoints selected.
        // Starting the drag must collapse selection to the touched device instead of moving
        // the connected topology as one system.
        tapButton("palette.tool.select")
        XCTAssertEqual(label(for: "debug.lastInteractionMode"), "Last interaction mode: paletteTap:select")
        assertDiagnosticEquals("debug.selectedNodeCount", expected: "Selected: 2")
        let cameraBeforeNodeDrag = label(for: "debug.cameraOffset")
        dragOnCanvas(from: CGVector(dx: 0.45, dy: 0.60), to: CGVector(dx: 0.68, dy: 0.48))
        assertDiagnosticEquals("debug.selectedNodeCount", expected: "Selected: 1")
        XCTAssertEqual(label(for: "debug.lastAction"), "Last action: moveSelectedNodes")
        XCTAssertEqual(
            label(for: "debug.cameraOffset"),
            cameraBeforeNodeDrag,
            "Dragging a topology object must not pan the canvas beneath it"
        )

        // With no selection, dragging empty canvas pans instead of forcing a zoom-out
        // or starting a marquee selection.
        tapCanvas(at: CGVector(dx: 0.08, dy: 0.92))
        assertDiagnosticEquals("debug.selectedNodeCount", expected: "Selected: 0")
        let cameraBeforeEmptySelectionPan = label(for: "debug.cameraOffset")
        dragOnCanvas(from: CGVector(dx: 0.15, dy: 0.15), to: CGVector(dx: 0.78, dy: 0.68))
        assertDiagnosticEquals("debug.selectedNodeCount", expected: "Selected: 0")
        waitForDiagnosticChange("debug.cameraOffset", from: cameraBeforeEmptySelectionPan, timeout: 3)

        // Canvas panning remains available while a non-selection tool owns the interaction.
        tapButton("palette.tool.connect")
        let cameraBeforePan = label(for: "debug.cameraOffset")
        dragOnCanvas(from: CGVector(dx: 0.05, dy: 0.90), to: CGVector(dx: 0.05, dy: 0.70))
        waitForDiagnosticChange("debug.cameraOffset", from: cameraBeforePan, timeout: 3)

        // Boundary condition: zoom gestures should stay clamped in viewport bounds.
        let canvas = canvasElement()
        canvas.pinch(withScale: 8.0, velocity: 2.0)
        canvas.pinch(withScale: 0.02, velocity: -2.0)

        let zoom = zoomValue()
        XCTAssertGreaterThanOrEqual(zoom, 0.5)
        XCTAssertLessThanOrEqual(zoom, 4.0)
    }

    func testEmptyCanvasDragPansInEveryWorkspaceMode() {
        assertDiagnosticEquals("debug.selectedNodeCount", expected: "Selected: 0")

        let designCamera = label(for: "debug.cameraOffset")
        dragOnCanvas(from: CGVector(dx: 0.75, dy: 0.70), to: CGVector(dx: 0.55, dy: 0.50))
        waitForDiagnosticChange("debug.cameraOffset", from: designCamera, timeout: 3)

        tapButton("java.mode.documentation")
        let documentationCamera = label(for: "debug.cameraOffset")
        dragOnCanvas(from: CGVector(dx: 0.75, dy: 0.70), to: CGVector(dx: 0.55, dy: 0.50))
        waitForDiagnosticChange("debug.cameraOffset", from: documentationCamera, timeout: 3)

        tapButton("runtime.control.stop")
        tapButton("runtime.control.start")
        let simulationCamera = label(for: "debug.cameraOffset")
        dragOnCanvas(from: CGVector(dx: 0.75, dy: 0.70), to: CGVector(dx: 0.55, dy: 0.50))
        waitForDiagnosticChange("debug.cameraOffset", from: simulationCamera, timeout: 3)
    }

    func testRegularDeviceInspectorProtectsUnsavedEditsWhenSelectionChanges() {
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.25, dy: 0.30))
        tapButton("palette.tool.place.switch")
        tapCanvas(at: CGVector(dx: 0.65, dy: 0.30))

        assertDiagnosticEquals("debug.nodeCount", expected: "Nodes: 2")
        assertDiagnosticEquals("debug.selectedNodeCount", expected: "Selected: 1")
        tapButton("design.configuration.open")

        let inspector = app.descendants(matching: .any)["design.configuration.inspector"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["design.configuration.sheet"].exists)

        let nameField = app.textFields["design.configuration.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.typeText(" edited")

        // Opening the inspector removes the palette but preserves world coordinates.
        // Select the PC placed on the left side of the now wider-origin canvas.
        tapCanvas(at: CGVector(dx: 0.30, dy: 0.30))
        let keepEditingButton = app.buttons.matching(
            identifier: "design.configuration.unsaved.keepEditing"
        ).firstMatch
        XCTAssertTrue(
            keepEditingButton.waitForExistence(timeout: 5),
            "Changing the selected device with a dirty inspector must require an explicit choice"
        )
        keepEditingButton.tap()

        XCTAssertTrue(inspector.exists)
        XCTAssertTrue(nameField.exists)
        XCTAssertTrue((nameField.value as? String)?.contains("edited") == true)
        assertDiagnosticEquals("debug.selectedNodeCount", expected: "Selected: 1")
    }

    func testDeleteShortcutDoesNotDeleteSelectionWhileEditingInspectorText() {
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.35, dy: 0.35))
        assertDiagnosticEquals("debug.nodeCount", expected: "Nodes: 1")

        tapButton("design.configuration.open")
        let nameField = requireElement(
            app.textFields["design.configuration.name"],
            named: "design.configuration.name"
        )
        nameField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.typeKey(.delete, modifierFlags: [])

        assertDiagnosticEquals("debug.nodeCount", expected: "Nodes: 1")
        XCTAssertTrue(nameField.exists)
    }

    func testUndoAndRedoMenuCommandsRestorePlacedDevice() {
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.35, dy: 0.35))
        assertDiagnosticEquals("debug.nodeCount", expected: "Nodes: 1")

        tapButton("java.menu.overflow")
        tapButton("java.menu.undo")
        assertDiagnosticEquals("debug.nodeCount", expected: "Nodes: 0")
        assertDiagnosticEquals("debug.lastAction", expected: "Last action: undo")

        tapButton("java.menu.overflow")
        tapButton("java.menu.redo")
        assertDiagnosticEquals("debug.nodeCount", expected: "Nodes: 1")
        assertDiagnosticEquals("debug.lastAction", expected: "Last action: redo")
    }

    func testCompactDeviceConfigurationUsesSheetFallback() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-compact-width-testing"]
        app.launch()

        _ = requireElement(canvasElement(), named: "canvas.surface")
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.40, dy: 0.35))
        tapButton("design.configuration.open")

        XCTAssertTrue(
            app.descendants(matching: .any)["design.configuration.sheet"].waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.descendants(matching: .any)["design.configuration.inspector"].exists)
        XCTAssertTrue(app.textFields["design.configuration.name"].exists)
        XCTAssertTrue(app.buttons["design.configuration.save"].exists)
    }

    func testMissingIdentifiersAreDetectedExplicitly() {
        let missingPaletteTool = app.descendants(matching: .any)["palette.tool.place.quantum"]
        XCTAssertFalse(
            missingPaletteTool.waitForExistence(timeout: 1),
            "Malformed input guard failed: unexpected element resolved for missing identifier"
        )

        let staleCanvasReference = app.descendants(matching: .any)["canvas.surface.stale"]
        XCTAssertFalse(
            staleCanvasReference.waitForExistence(timeout: 1),
            "Malformed input guard failed: stale canvas identifier should not resolve"
        )
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    // MARK: - Helpers

    @discardableResult
    private func requireControl(_ identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        let identified = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        let directTimeout = min(timeout, 2)
        if identified.waitForExistence(timeout: directTimeout) {
            return identified
        }

        if let fallbackLabel = fallbackLabel(for: identifier) {
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

        XCTFail("Setup failure: missing required accessibility identifier '\(identifier)'")
        return identified
    }

    private func fallbackLabel(for identifier: String) -> String? {
        switch identifier {
        case "palette.tool.select":
            return "Select"
        case "palette.tool.connect":
            return "Connect"
        case "palette.tool.place.pc":
            return "PC"
        case "palette.tool.place.switch":
            return "Switch"
        case "design.configuration.open":
            return "Configure"
        default:
            return nil
        }
    }

    @discardableResult
    private func requireElement(
        _ element: XCUIElement,
        named identifier: String,
        timeout: TimeInterval = 5
    ) -> XCUIElement {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Setup failure: missing required accessibility identifier '\(identifier)'"
        )
        return element
    }

    private func tapButton(_ identifier: String) {
        let button = requireControl(identifier)
        // Coordinate taps avoid XCTest's unreliable AX scroll-to-visible action
        // for buttons that are already visible inside the Java sidebar ScrollView.
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func canvasElement() -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "canvas.surface").firstMatch
    }

    private func tapCanvas(at normalizedOffset: CGVector) {
        let canvas = requireElement(canvasElement(), named: "canvas.surface")
        canvas.coordinate(withNormalizedOffset: normalizedOffset).tap()
    }

    private func dragOnCanvas(from start: CGVector, to end: CGVector) {
        let canvas = requireElement(canvasElement(), named: "canvas.surface")
        let startCoordinate = canvas.coordinate(withNormalizedOffset: start)
        let endCoordinate = canvas.coordinate(withNormalizedOffset: end)
        startCoordinate.press(forDuration: 0.1, thenDragTo: endCoordinate)
    }

    private func selectFirstAvailableConnectionPort() {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "connection.port.")
        let portButton = app.buttons.matching(predicate).firstMatch
        XCTAssertTrue(portButton.waitForExistence(timeout: 5), "Connection port picker must expose a port")
        portButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: portButton
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [dismissed], timeout: 5),
            .completed,
            "Connection port picker must dismiss after selecting a port"
        )
    }

    private func assertDiagnosticEquals(_ identifier: String, expected: String) {
        XCTAssertEqual(label(for: identifier), expected)
    }

    private func label(for identifier: String) -> String {
        let element = diagnosticElement(for: identifier)
        return element.label
    }

    private func waitForDiagnosticChange(
        _ identifier: String,
        from previousValue: String,
        timeout: TimeInterval
    ) {
        let element = diagnosticElement(for: identifier)
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", previousValue),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [changed], timeout: timeout),
            .completed,
            "Expected '\(identifier)' to change from '\(previousValue)'"
        )
    }

    private func diagnosticElement(for identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        let identified = app.staticTexts[identifier]
        if identified.waitForExistence(timeout: timeout) {
            return identified
        }

        if let prefix = diagnosticPrefixFallback(for: identifier) {
            let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
            let fallback = app.staticTexts.matching(predicate).firstMatch
            if fallback.waitForExistence(timeout: 2) {
                return fallback
            }
        }

        XCTFail("Setup failure: missing required accessibility identifier '\(identifier)'")
        return identified
    }

    private func diagnosticPrefixFallback(for identifier: String) -> String? {
        switch identifier {
        case "debug.activeTool":
            return "Tool:"
        case "debug.nodeCount":
            return "Nodes:"
        case "debug.linkCount":
            return "Links:"
        case "debug.selectedNodeCount":
            return "Selected:"
        case "debug.zoomScale":
            return "Zoom:"
        case "debug.lastValidationError":
            return "Last error:"
        case "debug.lastAction":
            return "Last action:"
        case "debug.lastInteractionMode":
            return "Last interaction mode:"
        case "debug.cameraOffset":
            return "Camera:"
        default:
            return nil
        }
    }

    private func zoomValue() -> Double {
        let labelText = label(for: "debug.zoomScale")
            .replacingOccurrences(of: "Zoom: ", with: "")
        return Double(labelText) ?? 0
    }
}
