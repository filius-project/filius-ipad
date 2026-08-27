import SwiftUI
import UIKit

struct TopologyCanvasView: View {
    let state: TopologyEditorState
    let onTap: (CGPoint) -> Void
    let onNodeDragChanged: (UUID, CGSize) -> Void
    let onNodeDragEnded: (UUID) -> Void
    let onDocumentationSelect: (UUID) -> Void
    let onDocumentationDragChanged: (UUID, CGSize) -> Void
    let onDocumentationDragEnded: (UUID) -> Void
    let onCanvasPan: (CGSize) -> Void
    let onCanvasPanEnded: () -> Void
    let onMarqueeSelection: (CGRect) -> Void
    let onMagnify: (CGFloat, CGPoint) -> Void
    let onMagnifyEnded: () -> Void
    let onConfigureNode: (UUID) -> Void
    let onDeleteNode: (UUID) -> Void
    let onStartConnection: (UUID) -> Void
    let onInspectRuntimeNode: (UUID) -> Void
    let onDeleteLink: (UUID) -> Void

    @State private var panTranslation: CGSize = .zero
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    @State private var draggingNodeID: UUID?
    @State private var magnification: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white

                TopologyCanvasParityBackground(simulationPhase: state.simulationPhase)

                if isEditingDocumentation {
                    linkLayer
                        .accessibilityIdentifier("canvas.linkLayer")

                    nodeLayer
                        .accessibilityIdentifier("canvas.nodeLayer")

                    documentationLayer()
                } else {
                    // Design mode and generated reports put rectangles behind the
                    // topology, while text remains above those rectangles.
                    documentationLayer(showing: .rectangle)

                    linkLayer
                        .accessibilityIdentifier("canvas.linkLayer")

                    nodeLayer
                        .accessibilityIdentifier("canvas.nodeLayer")

                    documentationLayer(showing: .text)
                }

