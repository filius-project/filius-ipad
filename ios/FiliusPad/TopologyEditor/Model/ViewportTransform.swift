import CoreGraphics
import Foundation

struct ViewportTransform: Equatable {
    static let minScale: CGFloat = 0.5
    static let maxScale: CGFloat = 3.0
    static let identity = ViewportTransform()

    var offset: CGSize
    var scale: CGFloat

    init(offset: CGSize = .zero, scale: CGFloat = 1) {
        self.offset = offset
        self.scale = Self.clampScale(scale)
    }

    static func clampScale(_ value: CGFloat) -> CGFloat {
        min(max(value, minScale), maxScale)
    }

    func worldToScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * scale + offset.width,
            y: point.y * scale + offset.height
        )
    }

    func screenToWorld(_ point: CGPoint) -> CGPoint {
        guard scale > 0 else {
            return point
        }

        return CGPoint(
            x: (point.x - offset.width) / scale,
            y: (point.y - offset.height) / scale
        )
    }

    func screenRectToWorld(_ rect: CGRect) -> CGRect {
        let normalized = rect.standardized
        let topLeft = screenToWorld(normalized.origin)
        let bottomRight = screenToWorld(
            CGPoint(
                x: normalized.maxX,
                y: normalized.maxY
            )
        )

        return CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
    }

    func panned(by delta: CGSize) -> ViewportTransform {
        guard Self.isFiniteSize(delta) else {
            return self
        }

        return ViewportTransform(
            offset: CGSize(
                width: offset.width + delta.width,
                height: offset.height + delta.height
            ),
            scale: scale
        )
    }

    func zoomed(by scaleDelta: CGFloat, anchor: CGPoint?) -> ViewportTransform {
        guard Self.isFiniteScalar(scaleDelta), scaleDelta > 0 else {
            return self
        }

        let nextScale = Self.clampScale(scale * scaleDelta)

        guard let anchor, Self.isFinitePoint(anchor) else {
            return ViewportTransform(offset: offset, scale: nextScale)
        }

        let worldAnchor = screenToWorld(anchor)
        let nextOffset = CGSize(
            width: anchor.x - (worldAnchor.x * nextScale),
            height: anchor.y - (worldAnchor.y * nextScale)
        )

        return ViewportTransform(offset: nextOffset, scale: nextScale)
    }

    func hitTestNode(
        atScreenPoint screenPoint: CGPoint,
        nodes: [TopologyNode],
        hitRadius: CGFloat = 28
    ) -> UUID? {
        guard Self.isFinitePoint(screenPoint) else {
            return nil
        }

        let worldPoint = screenToWorld(screenPoint)
        let worldRadius = max(hitRadius / max(scale, 0.001), 0)

        return nodes
            .reversed()
            .first(where: { node in
                let dx = node.position.x - worldPoint.x
                let dy = node.position.y - worldPoint.y
                return sqrt(dx * dx + dy * dy) <= worldRadius
            })?
            .id
    }

    private static func isFiniteSize(_ value: CGSize) -> Bool {
        isFiniteScalar(value.width) && isFiniteScalar(value.height)
    }

    private static func isFinitePoint(_ value: CGPoint) -> Bool {
        isFiniteScalar(value.x) && isFiniteScalar(value.y)
    }

    private static func isFiniteScalar(_ value: CGFloat) -> Bool {
        value.isFinite && !value.isNaN
    }
}
