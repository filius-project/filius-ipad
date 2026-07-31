import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct TopologyEditorView: View {
    @Environment(\.undoManager) private var systemUndoManager

    @Binding var state: TopologyEditorState
    @Binding var appPreferences: TopologyAppPreferences
    let isPersistenceBusy: Bool
    let stateReplacementGeneration: UInt64
    let onExternalStateReplacement: (TopologyEditorState) -> Void
    let onRestoreAppPreferences: () -> Void

    @State private var activeNodeDragTranslations: [UUID: CGSize] = [:]
    @State private var activeDocumentationDragTranslations: [UUID: CGSize] = [:]
    @State private var nodeDragInFlight = false
    @State private var documentationDragInFlight = false
    @State private var isHardwarePaletteCollapsed = false
    @State private var simulationTickTask: Task<Void, Never>?
    @State private var simulationClockDriver = TopologySimulationClockDriver()
    @State private var designConfigurationNodeID: UUID?
    @State private var designConfigurationDraft: TopologyDesignDeviceConfigurationDraft?
    @State private var designConfigurationBaseline: TopologyDesignDeviceConfigurationDraft?
    @State private var pendingConfigurationSelection: PendingConfigurationSelection?
    @State private var isShowingUnsavedConfigurationAlert = false
    @State private var isRegularEditorLayout = true
    @State private var connectionPortPickerNodeID: UUID?
    @State private var pendingRouterPortRemoval: RouterPortRemovalItem?
    @State private var isImportingFiliusProject = false
    @State private var filiusExportSession: FiliusProjectExportSession?
    // Explicit Java-compatible archive entries are session data, never native autosave data.
    @State private var filiusSupplementalArchiveEntries: [String: Data] = [:]
    @State private var filiusOpaqueContent: TopologyFLSOpaqueContent = .empty
    @State private var documentationEditorItemID: UUID?
    @State private var isExportingDocumentationImage = false
    @State private var documentationImageDocument: TopologyPNGFileDocument?
    @State private var isExportingDocumentationPDF = false
    @State private var documentationPDFDocument: TopologyPDFFileDocument?
    @State private var projectFileNotice: ProjectFileNotice?
    @State private var isShowingContextualHelp = false
    @State private var isShowingProductInformation = false
    @State private var isShowingProductSettings = false
    @State private var isShowingProtocolApplicationBuilder = false
    @State private var isShowingGuidedTour = false
    @StateObject private var undoCoordinator = TopologyEditorUndoCoordinator()

    private let canvasWorldBounds = CGRect(x: -10_000, y: -10_000, width: 20_000, height: 20_000)

    private enum EditorCommand {
        case newProject
        case openProject
        case saveProject
        case undo
        case redo
        case deleteSelection
        case designMode
        case simulationMode
        case documentationMode
        case cancel
    }

    var body: some View {
        editorContent
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            mainMenu

            if isPersistenceBusy {
                Text(FiliusLocalization.t("persistence.restore.inProgress"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.yellow.opacity(0.55))
                    .accessibilityIdentifier("persistence.restore.inProgress")
            }

            if state.isRecoveryNoticeVisible {
                recoveryNoticeBanner
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(FiliusExperienceTokens.javaPanelSurface)
            }

            GeometryReader { proxy in
                editorWorkspace(width: proxy.size.width)
                    .onAppear {
                        isRegularEditorLayout = !usesCompactEditorLayout(width: proxy.size.width)
                    }
                    .onChange(of: proxy.size.width) { _, width in
                        isRegularEditorLayout = !usesCompactEditorLayout(width: width)
                    }
            }
        }
        .background(FiliusExperienceTokens.javaPanelSurface)
        .allowsHitTesting(!isPersistenceBusy)
        .overlay(alignment: .topLeading) {
            if isUITesting {
                TopologyDebugOverlayView(state: state)
                    .overlay {
                        Color.clear
                            .accessibilityElement()
                            .accessibilityIdentifier("debug.overlay")
                    }
                    .opacity(0.001)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            keyboardCommandLayer
        }
        .sheet(isPresented: $isShowingProtocolApplicationBuilder) {
            TopologyProtocolApplicationBuilderView(
                definitions: state.sortedProtocolApplicationDefinitions,
                onCreate: { send(.createProtocolApplication(definition: $0)) },
                onUpdate: { send(.updateProtocolApplication(definition: $0)) },
                onDelete: { send(.deleteProtocolApplication(definitionID: $0)) },
                onClose: { isShowingProtocolApplicationBuilder = false }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $isShowingContextualHelp) {
            TopologyContextualHelpSheet(context: currentHelpContext)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isShowingProductInformation) {
            TopologyProductInformationSheet(metadata: .current())
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isShowingProductSettings) {
            TopologyProductSettingsSheet(
                preferences: $appPreferences,
                onShowGuidedTour: {
                    isShowingProductSettings = false
                    Task { @MainActor in
                        await Task.yield()
                        isShowingGuidedTour = true
                    }
                },
                onRestoreDefaults: onRestoreAppPreferences
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isShowingGuidedTour) {
            TopologyGuidedTourView(
                onSkip: completeGuidedTour,
                onComplete: completeGuidedTour
            )
            .interactiveDismissDisabled()
        }
        .fullScreenCover(item: runtimeDeviceSheetBinding) { item in
            runtimeDeviceSheet(for: item.id)
        }
        .sheet(item: designDeviceSheetBinding) { item in
            designDeviceSheet(for: item.id)
        }
        .alert(
            FiliusLocalization.t("inspector.unsaved.title"),
            isPresented: $isShowingUnsavedConfigurationAlert,
            presenting: pendingConfigurationSelection
        ) { _ in
            if let nodeID = designConfigurationNodeID,
               let node = state.graph.node(withID: nodeID),
               let draft = designConfigurationDraft,
               draft.isValid(for: node, availableSSIDs: availableDesignSSIDs) {
                Button(FiliusLocalization.t("inspector.unsaved.saveAndSwitch")) {
                    saveAndApplyPendingConfigurationSelection()
                }
                .accessibilityIdentifier("design.configuration.unsaved.saveAndSwitch")
            }
            Button(FiliusLocalization.t("inspector.unsaved.discardAndSwitch"), role: .destructive) {
                discardAndApplyPendingConfigurationSelection()
            }
            .accessibilityIdentifier("design.configuration.unsaved.discardAndSwitch")
            Button(FiliusLocalization.t("inspector.unsaved.keepEditing"), role: .cancel) {
                keepEditingCurrentConfiguration()
            }
            .accessibilityIdentifier("design.configuration.unsaved.keepEditing")
        } message: { _ in
            Text(FiliusLocalization.t("inspector.unsaved.message"))
        }
        .sheet(item: documentationEditorBinding) { item in
            TopologyDocumentationItemEditorSheet(
                item: item,
                onSave: { updated in
                    send(.updateDocumentationItem(item: updated))
                    if state.lastValidationError == nil {
                        documentationEditorItemID = nil
                    }
                },
                onCancel: { documentationEditorItemID = nil }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: connectionPortPickerBinding) { item in
            connectionPortPicker(for: item.id)
        }
        .alert(
            FiliusLocalization.t("editor.alert.removeInterface.title"),
            isPresented: routerRemovalAlertPresented,
            presenting: pendingRouterPortRemoval
        ) { item in
            Button(FiliusLocalization.t("ui.f78b6376e028"), role: .destructive) {
                send(
                    .removeRouterInterface(
                        nodeID: item.nodeID,
                        portID: item.portID,
                        confirmed: true
                    )
                )
                pendingRouterPortRemoval = nil
            }
            Button(FiliusLocalization.t("ui.07af7cb30fca"), role: .cancel) {
                pendingRouterPortRemoval = nil
            }
        } message: { item in
            Text(FiliusLocalization.t("editor.connectionRemoved", item.label))
        }
        .alert(
            FiliusLocalization.t("persistence.alert.title"),
            isPresented: persistenceAlertPresented,
            presenting: state.lastPersistenceError
        ) { _ in
            Button(FiliusLocalization.t("ui.70afe9eff3f2")) {
                send(.dismissPersistenceError)
            }
        } message: { failure in
            Text(persistenceAlertMessage(for: failure))
                .accessibilityIdentifier("persistence.error.alert")
        }
        .fileImporter(
            isPresented: $isImportingFiliusProject,
            allowedContentTypes: FiliusProjectImportResourcePolicy.allowedContentTypes,
            allowsMultipleSelection: false,
            onCompletion: handleFiliusProjectImport
        )
        .sheet(item: $filiusExportSession) { session in
            FiliusProjectExportPicker(
                fileURL: session.fileURL,
                onCompletion: { result in
                    handleFiliusProjectExport(result, session: session)
                }
            )
            .onDisappear {
                cleanupFiliusProjectExport(at: session.fileURL)
                if filiusExportSession?.id == session.id {
                    filiusExportSession = nil
                }
            }
        }
        .onOpenURL { url in
            guard url.isFileURL else {
                return
            }
            handleFiliusProjectImport(.success([url]))
        }
        .fileExporter(
            isPresented: $isExportingDocumentationImage,
            document: documentationImageDocument,
            contentType: .png,
            defaultFilename: FiliusLocalization.t("project.filename.documentationPNG"),
            onCompletion: handleDocumentationImageExport
        )
        .fileExporter(
            isPresented: $isExportingDocumentationPDF,
            document: documentationPDFDocument,
            contentType: .pdf,
            defaultFilename: FiliusLocalization.t("project.filename.documentationPDF"),
            onCompletion: handleDocumentationPDFExport
        )
        .alert(item: $projectFileNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text(FiliusLocalization.t("ui.9ce3bd4224c8")))
            )
        }
        .onAppear(perform: handleViewAppear)
        .onChange(of: state.simulationPhase) { _, newPhase in
            handleSimulationPhaseChange(newPhase)
        }
        .onChange(of: stateReplacementGeneration, handleStateReplacement)
        .onChange(of: appPreferences.experimentalProtocolApplicationsEnabled) { _, enabled in
            if !enabled {
                isShowingProtocolApplicationBuilder = false
            }
        }
        .onChange(of: appPreferences.simulationSpeed) { _, newSpeed in
            send(.setSimulationSpeed(percent: newSpeed.percent))
        }
        .onDisappear(perform: handleViewDisappear)
    }

    private func completeGuidedTour() {
        appPreferences.hasCompletedGuidedTour = true
        isShowingGuidedTour = false
    }

    private func handleViewDisappear() {
        stopSimulationTickLoop()
        if state.simulationPhase == .running {
            send(.stopSimulation)
        }
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }

    private func usesCompactEditorLayout(width: CGFloat) -> Bool {
        width < 700 || (isUITesting && ProcessInfo.processInfo.arguments.contains("-compact-width-testing"))
    }

    private var currentHelpContext: TopologyProductHelpContext {
        if state.simulationPhase == .running {
            return .simulation
        }
        return state.workspaceMode == .documentation ? .documentation : .design
    }

    private var selectedDocumentationItem: TopologyDocumentationItem? {
        guard let id = state.selectedDocumentationItemID else { return nil }
        return state.documentationItems.first { $0.id == id }
    }

    private var documentationEditorBinding: Binding<TopologyDocumentationItem?> {
        Binding(
            get: {
                guard let id = documentationEditorItemID else { return nil }
                return state.documentationItems.first { $0.id == id }
            },
            set: { item in documentationEditorItemID = item?.id }
        )
    }

    @ViewBuilder
    private func editorWorkspace(width: CGFloat) -> some View {
        if state.workspaceMode == .documentation && state.simulationPhase == .stopped {
            documentationWorkspace
        } else if usesCompactEditorLayout(width: width) {
            compactEditorWorkspace
        } else {
            regularEditorWorkspace
        }
    }

    private var documentationWorkspace: some View {
        HStack(spacing: 0) {
            TopologyDocumentationPaletteView(
                selectedItem: selectedDocumentationItem,
                activeTool: state.documentationTool,
                onSelectTool: { send(.setDocumentationTool(tool: $0)) },
                onEditSelected: { documentationEditorItemID = state.selectedDocumentationItemID },
                onDeleteSelected: { send(.deleteSelectedDocumentationItem) },
                onExportImage: prepareDocumentationImageExport,
                onExportPDF: prepareDocumentationPDFExport
            )
            canvasWorkspace
        }
    }

    private var compactEditorWorkspace: some View {
        VStack(spacing: 0) {
            canvasWorkspace
            TopologyPaletteView(
                activeTool: state.activeTool,
                simulationPhase: state.simulationPhase,
                onSelectTool: setToolMode,
                onPaletteDragPrepared: handlePaletteDragPrepared,
                presentation: .compactShelf
            )
        }
    }

    private var regularEditorWorkspace: some View {
        HStack(spacing: 0) {
            if !isHardwarePaletteCollapsed && regularInspectorNodeID == nil {
                TopologyPaletteView(
                    activeTool: state.activeTool,
                    simulationPhase: state.simulationPhase,
                    onSelectTool: setToolMode,
                    onPaletteDragPrepared: handlePaletteDragPrepared
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            canvasWorkspace
                .overlay(alignment: .topLeading) {
                    if regularInspectorNodeID == nil {
                        paletteToggleButton
                    }
                }

            if let nodeID = regularInspectorNodeID {
                Divider()
                designDeviceEditor(for: nodeID, presentation: .inspector)
                    .frame(width: 360)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onChange(of: state.selectedNodeIDs) { _, _ in
            handleRegularInspectorSelectionChange()
        }
    }

    private var paletteToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isHardwarePaletteCollapsed.toggle()
            }
        } label: {
            Image(systemName: "sidebar.left")
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .padding(8)
        .accessibilityLabel(isHardwarePaletteCollapsed ? FiliusLocalization.t("palette.expand") : FiliusLocalization.t("palette.collapse"))
        .accessibilityIdentifier("palette.toggle")
    }

    private var regularInspectorNodeID: UUID? {
        guard state.workspaceMode == .design,
              state.simulationPhase == .stopped,
              let nodeID = designConfigurationNodeID,
              let node = state.graph.node(withID: nodeID),
              node.kind != .unsupported
        else {
            return nil
        }
        return nodeID
    }

    private var documentationStatusStrip: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(FiliusLocalization.t("ui.e4fecfcb0f1c"))
                    .font(.system(size: 13, weight: .semibold))
                Text(selectedDocumentationItem.map { FiliusLocalization.t("editor.selected", $0.kind.rawValue) }
                    ?? FiliusLocalization.t("help.documentation.create.detail"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.black.opacity(0.72))
            }
            Spacer()
            Text(FiliusLocalization.t("editor.elementCount", state.documentationItems.count))
                .font(.system(size: 12, weight: .medium))
                .padding(.trailing, 14)
        }
        .padding(.horizontal, 14)
        .frame(height: 76)
        .background { JavaConfigurationBackground() }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.black.opacity(0.3)).frame(height: 1)
        }
        .accessibilityIdentifier("documentation.status")
    }

    private var canvasWorkspace: some View {
        VStack(spacing: 0) {
            TopologyCanvasView(
                state: state,
                onTap: handleCanvasTap,
                onNodeDragChanged: handleNodeDragChanged,
                onNodeDragEnded: handleNodeDragEnded,
                onDocumentationSelect: { send(.selectDocumentationItem(itemID: $0)) },
                onDocumentationDragChanged: handleDocumentationDragChanged,
                onDocumentationDragEnded: handleDocumentationDragEnded,
                onCanvasPan: handleCanvasPan,
                onCanvasPanEnded: {
                    nodeDragInFlight = false
                    documentationDragInFlight = false
                },
                onMarqueeSelection: { screenRect in
                    send(.selectNodes(in: state.viewport.screenRectToWorld(screenRect)))
                },
                onMagnify: handleCanvasMagnify,
                onMagnifyEnded: { },
                onConfigureNode: { requestDesignConfiguration(for: $0) },
                onDeleteNode: deleteNodeFromContextMenu,
                onStartConnection: startConnectionFromContextMenu,
                onInspectRuntimeNode: { send(.openRuntimeDevice(nodeID: $0)) },
                onDeleteLink: { send(.deleteLink(linkID: $0)) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dropDestination(for: String.self) { items, location in
                handlePaletteDrop(items: items, location: location)
            }

            if state.workspaceMode == .documentation && state.simulationPhase == .stopped {
                documentationStatusStrip
            } else {
                javaConfigurationStrip
            }
        }
    }

    private var javaConfigurationStrip: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.black.opacity(0.18))
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(configurationStripTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.84))

                Text(configurationStripDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.black.opacity(0.72))
                    .lineLimit(2)
            }

            Spacer()

            if state.simulationPhase == .stopped {
                if let selectedNode, selectedNode.kind != .unsupported {
                    Button(FiliusLocalization.t("ui.a2eb163fcbf0")) {
                        requestDesignConfiguration(for: selectedNode.id)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("design.configuration.open")

                    if selectedNode.kind == .router {
                        routerInterfaceMenu(for: selectedNode)
                    }
                }

                if !state.selectedNodeIDs.isEmpty || !state.selectedLinkIDs.isEmpty {
                    Button(FiliusLocalization.t("ui.ffa5a8a7e21d"), role: .destructive) {
                        send(.deleteSelection)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("topology.selection.delete")
                }
            }

            if state.simulationPhase == .running && appPreferences.showsVirtualClock {
                TopologyVirtualClockStatusView(
                    currentTimeMilliseconds: state.networkRuntime.state.currentTimeMilliseconds,
                    speed: appPreferences.simulationSpeed
                )
            }

            Text(state.simulationPhase == .running ? "Aktionsmodus" : "Entwurfsmodus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.72))
                .padding(.trailing, 14)
        }
        .frame(height: 76)
        .background {
            JavaConfigurationBackground()
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.3))
                .frame(height: 1)
        }
        .accessibilityIdentifier("java.configurationStrip")
    }

    private var configurationStripTitle: String {
        if let selectedNode {
            return selectedNode.displayName
        }
        if selectedLink != nil {
            return FiliusLocalization.t("editor.config.cable")
        }
        return FiliusLocalization.t("editor.config.properties")
    }

    private var configurationStripDetail: String {
        if let selectedNode {
            let occupiedPorts = selectedNode.ports.filter(\.isOccupied).count
            return FiliusLocalization.t("editor.selection.summary", javaDisplayName(for: selectedNode.kind), selectedNode.ports.count, occupiedPorts)
        }
        if let selectedLink,
           let source = state.graph.node(withID: selectedLink.sourceNodeID),
           let target = state.graph.node(withID: selectedLink.targetNodeID) {
            let sourcePort = source.ports.first(where: { $0.id == selectedLink.sourcePortID })?.label ?? "?"
            let targetPort = target.ports.first(where: { $0.id == selectedLink.targetPortID })?.label ?? "?"
            return FiliusLocalization.t("editor.selection.link", source.displayName, sourcePort, target.displayName, targetPort)
        }
        return FiliusLocalization.t("editor.selection.empty")
    }

    private var selectedNode: TopologyNode? {
        guard let selectedNodeID = state.selectedNodeIDs.first else {
            return nil
        }
        return state.graph.node(withID: selectedNodeID)
    }

    private var selectedLink: TopologyLink? {
        guard let linkID = state.selectedLinkIDs.first else {
            return nil
        }
        return state.graph.links.first(where: { $0.id == linkID })
    }

    @ViewBuilder
    private func routerInterfaceMenu(for node: TopologyNode) -> some View {
        Menu(FiliusLocalization.t("ui.38b9db2a96c2")) {
            Button(FiliusLocalization.t("ui.3111a40aa513")) {
                send(.addRouterInterface(nodeID: node.id, portID: UUID()))
            }
            Divider()
            ForEach(node.ports) { port in
                Button(FiliusLocalization.t("editor.port.remove", port.label), role: .destructive) {
                    if state.graph.isPortConnected(nodeID: node.id, portID: port.id) {
                        pendingRouterPortRemoval = RouterPortRemovalItem(
                            nodeID: node.id,
                            portID: port.id,
                            label: port.label
                        )
                    } else {
                        send(
                            .removeRouterInterface(
                                nodeID: node.id,
                                portID: port.id,
                                confirmed: true
                            )
                        )
                    }
                }
                .disabled(node.ports.count <= 1)
            }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("router.interfaces.menu")
    }

    private func javaDisplayName(for kind: TopologyNodeKind) -> String {
        switch kind {
        case .pc:
            return FiliusLocalization.t("model.pc")
        case .notebook:
            return FiliusLocalization.t("model.notebook")
        case .networkSwitch:
            return FiliusLocalization.t("model.switch")
        case .router:
            return FiliusLocalization.t("model.router")
        case .gateway:
            return FiliusLocalization.t("model.gateway")
        case .remoteLink:
            return FiliusLocalization.t("model.remoteLink")
        case .unsupported:
            return FiliusLocalization.t("model.unsupported")
        }
    }

    private var routerRemovalAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingRouterPortRemoval != nil },
            set: { if !$0 { pendingRouterPortRemoval = nil } }
        )
    }

    private var connectionPortPickerBinding: Binding<ConnectionPortPickerItem?> {
        Binding(
            get: {
                guard state.simulationPhase == .stopped,
                      state.activeTool == .connect,
                      let nodeID = connectionPortPickerNodeID,
                      state.graph.containsNode(id: nodeID)
                else {
                    return nil
                }
                return ConnectionPortPickerItem(id: nodeID)
            },
            set: { connectionPortPickerNodeID = $0?.id }
        )
    }

    private var designDeviceSheetBinding: Binding<DesignDeviceSheetItem?> {
        Binding(
            get: {
                guard !isRegularEditorLayout,
                      state.simulationPhase == .stopped,
                      let nodeID = designConfigurationNodeID,
                      state.graph.containsNode(id: nodeID)
                else {
                    return nil
                }
                return DesignDeviceSheetItem(id: nodeID)
            },
            set: { newValue in
                if let nodeID = newValue?.id {
                    requestDesignConfiguration(for: nodeID)
                } else if !isRegularEditorLayout {
                    closeDesignConfiguration()
                }
            }
        )
    }

    private var runtimeDeviceSheetBinding: Binding<RuntimeDeviceSheetItem?> {
        Binding(
            get: {
                guard let nodeID = state.openedRuntimeDeviceID,
                      state.graph.containsNode(id: nodeID)
                else {
                    return nil
                }

                return RuntimeDeviceSheetItem(id: nodeID)
            },
            set: { newValue in
                guard let newValue else {
                    send(.closeRuntimeDevice)
                    return
                }

                send(.openRuntimeDevice(nodeID: newValue.id))
            }
        )
    }

    private var persistenceAlertPresented: Binding<Bool> {
        Binding(
            get: {
                state.lastPersistenceError != nil
            },
            set: { isPresented in
                if !isPresented {
                    send(.dismissPersistenceError)
                }
            }
        )
    }

    private var recoveryNoticeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: state.lastRecoverySucceeded == false ? "exclamationmark.triangle.fill" : "arrow.clockwise.circle.fill")
                .foregroundStyle(state.lastRecoverySucceeded == false ? Color.orange : Color.green)

            Text(state.lastRecoveryMessage ?? FiliusLocalization.t("ui.66461601ca7f"))
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(FiliusLocalization.t("ui.70afe9eff3f2")) {
                send(.dismissRecoveryNotice)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("recovery.notice.dismiss")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(state.lastRecoverySucceeded == false ? Color.orange.opacity(0.5) : Color.green.opacity(0.45), lineWidth: 1)
        }
        .accessibilityIdentifier("recovery.notice.banner")
    }

    @ViewBuilder
    private func connectionPortPicker(for nodeID: UUID) -> some View {
        if let node = state.graph.node(withID: nodeID) {
            let availablePortIDs = Set(state.graph.availablePortIDs(for: nodeID))
            TopologyConnectionPortPickerSheet(
                node: node,
                availablePortIDs: availablePortIDs,
                isSourceSelection: state.pendingConnection == nil,
                onSelect: { portID in
                    if state.pendingConnection == nil {
                        send(.startConnection(nodeID: nodeID, portID: portID))
                    } else {
                        send(.completeConnection(nodeID: nodeID, portID: portID))
                    }
                    connectionPortPickerNodeID = nil
                },
                onCancel: {
                    connectionPortPickerNodeID = nil
                }
            )
            .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private func designDeviceSheet(for nodeID: UUID) -> some View {
        designDeviceEditor(for: nodeID, presentation: .sheet)
            .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func designDeviceEditor(
        for nodeID: UUID,
        presentation: TopologyDesignDeviceConfigurationEditor.Presentation
    ) -> some View {
        if let node = state.graph.node(withID: nodeID) {
            TopologyDesignDeviceConfigurationEditor(
                node: node,
                draft: designConfigurationDraftBinding(for: node),
                availableSSIDs: availableDesignSSIDs,
                portDetails: designPortDetails(for: node),
                presentation: presentation,
                onSave: {
                    saveDesignConfiguration(nodeID: nodeID, closeAfterSave: presentation == .sheet)
                },
                onCancel: closeDesignConfiguration
            )
            .id(nodeID)
        }
    }

    private var availableDesignSSIDs: [String] {
        state.graph.nodes
            .filter { $0.kind == .networkSwitch }
            .map { switchNode in
                state.switchConfigurationsByNodeID[switchNode.id]?.ssid
                    ?? TopologySwitchConfiguration.defaultConfiguration(nodeID: switchNode.id).ssid
            }
            .sorted()
    }

    private func requestDesignConfiguration(for nodeID: UUID) {
        guard let node = state.graph.node(withID: nodeID), node.kind != .unsupported else {
            return
        }
        guard designConfigurationNodeID != nodeID else {
            return
        }
        if hasUnsavedDesignConfiguration {
            pendingConfigurationSelection = PendingConfigurationSelection(nodeID: nodeID)
            isShowingUnsavedConfigurationAlert = true
        } else {
            switchDesignConfiguration(to: nodeID)
        }
    }

    private func handleRegularInspectorSelectionChange() {
        guard designConfigurationNodeID != nil else { return }
        let targetNodeID: UUID?
        if state.selectedNodeIDs.count == 1,
           let selectedNodeID = state.selectedNodeIDs.first,
           let node = state.graph.node(withID: selectedNodeID),
           node.kind != .unsupported {
            targetNodeID = selectedNodeID
        } else {
            targetNodeID = nil
        }
        guard targetNodeID != designConfigurationNodeID else { return }
        if hasUnsavedDesignConfiguration {
            pendingConfigurationSelection = PendingConfigurationSelection(nodeID: targetNodeID)
            isShowingUnsavedConfigurationAlert = true
        } else {
            switchDesignConfiguration(to: targetNodeID)
        }
    }

    private func switchDesignConfiguration(to nodeID: UUID?) {
        pendingConfigurationSelection = nil
        isShowingUnsavedConfigurationAlert = false
        guard let nodeID, let node = state.graph.node(withID: nodeID), node.kind != .unsupported else {
            closeDesignConfiguration()
            return
        }
        let draft = makeDesignConfigurationDraft(for: node)
        designConfigurationNodeID = nodeID
        designConfigurationDraft = draft
        designConfigurationBaseline = draft
    }

    private func closeDesignConfiguration() {
        designConfigurationNodeID = nil
        designConfigurationDraft = nil
        designConfigurationBaseline = nil
        pendingConfigurationSelection = nil
        isShowingUnsavedConfigurationAlert = false
    }

    private var hasUnsavedDesignConfiguration: Bool {
        guard let draft = designConfigurationDraft,
              let baseline = designConfigurationBaseline
        else {
            return false
        }
        return draft != baseline
    }

    private func makeDesignConfigurationDraft(for node: TopologyNode) -> TopologyDesignDeviceConfigurationDraft {
        let interfaceConfigurations = node.ports.map { port in
            let configuration = state.runtimeInterfaceConfigurations[
                TopologyRuntimeInterfaceKey(nodeID: node.id, portID: port.id)
            ] ?? TopologyRuntimeInterfaceDefaults.configurations(for: node)
                .first(where: { $0.0.portID == port.id })?.1
                ?? TopologyRuntimeInterfaceConfiguration(
                    ipAddress: "192.168.0.10",
                    subnetMask: "255.255.255.0"
                )
            return TopologyDesignInterfaceConfiguration(
                id: port.id,
                ipAddress: configuration.ipAddress,
                subnetMask: configuration.subnetMask
            )
        }
        let deviceConfiguration = state.runtimeDeviceConfigurations[node.id]
            ?? defaultDesignDeviceConfiguration(for: node, interfaces: interfaceConfigurations)
        return TopologyDesignDeviceConfigurationDraft(
            node: node,
            deviceConfiguration: deviceConfiguration,
            interfaceConfigurations: node.kind == .router || node.kind == .gateway
                ? interfaceConfigurations
                : [],
            switchConfiguration: state.switchConfigurationsByNodeID[node.id]
                ?? (node.kind == .networkSwitch ? .defaultConfiguration(nodeID: node.id) : nil),
            remoteLinkConfiguration: state.remoteLinkConfigurationsByNodeID[node.id]
                ?? (node.kind == .remoteLink ? .defaultConfiguration(nodeID: node.id) : nil),
            hostWirelessConfiguration: state.hostWirelessConfigurationsByNodeID[node.id]
                ?? TopologyHostWirelessConfiguration(),
            availableSSIDs: availableDesignSSIDs
        )
    }

    private func designConfigurationDraftBinding(for node: TopologyNode) -> Binding<TopologyDesignDeviceConfigurationDraft> {
        Binding(
            get: {
                if let draft = designConfigurationDraft, draft.nodeID == node.id {
                    return draft
                }
                return makeDesignConfigurationDraft(for: node)
            },
            set: { designConfigurationDraft = $0 }
        )
    }

    private func saveDesignConfiguration(nodeID: UUID, closeAfterSave: Bool) {
        guard let node = state.graph.node(withID: nodeID),
              let draft = designConfigurationDraft,
              draft.nodeID == nodeID,
              draft.isValid(for: node, availableSSIDs: availableDesignSSIDs)
        else {
            return
        }
        send(
            .saveDesignDeviceConfiguration(
                nodeID: nodeID,
                displayName: draft.displayName,
                deviceConfiguration: draft.deviceConfiguration(for: node),
                interfaceConfigurations: draft.interfaceConfigurations,
                switchConfiguration: draft.switchConfiguration(for: node),
                remoteLinkConfiguration: draft.remoteLinkConfiguration(for: node),
                hostWirelessConfiguration: draft.hostWirelessConfiguration(for: node)
            )
        )
        guard state.lastValidationError == nil else { return }
        designConfigurationBaseline = draft
        if closeAfterSave {
            closeDesignConfiguration()
        }
    }

    private func saveAndApplyPendingConfigurationSelection() {
        guard let pendingConfigurationSelection,
              let currentNodeID = designConfigurationNodeID
        else { return }
        saveDesignConfiguration(nodeID: currentNodeID, closeAfterSave: false)
        guard !hasUnsavedDesignConfiguration else { return }
        switchDesignConfiguration(to: pendingConfigurationSelection.nodeID)
    }

    private func discardAndApplyPendingConfigurationSelection() {
        switchDesignConfiguration(to: pendingConfigurationSelection?.nodeID)
    }

    private func keepEditingCurrentConfiguration() {
        pendingConfigurationSelection = nil
        isShowingUnsavedConfigurationAlert = false
        if let currentNodeID = designConfigurationNodeID {
            send(.selectSingleNode(nodeID: currentNodeID))
        }
    }

    private func designPortDetails(for node: TopologyNode) -> [TopologyDesignPortDetail] {
        node.ports.enumerated().map { index, port in
            let connectedLink = state.graph.links.first { link in
                (link.sourceNodeID == node.id && link.sourcePortID == port.id)
                    || (link.targetNodeID == node.id && link.targetPortID == port.id)
            }

            let role: String
            if node.kind == .gateway {
                role = index == 0 ? "WAN" : "LAN"
            } else if node.kind == .router {
                role = "Konfigurierbar"
            } else if node.kind == .remoteLink {
                role = "Lokales Netz"
            } else {
                role = "Netzwerkanschluss"
            }

            var connectionDescription = "Nicht verbunden"
            if let connectedLink {
                let peerNodeID = connectedLink.sourceNodeID == node.id
                    ? connectedLink.targetNodeID
                    : connectedLink.sourceNodeID
                let peerPortID = connectedLink.sourceNodeID == node.id
                    ? connectedLink.targetPortID
                    : connectedLink.sourcePortID
                if let peerNode = state.graph.node(withID: peerNodeID) {
                    let peerPort = peerNode.ports.first(where: { $0.id == peerPortID })?.label ?? "Port"
                    connectionDescription = "\(peerNode.displayName) · \(peerPort)"
                }
            }

            return TopologyDesignPortDetail(
                id: port.id,
                role: role,
                isOccupied: connectedLink != nil,
                connectionDescription: connectionDescription
            )
        }
    }

    private func defaultDesignDeviceConfiguration(
        for node: TopologyNode,
        interfaces: [TopologyDesignInterfaceConfiguration]
    ) -> TopologyRuntimeDeviceConfiguration? {
        switch node.kind {
        case .pc, .notebook:
            return TopologyRuntimeDeviceConfiguration(
                ipAddress: "192.168.0.10",
                subnetMask: "255.255.255.0"
            )
        case .gateway:
            guard let wan = interfaces.first else {
                return nil
            }
            return TopologyRuntimeDeviceConfiguration(
                ipAddress: wan.ipAddress,
                subnetMask: wan.subnetMask
            )
        case .router, .networkSwitch, .remoteLink, .unsupported:
            return nil
        }
    }

    @ViewBuilder
    private func runtimeDeviceSheet(for nodeID: UUID) -> some View {
        let node = state.graph.node(withID: nodeID)

        TopologyRuntimeDeviceSheet(
            nodeID: nodeID,
            nodeKind: node?.kind ?? .unsupported,
            configuration: state.runtimeDeviceConfigurations[nodeID],
            interfaceConfigurations: node?.ports.map { port in
                TopologyRuntimeInterfaceConfigurationItem(
                    id: port.id,
                    label: port.label,
                    configuration: state.runtimeInterfaceConfigurations[
                        TopologyRuntimeInterfaceKey(nodeID: nodeID, portID: port.id)
                    ]
                )
            } ?? [],
            manualRoutes: state.runtimeManualRoutesByNodeID[nodeID] ?? [],
            ripEnabled: state.runtimeRIPEnabledByNodeID[nodeID] == true,
            dhcpClientConfiguration: state.runtimeDHCPClientConfigurationsByNodeID[nodeID]
                ?? TopologyDHCPClientConfiguration(),
            dhcpServerConfiguration: state.runtimeDHCPServerConfigurationsByNodeID[nodeID]
                ?? TopologyDHCPServerConfiguration(),
            firewallConfiguration: state.runtimeFirewallConfigurationsByNodeID[nodeID]
                ?? (state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(.firewall) == true
                    ? TopologyFirewallConfiguration.javaPersonalDefaults
                    : TopologyFirewallConfiguration()),
            firewallDecisions: state.networkRuntime.state.firewallDecisions.filter { $0.nodeID == nodeID },
            switchConfiguration: state.switchConfigurationsByNodeID[nodeID],
            remoteLinkConfiguration: state.remoteLinkConfigurationsByNodeID[nodeID],
            remoteLinkStatus: state.networkRuntime.remoteLinkRuntimeStatus(nodeID: nodeID),
            switchSATEntries: state.networkRuntime.switchSATEntries(nodeID: nodeID),
            natMappings: state.networkRuntime.natMappings(gatewayNodeID: nodeID),
            portForwardingRows: state.runtimePortForwardingRowsByNodeID[nodeID] ?? [],
            packetCaptureTabs: state.networkRuntime.packetCaptureTabs(nodeID: nodeID),
            packetMessageRows: state.networkRuntime.packetMessageRows(nodeID: nodeID),
            packetLayerPath: { identity, localOnly in
                state.networkRuntime.packetLayerPath(
                    identity: identity,
                    localNodeID: localOnly ? nodeID : nil
                )
            },
            installedPrograms: state.runtimeInstalledProgramsByNodeID[nodeID] ?? [],
            activeProgram: state.runtimeActiveProgramByNodeID[nodeID],
            protocolApplicationsEnabled: appPreferences.experimentalProtocolApplicationsEnabled,
            protocolApplicationDefinitions: state.sortedProtocolApplicationDefinitions,
            installedProtocolApplicationIDs: state.runtimeInstalledProtocolApplicationIDsByNodeID[nodeID] ?? [],
            activeProtocolApplicationID: state.runtimeActiveProtocolApplicationIDByNodeID[nodeID],
            activeProtocolClientState: state.runtimeActiveProtocolApplicationIDByNodeID[nodeID].flatMap {
                state.runtimeProtocolApplicationClients[TopologyProtocolApplicationRuntimeKey(nodeID: nodeID, definitionID: $0)]
            },
            activeProtocolServerState: state.runtimeActiveProtocolApplicationIDByNodeID[nodeID].flatMap {
                state.runtimeProtocolApplicationServers[TopologyProtocolApplicationRuntimeKey(nodeID: nodeID, definitionID: $0)]
            },
            consoleEntries: state.runtimeConsoleEntriesByNodeID[nodeID] ?? [],
            terminalWorkingDirectory: state.runtimeWorkingDirectoryByNodeID[nodeID] ?? "/",
            dhcpLease: state.runtimeDHCPLeaseByNodeID[nodeID],
            dnsRecords: (state.runtimeDNSServerConfigurationsByNodeID[nodeID]?.recordsByHostname.values.map { $0 } ?? []).sorted { lhs, rhs in
                lhs.hostname < rhs.hostname
            },
            dnsServerState: state.runtimeDNSServerSocketIDByNodeID[nodeID] != nil ? TopologyRuntimeServiceProcessState(port: 53) : nil,
            webServerState: state.runtimeWebServerByNodeID[nodeID],
            webServerConfiguration: state.runtimeWebServerConfigurationsByNodeID[nodeID] ?? TopologyRuntimeWebServerConfiguration(),
            webServerRequestLogs: state.runtimeWebServerRequestLogsByNodeID[nodeID] ?? [],
            webBrowserConfiguration: state.runtimeWebBrowserConfigurationsByNodeID[nodeID] ?? TopologyRuntimeWebBrowserConfiguration(),
            webBrowserState: state.runtimeWebBrowserStateByNodeID[nodeID],
            echoServerState: state.runtimeEchoServerByNodeID[nodeID],
            virtualFileSystem: state.virtualFileSystemsByNodeID[nodeID] ?? .defaultForDevice(),
            simpleClientState: state.runtimeSimpleClientByNodeID[nodeID],
            emailClientConfiguration: state.runtimeEmailClientConfigurationsByNodeID[nodeID] ?? TopologyRuntimeEmailClientConfiguration(),
            emailClientState: state.runtimeEmailClientStateByNodeID[nodeID] ?? TopologyRuntimeEmailClientState(),
            emailServerConfiguration: state.runtimeEmailServerConfigurationsByNodeID[nodeID] ?? TopologyRuntimeEmailServerConfiguration(),
            emailServerProcessState: state.runtimeEmailServerProcessesByNodeID[nodeID] ?? TopologyRuntimeEmailServerProcessState(),
            gnutellaConfiguration: state.runtimeGnutellaConfigurationsByNodeID[nodeID] ?? TopologyRuntimeGnutellaConfiguration(),
            gnutellaSessionState: state.runtimeGnutellaSessionsByNodeID[nodeID] ?? TopologyRuntimeGnutellaSessionState(),
            fileExplorerSelection: state.runtimeFileExplorerSelectionByNodeID[nodeID],
            imageViewerSelection: state.runtimeImageViewerSelectionByNodeID[nodeID],
            textEditorSelection: state.runtimeTextEditorSelectionByNodeID[nodeID],
            textEditorDraft: state.runtimeTextEditorDraftByNodeID[nodeID],
            onSaveInterfaceConfiguration: { portID, ipAddress, subnetMask in
                send(
                    .saveRuntimeInterfaceConfiguration(
                        nodeID: nodeID,
                        portID: portID,
                        ipAddress: ipAddress,
                        subnetMask: subnetMask
                    )
                )
            },
            onSaveManualRoutes: { routes in
                send(.saveRuntimeManualRoutes(nodeID: nodeID, routes: routes))
            },
            onSetRIPEnabled: { enabled in
                send(.setRuntimeRIPEnabled(nodeID: nodeID, enabled: enabled))
            },
            onSetDHCPClientEnabled: { enabled in
                send(.setRuntimeDHCPClientEnabled(nodeID: nodeID, enabled: enabled))
            },
            onSaveDHCPServerConfiguration: { configuration in
                send(.saveRuntimeDHCPServerConfiguration(nodeID: nodeID, configuration: configuration))
            },
            onSaveFirewallConfiguration: { configuration in
                send(.saveRuntimeFirewallConfiguration(nodeID: nodeID, configuration: configuration))
            },
            onClearSwitchSAT: {
                send(.clearRuntimeSwitchSAT(nodeID: nodeID))
            },
            onResetNATTable: {
                send(.resetRuntimeNATTable(nodeID: nodeID))
            },
            onSavePortForwardingRows: { rows in
                send(.saveRuntimePortForwardingRows(nodeID: nodeID, rows: rows))
            },
            onResetPacketCapture: {
                send(.resetRuntimePacketCapture(nodeID: nil, interfaceID: nil))
            },
            onInstallProgram: { program in
                send(.installRuntimeProgram(nodeID: nodeID, program: program))
            },
            onUninstallProgram: { program in
                send(.uninstallRuntimeProgram(nodeID: nodeID, program: program))
            },
            onLaunchProgram: { program in
                send(.launchRuntimeProgram(nodeID: nodeID, program: program))
            },
            onCloseProgram: {
                send(.closeRuntimeProgram(nodeID: nodeID))
            },
            onInstallProtocolApplication: { definitionID in
                send(.installProtocolApplication(nodeID: nodeID, definitionID: definitionID))
            },
            onLaunchProtocolApplication: { definitionID in
                send(.launchProtocolApplication(nodeID: nodeID, definitionID: definitionID))
            },
            onCloseProtocolApplication: {
                send(.closeProtocolApplication(nodeID: nodeID))
            },
            onStartProtocolServer: { definitionID in
                send(.runtimeProtocolServerStart(nodeID: nodeID, definitionID: definitionID))
            },
            onStopProtocolServer: { definitionID in
                send(.runtimeProtocolServerStop(nodeID: nodeID, definitionID: definitionID))
            },
            onSendProtocolClientMessage: { definitionID, destination, templateID in
                send(.runtimeProtocolClientSend(
                    nodeID: nodeID,
                    definitionID: definitionID,
                    destinationIPAddress: destination,
                    templateID: templateID
                ))
            },
            onExecuteCommand: { command in
                send(.executePing(nodeID: nodeID, command: command))
            },
            onDHCPLease: { ipAddress, subnetMask in
                send(.runtimeDHCPLease(nodeID: nodeID, ipAddress: ipAddress, subnetMask: subnetMask))
            },
            onDHCPRelease: {
                send(.runtimeDHCPRelease(nodeID: nodeID))
            },
            onDNSAddRecord: { hostname, targetIPAddress in
                send(.runtimeDNSAddRecord(nodeID: nodeID, hostname: hostname, targetIPAddress: targetIPAddress))
            },
            onDNSRemoveRecord: { hostname in
                send(.runtimeDNSRemoveRecord(nodeID: nodeID, hostname: hostname))
            },
            onDNSResolveRecord: { hostname in
                send(.runtimeDNSResolveRecord(nodeID: nodeID, hostname: hostname))
            },
            onDNSStart: {
                send(.runtimeDNSStart(nodeID: nodeID))
            },
            onDNSStop: {
                send(.runtimeDNSStop(nodeID: nodeID))
            },
            onWebStart: { port in
                send(.runtimeWebStart(nodeID: nodeID, port: port))
            },
            onWebStop: {
                send(.runtimeWebStop(nodeID: nodeID))
            },
            onWebRestart: { port in
                send(.runtimeWebRestart(nodeID: nodeID, port: port))
            },
            onWebBrowserNavigate: { address in
                send(.runtimeWebBrowserNavigate(nodeID: nodeID, address: address))
            },
            onWebBrowserBack: {
                send(.runtimeWebBrowserBack(nodeID: nodeID))
            },
            onWebBrowserForward: {
                send(.runtimeWebBrowserForward(nodeID: nodeID))
            },
            onWebBrowserReset: {
                send(.runtimeWebBrowserReset(nodeID: nodeID))
            },
            onEchoStart: { port in
                send(.runtimeEchoStart(nodeID: nodeID, port: port))
            },
            onEchoStop: {
                send(.runtimeEchoStop(nodeID: nodeID))
            },
            onSimpleClientConnect: { destination, port, protocolKind in
                send(.runtimeSimpleClientConnect(nodeID: nodeID, destinationIPAddress: destination, port: port, protocolKind: protocolKind))
            },
            onSimpleClientSend: { message in
                send(.runtimeSimpleClientSend(nodeID: nodeID, message: message))
            },
            onSimpleClientDisconnect: {
                send(.runtimeSimpleClientDisconnect(nodeID: nodeID))
            },
            onSaveEmailClientConfiguration: { configuration in
                send(.saveRuntimeEmailClientConfiguration(nodeID: nodeID, configuration: configuration))
            },
            onSendEmail: { message in
                send(.runtimeEmailClientSend(nodeID: nodeID, message: message))
            },
            onRetrieveEmail: {
                send(.runtimeEmailClientRetrieve(nodeID: nodeID))
            },
            onSaveEmailServerConfiguration: { configuration in
                send(.saveRuntimeEmailServerConfiguration(nodeID: nodeID, configuration: configuration))
            },
            onStartEmailServer: { configuration in
                send(.saveAndStartRuntimeEmailServer(nodeID: nodeID, configuration: configuration))
            },
            onStopEmailServer: {
                send(.runtimeEmailServerStop(nodeID: nodeID))
            },
            onSaveGnutellaConfiguration: { configuration in
                send(.saveRuntimeGnutellaConfiguration(nodeID: nodeID, configuration: configuration))
            },
            onGnutellaJoin: { bootstrapIPAddress in
                send(.runtimeGnutellaJoin(nodeID: nodeID, bootstrapIPAddress: bootstrapIPAddress))
            },
            onGnutellaResetNetwork: {
                send(.runtimeGnutellaResetNetwork(nodeID: nodeID))
            },
            onGnutellaSearch: { searchTerm in
                send(.runtimeGnutellaSearch(nodeID: nodeID, searchTerm: searchTerm))
            },
            onGnutellaClearSearchResults: {
                send(.runtimeGnutellaClearSearchResults(nodeID: nodeID))
            },
            onGnutellaDownload: { result in
                send(.runtimeGnutellaDownload(nodeID: nodeID, result: result))
            },
            onFileExplorerSelectEntry: { entryID in
                send(.runtimeFileExplorerSelectEntry(nodeID: nodeID, entryID: entryID))
            },
            onImageViewerSelectImage: { imageID in
                send(.runtimeImageViewerSelectImage(nodeID: nodeID, imageID: imageID))
            },
            onTextEditorSelectFile: { path in
                send(.runtimeTextEditorSelectFile(nodeID: nodeID, path: path))
            },
            onTextEditorUpdateDraft: { text in
                send(.runtimeTextEditorUpdateDraft(nodeID: nodeID, text: text))
            },
            onTextEditorSaveDraft: {
                send(.runtimeTextEditorSaveDraft(nodeID: nodeID))
            },
            onTextEditorResetDraft: {
                send(.runtimeTextEditorResetDraft(nodeID: nodeID))
            },
            onFileSystemCreateDirectory: { path in
                send(.runtimeFileSystemCreateDirectory(nodeID: nodeID, path: path))
            },
            onFileSystemCreateTextFile: { path, text in
                send(.runtimeFileSystemCreateTextFile(nodeID: nodeID, path: path, text: text))
            },
            onFileSystemCopyItem: { source, destination in
                send(.runtimeFileSystemCopyItem(nodeID: nodeID, sourcePath: source, destinationPath: destination))
            },
            onFileSystemMoveItem: { source, destination in
                send(.runtimeFileSystemMoveItem(nodeID: nodeID, sourcePath: source, destinationPath: destination))
            },
            onFileSystemRenameItem: { path, newName in
                send(.runtimeFileSystemRenameItem(nodeID: nodeID, path: path, newName: newName))
            },
            onFileSystemDeleteItem: { path, recursive in
                send(.runtimeFileSystemDeleteItem(nodeID: nodeID, path: path, recursive: recursive))
            },
            onClose: {
                send(.closeRuntimeDevice)
            }
        )
        .presentationDetents([.large])
    }

    private func setToolMode(_ mode: TopologyEditorToolMode) {
        send(.setActiveTool(mode: mode))

        switch mode {
        case .select:
            send(.setInteractionMode(mode: "paletteTap:select"))
        case .connect:
            send(.setInteractionMode(mode: "paletteTap:connect"))
        case let .place(kind):
            send(.setInteractionMode(mode: "paletteTap:place:\(kind.rawValue)"))
        }
    }

    private func handleNewProject() {
        undoCoordinator.removeAllActions()
        stopSimulationTickLoop()
        filiusSupplementalArchiveEntries = [:]
        filiusOpaqueContent = .empty

        var replacementState = TopologyEditorState()
        replacementState.persistenceRevision = 1
        replacementState.lastPersistedRevision = 0
        onExternalStateReplacement(replacementState)
    }

    private func handleFiliusProjectImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                return
            }
            let accessedSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if accessedSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard FiliusProjectImportResourcePolicy.accepts(fileURL: url) else {
                throw ProjectFileOperationError(FiliusLocalization.t("project.import.unsupportedFileType"))
            }

            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard FiliusProjectImportResourcePolicy.accepts(isRegularFile: resourceValues.isRegularFile) else {
                throw ProjectFileOperationError(FiliusLocalization.t("project.import.notRegularFile"))
            }
            if let fileSize = resourceValues.fileSize, fileSize > 256 * 1_024 * 1_024 {
                throw ProjectFileOperationError(FiliusLocalization.t("project.import.tooLarge"))
            }

            let archiveData = try Data(contentsOf: url, options: .mappedIfSafe)
            let importedArchive = try TopologyProjectStore.importFiliusArchiveDocument(archiveData)
            let imported = importedArchive.project
            var importedState = imported.state
            let nextRevision = state.persistenceRevision == UInt64.max
                ? UInt64(1)
                : state.persistenceRevision + 1
            importedState.persistenceRevision = max(importedState.persistenceRevision, nextRevision)
            importedState.lastPersistedRevision = importedState.persistenceRevision > 0
                ? importedState.persistenceRevision - 1
                : 0
            filiusSupplementalArchiveEntries = [:]
            filiusOpaqueContent = .empty
            onExternalStateReplacement(importedState)
            filiusSupplementalArchiveEntries = importedArchive.supplementalEntries
            filiusOpaqueContent = importedArchive.opaqueContent

            var details = FiliusLocalization.t("project.import.summary", imported.report.importedNodeCount, imported.report.importedLinkCount, imported.report.importedDocumentationItemCount, url.lastPathComponent)
            details += " " + FiliusLocalization.t("project.import.archiveSummary", importedArchive.archiveEntryPaths.count, importedArchive.supplementalEntries.count)
            if imported.report.skippedNodeCount > 0 {
                details += " " + FiliusLocalization.t("project.import.skippedDevices", imported.report.skippedNodeCount)
            }
            if !imported.report.warnings.isEmpty {
                details += "\n\n" + FiliusLocalization.t("project.compatibilityNotices") + ":\n- " + imported.report.warnings.joined(separator: "\n- ")
            }
            projectFileNotice = ProjectFileNotice(title: FiliusLocalization.t("project.opened.title"), message: details)
        } catch {
            guard !isUserCancellation(error) else { return }
            projectFileNotice = ProjectFileNotice(
                title: FiliusLocalization.t("project.openFailed.title"),
                message: projectFileErrorMessage(error)
            )
        }
    }

    private func prepareFiliusProjectExport() {
        do {
            let export = try TopologyProjectStore.exportFiliusArchiveWithReport(
                from: state,
                supplementalEntries: filiusSupplementalArchiveEntries,
                opaqueContent: filiusOpaqueContent
            )
            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(FiliusLocalization.t("project.filename.fls"))
            try? FileManager.default.removeItem(at: temporaryURL)
            try export.data.write(to: temporaryURL, options: .atomic)
            // Couple the prepared URL and its presentation into one item. This
            // prevents SwiftUI from presenting a sheet before the export payload is
            // available, which previously left Save showing an empty loading sheet.
            filiusExportSession = FiliusProjectExportSession(
                fileURL: temporaryURL,
                report: export.report
            )
        } catch {
            projectFileNotice = ProjectFileNotice(
                title: FiliusLocalization.t("project.saveFailed.title"),
                message: projectFileErrorMessage(error)
            )
        }
    }

    private func handleFiliusProjectExport(
        _ result: Result<URL, Error>,
        session: FiliusProjectExportSession
    ) {
        defer {
            cleanupFiliusProjectExport(at: session.fileURL)
            if filiusExportSession?.id == session.id {
                filiusExportSession = nil
            }
        }
        switch result {
        case let .success(url):
            // M007/S03 approved autosave-separation anchor retained: Native autosave remains active separately.
            var details = FiliusLocalization.t("project.export.summary", url.lastPathComponent)
            if !session.report.warnings.isEmpty {
                details += "\n\n" + FiliusLocalization.t("project.compatibilityNotices") + ":\n- " + session.report.warnings.joined(separator: "\n- ")
            }
            projectFileNotice = ProjectFileNotice(
                title: FiliusLocalization.t("project.saved.title"),
                message: details
            )
        case let .failure(error):
            guard !isUserCancellation(error) else { return }
            projectFileNotice = ProjectFileNotice(
                title: FiliusLocalization.t("project.saveFailed.title"),
                message: projectFileErrorMessage(error)
            )
        }
    }

    private func cleanupFiliusProjectExport(at fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func prepareDocumentationImageExport() {
        guard let data = TopologyDocumentationReportRenderer.makePNGData(state: state) else {
            projectFileNotice = ProjectFileNotice(
                title: FiliusLocalization.t("documentation.image.exportFailed.title"),
                message: FiliusLocalization.t("documentation.image.rendererFailed")
            )
            return
        }
        documentationImageDocument = TopologyPNGFileDocument(data: data)
        isExportingDocumentationImage = true
    }

    private func handleDocumentationImageExport(_ result: Result<URL, Error>) {
        defer { documentationImageDocument = nil }
        switch result {
        case let .success(url):
            projectFileNotice = ProjectFileNotice(
                title: FiliusLocalization.t("documentation.image.saved.title"),
                message: FiliusLocalization.t("documentation.image.saved.message", url.lastPathComponent, 1024, 768)
            )
        case let .failure(error):
            guard !isUserCancellation(error) else { return }
            projectFileNotice = ProjectFileNotice(
                title: FiliusLocalization.t("documentation.image.saveFailed.title"),
                message: error.localizedDescription
            )
        }
    }

    private func prepareDocumentationPDFExport() {
        let data = TopologyDocumentationReportRenderer.makePDFData(state: state)
        documentationPDFDocument = TopologyPDFFileDocument(data: data)
        isExportingDocumentationPDF = true
    }

    private func handleDocumentationPDFExport(_ result: Result<URL, Error>) {
        defer { documentationPDFDocument = nil }
        switch result {
        case let .success(url):
            let report = TopologyDocumentationReport(state: state)
            projectFileNotice = ProjectFileNotice(
                title: FiliusLocalization.t("report.saved.title"),
                message: FiliusLocalization.t("report.saved.message", url.lastPathComponent, report.nodeCount, report.linkCount, report.textAnnotationCount, report.rectangleCount)
            )
        case let .failure(error):
            guard !isUserCancellation(error) else { return }
            projectFileNotice = ProjectFileNotice(
                title: FiliusLocalization.t("report.saveFailed"),
                message: error.localizedDescription
            )
        }
    }

    private func isUserCancellation(_ error: Error) -> Bool {
        (error as NSError).code == NSUserCancelledError
    }

    private func projectFileErrorMessage(_ error: Error) -> String {
        if let archiveError = error as? TopologyFLSArchiveError {
            return FiliusLocalization.t("persistence.code", archiveError.code.rawValue, archiveError.localizedDescription)
        }
        if let compatibilityError = error as? TopologyFLSCompatibilityError {
            return FiliusLocalization.t("persistence.code", compatibilityError.code.rawValue, compatibilityError.detail)
        }
        return error.localizedDescription
    }

    private func handleStartSimulation() {
        undoCoordinator.removeAllActions()
        send(.setSimulationSpeed(percent: appPreferences.simulationSpeed.percent))
        send(.startSimulation)
    }

    private func handleStopSimulation() {
        send(.stopSimulation)
    }

    private func handlePaletteDragPrepared(_ kind: TopologyNodeKind) {
        guard state.simulationPhase == .stopped, state.workspaceMode == .design else {
            return
        }

        send(.setInteractionMode(mode: "paletteDrag:start:\(kind.rawValue)"))
    }

    private func handlePaletteDrop(items: [String], location: CGPoint) -> Bool {
        guard state.simulationPhase == .stopped, state.workspaceMode == .design else {
            return false
        }

        guard let first = items.first,
              let kind = TopologyNodeKind(rawValue: first),
              kind != .unsupported
        else {
            send(.setInteractionMode(mode: "paletteDrag:invalidPayload"))
            return false
        }

        send(.setActiveTool(mode: .place(kind)))
        send(.setInteractionMode(mode: "paletteDrag:drop:\(kind.rawValue)"))
        handleCanvasTap(location)
        return true
    }

    private func handleSimulationPhaseChange(_ phase: TopologySimulationPhase) {
        switch phase {
        case .running:
            startSimulationTickLoopIfNeeded()
        case .stopped:
            stopSimulationTickLoop()
        }
    }

    private func startSimulationTickLoopIfNeeded() {
        switch simulationClockDriver.start() {
        case let .started(token):
            simulationTickTask = Task {
                await simulationTickLoop(token: token)
            }
        case .alreadyRunning:
            return
        case .generationExhausted:
            simulationTickTask = nil
        }
    }

    private func stopSimulationTickLoop() {
        simulationClockDriver.stop()
        simulationTickTask?.cancel()
        simulationTickTask = nil
    }

    private func simulationTickLoop(token: TopologySimulationClockDriver.Token) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: TopologySimulationSpeed.wallClockPulseNanoseconds)
            } catch {
                break
            }

            if Task.isCancelled {
                break
            }

            let acceptedPulse = await MainActor.run { () -> Bool in
                guard state.simulationPhase == .running else {
                    return false
                }

                switch simulationClockDriver.pulseDecision(
                    token: token,
                    speed: appPreferences.simulationSpeed,
                    currentVirtualTimeMilliseconds: state.networkRuntime.state.currentTimeMilliseconds
                ) {
                case let .advance(pulse):
                    send(.simulationTick(step: pulse.stepMilliseconds))
                    return true
                case .inactive:
                    return false
                case .overflow:
                    send(
                        .simulationFault(
                            code: "simulationClockOverflow",
                            message: FiliusLocalization.t("runtime.clock.overflow")
                        )
                    )
                    send(.stopSimulation)
                    return false
                }
            }
            if !acceptedPulse {
                break
            }
        }

        await MainActor.run {
            guard simulationClockDriver.activeToken == token else {
                return
            }
            simulationClockDriver.stop()
            simulationTickTask = nil
        }
    }

    private func handleCanvasTap(_ screenPoint: CGPoint) {
        if state.workspaceMode == .documentation && state.simulationPhase == .stopped {
            let worldPoint = state.viewport.screenToWorld(screenPoint)
            guard canvasWorldBounds.contains(worldPoint) else { return }
            switch state.documentationTool {
            case .select:
                send(.selectDocumentationItem(itemID: nil))
            case .text:
                send(.createDocumentationItem(kind: .text, at: worldPoint, itemID: UUID()))
            case .rectangle:
                send(.createDocumentationItem(kind: .rectangle, at: worldPoint, itemID: UUID()))
            }
            return
        }

        let hitNodeID = state.viewport.hitTestNode(atScreenPoint: screenPoint, nodes: state.graph.nodes)

        if state.simulationPhase == .running {
            guard let hitNodeID else {
                return
            }

            send(.openRuntimeDevice(nodeID: hitNodeID))
            return
        }

        switch state.activeTool {
        case let .place(kind):
            let worldPoint = state.viewport.screenToWorld(screenPoint)
            guard canvasWorldBounds.contains(worldPoint) else {
                return
            }
            send(.setInteractionMode(mode: "canvasTap:place:\(kind.rawValue)"))
            send(.placeNode(kind: kind, at: worldPoint, nodeID: UUID()))

        case .select:
            if let hitNodeID {
                send(.selectSingleNode(nodeID: hitNodeID))
            } else if let hitLinkID = hitTestLink(at: screenPoint) {
                send(.selectSingleLink(linkID: hitLinkID))
            } else {
                send(.clearSelection)
            }

        case .connect:
            guard let hitNodeID else {
                return
            }
            connectionPortPickerNodeID = hitNodeID
        }
    }

    private func hitTestLink(at point: CGPoint) -> UUID? {
        let parallelCableOffsets = TopologyLink.parallelCableOffsets(for: state.graph.links)
        for link in state.graph.links.reversed()
            where linkContains(
                point: point,
                link: link,
                parallelCableOffset: parallelCableOffsets[link.id, default: 0]
            ) {
            return link.id
        }
        return nil
    }

    private func linkContains(
        point: CGPoint,
        link: TopologyLink,
        parallelCableOffset: CGFloat
    ) -> Bool {
        guard let projection = state.graph.linkProjection(for: link) else {
            return false
        }
        let start = state.viewport.worldToScreen(projection.source)
        let end = state.viewport.worldToScreen(projection.target)
        let control = cableControlPoint(
            from: start,
            to: end,
            offset: parallelCableOffset
        )
        var previous = start
        for step in 1...24 {
            let t = CGFloat(step) / 24
            let inverse = 1 - t
            let startWeight = inverse * inverse
            let controlWeight = 2 * inverse * t
            let endWeight = t * t
            let sampleX = startWeight * start.x + controlWeight * control.x + endWeight * end.x
            let sampleY = startWeight * start.y + controlWeight * control.y + endWeight * end.y
            let sample = CGPoint(x: sampleX, y: sampleY)
            if distanceFrom(point, toSegmentFrom: previous, to: sample) <= 10 {
                return true
            }
            previous = sample
        }
        return false
    }

    private func cableControlPoint(from start: CGPoint, to end: CGPoint, offset: CGFloat) -> CGPoint {
        let inset: CGFloat = 2
        let localWidth = abs(end.x - start.x) + (2 * inset)
        let localHeight = abs(end.y - start.y) + (2 * inset)
        let falling = (start.x - end.x) * (start.y - end.y) > 0
        let base = CGPoint(
            x: min(start.x, end.x) - inset + (localWidth / 4) * (falling ? 3 : 1),
            y: min(start.y, end.y) - inset + localHeight / 4
        )
        let length = max(hypot(end.x - start.x, end.y - start.y), 0.001)
        return CGPoint(
            x: base.x - ((end.y - start.y) / length * offset),
            y: base.y + ((end.x - start.x) / length * offset)
        )
    }

    private func distanceFrom(_ point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let projection = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        return hypot(point.x - (start.x + projection * dx), point.y - (start.y + projection * dy))
    }

    private func handleNodeDragChanged(nodeID: UUID, translation: CGSize) {
        guard state.simulationPhase == .stopped,
              state.activeTool == .select
        else {
            return
        }

        nodeDragInFlight = true

        let isStartingDrag = activeNodeDragTranslations[nodeID] == nil
        if isStartingDrag {
            undoCoordinator.beginGrouping()
            // Dragging is an individual-device operation. Collapse any link-created
            // multi-selection before applying the first movement delta.
            send(.selectSingleNode(nodeID: nodeID))
        }

        let previous = activeNodeDragTranslations[nodeID] ?? .zero
        let incrementalScreenDelta = CGSize(
            width: translation.width - previous.width,
            height: translation.height - previous.height
        )

        activeNodeDragTranslations[nodeID] = translation

        guard incrementalScreenDelta != .zero else {
            return
        }

        let worldDelta = CGSize(
            width: incrementalScreenDelta.width / max(state.viewport.scale, 0.001),
            height: incrementalScreenDelta.height / max(state.viewport.scale, 0.001)
        )

        send(.moveSelectedNodes(delta: worldDelta))
    }

    private func handleNodeDragEnded(nodeID: UUID) {
        activeNodeDragTranslations.removeValue(forKey: nodeID)
        nodeDragInFlight = false
        undoCoordinator.endGrouping(actionName: FiliusLocalization.t("undo.action.moveNode"))
    }

    private func handleDocumentationDragChanged(itemID: UUID, translation: CGSize) {
        guard state.simulationPhase == .stopped, state.workspaceMode == .documentation else { return }
        documentationDragInFlight = true
        let isStartingDrag = activeDocumentationDragTranslations[itemID] == nil
        if isStartingDrag {
            undoCoordinator.beginGrouping()
        }
        if state.selectedDocumentationItemID != itemID {
            send(.selectDocumentationItem(itemID: itemID))
        }
        let previous = activeDocumentationDragTranslations[itemID] ?? .zero
        let incrementalScreenDelta = CGSize(
            width: translation.width - previous.width,
            height: translation.height - previous.height
        )
        activeDocumentationDragTranslations[itemID] = translation
        guard incrementalScreenDelta != .zero else { return }
        let worldDelta = CGSize(
            width: incrementalScreenDelta.width / max(state.viewport.scale, 0.001),
            height: incrementalScreenDelta.height / max(state.viewport.scale, 0.001)
        )
        send(.moveSelectedDocumentationItem(delta: worldDelta))
    }

    private func handleDocumentationDragEnded(itemID: UUID) {
        activeDocumentationDragTranslations.removeValue(forKey: itemID)
        documentationDragInFlight = false
        undoCoordinator.endGrouping(actionName: FiliusLocalization.t("undo.action.moveDocumentation"))
    }

    private func handleCanvasPan(_ delta: CGSize) {
        // Recover if SwiftUI/XCUITest omitted a drag-ended callback after the
        // previous node or documentation gesture. Active translation state is
        // the authoritative signal that a drag is still in flight.
        if nodeDragInFlight, activeNodeDragTranslations.isEmpty {
            nodeDragInFlight = false
            undoCoordinator.endGrouping(actionName: FiliusLocalization.t("undo.action.moveNode"))
        }
        if documentationDragInFlight, activeDocumentationDragTranslations.isEmpty {
            documentationDragInFlight = false
            undoCoordinator.endGrouping(actionName: FiliusLocalization.t("undo.action.moveDocumentation"))
        }

        guard !nodeDragInFlight,
              !documentationDragInFlight
        else {
            return
        }

        send(.panCanvas(delta: delta))
    }

    private func handleCanvasMagnify(_ scaleDelta: CGFloat, anchor: CGPoint) {
        send(.zoomCanvas(scaleDelta: scaleDelta, anchor: anchor))
    }

    private func persistenceAlertMessage(for failure: TopologyPersistenceFailure) -> String {
        FiliusLocalization.t(
            "persistence.failure.message",
            failure.operation.rawValue,
            failure.code.rawValue,
            failure.detail
        )
    }


    private func handleViewAppear() {
        undoCoordinator.configure(
            undoManager: systemUndoManager,
            currentState: { state },
            replaceState: { state = $0 }
        )
        handleSimulationPhaseChange(state.simulationPhase)
        if !isUITesting && !appPreferences.hasCompletedGuidedTour {
            isShowingGuidedTour = true
        }
    }

    private func handleStateReplacement(_ oldValue: UInt64, _ newValue: UInt64) {
        undoCoordinator.removeAllActions()
        filiusSupplementalArchiveEntries = [:]
        filiusOpaqueContent = .empty
    }

    private var mainMenu: some View {
        TopologyMainMenuView(
            simulationPhase: state.simulationPhase,
            workspaceMode: state.workspaceMode,
            simulationSpeed: appPreferences.simulationSpeed,
            isPersistenceBusy: isPersistenceBusy,
            canUndo: undoCoordinator.canUndo,
            canRedo: undoCoordinator.canRedo,
            showsProtocolApplicationBuilder: appPreferences.experimentalProtocolApplicationsEnabled,
            onSimulationSpeedChanged: { appPreferences.setSimulationSpeed(percent: $0) },
            onNewProject: handleNewProject,
            onOpenProject: { isImportingFiliusProject = true },
            onSaveProject: prepareFiliusProjectExport,
            onUndo: undoCoordinator.undo,
            onRedo: undoCoordinator.redo,
            onEnterDocumentation: { send(.setWorkspaceMode(mode: .documentation)) },
            onEnterDesign: { send(.setWorkspaceMode(mode: .design)) },
            onStartSimulation: handleStartSimulation,
            onStopSimulation: handleStopSimulation,
            onShowProtocolApplicationBuilder: {
                guard appPreferences.experimentalProtocolApplicationsEnabled else { return }
                isShowingProtocolApplicationBuilder = true
            },
            onShowHelp: { isShowingContextualHelp = true },
            onShowInformation: { isShowingProductInformation = true },
            onShowSettings: { isShowingProductSettings = true }
        )
    }

    private var keyboardCommandLayer: some View {
        Group {
            commandButton(.newProject, key: "n", modifiers: .command)
            commandButton(.openProject, key: "o", modifiers: .command)
            commandButton(.saveProject, key: "s", modifiers: .command)
            commandButton(.undo, key: "z", modifiers: .command)
            commandButton(.redo, key: "z", modifiers: [.command, .shift])
            commandButton(.deleteSelection, key: .delete, modifiers: [])
            commandButton(.designMode, key: "1", modifiers: .command)
            commandButton(.simulationMode, key: "2", modifiers: .command)
            commandButton(.documentationMode, key: "3", modifiers: .command)
            commandButton(.cancel, key: .escape, modifiers: [])
        }
        .frame(width: 1, height: 1)
        .opacity(0.001)
        .accessibilityHidden(true)
    }

    private func commandButton(
        _ command: EditorCommand,
        key: KeyEquivalent,
        modifiers: EventModifiers
    ) -> some View {
        Button { route(command) } label: { Color.clear.frame(width: 1, height: 1) }
            .keyboardShortcut(key, modifiers: modifiers)
    }

    private func route(_ command: EditorCommand) {
        guard !isPersistenceBusy else { return }
        switch command {
        case .newProject:
            guard state.simulationPhase == .stopped else { return }
            handleNewProject()
        case .openProject:
            guard state.simulationPhase == .stopped else { return }
            isImportingFiliusProject = true
        case .saveProject:
            guard state.simulationPhase == .stopped else { return }
            prepareFiliusProjectExport()
        case .undo:
            guard state.simulationPhase == .stopped else { return }
            undoCoordinator.undo()
        case .redo:
            guard state.simulationPhase == .stopped else { return }
            undoCoordinator.redo()
        case .deleteSelection:
            guard state.simulationPhase == .stopped else { return }
            if state.workspaceMode == .documentation {
                send(.deleteSelectedDocumentationItem)
            } else {
                send(.deleteSelection)
            }
        case .designMode:
            if state.simulationPhase == .running { handleStopSimulation() }
            send(.setWorkspaceMode(mode: .design))
        case .simulationMode:
            guard state.workspaceMode == .design, state.simulationPhase == .stopped else { return }
            handleStartSimulation()
        case .documentationMode:
            guard state.simulationPhase == .stopped else { return }
            send(.setWorkspaceMode(mode: .documentation))
        case .cancel:
            if state.pendingConnection != nil {
                send(.cancelConnection)
            } else {
                connectionPortPickerNodeID = nil
            }
        }
    }

    private func deleteNodeFromContextMenu(_ nodeID: UUID) {
        guard state.simulationPhase == .stopped else { return }
        send(.selectSingleNode(nodeID: nodeID))
        send(.deleteSelection)
    }

    private func startConnectionFromContextMenu(_ nodeID: UUID) {
        guard state.simulationPhase == .stopped else { return }
        setToolMode(.connect)
        connectionPortPickerNodeID = nodeID
    }

    private func send(_ action: TopologyEditorAction) {
        let before = state
        var snapshot = before
        TopologyEditorReducer.reduce(state: &snapshot, action: action)
        state = snapshot

        guard let actionNameKey = action.undoActionNameKey,
              before.simulationPhase == .stopped,
              snapshot.simulationPhase == .stopped,
              snapshot.persistenceRevision != before.persistenceRevision
        else {
            return
        }

        undoCoordinator.record(
            before: before,
            actionName: FiliusLocalization.t(actionNameKey)
        )
    }
}