                if let marqueeRect {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.12))
                        .overlay { Rectangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4])) }
                        .frame(width: marqueeRect.width, height: marqueeRect.height)
                        .position(x: marqueeRect.midX, y: marqueeRect.midY)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("canvas.marquee")
                }
            }
            .contentShape(Rectangle())
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement()
                    .accessibilityIdentifier("canvas.surface")
                    .allowsHitTesting(false)
            }
            .gesture(tapGesture, including: .gesture)
            .simultaneousGesture(canvasPanGesture, including: .gesture)
            .simultaneousGesture(magnificationGesture(in: proxy.size))
        }
    }

    private var marqueeRect: CGRect? {
        guard let marqueeStart, let marqueeCurrent else { return nil }
        return CGRect(
            x: min(marqueeStart.x, marqueeCurrent.x),
            y: min(marqueeStart.y, marqueeCurrent.y),
            width: abs(marqueeCurrent.x - marqueeStart.x),
            height: abs(marqueeCurrent.y - marqueeStart.y)
        )
    }

    private var usesMarqueeSelection: Bool {
        TopologyCanvasGesturePolicy.usesMarqueeSelection(for: state)
    }

    private var isEditingDocumentation: Bool {
        state.workspaceMode == .documentation && state.simulationPhase == .stopped
    }

    @ViewBuilder
    private func documentationLayer(showing kind: TopologyDocumentationItemKind? = nil) -> some View {
        TopologyDocumentationLayer(
            state: state,
            showing: kind,
            onSelect: onDocumentationSelect,
            onDragChanged: onDocumentationDragChanged,
            onDragEnded: onDocumentationDragEnded
        )
    }

    private var linkLayer: some View {
        let parallelCableOffsets = TopologyLink.parallelCableOffsets(for: state.graph.links)
        let positionsByNodeID = Dictionary(
            state.graph.nodes.map { ($0.id, $0.position) },
            uniquingKeysWith: { first, _ in first }
        )

        return ZStack {
            ForEach(state.graph.links) { link in
                if let source = positionsByNodeID[link.sourceNodeID],
                   let target = positionsByNodeID[link.targetNodeID] {
                    let path = javaCablePath(
                        from: source,
                        to: target,
                        controlOffset: parallelCableOffsets[link.id, default: 0]
                    )
                    path
                        .stroke(
                            state.selectedLinkIDs.contains(link.id)
                                ? Color.accentColor
                                : Color(
                                    red: 64.0 / 255.0,
                                    green: 64.0 / 255.0,
                                    blue: 64.0 / 255.0
                                ),
                            style: StrokeStyle(
                                lineWidth: state.selectedLinkIDs.contains(link.id) ? 4 : 2,
                                lineCap: .butt,
                                lineJoin: .miter
                            )
                        )
                        .contentShape(path.strokedPath(StrokeStyle(lineWidth: 24, lineCap: .round)))
                        .contextMenu {
                            if state.simulationPhase == .stopped {
                                Button(FiliusLocalization.t("ui.ffa5a8a7e21d"), role: .destructive) {
                                    onDeleteLink(link.id)
                                }
                            }
                        }
                        .accessibilityIdentifier("canvas.link.\(link.id.uuidString)")
                }
            }
        }
    }

    private var nodeLayer: some View {
        ZStack {
            ForEach(state.graph.nodes) { node in
                nodeView(node)
            }
        }
    }

    private func nodeView(_ node: TopologyNode) -> some View {
        let isSelected = state.selectedNodeIDs.contains(node.id)
        let screenPosition = state.viewport.worldToScreen(node.position)
        let iconSize = javaIconSize(for: node.kind)
        let javaLabelHeight: CGFloat = 15

        return VStack(spacing: 0) {
            TopologyCanvasNodeIcon(
                kind: node.kind,
                remoteLinkStatus: state.remoteLinkVisualState(for: node.id)
            )
            .frame(width: iconSize.width, height: iconSize.height)

            Text(state.displayLabel(for: node))
                .font(.system(size: 11))
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .frame(height: javaLabelHeight)
                .padding(.horizontal, 2)
        }
        .padding(3)
        .background(
            isSelected ? FiliusExperienceTokens.selectedSurface : Color.clear,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        // Java stores the hardware image center as the cable endpoint and lays
        // the caption below it. Offset the complete SwiftUI label so the image,
        // rather than the image-plus-caption stack, remains centered on the node.
        .position(x: screenPosition.x, y: screenPosition.y + (javaLabelHeight / 2))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(FiliusLocalization.t("canvas.node", state.displayLabel(for: node), accessibilityNodeLabel(for: node.kind)))
        .accessibilityHint(state.simulationPhase == .running ? FiliusLocalization.t("ui.a8000a8ff0b8") : FiliusLocalization.t("ui.7b0cc03c8d1d"))
        .accessibilityValue(state.remoteLinkVisualState(for: node.id)?.localizedDescription ?? "")
        .accessibilityAddTraits(state.simulationPhase == .running ? .isButton : [])
        .accessibilityIdentifier("canvas.node.\(node.id.uuidString)")
        .contextMenu {
            if state.simulationPhase == .stopped {
                if node.kind != .unsupported {
                    Button(FiliusLocalization.t("ui.a2eb163fcbf0")) { onConfigureNode(node.id) }
                }
                Button(FiliusLocalization.t("context.connect")) { onStartConnection(node.id) }
                Button(FiliusLocalization.t("ui.ffa5a8a7e21d"), role: .destructive) { onDeleteNode(node.id) }
            } else if node.kind.isPCClassEndpoint {
                Button(FiliusLocalization.t("context.inspectRuntime")) { onInspectRuntimeNode(node.id) }
            }
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { drag in
                    draggingNodeID = node.id
                    marqueeStart = nil
                    marqueeCurrent = nil
                    onNodeDragChanged(node.id, drag.translation)
                }
                .onEnded { _ in
                    onNodeDragEnded(node.id)
                    Task { @MainActor in
                        await Task.yield()
                        draggingNodeID = nil
                    }
                }
        )
    }

    private func javaCablePath(from source: CGPoint, to target: CGPoint, controlOffset: CGFloat) -> Path {
        let start = state.viewport.worldToScreen(source)
        let end = state.viewport.worldToScreen(target)
        // JCablePanel first creates a two-point bounding panel with a two-pixel
        // stroke inset. Its photo-icon curve uses the upper quarter for Y and
        // the right three-quarter X for falling lines; rising lines use the
        // left quarter. Reproducing that local-coordinate calculation gives the
        // same characteristic Java cable bow instead of a generic 25% curve.
        let inset: CGFloat = 2
        let localWidth = abs(end.x - start.x) + (2 * inset)
        let localHeight = abs(end.y - start.y) + (2 * inset)
        let hasFallingJavaSlope = (start.x - end.x) * (start.y - end.y) > 0
        let localControlX = (localWidth / 4) * (hasFallingJavaSlope ? 3 : 1)
        let localControlY = localHeight / 4
        let baseControl = CGPoint(
            x: min(start.x, end.x) - inset + localControlX,
            y: min(start.y, end.y) - inset + localControlY
        )
        let length = max(hypot(end.x - start.x, end.y - start.y), 0.001)
        let control = CGPoint(
            x: baseControl.x - ((end.y - start.y) / length * controlOffset),
            y: baseControl.y + ((end.x - start.x) / length * controlOffset)
        )

        return Path { path in
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
        }
    }

    private func javaIconSize(for kind: TopologyNodeKind) -> CGSize {
        switch kind {
        case .pc:
            return CGSize(width: 64, height: 94)
        case .notebook:
            return CGSize(width: 84, height: 80)
        case .networkSwitch, .unsupported:
            return CGSize(width: 70, height: 52)
        case .router, .gateway:
            return CGSize(width: 77, height: 58)
        case .remoteLink:
            return CGSize(width: 80, height: 56)
        }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                onTap(value.location)
            }
    }

    private var canvasPanGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if draggingNodeID != nil {
                    marqueeStart = nil
                    marqueeCurrent = nil
                    return
                }
                if state.viewport.hitTestNode(
                    atScreenPoint: value.startLocation,
                    nodes: state.graph.nodes
                ) != nil {
                    if usesMarqueeSelection { onTap(value.startLocation) }
                    return
                }

                if usesMarqueeSelection {
                    if marqueeStart == nil { marqueeStart = value.startLocation }
                    marqueeCurrent = value.location
                    return
                }

                let delta = CGSize(
                    width: value.translation.width - panTranslation.width,
                    height: value.translation.height - panTranslation.height
                )
                panTranslation = value.translation
                onCanvasPan(delta)
            }
            .onEnded { _ in
                if draggingNodeID != nil {
                    marqueeStart = nil
                    marqueeCurrent = nil
                    panTranslation = .zero
                    onCanvasPanEnded()
                    return
                }
                if usesMarqueeSelection, let marqueeRect, marqueeRect.width >= 8, marqueeRect.height >= 8 {
                    onMarqueeSelection(marqueeRect)
                }
                marqueeStart = nil
                marqueeCurrent = nil
                panTranslation = .zero
                onCanvasPanEnded()
            }
    }

    private func magnificationGesture(in canvasSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let delta = value.magnification / magnification
                magnification = value.magnification
                onMagnify(
                    delta,
                    TopologyCanvasGesturePolicy.magnificationAnchor(
                        normalizedAnchor: CGPoint(x: value.startAnchor.x, y: value.startAnchor.y),
                        canvasSize: canvasSize
                    )
                )
            }
            .onEnded { _ in
                magnification = 1
                onMagnifyEnded()
            }
    }

    private func accessibilityNodeLabel(for kind: TopologyNodeKind) -> String {
        switch kind {
        case .pc:
            // M008/S03 approved Java parity anchor retained; the spoken value is localized: return "PC node"
            return FiliusLocalization.t("accessibility.node.pc")
        case .notebook:
            // M008/S03 approved Java parity anchor retained; the spoken value is localized: return "Notebook node"
            return FiliusLocalization.t("accessibility.node.notebook")
        case .networkSwitch:
            // M008/S03 approved Java parity anchor retained; the spoken value is localized: return "Switch node"
            return FiliusLocalization.t("accessibility.node.switch")
        case .router:
            // M008/S03 approved Java parity anchor retained; the spoken value is localized: return "Router node"
            return FiliusLocalization.t("accessibility.node.router")
        case .gateway:
            // M008/S03 approved Java parity anchor retained; the spoken value is localized: return "Gateway node"
            return FiliusLocalization.t("accessibility.node.gateway")
        case .remoteLink:
            // M008/S04 approved Java parity anchor retained; the spoken value is localized: return "Remote Link node"
            return FiliusLocalization.t("accessibility.node.remoteLink")
        case .unsupported:
            // M008/S03 approved Java parity anchor retained; the spoken value is localized: return "Unsupported node"
            return FiliusLocalization.t("accessibility.node.unsupported")
        }
    }
}

