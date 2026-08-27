import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct TopologyDocumentationReport: Equatable {
    let nodeCount: Int
    let linkCount: Int
    let textAnnotationCount: Int
    let rectangleCount: Int

    init(state: TopologyEditorState) {
        nodeCount = state.graph.nodes.count
        linkCount = state.graph.links.count
        let renderableItems = state.documentationItems.filter(\.hasSafeRenderValues)
        textAnnotationCount = renderableItems.filter { $0.kind == .text }.count
        rectangleCount = renderableItems.filter { $0.kind == .rectangle }.count
    }
}

enum TopologyDocumentationReportRenderer {
    static let pageSize = CGSize(width: 1_024, height: 768)

    static func makePNGData(state: TopologyEditorState) -> Data? {
        let bounds = CGRect(origin: .zero, size: pageSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: pageSize, format: format)
        return renderer.image { context in
            drawReport(state: state, in: context.cgContext, pageBounds: bounds)
        }.pngData()
    }

    static func makePDFData(state: TopologyEditorState) -> Data {
        let bounds = CGRect(origin: .zero, size: pageSize)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Filius on iPad",
            kCGPDFContextTitle as String: FiliusLocalization.t("report.title"),
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        return renderer.pdfData { context in
            context.beginPage()
            drawReport(state: state, in: context.cgContext, pageBounds: bounds)
        }
    }

    private static func drawReport(state: TopologyEditorState, in context: CGContext, pageBounds: CGRect) {
        context.setFillColor(UIColor.white.cgColor)
        context.fill(pageBounds)

        let title = FiliusLocalization.t("report.title") as NSString
        title.draw(
            at: CGPoint(x: 36, y: 24),
            withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: UIColor.black,
            ]
        )

        let report = TopologyDocumentationReport(state: state)
        let summary = FiliusLocalization.t("report.summary", report.nodeCount, report.linkCount, report.textAnnotationCount, report.rectangleCount) as NSString
        summary.draw(
            at: CGPoint(x: 36, y: 55),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.darkGray,
            ]
        )

        let contentRect = CGRect(x: 36, y: 84, width: pageBounds.width - 72, height: pageBounds.height - 120)
        let worldBounds = reportWorldBounds(state: state)
        let scale = min(contentRect.width / max(worldBounds.width, 1), contentRect.height / max(worldBounds.height, 1))
        let offset = CGPoint(
            x: contentRect.minX + (contentRect.width - worldBounds.width * scale) / 2 - worldBounds.minX * scale,
            y: contentRect.minY + (contentRect.height - worldBounds.height * scale) / 2 - worldBounds.minY * scale
        )

        func project(_ point: CGPoint) -> CGPoint {
            CGPoint(x: offset.x + point.x * scale, y: offset.y + point.y * scale)
        }

        for item in state.documentationItems.inDeterministicRenderOrder
        where item.kind == .rectangle && item.hasSafeRenderValues {
            let origin = project(item.frame.origin)
            let rect = CGRect(
                x: origin.x,
                y: origin.y,
                width: item.frame.width * scale,
                height: item.frame.height * scale
            )
            context.setFillColor(uiColor(item.color).cgColor)
            context.fill(rect)
        }

        context.setStrokeColor(UIColor.darkGray.cgColor)
        context.setLineWidth(max(1, scale * 1.5))
        for link in state.graph.links {
            guard let projection = state.graph.linkProjection(for: link) else { continue }
            context.move(to: project(projection.source))
            context.addLine(to: project(projection.target))
            context.strokePath()
        }

        for node in state.graph.nodes.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let point = project(node.position)
            let nodeRect = CGRect(x: point.x - 25, y: point.y - 18, width: 50, height: 36)
            context.setFillColor(UIColor(white: 0.93, alpha: 1).cgColor)
            context.setStrokeColor(UIColor.black.cgColor)
            context.fill(nodeRect)
            context.stroke(nodeRect)
            (node.displayName as NSString).draw(
                in: nodeRect.insetBy(dx: 3, dy: 3),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 8),
                    .foregroundColor: UIColor.black,
                ]
            )
        }

        for item in state.documentationItems.inDeterministicRenderOrder
        where item.kind == .text && item.hasSafeRenderValues {
            let origin = project(item.frame.origin)
            let rect = CGRect(
                x: origin.x,
                y: origin.y,
                width: item.frame.width * scale,
                height: item.frame.height * scale
            )
            let font = UIFont.systemFont(
                ofSize: max(7, item.fontSize * scale),
                weight: item.isBold ? .bold : .regular
            )
            (item.text as NSString).draw(
                in: rect,
                withAttributes: [
                    .font: font,
                    .foregroundColor: uiColor(item.color),
                ]
            )
        }

        context.setStrokeColor(UIColor(white: 0.72, alpha: 1).cgColor)
        context.setLineWidth(1)
        context.stroke(contentRect)
    }

    private static func reportWorldBounds(state: TopologyEditorState) -> CGRect {
        var bounds: CGRect?
        for node in state.graph.nodes {
            let rect = CGRect(x: node.position.x - 40, y: node.position.y - 40, width: 80, height: 80)
            bounds = bounds.map { $0.union(rect) } ?? rect
        }
        for item in state.documentationItems where item.hasSafeRenderValues {
            bounds = bounds.map { $0.union(item.frame) } ?? item.frame
        }
        return (bounds ?? CGRect(x: 0, y: 0, width: 640, height: 480)).insetBy(dx: -24, dy: -24)
    }

    private static func uiColor(_ color: TopologyDocumentationColor) -> UIColor {
        UIColor(
            red: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(color.alpha)
        )
    }
}

struct TopologyPDFFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct TopologyPNGFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct TopologyTextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .tabSeparatedText] }

    let data: Data

    init(text: String) {
        data = Data(text.utf8)
    }

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