private struct RuntimeDeviceSheetItem: Identifiable, Equatable {
    let id: UUID
}

private struct PendingConfigurationSelection: Identifiable {
    let id = UUID()
    let nodeID: UUID?
}

private struct DesignDeviceSheetItem: Identifiable, Equatable {
    let id: UUID
}

private struct ConnectionPortPickerItem: Identifiable, Equatable {
    let id: UUID
}

private struct RouterPortRemovalItem: Identifiable, Equatable {
    let nodeID: UUID
    let portID: UUID
    let label: String
    var id: String { "\(nodeID.uuidString)-\(portID.uuidString)" }
}

private struct TopologyConnectionPortPickerSheet: View {
    let node: TopologyNode
    let availablePortIDs: Set<UUID>
    let isSourceSelection: Bool
    let onSelect: (UUID) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if availablePorts.isEmpty {
                    ContentUnavailableView(
                        FiliusLocalization.t("editor.ports.empty"),
                        systemImage: "cable.connector.slash",
                        description: Text(FiliusLocalization.t("ui.f04d50fc4d2a"))
                    )
                } else {
                    ForEach(availablePorts) { port in
                        Button {
                            onSelect(port.id)
                        } label: {
                            HStack {
                                Text(port.label)
                                Spacer()
                                Text(FiliusLocalization.t("ui.fb95c39327b4"))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("connection.port.\(port.id.uuidString)")
                    }
                }
            }
            .navigationTitle(isSourceSelection ? "Quellanschluss" : "Zielanschluss")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(FiliusLocalization.t("ui.07af7cb30fca")) { onCancel() }
                }
            }
        }
        .accessibilityIdentifier("connection.portPicker")
    }

    private var availablePorts: [TopologyPortMetadata] {
        node.ports.filter { availablePortIDs.contains($0.id) }
    }
}


