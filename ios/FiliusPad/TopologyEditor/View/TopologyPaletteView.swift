import SwiftUI
import UIKit

enum FiliusExperienceTokens {
    static let minimumHitSize: CGFloat = 44
    static let compactSpacing: CGFloat = 6
    static let regularSpacing: CGFloat = 10
    static let groupCornerRadius: CGFloat = 12
    static let selectedSurface = Color.accentColor.opacity(0.18)
    static let toolbarSurface = Color.white.opacity(0.72)
    static let javaPanelSurface = Color(red: 0.81, green: 0.81, blue: 0.81)
    static let runtimeWindowSurface = Color(red: 0.95, green: 0.95, blue: 0.95)
    static let statusActive = Color.green
    static let statusWarning = Color.orange
    static let statusDisabled = Color.secondary
    static let statusAmbiguous = Color.red
}

enum RemoteLinkVisualState: String, Equatable {
    case unpaired
    case active
    case ambiguous
    case disabled

    var color: Color {
        switch self {
        case .unpaired: return FiliusExperienceTokens.statusWarning
        case .active: return FiliusExperienceTokens.statusActive
        case .ambiguous: return FiliusExperienceTokens.statusAmbiguous
        case .disabled: return FiliusExperienceTokens.statusDisabled
        }
    }

    var systemImage: String {
        switch self {
        case .unpaired: return "questionmark"
        case .active: return "checkmark"
        case .ambiguous: return "exclamationmark"
        case .disabled: return "pause.fill"
        }
    }

    var localizedDescription: String {
        switch self {
        case .unpaired: return FiliusLocalization.t("remoteLink.status.unpaired")
        case .active: return FiliusLocalization.t("remoteLink.status.active")
        case .ambiguous: return FiliusLocalization.t("remoteLink.status.ambiguous")
        case .disabled: return FiliusLocalization.t("remoteLink.status.disabled")
        }
    }
}

extension TopologyEditorState {
    func remoteLinkVisualState(for nodeID: UUID) -> RemoteLinkVisualState? {
        guard graph.node(withID: nodeID)?.kind == .remoteLink,
              let configuration = remoteLinkConfigurationsByNodeID[nodeID] else {
            return nil
        }
        guard configuration.isEnabled else { return .disabled }
        let matchingPeerCount = graph.nodes.filter { node in
            node.id != nodeID
                && node.kind == .remoteLink
                && remoteLinkConfigurationsByNodeID[node.id]?.isEnabled == true
                && remoteLinkConfigurationsByNodeID[node.id]?.pairIdentifier == configuration.pairIdentifier
        }.count
        switch matchingPeerCount {
        case 0: return .unpaired
        case 1: return .active
        default: return .ambiguous
        }
    }
}

struct RemoteLinkSymbolView: View {
    var status: RemoteLinkVisualState?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.95), Color.cyan.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            HStack(spacing: 5) {
                Circle().fill(.white).frame(width: 13, height: 13)
                Capsule().fill(.white.opacity(0.9)).frame(width: 26, height: 6)
                Circle().fill(.white).frame(width: 13, height: 13)
            }
            if let status {
                Image(systemName: status.systemImage)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(status.color, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .offset(x: 27, y: 18)
            }
        }
        .shadow(color: Color.black.opacity(0.22), radius: 2, y: 1)
    }
}

struct TopologyMainMenuView: View {
    let simulationPhase: TopologySimulationPhase
    let workspaceMode: TopologyWorkspaceMode
    let simulationSpeed: TopologySimulationSpeed
    let isPersistenceBusy: Bool
    let canUndo: Bool
    let canRedo: Bool
    let showsProtocolApplicationBuilder: Bool
    let onSimulationSpeedChanged: (Int) -> Void
    let onNewProject: () -> Void
    let onOpenProject: () -> Void
    let onSaveProject: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onEnterDocumentation: () -> Void
    let onEnterDesign: () -> Void
    let onStartSimulation: () -> Void
    let onStopSimulation: () -> Void
    let onShowProtocolApplicationBuilder: () -> Void
    let onShowHelp: () -> Void
    let onShowInformation: () -> Void
    let onShowSettings: () -> Void

