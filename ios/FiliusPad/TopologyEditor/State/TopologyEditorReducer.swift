import CoreGraphics
import Foundation

enum TopologyEditorReducer {
    private static let maxRuntimeConsoleEntriesPerDevice = 60
    private static let terminalCatMaximumBytes = 4_096
    private static let terminalCatMaximumLines = 48

    private enum RuntimeCommandTarget {
        case ipAddress(String)
        case hostname(String)
    }

    private enum RuntimeCommand {
        case ping(RuntimeCommandTarget)
        case trace(RuntimeCommandTarget)
        case route(RuntimeCommandTarget)
        case hostResolve(hostname: String, commandToken: String)
        case help(commandToken: String?)
        case ipconfig
        case netstat
        case arpList(filterIPAddress: String?)
        case arpDelete(ipAddress: String?)
        case arpSend(senderIPAddress: String, targetIPAddress: String)
        case tcpdump
        case dhcpLease(ipAddress: String, subnetMask: String)
        case dhcpRelease
        case dnsRegister(hostname: String, targetIPAddress: String)
        case dnsRemove(hostname: String)
        case dnsResolve(hostname: String)
        case filesystemCat(path: String)
        case filesystemCd(path: String?)
        case filesystemCopy(source: String, destination: String)
        case filesystemDelete(path: String)
        case filesystemList(path: String?)
        case filesystemMakeDirectory(path: String)
        case filesystemMove(source: String, destination: String)
        case filesystemPrintWorkingDirectory
        case filesystemTouch(path: String)
    }

    private enum RuntimeCommandParseResult {
        case success(RuntimeCommand)
        case malformed(command: String?, reason: String)
        case unsupported(command: String)
    }

    private enum PortResolutionResult {
        case success(UUID)
        case failure(TopologyValidationErrorCode)
    }

    private enum UnsupportedRuntimeCommandFamily: String {
        case generic
        case linkLayer
        case hostConfiguration
        case socketInspection
        case filesystem
    }

    private struct UnsupportedRuntimeCommandDescriptor {
        let faultCode: String
        let message: String
        let detail: String
    }

    static func reduce(state: inout TopologyEditorState, action: TopologyEditorAction) {
        state.transitionCount += 1
        state.lastAction = action.debugName
        state.lastActionAt = Date()
        state.lastValidationError = nil

        switch action {
        case let .placeNode(kind, point, nodeID):
            guard let nodeID else {
                state.lastValidationError = .missingNodeIdentifier
                return
            }

            guard kind != .unsupported else {
                state.lastValidationError = .unknownNodeKind
                return
            }

            let node = TopologyNode(id: nodeID, kind: kind, position: point)
            state.graph.appendNode(node)
            state.seedJavaRuntimeInterfaceDefaults(for: node)
            state.selectedNodeIDs = [nodeID]
            state.selectedLinkIDs.removeAll()
            state.activeTool = .select
            state.pendingConnection = nil
            advancePersistenceRevision(state: &state)

        case let .selectSingleNode(nodeID):
            guard let nodeID else {
                state.selectedNodeIDs = []
                state.lastValidationError = .missingNodeIdentifier
                return
            }

            guard state.graph.containsNode(id: nodeID) else {
                state.selectedNodeIDs = []
                state.lastValidationError = .nodeNotFound
                return
            }

            state.selectedNodeIDs = [nodeID]
            state.selectedLinkIDs.removeAll()
            state.activeTool = .select

        case let .selectSingleLink(linkID):
            guard let linkID else {
                state.selectedLinkIDs = []
                state.lastValidationError = .malformedActionPayload
                return
            }
            guard state.graph.containsLink(id: linkID) else {
                state.selectedLinkIDs = []
                state.lastValidationError = .linkNotFound
                return
            }
            state.selectedNodeIDs.removeAll()
            state.selectedLinkIDs = [linkID]
            state.activeTool = .select

        case let .selectNodes(selectionRect):
            guard let selectionRect else {
                state.lastValidationError = .malformedActionPayload
                return
            }

            let normalizedRect = selectionRect.standardized
            let selectedNodeIDs = state.graph.nodes
                .filter { normalizedRect.contains($0.position) }
                .map(\.id)

            state.selectedNodeIDs = Set(selectedNodeIDs)
            state.selectedLinkIDs.removeAll()
            state.activeTool = .select

        case .clearSelection:
            state.selectedNodeIDs.removeAll()
            state.selectedLinkIDs.removeAll()
            state.activeTool = .select

        case .deleteSelection:
            guard state.simulationPhase == .stopped else {
                state.lastValidationError = .simulationMustBeStopped
                return
            }
            let nodeIDs = state.selectedNodeIDs
            let directLinkIDs = state.selectedLinkIDs
            guard !nodeIDs.isEmpty || !directLinkIDs.isEmpty else {
                return
            }
            _ = state.graph.removeLinks(withIDs: directLinkIDs)
            _ = state.graph.removeNodes(withIDs: nodeIDs)
            for nodeID in nodeIDs {
                removeDeviceState(nodeID: nodeID, state: &state)
            }
            state.selectedNodeIDs.removeAll()
            state.selectedLinkIDs.removeAll()
            state.pendingConnection = nil
            state.activeTool = .select
            advancePersistenceRevision(state: &state)

        case .cancelConnection:
            state.pendingConnection = nil
            state.lastValidationError = nil

        case let .deleteLink(linkID):
            guard state.simulationPhase == .stopped else {
                state.lastValidationError = .simulationMustBeStopped
                return
            }
            guard let linkID else {
                state.lastValidationError = .malformedActionPayload
                return
            }
            guard state.graph.containsLink(id: linkID) else {
                state.lastValidationError = .linkNotFound
                return
            }
            _ = state.graph.removeLinks(withIDs: [linkID])
            state.selectedLinkIDs.remove(linkID)
            advancePersistenceRevision(state: &state)

        case let .setWorkspaceMode(mode):
            guard state.simulationPhase == .stopped else {
                state.lastValidationError = .simulationMustBeStopped
                return
            }
            state.workspaceMode = mode
            state.pendingConnection = nil
            state.activeTool = .select
            state.documentationTool = .select
            state.selectedNodeIDs.removeAll()
            state.selectedLinkIDs.removeAll()
            state.selectedDocumentationItemID = nil

        case let .setDocumentationTool(tool):
            guard state.simulationPhase == .stopped, state.workspaceMode == .documentation else {
                state.lastValidationError = .simulationMustBeStopped
                return
            }
            state.documentationTool = tool
            if tool != .select {
                state.selectedDocumentationItemID = nil
            }

        case let .createDocumentationItem(kind, point, itemID):
            guard state.simulationPhase == .stopped, state.workspaceMode == .documentation else {
                state.lastValidationError = .simulationMustBeStopped
                return
            }
            guard let itemID, isFinitePoint(point) else {
                state.lastValidationError = .malformedActionPayload
                return
            }
            guard !state.documentationItems.contains(where: { $0.id == itemID }) else {
                state.lastValidationError = .malformedActionPayload
                return
            }
            let order = state.documentationItems.nextDocumentationOrder
            let item: TopologyDocumentationItem
            switch kind {
            case .text:
                item = .text(id: itemID, origin: point, order: order)
            case .rectangle:
                item = .rectangle(id: itemID, origin: point, order: order)
            }
            state.documentationItems.append(item)
            state.selectedDocumentationItemID = itemID
            state.documentationTool = .select
            advancePersistenceRevision(state: &state)

        case let .selectDocumentationItem(itemID):
            guard state.workspaceMode == .documentation else {
                state.selectedDocumentationItemID = nil
                return
            }
            guard let itemID else {
                state.selectedDocumentationItemID = nil
                return
            }
            guard state.documentationItems.contains(where: { $0.id == itemID }) else {
                state.selectedDocumentationItemID = nil
                state.lastValidationError = .malformedActionPayload
                return
            }
            state.selectedDocumentationItemID = itemID
            state.documentationTool = .select

        case let .moveSelectedDocumentationItem(delta):
            guard state.simulationPhase == .stopped, state.workspaceMode == .documentation else {
                state.lastValidationError = .simulationMustBeStopped
                return
            }
            guard let delta, isFiniteSize(delta), delta != .zero,
                  let itemID = state.selectedDocumentationItemID,
                  let index = state.documentationItems.firstIndex(where: { $0.id == itemID })
            else {
                if delta == nil { state.lastValidationError = .malformedActionPayload }
                return
            }
            state.documentationItems[index].frame = TopologyDocumentationItem.normalizedFrame(
                state.documentationItems[index].frame.offsetBy(dx: delta.width, dy: delta.height)
            )
            advancePersistenceRevision(state: &state)

        case let .updateDocumentationItem(item):
            guard state.simulationPhase == .stopped, state.workspaceMode == .documentation else {
                state.lastValidationError = .simulationMustBeStopped
                return
            }
            guard let item,
                  let index = state.documentationItems.firstIndex(where: { $0.id == item.id }),
                  item.hasSafeRenderValues
            else {
                state.lastValidationError = .malformedActionPayload
                return
            }
            state.documentationItems[index] = TopologyDocumentationItem(
                id: item.id,
                kind: item.kind,
                frame: item.frame,
                text: item.text,
                color: item.color,
                fontName: item.fontName,
                fontSize: item.fontSize,
                isBold: item.isBold,
                order: state.documentationItems[index].order
            )
            state.selectedDocumentationItemID = item.id
            advancePersistenceRevision(state: &state)

        case .deleteSelectedDocumentationItem:
            guard state.simulationPhase == .stopped, state.workspaceMode == .documentation else {
                state.lastValidationError = .simulationMustBeStopped
                return
            }
            guard let itemID = state.selectedDocumentationItemID else { return }
            let originalCount = state.documentationItems.count
            state.documentationItems.removeAll { $0.id == itemID }
            state.selectedDocumentationItemID = nil
            if state.documentationItems.count != originalCount {
                advancePersistenceRevision(state: &state)
            }

        case let .addRouterInterface(nodeID, portID):
            guard state.simulationPhase == .stopped else {
                state.lastValidationError = .simulationMustBeStopped
                return
            }
            guard let nodeID, let portID else {
                state.lastValidationError = nodeID == nil ? .missingNodeIdentifier : .invalidPortIdentifier
                return
            }
            guard let nodeIndex = state.graph.nodeIndex(withID: nodeID) else {
                state.lastValidationError = .nodeNotFound
                return
            }
            guard state.graph.nodes[nodeIndex].kind == .router else {
                state.lastValidationError = .unsupportedConfiguration
                return
            }
            guard !state.graph.nodes[nodeIndex].ports.contains(where: { $0.id == portID }) else {
                state.lastValidationError = .invalidPortIdentifier
                return
            }
            let labels = Set(state.graph.nodes[nodeIndex].ports.map(\.label))
            var index = 1
            while labels.contains("rt\(index)") {
                index += 1
            }
            let port = TopologyPortMetadata(id: portID, label: "rt\(index)")
            state.graph.nodes[nodeIndex].ports.append(port)
            state.runtimeInterfaceConfigurations[
                TopologyRuntimeInterfaceKey(nodeID: nodeID, portID: portID)
            ] = TopologyRuntimeInterfaceConfiguration(
                ipAddress: "192.168.0.10",
                subnetMask: "255.255.255.0"
            )
            advancePersistenceRevision(state: &state)

        case let .removeRouterInterface(nodeID, portID, confirmed):
            guard state.simulationPhase == .stopped else {
                state.lastValidationError = .simulationMustBeStopped
                return
            }
            guard let nodeID else {
                state.lastValidationError = .missingNodeIdentifier
                return
            }
            guard let portID else {
                state.lastValidationError = .invalidPortIdentifier
                return
            }
            guard let confirmed else {
                state.lastValidationError = .malformedActionPayload
                return
            }
            guard let nodeIndex = state.graph.nodeIndex(withID: nodeID) else {
                state.lastValidationError = .nodeNotFound
                return
            }
            guard state.graph.nodes[nodeIndex].kind == .router else {
                state.lastValidationError = .unsupportedConfiguration
                return
            }
            guard state.graph.nodes[nodeIndex].ports.count > 1 else {
                state.lastValidationError = .routerRequiresInterface
                return
            }
            guard state.graph.nodes[nodeIndex].ports.contains(where: { $0.id == portID }) else {
                state.lastValidationError = .invalidPortIdentifier
                return
            }
            let connectedLinkIDs = Set(state.graph.links.filter {
                ($0.sourceNodeID == nodeID && $0.sourcePortID == portID)
                    || ($0.targetNodeID == nodeID && $0.targetPortID == portID)
            }.map(\.id))
            guard connectedLinkIDs.isEmpty || confirmed else {
                state.lastValidationError = .connectedPortRemovalRequiresConfirmation
                return
            }
            _ = state.graph.removeLinks(withIDs: connectedLinkIDs)
            state.graph.nodes[nodeIndex].ports.removeAll { $0.id == portID }
            state.runtimeInterfaceConfigurations.removeValue(
                forKey: TopologyRuntimeInterfaceKey(nodeID: nodeID, portID: portID)
            )
            if state.pendingConnection?.sourceNodeID == nodeID,
               state.pendingConnection?.sourcePortID == portID {
                state.pendingConnection = nil
            }
            state.selectedLinkIDs.subtract(connectedLinkIDs)
            advancePersistenceRevision(state: &state)

        case let .setActiveTool(mode):
            state.activeTool = mode
            if mode != .connect {
                state.pendingConnection = nil
            }

        case let .saveDesignDeviceConfiguration(
            nodeID,
            displayName,
            deviceConfiguration,
            interfaceConfigurations,
            switchConfiguration,
            remoteLinkConfiguration,
            hostWirelessConfiguration
        ):
            guard state.simulationPhase == .stopped else {
                state.lastValidationError = .simulationMustBeStopped
                return
            }

            guard let nodeID else {
                state.lastValidationError = .missingNodeIdentifier
                return
            }
            guard let nodeIndex = state.graph.nodeIndex(withID: nodeID) else {
                state.lastValidationError = .nodeNotFound
                return
            }
            guard let displayName, let interfaceConfigurations else {
                state.lastValidationError = .malformedActionPayload
                return
            }

            let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedDisplayName.isEmpty else {
                state.lastValidationError = .invalidDisplayName
                return
            }

            let node = state.graph.nodes[nodeIndex]
            var normalizedDeviceConfiguration: TopologyRuntimeDeviceConfiguration?
            var normalizedInterfaceConfigurations: [TopologyDesignInterfaceConfiguration] = []
            var normalizedSwitchConfiguration: TopologySwitchConfiguration?
            var normalizedRemoteLinkConfiguration: TopologyRemoteLinkConfiguration?
            var normalizedHostWirelessConfiguration: TopologyHostWirelessConfiguration?

            switch node.kind {
            case .pc, .notebook:
                guard interfaceConfigurations.isEmpty,
                      switchConfiguration == nil,
                      remoteLinkConfiguration == nil,
                      let hostWirelessConfiguration,
                      let deviceConfiguration,
                      let ipAddress = normalizedIPv4Address(deviceConfiguration.ipAddress),
                      let subnetMask = normalizedSubnetMask(deviceConfiguration.subnetMask),
                      let defaultGateway = normalizedOptionalIPv4Address(deviceConfiguration.defaultGateway),
                      let dnsServer = normalizedOptionalIPv4Address(deviceConfiguration.dnsServer)
                else {
                    state.lastValidationError = .invalidDeviceConfiguration
                    return
                }

                let wirelessSSID = hostWirelessConfiguration.ssid.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !hostWirelessConfiguration.isEnabled || normalizedSSID(wirelessSSID) != nil else {
                    state.lastValidationError = .invalidDeviceConfiguration
                    return
                }
                if hostWirelessConfiguration.isEnabled,
                   node.ports.contains(where: { state.graph.isPortConnected(nodeID: nodeID, portID: $0.id) }) {
                    state.lastValidationError = .noFreePort
                    return
                }

                normalizedDeviceConfiguration = TopologyRuntimeDeviceConfiguration(
                    ipAddress: ipAddress,
                    subnetMask: subnetMask,
                    defaultGateway: defaultGateway,
                    dnsServer: dnsServer
                )
                normalizedHostWirelessConfiguration = TopologyHostWirelessConfiguration(
                    isEnabled: hostWirelessConfiguration.isEnabled,
                    ssid: hostWirelessConfiguration.isEnabled ? wirelessSSID : ""
                )

            case .router, .gateway:
                guard switchConfiguration == nil,
                      remoteLinkConfiguration == nil,
                      hostWirelessConfiguration == nil else {
                    state.lastValidationError = .invalidDeviceConfiguration
                    return
                }
                let portIDs = Set(node.ports.map(\.id))
                guard !node.ports.isEmpty,
                      interfaceConfigurations.count == node.ports.count,
                      Set(interfaceConfigurations.map(\.id)) == portIDs
                else {
                    state.lastValidationError = .invalidDeviceConfiguration
                    return
                }

                for configuration in interfaceConfigurations {
                    guard let ipAddress = normalizedIPv4Address(configuration.ipAddress),
                          let subnetMask = normalizedSubnetMask(configuration.subnetMask)
                    else {
                        state.lastValidationError = .invalidDeviceConfiguration
                        return
                    }
                    normalizedInterfaceConfigurations.append(
                        TopologyDesignInterfaceConfiguration(
                            id: configuration.id,
                            ipAddress: ipAddress,
                            subnetMask: subnetMask
                        )
                    )
                }

                if node.kind == .gateway {
                    guard let deviceConfiguration,
                          let wanPort = node.ports.first,
                          let wan = normalizedInterfaceConfigurations.first(where: { $0.id == wanPort.id }),
                          let defaultGateway = normalizedOptionalIPv4Address(deviceConfiguration.defaultGateway),
                          let dnsServer = normalizedOptionalIPv4Address(deviceConfiguration.dnsServer)
                    else {
                        state.lastValidationError = .invalidDeviceConfiguration
                        return
                    }
                    normalizedDeviceConfiguration = TopologyRuntimeDeviceConfiguration(
                        ipAddress: wan.ipAddress,
                        subnetMask: wan.subnetMask,
                        defaultGateway: defaultGateway,
                        dnsServer: dnsServer
                    )
                } else if deviceConfiguration != nil {
                    state.lastValidationError = .invalidDeviceConfiguration
                    return
                }

            case .networkSwitch:
                guard deviceConfiguration == nil,
                      interfaceConfigurations.isEmpty,
                      remoteLinkConfiguration == nil,
                      hostWirelessConfiguration == nil,
                      let switchConfiguration,
                      let normalizedSwitchSSID = normalizedSSID(switchConfiguration.ssid)
                else {
                    state.lastValidationError = .invalidDeviceConfiguration
                    return
                }
                normalizedSwitchConfiguration = TopologySwitchConfiguration(
                    ssid: normalizedSwitchSSID,
                    retentionTimeMilliseconds: switchConfiguration.retentionTimeMilliseconds
                )

            case .remoteLink:
                guard deviceConfiguration == nil,
                      interfaceConfigurations.isEmpty,
                      switchConfiguration == nil,
                      hostWirelessConfiguration == nil,
                      let remoteLinkConfiguration
                else {
                    state.lastValidationError = .invalidDeviceConfiguration
                    return
                }
                let normalizedPairIdentifier = remoteLinkConfiguration.pairIdentifier
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedPairIdentifier.isEmpty else {
                    state.lastValidationError = .invalidDeviceConfiguration
                    return
                }
                normalizedRemoteLinkConfiguration = TopologyRemoteLinkConfiguration(
                    pairIdentifier: normalizedPairIdentifier,
                    latencyMilliseconds: remoteLinkConfiguration.latencyMilliseconds,
                    isEnabled: remoteLinkConfiguration.isEnabled
                )

            case .unsupported:
                state.lastValidationError = .unsupportedConfiguration
                return
            }

            state.graph.nodes[nodeIndex].displayName = normalizedDisplayName
            if let normalizedDeviceConfiguration {
                state.runtimeDeviceConfigurations[nodeID] = normalizedDeviceConfiguration
            } else if !node.kind.isPCClassEndpoint && node.kind != .gateway {
                state.runtimeDeviceConfigurations.removeValue(forKey: nodeID)
            }
            for configuration in normalizedInterfaceConfigurations {
                state.runtimeInterfaceConfigurations[
                    TopologyRuntimeInterfaceKey(nodeID: nodeID, portID: configuration.id)
                ] = TopologyRuntimeInterfaceConfiguration(
                    ipAddress: configuration.ipAddress,
                    subnetMask: configuration.subnetMask
                )
            }
            if let normalizedSwitchConfiguration {
                state.switchConfigurationsByNodeID[nodeID] = normalizedSwitchConfiguration
            } else {
                state.switchConfigurationsByNodeID.removeValue(forKey: nodeID)
            }
            if let normalizedRemoteLinkConfiguration {
                state.remoteLinkConfigurationsByNodeID[nodeID] = normalizedRemoteLinkConfiguration
            } else {
                state.remoteLinkConfigurationsByNodeID.removeValue(forKey: nodeID)
            }
            if let normalizedHostWirelessConfiguration, normalizedHostWirelessConfiguration.isEnabled {
                state.hostWirelessConfigurationsByNodeID[nodeID] = normalizedHostWirelessConfiguration
            } else {
                state.hostWirelessConfigurationsByNodeID.removeValue(forKey: nodeID)
            }
            advancePersistenceRevision(state: &state)

        case let .startConnection(nodeID, portID):
            guard let nodeID else {
                state.lastValidationError = .missingNodeIdentifier
                return
            }

            guard let sourceNode = state.graph.node(withID: nodeID) else {
                state.lastValidationError = .nodeNotFound
                return
            }
            if sourceNode.kind.isPCClassEndpoint, state.hostWirelessConfigurationsByNodeID[nodeID]?.isEnabled == true {
                state.lastValidationError = .noFreePort
                return
            }

            switch resolvePortID(on: sourceNode, requestedPortID: portID, graph: state.graph) {
            case let .success(sourcePortID):
                state.pendingConnection = TopologyConnectionDraft(sourceNodeID: nodeID, sourcePortID: sourcePortID)
                state.activeTool = .connect
                state.selectedNodeIDs = [nodeID]

            case let .failure(validationError):
                state.lastValidationError = validationError
            }

        case let .completeConnection(nodeID, portID):
            guard let nodeID else {
                state.lastValidationError = .missingNodeIdentifier
                return
            }

            guard let pendingConnection = state.pendingConnection else {
                state.lastValidationError = .connectionSourceNotSelected
                return
            }

            guard let sourceNode = state.graph.node(withID: pendingConnection.sourceNodeID) else {
                state.pendingConnection = nil
                state.lastValidationError = .nodeNotFound
                return
            }

            guard let targetNode = state.graph.node(withID: nodeID) else {
                state.lastValidationError = .nodeNotFound
                return
            }

            guard sourceNode.id != targetNode.id else {
                state.lastValidationError = .selfConnectionNotAllowed
                return
            }

            guard areCompatibleEndpoints(sourceNode, targetNode) else {
                state.lastValidationError = .incompatibleEndpoint
                return
            }

            guard !sourceNode.kind.isPCClassEndpoint || state.hostWirelessConfigurationsByNodeID[sourceNode.id]?.isEnabled != true else {
                state.lastValidationError = .noFreePort
                return
            }

            guard isPortAvailable(
                sourcePortID: pendingConnection.sourcePortID,
                on: sourceNode,
                in: state.graph
            ) else {
                state.lastValidationError = .noFreePort
                return
            }

            guard !targetNode.kind.isPCClassEndpoint || state.hostWirelessConfigurationsByNodeID[targetNode.id]?.isEnabled != true else {
                state.lastValidationError = .noFreePort
                return
            }

            switch resolvePortID(on: targetNode, requestedPortID: portID, graph: state.graph) {
            case let .success(targetPortID):
                let link = TopologyLink(
                    sourceNodeID: sourceNode.id,
                    sourcePortID: pendingConnection.sourcePortID,
                    targetNodeID: targetNode.id,
                    targetPortID: targetPortID
                )
                state.graph.appendLink(link)
                state.selectedNodeIDs = [sourceNode.id, targetNode.id]
                state.selectedLinkIDs.removeAll()
                state.pendingConnection = nil
                state.activeTool = .select
                advancePersistenceRevision(state: &state)

            case let .failure(validationError):
                state.lastValidationError = validationError
            }

        case let .setSimulationSpeed(percent):
            guard let percent else {
                setMalformedRuntimePayload(
                    state: &state,
                    reason: "setSimulationSpeed requires percent"
                )
                return
            }
            state.networkRuntime.setSimulationSpeed(percent: percent)
            recordRuntimeEvent(
                state: &state,
                code: .simulationSpeedChanged,
                detail: "percent=\(state.networkRuntime.simulationSpeed.percent),linkDelayMilliseconds=\(state.networkRuntime.simulationSpeed.linkTransmissionDelayMilliseconds)"
            )

        case .startSimulation:
            guard state.simulationPhase != .running else {
                recordRuntimeEvent(
                    state: &state,
                    code: .simulationStartIgnoredAlreadyRunning
                )
                return
            }

            state.runtimeDHCPLeaseByNodeID.removeAll()
            state.runtimeDNSServerSocketIDByNodeID.removeAll()
            state.runtimeDNSCacheByNodeID.removeAll()
            let runtimeSeed = state.networkRuntime.state.seed
            state.networkRuntime.handle(
                .start(
                    snapshot: TopologyNetworkRuntimeTopologySnapshot(editorState: state),
                    seed: runtimeSeed,
                    initialTimeMilliseconds: state.simulationTick
                )
            )
            state.workspaceMode = .design
            state.documentationTool = .select
            state.selectedDocumentationItemID = nil
            state.simulationPhase = .running
            let seededPrograms = seedRuntimeDesktopDefaults(state: &state)
            state.lastRuntimeFault = nil
            recordRuntimeEvent(
                state: &state,
                code: .simulationStarted,
                detail: "seededCommandPrompts=\(seededPrograms)"
            )

        case .stopSimulation:
            guard state.simulationPhase != .stopped else {
                recordRuntimeEvent(
                    state: &state,
                    code: .simulationStopIgnoredAlreadyStopped
                )
                return
            }

            stopSimulationRuntime(state: &state)
            recordRuntimeEvent(state: &state, code: .simulationStopped)

        case let .simulationTick(step):
            guard let step, step > 0 else {
                setMalformedRuntimePayload(
                    state: &state,
                    reason: "simulationTick requires a positive step"
                )
                return
            }

            guard state.simulationPhase == .running else {
                recordRuntimeEvent(
                    state: &state,
                    code: .simulationTickIgnoredWhileStopped,
                    detail: "phase=\(state.simulationPhase.rawValue),step=\(step)"
                )
                return
            }

            // Runtime APIs are intentionally synchronous for the native app surface: TCP/UDP
            // connect/send and link delivery may advance the engine while this reducer call is
            // still on the stack. Treat the engine's clock as authoritative before planning the
            // next UI pulse so a normal pulse can never target a time in the past.
            let authoritativeTick = max(
                state.simulationTick,
                state.networkRuntime.state.currentTimeMilliseconds
            )
            state.simulationTick = authoritativeTick
            let (nextTick, overflowed) = authoritativeTick.addingReportingOverflow(step)
            guard !overflowed else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .runtimeFault,
                    code: "tickOverflow",
                    message: "Simulation tick overflowed UInt64 capacity"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .simulationFaultReported,
                    detail: "tickOverflow"
                )
                stopSimulationRuntime(state: &state)
                return
            }