private struct TopologyDesignPortDetail: Identifiable, Equatable {
    let id: UUID
    let role: String
    let isOccupied: Bool
    let connectionDescription: String
}

struct TopologyDesignDeviceConfigurationDraft: Equatable {
    let nodeID: UUID
    var displayName: String
    var ipAddress: String
    var subnetMask: String
    var defaultGateway: String
    var dnsServer: String
    var interfaceConfigurations: [TopologyDesignInterfaceConfiguration]
    var switchSSID: String
    var switchRetentionSeconds: String
    var remoteLinkPairIdentifier: String
    var remoteLinkLatencyMilliseconds: String
    var remoteLinkEnabled: Bool
    var wirelessEnabled: Bool
    var wirelessSSID: String

    init(
        node: TopologyNode,
        deviceConfiguration: TopologyRuntimeDeviceConfiguration?,
        interfaceConfigurations: [TopologyDesignInterfaceConfiguration],
        switchConfiguration: TopologySwitchConfiguration?,
        remoteLinkConfiguration: TopologyRemoteLinkConfiguration?,
        hostWirelessConfiguration: TopologyHostWirelessConfiguration,
        availableSSIDs: [String]
    ) {
        nodeID = node.id
        displayName = node.displayName
        ipAddress = deviceConfiguration?.ipAddress ?? ""
        subnetMask = deviceConfiguration?.subnetMask ?? ""
        defaultGateway = deviceConfiguration?.defaultGateway ?? ""
        dnsServer = deviceConfiguration?.dnsServer ?? ""
        self.interfaceConfigurations = interfaceConfigurations
        switchSSID = switchConfiguration?.ssid ?? ""
        switchRetentionSeconds = String(
            (switchConfiguration?.retentionTimeMilliseconds
                ?? TopologySwitchConfiguration.defaultRetentionTimeMilliseconds) / 1_000
        )
        let effectiveRemoteLinkConfiguration = remoteLinkConfiguration
            ?? TopologyRemoteLinkConfiguration.defaultConfiguration(nodeID: node.id)
        remoteLinkPairIdentifier = effectiveRemoteLinkConfiguration.pairIdentifier
        remoteLinkLatencyMilliseconds = String(effectiveRemoteLinkConfiguration.latencyMilliseconds)
        remoteLinkEnabled = effectiveRemoteLinkConfiguration.isEnabled
        wirelessEnabled = hostWirelessConfiguration.isEnabled
        wirelessSSID = hostWirelessConfiguration.ssid.isEmpty
            ? availableSSIDs.first ?? ""
            : hostWirelessConfiguration.ssid
    }

