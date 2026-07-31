import CoreGraphics
import CoreImage
import UIKit
import XCTest

final class TopologyVisualRegressionUITests: XCTestCase {
    private var app: XCUIApplication!
    private let similarityThreshold = 0.94

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft

        app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-visual-testing",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        XCTAssertTrue(app.otherElements["java.mainMenu"].waitForExistence(timeout: 8))
        XCTAssertTrue(canvas.waitForExistence(timeout: 8))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
        XCUIDevice.shared.orientation = .portrait
    }

    func testEmptyDesignWorkspaceVisualBaseline() throws {
        assertPrimaryShellSemantics()
        try assertVisualBaseline(named: "empty-design-workspace")
    }

    func testPopulatedDesignWorkspaceVisualBaseline() throws {
        seedConnectedPCAndSwitch()
        tapButton("palette.tool.select")
        tapCanvas(at: CGVector(dx: 0.25, dy: 0.30))

        XCTAssertEqual(diagnosticInteger("debug.nodeCount"), 2)
        XCTAssertEqual(diagnosticInteger("debug.linkCount"), 1)
        XCTAssertEqual(diagnosticInteger("debug.selectedNodeCount"), 1)
        try assertVisualBaseline(named: "populated-design-workspace")
    }

    func testDeviceInspectorVisualBaseline() throws {
        seedConnectedPCAndSwitch()
        tapButton("palette.tool.select")
        tapCanvas(at: CGVector(dx: 0.45, dy: 0.60))
        tapButton("design.configuration.open")

        let inspector = app.descendants(matching: .any)["design.configuration.inspector"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["design.configuration.name"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["design.configuration.sheet"].exists)
        try assertVisualBaseline(named: "device-inspector")
    }

    func testSimulationDesktopVisualBaseline() throws {
        openSinglePCRuntimeDesktop()

        XCTAssertTrue(app.otherElements["runtime.device.sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(identifier: "runtime.device.install.open").firstMatch.exists)
        assertRuntimeDesktopUsesAvailableSpace()
        try assertVisualBaseline(named: "simulation-desktop")
    }

    func testSoftwareManagerVisualBaseline() throws {
        openSinglePCRuntimeDesktop()
        tapRuntimeControl("runtime.device.install.open", towardTop: true)

        XCTAssertTrue(app.otherElements["runtime.device.installer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["runtime.device.desktop"].exists)
        XCTAssertTrue(app.otherElements["runtime.workspace.window"].exists)
        XCTAssertTrue(app.otherElements["runtime.workspace.taskbar"].exists)
        XCTAssertTrue(app.buttons["runtime.workspace.applications"].exists)
        try assertVisualBaseline(named: "runtime-software-manager")
    }

    func testRuntimeApplicationVisualBaseline() throws {
        openSinglePCRuntimeDesktop()
        installCommandPromptIfNeeded()
        tapRuntimeControl("runtime.device.launch.commandPrompt", towardTop: true)

        XCTAssertTrue(
            revealRuntimeElement(
                app.otherElements["runtime.device.appShell.commandPrompt"],
                towardTop: false
            ).exists
        )
        XCTAssertTrue(app.otherElements["runtime.workspace.chrome"].exists)
        XCTAssertTrue(app.buttons["runtime.device.app.close"].exists)
        XCTAssertTrue(app.otherElements["runtime.device.desktop"].exists)
        XCTAssertTrue(app.otherElements["runtime.workspace.window"].exists)
        XCTAssertTrue(app.otherElements["runtime.workspace.taskbar"].exists)
        XCTAssertTrue(app.buttons["runtime.workspace.applications"].exists)
        XCTAssertTrue(app.scrollViews["runtime.device.console.list"].exists)
        XCTAssertEqual(app.staticTexts["runtime.device.command.prompt"].label, "/>")
        assertRuntimeDesktopUsesAvailableSpace()
        try assertVisualBaseline(named: "runtime-command-prompt")
    }

    func testPacketViewerVisualBaseline() throws {
        openSinglePCRuntimeDesktop()
        tapRuntimeControl("runtime.device.packet-exchange.show", towardTop: false)

        XCTAssertTrue(app.staticTexts["No messages recorded"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["runtime.device.packet-exchange.show"].exists)
        try assertVisualBaseline(named: "packet-viewer")
    }

    // MARK: - Scenarios

    private func assertPrimaryShellSemantics() {
        XCTAssertTrue(app.buttons["java.menu.new"].exists)
        XCTAssertTrue(app.buttons["java.menu.open"].exists)
        XCTAssertTrue(app.buttons["java.menu.save"].exists)
        XCTAssertTrue(app.buttons["runtime.control.stop"].exists)
        XCTAssertTrue(app.buttons["runtime.control.start"].exists)
        XCTAssertGreaterThanOrEqual(app.buttons["java.menu.new"].frame.width, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["java.menu.new"].frame.height, 44)
    }

    private func seedConnectedPCAndSwitch() {
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.25, dy: 0.30))
        tapButton("palette.tool.place.switch")
        tapCanvas(at: CGVector(dx: 0.45, dy: 0.60))

        tapButton("palette.tool.connect")
        tapCanvas(at: CGVector(dx: 0.25, dy: 0.30))
        selectFirstAvailableConnectionPort()
        tapCanvas(at: CGVector(dx: 0.45, dy: 0.60))
        selectFirstAvailableConnectionPort()
    }

    private func openSinglePCRuntimeDesktop() {
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.40, dy: 0.35))
        tapButton("runtime.control.start")
        waitForDiagnostic("debug.simulationPhase", toContain: "running")
        tapCanvas(at: CGVector(dx: 0.40, dy: 0.35))
        XCTAssertTrue(app.otherElements["runtime.device.sheet"].waitForExistence(timeout: 5))
    }

    private func assertRuntimeDesktopUsesAvailableSpace(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let windowFrame = app.windows.firstMatch.frame
        let desktopFrame = app.otherElements["runtime.device.desktop"].frame
        XCTAssertGreaterThanOrEqual(
            desktopFrame.width,
            windowFrame.width * 0.94,
            "Runtime desktop should use nearly the full available width",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            desktopFrame.height,
            windowFrame.height * 0.88,
            "Runtime desktop should use nearly the full available height",
            file: file,
            line: line
        )
    }

    private func installCommandPromptIfNeeded() {
        let launchButton = app.buttons.matching(identifier: "runtime.device.launch.commandPrompt").firstMatch
        if revealRuntimeElement(launchButton, towardTop: true, required: false).exists {
            return
        }

        let installer = revealRuntimeElement(
            app.buttons.matching(identifier: "runtime.device.install.open").firstMatch,
            towardTop: true
        )
        installer.tap()
        tapRuntimeControl("runtime.device.install.commandPrompt", towardTop: false)
        XCTAssertTrue(revealRuntimeElement(launchButton, towardTop: true).exists)
    }

    // MARK: - Visual comparison

    private func assertVisualBaseline(named name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let screenshot = app.windows.firstMatch.screenshot()
        let normalizedImage = normalizedImage(screenshot.image)
        guard let actualData = normalizedImage.pngData() else {
            throw VisualRegressionError.invalidPNG
        }
        let baselineURL = baselineDirectory.appendingPathComponent("\(name).png")

        let actualAttachment = XCTAttachment(data: actualData, uniformTypeIdentifier: "public.png")
        actualAttachment.name = "actual-\(name)"
        actualAttachment.lifetime = .keepAlways
        add(actualAttachment)

        if shouldUpdateBaselines {
            try FileManager.default.createDirectory(
                at: baselineDirectory,
                withIntermediateDirectories: true
            )
            try actualData.write(to: baselineURL, options: .atomic)
            return
        }

        guard FileManager.default.fileExists(atPath: baselineURL.path) else {
            XCTFail(
                "Missing visual baseline '\(baselineURL.lastPathComponent)'. Run ios/scripts/run-visual-regression.sh --record on the canonical Mac simulator.",
                file: file,
                line: line
            )
            return
        }

        let expectedData = try Data(contentsOf: baselineURL)
        let expectedAttachment = XCTAttachment(data: expectedData, uniformTypeIdentifier: "public.png")
        expectedAttachment.name = "expected-\(name)"
        expectedAttachment.lifetime = .keepAlways
        add(expectedAttachment)

        let result = try imageComparison(expectedData: expectedData, actualData: actualData)
        if let differenceData = result.differencePNGData {
            let differenceAttachment = XCTAttachment(data: differenceData, uniformTypeIdentifier: "public.png")
            differenceAttachment.name = "difference-\(name)-similarity-\(String(format: "%.5f", result.similarity))"
            differenceAttachment.lifetime = .keepAlways
            add(differenceAttachment)
        }

        XCTAssertGreaterThanOrEqual(
            result.similarity,
            similarityThreshold,
            "Visual similarity for '\(name)' was \(String(format: "%.5f", result.similarity)); expected at least \(similarityThreshold).",
            file: file,
            line: line
        )
    }

    private var baselineDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ParityBaselines", isDirectory: true)
    }

    private var shouldUpdateBaselines: Bool {
        FileManager.default.fileExists(
            atPath: baselineDirectory.appendingPathComponent(".recording").path
        )
    }

    private func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up,
              let sourceCGImage = image.cgImage else {
            return image
        }
        let orientedImage = CIImage(cgImage: sourceCGImage)
            .oriented(forExifOrientation: image.imageOrientation.exifOrientation)
        let normalizedExtent = orientedImage.extent.integral
        let translatedImage = orientedImage.transformed(
            by: CGAffineTransform(
                translationX: -normalizedExtent.origin.x,
                y: -normalizedExtent.origin.y
            )
        )
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let cgImage = context.createCGImage(translatedImage, from: translatedImage.extent.integral) else {
            return image
        }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    private func imageComparison(expectedData: Data, actualData: Data) throws -> ImageComparisonResult {
        guard let expected = UIImage(data: expectedData)?.cgImage,
              let actual = UIImage(data: actualData)?.cgImage else {
            throw VisualRegressionError.invalidPNG
        }
        guard expected.width == actual.width, expected.height == actual.height else {
            return ImageComparisonResult(similarity: 0, differencePNGData: actualData)
        }

        let expectedBytes = try rgbaBytes(from: expected)
        let actualBytes = try rgbaBytes(from: actual)
        var differenceBytes = [UInt8](repeating: 0, count: expectedBytes.count)
        var totalDifference: UInt64 = 0

        for index in stride(from: 0, to: expectedBytes.count, by: 4) {
            let redDifference = abs(Int(expectedBytes[index]) - Int(actualBytes[index]))
            let greenDifference = abs(Int(expectedBytes[index + 1]) - Int(actualBytes[index + 1]))
            let blueDifference = abs(Int(expectedBytes[index + 2]) - Int(actualBytes[index + 2]))
            totalDifference += UInt64(redDifference + greenDifference + blueDifference)

            differenceBytes[index] = UInt8(redDifference)
            differenceBytes[index + 1] = UInt8(greenDifference)
            differenceBytes[index + 2] = UInt8(blueDifference)
            differenceBytes[index + 3] = 255
        }

        let maximumDifference = Double(expected.width * expected.height * 3 * 255)
        let similarity = 1 - (Double(totalDifference) / maximumDifference)
        let differencePNGData = pngData(
            from: differenceBytes,
            width: expected.width,
            height: expected.height
        )
        return ImageComparisonResult(similarity: similarity, differencePNGData: differencePNGData)
    }

    private func rgbaBytes(from image: CGImage) throws -> [UInt8] {
        let bytesPerRow = image.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        guard let context = CGContext(
            data: &bytes,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw VisualRegressionError.cannotCreateBitmapContext
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    private func pngData(from bytes: [UInt8], width: Int, height: Int) -> Data? {
        var mutableBytes = bytes
        let bytesPerRow = width * 4
        guard let context = CGContext(
            data: &mutableBytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            return nil
        }
        return UIImage(cgImage: image).pngData()
    }

    // MARK: - UI helpers

    private var canvas: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "canvas.surface").firstMatch
    }

    private func tapButton(_ identifier: String) {
        var button = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        if !button.waitForExistence(timeout: 2) {
            switch identifier {
            case "design.configuration.open": button = app.buttons["Configure"]
            case "palette.tool.place.pc": button = app.buttons["PC"]
            default: break
            }
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing button '\(identifier)'")
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func tapCanvas(at offset: CGVector) {
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.coordinate(withNormalizedOffset: offset).tap()
    }

    private func selectFirstAvailableConnectionPort() {
        let port = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "connection.port.")
        ).firstMatch
        XCTAssertTrue(port.waitForExistence(timeout: 5))
        port.tap()
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: port
        )
        XCTAssertEqual(XCTWaiter().wait(for: [dismissed], timeout: 5), .completed)
    }

    private func tapRuntimeControl(_ identifier: String, towardTop: Bool) {
        let element = revealRuntimeElement(
            app.buttons.matching(identifier: identifier).firstMatch,
            towardTop: towardTop
        )
        element.tap()
    }

    @discardableResult
    private func revealRuntimeElement(
        _ element: XCUIElement,
        towardTop: Bool,
        required: Bool = true
    ) -> XCUIElement {
        let scroll = app.scrollViews["runtime.device.scroll"]
        for _ in 0..<8 where !element.exists || !element.isHittable {
            guard scroll.exists else { break }
            towardTop ? scroll.swipeDown() : scroll.swipeUp()
        }
        if required {
            XCTAssertTrue(element.exists, "Runtime element never appeared")
            XCTAssertTrue(element.isHittable, "Runtime element never became hittable")
        }
        return element
    }

    private func waitForDiagnostic(_ identifier: String, toContain substring: String) {
        let element = app.staticTexts[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", substring),
            object: element
        )
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed)
    }

    private func diagnosticInteger(_ identifier: String) -> Int? {
        let label = app.staticTexts[identifier].label
        return Int(label.split(separator: " ").last ?? "")
    }
}

private struct ImageComparisonResult {
    let similarity: Double
    let differencePNGData: Data?
}

private enum VisualRegressionError: Error {
    case invalidPNG
    case cannotCreateBitmapContext
}
private extension UIImage.Orientation {
    var exifOrientation: Int32 {
        switch self {
        case .up: return 1
        case .upMirrored: return 2
        case .down: return 3
        case .downMirrored: return 4
        case .leftMirrored: return 5
        case .right: return 6
        case .rightMirrored: return 7
        case .left: return 8
        @unknown default: return 1
        }
    }
}