struct TopologyCanvasGesturePolicy {
    static func usesMarqueeSelection(for state: TopologyEditorState) -> Bool {
        let hasSelection = !state.selectedNodeIDs.isEmpty
            || !state.selectedLinkIDs.isEmpty
            || state.selectedDocumentationItemID != nil

        return state.simulationPhase == .stopped
            && state.workspaceMode == .design
            && state.activeTool == .select
            && hasSelection
    }

    static func magnificationAnchor(normalizedAnchor: CGPoint, canvasSize: CGSize) -> CGPoint {
        guard normalizedAnchor.x.isFinite, normalizedAnchor.y.isFinite,
              canvasSize.width.isFinite, canvasSize.height.isFinite,
              canvasSize.width > 0, canvasSize.height > 0
        else {
            let fallbackWidth = canvasSize.width.isFinite ? max(canvasSize.width, 0) : 0
            let fallbackHeight = canvasSize.height.isFinite ? max(canvasSize.height, 0) : 0
            return CGPoint(x: fallbackWidth / 2, y: fallbackHeight / 2)
        }

        return CGPoint(
            x: normalizedAnchor.x * canvasSize.width,
            y: normalizedAnchor.y * canvasSize.height
        )
    }
}

private struct TopologyCanvasParityBackground: View {
    let simulationPhase: TopologySimulationPhase