    func isValid(for node: TopologyNode, availableSSIDs: [String]) -> Bool {
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        switch node.kind {
        case .pc, .notebook:
            return Self.isIPv4(ipAddress)
                && Self.isSubnetMask(subnetMask)
                && Self.isOptionalIPv4(defaultGateway)
                && Self.isOptionalIPv4(dnsServer)
                && (!wirelessEnabled || availableSSIDs.contains(wirelessSSID))
        case .router:
            return interfacesAreValid(for: node)
        case .gateway:
            return interfacesAreValid(for: node)
                && Self.isOptionalIPv4(defaultGateway)
                && Self.isOptionalIPv4(dnsServer)
        case .networkSwitch:
            return Self.isValidSSID(switchSSID) && retentionMilliseconds != nil
        case .remoteLink:
            return !remoteLinkPairIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && remoteLinkLatencyMillisecondsValue != nil
        case .unsupported:
            return false
        }
    }

    func deviceConfiguration(for node: TopologyNode) -> TopologyRuntimeDeviceConfiguration? {
        switch node.kind {
        case .pc, .notebook:
            return TopologyRuntimeDeviceConfiguration(
                ipAddress: ipAddress,
                subnetMask: subnetMask,
                defaultGateway: defaultGateway,
                dnsServer: dnsServer
            )
        case .gateway:
            let wan = interfaceConfigurations.first
            return TopologyRuntimeDeviceConfiguration(
                ipAddress: wan?.ipAddress ?? "",
                subnetMask: wan?.subnetMask ?? "",
                defaultGateway: defaultGateway,
                dnsServer: dnsServer
            )
        case .router, .networkSwitch, .remoteLink, .unsupported:
            return nil
        }
    }

