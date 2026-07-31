import CoreGraphics
import XCTest
@testable import FiliusPad

final class ViewportTransformTests: XCTestCase {
    func testZoomClampsScaleToConfiguredBounds() {
        let base = ViewportTransform(offset: .zero, scale: 1)

        let zoomedIn = base.zoomed(by: 100, anchor: CGPoint(x: 50, y: 50))
        XCTAssertEqual(zoomedIn.scale, ViewportTransform.maxScale)

        let zoomedOut = base.zoomed(by: 0.0001, anchor: CGPoint(x: 50, y: 50))
        XCTAssertEqual(zoomedOut.scale, ViewportTransform.minScale)
    }

    func testZoomWithNonPositiveDeltaKeepsPreviousTransform() {
        let base = ViewportTransform(offset: CGSize(width: 10, height: -5), scale: 1.4)

        XCTAssertEqual(base.zoomed(by: 0, anchor: CGPoint(x: 100, y: 100)), base)
        XCTAssertEqual(base.zoomed(by: -1, anchor: CGPoint(x: 100, y: 100)), base)
    }

    func testPanWithInvalidDeltaKeepsPreviousTransform() {
        let base = ViewportTransform(offset: CGSize(width: 20, height: 30), scale: 1)

        let invalid = base.panned(by: CGSize(width: CGFloat.infinity, height: 15))
        XCTAssertEqual(invalid, base)
    }

    func testZoomKeepsOffCenterAnchorStable() {
        let base = ViewportTransform(offset: CGSize(width: 90, height: -40), scale: 1.25)
        let anchor = CGPoint(x: 170, y: 310)
        let worldPointUnderFingers = base.screenToWorld(anchor)

        let zoomed = base.zoomed(by: 1.6, anchor: anchor)
        let projectedAnchor = zoomed.worldToScreen(worldPointUnderFingers)

        XCTAssertEqual(projectedAnchor.x, anchor.x, accuracy: 0.0001)
        XCTAssertEqual(projectedAnchor.y, anchor.y, accuracy: 0.0001)
    }

    func testMagnificationAnchorUsesOffCenterFingerPosition() {
        let anchor = TopologyCanvasGesturePolicy.magnificationAnchor(
            normalizedAnchor: CGPoint(x: 0.2, y: 0.75),
            canvasSize: CGSize(width: 1_000, height: 600)
        )

        XCTAssertEqual(anchor.x, 200, accuracy: 0.0001)
        XCTAssertEqual(anchor.y, 450, accuracy: 0.0001)
    }

    func testEmptySelectionPansInsteadOfStartingMarquee() {
        var state = TopologyEditorState()
        state.activeTool = .select

        XCTAssertFalse(TopologyCanvasGesturePolicy.usesMarqueeSelection(for: state))

        state.selectedNodeIDs = [uuid("11111111-1111-1111-1111-111111111111")]
        XCTAssertTrue(TopologyCanvasGesturePolicy.usesMarqueeSelection(for: state))

        state.workspaceMode = .documentation
        XCTAssertFalse(TopologyCanvasGesturePolicy.usesMarqueeSelection(for: state))

        state.workspaceMode = .design
        state.simulationPhase = .running
        XCTAssertFalse(TopologyCanvasGesturePolicy.usesMarqueeSelection(for: state))
    }

    func testWorldScreenRoundTripAfterPanAndZoom() {
        let transform = ViewportTransform(offset: CGSize(width: 150, height: -90), scale: 1.8)
        let worldPoint = CGPoint(x: 220, y: 140)

        let screenPoint = transform.worldToScreen(worldPoint)
        let projectedBack = transform.screenToWorld(screenPoint)

        XCTAssertEqual(projectedBack.x, worldPoint.x, accuracy: 0.0001)
        XCTAssertEqual(projectedBack.y, worldPoint.y, accuracy: 0.0001)
    }

    func testHitTestingRemainsCorrectAfterPanAndZoom() {
        let nearNode = TopologyNode(
            id: uuid("11111111-1111-1111-1111-111111111111"),
            kind: .pc,
            position: CGPoint(x: 100, y: 100)
        )
        let farNode = TopologyNode(
            id: uuid("22222222-2222-2222-2222-222222222222"),
            kind: .networkSwitch,
            position: CGPoint(x: 360, y: 260)
        )

        let transform = ViewportTransform(offset: CGSize(width: 200, height: 120), scale: 2)
        let nearNodeScreenPoint = transform.worldToScreen(CGPoint(x: 102, y: 98))
        let farEmptyPoint = transform.worldToScreen(CGPoint(x: 700, y: 700))

        XCTAssertEqual(
            transform.hitTestNode(atScreenPoint: nearNodeScreenPoint, nodes: [nearNode, farNode]),
            nearNode.id
        )
        XCTAssertNil(transform.hitTestNode(atScreenPoint: farEmptyPoint, nodes: [nearNode, farNode]))
    }

    func testScreenRectToWorldReflectsCurrentTransform() {
        let transform = ViewportTransform(offset: CGSize(width: 100, height: 50), scale: 2)
        let screenRect = CGRect(x: 100, y: 50, width: 200, height: 100)

        let worldRect = transform.screenRectToWorld(screenRect)

        XCTAssertEqual(worldRect, CGRect(x: 0, y: 0, width: 100, height: 50))
    }

    private func uuid(_ rawValue: String) -> UUID {
        UUID(uuidString: rawValue) ?? UUID()
    }
}
