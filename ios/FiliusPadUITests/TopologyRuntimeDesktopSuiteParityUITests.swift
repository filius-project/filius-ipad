import CoreGraphics
import Foundation
import XCTest

final class TopologyRuntimeDesktopSuiteParityUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launch()

        _ = requireElement(app.otherElements["canvas.surface"], named: "canvas.surface", timeout: 8)
        _ = requireControl("palette.tool.place.pc")
        _ = requireControl("runtime.control.start")
        _ = requireDiagnosticElement("debug.nodeCount")
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

    func testFileExplorerInstallLaunchSelectAndClosePublishesDeterministicDiagnostics() {
        seedSinglePCRuntimeSheet()
        installProgramIfNeeded(.fileExplorer)
        launchProgram(.fileExplorer)

        let shellIdentifier = "runtime.device.appShell.fileExplorer"
        _ = requireElement(app.otherElements[shellIdentifier], named: shellIdentifier)

        _ = requireElement(app.otherElements["runtime.workspace.window"], named: "runtime.workspace.window")
        _ = requireElement(app.otherElements["runtime.workspace.taskbar"], named: "runtime.workspace.taskbar")

        tapButton("runtime.device.app.file.back")
        tapButton("runtime.device.app.file.open./var")
        tapButton("runtime.device.app.file.open./var/log")
        tapButton("runtime.device.app.file.select./var/log/runtime-events.log")
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "none")
        waitForLabelContains("runtime.device.app.file.selected", expectedSubstring: "runtime-events.log", timeout: 4)

        tapButton("runtime.device.app.file.back")
        _ = requireElement(
            app.buttons["runtime.device.app.file.open./var/log"],
            named: "runtime.device.app.file.open./var/log"
        )

        closeProgramAndAssertDesktop(shellIdentifier: shellIdentifier)
    }

    func testImageViewerInstallLaunchSelectAndClosePublishesDeterministicDiagnostics() {
        seedSinglePCRuntimeSheet()
        installProgramIfNeeded(.imageViewer)
        launchProgram(.imageViewer)

        let shellIdentifier = "runtime.device.appShell.imageViewer"
        _ = requireElement(app.otherElements[shellIdentifier], named: shellIdentifier)

        _ = requireElement(app.otherElements["runtime.workspace.window"], named: "runtime.workspace.window")
        _ = requireElement(app.otherElements["runtime.workspace.taskbar"], named: "runtime.workspace.taskbar")

        tapButton("runtime.device.app.image.back")
        tapButton("runtime.device.app.image.open./images")
        tapButton("runtime.device.app.image.select./images/traffic-heatmap.png")
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "none")
        waitForLabelContains("runtime.device.app.image.selected", expectedSubstring: "traffic-heatmap.png", timeout: 4)
        _ = requireElement(
            app.images.matching(identifier: "runtime.device.app.image.preview").firstMatch,
            named: "runtime.device.app.image.preview"
        )

        tapButton("runtime.device.app.image.back")
        _ = requireElement(
            app.buttons["runtime.device.app.image.open./images"],
            named: "runtime.device.app.image.open./images"
        )

        closeProgramAndAssertDesktop(shellIdentifier: shellIdentifier)
    }

    func testTextEditorInstallLaunchApplySaveResetAndClosePublishesDeterministicDiagnostics() {
        seedSinglePCRuntimeSheet()
        installProgramIfNeeded(.textEditor)
        launchProgram(.textEditor)

        let shellIdentifier = "runtime.device.appShell.textEditor"
        _ = requireElement(app.otherElements[shellIdentifier], named: shellIdentifier)

        let editor = requireElement(app.textViews["runtime.device.app.text.input"], named: "runtime.device.app.text.input")
        makeElementHittable(editor, identifier: "runtime.device.app.text.input", preferUpwardScroll: true)

        let originalPath = "/home/lab-notes.txt"
        let originalDraft = "Document deterministic runtime notes here."
        let alternatePath = "/home/topology-exports.csv"
        selectTextEditorFile(alternatePath)
        waitForLabelContains("runtime.device.app.text.status", expectedSubstring: alternatePath, timeout: 4)

        let alternateDraftExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "timestamp,event,detail"),
            object: editor
        )
        XCTAssertEqual(XCTWaiter.wait(for: [alternateDraftExpectation], timeout: 4), .completed)

        let defaultSelectionReappeared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", originalPath),
            object: app.staticTexts["runtime.device.app.text.status"]
        )
        defaultSelectionReappeared.isInverted = true
        XCTAssertEqual(
            XCTWaiter.wait(for: [defaultSelectionReappeared], timeout: 1),
            .completed,
            "Selecting another text file must not leave the default file selected"
        )

        selectTextEditorFile(originalPath)
        waitForLabelContains("runtime.device.app.text.status", expectedSubstring: originalPath, timeout: 4)
        waitForElementValue(editor, expected: originalDraft, timeout: 4)
        let appendedDraft = "\nS05 deterministic parity note"
        editor.tap()
        editor.typeText(appendedDraft)
        let savedDraft = (editor.value as? String) ?? ""
        XCTAssertEqual(savedDraft.count, originalDraft.count + appendedDraft.count)
        XCTAssertTrue(savedDraft.contains("S05 deterministic parity note"))

        tapButton("runtime.device.app.text.apply")
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "none")

        tapButton("runtime.device.app.text.save")
        waitForAnyConsoleLineContains("Text Editor saved: /home/lab-notes.txt", timeout: 4)

        editor.tap()
        editor.typeText("\nunsaved local edit")
        tapButton("runtime.device.app.text.reset")
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "none")
        waitForElementValue(editor, expected: savedDraft, timeout: 4)

        closeProgramAndAssertDesktop(shellIdentifier: shellIdentifier)
    }

    // MARK: - Helpers

    private func seedSinglePCRuntimeSheet() {
        for _ in 0..<2 where !diagnosticContains("debug.nodeCount", substring: "Nodes: 1") {
            tapButton("palette.tool.place.pc")
            tapCanvas(at: CGVector(dx: 0.40, dy: 0.35))
            _ = waitForDiagnosticContainsWithoutFailure("debug.nodeCount", expectedSubstring: "Nodes: 1", timeout: 2)
        }
        XCTAssertTrue(diagnosticContains("debug.nodeCount", substring: "Nodes: 1"), "Failed to place the runtime PC")

        tapButton("runtime.control.start")
        waitForDiagnosticContains("debug.simulationPhase", expectedSubstring: "running", timeout: 4)

        let sheet = app.otherElements["runtime.device.sheet"]
        for _ in 0..<2 where !sheet.exists {
            tapCanvas(at: CGVector(dx: 0.40, dy: 0.35))
            _ = sheet.waitForExistence(timeout: 2)
        }
        requireRuntimeDeviceSheetOpen()
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

    private func installProgramIfNeeded(_ program: TopologyRuntimeDesktopProgramFixture) {
        let launchIdentifier = "runtime.device.launch.\(program.rawValue)"
        let launchButton = app.buttons.matching(identifier: launchIdentifier).firstMatch
        if revealRuntimeSheetElementIfPresent(launchButton, towardTop: true) { return }

        tapRuntimeSheetButton("runtime.device.install.open", towardTop: true)
        tapRuntimeSheetButton("runtime.device.install.\(program.rawValue)", towardTop: false)
        _ = revealRuntimeSheetElement(launchButton, named: launchIdentifier, towardTop: true)
    }

    private func launchProgram(_ program: TopologyRuntimeDesktopProgramFixture) {
        tapRuntimeSheetButton("runtime.device.launch.\(program.rawValue)", towardTop: true)
        waitForDiagnosticContains("debug.openedRuntimeProgram", expectedSubstring: program.rawValue, timeout: 4)
        _ = revealRuntimeSheetElement(
            app.otherElements["runtime.device.appShell.\(program.rawValue)"],
            named: "runtime.device.appShell.\(program.rawValue)",
            towardTop: false
        )
        _ = requireElement(app.buttons["runtime.workspace.applications"], named: "runtime.workspace.applications")
    }

    private func closeProgramAndAssertDesktop(shellIdentifier: String) {
        tapRuntimeSheetButton("runtime.device.app.close", towardTop: false)
        waitForElementToDisappear(app.otherElements[shellIdentifier], timeout: 4, identifier: shellIdentifier)
        assertDiagnosticContains("debug.openedRuntimeProgram", expectedSubstring: "none")
    }

    private func selectTextEditorFile(_ path: String) {
        let picker = requireControl("runtime.device.app.text.file")
        makeElementHittable(picker, identifier: "runtime.device.app.text.file", preferUpwardScroll: true)
        picker.tap()

        let optionIdentifier = "runtime.device.app.text.file.option.\(path)"
        let option = requireElement(
            app.buttons.matching(identifier: optionIdentifier).firstMatch,
            named: optionIdentifier
        )
        makeElementHittable(option, identifier: optionIdentifier, preferUpwardScroll: true)
        option.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @discardableResult
    private func requireElement(_ element: XCUIElement, named identifier: String, timeout: TimeInterval = 10) -> XCUIElement {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail("Missing required accessibility identifier '\(identifier)'")
            return element
        }
        return element
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

        XCTFail("Missing required accessibility identifier '\(identifier)'")
        return direct
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
        case "debug.lastRuntimeFault":
            return "Last runtime fault:"
        case "debug.openedRuntimeDevice":
            return "Opened runtime device:"
        case "debug.openedRuntimeProgram":
            return "Opened runtime program:"
        default:
            return nil
        }
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

    private func tapButton(_ identifier: String, preferUpwardScroll: Bool = true) {
        let button = requireControl(identifier)
        XCTAssertTrue(button.isEnabled, "Button '\(identifier)' must be enabled before tapping")
        if identifier.hasPrefix("palette.") || identifier.hasPrefix("runtime.control.") {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return
        }

        makeElementHittable(button, identifier: identifier, preferUpwardScroll: preferUpwardScroll)
        button.tap()
    }

    private func makeElementHittable(
        _ element: XCUIElement,
        identifier: String,
        preferUpwardScroll: Bool
    ) {
        if runtimeSheetElementIsReady(element, requiresSafeViewport: true) {
            return
        }

        for _ in 0..<8 where !runtimeSheetElementIsReady(element, requiresSafeViewport: true) {
            scrollRuntimeSheet(toward: element, fallbackTowardTop: !preferUpwardScroll)
        }

        XCTAssertTrue(element.isHittable, "Element '\(identifier)' must become hittable after bounded scrolling")
        XCTAssertTrue(
            runtimeSheetElementIsReady(element, requiresSafeViewport: true),
            "Element '\(identifier)' must be fully visible below the runtime navigation bar before interaction"
        )
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
        requireDiagnosticElement(identifier).label
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
        waitForLabelContains(identifier, expectedSubstring: expectedSubstring, timeout: timeout, diagnostic: true)
    }

    private func diagnosticContains(_ identifier: String, substring: String) -> Bool {
        requireDiagnosticElement(identifier).label.contains(substring)
    }

    private func waitForDiagnosticContainsWithoutFailure(
        _ identifier: String,
        expectedSubstring: String,
        timeout: TimeInterval
    ) -> Bool {
        let element = requireDiagnosticElement(identifier)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.label.contains(expectedSubstring) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return element.label.contains(expectedSubstring)
    }

    private func waitForElementValue(_ element: XCUIElement, expected: String, timeout: TimeInterval) {
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(
            result,
            .completed,
            "Timed out waiting for element value '\(expected)'; found '\(element.value ?? "nil")'"
        )
    }

    private func waitForAnyConsoleLineContains(_ expectedText: String, timeout: TimeInterval) {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "runtime.device.console.line.")
        let lines = app.staticTexts.matching(predicate)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            for index in 0..<lines.count {
                let line = lines.element(boundBy: index)
                if line.exists, line.label.contains(expectedText) {
                    return
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Expected a runtime console line containing '\(expectedText)'")
    }

    private func waitForLabelContains(
        _ identifier: String,
        expectedSubstring: String,
        timeout: TimeInterval,
        diagnostic: Bool = false
    ) {
        let element = diagnostic
            ? requireDiagnosticElement(identifier)
            : requireElement(app.staticTexts[identifier], named: identifier)
        let predicate = NSPredicate(format: "label CONTAINS %@", expectedSubstring)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Timed out waiting for \(identifier) to contain '\(expectedSubstring)'")
    }

    private func waitForElementToDisappear(_ element: XCUIElement, timeout: TimeInterval, identifier: String) {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Timed out waiting for '\(identifier)' to disappear")
    }
}

private enum TopologyRuntimeDesktopProgramFixture: String {
    case fileExplorer
    case imageViewer
    case textEditor
}