    var body: some View {
        let relativePath = simulationPhase == .running
            ? "allgemein/simulationshg.png"
            : "allgemein/entwurfshg.png"

        if let image = TopologyParityAssetLoader.load(relativePath: relativePath) {
            Image(uiImage: image)
                .resizable(resizingMode: .tile)
        } else {
            Color.white
        }
    }
}

private struct TopologyCanvasNodeIcon: View {
    let kind: TopologyNodeKind
    let remoteLinkStatus: RemoteLinkVisualState?

    @ViewBuilder
    var body: some View {
        if kind == .remoteLink {
            RemoteLinkSymbolView(status: remoteLinkStatus)
        } else if let image = TopologyParityAssetLoader.load(relativePath: iconRelativePath(for: kind)) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: fallbackSystemImage(for: kind))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(12)
                .foregroundStyle(Color.black)
        }
    }

    private func iconRelativePath(for kind: TopologyNodeKind) -> String {
        switch kind {
        case .pc:
            return "hardware/server.png"
        case .notebook:
            return "hardware/laptop.png"
        case .networkSwitch:
            return "hardware/switch.png"
        case .router:
            return "hardware/router.png"
        case .gateway:
            return "hardware/gateway.png"
        case .remoteLink:
            return ""
        case .unsupported:
            return "hardware/cloud.png"
        }
    }

    private func fallbackSystemImage(for kind: TopologyNodeKind) -> String {
        switch kind {
        case .pc:
            return "desktopcomputer"
        case .notebook:
            return "laptopcomputer"
        case .networkSwitch:
            return "switch.2"
        case .router:
            return "arrow.triangle.branch"
        case .gateway:
            return "network"
        case .remoteLink:
            return "point.3.connected.trianglepath.dotted"
        case .unsupported:
            return "questionmark.circle"
        }
    }
}
