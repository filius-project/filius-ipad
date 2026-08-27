import Foundation
import SwiftUI

struct TopologyDebugOverlayView: View {
    let state: TopologyEditorState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(FiliusLocalization.t("debug.tool", debugToolName(state.activeTool)))
                .accessibilityIdentifier("debug.activeTool")

            Text(FiliusLocalization.t("debug.nodes", state.graph.nodes.count))
                .accessibilityIdentifier("debug.nodeCount")

            Text(FiliusLocalization.t("debug.links", state.graph.links.count))
                .accessibilityIdentifier("debug.linkCount")

            Text(FiliusLocalization.t("debug.selected", state.selectedNodeIDs.count))
                .accessibilityIdentifier("debug.selectedNodeCount")

            Text(FiliusLocalization.t("debug.phase", state.simulationPhase.rawValue))
                .accessibilityIdentifier("debug.simulationPhase")

            Text(FiliusLocalization.t("debug.tick", String(state.simulationTick)))
                .accessibilityIdentifier("debug.simulationTick")

            Text(FiliusLocalization.t(
                "debug.packetLoss",
                FiliusLocalization.t(
                    state.networkRuntime.state.globalPacketLossEnabled
                        ? "menu.packetLoss.active"
                        : "menu.packetLoss.inactive"
                )
            ))
            .accessibilityIdentifier("debug.globalPacketLoss")

            Text(FiliusLocalization.t("debug.openedDevice", state.openedRuntimeDeviceID?.uuidString ?? FiliusLocalization.t("ui.fallback.none")))
                .accessibilityIdentifier("debug.openedRuntimeDevice")

            Text(FiliusLocalization.t("debug.openedProgram", openedRuntimeProgramLabel))
                .accessibilityIdentifier("debug.openedRuntimeProgram")

            Text(FiliusLocalization.t("debug.lastEvent", debugRuntimeEvent(state.lastRuntimeEvent)))
                .accessibilityIdentifier("debug.lastRuntimeEvent")

            Text(FiliusLocalization.t("debug.lastRoute", debugRuntimeRoute(state.lastRuntimeEvent)))
                .accessibilityIdentifier("debug.lastRuntimeRoute")

            Text(FiliusLocalization.t("debug.lastFault", debugRuntimeFault(state.lastRuntimeFault)))
                .accessibilityIdentifier("debug.lastRuntimeFault")

            Text(FiliusLocalization.t("debug.lastPingEvent", debugRuntimeEvent(state.lastPingEvent)))
                .accessibilityIdentifier("debug.lastPingEvent")

            Text(FiliusLocalization.t("debug.lastPingFault", debugRuntimeFault(state.lastPingFault)))
                .accessibilityIdentifier("debug.lastPingFault")

            Text(FiliusLocalization.t("debug.consoleEntries", openedRuntimeConsoleCount))
                .accessibilityIdentifier("debug.runtimeConsoleCount")

            Text(FiliusLocalization.t("debug.dhcpLeases", state.runtimeDHCPLeaseByNodeID.count))
                .accessibilityIdentifier("debug.runtimeDHCPLeaseCount")

            Text(FiliusLocalization.t("debug.dnsRecords", state.runtimeDNSServerConfigurationsByNodeID.values.reduce(0) { $0 + $1.recordsByHostname.count }))
                .accessibilityIdentifier("debug.runtimeDNSRecordCount")

            Text(FiliusLocalization.t("debug.webServers", state.runtimeWebServerByNodeID.count))
                .accessibilityIdentifier("debug.runtimeWebServerCount")

            Text(FiliusLocalization.t("debug.echoServers", state.runtimeEchoServerByNodeID.count))
                .accessibilityIdentifier("debug.runtimeEchoServerCount")

            Text(FiliusLocalization.t("debug.fileSelections", state.runtimeFileExplorerSelectionByNodeID.count))
                .accessibilityIdentifier("debug.runtimeFileExplorerSelectionCount")

            Text(FiliusLocalization.t("debug.imageSelections", state.runtimeImageViewerSelectionByNodeID.count))
                .accessibilityIdentifier("debug.runtimeImageViewerSelectionCount")

            Text(FiliusLocalization.t("debug.fileSystems", state.virtualFileSystemsByNodeID.count))
                .accessibilityIdentifier("debug.virtualFileSystemCount")

            Text(FiliusLocalization.t("debug.fileEntries", state.virtualFileSystemsByNodeID.values.reduce(0) { $0 + $1.allEntries().count }))
                .accessibilityIdentifier("debug.virtualFileSystemEntryCount")

            Text(FiliusLocalization.t("debug.textDrafts", state.runtimeTextEditorDraftByNodeID.count))
                .accessibilityIdentifier("debug.runtimeTextEditorDraftCount")

            Text(
                String(
                    format: FiliusLocalization.t("debug.camera"),
                    state.viewport.offset.width,
                    state.viewport.offset.height
                )
            )
            .accessibilityIdentifier("debug.cameraOffset")