            let runtimeOutputs = state.networkRuntime.handle(.advance(toMilliseconds: nextTick))
            guard state.networkRuntime.state.currentTimeMilliseconds == nextTick else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .runtimeFault,
                    code: "runtimeClockAdvanceRejected",
                    message: "The deterministic network runtime rejected the requested clock advancement"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .simulationFaultReported,
                    detail: "runtimeClockAdvanceRejected"
                )
                return
            }

            state.simulationTick = state.networkRuntime.state.currentTimeMilliseconds
            for nodeID in state.runtimeEchoServerByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                _ = state.pumpEchoServer(nodeID: nodeID)
            }
            _ = state.processProtocolApplicationServers()
            _ = state.processRuntimeEmailServers()
            for nodeID in state.runtimeWebServerByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                _ = state.processWebServerRequests(nodeID: nodeID)
            }
            projectDHCPRuntimeState(state: &state)
            if state.openedRuntimeDeviceID == nil {
                state.lastRuntimeFault = nil
                let firedEventCount = runtimeOutputs.reduce(into: 0) { count, output in
                    if case .fired = output.kind {
                        count += 1
                    }
                }
                recordRuntimeEvent(
                    state: &state,
                    code: .simulationTickAdvanced,
                    detail: "step=\(step),timeMilliseconds=\(state.simulationTick),firedEvents=\(firedEventCount)"
                )
            }

        case let .simulationFault(code, message):
            guard let normalizedCode = normalizedRuntimeValue(code) else {
                setMalformedRuntimePayload(
                    state: &state,
                    reason: "simulationFault requires a non-empty code"
                )
                return
            }

            state.lastRuntimeFault = TopologyRuntimeFault(
                category: .runtimeFault,
                code: normalizedCode,
                message: normalizedRuntimeValue(message) ?? "unspecified"
            )
            recordRuntimeEvent(
                state: &state,
                code: .simulationFaultReported,
                detail: normalizedCode
            )

        case let .openRuntimeDevice(nodeID):
            guard let nodeID else {
                setMalformedRuntimePayload(
                    state: &state,
                    reason: "openRuntimeDevice requires nodeID"
                )
                return
            }

            guard state.graph.containsNode(id: nodeID) else {
                state.lastValidationError = .nodeNotFound
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkRouting,
                    code: "runtimeDeviceNotFound",
                    message: "Cannot open runtime panel for unknown node \(nodeID.uuidString)"
                )
                recordRuntimeEvent(state: &state, code: .simulationFaultReported, detail: "runtimeDeviceNotFound")
                return
            }

            let previousOpenedNodeID = state.openedRuntimeDeviceID
            state.openedRuntimeDeviceID = nodeID

            if let previousOpenedNodeID, previousOpenedNodeID != nodeID {
                state.runtimeActiveProgramByNodeID.removeValue(forKey: previousOpenedNodeID)
                state.runtimeActiveProtocolApplicationIDByNodeID.removeValue(forKey: previousOpenedNodeID)
            }

            if let activeProgram = state.runtimeActiveProgramByNodeID[nodeID],
               !(state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(activeProgram) ?? false) {
                state.runtimeActiveProgramByNodeID.removeValue(forKey: nodeID)
            }
            if let activeDefinitionID = state.runtimeActiveProtocolApplicationIDByNodeID[nodeID],
               (!(state.runtimeInstalledProtocolApplicationIDsByNodeID[nodeID]?.contains(activeDefinitionID) ?? false)
                || state.protocolApplicationDefinitionsByID[activeDefinitionID] == nil) {
                state.runtimeActiveProtocolApplicationIDByNodeID.removeValue(forKey: nodeID)
            }

            state.lastRuntimeFault = nil
            recordRuntimeEvent(state: &state, code: .runtimeDeviceOpened, detail: nodeID.uuidString)

        case .closeRuntimeDevice:
            guard let previousNodeID = state.openedRuntimeDeviceID else {
                recordRuntimeEvent(state: &state, code: .runtimeDeviceCloseIgnoredAlreadyClosed)
                return
            }

            state.openedRuntimeDeviceID = nil
            state.runtimeActiveProgramByNodeID.removeValue(forKey: previousNodeID)
            state.runtimeActiveProtocolApplicationIDByNodeID.removeValue(forKey: previousNodeID)
            recordRuntimeEvent(state: &state, code: .runtimeDeviceClosed, detail: previousNodeID.uuidString)

        case let .saveRuntimeDeviceIP(nodeID, ipAddress, subnetMask):
            let retainedDefaultGateway = nodeID
                .flatMap { state.runtimeDeviceConfigurations[$0]?.defaultGateway } ?? ""
            saveRuntimeDeviceConfiguration(
                state: &state,
                nodeID: nodeID,
                ipAddress: ipAddress,
                subnetMask: subnetMask,
                defaultGateway: retainedDefaultGateway,
                actionName: "saveRuntimeDeviceIP"
            )

        case let .saveRuntimeDeviceConfiguration(nodeID, ipAddress, subnetMask, defaultGateway):
            saveRuntimeDeviceConfiguration(
                state: &state,
                nodeID: nodeID,
                ipAddress: ipAddress,
                subnetMask: subnetMask,
                defaultGateway: defaultGateway,
                actionName: "saveRuntimeDeviceConfiguration"
            )

        case let .saveRuntimeInterfaceConfiguration(nodeID, portID, ipAddress, subnetMask):
            guard let nodeID, let portID else {
                setMalformedRuntimePayload(
                    state: &state,
                    reason: "saveRuntimeInterfaceConfiguration requires nodeID and portID"
                )
                return
            }

            guard let node = state.graph.node(withID: nodeID) else {
                state.lastValidationError = .nodeNotFound
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "runtimeDeviceNotFound",
                    message: "Cannot save interface configuration for unknown node \(nodeID.uuidString)"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeInterfaceConfigurationRejectedInvalidConfiguration,
                    detail: "runtimeDeviceNotFound"
                )
                return
            }

            guard node.kind == .router || node.kind == .gateway else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "interfaceConfigurationUnsupportedForNodeKind",
                    message: "Per-interface configuration is currently supported for routers and gateways"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeInterfaceConfigurationRejectedInvalidConfiguration,
                    detail: "interfaceConfigurationUnsupportedForNodeKind"
                )
                return
            }

            guard node.ports.contains(where: { $0.id == portID }) else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "runtimeInterfaceNotFound",
                    message: "Cannot save configuration for unknown interface \(portID.uuidString)"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeInterfaceConfigurationRejectedInvalidConfiguration,
                    detail: "runtimeInterfaceNotFound"
                )
                return
            }

            guard let normalizedIPAddress = normalizedIPv4Address(ipAddress) else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "invalidIPAddress",
                    message: "IP address must be a valid IPv4 address"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeInterfaceConfigurationRejectedInvalidConfiguration,
                    detail: "invalidIPAddress"
                )
                return
            }

            guard let normalizedSubnetMask = normalizedSubnetMask(subnetMask) else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "invalidSubnetMask",
                    message: "Subnet mask must be a contiguous IPv4 mask"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeInterfaceConfigurationRejectedInvalidConfiguration,
                    detail: "invalidSubnetMask"
                )
                return
            }

            let key = TopologyRuntimeInterfaceKey(nodeID: nodeID, portID: portID)
            state.runtimeInterfaceConfigurations[key] = TopologyRuntimeInterfaceConfiguration(
                ipAddress: normalizedIPAddress,
                subnetMask: normalizedSubnetMask
            )
            state.lastRuntimeFault = nil
            advancePersistenceRevision(state: &state)
            recordRuntimeEvent(
                state: &state,
                code: .runtimeInterfaceConfigurationSaved,
                detail: "node=\(nodeID.uuidString),port=\(portID.uuidString),ip=\(normalizedIPAddress),subnet=\(normalizedSubnetMask)"
            )

        case let .saveRuntimeManualRoutes(nodeID, routes):
            guard let nodeID, let routes else {
                setMalformedRuntimePayload(
                    state: &state,
                    reason: "saveRuntimeManualRoutes requires nodeID and routes"
                )
                return
            }

            guard let node = state.graph.node(withID: nodeID) else {
                state.lastValidationError = .nodeNotFound
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "runtimeDeviceNotFound",
                    message: "Cannot save routing table for unknown node \(nodeID.uuidString)"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeManualRoutesRejectedInvalidConfiguration,
                    detail: "runtimeDeviceNotFound"
                )
                return
            }

            guard node.kind == .router else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "manualRoutesUnsupportedForNodeKind",
                    message: "Manual routing-table configuration is supported only for routers"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeManualRoutesRejectedInvalidConfiguration,
                    detail: "manualRoutesUnsupportedForNodeKind"
                )
                return
            }

            for route in routes {
                let fields: [(TopologyJavaRouteTableColumn, String)] = [
                    (.destination, route.destinationNetwork),
                    (.subnetMask, route.subnetMask),
                    (.nextGateway, route.gateway),
                    (.interface, route.interfaceIPAddress),
                ]
                guard fields.allSatisfy({ TopologyJavaRouteTable.isValid($0.1, for: $0.0) }) else {
                    state.lastRuntimeFault = TopologyRuntimeFault(
                        category: .networkConfiguration,
                        code: "invalidManualRoute",
                        message: "Every manual route cell must match the FILIUS IPv4 route-table syntax"
                    )
                    recordRuntimeEvent(
                        state: &state,
                        code: .runtimeManualRoutesRejectedInvalidConfiguration,
                        detail: "invalidManualRoute"
                    )
                    return
                }
            }

            if routes.isEmpty {
                state.runtimeManualRoutesByNodeID.removeValue(forKey: nodeID)
            } else {
                state.runtimeManualRoutesByNodeID[nodeID] = routes
            }
            state.lastRuntimeFault = nil
            advancePersistenceRevision(state: &state)
            recordRuntimeEvent(
                state: &state,
                code: .runtimeManualRoutesSaved,
                detail: "node=\(nodeID.uuidString),count=\(routes.count)"
            )

        case let .setRuntimeRIPEnabled(nodeID, enabled):
            guard let nodeID, let enabled else {
                setMalformedRuntimePayload(
                    state: &state,
                    reason: "setRuntimeRIPEnabled requires nodeID and enabled"
                )
                return
            }
            guard let node = state.graph.node(withID: nodeID), node.kind == .router else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "ripUnsupportedForNodeKind",
                    message: "RIP is supported only by Router nodes"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeRIPConfigurationRejected,
                    detail: "ripUnsupportedForNodeKind"
                )
                return
            }
            if enabled {
                state.runtimeRIPEnabledByNodeID[nodeID] = true
            } else {
                state.runtimeRIPEnabledByNodeID.removeValue(forKey: nodeID)
            }
            if state.simulationPhase == .running {
                state.networkRuntime.setRIPEnabled(nodeID: nodeID, enabled: enabled)
            }
            state.lastRuntimeFault = nil
            advancePersistenceRevision(state: &state)
            recordRuntimeEvent(
                state: &state,
                code: .runtimeRIPConfigurationSaved,
                detail: "node=\(nodeID.uuidString),enabled=\(enabled)"
            )
        case let .setRuntimeDHCPClientEnabled(nodeID, enabled):
            guard let nodeID, let enabled else {
                setMalformedRuntimePayload(
                    state: &state,
                    reason: "setRuntimeDHCPClientEnabled requires nodeID and enabled"
                )
                return
            }
            guard let node = state.graph.node(withID: nodeID), node.kind.isPCClassEndpoint || node.kind == .gateway else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "dhcpClientUnsupportedForNodeKind",
                    message: "DHCP client configuration is supported only by Host, Notebook, and Gateway nodes"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeDHCPClientConfigurationRejected,
                    detail: "dhcpClientUnsupportedForNodeKind"
                )
                return
            }
            if enabled {
                state.runtimeDHCPClientConfigurationsByNodeID[nodeID] = TopologyDHCPClientConfiguration(isEnabled: true)
            } else {
                state.runtimeDHCPClientConfigurationsByNodeID.removeValue(forKey: nodeID)
            }
            state.lastRuntimeFault = nil
            advancePersistenceRevision(state: &state)
            recordRuntimeEvent(
                state: &state,
                code: .runtimeDHCPClientConfigurationSaved,
                detail: "nodeID=\(nodeID.uuidString),enabled=\(enabled)"
            )

        case let .saveRuntimeDHCPServerConfiguration(nodeID, configuration):
            guard let nodeID, let configuration else {
                setMalformedRuntimePayload(
                    state: &state,
                    reason: "saveRuntimeDHCPServerConfiguration requires nodeID and configuration"
                )
                return
            }
            guard let node = state.graph.node(withID: nodeID), node.kind.isPCClassEndpoint || node.kind == .gateway else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "dhcpServerUnsupportedForNodeKind",
                    message: "DHCP server configuration is supported only by Host, Notebook, and Gateway nodes"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeDHCPServerConfigurationRejected,
                    detail: "dhcpServerUnsupportedForNodeKind"
                )
                return
            }
            let old = state.runtimeDHCPServerConfigurationsByNodeID[nodeID] ?? TopologyDHCPServerConfiguration()
            let lower = normalizedIPv4Address(configuration.lowerBoundIPAddress) ?? old.lowerBoundIPAddress
            let upper = normalizedIPv4Address(configuration.upperBoundIPAddress) ?? old.upperBoundIPAddress
            let gateway = node.kind == .gateway || !configuration.useOwnSettings
                ? old.gatewayIPAddress
                : normalizedIPv4Address(configuration.gatewayIPAddress) ?? old.gatewayIPAddress
            let dns: String
            if node.kind == .gateway || configuration.useOwnSettings {
                dns = normalizedIPv4Address(configuration.dnsServerIPAddress) ?? old.dnsServerIPAddress
            } else {
                dns = old.dnsServerIPAddress
            }
            var seenMACAddresses: Set<String> = []
            let staticAssignments = configuration.staticAssignments.compactMap { assignment -> TopologyDHCPStaticAssignment? in
                guard let macAddress = normalizedMACAddress(assignment.macAddress),
                      let ipAddress = normalizedIPv4Address(assignment.ipAddress),
                      seenMACAddresses.insert(macAddress.lowercased()).inserted else { return nil }
                return TopologyDHCPStaticAssignment(id: assignment.id, macAddress: macAddress, ipAddress: ipAddress)
            }
            state.runtimeDHCPServerConfigurationsByNodeID[nodeID] = TopologyDHCPServerConfiguration(
                isActive: configuration.isActive,
                lowerBoundIPAddress: lower,
                upperBoundIPAddress: upper,
                gatewayIPAddress: gateway,
                dnsServerIPAddress: dns,
                useOwnSettings: node.kind == .gateway ? false : configuration.useOwnSettings,
                staticAssignments: staticAssignments
            )
            state.lastRuntimeFault = nil
            advancePersistenceRevision(state: &state)
            recordRuntimeEvent(
                state: &state,
                code: .runtimeDHCPServerConfigurationSaved,
                detail: "nodeID=\(nodeID.uuidString),staticAssignments=\(staticAssignments.count)"
            )

        case let .saveRuntimeFirewallConfiguration(nodeID, configuration):
            guard let nodeID, let configuration else {
                setMalformedRuntimePayload(
                    state: &state,
                    reason: "saveRuntimeFirewallConfiguration requires nodeID and configuration"
                )
                return
            }
            guard let node = state.graph.node(withID: nodeID) else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "firewallUnsupportedForNodeKind",
                    message: "Firewall configuration requires an existing supported node"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeFirewallConfigurationRejected,
                    detail: "firewallUnsupportedForNodeKind"
                )
                return
            }
            let isInfrastructureFirewall = node.kind == .router || node.kind == .gateway
            let isInstalledPersonalFirewall = node.kind.isPCClassEndpoint
                && state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(.firewall) == true
            guard isInfrastructureFirewall || isInstalledPersonalFirewall else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "firewallUnsupportedForNodeKind",
                    message: "Personal Firewall configuration requires the installed Firewall application on a PC or Notebook"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeFirewallConfigurationRejected,
                    detail: "firewallUnsupportedForNodeKind"
                )
                return
            }
            guard let normalizedRules = normalizedFirewallRules(configuration.rules) else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "invalidFirewallRule",
                    message: "Firewall rules must use valid optional IPv4 networks, masks, and ports"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeFirewallConfigurationRejected,
                    detail: "invalidFirewallRule"
                )
                return
            }
            let normalizedConfiguration = TopologyFirewallConfiguration(
                isActive: configuration.isActive,
                defaultPolicy: configuration.defaultPolicy,
                dropICMP: configuration.dropICMP,
                filterSYNSegmentsOnly: configuration.filterSYNSegmentsOnly,
                filterUDP: configuration.filterUDP,
                rules: normalizedRules
            )
            state.runtimeFirewallConfigurationsByNodeID[nodeID] = normalizedConfiguration
            if state.simulationPhase == .running {
                state.networkRuntime.setFirewallConfiguration(nodeID: nodeID, configuration: normalizedConfiguration)
            }
            state.lastRuntimeFault = nil
            advancePersistenceRevision(state: &state)
            recordRuntimeEvent(
                state: &state,
                code: .runtimeFirewallConfigurationSaved,
                detail: "nodeID=\(nodeID.uuidString),rules=\(normalizedRules.count)"
            )

        case let .resetRuntimeNATTable(nodeID):
            guard let nodeID else {
                setMalformedRuntimePayload(
                    state: &state,
                    reason: "resetRuntimeNATTable requires nodeID"
                )
                return
            }
            guard let node = state.graph.node(withID: nodeID), node.kind == .gateway else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "natUnsupportedForNodeKind",
                    message: "NAT is supported only by Gateway nodes"
                )
                return
            }
            state.networkRuntime.clearDynamicNATMappings(gatewayNodeID: nodeID)
            state.lastRuntimeFault = nil
            recordRuntimeEvent(
                state: &state,
                code: .runtimeNATTableReset,
                detail: "nodeID=\(nodeID.uuidString)"
            )

        case let .clearRuntimeSwitchSAT(nodeID):
            guard let nodeID else {
                setMalformedRuntimePayload(state: &state, reason: "clearRuntimeSwitchSAT requires nodeID")
                return
            }
            guard let node = state.graph.node(withID: nodeID), node.kind == .networkSwitch else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "switchSATUnsupportedForNodeKind",
                    message: "The Source Address Table is available only on Switch nodes"
                )
                return
            }
            state.networkRuntime.clearSwitchSAT(nodeID: nodeID)
            state.lastRuntimeFault = nil
            recordRuntimeEvent(
                state: &state,
                code: .runtimeSwitchSATCleared,
                detail: "nodeID=\(nodeID.uuidString)"
            )

        case let .resetRuntimePacketCapture(nodeID, interfaceID):
            state.networkRuntime.clearPacketCapture(nodeID: nodeID, interfaceID: interfaceID)

        case let .saveRuntimePortForwardingRows(nodeID, rows):
            guard let nodeID, let rows else {
                setMalformedRuntimePayload(
                    state: &state,
                    reason: "saveRuntimePortForwardingRows requires nodeID and rows"
                )
                return
            }
            guard let node = state.graph.node(withID: nodeID), node.kind == .gateway else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "portForwardingUnsupportedForNodeKind",
                    message: "Port forwarding is supported only by Gateway nodes"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimePortForwardingConfigurationRejected,
                    detail: "portForwardingUnsupportedForNodeKind"
                )
                return
            }
            if rows.isEmpty {
                state.runtimePortForwardingRowsByNodeID.removeValue(forKey: nodeID)
            } else {
                state.runtimePortForwardingRowsByNodeID[nodeID] = rows
            }
            if state.simulationPhase == .running {
                state.networkRuntime.setStaticPortForwardingRows(gatewayNodeID: nodeID, rows: rows)
            }
            state.lastRuntimeFault = nil
            advancePersistenceRevision(state: &state)
            recordRuntimeEvent(
                state: &state,
                code: .runtimePortForwardingConfigurationSaved,
                detail: "nodeID=\(nodeID.uuidString),rows=\(rows.count),active=\(rows.filter(\.isRuntimeValid).count)"
            )
        case let .installRuntimeProgram(nodeID, program):
            guard let nodeID else {
                setMalformedRuntimePayload(
                    state: &state,
                    reason: "installRuntimeProgram requires nodeID"
                )
                return
            }

            guard let program else {
                setMalformedRuntimePayload(
                    state: &state,
                    reason: "installRuntimeProgram requires program"
                )
                return
            }

            guard let node = state.graph.node(withID: nodeID) else {
                state.lastValidationError = .nodeNotFound
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "runtimeDeviceNotFound",
                    message: "Cannot install runtime program for unknown node \(nodeID.uuidString)"
                )
                recordRuntimeEvent(state: &state, code: .simulationFaultReported, detail: "runtimeDeviceNotFound")
                return
            }

            guard node.kind.isPCClassEndpoint else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .commandValidation,
                    code: "programInstallationUnsupportedForNodeKind",
                    message: "Only PCs and Notebooks support desktop program installation"
                )
                recordRuntimeEvent(state: &state, code: .simulationFaultReported, detail: "programInstallationUnsupportedForNodeKind")
                return
            }

            let previousInstalledPrograms = state.runtimeInstalledProgramsByNodeID[nodeID]
            let previousGnutellaConfiguration = state.runtimeGnutellaConfigurationsByNodeID[nodeID]
            let previousFileSystem = state.virtualFileSystemsByNodeID[nodeID]
            var installedPrograms = previousInstalledPrograms ?? Set<TopologyRuntimeInstallableProgram>()
            installedPrograms.insert(program)
            state.runtimeInstalledProgramsByNodeID[nodeID] = installedPrograms
            if program == .webServer {
                state.runtimeWebServerConfigurationsByNodeID[nodeID] = state.runtimeWebServerConfigurationsByNodeID[nodeID] ?? TopologyRuntimeWebServerConfiguration()
                var fileSystem = state.virtualFileSystemsByNodeID[nodeID] ?? .defaultForDevice()
                if !fileSystem.contains(TopologyRuntimeWebServerConfiguration.defaultDocumentRoot) {
                    try? fileSystem.createDirectory(at: TopologyRuntimeWebServerConfiguration.defaultDocumentRoot, recursive: true)
                }
                if !fileSystem.contains("/www/index.html") {
                    try? fileSystem.writeTextFile(
                        at: "/www/index.html",
                        text: "<html><head><title>FILIUS Web Server</title></head><body><h1>FILIUS Web Server</h1><p>Deterministic simulated HTTP content.</p></body></html>"
                    )
                }
                state.virtualFileSystemsByNodeID[nodeID] = fileSystem
            }
            if program == .webBrowser {
                state.runtimeWebBrowserConfigurationsByNodeID[nodeID] = state.runtimeWebBrowserConfigurationsByNodeID[nodeID] ?? TopologyRuntimeWebBrowserConfiguration()
            }
            if program == .firewall {
                let configuration = state.runtimeFirewallConfigurationsByNodeID[nodeID]
                    ?? TopologyFirewallConfiguration.javaPersonalDefaults
                state.runtimeFirewallConfigurationsByNodeID[nodeID] = configuration
                if state.simulationPhase == .running {
                    state.networkRuntime.setFirewallConfiguration(nodeID: nodeID, configuration: configuration)
                }
            }
            if program == .emailClient {
                state.runtimeEmailClientConfigurationsByNodeID[nodeID] = state.runtimeEmailClientConfigurationsByNodeID[nodeID]
                    ?? TopologyRuntimeEmailClientConfiguration()
                state.runtimeEmailClientStateByNodeID[nodeID] = state.runtimeEmailClientStateByNodeID[nodeID]
                    ?? TopologyRuntimeEmailClientState()
                try? state.persistRuntimeEmailClientConfiguration(nodeID: nodeID)
            }
            if program == .emailServer {
                state.runtimeEmailServerConfigurationsByNodeID[nodeID] = state.runtimeEmailServerConfigurationsByNodeID[nodeID]
                    ?? TopologyRuntimeEmailServerConfiguration()
                state.runtimeEmailServerProcessesByNodeID[nodeID] = state.runtimeEmailServerProcessesByNodeID[nodeID]
                    ?? TopologyRuntimeEmailServerProcessState()
                try? state.persistRuntimeEmailServerConfiguration(nodeID: nodeID)
            }
            if program == .gnutella {
                state.runtimeGnutellaConfigurationsByNodeID[nodeID] = previousGnutellaConfiguration
                    ?? TopologyRuntimeGnutellaConfiguration()
                do {
                    try state.persistRuntimeGnutellaConfiguration(nodeID: nodeID)
                } catch {
                    if let previousInstalledPrograms {
                        state.runtimeInstalledProgramsByNodeID[nodeID] = previousInstalledPrograms
                    } else {
                        state.runtimeInstalledProgramsByNodeID.removeValue(forKey: nodeID)
                    }
                    if let previousGnutellaConfiguration {
                        state.runtimeGnutellaConfigurationsByNodeID[nodeID] = previousGnutellaConfiguration
                    } else {
                        state.runtimeGnutellaConfigurationsByNodeID.removeValue(forKey: nodeID)
                    }
                    if let previousFileSystem {
                        state.virtualFileSystemsByNodeID[nodeID] = previousFileSystem
                    } else {
                        state.virtualFileSystemsByNodeID.removeValue(forKey: nodeID)
                    }
                    setGnutellaFailure(
                        state: &state,
                        nodeID: nodeID,
                        faultCode: "gnutellaInstallationRejected",
                        error: error
                    )
                    return
                }
            }
            state.lastRuntimeFault = nil
            advancePersistenceRevision(state: &state)
            recordRuntimeEvent(
                state: &state,
                code: .runtimeProgramInstalled,
                detail: "node=\(nodeID.uuidString),program=\(program.rawValue)"
            )
            appendConsoleLine(
                state: &state,
                nodeID: nodeID,
                line: "Program installed: \(program.rawValue)"
            )

        case let .uninstallRuntimeProgram(nodeID, program):
            guard let nodeID, let program else {
                setMalformedRuntimePayload(
                    state: &state,
                    reason: "uninstallRuntimeProgram requires nodeID and program"
                )
                return
            }
            guard state.graph.node(withID: nodeID)?.kind.isPCClassEndpoint == true else {
                state.lastValidationError = state.graph.containsNode(id: nodeID) ? nil : .nodeNotFound
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .commandValidation,
                    code: "programUninstallationUnsupported",
                    message: "The selected node does not support software management"
                )
                recordRuntimeEvent(state: &state, code: .simulationFaultReported, detail: "programUninstallationUnsupported")
                return
            }
            guard state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(program) == true else {
                state.lastRuntimeFault = nil
                return
            }

            cleanupRuntimeProgram(program, nodeID: nodeID, state: &state)
            var installedPrograms = state.runtimeInstalledProgramsByNodeID[nodeID] ?? []
            installedPrograms.remove(program)
            if installedPrograms.isEmpty {
                state.runtimeInstalledProgramsByNodeID.removeValue(forKey: nodeID)
            } else {
                state.runtimeInstalledProgramsByNodeID[nodeID] = installedPrograms
            }
            state.lastRuntimeFault = nil
            advancePersistenceRevision(state: &state)
            recordRuntimeEvent(
                state: &state,
                code: .runtimeProgramUninstalled,
                detail: "node=\(nodeID.uuidString),program=\(program.rawValue),data=preserved"
            )
            appendConsoleLine(
                state: &state,
                nodeID: nodeID,
                line: "Program uninstalled: \(program.rawValue) (application data preserved)"
            )

        case let .launchRuntimeProgram(nodeID, program):
            guard let nodeID else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .malformedRuntimePayload,
                    code: "runtimeProgramLaunchMalformedPayload",
                    message: "launchRuntimeProgram requires nodeID"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeProgramLaunchRejectedMalformedPayload,
                    detail: "missingNodeID"
                )
                return
            }

            guard let program else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .malformedRuntimePayload,
                    code: "runtimeProgramLaunchMalformedPayload",
                    message: "launchRuntimeProgram requires program"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeProgramLaunchRejectedMalformedPayload,
                    detail: "missingProgram"
                )
                return
            }

            guard let node = state.graph.node(withID: nodeID) else {
                state.lastValidationError = .nodeNotFound
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "runtimeDeviceNotFound",
                    message: "Cannot launch runtime program for unknown node \(nodeID.uuidString)"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeProgramLaunchRejectedUnknownNode,
                    detail: "runtimeDeviceNotFound"
                )
                return
            }

            guard node.kind.isPCClassEndpoint else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .commandValidation,
                    code: "runtimeProgramUnsupportedForNodeKind",
                    message: "Only PCs and Notebooks support runtime program launch"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeProgramLaunchRejectedUnsupportedNodeKind,
                    detail: "runtimeProgramUnsupportedForNodeKind"
                )
                return
            }

            guard state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(program) == true else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .commandValidation,
                    code: "runtimeProgramNotInstalled",
                    message: "Program \(program.rawValue) is not installed on node \(nodeID.uuidString)"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeProgramLaunchRejectedNotInstalled,
                    detail: "program=\(program.rawValue)"
                )
                return
            }

            state.runtimeActiveProtocolApplicationIDByNodeID.removeValue(forKey: nodeID)
            if state.runtimeActiveProgramByNodeID[nodeID] == program {
                if program == .gnutella,
                   state.runtimeGnutellaSessionsByNodeID[nodeID]?.isRunning != true {
                    switch state.startRuntimeGnutella(nodeID: nodeID) {
                    case .success:
                        recordRuntimeEvent(state: &state, code: .gnutellaStarted, detail: "node=\(nodeID.uuidString),port=6346")
                    case let .failure(error):
                        state.runtimeActiveProgramByNodeID.removeValue(forKey: nodeID)
                        setGnutellaFailure(state: &state, nodeID: nodeID, faultCode: "gnutellaStartRejected", error: error)
                        return
                    }
                } else {
                    state.lastRuntimeFault = nil
                }
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeProgramFocusedAlreadyActive,
                    detail: "node=\(nodeID.uuidString),program=\(program.rawValue)"
                )
                return
            }

            let previouslyActiveProgram = state.runtimeActiveProgramByNodeID[nodeID]
            state.runtimeActiveProgramByNodeID[nodeID] = program
            seedDesktopSuiteProgramDefaults(state: &state, nodeID: nodeID, program: program)
            if program == .gnutella {
                switch state.startRuntimeGnutella(nodeID: nodeID) {
                case .success:
                    recordRuntimeEvent(state: &state, code: .gnutellaStarted, detail: "node=\(nodeID.uuidString),port=6346")
                case let .failure(error):
                    if let previouslyActiveProgram {
                        state.runtimeActiveProgramByNodeID[nodeID] = previouslyActiveProgram
                    } else {
                        state.runtimeActiveProgramByNodeID.removeValue(forKey: nodeID)
                    }
                    setGnutellaFailure(state: &state, nodeID: nodeID, faultCode: "gnutellaStartRejected", error: error)
                    return
                }
            }
            recordRuntimeCompatibilityOperation(
                state: &state,
                nodeID: nodeID,
                kind: .applicationOperation,
                detail: "launch:\(program.rawValue)"
            )
            state.lastRuntimeFault = nil
            recordRuntimeEvent(
                state: &state,
                code: .runtimeProgramLaunched,
                detail: "node=\(nodeID.uuidString),program=\(program.rawValue)"
            )

        case let .closeRuntimeProgram(nodeID):
            guard let nodeID else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .malformedRuntimePayload,
                    code: "runtimeProgramCloseMalformedPayload",
                    message: "closeRuntimeProgram requires nodeID"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeProgramCloseRejectedMalformedPayload,
                    detail: "missingNodeID"
                )
                return
            }

            guard state.graph.containsNode(id: nodeID) else {
                state.lastValidationError = .nodeNotFound
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "runtimeDeviceNotFound",
                    message: "Cannot close runtime program for unknown node \(nodeID.uuidString)"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeProgramCloseRejectedUnknownNode,
                    detail: "runtimeDeviceNotFound"
                )
                return
            }

            guard let activeProgram = state.runtimeActiveProgramByNodeID.removeValue(forKey: nodeID) else {
                state.lastRuntimeFault = nil
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeProgramCloseIgnoredAlreadyDesktop,
                    detail: "node=\(nodeID.uuidString)"
                )
                return
            }

            recordRuntimeCompatibilityOperation(
                state: &state,
                nodeID: nodeID,
                kind: .applicationOperation,
                detail: "close:\(activeProgram.rawValue)"
            )
            state.lastRuntimeFault = nil
            recordRuntimeEvent(
                state: &state,
                code: .runtimeProgramClosed,
                detail: "node=\(nodeID.uuidString),program=\(activeProgram.rawValue)"
            )

        case let .createProtocolApplication(definition):
            guard state.simulationPhase == .stopped, let definition else {
                rejectProtocolApplication(state: &state, code: "protocolDefinitionCreateRejected")
                return
            }
            guard state.protocolApplicationDefinitionsByID[definition.id] == nil else {
                rejectProtocolApplication(state: &state, code: "protocolDefinitionDuplicateID")
                return
            }
            var definitions = Array(state.protocolApplicationDefinitionsByID.values)
            definitions.append(definition)
            do {
                try TopologyProtocolApplicationCatalog.validateDefinitions(definitions)
            } catch {
                rejectProtocolApplication(state: &state, code: "protocolDefinitionInvalid", detail: String(describing: error))
                return
            }
            state.protocolApplicationDefinitionsByID[definition.id] = definition
            advancePersistenceRevision(state: &state)
            state.lastRuntimeFault = nil
            recordRuntimeEvent(state: &state, code: .protocolApplicationDefinitionCreated, detail: "definition=\(definition.id.uuidString)")

        case let .updateProtocolApplication(definition):
            guard state.simulationPhase == .stopped, let definition,
                  state.protocolApplicationDefinitionsByID[definition.id] != nil else {
                rejectProtocolApplication(state: &state, code: "protocolDefinitionUpdateRejected")
                return
            }
            var definitions = state.protocolApplicationDefinitionsByID
            definitions[definition.id] = definition
            do {
                try TopologyProtocolApplicationCatalog.validateDefinitions(Array(definitions.values))
            } catch {
                rejectProtocolApplication(state: &state, code: "protocolDefinitionInvalid", detail: String(describing: error))
                return
            }
            state.protocolApplicationDefinitionsByID = definitions
            advancePersistenceRevision(state: &state)
            state.lastRuntimeFault = nil
            recordRuntimeEvent(state: &state, code: .protocolApplicationDefinitionUpdated, detail: "definition=\(definition.id.uuidString)")

        case let .deleteProtocolApplication(definitionID):
            guard state.simulationPhase == .stopped, let definitionID,
                  state.protocolApplicationDefinitionsByID[definitionID] != nil else {
                rejectProtocolApplication(state: &state, code: "protocolDefinitionDeleteRejected")
                return
            }
            state.stopProtocolApplicationRuntime(definitionID: definitionID)
            state.protocolApplicationDefinitionsByID.removeValue(forKey: definitionID)
            for nodeID in Array(state.runtimeInstalledProtocolApplicationIDsByNodeID.keys) {
                state.runtimeInstalledProtocolApplicationIDsByNodeID[nodeID]?.remove(definitionID)
                if state.runtimeInstalledProtocolApplicationIDsByNodeID[nodeID]?.isEmpty == true {
                    state.runtimeInstalledProtocolApplicationIDsByNodeID.removeValue(forKey: nodeID)
                }
                if state.runtimeActiveProtocolApplicationIDByNodeID[nodeID] == definitionID {
                    state.runtimeActiveProtocolApplicationIDByNodeID.removeValue(forKey: nodeID)
                }
            }
            advancePersistenceRevision(state: &state)
            state.lastRuntimeFault = nil
            recordRuntimeEvent(state: &state, code: .protocolApplicationDefinitionDeleted, detail: "definition=\(definitionID.uuidString)")

        case let .installProtocolApplication(nodeID, definitionID):
            guard let nodeID, let definitionID,
                  let node = state.graph.node(withID: nodeID), node.kind.isPCClassEndpoint,
                  state.protocolApplicationDefinitionsByID[definitionID] != nil else {
                rejectProtocolApplication(state: &state, code: "protocolInstallationRejected")
                return
            }
            let inserted = state.runtimeInstalledProtocolApplicationIDsByNodeID[nodeID, default: []].insert(definitionID).inserted
            if inserted { advancePersistenceRevision(state: &state) }
            state.lastRuntimeFault = nil
            recordRuntimeEvent(state: &state, code: .protocolApplicationInstalled, detail: "node=\(nodeID.uuidString),definition=\(definitionID.uuidString)")

        case let .uninstallProtocolApplication(nodeID, definitionID):
            guard let nodeID, let definitionID,
                  state.runtimeInstalledProtocolApplicationIDsByNodeID[nodeID]?.contains(definitionID) == true else {
                rejectProtocolApplication(state: &state, code: "protocolUninstallRejected")
                return
            }
            state.stopProtocolApplicationServer(nodeID: nodeID, definitionID: definitionID)
            state.runtimeInstalledProtocolApplicationIDsByNodeID[nodeID]?.remove(definitionID)
            if state.runtimeInstalledProtocolApplicationIDsByNodeID[nodeID]?.isEmpty == true {
                state.runtimeInstalledProtocolApplicationIDsByNodeID.removeValue(forKey: nodeID)
            }
            if state.runtimeActiveProtocolApplicationIDByNodeID[nodeID] == definitionID {
                state.runtimeActiveProtocolApplicationIDByNodeID.removeValue(forKey: nodeID)
            }
            state.stopProtocolApplicationClient(nodeID: nodeID, definitionID: definitionID)
            advancePersistenceRevision(state: &state)
            state.lastRuntimeFault = nil
            recordRuntimeEvent(state: &state, code: .protocolApplicationUninstalled, detail: "node=\(nodeID.uuidString),definition=\(definitionID.uuidString)")

        case let .launchProtocolApplication(nodeID, definitionID):
            guard let nodeID, let definitionID,
                  state.simulationPhase == .running,
                  state.graph.node(withID: nodeID)?.kind.isPCClassEndpoint == true,
                  state.runtimeInstalledProtocolApplicationIDsByNodeID[nodeID]?.contains(definitionID) == true,
                  state.protocolApplicationDefinitionsByID[definitionID] != nil else {
                rejectProtocolApplication(state: &state, code: "protocolLaunchRejected")
                return
            }
            state.runtimeActiveProgramByNodeID.removeValue(forKey: nodeID)
            state.runtimeActiveProtocolApplicationIDByNodeID[nodeID] = definitionID
            state.lastRuntimeFault = nil
            recordRuntimeEvent(state: &state, code: .protocolApplicationLaunched, detail: "node=\(nodeID.uuidString),definition=\(definitionID.uuidString)")

        case let .closeProtocolApplication(nodeID):
            guard let nodeID else {
                rejectProtocolApplication(state: &state, code: "protocolCloseRejected")
                return
            }
            state.runtimeActiveProtocolApplicationIDByNodeID.removeValue(forKey: nodeID)
            state.lastRuntimeFault = nil
            recordRuntimeEvent(state: &state, code: .protocolApplicationClosed, detail: "node=\(nodeID.uuidString)")

        case let .runtimeProtocolServerStart(nodeID, definitionID):
            guard let context = validateProtocolApplicationContext(
                state: &state,
                nodeID: nodeID,
                definitionID: definitionID,
                expectedRole: .server,
                actionName: "runtimeProtocolServerStart"
            ) else { return }
            if let error = state.startProtocolApplicationServer(nodeID: context.nodeID, definitionID: context.definitionID) {
                rejectProtocolApplication(state: &state, code: "protocolServerStartRejected", detail: String(describing: error))
                return
            }
            state.lastRuntimeFault = nil
            recordRuntimeEvent(state: &state, code: .protocolApplicationServerStarted, detail: "node=\(context.nodeID.uuidString),definition=\(context.definitionID.uuidString)")

        case let .runtimeProtocolServerStop(nodeID, definitionID):
            guard let context = validateProtocolApplicationContext(
                state: &state,
                nodeID: nodeID,
                definitionID: definitionID,
                expectedRole: .server,
                actionName: "runtimeProtocolServerStop"
            ) else { return }
            let key = TopologyProtocolApplicationRuntimeKey(nodeID: context.nodeID, definitionID: context.definitionID)
            guard state.runtimeProtocolApplicationServers[key] != nil else {
                rejectProtocolApplication(state: &state, code: "protocolServerStopRejected", detail: "serverNotRunning")
                return
            }
            state.stopProtocolApplicationServer(nodeID: context.nodeID, definitionID: context.definitionID)
            state.lastRuntimeFault = nil
            recordRuntimeEvent(state: &state, code: .protocolApplicationServerStopped, detail: "node=\(context.nodeID.uuidString),definition=\(context.definitionID.uuidString)")

        case let .runtimeProtocolClientSend(nodeID, definitionID, destinationIPAddress, templateID):
            guard let destinationIPAddress, let templateID else {
                rejectProtocolApplication(state: &state, code: "protocolClientSendRejected")
                return
            }
            guard let context = validateProtocolApplicationContext(
                state: &state,
                nodeID: nodeID,
                definitionID: definitionID,
                expectedRole: .client,
                actionName: "runtimeProtocolClientSend"
            ) else { return }
            switch state.executeProtocolApplicationClientMessage(
                nodeID: context.nodeID,
                definitionID: context.definitionID,
                destinationIPAddress: destinationIPAddress,
                templateID: templateID
            ) {
            case let .success(result):
                state.lastRuntimeFault = nil
                recordRuntimeEvent(
                    state: &state,
                    code: .protocolApplicationClientCompleted,
                    detail: "node=\(context.nodeID.uuidString),definition=\(context.definitionID.uuidString),timeout=\(result.timedOut)"
                )
            case let .failure(error):
                rejectProtocolApplication(state: &state, code: "protocolClientSendRejected", detail: String(describing: error))
            }

        case let .runtimeFileExplorerSelectEntry(nodeID, entryID):
            guard let sourceNodeID = validateDesktopSuiteAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .fileExplorer,
                actionName: "runtimeFileExplorerSelectEntry"
            ) else { return }
            guard normalizedRuntimeValue(entryID) != nil else {
                setDesktopSuiteMalformedPayload(
                    state: &state,
                    actionName: "runtimeFileExplorerSelectEntry",
                    reason: "missingEntryID",
                    message: "File Explorer selection requires a non-empty absolute path"
                )
                return
            }
            guard let fileSystem = state.virtualFileSystemsByNodeID[sourceNodeID],
                  let path = resolveVirtualFilePath(entryID, in: fileSystem),
                  fileSystem.contains(path)
            else {
                setDesktopSuiteUnknownTarget(
                    state: &state,
                    actionName: "runtimeFileExplorerSelectEntry",
                    reason: "unknownFileEntry",
                    target: entryID ?? ""
                )
                return
            }
            state.runtimeFileExplorerSelectionByNodeID[sourceNodeID] = path
            state.lastRuntimeFault = nil
            recordRuntimeEvent(
                state: &state,
                code: .runtimeFileExplorerSelectionChanged,
                detail: "node=\(sourceNodeID.uuidString),entry=\(path)"
            )
            appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "File Explorer selected: \(path)")

        case let .runtimeImageViewerSelectImage(nodeID, imageID):
            guard let sourceNodeID = validateDesktopSuiteAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .imageViewer,
                actionName: "runtimeImageViewerSelectImage"
            ) else { return }
            guard normalizedRuntimeValue(imageID) != nil else {
                setDesktopSuiteMalformedPayload(
                    state: &state,
                    actionName: "runtimeImageViewerSelectImage",
                    reason: "missingImageID",
                    message: "Image Viewer selection requires a non-empty absolute path"
                )
                return
            }
            guard let fileSystem = state.virtualFileSystemsByNodeID[sourceNodeID],
                  let path = resolveVirtualFilePath(imageID, in: fileSystem),
                  let entry = try? fileSystem.entry(at: path),
                  entry.content.isImage
            else {
                setDesktopSuiteUnknownTarget(
                    state: &state,
                    actionName: "runtimeImageViewerSelectImage",
                    reason: "unknownImageTarget",
                    target: imageID ?? ""
                )
                return
            }
            state.runtimeImageViewerSelectionByNodeID[sourceNodeID] = path
            state.lastRuntimeFault = nil
            recordRuntimeEvent(
                state: &state,
                code: .runtimeImageViewerSelectionChanged,
                detail: "node=\(sourceNodeID.uuidString),image=\(path)"
            )
            appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Image Viewer opened: \(path)")

        case let .runtimeTextEditorSelectFile(nodeID, path):
            guard let sourceNodeID = validateDesktopSuiteAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .textEditor,
                actionName: "runtimeTextEditorSelectFile"
            ) else { return }
            guard normalizedRuntimeValue(path) != nil else {
                setDesktopSuiteMalformedPayload(
                    state: &state,
                    actionName: "runtimeTextEditorSelectFile",
                    reason: "missingPath",
                    message: "Text Editor selection requires a non-empty absolute path"
                )
                return
            }
            guard let fileSystem = state.virtualFileSystemsByNodeID[sourceNodeID],
                  let normalizedPath = resolveVirtualFilePath(path, in: fileSystem),
                  let text = try? fileSystem.textFile(at: normalizedPath)
            else {
                setDesktopSuiteUnknownTarget(
                    state: &state,
                    actionName: "runtimeTextEditorSelectFile",
                    reason: "unknownTextFile",
                    target: path ?? ""
                )
                return
            }
            state.runtimeTextEditorSelectionByNodeID[sourceNodeID] = normalizedPath
            state.runtimeTextEditorDraftByNodeID[sourceNodeID] = text
            state.lastRuntimeFault = nil
            recordRuntimeEvent(
                state: &state,
                code: .runtimeTextEditorDraftReset,
                detail: "node=\(sourceNodeID.uuidString),path=\(normalizedPath),chars=\(text.count)"
            )

        case let .runtimeTextEditorUpdateDraft(nodeID, text):
            guard let sourceNodeID = validateDesktopSuiteAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .textEditor,
                actionName: "runtimeTextEditorUpdateDraft"
            ) else { return }
            guard let text else {
                setDesktopSuiteMalformedPayload(
                    state: &state,
                    actionName: "runtimeTextEditorUpdateDraft",
                    reason: "missingDraft",
                    message: "Text Editor draft update requires text"
                )
                return
            }
            state.runtimeTextEditorDraftByNodeID[sourceNodeID] = text
            state.lastRuntimeFault = nil
            recordRuntimeEvent(
                state: &state,
                code: .runtimeTextEditorDraftUpdated,
                detail: "node=\(sourceNodeID.uuidString),chars=\(text.count)"
            )

        case let .runtimeTextEditorSaveDraft(nodeID):
            guard let sourceNodeID = validateDesktopSuiteAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .textEditor,
                actionName: "runtimeTextEditorSaveDraft"
            ) else { return }
            guard let path = state.runtimeTextEditorSelectionByNodeID[sourceNodeID],
                  let draft = state.runtimeTextEditorDraftByNodeID[sourceNodeID]
            else {
                setVirtualFileSystemFailure(
                    state: &state,
                    actionName: "runtimeTextEditorSaveDraft",
                    detail: "No text file is selected."
                )
                return
            }
            do {
                var fileSystem = state.virtualFileSystemsByNodeID[sourceNodeID] ?? .defaultForDevice()
                try fileSystem.writeTextFile(at: path, text: draft)
                var candidateFileSystems = state.virtualFileSystemsByNodeID
                candidateFileSystems[sourceNodeID] = fileSystem
                try TopologyVirtualFileSystem.validateProjectQuotas(candidateFileSystems)
                state.virtualFileSystemsByNodeID = candidateFileSystems
                state.synchronizeRuntimeDNSConfigurationFromHostsFile(nodeID: sourceNodeID)
                state.lastRuntimeFault = nil
                advancePersistenceRevision(state: &state)
                recordRuntimeEvent(
                    state: &state,
                    code: .runtimeTextEditorDraftSaved,
                    detail: "node=\(sourceNodeID.uuidString),path=\(path),chars=\(draft.count)"
                )
                appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Text Editor saved: \(path)")
            } catch {
                setVirtualFileSystemFailure(
                    state: &state,
                    actionName: "runtimeTextEditorSaveDraft",
                    detail: error.localizedDescription
                )
            }

        case let .runtimeTextEditorResetDraft(nodeID):
            guard let sourceNodeID = validateDesktopSuiteAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .textEditor,
                actionName: "runtimeTextEditorResetDraft"
            ) else { return }
            guard let fileSystem = state.virtualFileSystemsByNodeID[sourceNodeID],
                  let path = state.runtimeTextEditorSelectionByNodeID[sourceNodeID],
                  let text = try? fileSystem.textFile(at: path)
            else {
                setVirtualFileSystemFailure(
                    state: &state,
                    actionName: "runtimeTextEditorResetDraft",
                    detail: "The selected text file is unavailable."
                )
                return
            }
            state.runtimeTextEditorDraftByNodeID[sourceNodeID] = text
            state.lastRuntimeFault = nil
            recordRuntimeEvent(
                state: &state,
                code: .runtimeTextEditorDraftReset,
                detail: "node=\(sourceNodeID.uuidString),path=\(path),chars=\(text.count)"
            )

        case let .runtimeFileSystemCreateDirectory(nodeID, path):
            mutateVirtualFileSystem(
                state: &state,
                nodeID: nodeID,
                actionName: "runtimeFileSystemCreateDirectory"
            ) { fileSystem in
                let path = try normalizedRequiredVirtualFilePath(path)
                try fileSystem.createDirectory(at: path, recursive: true)
                return path
            }

        case let .runtimeFileSystemCreateTextFile(nodeID, path, text):
            mutateVirtualFileSystem(
                state: &state,
                nodeID: nodeID,
                actionName: "runtimeFileSystemCreateTextFile"
            ) { fileSystem in
                let path = try normalizedRequiredVirtualFilePath(path)
                try fileSystem.writeTextFile(at: path, text: text ?? "", overwrite: false)
                return path
            }

        case let .runtimeFileSystemCopyItem(nodeID, sourcePath, destinationPath):
            mutateVirtualFileSystem(
                state: &state,
                nodeID: nodeID,
                actionName: "runtimeFileSystemCopyItem"
            ) { fileSystem in
                let source = try normalizedRequiredVirtualFilePath(sourcePath)
                let destination = try normalizedRequiredVirtualFilePath(destinationPath)
                try fileSystem.copyItem(at: source, to: destination)
                return "\(source)->\(destination)"
            }

        case let .runtimeFileSystemMoveItem(nodeID, sourcePath, destinationPath):
            mutateVirtualFileSystem(
                state: &state,
                nodeID: nodeID,
                actionName: "runtimeFileSystemMoveItem"
            ) { fileSystem in
                let source = try normalizedRequiredVirtualFilePath(sourcePath)
                let destination = try normalizedRequiredVirtualFilePath(destinationPath)
                try fileSystem.moveItem(at: source, to: destination)
                return "\(source)->\(destination)"
            }

        case let .runtimeFileSystemRenameItem(nodeID, path, newName):
            mutateVirtualFileSystem(
                state: &state,
                nodeID: nodeID,
                actionName: "runtimeFileSystemRenameItem"
            ) { fileSystem in
                let source = try normalizedRequiredVirtualFilePath(path)
                guard let newName = normalizedRuntimeValue(newName) else {
                    throw TopologyVirtualFileSystemError.invalidPathComponent(newName ?? "")
                }
                let destination = try fileSystem.renameItem(at: source, to: newName)
                return "\(source)->\(destination)"
            }

        case let .runtimeFileSystemDeleteItem(nodeID, path, recursive):
            mutateVirtualFileSystem(
                state: &state,
                nodeID: nodeID,
                actionName: "runtimeFileSystemDeleteItem"
            ) { fileSystem in
                let path = try normalizedRequiredVirtualFilePath(path)
                try fileSystem.deleteItem(at: path, recursive: recursive ?? false)
                return path
            }

        case let .runtimeDHCPLease(nodeID, ipAddress, subnetMask):
            guard let sourceNodeID = validateServiceAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .dhcpServer,
                actionName: "runtimeDHCPLease"
            ) else {
                return
            }

            guard state.simulationPhase == .running else {
                setDHCPFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .dhcpLeaseRejectedSimulationStopped,
                    faultCategory: .runtimeFault,
                    faultCode: "dhcpWhileSimulationStopped",
                    message: "DHCP lease actions require a running simulation",
                    detail: "phase=\(state.simulationPhase.rawValue),source=serviceApp"
                )
                return
            }

            guard let normalizedAddress = normalizedIPv4Address(ipAddress) else {
                setDHCPFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .dhcpLeaseRejectedMalformedCommand,
                    faultCategory: .commandValidation,
                    faultCode: "malformedDHCPCommand",
                    message: "DHCP lease IP must be a valid IPv4 address",
                    detail: "malformedDHCPCommand"
                )
                return
            }

            guard let normalizedMask = normalizedSubnetMask(subnetMask) else {
                setDHCPFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .dhcpLeaseRejectedMalformedCommand,
                    faultCategory: .commandValidation,
                    faultCode: "malformedDHCPCommand",
                    message: "DHCP lease subnet mask must be a contiguous IPv4 mask",
                    detail: "malformedDHCPCommand"
                )
                return
            }

            executeDHCPLeaseCommand(
                state: &state,
                sourceNodeID: sourceNodeID,
                ipAddress: normalizedAddress,
                subnetMask: normalizedMask
            )

        case let .runtimeDHCPRelease(nodeID):
            guard let sourceNodeID = validateServiceAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .dhcpServer,
                actionName: "runtimeDHCPRelease"
            ) else {
                return
            }

            guard state.simulationPhase == .running else {
                setDHCPFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .dhcpLeaseRejectedSimulationStopped,
                    faultCategory: .runtimeFault,
                    faultCode: "dhcpWhileSimulationStopped",
                    message: "DHCP release actions require a running simulation",
                    detail: "phase=\(state.simulationPhase.rawValue),source=serviceApp"
                )
                return
            }

            executeDHCPReleaseCommand(
                state: &state,
                sourceNodeID: sourceNodeID
            )

        case let .runtimeDNSStart(nodeID):
            guard let sourceNodeID = validateServiceAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .dnsServer,
                actionName: "runtimeDNSStart"
            ) else { return }
            guard state.simulationPhase == .running else {
                setDNSFailure(
                    state: &state, sourceNodeID: sourceNodeID,
                    eventCode: .dnsResolveRejectedSimulationStopped,
                    faultCategory: .runtimeFault, faultCode: "dnsWhileSimulationStopped",
                    message: "DNS Server requires a running simulation",
                    detail: "phase=\(state.simulationPhase.rawValue),source=serviceApp"
                )
                return
            }
            if state.runtimeDNSServerSocketIDByNodeID[sourceNodeID] != nil,
               state.networkRuntime.isDNSServerRunning(nodeID: sourceNodeID) {
                state.lastRuntimeFault = nil
                recordRuntimeEvent(state: &state, code: .dnsServerStartIgnoredAlreadyRunning, detail: "node=\(sourceNodeID.uuidString),port=53")
                appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "DNS Server already running on UDP port 53")
                return
            }
            guard let configuredIPAddress = state.runtimeDeviceConfigurations[sourceNodeID]?.ipAddress,
                  configuredIPAddress != "0.0.0.0",
                  let socketID = state.networkRuntime.startDNSServer(nodeID: sourceNodeID)
            else {
                setDNSFailure(
                    state: &state, sourceNodeID: sourceNodeID,
                    eventCode: .dnsServerRejectedInvalidConfiguration,
                    faultCategory: .networkConfiguration, faultCode: "dnsServerUnavailable",
                    message: "Configure a unique device IPv4 address and free UDP port 53 before starting DNS Server",
                    detail: "dnsServerUnavailable"
                )
                return
            }
            state.runtimeDNSServerSocketIDByNodeID[sourceNodeID] = socketID
            state.lastRuntimeFault = nil
            recordRuntimeEvent(state: &state, code: .dnsServerStarted, detail: "node=\(sourceNodeID.uuidString),ip=\(configuredIPAddress),port=53")
            appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "DNS Server started on \(configuredIPAddress):53/udp")

        case let .runtimeDNSStop(nodeID):
            guard let sourceNodeID = validateServiceAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .dnsServer,
                actionName: "runtimeDNSStop"
            ) else { return }
            guard state.simulationPhase == .running else {
                setDNSFailure(
                    state: &state, sourceNodeID: sourceNodeID,
                    eventCode: .dnsResolveRejectedSimulationStopped,
                    faultCategory: .runtimeFault, faultCode: "dnsWhileSimulationStopped",
                    message: "DNS Server requires a running simulation",
                    detail: "phase=\(state.simulationPhase.rawValue),source=serviceApp"
                )
                return
            }
            guard state.runtimeDNSServerSocketIDByNodeID.removeValue(forKey: sourceNodeID) != nil else {
                state.lastRuntimeFault = nil
                recordRuntimeEvent(state: &state, code: .dnsServerStopIgnoredAlreadyStopped, detail: "node=\(sourceNodeID.uuidString)")
                appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "DNS Server is already stopped")
                return
            }
            state.networkRuntime.stopDNSServer(nodeID: sourceNodeID)
            state.lastRuntimeFault = nil
            recordRuntimeEvent(state: &state, code: .dnsServerStopped, detail: "node=\(sourceNodeID.uuidString)")
            appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "DNS Server stopped")

        case let .runtimeDNSAddRecord(nodeID, hostname, targetIPAddress):
            guard let sourceNodeID = validateServiceAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .dnsServer,
                actionName: "runtimeDNSAddRecord"
            ) else {
                return
            }

            guard state.simulationPhase == .running else {
                setDNSFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .dnsRecordRejectedSimulationStopped,
                    faultCategory: .runtimeFault,
                    faultCode: "dnsWhileSimulationStopped",
                    message: "DNS actions require a running simulation",
                    detail: "phase=\(state.simulationPhase.rawValue),source=serviceApp"
                )
                return
            }

            guard let normalizedHost = normalizedHostname(hostname) else {
                setDNSFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .dnsRecordRejectedMalformedCommand,
                    faultCategory: .commandValidation,
                    faultCode: "malformedDNSCommand",
                    message: "DNS hostname must contain only letters, numbers, '-' or '.'",
                    detail: "malformedDNSCommand"
                )
                return
            }

            guard let normalizedAddress = normalizedIPv4Address(targetIPAddress) else {
                setDNSFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .dnsRecordRejectedMalformedCommand,
                    faultCategory: .commandValidation,
                    faultCode: "malformedDNSCommand",
                    message: "DNS target must be a valid IPv4 address",
                    detail: "malformedDNSCommand"
                )
                return
            }

            executeDNSRegisterCommand(
                state: &state,
                sourceNodeID: sourceNodeID,
                hostname: normalizedHost,
                targetIPAddress: normalizedAddress
            )

        case let .runtimeDNSRemoveRecord(nodeID, hostname):
            guard let sourceNodeID = validateServiceAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .dnsServer,
                actionName: "runtimeDNSRemoveRecord"
            ) else {
                return
            }

            guard state.simulationPhase == .running else {
                setDNSFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .dnsRecordRejectedSimulationStopped,
                    faultCategory: .runtimeFault,
                    faultCode: "dnsWhileSimulationStopped",
                    message: "DNS actions require a running simulation",
                    detail: "phase=\(state.simulationPhase.rawValue),source=serviceApp"
                )
                return
            }

            guard let normalizedHost = normalizedHostname(hostname) else {
                setDNSFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .dnsRecordRejectedMalformedCommand,
                    faultCategory: .commandValidation,
                    faultCode: "malformedDNSCommand",
                    message: "DNS hostname must contain only letters, numbers, '-' or '.'",
                    detail: "malformedDNSCommand"
                )
                return
            }

            executeDNSRemoveCommand(
                state: &state,
                sourceNodeID: sourceNodeID,
                hostname: normalizedHost
            )

        case let .runtimeDNSResolveRecord(nodeID, hostname):
            guard let sourceNodeID = validateServiceAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .dnsServer,
                actionName: "runtimeDNSResolveRecord"
            ) else {
                return
            }

            guard state.simulationPhase == .running else {
                setDNSFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .dnsResolveRejectedSimulationStopped,
                    faultCategory: .runtimeFault,
                    faultCode: "dnsWhileSimulationStopped",
                    message: "DNS actions require a running simulation",
                    detail: "phase=\(state.simulationPhase.rawValue),source=serviceApp"
                )
                return
            }

            guard let normalizedHost = normalizedHostname(hostname) else {
                setDNSFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .dnsRecordRejectedMalformedCommand,
                    faultCategory: .commandValidation,
                    faultCode: "malformedDNSCommand",
                    message: "DNS hostname must contain only letters, numbers, '-' or '.'",
                    detail: "malformedDNSCommand"
                )
                return
            }

            executeDNSResolveCommand(
                state: &state,
                sourceNodeID: sourceNodeID,
                hostname: normalizedHost
            )

        case let .runtimeWebStart(nodeID, port):
            guard let sourceNodeID = validateServiceAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .webServer,
                actionName: "runtimeWebStart"
            ) else {
                return
            }

            guard state.simulationPhase == .running else {
                setWebServiceFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .webServerRejectedSimulationStopped,
                    faultCategory: .runtimeFault,
                    faultCode: "webServerWhileSimulationStopped",
                    message: "Web Server actions require a running simulation",
                    detail: "phase=\(state.simulationPhase.rawValue)"
                )
                return
            }

            guard let normalizedPort = normalizedServicePort(port) else {
                setWebServiceFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .webServerRejectedInvalidConfiguration,
                    faultCategory: .commandValidation,
                    faultCode: "invalidWebServerPort",
                    message: "Web Server port must be an integer between 1 and 65535",
                    detail: "invalidWebServerPort"
                )
                return
            }

            if let current = state.runtimeWebServerByNodeID[sourceNodeID] {
                state.lastRuntimeFault = nil
                recordRuntimeEvent(
                    state: &state,
                    code: .webServerStartIgnoredAlreadyRunning,
                    detail: "node=\(sourceNodeID.uuidString),port=\(current.port)"
                )
                appendConsoleLine(
                    state: &state,
                    nodeID: sourceNodeID,
                    line: "Web Server already running on port \(current.port)"
                )
                return
            }

            state.runtimeWebServerConfigurationsByNodeID[sourceNodeID] = TopologyRuntimeWebServerConfiguration(
                port: normalizedPort,
                documentRoot: state.runtimeWebServerConfigurationsByNodeID[sourceNodeID]?.documentRoot ?? TopologyRuntimeWebServerConfiguration.defaultDocumentRoot
            )
            advancePersistenceRevision(state: &state)

            guard let listenerSocketID = state.networkRuntime.openTCPServerSocket(
                nodeID: sourceNodeID,
                localPort: UInt16(normalizedPort)
            ) else {
                setWebServiceFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .webServerRejectedInvalidConfiguration,
                    faultCategory: .runtimeFault,
                    faultCode: "webServerPortInUse",
                    message: "Web Server port is already in use",
                    detail: "port=\(normalizedPort)"
                )
                return
            }
            state.runtimeWebServerSocketIDByNodeID[sourceNodeID] = listenerSocketID
            state.runtimeWebServerByNodeID[sourceNodeID] = TopologyRuntimeServiceProcessState(port: normalizedPort)
            state.lastRuntimeFault = nil
            recordRuntimeEvent(
                state: &state,
                code: .webServerStarted,
                detail: "node=\(sourceNodeID.uuidString),port=\(normalizedPort)"
            )
            appendConsoleLine(
                state: &state,
                nodeID: sourceNodeID,
                line: "Web Server started on port \(normalizedPort)"
            )

        case let .runtimeWebStop(nodeID):
            guard let sourceNodeID = validateServiceAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .webServer,
                actionName: "runtimeWebStop"
            ) else {
                return
            }

            guard state.simulationPhase == .running else {
                setWebServiceFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .webServerRejectedSimulationStopped,
                    faultCategory: .runtimeFault,
                    faultCode: "webServerWhileSimulationStopped",
                    message: "Web Server actions require a running simulation",
                    detail: "phase=\(state.simulationPhase.rawValue)"
                )
                return
            }

            guard let runningState = state.runtimeWebServerByNodeID.removeValue(forKey: sourceNodeID) else {
                state.lastRuntimeFault = nil
                recordRuntimeEvent(
                    state: &state,
                    code: .webServerStopIgnoredAlreadyStopped,
                    detail: "node=\(sourceNodeID.uuidString)"
                )
                appendConsoleLine(
                    state: &state,
                    nodeID: sourceNodeID,
                    line: "Web Server already stopped"
                )
                return
            }

            if let listenerSocketID = state.runtimeWebServerSocketIDByNodeID.removeValue(forKey: sourceNodeID) {
                for acceptedSocketID in state.networkRuntime.acceptedTCPSocketIDs(listenerSocketID: listenerSocketID) {
                    _ = state.networkRuntime.closeTCPConnectionAndClean(socketID: acceptedSocketID)
                }
                state.networkRuntime.closeTCPSocket(socketID: listenerSocketID)
            }
            state.lastRuntimeFault = nil
            recordRuntimeEvent(
                state: &state,
                code: .webServerStopped,
                detail: "node=\(sourceNodeID.uuidString),port=\(runningState.port)"
            )
            appendConsoleLine(
                state: &state,
                nodeID: sourceNodeID,
                line: "Web Server stopped"
            )

        case let .runtimeWebRestart(nodeID, port):
            guard let sourceNodeID = validateServiceAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .webServer,
                actionName: "runtimeWebRestart"
            ) else { return }
            let configuredPort = port ?? String(state.runtimeWebServerConfigurationsByNodeID[sourceNodeID]?.port ?? TopologyRuntimeWebServerConfiguration.defaultPort)
            guard let normalizedPort = normalizedServicePort(configuredPort) else {
                setWebServiceFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .webServerRejectedInvalidConfiguration,
                    faultCategory: .commandValidation,
                    faultCode: "invalidWebServerPort",
                    message: "Web Server port must be an integer between 1 and 65535",
                    detail: "invalidWebServerPort"
                )
                return
            }
            if let running = state.runtimeWebServerByNodeID[sourceNodeID],
               running.port != normalizedPort,
               state.networkRuntime.isTCPPortReserved(nodeID: sourceNodeID, port: UInt16(normalizedPort)) {
                setWebServiceFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .webServerRejectedInvalidConfiguration,
                    faultCategory: .runtimeFault,
                    faultCode: "webServerPortInUse",
                    message: "Web Server port is already in use",
                    detail: "port=\(normalizedPort)"
                )
                return
            }
            if state.runtimeWebServerByNodeID[sourceNodeID] != nil {
                reduce(state: &state, action: .runtimeWebStop(nodeID: sourceNodeID))
            }
            state.runtimeWebServerRequestLogsByNodeID[sourceNodeID]?.removeAll()
            reduce(state: &state, action: .runtimeWebStart(nodeID: sourceNodeID, port: String(normalizedPort)))
            guard state.runtimeWebServerByNodeID[sourceNodeID]?.port == normalizedPort else { return }
            recordRuntimeEvent(state: &state, code: .webServerRestarted, detail: "node=\(sourceNodeID.uuidString),port=\(normalizedPort)")

        case let .runtimeWebBrowserNavigate(nodeID, address):
            guard let sourceNodeID = validateServiceAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .webBrowser,
                actionName: "runtimeWebBrowserNavigate"
            ) else { return }
            guard state.simulationPhase == .running else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .runtimeFault,
                    code: "webBrowserWhileSimulationStopped",
                    message: "Web Browser actions require a running simulation"
                )
                recordRuntimeEvent(state: &state, code: .webBrowserNavigationFailed, detail: "simulationStopped")
                return
            }
            guard let address, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .malformedRuntimePayload,
                    code: "webBrowserMissingAddress",
                    message: "Web Browser navigation requires a URL, host, IP, or path"
                )
                recordRuntimeEvent(state: &state, code: .webBrowserRejectedMalformedURL, detail: "missingAddress")
                return
            }
            switch state.navigateWebBrowser(nodeID: sourceNodeID, rawAddress: address) {
            case .success:
                state.lastRuntimeFault = nil
                advancePersistenceRevision(state: &state)
                recordRuntimeEvent(state: &state, code: .webBrowserNavigationSucceeded, detail: "node=\(sourceNodeID.uuidString),address=\(address)")
            case let .failure(error):
                recordWebBrowserNavigationFailure(state: &state, error: error)
            }

        case let .runtimeWebBrowserBack(nodeID):
            guard let sourceNodeID = validateServiceAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .webBrowser,
                actionName: "runtimeWebBrowserBack"
            ) else { return }
            guard let browser = state.runtimeWebBrowserStateByNodeID[sourceNodeID], let index = browser.historyIndex, index > 0 else { return }
            let targetIndex = index - 1
            let target = browser.history[targetIndex].address
            switch state.navigateWebBrowser(nodeID: sourceNodeID, rawAddress: target, historyIndex: targetIndex) {
            case .success:
                state.lastRuntimeFault = nil
                advancePersistenceRevision(state: &state)
                recordRuntimeEvent(state: &state, code: .webBrowserNavigationSucceeded, detail: "node=\(sourceNodeID.uuidString),history=back")
            case let .failure(error):
                recordWebBrowserNavigationFailure(state: &state, error: error)
            }

        case let .runtimeWebBrowserForward(nodeID):
            guard let sourceNodeID = validateServiceAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .webBrowser,
                actionName: "runtimeWebBrowserForward"
            ) else { return }
            guard let browser = state.runtimeWebBrowserStateByNodeID[sourceNodeID], let index = browser.historyIndex, index + 1 < browser.history.count else { return }
            let targetIndex = index + 1
            let target = browser.history[targetIndex].address
            switch state.navigateWebBrowser(nodeID: sourceNodeID, rawAddress: target, historyIndex: targetIndex) {
            case .success:
                state.lastRuntimeFault = nil
                advancePersistenceRevision(state: &state)
                recordRuntimeEvent(state: &state, code: .webBrowserNavigationSucceeded, detail: "node=\(sourceNodeID.uuidString),history=forward")
            case let .failure(error):
                recordWebBrowserNavigationFailure(state: &state, error: error)
            }

        case let .runtimeWebBrowserReset(nodeID):
            guard let sourceNodeID = validateServiceAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .webBrowser,
                actionName: "runtimeWebBrowserReset"
            ) else { return }
            state.runtimeWebBrowserStateByNodeID[sourceNodeID]?.resetTransientSession()
            state.runtimeWebBrowserStateByNodeID.removeValue(forKey: sourceNodeID)

        case let .runtimeEchoStart(nodeID, port):
            guard let sourceNodeID = validateServiceAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .echoServer,
                actionName: "runtimeEchoStart"
            ) else {
                return
            }

            guard state.simulationPhase == .running else {
                setEchoServiceFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .echoServerRejectedSimulationStopped,
                    faultCategory: .runtimeFault,
                    faultCode: "echoServerWhileSimulationStopped",
                    message: "Echo Server actions require a running simulation",
                    detail: "phase=\(state.simulationPhase.rawValue)"
                )
                return
            }

            guard let normalizedPort = normalizedServicePort(port) else {
                setEchoServiceFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .echoServerRejectedInvalidConfiguration,
                    faultCategory: .commandValidation,
                    faultCode: "invalidEchoServerPort",
                    message: "Echo Server port must be an integer between 1 and 65535",
                    detail: "invalidEchoServerPort"
                )
                return
            }

            if let current = state.runtimeEchoServerByNodeID[sourceNodeID] {
                state.lastRuntimeFault = nil
                recordRuntimeEvent(
                    state: &state,
                    code: .echoServerStartIgnoredAlreadyRunning,
                    detail: "node=\(sourceNodeID.uuidString),port=\(current.port)"
                )
                appendConsoleLine(
                    state: &state,
                    nodeID: sourceNodeID,
                    line: "Echo Server already running on port \(current.port)"
                )
                return
            }

            guard let listenerSocketID = state.networkRuntime.openTCPServerSocket(
                nodeID: sourceNodeID,
                localPort: UInt16(normalizedPort)
            ) else {
                setEchoServiceFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .echoServerRejectedInvalidConfiguration,
                    faultCategory: .runtimeFault,
                    faultCode: "echoServerPortInUse",
                    message: "Echo Server port is already in use",
                    detail: "port=\(normalizedPort)"
                )
                return
            }
            guard let udpSocketID = state.networkRuntime.bindUDPSocket(
                nodeID: sourceNodeID,
                localPort: UInt16(normalizedPort)
            ) else {
                state.networkRuntime.discardSocket(socketID: listenerSocketID)
                setEchoServiceFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .echoServerRejectedInvalidConfiguration,
                    faultCategory: .runtimeFault,
                    faultCode: "echoServerUDPPortInUse",
                    message: "Echo Server UDP port is already in use",
                    detail: "port=\(normalizedPort)"
                )
                return
            }
            state.runtimeEchoServerSocketIDByNodeID[sourceNodeID] = listenerSocketID
            state.runtimeEchoServerUDPSocketIDByNodeID[sourceNodeID] = udpSocketID
            state.runtimeEchoServerServiceStateByNodeID[sourceNodeID] = TopologyRuntimeEchoServerServiceState()
            state.runtimeEchoServerByNodeID[sourceNodeID] = TopologyRuntimeServiceProcessState(port: normalizedPort)
            state.lastRuntimeFault = nil
            recordRuntimeEvent(
                state: &state,
                code: .echoServerStarted,
                detail: "node=\(sourceNodeID.uuidString),port=\(normalizedPort)"
            )
            appendConsoleLine(
                state: &state,
                nodeID: sourceNodeID,
                line: "Echo Server started on port \(normalizedPort)"
            )

        case let .runtimeEchoStop(nodeID):
            guard let sourceNodeID = validateServiceAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .echoServer,
                actionName: "runtimeEchoStop"
            ) else {
                return
            }

            guard state.simulationPhase == .running else {
                setEchoServiceFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .echoServerRejectedSimulationStopped,
                    faultCategory: .runtimeFault,
                    faultCode: "echoServerWhileSimulationStopped",
                    message: "Echo Server actions require a running simulation",
                    detail: "phase=\(state.simulationPhase.rawValue)"
                )
                return
            }

            guard let runningState = state.runtimeEchoServerByNodeID.removeValue(forKey: sourceNodeID) else {
                state.lastRuntimeFault = nil
                recordRuntimeEvent(
                    state: &state,
                    code: .echoServerStopIgnoredAlreadyStopped,
                    detail: "node=\(sourceNodeID.uuidString)"
                )
                appendConsoleLine(
                    state: &state,
                    nodeID: sourceNodeID,
                    line: "Echo Server already stopped"
                )
                return
            }

            var closedTCPSocketIDs: Set<UUID> = []
            if let listenerSocketID = state.runtimeEchoServerSocketIDByNodeID.removeValue(forKey: sourceNodeID) {
                for acceptedSocketID in state.networkRuntime.acceptedTCPSocketIDs(listenerSocketID: listenerSocketID) {
                    closedTCPSocketIDs.formUnion(
                        state.networkRuntime.closeTCPConnectionAndClean(socketID: acceptedSocketID)
                    )
                }
                closedTCPSocketIDs.formUnion(
                    state.networkRuntime.closeTCPConnectionAndClean(socketID: listenerSocketID)
                )
            }
            if let udpSocketID = state.runtimeEchoServerUDPSocketIDByNodeID.removeValue(forKey: sourceNodeID) {
                state.networkRuntime.closeSocket(socketID: udpSocketID)
            }
            for clientNodeID in Array(state.runtimeSimpleClientByNodeID.keys) {
                guard var client = state.runtimeSimpleClientByNodeID[clientNodeID],
                      let clientSocketID = client.socketID,
                      closedTCPSocketIDs.contains(clientSocketID) else { continue }
                client.socketID = nil
                client.connectionState = .disconnected
                client.appendLog(
                    timestampMilliseconds: state.networkRuntime.state.currentTimeMilliseconds,
                    direction: "system",
                    message: "Disconnected: Echo Server stopped"
                )
                state.runtimeSimpleClientByNodeID[clientNodeID] = client
            }
            state.simulationTick = max(state.simulationTick, state.networkRuntime.state.currentTimeMilliseconds)
            state.runtimeEchoServerServiceStateByNodeID.removeValue(forKey: sourceNodeID)
            state.lastRuntimeFault = nil
            recordRuntimeEvent(
                state: &state,
                code: .echoServerStopped,
                detail: "node=\(sourceNodeID.uuidString),port=\(runningState.port)"
            )
            appendConsoleLine(
                state: &state,
                nodeID: sourceNodeID,
                line: "Echo Server stopped"
            )

        case let .runtimeSimpleClientConnect(nodeID, destinationIPAddress, port, protocolKind):
            guard let sourceNodeID = validateDesktopSuiteAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .simpleClient,
                actionName: "runtimeSimpleClientConnect"
            ) else { return }
            guard state.simulationPhase == .running else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .runtimeFault,
                    code: "simpleClientWhileSimulationStopped",
                    message: "Simple Client actions require a running simulation"
                )
                recordRuntimeEvent(state: &state, code: .simpleClientRejectedSimulationStopped)
                return
            }
            guard let destination = normalizedRuntimeValue(destinationIPAddress),
                  TopologyJavaRouteTable.isValidJavaIPAddress(destination),
                  let normalizedPort = normalizedServicePort(port) else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .commandValidation,
                    code: "invalidSimpleClientConfiguration",
                    message: "Simple Client requires a valid IPv4 destination and port 1-65535"
                )
                recordRuntimeEvent(state: &state, code: .simpleClientRejectedInvalidConfiguration)
                appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Simple Client failed: invalid destination or port")
                return
            }
            let selectedProtocol = protocolKind ?? .tcp
            if let oldClient = state.runtimeSimpleClientByNodeID[sourceNodeID],
               let oldSocketID = oldClient.socketID {
                switch oldClient.protocolKind {
                case .tcp:
                    _ = state.networkRuntime.closeTCPConnectionAndClean(socketID: oldSocketID)
                case .udp:
                    state.networkRuntime.closeSocket(socketID: oldSocketID)
                }
                state.simulationTick = max(state.simulationTick, state.networkRuntime.state.currentTimeMilliseconds)
            }
            var client = TopologyRuntimeSimpleClientState(
                protocolKind: selectedProtocol,
                destinationIPAddress: destination,
                destinationPort: normalizedPort,
                socketID: nil,
                connectionState: .connecting,
                nextLogID: 1,
                logs: []
            )
            client.appendLog(
                timestampMilliseconds: state.networkRuntime.state.currentTimeMilliseconds,
                direction: "system",
                message: "Connecting \(selectedProtocol.displayName) \(destination):\(normalizedPort)"
            )
            switch selectedProtocol {
            case .tcp:
                guard let socketID = state.networkRuntime.openTCPClientSocket(
                    nodeID: sourceNodeID,
                    remoteIPAddress: destination,
                    remotePort: UInt16(normalizedPort)
                ) else {
                    client.connectionState = .failed
                    client.appendLog(timestampMilliseconds: state.networkRuntime.state.currentTimeMilliseconds, direction: "error", message: "Unable to allocate TCP socket")
                    state.runtimeSimpleClientByNodeID[sourceNodeID] = client
                    state.lastRuntimeFault = TopologyRuntimeFault(category: .runtimeFault, code: "simpleClientSocketUnavailable", message: "Simple Client could not allocate a TCP socket")
                    recordRuntimeEvent(state: &state, code: .simpleClientRejectedInvalidConfiguration)
                    return
                }
                guard state.networkRuntime.connectTCP(socketID: socketID) else {
                    state.networkRuntime.discardSocket(socketID: socketID)
                    client.connectionState = .failed
                    client.appendLog(timestampMilliseconds: state.networkRuntime.state.currentTimeMilliseconds, direction: "error", message: "Connection timeout or unreachable destination")
                    state.runtimeSimpleClientByNodeID[sourceNodeID] = client
                    state.lastRuntimeFault = TopologyRuntimeFault(category: .networkRouting, code: "simpleClientUnreachable", message: "Simple Client could not connect to the destination")
                    recordRuntimeEvent(state: &state, code: .simpleClientRejectedUnreachable, detail: "destination=\(destination),port=\(normalizedPort)")
                    appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Simple Client failed: timeout or unreachable destination")
                    return
                }
                client.socketID = socketID
            case .udp:
                guard let socketID = state.networkRuntime.bindUDPSocket(
                    nodeID: sourceNodeID,
                    remoteIPAddress: destination,
                    remotePort: UInt16(normalizedPort)
                ) else {
                    client.connectionState = .failed
                    client.appendLog(timestampMilliseconds: state.networkRuntime.state.currentTimeMilliseconds, direction: "error", message: "Unable to allocate UDP socket")
                    state.runtimeSimpleClientByNodeID[sourceNodeID] = client
                    state.lastRuntimeFault = TopologyRuntimeFault(category: .runtimeFault, code: "simpleClientSocketUnavailable", message: "Simple Client could not allocate a UDP socket")
                    recordRuntimeEvent(state: &state, code: .simpleClientRejectedInvalidConfiguration)
                    return
                }
                client.socketID = socketID
            }
            client.connectionState = .connected
            client.appendLog(timestampMilliseconds: state.networkRuntime.state.currentTimeMilliseconds, direction: "system", message: "Connected")
            state.runtimeSimpleClientByNodeID[sourceNodeID] = client
            state.lastRuntimeFault = nil
            recordRuntimeEvent(state: &state, code: .simpleClientConnected, detail: "protocol=\(selectedProtocol.rawValue),destination=\(destination),port=\(normalizedPort)")
            appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Simple Client connected to \(destination):\(normalizedPort) (\(selectedProtocol.displayName))")

        case let .runtimeSimpleClientSend(nodeID, message):
            guard let sourceNodeID = validateDesktopSuiteAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .simpleClient,
                actionName: "runtimeSimpleClientSend"
            ), let message = message else {
                return
            }
            guard var client = state.runtimeSimpleClientByNodeID[sourceNodeID],
                  let socketID = client.socketID,
                  client.connectionState == .connected else {
                state.lastRuntimeFault = TopologyRuntimeFault(category: .networkRouting, code: "simpleClientNotConnected", message: "Connect the Simple Client before sending a message")
                recordRuntimeEvent(state: &state, code: .simpleClientRejectedNotConnected)
                appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Simple Client failed: not connected")
                return
            }
            let payload = Data(message.utf8)
            client.appendLog(timestampMilliseconds: state.networkRuntime.state.currentTimeMilliseconds, direction: "outbound", message: message)
            let initialResult = state.networkRuntime.simpleClientSend(socketID: socketID, protocolKind: client.protocolKind, payload: payload)
            guard initialResult.succeeded else {
                client.appendLog(timestampMilliseconds: state.networkRuntime.state.currentTimeMilliseconds, direction: "error", message: initialResult.failureCode ?? "send failed")
                state.runtimeSimpleClientByNodeID[sourceNodeID] = client
                state.simulationTick = max(state.simulationTick, state.networkRuntime.state.currentTimeMilliseconds)
                state.lastRuntimeFault = TopologyRuntimeFault(category: .networkRouting, code: initialResult.failureCode ?? "simpleClientSendFailed", message: "Simple Client could not send the message")
                recordRuntimeEvent(state: &state, code: .simpleClientRejectedUnreachable, detail: initialResult.failureCode)
                return
            }
            for serverNodeID in state.runtimeEchoServerByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                _ = state.pumpEchoServer(nodeID: serverNodeID)
            }
            _ = state.processProtocolApplicationServers()
            for serverNodeID in state.runtimeWebServerByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                _ = state.processWebServerRequests(nodeID: serverNodeID)
            }
            let response: Data?
            if let immediateResponse = initialResult.response {
                response = immediateResponse
            } else {
                switch client.protocolKind {
                case .tcp:
                    response = state.networkRuntime.receiveTCP(socketID: socketID)
                case .udp:
                    response = state.networkRuntime.receiveUDP(
                        socketID: socketID,
                        timeoutMilliseconds: TopologyNetworkRuntimeEngine.simpleClientUDPReceiveTimeoutMilliseconds
                    )?.datagram.payload
                }
            }
            state.simulationTick = max(state.simulationTick, state.networkRuntime.state.currentTimeMilliseconds)
            recordRuntimeEvent(state: &state, code: .simpleClientMessageSent, detail: "bytes=\(payload.count)")
            if let response {
                let text = String(data: response, encoding: .utf8) ?? "<binary \(response.count) bytes>"
                client.appendLog(timestampMilliseconds: state.networkRuntime.state.currentTimeMilliseconds, direction: "inbound", message: text)
                recordRuntimeEvent(state: &state, code: .simpleClientMessageReceived, detail: "bytes=\(response.count)")
            } else {
                client.appendLog(timestampMilliseconds: state.networkRuntime.state.currentTimeMilliseconds, direction: "timeout", message: "No echo response")
            }
            state.runtimeSimpleClientByNodeID[sourceNodeID] = client
            state.lastRuntimeFault = nil

        case let .runtimeSimpleClientDisconnect(nodeID):
            guard let sourceNodeID = validateDesktopSuiteAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .simpleClient,
                actionName: "runtimeSimpleClientDisconnect"
            ) else { return }
            guard var client = state.runtimeSimpleClientByNodeID[sourceNodeID] else { return }
            if let socketID = client.socketID {
                switch client.protocolKind {
                case .tcp:
                    _ = state.networkRuntime.closeTCPConnectionAndClean(socketID: socketID)
                case .udp:
                    state.networkRuntime.closeSocket(socketID: socketID)
                }
                state.simulationTick = max(state.simulationTick, state.networkRuntime.state.currentTimeMilliseconds)
            }
            client.socketID = nil
            client.connectionState = .disconnected
            client.appendLog(timestampMilliseconds: state.networkRuntime.state.currentTimeMilliseconds, direction: "system", message: "Disconnected")
            state.runtimeSimpleClientByNodeID[sourceNodeID] = client
            state.lastRuntimeFault = nil
            recordRuntimeEvent(state: &state, code: .simpleClientDisconnected)
            appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Simple Client disconnected")

        case let .saveRuntimeEmailClientConfiguration(nodeID, configuration):
            guard let sourceNodeID = validateServiceAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .emailClient,
                actionName: "saveRuntimeEmailClientConfiguration"
            ), let configuration else {
                if configuration == nil {
                    setMalformedRuntimePayload(state: &state, reason: "saveRuntimeEmailClientConfiguration requires configuration")
                }
                return
            }
            switch state.saveRuntimeEmailClientConfiguration(nodeID: sourceNodeID, configuration: configuration) {
            case .success:
                state.lastRuntimeFault = nil
                advancePersistenceRevision(state: &state)
                recordRuntimeEvent(state: &state, code: .emailClientConfigured, detail: "node=\(sourceNodeID.uuidString)")
            case let .failure(error):
                setEmailFailure(state: &state, nodeID: sourceNodeID, eventCode: .emailClientConfigurationRejected, faultCode: "emailClientConfigurationRejected", error: error)
            }

        case let .saveRuntimeEmailServerConfiguration(nodeID, configuration):
            guard let sourceNodeID = validateServiceAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .emailServer,
                actionName: "saveRuntimeEmailServerConfiguration"
            ), let configuration else {
                if configuration == nil {
                    setMalformedRuntimePayload(state: &state, reason: "saveRuntimeEmailServerConfiguration requires configuration")
                }
                return
            }
            switch state.saveRuntimeEmailServerConfiguration(nodeID: sourceNodeID, configuration: configuration) {
            case .success:
                state.lastRuntimeFault = nil
                advancePersistenceRevision(state: &state)
                recordRuntimeEvent(state: &state, code: .emailServerConfigured, detail: "node=\(sourceNodeID.uuidString),accounts=\(configuration.accounts.count)")
            case let .failure(error):
                setEmailFailure(state: &state, nodeID: sourceNodeID, eventCode: .emailServerRejected, faultCode: "emailServerConfigurationRejected", error: error)
            }

        case let .saveAndStartRuntimeEmailServer(nodeID, configuration):
            guard let sourceNodeID = validateServiceAppContext(
                state: &state,
                nodeID: nodeID,
                expectedProgram: .emailServer,
                actionName: "saveAndStartRuntimeEmailServer"
            ), let configuration else {
                if configuration == nil {
                    setMalformedRuntimePayload(state: &state, reason: "saveAndStartRuntimeEmailServer requires configuration")
                }
                return
            }
            switch state.saveRuntimeEmailServerConfiguration(nodeID: sourceNodeID, configuration: configuration) {
            case .success:
                advancePersistenceRevision(state: &state)
                recordRuntimeEvent(
                    state: &state,
                    code: .emailServerConfigured,
                    detail: "node=\(sourceNodeID.uuidString),accounts=\(configuration.accounts.count)"
                )
                switch state.startRuntimeEmailServer(nodeID: sourceNodeID) {
                case .success:
                    state.lastRuntimeFault = nil
                    recordRuntimeEvent(
                        state: &state,
                        code: .emailServerStarted,
                        detail: "node=\(sourceNodeID.uuidString),smtp=25,pop3=\(configuration.pop3Port)"
                    )
                case let .failure(error):
                    setEmailFailure(
                        state: &state,
                        nodeID: sourceNodeID,
                        eventCode: .emailServerRejected,
                        faultCode: "emailServerStartRejected",
                        error: error
                    )
                }
            case let .failure(error):
                setEmailFailure(
                    state: &state,
                    nodeID: sourceNodeID,
                    eventCode: .emailServerRejected,
                    faultCode: "emailServerConfigurationRejected",
                    error: error
                )
            }

        case let .runtimeEmailServerStart(nodeID):
            guard let sourceNodeID = validateServiceAppContext(
                state: &state, nodeID: nodeID, expectedProgram: .emailServer, actionName: "runtimeEmailServerStart"
            ) else { return }
            switch state.startRuntimeEmailServer(nodeID: sourceNodeID) {
            case .success:
                state.lastRuntimeFault = nil
                recordRuntimeEvent(state: &state, code: .emailServerStarted, detail: "node=\(sourceNodeID.uuidString),smtp=25,pop3=\(state.runtimeEmailServerConfigurationsByNodeID[sourceNodeID]?.pop3Port ?? 110)")
            case let .failure(error):
                setEmailFailure(state: &state, nodeID: sourceNodeID, eventCode: .emailServerRejected, faultCode: "emailServerStartRejected", error: error)
            }

        case let .runtimeEmailServerStop(nodeID):
            guard let sourceNodeID = validateServiceAppContext(
                state: &state, nodeID: nodeID, expectedProgram: .emailServer, actionName: "runtimeEmailServerStop"
            ) else { return }
            _ = state.stopRuntimeEmailServer(nodeID: sourceNodeID)
            state.lastRuntimeFault = nil
            recordRuntimeEvent(state: &state, code: .emailServerStopped, detail: "node=\(sourceNodeID.uuidString)")

        case let .runtimeEmailClientSend(nodeID, message):
            guard let sourceNodeID = validateDesktopSuiteAppContext(
                state: &state, nodeID: nodeID, expectedProgram: .emailClient, actionName: "runtimeEmailClientSend"
            ), let message else {
                if message == nil {
                    setMalformedRuntimePayload(state: &state, reason: "runtimeEmailClientSend requires message")
                }
                return
            }
            switch state.sendRuntimeEmail(nodeID: sourceNodeID, message: message) {
            case .success:
                state.lastRuntimeFault = nil
                advancePersistenceRevision(state: &state)
                recordRuntimeEvent(state: &state, code: .emailClientSendSucceeded, detail: "node=\(sourceNodeID.uuidString),recipients=\(message.envelopeRecipients.count)")
            case let .failure(error):
                setEmailFailure(state: &state, nodeID: sourceNodeID, eventCode: .emailClientSendRejected, faultCode: "emailClientSendRejected", error: error)
            }

        case let .runtimeEmailClientRetrieve(nodeID):
            guard let sourceNodeID = validateDesktopSuiteAppContext(
                state: &state, nodeID: nodeID, expectedProgram: .emailClient, actionName: "runtimeEmailClientRetrieve"
            ) else { return }
            switch state.retrieveRuntimeEmail(nodeID: sourceNodeID) {
            case let .success(messages):
                state.lastRuntimeFault = nil
                if !messages.isEmpty { advancePersistenceRevision(state: &state) }
                recordRuntimeEvent(state: &state, code: .emailClientRetrieveSucceeded, detail: "node=\(sourceNodeID.uuidString),messages=\(messages.count)")
            case let .failure(error):
                setEmailFailure(state: &state, nodeID: sourceNodeID, eventCode: .emailClientRetrieveRejected, faultCode: "emailClientRetrieveRejected", error: error)
            }

        case let .saveRuntimeGnutellaConfiguration(nodeID, configuration):
            guard let sourceNodeID = validateDesktopSuiteAppContext(
                state: &state, nodeID: nodeID, expectedProgram: .gnutella, actionName: "saveRuntimeGnutellaConfiguration"
            ), let configuration else {
                if configuration == nil {
                    setMalformedRuntimePayload(state: &state, reason: "saveRuntimeGnutellaConfiguration requires configuration")
                }
                return
            }
            switch state.saveRuntimeGnutellaConfiguration(nodeID: sourceNodeID, configuration: configuration) {
            case .success:
                state.lastRuntimeFault = nil
                advancePersistenceRevision(state: &state)
                recordRuntimeEvent(state: &state, code: .gnutellaConfigured, detail: "node=\(sourceNodeID.uuidString),maximumKnownPeers=\(configuration.maximumKnownPeers)")
            case let .failure(error):
                setGnutellaFailure(state: &state, nodeID: sourceNodeID, faultCode: "gnutellaConfigurationRejected", error: error)
            }

        case let .runtimeGnutellaJoin(nodeID, bootstrapIPAddress):
            guard let sourceNodeID = validateDesktopSuiteAppContext(
                state: &state, nodeID: nodeID, expectedProgram: .gnutella, actionName: "runtimeGnutellaJoin"
            ), let bootstrapIPAddress = normalizedRuntimeValue(bootstrapIPAddress) else {
                if normalizedRuntimeValue(bootstrapIPAddress) == nil {
                    setMalformedRuntimePayload(state: &state, reason: "runtimeGnutellaJoin requires bootstrapIPAddress")
                }
                return
            }
            switch state.joinRuntimeGnutella(nodeID: sourceNodeID, bootstrapIPAddress: bootstrapIPAddress) {
            case let .success(peers):
                state.lastRuntimeFault = nil
                recordRuntimeEvent(state: &state, code: .gnutellaJoined, detail: "node=\(sourceNodeID.uuidString),bootstrap=\(bootstrapIPAddress),peers=\(peers.count)")
            case let .failure(error):
                setGnutellaFailure(state: &state, nodeID: sourceNodeID, faultCode: "gnutellaJoinRejected", error: error)
            }

        case let .runtimeGnutellaResetNetwork(nodeID):
            guard let sourceNodeID = validateDesktopSuiteAppContext(
                state: &state, nodeID: nodeID, expectedProgram: .gnutella, actionName: "runtimeGnutellaResetNetwork"
            ) else { return }
            switch state.resetRuntimeGnutellaNetwork(nodeID: sourceNodeID) {
            case .success:
                state.lastRuntimeFault = nil
                recordRuntimeEvent(state: &state, code: .gnutellaNetworkReset, detail: "node=\(sourceNodeID.uuidString)")
            case let .failure(error):
                setGnutellaFailure(state: &state, nodeID: sourceNodeID, faultCode: "gnutellaResetRejected", error: error)
            }

        case let .runtimeGnutellaSearch(nodeID, searchTerm):
            guard let sourceNodeID = validateDesktopSuiteAppContext(
                state: &state, nodeID: nodeID, expectedProgram: .gnutella, actionName: "runtimeGnutellaSearch"
            ), let searchTerm = normalizedRuntimeValue(searchTerm) else {
                if normalizedRuntimeValue(searchTerm) == nil {
                    setMalformedRuntimePayload(state: &state, reason: "runtimeGnutellaSearch requires searchTerm")
                }
                return
            }
            switch state.searchRuntimeGnutella(nodeID: sourceNodeID, searchTerm: searchTerm) {
            case let .success(results):
                state.lastRuntimeFault = nil
                recordRuntimeEvent(state: &state, code: .gnutellaSearchCompleted, detail: "node=\(sourceNodeID.uuidString),results=\(results.count)")
            case let .failure(error):
                setGnutellaFailure(state: &state, nodeID: sourceNodeID, faultCode: "gnutellaSearchRejected", error: error)
            }

        case let .runtimeGnutellaClearSearchResults(nodeID):
            guard let sourceNodeID = validateDesktopSuiteAppContext(
                state: &state, nodeID: nodeID, expectedProgram: .gnutella, actionName: "runtimeGnutellaClearSearchResults"
            ) else { return }
            state.clearRuntimeGnutellaSearchResults(nodeID: sourceNodeID)
            state.lastRuntimeFault = nil
            recordRuntimeEvent(state: &state, code: .gnutellaSearchResultsCleared, detail: "node=\(sourceNodeID.uuidString)")

        case let .runtimeGnutellaDownload(nodeID, result):
            guard let sourceNodeID = validateDesktopSuiteAppContext(
                state: &state, nodeID: nodeID, expectedProgram: .gnutella, actionName: "runtimeGnutellaDownload"
            ), let result else {
                if result == nil {
                    setMalformedRuntimePayload(state: &state, reason: "runtimeGnutellaDownload requires result")
                }
                return
            }
            switch state.downloadRuntimeGnutella(nodeID: sourceNodeID, result: result) {
            case let .success(metadata):
                state.lastRuntimeFault = nil
                advancePersistenceRevision(state: &state)
                recordRuntimeEvent(state: &state, code: .gnutellaDownloadCompleted, detail: "node=\(sourceNodeID.uuidString),file=\(metadata.name),bytes=\(metadata.sizeBytes)")
            case let .failure(error):
                setGnutellaFailure(state: &state, nodeID: sourceNodeID, faultCode: "gnutellaDownloadRejected", error: error)
            }

        case let .executePing(nodeID, command):
            guard let sourceNodeID = nodeID else {
                setMalformedPingPayload(
                    state: &state,
                    detail: "missing source node identifier"
                )
                return
            }

            guard state.graph.containsNode(id: sourceNodeID) else {
                setPingFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .pingRejectedInvalidSourceConfiguration,
                    faultCategory: .networkConfiguration,
                    faultCode: "sourceNodeNotFound",
                    message: "Ping source node does not exist in graph",
                    detail: "sourceNodeNotFound"
                )
                return
            }

            let normalizedCommand = normalizedRuntimeValue(command) ?? ""
            recordRuntimeCompatibilityOperation(
                state: &state,
                nodeID: sourceNodeID,
                kind: .terminalCommand,
                detail: normalizedCommand
            )
            let terminalPrompt = "\(state.runtimeWorkingDirectoryByNodeID[sourceNodeID] ?? "/")>"
            appendConsoleLine(
                state: &state,
                nodeID: sourceNodeID,
                line: "\(terminalPrompt) \(normalizedCommand.isEmpty ? "(empty)" : normalizedCommand)"
            )

            switch parseRuntimeCommand(normalizedCommand) {
            case let .unsupported(command):
                let unsupportedDescriptor = unsupportedRuntimeCommandDescriptor(for: command)
                setRuntimeCommandFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .runtimeCommandRejectedUnsupported,
                    faultCode: unsupportedDescriptor.faultCode,
                    message: unsupportedDescriptor.message,
                    detail: unsupportedDescriptor.detail
                )
                return

            case let .malformed(command, reason):
                switch command {
                case "trace":
                    setTraceFailure(
                        state: &state,
                        sourceNodeID: sourceNodeID,
                        eventCode: .traceRejectedMalformedCommand,
                        faultCategory: .commandValidation,
                        faultCode: "malformedTraceCommand",
                        message: reason,
                        detail: "malformedTraceCommand"
                    )
                    return

                case "route":
                    setRouteFailure(
                        state: &state,
                        sourceNodeID: sourceNodeID,
                        eventCode: .routeRejectedMalformedCommand,
                        faultCategory: .commandValidation,
                        faultCode: "malformedRouteCommand",
                        message: reason,
                        detail: "malformedRouteCommand"
                    )
                    return

                case "host", "nslookup":
                    setHostResolveFailure(
                        state: &state,
                        sourceNodeID: sourceNodeID,
                        eventCode: .hostResolveRejectedMalformedCommand,
                        faultCategory: .commandValidation,
                        faultCode: "malformedHostResolveCommand",
                        message: reason,
                        detail: "malformedHostResolveCommand"
                    )
                    return

                case "help":
                    setRuntimeCommandFailure(
                        state: &state,
                        sourceNodeID: sourceNodeID,
                        eventCode: .runtimeHelpRejectedMalformedCommand,
                        faultCode: "malformedHelpCommand",
                        message: reason,
                        detail: "malformedHelpCommand"
                    )
                    return

                case "dhcp":
                    setDHCPFailure(
                        state: &state,
                        sourceNodeID: sourceNodeID,
                        eventCode: .dhcpLeaseRejectedMalformedCommand,
                        faultCategory: .commandValidation,
                        faultCode: "malformedDHCPCommand",
                        message: reason,
                        detail: "malformedDHCPCommand"
                    )
                    return

                case "dns":
                    setDNSFailure(
                        state: &state,
                        sourceNodeID: sourceNodeID,
                        eventCode: .dnsRecordRejectedMalformedCommand,
                        faultCategory: .commandValidation,
                        faultCode: "malformedDNSCommand",
                        message: reason,
                        detail: "malformedDNSCommand"
                    )
                    return

                case "ipconfig", "netstat", "arp", "arpsend", "tcpdump":
                    setRuntimeCommandFailure(
                        state: &state,
                        sourceNodeID: sourceNodeID,
                        eventCode: .runtimeNetworkInspectionCommandRejected,
                        faultCode: "malformedNetworkInspectionCommand",
                        message: reason,
                        detail: "malformedNetworkInspectionCommand;command=\(command ?? "")"
                    )
                    return

                case "cat", "cd", "cp", "copy", "del", "dir", "ls", "mkdir", "move", "mv", "pwd", "rm", "touch":
                    setFilesystemCommandFailure(
                        state: &state,
                        sourceNodeID: sourceNodeID,
                        eventCode: .runtimeFilesystemCommandRejectedMalformed,
                        faultCode: "malformedFilesystemCommand",
                        message: reason,
                        detail: "malformedFilesystemCommand;command=\(command ?? "")"
                    )
                    return

                default:
                    setPingFailure(
                        state: &state,
                        sourceNodeID: sourceNodeID,
                        eventCode: .pingRejectedMalformedCommand,
                        faultCategory: .commandValidation,
                        faultCode: "malformedPingCommand",
                        message: reason,
                        detail: "malformedPingCommand"
                    )
                    return
                }

            case let .success(runtimeCommand):
                switch runtimeCommand {
                case let .ping(target):
                    guard state.simulationPhase == .running else {
                        setPingFailure(
                            state: &state,
                            sourceNodeID: sourceNodeID,
                            eventCode: .pingRejectedSimulationStopped,
                            faultCategory: .runtimeFault,
                            faultCode: "pingWhileSimulationStopped",
                            message: "Ping commands require a running simulation",
                            detail: "phase=\(state.simulationPhase.rawValue)"
                        )
                        return
                    }

                    executePingCommand(
                        state: &state,
                        sourceNodeID: sourceNodeID,
                        target: target
                    )

                case let .trace(target):
                    guard state.simulationPhase == .running else {
                        setTraceFailure(
                            state: &state,
                            sourceNodeID: sourceNodeID,
                            eventCode: .traceRejectedSimulationStopped,
                            faultCategory: .runtimeFault,
                            faultCode: "traceWhileSimulationStopped",
                            message: "Trace commands require a running simulation",
                            detail: "phase=\(state.simulationPhase.rawValue)"
                        )
                        return
                    }

                    executeTraceCommand(
                        state: &state,
                        sourceNodeID: sourceNodeID,
                        target: target
                    )

                case let .route(target):
                    guard state.simulationPhase == .running else {
                        setRouteFailure(
                            state: &state,
                            sourceNodeID: sourceNodeID,
                            eventCode: .routeRejectedSimulationStopped,
                            faultCategory: .runtimeFault,
                            faultCode: "routeWhileSimulationStopped",
                            message: "Route commands require a running simulation",
                            detail: "phase=\(state.simulationPhase.rawValue)"
                        )
                        return
                    }

                    executeRouteCommand(
                        state: &state,
                        sourceNodeID: sourceNodeID,
                        target: target
                    )

                case let .hostResolve(hostname, commandToken):
                    guard state.simulationPhase == .running else {
                        setHostResolveFailure(
                            state: &state,
                            sourceNodeID: sourceNodeID,
                            eventCode: .hostResolveRejectedSimulationStopped,
                            faultCategory: .runtimeFault,
                            faultCode: "hostResolveWhileSimulationStopped",
                            message: "\(commandToken) commands require a running simulation",
                            detail: "phase=\(state.simulationPhase.rawValue),command=\(commandToken)"
                        )
                        return
                    }

                    executeHostResolveCommand(
                        state: &state,
                        sourceNodeID: sourceNodeID,
                        hostname: hostname,
                        commandToken: commandToken
                    )

                case let .help(commandToken):
                    executeHelpCommand(
                        state: &state,
                        sourceNodeID: sourceNodeID,
                        commandToken: commandToken
                    )

                case .ipconfig:
                    executeIPConfigCommand(state: &state, sourceNodeID: sourceNodeID)
                case .netstat:
                    executeNetstatCommand(state: &state, sourceNodeID: sourceNodeID)
                case let .arpList(filterIPAddress):
                    executeARPListCommand(state: &state, sourceNodeID: sourceNodeID, filterIPAddress: filterIPAddress)
                case let .arpDelete(ipAddress):
                    executeARPDeleteCommand(state: &state, sourceNodeID: sourceNodeID, ipAddress: ipAddress)
                case let .arpSend(senderIPAddress, targetIPAddress):
                    executeARPSendCommand(state: &state, sourceNodeID: sourceNodeID, senderIPAddress: senderIPAddress, targetIPAddress: targetIPAddress)
                case .tcpdump:
                    executeTCPDumpCommand(state: &state, sourceNodeID: sourceNodeID)

                case let .dhcpLease(ipAddress, subnetMask):
                    guard state.simulationPhase == .running else {
                        setDHCPFailure(
                            state: &state,
                            sourceNodeID: sourceNodeID,
                            eventCode: .dhcpLeaseRejectedSimulationStopped,
                            faultCategory: .runtimeFault,
                            faultCode: "dhcpWhileSimulationStopped",
                            message: "DHCP lease commands require a running simulation",
                            detail: "phase=\(state.simulationPhase.rawValue)"
                        )
                        return
                    }

                    executeDHCPLeaseCommand(
                        state: &state,
                        sourceNodeID: sourceNodeID,
                        ipAddress: ipAddress,
                        subnetMask: subnetMask
                    )

                case .dhcpRelease:
                    guard state.simulationPhase == .running else {
                        setDHCPFailure(
                            state: &state,
                            sourceNodeID: sourceNodeID,
                            eventCode: .dhcpLeaseRejectedSimulationStopped,
                            faultCategory: .runtimeFault,
                            faultCode: "dhcpWhileSimulationStopped",
                            message: "DHCP release commands require a running simulation",
                            detail: "phase=\(state.simulationPhase.rawValue)"
                        )
                        return
                    }

                    executeDHCPReleaseCommand(
                        state: &state,
                        sourceNodeID: sourceNodeID
                    )

                case let .dnsRegister(hostname, targetIPAddress):
                    guard state.simulationPhase == .running else {
                        setDNSFailure(
                            state: &state,
                            sourceNodeID: sourceNodeID,
                            eventCode: .dnsRecordRejectedSimulationStopped,
                            faultCategory: .runtimeFault,
                            faultCode: "dnsWhileSimulationStopped",
                            message: "DNS commands require a running simulation",
                            detail: "phase=\(state.simulationPhase.rawValue)"
                        )
                        return
                    }

                    executeDNSRegisterCommand(
                        state: &state,
                        sourceNodeID: sourceNodeID,
                        hostname: hostname,
                        targetIPAddress: targetIPAddress
                    )

                case let .dnsRemove(hostname):
                    guard state.simulationPhase == .running else {
                        setDNSFailure(
                            state: &state,
                            sourceNodeID: sourceNodeID,
                            eventCode: .dnsRecordRejectedSimulationStopped,
                            faultCategory: .runtimeFault,
                            faultCode: "dnsWhileSimulationStopped",
                            message: "DNS commands require a running simulation",
                            detail: "phase=\(state.simulationPhase.rawValue)"
                        )
                        return
                    }

                    executeDNSRemoveCommand(
                        state: &state,
                        sourceNodeID: sourceNodeID,
                        hostname: hostname
                    )

                case let .dnsResolve(hostname):
                    guard state.simulationPhase == .running else {
                        setDNSFailure(
                            state: &state,
                            sourceNodeID: sourceNodeID,
                            eventCode: .dnsResolveRejectedSimulationStopped,
                            faultCategory: .runtimeFault,
                            faultCode: "dnsWhileSimulationStopped",
                            message: "DNS commands require a running simulation",
                            detail: "phase=\(state.simulationPhase.rawValue)"
                        )
                        return
                    }

                    executeDNSResolveCommand(
                        state: &state,
                        sourceNodeID: sourceNodeID,
                        hostname: hostname
                    )
                case let .filesystemCat(path):
                    executeFilesystemCommand(state: &state, sourceNodeID: sourceNodeID, command: .cat(path))
                case let .filesystemCd(path):
                    executeFilesystemCommand(state: &state, sourceNodeID: sourceNodeID, command: .cd(path))
                case let .filesystemCopy(source, destination):
                    executeFilesystemCommand(state: &state, sourceNodeID: sourceNodeID, command: .copy(source, destination))
                case let .filesystemDelete(path):
                    executeFilesystemCommand(state: &state, sourceNodeID: sourceNodeID, command: .delete(path))
                case let .filesystemList(path):
                    executeFilesystemCommand(state: &state, sourceNodeID: sourceNodeID, command: .list(path))
                case let .filesystemMakeDirectory(path):
                    executeFilesystemCommand(state: &state, sourceNodeID: sourceNodeID, command: .makeDirectory(path))
                case let .filesystemMove(source, destination):
                    executeFilesystemCommand(state: &state, sourceNodeID: sourceNodeID, command: .move(source, destination))
                case .filesystemPrintWorkingDirectory:
                    executeFilesystemCommand(state: &state, sourceNodeID: sourceNodeID, command: .printWorkingDirectory)
                case let .filesystemTouch(path):
                    executeFilesystemCommand(state: &state, sourceNodeID: sourceNodeID, command: .touch(path))
                }
            }

        case let .moveSelectedNodes(delta):
            guard let delta else {
                state.lastValidationError = .malformedActionPayload
                return
            }

            guard delta != .zero else {
                return
            }

            for nodeID in state.selectedNodeIDs {
                state.graph.moveNode(withID: nodeID, delta: delta)
            }
            advancePersistenceRevision(state: &state)

        case let .panCanvas(delta):
            guard let delta, isFiniteSize(delta) else {
                state.lastValidationError = .malformedActionPayload
                return
            }

            state.viewport = state.viewport.panned(by: delta)
            advancePersistenceRevision(state: &state)

        case let .zoomCanvas(scaleDelta, anchor):
            guard let scaleDelta, isFiniteScalar(scaleDelta), scaleDelta > 0 else {
                state.lastValidationError = .malformedActionPayload
                return
            }

            if let anchor, !isFinitePoint(anchor) {
                state.lastValidationError = .malformedActionPayload
                return
            }

            state.viewport = state.viewport.zoomed(by: scaleDelta, anchor: anchor)
            advancePersistenceRevision(state: &state)

        case let .setInteractionMode(mode):
            state.lastInteractionMode = normalizedRuntimeValue(mode) ?? "none"

        case .dismissRecoveryNotice:
            state.dismissRecoveryNotice()

        case .dismissPersistenceError:
            state.dismissPersistenceError()
        }
    }


    private static func cleanupRuntimeProgram(
        _ program: TopologyRuntimeInstallableProgram,
        nodeID: UUID,
        state: inout TopologyEditorState
    ) {
        if state.runtimeActiveProgramByNodeID[nodeID] == program {
            state.runtimeActiveProgramByNodeID.removeValue(forKey: nodeID)
        }

        switch program {
        case .commandPrompt:
            state.runtimeWorkingDirectoryByNodeID.removeValue(forKey: nodeID)
        case .fileExplorer:
            state.runtimeFileExplorerSelectionByNodeID.removeValue(forKey: nodeID)
        case .imageViewer:
            state.runtimeImageViewerSelectionByNodeID.removeValue(forKey: nodeID)
        case .textEditor:
            state.runtimeTextEditorSelectionByNodeID.removeValue(forKey: nodeID)
            state.runtimeTextEditorDraftByNodeID.removeValue(forKey: nodeID)
        case .webServer:
            state.runtimeWebServerByNodeID.removeValue(forKey: nodeID)
            if let listenerSocketID = state.runtimeWebServerSocketIDByNodeID.removeValue(forKey: nodeID) {
                for acceptedSocketID in state.networkRuntime.acceptedTCPSocketIDs(listenerSocketID: listenerSocketID) {
                    _ = state.networkRuntime.closeTCPConnectionAndClean(socketID: acceptedSocketID)
                }
                state.networkRuntime.closeTCPSocket(socketID: listenerSocketID)
            }
            state.runtimeWebServerRequestLogsByNodeID.removeValue(forKey: nodeID)
        case .webBrowser:
            state.runtimeWebBrowserStateByNodeID.removeValue(forKey: nodeID)
        case .echoServer:
            state.runtimeEchoServerByNodeID.removeValue(forKey: nodeID)
            if let listenerSocketID = state.runtimeEchoServerSocketIDByNodeID.removeValue(forKey: nodeID) {
                for acceptedSocketID in state.networkRuntime.acceptedTCPSocketIDs(listenerSocketID: listenerSocketID) {
                    _ = state.networkRuntime.closeTCPConnectionAndClean(socketID: acceptedSocketID)
                }
                _ = state.networkRuntime.closeTCPConnectionAndClean(socketID: listenerSocketID)
            }
            if let udpSocketID = state.runtimeEchoServerUDPSocketIDByNodeID.removeValue(forKey: nodeID) {
                state.networkRuntime.closeSocket(socketID: udpSocketID)
            }
            state.runtimeEchoServerServiceStateByNodeID.removeValue(forKey: nodeID)
        case .simpleClient:
            if let socketID = state.runtimeSimpleClientByNodeID[nodeID]?.socketID {
                _ = state.networkRuntime.closeTCPConnectionAndClean(socketID: socketID)
                state.networkRuntime.closeSocket(socketID: socketID)
            }
            state.runtimeSimpleClientByNodeID.removeValue(forKey: nodeID)
        case .dnsServer:
            if state.runtimeDNSServerSocketIDByNodeID.removeValue(forKey: nodeID) != nil {
                state.networkRuntime.stopDNSServer(nodeID: nodeID)
            }
        case .dhcpServer:
            break
        case .firewall:
            if state.simulationPhase == .running {
                var inactiveConfiguration = state.runtimeFirewallConfigurationsByNodeID[nodeID] ?? TopologyFirewallConfiguration()
                inactiveConfiguration.isActive = false
                state.networkRuntime.setFirewallConfiguration(nodeID: nodeID, configuration: inactiveConfiguration)
            }
        case .emailClient:
            break
        case .emailServer:
            _ = state.stopRuntimeEmailServer(nodeID: nodeID)
        case .gnutella:
            _ = state.stopRuntimeGnutella(nodeID: nodeID)
        }
    }

    private static func removeDeviceState(nodeID: UUID, state: inout TopologyEditorState) {
        _ = state.stopRuntimeEmailServer(nodeID: nodeID)
        state.runtimeDeviceConfigurations.removeValue(forKey: nodeID)
        state.switchConfigurationsByNodeID.removeValue(forKey: nodeID)
        state.remoteLinkConfigurationsByNodeID.removeValue(forKey: nodeID)
        state.hostWirelessConfigurationsByNodeID.removeValue(forKey: nodeID)
        state.runtimeInterfaceConfigurations = state.runtimeInterfaceConfigurations.filter { $0.key.nodeID != nodeID }
        state.runtimeManualRoutesByNodeID.removeValue(forKey: nodeID)
        state.runtimeRIPEnabledByNodeID.removeValue(forKey: nodeID)
        state.runtimeDHCPClientConfigurationsByNodeID.removeValue(forKey: nodeID)
        state.runtimeDHCPServerConfigurationsByNodeID.removeValue(forKey: nodeID)
        state.runtimeFirewallConfigurationsByNodeID.removeValue(forKey: nodeID)
        state.runtimePortForwardingRowsByNodeID.removeValue(forKey: nodeID)
        state.runtimeDHCPLeaseByNodeID.removeValue(forKey: nodeID)
        state.runtimeDNSServerConfigurationsByNodeID.removeValue(forKey: nodeID)
        state.runtimeDNSServerSocketIDByNodeID.removeValue(forKey: nodeID)
        state.runtimeDNSCacheByNodeID.removeValue(forKey: nodeID)
        state.runtimeWebServerByNodeID.removeValue(forKey: nodeID)
        state.runtimeWebServerConfigurationsByNodeID.removeValue(forKey: nodeID)
        state.runtimeWebBrowserConfigurationsByNodeID.removeValue(forKey: nodeID)
        state.runtimeWebServerRequestLogsByNodeID.removeValue(forKey: nodeID)
        state.runtimeWebBrowserStateByNodeID.removeValue(forKey: nodeID)
        state.runtimeEmailClientConfigurationsByNodeID.removeValue(forKey: nodeID)
        state.runtimeEmailServerConfigurationsByNodeID.removeValue(forKey: nodeID)
        state.runtimeEmailClientStateByNodeID.removeValue(forKey: nodeID)
        state.runtimeEmailServerProcessesByNodeID.removeValue(forKey: nodeID)
        _ = state.stopRuntimeGnutella(nodeID: nodeID)
        state.runtimeGnutellaConfigurationsByNodeID.removeValue(forKey: nodeID)
        state.runtimeGnutellaSessionsByNodeID.removeValue(forKey: nodeID)
        state.runtimeGnutellaCoresByNodeID.removeValue(forKey: nodeID)
        state.runtimeGnutellaRestartEpochByNodeID.removeValue(forKey: nodeID)
        state.runtimeGnutellaFileStoresByNodeID.removeValue(forKey: nodeID)
        state.runtimeEchoServerByNodeID.removeValue(forKey: nodeID)
        state.runtimeWebServerSocketIDByNodeID.removeValue(forKey: nodeID)
        state.runtimeEchoServerSocketIDByNodeID.removeValue(forKey: nodeID)
        state.runtimeEchoServerUDPSocketIDByNodeID.removeValue(forKey: nodeID)
        state.runtimeEchoServerServiceStateByNodeID.removeValue(forKey: nodeID)
        state.runtimeSimpleClientByNodeID.removeValue(forKey: nodeID)
        state.runtimeInstalledProgramsByNodeID.removeValue(forKey: nodeID)
        state.runtimeActiveProgramByNodeID.removeValue(forKey: nodeID)
        state.runtimeInstalledProtocolApplicationIDsByNodeID.removeValue(forKey: nodeID)
        state.runtimeActiveProtocolApplicationIDByNodeID.removeValue(forKey: nodeID)
        state.runtimeProtocolApplicationClients = state.runtimeProtocolApplicationClients.filter { $0.key.nodeID != nodeID }
        state.runtimeProtocolApplicationServers = state.runtimeProtocolApplicationServers.filter { $0.key.nodeID != nodeID }
        state.runtimeConsoleEntriesByNodeID.removeValue(forKey: nodeID)
        state.runtimeWorkingDirectoryByNodeID.removeValue(forKey: nodeID)
        state.virtualFileSystemsByNodeID.removeValue(forKey: nodeID)
        state.runtimeFileExplorerSelectionByNodeID.removeValue(forKey: nodeID)
        state.runtimeImageViewerSelectionByNodeID.removeValue(forKey: nodeID)
        state.runtimeTextEditorSelectionByNodeID.removeValue(forKey: nodeID)
        state.runtimeTextEditorDraftByNodeID.removeValue(forKey: nodeID)
        if state.openedRuntimeDeviceID == nodeID {
            state.openedRuntimeDeviceID = nil
        }
    }

    private static func stopSimulationRuntime(state: inout TopologyEditorState) {
        // Synchronous application operations may have advanced the runtime after the
        // last UI pulse. Persist the authoritative time before stopping so the next
        // start cannot initialize the runtime clock backwards from a stale state tick.
        state.simulationTick = max(
            state.simulationTick,
            state.networkRuntime.state.currentTimeMilliseconds
        )
        state.resetRuntimeEmailTransientState()
        state.resetRuntimeGnutellaTransientState()
        state.networkRuntime.handle(.stop)
        state.simulationPhase = .stopped
        state.openedRuntimeDeviceID = nil
        state.runtimeActiveProgramByNodeID.removeAll()
        state.resetProtocolApplicationRuntime()
        state.runtimeDHCPLeaseByNodeID.removeAll()
        state.runtimeDNSServerSocketIDByNodeID.removeAll()
        state.runtimeDNSCacheByNodeID.removeAll()
        state.runtimeWebServerByNodeID.removeAll()
        state.runtimeWebServerRequestLogsByNodeID.removeAll()
        state.runtimeWebBrowserStateByNodeID.removeAll()
        state.runtimeEchoServerByNodeID.removeAll()
        state.runtimeWebServerSocketIDByNodeID.removeAll()
        state.runtimeEchoServerSocketIDByNodeID.removeAll()
        state.runtimeEchoServerUDPSocketIDByNodeID.removeAll()
        state.runtimeEchoServerServiceStateByNodeID.removeAll()
        state.runtimeSimpleClientByNodeID.removeAll()
    }

    private static func advancePersistenceRevision(state: inout TopologyEditorState) {
        let (nextRevision, overflowed) = state.persistenceRevision.addingReportingOverflow(1)
        state.persistenceRevision = overflowed ? UInt64.max : nextRevision
    }

    private static func recordRuntimeCompatibilityOperation(
        state: inout TopologyEditorState,
        nodeID: UUID,
        interfaceID: UUID? = nil,
        kind: TopologyNetworkRuntimeCompatibilityOperationKind,
        detail: String
    ) {
        state.networkRuntime.handle(
            .compatibilityOperation(
                TopologyNetworkRuntimeCompatibilityOperation(
                    kind: kind,
                    nodeID: nodeID,
                    interfaceID: interfaceID,
                    detail: detail
                )
            )
        )
    }
    private static func projectDHCPRuntimeState(state: inout TopologyEditorState) {
        for (nodeID, status) in state.networkRuntime.state.dhcpClientStatusesByNodeID {
            guard status.succeeded, let node = state.graph.node(withID: nodeID) else {
                state.runtimeDHCPLeaseByNodeID.removeValue(forKey: nodeID)
                continue
            }
            if node.kind.isPCClassEndpoint,
               let configuration = state.networkRuntime.state.topologySnapshot.deviceConfigurations[nodeID] {
                state.runtimeDHCPLeaseByNodeID[nodeID] = configuration
            } else if node.kind == .gateway,
                      let wanPortID = node.ports.first?.id,
                      let wan = state.networkRuntime.state.topologySnapshot.interfaceConfigurations[
                        TopologyRuntimeInterfaceKey(nodeID: nodeID, portID: wanPortID)
                      ] {
                let device = state.networkRuntime.state.topologySnapshot.deviceConfigurations[nodeID]
                state.runtimeDHCPLeaseByNodeID[nodeID] = TopologyRuntimeDeviceConfiguration(
                    ipAddress: wan.ipAddress,
                    subnetMask: wan.subnetMask,
                    defaultGateway: device?.defaultGateway ?? "",
                    dnsServer: device?.dnsServer ?? ""
                )
            }
        }
    }

    private static func recordRuntimeEvent(
        state: inout TopologyEditorState,
        code: TopologyRuntimeEventCode,
        detail: String? = nil
    ) {
        state.lastRuntimeEvent = TopologyRuntimeEvent(code: code, detail: detail)
    }

    private static func setEmailFailure(
        state: inout TopologyEditorState,
        nodeID: UUID,
        eventCode: TopologyRuntimeEventCode,
        faultCode: String,
        error: TopologyRuntimeEmailOperationError
    ) {
        state.lastRuntimeFault = TopologyRuntimeFault(
            category: .networkService,
            code: faultCode,
            message: error.localizedDescription
        )
        recordRuntimeEvent(state: &state, code: eventCode, detail: "node=\(nodeID.uuidString),reason=\(faultCode)")
        appendConsoleLine(state: &state, nodeID: nodeID, line: "Email operation failed: \(error.localizedDescription)")
    }

    private static func setGnutellaFailure(
        state: inout TopologyEditorState,
        nodeID: UUID,
        faultCode: String,
        error: Error
    ) {
        state.lastRuntimeFault = TopologyRuntimeFault(
            category: .networkService,
            code: faultCode,
            message: error.localizedDescription
        )
        recordRuntimeEvent(state: &state, code: .gnutellaRejected, detail: "node=\(nodeID.uuidString),reason=\(faultCode)")
        appendConsoleLine(state: &state, nodeID: nodeID, line: "Gnutella operation failed: \(error.localizedDescription)")
    }

    private static func validateProtocolApplicationContext(
        state: inout TopologyEditorState,
        nodeID: UUID?,
        definitionID: UUID?,
        expectedRole: TopologyProtocolApplicationRole,
        actionName: String
    ) -> (nodeID: UUID, definitionID: UUID)? {
        guard let nodeID, let definitionID else {
            rejectProtocolApplication(state: &state, code: "protocolActionMalformedPayload", detail: "action=\(actionName)")
            return nil
        }
        guard state.simulationPhase == .running,
              state.graph.node(withID: nodeID)?.kind.isPCClassEndpoint == true,
              state.openedRuntimeDeviceID == nodeID,
              state.runtimeInstalledProtocolApplicationIDsByNodeID[nodeID]?.contains(definitionID) == true,
              state.runtimeActiveProtocolApplicationIDByNodeID[nodeID] == definitionID,
              state.protocolApplicationDefinitionsByID[definitionID]?.role == expectedRole else {
            rejectProtocolApplication(state: &state, code: "protocolActionInvalidContext", detail: "action=\(actionName),node=\(nodeID.uuidString),definition=\(definitionID.uuidString)")
            return nil
        }
        return (nodeID, definitionID)
    }

    private static func rejectProtocolApplication(
        state: inout TopologyEditorState,
        code: String,
        detail: String? = nil
    ) {
        state.lastRuntimeFault = TopologyRuntimeFault(
            category: .commandValidation,
            code: code,
            message: detail ?? code
        )
        recordRuntimeEvent(state: &state, code: .protocolApplicationRuntimeRejected, detail: detail ?? code)
    }

    private static func setMalformedRuntimePayload(state: inout TopologyEditorState, reason: String) {
        state.lastRuntimeFault = TopologyRuntimeFault(
            category: .malformedRuntimePayload,
            code: "malformedRuntimePayload",
            message: reason
        )
        recordRuntimeEvent(
            state: &state,
            code: .simulationFaultRejectedMalformedPayload,
            detail: reason
        )
    }

    private static func setMalformedPingPayload(state: inout TopologyEditorState, detail: String) {
        let fault = TopologyRuntimeFault(
            category: .commandValidation,
            code: "malformedPingCommand",
            message: detail
        )
        state.lastPingFault = fault
        state.lastRuntimeFault = fault
        state.lastPingEvent = TopologyRuntimeEvent(code: .pingRejectedMalformedCommand, detail: detail)
        recordRuntimeEvent(state: &state, code: .pingRejectedMalformedCommand, detail: detail)
    }

    private static func setPingFailure(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        eventCode: TopologyRuntimeEventCode,
        faultCategory: TopologyRuntimeFaultCategory,
        faultCode: String,
        message: String,
        detail: String
    ) {
        let fault = TopologyRuntimeFault(
            category: faultCategory,
            code: faultCode,
            message: message
        )
        state.lastPingFault = fault
        state.lastRuntimeFault = fault
        state.lastPingEvent = TopologyRuntimeEvent(code: eventCode, detail: detail)
        recordRuntimeEvent(state: &state, code: eventCode, detail: detail)
        appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Ping failed: \(faultCode) — \(message)")
    }

    private static func setTraceFailure(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        eventCode: TopologyRuntimeEventCode,
        faultCategory: TopologyRuntimeFaultCategory,
        faultCode: String,
        message: String,
        detail: String
    ) {
        let fault = TopologyRuntimeFault(
            category: faultCategory,
            code: faultCode,
            message: message
        )
        state.lastRuntimeFault = fault
        recordRuntimeEvent(state: &state, code: eventCode, detail: detail)
        appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Trace failed: \(faultCode) — \(message)")
    }

    private static func setRouteFailure(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        eventCode: TopologyRuntimeEventCode,
        faultCategory: TopologyRuntimeFaultCategory,
        faultCode: String,
        message: String,
        detail: String
    ) {
        let fault = TopologyRuntimeFault(
            category: faultCategory,
            code: faultCode,
            message: message
        )
        state.lastRuntimeFault = fault
        recordRuntimeEvent(state: &state, code: eventCode, detail: detail)
        appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Route failed: \(faultCode) — \(message)")
    }

    private static func setHostResolveFailure(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        eventCode: TopologyRuntimeEventCode,
        faultCategory: TopologyRuntimeFaultCategory,
        faultCode: String,
        message: String,
        detail: String
    ) {
        let fault = TopologyRuntimeFault(
            category: faultCategory,
            code: faultCode,
            message: message
        )
        state.lastRuntimeFault = fault
        recordRuntimeEvent(state: &state, code: eventCode, detail: detail)
        appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Host lookup failed: \(faultCode) — \(message)")
    }

    private static func setDHCPFailure(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        eventCode: TopologyRuntimeEventCode,
        faultCategory: TopologyRuntimeFaultCategory,
        faultCode: String,
        message: String,
        detail: String
    ) {
        let fault = TopologyRuntimeFault(
            category: faultCategory,
            code: faultCode,
            message: message
        )
        state.lastRuntimeFault = fault
        recordRuntimeEvent(state: &state, code: eventCode, detail: detail)
        appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "DHCP failed: \(faultCode) — \(message)")
    }

    private static func setDNSFailure(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        eventCode: TopologyRuntimeEventCode,
        faultCategory: TopologyRuntimeFaultCategory,
        faultCode: String,
        message: String,
        detail: String
    ) {
        let fault = TopologyRuntimeFault(
            category: faultCategory,
            code: faultCode,
            message: message
        )
        state.lastRuntimeFault = fault
        recordRuntimeEvent(state: &state, code: eventCode, detail: detail)
        appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "DNS failed: \(faultCode) — \(message)")
    }

    private static func setWebServiceFailure(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        eventCode: TopologyRuntimeEventCode,
        faultCategory: TopologyRuntimeFaultCategory,
        faultCode: String,
        message: String,
        detail: String
    ) {
        let fault = TopologyRuntimeFault(
            category: faultCategory,
            code: faultCode,
            message: message
        )
        state.lastRuntimeFault = fault
        recordRuntimeEvent(state: &state, code: eventCode, detail: detail)
        appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Web Server failed: \(faultCode) — \(message)")
    }

    private static func recordWebBrowserNavigationFailure(
        state: inout TopologyEditorState,
        error: TopologyRuntimeHTTPError
    ) {
        let eventCode: TopologyRuntimeEventCode
        switch error {
        case .dnsFailure:
            eventCode = .webBrowserRejectedDNSFailure
        case .timeout:
            eventCode = .webBrowserRejectedTimeout
        case .unreachable, .serverNotRunning:
            eventCode = .webBrowserRejectedUnreachable
        case .invalidURL, .invalidPort, .unsupportedScheme, .missingHost, .invalidHost, .malformedRequest, .responseMissing:
            eventCode = .webBrowserRejectedMalformedURL
        }
        state.lastRuntimeFault = TopologyRuntimeFault(
            category: .networkService,
            code: "webBrowserNavigationFailed",
            message: error.localizedDescription
        )
        recordRuntimeEvent(state: &state, code: eventCode, detail: error.localizedDescription)
    }

    private static func setEchoServiceFailure(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        eventCode: TopologyRuntimeEventCode,
        faultCategory: TopologyRuntimeFaultCategory,
        faultCode: String,
        message: String,
        detail: String
    ) {
        let fault = TopologyRuntimeFault(
            category: faultCategory,
            code: faultCode,
            message: message
        )
        state.lastRuntimeFault = fault
        recordRuntimeEvent(state: &state, code: eventCode, detail: detail)
        appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Echo Server failed: \(faultCode) — \(message)")
    }

    private static func setRuntimeCommandFailure(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        eventCode: TopologyRuntimeEventCode,
        faultCode: String,
        message: String,
        detail: String
    ) {
        let fault = TopologyRuntimeFault(
            category: .commandValidation,
            code: faultCode,
            message: message
        )
        state.lastRuntimeFault = fault
        recordRuntimeEvent(state: &state, code: eventCode, detail: detail)
        appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Command failed: \(faultCode) — \(message)")
    }

    private static func saveRuntimeDeviceConfiguration(
        state: inout TopologyEditorState,
        nodeID: UUID?,
        ipAddress: String?,
        subnetMask: String?,
        defaultGateway: String?,
        actionName: String
    ) {
        guard let nodeID else {
            setMalformedRuntimePayload(
                state: &state,
                reason: "\(actionName) requires nodeID"
            )
            return
        }

        guard let node = state.graph.node(withID: nodeID) else {
            state.lastValidationError = .nodeNotFound
            state.lastRuntimeFault = TopologyRuntimeFault(
                category: .networkConfiguration,
                code: "runtimeDeviceNotFound",
                message: "Cannot save IP configuration for unknown node \(nodeID.uuidString)"
            )
            recordRuntimeEvent(
                state: &state,
                code: .runtimeDeviceIPRejectedInvalidConfiguration,
                detail: "runtimeDeviceNotFound"
            )
            return
        }

        guard node.kind.isPCClassEndpoint else {
            state.lastRuntimeFault = TopologyRuntimeFault(
                category: .networkConfiguration,
                code: "ipConfigurationUnsupportedForNodeKind",
                message: "Only PCs and Notebooks can be configured with runtime IP addresses"
            )
            recordRuntimeEvent(
                state: &state,
                code: .runtimeDeviceIPRejectedInvalidConfiguration,
                detail: "ipConfigurationUnsupportedForNodeKind"
            )
            return
        }

        guard let normalizedIPAddress = normalizedIPv4Address(ipAddress) else {
            state.lastRuntimeFault = TopologyRuntimeFault(
                category: .networkConfiguration,
                code: "invalidIPv4Address",
                message: "IP address must use four octets between 0 and 255"
            )
            recordRuntimeEvent(
                state: &state,
                code: .runtimeDeviceIPRejectedInvalidConfiguration,
                detail: "invalidIPv4Address"
            )
            return
        }

        guard let normalizedSubnetMask = normalizedSubnetMask(subnetMask) else {
            state.lastRuntimeFault = TopologyRuntimeFault(
                category: .networkConfiguration,
                code: "invalidSubnetMask",
                message: "Subnet mask must be a contiguous IPv4 mask"
            )
            recordRuntimeEvent(
                state: &state,
                code: .runtimeDeviceIPRejectedInvalidConfiguration,
                detail: "invalidSubnetMask"
            )
            return
        }

        let normalizedDefaultGateway: String
        if normalizedRuntimeValue(defaultGateway) == nil {
            normalizedDefaultGateway = ""
        } else if let gateway = normalizedIPv4Address(defaultGateway) {
            normalizedDefaultGateway = gateway
        } else {
            state.lastRuntimeFault = TopologyRuntimeFault(
                category: .networkConfiguration,
                code: "invalidDefaultGateway",
                message: "Default gateway must be blank or a valid IPv4 address"
            )
            recordRuntimeEvent(
                state: &state,
                code: .runtimeDeviceIPRejectedInvalidConfiguration,
                detail: "invalidDefaultGateway"
            )
            return
        }

        let retainedDNSServer = state.runtimeDeviceConfigurations[nodeID]?.dnsServer ?? ""
        let savedConfiguration = TopologyRuntimeDeviceConfiguration(
            ipAddress: normalizedIPAddress,
            subnetMask: normalizedSubnetMask,
            defaultGateway: normalizedDefaultGateway,
            dnsServer: retainedDNSServer
        )
        state.runtimeDeviceConfigurations[nodeID] = savedConfiguration
        state.networkRuntime.updateDeviceConfiguration(
            nodeID: nodeID,
            configuration: savedConfiguration
        )
        state.runtimeDNSCacheByNodeID.removeValue(forKey: nodeID)
        state.lastRuntimeFault = nil
        advancePersistenceRevision(state: &state)
        recordRuntimeEvent(
            state: &state,
            code: .runtimeDeviceIPSaved,
            detail: "node=\(nodeID.uuidString),ip=\(normalizedIPAddress),subnet=\(normalizedSubnetMask),gateway=\(normalizedDefaultGateway)"
        )
    }

    private static func executePingCommand(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        target: RuntimeCommandTarget
    ) {
        guard let sourceConfiguration = state.runtimeDeviceConfigurations[sourceNodeID] else {
            setPingFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .pingRejectedInvalidSourceConfiguration,
                faultCategory: .networkConfiguration,
                faultCode: "sourceConfigurationMissing",
                message: "Configure source IP and subnet before pinging",
                detail: "sourceConfigurationMissing"
            )
            return
        }

        let targetIPAddress: String
        let targetHostname: String?

        switch target {
        case let .ipAddress(ipAddress):
            targetIPAddress = ipAddress
            targetHostname = nil

        case let .hostname(hostname):
            let resolution = state.resolveRuntimeHostname(nodeID: sourceNodeID, hostname: hostname)
            guard case let .success(record, _, _) = resolution else {
                let failure = dnsResolutionFailureDescriptor(resolution, hostname: hostname)
                setPingFailure(
                    state: &state, sourceNodeID: sourceNodeID,
                    eventCode: .pingRejectedUnknownTarget, faultCategory: .networkService,
                    faultCode: failure.faultCode, message: failure.message, detail: failure.detail
                )
                return
            }
            targetIPAddress = record.targetIPAddress
            targetHostname = hostname
        }

        let targetNodeIDs = runtimeNodeIDs(
            configuredWithIPAddress: targetIPAddress,
            state: state
        )

        guard targetNodeIDs.count == 1, let targetNodeID = targetNodeIDs.first else {
            setPingFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .pingRejectedUnknownTarget,
                faultCategory: .networkRouting,
                faultCode: "pingTargetUnknown",
                message: "No unique node is configured with target \(targetIPAddress)",
                detail: "pingTargetUnknown"
            )
            return
        }

        guard state.graph.containsNode(id: targetNodeID) else {
            setPingFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .pingRejectedUnknownTarget,
                faultCategory: .networkRouting,
                faultCode: "pingTargetUnknown",
                message: "Target node is unavailable in topology",
                detail: "pingTargetUnknown"
            )
            return
        }

        guard let targetConfiguration = compatibilityDeviceConfiguration(
            nodeID: targetNodeID,
            ipAddress: targetIPAddress,
            state: state
        ) else {
            setPingFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .pingRejectedUnknownTarget,
                faultCategory: .networkRouting,
                faultCode: "pingTargetUnknown",
                message: "Target node has no compatible IPv4 interface",
                detail: "pingTargetUnknown"
            )
            return
        }
        let compatibilityRoute: RuntimeResolvedRoute
        switch TopologyNetworkRuntimeCompatibilityRouteResolver.resolve(
            state: state,
            sourceNodeID: sourceNodeID,
            sourceConfiguration: sourceConfiguration,
            targetNodeID: targetNodeID,
            targetConfiguration: targetConfiguration,
            requiresReturnPath: true
        ) {
        case let .success(route):
            compatibilityRoute = route

        case let .failure(failure):
            let eventCode: TopologyRuntimeEventCode = failure.kind == .topologyUnreachable
                ? .pingRejectedTopologyUnreachable
                : .pingRejectedSubnetMismatch
            setPingFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: eventCode,
                faultCategory: .networkRouting,
                faultCode: failure.faultCode,
                message: failure.message,
                detail: failure.detail
            )
            return
        }

        let deliveryResult = state.networkRuntime.sendICMPEcho(
            fromNodeID: sourceNodeID,
            targetIPAddress: targetIPAddress
        )
        state.simulationTick = state.networkRuntime.state.currentTimeMilliseconds

        let requestPacketIdentity: UInt64
        switch deliveryResult {
        case let .delivered(packetIdentity, receivingNodeID):
            guard receivingNodeID == sourceNodeID else {
                setPingFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .pingRejectedTopologyUnreachable,
                    faultCategory: .networkRouting,
                    faultCode: "pingReplyDestinationMismatch",
                    message: "ICMP echo reply was delivered to an unexpected node",
                    detail: "pingReplyDestinationMismatch;expected=\(sourceNodeID.uuidString);actual=\(receivingNodeID.uuidString)"
                )
                return
            }
            requestPacketIdentity = packetIdentity

        case let .icmpError(_, responderNodeID, kind):
            setPingFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .pingRejectedTopologyUnreachable,
                faultCategory: .networkRouting,
                faultCode: "pingICMPError",
                message: "ICMP echo failed with \(kind.rawValue) from \(responderNodeID.uuidString)",
                detail: "pingICMPError;kind=\(kind.rawValue);responder=\(responderNodeID.uuidString)"
            )
            return

        case let .dropped(_, responderNodeID):
            setPingFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .pingRejectedTopologyUnreachable,
                faultCategory: .networkRouting,
                faultCode: "pingResponseDropped",
                message: "ICMP echo did not receive a reply",
                detail: "pingResponseDropped;responder=\(responderNodeID?.uuidString ?? "none")"
            )
            return
        }

        let pathNodeIDs = state.networkRuntime.tracedNodePath(packetIdentity: requestPacketIdentity)
        guard pathNodeIDs == compatibilityRoute.pathNodeIDs else {
            setPingFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .pingRejectedTopologyUnreachable,
                faultCategory: .networkRouting,
                faultCode: "pingResponderPathIncomplete",
                message: "ICMP packet trace did not cover the validated route",
                detail: "pingResponderPathIncomplete;expected=\(compatibilityRoute.pathNodeIDs.map(\.uuidString).joined(separator: "->"));actual=\(pathNodeIDs.map(\.uuidString).joined(separator: "->"))"
            )
            return
        }
        let hopCount = max(0, pathNodeIDs.count - 1)
        let latencyMilliseconds = deterministicLatencyMilliseconds(forHopCount: hopCount)
        state.lastPingFault = nil
        state.lastRuntimeFault = nil

        let successDetail = routeDetail(
            command: "ping",
            sourceNodeID: sourceNodeID,
            targetNodeID: targetNodeID,
            targetIPAddress: targetIPAddress,
            targetHostname: targetHostname,
            hopCount: hopCount,
            latencyMilliseconds: latencyMilliseconds,
            pathNodeIDs: pathNodeIDs
        )
        state.lastPingEvent = TopologyRuntimeEvent(code: .pingSucceeded, detail: successDetail)
        recordRuntimeEvent(state: &state, code: .pingSucceeded, detail: successDetail)
        appendSuccessfulPingTranscript(
            state: &state,
            sourceNodeID: sourceNodeID,
            targetIPAddress: targetIPAddress,
            targetHostname: targetHostname,
            hopCount: hopCount,
            baseLatencyMilliseconds: latencyMilliseconds
        )
    }

    private static func executeTraceCommand(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        target: RuntimeCommandTarget
    ) {
        guard let sourceConfiguration = state.runtimeDeviceConfigurations[sourceNodeID] else {
            setTraceFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .traceRejectedInvalidSourceConfiguration,
                faultCategory: .networkConfiguration,
                faultCode: "sourceConfigurationMissing",
                message: "Configure source IP and subnet before tracing",
                detail: "sourceConfigurationMissing"
            )
            return
        }

        let targetIPAddress: String
        let targetHostname: String?

        switch target {
        case let .ipAddress(ipAddress):
            targetIPAddress = ipAddress
            targetHostname = nil

        case let .hostname(hostname):
            let resolution = state.resolveRuntimeHostname(nodeID: sourceNodeID, hostname: hostname)
            guard case let .success(record, _, _) = resolution else {
                let failure = dnsResolutionFailureDescriptor(resolution, hostname: hostname)
                setTraceFailure(
                    state: &state, sourceNodeID: sourceNodeID,
                    eventCode: .traceRejectedUnknownTarget, faultCategory: .networkService,
                    faultCode: failure.faultCode, message: failure.message, detail: failure.detail
                )
                return
            }
            targetIPAddress = record.targetIPAddress
            targetHostname = hostname
        }

        let targetNodeIDs = runtimeNodeIDs(
            configuredWithIPAddress: targetIPAddress,
            state: state
        )

        guard targetNodeIDs.count == 1, let targetNodeID = targetNodeIDs.first else {
            setTraceFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .traceRejectedUnknownTarget,
                faultCategory: .networkRouting,
                faultCode: "traceTargetUnknown",
                message: "No unique node is configured with target \(targetIPAddress)",
                detail: "traceTargetUnknown"
            )
            return
        }

        guard state.graph.containsNode(id: targetNodeID) else {
            setTraceFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .traceRejectedUnknownTarget,
                faultCategory: .networkRouting,
                faultCode: "traceTargetUnknown",
                message: "Target node is unavailable in topology",
                detail: "traceTargetUnknown"
            )
            return
        }

        guard let targetConfiguration = compatibilityDeviceConfiguration(
            nodeID: targetNodeID,
            ipAddress: targetIPAddress,
            state: state
        ) else {
            setTraceFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .traceRejectedUnknownTarget,
                faultCategory: .networkRouting,
                faultCode: "traceTargetUnknown",
                message: "Target node has no compatible IPv4 interface",
                detail: "traceTargetUnknown"
            )
            return
        }
        let compatibilityRoute: RuntimeResolvedRoute
        switch TopologyNetworkRuntimeCompatibilityRouteResolver.resolve(
            state: state,
            sourceNodeID: sourceNodeID,
            sourceConfiguration: sourceConfiguration,
            targetNodeID: targetNodeID,
            targetConfiguration: targetConfiguration,
            requiresReturnPath: true
        ) {
        case let .success(route):
            compatibilityRoute = route

        case let .failure(failure):
            let eventCode: TopologyRuntimeEventCode = failure.kind == .topologyUnreachable
                ? .traceRejectedTopologyUnreachable
                : .traceRejectedSubnetMismatch
            setTraceFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: eventCode,
                faultCategory: .networkRouting,
                faultCode: failure.faultCode,
                message: failure.message,
                detail: failure.detail
            )
            return
        }

        let observations = state.networkRuntime.traceICMPEcho(
            fromNodeID: sourceNodeID,
            targetIPAddress: targetIPAddress
        )
        let expectedKinds = Array(
            repeating: TopologyICMPMessageKind.timeExceeded,
            count: compatibilityRoute.forwardingNodeIDs.count
        ) + [.echoReply]
        let expectedSequences = (1...expectedKinds.count).map { UInt16($0) }
        let expectedResponderNodeIDs = compatibilityRoute.forwardingNodeIDs + [targetNodeID]
        let actualResponderNodeIDs = observations.compactMap { observation -> UUID? in
            let matchingNodeIDs = runtimeNodeIDs(
                configuredWithIPAddress: observation.packet.senderIPAddress,
                state: state
            )
            return matchingNodeIDs.count == 1 ? matchingNodeIDs[0] : nil
        }
        guard observations.map(\.message.kind) == expectedKinds,
              observations.map(\.message.sequenceNumber) == expectedSequences,
              actualResponderNodeIDs.count == observations.count,
              actualResponderNodeIDs == expectedResponderNodeIDs
        else {
            setTraceFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .traceRejectedTopologyUnreachable,
                faultCategory: .networkRouting,
                faultCode: "traceResponderPathInvalid",
                message: "Traceroute responders did not match the validated forwarding path",
                detail: "traceResponderPathInvalid;expected=\(expectedResponderNodeIDs.map(\.uuidString).joined(separator: "->"));actual=\(actualResponderNodeIDs.map(\.uuidString).joined(separator: "->"));observations=\(observations.count)"
            )
            return
        }
        let pathNodeIDs = compatibilityRoute.pathNodeIDs
        let hopCount = max(0, pathNodeIDs.count - 1)
        let latencyMilliseconds = deterministicLatencyMilliseconds(forHopCount: hopCount)
        state.lastRuntimeFault = nil

        let detail = routeDetail(
            command: "trace",
            sourceNodeID: sourceNodeID,
            targetNodeID: targetNodeID,
            targetIPAddress: targetIPAddress,
            targetHostname: targetHostname,
            hopCount: hopCount,
            latencyMilliseconds: latencyMilliseconds,
            pathNodeIDs: pathNodeIDs
        )
        recordRuntimeEvent(state: &state, code: .traceSucceeded, detail: detail)
        appendConsoleLine(
            state: &state,
            nodeID: sourceNodeID,
            line: "Trace to \(targetIPAddress) succeeded (hops=\(hopCount), latencyMs=\(latencyMilliseconds))"
        )
        appendConsoleLine(
            state: &state,
            nodeID: sourceNodeID,
            line: "Path: \(pathNodeIDs.map(\.uuidString).joined(separator: " -> "))"
        )
    }

    private static func executeRouteCommand(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        target: RuntimeCommandTarget
    ) {
        guard let sourceConfiguration = state.runtimeDeviceConfigurations[sourceNodeID] else {
            setRouteFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .routeRejectedInvalidSourceConfiguration,
                faultCategory: .networkConfiguration,
                faultCode: "sourceConfigurationMissing",
                message: "Configure source IP and subnet before routing",
                detail: "sourceConfigurationMissing"
            )
            return
        }

        let targetIPAddress: String
        let targetHostname: String?

        switch target {
        case let .ipAddress(ipAddress):
            targetIPAddress = ipAddress
            targetHostname = nil

        case let .hostname(hostname):
            let resolution = state.resolveRuntimeHostname(nodeID: sourceNodeID, hostname: hostname)
            guard case let .success(record, _, _) = resolution else {
                let failure = dnsResolutionFailureDescriptor(resolution, hostname: hostname)
                setRouteFailure(
                    state: &state, sourceNodeID: sourceNodeID,
                    eventCode: .routeRejectedUnknownTarget, faultCategory: .networkService,
                    faultCode: failure.faultCode, message: failure.message, detail: failure.detail
                )
                return
            }
            targetIPAddress = record.targetIPAddress
            targetHostname = hostname
        }

        let targetNodeIDs = runtimeNodeIDs(
            configuredWithIPAddress: targetIPAddress,
            state: state
        )

        guard targetNodeIDs.count == 1, let targetNodeID = targetNodeIDs.first else {
            setRouteFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .routeRejectedUnknownTarget,
                faultCategory: .networkRouting,
                faultCode: "routeTargetUnknown",
                message: "No unique node is configured with target \(targetIPAddress)",
                detail: "routeTargetUnknown"
            )
            return
        }

        guard state.graph.containsNode(id: targetNodeID),
              let targetConfiguration = state.runtimeDeviceConfigurations[targetNodeID] else {
            setRouteFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .routeRejectedUnknownTarget,
                faultCategory: .networkRouting,
                faultCode: "routeTargetUnknown",
                message: "Target node is unavailable in topology",
                detail: "routeTargetUnknown"
            )
            return
        }

        let resolvedRoute: RuntimeResolvedRoute
        switch TopologyNetworkRuntimeCompatibilityRouteResolver.resolve(
            state: state,
            sourceNodeID: sourceNodeID,
            sourceConfiguration: sourceConfiguration,
            targetNodeID: targetNodeID,
            targetConfiguration: targetConfiguration,
            requiresReturnPath: false
        ) {
        case let .success(route):
            resolvedRoute = route

        case let .failure(failure):
            let eventCode: TopologyRuntimeEventCode = failure.kind == .topologyUnreachable
                ? .routeRejectedTopologyUnreachable
                : .routeRejectedSubnetMismatch
            setRouteFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: eventCode,
                faultCategory: .networkRouting,
                faultCode: failure.faultCode,
                message: failure.message,
                detail: failure.detail
            )
            return
        }

        let pathNodeIDs = resolvedRoute.pathNodeIDs
        let hopCount = max(0, pathNodeIDs.count - 1)
        let latencyMilliseconds = deterministicLatencyMilliseconds(forHopCount: hopCount)

        state.lastRuntimeFault = nil

        let detail = routeDetail(
            command: "route",
            sourceNodeID: sourceNodeID,
            targetNodeID: targetNodeID,
            targetIPAddress: targetIPAddress,
            targetHostname: targetHostname,
            hopCount: hopCount,
            latencyMilliseconds: latencyMilliseconds,
            pathNodeIDs: pathNodeIDs
        )
        recordRuntimeEvent(state: &state, code: .routeSucceeded, detail: detail)
        appendConsoleLine(
            state: &state,
            nodeID: sourceNodeID,
            line: "Route to \(targetIPAddress) succeeded (hops=\(hopCount), latencyMs=\(latencyMilliseconds))"
        )
        appendConsoleLine(
            state: &state,
            nodeID: sourceNodeID,
            line: "Route path: \(pathNodeIDs.map(\.uuidString).joined(separator: " -> "))"
        )
    }

    private static func executeHostResolveCommand(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        hostname: String,
        commandToken: String
    ) {
        let normalizedHost = hostname.lowercased()
        let resolution = state.resolveRuntimeHostname(nodeID: sourceNodeID, hostname: normalizedHost)
        guard case let .success(record, serverIPAddress, cached) = resolution else {
            let failure = dnsResolutionFailureDescriptor(resolution, hostname: normalizedHost)
            setHostResolveFailure(
                state: &state, sourceNodeID: sourceNodeID,
                eventCode: .hostResolveRejectedUnknownHost, faultCategory: .networkService,
                faultCode: failure.faultCode, message: failure.message,
                detail: "command=\(commandToken),\(failure.detail)"
            )
            return
        }

        state.lastRuntimeFault = nil
        let detail = "command=\(commandToken),host=\(record.hostname),ip=\(record.targetIPAddress),server=\(serverIPAddress),cache=\(cached ? "hit" : "miss")"
        recordRuntimeEvent(state: &state, code: .hostResolveSucceeded, detail: detail)
        appendConsoleLine(
            state: &state, nodeID: sourceNodeID,
            line: "\(commandToken) resolved \(record.hostname) -> \(record.targetIPAddress) via \(serverIPAddress) [cache \(cached ? "hit" : "miss")]"
        )
    }

    private static func requireNetworkInspectionSimulation(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        command: String
    ) -> Bool {
        guard state.simulationPhase == .running else {
            setRuntimeCommandFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .runtimeNetworkInspectionCommandRejected,
                faultCode: "networkInspectionWhileSimulationStopped",
                message: "\(command) commands require a running simulation",
                detail: "command=\(command);phase=\(state.simulationPhase.rawValue)"
            )
            return false
        }
        return true
    }

    private static func completeNetworkInspectionCommand(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        command: String,
        detail: String
    ) {
        state.lastRuntimeFault = nil
        recordRuntimeEvent(
            state: &state,
            code: .runtimeNetworkInspectionCommandExecuted,
            detail: "command=\(command);\(detail)"
        )
    }

    private static func executeIPConfigCommand(
        state: inout TopologyEditorState,
        sourceNodeID: UUID
    ) {
        guard requireNetworkInspectionSimulation(state: &state, sourceNodeID: sourceNodeID, command: "ipconfig") else { return }
        let interfaces = state.networkRuntime.networkInterfaces(nodeID: sourceNodeID)
        appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "IP configuration:")
        if interfaces.isEmpty {
            if let configuration = state.runtimeDeviceConfigurations[sourceNodeID] {
                appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "IP address: \(configuration.ipAddress)")
                appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Subnet mask: \(configuration.subnetMask)")
                appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Default gateway: \(configuration.defaultGateway.isEmpty ? "-" : configuration.defaultGateway)")
                appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "DNS server: \(configuration.dnsServer.isEmpty ? "-" : configuration.dnsServer)")
            } else {
                appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "No configured interfaces")
            }
        } else {
            for (index, interface) in interfaces.enumerated() {
                appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Interface \(index + 1): \(interface.ipAddress) / \(interface.subnetMask)")
                appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "  MAC address: \(interface.macAddress)")
                appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "  Default gateway: \(interface.defaultGateway.isEmpty ? "-" : interface.defaultGateway)")
                if index == 0 {
                    let dnsServer = state.runtimeDeviceConfigurations[sourceNodeID]?.dnsServer ?? ""
                    appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "  DNS server: \(dnsServer.isEmpty ? "-" : dnsServer)")
                }
            }
        }
        completeNetworkInspectionCommand(state: &state, sourceNodeID: sourceNodeID, command: "ipconfig", detail: "interfaces=\(interfaces.count)")
    }

    private static func executeNetstatCommand(
        state: inout TopologyEditorState,
        sourceNodeID: UUID
    ) {
        guard requireNetworkInspectionSimulation(state: &state, sourceNodeID: sourceNodeID, command: "netstat") else { return }
        appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Proto Local Address Foreign Address State")
        let sockets = state.networkRuntime.socketRecords(nodeID: sourceNodeID)
        for socket in sockets {
            let protocolName = socket.protocolKind.rawValue.uppercased()
            let localAddress = "\(socket.localIPAddress ?? "0.0.0.0"):\(socket.localPort)"
            let remoteAddress = "\(socket.remoteIPAddress ?? "-"):\(socket.remotePort.map(String.init) ?? "-")"
            let stateName = socket.tcpState?.rawValue ?? (socket.protocolKind == .udp ? "OPEN" : "UNKNOWN")
            appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "\(protocolName) \(localAddress) \(remoteAddress) \(stateName)")
        }
        if sockets.isEmpty { appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "(no active sockets)") }
        completeNetworkInspectionCommand(state: &state, sourceNodeID: sourceNodeID, command: "netstat", detail: "sockets=\(sockets.count)")
    }

    private static func executeARPListCommand(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        filterIPAddress: String?
    ) {
        guard requireNetworkInspectionSimulation(state: &state, sourceNodeID: sourceNodeID, command: "arp") else { return }
        let entries = state.networkRuntime.arpCacheEntries(nodeID: sourceNodeID).filter {
            filterIPAddress == nil || $0.ipAddress == filterIPAddress
        }
        appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Internet Address       Physical Address")
        for entry in entries {
            appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "\(entry.ipAddress) \(entry.macAddress)")
        }
        if entries.isEmpty { appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "(no ARP entries)") }
        completeNetworkInspectionCommand(state: &state, sourceNodeID: sourceNodeID, command: "arp", detail: "entries=\(entries.count);filter=\(filterIPAddress ?? "all")")
    }

    private static func executeARPDeleteCommand(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        ipAddress: String?
    ) {
        guard requireNetworkInspectionSimulation(state: &state, sourceNodeID: sourceNodeID, command: "arp") else { return }
        if let ipAddress {
            state.networkRuntime.removeARPCacheEntry(nodeID: sourceNodeID, ipAddress: ipAddress)
            appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Deleted ARP entry for \(ipAddress)")
        } else {
            state.networkRuntime.clearARPCache(nodeID: sourceNodeID)
            appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Cleared ARP cache")
        }
        completeNetworkInspectionCommand(state: &state, sourceNodeID: sourceNodeID, command: "arp", detail: "delete=\(ipAddress ?? "all")")
    }

    private static func executeARPSendCommand(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        senderIPAddress: String,
        targetIPAddress: String
    ) {
        guard requireNetworkInspectionSimulation(state: &state, sourceNodeID: sourceNodeID, command: "arpsend") else { return }
        let sent = state.networkRuntime.sendARPReply(
            fromNodeID: sourceNodeID,
            senderIPAddress: senderIPAddress,
            targetIPAddress: targetIPAddress
        )
        guard sent else {
            setRuntimeCommandFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .runtimeNetworkInspectionCommandRejected,
                faultCode: "arpSendUnavailable",
                message: "Cannot send ARP reply because no configured interface or resolvable target is available",
                detail: "command=arpsend;sender=\(senderIPAddress);target=\(targetIPAddress)"
            )
            return
        }
        appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "ARP reply sent: \(senderIPAddress) -> \(targetIPAddress)")
        completeNetworkInspectionCommand(state: &state, sourceNodeID: sourceNodeID, command: "arpsend", detail: "sender=\(senderIPAddress);target=\(targetIPAddress)")
    }

    private static func executeTCPDumpCommand(
        state: inout TopologyEditorState,
        sourceNodeID: UUID
    ) {
        guard requireNetworkInspectionSimulation(state: &state, sourceNodeID: sourceNodeID, command: "tcpdump") else { return }
        let rows = state.networkRuntime.packetCaptureMessageRows(nodeID: sourceNodeID).suffix(60)
        var outputLines = ["tcpdump snapshot:"]
        outputLines.append(contentsOf: rows.map { row in
            "\(row.timeMilliseconds) \(row.protocolName) \(row.source) > \(row.destination) \(row.detail)"
        })
        if rows.isEmpty { outputLines.append("(no captured packets)") }
        appendConsoleLine(
            state: &state,
            nodeID: sourceNodeID,
            line: outputLines.joined(separator: "\n")
        )
        completeNetworkInspectionCommand(state: &state, sourceNodeID: sourceNodeID, command: "tcpdump", detail: "rows=\(rows.count)")
    }

    private static func executeHelpCommand(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        commandToken: String?
    ) {
        state.lastRuntimeFault = nil
        recordRuntimeEvent(
            state: &state,
            code: .runtimeHelpDisplayed,
            detail: "command=help;target=\(commandToken ?? "all")"
        )

        appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "CMD help:")
        if let commandToken {
            appendConsoleLine(
                state: &state,
                nodeID: sourceNodeID,
                line: TopologyRuntimeCommandCatalog.usage(for: commandToken) ?? "Unknown command: \(commandToken)"
            )
        } else {
            TopologyRuntimeCommandCatalog.helpLines.forEach { line in
                appendConsoleLine(state: &state, nodeID: sourceNodeID, line: line)
            }
        }
    }

    private static func executeDHCPLeaseCommand(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        ipAddress: String,
        subnetMask: String
    ) {
        guard state.graph.containsNode(id: sourceNodeID) else {
            setDHCPFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .dhcpLeaseRejectedInvalidConfiguration,
                faultCategory: .networkConfiguration,
                faultCode: "dhcpSourceNodeNotFound",
                message: "Cannot assign DHCP lease for unknown source node",
                detail: "dhcpSourceNodeNotFound"
            )
            return
        }

        let configuration = TopologyRuntimeDeviceConfiguration(
            ipAddress: ipAddress,
            subnetMask: subnetMask
        )

        state.runtimeDeviceConfigurations[sourceNodeID] = configuration
        state.runtimeDHCPLeaseByNodeID[sourceNodeID] = configuration
        state.lastRuntimeFault = nil
        advancePersistenceRevision(state: &state)

        let detail = "node=\(sourceNodeID.uuidString),ip=\(ipAddress),subnet=\(subnetMask)"
        recordRuntimeEvent(state: &state, code: .dhcpLeaseAssigned, detail: detail)
        appendConsoleLine(
            state: &state,
            nodeID: sourceNodeID,
            line: "DHCP lease assigned: \(ipAddress)/\(subnetMask)"
        )
    }

    private static func executeDHCPReleaseCommand(
        state: inout TopologyEditorState,
        sourceNodeID: UUID
    ) {
        let hadLease = state.runtimeDHCPLeaseByNodeID.removeValue(forKey: sourceNodeID) != nil
        let hadConfiguration = state.runtimeDeviceConfigurations.removeValue(forKey: sourceNodeID) != nil

        guard hadLease || hadConfiguration else {
            setDHCPFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .dhcpLeaseRejectedMissingLease,
                faultCategory: .networkService,
                faultCode: "dhcpLeaseMissing",
                message: "No DHCP lease is active for this node",
                detail: "dhcpLeaseMissing"
            )
            return
        }

        state.lastRuntimeFault = nil
        advancePersistenceRevision(state: &state)

        let detail = "node=\(sourceNodeID.uuidString)"
        recordRuntimeEvent(state: &state, code: .dhcpLeaseReleased, detail: detail)
        appendConsoleLine(
            state: &state,
            nodeID: sourceNodeID,
            line: "DHCP lease released"
        )
    }

    private static func executeDNSRegisterCommand(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        hostname: String,
        targetIPAddress: String
    ) {
        guard state.runtimeInstalledProgramsByNodeID[sourceNodeID]?.contains(.dnsServer) == true else {
            setDNSFailure(
                state: &state, sourceNodeID: sourceNodeID,
                eventCode: .dnsServerRejectedInvalidConfiguration,
                faultCategory: .networkService, faultCode: "dnsServerNotInstalled",
                message: "Install DNS Server on this device before editing records",
                detail: "dnsServerNotInstalled"
            )
            return
        }
        let normalizedHost = hostname.lowercased()
        let record = TopologyRuntimeDNSRecord(hostname: normalizedHost, targetIPAddress: targetIPAddress)
        let previousConfiguration = state.runtimeDNSServerConfigurationsByNodeID[sourceNodeID]
        var configuration = previousConfiguration ?? TopologyRuntimeDNSServerConfiguration()
        configuration.recordsByHostname[normalizedHost] = record
        state.runtimeDNSServerConfigurationsByNodeID[sourceNodeID] = configuration
        do {
            try state.mirrorRuntimeDNSConfigurationToHostsFile(nodeID: sourceNodeID)
        } catch {
            state.runtimeDNSServerConfigurationsByNodeID[sourceNodeID] = previousConfiguration
            setDNSFailure(
                state: &state, sourceNodeID: sourceNodeID,
                eventCode: .dnsServerRejectedInvalidConfiguration,
                faultCategory: .runtimeFault, faultCode: "dnsHostsFileWriteFailed",
                message: "DNS records could not be synchronized with /dns/hosts",
                detail: "dnsHostsFileWriteFailed"
            )
            return
        }
        state.invalidateRuntimeDNSCache(hostname: normalizedHost)
        state.lastRuntimeFault = nil
        advancePersistenceRevision(state: &state)

        let detail = "serverNode=\(sourceNodeID.uuidString),host=\(normalizedHost),ip=\(targetIPAddress)"
        recordRuntimeEvent(state: &state, code: .dnsRecordRegistered, detail: detail)
        appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "DNS record registered: \(normalizedHost) -> \(targetIPAddress)")
    }

    private static func executeDNSRemoveCommand(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        hostname: String
    ) {
        let normalizedHost = hostname.lowercased()
        let previousConfiguration = state.runtimeDNSServerConfigurationsByNodeID[sourceNodeID]
        guard var configuration = previousConfiguration,
              configuration.recordsByHostname.removeValue(forKey: normalizedHost) != nil
        else {
            setDNSFailure(
                state: &state, sourceNodeID: sourceNodeID,
                eventCode: .dnsRecordRejectedUnknownHost, faultCategory: .networkService,
                faultCode: "dnsUnknownHost",
                message: "No DNS record exists for host '\(normalizedHost)' on this server",
                detail: "dnsUnknownHost"
            )
            return
        }
        state.runtimeDNSServerConfigurationsByNodeID[sourceNodeID] = configuration
        do {
            try state.mirrorRuntimeDNSConfigurationToHostsFile(nodeID: sourceNodeID)
        } catch {
            state.runtimeDNSServerConfigurationsByNodeID[sourceNodeID] = previousConfiguration
            setDNSFailure(
                state: &state, sourceNodeID: sourceNodeID,
                eventCode: .dnsServerRejectedInvalidConfiguration,
                faultCategory: .runtimeFault, faultCode: "dnsHostsFileWriteFailed",
                message: "DNS records could not be synchronized with /dns/hosts",
                detail: "dnsHostsFileWriteFailed"
            )
            return
        }
        state.invalidateRuntimeDNSCache(hostname: normalizedHost)
        state.lastRuntimeFault = nil
        advancePersistenceRevision(state: &state)

        let detail = "serverNode=\(sourceNodeID.uuidString),host=\(normalizedHost)"
        recordRuntimeEvent(state: &state, code: .dnsRecordRemoved, detail: detail)
        appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "DNS record removed: \(normalizedHost)")
    }

    private static func executeDNSResolveCommand(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        hostname: String
    ) {
        let normalizedHost = hostname.lowercased()
        let resolution = state.resolveRuntimeHostname(nodeID: sourceNodeID, hostname: normalizedHost)
        switch resolution {
        case let .success(record, serverIPAddress, cached):
            state.lastRuntimeFault = nil
            let eventCode: TopologyRuntimeEventCode = cached ? .dnsResolveCacheHit : .dnsResolveSucceeded
            let detail = "host=\(record.hostname),ip=\(record.targetIPAddress),server=\(serverIPAddress),cache=\(cached ? "hit" : "miss")"
            recordRuntimeEvent(state: &state, code: eventCode, detail: detail)
            appendConsoleLine(
                state: &state, nodeID: sourceNodeID,
                line: "DNS resolved \(record.hostname) -> \(record.targetIPAddress) via \(serverIPAddress) [cache \(cached ? "hit" : "miss")]"
            )

        case let .nxdomain(_, serverIPAddress, cached):
            setDNSFailure(
                state: &state, sourceNodeID: sourceNodeID,
                eventCode: .dnsResolveRejectedUnknownHost, faultCategory: .networkService,
                faultCode: "dnsNXDOMAIN",
                message: "DNS server \(serverIPAddress) returned NXDOMAIN for '\(normalizedHost)'",
                detail: "dnsNXDOMAIN,cache=\(cached ? "hit" : "miss")"
            )

        case .unreachable, .timeout, .missingServerConfiguration, .simulationStopped:
            let failure = dnsResolutionFailureDescriptor(resolution, hostname: normalizedHost)
            let eventCode: TopologyRuntimeEventCode
            switch resolution {
            case .unreachable: eventCode = .dnsResolveRejectedUnreachable
            case .timeout: eventCode = .dnsResolveRejectedTimeout
            case .missingServerConfiguration: eventCode = .dnsResolveRejectedMissingServerConfiguration
            case .simulationStopped: eventCode = .dnsResolveRejectedSimulationStopped
            case .success, .nxdomain: eventCode = .dnsResolveRejectedUnknownHost
            }
            setDNSFailure(
                state: &state, sourceNodeID: sourceNodeID, eventCode: eventCode,
                faultCategory: .networkService, faultCode: failure.faultCode,
                message: failure.message, detail: failure.detail
            )
        }
    }

    private static func dnsResolutionFailureDescriptor(
        _ result: TopologyRuntimeDNSResolutionResult,
        hostname: String
    ) -> (faultCode: String, message: String, detail: String) {
        switch result {
        case .success:
            return ("dnsUnexpectedSuccess", "DNS unexpectedly succeeded for '\(hostname)'", "dnsUnexpectedSuccess")
        case let .nxdomain(_, serverIPAddress, _):
            return ("dnsNXDOMAIN", "DNS server \(serverIPAddress) returned NXDOMAIN for '\(hostname)'", "dnsNXDOMAIN")
        case let .unreachable(serverIPAddress):
            return ("dnsServerUnreachable", "Configured DNS server \(serverIPAddress) is unreachable", "dnsServerUnreachable")
        case let .timeout(serverIPAddress):
            return ("dnsTimeout", "DNS request to \(serverIPAddress) timed out", "dnsTimeout")
        case .missingServerConfiguration:
            return ("dnsServerMissing", "Configure a DNS server IPv4 address before resolving hostnames", "dnsServerMissing")
        case .simulationStopped:
            return ("dnsWhileSimulationStopped", "DNS resolution requires a running simulation", "dnsWhileSimulationStopped")
        }
    }

    private static func compatibilityDeviceConfiguration(
        nodeID: UUID,
        ipAddress: String,
        state: TopologyEditorState
    ) -> TopologyRuntimeDeviceConfiguration? {
        if let configuration = state.runtimeDeviceConfigurations[nodeID], configuration.ipAddress == ipAddress {
            return configuration
        }
        guard let interface = state.networkRuntime.networkInterfaces(nodeID: nodeID)
            .first(where: { $0.ipAddress == ipAddress }) else {
            return nil
        }
        return TopologyRuntimeDeviceConfiguration(
            ipAddress: interface.ipAddress,
            subnetMask: interface.subnetMask,
            defaultGateway: interface.defaultGateway
        )
    }
    private static func runtimeNodeIDs(
        configuredWithIPAddress ipAddress: String,
        state: TopologyEditorState
    ) -> [UUID] {
        state.networkRuntime.state.topologySnapshot.nodes.compactMap { node in
            let hasAddress = state.networkRuntime.networkInterfaces(nodeID: node.id)
                .contains { $0.ipAddress == ipAddress }
            return hasAddress ? node.id : nil
        }
        .sorted { $0.uuidString < $1.uuidString }
    }
    private static func routeDetail(
        command: String,
        sourceNodeID: UUID,
        targetNodeID: UUID,
        targetIPAddress: String,
        targetHostname: String? = nil,
        hopCount: Int,
        latencyMilliseconds: Int,
        pathNodeIDs: [UUID]
    ) -> String {
        let hostSegment = targetHostname.map { ",targetHost=\($0)" } ?? ""
        return "command=\(command),source=\(sourceNodeID.uuidString),target=\(targetNodeID.uuidString),targetIP=\(targetIPAddress)\(hostSegment),hops=\(hopCount),latencyMs=\(latencyMilliseconds),path=\(pathNodeIDs.map(\.uuidString).joined(separator: "->"))"
    }

    private static func deterministicLatencyMilliseconds(forHopCount hopCount: Int) -> Int {
        max(1, 2 + (hopCount * 4))
    }

    private static func appendSuccessfulPingTranscript(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        targetIPAddress: String,
        targetHostname: String?,
        hopCount: Int,
        baseLatencyMilliseconds: Int
    ) {
        let displayTarget = targetHostname ?? targetIPAddress
        let replySource = targetHostname.map { "\($0) (\(targetIPAddress))" } ?? targetIPAddress
        let ttl = max(1, 64 - hopCount)
        let sampleTimes = [
            baseLatencyMilliseconds,
            baseLatencyMilliseconds + 1,
            max(1, baseLatencyMilliseconds - 1),
            baseLatencyMilliseconds,
        ]

        appendConsoleLine(
            state: &state,
            nodeID: sourceNodeID,
            line: "PING \(displayTarget) (\(targetIPAddress)) 56(84) bytes of data."
        )
        for (index, milliseconds) in sampleTimes.enumerated() {
            appendConsoleLine(
                state: &state,
                nodeID: sourceNodeID,
                line: "64 bytes from \(replySource): icmp_seq=\(index + 1) ttl=\(ttl) time=\(formatPingMilliseconds(Double(milliseconds))) ms"
            )
        }

        let minimum = sampleTimes.min() ?? baseLatencyMilliseconds
        let maximum = sampleTimes.max() ?? baseLatencyMilliseconds
        let average = Double(sampleTimes.reduce(0, +)) / Double(sampleTimes.count)
        let variance = sampleTimes.reduce(0.0) { partialResult, milliseconds in
            let difference = Double(milliseconds) - average
            return partialResult + (difference * difference)
        } / Double(sampleTimes.count)
        let meanDeviation = variance.squareRoot()

        appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "")
        appendConsoleLine(
            state: &state,
            nodeID: sourceNodeID,
            line: "--- \(displayTarget) ping statistics ---"
        )
        appendConsoleLine(
            state: &state,
            nodeID: sourceNodeID,
            line: "4 packets transmitted, 4 received, 0% packet loss, time 3000ms"
        )
        appendConsoleLine(
            state: &state,
            nodeID: sourceNodeID,
            line: "rtt min/avg/max/mdev = \(formatPingMilliseconds(Double(minimum)))/\(formatPingMilliseconds(average))/\(formatPingMilliseconds(Double(maximum)))/\(formatPingMilliseconds(meanDeviation)) ms"
        )
    }

    private static func formatPingMilliseconds(_ milliseconds: Double) -> String {
        String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            milliseconds
        )
    }

    private static func appendConsoleLine(state: inout TopologyEditorState, nodeID: UUID, line: String) {
        var entries = state.runtimeConsoleEntriesByNodeID[nodeID] ?? []
        entries.append(line)

        if entries.count > maxRuntimeConsoleEntriesPerDevice {
            entries.removeFirst(entries.count - maxRuntimeConsoleEntriesPerDevice)
        }

        state.runtimeConsoleEntriesByNodeID[nodeID] = entries
    }

    private static func seedRuntimeDesktopDefaults(state: inout TopologyEditorState) -> Int {
        let pcNodeIDs = state.graph.nodes
            .filter { $0.kind.isPCClassEndpoint }
            .map(\.id)

        guard !pcNodeIDs.isEmpty else {
            return 0
        }

        var seededCount = 0

        for nodeID in pcNodeIDs {
            var installedPrograms = state.runtimeInstalledProgramsByNodeID[nodeID] ?? []
            if installedPrograms.insert(.commandPrompt).inserted {
                seededCount += 1
            }
            state.runtimeInstalledProgramsByNodeID[nodeID] = installedPrograms
            let hadFileSystem = state.virtualFileSystemsByNodeID[nodeID] != nil
            var fileSystem = state.virtualFileSystemsByNodeID[nodeID] ?? .defaultForDevice()
            _ = fileSystem.upgradeLegacyDefaultImages()
            state.virtualFileSystemsByNodeID[nodeID] = fileSystem
            if !hadFileSystem {
                seededCount += 1
            }
        }

        return seededCount
    }

    private static func seedDesktopSuiteProgramDefaults(
        state: inout TopologyEditorState,
        nodeID: UUID,
        program: TopologyRuntimeInstallableProgram
    ) {
        let fileSystem = state.virtualFileSystemsByNodeID[nodeID] ?? .defaultForDevice()
        state.virtualFileSystemsByNodeID[nodeID] = fileSystem
        let files = fileSystem.allEntries().filter { $0.content.isFile }
        let images = files.filter { $0.content.isImage }
        let textFiles = files.filter {
            if case .text = $0.content { return true }
            return false
        }

        switch program {
        case .fileExplorer:
            if state.runtimeFileExplorerSelectionByNodeID[nodeID].flatMap({ fileSystem.contains($0) ? $0 : nil }) == nil {
                state.runtimeFileExplorerSelectionByNodeID[nodeID] = files.first?.path
            }

        case .imageViewer:
            if state.runtimeImageViewerSelectionByNodeID[nodeID].flatMap({ fileSystem.contains($0) ? $0 : nil }) == nil {
                state.runtimeImageViewerSelectionByNodeID[nodeID] = images.first?.path
            }

        case .textEditor:
            let previousSelectedPath = state.runtimeTextEditorSelectionByNodeID[nodeID]
            let selectedPath = previousSelectedPath
                .flatMap { path in (try? fileSystem.textFile(at: path)) == nil ? nil : path }
                ?? textFiles.first?.path
            state.runtimeTextEditorSelectionByNodeID[nodeID] = selectedPath
            if previousSelectedPath != selectedPath || state.runtimeTextEditorDraftByNodeID[nodeID] == nil {
                if let selectedPath, let text = try? fileSystem.textFile(at: selectedPath) {
                    state.runtimeTextEditorDraftByNodeID[nodeID] = text
                } else {
                    state.runtimeTextEditorDraftByNodeID.removeValue(forKey: nodeID)
                }
            }

        case .commandPrompt, .webServer, .webBrowser, .echoServer, .simpleClient, .dnsServer, .dhcpServer, .firewall, .emailClient, .emailServer, .gnutella:
            break
        }
    }

    private static func normalizedSSID(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines), !normalized.isEmpty else {
            return nil
        }
        guard normalized.unicodeScalars.allSatisfy({ (UInt32(0x20)...UInt32(0x7e)).contains($0.value) }) else {
            return nil
        }
        return normalized
    }

    private static func normalizedRuntimeValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizedServicePort(_ value: String?) -> Int? {
        guard let normalizedValue = normalizedRuntimeValue(value),
              let port = Int(normalizedValue),
              (1...65_535).contains(port)
        else {
            return nil
        }

        return port
    }

    private static func validateDesktopSuiteAppContext(
        state: inout TopologyEditorState,
        nodeID: UUID?,
        expectedProgram: TopologyRuntimeInstallableProgram,
        actionName: String
    ) -> UUID? {
        guard let nodeID else {
            setDesktopSuiteMalformedPayload(
                state: &state,
                actionName: actionName,
                reason: "missingNodeID",
                message: "\(actionName) requires nodeID"
            )
            return nil
        }

        guard state.graph.containsNode(id: nodeID) else {
            state.lastValidationError = .nodeNotFound
            state.lastRuntimeFault = TopologyRuntimeFault(
                category: .networkConfiguration,
                code: "runtimeDeviceNotFound",
                message: "Cannot perform \(actionName) for unknown node \(nodeID.uuidString)"
            )
            recordRuntimeEvent(
                state: &state,
                code: .runtimeDesktopAppActionRejectedInvalidContext,
                detail: "action=\(actionName),reason=runtimeDeviceNotFound"
            )
            return nil
        }

        guard state.simulationPhase == .running else {
            state.lastRuntimeFault = TopologyRuntimeFault(
                category: .commandValidation,
                code: "runtimeDesktopAppSimulationNotRunning",
                message: "Desktop application actions require a running simulation"
            )
            recordRuntimeEvent(
                state: &state,
                code: .runtimeDesktopAppActionRejectedInvalidContext,
                detail: "action=\(actionName),reason=simulationNotRunning,program=\(expectedProgram.rawValue)"
            )
            return nil
        }

        guard state.openedRuntimeDeviceID == nodeID else {
            state.lastRuntimeFault = TopologyRuntimeFault(
                category: .commandValidation,
                code: "runtimeDesktopAppNodeNotOpened",
                message: "Open node \(nodeID.uuidString) before using \(expectedProgram.rawValue) controls"
            )
            recordRuntimeEvent(
                state: &state,
                code: .runtimeDesktopAppActionRejectedInvalidContext,
                detail: "action=\(actionName),reason=nodeNotOpened,program=\(expectedProgram.rawValue)"
            )
            return nil
        }

        guard state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(expectedProgram) == true else {
            state.lastRuntimeFault = TopologyRuntimeFault(
                category: .commandValidation,
                code: "runtimeProgramNotInstalled",
                message: "Program \(expectedProgram.rawValue) is not installed on node \(nodeID.uuidString)"
            )
            recordRuntimeEvent(
                state: &state,
                code: .runtimeDesktopAppActionRejectedInvalidContext,
                detail: "action=\(actionName),reason=programNotInstalled,program=\(expectedProgram.rawValue)"
            )
            return nil
        }

        guard state.runtimeActiveProgramByNodeID[nodeID] == expectedProgram else {
            state.lastRuntimeFault = TopologyRuntimeFault(
                category: .commandValidation,
                code: "runtimeProgramNotActive",
                message: "Launch \(expectedProgram.rawValue) from desktop before using app controls"
            )
            recordRuntimeEvent(
                state: &state,
                code: .runtimeDesktopAppActionRejectedInvalidContext,
                detail: "action=\(actionName),reason=programNotActive,program=\(expectedProgram.rawValue)"
            )
            return nil
        }

        return nodeID
    }

    private static func setDesktopSuiteMalformedPayload(
        state: inout TopologyEditorState,
        actionName: String,
        reason: String,
        message: String
    ) {
        state.lastRuntimeFault = TopologyRuntimeFault(
            category: .malformedRuntimePayload,
            code: "runtimeDesktopAppActionMalformedPayload",
            message: message
        )
        recordRuntimeEvent(
            state: &state,
            code: .runtimeDesktopAppActionRejectedMalformedPayload,
            detail: "action=\(actionName),reason=\(reason)"
        )
    }

    private static func setDesktopSuiteUnknownTarget(
        state: inout TopologyEditorState,
        actionName: String,
        reason: String,
        target: String
    ) {
        state.lastRuntimeFault = TopologyRuntimeFault(
            category: .commandValidation,
            code: "runtimeDesktopAppUnknownTarget",
            message: "Unknown desktop application target for \(actionName)"
        )
        recordRuntimeEvent(
            state: &state,
            code: .runtimeDesktopAppActionRejectedUnknownTarget,
            detail: "action=\(actionName),reason=\(reason),targetLength=\(target.count)"
        )
    }

    private static func resolveVirtualFilePath(
        _ rawPath: String?,
        in fileSystem: TopologyVirtualFileSystem
    ) -> String? {
        guard let rawPath,
              !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        if rawPath.hasPrefix("/") || rawPath.hasPrefix("\\") {
            return try? TopologyVirtualFileSystem.normalizedAbsolutePath(rawPath)
        }
        let matches = fileSystem.allEntries().filter { $0.name == rawPath }
        return matches.count == 1 ? matches[0].path : nil
    }

    private static func normalizedRequiredVirtualFilePath(_ rawPath: String?) throws -> String {
        guard let rawPath,
              !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw TopologyVirtualFileSystemError.invalidPathComponent(rawPath ?? "")
        }
        return try TopologyVirtualFileSystem.normalizedAbsolutePath(rawPath)
    }

    private static func mutateVirtualFileSystem(
        state: inout TopologyEditorState,
        nodeID: UUID?,
        actionName: String,
        operation: (inout TopologyVirtualFileSystem) throws -> String
    ) {
        guard let sourceNodeID = validateDesktopSuiteAppContext(
            state: &state,
            nodeID: nodeID,
            expectedProgram: .fileExplorer,
            actionName: actionName
        ) else { return }

        do {
            var fileSystem = state.virtualFileSystemsByNodeID[sourceNodeID] ?? .defaultForDevice()
            let detail = try operation(&fileSystem)
            var candidateFileSystems = state.virtualFileSystemsByNodeID
            candidateFileSystems[sourceNodeID] = fileSystem
            try TopologyVirtualFileSystem.validateProjectQuotas(candidateFileSystems)
            state.virtualFileSystemsByNodeID = candidateFileSystems
            state.synchronizeRuntimeDNSConfigurationFromHostsFile(nodeID: sourceNodeID, clearWhenMissing: true)
            sanitizeVirtualFileSelections(state: &state, nodeID: sourceNodeID, fileSystem: fileSystem)
            state.lastRuntimeFault = nil
            advancePersistenceRevision(state: &state)
            recordRuntimeEvent(
                state: &state,
                code: .runtimeVirtualFileSystemChanged,
                detail: "node=\(sourceNodeID.uuidString),action=\(actionName),item=\(detail)"
            )
            appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Filesystem: \(actionName) \(detail)")
        } catch {
            setVirtualFileSystemFailure(state: &state, actionName: actionName, detail: error.localizedDescription)
        }
    }

    private static func sanitizeVirtualFileSelections(
        state: inout TopologyEditorState,
        nodeID: UUID,
        fileSystem: TopologyVirtualFileSystem
    ) {
        let files = fileSystem.allEntries().filter { $0.content.isFile }
        let images = files.filter { $0.content.isImage }
        let textFiles = files.filter {
            if case .text = $0.content { return true }
            return false
        }
        if state.runtimeFileExplorerSelectionByNodeID[nodeID].flatMap({ fileSystem.contains($0) ? $0 : nil }) == nil {
            state.runtimeFileExplorerSelectionByNodeID[nodeID] = files.first?.path
        }
        let selectedImagePath = state.runtimeImageViewerSelectionByNodeID[nodeID]
        if selectedImagePath == nil || !images.contains(where: { $0.path == selectedImagePath }) {
            state.runtimeImageViewerSelectionByNodeID[nodeID] = images.first?.path
        }
        let previousTextPath = state.runtimeTextEditorSelectionByNodeID[nodeID]
        let selectedTextPath = previousTextPath
            .flatMap { path in (try? fileSystem.textFile(at: path)) == nil ? nil : path }
            ?? textFiles.first?.path
        state.runtimeTextEditorSelectionByNodeID[nodeID] = selectedTextPath
        if previousTextPath != selectedTextPath || state.runtimeTextEditorDraftByNodeID[nodeID] == nil {
            if let selectedTextPath, let text = try? fileSystem.textFile(at: selectedTextPath) {
                state.runtimeTextEditorDraftByNodeID[nodeID] = text
            } else {
                state.runtimeTextEditorDraftByNodeID.removeValue(forKey: nodeID)
            }
        }
    }

    private static func setVirtualFileSystemFailure(
        state: inout TopologyEditorState,
        actionName: String,
        detail: String
    ) {
        state.lastRuntimeFault = TopologyRuntimeFault(
            category: .commandValidation,
            code: "virtualFileSystemOperationRejected",
            message: detail
        )
        recordRuntimeEvent(
            state: &state,
            code: .runtimeVirtualFileSystemOperationRejected,
            detail: "action=\(actionName),reason=\(detail)"
        )
    }

    private static func validateServiceAppContext(
        state: inout TopologyEditorState,
        nodeID: UUID?,
        expectedProgram: TopologyRuntimeInstallableProgram,
        actionName: String
    ) -> UUID? {
        guard let nodeID else {
            state.lastRuntimeFault = TopologyRuntimeFault(
                category: .malformedRuntimePayload,
                code: "runtimeServiceActionMalformedPayload",
                message: "\(actionName) requires nodeID"
            )
            recordRuntimeEvent(
                state: &state,
                code: .runtimeServiceActionRejectedMalformedPayload,
                detail: "action=\(actionName),reason=missingNodeID"
            )
            return nil
        }

        guard state.graph.containsNode(id: nodeID) else {
            state.lastValidationError = .nodeNotFound
            state.lastRuntimeFault = TopologyRuntimeFault(
                category: .networkConfiguration,
                code: "runtimeDeviceNotFound",
                message: "Cannot perform \(actionName) for unknown node \(nodeID.uuidString)"
            )
            recordRuntimeEvent(
                state: &state,
                code: .runtimeServiceActionRejectedInvalidContext,
                detail: "action=\(actionName),reason=runtimeDeviceNotFound"
            )
            return nil
        }

        if state.simulationPhase != .running {
            return nodeID
        }

        guard state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(expectedProgram) == true else {
            state.lastRuntimeFault = TopologyRuntimeFault(
                category: .commandValidation,
                code: "runtimeProgramNotInstalled",
                message: "Program \(expectedProgram.rawValue) is not installed on node \(nodeID.uuidString)"
            )
            recordRuntimeEvent(
                state: &state,
                code: .runtimeServiceActionRejectedInvalidContext,
                detail: "action=\(actionName),reason=programNotInstalled,program=\(expectedProgram.rawValue)"
            )
            return nil
        }

        guard state.runtimeActiveProgramByNodeID[nodeID] == expectedProgram else {
            state.lastRuntimeFault = TopologyRuntimeFault(
                category: .commandValidation,
                code: "runtimeProgramNotActive",
                message: "Launch \(expectedProgram.rawValue) from desktop before using service controls"
            )
            recordRuntimeEvent(
                state: &state,
                code: .runtimeServiceActionRejectedInvalidContext,
                detail: "action=\(actionName),reason=programNotActive,program=\(expectedProgram.rawValue)"
            )
            return nil
        }

        return nodeID
    }

    private enum FilesystemCommand {
        case cat(String)
        case cd(String?)
        case copy(String, String)
        case delete(String)
        case list(String?)
        case makeDirectory(String)
        case move(String, String)
        case printWorkingDirectory
        case touch(String)
    }

    private static func executeFilesystemCommand(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        command: FilesystemCommand
    ) {
        guard state.graph.containsNode(id: sourceNodeID) else {
            setFilesystemCommandFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .runtimeFilesystemCommandRejectedPath,
                faultCode: "filesystemDeviceNotFound",
                message: "The terminal device does not exist.",
                detail: "filesystemDeviceNotFound"
            )
            return
        }

        guard state.graph.node(withID: sourceNodeID)?.kind.isPCClassEndpoint == true else {
            setFilesystemCommandFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .runtimeFilesystemCommandRejectedContext,
                faultCode: "filesystemCommandUnsupportedDevice",
                message: "Command Prompt filesystem commands require a PC or Notebook.",
                detail: "filesystemCommandContextRejected;reason=unsupportedDevice"
            )
            return
        }

        guard validateDesktopSuiteAppContext(
            state: &state,
            nodeID: sourceNodeID,
            expectedProgram: .commandPrompt,
            actionName: "executeFilesystemCommand"
        ) != nil else { return }

        guard let existingFileSystem = state.virtualFileSystemsByNodeID[sourceNodeID] else {
            setFilesystemCommandFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .runtimeFilesystemCommandRejectedContext,
                faultCode: "filesystemCommandMissingDeviceFilesystem",
                message: "The device filesystem is unavailable.",
                detail: "filesystemCommandContextRejected;reason=missingDeviceFilesystem"
            )
            return
        }

        var fileSystem = existingFileSystem
        let currentDirectory = terminalWorkingDirectory(state: state, nodeID: sourceNodeID, fileSystem: fileSystem)
        state.runtimeWorkingDirectoryByNodeID[sourceNodeID] = currentDirectory

        do {
            switch command {
            case let .cat(rawPath):
                let path = try terminalPath(rawPath, currentDirectory: currentDirectory)
                let entry = try fileSystem.entry(at: path)
                guard entry.content.isFile else {
                    throw TopologyVirtualFileSystemError.expectedFile(entry.path)
                }
                let rendered = terminalCatOutput(for: entry.content)
                rendered.lines.forEach { line in
                    appendConsoleLine(state: &state, nodeID: sourceNodeID, line: line)
                }
                finishFilesystemCommand(
                    state: &state,
                    nodeID: sourceNodeID,
                    detail: "command=cat,path=\(path)"
                )

            case let .cd(rawPath):
                guard let rawPath else {
                    appendConsoleLine(state: &state, nodeID: sourceNodeID, line: currentDirectory)
                    finishFilesystemCommand(state: &state, nodeID: sourceNodeID, detail: "command=cd,path=\(currentDirectory)")
                    return
                }
                let path = try terminalPath(rawPath, currentDirectory: currentDirectory)
                let entry = try fileSystem.entry(at: path)
                guard entry.content.isDirectory else {
                    throw TopologyVirtualFileSystemError.expectedDirectory(path)
                }
                state.runtimeWorkingDirectoryByNodeID[sourceNodeID] = entry.path
                appendConsoleLine(state: &state, nodeID: sourceNodeID, line: entry.path)
                finishFilesystemCommand(state: &state, nodeID: sourceNodeID, detail: "command=cd,path=\(entry.path)")

            case let .copy(rawSource, rawDestination):
                let source = try terminalPath(rawSource, currentDirectory: currentDirectory)
                let destination = try terminalPath(rawDestination, currentDirectory: currentDirectory)
                let sourceEntry = try fileSystem.entry(at: source)
                guard sourceEntry.content.isFile else {
                    throw TopologyVirtualFileSystemError.expectedFile(source)
                }
                try fileSystem.copyItem(at: source, to: destination, overwrite: true)
                commitTerminalFileSystemMutation(
                    state: &state,
                    nodeID: sourceNodeID,
                    fileSystem: fileSystem,
                    output: "File copied successfully: \(source) -> \(destination)",
                    detail: "command=cp,source=\(source),destination=\(destination)"
                )

            case let .delete(rawPath):
                let path = try terminalPath(rawPath, currentDirectory: currentDirectory)
                let entry = try fileSystem.entry(at: path)
                guard entry.content.isFile else {
                    throw TopologyVirtualFileSystemError.expectedFile(path)
                }
                try fileSystem.deleteItem(at: path)
                commitTerminalFileSystemMutation(
                    state: &state,
                    nodeID: sourceNodeID,
                    fileSystem: fileSystem,
                    output: "File deleted successfully: \(path)",
                    detail: "command=del,path=\(path)"
                )

            case let .list(rawPath):
                let path: String
                if let rawPath {
                    path = try terminalPath(rawPath, currentDirectory: currentDirectory)
                } else {
                    path = currentDirectory
                }
                let entries = try fileSystem.entries(in: path)
                if entries.isEmpty {
                    appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Directory is empty: \(path)")
                } else {
                    appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Directory of \(path):")
                    for entry in entries {
                        if entry.content.isDirectory {
                            appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "[\(entry.name)]")
                        } else {
                            appendConsoleLine(
                                state: &state,
                                nodeID: sourceNodeID,
                                line: "\(entry.name)\(String(repeating: ".", count: max(1, 24 - entry.name.count)))\(entry.content.byteCount)"
                            )
                        }
                    }
                    let directoryCount = entries.filter { $0.content.isDirectory }.count
                    let fileCount = entries.count - directoryCount
                    appendConsoleLine(
                        state: &state,
                        nodeID: sourceNodeID,
                        line: "Directories: \(directoryCount) Files: \(fileCount)"
                    )
                }
                finishFilesystemCommand(state: &state, nodeID: sourceNodeID, detail: "command=ls,path=\(path)")

            case let .makeDirectory(rawPath):
                let path = try terminalPath(rawPath, currentDirectory: currentDirectory)
                try fileSystem.createDirectory(at: path, recursive: false)
                commitTerminalFileSystemMutation(
                    state: &state,
                    nodeID: sourceNodeID,
                    fileSystem: fileSystem,
                    output: "Directory created successfully: \(path)",
                    detail: "command=mkdir,path=\(path)"
                )

            case let .move(rawSource, rawDestination):
                let source = try terminalPath(rawSource, currentDirectory: currentDirectory)
                let destination = try terminalPath(rawDestination, currentDirectory: currentDirectory)
                let sourceEntry = try fileSystem.entry(at: source)
                guard sourceEntry.content.isFile else {
                    throw TopologyVirtualFileSystemError.expectedFile(source)
                }
                try fileSystem.moveItem(at: source, to: destination, overwrite: true)
                commitTerminalFileSystemMutation(
                    state: &state,
                    nodeID: sourceNodeID,
                    fileSystem: fileSystem,
                    output: "File moved/renamed successfully: \(source) -> \(destination)",
                    detail: "command=mv,source=\(source),destination=\(destination)"
                )

            case .printWorkingDirectory:
                appendConsoleLine(state: &state, nodeID: sourceNodeID, line: currentDirectory)
                finishFilesystemCommand(state: &state, nodeID: sourceNodeID, detail: "command=pwd,path=\(currentDirectory)")

            case let .touch(rawPath):
                let path = try terminalPath(rawPath, currentDirectory: currentDirectory)
                if fileSystem.contains(path) {
                    let entry = try fileSystem.entry(at: path)
                    guard entry.content.isFile else {
                        throw TopologyVirtualFileSystemError.expectedFile(path)
                    }
                    appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "File already exists: \(path)")
                    finishFilesystemCommand(state: &state, nodeID: sourceNodeID, detail: "command=touch,existing=\(path)")
                    return
                }
                try fileSystem.writeTextFile(at: path, text: "", overwrite: false)
                commitTerminalFileSystemMutation(
                    state: &state,
                    nodeID: sourceNodeID,
                    fileSystem: fileSystem,
                    output: "File created successfully: \(path)",
                    detail: "command=touch,path=\(path)"
                )
            }
        } catch {
            setFilesystemCommandFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .runtimeFilesystemCommandRejectedPath,
                faultCode: "filesystemCommandFailed",
                message: error.localizedDescription,
                detail: "filesystemCommandFailed;command=\(filesystemCommandName(command));cwd=\(currentDirectory)"
            )
        }
    }

    private static func terminalCatOutput(
        for content: TopologyVirtualFileContent
    ) -> (lines: [String], truncated: Bool, renderedBytes: Int) {
        let rendered: String
        switch content {
        case .directory:
            rendered = "cat: cannot read a directory"
        case let .text(value):
            rendered = value
        case let .binary(data, mediaType):
            rendered = "base64;media-type=\(mediaType ?? "application/octet-stream"):" + data.base64EncodedString()
        case let .image(data, mediaType):
            rendered = "base64;media-type=\(mediaType):" + data.base64EncodedString()
        }

        let renderedBytes = rendered.lengthOfBytes(using: .utf8)
        let byteTruncated = renderedBytes > terminalCatMaximumBytes
        let byteLimited = byteTruncated
            ? String(decoding: Data(rendered.utf8).prefix(terminalCatMaximumBytes), as: UTF8.self)
            : rendered
        let rawLines = byteLimited.split(separator: "\n", omittingEmptySubsequences: false)
        let lineTruncated = rawLines.count > terminalCatMaximumLines
        let lines = rawLines.prefix(terminalCatMaximumLines).map {
            String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        }
        let truncated = byteTruncated || lineTruncated
        guard truncated else {
            return (lines.isEmpty ? [""] : lines, false, renderedBytes)
        }
        var boundedLines = lines
        boundedLines.append(
            "[cat output truncated: maxBytes=\(terminalCatMaximumBytes), maxLines=\(terminalCatMaximumLines)]"
        )
        return (boundedLines, true, renderedBytes)
    }

    private static func terminalWorkingDirectory(
        state: TopologyEditorState,
        nodeID: UUID,
        fileSystem: TopologyVirtualFileSystem
    ) -> String {
        guard let candidate = state.runtimeWorkingDirectoryByNodeID[nodeID],
              let entry = try? fileSystem.entry(at: candidate),
              entry.content.isDirectory
        else { return "/" }
        return entry.path
    }

    private static func terminalPath(_ rawPath: String, currentDirectory: String) throws -> String {
        guard !rawPath.isEmpty else {
            throw TopologyVirtualFileSystemError.invalidPathComponent(rawPath)
        }
        let joinedPath: String
        if rawPath.hasPrefix("/") || rawPath.hasPrefix("\\") {
            joinedPath = rawPath
        } else {
            joinedPath = currentDirectory == "/" ? "/\(rawPath)" : "\(currentDirectory)/\(rawPath)"
        }
        return try TopologyVirtualFileSystem.normalizedAbsolutePath(joinedPath)
    }

    private static func commitTerminalFileSystemMutation(
        state: inout TopologyEditorState,
        nodeID: UUID,
        fileSystem: TopologyVirtualFileSystem,
        output: String,
        detail: String
    ) {
        var candidateFileSystems = state.virtualFileSystemsByNodeID
        candidateFileSystems[nodeID] = fileSystem
        do {
            try TopologyVirtualFileSystem.validateProjectQuotas(candidateFileSystems)
        } catch {
            setFilesystemCommandFailure(
                state: &state,
                sourceNodeID: nodeID,
                eventCode: .runtimeFilesystemCommandRejectedPath,
                faultCode: "filesystemQuotaRejected",
                message: error.localizedDescription,
                detail: "filesystemQuotaRejected;\(detail)"
            )
            return
        }
        state.virtualFileSystemsByNodeID = candidateFileSystems
        state.synchronizeRuntimeDNSConfigurationFromHostsFile(nodeID: nodeID, clearWhenMissing: true)
        sanitizeVirtualFileSelections(state: &state, nodeID: nodeID, fileSystem: fileSystem)
        state.lastRuntimeFault = nil
        advancePersistenceRevision(state: &state)
        appendConsoleLine(state: &state, nodeID: nodeID, line: output)
        recordRuntimeEvent(state: &state, code: .runtimeFilesystemCommandSucceeded, detail: detail)
    }

    private static func finishFilesystemCommand(
        state: inout TopologyEditorState,
        nodeID: UUID,
        detail: String
    ) {
        state.lastRuntimeFault = nil
        recordRuntimeEvent(state: &state, code: .runtimeFilesystemCommandSucceeded, detail: detail)
    }

    private static func setFilesystemCommandFailure(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        eventCode: TopologyRuntimeEventCode,
        faultCode: String,
        message: String,
        detail: String
    ) {
        state.lastRuntimeFault = TopologyRuntimeFault(
            category: .commandValidation,
            code: faultCode,
            message: message
        )
        recordRuntimeEvent(state: &state, code: eventCode, detail: detail)
        appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Filesystem command failed: \(faultCode) — \(message)")
    }

    private static func filesystemCommandName(_ command: FilesystemCommand) -> String {
        switch command {
        case .cat: return "cat"
        case .cd: return "cd"
        case .copy: return "cp"
        case .delete: return "del"
        case .list: return "ls"
        case .makeDirectory: return "mkdir"
        case .move: return "mv"
        case .printWorkingDirectory: return "pwd"
        case .touch: return "touch"
        }
    }

    private static func parseRuntimeCommand(_ command: String) -> RuntimeCommandParseResult {
        let parts = command.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        guard let firstToken = parts.first else {
            return .malformed(
                command: nil,
                reason: "Command must follow deterministic format: help OR ping/trace/route <target-ipv4|hostname> OR host/nslookup <hostname>"
            )
        }

        let commandToken = firstToken.lowercased()
        switch commandToken {
        case "ping":
            guard parts.count == 2 else {
                return .malformed(
                    command: "ping",
                    reason: "Command must follow deterministic format: ping <target-ipv4|hostname>"
                )
            }

            if let normalizedTargetAddress = normalizedIPv4Address(parts[1]) {
                return .success(.ping(.ipAddress(normalizedTargetAddress)))
            }

            if let normalizedHostname = normalizedHostname(parts[1]) {
                return .success(.ping(.hostname(normalizedHostname)))
            }

            return .malformed(
                command: "ping",
                reason: "Ping target must be a valid IPv4 address or hostname"
            )

        case "trace", "path", "traceroute":
            guard parts.count == 2 else {
                return .malformed(
                    command: "trace",
                    reason: "Command must follow deterministic format: trace <target-ipv4|hostname>"
                )
            }

            if let normalizedTargetAddress = normalizedIPv4Address(parts[1]) {
                return .success(.trace(.ipAddress(normalizedTargetAddress)))
            }

            if let normalizedHostname = normalizedHostname(parts[1]) {
                return .success(.trace(.hostname(normalizedHostname)))
            }

            return .malformed(
                command: "trace",
                reason: "Trace target must be a valid IPv4 address or hostname"
            )

        case "route":
            guard parts.count == 2 else {
                return .malformed(
                    command: "route",
                    reason: "Command must follow deterministic format: route <target-ipv4|hostname>"
                )
            }

            if let normalizedTargetAddress = normalizedIPv4Address(parts[1]) {
                return .success(.route(.ipAddress(normalizedTargetAddress)))
            }

            if let normalizedHostname = normalizedHostname(parts[1]) {
                return .success(.route(.hostname(normalizedHostname)))
            }

            return .malformed(
                command: "route",
                reason: "Route target must be a valid IPv4 address or hostname"
            )

        case "host", "nslookup":
            guard parts.count == 2 else {
                return .malformed(
                    command: commandToken,
                    reason: "Command must follow deterministic format: \(commandToken) <hostname>"
                )
            }

            guard let hostname = normalizedHostname(parts[1]) else {
                return .malformed(
                    command: commandToken,
                    reason: "Host lookup target must be a valid hostname"
                )
            }

            return .success(.hostResolve(hostname: hostname, commandToken: commandToken))

        case "help", "?":
            guard parts.count <= 2 else {
                return .malformed(
                    command: "help",
                    reason: "Command must follow deterministic format: help [command]"
                )
            }

            let commandToken = parts.count == 2 ? parts[1].lowercased() : nil
            if let commandToken, TopologyRuntimeCommandCatalog.usage(for: commandToken) == nil {
                return .malformed(command: "help", reason: "Unknown command: \(commandToken)")
            }
            return .success(.help(commandToken: commandToken))

        case "ipconfig":
            guard parts.count == 1 else { return .malformed(command: "ipconfig", reason: "Usage: ipconfig") }
            return .success(.ipconfig)

        case "netstat":
            guard parts.count == 1 else { return .malformed(command: "netstat", reason: "Usage: netstat") }
            return .success(.netstat)

        case "arp":
            guard parts.count == 1 || parts.count == 2 || parts.count == 3 else {
                return .malformed(command: "arp", reason: "Usage: arp [-a <ipv4> | -d [ipv4]]")
            }
            if parts.count == 1 { return .success(.arpList(filterIPAddress: nil)) }
            let option = parts[1].lowercased()
            switch option {
            case "-a":
                guard parts.count == 3, let address = normalizedIPv4Address(parts[2]) else {
                    return .malformed(command: "arp", reason: "Usage: arp -a <ipv4>")
                }
                return .success(.arpList(filterIPAddress: address))
            case "-d":
                guard parts.count <= 3 else { return .malformed(command: "arp", reason: "Usage: arp -d [ipv4]") }
                if parts.count == 2 { return .success(.arpDelete(ipAddress: nil)) }
                guard let address = normalizedIPv4Address(parts[2]) else {
                    return .malformed(command: "arp", reason: "ARP delete target must be a valid IPv4 address")
                }
                return .success(.arpDelete(ipAddress: address))
            default:
                return .malformed(command: "arp", reason: "Usage: arp [-a <ipv4> | -d [ipv4]]")
            }

        case "arpsend":
            guard parts.count == 3,
                  let senderIPAddress = normalizedIPv4Address(parts[1]),
                  let targetIPAddress = normalizedIPv4Address(parts[2])
            else {
                return .malformed(command: "arpsend", reason: "Usage: arpsend <sender-ipv4> <target-ipv4>")
            }
            return .success(.arpSend(senderIPAddress: senderIPAddress, targetIPAddress: targetIPAddress))

        case "tcpdump":
            guard parts.count == 1 else { return .malformed(command: "tcpdump", reason: "Usage: tcpdump") }
            return .success(.tcpdump)

        case "dhcp":
            guard parts.count >= 2 else {
                return .malformed(
                    command: "dhcp",
                    reason: "Command must follow deterministic format: dhcp lease <ipv4> <subnet-mask> OR dhcp release"
                )
            }

            switch parts[1].lowercased() {
            case "lease":
                guard parts.count == 4 else {
                    return .malformed(
                        command: "dhcp",
                        reason: "Command must follow deterministic format: dhcp lease <ipv4> <subnet-mask>"
                    )
                }

                guard let normalizedAddress = normalizedIPv4Address(parts[2]) else {
                    return .malformed(
                        command: "dhcp",
                        reason: "DHCP lease IP must be a valid IPv4 address"
                    )
                }

                guard let normalizedMask = normalizedSubnetMask(parts[3]) else {
                    return .malformed(
                        command: "dhcp",
                        reason: "DHCP lease subnet mask must be a contiguous IPv4 mask"
                    )
                }

                return .success(.dhcpLease(ipAddress: normalizedAddress, subnetMask: normalizedMask))

            case "release":
                guard parts.count == 2 else {
                    return .malformed(
                        command: "dhcp",
                        reason: "Command must follow deterministic format: dhcp release"
                    )
                }

                return .success(.dhcpRelease)

            default:
                return .malformed(
                    command: "dhcp",
                    reason: "DHCP command verb must be 'lease' or 'release'"
                )
            }

        case "cat":
            guard parts.count == 2 else { return .malformed(command: "cat", reason: "Usage: cat <file>") }
            return .success(.filesystemCat(path: parts[1]))

        case "cd":
            guard parts.count <= 2 else { return .malformed(command: "cd", reason: "Usage: cd [directory]") }
            return .success(.filesystemCd(path: parts.count == 2 ? parts[1] : nil))

        case "cp", "copy":
            guard parts.count == 3 else { return .malformed(command: "cp", reason: "Usage: cp <source-file> <destination>") }
            return .success(.filesystemCopy(source: parts[1], destination: parts[2]))

        case "del", "rm":
            guard parts.count == 2 else { return .malformed(command: "del", reason: "Usage: del <file>") }
            return .success(.filesystemDelete(path: parts[1]))

        case "dir", "ls":
            guard parts.count <= 2 else { return .malformed(command: "ls", reason: "Usage: ls [directory]") }
            return .success(.filesystemList(path: parts.count == 2 ? parts[1] : nil))

        case "mkdir":
            guard parts.count == 2 else { return .malformed(command: "mkdir", reason: "Usage: mkdir <directory>") }
            return .success(.filesystemMakeDirectory(path: parts[1]))

        case "move", "mv":
            guard parts.count == 3 else { return .malformed(command: "mv", reason: "Usage: mv <source-file> <destination>") }
            return .success(.filesystemMove(source: parts[1], destination: parts[2]))

        case "pwd":
            guard parts.count == 1 else { return .malformed(command: "pwd", reason: "Usage: pwd") }
            return .success(.filesystemPrintWorkingDirectory)

        case "touch":
            guard parts.count == 2 else { return .malformed(command: "touch", reason: "Usage: touch <file>") }
            return .success(.filesystemTouch(path: parts[1]))

        case "dns":
            guard parts.count >= 3 else {
                return .malformed(
                    command: "dns",
                    reason: "Command must follow deterministic format: dns resolve <hostname> OR dns add <hostname> <target-ipv4> OR dns remove <hostname>"
                )
            }

            let verb = parts[1].lowercased()
            switch verb {
            case "resolve":
                guard parts.count == 3 else {
                    return .malformed(
                        command: "dns",
                        reason: "Command must follow deterministic format: dns resolve <hostname>"
                    )
                }

                guard let hostname = normalizedHostname(parts[2]) else {
                    return .malformed(
                        command: "dns",
                        reason: "DNS hostname must contain only letters, numbers, '-' or '.'"
                    )
                }

                return .success(.dnsResolve(hostname: hostname))

            case "add":
                guard parts.count == 4 else {
                    return .malformed(
                        command: "dns",
                        reason: "Command must follow deterministic format: dns add <hostname> <target-ipv4>"
                    )
                }

                guard let hostname = normalizedHostname(parts[2]) else {
                    return .malformed(
                        command: "dns",
                        reason: "DNS hostname must contain only letters, numbers, '-' or '.'"
                    )
                }

                guard let normalizedAddress = normalizedIPv4Address(parts[3]) else {
                    return .malformed(
                        command: "dns",
                        reason: "DNS target must be a valid IPv4 address"
                    )
                }

                return .success(.dnsRegister(hostname: hostname, targetIPAddress: normalizedAddress))

            case "remove":
                guard parts.count == 3 else {
                    return .malformed(
                        command: "dns",
                        reason: "Command must follow deterministic format: dns remove <hostname>"
                    )
                }

                guard let hostname = normalizedHostname(parts[2]) else {
                    return .malformed(
                        command: "dns",
                        reason: "DNS hostname must contain only letters, numbers, '-' or '.'"
                    )
                }

                return .success(.dnsRemove(hostname: hostname))

            default:
                return .malformed(
                    command: "dns",
                    reason: "DNS command verb must be 'add', 'remove', or 'resolve'"
                )
            }

        default:
            return .unsupported(command: commandToken)
        }
    }

    private static func unsupportedRuntimeCommandDescriptor(for commandToken: String) -> UnsupportedRuntimeCommandDescriptor {
        let normalizedToken = commandToken.lowercased()
        let family: UnsupportedRuntimeCommandFamily

        switch normalizedToken {
        case "arp", "arpsend":
            family = .linkLayer

        case "ipconfig":
            family = .hostConfiguration

        case "netstat":
            family = .socketInspection

        case "dir", "ls", "cd", "copy", "cp", "move", "mv", "del", "rm", "type", "cat", "mkdir", "rmdir":
            family = .filesystem

        default:
            family = .generic
        }

        switch family {
        case .linkLayer:
            return UnsupportedRuntimeCommandDescriptor(
                faultCode: "unsupportedRuntimeCommandLinkLayer",
                message: "Command '\(normalizedToken)' is unsupported in S03 link-layer tooling; use route or trace for route diagnostics.",
                detail: "unsupportedRuntimeCommand;token=\(normalizedToken);family=linkLayer"
            )

        case .hostConfiguration:
            return UnsupportedRuntimeCommandDescriptor(
                faultCode: "unsupportedRuntimeCommandHostConfiguration",
                message: "Command '\(normalizedToken)' is unsupported in S03 host configuration tooling; use runtime IP configuration or DHCP commands.",
                detail: "unsupportedRuntimeCommand;token=\(normalizedToken);family=hostConfiguration"
            )

        case .socketInspection:
            return UnsupportedRuntimeCommandDescriptor(
                faultCode: "unsupportedRuntimeCommandSocketInspection",
                message: "Command '\(normalizedToken)' is unsupported in S03 socket inspection tooling; use route/trace/host diagnostics.",
                detail: "unsupportedRuntimeCommand;token=\(normalizedToken);family=socketInspection"
            )

        case .filesystem:
            return UnsupportedRuntimeCommandDescriptor(
                faultCode: "unsupportedRuntimeCommandFilesystem",
                message: "Command '\(normalizedToken)' is unsupported in the terminal filesystem surface.",
                detail: "unsupportedRuntimeCommand;token=\(normalizedToken);family=filesystem"
            )

        case .generic:
            return UnsupportedRuntimeCommandDescriptor(
                faultCode: "unsupportedRuntimeCommand",
                message: "Unsupported runtime command '\(normalizedToken)'. Supported commands are: \(TopologyRuntimeCommandCatalog.supportedCommandsInline)",
                detail: "unsupportedRuntimeCommand;token=\(normalizedToken);family=generic"
            )
        }
    }

    private static func normalizedFirewallRules(
        _ rules: [TopologyFirewallRule]
    ) -> [TopologyFirewallRule]? {
        var normalized: [TopologyFirewallRule] = []
        normalized.reserveCapacity(rules.count)
        for rule in rules {
            guard rule.port == TopologyFirewallRule.allPorts || (1...65_535).contains(rule.port) else {
                return nil
            }
            let source: String
            if rule.sourceIPAddress == TopologyFirewallRule.directlyConnectedSourceMarker {
                source = rule.sourceIPAddress
            } else if rule.sourceIPAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                source = ""
            } else if let value = normalizedIPv4Address(rule.sourceIPAddress) {
                source = value
            } else {
                return nil
            }
            let destination: String
            if rule.destinationIPAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                destination = ""
            } else if let value = normalizedIPv4Address(rule.destinationIPAddress) {
                destination = value
            } else {
                return nil
            }
            let sourceMask: String
            if rule.sourceSubnetMask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sourceMask = ""
            } else if let value = normalizedSubnetMask(rule.sourceSubnetMask) {
                sourceMask = value
            } else {
                return nil
            }
            let destinationMask: String
            if rule.destinationSubnetMask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                destinationMask = ""
            } else if let value = normalizedSubnetMask(rule.destinationSubnetMask) {
                destinationMask = value
            } else {
                return nil
            }
            guard source == TopologyFirewallRule.directlyConnectedSourceMarker || source.isEmpty || !sourceMask.isEmpty,
                  destination.isEmpty || !destinationMask.isEmpty else {
                return nil
            }
            normalized.append(TopologyFirewallRule(
                sourceIPAddress: source,
                sourceSubnetMask: sourceMask,
                destinationIPAddress: destination,
                destinationSubnetMask: destinationMask,
                port: rule.port,
                protocolType: rule.protocolType,
                action: rule.action
            ))
        }
        return normalized
    }

    private static func normalizedMACAddress(_ value: String?) -> String? {
        guard let value = normalizedRuntimeValue(value) else { return nil }
        let segments = value.split(separator: ":", omittingEmptySubsequences: false)
        guard segments.count == 6,
              segments.allSatisfy({ segment in
                segment.count == 2 && segment.allSatisfy(\.isHexDigit)
              }) else { return nil }
        return segments.map { $0.uppercased() }.joined(separator: ":")
    }

    private static func normalizedHostname(_ value: String?) -> String? {
        guard let normalized = normalizedRuntimeValue(value)?.lowercased() else {
            return nil
        }

        guard normalized.count <= 63 else {
            return nil
        }

        guard normalized.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }) else {
            return nil
        }

        guard !normalized.hasPrefix("."),
              !normalized.hasSuffix("."),
              !normalized.contains("..")
        else {
            return nil
        }

        return normalized
    }

    private static func normalizedIPv4Address(_ value: String?) -> String? {
        guard let octets = parseIPv4Octets(value) else {
            return nil
        }

        return octets.map(String.init).joined(separator: ".")
    }

    private static func normalizedOptionalIPv4Address(_ value: String?) -> String? {
        guard normalizedRuntimeValue(value) != nil else {
            return ""
        }
        return normalizedIPv4Address(value)
    }

    private static func normalizedSubnetMask(_ value: String?) -> String? {
        guard let octets = parseIPv4Octets(value), isContiguousSubnetMask(octets) else {
            return nil
        }

        return octets.map(String.init).joined(separator: ".")
    }

    private static func parseIPv4Octets(_ value: String?) -> [UInt8]? {
        guard let normalized = normalizedRuntimeValue(value) else {
            return nil
        }

        let segments = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 4 else {
            return nil
        }

        var octets: [UInt8] = []
        octets.reserveCapacity(4)

        for segment in segments {
            let text = String(segment)
            guard !text.isEmpty, text.allSatisfy({ $0.isNumber }), let octet = UInt8(text) else {
                return nil
            }
            octets.append(octet)
        }

        return octets
    }

    private static func isContiguousSubnetMask(_ octets: [UInt8]) -> Bool {
        guard octets.count == 4 else {
            return false
        }

        let mask = octets.reduce(UInt32(0)) { partial, octet in
            (partial << 8) | UInt32(octet)
        }

        let inverted = ~mask
        return (inverted & (inverted &+ 1)) == 0
    }

    private static func networkPrefix(ipAddress: String, subnetMask: String) -> UInt32? {
        guard
            let ipOctets = parseIPv4Octets(ipAddress),
            let subnetOctets = parseIPv4Octets(subnetMask)
        else {
            return nil
        }

        let ip = ipOctets.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let mask = subnetOctets.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return ip & mask
    }

    private static func networkAddress(ipAddress: String, subnetMask: String) -> String? {
        guard let prefix = networkPrefix(ipAddress: ipAddress, subnetMask: subnetMask) else {
            return nil
        }
        return [24, 16, 8, 0].map { shift in
            String((prefix >> shift) & 0xff)
        }.joined(separator: ".")
    }

    private static func runtimeConfigurationsShareSubnet(
        _ source: TopologyRuntimeDeviceConfiguration,
        _ target: TopologyRuntimeDeviceConfiguration
    ) -> Bool {
        networkPrefix(ipAddress: source.ipAddress, subnetMask: source.subnetMask)
            == networkPrefix(ipAddress: target.ipAddress, subnetMask: source.subnetMask)
            && networkPrefix(ipAddress: source.ipAddress, subnetMask: target.subnetMask)
                == networkPrefix(ipAddress: target.ipAddress, subnetMask: target.subnetMask)
    }

    private static func areCompatibleEndpoints(_ sourceNode: TopologyNode, _ targetNode: TopologyNode) -> Bool {
        (sourceNode.kind.isPCClassEndpoint && targetNode.kind.isPCClassEndpoint)
            || isNetworkInfrastructure(sourceNode.kind)
            || isNetworkInfrastructure(targetNode.kind)
    }

    private static func isNetworkInfrastructure(_ kind: TopologyNodeKind) -> Bool {
        switch kind {
        case .networkSwitch, .router, .gateway, .remoteLink:
            return true
        case .pc, .notebook, .unsupported:
            return false
        }
    }

    private static func resolvePortID(
        on node: TopologyNode,
        requestedPortID: UUID?,
        graph: TopologyGraph
    ) -> PortResolutionResult {
        guard !node.ports.isEmpty else {
            return .failure(.noFreePort)
        }

        if let requestedPortID {
            guard node.ports.contains(where: { $0.id == requestedPortID }) else {
                return .failure(.invalidPortIdentifier)
            }

            guard isPortAvailable(sourcePortID: requestedPortID, on: node, in: graph) else {
                return .failure(.noFreePort)
            }

            return .success(requestedPortID)
        }

        guard let availablePortID = node.ports.first(where: {
            isPortAvailable(sourcePortID: $0.id, on: node, in: graph)
        })?.id else {
            return .failure(.noFreePort)
        }

        return .success(availablePortID)
    }

    private static func isPortAvailable(sourcePortID: UUID, on node: TopologyNode, in graph: TopologyGraph) -> Bool {
        guard let port = node.ports.first(where: { $0.id == sourcePortID }) else {
            return false
        }

        return !port.isOccupied && !graph.isPortConnected(nodeID: node.id, portID: sourcePortID)
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

private extension TopologyEditorAction {
    var debugName: String {
        switch self {
        case .placeNode:
            return "placeNode"
        case .selectSingleNode:
            return "selectSingleNode"
        case .selectSingleLink:
            return "selectSingleLink"
        case .selectNodes:
            return "selectNodes"
        case .clearSelection:
            return "clearSelection"
        case .deleteSelection:
            return "deleteSelection"
        case .deleteLink:
            return "deleteLink"
        case .cancelConnection:
            return "cancelConnection"
        case .setWorkspaceMode:
            return "setWorkspaceMode"
        case .setDocumentationTool:
            return "setDocumentationTool"
        case .createDocumentationItem:
            return "createDocumentationItem"
        case .selectDocumentationItem:
            return "selectDocumentationItem"
        case .moveSelectedDocumentationItem:
            return "moveSelectedDocumentationItem"
        case .updateDocumentationItem:
            return "updateDocumentationItem"
        case .deleteSelectedDocumentationItem:
            return "deleteSelectedDocumentationItem"
        case .addRouterInterface:
            return "addRouterInterface"
        case .removeRouterInterface:
            return "removeRouterInterface"
        case .setActiveTool:
            return "setActiveTool"
        case .saveDesignDeviceConfiguration:
            return "saveDesignDeviceConfiguration"
        case .startConnection:
            return "startConnection"
        case .completeConnection:
            return "completeConnection"
        case .startSimulation:
            return "startSimulation"
        case .stopSimulation:
            return "stopSimulation"
        case .setSimulationSpeed:
            return "setSimulationSpeed"
        case .simulationTick:
            return "simulationTick"
        case .simulationFault:
            return "simulationFault"
        case .openRuntimeDevice:
            return "openRuntimeDevice"
        case .closeRuntimeDevice:
            return "closeRuntimeDevice"
        case .saveRuntimeDeviceIP:
            return "saveRuntimeDeviceIP"
        case .saveRuntimeDeviceConfiguration:
            return "saveRuntimeDeviceConfiguration"
        case .saveRuntimeInterfaceConfiguration:
            return "saveRuntimeInterfaceConfiguration"
        case .saveRuntimeManualRoutes:
            return "saveRuntimeManualRoutes"
        case .setRuntimeRIPEnabled:
            return "setRuntimeRIPEnabled"
        case .setRuntimeDHCPClientEnabled:
            return "setRuntimeDHCPClientEnabled"
        case .saveRuntimeDHCPServerConfiguration:
            return "saveRuntimeDHCPServerConfiguration"
        case .saveRuntimeFirewallConfiguration:
            return "saveRuntimeFirewallConfiguration"
        case .resetRuntimeNATTable:
            return "resetRuntimeNATTable"
        case .clearRuntimeSwitchSAT:
            return "clearRuntimeSwitchSAT"
        case .resetRuntimePacketCapture:
            return "resetRuntimePacketCapture"
        case .saveRuntimePortForwardingRows:
            return "saveRuntimePortForwardingRows"
        case .installRuntimeProgram:
            return "installRuntimeProgram"
        case .uninstallRuntimeProgram:
            return "uninstallRuntimeProgram"
        case .launchRuntimeProgram:
            return "launchRuntimeProgram"
        case .closeRuntimeProgram:
            return "closeRuntimeProgram"
        case .createProtocolApplication:
            return "createProtocolApplication"
        case .updateProtocolApplication:
            return "updateProtocolApplication"
        case .deleteProtocolApplication:
            return "deleteProtocolApplication"
        case .installProtocolApplication:
            return "installProtocolApplication"
        case .uninstallProtocolApplication:
            return "uninstallProtocolApplication"
        case .launchProtocolApplication:
            return "launchProtocolApplication"
        case .closeProtocolApplication:
            return "closeProtocolApplication"
        case .runtimeProtocolServerStart:
            return "runtimeProtocolServerStart"
        case .runtimeProtocolServerStop:
            return "runtimeProtocolServerStop"
        case .runtimeProtocolClientSend:
            return "runtimeProtocolClientSend"
        case .runtimeDHCPLease:
            return "runtimeDHCPLease"
        case .runtimeDHCPRelease:
            return "runtimeDHCPRelease"
        case .runtimeDNSStart:
            return "runtimeDNSStart"
        case .runtimeDNSStop:
            return "runtimeDNSStop"
        case .runtimeDNSAddRecord:
            return "runtimeDNSAddRecord"
        case .runtimeDNSRemoveRecord:
            return "runtimeDNSRemoveRecord"
        case .runtimeDNSResolveRecord:
            return "runtimeDNSResolveRecord"
        case .runtimeWebStart:
            return "runtimeWebStart"
        case .runtimeWebStop:
            return "runtimeWebStop"
        case .runtimeWebRestart:
            return "runtimeWebRestart"
        case .runtimeWebBrowserNavigate:
            return "runtimeWebBrowserNavigate"
        case .runtimeWebBrowserBack:
            return "runtimeWebBrowserBack"
        case .runtimeWebBrowserForward:
            return "runtimeWebBrowserForward"
        case .runtimeWebBrowserReset:
            return "runtimeWebBrowserReset"
        case .runtimeEchoStart:
            return "runtimeEchoStart"
        case .runtimeEchoStop:
            return "runtimeEchoStop"
        case .runtimeSimpleClientConnect:
            return "runtimeSimpleClientConnect"
        case .runtimeSimpleClientSend:
            return "runtimeSimpleClientSend"
        case .runtimeSimpleClientDisconnect:
            return "runtimeSimpleClientDisconnect"
        case .saveRuntimeEmailClientConfiguration:
            return "saveRuntimeEmailClientConfiguration"
        case .saveRuntimeEmailServerConfiguration:
            return "saveRuntimeEmailServerConfiguration"
        case .saveAndStartRuntimeEmailServer:
            return "saveAndStartRuntimeEmailServer"
        case .runtimeEmailServerStart:
            return "runtimeEmailServerStart"
        case .runtimeEmailServerStop:
            return "runtimeEmailServerStop"
        case .runtimeEmailClientSend:
            return "runtimeEmailClientSend"
        case .runtimeEmailClientRetrieve:
            return "runtimeEmailClientRetrieve"
        case .saveRuntimeGnutellaConfiguration:
            return "saveRuntimeGnutellaConfiguration"
        case .runtimeGnutellaJoin:
            return "runtimeGnutellaJoin"
        case .runtimeGnutellaResetNetwork:
            return "runtimeGnutellaResetNetwork"
        case .runtimeGnutellaSearch:
            return "runtimeGnutellaSearch"
        case .runtimeGnutellaClearSearchResults:
            return "runtimeGnutellaClearSearchResults"
        case .runtimeGnutellaDownload:
            return "runtimeGnutellaDownload"
        case .runtimeFileExplorerSelectEntry:
            return "runtimeFileExplorerSelectEntry"
        case .runtimeImageViewerSelectImage:
            return "runtimeImageViewerSelectImage"
        case .runtimeTextEditorSelectFile:
            return "runtimeTextEditorSelectFile"
        case .runtimeTextEditorUpdateDraft:
            return "runtimeTextEditorUpdateDraft"
        case .runtimeTextEditorSaveDraft:
            return "runtimeTextEditorSaveDraft"
        case .runtimeTextEditorResetDraft:
            return "runtimeTextEditorResetDraft"
        case .runtimeFileSystemCreateDirectory:
            return "runtimeFileSystemCreateDirectory"
        case .runtimeFileSystemCreateTextFile:
            return "runtimeFileSystemCreateTextFile"
        case .runtimeFileSystemCopyItem:
            return "runtimeFileSystemCopyItem"
        case .runtimeFileSystemMoveItem:
            return "runtimeFileSystemMoveItem"
        case .runtimeFileSystemRenameItem:
            return "runtimeFileSystemRenameItem"
        case .runtimeFileSystemDeleteItem:
            return "runtimeFileSystemDeleteItem"
        case .executePing:
            return "executePing"
        case .moveSelectedNodes:
            return "moveSelectedNodes"
        case .panCanvas:
            return "panCanvas"
        case .zoomCanvas:
            return "zoomCanvas"
        case .setInteractionMode:
            return "setInteractionMode"
        case .dismissRecoveryNotice:
            return "dismissRecoveryNotice"
        case .dismissPersistenceError:
            return "dismissPersistenceError"
        }
    }
}