    func switchConfiguration(for node: TopologyNode) -> TopologySwitchConfiguration? {
        guard node.kind == .networkSwitch, let retentionMilliseconds else { return nil }
        return TopologySwitchConfiguration(
            ssid: switchSSID,
            retentionTimeMilliseconds: retentionMilliseconds
        )
    }

    func remoteLinkConfiguration(for node: TopologyNode) -> TopologyRemoteLinkConfiguration? {
        guard node.kind == .remoteLink, let latencyMilliseconds = remoteLinkLatencyMillisecondsValue else {
            return nil
        }
        return TopologyRemoteLinkConfiguration(
            pairIdentifier: remoteLinkPairIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            latencyMilliseconds: latencyMilliseconds,
            isEnabled: remoteLinkEnabled
        )
    }

    func hostWirelessConfiguration(for node: TopologyNode) -> TopologyHostWirelessConfiguration? {
        guard node.kind.isPCClassEndpoint else { return nil }
        return TopologyHostWirelessConfiguration(
            isEnabled: wirelessEnabled,
            ssid: wirelessEnabled ? wirelessSSID : ""
        )
    }

    var retentionMilliseconds: UInt64? {
        guard let seconds = UInt64(switchRetentionSeconds),
              seconds <= UInt64.max / 1_000 else { return nil }
        return seconds * 1_000
    }