            Text(FiliusLocalization.t("debug.zoom", state.viewport.scale))
                .accessibilityIdentifier("debug.zoomScale")

            Text(FiliusLocalization.t("debug.persistenceRevision", state.persistenceRevision))
                .accessibilityIdentifier("debug.persistenceRevision")

            Text(FiliusLocalization.t("debug.lastSave", debugDate(state.lastPersistenceSaveAt)))
                .accessibilityIdentifier("debug.lastPersistenceSaveAt")

            Text(FiliusLocalization.t("debug.lastLoad", debugDate(state.lastPersistenceLoadAt)))
                .accessibilityIdentifier("debug.lastPersistenceLoadAt")

            Text(FiliusLocalization.t("debug.recoveryState", debugRecoveryState()))
                .accessibilityIdentifier("debug.lastRecoveryState")

            Text(FiliusLocalization.t("debug.lastRecovery", debugDate(state.lastRecoveryAt)))
                .accessibilityIdentifier("debug.lastRecoveryAt")

            Text(FiliusLocalization.t("debug.persistenceError", debugPersistenceError(state.lastPersistenceError)))
                .accessibilityIdentifier("debug.lastPersistenceError")

            Text(FiliusLocalization.t("debug.lastError", state.lastValidationError?.localizedMessage ?? FiliusLocalization.t("ui.fallback.none")))
                .accessibilityIdentifier("debug.lastValidationError")

            Text(FiliusLocalization.t("debug.lastAction", state.lastAction ?? FiliusLocalization.t("ui.fallback.none")))
                .accessibilityIdentifier("debug.lastAction")

            Text(FiliusLocalization.t("debug.lastMode", state.lastInteractionMode ?? FiliusLocalization.t("ui.fallback.none")))
                .accessibilityIdentifier("debug.lastInteractionMode")

            Text(FiliusLocalization.t("debug.transitions", state.transitionCount))
                .accessibilityIdentifier("debug.transitionCount")
        }
        .font(.footnote.monospaced())
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var openedRuntimeConsoleCount: Int {
        guard let openedRuntimeDeviceID = state.openedRuntimeDeviceID else {
            return 0
        }

        return state.runtimeConsoleEntriesByNodeID[openedRuntimeDeviceID]?.count ?? 0
    }

    private var openedRuntimeProgramLabel: String {
        guard let openedRuntimeDeviceID = state.openedRuntimeDeviceID,
              let program = state.runtimeActiveProgramByNodeID[openedRuntimeDeviceID]
        else {
            return FiliusLocalization.t("ui.fallback.none")
        }

        return program.rawValue
    }

    private func debugToolName(_ mode: TopologyEditorToolMode) -> String {
        switch mode {
        case .select:
            return FiliusLocalization.t("palette.select")
        case .connect:
            return FiliusLocalization.t("palette.connect")
        case let .place(kind):
            return FiliusLocalization.t("debug.place", kind.rawValue)
        }
    }

    private func debugRuntimeEvent(_ event: TopologyRuntimeEvent?) -> String {
        guard let event else {
            return FiliusLocalization.t("ui.fallback.none")
        }

        if let detail = event.detail, !detail.isEmpty {
            return FiliusLocalization.t("debug.event.detail", event.code.rawValue, detail)
        }

        return event.code.rawValue
    }

    private func debugRuntimeRoute(_ event: TopologyRuntimeEvent?) -> String {
        guard let event,
              let detail = event.detail,
              detail.contains("path=") || detail.contains("hops=") || detail.contains("latencyMs=")
        else {
            return FiliusLocalization.t("ui.fallback.none")
        }

        return detail
    }

    private func debugRuntimeFault(_ fault: TopologyRuntimeFault?) -> String {
        guard let fault else {
            return FiliusLocalization.t("ui.fallback.none")
        }

        return FiliusLocalization.t("debug.fault.detail", fault.category.rawValue, fault.code, fault.message)
    }

    private func debugPersistenceError(_ failure: TopologyPersistenceFailure?) -> String {
        guard let failure else {
            return FiliusLocalization.t("ui.fallback.none")
        }

        let timestamp = ISO8601DateFormatter().string(from: failure.occurredAt)
        return FiliusLocalization.t("debug.persistence.detail", failure.operation.rawValue, failure.code.rawValue, failure.detail, timestamp)
    }

    private func debugRecoveryState() -> String {
        guard let message = state.lastRecoveryMessage else {
            return FiliusLocalization.t("ui.fallback.none")
        }

        let prefix: String
        if let lastRecoverySucceeded = state.lastRecoverySucceeded {
            prefix = lastRecoverySucceeded
                ? FiliusLocalization.t("debug.recovery.success")
                : FiliusLocalization.t("debug.recovery.failure")
        } else {
            prefix = FiliusLocalization.t("debug.recovery.unknown")
        }

        return FiliusLocalization.t("debug.recovery.message", prefix, message)
    }

    private func debugDate(_ date: Date?) -> String {
        guard let date else {
            return FiliusLocalization.t("ui.fallback.none")
        }

        return ISO8601DateFormatter().string(from: date)
    }
}
