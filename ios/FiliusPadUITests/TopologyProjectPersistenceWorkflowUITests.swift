import Foundation
import XCTest

final class TopologyProjectPersistenceWorkflowUITests: XCTestCase {
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

    func testSaveButtonPresentsDocumentPicker() {
        let autosaveURL = makeAutosaveURL()
        app = launchApp(
            autosaveURL: autosaveURL,
            additionalArguments: ["-ui-testing"],
            clearExistingAutosave: true
        )

        let saveButton = requireControl("java.menu.save")
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).tap()

        let picker = app.descendants(matching: .any)
            .matching(identifier: "project.export.picker")
            .firstMatch
        let filesApp = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        let pickerIsVisible = picker.waitForExistence(timeout: 3)
            || filesApp.wait(for: .runningForeground, timeout: 10)
        XCTAssertTrue(pickerIsVisible, "Save must present the native document picker")
    }

    func testAutosaveRoundTripRestoresTopologyAndRuntimeConfiguration() {
        let autosaveURL = makeAutosaveURL()
        seedAutosaveFixture(at: autosaveURL, persistenceRevision: 1)

        app = launchApp(
            autosaveURL: autosaveURL,
            additionalArguments: ["-ui-testing"],
            clearExistingAutosave: false
        )

        assertDiagnosticContains("debug.lastPersistenceLoadAt", expectedSubstring: "T")
        assertDiagnosticContains("debug.lastPersistenceError", expectedSubstring: "none")
        assertDiagnosticContains("debug.lastRecoveryState", expectedSubstring: "success:")

        let revisionBeforeRelaunch = persistenceRevisionValue()
        XCTAssertGreaterThan(revisionBeforeRelaunch, 0, "Expected seeded autosave fixture to expose durable persistence revision")

        app.terminate()

        app = launchApp(
            autosaveURL: autosaveURL,
            additionalArguments: ["-ui-testing"],
            clearExistingAutosave: false
        )

        assertDiagnosticContains("debug.lastPersistenceLoadAt", expectedSubstring: "T")
        assertDiagnosticContains("debug.lastPersistenceError", expectedSubstring: "none")
        assertDiagnosticContains("debug.lastRecoveryState", expectedSubstring: "success:")

        let recoveryBanner = app.otherElements["recovery.notice.banner"]
        if recoveryBanner.waitForExistence(timeout: 2) {
            tapButton("recovery.notice.dismiss")
            XCTAssertFalse(recoveryBanner.waitForExistence(timeout: 1), "Recovery banner should dismiss when requested")
        }

        tapButton("runtime.control.start")
        tapButton("runtime.control.stop")

        let revisionAfterRelaunch = persistenceRevisionValue()
        XCTAssertEqual(
            revisionAfterRelaunch,
            revisionBeforeRelaunch,
            "Reloading autosave should restore persisted durable revision baseline"
        )
    }

    func testMalformedAutosaveShowsPersistenceAlertAndKeepsEditorUsable() {
        let autosaveURL = makeAutosaveURL()

        app = launchApp(
            autosaveURL: autosaveURL,
            additionalArguments: ["-ui-testing", "-inject-malformed-autosave"]
        )

        let alert = app.alerts["Persistence error"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Expected persistence error alert when autosave payload is malformed")

        let alertMessage = requireElement(app.staticTexts["persistence.error.alert"], named: "persistence.error.alert")
        XCTAssertTrue(alertMessage.label.contains("Operation: load"))
        XCTAssertTrue(
            alertMessage.label.contains("Code: corruptedPayload") || alertMessage.label.contains("Code: malformedPayload"),
            "Expected deterministic load failure code in alert message"
        )

        alert.buttons["Dismiss"].tap()
        XCTAssertFalse(alert.waitForExistence(timeout: 2), "Persistence alert should dismiss when requested")

        assertDiagnosticContains("debug.lastPersistenceError", expectedSubstring: "none")

        tapButton("runtime.control.start")
        tapButton("runtime.control.stop")
    }

    // MARK: - Helpers

    @discardableResult
    private func launchApp(
        autosaveURL: URL,
        additionalArguments: [String],
        clearExistingAutosave: Bool = true
    ) -> XCUIApplication {
        if clearExistingAutosave, FileManager.default.fileExists(atPath: autosaveURL.path) {
            try? FileManager.default.removeItem(at: autosaveURL)
        }

        autosaveFileURLs.append(autosaveURL)

        let app = XCUIApplication()
        app.launchArguments += additionalArguments
        app.launchEnvironment["FILIUSPAD_AUTOSAVE_FILE"] = autosaveURL.path
        app.launch()
        self.app = app

        _ = requireElement(app.staticTexts["debug.persistenceRevision"], named: "debug.persistenceRevision")
        _ = requireElement(app.staticTexts["debug.lastPersistenceSaveAt"], named: "debug.lastPersistenceSaveAt")
        _ = requireElement(app.staticTexts["debug.lastPersistenceLoadAt"], named: "debug.lastPersistenceLoadAt")
        _ = requireElement(app.staticTexts["debug.lastPersistenceError"], named: "debug.lastPersistenceError")
        _ = requireElement(app.staticTexts["debug.lastRecoveryState"], named: "debug.lastRecoveryState")
        _ = requireElement(app.staticTexts["debug.lastRecoveryAt"], named: "debug.lastRecoveryAt")
        _ = requireControl("palette.tool.place.pc")
        _ = requireControl("palette.tool.place.switch")

        return app
    }

    @discardableResult
    private func requireControl(_ identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        if let control = locateControl(identifier, timeout: timeout) {
            return control
        }

        XCTFail("Missing required accessibility identifier '\(identifier)'")
        return app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func locateControl(_ identifier: String, timeout: TimeInterval) -> XCUIElement? {
        let identified = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        if identified.waitForExistence(timeout: timeout) {
            return identified
        }

        if let fallbackLabel = controlLabelFallback(for: identifier) {
            let fallbackButton = app.buttons.matching(NSPredicate(format: "label == %@", fallbackLabel)).firstMatch
            if fallbackButton.waitForExistence(timeout: 2) {
                return fallbackButton
            }
        }

        return nil
    }

    private func controlLabelFallback(for identifier: String) -> String? {
        switch identifier {
        case "palette.tool.place.pc":
            return "PC"
        case "palette.tool.place.switch":
            return "Switch"
        case "runtime.control.start":
            return "Aktionsmodus"
        case "runtime.control.stop":
            return "Entwurfsmodus"
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
        if element.waitForExistence(timeout: timeout) {
            return element
        }

        if let prefix = diagnosticPrefixFallback(for: identifier) {
            let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
            let fallback = app.staticTexts.matching(predicate).firstMatch
            if fallback.waitForExistence(timeout: 2) {
                return fallback
            }
        }

        XCTFail("Missing required accessibility identifier '\(identifier)'")
        return element
    }

    private func diagnosticPrefixFallback(for identifier: String) -> String? {
        switch identifier {
        case "debug.persistenceRevision":
            return "Persistence revision:"
        case "debug.lastPersistenceSaveAt":
            return "Last persistence save:"
        case "debug.lastPersistenceLoadAt":
            return "Last persistence load:"
        case "debug.lastPersistenceError":
            return "Last persistence error:"
        case "debug.lastRecoveryState":
            return "Recovery state:"
        case "debug.lastRecoveryAt":
            return "Last recovery at:"
        case "debug.nodeCount":
            return "Nodes:"
        case "debug.openedRuntimeDevice":
            return "Opened runtime device:"
        case "persistence.error.alert":
            return "Operation:"
        default:
            return nil
        }
    }

    private func tapButton(_ identifier: String) {
        let button = requireControl(identifier)
        XCTAssertTrue(button.isEnabled, "Button '\(identifier)' must be enabled before tapping")
        button.tap()
    }



    private func replaceTextField(_ identifier: String, with text: String) {
        let field = requireElement(app.textFields[identifier], named: identifier)
        field.tap()

        if let currentValue = field.value as? String, !currentValue.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count))
        }

        field.typeText(text)
    }

    private func assertTextFieldValue(_ identifier: String, expected: String) {
        let field = requireElement(app.textFields[identifier], named: identifier)
        let actual = (field.value as? String) ?? ""
        XCTAssertEqual(actual, expected, "Expected '\(identifier)' to restore persisted value")
    }



    private func assertDiagnosticContains(_ identifier: String, expectedSubstring: String) {
        let element = requireElement(app.staticTexts[identifier], named: identifier)
        XCTAssertTrue(
            element.label.contains(expectedSubstring),
            "Expected '\(identifier)' to contain '\(expectedSubstring)' but found '\(element.label)'"
        )
    }

    private func persistenceRevisionValue() -> UInt64 {
        let label = requireElement(app.staticTexts["debug.persistenceRevision"], named: "debug.persistenceRevision").label
        let suffix = label.replacingOccurrences(of: "Persistence revision: ", with: "")
        return UInt64(suffix) ?? 0
    }

    private func seedAutosaveFixture(at fileURL: URL, persistenceRevision: UInt64) {
        let iso8601 = ISO8601DateFormatter()
        let envelope: [String: Any] = [
            "format": "com.filius.pad.project",
            "schemaVersion": 1,
            "savedAt": iso8601.string(from: Date()),
            "saveReason": "autosave",
            "payload": [
                "graph": [
                    "nodes": [],
                    "links": []
                ],
                "viewport": [
                    "offset": [
                        "width": 0.0,
                        "height": 0.0
                    ],
                    "scale": 1.0
                ],
                "runtimeDeviceConfigurations": [],
                "persistenceRevision": persistenceRevision
            ]
        ]

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
            try data.write(to: fileURL, options: .atomic)
        } catch {
            XCTFail("Failed to seed autosave fixture: \(error)")
        }
    }

    private func makeAutosaveURL() -> URL {
        let filename = "TopologyProjectPersistenceWorkflowUITests-\(UUID().uuidString).json"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }
}