    var body: some View {
        GeometryReader { proxy in
            Group {
                if proxy.size.width >= 760 {
                    regularToolbar
                } else {
                    compactToolbar
                }
            }
            .padding(.horizontal, 8)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: 68)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
        .overlay(alignment: .topLeading) {
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("java.mainMenu")
                .allowsHitTesting(false)
        }
    }

    private var regularToolbar: some View {
        HStack(spacing: FiliusExperienceTokens.regularSpacing) {
            toolbarGroup {
                actionButton(FiliusLocalization.t("menu.new"), image: "allgemein/neu.png", identifier: "java.menu.new", enabled: canEditProject, action: onNewProject)
                actionButton(FiliusLocalization.t("menu.open"), image: "allgemein/oeffnen.png", identifier: "java.menu.open", enabled: canEditProject, action: onOpenProject)
                actionButton(FiliusLocalization.t("menu.save"), image: "allgemein/speichern.png", identifier: "java.menu.save", enabled: canEditProject, action: onSaveProject)
            }
            toolbarGroup {
                modeButton(FiliusLocalization.t("menu.designMode"), image: "allgemein/entwurfsmodus.png", identifier: "runtime.control.stop", selected: simulationPhase == .stopped && workspaceMode == .design, enabled: simulationPhase == .running || workspaceMode != .design) {
                    simulationPhase == .running ? onStopSimulation() : onEnterDesign()
                }
                modeButton(FiliusLocalization.t("menu.simulationMode"), image: "allgemein/aktionsmodus.png", identifier: "runtime.control.start", selected: simulationPhase == .running, enabled: workspaceMode == .design && simulationPhase == .stopped) { onStartSimulation() }
                modeButton(FiliusLocalization.t("menu.documentation"), image: "allgemein/dokumodus.png", identifier: "java.mode.documentation", selected: simulationPhase == .stopped && workspaceMode == .documentation, enabled: simulationPhase == .stopped) { onEnterDocumentation() }
            }
            speedControl
            Spacer(minLength: 0)
            toolbarGroup {
                compactImageButton(FiliusLocalization.t("menu.help"), image: "allgemein/hilfe.png", identifier: "java.menu.help", action: onShowHelp)
                compactImageButton(FiliusLocalization.t("menu.information"), image: "allgemein/info.png", identifier: "java.menu.info", action: onShowInformation)
                overflowMenu
            }
        }
    }

    private var compactToolbar: some View {
        HStack(spacing: FiliusExperienceTokens.compactSpacing) {
            Menu {
                Button(FiliusLocalization.t("menu.new"), action: onNewProject).disabled(!canEditProject)
                Button(FiliusLocalization.t("menu.open"), action: onOpenProject).disabled(!canEditProject)
                Button(FiliusLocalization.t("menu.save"), action: onSaveProject).disabled(!canEditProject)
                Divider()
                Button(FiliusLocalization.t("menu.undo"), action: onUndo)
                    .disabled(!canUseUndo || !canUndo)
                    .accessibilityIdentifier("java.menu.undo")
                Button(FiliusLocalization.t("menu.redo"), action: onRedo)
                    .disabled(!canUseUndo || !canRedo)
                    .accessibilityIdentifier("java.menu.redo")
            } label: { Label(FiliusLocalization.t("menu.file"), systemImage: "folder") }
            .buttonStyle(.bordered)
            toolbarGroup {
                compactModeButton(FiliusLocalization.t("menu.designMode"), image: "hammer", identifier: "runtime.control.stop", selected: simulationPhase == .stopped && workspaceMode == .design, enabled: simulationPhase == .running || workspaceMode != .design) { simulationPhase == .running ? onStopSimulation() : onEnterDesign() }
                compactModeButton(FiliusLocalization.t("menu.simulationMode"), image: "play.fill", identifier: "runtime.control.start", selected: simulationPhase == .running, enabled: workspaceMode == .design && simulationPhase == .stopped) { onStartSimulation() }
                compactModeButton(FiliusLocalization.t("menu.documentation"), image: "pencil", identifier: "java.mode.documentation", selected: simulationPhase == .stopped && workspaceMode == .documentation, enabled: simulationPhase == .stopped) { onEnterDocumentation() }
            }
            speedControl
            overflowMenu
        }
    }