    var remoteLinkLatencyMillisecondsValue: UInt64? {
        UInt64(remoteLinkLatencyMilliseconds.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func interfacesAreValid(for node: TopologyNode) -> Bool {
        interfaceConfigurations.count == node.ports.count
            && interfaceConfigurations.allSatisfy {
                Self.isIPv4($0.ipAddress) && Self.isSubnetMask($0.subnetMask)
            }
    }

    static func isValidSSID(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !normalized.isEmpty
            && normalized.unicodeScalars.allSatisfy { (UInt32(0x20)...UInt32(0x7e)).contains($0.value) }
    }

    static func isOptionalIPv4(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isIPv4(value)
    }

    static func isIPv4(_ value: String) -> Bool {
        let segments = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".", omittingEmptySubsequences: false)
        return segments.count == 4 && segments.allSatisfy { segment in
            !segment.isEmpty && segment.allSatisfy(\.isNumber) && UInt8(String(segment)) != nil
        }
    }

    static func isSubnetMask(_ value: String) -> Bool {
        let segments = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 4 else { return false }
        let octets = segments.compactMap { UInt8(String($0)) }
        guard octets.count == 4 else { return false }
        let mask = octets.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let inverted = ~mask
        return (inverted & (inverted &+ 1)) == 0
    }
}

private struct TopologyDesignDeviceConfigurationEditor: View {
    enum Presentation: Equatable {
        case sheet
        case inspector
    }

