import CoreGraphics
import Foundation

struct TopologyDocumentationItemSnapshot: Codable, Equatable {
    let id: UUID
    let kind: TopologyDocumentationItemKind
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let text: String
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    let fontName: String
    let fontSize: Double
    let isBold: Bool
    let order: Int

    init(_ item: TopologyDocumentationItem) {
        let boundedFrame = TopologyDocumentationItem.normalizedFrame(item.frame)
        let boundedColor = TopologyDocumentationColor(
            red: item.color.red,
            green: item.color.green,
            blue: item.color.blue,
            alpha: item.color.alpha
        )
        id = item.id
        kind = item.kind
        x = Double(boundedFrame.origin.x)
        y = Double(boundedFrame.origin.y)
        width = Double(boundedFrame.width)
        height = Double(boundedFrame.height)
        text = item.text
        red = boundedColor.red
        green = boundedColor.green
        blue = boundedColor.blue
        alpha = boundedColor.alpha
        fontName = item.fontName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "System" : item.fontName
        fontSize = Double(TopologyDocumentationItem.normalizedFontSize(item.fontSize))
        isBold = item.isBold
        order = item.order
    }

    func toDocumentationItem() -> TopologyDocumentationItem {
        TopologyDocumentationItem(
            id: id,
            kind: kind,
            frame: CGRect(x: x, y: y, width: width, height: height),
            text: text,
            color: TopologyDocumentationColor(red: red, green: green, blue: blue, alpha: alpha),
            fontName: fontName,
            fontSize: CGFloat(fontSize),
            isBold: isBold,
            order: order
        )
    }

    var hasValidScalarValues: Bool {
        [x, y, width, height, red, green, blue, alpha, fontSize].allSatisfy(\.isFinite)
            && TopologyDocumentationItem.isSafeFrame(
                CGRect(x: x, y: y, width: width, height: height)
            )
            && (0...1).contains(red)
            && (0...1).contains(green)
            && (0...1).contains(blue)
            && (0...1).contains(alpha)
            && (8...72).contains(fontSize)
            && order >= 0
            && !fontName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
