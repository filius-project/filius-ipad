import Combine
import Foundation

/// Owns the editor's bounded document-history stack and bridges it to the
/// system UndoManager so keyboard and iPad undo gestures use the same history.
@MainActor
final class TopologyEditorUndoCoordinator: ObservableObject {
    private(set) var undoManager: UndoManager

    private let limit: Int
    private var currentState: (() -> TopologyEditorState)?
    private var replaceState: ((TopologyEditorState) -> Void)?
    private var hasOpenGrouping = false

    init(limit: Int = 20) {
        self.limit = max(1, limit)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        undoManager.levelsOfUndo = self.limit
        self.undoManager = undoManager
    }

    var canUndo: Bool { undoManager.canUndo }
    var canRedo: Bool { undoManager.canRedo }

    func configure(
        undoManager suppliedUndoManager: UndoManager? = nil,
        currentState: @escaping () -> TopologyEditorState,
        replaceState: @escaping (TopologyEditorState) -> Void
    ) {
        if let suppliedUndoManager, suppliedUndoManager !== undoManager {
            undoManager.removeAllActions()
            undoManager = suppliedUndoManager
            undoManager.groupsByEvent = false
            undoManager.levelsOfUndo = limit
        }
        self.currentState = currentState
        self.replaceState = replaceState
        objectWillChange.send()
    }

    func record(before snapshot: TopologyEditorState, actionName: String) {
        let createsOwnGroup = !hasOpenGrouping
        if createsOwnGroup {
            undoManager.beginUndoGrouping()
        }

        register(snapshot: snapshot, actionName: actionName)
        undoManager.setActionName(actionName)

        if createsOwnGroup {
            undoManager.endUndoGrouping()
        }
        objectWillChange.send()
    }

    func beginGrouping() {
        guard !hasOpenGrouping else { return }
        undoManager.beginUndoGrouping()
        hasOpenGrouping = true
    }

    func endGrouping(actionName: String) {
        guard hasOpenGrouping else { return }
        undoManager.setActionName(actionName)
        undoManager.endUndoGrouping()
        hasOpenGrouping = false
        objectWillChange.send()
    }

    func undo() {
        closeOpenGroupingIfNeeded()
        guard undoManager.canUndo else { return }
        undoManager.undo()
        objectWillChange.send()
    }

    func redo() {
        closeOpenGroupingIfNeeded()
        guard undoManager.canRedo else { return }
        undoManager.redo()
        objectWillChange.send()
    }

    func removeAllActions() {
        closeOpenGroupingIfNeeded()
        undoManager.removeAllActions()
        objectWillChange.send()
    }

    private func register(snapshot: TopologyEditorState, actionName: String) {
        undoManager.registerUndo(withTarget: self) { target in
            target.restore(snapshot: snapshot, actionName: actionName)
        }
    }

    private func restore(snapshot: TopologyEditorState, actionName: String) {
        guard let currentState, let replaceState else { return }

        let current = currentState()
        let operation = undoManager.isUndoing ? "undo" : "redo"
        let replacement = TopologyEditorUndoRestorer.restore(
            snapshot,
            preserving: current,
            operation: operation
        )
        replaceState(replacement)

        register(snapshot: current, actionName: actionName)
        undoManager.setActionName(actionName)
        objectWillChange.send()
    }

    private func closeOpenGroupingIfNeeded() {
        guard hasOpenGrouping else { return }
        undoManager.endUndoGrouping()
        hasOpenGrouping = false
    }
}

enum TopologyEditorUndoRestorer {
    static func restore(
        _ snapshot: TopologyEditorState,
        preserving current: TopologyEditorState,
        operation: String
    ) -> TopologyEditorState {
        var restored = snapshot

        // Navigation and persistence diagnostics are session state, not document
        // edits. Keep them stable while making the restored document dirty.
        restored.viewport = current.viewport
        restored.lastPersistedRevision = current.lastPersistedRevision
        restored.lastPersistenceSaveAt = current.lastPersistenceSaveAt
        restored.lastPersistenceLoadAt = current.lastPersistenceLoadAt
        restored.lastPersistenceError = current.lastPersistenceError
        restored.lastRecoveryMessage = current.lastRecoveryMessage
        restored.lastRecoveryAt = current.lastRecoveryAt
        restored.lastRecoverySucceeded = current.lastRecoverySucceeded
        restored.isRecoveryNoticeVisible = current.isRecoveryNoticeVisible
        restored.persistenceRevision = incrementing(current.persistenceRevision)

        // Undo is document-only. Never revive a half-finished connection or a
        // runtime presentation captured immediately before a design edit.
        restored.simulationPhase = .stopped
        restored.activeTool = .select
        restored.pendingConnection = nil
        restored.openedRuntimeDeviceID = nil
        restored.lastValidationError = nil
        restored.lastInteractionMode = current.lastInteractionMode
        restored.lastAction = operation
        restored.lastActionAt = Date()
        restored.transitionCount = incrementing(current.transitionCount)

        let nodeIDs = Set(restored.graph.nodes.map(\.id))
        restored.selectedNodeIDs.formIntersection(nodeIDs)
        let linkIDs = Set(restored.graph.links.map(\.id))
        restored.selectedLinkIDs.formIntersection(linkIDs)
        if let selectedDocumentationItemID = restored.selectedDocumentationItemID,
           !restored.documentationItems.contains(where: { $0.id == selectedDocumentationItemID }) {
            restored.selectedDocumentationItemID = nil
        }

        return restored
    }

    private static func incrementing(_ value: UInt64) -> UInt64 {
        value == .max ? .max : value + 1
    }

    private static func incrementing(_ value: Int) -> Int {
        value == .max ? .max : value + 1
    }
}

extension TopologyEditorAction {
    /// Positive allowlist: transient UI, viewport, simulation, and runtime
    /// actions intentionally do not enter document history.
    var undoActionNameKey: String? {
        switch self {
        case .placeNode:
            "undo.action.placeNode"
        case .moveSelectedNodes:
            "undo.action.moveNode"
        case .deleteSelection, .deleteLink:
            "undo.action.delete"
        case .completeConnection:
            "undo.action.connect"
        case .createDocumentationItem:
            "undo.action.createDocumentation"
        case .moveSelectedDocumentationItem:
            "undo.action.moveDocumentation"
        case .updateDocumentationItem:
            "undo.action.editDocumentation"
        case .deleteSelectedDocumentationItem:
            "undo.action.delete"
        case .addRouterInterface, .removeRouterInterface, .saveDesignDeviceConfiguration:
            "undo.action.configureDevice"
        case .createProtocolApplication, .updateProtocolApplication, .deleteProtocolApplication:
            "undo.action.editProtocolApplication"
        default:
            nil
        }
    }
}