    private var canEditProject: Bool { simulationPhase == .stopped && !isPersistenceBusy }
    private var canUseUndo: Bool { simulationPhase == .stopped && !isPersistenceBusy }

    private var speedControl: some View {
        HStack(spacing: 4) {
            Slider(value: Binding(get: { Double(simulationSpeed.percent) }, set: { onSimulationSpeedChanged(Int($0.rounded())) }), in: Double(TopologySimulationSpeed.minimumPercent)...Double(TopologySimulationSpeed.maximumPercent), step: 1)
                .frame(minWidth: 64, idealWidth: 105, maxWidth: 120)
                .accessibilityLabel(FiliusLocalization.t("menu.simulationSpeed"))
                .accessibilityValue(simulationSpeed.accessibilityValue)
                .accessibilityIdentifier("simulation.speed.slider")
            Text("\(simulationSpeed.percent)%")
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(width: 38, alignment: .trailing)
                .accessibilityIdentifier("simulation.speed.value")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(FiliusExperienceTokens.toolbarSurface, in: RoundedRectangle(cornerRadius: FiliusExperienceTokens.groupCornerRadius))
    }

    private var overflowMenu: some View {
        Menu {
            Button(FiliusLocalization.t("menu.undo"), action: onUndo)
                .disabled(!canUseUndo || !canUndo)
                .accessibilityIdentifier("java.menu.undo")
            Button(FiliusLocalization.t("menu.redo"), action: onRedo)
                .disabled(!canUseUndo || !canRedo)
                .accessibilityIdentifier("java.menu.redo")
            Divider()
            Button(FiliusLocalization.t("menu.help"), action: onShowHelp)
            Button(FiliusLocalization.t("menu.information"), action: onShowInformation)
            if showsProtocolApplicationBuilder {
                Button(FiliusLocalization.t("menu.protocolBuilder"), action: onShowProtocolApplicationBuilder).disabled(!canEditProject)
            }
            Button(FiliusLocalization.t("menu.settings"), action: onShowSettings)
        } label: { Image(systemName: "ellipsis.circle").font(.title2).frame(width: 44, height: 44) }
        .accessibilityLabel(FiliusLocalization.t("menu.more"))
        .accessibilityIdentifier("java.menu.overflow")
    }

    private func toolbarGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 4) { content() }
            .padding(4)
            .background(FiliusExperienceTokens.toolbarSurface, in: RoundedRectangle(cornerRadius: FiliusExperienceTokens.groupCornerRadius))
    }

    private func actionButton(_ title: String, image: String, identifier: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TopologyParityImageView(relativePath: image, fallbackSystemImage: "square", contentMode: .fit)
                .frame(width: 30, height: 30)
                .frame(width: FiliusExperienceTokens.minimumHitSize, height: FiliusExperienceTokens.minimumHitSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .frame(minHeight: FiliusExperienceTokens.minimumHitSize)
        .contentShape(Rectangle())
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
    }

    private func modeButton(_ title: String, image: String, identifier: String, selected: Bool, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TopologyParityImageView(relativePath: image, fallbackSystemImage: "circle", contentMode: .fit)
                .frame(width: 30, height: 30)
                .frame(width: FiliusExperienceTokens.minimumHitSize, height: FiliusExperienceTokens.minimumHitSize)
                .background(selected ? FiliusExperienceTokens.selectedSurface : .clear, in: RoundedRectangle(cornerRadius: 9))
                .overlay { if selected { RoundedRectangle(cornerRadius: 9).stroke(Color.accentColor, lineWidth: 2) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .frame(minHeight: FiliusExperienceTokens.minimumHitSize)
        .contentShape(Rectangle())
        .disabled(!enabled || isPersistenceBusy)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func compactModeButton(_ title: String, image: String, identifier: String, selected: Bool, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: image).frame(width: 34, height: 34).background(selected ? FiliusExperienceTokens.selectedSurface : .clear, in: RoundedRectangle(cornerRadius: 8)) }
            .buttonStyle(.plain).disabled(!enabled || isPersistenceBusy).accessibilityLabel(title).accessibilityIdentifier(identifier).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func compactImageButton(_ title: String, image: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { TopologyParityImageView(relativePath: image, fallbackSystemImage: "questionmark", contentMode: .fit).frame(width: 32, height: 32).frame(width: 44, height: 44) }
            .buttonStyle(.plain).accessibilityLabel(title).accessibilityIdentifier(identifier)
    }
}

enum TopologyPalettePresentation {
    case sidebar
    case compactShelf
}

struct TopologyPaletteView: View {
    let activeTool: TopologyEditorToolMode
    let simulationPhase: TopologySimulationPhase
    let onSelectTool: (TopologyEditorToolMode) -> Void
    let onPaletteDragPrepared: (TopologyNodeKind) -> Void
    var presentation: TopologyPalettePresentation = .sidebar

    @ViewBuilder
    var body: some View {
        switch presentation {
        case .sidebar:
            sidebar
        case .compactShelf:
            compactShelf
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    sidebarToolButton(
                        title: FiliusLocalization.t("palette.cable"),
                        mode: .connect,
                        draggableNodeKind: nil,
                        iconRelativePath: "hardware/kabel.png",
                        iconSize: CGSize(width: 80, height: 56),
                        fallbackSystemImage: "link",
                        identifier: "palette.tool.connect"
                    )

                    sidebarToolButton(
                        title: FiliusLocalization.t("palette.pc"),
                        mode: .place(.pc),
                        draggableNodeKind: .pc,
                        iconRelativePath: "hardware/server.png",
                        iconSize: CGSize(width: 64, height: 94),
                        fallbackSystemImage: "desktopcomputer",
                        identifier: "palette.tool.place.pc"
                    )

                    sidebarToolButton(
                        title: FiliusLocalization.t("palette.notebook"),
                        mode: .place(.notebook),
                        draggableNodeKind: .notebook,
                        iconRelativePath: "hardware/laptop.png",
                        iconSize: CGSize(width: 84, height: 80),
                        fallbackSystemImage: "laptopcomputer",
                        identifier: "palette.tool.place.notebook"
                    )

                    sidebarToolButton(
                        title: FiliusLocalization.t("palette.switch"),
                        mode: .place(.networkSwitch),
                        draggableNodeKind: .networkSwitch,
                        iconRelativePath: "hardware/switch.png",
                        iconSize: CGSize(width: 70, height: 52),
                        fallbackSystemImage: "switch.2",
                        identifier: "palette.tool.place.switch"
                    )

                    sidebarToolButton(
                        title: FiliusLocalization.t("palette.gateway"),
                        mode: .place(.gateway),
                        draggableNodeKind: .gateway,
                        iconRelativePath: "hardware/gateway.png",
                        iconSize: CGSize(width: 77, height: 58),
                        fallbackSystemImage: "network",
                        identifier: "palette.tool.place.gateway"
                    )

                    sidebarToolButton(
                        title: FiliusLocalization.t("palette.router"),
                        mode: .place(.router),
                        draggableNodeKind: .router,
                        iconRelativePath: "hardware/router.png",
                        iconSize: CGSize(width: 77, height: 58),
                        fallbackSystemImage: "arrow.triangle.branch",
                        identifier: "palette.tool.place.router"
                    )

                    sidebarToolButton(
                        title: FiliusLocalization.t("palette.remoteLink"),
                        mode: .place(.remoteLink),
                        draggableNodeKind: .remoteLink,
                        iconRelativePath: "hardware/modem.png",
                        iconSize: CGSize(width: 80, height: 56),
                        fallbackSystemImage: "point.3.connected.trianglepath.dotted",
                        identifier: "palette.tool.place.remote-link"
                    )
                }
                .padding(.top, 6)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topLeading) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityIdentifier("palette.toolbar.content")
                        .allowsHitTesting(false)
                }
            }

            Rectangle()
                .fill(Color.black.opacity(0.28))
                .frame(height: 1)

            sidebarToolButton(
                title: FiliusLocalization.t("palette.select"),
                mode: .select,
                draggableNodeKind: nil,
                iconRelativePath: "allgemein/auswahl.png",
                iconSize: CGSize(width: 38, height: 38),
                fallbackSystemImage: "cursorarrow",
                identifier: "palette.tool.select"
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
        }
        .frame(width: 152)
        .background {
            TopologyParityImageView(
                relativePath: "allgemein/leisten_hg.png",
                fallbackSystemImage: nil,
                contentMode: .fill,
                isTiled: true
            )
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.black.opacity(0.3))
                .frame(width: 1)
        }
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("palette.toolbar")
                .allowsHitTesting(false)
        }
    }

    private var compactShelf: some View {
        HStack(spacing: 8) {
            compactToolButton(
                title: FiliusLocalization.t("palette.select"),
                systemImage: "cursorarrow",
                mode: .select,
                identifier: "palette.compact.select"
            )
            compactToolButton(
                title: FiliusLocalization.t("palette.cable"),
                systemImage: "link",
                mode: .connect,
                identifier: "palette.compact.connect"
            )
            Divider().frame(height: 44)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    compactDeviceButton(.pc, title: FiliusLocalization.t("palette.pc"), image: "desktopcomputer")
                    compactDeviceButton(.notebook, title: FiliusLocalization.t("palette.notebook"), image: "laptopcomputer")
                    compactDeviceButton(.networkSwitch, title: FiliusLocalization.t("palette.switch"), image: "switch.2")
                    compactDeviceButton(.gateway, title: FiliusLocalization.t("palette.gateway"), image: "network")
                    compactDeviceButton(.router, title: FiliusLocalization.t("palette.router"), image: "arrow.triangle.branch")
                    compactDeviceButton(.remoteLink, title: FiliusLocalization.t("palette.remoteLink"), image: "point.3.connected.trianglepath.dotted")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
        .accessibilityIdentifier("palette.compact")
    }

    private func compactToolButton(
        title: String,
        systemImage: String,
        mode: TopologyEditorToolMode,
        identifier: String
    ) -> some View {
        Button { onSelectTool(mode) } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .background(activeTool == mode ? FiliusExperienceTokens.selectedSurface : .clear, in: RoundedRectangle(cornerRadius: 9))
                .overlay { if activeTool == mode { RoundedRectangle(cornerRadius: 9).stroke(Color.accentColor, lineWidth: 2) } }
        }
        .buttonStyle(.plain)
        .disabled(!isEditingEnabled)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func compactDeviceButton(_ kind: TopologyNodeKind, title: String, image: String) -> some View {
        let mode = TopologyEditorToolMode.place(kind)
        let button = Button { onSelectTool(mode) } label: {
            Group {
                if kind == .remoteLink {
                    TopologyParityImageView(
                        relativePath: "hardware/modem.png",
                        fallbackSystemImage: image,
                        contentMode: .fit
                    )
                    .frame(width: 40, height: 34)
                } else {
                    Image(systemName: image)
                        .font(.title3)
                }
            }
            .frame(width: 44, height: 44)
            .background(activeTool == mode ? FiliusExperienceTokens.selectedSurface : .clear, in: RoundedRectangle(cornerRadius: 9))
            .overlay { if activeTool == mode { RoundedRectangle(cornerRadius: 9).stroke(Color.accentColor, lineWidth: 2) } }
        }
        .buttonStyle(.plain)
        .disabled(!isEditingEnabled)
        .accessibilityLabel(title)
        .accessibilityIdentifier("palette.compact.place.\(kind.rawValue)")

        if isEditingEnabled {
            button.onDrag {
                onPaletteDragPrepared(kind)
                return NSItemProvider(object: kind.rawValue as NSString)
            }
        } else {
            button
        }
    }

    private var isEditingEnabled: Bool {
        simulationPhase == .stopped
    }

    @ViewBuilder
    private func sidebarToolButton(
        title: String,
        mode: TopologyEditorToolMode,
        draggableNodeKind: TopologyNodeKind?,
        iconRelativePath: String,
        iconSize: CGSize,
        fallbackSystemImage: String,
        identifier: String,
        usesRemoteLinkSymbol: Bool = false
    ) -> some View {
        let button = Button {
            onSelectTool(mode)
        } label: {
            JavaSidebarToolLabel(
                title: title,
                iconRelativePath: iconRelativePath,
                iconSize: iconSize,
                fallbackSystemImage: fallbackSystemImage,
                isSelected: activeTool == mode,
                isEnabled: isEditingEnabled,
                usesRemoteLinkSymbol: usesRemoteLinkSymbol
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEditingEnabled)
        .accessibilityLabel(accessibilityTitle(for: mode))
        .accessibilityIdentifier(identifier)

        if let draggableNodeKind, isEditingEnabled {
            button.onDrag {
                onPaletteDragPrepared(draggableNodeKind)
                return NSItemProvider(object: draggableNodeKind.rawValue as NSString)
            }
        } else {
            button
        }
    }

    private func accessibilityTitle(for mode: TopologyEditorToolMode) -> String {
        switch mode {
        case .select:
            return FiliusLocalization.t("palette.select")
        case .connect:
            return FiliusLocalization.t("palette.connect")
        case .place(.pc):
            return FiliusLocalization.t("palette.pc")
        case .place(.notebook):
            return FiliusLocalization.t("palette.notebook")
        case .place(.networkSwitch):
            return FiliusLocalization.t("palette.switch")
        case .place(.router):
            return FiliusLocalization.t("palette.router")
        case .place(.gateway):
            return FiliusLocalization.t("palette.gateway")
        case .place(.remoteLink):
            return FiliusLocalization.t("palette.remoteLink")
        case .place(.unsupported):
            return FiliusLocalization.t("palette.unsupported")
        }
    }
}

private struct JavaSidebarToolLabel: View {
    let title: String
    let iconRelativePath: String
    let iconSize: CGSize
    let fallbackSystemImage: String
    let isSelected: Bool
    let isEnabled: Bool
    var usesRemoteLinkSymbol = false

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if usesRemoteLinkSymbol {
                    RemoteLinkSymbolView(status: nil)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                } else {
                    TopologyParityImageView(
                        relativePath: iconRelativePath,
                        fallbackSystemImage: fallbackSystemImage,
                        contentMode: .fit
                    )
                }
            }
            .frame(width: iconSize.width, height: iconSize.height)

            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Color.black.opacity(isEnabled ? 0.9 : 0.42))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: iconSize.height + 21)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            isSelected ? FiliusExperienceTokens.selectedSurface : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .opacity(isEnabled ? 1 : 0.62)
    }
}

private struct TopologyParityImageView: View {
    let relativePath: String
    let fallbackSystemImage: String?
    let contentMode: ContentMode
    var isTiled = false

    var body: some View {
        if let image = TopologyParityAssetLoader.load(relativePath: relativePath) {
            if isTiled {
                Image(uiImage: image)
                    .resizable(resizingMode: .tile)
            } else {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        } else if let fallbackSystemImage {
            Image(systemName: fallbackSystemImage)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            Color.clear
        }
    }
}

private struct JavaImageButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.12 : 0)
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}