    let node: TopologyNode
    @Binding var draft: TopologyDesignDeviceConfigurationDraft
    let availableSSIDs: [String]
    let portDetails: [TopologyDesignPortDetail]
    let presentation: Presentation
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        switch presentation {
        case .sheet:
            NavigationStack {
                configurationForm
                    .navigationTitle(FiliusLocalization.t("inspector.device.title"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { editorToolbar }
            }
            .accessibilityIdentifier("design.configuration.sheet")
        case .inspector:
            VStack(spacing: 0) {
                inspectorHeader
                Divider()
                configurationForm
                    .scrollContentBackground(.hidden)
                Divider()
                inspectorActions
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("design.configuration.inspector")
        }
    }

    private var configurationForm: some View {
        Form {
            Section(FiliusLocalization.t("ui.945d2bcd535c")) {
                TextField(FiliusLocalization.t("editor.field.name"), text: $draft.displayName)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("design.configuration.name")
                LabeledContent(FiliusLocalization.t("ui.edcaf9aaa282"), value: nodeKindLabel)
            }

            switch node.kind {
            case .pc, .notebook:
                endpointSections
            case .router, .gateway:
                routerSections
            case .networkSwitch:
                switchSections
            case .remoteLink:
                remoteLinkSections
            case .unsupported:
                Section { Text(FiliusLocalization.t("ui.2d1053ab9ff3")) }
            }
        }
    }

    @ViewBuilder
    private var endpointSections: some View {
        Section(FiliusLocalization.t("ui.8ddcaf1cd0d5")) {
            ipv4Field(FiliusLocalization.t("editor.field.ipAddress"), text: $draft.ipAddress, identifier: "design.configuration.ip")
            ipv4Field(FiliusLocalization.t("editor.field.subnetMask"), text: $draft.subnetMask, identifier: "design.configuration.mask")
            ipv4Field(FiliusLocalization.t("editor.field.gatewayOptional"), text: $draft.defaultGateway, identifier: "design.configuration.gateway")
            ipv4Field(FiliusLocalization.t("editor.field.dnsOptional"), text: $draft.dnsServer, identifier: "design.configuration.dns")
        }
        Section(FiliusLocalization.t("ui.e50d347f8eb0")) {
            Toggle(FiliusLocalization.t("ui.83d74216aac0"), isOn: $draft.wirelessEnabled)
                .accessibilityIdentifier("design.configuration.wireless.enabled")
            if draft.wirelessEnabled {
                if availableSSIDs.isEmpty {
                    Text(FiliusLocalization.t("ui.cb60e994fda6"))
                        .foregroundStyle(.secondary)
                } else {
                    Picker(FiliusLocalization.t("ui.35730746424a"), selection: $draft.wirelessSSID) {
                        ForEach(availableSSIDs, id: \.self) { ssid in
                            Text(ssid).tag(ssid)
                        }
                    }
                    .accessibilityIdentifier("design.configuration.wireless.ssid")
                }
            }
        }
    }

    @ViewBuilder
    private var routerSections: some View {
        ForEach($draft.interfaceConfigurations) { $configuration in
            Section(interfaceSectionTitle(for: configuration.id)) {
                if let detail = portDetails.first(where: { $0.id == configuration.id }) {
                    LabeledContent(FiliusLocalization.t("ui.2843ee905670"), value: draft.displayName)
                    LabeledContent(FiliusLocalization.t("ui.6237f0afe77f"), value: detail.role)
                    LabeledContent(
                        FiliusLocalization.t("ui.bae7d5be7082"),
                        value: detail.isOccupied
                            ? FiliusLocalization.t("ui.76093d1436a5")
                            : FiliusLocalization.t("ui.308e7cd094c0")
                    )
                    LabeledContent(FiliusLocalization.t("ui.5fbdf271e241"), value: detail.connectionDescription)
                        .accessibilityIdentifier("design.configuration.interface.\(configuration.id.uuidString).connection")
                }
                ipv4Field(
                    FiliusLocalization.t("editor.field.ipAddress"),
                    text: $configuration.ipAddress,
                    identifier: "design.configuration.interface.\(configuration.id.uuidString).ip"
                )
                ipv4Field(
                    FiliusLocalization.t("editor.field.subnetMask"),
                    text: $configuration.subnetMask,
                    identifier: "design.configuration.interface.\(configuration.id.uuidString).mask"
                )
            }
        }
        if node.kind == .gateway {
            Section(FiliusLocalization.t("ui.a2e94dff1252")) {
                ipv4Field(FiliusLocalization.t("editor.field.gatewayOptional"), text: $draft.defaultGateway, identifier: "design.configuration.gateway")
                ipv4Field(FiliusLocalization.t("editor.field.dnsOptional"), text: $draft.dnsServer, identifier: "design.configuration.dns")
            }
        }
    }

    @ViewBuilder
    private var switchSections: some View {
        Section(FiliusLocalization.t("ui.610c95b70c4d")) {
            TextField(FiliusLocalization.t("editor.field.wlanSSID"), text: $draft.switchSSID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("design.configuration.switch.ssid")
            TextField(FiliusLocalization.t("editor.field.satRetentionSeconds"), text: $draft.switchRetentionSeconds)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("design.configuration.switch.retentionSeconds")
        }
        Section(FiliusLocalization.t("ui.10a159f4e31f")) {
            LabeledContent(FiliusLocalization.t("ui.764c4c059865"), value: "\(node.ports.count)")
            LabeledContent(FiliusLocalization.t("ui.14cb26ef5342"), value: "\(node.ports.filter { !$0.isOccupied }.count)")
        }
    }

    @ViewBuilder
    private var remoteLinkSections: some View {
        Section(FiliusLocalization.t("ui.30b8b5ee6804")) {
            Toggle(FiliusLocalization.t("ui.4f68e5cafabb"), isOn: $draft.remoteLinkEnabled)
                .accessibilityIdentifier("design.configuration.remote-link.enabled")
            TextField(FiliusLocalization.t("editor.field.pairID"), text: $draft.remoteLinkPairIdentifier)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("design.configuration.remote-link.pair-id")
            TextField(FiliusLocalization.t("editor.field.deterministicLatency"), text: $draft.remoteLinkLatencyMilliseconds)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("design.configuration.remote-link.latency-ms")
            Text(FiliusLocalization.t("ui.4e9c2f9ead7f"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("design.configuration.remote-link.compatibility")
        }
        Section(FiliusLocalization.t("ui.0351a971d122")) {
            if let detail = portDetails.first {
                LabeledContent(FiliusLocalization.t("ui.2843ee905670"), value: draft.displayName)
                LabeledContent(FiliusLocalization.t("ui.6237f0afe77f"), value: detail.role)
                LabeledContent(
                    FiliusLocalization.t("ui.bae7d5be7082"),
                    value: detail.isOccupied
                        ? FiliusLocalization.t("ui.76093d1436a5")
                        : FiliusLocalization.t("ui.308e7cd094c0")
                )
                LabeledContent(FiliusLocalization.t("ui.5fbdf271e241"), value: detail.connectionDescription)
            }
        }
    }

    private var inspectorHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(FiliusLocalization.t("inspector.device.title"))
                    .font(.headline)
                Text(draft.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(FiliusLocalization.t("ui.07af7cb30fca"))
            .accessibilityIdentifier("design.configuration.close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var inspectorActions: some View {
        HStack {
            Button(FiliusLocalization.t("ui.07af7cb30fca"), action: onCancel)
                .buttonStyle(.bordered)
            Spacer()
            Button(FiliusLocalization.t("ui.9ed6503318b5"), action: onSave)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
                .accessibilityIdentifier("design.configuration.save")
        }
        .padding(12)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(FiliusLocalization.t("ui.07af7cb30fca"), action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(FiliusLocalization.t("ui.9ed6503318b5"), action: onSave)
                .disabled(!isValid)
                .accessibilityIdentifier("design.configuration.save")
        }
    }

    @ViewBuilder
    private func ipv4Field(_ title: String, text: Binding<String>, identifier: String) -> some View {
        TextField(title, text: text)
            .keyboardType(.numbersAndPunctuation)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier(identifier)
    }

    private var isValid: Bool {
        draft.isValid(for: node, availableSSIDs: availableSSIDs)
    }

    private var nodeKindLabel: String {
        switch node.kind {
        case .pc: return FiliusLocalization.t("model.pc")
        case .notebook: return FiliusLocalization.t("model.notebook")
        case .networkSwitch: return FiliusLocalization.t("model.switch")
        case .router: return FiliusLocalization.t("model.router")
        case .gateway: return FiliusLocalization.t("model.gateway")
        case .remoteLink: return FiliusLocalization.t("model.remoteLink")
        case .unsupported: return FiliusLocalization.t("model.unsupported")
        }
    }

    private func interfaceSectionTitle(for portID: UUID) -> String {
        let label = interfaceLabel(for: portID)
        guard let detail = portDetails.first(where: { $0.id == portID }) else {
            return label
        }
        return FiliusLocalization.t("editor.interface.section", detail.role, label)
    }

    private func interfaceLabel(for portID: UUID) -> String {
        guard let port = node.ports.first(where: { $0.id == portID }) else {
            return FiliusLocalization.t("editor.interface")
        }
        return FiliusLocalization.t("editor.interface.named", port.label)
    }
}

private struct JavaConfigurationBackground: View {
    var body: some View {
        if let image = TopologyParityAssetLoader.load(relativePath: "allgemein/konfigPanel_hg.png") {
            Image(uiImage: image)
                .resizable(resizingMode: .tile)
        } else {
            FiliusExperienceTokens.javaPanelSurface
        }
    }
}

private struct ProjectFileNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct ProjectFileOperationError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

private struct FiliusProjectExportSession: Identifiable {
    let id = UUID()
    let fileURL: URL
    let report: TopologyFLSExportReport
}

private struct FiliusProjectExportPicker: UIViewControllerRepresentable {
    let fileURL: URL
    let onCompletion: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        picker.view.accessibilityIdentifier = "project.export.picker"
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) { }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onCompletion: (Result<URL, Error>) -> Void
        private var hasCompleted = false

        init(onCompletion: @escaping (Result<URL, Error>) -> Void) {
            self.onCompletion = onCompletion
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                finish(.failure(CancellationError()))
                return
            }
            finish(.success(url))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            finish(.failure(CancellationError()))
        }

        private func finish(_ result: Result<URL, Error>) {
            guard !hasCompleted else { return }
            hasCompleted = true
            onCompletion(result)
        }
    }
}

struct FiliusProjectFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.filiusProjectArchive] }
    static var writableContentTypes: [UTType] { [.filiusProjectArchive] }

    let archiveData: Data

    init(archiveData: Data) {
        self.archiveData = archiveData
    }

    init(configuration: ReadConfiguration) throws {
        guard let archiveData = configuration.file.regularFileContents else {
            throw ProjectFileOperationError(FiliusLocalization.t("project.import.unreadableData"))
        }
        self.archiveData = archiveData
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: archiveData)
    }
}

enum FiliusProjectImportResourcePolicy {
    static let allowedContentTypes: [UTType] = [.filiusProjectArchive, .data]

    static func accepts(fileURL: URL) -> Bool {
        fileURL.pathExtension.caseInsensitiveCompare("fls") == .orderedSame
    }

    static func accepts(isRegularFile: Bool?) -> Bool {
        isRegularFile == true
    }
}

extension UTType {
    static let filiusProjectArchive = UTType(
        exportedAs: "com.filius.pad.fls",
        conformingTo: .zip
    )
}
