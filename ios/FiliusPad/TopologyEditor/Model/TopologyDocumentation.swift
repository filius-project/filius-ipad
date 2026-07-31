import CoreGraphics
import Foundation

enum TopologyWorkspaceMode: String, Codable, Equatable {
    case design
    case documentation
}

enum TopologyDocumentationTool: String, CaseIterable, Codable, Equatable {
    case select
    case text
    case rectangle
}

enum TopologyDocumentationItemKind: String, Codable, Equatable {
    case text
    case rectangle
}

struct TopologyDocumentationColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    static let black = TopologyDocumentationColor(red: 0, green: 0, blue: 0)
    static let paleYellow = TopologyDocumentationColor(
        red: 255.0 / 255.0,
        green: 255.0 / 255.0,
        blue: 227.0 / 255.0,
        alpha: 0.82
    )

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

struct TopologyDocumentationItem: Identifiable, Equatable {
    static let defaultTextSize = CGSize(width: 220, height: 96)
    static let defaultRectangleSize = CGSize(width: 240, height: 140)
    static let minimumSize = CGSize(width: 32, height: 24)
    /// Matches the editor canvas coordinate range and keeps Java `int` export
    /// plus CoreGraphics rendering in a deliberately safe domain.
    static let worldBounds = CGRect(x: -10_000, y: -10_000, width: 20_000, height: 20_000)

    let id: UUID
    var kind: TopologyDocumentationItemKind
    var frame: CGRect
    var text: String
    var color: TopologyDocumentationColor
    var fontName: String
    var fontSize: CGFloat
    var isBold: Bool
    var order: Int

    init(
        id: UUID = UUID(),
        kind: TopologyDocumentationItemKind,
        frame: CGRect,
        text: String = "",
        color: TopologyDocumentationColor,
        fontName: String = "System",
        fontSize: CGFloat = 14,
        isBold: Bool = false,
        order: Int
    ) {
        self.id = id
        self.kind = kind
        self.frame = Self.normalizedFrame(frame)
        self.text = kind == .text ? text : ""
        self.color = color
        self.fontName = fontName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "System"
            : fontName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fontSize = Self.normalizedFontSize(fontSize)
        self.isBold = isBold
        self.order = max(0, order)
    }

    static func text(
        id: UUID,
        origin: CGPoint,
        order: Int,
        value: String = "Text"
    ) -> TopologyDocumentationItem {
        TopologyDocumentationItem(
            id: id,
            kind: .text,
            frame: CGRect(origin: origin, size: defaultTextSize),
            text: value,
            color: .black,
            fontSize: 14,
            order: order
        )
    }

    static func rectangle(
        id: UUID,
        origin: CGPoint,
        order: Int
    ) -> TopologyDocumentationItem {
        TopologyDocumentationItem(
            id: id,
            kind: .rectangle,
            frame: CGRect(origin: origin, size: defaultRectangleSize),
            color: .paleYellow,
            order: order
        )
    }

    static func normalizedFrame(_ frame: CGRect) -> CGRect {
        guard frame.origin.x.isFinite,
              frame.origin.y.isFinite,
              frame.width.isFinite,
              frame.height.isFinite
        else {
            return CGRect(origin: worldBounds.origin, size: minimumSize)
        }

        let standardized = frame.standardized
        guard standardized.origin.x.isFinite,
              standardized.origin.y.isFinite,
              standardized.width.isFinite,
              standardized.height.isFinite
        else {
            return CGRect(origin: worldBounds.origin, size: minimumSize)
        }

        let width = min(max(standardized.width, minimumSize.width), worldBounds.width)
        let height = min(max(standardized.height, minimumSize.height), worldBounds.height)
        let x = min(max(standardized.origin.x, worldBounds.minX), worldBounds.maxX - width)
        let y = min(max(standardized.origin.y, worldBounds.minY), worldBounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func isSafeFrame(_ frame: CGRect) -> Bool {
        guard frame.origin.x.isFinite,
              frame.origin.y.isFinite,
              frame.width.isFinite,
              frame.height.isFinite,
              frame.width > 0,
              frame.height > 0,
              frame.width <= worldBounds.width,
              frame.height <= worldBounds.height
        else {
            return false
        }

        return frame.minX >= worldBounds.minX
            && frame.minY >= worldBounds.minY
            && frame.maxX <= worldBounds.maxX
            && frame.maxY <= worldBounds.maxY
    }

    static func javaInteger(_ value: CGFloat) -> Int? {
        guard value.isFinite,
              value >= CGFloat(Int32.min),
              value <= CGFloat(Int32.max)
        else {
            return nil
        }
        return Int(value.rounded())
    }

    var hasSafeGeometry: Bool {
        Self.isSafeFrame(frame)
    }

    var hasSafeRenderValues: Bool {
        hasSafeGeometry
            && fontSize.isFinite
            && (8...72).contains(fontSize)
            && color.red.isFinite
            && color.green.isFinite
            && color.blue.isFinite
            && color.alpha.isFinite
            && (0...1).contains(color.red)
            && (0...1).contains(color.green)
            && (0...1).contains(color.blue)
            && (0...1).contains(color.alpha)
    }

    static func normalizedFontSize(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 14 }
        return min(max(value, 8), 72)
    }
}

extension Array where Element == TopologyDocumentationItem {
    var inDeterministicRenderOrder: [TopologyDocumentationItem] {
        sorted { lhs, rhs in
            let lhsLayer = lhs.kind == .rectangle ? 0 : 1
            let rhsLayer = rhs.kind == .rectangle ? 0 : 1
            if lhsLayer != rhsLayer { return lhsLayer < rhsLayer }
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    var nextDocumentationOrder: Int {
        (map(\.order).max() ?? -1) + 1
    }
}


func deterministicDocumentationUUID(seed: String) -> UUID {
    let bytes = Array(seed.utf8)
    func hash(offset: UInt64, prime: UInt64) -> UInt64 {
        bytes.reduce(offset) { partial, byte in
            (partial ^ UInt64(byte)) &* prime
        }
    }
    let high = hash(offset: 0xcbf29ce484222325, prime: 0x100000001b3)
    let low = hash(offset: 0x84222325cbf29ce4, prime: 0x100000001b3) ^ UInt64(bytes.count)
    let tuple: uuid_t = (
        UInt8((high >> 56) & 0xff), UInt8((high >> 48) & 0xff),
        UInt8((high >> 40) & 0xff), UInt8((high >> 32) & 0xff),
        UInt8((high >> 24) & 0xff), UInt8((high >> 16) & 0xff),
        UInt8((high >> 8) & 0xff), UInt8(high & 0xff),
        UInt8((low >> 56) & 0xff), UInt8((low >> 48) & 0xff),
        UInt8((low >> 40) & 0xff), UInt8((low >> 32) & 0xff),
        UInt8((low >> 24) & 0xff), UInt8((low >> 16) & 0xff),
        UInt8((low >> 8) & 0xff), UInt8(low & 0xff)
    )
    return UUID(uuid: tuple)
}
