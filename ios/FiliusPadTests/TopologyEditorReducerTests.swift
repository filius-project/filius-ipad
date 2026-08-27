import CoreGraphics
import UIKit
import XCTest
@testable import FiliusPad

final class TopologyEditorReducerTests: XCTestCase {
    func testParallelCableOffsetsFollowStableIdentifierOrder() {
        let firstNodeID = uuid("00000000-0000-0000-0000-000000000010")
        let secondNodeID = uuid("00000000-0000-0000-0000-000000000020")
        let lowID = uuid("00000000-0000-0000-0000-000000000101")
        let middleID = uuid("00000000-0000-0000-0000-000000000102")
        let highID = uuid("00000000-0000-0000-0000-000000000103")
        let links = [highID, lowID, middleID].map { linkID in
            TopologyLink(
                id: linkID,
                sourceNodeID: firstNodeID,
                sourcePortID: UUID(),
                targetNodeID: secondNodeID,
                targetPortID: UUID()
            )
        }

        let offsets = TopologyLink.parallelCableOffsets(for: links)
        let reversedInputOffsets = TopologyLink.parallelCableOffsets(for: Array(links.reversed()))

        XCTAssertEqual(offsets[lowID], -14)
        XCTAssertEqual(offsets[middleID], 0)
        XCTAssertEqual(offsets[highID], 14)
        XCTAssertEqual(reversedInputOffsets, offsets)
    }

    func testParallelCableOffsetsInvertForReversedEndpointDirection() {
        let firstNodeID = uuid("00000000-0000-0000-0000-000000000010")
        let secondNodeID = uuid("00000000-0000-0000-0000-000000000020")
        let lowID = uuid("00000000-0000-0000-0000-000000000101")
        let highID = uuid("00000000-0000-0000-0000-000000000102")
        let forwardLinks = [lowID, highID].map { linkID in
            TopologyLink(
                id: linkID,
                sourceNodeID: firstNodeID,
                sourcePortID: UUID(),
                targetNodeID: secondNodeID,
                targetPortID: UUID()
            )
        }
        let reversedLinks = forwardLinks.map { link in
            TopologyLink(
                id: link.id,
                sourceNodeID: link.targetNodeID,
                sourcePortID: link.targetPortID,
                targetNodeID: link.sourceNodeID,
                targetPortID: link.sourcePortID
            )
        }

        let mixedDirectionLinks = [reversedLinks[0], forwardLinks[1]]
        let forwardOffsets = TopologyLink.parallelCableOffsets(for: forwardLinks)
        let reversedOffsets = TopologyLink.parallelCableOffsets(for: reversedLinks)
        let mixedDirectionOffsets = TopologyLink.parallelCableOffsets(for: mixedDirectionLinks)

        XCTAssertEqual(forwardOffsets[lowID], -7)
        XCTAssertEqual(forwardOffsets[highID], 7)
        XCTAssertEqual(reversedOffsets[lowID], 7)
        XCTAssertEqual(reversedOffsets[highID], -7)
        XCTAssertEqual(mixedDirectionOffsets[lowID], 7)
        XCTAssertEqual(mixedDirectionOffsets[highID], 7)
    }

    func testParallelCableOffsetsKeepUnrelatedNodePairsIndependent() {
        let firstNodeID = uuid("00000000-0000-0000-0000-000000000010")
        let secondNodeID = uuid("00000000-0000-0000-0000-000000000020")
        let unrelatedFirstNodeID = uuid("00000000-0000-0000-0000-000000000030")
        let unrelatedSecondNodeID = uuid("00000000-0000-0000-0000-000000000040")
        let firstPairLowID = uuid("00000000-0000-0000-0000-000000000101")
        let firstPairHighID = uuid("00000000-0000-0000-0000-000000000102")
        let unrelatedID = uuid("00000000-0000-0000-0000-000000000001")
        let firstPairLinks = [firstPairLowID, firstPairHighID].map { linkID in
            TopologyLink(
                id: linkID,
                sourceNodeID: firstNodeID,
                sourcePortID: UUID(),
                targetNodeID: secondNodeID,
                targetPortID: UUID()
            )
        }
        let unrelatedLink = TopologyLink(
            id: unrelatedID,
            sourceNodeID: unrelatedFirstNodeID,
            sourcePortID: UUID(),
            targetNodeID: unrelatedSecondNodeID,
            targetPortID: UUID()
        )

        let offsets = TopologyLink.parallelCableOffsets(for: [unrelatedLink] + firstPairLinks)

        XCTAssertEqual(offsets[firstPairLowID], -7)
        XCTAssertEqual(offsets[firstPairHighID], 7)
        XCTAssertEqual(offsets[unrelatedID], 0)
    }

    func testDesignPortOwnerLabelsUseLiveDraftDisplayName() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let editorViewURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FiliusPad/TopologyEditor/View/TopologyEditorView.swift")
        let source = try String(contentsOf: editorViewURL, encoding: .utf8)
        let liveOwnerLabel = "LabeledContent(FiliusLocalization.t(\"ui.2843ee905670\"), value: draft.displayName)"

        XCTAssertEqual(source.components(separatedBy: liveOwnerLabel).count - 1, 2)
        XCTAssertFalse(source.contains("ownerName"))
    }

    func testDNSRecursionEditorUsesExplicitSaveForCurrentToggleAndForwarderValues() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let deviceSheetURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FiliusPad/TopologyEditor/View/TopologyRuntimeDeviceSheet.swift")
        let source = try String(contentsOf: deviceSheetURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains(
                "Toggle(FiliusLocalization.t(\"runtime.dns.recursive\"), isOn: $dnsRecursionEnabled)"
            )
        )
        XCTAssertTrue(
            source.contains(
                "Button(FiliusLocalization.t(\"common.save\")) {\n"
                    + "                onDNSSetRecursion(dnsRecursionEnabled, dnsForwarder)"
            )
        )
        XCTAssertTrue(
            source.contains(
                ".accessibilityIdentifier(\"runtime.device.app.dns.recursion.save\")"
            )
        )
        XCTAssertFalse(
            source.contains("onDNSSetRecursion(enabled, dnsForwarder)")
        )
    }

    func testManualRouteSelectionUsesGreatestMaskAndPreservesFirstEqualMaskMatch() {
        let broad = TopologyRuntimeManualRoute(
            destinationNetwork: "10.0.0.0",
            subnetMask: "255.0.0.0",
            gateway: "192.168.1.8",
            interfaceIPAddress: "192.168.1.1"
        )
        let medium = TopologyRuntimeManualRoute(
            destinationNetwork: "10.20.0.0",
            subnetMask: "255.255.0.0",
            gateway: "192.168.1.16",
            interfaceIPAddress: "192.168.1.1"
        )
        let specificFirst = TopologyRuntimeManualRoute(
            destinationNetwork: "10.20.30.0",
            subnetMask: "255.255.255.0",
            gateway: "192.168.1.24",
            interfaceIPAddress: "192.168.1.1"
        )
        let specificSecond = TopologyRuntimeManualRoute(
            destinationNetwork: "10.20.30.0",
            subnetMask: "255.255.255.0",
            gateway: "192.168.1.25",
            interfaceIPAddress: "192.168.1.2"
        )
        let defaultRoute = TopologyRuntimeManualRoute(
            destinationNetwork: "0.0.0.0",
            subnetMask: "0.0.0.0",
            gateway: "192.168.1.254",
            interfaceIPAddress: "192.168.1.1"
        )
        let routes = [defaultRoute, broad, medium, specificFirst, specificSecond]

        XCTAssertEqual(
            TopologyRuntimeManualRoute.bestMatching(targetIPAddress: "10.20.30.42", routes: routes),
            specificFirst
        )
        XCTAssertEqual(
            TopologyRuntimeManualRoute.bestMatching(targetIPAddress: "10.20.99.42", routes: routes),
            medium
        )
        XCTAssertEqual(
            TopologyRuntimeManualRoute.bestMatching(targetIPAddress: "10.99.0.1", routes: routes),
            broad
        )
        XCTAssertEqual(
            TopologyRuntimeManualRoute.bestMatching(targetIPAddress: "172.16.0.1", routes: routes),
            defaultRoute
        )
        XCTAssertNil(TopologyRuntimeManualRoute.bestMatching(targetIPAddress: "172.16.0.1", routes: [broad, medium]))
        XCTAssertNil(TopologyRuntimeManualRoute.bestMatching(targetIPAddress: "invalid", routes: routes))
    }

    func testPlaceNodeAtCanvasEdgeAddsNodeAndSelectsIt() {
        var state = TopologyEditorState()
        let id = uuid("11111111-1111-1111-1111-111111111111")

        TopologyEditorReducer.reduce(
            state: &state,
            action: .placeNode(kind: .pc, at: CGPoint(x: 0, y: 0), nodeID: id)
        )

        XCTAssertEqual(state.graph.nodes.count, 1)
        XCTAssertEqual(state.graph.nodes.first?.id, id)
        XCTAssertEqual(state.graph.nodes.first?.position, CGPoint(x: 0, y: 0))
        XCTAssertEqual(state.selectedNodeIDs, [id])
        XCTAssertNil(state.lastValidationError)
    }

    func testPlacedNodesReceivePersistentJavaDisplayNames() {
        var state = TopologyEditorState()
        let kinds: [TopologyNodeKind] = [.pc, .notebook, .networkSwitch, .router, .gateway]
        let expectedNames = ["Rechner", "Notebook", "Switch", "Vermittlungsrechner", "Gateway"]

        for (index, kind) in kinds.enumerated() {
            _ = addNode(kind: kind, at: CGPoint(x: CGFloat(index * 20), y: 20), to: &state)
        }

        XCTAssertEqual(state.graph.nodes.map(\.displayName), expectedNames)
    }

    func testNotebookUsesPCClassNetworkingWithoutLosingIdentity() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .notebook, at: CGPoint(x: 30, y: 40), to: &state)
        let configuration = TopologyRuntimeDeviceConfiguration(
            ipAddress: "192.168.44.10",
            subnetMask: "255.255.255.0",
            defaultGateway: "192.168.44.1",
            dnsServer: "192.168.44.53"
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveDesignDeviceConfiguration(
                nodeID: nodeID,
                displayName: "Mobile Lab",
                hostLabelPolicy: nil,
                deviceConfiguration: configuration,
                interfaceConfigurations: [],
                switchConfiguration: nil,
                remoteLinkConfiguration: nil,
                hostWirelessConfiguration: TopologyHostWirelessConfiguration()
            )
        )

        XCTAssertEqual(state.graph.node(withID: nodeID)?.kind, .notebook)
        XCTAssertEqual(state.graph.node(withID: nodeID)?.ports.map(\.label), ["eth0"])
        XCTAssertEqual(state.runtimeDeviceConfigurations[nodeID], configuration)
        XCTAssertNil(state.lastValidationError)
    }

    func testHostLabelPolicyDerivesIPMACAndFallsBackToManualName() throws {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 40, y: 60), to: &state)
        let node = try XCTUnwrap(state.graph.node(withID: nodeID))
        let expectedMAC = TopologyNetworkRuntimeEngine.stableMACAddress(for: try XCTUnwrap(node.ports.first?.id))

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveDesignDeviceConfiguration(
                nodeID: nodeID,
                displayName: "Lab Host",
                hostLabelPolicy: .ipAndMAC,
                deviceConfiguration: TopologyRuntimeDeviceConfiguration(
                    ipAddress: "10.20.30.40",
                    subnetMask: "255.255.255.0"
                ),
                interfaceConfigurations: [],
                switchConfiguration: nil,
                remoteLinkConfiguration: nil,
                hostWirelessConfiguration: TopologyHostWirelessConfiguration()
            )
        )

        let configured = try XCTUnwrap(state.graph.node(withID: nodeID))
        XCTAssertEqual(configured.hostLabelPolicy, .ipAndMAC)
        XCTAssertEqual(state.displayLabel(for: configured), "10.20.30.40 (\(expectedMAC))")

        state.runtimeDeviceConfigurations[nodeID] = TopologyRuntimeDeviceConfiguration(
            ipAddress: "invalid",
            subnetMask: "255.255.255.0"
        )
        XCTAssertEqual(state.displayLabel(for: configured), expectedMAC)
    }

    func testIPDerivedHostLabelTracksActiveDHCPLeaseAndConfiguredFallback() throws {
        var state = TopologyEditorState()
        let serverNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let clientNodeID = addNode(kind: .pc, at: CGPoint(x: 220, y: 20), to: &state)
        connect(serverNodeID, clientNodeID, state: &state)

        let clientIndex = try XCTUnwrap(state.graph.nodeIndex(withID: clientNodeID))
        state.graph.nodes[clientIndex].hostLabelPolicy = .ipAddress
        state.runtimeDeviceConfigurations[serverNodeID] = TopologyRuntimeDeviceConfiguration(
            ipAddress: "192.168.50.1",
            subnetMask: "255.255.255.0"
        )
        let configuredClient = TopologyRuntimeDeviceConfiguration(
            ipAddress: "169.254.1.2",
            subnetMask: "255.255.0.0"
        )
        state.runtimeDeviceConfigurations[clientNodeID] = configuredClient
        state.runtimeDHCPClientConfigurationsByNodeID[clientNodeID] = TopologyDHCPClientConfiguration(isEnabled: true)
        state.runtimeDHCPServerConfigurationsByNodeID[serverNodeID] = TopologyDHCPServerConfiguration(
            isActive: true,
            lowerBoundIPAddress: "192.168.50.20",
            upperBoundIPAddress: "192.168.50.29",
            gatewayIPAddress: "192.168.50.1",
            dnsServerIPAddress: "192.168.50.53",
            useOwnSettings: true
        )

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .simulationTick(step: 1_000))

        let client = try XCTUnwrap(state.graph.node(withID: clientNodeID))
        XCTAssertEqual(state.runtimeDeviceConfigurations[clientNodeID], configuredClient)
        XCTAssertEqual(state.runtimeDHCPLeaseByNodeID[clientNodeID]?.ipAddress, "192.168.50.20")
        XCTAssertEqual(state.displayLabel(for: client), "192.168.50.20")

        TopologyEditorReducer.reduce(state: &state, action: .stopSimulation)

        XCTAssertNil(state.runtimeDHCPLeaseByNodeID[clientNodeID])
        XCTAssertEqual(state.displayLabel(for: client), "169.254.1.2")
    }

    func testImportedJavaMACOverridesGeneratedMACForHostLabelAndRuntimeInterface() throws {
        let port = TopologyPortMetadata(
            id: uuid("20202020-2020-2020-2020-202020202021"),
            label: "eth0",
            importedMACAddress: "aa:bb:cc:dd:ee:ff"
        )
        let node = TopologyNode(
            id: uuid("20202020-2020-2020-2020-202020202020"),
            kind: .pc,
            displayName: "Imported Host",
            hostLabelPolicy: .macAddress,
            position: CGPoint(x: 40, y: 60),
            ports: [port]
        )
        var state = TopologyEditorState()
        state.graph = TopologyGraph(nodes: [node], links: [])
        state.runtimeDeviceConfigurations[node.id] = TopologyRuntimeDeviceConfiguration(
            ipAddress: "10.0.0.10",
            subnetMask: "255.255.255.0"
        )

        XCTAssertEqual(state.displayLabel(for: node), "AA:BB:CC:DD:EE:FF")

        var runtime = TopologyNetworkRuntimeEngine(seed: 7)
        runtime.handle(
            .start(
                snapshot: TopologyNetworkRuntimeTopologySnapshot(editorState: state),
                seed: 7,
                initialTimeMilliseconds: 0
            )
        )
        XCTAssertEqual(runtime.networkInterfaces(nodeID: node.id).first?.macAddress, "AA:BB:CC:DD:EE:FF")
    }

    func testDesignConfigurationRenamesPCAndUpdatesNextRuntimeSnapshotInputs() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 40, y: 60), to: &state)
        let initialRevision = state.persistenceRevision
        let configuration = TopologyRuntimeDeviceConfiguration(
            ipAddress: "10.20.30.40",
            subnetMask: "255.255.255.0",
            defaultGateway: "10.20.30.1",
            dnsServer: "10.20.30.53"
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveDesignDeviceConfiguration(
                nodeID: nodeID,
                displayName: "  Labor-PC  ",
                hostLabelPolicy: nil,
                deviceConfiguration: configuration,
                interfaceConfigurations: [],
                switchConfiguration: nil,
                remoteLinkConfiguration: nil,
                hostWirelessConfiguration: TopologyHostWirelessConfiguration()
            )
        )

        XCTAssertEqual(state.graph.node(withID: nodeID)?.displayName, "Labor-PC")
        XCTAssertEqual(state.runtimeDeviceConfigurations[nodeID], configuration)
        XCTAssertEqual(state.persistenceRevision, initialRevision + 1)
        XCTAssertNil(state.lastValidationError)

        let nextRuntime = TopologyNetworkRuntimeTopologySnapshot(editorState: state)
        XCTAssertEqual(nextRuntime.deviceConfigurations[nodeID], configuration)
    }

    func testGlobalPacketLossActionRequiresRunningSimulationAndResetsOnStop() {
        var state = TopologyEditorState()

        TopologyEditorReducer.reduce(state: &state, action: .setGlobalPacketLoss(enabled: true))
        XCTAssertFalse(state.networkRuntime.state.globalPacketLossEnabled)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .setGlobalPacketLoss(enabled: true))
        XCTAssertTrue(state.networkRuntime.state.globalPacketLossEnabled)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .globalPacketLossChanged)

        TopologyEditorReducer.reduce(state: &state, action: .stopSimulation)
        XCTAssertFalse(state.networkRuntime.state.globalPacketLossEnabled)
    }

    func testDesignConfigurationUpdatesRouterInterfacesAndRejectsWhileSimulationRuns() throws {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .router, at: CGPoint(x: 40, y: 60), to: &state)
        let router = try XCTUnwrap(state.graph.node(withID: nodeID))
        let portID = try XCTUnwrap(router.ports.first?.id)
        let interface = TopologyDesignInterfaceConfiguration(
            id: portID,
            ipAddress: "172.16.0.1",
            subnetMask: "255.255.0.0"
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveDesignDeviceConfiguration(
                nodeID: nodeID,
                displayName: "Backbone",
                hostLabelPolicy: nil,
                deviceConfiguration: nil,
                interfaceConfigurations: [interface],
                switchConfiguration: nil,
                remoteLinkConfiguration: nil,
                hostWirelessConfiguration: nil
            )
        )

        let key = TopologyRuntimeInterfaceKey(nodeID: nodeID, portID: portID)
        XCTAssertEqual(state.graph.node(withID: nodeID)?.displayName, "Backbone")
        XCTAssertEqual(
            state.runtimeInterfaceConfigurations[key],
            TopologyRuntimeInterfaceConfiguration(ipAddress: "172.16.0.1", subnetMask: "255.255.0.0")
        )
        XCTAssertNil(state.lastValidationError)

        state.simulationPhase = .running
        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveDesignDeviceConfiguration(
                nodeID: nodeID,
                displayName: "Should Not Apply",
                hostLabelPolicy: nil,
                deviceConfiguration: nil,
                interfaceConfigurations: [interface],
                switchConfiguration: nil,
                remoteLinkConfiguration: nil,
                hostWirelessConfiguration: nil
            )
        )

        XCTAssertEqual(state.graph.node(withID: nodeID)?.displayName, "Backbone")
        XCTAssertEqual(state.lastValidationError, .simulationMustBeStopped)
    }

    func testDesignConfigurationRenamesSwitchWithoutFabricatingNetworkConfiguration() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 40, y: 60), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveDesignDeviceConfiguration(
                nodeID: nodeID,
                displayName: "Verteiler 1",
                hostLabelPolicy: nil,
                deviceConfiguration: nil,
                interfaceConfigurations: [],
                switchConfiguration: TopologySwitchConfiguration(ssid: "Klassenraum", retentionTimeMilliseconds: 90_000),
                remoteLinkConfiguration: nil,
                hostWirelessConfiguration: nil
            )
        )

        XCTAssertEqual(state.graph.node(withID: nodeID)?.displayName, "Verteiler 1")
        XCTAssertNil(state.runtimeDeviceConfigurations[nodeID])
        XCTAssertEqual(
            state.switchConfigurationsByNodeID[nodeID],
            TopologySwitchConfiguration(ssid: "Klassenraum", retentionTimeMilliseconds: 90_000)
        )
        XCTAssertNil(state.lastValidationError)
    }

    func testNewRemoteLinksUseUniqueSixDigitShareCodes() throws {
        var state = TopologyEditorState()
        let firstNodeID = uuid("ABCD0000-0000-0000-0000-000000000001")
        let secondNodeID = uuid("ABCD0000-0000-0000-0000-000000000002")

        addNode(kind: .remoteLink, at: CGPoint(x: 40, y: 60), nodeID: firstNodeID, to: &state)
        addNode(kind: .remoteLink, at: CGPoint(x: 120, y: 60), nodeID: secondNodeID, to: &state)

        let firstCode = try XCTUnwrap(state.remoteLinkConfigurationsByNodeID[firstNodeID]?.pairIdentifier)
        let secondCode = try XCTUnwrap(state.remoteLinkConfigurationsByNodeID[secondNodeID]?.pairIdentifier)

        XCTAssertEqual(firstCode.count, 6)
        XCTAssertTrue(firstCode.utf8.allSatisfy { $0 >= 48 && $0 <= 57 })
        XCTAssertEqual(secondCode.count, 6)
        XCTAssertTrue(secondCode.utf8.allSatisfy { $0 >= 48 && $0 <= 57 })
        XCTAssertNotEqual(firstCode, secondCode)
    }

    func testDesignConfigurationPreservesLocalNetworkRemoteLinkSettings() throws {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .remoteLink, at: CGPoint(x: 40, y: 60), to: &state)
        let configuration = TopologyRemoteLinkConfiguration(
            pairIdentifier: "  classroom-link  ",
            latencyMilliseconds: 125,
            isEnabled: true,
            transportMode: .localNetwork,
            lanRole: .join,
            lanPort: 12_345,
            lanJoinMethod: .manual,
            lanRemoteHost: "  192.168.1.44  ",
            lanRemotePort: 23_456
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveDesignDeviceConfiguration(
                nodeID: nodeID,
                displayName: "Remote Classroom",
                hostLabelPolicy: nil,
                deviceConfiguration: nil,
                interfaceConfigurations: [],
                switchConfiguration: nil,
                remoteLinkConfiguration: configuration,
                hostWirelessConfiguration: nil
            )
        )

        XCTAssertNil(state.lastValidationError)
        XCTAssertEqual(state.graph.node(withID: nodeID)?.displayName, "Remote Classroom")
        XCTAssertEqual(
            try XCTUnwrap(state.remoteLinkConfigurationsByNodeID[nodeID]),
            TopologyRemoteLinkConfiguration(
                pairIdentifier: "classroom-link",
                latencyMilliseconds: 125,
                isEnabled: true,
                transportMode: .localNetwork,
                lanRole: .join,
                lanPort: 12_345,
                lanJoinMethod: .manual,
                lanRemoteHost: "192.168.1.44",
                lanRemotePort: 23_456
            )
        )
    }

    func testDesignConfigurationRejectsInvalidManualLocalNetworkRemoteLinkEndpoint() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .remoteLink, at: CGPoint(x: 40, y: 60), to: &state)
        let originalConfiguration = state.remoteLinkConfigurationsByNodeID[nodeID]

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveDesignDeviceConfiguration(
                nodeID: nodeID,
                displayName: "Invalid Remote",
                hostLabelPolicy: nil,
                deviceConfiguration: nil,
                interfaceConfigurations: [],
                switchConfiguration: nil,
                remoteLinkConfiguration: TopologyRemoteLinkConfiguration(
                    pairIdentifier: "classroom-link",
                    transportMode: .localNetwork,
                    lanRole: .join,
                    lanJoinMethod: .manual,
                    lanRemoteHost: "   ",
                    lanRemotePort: 0
                ),
                hostWirelessConfiguration: nil
            )
        )

        XCTAssertEqual(state.lastValidationError, .invalidDeviceConfiguration)
        XCTAssertEqual(state.remoteLinkConfigurationsByNodeID[nodeID], originalConfiguration)
        XCTAssertNotEqual(state.graph.node(withID: nodeID)?.displayName, "Invalid Remote")
    }

    func testDesignConfigurationAssociatesWirelessPCBySSIDAndReservesItsPort() throws {
        var state = TopologyEditorState()
        let switchID = addNode(kind: .networkSwitch, at: CGPoint(x: 20, y: 20), to: &state)
        state.switchConfigurationsByNodeID[switchID] = TopologySwitchConfiguration(ssid: "Lab-WLAN")
        let pcID = addNode(kind: .pc, at: CGPoint(x: 80, y: 20), to: &state)
        let pc = try XCTUnwrap(state.graph.node(withID: pcID))

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveDesignDeviceConfiguration(
                nodeID: pcID,
                displayName: "Wireless PC",
                hostLabelPolicy: nil,
                deviceConfiguration: TopologyRuntimeDeviceConfiguration(
                    ipAddress: "192.168.50.10", subnetMask: "255.255.255.0"
                ),
                interfaceConfigurations: [],
                switchConfiguration: nil,
                remoteLinkConfiguration: nil,
                hostWirelessConfiguration: TopologyHostWirelessConfiguration(isEnabled: true, ssid: "Lab-WLAN")
            )
        )

        XCTAssertNil(state.lastValidationError)
        XCTAssertEqual(state.wirelessAssociations().first?.hostNodeID, pcID)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: pcID, portID: pc.ports.first?.id)
        )
        XCTAssertEqual(state.lastValidationError, .noFreePort)
    }

    func testSelectNodesInRectangleSelectsOnlyMembers() {
        var state = TopologyEditorState()

        let insideA = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)
        let insideB = addNode(kind: .networkSwitch, at: CGPoint(x: 90, y: 80), to: &state)
        _ = addNode(kind: .pc, at: CGPoint(x: 160, y: 160), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .selectNodes(in: CGRect(x: 0, y: 0, width: 120, height: 120))
        )

        XCTAssertEqual(state.selectedNodeIDs, [insideA, insideB])
        XCTAssertNil(state.lastValidationError)
    }

    func testSelectNodesWithZeroAreaRectangleReturnsEmptySelection() {
        var state = TopologyEditorState()
        _ = addNode(kind: .pc, at: CGPoint(x: 40, y: 60), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .selectNodes(in: CGRect(x: 0, y: 0, width: 0, height: 0))
        )

        XCTAssertTrue(state.selectedNodeIDs.isEmpty)
        XCTAssertNil(state.lastValidationError)
    }

    func testStartAndCompleteConnectionAddsLinkAndClearsDraft() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let targetNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 150, y: 20), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: sourceNodeID, portID: nil)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .completeConnection(nodeID: targetNodeID, portID: nil)
        )

        XCTAssertEqual(state.graph.links.count, 1)
        XCTAssertNil(state.pendingConnection)
        XCTAssertEqual(state.selectedNodeIDs, [sourceNodeID, targetNodeID])
        XCTAssertNil(state.lastValidationError)
    }

    func testRouterAndGatewayDefaultPortsMatchJavaConstructorShape() {
        let router = TopologyNode(id: UUID(), kind: .router, position: .zero)
        let gateway = TopologyNode(id: UUID(), kind: .gateway, position: .zero)

        XCTAssertEqual(router.ports.map(\.label), ["rt1"])
        XCTAssertEqual(gateway.ports.map(\.label), ["wan0", "lan0"])
    }

    func testPlacingRouterAndGatewaySeedsExactJavaInterfaceDefaults() {
        var state = TopologyEditorState()
        let routerNodeID = addNode(
            kind: .router,
            at: CGPoint(x: 100, y: 100),
            nodeID: uuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            to: &state
        )
        let gatewayNodeID = addNode(
            kind: .gateway,
            at: CGPoint(x: 300, y: 100),
            nodeID: uuid("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
            to: &state
        )

        let router = tryUnwrap(state.graph.node(withID: routerNodeID))
        let gateway = tryUnwrap(state.graph.node(withID: gatewayNodeID))
        let routerConfiguration = state.runtimeInterfaceConfigurations[
            TopologyRuntimeInterfaceKey(nodeID: routerNodeID, portID: router.ports[0].id)
        ]
        let gatewayWANConfiguration = state.runtimeInterfaceConfigurations[
            TopologyRuntimeInterfaceKey(nodeID: gatewayNodeID, portID: gateway.ports[0].id)
        ]
        let gatewayLANConfiguration = state.runtimeInterfaceConfigurations[
            TopologyRuntimeInterfaceKey(nodeID: gatewayNodeID, portID: gateway.ports[1].id)
        ]

        XCTAssertEqual(
            routerConfiguration,
            TopologyRuntimeInterfaceConfiguration(
                ipAddress: "192.168.0.10",
                subnetMask: "255.255.255.0"
            )
        )
        XCTAssertEqual(
            gatewayWANConfiguration,
            TopologyRuntimeInterfaceConfiguration(
                ipAddress: "42.0.0.10",
                subnetMask: "255.0.0.0"
            )
        )
        XCTAssertEqual(
            gatewayLANConfiguration,
            TopologyRuntimeInterfaceConfiguration(
                ipAddress: "192.168.0.10",
                subnetMask: "255.255.255.0"
            )
        )
    }

    func testRouterInterfaceConfigurationCanBeEditedWithoutChangingPCConfigurationModel() {
        var state = TopologyEditorState()
        let routerNodeID = addNode(kind: .router, at: CGPoint(x: 100, y: 100), to: &state)
        let router = tryUnwrap(state.graph.node(withID: routerNodeID))
        let portID = router.ports[0].id

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeInterfaceConfiguration(
                nodeID: routerNodeID,
                portID: portID,
                ipAddress: "10.0.0.1",
                subnetMask: "255.255.255.0"
            )
        )

        XCTAssertEqual(
            state.runtimeInterfaceConfigurations[
                TopologyRuntimeInterfaceKey(nodeID: routerNodeID, portID: portID)
            ],
            TopologyRuntimeInterfaceConfiguration(
                ipAddress: "10.0.0.1",
                subnetMask: "255.255.255.0"
            )
        )
        XCTAssertTrue(state.runtimeDeviceConfigurations.isEmpty)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeInterfaceConfigurationSaved)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testGatewayInterfaceConfigurationRejectsUnknownPort() {
        var state = TopologyEditorState()
        let gatewayNodeID = addNode(kind: .gateway, at: CGPoint(x: 100, y: 100), to: &state)
        let existingConfigurations = state.runtimeInterfaceConfigurations

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeInterfaceConfiguration(
                nodeID: gatewayNodeID,
                portID: UUID(),
                ipAddress: "10.0.0.1",
                subnetMask: "255.255.255.0"
            )
        )

        XCTAssertEqual(state.runtimeInterfaceConfigurations, existingConfigurations)
        XCTAssertEqual(state.lastRuntimeFault?.code, "runtimeInterfaceNotFound")
        XCTAssertEqual(
            state.lastRuntimeEvent?.code,
            .runtimeInterfaceConfigurationRejectedInvalidConfiguration
        )
    }

    func testPCConnectsToRouterAndGatewayInfrastructureEndpoints() {
        var state = TopologyEditorState()
        let firstPCNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let routerNodeID = addNode(kind: .router, at: CGPoint(x: 160, y: 20), to: &state)
        let secondPCNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 180), to: &state)
        let gatewayNodeID = addNode(kind: .gateway, at: CGPoint(x: 160, y: 180), to: &state)

        connect(firstPCNodeID, routerNodeID, state: &state)
        connect(secondPCNodeID, gatewayNodeID, state: &state)

        XCTAssertEqual(state.graph.links.count, 2)
        XCTAssertEqual(state.graph.node(withID: routerNodeID)?.ports.filter(\.isOccupied).count, 1)
        XCTAssertEqual(state.graph.node(withID: gatewayNodeID)?.ports.filter(\.isOccupied).count, 1)
    }

    func testRouterRejectsSecondLinkAfterSingleJavaParityPortIsOccupied() {
        var state = TopologyEditorState()
        let routerNodeID = addNode(kind: .router, at: CGPoint(x: 160, y: 80), to: &state)
        let firstPCNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let secondPCNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 160), to: &state)

        connect(firstPCNodeID, routerNodeID, state: &state)
        let graphAfterFirstLink = state.graph

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: routerNodeID, portID: nil)
        )

        XCTAssertEqual(state.graph, graphAfterFirstLink)
        XCTAssertNil(state.pendingConnection)
        XCTAssertEqual(state.lastValidationError, .noFreePort)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: secondPCNodeID, portID: nil)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .completeConnection(nodeID: routerNodeID, portID: nil)
        )

        XCTAssertEqual(state.graph, graphAfterFirstLink)
        XCTAssertEqual(state.lastValidationError, .noFreePort)
    }

    func testGatewayAcceptsExactlyTwoLinksInWANThenLANPortOrder() {
        var state = TopologyEditorState()
        let gatewayNodeID = addNode(kind: .gateway, at: CGPoint(x: 180, y: 100), to: &state)
        let firstPCNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let secondPCNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 100), to: &state)
        let thirdPCNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 180), to: &state)

        connect(firstPCNodeID, gatewayNodeID, state: &state)
        connect(secondPCNodeID, gatewayNodeID, state: &state)

        let gateway = tryUnwrap(state.graph.node(withID: gatewayNodeID))
        XCTAssertEqual(gateway.ports.map(\.label), ["wan0", "lan0"])
        XCTAssertEqual(gateway.ports.map(\.isOccupied), [true, true])
        XCTAssertEqual(state.graph.links.count, 2)
        let graphAfterTwoLinks = state.graph

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: thirdPCNodeID, portID: nil)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .completeConnection(nodeID: gatewayNodeID, portID: nil)
        )

        XCTAssertEqual(state.graph, graphAfterTwoLinks)
        XCTAssertEqual(state.lastValidationError, .noFreePort)
    }

    func testMultipleLinksBetweenSameNodesUseChosenFreePorts() throws {
        var state = TopologyEditorState()
        let firstID = addNode(kind: .networkSwitch, at: CGPoint(x: 30, y: 30), to: &state)
        let secondID = addNode(kind: .networkSwitch, at: CGPoint(x: 180, y: 30), to: &state)
        let first = try XCTUnwrap(state.graph.node(withID: firstID))
        let second = try XCTUnwrap(state.graph.node(withID: secondID))

        for index in 0...1 {
            TopologyEditorReducer.reduce(
                state: &state,
                action: .startConnection(nodeID: firstID, portID: first.ports[index].id)
            )
            TopologyEditorReducer.reduce(
                state: &state,
                action: .completeConnection(nodeID: secondID, portID: second.ports[index].id)
            )
            XCTAssertNil(state.lastValidationError)
        }

        XCTAssertEqual(state.graph.links.count, 2)
        XCTAssertEqual(Set(state.graph.links.map(\.sourcePortID)), Set(first.ports.prefix(2).map(\.id)))
        XCTAssertEqual(Set(state.graph.links.map(\.targetPortID)), Set(second.ports.prefix(2).map(\.id)))
    }

    func testDeletingSelectedCableReleasesBothPhysicalPorts() throws {
        var state = TopologyEditorState()
        let pcID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let switchID = addNode(kind: .networkSwitch, at: CGPoint(x: 180, y: 30), to: &state)
        connect(pcID, switchID, state: &state)
        let link = try XCTUnwrap(state.graph.links.first)

        TopologyEditorReducer.reduce(state: &state, action: .selectSingleLink(linkID: link.id))
        TopologyEditorReducer.reduce(state: &state, action: .deleteSelection)

        XCTAssertTrue(state.graph.links.isEmpty)
        XCTAssertFalse(state.graph.isPortConnected(nodeID: pcID, portID: link.sourcePortID))
        XCTAssertFalse(state.graph.isPortConnected(nodeID: switchID, portID: link.targetPortID))
        XCTAssertTrue(state.selectedLinkIDs.isEmpty)
        XCTAssertNil(state.lastValidationError)
    }

    func testDeletingNodeRemovesIncidentCablesAndDurableDeviceState() throws {
        var state = TopologyEditorState()
        let pcID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let switchID = addNode(kind: .networkSwitch, at: CGPoint(x: 180, y: 30), to: &state)
        connect(pcID, switchID, state: &state)
        let switchPortID = try XCTUnwrap(state.graph.links.first?.targetPortID)
        state.runtimeDeviceConfigurations[pcID] = TopologyRuntimeDeviceConfiguration(
            ipAddress: "10.0.0.2",
            subnetMask: "255.255.255.0"
        )

        TopologyEditorReducer.reduce(state: &state, action: .selectSingleNode(nodeID: pcID))
        TopologyEditorReducer.reduce(state: &state, action: .deleteSelection)

        XCTAssertFalse(state.graph.containsNode(id: pcID))
        XCTAssertTrue(state.graph.links.isEmpty)
        XCTAssertFalse(state.graph.isPortConnected(nodeID: switchID, portID: switchPortID))
        XCTAssertNil(state.runtimeDeviceConfigurations[pcID])
        XCTAssertNil(state.lastValidationError)
    }

    func testRouterInterfaceAddAndConnectedRemovalConfirmation() throws {
        var state = TopologyEditorState()
        let routerID = addNode(kind: .router, at: CGPoint(x: 30, y: 30), to: &state)
        let switchID = addNode(kind: .networkSwitch, at: CGPoint(x: 180, y: 30), to: &state)
        let newPortID = uuid("abababab-abab-abab-abab-abababababab")

        TopologyEditorReducer.reduce(
            state: &state,
            action: .addRouterInterface(nodeID: routerID, portID: newPortID)
        )
        let router = try XCTUnwrap(state.graph.node(withID: routerID))
        XCTAssertEqual(router.ports.map(\.label), ["rt1", "rt2"])
        XCTAssertNotNil(
            state.runtimeInterfaceConfigurations[
                TopologyRuntimeInterfaceKey(nodeID: routerID, portID: newPortID)
            ]
        )

        let switchPortID = try XCTUnwrap(state.graph.node(withID: switchID)?.ports.first?.id)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: routerID, portID: newPortID)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .completeConnection(nodeID: switchID, portID: switchPortID)
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .removeRouterInterface(nodeID: routerID, portID: newPortID, confirmed: false)
        )
        XCTAssertEqual(state.lastValidationError, .connectedPortRemovalRequiresConfirmation)
        XCTAssertEqual(state.graph.links.count, 1)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .removeRouterInterface(nodeID: routerID, portID: newPortID, confirmed: true)
        )
        XCTAssertEqual(state.graph.node(withID: routerID)?.ports.map(\.label), ["rt1"])
        XCTAssertTrue(state.graph.links.isEmpty)
        XCTAssertNil(
            state.runtimeInterfaceConfigurations[
                TopologyRuntimeInterfaceKey(nodeID: routerID, portID: newPortID)
            ]
        )
        XCTAssertNil(state.lastValidationError)
    }

    func testUserCreatedRouterSupportsThreeConfiguredConnectedInterfaces() throws {
        var state = TopologyEditorState()
        let routerID = addNode(kind: .router, at: CGPoint(x: 40, y: 120), to: &state)
        let switchIDs = [
            addNode(kind: .networkSwitch, at: CGPoint(x: 240, y: 40), to: &state),
            addNode(kind: .networkSwitch, at: CGPoint(x: 240, y: 120), to: &state),
            addNode(kind: .networkSwitch, at: CGPoint(x: 240, y: 200), to: &state),
        ]
        let addedPortIDs = [
            uuid("81000000-0000-0000-0000-000000000001"),
            uuid("81000000-0000-0000-0000-000000000002"),
        ]
        for portID in addedPortIDs {
            TopologyEditorReducer.reduce(
                state: &state,
                action: .addRouterInterface(nodeID: routerID, portID: portID)
            )
        }

        let router = try XCTUnwrap(state.graph.node(withID: routerID))
        XCTAssertEqual(router.ports.map(\.label), ["rt1", "rt2", "rt3"])
        let configurations = router.ports.enumerated().map { index, port in
            TopologyDesignInterfaceConfiguration(
                id: port.id,
                ipAddress: "10.\(index + 1).0.1",
                subnetMask: "255.255.255.0"
            )
        }
        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveDesignDeviceConfiguration(
                nodeID: routerID,
                displayName: "Classroom Router",
                hostLabelPolicy: nil,
                deviceConfiguration: nil,
                interfaceConfigurations: configurations,
                switchConfiguration: nil,
                remoteLinkConfiguration: nil,
                hostWirelessConfiguration: nil
            )
        )
        XCTAssertNil(state.lastValidationError)
        XCTAssertEqual(state.graph.node(withID: routerID)?.displayName, "Classroom Router")

        for (index, port) in router.ports.enumerated() {
            let switchPortID = try XCTUnwrap(state.graph.node(withID: switchIDs[index])?.ports.first?.id)
            TopologyEditorReducer.reduce(
                state: &state,
                action: .startConnection(nodeID: routerID, portID: port.id)
            )
            TopologyEditorReducer.reduce(
                state: &state,
                action: .completeConnection(nodeID: switchIDs[index], portID: switchPortID)
            )
        }

        XCTAssertEqual(state.graph.links.count, 3)
        XCTAssertTrue(router.ports.allSatisfy { state.graph.isPortConnected(nodeID: routerID, portID: $0.id) })
        for configuration in configurations {
            XCTAssertEqual(
                state.runtimeInterfaceConfigurations[
                    TopologyRuntimeInterfaceKey(nodeID: routerID, portID: configuration.id)
                ],
                TopologyRuntimeInterfaceConfiguration(
                    ipAddress: configuration.ipAddress,
                    subnetMask: configuration.subnetMask
                )
            )
        }
    }

    func testGatewayRejectsInterfaceMutationAndPreservesWANLANOrder() throws {
        var state = TopologyEditorState()
        let gatewayID = addNode(kind: .gateway, at: CGPoint(x: 120, y: 120), to: &state)
        let originalPorts = try XCTUnwrap(state.graph.node(withID: gatewayID)?.ports)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .addRouterInterface(
                nodeID: gatewayID,
                portID: uuid("82000000-0000-0000-0000-000000000001")
            )
        )
        XCTAssertEqual(state.lastValidationError, .unsupportedConfiguration)
        XCTAssertEqual(state.graph.node(withID: gatewayID)?.ports, originalPorts)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .removeRouterInterface(
                nodeID: gatewayID,
                portID: originalPorts[0].id,
                confirmed: true
            )
        )
        XCTAssertEqual(state.lastValidationError, .unsupportedConfiguration)
        XCTAssertEqual(state.graph.node(withID: gatewayID)?.ports.map(\.label), ["wan0", "lan0"])
    }

    func testNoFreePortRejectedWithoutMutatingGraph() {
        var state = TopologyEditorState()

        let saturatedPCNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let switchAID = addNode(kind: .networkSwitch, at: CGPoint(x: 180, y: 30), to: &state)
        let switchBID = addNode(kind: .networkSwitch, at: CGPoint(x: 340, y: 30), to: &state)

        connect(saturatedPCNodeID, switchAID, state: &state)
        let snapshot = state.graph

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: saturatedPCNodeID, portID: nil)
        )

        XCTAssertEqual(state.graph, snapshot)
        XCTAssertEqual(state.lastValidationError, .noFreePort)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: switchBID, portID: nil)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .completeConnection(nodeID: saturatedPCNodeID, portID: nil)
        )

        XCTAssertEqual(state.graph, snapshot)
        XCTAssertEqual(state.lastValidationError, .noFreePort)
    }

    func testPCClassEndpointsCanConnectDirectlyWithoutNetworkInfrastructure() {
        let endpointPairs: [(TopologyNodeKind, TopologyNodeKind)] = [
            (.pc, .pc),
            (.pc, .notebook),
            (.notebook, .notebook),
        ]

        for (sourceKind, targetKind) in endpointPairs {
            var state = TopologyEditorState()
            let sourceNodeID = addNode(kind: sourceKind, at: CGPoint(x: 50, y: 50), to: &state)
            let targetNodeID = addNode(kind: targetKind, at: CGPoint(x: 200, y: 50), to: &state)

            TopologyEditorReducer.reduce(
                state: &state,
                action: .startConnection(nodeID: sourceNodeID, portID: nil)
            )
            TopologyEditorReducer.reduce(
                state: &state,
                action: .completeConnection(nodeID: targetNodeID, portID: nil)
            )

            let link = tryUnwrap(state.graph.links.first)
            XCTAssertEqual(state.graph.links.count, 1, "Expected a direct cable for \(sourceKind) -> \(targetKind)")
            XCTAssertEqual(link.sourceNodeID, sourceNodeID)
            XCTAssertEqual(link.targetNodeID, targetNodeID)
            XCTAssertNil(state.pendingConnection)
            XCTAssertNil(state.lastValidationError)
        }
    }

    func testInvalidPortIdentifierRejected() {
        var state = TopologyEditorState()

        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: switchNodeID, portID: UUID())
        )

        XCTAssertEqual(state.lastValidationError, .invalidPortIdentifier)
        XCTAssertNil(state.pendingConnection)
    }

    func testConnectionToSelfRejected() {
        var state = TopologyEditorState()

        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: switchNodeID, portID: nil)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .completeConnection(nodeID: switchNodeID, portID: nil)
        )

        XCTAssertEqual(state.lastValidationError, .selfConnectionNotAllowed)
        XCTAssertTrue(state.graph.links.isEmpty)
    }

    func testConnectWithNonexistentNodeIdentifierRejected() {
        var state = TopologyEditorState()
        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: switchNodeID, portID: nil)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .completeConnection(nodeID: uuid("99999999-9999-9999-9999-999999999999"), portID: nil)
        )

        XCTAssertEqual(state.lastValidationError, .nodeNotFound)
        XCTAssertTrue(state.graph.links.isEmpty)
    }

    func testMalformedSelectionAndMovePayloadsAreRejected() {
        var state = TopologyEditorState()

        TopologyEditorReducer.reduce(state: &state, action: .selectNodes(in: nil))
        XCTAssertEqual(state.lastValidationError, .malformedActionPayload)

        TopologyEditorReducer.reduce(state: &state, action: .moveSelectedNodes(delta: nil))
        XCTAssertEqual(state.lastValidationError, .malformedActionPayload)
    }

    func testMoveSelectedNodesWithZeroDeltaDoesNotMutateGraph() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 40), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .selectSingleNode(nodeID: nodeID))
        let snapshot = state.graph

        TopologyEditorReducer.reduce(state: &state, action: .moveSelectedNodes(delta: .zero))

        XCTAssertEqual(state.graph, snapshot)
        XCTAssertNil(state.lastValidationError)
    }

    func testMoveSelectedNodeUpdatesLinkProjection() {
        var state = TopologyEditorState()

        let movingNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let anchorNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 200, y: 20), to: &state)
        connect(movingNodeID, anchorNodeID, state: &state)

        let linkID = tryUnwrap(state.graph.links.first?.id)
        let beforeProjection = tryUnwrap(state.graph.linkProjection(for: linkID))

        TopologyEditorReducer.reduce(state: &state, action: .selectSingleNode(nodeID: movingNodeID))
        TopologyEditorReducer.reduce(
            state: &state,
            action: .moveSelectedNodes(delta: CGSize(width: 40, height: 15))
        )

        let afterProjection = tryUnwrap(state.graph.linkProjection(for: linkID))
        XCTAssertEqual(afterProjection.source, CGPoint(x: 60, y: 35))
        XCTAssertEqual(afterProjection.target, beforeProjection.target)
        XCTAssertNotEqual(afterProjection, beforeProjection)
    }

    func testPanAndZoomUpdateViewportWithoutMutatingGraph() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 50, y: 50), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: nodeID))
        let graphSnapshot = state.graph

        TopologyEditorReducer.reduce(state: &state, action: .setActiveTool(mode: .connect))
        TopologyEditorReducer.reduce(state: &state, action: .panCanvas(delta: CGSize(width: 24, height: -12)))
        TopologyEditorReducer.reduce(
            state: &state,
            action: .zoomCanvas(scaleDelta: 1.5, anchor: CGPoint(x: 100, y: 100))
        )

        XCTAssertEqual(state.graph, graphSnapshot)
        XCTAssertNotEqual(state.viewport.offset, .zero)
        XCTAssertGreaterThan(state.viewport.scale, 1)
        XCTAssertEqual(state.activeTool, .connect)
        XCTAssertEqual(state.selectedNodeIDs, [nodeID])
        XCTAssertNil(state.lastValidationError)
    }

    func testMalformedViewportPayloadsAreRejectedAndDoNotChangeViewport() {
        var state = TopologyEditorState()
        let initialViewport = state.viewport

        TopologyEditorReducer.reduce(
            state: &state,
            action: .panCanvas(delta: CGSize(width: CGFloat.infinity, height: 10))
        )
        XCTAssertEqual(state.lastValidationError, .malformedActionPayload)
        XCTAssertEqual(state.viewport, initialViewport)

        TopologyEditorReducer.reduce(state: &state, action: .zoomCanvas(scaleDelta: 0, anchor: nil))
        XCTAssertEqual(state.lastValidationError, .malformedActionPayload)
        XCTAssertEqual(state.viewport, initialViewport)
    }

    func testStartSimulationIsIdempotentAndDeterministic() {
        var state = TopologyEditorState()

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        XCTAssertEqual(state.simulationPhase, .running)
        XCTAssertEqual(state.simulationTick, 0)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simulationStarted)
        XCTAssertNil(state.lastRuntimeFault)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        XCTAssertEqual(state.simulationPhase, .running)
        XCTAssertEqual(state.simulationTick, 0)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simulationStartIgnoredAlreadyRunning)
        XCTAssertEqual(state.lastAction, "startSimulation")
    }

    func testStartSimulationSeedsCommandPromptForAllPCNodes() {
        var state = TopologyEditorState()

        let firstPCNodeID = addNode(kind: .pc, at: CGPoint(x: 40, y: 40), to: &state)
        let secondPCNodeID = addNode(kind: .pc, at: CGPoint(x: 180, y: 40), to: &state)
        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 100, y: 140), to: &state)

        state.runtimeInstalledProgramsByNodeID[secondPCNodeID] = [.dnsServer]

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)

        XCTAssertEqual(state.runtimeInstalledProgramsByNodeID[firstPCNodeID], [.commandPrompt])
        XCTAssertEqual(state.runtimeInstalledProgramsByNodeID[secondPCNodeID], [.commandPrompt, .dnsServer])
        XCTAssertNil(state.runtimeInstalledProgramsByNodeID[switchNodeID])
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("seededCommandPrompts=2") ?? false)
    }

    func testSimulationTickMutatesOnlyRuntimeStateWhileRunning() {
        var state = TopologyEditorState()
        _ = addNode(kind: .pc, at: CGPoint(x: 50, y: 50), to: &state)

        let graphSnapshot = state.graph
        let selectedSnapshot = state.selectedNodeIDs
        let activeToolSnapshot = state.activeTool
        let pendingConnectionSnapshot = state.pendingConnection
        let viewportSnapshot = state.viewport

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .simulationTick(step: 3))

        XCTAssertEqual(state.simulationPhase, .running)
        XCTAssertEqual(state.simulationTick, 3)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simulationTickAdvanced)
        XCTAssertEqual(state.graph, graphSnapshot)
        XCTAssertEqual(state.selectedNodeIDs, selectedSnapshot)
        XCTAssertEqual(state.activeTool, activeToolSnapshot)
        XCTAssertEqual(state.pendingConnection, pendingConnectionSnapshot)
        XCTAssertEqual(state.viewport, viewportSnapshot)
    }

    func testSimulationTickPreservesInspectableDiagnosticsWhileRuntimeDeviceIsOpen() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 50, y: 50), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: nodeID))
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: nodeID, command: "route"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .routeRejectedMalformedCommand)
        XCTAssertEqual(state.lastRuntimeFault?.code, "malformedRouteCommand")
        let eventSnapshot = state.lastRuntimeEvent
        let faultSnapshot = state.lastRuntimeFault

        TopologyEditorReducer.reduce(state: &state, action: .simulationTick(step: 3))

        XCTAssertEqual(state.simulationTick, 3)
        XCTAssertEqual(state.lastRuntimeEvent, eventSnapshot)
        XCTAssertEqual(state.lastRuntimeFault, faultSnapshot)
    }

    func testSimulationTickWhileStoppedIsIgnored() {
        var state = TopologyEditorState()

        TopologyEditorReducer.reduce(state: &state, action: .simulationTick(step: 1))

        XCTAssertEqual(state.simulationPhase, .stopped)
        XCTAssertEqual(state.simulationTick, 0)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simulationTickIgnoredWhileStopped)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testSimulationTickWithMalformedPayloadDoesNotAdvanceTickAndSetsFault() {
        var state = TopologyEditorState()

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .simulationTick(step: 2))
        let snapshotTick = state.simulationTick

        TopologyEditorReducer.reduce(state: &state, action: .simulationTick(step: nil))

        XCTAssertEqual(state.simulationTick, snapshotTick)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simulationFaultRejectedMalformedPayload)
        XCTAssertEqual(state.lastRuntimeFault?.category, .malformedRuntimePayload)
        XCTAssertEqual(state.lastRuntimeFault?.code, "malformedRuntimePayload")
    }

    func testStopSimulationIsIdempotentAfterStartAndTick() {
        var state = TopologyEditorState()

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .simulationTick(step: 1))
        TopologyEditorReducer.reduce(state: &state, action: .stopSimulation)

        XCTAssertEqual(state.simulationPhase, .stopped)
        XCTAssertEqual(state.simulationTick, 1)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simulationStopped)

        TopologyEditorReducer.reduce(state: &state, action: .stopSimulation)

        XCTAssertEqual(state.simulationPhase, .stopped)
        XCTAssertEqual(state.simulationTick, 1)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simulationStopIgnoredAlreadyStopped)
    }

    func testOpenAndCloseRuntimeDeviceAreIdempotent() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: nodeID))
        XCTAssertEqual(state.openedRuntimeDeviceID, nodeID)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceOpened)

        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: nodeID))
        XCTAssertEqual(state.openedRuntimeDeviceID, nodeID)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceOpened)

        TopologyEditorReducer.reduce(state: &state, action: .closeRuntimeDevice)
        XCTAssertNil(state.openedRuntimeDeviceID)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceClosed)

        TopologyEditorReducer.reduce(state: &state, action: .closeRuntimeDevice)
        XCTAssertNil(state.openedRuntimeDeviceID)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceCloseIgnoredAlreadyClosed)
    }

    func testSaveRuntimeDeviceIPStoresNormalizedConfiguration() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeDeviceIP(nodeID: nodeID, ipAddress: " 192.168.001.010 ", subnetMask: "255.255.255.000")
        )

        XCTAssertEqual(
            state.runtimeDeviceConfigurations[nodeID],
            TopologyRuntimeDeviceConfiguration(ipAddress: "192.168.1.10", subnetMask: "255.255.255.0")
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceIPSaved)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testSaveRuntimeDeviceConfigurationNormalizesAndStoresDefaultGateway() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeDeviceConfiguration(
                nodeID: nodeID,
                ipAddress: " 42.0.0.20 ",
                subnetMask: " 255.0.0.0 ",
                defaultGateway: " 42.0.0.10 "
            )
        )

        XCTAssertEqual(
            state.runtimeDeviceConfigurations[nodeID],
            TopologyRuntimeDeviceConfiguration(
                ipAddress: "42.0.0.20",
                subnetMask: "255.0.0.0",
                defaultGateway: "42.0.0.10"
            )
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceIPSaved)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("gateway=42.0.0.10") ?? false)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testSaveRuntimeDeviceConfigurationUpdatesRunningNetworkSnapshot() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeDeviceConfiguration(
                nodeID: nodeID,
                ipAddress: "192.168.10.10",
                subnetMask: "255.255.255.0",
                defaultGateway: ""
            )
        )

        XCTAssertEqual(
            state.networkRuntime.state.topologySnapshot.deviceConfigurations[nodeID],
            TopologyRuntimeDeviceConfiguration(
                ipAddress: "192.168.10.10",
                subnetMask: "255.255.255.0"
            )
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceIPSaved)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testSaveRuntimeDeviceConfigurationAcceptsBlankDefaultGatewayAndRejectsInvalidValue() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)

        saveRuntimeConfiguration(
            nodeID: nodeID,
            ipAddress: "192.168.0.20",
            subnetMask: "255.255.255.0",
            defaultGateway: "   ",
            state: &state
        )
        XCTAssertEqual(state.runtimeDeviceConfigurations[nodeID]?.defaultGateway, "")
        let saved = state.runtimeDeviceConfigurations[nodeID]

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeDeviceConfiguration(
                nodeID: nodeID,
                ipAddress: "192.168.0.20",
                subnetMask: "255.255.255.0",
                defaultGateway: "999.1.1.1"
            )
        )

        XCTAssertEqual(state.runtimeDeviceConfigurations[nodeID], saved)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceIPRejectedInvalidConfiguration)
        XCTAssertEqual(state.lastRuntimeFault?.code, "invalidDefaultGateway")
    }

    func testSaveRuntimeDeviceIPRejectedForSwitchNodes() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 10, y: 10), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeDeviceIP(nodeID: nodeID, ipAddress: "192.168.1.10", subnetMask: "255.255.255.0")
        )

        XCTAssertNil(state.runtimeDeviceConfigurations[nodeID])
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceIPRejectedInvalidConfiguration)
        XCTAssertEqual(state.lastRuntimeFault?.code, "ipConfigurationUnsupportedForNodeKind")
    }

    func testInstallRuntimeProgramRegistersProgramForPCNode() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .installRuntimeProgram(nodeID: nodeID, program: .commandPrompt)
        )

        XCTAssertEqual(state.runtimeInstalledProgramsByNodeID[nodeID], [.commandPrompt])
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeProgramInstalled)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testInstallRuntimeGnutellaRollsBackWhenPeerToPeerInitializationFails() throws {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)
        let previousInstalledPrograms: Set<TopologyRuntimeInstallableProgram> = [.commandPrompt]
        let previousConfiguration = TopologyRuntimeGnutellaConfiguration(maximumKnownPeers: 7)
        var previousFileSystem = try XCTUnwrap(state.virtualFileSystemsByNodeID[nodeID])
        try previousFileSystem.writeTextFile(
            at: TopologyGnutella.peerToPeerDirectory,
            text: "blocks Gnutella directory creation",
            overwrite: false
        )
        state.runtimeInstalledProgramsByNodeID[nodeID] = previousInstalledPrograms
        state.runtimeGnutellaConfigurationsByNodeID[nodeID] = previousConfiguration
        state.virtualFileSystemsByNodeID[nodeID] = previousFileSystem
        let previousPersistenceRevision = state.persistenceRevision

        TopologyEditorReducer.reduce(
            state: &state,
            action: .installRuntimeProgram(nodeID: nodeID, program: .gnutella)
        )

        XCTAssertEqual(state.runtimeInstalledProgramsByNodeID[nodeID], previousInstalledPrograms)
        XCTAssertEqual(state.runtimeGnutellaConfigurationsByNodeID[nodeID], previousConfiguration)
        XCTAssertEqual(state.virtualFileSystemsByNodeID[nodeID], previousFileSystem)
        XCTAssertEqual(state.persistenceRevision, previousPersistenceRevision)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .gnutellaRejected)
        XCTAssertEqual(state.lastRuntimeFault?.category, .networkService)
        XCTAssertEqual(state.lastRuntimeFault?.code, "gnutellaInstallationRejected")
        XCTAssertFalse(
            state.runtimeConsoleEntriesByNodeID[nodeID]?.contains("Program installed: gnutella") == true
        )
    }

    func testRuntimeGnutellaCanJoinSearchAndDownloadAcrossConnectedPeers() throws {
        var state = TopologyEditorState()
        let peerA = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let peerB = addNode(kind: .pc, at: CGPoint(x: 300, y: 20), to: &state)
        let networkSwitch = addNode(kind: .networkSwitch, at: CGPoint(x: 160, y: 140), to: &state)
        connect(peerA, networkSwitch, state: &state)
        connect(peerB, networkSwitch, state: &state)
        saveRuntimeConfiguration(
            nodeID: peerA,
            ipAddress: "10.66.0.10",
            subnetMask: "255.255.255.0",
            defaultGateway: "",
            state: &state
        )
        saveRuntimeConfiguration(
            nodeID: peerB,
            ipAddress: "10.66.0.11",
            subnetMask: "255.255.255.0",
            defaultGateway: "",
            state: &state
        )

        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: peerA, program: .gnutella))
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: peerB, program: .gnutella))
        var peerBFileSystem = try XCTUnwrap(state.virtualFileSystemsByNodeID[peerB])
        try peerBFileSystem.writeTextFile(
            at: "/peer2peer/Lesson.txt",
            text: "Gnutella works end to end",
            overwrite: true
        )
        state.virtualFileSystemsByNodeID[peerB] = peerBFileSystem

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: peerB))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: peerB, program: .gnutella))
        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: peerA))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: peerA, program: .gnutella))

        XCTAssertTrue(state.runtimeGnutellaSessionsByNodeID[peerA]?.isRunning == true)
        XCTAssertTrue(state.runtimeGnutellaSessionsByNodeID[peerB]?.isRunning == true)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeGnutellaJoin(nodeID: peerA, bootstrapIPAddress: "10.66.0.11")
        )
        XCTAssertEqual(state.runtimeGnutellaSessionsByNodeID[peerA]?.knownPeers.map(\.host), ["10.66.0.11"])
        XCTAssertNil(state.lastRuntimeFault)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeGnutellaSearch(nodeID: peerA, searchTerm: "lesson")
        )
        let result = try XCTUnwrap(state.runtimeGnutellaSessionsByNodeID[peerA]?.searchResults.first)
        XCTAssertEqual(result.file.name, "Lesson.txt")
        XCTAssertEqual(result.peer.host, "10.66.0.11")
        XCTAssertNil(state.lastRuntimeFault)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeGnutellaDownload(nodeID: peerA, result: result)
        )
        XCTAssertEqual(
            try state.virtualFileSystemsByNodeID[peerA]?.textFile(at: "/peer2peer/Lesson.txt"),
            "Gnutella works end to end"
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .gnutellaDownloadCompleted)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testLaunchRuntimeProgramSuccessSetsActiveProgramAndRuntimeEvent() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .installRuntimeProgram(nodeID: nodeID, program: .commandPrompt)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .launchRuntimeProgram(nodeID: nodeID, program: .commandPrompt)
        )

        XCTAssertEqual(state.runtimeActiveProgramByNodeID[nodeID], .commandPrompt)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeProgramLaunched)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("node=\(nodeID.uuidString)") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("program=commandPrompt") ?? false)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testLaunchRuntimeProgramLifecycleEmitsDeterministicOrderedEvents() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .installRuntimeProgram(nodeID: nodeID, program: .commandPrompt)
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeProgramInstalled)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("node=\(nodeID.uuidString)") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("program=commandPrompt") ?? false)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .launchRuntimeProgram(nodeID: nodeID, program: .commandPrompt)
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeProgramLaunched)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("node=\(nodeID.uuidString)") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("program=commandPrompt") ?? false)

        TopologyEditorReducer.reduce(state: &state, action: .closeRuntimeProgram(nodeID: nodeID))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeProgramClosed)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("node=\(nodeID.uuidString)") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("program=commandPrompt") ?? false)

        TopologyEditorReducer.reduce(state: &state, action: .closeRuntimeProgram(nodeID: nodeID))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeProgramCloseIgnoredAlreadyDesktop)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("node=\(nodeID.uuidString)") ?? false)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testLaunchRuntimeProgramRelaunchFocusesWithoutDuplicatingState() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .installRuntimeProgram(nodeID: nodeID, program: .commandPrompt)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .launchRuntimeProgram(nodeID: nodeID, program: .commandPrompt)
        )

        let snapshot = state.runtimeActiveProgramByNodeID

        TopologyEditorReducer.reduce(
            state: &state,
            action: .launchRuntimeProgram(nodeID: nodeID, program: .commandPrompt)
        )

        XCTAssertEqual(state.runtimeActiveProgramByNodeID, snapshot)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeProgramFocusedAlreadyActive)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testCloseRuntimeProgramReturnsToDesktopAndNoopIsDeterministic() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .installRuntimeProgram(nodeID: nodeID, program: .commandPrompt)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .launchRuntimeProgram(nodeID: nodeID, program: .commandPrompt)
        )
        TopologyEditorReducer.reduce(state: &state, action: .closeRuntimeProgram(nodeID: nodeID))

        XCTAssertNil(state.runtimeActiveProgramByNodeID[nodeID])
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeProgramClosed)
        XCTAssertNil(state.lastRuntimeFault)

        TopologyEditorReducer.reduce(state: &state, action: .closeRuntimeProgram(nodeID: nodeID))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeProgramCloseIgnoredAlreadyDesktop)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testLaunchRuntimeProgramRejectsMalformedAndNonInstalledRequests() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nil, program: .commandPrompt))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeProgramLaunchRejectedMalformedPayload)
        XCTAssertEqual(state.lastRuntimeEvent?.detail, "missingNodeID")
        XCTAssertEqual(state.lastRuntimeFault?.code, "runtimeProgramLaunchMalformedPayload")

        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: nil))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeProgramLaunchRejectedMalformedPayload)
        XCTAssertEqual(state.lastRuntimeEvent?.detail, "missingProgram")
        XCTAssertEqual(state.lastRuntimeFault?.code, "runtimeProgramLaunchMalformedPayload")

        TopologyEditorReducer.reduce(
            state: &state,
            action: .launchRuntimeProgram(nodeID: nodeID, program: .webServer)
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeProgramLaunchRejectedNotInstalled)
        XCTAssertEqual(state.lastRuntimeEvent?.detail, "program=webServer")
        XCTAssertEqual(state.lastRuntimeFault?.code, "runtimeProgramNotInstalled")
        XCTAssertNil(state.runtimeActiveProgramByNodeID[nodeID])
    }

    func testLaunchRuntimeProgramRejectsUnknownNodeAndCloseUnknownNode() {
        var state = TopologyEditorState()
        let unknownNodeID = uuid("99999999-9999-9999-9999-999999999999")

        TopologyEditorReducer.reduce(
            state: &state,
            action: .launchRuntimeProgram(nodeID: unknownNodeID, program: .commandPrompt)
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeProgramLaunchRejectedUnknownNode)
        XCTAssertEqual(state.lastRuntimeFault?.code, "runtimeDeviceNotFound")

        TopologyEditorReducer.reduce(state: &state, action: .closeRuntimeProgram(nodeID: unknownNodeID))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeProgramCloseRejectedUnknownNode)
        XCTAssertEqual(state.lastRuntimeFault?.code, "runtimeDeviceNotFound")
    }

    func testOpenRuntimeDeviceClearsActiveProgramWhenProgramIsNotInstalled() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)

        state.runtimeInstalledProgramsByNodeID[nodeID] = [.commandPrompt]
        state.runtimeActiveProgramByNodeID[nodeID] = .webServer

        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: nodeID))

        XCTAssertNil(state.runtimeActiveProgramByNodeID[nodeID])
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceOpened)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testOpenRuntimeDeviceWithoutInstalledProgramsKeepsDesktopStateDeterministic() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: nodeID))

        XCTAssertEqual(state.openedRuntimeDeviceID, nodeID)
        XCTAssertNil(state.runtimeInstalledProgramsByNodeID[nodeID])
        XCTAssertNil(state.runtimeActiveProgramByNodeID[nodeID])
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceOpened)
    }

    func testRuntimeProgramLaunchStateResetsOnSimulationStopAndRuntimeDeviceContextChange() {
        var state = TopologyEditorState()
        let firstNodeID = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)
        let secondNodeID = addNode(kind: .pc, at: CGPoint(x: 80, y: 10), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .installRuntimeProgram(nodeID: firstNodeID, program: .commandPrompt)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .launchRuntimeProgram(nodeID: firstNodeID, program: .commandPrompt)
        )

        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: firstNodeID))
        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: secondNodeID))

        XCTAssertNil(state.runtimeActiveProgramByNodeID[firstNodeID])

        TopologyEditorReducer.reduce(state: &state, action: .stopSimulation)

        XCTAssertTrue(state.runtimeActiveProgramByNodeID.isEmpty)
        XCTAssertNil(state.openedRuntimeDeviceID)
    }

    func testRuntimeProgramLaunchActionsAreTransientAndDoNotAdvancePersistenceRevision() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .installRuntimeProgram(nodeID: nodeID, program: .commandPrompt)
        )
        let revisionAfterInstall = state.persistenceRevision

        TopologyEditorReducer.reduce(
            state: &state,
            action: .launchRuntimeProgram(nodeID: nodeID, program: .commandPrompt)
        )
        XCTAssertEqual(state.persistenceRevision, revisionAfterInstall)

        TopologyEditorReducer.reduce(state: &state, action: .closeRuntimeProgram(nodeID: nodeID))
        XCTAssertEqual(state.persistenceRevision, revisionAfterInstall)

        let snapshot = tryUnwrap(try? TopologyProjectSnapshot(state: state))
        let encodedSnapshot = tryUnwrap(try? JSONEncoder().encode(snapshot))
        let snapshotObject = tryUnwrap(try? JSONSerialization.jsonObject(with: encodedSnapshot) as? [String: Any])

        XCTAssertNil(snapshotObject["runtimeActiveProgramByNodeID"])

        let restoredState = tryUnwrap(try? snapshot.toEditorState())
        XCTAssertTrue(restoredState.runtimeActiveProgramByNodeID.isEmpty)
    }

    func testLaunchShellInvariantsRemainStableAcrossExpandedRuntimeCommands() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 280, y: 30), to: &state)
        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 150, y: 100), to: &state)

        connect(sourceNodeID, switchNodeID, state: &state)
        connect(targetNodeID, switchNodeID, state: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.1.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "192.168.1.20", subnetMask: "255.255.255.0", state: &state)

        startLocalDNSServer(nodeID: sourceNodeID, state: &state)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .installRuntimeProgram(nodeID: sourceNodeID, program: .commandPrompt)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .launchRuntimeProgram(nodeID: sourceNodeID, program: .commandPrompt)
        )

        XCTAssertEqual(state.runtimeActiveProgramByNodeID[sourceNodeID], .commandPrompt)

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "help"))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeHelpDisplayed)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "dns add shell.lab 192.168.1.20")
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsRecordRegistered)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "ping shell.lab")
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .pingSucceeded)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "trace shell.lab")
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .traceSucceeded)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "route shell.lab")
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .routeSucceeded)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "dhcp lease 192.168.1.10 255.255.255.0")
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dhcpLeaseAssigned)

        XCTAssertEqual(state.runtimeActiveProgramByNodeID[sourceNodeID], .commandPrompt)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testDesktopSuiteProgramsUseSharedVirtualFileSystem() throws {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 40, y: 40), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: nodeID))
        XCTAssertNotNil(state.virtualFileSystemsByNodeID[nodeID])

        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .fileExplorer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .fileExplorer))
        XCTAssertTrue(state.virtualFileSystemsByNodeID[nodeID]?.contains(state.runtimeFileExplorerSelectionByNodeID[nodeID] ?? "") == true)

        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .imageViewer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .imageViewer))
        let imagePath = try XCTUnwrap(state.runtimeImageViewerSelectionByNodeID[nodeID])
        XCTAssertTrue(try XCTUnwrap(state.virtualFileSystemsByNodeID[nodeID]).entry(at: imagePath).content.isImage)

        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .textEditor))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .textEditor))
        let textPath = try XCTUnwrap(state.runtimeTextEditorSelectionByNodeID[nodeID])
        let storedText = try XCTUnwrap(state.virtualFileSystemsByNodeID[nodeID]).textFile(at: textPath)
        XCTAssertEqual(state.runtimeTextEditorDraftByNodeID[nodeID], storedText)
    }

    func testDefaultVirtualImagesAreDistinctRenderableAndNonBlack() throws {
        let fileSystem = TopologyVirtualFileSystem.defaultForDevice()
        let imagePaths = [
            "/images/network-map.png",
            "/images/traffic-heatmap.png",
            "/images/switch-backplane.png",
        ]
        var payloads: [Data] = []

        for path in imagePaths {
            let imageFile = try fileSystem.imageFile(at: path)
            let image = try XCTUnwrap(UIImage(data: imageFile.data), "Expected \(path) to decode as a PNG")

            XCTAssertEqual(imageFile.mediaType, "image/png")
            XCTAssertGreaterThan(image.size.width, 1)
            XCTAssertGreaterThan(image.size.height, 1)
            XCTAssertTrue(imageContainsVisibleColor(image), "Expected \(path) to contain visible non-black pixels")
            payloads.append(imageFile.data)
        }

        XCTAssertEqual(Set(payloads).count, imagePaths.count, "Default Image Viewer files must not reuse one placeholder image")
    }

    func testStartingSimulationUpgradesLegacyBlackDefaultImages() throws {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 40, y: 40), to: &state)
        let legacyImageData = try XCTUnwrap(
            Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
        )
        let imagePaths = [
            "/images/network-map.png",
            "/images/traffic-heatmap.png",
            "/images/switch-backplane.png",
        ]
        var fileSystem = TopologyVirtualFileSystem()
        try fileSystem.createDirectory(at: "/images")
        for path in imagePaths {
            try fileSystem.writeImageFile(at: path, data: legacyImageData, mediaType: "image/png")
        }
        state.virtualFileSystemsByNodeID[nodeID] = fileSystem

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)

        let upgradedFileSystem = try XCTUnwrap(state.virtualFileSystemsByNodeID[nodeID])
        let upgradedPayloads = try imagePaths.map { path in
            try upgradedFileSystem.imageFile(at: path).data
        }
        XCTAssertTrue(upgradedPayloads.allSatisfy { $0 != legacyImageData })
        XCTAssertEqual(Set(upgradedPayloads).count, imagePaths.count)
    }

    func testTextEditorSelectingAnotherFileReplacesThePreviousSelection() throws {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 40, y: 40), to: &state)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: nodeID))
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .textEditor))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .textEditor))

        let defaultPath = try XCTUnwrap(state.runtimeTextEditorSelectionByNodeID[nodeID])
        let selectedPath = "/home/topology-exports.csv"
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeTextEditorSelectFile(nodeID: nodeID, path: selectedPath)
        )

        XCTAssertNotEqual(defaultPath, selectedPath)
        XCTAssertEqual(state.runtimeTextEditorSelectionByNodeID[nodeID], selectedPath)
        XCTAssertEqual(
            state.runtimeTextEditorDraftByNodeID[nodeID],
            try state.virtualFileSystemsByNodeID[nodeID]?.textFile(at: selectedPath)
        )
    }

    func testFileExplorerMutationsAndTextEditorSharePersistedFiles() throws {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 50, y: 50), to: &state)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: nodeID))
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .fileExplorer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .fileExplorer))

        TopologyEditorReducer.reduce(state: &state, action: .runtimeFileSystemCreateDirectory(nodeID: nodeID, path: "/work"))
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeFileSystemCreateTextFile(nodeID: nodeID, path: "/work/note.txt", text: "one")
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeFileSystemCopyItem(nodeID: nodeID, sourcePath: "/work/note.txt", destinationPath: "/work/copy.txt")
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeFileSystemMoveItem(nodeID: nodeID, sourcePath: "/work/copy.txt", destinationPath: "/home/moved.txt")
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeFileSystemRenameItem(nodeID: nodeID, path: "/home/moved.txt", newName: "renamed.txt")
        )
        XCTAssertEqual(try state.virtualFileSystemsByNodeID[nodeID]?.textFile(at: "/home/renamed.txt"), "one")

        TopologyEditorReducer.reduce(state: &state, action: .closeRuntimeProgram(nodeID: nodeID))
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .textEditor))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .textEditor))
        TopologyEditorReducer.reduce(state: &state, action: .runtimeTextEditorSelectFile(nodeID: nodeID, path: "/home/renamed.txt"))
        TopologyEditorReducer.reduce(state: &state, action: .runtimeTextEditorUpdateDraft(nodeID: nodeID, text: "two"))
        TopologyEditorReducer.reduce(state: &state, action: .runtimeTextEditorSaveDraft(nodeID: nodeID))
        XCTAssertEqual(try state.virtualFileSystemsByNodeID[nodeID]?.textFile(at: "/home/renamed.txt"), "two")

        TopologyEditorReducer.reduce(state: &state, action: .closeRuntimeProgram(nodeID: nodeID))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .fileExplorer))
        TopologyEditorReducer.reduce(state: &state, action: .runtimeFileSystemDeleteItem(nodeID: nodeID, path: "/work", recursive: true))
        XCTAssertFalse(try XCTUnwrap(state.virtualFileSystemsByNodeID[nodeID]).contains("/work"))
    }

    func testUnrelatedFileExplorerMutationPreservesUnsavedTextEditorDraft() throws {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 50, y: 50), to: &state)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: nodeID))
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .textEditor))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .textEditor))
        let path = try XCTUnwrap(state.runtimeTextEditorSelectionByNodeID[nodeID])
        let storedText = try XCTUnwrap(state.virtualFileSystemsByNodeID[nodeID]).textFile(at: path)
        TopologyEditorReducer.reduce(state: &state, action: .runtimeTextEditorUpdateDraft(nodeID: nodeID, text: "unsaved"))

        TopologyEditorReducer.reduce(state: &state, action: .closeRuntimeProgram(nodeID: nodeID))
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .fileExplorer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .fileExplorer))
        TopologyEditorReducer.reduce(state: &state, action: .runtimeFileSystemCreateDirectory(nodeID: nodeID, path: "/unrelated"))
        TopologyEditorReducer.reduce(state: &state, action: .closeRuntimeProgram(nodeID: nodeID))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .textEditor))

        XCTAssertEqual(state.runtimeTextEditorDraftByNodeID[nodeID], "unsaved")
        XCTAssertEqual(try state.virtualFileSystemsByNodeID[nodeID]?.textFile(at: path), storedText)
    }

    func testVirtualFileSystemActionsRejectInvalidContextAndEscapingPaths() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 50, y: 50), to: &state)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: nodeID))
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .fileExplorer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .fileExplorer))

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeFileSystemCreateTextFile(nodeID: nodeID, path: "/../../escape.txt", text: "blocked")
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeVirtualFileSystemOperationRejected)
        XCTAssertEqual(state.lastRuntimeFault?.code, "virtualFileSystemOperationRejected")
        XCTAssertFalse(state.virtualFileSystemsByNodeID[nodeID]?.contains("/escape.txt") == true)
    }

    func testDesktopSuiteActionsRejectStoppedSimulationAndWrongOpenedNodeWithoutMutation() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 100, y: 100), to: &state)
        let otherNodeID = addNode(kind: .pc, at: CGPoint(x: 200, y: 100), to: &state)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: nodeID))
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .fileExplorer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .fileExplorer))
        let initialSelection = state.runtimeFileExplorerSelectionByNodeID[nodeID]

        TopologyEditorReducer.reduce(state: &state, action: .stopSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeFileExplorerSelectEntry(nodeID: nodeID, entryID: "/home/topology-exports.csv")
        )
        XCTAssertEqual(state.runtimeFileExplorerSelectionByNodeID[nodeID], initialSelection)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("reason=simulationNotRunning") ?? false)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: nodeID))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .fileExplorer))
        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: otherNodeID))
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeFileExplorerSelectEntry(nodeID: nodeID, entryID: "/home/topology-exports.csv")
        )
        XCTAssertEqual(state.runtimeFileExplorerSelectionByNodeID[nodeID], initialSelection)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("reason=nodeNotOpened") ?? false)
    }

    func testFileExplorerRejectsMalformedAndUnknownTargetsWithoutMutation() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 100, y: 100), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: nodeID))
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .fileExplorer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .fileExplorer))
        let initialSelection = state.runtimeFileExplorerSelectionByNodeID[nodeID]

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeFileSystemCreateTextFile(nodeID: nodeID, path: "/trimmed.txt ", text: "no")
        )
        XCTAssertFalse(state.virtualFileSystemsByNodeID[nodeID]?.contains("/trimmed.txt") ?? true)
        XCTAssertEqual(state.lastRuntimeFault?.code, "virtualFileSystemOperationRejected")

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeFileExplorerSelectEntry(nodeID: nodeID, entryID: "  ")
        )
        XCTAssertEqual(state.runtimeFileExplorerSelectionByNodeID[nodeID], initialSelection)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDesktopAppActionRejectedMalformedPayload)
        XCTAssertEqual(state.lastRuntimeFault?.code, "runtimeDesktopAppActionMalformedPayload")

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeFileExplorerSelectEntry(nodeID: nodeID, entryID: "/missing.txt")
        )
        XCTAssertEqual(state.runtimeFileExplorerSelectionByNodeID[nodeID], initialSelection)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDesktopAppActionRejectedUnknownTarget)
        XCTAssertEqual(state.lastRuntimeFault?.code, "runtimeDesktopAppUnknownTarget")
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("reason=unknownFileEntry") ?? false)
    }

    func testImageViewerRejectsMalformedAndUnknownTargetsWithoutMutation() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 110, y: 110), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: nodeID))
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .imageViewer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .imageViewer))
        let initialSelection = state.runtimeImageViewerSelectionByNodeID[nodeID]

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeImageViewerSelectImage(nodeID: nodeID, imageID: nil)
        )
        XCTAssertEqual(state.runtimeImageViewerSelectionByNodeID[nodeID], initialSelection)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDesktopAppActionRejectedMalformedPayload)
        XCTAssertEqual(state.lastRuntimeFault?.category, .malformedRuntimePayload)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeImageViewerSelectImage(nodeID: nodeID, imageID: "/images/missing.png")
        )
        XCTAssertEqual(state.runtimeImageViewerSelectionByNodeID[nodeID], initialSelection)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDesktopAppActionRejectedUnknownTarget)
        XCTAssertEqual(state.lastRuntimeFault?.code, "runtimeDesktopAppUnknownTarget")
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("reason=unknownImageTarget") ?? false)
    }

    func testSaveRuntimeDeviceIPRejectsInvalidSubnetMaskWithoutMutatingPriorConfig() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)

        saveRuntimeIP(nodeID: nodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        let snapshot = state.runtimeDeviceConfigurations[nodeID]

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeDeviceIP(nodeID: nodeID, ipAddress: "192.168.0.10", subnetMask: "255.0.255.0")
        )

        XCTAssertEqual(state.runtimeDeviceConfigurations[nodeID], snapshot)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceIPRejectedInvalidConfiguration)
        XCTAssertEqual(state.lastRuntimeFault?.category, .networkConfiguration)
        XCTAssertEqual(state.lastRuntimeFault?.code, "invalidSubnetMask")
    }

    func testExecutePingSuccessAppendsConsoleEntryAndClearsPingFault() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 280, y: 30), to: &state)
        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 150, y: 100), to: &state)
        connect(sourceNodeID, switchNodeID, state: &state)
        connect(targetNodeID, switchNodeID, state: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "192.168.0.20", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.0.20"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingSucceeded)
        XCTAssertTrue(state.lastPingEvent?.detail?.contains("targetIP=192.168.0.20") ?? false)
        XCTAssertTrue(state.lastPingEvent?.detail?.contains("hops=") ?? false)
        XCTAssertTrue(state.lastPingEvent?.detail?.contains("path=") ?? false)
        XCTAssertTrue(state.lastPingEvent?.detail?.contains("latencyMs=") ?? false)
        XCTAssertNil(state.lastPingFault)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .pingSucceeded)
        let consoleLines = state.runtimeConsoleEntriesByNodeID[sourceNodeID] ?? []
        XCTAssertEqual(consoleLines.first, "/> ping 192.168.0.20")
        XCTAssertEqual(consoleLines.dropFirst().first, "PING 192.168.0.20 (192.168.0.20) 56(84) bytes of data.")
        XCTAssertEqual(consoleLines.filter { $0.contains("icmp_seq=") }.count, 4)
        XCTAssertTrue(consoleLines.contains("4 packets transmitted, 4 received, 0% packet loss, time 3000ms"))
        XCTAssertTrue(consoleLines.last?.hasPrefix("rtt min/avg/max/mdev = ") == true)
    }

    func testExecutePingSucceedsAcrossDirectPCToNotebookCable() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let targetNodeID = addNode(kind: .notebook, at: CGPoint(x: 280, y: 30), to: &state)
        connect(sourceNodeID, targetNodeID, state: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "192.168.0.20", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.0.20"))

        XCTAssertEqual(state.graph.links.count, 1)
        XCTAssertEqual(state.lastPingEvent?.code, .pingSucceeded)
        XCTAssertNil(state.lastPingFault)
        let consoleLines = state.runtimeConsoleEntriesByNodeID[sourceNodeID] ?? []
        XCTAssertEqual(consoleLines.dropFirst().first, "PING 192.168.0.20 (192.168.0.20) 56(84) bytes of data.")
        XCTAssertEqual(consoleLines.filter { $0.contains("icmp_seq=") }.count, 4)
        XCTAssertTrue(consoleLines.last?.contains(" min/avg/max/mdev = ") == true)
    }

    func testWebBrowserPresentationRendersOnlyNonEmptyHTMLResponses() {
        var browserState = TopologyRuntimeWebBrowserState()
        XCTAssertFalse(browserState.shouldRenderBodyAsHTML)

        browserState.contentType = "text/html; charset=utf-8"
        browserState.body = "<h1>Delivered page</h1>"
        XCTAssertTrue(browserState.shouldRenderBodyAsHTML)

        browserState.contentType = "text/plain"
        XCTAssertFalse(browserState.shouldRenderBodyAsHTML)

        browserState.contentType = "text/html"
        browserState.body = ""
        XCTAssertFalse(browserState.shouldRenderBodyAsHTML)
    }

    func testHTMLDocumentIsolationPreservesDeliveredMarkupAndBlocksHostResources() {
        let deliveredHTML = "<html><head><title>Lab</title></head><body><h1>Delivered page</h1></body></html>"
        let isolatedHTML = RuntimeHTMLDocumentIsolation.document(containing: deliveredHTML)

        XCTAssertTrue(isolatedHTML.contains("<h1>Delivered page</h1>"))
        XCTAssertTrue(isolatedHTML.contains("Content-Security-Policy"))
        XCTAssertTrue(isolatedHTML.contains("default-src 'none'"))
    }

    func testVirtualHostEditorSelectsEditsDefaultsAndFallsBackAfterDeletion() throws {
        let first = try TopologyRuntimeWebVirtualHost(
            id: "first",
            hostname: "first.lab",
            port: nil,
            documentRoot: "/sites/first",
            isEnabled: true
        )
        let second = try TopologyRuntimeWebVirtualHost(
            id: "second",
            hostname: "second.lab",
            port: nil,
            documentRoot: "/sites/second",
            isEnabled: true
        )
        let existing = try TopologyRuntimeWebVirtualHostConfiguration(
            hosts: [first, second],
            defaultHostID: first.id
        )
        let editedSecond = try TopologyRuntimeWebVirtualHost(
            id: "renamed-second",
            hostname: "second.lab",
            port: 8080,
            documentRoot: "/sites/second-v2",
            isEnabled: true
        )

        let edited = try TopologyRuntimeVirtualHostEditor.saving(
            editedSecond,
            selectedHostID: second.id,
            selectedDefaultHostID: second.id,
            in: existing
        )
        XCTAssertEqual(edited.defaultHostID, editedSecond.id)
        XCTAssertEqual(edited.hosts.count, 2)
        XCTAssertNil(edited.hosts.first(where: { $0.id == second.id }))
        XCTAssertEqual(
            edited.hosts.first(where: { $0.id == editedSecond.id })?.documentRoot,
            "/sites/second-v2"
        )

        let afterDeletingDefault = try XCTUnwrap(
            TopologyRuntimeVirtualHostEditor.removing(
                hostID: editedSecond.id,
                from: edited
            )
        )
        XCTAssertEqual(afterDeletingDefault.defaultHostID, first.id)
    }

    func testWebBrowserHistoryEvictsOldestEntriesByCountAndByteBudget() {
        var browser = TopologyRuntimeWebBrowserState()
        let entryBody = Data(repeating: 0x41, count: 512 * 1_024)

        for index in 0..<(TopologyRuntimeWebBrowserState.maximumHistoryEntries + 2) {
            browser.appendHistoryEntry(TopologyRuntimeWebBrowserHistoryEntry(
                address: "http://history.test/\(index)",
                statusCode: 200,
                title: nil,
                resolvedIPAddress: "10.0.0.20",
                contentType: "application/octet-stream",
                bodyData: entryBody
            ))
        }

        XCTAssertLessThanOrEqual(
            browser.history.count,
            TopologyRuntimeWebBrowserState.maximumHistoryEntries
        )
        XCTAssertFalse(browser.history.contains { $0.address.hasSuffix("/0") })
        XCTAssertEqual(browser.historyIndex, browser.history.indices.last)
        XCTAssertTrue(browser.canNavigateBack)
        XCTAssertFalse(browser.canNavigateForward)
    }

    func testWebBrowserStateExposesConsistentBackAndForwardAvailability() {
        var browserState = TopologyRuntimeWebBrowserState()
        XCTAssertFalse(browserState.canNavigateBack)
        XCTAssertFalse(browserState.canNavigateForward)

        browserState.history = [
            TopologyRuntimeWebBrowserHistoryEntry(
                address: "http://router.lab:8081/admin",
                statusCode: 200,
                title: "Status"
            ),
            TopologyRuntimeWebBrowserHistoryEntry(
                address: "http://router.lab:8081/admin/routes",
                statusCode: 200,
                title: "Routes"
            ),
        ]
        browserState.historyIndex = 1
        XCTAssertTrue(browserState.canNavigateBack)
        XCTAssertFalse(browserState.canNavigateForward)

        browserState.historyIndex = 0
        XCTAssertFalse(browserState.canNavigateBack)
        XCTAssertTrue(browserState.canNavigateForward)

        browserState.historyIndex = 99
        XCTAssertFalse(browserState.canNavigateBack)
        XCTAssertFalse(browserState.canNavigateForward)
    }

    func testRenderedHTMLPreservesAdministrationLinksAndFormsWhileRemovingActiveContent() {
        let response = TopologyRuntimeHTTPResponse(
            statusCode: 200,
            contentType: "text/html; charset=utf-8",
            body: Data(
                """
                <html><body onload="steal()">
                <a href="/admin/routes">Routes</a>
                <form method="post" action="/admin/actions/routes/add">
                <input name="destinationNetwork" value="10.30.0.0">
                </form>
                <script>steal()</script>
                <img src="https://outside.invalid/pixel.png">
                </body></html>
                """.utf8
            ),
            detail: "test"
        )

        let rendered = response.renderedBody
        XCTAssertTrue(rendered.contains(#"href="/admin/routes""#))
        XCTAssertTrue(rendered.contains(#"method="post""#))
        XCTAssertTrue(rendered.contains(#"action="/admin/actions/routes/add""#))
        XCTAssertFalse(rendered.lowercased().contains("<script"))
        XCTAssertFalse(rendered.lowercased().contains("onload="))
        XCTAssertFalse(rendered.contains("https://outside.invalid"))
    }

    func testWebBrowserRequestEncodingRoundTripsPOSTAndRejectsOversizedBody() throws {
        let request = TopologyRuntimeWebBrowserRequest(
            address: "http://192.168.1.1:8081/admin/actions/routes/add",
            method: "post",
            body: Data("destinationNetwork=10.30.0.0".utf8)
        )
        let encoded = try XCTUnwrap(request.encodedNavigationAddress)
        XCTAssertEqual(TopologyRuntimeWebBrowserRequest.decodeNavigationAddress(encoded), request)

        let oversized = TopologyRuntimeWebBrowserRequest(
            address: "http://192.168.1.1:8081/admin",
            method: "POST",
            body: Data(repeating: 0, count: TopologyRuntimeWebBrowserRequest.maximumBodySize + 1)
        )
        XCTAssertNil(oversized.encodedNavigationAddress)
    }

    func testRuntimeWebVirtualHostDispatchesExactHostToSelectedDocumentRoot() throws {
        var runtime = try makeWebVirtualHostRuntime()

        let response = try performWebRuntimeRequest(
            state: &runtime.state,
            clientNodeID: runtime.clientNodeID,
            serverNodeID: runtime.serverNodeID,
            hostHeader: "exact.lab",
            target: "/"
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.body, "exact host")
        XCTAssertTrue(response.detail.contains("path=/sites/exact/index.html"))
        XCTAssertTrue(response.detail.contains("virtualHost=exact"))
    }

    func testRuntimeWebVirtualHostDispatchesHostAndPortToPortSpecificRoot() throws {
        var runtime = try makeWebVirtualHostRuntime()

        let response = try performWebRuntimeRequest(
            state: &runtime.state,
            clientNodeID: runtime.clientNodeID,
            serverNodeID: runtime.serverNodeID,
            hostHeader: "port.lab:8080",
            target: "/"
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.body, "port-specific host")
        XCTAssertTrue(response.detail.contains("path=/sites/port-specific/index.html"))
        XCTAssertTrue(response.detail.contains("virtualHost=port-specific"))
    }

    func testRuntimeWebVirtualHostUsesDefaultHostWhenAuthorityIsMissing() throws {
        var runtime = try makeWebVirtualHostRuntime()

        let response = try performWebRuntimeRequest(
            state: &runtime.state,
            clientNodeID: runtime.clientNodeID,
            serverNodeID: runtime.serverNodeID,
            hostHeader: nil,
            target: "/"
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.body, "default host")
        XCTAssertTrue(response.detail.contains("virtualHost=default"))
        XCTAssertTrue(response.detail.contains("dispatch=defaultHost"))
    }

    func testRuntimeWebVirtualHostFallsBackToDefaultHostForUnknownAuthority() throws {
        var runtime = try makeWebVirtualHostRuntime()

        let response = try performWebRuntimeRequest(
            state: &runtime.state,
            clientNodeID: runtime.clientNodeID,
            serverNodeID: runtime.serverNodeID,
            hostHeader: "unknown.lab",
            target: "/"
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.body, "default host")
        XCTAssertTrue(response.detail.contains("virtualHost=default"))
        XCTAssertTrue(response.detail.contains("dispatch=defaultHost"))
    }

    func testRuntimeWebVirtualHostRejectsRepeatedlyEncodedTraversalRequest() throws {
        var runtime = try makeWebVirtualHostRuntime()

        let response = try performWebRuntimeRequest(
            state: &runtime.state,
            clientNodeID: runtime.clientNodeID,
            serverNodeID: runtime.serverNodeID,
            hostHeader: "exact.lab",
            target: "/..%252Fsecret.txt"
        )

        XCTAssertEqual(response.statusCode, 400)
        XCTAssertEqual(response.body, "Bad Request\n")
        XCTAssertEqual(response.detail, "unsafePath")
        XCTAssertFalse(response.body.contains("outside document roots"))
    }

    func testRuntimeWebServerWithoutVirtualHostsPreservesLegacyDocumentRoot() throws {
        var runtime = try makeWebVirtualHostRuntime()
        runtime.state.runtimeWebServerConfigurationsByNodeID[runtime.serverNodeID] =
            TopologyRuntimeWebServerConfiguration(port: 8080, documentRoot: "/www")

        let response = try performWebRuntimeRequest(
            state: &runtime.state,
            clientNodeID: runtime.clientNodeID,
            serverNodeID: runtime.serverNodeID,
            hostHeader: "anything.lab",
            target: "/"
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.body, "legacy root")
        XCTAssertTrue(response.detail.contains("path=/www/index.html"))
        XCTAssertTrue(response.detail.contains("documentRoot=legacy"))
    }

    func testExecutePingRejectsMalformedCommand() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedMalformedCommand)
        XCTAssertEqual(state.lastPingFault?.category, .commandValidation)
        XCTAssertEqual(state.lastPingFault?.code, "malformedPingCommand")
    }

    func testExecutePingRejectsUnknownTarget() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.0.200"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedUnknownTarget)
        XCTAssertEqual(state.lastPingFault?.category, .networkRouting)
        XCTAssertEqual(state.lastPingFault?.code, "pingTargetUnknown")
    }

    func testExecutePingRejectsInvalidSourceConfiguration() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.0.20"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedInvalidSourceConfiguration)
        XCTAssertEqual(state.lastPingFault?.category, .networkConfiguration)
        XCTAssertEqual(state.lastPingFault?.code, "sourceConfigurationMissing")
    }

    func testExecutePingRejectsSubnetMismatch() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 280, y: 30), to: &state)
        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 150, y: 100), to: &state)
        connect(sourceNodeID, switchNodeID, state: &state)
        connect(targetNodeID, switchNodeID, state: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "10.0.0.20", subnetMask: "255.0.0.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping 10.0.0.20"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedSubnetMismatch)
        XCTAssertEqual(state.lastPingFault?.category, .networkRouting)
        XCTAssertEqual(state.lastPingFault?.code, "sourceDefaultGatewayMissing")
    }

    func testSameSubnetPingSupportsDifferentCompatibleEndpointMasks() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 280, y: 30), to: &state)
        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 150, y: 100), to: &state)
        connect(sourceNodeID, switchNodeID, state: &state)
        connect(targetNodeID, switchNodeID, state: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.1.10", subnetMask: "255.255.0.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "192.168.1.20", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.1.20")
        )

        XCTAssertEqual(state.lastPingEvent?.code, .pingSucceeded)
        XCTAssertNil(state.lastPingFault)
    }

    func testCrossSubnetPingSucceedsThroughGatewayWithMatchingDefaultGateways() {
        var state = TopologyEditorState()
        // The gateway's first port is WAN. Attach the target first so this exercises LAN-to-WAN forwarding.
        let (targetNodeID, gatewayNodeID, sourceNodeID) = makeDefaultGatewayTopology(state: &state)
        saveRuntimeConfiguration(
            nodeID: sourceNodeID,
            ipAddress: "192.168.0.20",
            subnetMask: "255.255.255.0",
            defaultGateway: "192.168.0.10",
            state: &state
        )
        saveRuntimeConfiguration(
            nodeID: targetNodeID,
            ipAddress: "42.0.0.20",
            subnetMask: "255.0.0.0",
            defaultGateway: "42.0.0.10",
            state: &state
        )

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "ping 42.0.0.20")
        )

        let requestPacketIdentity = tryUnwrap(
            state.networkRuntime.state.packetTraces.first {
                $0.nodeID == sourceNodeID && $0.detail == "ICMP echo request"
            }?.packetIdentity
        )
        XCTAssertEqual(state.lastPingEvent?.code, .pingSucceeded)
        XCTAssertEqual(
            state.networkRuntime.tracedNodePath(packetIdentity: requestPacketIdentity),
            [sourceNodeID, gatewayNodeID, targetNodeID]
        )
        XCTAssertTrue(state.lastPingEvent?.detail?.contains(gatewayNodeID.uuidString) ?? false)
        XCTAssertNil(state.lastPingFault)
    }

    func testCrossSubnetPingSucceedsThroughDynamicRouterInterfaces() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let routerNodeID = addNode(kind: .router, at: CGPoint(x: 160, y: 20), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 300, y: 20), to: &state)

        let routerIndex = tryUnwrap(state.graph.nodeIndex(withID: routerNodeID))
        let secondRouterPort = TopologyPortMetadata(
            id: uuid("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"),
            label: "rt2"
        )
        state.graph.nodes[routerIndex].ports.append(secondRouterPort)
        connect(sourceNodeID, routerNodeID, state: &state)
        connect(targetNodeID, routerNodeID, state: &state)

        let router = tryUnwrap(state.graph.node(withID: routerNodeID))
        XCTAssertEqual(router.ports.map(\.label), ["rt1", "rt2"])
        state.runtimeInterfaceConfigurations[
            TopologyRuntimeInterfaceKey(nodeID: routerNodeID, portID: router.ports[0].id)
        ] = TopologyRuntimeInterfaceConfiguration(
            ipAddress: "10.0.0.1",
            subnetMask: "255.255.255.0"
        )
        state.runtimeInterfaceConfigurations[
            TopologyRuntimeInterfaceKey(nodeID: routerNodeID, portID: router.ports[1].id)
        ] = TopologyRuntimeInterfaceConfiguration(
            ipAddress: "10.0.1.1",
            subnetMask: "255.255.255.0"
        )
        saveRuntimeConfiguration(
            nodeID: sourceNodeID,
            ipAddress: "10.0.0.10",
            subnetMask: "255.255.255.0",
            defaultGateway: "10.0.0.1",
            state: &state
        )
        saveRuntimeConfiguration(
            nodeID: targetNodeID,
            ipAddress: "10.0.1.10",
            subnetMask: "255.255.255.0",
            defaultGateway: "10.0.1.1",
            state: &state
        )

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "ping 10.0.1.10")
        )

        XCTAssertEqual(state.lastPingEvent?.code, .pingSucceeded)
        XCTAssertTrue(state.lastPingEvent?.detail?.contains(routerNodeID.uuidString) ?? false)
        XCTAssertNil(state.lastPingFault)
    }

    func testMultiRouterPingUsesManualRouteOnEachForwardingRouter() {
        var state = TopologyEditorState()
        let topology = makeTwoRouterTopology(state: &state)
        state.runtimeManualRoutesByNodeID[topology.firstRouterNodeID] = [
            manualRoute(destination: "10.0.2.0", gateway: "10.0.1.2", interface: "10.0.1.1")
        ]
        state.runtimeManualRoutesByNodeID[topology.secondRouterNodeID] = [
            manualRoute(destination: "10.0.0.0", gateway: "10.0.1.1", interface: "10.0.1.2")
        ]

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: topology.sourceNodeID, command: "ping 10.0.2.10")
        )

        XCTAssertEqual(state.lastPingEvent?.code, .pingSucceeded)
        XCTAssertTrue(state.lastPingEvent?.detail?.contains(topology.firstRouterNodeID.uuidString) ?? false)
        XCTAssertTrue(state.lastPingEvent?.detail?.contains(topology.secondRouterNodeID.uuidString) ?? false)
        XCTAssertNil(state.lastPingFault)
    }

    func testExecutePingReportsPacketDerivedResponderPathAcrossRouters() {
        var state = TopologyEditorState()
        let topology = makeTwoRouterTopology(state: &state)
        state.runtimeManualRoutesByNodeID[topology.firstRouterNodeID] = [
            manualRoute(destination: "10.0.2.0", gateway: "10.0.1.2", interface: "10.0.1.1")
        ]
        state.runtimeManualRoutesByNodeID[topology.secondRouterNodeID] = [
            manualRoute(destination: "10.0.0.0", gateway: "10.0.1.1", interface: "10.0.1.2")
        ]

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: topology.sourceNodeID, command: "ping 10.0.2.10")
        )

        let requestPacketIdentity = tryUnwrap(
            state.networkRuntime.state.packetTraces.first {
                $0.nodeID == topology.sourceNodeID && $0.detail == "ICMP echo request"
            }?.packetIdentity
        )
        let packetDerivedPath = state.networkRuntime.tracedNodePath(packetIdentity: requestPacketIdentity)
        let expectedPath = [
            topology.sourceNodeID,
            topology.firstRouterNodeID,
            topology.secondRouterNodeID,
            topology.targetNodeID,
        ]

        XCTAssertEqual(state.lastPingEvent?.code, .pingSucceeded)
        XCTAssertEqual(packetDerivedPath, expectedPath)
        XCTAssertTrue(
            state.lastPingEvent?.detail?.contains(
                "path=\(expectedPath.map(\.uuidString).joined(separator: "->"))"
            ) ?? false
        )
    }

    func testExecuteTracerouteReportsPacketDerivedRespondersAcrossRouters() {
        var state = TopologyEditorState()
        let topology = makeTwoRouterTopology(state: &state)
        state.runtimeManualRoutesByNodeID[topology.firstRouterNodeID] = [
            manualRoute(destination: "10.0.2.0", gateway: "10.0.1.2", interface: "10.0.1.1")
        ]
        state.runtimeManualRoutesByNodeID[topology.secondRouterNodeID] = [
            manualRoute(destination: "10.0.0.0", gateway: "10.0.1.1", interface: "10.0.1.2")
        ]

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: topology.sourceNodeID, command: "traceroute 10.0.2.10")
        )

        let observations = state.networkRuntime.state.icmpObservationsByNodeID[topology.sourceNodeID] ?? []

        XCTAssertEqual(state.lastRuntimeEvent?.code, .traceSucceeded)
        XCTAssertEqual(observations.map(\.message.kind), [.timeExceeded, .timeExceeded, .echoReply])
        XCTAssertEqual(observations.map(\.message.sequenceNumber), [1, 2, 3])
        XCTAssertEqual(
            observations.map(\.packet.senderIPAddress),
            ["10.0.0.1", "10.0.1.2", "10.0.2.10"]
        )
    }

    func testMultiRouterPingRejectsMissingManualRoute() {
        var state = TopologyEditorState()
        let topology = makeTwoRouterTopology(state: &state)
        state.runtimeManualRoutesByNodeID[topology.secondRouterNodeID] = [
            manualRoute(destination: "10.0.0.0", gateway: "10.0.1.1", interface: "10.0.1.2")
        ]

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: topology.sourceNodeID, command: "ping 10.0.2.10")
        )

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedSubnetMismatch)
        XCTAssertEqual(state.lastPingFault?.code, "forwardingRouteMissing")
    }

    func testMultiRouterMoreSpecificManualRouteBeatsDefaultRoute() {
        var state = TopologyEditorState()
        let topology = makeTwoRouterTopology(state: &state)
        state.runtimeManualRoutesByNodeID[topology.firstRouterNodeID] = [
            TopologyRuntimeManualRoute(
                destinationNetwork: "0.0.0.0",
                subnetMask: "0.0.0.0",
                gateway: "10.0.1.254",
                interfaceIPAddress: "10.0.1.1"
            ),
            manualRoute(destination: "10.0.2.0", gateway: "10.0.1.2", interface: "10.0.1.1")
        ]
        state.runtimeManualRoutesByNodeID[topology.secondRouterNodeID] = [
            manualRoute(destination: "10.0.0.0", gateway: "10.0.1.1", interface: "10.0.1.2")
        ]

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: topology.sourceNodeID, command: "ping 10.0.2.10")
        )

        XCTAssertEqual(state.lastPingEvent?.code, .pingSucceeded)
        XCTAssertNil(state.lastPingFault)
    }

    func testMultiRouterEqualMaskKeepsFirstManualRoute() {
        var state = TopologyEditorState()
        let topology = makeTwoRouterTopology(state: &state)
        state.runtimeManualRoutesByNodeID[topology.firstRouterNodeID] = [
            manualRoute(destination: "10.0.2.0", gateway: "10.0.1.254", interface: "10.0.1.1"),
            manualRoute(destination: "10.0.2.0", gateway: "10.0.1.2", interface: "10.0.1.1")
        ]

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: topology.sourceNodeID, command: "ping 10.0.2.10")
        )

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedTopologyUnreachable)
        XCTAssertEqual(state.lastPingFault?.code, "forwardingNextHopUnreachable")
    }

    func testMultiRouterRejectsInvalidManualRouteInterface() {
        var state = TopologyEditorState()
        let topology = makeTwoRouterTopology(state: &state)
        state.runtimeManualRoutesByNodeID[topology.firstRouterNodeID] = [
            manualRoute(destination: "10.0.2.0", gateway: "10.0.1.2", interface: "10.99.0.1")
        ]

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: topology.sourceNodeID, command: "ping 10.0.2.10")
        )

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedSubnetMismatch)
        XCTAssertEqual(state.lastPingFault?.code, "forwardingRouteInterfaceInvalid")
    }

    func testMultiRouterRejectsUnreachableNextHopGateway() {
        var state = TopologyEditorState()
        let topology = makeTwoRouterTopology(state: &state)
        state.runtimeManualRoutesByNodeID[topology.firstRouterNodeID] = [
            manualRoute(destination: "10.0.2.0", gateway: "10.0.1.99", interface: "10.0.1.1")
        ]

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: topology.sourceNodeID, command: "ping 10.0.2.10")
        )

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedTopologyUnreachable)
        XCTAssertEqual(state.lastPingFault?.code, "forwardingNextHopUnreachable")
    }

    func testMultiRouterPingRejectsMissingReturnRoute() {
        var state = TopologyEditorState()
        let topology = makeTwoRouterTopology(state: &state)
        state.runtimeManualRoutesByNodeID[topology.firstRouterNodeID] = [
            manualRoute(destination: "10.0.2.0", gateway: "10.0.1.2", interface: "10.0.1.1")
        ]

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: topology.sourceNodeID, command: "ping 10.0.2.10")
        )

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedSubnetMismatch)
        XCTAssertEqual(state.lastPingFault?.code, "forwardingRouteMissing")
    }

    func testMultiRouterDetectsManualRoutingLoop() {
        var state = TopologyEditorState()
        let topology = makeTwoRouterTopology(state: &state)
        state.runtimeManualRoutesByNodeID[topology.firstRouterNodeID] = [
            manualRoute(destination: "10.0.2.0", gateway: "10.0.1.2", interface: "10.0.1.1")
        ]
        state.runtimeManualRoutesByNodeID[topology.secondRouterNodeID] = [
            TopologyRuntimeManualRoute(
                destinationNetwork: "10.0.2.10",
                subnetMask: "255.255.255.255",
                gateway: "10.0.1.1",
                interfaceIPAddress: "10.0.1.2"
            )
        ]

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: topology.sourceNodeID, command: "ping 10.0.2.10")
        )

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedTopologyUnreachable)
        XCTAssertEqual(state.lastPingFault?.code, "forwardingLoopDetected")
    }

    func testCrossSubnetPingReportsRouterEgressSubnetMismatch() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let routerNodeID = addNode(kind: .router, at: CGPoint(x: 160, y: 20), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 300, y: 20), to: &state)

        let routerIndex = tryUnwrap(state.graph.nodeIndex(withID: routerNodeID))
        state.graph.nodes[routerIndex].ports.append(
            TopologyPortMetadata(
                id: uuid("dddddddd-dddd-dddd-dddd-dddddddddddd"),
                label: "rt2"
            )
        )
        connect(sourceNodeID, routerNodeID, state: &state)
        connect(targetNodeID, routerNodeID, state: &state)

        let router = tryUnwrap(state.graph.node(withID: routerNodeID))
        state.runtimeInterfaceConfigurations[
            TopologyRuntimeInterfaceKey(nodeID: routerNodeID, portID: router.ports[0].id)
        ] = TopologyRuntimeInterfaceConfiguration(
            ipAddress: "10.0.0.1",
            subnetMask: "255.255.255.0"
        )
        state.runtimeInterfaceConfigurations[
            TopologyRuntimeInterfaceKey(nodeID: routerNodeID, portID: router.ports[1].id)
        ] = TopologyRuntimeInterfaceConfiguration(
            ipAddress: "10.0.2.1",
            subnetMask: "255.255.255.0"
        )
        saveRuntimeConfiguration(
            nodeID: sourceNodeID,
            ipAddress: "10.0.0.10",
            subnetMask: "255.255.255.0",
            defaultGateway: "10.0.0.1",
            state: &state
        )
        saveRuntimeConfiguration(
            nodeID: targetNodeID,
            ipAddress: "10.0.1.10",
            subnetMask: "255.255.255.0",
            defaultGateway: "10.0.2.1",
            state: &state
        )

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "ping 10.0.1.10")
        )

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedSubnetMismatch)
        XCTAssertEqual(state.lastPingFault?.code, "routerEgressSubnetMismatch")
    }

    func testCrossSubnetPingRejectsMissingSourceDefaultGateway() {
        var state = TopologyEditorState()
        let (sourceNodeID, _, targetNodeID) = makeDefaultGatewayTopology(state: &state)
        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "42.0.0.20", subnetMask: "255.0.0.0", state: &state)
        saveRuntimeConfiguration(
            nodeID: targetNodeID,
            ipAddress: "192.168.0.20",
            subnetMask: "255.255.255.0",
            defaultGateway: "192.168.0.10",
            state: &state
        )

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.0.20")
        )

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedSubnetMismatch)
        XCTAssertEqual(state.lastPingFault?.code, "sourceDefaultGatewayMissing")
    }

    func testCrossSubnetPingRejectsMissingReturnGateway() {
        var state = TopologyEditorState()
        let (sourceNodeID, _, targetNodeID) = makeDefaultGatewayTopology(state: &state)
        saveRuntimeConfiguration(
            nodeID: sourceNodeID,
            ipAddress: "42.0.0.20",
            subnetMask: "255.0.0.0",
            defaultGateway: "42.0.0.10",
            state: &state
        )
        saveRuntimeIP(
            nodeID: targetNodeID,
            ipAddress: "192.168.0.20",
            subnetMask: "255.255.255.0",
            state: &state
        )

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.0.20")
        )

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedSubnetMismatch)
        XCTAssertEqual(state.lastPingFault?.code, "targetDefaultGatewayMissing")
    }

    func testCrossSubnetPingRejectsGatewayInterfaceSubnetMismatch() {
        var state = TopologyEditorState()
        let (sourceNodeID, gatewayNodeID, targetNodeID) = makeDefaultGatewayTopology(state: &state)
        let gateway = tryUnwrap(state.graph.node(withID: gatewayNodeID))
        state.runtimeInterfaceConfigurations[
            TopologyRuntimeInterfaceKey(nodeID: gatewayNodeID, portID: gateway.ports[1].id)
        ] = TopologyRuntimeInterfaceConfiguration(
            ipAddress: "10.0.0.10",
            subnetMask: "255.0.0.0"
        )
        saveRuntimeConfiguration(
            nodeID: sourceNodeID,
            ipAddress: "42.0.0.20",
            subnetMask: "255.0.0.0",
            defaultGateway: "42.0.0.10",
            state: &state
        )
        saveRuntimeConfiguration(
            nodeID: targetNodeID,
            ipAddress: "192.168.0.20",
            subnetMask: "255.255.255.0",
            defaultGateway: "10.0.0.10",
            state: &state
        )

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.0.20")
        )

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedSubnetMismatch)
        XCTAssertEqual(state.lastPingFault?.code, "gatewayEgressSubnetMismatch")
    }

    func testCrossSubnetTraceReportsGatewayHopAndRouteNeedsOnlyOutboundGateway() {
        var state = TopologyEditorState()
        // Traceroute follows the same supported LAN-to-WAN gateway direction as normal outbound traffic.
        let (targetNodeID, gatewayNodeID, sourceNodeID) = makeDefaultGatewayTopology(state: &state)
        saveRuntimeConfiguration(
            nodeID: sourceNodeID,
            ipAddress: "192.168.0.20",
            subnetMask: "255.255.255.0",
            defaultGateway: "192.168.0.10",
            state: &state
        )
        saveRuntimeConfiguration(
            nodeID: targetNodeID,
            ipAddress: "42.0.0.20",
            subnetMask: "255.0.0.0",
            defaultGateway: "42.0.0.10",
            state: &state
        )

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "trace 42.0.0.20")
        )
        let observations = state.networkRuntime.state.icmpObservationsByNodeID[sourceNodeID] ?? []
        XCTAssertEqual(state.lastRuntimeEvent?.code, .traceSucceeded)
        XCTAssertEqual(observations.map(\.message.kind), [.timeExceeded, .echoReply])
        XCTAssertEqual(observations.map(\.packet.senderIPAddress), ["192.168.0.10", "42.0.0.20"])
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains(gatewayNodeID.uuidString) ?? false)

        saveRuntimeIP(
            nodeID: targetNodeID,
            ipAddress: "42.0.0.20",
            subnetMask: "255.0.0.0",
            state: &state
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "route 42.0.0.20")
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .routeSucceeded)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains(gatewayNodeID.uuidString) ?? false)
    }

    func testSameSubnetTrafficDoesNotTreatGatewayAsTransparentBridge() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let gatewayNodeID = addNode(kind: .gateway, at: CGPoint(x: 160, y: 20), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 300, y: 20), to: &state)
        connect(sourceNodeID, gatewayNodeID, state: &state)
        connect(targetNodeID, gatewayNodeID, state: &state)
        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.30", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "192.168.0.40", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.0.40")
        )

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedTopologyUnreachable)
        XCTAssertEqual(state.lastPingFault?.code, "sameSubnetPathUnavailable")
    }

    func testExecutePingRejectsDisconnectedTopology() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 280, y: 30), to: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "192.168.0.20", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.0.20"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedTopologyUnreachable)
        XCTAssertEqual(state.lastPingFault?.category, .networkRouting)
        XCTAssertEqual(state.lastPingFault?.code, "sameSubnetPathUnavailable")
    }

    func testExecutePingWhileStoppedReturnsDeterministicFailure() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 280, y: 30), to: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "192.168.0.20", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.0.20"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedSimulationStopped)
        XCTAssertEqual(state.lastPingFault?.category, .runtimeFault)
        XCTAssertEqual(state.lastPingFault?.code, "pingWhileSimulationStopped")
    }

    func testExecutePingAgainstSelfSucceedsWhenConfigured() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.0.10"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingSucceeded)
        XCTAssertNil(state.lastPingFault)
    }

    func testExecuteTraceSuccessReportsDeterministicPathAndHopMetadata() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), nodeID: uuid("10000000-0000-0000-0000-000000000001"), to: &state)
        let switchAID = addNode(kind: .networkSwitch, at: CGPoint(x: 140, y: 20), nodeID: uuid("20000000-0000-0000-0000-000000000002"), to: &state)
        let switchBID = addNode(kind: .networkSwitch, at: CGPoint(x: 260, y: 20), nodeID: uuid("30000000-0000-0000-0000-000000000003"), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 380, y: 20), nodeID: uuid("40000000-0000-0000-0000-000000000004"), to: &state)

        connect(sourceNodeID, switchAID, state: &state)
        connect(switchAID, switchBID, state: &state)
        connect(switchBID, targetNodeID, state: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "192.168.0.20", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "trace 192.168.0.20"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .traceSucceeded)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("command=trace") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("hops=3") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("latencyMs=14") ?? false)
        XCTAssertTrue(
            state.lastRuntimeEvent?.detail?.contains(
                "path=10000000-0000-0000-0000-000000000001->20000000-0000-0000-0000-000000000002->30000000-0000-0000-0000-000000000003->40000000-0000-0000-0000-000000000004"
            ) ?? false
        )
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertEqual(
            Array(state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.suffix(2) ?? []),
            [
                "Trace to 192.168.0.20 succeeded (hops=3, latencyMs=14)",
                "Path: 10000000-0000-0000-0000-000000000001 -> 20000000-0000-0000-0000-000000000002 -> 30000000-0000-0000-0000-000000000003 -> 40000000-0000-0000-0000-000000000004"
            ]
        )
    }

    func testMalformedARPCommandIsAttributedExplicitly() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "arp 192.168.0.20"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeNetworkInspectionCommandRejected)
        XCTAssertEqual(state.lastRuntimeFault?.category, .commandValidation)
        XCTAssertEqual(state.lastRuntimeFault?.code, "malformedNetworkInspectionCommand")
        XCTAssertTrue(state.lastRuntimeFault?.message.contains("arp") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("command=arp") ?? false)
    }

    func testExecuteRouteSuccessReportsDeterministicPathAndHopMetadata() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 160, y: 100), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 300, y: 20), to: &state)

        connect(sourceNodeID, switchNodeID, state: &state)
        connect(targetNodeID, switchNodeID, state: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "172.16.10.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "172.16.10.20", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "route 172.16.10.20"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .routeSucceeded)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("command=route") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("targetIP=172.16.10.20") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("hops=2") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("latencyMs=10") ?? false)
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertEqual(
            Array(state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.suffix(2) ?? []),
            [
                "Route to 172.16.10.20 succeeded (hops=2, latencyMs=10)",
                "Route path: \(sourceNodeID.uuidString) -> \(switchNodeID.uuidString) -> \(targetNodeID.uuidString)"
            ]
        )
    }

    func testExecuteRouteRejectedWhileSimulationIsStopped() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "route 10.0.0.1"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .routeRejectedSimulationStopped)
        XCTAssertEqual(state.lastRuntimeFault?.category, .runtimeFault)
        XCTAssertEqual(state.lastRuntimeFault?.code, "routeWhileSimulationStopped")
    }

    func testExecuteHostAndNslookupMapToDeterministicDNSResolveSemantics() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "10.2.0.10", subnetMask: "255.255.255.0", state: &state)
        startLocalDNSServer(nodeID: sourceNodeID, state: &state)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "dns add api.school.local 10.2.0.44")
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "host api.school.local")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .hostResolveSucceeded)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("command=host") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("host=api.school.local") ?? false)
        XCTAssertEqual(
            state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.last,
            "host resolved api.school.local -> 10.2.0.44 via 10.2.0.10 [cache miss]"
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "nslookup api.school.local")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .hostResolveSucceeded)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("command=nslookup") ?? false)
        XCTAssertEqual(
            state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.last,
            "nslookup resolved api.school.local -> 10.2.0.44 via 10.2.0.10 [cache hit]"
        )
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testExecuteHelpDisplaysDeterministicCommandCatalogWhileSimulationStopped() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "help"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeHelpDisplayed)
        XCTAssertEqual(state.lastRuntimeEvent?.detail, "command=help;target=all")
        XCTAssertNil(state.lastRuntimeFault)

        let expectedSuffix = ["CMD help:"] + TopologyRuntimeCommandCatalog.helpLines
        XCTAssertEqual(Array(state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.suffix(expectedSuffix.count) ?? []), expectedSuffix)
    }

    func testExecuteTraceAliasesRemainEquivalentToTrace() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 160, y: 100), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 300, y: 20), to: &state)

        connect(sourceNodeID, switchNodeID, state: &state)
        connect(targetNodeID, switchNodeID, state: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "172.16.10.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "172.16.10.20", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)

        let commands = ["trace 172.16.10.20", "path 172.16.10.20", "traceroute 172.16.10.20"]
        for command in commands {
            TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: command))

            XCTAssertEqual(state.lastRuntimeEvent?.code, .traceSucceeded)
            XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("command=trace") ?? false)
            XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("targetIP=172.16.10.20") ?? false)
            XCTAssertNil(state.lastRuntimeFault)
        }
    }

    func testExecuteHelpQuestionMarkAliasMatchesCatalogOutput() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "?"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeHelpDisplayed)
        XCTAssertEqual(state.lastRuntimeEvent?.detail, "command=help;target=all")
        XCTAssertNil(state.lastRuntimeFault)

        let expectedSuffix = ["CMD help:"] + TopologyRuntimeCommandCatalog.helpLines
        XCTAssertEqual(Array(state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.suffix(expectedSuffix.count) ?? []), expectedSuffix)
    }

    func testUnsupportedRuntimeCommandTaxonomyIsDeterministicByFamily() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)

        let cases: [(String, String, String)] = [
            ("rmdir", "unsupportedRuntimeCommandFilesystem", "family=filesystem"),
            ("nmap", "unsupportedRuntimeCommand", "family=generic"),
            ("curl", "unsupportedRuntimeCommand", "family=generic"),
            ("ssh", "unsupportedRuntimeCommand", "family=generic"),
        ]

        for commandCase in cases {
            let command = commandCase.0
            let expectedCode = commandCase.1
            let expectedFamilyToken = commandCase.2

            TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: command))

            let token = command.split(separator: " ").first.map(String.init) ?? command
            XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeCommandRejectedUnsupported)
            XCTAssertEqual(state.lastRuntimeFault?.code, expectedCode)
            XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains(expectedFamilyToken) ?? false)
            XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("token=\(token)") ?? false)
        }
    }

    func testExecuteTraceMalformedCommandIsAttributedWithoutMutatingPingContracts() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "trace"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .traceRejectedMalformedCommand)
        XCTAssertEqual(state.lastRuntimeFault?.category, .commandValidation)
        XCTAssertEqual(state.lastRuntimeFault?.code, "malformedTraceCommand")
        XCTAssertNil(state.lastPingEvent)
    }

    func testExecuteDHCPLeaseCommandAssignsRuntimeConfigurationAndEmitsDiagnostics() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "dhcp lease 10.2.0.10 255.255.255.0")
        )

        let expectedConfiguration = TopologyRuntimeDeviceConfiguration(
            ipAddress: "10.2.0.10",
            subnetMask: "255.255.255.0"
        )

        XCTAssertEqual(state.runtimeDeviceConfigurations[sourceNodeID], expectedConfiguration)
        XCTAssertEqual(state.runtimeDHCPLeaseByNodeID[sourceNodeID], expectedConfiguration)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dhcpLeaseAssigned)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("ip=10.2.0.10") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("subnet=255.255.255.0") ?? false)
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertEqual(state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.last, "DHCP lease assigned: 10.2.0.10/255.255.255.0")
    }

    func testExecuteDHCPLeaseRejectedWhileSimulationIsStopped() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "dhcp lease 10.2.0.10 255.255.255.0")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dhcpLeaseRejectedSimulationStopped)
        XCTAssertEqual(state.lastRuntimeFault?.category, .runtimeFault)
        XCTAssertEqual(state.lastRuntimeFault?.code, "dhcpWhileSimulationStopped")
    }

    func testExecuteDNSRegisterAndResolveCommandsEmitDeterministicRuntimeEvents() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "10.2.0.10", subnetMask: "255.255.255.0", state: &state)
        startLocalDNSServer(nodeID: sourceNodeID, state: &state)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "dns add classroom.local 10.2.0.44")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsRecordRegistered)
        XCTAssertEqual(
            state.runtimeDNSServerConfigurationsByNodeID[sourceNodeID]?.recordsByHostname["classroom.local"],
            TopologyRuntimeDNSRecord(hostname: "classroom.local", targetIPAddress: "10.2.0.44")
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "dns resolve classroom.local")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsResolveSucceeded)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("host=classroom.local") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("ip=10.2.0.44") ?? false)
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertEqual(
            state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.last,
            "DNS resolved classroom.local -> 10.2.0.44 via 10.2.0.10 [cache miss]"
        )
    }

    func testLegacyDNSActionsPreserveMultipleAddressRecordsMirroringAndPersistenceOrder() throws {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)

        saveRuntimeIP(
            nodeID: sourceNodeID,
            ipAddress: "10.2.0.10",
            subnetMask: "255.255.255.0",
            state: &state
        )
        startLocalDNSServer(nodeID: sourceNodeID, state: &state)

        for address in ["10.2.0.44", "10.2.0.45", "10.2.0.46", "10.2.0.46"] {
            TopologyEditorReducer.reduce(
                state: &state,
                action: .runtimeDNSAddRecord(
                    nodeID: sourceNodeID,
                    hostname: "service.lab",
                    targetIPAddress: address
                )
            )
            XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsRecordRegistered)
            XCTAssertNil(state.lastRuntimeFault)
        }

        XCTAssertEqual(
            state.runtimeDNSServerConfigurationsByNodeID[sourceNodeID]?.typedRecords.map(\.target),
            ["10.2.0.44", "10.2.0.45", "10.2.0.46"]
        )
        XCTAssertEqual(
            state.runtimeDNSServerConfigurationsByNodeID[sourceNodeID]?
                .recordsByHostname["service.lab"]?.targetIPAddress,
            "10.2.0.44"
        )
        let mirroredBeforeRemoval = try XCTUnwrap(
            state.virtualFileSystemsByNodeID[sourceNodeID]?.textFile(at: TopologyRuntimeDNSHostsFile.path)
        )
        XCTAssertEqual(
            TopologyRuntimeDNSHostsFile.typedRecords(from: mirroredBeforeRemoval).map(\.target),
            ["10.2.0.44", "10.2.0.45", "10.2.0.46"]
        )

        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FiliusPad-DNS-Legacy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let store = TopologyProjectStore(fileURL: projectURL)
        try store.save(state: state, savedAt: Date(timeIntervalSince1970: 1_700_000_000))
        var restored = try store.load()

        XCTAssertEqual(
            restored.runtimeDNSServerConfigurationsByNodeID[sourceNodeID]?.typedRecords.map(\.target),
            ["10.2.0.44", "10.2.0.45", "10.2.0.46"]
        )
        XCTAssertEqual(
            try restored.virtualFileSystemsByNodeID[sourceNodeID]?
                .textFile(at: TopologyRuntimeDNSHostsFile.path),
            mirroredBeforeRemoval
        )

        startLocalDNSServer(nodeID: sourceNodeID, state: &restored)
        TopologyEditorReducer.reduce(
            state: &restored,
            action: .runtimeDNSRemoveRecord(nodeID: sourceNodeID, hostname: "service.lab")
        )

        XCTAssertEqual(restored.lastRuntimeEvent?.code, .dnsRecordRemoved)
        XCTAssertNil(restored.lastRuntimeFault)
        XCTAssertEqual(
            restored.runtimeDNSServerConfigurationsByNodeID[sourceNodeID]?.typedRecords.map(\.target),
            ["10.2.0.45", "10.2.0.46"]
        )
        XCTAssertEqual(
            restored.runtimeDNSServerConfigurationsByNodeID[sourceNodeID]?
                .recordsByHostname["service.lab"]?.targetIPAddress,
            "10.2.0.45"
        )
        let mirroredAfterRemoval = try XCTUnwrap(
            restored.virtualFileSystemsByNodeID[sourceNodeID]?.textFile(at: TopologyRuntimeDNSHostsFile.path)
        )
        XCTAssertEqual(
            TopologyRuntimeDNSHostsFile.typedRecords(from: mirroredAfterRemoval).map(\.target),
            ["10.2.0.45", "10.2.0.46"]
        )
    }

    func testDNSRecursionApplyPersistsLatestForwarderAndUsesItForLookup() {
        var state = TopologyEditorState()
        let resolverNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let authoritativeNodeID = addNode(kind: .pc, at: CGPoint(x: 280, y: 30), to: &state)

        saveRuntimeIP(
            nodeID: resolverNodeID,
            ipAddress: "10.0.0.10",
            subnetMask: "255.255.255.0",
            state: &state
        )
        saveRuntimeIP(
            nodeID: authoritativeNodeID,
            ipAddress: "10.0.0.53",
            subnetMask: "255.255.255.0",
            state: &state
        )
        connect(resolverNodeID, authoritativeNodeID, state: &state)
        startLocalDNSServer(nodeID: resolverNodeID, state: &state)
        startLocalDNSServer(nodeID: authoritativeNodeID, state: &state)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSAddRecord(
                nodeID: authoritativeNodeID,
                hostname: "saved-forwarder.test",
                targetIPAddress: "10.0.0.44"
            )
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSSetRecursion(
                nodeID: resolverNodeID,
                enabled: true,
                forwardingServerIPAddress: "10.0.0.53"
            )
        )

        XCTAssertEqual(
            state.runtimeDNSServerConfigurationsByNodeID[resolverNodeID]?.forwardingServerIPAddress,
            "10.0.0.53"
        )
        XCTAssertTrue(
            state.runtimeDNSServerConfigurationsByNodeID[resolverNodeID]?.recursiveResolutionEnabled == true
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSResolveTypedRecord(
                nodeID: resolverNodeID,
                hostname: "saved-forwarder.test",
                recordType: .address
            )
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsResolveSucceeded)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("A=10.0.0.44") == true)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("server=10.0.0.53") == true)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testExecuteDNSResolveUnknownHostUsesAttributableFault() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "10.2.0.10", subnetMask: "255.255.255.0", state: &state)
        startLocalDNSServer(nodeID: sourceNodeID, state: &state)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "dns resolve missing.local")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsResolveRejectedUnknownHost)
        XCTAssertEqual(state.lastRuntimeFault?.category, .networkService)
        XCTAssertEqual(state.lastRuntimeFault?.code, "dnsNXDOMAIN")
        XCTAssertTrue(state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.last?.contains("dnsNXDOMAIN") ?? false)
    }

    func testExecuteDHCPReleaseClearsRuntimeConfigurationAndEmitsDiagnostics() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "dhcp lease 10.2.0.10 255.255.255.0")
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "dhcp release")
        )

        XCTAssertNil(state.runtimeDHCPLeaseByNodeID[sourceNodeID])
        XCTAssertNil(state.runtimeDeviceConfigurations[sourceNodeID])
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dhcpLeaseReleased)
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertEqual(state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.last, "DHCP lease released")
    }

    func testExecuteDHCPReleaseRejectedWhenLeaseIsMissing() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "dhcp release")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dhcpLeaseRejectedMissingLease)
        XCTAssertEqual(state.lastRuntimeFault?.category, .networkService)
        XCTAssertEqual(state.lastRuntimeFault?.code, "dhcpLeaseMissing")
    }

    func testExecuteDNSRemoveCommandDeletesRecordAndEmitsDiagnostics() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "10.2.0.10", subnetMask: "255.255.255.0", state: &state)
        startLocalDNSServer(nodeID: sourceNodeID, state: &state)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "dns add classroom.local 10.2.0.44")
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "dns remove classroom.local")
        )

        XCTAssertNil(state.runtimeDNSServerConfigurationsByNodeID[sourceNodeID]?.recordsByHostname["classroom.local"])
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsRecordRemoved)
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertEqual(state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.last, "DNS record removed: classroom.local")
    }

    func testTypedDNSMXAndNSReducerActionsAddResolveAndRemoveRecords() {
        var state = TopologyEditorState()
        let dnsNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        state.runtimeDeviceConfigurations[dnsNodeID] = TopologyRuntimeDeviceConfiguration(
            ipAddress: "10.2.0.10",
            subnetMask: "255.255.255.0",
            dnsServer: "10.2.0.10"
        )
        startLocalDNSServer(nodeID: dnsNodeID, state: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSAddTypedRecord(
                nodeID: dnsNodeID,
                hostname: "mail.example.test",
                recordType: .mailExchange,
                target: "mx.example.test.",
                ttlSeconds: 600
            )
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsRecordRegistered)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSAddTypedRecord(
                nodeID: dnsNodeID,
                hostname: "example.test",
                recordType: .nameServer,
                target: "ns1.example.test.",
                ttlSeconds: 900
            )
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsRecordRegistered)

        guard let dnsConfiguration = state.runtimeDNSServerConfigurationsByNodeID[dnsNodeID] else {
            XCTFail(
                "Typed DNS configuration missing; installed=\(String(describing: state.runtimeInstalledProgramsByNodeID[dnsNodeID])), active=\(String(describing: state.runtimeActiveProgramByNodeID[dnsNodeID])), socket=\(String(describing: state.runtimeDNSServerSocketIDByNodeID[dnsNodeID])), event=\(String(describing: state.lastRuntimeEvent)), fault=\(String(describing: state.lastRuntimeFault))"
            )
            return
        }
        let typedRecords = dnsConfiguration.additionalTypedRecords
        XCTAssertTrue(typedRecords.contains {
            $0.name.rawValue == "mail.example.test"
                && $0.type == .mailExchange
                && $0.target == "mx.example.test."
                && $0.ttlSeconds == 600
        })
        XCTAssertTrue(typedRecords.contains {
            $0.name.rawValue == "example.test"
                && $0.type == .nameServer
                && $0.target == "ns1.example.test."
                && $0.ttlSeconds == 900
        })

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSResolveTypedRecord(
                nodeID: dnsNodeID,
                hostname: "mail.example.test",
                recordType: .mailExchange
            )
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsResolveSucceeded)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("type=MX") == true)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("mx.example.test") == true)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSResolveTypedRecord(
                nodeID: dnsNodeID,
                hostname: "example.test",
                recordType: .nameServer
            )
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsResolveSucceeded)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("type=NS") == true)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("ns1.example.test") == true)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSRemoveTypedRecord(
                nodeID: dnsNodeID,
                hostname: "mail.example.test",
                recordType: .mailExchange,
                target: "mx.example.test."
            )
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsRecordRemoved)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSRemoveTypedRecord(
                nodeID: dnsNodeID,
                hostname: "example.test",
                recordType: .nameServer,
                target: "ns1.example.test."
            )
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsRecordRemoved)
        XCTAssertTrue(
            state.runtimeDNSServerConfigurationsByNodeID[dnsNodeID]?.additionalTypedRecords.isEmpty == true
        )
    }

    func testTypedDNSRecursiveForwardingResolvesAcrossTwoDNSServers() {
        var state = TopologyEditorState()
        let resolverNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let authoritativeNodeID = addNode(kind: .pc, at: CGPoint(x: 280, y: 30), to: &state)

        saveRuntimeIP(
            nodeID: resolverNodeID,
            ipAddress: "10.0.0.10",
            subnetMask: "255.255.255.0",
            state: &state
        )
        saveRuntimeIP(
            nodeID: authoritativeNodeID,
            ipAddress: "10.0.0.53",
            subnetMask: "255.255.255.0",
            state: &state
        )
        connect(resolverNodeID, authoritativeNodeID, state: &state)
        startLocalDNSServer(nodeID: resolverNodeID, state: &state)
        startLocalDNSServer(nodeID: authoritativeNodeID, state: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSAddTypedRecord(
                nodeID: authoritativeNodeID,
                hostname: "mail.forwarded.test",
                recordType: .mailExchange,
                target: "mx.forwarded.test.",
                ttlSeconds: 120
            )
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsRecordRegistered)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSSetRecursion(
                nodeID: resolverNodeID,
                enabled: true,
                forwardingServerIPAddress: "10.0.0.53"
            )
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsRecordRegistered)
        XCTAssertTrue(
            state.runtimeDNSServerConfigurationsByNodeID[resolverNodeID]?.recursiveResolutionEnabled == true
        )
        XCTAssertEqual(
            state.runtimeDNSServerConfigurationsByNodeID[resolverNodeID]?.forwardingServerIPAddress,
            "10.0.0.53"
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSResolveTypedRecord(
                nodeID: resolverNodeID,
                hostname: "mail.forwarded.test",
                recordType: .mailExchange
            )
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsResolveSucceeded)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("server=10.0.0.53") == true)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("hops=1") == true)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testTypedDNSRecursiveForwardingRejectsUnreachableUpstream() {
        var state = TopologyEditorState()
        let resolverNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let authoritativeNodeID = addNode(kind: .pc, at: CGPoint(x: 280, y: 30), to: &state)

        saveRuntimeIP(
            nodeID: resolverNodeID,
            ipAddress: "10.0.0.10",
            subnetMask: "255.255.255.0",
            state: &state
        )
        saveRuntimeIP(
            nodeID: authoritativeNodeID,
            ipAddress: "10.0.0.53",
            subnetMask: "255.255.255.0",
            state: &state
        )
        startLocalDNSServer(nodeID: resolverNodeID, state: &state)
        startLocalDNSServer(nodeID: authoritativeNodeID, state: &state)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSAddTypedRecord(
                nodeID: authoritativeNodeID,
                hostname: "mail.unreachable.test",
                recordType: .mailExchange,
                target: "mx.unreachable.test.",
                ttlSeconds: 120
            )
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSSetRecursion(
                nodeID: resolverNodeID,
                enabled: true,
                forwardingServerIPAddress: "10.0.0.53"
            )
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSResolveTypedRecord(
                nodeID: resolverNodeID,
                hostname: "mail.unreachable.test",
                recordType: .mailExchange
            )
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsResolveRejectedUnreachable)
        XCTAssertEqual(state.lastRuntimeFault?.code, "dnsResolutionFailed")
        XCTAssertTrue(state.lastRuntimeFault?.message.contains("10.0.0.53") == true)
    }

    func testTypedDNSResolverReusesTTLCacheWithoutAdditionalNetworkPackets() {
        var state = TopologyEditorState()
        let clientNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let dnsNodeID = addNode(kind: .pc, at: CGPoint(x: 280, y: 30), to: &state)
        connect(clientNodeID, dnsNodeID, state: &state)
        saveRuntimeIP(
            nodeID: clientNodeID,
            ipAddress: "10.0.0.10",
            subnetMask: "255.255.255.0",
            state: &state
        )
        saveRuntimeIP(
            nodeID: dnsNodeID,
            ipAddress: "10.0.0.53",
            subnetMask: "255.255.255.0",
            state: &state
        )
        startLocalDNSServer(nodeID: dnsNodeID, state: &state)
        let clientConfiguration = tryUnwrap(state.runtimeDeviceConfigurations[clientNodeID])
        state.runtimeDeviceConfigurations[clientNodeID] = TopologyRuntimeDeviceConfiguration(
            ipAddress: clientConfiguration.ipAddress,
            subnetMask: clientConfiguration.subnetMask,
            defaultGateway: clientConfiguration.defaultGateway,
            dnsServer: "10.0.0.53"
        )
        state.networkRuntime.updateDeviceConfiguration(
            nodeID: clientNodeID,
            configuration: tryUnwrap(state.runtimeDeviceConfigurations[clientNodeID])
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSAddTypedRecord(
                nodeID: dnsNodeID,
                hostname: "school.cache.test",
                recordType: .nameServer,
                target: "ns.school.cache.test.",
                ttlSeconds: 120
            )
        )

        let first = state.resolveRuntimeDNSQuestion(
            nodeID: clientNodeID,
            hostname: "school.cache.test",
            recordType: .nameServer
        )
        let firstTraceCount = state.networkRuntime.state.packetTraces.count
        let second = state.resolveRuntimeDNSQuestion(
            nodeID: clientNodeID,
            hostname: "school.cache.test",
            recordType: .nameServer
        )

        XCTAssertFalse(first.trace.cacheHit)
        XCTAssertTrue(second.trace.cacheHit)
        XCTAssertEqual(state.networkRuntime.state.packetTraces.count, firstTraceCount)
        XCTAssertEqual(state.runtimeTypedDNSResolverCacheByNodeID[clientNodeID]?.entryCount, 1)
    }

    func testExecuteDNSRemoveUnknownHostUsesAttributableFault() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "dns remove missing.local")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsRecordRejectedUnknownHost)
        XCTAssertEqual(state.lastRuntimeFault?.category, .networkService)
        XCTAssertEqual(state.lastRuntimeFault?.code, "dnsUnknownHost")
    }

    func testOrdinaryHostnameResolutionFollowsNSReferralFromRequestingClient() {
        var state = TopologyEditorState()
        let clientNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let referralNodeID = addNode(kind: .pc, at: CGPoint(x: 280, y: 30), to: &state)
        let authorityNodeID = addNode(kind: .pc, at: CGPoint(x: 530, y: 30), to: &state)
        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 280, y: 140), to: &state)
        connect(clientNodeID, switchNodeID, state: &state)
        connect(referralNodeID, switchNodeID, state: &state)
        connect(authorityNodeID, switchNodeID, state: &state)

        saveRuntimeIP(
            nodeID: clientNodeID, ipAddress: "10.0.0.10",
            subnetMask: "255.255.255.0", state: &state
        )
        saveRuntimeIP(
            nodeID: referralNodeID, ipAddress: "10.0.0.1",
            subnetMask: "255.255.255.0", state: &state
        )
        saveRuntimeIP(
            nodeID: authorityNodeID, ipAddress: "10.0.0.53",
            subnetMask: "255.255.255.0", state: &state
        )
        startLocalDNSServer(nodeID: referralNodeID, state: &state)
        startLocalDNSServer(nodeID: authorityNodeID, state: &state)

        let clientConfiguration = tryUnwrap(state.runtimeDeviceConfigurations[clientNodeID])
        state.runtimeDeviceConfigurations[clientNodeID] = TopologyRuntimeDeviceConfiguration(
            ipAddress: clientConfiguration.ipAddress,
            subnetMask: clientConfiguration.subnetMask,
            defaultGateway: clientConfiguration.defaultGateway,
            dnsServer: "10.0.0.1"
        )
        state.networkRuntime.updateDeviceConfiguration(
            nodeID: clientNodeID,
            configuration: tryUnwrap(state.runtimeDeviceConfigurations[clientNodeID])
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSAddTypedRecord(
                nodeID: referralNodeID, hostname: "school.test",
                recordType: .nameServer, target: "ns.school.test.", ttlSeconds: 120
            )
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSAddTypedRecord(
                nodeID: referralNodeID, hostname: "ns.school.test",
                recordType: .address, target: "10.0.0.53", ttlSeconds: 120
            )
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSAddTypedRecord(
                nodeID: authorityNodeID, hostname: "www.school.test",
                recordType: .address, target: "10.0.0.20", ttlSeconds: 120
            )
        )

        let first = state.resolveRuntimeHostname(
            nodeID: clientNodeID, hostname: "www.school.test"
        )
        let packetTraceCount = state.networkRuntime.state.packetTraces.count
        let second = state.resolveRuntimeHostname(
            nodeID: clientNodeID, hostname: "www.school.test"
        )

        XCTAssertEqual(
            first,
            .success(
                record: TopologyRuntimeDNSRecord(
                    hostname: "www.school.test", targetIPAddress: "10.0.0.20"
                ),
                serverIPAddress: "10.0.0.1", cached: false
            )
        )
        XCTAssertEqual(
            second,
            .success(
                record: TopologyRuntimeDNSRecord(
                    hostname: "www.school.test", targetIPAddress: "10.0.0.20"
                ),
                serverIPAddress: "10.0.0.1", cached: true
            )
        )
        XCTAssertEqual(state.networkRuntime.state.packetTraces.count, packetTraceCount + 1)
        XCTAssertEqual(state.networkRuntime.state.packetTraces.last?.detail, "DNS cache hit server=10.0.0.1")
    }

    func testOrdinaryHostnameResolutionUsesRecursiveForwarder() {
        var state = TopologyEditorState()
        let clientNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let resolverNodeID = addNode(kind: .pc, at: CGPoint(x: 280, y: 30), to: &state)
        let upstreamNodeID = addNode(kind: .pc, at: CGPoint(x: 530, y: 30), to: &state)
        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 280, y: 140), to: &state)
        connect(clientNodeID, switchNodeID, state: &state)
        connect(resolverNodeID, switchNodeID, state: &state)
        connect(upstreamNodeID, switchNodeID, state: &state)

        saveRuntimeIP(
            nodeID: clientNodeID, ipAddress: "10.1.0.10",
            subnetMask: "255.255.255.0", state: &state
        )
        saveRuntimeIP(
            nodeID: resolverNodeID, ipAddress: "10.1.0.1",
            subnetMask: "255.255.255.0", state: &state
        )
        saveRuntimeIP(
            nodeID: upstreamNodeID, ipAddress: "10.1.0.53",
            subnetMask: "255.255.255.0", state: &state
        )
        startLocalDNSServer(nodeID: resolverNodeID, state: &state)
        startLocalDNSServer(nodeID: upstreamNodeID, state: &state)

        let clientConfiguration = tryUnwrap(state.runtimeDeviceConfigurations[clientNodeID])
        state.runtimeDeviceConfigurations[clientNodeID] = TopologyRuntimeDeviceConfiguration(
            ipAddress: clientConfiguration.ipAddress,
            subnetMask: clientConfiguration.subnetMask,
            defaultGateway: clientConfiguration.defaultGateway,
            dnsServer: "10.1.0.1"
        )
        state.networkRuntime.updateDeviceConfiguration(
            nodeID: clientNodeID,
            configuration: tryUnwrap(state.runtimeDeviceConfigurations[clientNodeID])
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSAddTypedRecord(
                nodeID: upstreamNodeID, hostname: "forwarded.school.test",
                recordType: .address, target: "10.1.0.20", ttlSeconds: 120
            )
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSSetRecursion(
                nodeID: resolverNodeID, enabled: true,
                forwardingServerIPAddress: "10.1.0.53"
            )
        )

        XCTAssertEqual(
            state.resolveRuntimeHostname(
                nodeID: clientNodeID, hostname: "forwarded.school.test"
            ),
            .success(
                record: TopologyRuntimeDNSRecord(
                    hostname: "forwarded.school.test", targetIPAddress: "10.1.0.20"
                ),
                serverIPAddress: "10.1.0.1", cached: false
            )
        )
    }

    func testExecutePingAndTraceResolveHostnameTargetsViaDNSRecords() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 280, y: 30), to: &state)
        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 150, y: 100), to: &state)
        connect(sourceNodeID, switchNodeID, state: &state)
        connect(targetNodeID, switchNodeID, state: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "192.168.0.20", subnetMask: "255.255.255.0", state: &state)

        startLocalDNSServer(nodeID: sourceNodeID, state: &state)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "dns add host-a.local 192.168.0.20")
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "ping host-a.local")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .pingSucceeded)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("targetHost=host-a.local") ?? false)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "trace host-a.local")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .traceSucceeded)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("targetHost=host-a.local") ?? false)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testExecutePingHostnameUnknownHostUsesServiceFault() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)

        startLocalDNSServer(nodeID: sourceNodeID, state: &state)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "ping missing.local")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .pingRejectedUnknownTarget)
        XCTAssertEqual(state.lastRuntimeFault?.category, .networkService)
        XCTAssertEqual(state.lastRuntimeFault?.code, "dnsNXDOMAIN")
    }

    func testExecuteTraceHostnameUnknownHostUsesServiceFault() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)

        startLocalDNSServer(nodeID: sourceNodeID, state: &state)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "trace missing.local")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .traceRejectedUnknownTarget)
        XCTAssertEqual(state.lastRuntimeFault?.category, .networkService)
        XCTAssertEqual(state.lastRuntimeFault?.code, "dnsNXDOMAIN")
    }

    func testExecuteTraceTwentyNodeRuntimeDepthContractIsDeterministic() {
        let phaseTag = "[M002/S03/T03 tests]"
        var state = TopologyEditorState()

        var pathNodeIDs: [UUID] = []
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        pathNodeIDs.append(sourceNodeID)

        for index in 1...18 {
            let switchNodeID = addNode(
                kind: .networkSwitch,
                at: CGPoint(x: CGFloat(20 + (index * 20)), y: index.isMultiple(of: 2) ? 20 : 120),
                to: &state
            )
            pathNodeIDs.append(switchNodeID)
        }

        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 420, y: 20), to: &state)
        pathNodeIDs.append(targetNodeID)

        for (source, destination) in zip(pathNodeIDs, pathNodeIDs.dropFirst()) {
            connect(source, destination, state: &state)
        }

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "10.20.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "10.20.0.20", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        let tickSnapshot = state.simulationTick

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "trace 10.20.0.20"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .traceSucceeded, "\(phaseTag) expected trace success over 20-node chain")

        let detail = tryUnwrap(state.lastRuntimeEvent?.detail)
        let expectedPath = pathNodeIDs.map(\.uuidString).joined(separator: "->")

        XCTAssertTrue(detail.contains("command=trace"), "\(phaseTag) runtime detail should record trace command")
        XCTAssertTrue(detail.contains("targetIP=10.20.0.20"), "\(phaseTag) runtime detail should retain target attribution")
        XCTAssertTrue(detail.contains("hops=19"), "\(phaseTag) deterministic chain should produce 19 hops")
        XCTAssertTrue(detail.contains("latencyMs=78"), "\(phaseTag) deterministic latency should scale with hop count")
        XCTAssertTrue(detail.contains("path=\(expectedPath)"), "\(phaseTag) runtime detail should expose full path metadata")

        XCTAssertEqual(state.simulationTick, tickSnapshot, "\(phaseTag) trace execution should not mutate simulation tick directly")
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertNil(state.lastPingEvent)

        XCTAssertEqual(
            Array(state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.suffix(2) ?? []),
            [
                "Trace to 10.20.0.20 succeeded (hops=19, latencyMs=78)",
                "Path: \(pathNodeIDs.map(\.uuidString).joined(separator: " -> "))"
            ]
        )
    }

    func testShortestPathHopCountReturnsExpectedHopsForLinearTopology() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let switchAID = addNode(kind: .networkSwitch, at: CGPoint(x: 140, y: 20), to: &state)
        let switchBID = addNode(kind: .networkSwitch, at: CGPoint(x: 260, y: 20), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 380, y: 20), to: &state)

        connect(sourceNodeID, switchAID, state: &state)
        connect(switchAID, switchBID, state: &state)
        connect(switchBID, targetNodeID, state: &state)

        XCTAssertEqual(state.graph.shortestPathHopCount(from: sourceNodeID, to: targetNodeID), 3)
        XCTAssertEqual(state.graph.shortestPathNodeIDs(from: sourceNodeID, to: targetNodeID), [sourceNodeID, switchAID, switchBID, targetNodeID])
    }

    func testShortestPathHelpersHandleIdentityAndMissingNodesDeterministically() {
        var state = TopologyEditorState()

        let existingNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let missingNodeID = uuid("99999999-9999-9999-9999-999999999999")

        XCTAssertEqual(state.graph.shortestPathHopCount(from: existingNodeID, to: existingNodeID), 0)
        XCTAssertEqual(state.graph.shortestPathNodeIDs(from: existingNodeID, to: existingNodeID), [existingNodeID])
        XCTAssertNil(state.graph.shortestPathHopCount(from: existingNodeID, to: missingNodeID))
        XCTAssertNil(state.graph.shortestPathNodeIDs(from: existingNodeID, to: missingNodeID))
    }

    func testShortestPathNodeIDsPrefersLexicographicallyStableRouteWhenHopsTie() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(
            kind: .networkSwitch,
            at: CGPoint(x: 40, y: 40),
            nodeID: uuid("10000000-0000-0000-0000-000000000001"),
            to: &state
        )
        let preferredMidNodeID = addNode(
            kind: .networkSwitch,
            at: CGPoint(x: 180, y: 10),
            nodeID: uuid("20000000-0000-0000-0000-000000000002"),
            to: &state
        )
        let alternateMidNodeID = addNode(
            kind: .networkSwitch,
            at: CGPoint(x: 180, y: 100),
            nodeID: uuid("30000000-0000-0000-0000-000000000003"),
            to: &state
        )
        let targetNodeID = addNode(
            kind: .networkSwitch,
            at: CGPoint(x: 340, y: 40),
            nodeID: uuid("40000000-0000-0000-0000-000000000004"),
            to: &state
        )

        // Insert links in non-lexicographic order to prove deterministic route selection is data-order independent.
        connect(sourceNodeID, alternateMidNodeID, state: &state)
        connect(sourceNodeID, preferredMidNodeID, state: &state)
        connect(alternateMidNodeID, targetNodeID, state: &state)
        connect(preferredMidNodeID, targetNodeID, state: &state)

        XCTAssertEqual(state.graph.shortestPathHopCount(from: sourceNodeID, to: targetNodeID), 2)
        XCTAssertEqual(state.graph.shortestPathNodeIDs(from: sourceNodeID, to: targetNodeID), [sourceNodeID, preferredMidNodeID, targetNodeID])
    }

    func testAdjacencyAndReachabilityHelpersPreserveExistingSemantics() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 30, y: 30), to: &state)
        let firstNeighborID = addNode(kind: .networkSwitch, at: CGPoint(x: 180, y: 30), to: &state)
        let secondNeighborID = addNode(kind: .networkSwitch, at: CGPoint(x: 180, y: 150), to: &state)
        let disconnectedNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 340, y: 30), to: &state)

        connect(sourceNodeID, firstNeighborID, state: &state)
        connect(sourceNodeID, secondNeighborID, state: &state)

        XCTAssertEqual(state.graph.adjacentNodeIDs(for: sourceNodeID), [firstNeighborID, secondNeighborID])
        XCTAssertTrue(state.graph.isReachable(from: sourceNodeID, to: secondNeighborID))
        XCTAssertFalse(state.graph.isReachable(from: sourceNodeID, to: disconnectedNodeID))
        XCTAssertNil(state.graph.shortestPathHopCount(from: sourceNodeID, to: disconnectedNodeID))
    }

    func testPersistenceRevisionAdvancesOnlyForDurableMutations() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        XCTAssertEqual(state.persistenceRevision, 1)

        TopologyEditorReducer.reduce(state: &state, action: .setActiveTool(mode: .connect))
        XCTAssertEqual(state.persistenceRevision, 1)

        TopologyEditorReducer.reduce(state: &state, action: .selectSingleNode(nodeID: nodeID))
        XCTAssertEqual(state.persistenceRevision, 1)

        TopologyEditorReducer.reduce(state: &state, action: .panCanvas(delta: CGSize(width: 30, height: -10)))
        XCTAssertEqual(state.persistenceRevision, 2)

        TopologyEditorReducer.reduce(state: &state, action: .zoomCanvas(scaleDelta: 1.2, anchor: CGPoint(x: 0, y: 0)))
        XCTAssertEqual(state.persistenceRevision, 3)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .moveSelectedNodes(delta: CGSize(width: 5, height: 5))
        )
        XCTAssertEqual(state.persistenceRevision, 4)
    }

    func testMalformedOrNoOpDurableActionsDoNotAdvancePersistenceRevision() {
        var state = TopologyEditorState()
        _ = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)
        let startingRevision = state.persistenceRevision

        TopologyEditorReducer.reduce(state: &state, action: .moveSelectedNodes(delta: .zero))
        XCTAssertEqual(state.persistenceRevision, startingRevision)

        TopologyEditorReducer.reduce(state: &state, action: .moveSelectedNodes(delta: nil))
        XCTAssertEqual(state.persistenceRevision, startingRevision)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .panCanvas(delta: CGSize(width: CGFloat.infinity, height: 1))
        )
        XCTAssertEqual(state.persistenceRevision, startingRevision)

        TopologyEditorReducer.reduce(state: &state, action: .zoomCanvas(scaleDelta: 0, anchor: nil))
        XCTAssertEqual(state.persistenceRevision, startingRevision)
    }

    func testDismissPersistenceErrorClearsFailureWithoutAdvancingRevision() {
        var state = TopologyEditorState()
        state.persistenceRevision = 9
        state.recordPersistenceFailure(
            operation: .save,
            code: .fileWriteFailed,
            detail: "sandbox write denied"
        )

        TopologyEditorReducer.reduce(state: &state, action: .dismissPersistenceError)

        XCTAssertNil(state.lastPersistenceError)
        XCTAssertEqual(state.persistenceRevision, 9)
        XCTAssertEqual(state.lastAction, "dismissPersistenceError")
    }

    func testRuntimeServiceDNSActionsViaAppShellMutateStateAndPublishDiagnostics() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        saveRuntimeIP(nodeID: nodeID, ipAddress: "10.10.0.10", subnetMask: "255.255.255.0", state: &state)
        startLocalDNSServer(nodeID: nodeID, state: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSAddRecord(nodeID: nodeID, hostname: "service.lab", targetIPAddress: "10.10.0.22")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsRecordRegistered)
        XCTAssertEqual(state.runtimeDNSServerConfigurationsByNodeID[nodeID]?.recordsByHostname["service.lab"]?.targetIPAddress, "10.10.0.22")

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSResolveRecord(nodeID: nodeID, hostname: "service.lab")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsResolveSucceeded)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("host=service.lab") ?? false)
        XCTAssertEqual(
            state.runtimeConsoleEntriesByNodeID[nodeID]?.last,
            "DNS resolved service.lab -> 10.10.0.22 via 10.10.0.10 [cache miss]"
        )
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testRuntimeServiceDHCPActionsViaAppShellRejectMalformedAndMissingLeaseDeterministically() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .dhcpServer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .dhcpServer))

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDHCPLease(nodeID: nodeID, ipAddress: "  ", subnetMask: "255.255.255.0")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dhcpLeaseRejectedMalformedCommand)
        XCTAssertEqual(state.lastRuntimeFault?.code, "malformedDHCPCommand")

        TopologyEditorReducer.reduce(state: &state, action: .runtimeDHCPRelease(nodeID: nodeID))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dhcpLeaseRejectedMissingLease)
        XCTAssertEqual(state.lastRuntimeFault?.code, "dhcpLeaseMissing")
    }

    func testRuntimeWebAndEchoLifecycleViaAppShellAreDeterministicAndIdempotent() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .webServer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .webServer))

        TopologyEditorReducer.reduce(state: &state, action: .runtimeWebStart(nodeID: nodeID, port: "8080"))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .webServerStarted)
        XCTAssertEqual(state.runtimeWebServerByNodeID[nodeID]?.port, 8080)
        let webSocketID = try! XCTUnwrap(state.runtimeWebServerSocketIDByNodeID[nodeID])
        XCTAssertEqual(state.networkRuntime.state.socketsByID[webSocketID]?.tcpState, .listen)

        TopologyEditorReducer.reduce(state: &state, action: .runtimeWebStart(nodeID: nodeID, port: "8080"))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .webServerStartIgnoredAlreadyRunning)

        TopologyEditorReducer.reduce(state: &state, action: .runtimeWebStop(nodeID: nodeID))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .webServerStopped)
        XCTAssertNil(state.runtimeWebServerByNodeID[nodeID])
        XCTAssertNil(state.runtimeWebServerSocketIDByNodeID[nodeID])
        XCTAssertEqual(state.networkRuntime.state.socketsByID[webSocketID]?.tcpState, .closed)

        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .echoServer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .echoServer))

        TopologyEditorReducer.reduce(state: &state, action: .runtimeEchoStart(nodeID: nodeID, port: "7000"))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .echoServerStarted)
        XCTAssertEqual(state.runtimeEchoServerByNodeID[nodeID]?.port, 7000)
        let echoSocketID = try! XCTUnwrap(state.runtimeEchoServerSocketIDByNodeID[nodeID])
        XCTAssertEqual(state.networkRuntime.state.socketsByID[echoSocketID]?.tcpState, .listen)

        TopologyEditorReducer.reduce(state: &state, action: .runtimeEchoStop(nodeID: nodeID))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .echoServerStopped)
        XCTAssertNil(state.runtimeEchoServerByNodeID[nodeID])
        XCTAssertNil(state.runtimeEchoServerSocketIDByNodeID[nodeID])
        XCTAssertNil(state.networkRuntime.state.socketsByID[echoSocketID])
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testRuntimeServiceActionsRejectInvalidLaunchContext() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .dnsServer))

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSResolveRecord(nodeID: nodeID, hostname: "service.lab")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeServiceActionRejectedInvalidContext)
        XCTAssertEqual(state.lastRuntimeFault?.code, "runtimeProgramNotActive")
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("reason=programNotActive") ?? false)
    }

    func testRuntimeServiceDNSRemoveUnknownHostPublishesDeterministicFaultCode() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .dnsServer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .dnsServer))

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSRemoveRecord(nodeID: nodeID, hostname: "missing.service")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsRecordRejectedUnknownHost)
        XCTAssertEqual(state.lastRuntimeFault?.category, .networkService)
        XCTAssertEqual(state.lastRuntimeFault?.code, "dnsUnknownHost")
    }

    func testRuntimeServiceDHCPRepeatedLeaseAndReleaseRemainsDeterministic() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .dhcpServer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .dhcpServer))

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDHCPLease(nodeID: nodeID, ipAddress: "10.2.0.10", subnetMask: "255.255.255.0")
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dhcpLeaseAssigned)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDHCPLease(nodeID: nodeID, ipAddress: "10.2.0.11", subnetMask: "255.255.255.0")
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dhcpLeaseAssigned)
        XCTAssertEqual(state.runtimeDHCPLeaseByNodeID[nodeID]?.ipAddress, "10.2.0.11")

        TopologyEditorReducer.reduce(state: &state, action: .runtimeDHCPRelease(nodeID: nodeID))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dhcpLeaseReleased)

        TopologyEditorReducer.reduce(state: &state, action: .runtimeDHCPRelease(nodeID: nodeID))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dhcpLeaseRejectedMissingLease)
        XCTAssertEqual(state.lastRuntimeFault?.code, "dhcpLeaseMissing")
    }

    func testRuntimeServiceWebAndEchoStopBeforeStartUseIdempotentLifecycleEvents() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .webServer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .webServer))

        TopologyEditorReducer.reduce(state: &state, action: .runtimeWebStop(nodeID: nodeID))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .webServerStopIgnoredAlreadyStopped)
        XCTAssertNil(state.lastRuntimeFault)

        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .echoServer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .echoServer))

        TopologyEditorReducer.reduce(state: &state, action: .runtimeEchoStop(nodeID: nodeID))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .echoServerStopIgnoredAlreadyStopped)
        XCTAssertNil(state.lastRuntimeFault)
    }


    func testRIPConfigurationIsRouterOnlyAndUpdatesRunningRuntimeImmediately() {
        var state = TopologyEditorState()
        let routerID = addNode(kind: .router, at: CGPoint(x: 20, y: 20), to: &state)
        let gatewayID = addNode(kind: .gateway, at: CGPoint(x: 220, y: 20), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .setRuntimeRIPEnabled(nodeID: routerID, enabled: true)
        )
        XCTAssertEqual(state.runtimeRIPEnabledByNodeID[routerID], true)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeRIPConfigurationSaved)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        XCTAssertNotNil(state.networkRuntime.state.ripTablesByNodeID[routerID])
        XCTAssertTrue(state.networkRuntime.state.pendingEvents.contains {
            $0.kind == .ripBeacon(nodeID: routerID)
        })

        TopologyEditorReducer.reduce(
            state: &state,
            action: .setRuntimeRIPEnabled(nodeID: routerID, enabled: false)
        )
        XCTAssertNil(state.runtimeRIPEnabledByNodeID[routerID])
        XCTAssertNil(state.networkRuntime.state.ripTablesByNodeID[routerID])

        TopologyEditorReducer.reduce(
            state: &state,
            action: .setRuntimeRIPEnabled(nodeID: gatewayID, enabled: true)
        )
        XCTAssertNil(state.runtimeRIPEnabledByNodeID[gatewayID])
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeRIPConfigurationRejected)
        XCTAssertEqual(state.lastRuntimeFault?.code, "ripUnsupportedForNodeKind")
    }

    func testUninstallRuntimeProgramClosesActiveAppPreservesFilesAndSupportsReinstall() throws {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 40, y: 40), to: &state)
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .fileExplorer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .fileExplorer))
        var fileSystem = state.virtualFileSystemsByNodeID[nodeID] ?? .defaultForDevice()
        try fileSystem.createDirectory(at: "/home/student", recursive: true)
        try fileSystem.writeTextFile(at: "/home/student/lesson.txt", text: "keep me")
        state.virtualFileSystemsByNodeID[nodeID] = fileSystem
        state.runtimeFileExplorerSelectionByNodeID[nodeID] = "/home/student/lesson.txt"

        TopologyEditorReducer.reduce(state: &state, action: .uninstallRuntimeProgram(nodeID: nodeID, program: .fileExplorer))

        XCTAssertFalse(state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(.fileExplorer) == true)
        XCTAssertNil(state.runtimeActiveProgramByNodeID[nodeID])
        XCTAssertNil(state.runtimeFileExplorerSelectionByNodeID[nodeID])
        XCTAssertEqual(try state.virtualFileSystemsByNodeID[nodeID]?.textFile(at: "/home/student/lesson.txt"), "keep me")
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeProgramUninstalled)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("data=preserved") == true)

        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .fileExplorer))
        XCTAssertTrue(state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(.fileExplorer) == true)
        XCTAssertEqual(try state.virtualFileSystemsByNodeID[nodeID]?.textFile(at: "/home/student/lesson.txt"), "keep me")
    }

    func testUninstallRuntimeServiceRemovesTransientStateButPreservesConfiguration() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 40, y: 40), to: &state)
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .webServer))
        let configuration = TopologyRuntimeWebServerConfiguration(port: 8080)
        state.runtimeWebServerConfigurationsByNodeID[nodeID] = configuration
        state.runtimeWebServerByNodeID[nodeID] = TopologyRuntimeServiceProcessState(port: 8080)
        state.runtimeActiveProgramByNodeID[nodeID] = .webServer

        TopologyEditorReducer.reduce(state: &state, action: .uninstallRuntimeProgram(nodeID: nodeID, program: .webServer))

        XCTAssertNil(state.runtimeWebServerByNodeID[nodeID])
        XCTAssertNil(state.runtimeActiveProgramByNodeID[nodeID])
        XCTAssertEqual(state.runtimeWebServerConfigurationsByNodeID[nodeID], configuration)
        XCTAssertFalse(state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(.webServer) == true)
    }

    func testCancelConnectionClearsDraftWithoutDeletingSelection() {
        var state = TopologyEditorState()
        let first = addNode(kind: .pc, at: CGPoint(x: 40, y: 40), to: &state)
        let second = addNode(kind: .pc, at: CGPoint(x: 160, y: 40), to: &state)
        TopologyEditorReducer.reduce(state: &state, action: .selectSingleNode(nodeID: second))
        TopologyEditorReducer.reduce(state: &state, action: .startConnection(nodeID: first, portID: nil))
        XCTAssertNotNil(state.pendingConnection)
        let selectionBeforeCancel = state.selectedNodeIDs

        TopologyEditorReducer.reduce(state: &state, action: .cancelConnection)

        XCTAssertNil(state.pendingConnection)
        XCTAssertEqual(state.selectedNodeIDs, selectionBeforeCancel)
        XCTAssertEqual(state.lastAction, "cancelConnection")
    }

    // MARK: - Helpers

    @discardableResult
    func testDHCPConfigurationIsHostAndGatewayOnlyAndSavesJavaFieldsIndependently() {
        var state = TopologyEditorState()
        let hostID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let gatewayID = addNode(kind: .gateway, at: CGPoint(x: 160, y: 20), to: &state)
        let routerID = addNode(kind: .router, at: CGPoint(x: 300, y: 20), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .setRuntimeDHCPClientEnabled(nodeID: hostID, enabled: true)
        )
        XCTAssertEqual(state.runtimeDHCPClientConfigurationsByNodeID[hostID]?.isEnabled, true)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDHCPClientConfigurationSaved)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .setRuntimeDHCPClientEnabled(nodeID: routerID, enabled: true)
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDHCPClientConfigurationRejected)
        XCTAssertEqual(state.lastRuntimeFault?.code, "dhcpClientUnsupportedForNodeKind")

        let original = TopologyDHCPServerConfiguration(
            isActive: true,
            lowerBoundIPAddress: "10.0.0.20",
            upperBoundIPAddress: "10.0.0.30",
            gatewayIPAddress: "10.0.0.1",
            dnsServerIPAddress: "10.0.0.53",
            useOwnSettings: true
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeDHCPServerConfiguration(nodeID: hostID, configuration: original)
        )

        let edited = TopologyDHCPServerConfiguration(
            isActive: false,
            lowerBoundIPAddress: "10.0.0.21",
            upperBoundIPAddress: "999.0.0.1",
            gatewayIPAddress: "invalid",
            dnsServerIPAddress: "10.0.0.54",
            useOwnSettings: true,
            staticAssignments: [
                TopologyDHCPStaticAssignment(macAddress: "aa:bb:cc:dd:ee:ff", ipAddress: "10.0.0.25"),
                TopologyDHCPStaticAssignment(macAddress: "AA:BB:CC:DD:EE:FF", ipAddress: "10.0.0.26"),
                TopologyDHCPStaticAssignment(macAddress: "bad", ipAddress: "10.0.0.27"),
            ]
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeDHCPServerConfiguration(nodeID: hostID, configuration: edited)
        )

        let hostConfiguration = state.runtimeDHCPServerConfigurationsByNodeID[hostID]
        XCTAssertEqual(hostConfiguration?.isActive, false)
        XCTAssertEqual(hostConfiguration?.lowerBoundIPAddress, "10.0.0.21")
        XCTAssertEqual(hostConfiguration?.upperBoundIPAddress, "10.0.0.30")
        XCTAssertEqual(hostConfiguration?.gatewayIPAddress, "10.0.0.1")
        XCTAssertEqual(hostConfiguration?.dnsServerIPAddress, "10.0.0.54")
        XCTAssertEqual(hostConfiguration?.staticAssignments.count, 1)
        XCTAssertEqual(hostConfiguration?.staticAssignments.first?.macAddress, "AA:BB:CC:DD:EE:FF")

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeDHCPServerConfiguration(
                nodeID: gatewayID,
                configuration: TopologyDHCPServerConfiguration(
                    isActive: true,
                    lowerBoundIPAddress: "192.168.0.20",
                    upperBoundIPAddress: "192.168.0.30",
                    gatewayIPAddress: "192.168.0.99",
                    dnsServerIPAddress: "192.168.0.53",
                    useOwnSettings: true
                )
            )
        )
        let gatewayConfiguration = state.runtimeDHCPServerConfigurationsByNodeID[gatewayID]
        XCTAssertEqual(gatewayConfiguration?.gatewayIPAddress, "0.0.0.0")
        XCTAssertEqual(gatewayConfiguration?.dnsServerIPAddress, "192.168.0.53")
        XCTAssertEqual(gatewayConfiguration?.useOwnSettings, false)
    }

    func testFirewallConfigurationSupportsInstalledEndpointProgramAndUpdatesRunningRuntime() {
        var state = TopologyEditorState()
        let routerID = addNode(kind: .router, at: CGPoint(x: 20, y: 20), to: &state)
        let gatewayID = addNode(kind: .gateway, at: CGPoint(x: 160, y: 20), to: &state)
        let hostID = addNode(kind: .pc, at: CGPoint(x: 300, y: 20), to: &state)
        let configuration = TopologyFirewallConfiguration(
            isActive: true,
            defaultPolicy: .drop,
            dropICMP: true,
            filterSYNSegmentsOnly: true,
            filterUDP: true,
            rules: [
                TopologyFirewallRule(
                    sourceIPAddress: "10.0.0.0",
                    sourceSubnetMask: "255.255.255.0",
                    destinationIPAddress: "192.168.0.10",
                    destinationSubnetMask: "255.255.255.255",
                    port: 443,
                    protocolType: .tcp,
                    action: .accept
                ),
            ]
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeFirewallConfiguration(nodeID: routerID, configuration: configuration)
        )
        XCTAssertEqual(state.runtimeFirewallConfigurationsByNodeID[routerID], configuration)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeFirewallConfigurationSaved)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        let gatewayConfiguration = TopologyFirewallConfiguration(
            isActive: true,
            defaultPolicy: .accept,
            filterSYNSegmentsOnly: false,
            filterUDP: false,
            rules: [TopologyFirewallRule(protocolType: .all, action: .drop)]
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeFirewallConfiguration(nodeID: gatewayID, configuration: gatewayConfiguration)
        )
        XCTAssertEqual(
            state.networkRuntime.state.topologySnapshot.firewallConfigurationsByNodeID[gatewayID],
            gatewayConfiguration
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeFirewallConfiguration(nodeID: hostID, configuration: configuration)
        )
        XCTAssertNil(state.runtimeFirewallConfigurationsByNodeID[hostID])
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeFirewallConfigurationRejected)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .installRuntimeProgram(nodeID: hostID, program: .firewall)
        )
        XCTAssertEqual(
            state.runtimeFirewallConfigurationsByNodeID[hostID],
            TopologyFirewallConfiguration.javaPersonalDefaults
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeFirewallConfiguration(nodeID: hostID, configuration: configuration)
        )
        XCTAssertEqual(state.runtimeFirewallConfigurationsByNodeID[hostID], configuration)
        XCTAssertEqual(
            state.networkRuntime.state.topologySnapshot.firewallConfigurationsByNodeID[hostID],
            configuration
        )

        var invalid = configuration
        invalid.rules[0].port = 70_000
        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeFirewallConfiguration(nodeID: routerID, configuration: invalid)
        )
        XCTAssertEqual(state.runtimeFirewallConfigurationsByNodeID[routerID], configuration)
        XCTAssertEqual(state.lastRuntimeFault?.code, "invalidFirewallRule")
    }

    func testNATTableResetIsGatewayOnlyAndRecordsRuntimeEvent() {
        var state = TopologyEditorState()
        let gatewayID = addNode(kind: .gateway, at: CGPoint(x: 20, y: 20), to: &state)
        let hostID = addNode(kind: .pc, at: CGPoint(x: 160, y: 20), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .resetRuntimeNATTable(nodeID: gatewayID)
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeNATTableReset)
        XCTAssertNil(state.lastRuntimeFault)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .resetRuntimeNATTable(nodeID: hostID)
        )
        XCTAssertEqual(state.lastRuntimeFault?.code, "natUnsupportedForNodeKind")
    }
    func testPortForwardingRowsPersistInvalidJavaRowsAndAreGatewayOnly() {
        var state = TopologyEditorState()
        let gatewayID = addNode(kind: .gateway, at: CGPoint(x: 20, y: 20), to: &state)
        let routerID = addNode(kind: .router, at: CGPoint(x: 160, y: 20), to: &state)
        let rows = [
            TopologyGatewayPortForwardingRow(
                protocolValue: "TCP",
                publicPortValue: "443",
                lanIPAddress: "192.168.0.10",
                lanPortValue: "8443"
            ),
            TopologyGatewayPortForwardingRow(
                protocolValue: "broken",
                publicPortValue: "70000",
                lanIPAddress: "not-an-ip",
                lanPortValue: "0"
            ),
        ]

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimePortForwardingRows(nodeID: gatewayID, rows: rows)
        )
        XCTAssertEqual(state.runtimePortForwardingRowsByNodeID[gatewayID], rows)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimePortForwardingConfigurationSaved)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        XCTAssertEqual(
            state.networkRuntime.state.topologySnapshot.portForwardingRowsByNodeID[gatewayID],
            rows
        )
        XCTAssertEqual(
            state.networkRuntime.natMappings(gatewayNodeID: gatewayID).filter { $0.type == .staticEntry }.count,
            1
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimePortForwardingRows(nodeID: routerID, rows: rows)
        )
        XCTAssertNil(state.runtimePortForwardingRowsByNodeID[routerID])
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimePortForwardingConfigurationRejected)
    }
    func testResetRuntimePacketCaptureSupportsInterfaceAndGlobalJavaTableReset() {
        var state = TopologyEditorState()
        let nodeID = uuid("00000000-0000-0000-0000-000000002401")
        let firstInterfaceID = uuid("00000000-0000-0000-0000-000000002411")
        let secondInterfaceID = uuid("00000000-0000-0000-0000-000000002412")
        state.networkRuntime.recordTrace(
            nodeID: nodeID,
            interfaceID: firstInterfaceID,
            direction: .inbound,
            layer: .dataLink,
            operation: .received
        )
        state.networkRuntime.recordTrace(
            nodeID: nodeID,
            interfaceID: secondInterfaceID,
            direction: .outbound,
            layer: .network,
            operation: .sent
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .resetRuntimePacketCapture(nodeID: nodeID, interfaceID: firstInterfaceID)
        )
        XCTAssertEqual(state.networkRuntime.state.packetTraces.map(\.interfaceID), [secondInterfaceID])

        TopologyEditorReducer.reduce(
            state: &state,
            action: .resetRuntimePacketCapture(nodeID: nil, interfaceID: nil)
        )
        XCTAssertTrue(state.networkRuntime.state.packetTraces.isEmpty)
    }

    private struct WebVirtualHostRuntimeFixture {
        var state: TopologyEditorState
        let clientNodeID: UUID
        let serverNodeID: UUID
    }

    private struct WebRuntimeResponse {
        let statusCode: Int
        let body: String
        let detail: String
    }

    private func makeWebVirtualHostRuntime() throws -> WebVirtualHostRuntimeFixture {
        let clientNodeID = uuid("00000000-0000-0000-0000-00000000A001")
        let serverNodeID = uuid("00000000-0000-0000-0000-00000000A002")
        let hosts = [
            try TopologyRuntimeWebVirtualHost(
                id: "default", hostname: "default.lab", documentRoot: "/sites/default"
            ),
            try TopologyRuntimeWebVirtualHost(
                id: "exact", hostname: "exact.lab", documentRoot: "/sites/exact"
            ),
            try TopologyRuntimeWebVirtualHost(
                id: "port-specific", hostname: "port.lab", port: 8080, documentRoot: "/sites/port-specific"
            ),
        ]
        let virtualHosts = try TopologyRuntimeWebVirtualHostConfiguration(
            hosts: hosts, defaultHostID: "default"
        )
        let fileSystem = try TopologyVirtualFileSystem(entries: [
            TopologyVirtualFileEntry(path: "/sites", content: .directory),
            TopologyVirtualFileEntry(path: "/sites/default", content: .directory),
            TopologyVirtualFileEntry(path: "/sites/default/index.html", content: .text("default host")),
            TopologyVirtualFileEntry(path: "/sites/exact", content: .directory),
            TopologyVirtualFileEntry(path: "/sites/exact/index.html", content: .text("exact host")),
            TopologyVirtualFileEntry(path: "/sites/port-specific", content: .directory),
            TopologyVirtualFileEntry(path: "/sites/port-specific/index.html", content: .text("port-specific host")),
            TopologyVirtualFileEntry(path: "/www", content: .directory),
            TopologyVirtualFileEntry(path: "/www/index.html", content: .text("legacy root")),
        ])
        var state = TopologyEditorState()
        state.virtualFileSystemsByNodeID[serverNodeID] = fileSystem
        state.runtimeWebServerConfigurationsByNodeID[serverNodeID] = TopologyRuntimeWebServerConfiguration(
            port: 80, documentRoot: "/www", virtualHostConfiguration: virtualHosts
        )
        return WebVirtualHostRuntimeFixture(
            state: state, clientNodeID: clientNodeID, serverNodeID: serverNodeID
        )
    }

    private func performWebRuntimeRequest(
        state: inout TopologyEditorState,
        clientNodeID: UUID,
        serverNodeID: UUID,
        hostHeader: String?,
        target: String
    ) throws -> WebRuntimeResponse {
        _ = clientNodeID
        let configuration = try XCTUnwrap(
            state.runtimeWebServerConfigurationsByNodeID[serverNodeID]
        )
        let fileSystem = state.virtualFileSystemsByNodeID[serverNodeID] ?? .defaultForDevice()
        let request = TopologyRuntimeHTTPParsedRequest(
            method: "GET", target: target, path: target, host: hostHeader, body: Data()
        )
        let response = TopologyRuntimeHTTPResponse.serve(
            request: request, fileSystem: fileSystem, configuration: configuration
        )
        return WebRuntimeResponse(
            statusCode: response.statusCode,
            body: String(decoding: response.body, as: UTF8.self),
            detail: response.detail
        )
    }

    private func addNode(kind: TopologyNodeKind, at position: CGPoint, to state: inout TopologyEditorState) -> UUID {
        addNode(kind: kind, at: position, nodeID: UUID(), to: &state)
    }

    @discardableResult
    private func addNode(
        kind: TopologyNodeKind,
        at position: CGPoint,
        nodeID: UUID,
        to state: inout TopologyEditorState
    ) -> UUID {
        TopologyEditorReducer.reduce(state: &state, action: .placeNode(kind: kind, at: position, nodeID: nodeID))
        return nodeID
    }

    private func connect(_ sourceNodeID: UUID, _ targetNodeID: UUID, state: inout TopologyEditorState) {
        TopologyEditorReducer.reduce(state: &state, action: .startConnection(nodeID: sourceNodeID, portID: nil))
        TopologyEditorReducer.reduce(state: &state, action: .completeConnection(nodeID: targetNodeID, portID: nil))
        XCTAssertNil(state.lastValidationError)
    }

    private func saveRuntimeIP(
        nodeID: UUID,
        ipAddress: String,
        subnetMask: String,
        state: inout TopologyEditorState
    ) {
        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeDeviceIP(nodeID: nodeID, ipAddress: ipAddress, subnetMask: subnetMask)
        )
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceIPSaved)
    }

    private func startLocalDNSServer(
        nodeID: UUID,
        state: inout TopologyEditorState
    ) {
        let configuration = tryUnwrap(state.runtimeDeviceConfigurations[nodeID])
        state.runtimeDeviceConfigurations[nodeID] = TopologyRuntimeDeviceConfiguration(
            ipAddress: configuration.ipAddress,
            subnetMask: configuration.subnetMask,
            defaultGateway: configuration.defaultGateway,
            dnsServer: configuration.ipAddress
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .installRuntimeProgram(nodeID: nodeID, program: .dnsServer)
        )
        if state.simulationPhase != .running {
            TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        }
        TopologyEditorReducer.reduce(
            state: &state,
            action: .launchRuntimeProgram(nodeID: nodeID, program: .dnsServer)
        )
        TopologyEditorReducer.reduce(state: &state, action: .runtimeDNSStart(nodeID: nodeID))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsServerStarted)
        XCTAssertNotNil(state.runtimeDNSServerSocketIDByNodeID[nodeID])
        XCTAssertNil(state.lastRuntimeFault)
    }

    private func saveRuntimeConfiguration(
        nodeID: UUID,
        ipAddress: String,
        subnetMask: String,
        defaultGateway: String,
        state: inout TopologyEditorState
    ) {
        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeDeviceConfiguration(
                nodeID: nodeID,
                ipAddress: ipAddress,
                subnetMask: subnetMask,
                defaultGateway: defaultGateway
            )
        )
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceIPSaved)
    }

    private typealias TwoRouterTopology = (
        sourceNodeID: UUID,
        firstRouterNodeID: UUID,
        secondRouterNodeID: UUID,
        targetNodeID: UUID
    )

    private func makeTwoRouterTopology(state: inout TopologyEditorState) -> TwoRouterTopology {
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let firstRouterNodeID = addNode(kind: .router, at: CGPoint(x: 140, y: 20), to: &state)
        let secondRouterNodeID = addNode(kind: .router, at: CGPoint(x: 260, y: 20), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 380, y: 20), to: &state)

        appendRouterPort(nodeID: firstRouterNodeID, label: "rt2", state: &state)
        appendRouterPort(nodeID: secondRouterNodeID, label: "rt2", state: &state)
        connect(sourceNodeID, firstRouterNodeID, state: &state)
        connect(firstRouterNodeID, secondRouterNodeID, state: &state)
        connect(secondRouterNodeID, targetNodeID, state: &state)

        let firstRouter = tryUnwrap(state.graph.node(withID: firstRouterNodeID))
        let secondRouter = tryUnwrap(state.graph.node(withID: secondRouterNodeID))
        configureInterface(nodeID: firstRouterNodeID, portID: firstRouter.ports[0].id, ipAddress: "10.0.0.1", state: &state)
        configureInterface(nodeID: firstRouterNodeID, portID: firstRouter.ports[1].id, ipAddress: "10.0.1.1", state: &state)
        configureInterface(nodeID: secondRouterNodeID, portID: secondRouter.ports[0].id, ipAddress: "10.0.1.2", state: &state)
        configureInterface(nodeID: secondRouterNodeID, portID: secondRouter.ports[1].id, ipAddress: "10.0.2.1", state: &state)
        saveRuntimeConfiguration(
            nodeID: sourceNodeID,
            ipAddress: "10.0.0.10",
            subnetMask: "255.255.255.0",
            defaultGateway: "10.0.0.1",
            state: &state
        )
        saveRuntimeConfiguration(
            nodeID: targetNodeID,
            ipAddress: "10.0.2.10",
            subnetMask: "255.255.255.0",
            defaultGateway: "10.0.2.1",
            state: &state
        )
        return (sourceNodeID, firstRouterNodeID, secondRouterNodeID, targetNodeID)
    }

    private func appendRouterPort(nodeID: UUID, label: String, state: inout TopologyEditorState) {
        let index = tryUnwrap(state.graph.nodeIndex(withID: nodeID))
        state.graph.nodes[index].ports.append(TopologyPortMetadata(label: label))
    }

    private func configureInterface(
        nodeID: UUID,
        portID: UUID,
        ipAddress: String,
        state: inout TopologyEditorState
    ) {
        state.runtimeInterfaceConfigurations[
            TopologyRuntimeInterfaceKey(nodeID: nodeID, portID: portID)
        ] = TopologyRuntimeInterfaceConfiguration(
            ipAddress: ipAddress,
            subnetMask: "255.255.255.0"
        )
    }

    private func manualRoute(destination: String, gateway: String, interface: String) -> TopologyRuntimeManualRoute {
        TopologyRuntimeManualRoute(
            destinationNetwork: destination,
            subnetMask: "255.255.255.0",
            gateway: gateway,
            interfaceIPAddress: interface
        )
    }

    private func makeDefaultGatewayTopology(
        state: inout TopologyEditorState
    ) -> (sourceNodeID: UUID, gatewayNodeID: UUID, targetNodeID: UUID) {
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let gatewayNodeID = addNode(kind: .gateway, at: CGPoint(x: 160, y: 20), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 300, y: 20), to: &state)
        connect(sourceNodeID, gatewayNodeID, state: &state)
        connect(targetNodeID, gatewayNodeID, state: &state)
        return (sourceNodeID, gatewayNodeID, targetNodeID)
    }

    func testDocumentationModeCreateMoveEditDeleteIsDeterministic() {
        var state = TopologyEditorState()
        let textID = uuid("71717171-7171-7171-7171-717171717171")
        let rectangleID = uuid("72727272-7272-7272-7272-727272727272")

        TopologyEditorReducer.reduce(state: &state, action: .setWorkspaceMode(mode: .documentation))
        TopologyEditorReducer.reduce(state: &state, action: .setDocumentationTool(tool: .text))
        TopologyEditorReducer.reduce(
            state: &state,
            action: .createDocumentationItem(kind: .text, at: CGPoint(x: 100, y: 80), itemID: textID)
        )
        TopologyEditorReducer.reduce(state: &state, action: .setDocumentationTool(tool: .rectangle))
        TopologyEditorReducer.reduce(
            state: &state,
            action: .createDocumentationItem(kind: .rectangle, at: CGPoint(x: 60, y: 40), itemID: rectangleID)
        )

        XCTAssertEqual(state.documentationItems.inDeterministicRenderOrder.map(\.id), [rectangleID, textID])
        XCTAssertEqual(state.persistenceRevision, 2)

        TopologyEditorReducer.reduce(state: &state, action: .selectDocumentationItem(itemID: textID))
        TopologyEditorReducer.reduce(
            state: &state,
            action: .moveSelectedDocumentationItem(delta: CGSize(width: 20, height: -10))
        )
        var text = tryUnwrap(state.documentationItems.first { $0.id == textID })
        text.text = "Updated annotation"
        text.fontSize = 20
        TopologyEditorReducer.reduce(state: &state, action: .updateDocumentationItem(item: text))

        XCTAssertEqual(state.documentationItems.first { $0.id == textID }?.frame.origin, CGPoint(x: 120, y: 70))
        XCTAssertEqual(state.documentationItems.first { $0.id == textID }?.text, "Updated annotation")
        XCTAssertEqual(state.persistenceRevision, 4)

        TopologyEditorReducer.reduce(state: &state, action: .selectDocumentationItem(itemID: rectangleID))
        TopologyEditorReducer.reduce(state: &state, action: .deleteSelectedDocumentationItem)
        XCTAssertEqual(state.documentationItems.map(\.id), [textID])
        XCTAssertEqual(state.persistenceRevision, 5)

        TopologyEditorReducer.reduce(state: &state, action: .setWorkspaceMode(mode: .design))
        XCTAssertEqual(state.workspaceMode, .design)
        XCTAssertEqual(state.documentationTool, .select)
        XCTAssertNil(state.selectedDocumentationItemID)
    }

    func testTerminalFilesystemCommandsUsePerDeviceWorkingDirectoryAndSharedVFS() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        activateRuntimeProgram(.commandPrompt, nodeID: nodeID, state: &state)

        let execute: (String) -> Void = { command in
            TopologyEditorReducer.reduce(
                state: &state,
                action: .executePing(nodeID: nodeID, command: command)
            )
        }

        execute("mkdir /home/cli")
        execute("cd /HOME/CLI")
        execute("touch note.txt")
        var fileSystem = tryUnwrap(state.virtualFileSystemsByNodeID[nodeID])
        try? fileSystem.writeTextFile(at: "/home/cli/note.txt", text: "hello from shared VFS")
        state.virtualFileSystemsByNodeID[nodeID] = fileSystem

        execute("cat NOTE.TXT")
        execute("cp note.txt copy.txt")
        execute("mv copy.txt moved.txt")
        execute("ls")
        execute("del MOVED.TXT")
        execute("pwd")

        XCTAssertEqual(state.runtimeWorkingDirectoryByNodeID[nodeID], "/home/cli")
        XCTAssertEqual(try? state.virtualFileSystemsByNodeID[nodeID]?.textFile(at: "/HOME/CLI/NOTE.TXT"), "hello from shared VFS")
        XCTAssertFalse(state.virtualFileSystemsByNodeID[nodeID]?.contains("/home/cli/moved.txt") ?? true)
        XCTAssertTrue(state.runtimeConsoleEntriesByNodeID[nodeID]?.contains("hello from shared VFS") ?? false)
        XCTAssertTrue(state.runtimeConsoleEntriesByNodeID[nodeID]?.contains(where: { $0.contains("note.txt") }) ?? false)
        XCTAssertEqual(state.runtimeConsoleEntriesByNodeID[nodeID]?.last, "/home/cli")
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeFilesystemCommandSucceeded)
    }

    func testTerminalFilesystemCommandsRejectMalformedAndEscapingPathsWithoutMutation() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        activateRuntimeProgram(.commandPrompt, nodeID: nodeID, state: &state)
        let before = state.virtualFileSystemsByNodeID[nodeID]

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: nodeID, command: "mkdir"))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeFilesystemCommandRejectedMalformed)
        XCTAssertEqual(state.lastRuntimeFault?.code, "malformedFilesystemCommand")

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: nodeID, command: "touch /../../escape.txt"))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeFilesystemCommandRejectedPath)
        XCTAssertEqual(state.lastRuntimeFault?.code, "filesystemCommandFailed")
        XCTAssertEqual(state.virtualFileSystemsByNodeID[nodeID], before)
        XCTAssertEqual(state.runtimeWorkingDirectoryByNodeID[nodeID], "/")
    }

    func testTerminalFilesystemCommandsRequireRunningPCClassCommandPromptAndExistingVFS() {
        var state = TopologyEditorState()
        let pcID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let routerID = addNode(kind: .router, at: CGPoint(x: 120, y: 30), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: pcID, command: "pwd"))
        XCTAssertEqual(state.lastRuntimeFault?.code, "runtimeDesktopAppSimulationNotRunning")

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: routerID, command: "pwd"))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeFilesystemCommandRejectedContext)
        XCTAssertEqual(state.lastRuntimeFault?.code, "filesystemCommandUnsupportedDevice")

        activateRuntimeProgram(.commandPrompt, nodeID: pcID, state: &state)
        state.virtualFileSystemsByNodeID.removeValue(forKey: pcID)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: pcID, command: "pwd"))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeFilesystemCommandRejectedContext)
        XCTAssertEqual(state.lastRuntimeFault?.code, "filesystemCommandMissingDeviceFilesystem")
        XCTAssertNil(state.virtualFileSystemsByNodeID[pcID], "terminal must not synthesize a default VFS")
    }

    func testTerminalFilesystemCommandsIsolateDevicesAndShareDesktopAppState() {
        var state = TopologyEditorState()
        let firstID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let secondID = addNode(kind: .notebook, at: CGPoint(x: 180, y: 30), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        activateRuntimeProgram(.fileExplorer, nodeID: firstID, state: &state)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeFileSystemCreateTextFile(nodeID: firstID, path: "/home/DesktopShared.txt", text: "desktop and terminal")
        )
        activateRuntimeProgram(.commandPrompt, nodeID: firstID, state: &state)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: firstID, command: "cat /HOME/desktopshared.TXT"))
        XCTAssertTrue(state.runtimeConsoleEntriesByNodeID[firstID]?.contains("desktop and terminal") ?? false)

        activateRuntimeProgram(.commandPrompt, nodeID: secondID, state: &state)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: secondID, command: "cat /home/DesktopShared.txt"))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeFilesystemCommandRejectedPath)
        XCTAssertFalse(state.virtualFileSystemsByNodeID[secondID]?.contains("/home/DesktopShared.txt") ?? true)
        XCTAssertTrue(state.virtualFileSystemsByNodeID[firstID]?.contains("/home/DesktopShared.txt") ?? false)
    }

    func testTerminalCopyMoveOverwriteTextBinaryAndImageAndCatEncodesContent() throws {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        activateRuntimeProgram(.commandPrompt, nodeID: nodeID, state: &state)
        var fileSystem = tryUnwrap(state.virtualFileSystemsByNodeID[nodeID])
        try fileSystem.writeTextFile(at: "/home/source.txt", text: "replacement")
        try fileSystem.writeTextFile(at: "/home/destination.txt", text: "old")
        try fileSystem.writeBinaryFile(at: "/home/source.bin", data: Data([0x00, 0x01, 0x02]), mediaType: "application/octet-stream")
        try fileSystem.writeBinaryFile(at: "/home/destination.bin", data: Data([0xff]), mediaType: "application/octet-stream")
        try fileSystem.writeImageFile(at: "/home/source.png", data: Data([0x89, 0x50, 0x4e, 0x47]), mediaType: "image/png")
        try fileSystem.writeImageFile(at: "/home/destination.png", data: Data([0x00]), mediaType: "image/png")
        try fileSystem.writeTextFile(at: "/home/long.txt", text: String(repeating: "line payload\n", count: 500))
        state.virtualFileSystemsByNodeID[nodeID] = fileSystem

        for command in [
            "cp /home/source.txt /home/destination.txt",
            "cp /home/source.bin /home/destination.bin",
            "mv /home/source.png /home/destination.png",
            "cat /home/destination.bin",
            "cat /home/destination.png",
            "cat /home/long.txt",
        ] {
            TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: nodeID, command: command))
        }

        fileSystem = tryUnwrap(state.virtualFileSystemsByNodeID[nodeID])
        XCTAssertEqual(try fileSystem.textFile(at: "/home/destination.txt"), "replacement")
        XCTAssertEqual(try fileSystem.entry(at: "/home/destination.bin").content, .binary(Data([0x00, 0x01, 0x02]), mediaType: "application/octet-stream"))
        XCTAssertEqual(try fileSystem.entry(at: "/home/destination.png").content, .image(Data([0x89, 0x50, 0x4e, 0x47]), mediaType: "image/png"))
        XCTAssertFalse(fileSystem.contains("/home/source.png"), "atomic mv must remove source only after final-state validation")
        let output = state.runtimeConsoleEntriesByNodeID[nodeID] ?? []
        XCTAssertTrue(output.contains(where: { $0.contains("base64;media-type=image/png:iVBORw==") }))
        XCTAssertTrue(output.contains(where: { $0.contains("[cat output truncated: maxBytes=") }))
    }

    func testVirtualFileSystemOverwriteUsesFinalStateQuotaAndMoveIsAtomic() throws {
        var fileSystem = TopologyVirtualFileSystem()
        let maximumSized = Data(repeating: 0x41, count: TopologyVirtualFileSystem.maximumFileBytes)
        try fileSystem.writeBinaryFile(at: "/source.bin", data: maximumSized, mediaType: "application/octet-stream")
        try fileSystem.writeBinaryFile(at: "/destination.bin", data: maximumSized, mediaType: "application/octet-stream")
        try fileSystem.writeBinaryFile(at: "/third.bin", data: maximumSized, mediaType: "application/octet-stream")
        try fileSystem.writeBinaryFile(at: "/fourth.bin", data: maximumSized, mediaType: "application/octet-stream")

        XCTAssertNoThrow(try fileSystem.copyItem(at: "/SOURCE.BIN", to: "/DESTINATION.BIN", overwrite: true))
        let beforeRejectedCopy = fileSystem
        XCTAssertThrowsError(try fileSystem.copyItem(at: "/source.bin", to: "/new.bin", overwrite: true))
        XCTAssertEqual(fileSystem, beforeRejectedCopy, "quota rejection must leave the VFS unchanged")

        XCTAssertNoThrow(try fileSystem.moveItem(at: "/SOURCE.BIN", to: "/DESTINATION.BIN", overwrite: true))
        XCTAssertFalse(fileSystem.contains("/source.bin"))
        XCTAssertTrue(fileSystem.contains("/destination.bin"))
    }

    func testProtocolApplicationTCPResponseRetriesAfterDeterministicAdvance() {
        struct StubRuntime {
            var receiveAttempts = 0
            var advanceCount = 0
        }

        let expected = Data("late response".utf8)
        var runtime = StubRuntime()
        let response = receiveProtocolApplicationTCPResponse(
            runtime: &runtime,
            receive: { runtime in
                runtime.receiveAttempts += 1
                return runtime.receiveAttempts == 2 ? expected : nil
            },
            advanceToTimeout: { runtime in
                runtime.advanceCount += 1
            }
        )

        XCTAssertEqual(response, expected)
        XCTAssertEqual(runtime.receiveAttempts, 2)
        XCTAssertEqual(runtime.advanceCount, 1)
    }

    func testFailedUDPSimpleClientSendDoesNotAdvanceReceiveTimeout() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        saveRuntimeConfiguration(
            nodeID: nodeID,
            ipAddress: "192.0.2.10",
            subnetMask: "255.255.255.0",
            defaultGateway: "",
            state: &state
        )
        activateRuntimeProgram(.simpleClient, nodeID: nodeID, state: &state)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeSimpleClientConnect(
                nodeID: nodeID,
                destinationIPAddress: "198.51.100.20",
                port: "55555",
                protocolKind: .udp
            )
        )
        XCTAssertEqual(state.runtimeSimpleClientByNodeID[nodeID]?.connectionState, .connected)

        let beforeSend = state.networkRuntime.state.currentTimeMilliseconds
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeSimpleClientSend(nodeID: nodeID, message: "unreachable")
        )

        XCTAssertEqual(state.networkRuntime.state.currentTimeMilliseconds, beforeSend)
        XCTAssertEqual(state.simulationTick, beforeSend)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simpleClientRejectedUnreachable)
        XCTAssertEqual(state.lastRuntimeFault?.code, "unreachable")
    }

    func testPersonalFirewallEditPreservesImportedHiddenFields() {
        let imported = TopologyFirewallConfiguration(
            isActive: false,
            defaultPolicy: .accept,
            dropICMP: true,
            filterSYNSegmentsOnly: false,
            filterUDP: false,
            rules: [TopologyFirewallRule(protocolType: .udp, action: .drop)]
        )

        let edited = updatingPersonalFirewallConfiguration(imported) { configuration in
            configuration.isActive = true
            configuration.dropICMP = false
        }

        XCTAssertTrue(edited.isActive)
        XCTAssertFalse(edited.dropICMP)
        XCTAssertEqual(edited.defaultPolicy, .accept)
        XCTAssertFalse(edited.filterSYNSegmentsOnly)
        XCTAssertEqual(edited.rules, imported.rules)

        var state = TopologyEditorState()
        let importedNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        state.runtimeFirewallConfigurationsByNodeID[importedNodeID] = imported
        TopologyEditorReducer.reduce(
            state: &state,
            action: .installRuntimeProgram(nodeID: importedNodeID, program: .firewall)
        )
        XCTAssertEqual(state.runtimeFirewallConfigurationsByNodeID[importedNodeID], imported)

        let freshNodeID = addNode(kind: .notebook, at: CGPoint(x: 180, y: 20), to: &state)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .installRuntimeProgram(nodeID: freshNodeID, program: .firewall)
        )
        XCTAssertEqual(
            state.runtimeFirewallConfigurationsByNodeID[freshNodeID],
            TopologyFirewallConfiguration.javaPersonalDefaults
        )
    }

    func testEmailConfigurationAndSendFailuresUseDistinctEventCodes() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        activateRuntimeProgram(.emailClient, nodeID: nodeID, state: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeEmailClientConfiguration(
                nodeID: nodeID,
                configuration: TopologyRuntimeEmailClientConfiguration()
            )
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .emailClientConfigurationRejected)
        XCTAssertEqual(state.lastRuntimeEvent?.code.rawValue, "emailClientConfigurationRejected")
        XCTAssertEqual(state.lastRuntimeFault?.code, "emailClientConfigurationRejected")

        let message = TopologyRuntimeEmailMessage(
            from: TopologyRuntimeEmailAddress(mailAddress: "sender@example.test"),
            to: [TopologyRuntimeEmailAddress(mailAddress: "recipient@example.test")],
            subject: "Test",
            body: "Body"
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeEmailClientSend(nodeID: nodeID, message: message)
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .emailClientSendRejected)
        XCTAssertEqual(state.lastRuntimeEvent?.code.rawValue, "emailClientSendRejected")
        XCTAssertEqual(state.lastRuntimeFault?.code, "emailClientSendRejected")
    }

    func testEmailDeletionReducerActionRemovesInboxAndSentMessagesAndEmitsEvents() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        activateRuntimeProgram(.emailClient, nodeID: nodeID, state: &state)

        let inboxMessage = TopologyRuntimeEmailMessage(
            id: 101,
            from: TopologyRuntimeEmailAddress(mailAddress: "bob@example.test"),
            to: [TopologyRuntimeEmailAddress(mailAddress: "alice@example.test")],
            subject: "Incoming",
            body: "Inbox body"
        )
        let sentMessage = TopologyRuntimeEmailMessage(
            id: 102,
            from: TopologyRuntimeEmailAddress(mailAddress: "alice@example.test"),
            to: [TopologyRuntimeEmailAddress(mailAddress: "bob@example.test")],
            subject: "Outgoing",
            body: "Sent body",
            isNew: false,
            isSent: true
        )
        let configuration = TopologyRuntimeEmailClientConfiguration(
            pop3Host: "10.0.0.20",
            smtpHost: "10.0.0.20",
            username: "alice",
            password: "secret",
            name: "Alice Example",
            email: "alice@example.test",
            inbox: [inboxMessage],
            sent: [sentMessage],
            nextMessageID: 103
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeEmailClientConfiguration(nodeID: nodeID, configuration: configuration)
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .emailClientConfigured)
        XCTAssertNil(state.lastRuntimeFault)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeEmailClientDeleteMessages(
                nodeID: nodeID,
                folder: .inbox,
                messageIDs: [inboxMessage.id]
            )
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .emailClientMessagesDeleted)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("folder=inbox") == true)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("messages=1") == true)
        XCTAssertEqual(state.runtimeEmailClientConfigurationsByNodeID[nodeID]?.inbox, [])
        XCTAssertEqual(state.runtimeEmailClientConfigurationsByNodeID[nodeID]?.sent, [sentMessage])
        XCTAssertNil(state.lastRuntimeFault)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeEmailClientDeleteMessages(
                nodeID: nodeID,
                folder: .sent,
                messageIDs: [sentMessage.id]
            )
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .emailClientMessagesDeleted)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("folder=sent") == true)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("messages=1") == true)
        XCTAssertEqual(state.runtimeEmailClientConfigurationsByNodeID[nodeID]?.inbox, [])
        XCTAssertEqual(state.runtimeEmailClientConfigurationsByNodeID[nodeID]?.sent, [])
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testRemoveRouterInterfaceDistinguishesMissingActionFields() {
        var state = TopologyEditorState()
        let nodeID = UUID()
        let portID = UUID()

        TopologyEditorReducer.reduce(
            state: &state,
            action: .removeRouterInterface(nodeID: nil, portID: portID, confirmed: true)
        )
        XCTAssertEqual(state.lastValidationError, .missingNodeIdentifier)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .removeRouterInterface(nodeID: nodeID, portID: nil, confirmed: true)
        )
        XCTAssertEqual(state.lastValidationError, .invalidPortIdentifier)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .removeRouterInterface(nodeID: nodeID, portID: portID, confirmed: nil)
        )
        XCTAssertEqual(state.lastValidationError, .malformedActionPayload)
    }

    func testNotebookRuntimeTitleKeepsNotebookIdentity() {
        XCTAssertEqual(topologyRuntimeDeviceTitle(for: .pc), FiliusLocalization.t("runtime.kind.pc"))
        XCTAssertEqual(topologyRuntimeDeviceTitle(for: .notebook), FiliusLocalization.t("model.notebook"))
        XCTAssertNotEqual(topologyRuntimeDeviceTitle(for: .notebook), topologyRuntimeDeviceTitle(for: .pc))
    }


    func testWebAdministrationPolicyIsDefaultDeniedAndRouterGatewayOnly() throws {
        var state = TopologyEditorState()
        let routerID = addNode(kind: .router, at: CGPoint(x: 20, y: 20), to: &state)
        let gatewayID = addNode(kind: .gateway, at: CGPoint(x: 180, y: 20), to: &state)
        let pcID = addNode(kind: .pc, at: CGPoint(x: 340, y: 20), to: &state)
        let network = try TopologyRuntimeWebAdministrationIPv4Network(
            networkAddress: "192.168.10.77",
            subnetMask: "255.255.255.0"
        )
        let policy = TopologyRuntimeWebAdministrationAccessPolicy(
            isEnabled: true,
            allowedSourceNetworks: [network]
        )

        XCTAssertNil(state.runtimeWebAdministrationConfigurationsByNodeID[routerID])
        XCTAssertNil(state.runtimeWebAdministrationConfigurationsByNodeID[gatewayID])

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeWebAdministrationPolicy(nodeID: routerID, policy: policy)
        )
        XCTAssertEqual(state.runtimeWebAdministrationConfigurationsByNodeID[routerID]?.accessPolicy, policy)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeWebAdministrationConfigurationSaved)
        XCTAssertNil(state.lastRuntimeFault)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeWebAdministrationPolicy(nodeID: pcID, policy: policy)
        )
        XCTAssertNil(state.runtimeWebAdministrationConfigurationsByNodeID[pcID])
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeWebAdministrationConfigurationRejected)
        XCTAssertEqual(state.lastRuntimeFault?.code, "webAdministrationUnsupportedForNodeKind")
    }

    func testWebAdministrationConfigurationValidatesPortPolicyAndRunningListenerChanges() throws {
        var state = TopologyEditorState()
        let routerID = addNode(kind: .router, at: CGPoint(x: 20, y: 20), to: &state)
        let allowedNetwork = try TopologyRuntimeWebAdministrationIPv4Network(
            networkAddress: "192.168.50.0",
            subnetMask: "255.255.255.0"
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeWebAdministrationConfiguration(
                nodeID: routerID,
                configuration: TopologyRuntimeWebAdministrationConfiguration(
                    port: 0,
                    accessPolicy: TopologyRuntimeWebAdministrationAccessPolicy()
                )
            )
        )
        XCTAssertNil(state.runtimeWebAdministrationConfigurationsByNodeID[routerID])
        XCTAssertEqual(state.lastRuntimeFault?.code, "invalidWebAdministrationPort")

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeWebAdministrationConfiguration(
                nodeID: routerID,
                configuration: TopologyRuntimeWebAdministrationConfiguration(
                    port: 8081,
                    accessPolicy: TopologyRuntimeWebAdministrationAccessPolicy(
                        isEnabled: true,
                        allowedSourceNetworks: []
                    )
                )
            )
        )
        XCTAssertNil(state.runtimeWebAdministrationConfigurationsByNodeID[routerID])
        XCTAssertEqual(state.lastRuntimeFault?.code, "webAdministrationPolicyNotReady")

        let configuration = TopologyRuntimeWebAdministrationConfiguration(
            port: 8081,
            accessPolicy: TopologyRuntimeWebAdministrationAccessPolicy(
                isEnabled: true,
                allowedSourceNetworks: [allowedNetwork]
            )
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeWebAdministrationConfiguration(
                nodeID: routerID,
                configuration: configuration
            )
        )
        XCTAssertEqual(state.runtimeWebAdministrationConfigurationsByNodeID[routerID], configuration)
        XCTAssertNil(state.lastRuntimeFault)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationStart(nodeID: routerID, port: nil)
        )
        XCTAssertEqual(state.runtimeWebAdministrationByNodeID[routerID]?.port, 8081)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeWebAdministrationConfiguration(
                nodeID: routerID,
                configuration: TopologyRuntimeWebAdministrationConfiguration(
                    port: 8082,
                    accessPolicy: configuration.accessPolicy
                )
            )
        )
        XCTAssertEqual(state.runtimeWebAdministrationConfigurationsByNodeID[routerID], configuration)
        XCTAssertEqual(state.lastRuntimeFault?.code, "webAdministrationRestartRequired")
    }

    func testWebAdministrationStartRejectsDefaultDeniedPolicy() {
        var state = TopologyEditorState()
        let routerID = addNode(kind: .router, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationStart(nodeID: routerID, port: "8081")
        )

        XCTAssertNil(state.runtimeWebAdministrationByNodeID[routerID])
        XCTAssertNil(state.runtimeWebAdministrationSocketIDByNodeID[routerID])
        XCTAssertEqual(state.lastRuntimeFault?.code, "webAdministrationPolicyNotReady")
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeWebAdministrationConfigurationRejected)
    }

    func testRouterGatewayWebAdministrationListenerLifecycleValidatesPortAndStopsCleanly() throws {
        var state = TopologyEditorState()
        let routerID = addNode(kind: .router, at: CGPoint(x: 20, y: 20), to: &state)

        try enableWebAdministration(nodeID: routerID, state: &state)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationStart(nodeID: routerID, port: "8081")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeWebAdministrationConfigurationSaved)
        XCTAssertEqual(state.runtimeWebAdministrationByNodeID[routerID]?.port, 8081)
        XCTAssertNil(state.runtimeWebServerByNodeID[routerID])
        XCTAssertNil(state.runtimeWebServerSocketIDByNodeID[routerID])
        XCTAssertNil(state.runtimeWebServerConfigurationsByNodeID[routerID])
        let listenerID = try XCTUnwrap(state.runtimeWebAdministrationSocketIDByNodeID[routerID])
        XCTAssertEqual(state.networkRuntime.state.socketsByID[listenerID]?.tcpState, .listen)
        XCTAssertEqual(state.runtimeWebAdministrationConfigurationsByNodeID[routerID]?.port, 8081)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationStart(nodeID: routerID, port: "not-a-port")
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeWebAdministrationConfigurationRejected)
        XCTAssertEqual(state.lastRuntimeFault?.code, "invalidWebAdministrationPort")
        XCTAssertEqual(state.runtimeWebAdministrationByNodeID[routerID]?.port, 8081)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationStop(nodeID: routerID)
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeWebAdministrationConfigurationSaved)
        XCTAssertNil(state.runtimeWebAdministrationByNodeID[routerID])
        XCTAssertNil(state.runtimeWebAdministrationSocketIDByNodeID[routerID])
        XCTAssertEqual(state.networkRuntime.state.socketsByID[listenerID]?.tcpState, .closed)
    }

    func testWebServerConfigurationActionPersistsVirtualHostConfiguration() throws {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let host = try TopologyRuntimeWebVirtualHost(
            id: "docs",
            hostname: "docs.example.test",
            documentRoot: "/www/docs"
        )
        let virtualHosts = try TopologyRuntimeWebVirtualHostConfiguration(
            hosts: [host],
            defaultHostID: host.id
        )
        let configuration = TopologyRuntimeWebServerConfiguration(
            port: 8080,
            documentRoot: "/www",
            virtualHostConfiguration: virtualHosts
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeWebServerConfiguration(nodeID: nodeID, configuration: configuration)
        )

        XCTAssertEqual(state.runtimeWebServerConfigurationsByNodeID[nodeID], configuration)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .webServerConfigurationSaved)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testWebServerConfigurationRejectsInvalidDocumentRootTransactionally() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let original = TopologyRuntimeWebServerConfiguration()
        state.runtimeWebServerConfigurationsByNodeID[nodeID] = original
        let invalid = TopologyRuntimeWebServerConfiguration(
            port: 8080,
            documentRoot: "relative/www"
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeWebServerConfiguration(nodeID: nodeID, configuration: invalid)
        )

        XCTAssertEqual(state.runtimeWebServerConfigurationsByNodeID[nodeID], original)
        XCTAssertEqual(state.lastRuntimeFault?.code, "invalidWebServerConfiguration")
        XCTAssertEqual(state.lastRuntimeEvent?.code, .webServerRejectedInvalidConfiguration)
    }

    func testWebServerConfigurationRejectsListenerPortChangeWhileRunning() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let running = TopologyRuntimeServiceProcessState(port: 8080)
        let original = TopologyRuntimeWebServerConfiguration(port: 8080)
        state.runtimeWebServerByNodeID[nodeID] = running
        state.runtimeWebServerConfigurationsByNodeID[nodeID] = original

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeWebServerConfiguration(
                nodeID: nodeID,
                configuration: TopologyRuntimeWebServerConfiguration(port: 8081)
            )
        )

        XCTAssertEqual(state.runtimeWebServerConfigurationsByNodeID[nodeID], original)
        XCTAssertEqual(state.runtimeWebServerByNodeID[nodeID], running)
        XCTAssertEqual(state.lastRuntimeFault?.code, "webServerPortChangeRequiresStop")
        XCTAssertEqual(state.lastRuntimeEvent?.code, .webServerRejectedInvalidConfiguration)
    }

    func testWebAdministrationRequestUsesPolicyAndSecretFreeSnapshot() throws {
        var state = TopologyEditorState()
        let gatewayID = addNode(kind: .gateway, at: CGPoint(x: 20, y: 20), to: &state)
        let sourceNetwork = try TopologyRuntimeWebAdministrationIPv4Network(
            networkAddress: "10.20.0.0",
            subnetMask: "255.255.255.0"
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeWebAdministrationPolicy(
                nodeID: gatewayID,
                policy: TopologyRuntimeWebAdministrationAccessPolicy(
                    isEnabled: true,
                    allowedSourceNetworks: [sourceNetwork]
                )
            )
        )
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)

        let allowedRequest = TopologyRuntimeWebAdministrationRequest(
            method: "GET",
            target: "/admin",
            sourceIPAddress: "10.20.0.42"
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(nodeID: gatewayID, request: allowedRequest)
        )
        let allowedResponse = try XCTUnwrap(state.runtimeWebAdministrationResponsesByNodeID[gatewayID])
        XCTAssertEqual(allowedResponse.statusCode, 200)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeWebAdministrationRequestServed)
        XCTAssertTrue(allowedResponse.body.contains("Gateway"))
        XCTAssertTrue(allowedResponse.body.contains("Interface"))
        XCTAssertFalse(allowedResponse.body.contains("password"))
        XCTAssertFalse(allowedResponse.body.contains("secret"))

        let deniedRequest = TopologyRuntimeWebAdministrationRequest(
            method: "GET",
            target: "/admin",
            sourceIPAddress: "10.21.0.42"
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(nodeID: gatewayID, request: deniedRequest)
        )
        let deniedResponse = try XCTUnwrap(state.runtimeWebAdministrationResponsesByNodeID[gatewayID])
        XCTAssertEqual(deniedResponse.statusCode, 403)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeWebAdministrationRequestRejected)
        XCTAssertEqual(state.lastRuntimeFault?.code, "webAdministrationHTTP403")
        XCTAssertFalse(deniedResponse.body.contains("Gateway"))
    }

    func testWebAdministrationListenerStateIsIndependentFromOrdinaryWebServerState() throws {
        var state = TopologyEditorState()
        let gatewayID = addNode(kind: .gateway, at: CGPoint(x: 20, y: 20), to: &state)
        state.runtimeWebServerConfigurationsByNodeID[gatewayID] = TopologyRuntimeWebServerConfiguration(port: 8080)
        state.runtimeWebServerByNodeID[gatewayID] = TopologyRuntimeServiceProcessState(port: 8080)
        try enableWebAdministration(nodeID: gatewayID, state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationStart(nodeID: gatewayID, port: "8081")
        )

        XCTAssertEqual(state.runtimeWebServerConfigurationsByNodeID[gatewayID]?.port, 8080)
        XCTAssertEqual(state.runtimeWebServerByNodeID[gatewayID]?.port, 8080)
        XCTAssertEqual(state.runtimeWebAdministrationConfigurationsByNodeID[gatewayID]?.port, 8081)
        XCTAssertEqual(state.runtimeWebAdministrationByNodeID[gatewayID]?.port, 8081)
        XCTAssertNotEqual(
            state.runtimeWebServerSocketIDByNodeID[gatewayID],
            state.runtimeWebAdministrationSocketIDByNodeID[gatewayID]
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationStop(nodeID: gatewayID)
        )
        XCTAssertEqual(state.runtimeWebServerByNodeID[gatewayID]?.port, 8080)
        XCTAssertNil(state.runtimeWebAdministrationByNodeID[gatewayID])
    }

    func testDedicatedWebAdministrationListenerServesBrowserAndOwnsOnlyAdminNamespace() throws {
        var state = TopologyEditorState()
        let clientID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let routerID = addNode(kind: .router, at: CGPoint(x: 180, y: 20), to: &state)
        connect(clientID, routerID, state: &state)
        saveRuntimeConfiguration(
            nodeID: clientID,
            ipAddress: "192.168.1.10",
            subnetMask: "255.255.255.0",
            defaultGateway: "",
            state: &state
        )
        let routerPortID = try XCTUnwrap(state.graph.node(withID: routerID)?.ports.first?.id)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeInterfaceConfiguration(
                nodeID: routerID,
                portID: routerPortID,
                ipAddress: "192.168.1.1",
                subnetMask: "255.255.255.0"
            )
        )
        try enableWebAdministration(nodeID: routerID, state: &state)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationStart(nodeID: routerID, port: "8081")
        )

        let adminResult = state.navigateWebBrowser(
            nodeID: clientID,
            rawAddress: "http://192.168.1.1:8081/admin"
        )
        guard case let .success(adminPage) = adminResult else {
            return XCTFail("Dedicated administration listener did not serve /admin: \(adminResult)")
        }
        XCTAssertEqual(adminPage.statusCode, 200)
        XCTAssertTrue(adminPage.body.lowercased().contains("router"))
        XCTAssertEqual(state.runtimeWebServerRequestLogsByNodeID[routerID]?.last?.path, "/admin")

        let ordinaryPathResult = state.navigateWebBrowser(
            nodeID: clientID,
            rawAddress: "http://192.168.1.1:8081/"
        )
        guard case let .success(ordinaryPathPage) = ordinaryPathResult else {
            return XCTFail("Dedicated administration listener did not return an HTTP response: \(ordinaryPathResult)")
        }
        XCTAssertEqual(ordinaryPathPage.statusCode, 404)
        XCTAssertEqual(state.runtimeWebServerRequestLogsByNodeID[routerID]?.last?.detail, "administrationNamespaceOnly")
    }

    func testDedicatedWebAdministrationBrowserAppliesPOSTAndRestoresCachedHistory() throws {
        var state = TopologyEditorState()
        let clientID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let routerID = addNode(kind: .router, at: CGPoint(x: 180, y: 20), to: &state)
        connect(clientID, routerID, state: &state)
        saveRuntimeConfiguration(
            nodeID: clientID,
            ipAddress: "192.168.1.10",
            subnetMask: "255.255.255.0",
            defaultGateway: "",
            state: &state
        )
        let routerPortID = try XCTUnwrap(state.graph.node(withID: routerID)?.ports.first?.id)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeInterfaceConfiguration(
                nodeID: routerID,
                portID: routerPortID,
                ipAddress: "192.168.1.1",
                subnetMask: "255.255.255.0"
            )
        )
        try enableWebAdministration(nodeID: routerID, state: &state)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationStart(nodeID: routerID, port: "8081")
        )

        guard case let .success(statusPage) = state.navigateWebBrowser(
            nodeID: clientID,
            rawAddress: "http://192.168.1.1:8081/admin"
        ) else {
            return XCTFail("Administration status navigation failed")
        }
        XCTAssertTrue(statusPage.body.contains(#"href="/admin/routes""#))

        let request = TopologyRuntimeWebBrowserRequest(
            address: "http://192.168.1.1:8081/admin/actions/routes/add",
            method: "POST",
            body: Data(
                "destinationNetwork=10.30.0.0&subnetMask=255.255.255.0&gatewayIPAddress=192.168.1.254&interfaceIPAddress=192.168.1.1".utf8
            )
        )
        let encodedRequest = try XCTUnwrap(request.encodedNavigationAddress)
        guard case let .success(mutationPage) = state.navigateWebBrowser(
            nodeID: clientID,
            rawAddress: encodedRequest
        ) else {
            return XCTFail("Administration POST navigation failed")
        }
        XCTAssertEqual(mutationPage.statusCode, 200)
        XCTAssertFalse(mutationPage.body.isEmpty)
        XCTAssertEqual(state.runtimeManualRoutesByNodeID[routerID]?.first?.destinationNetwork, "10.30.0.0")
        XCTAssertEqual(mutationPage.history.count, 2)
        XCTAssertTrue(mutationPage.canNavigateBack)

        guard case let .success(restoredStatus) = state.navigateWebBrowser(
            nodeID: clientID,
            rawAddress: mutationPage.history[0].address,
            historyIndex: 0
        ) else {
            return XCTFail("Browser history restoration failed")
        }
        XCTAssertEqual(restoredStatus.body, statusPage.body)
        XCTAssertFalse(restoredStatus.canNavigateBack)
        XCTAssertTrue(restoredStatus.canNavigateForward)
    }

    func testDedicatedWebAdministrationListenerAppliesPOSTMutationFromSimpleClient() throws {
        var state = TopologyEditorState()
        let clientID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let routerID = addNode(kind: .router, at: CGPoint(x: 180, y: 20), to: &state)
        connect(clientID, routerID, state: &state)
        saveRuntimeConfiguration(
            nodeID: clientID,
            ipAddress: "192.168.1.10",
            subnetMask: "255.255.255.0",
            defaultGateway: "",
            state: &state
        )
        let routerPortID = try XCTUnwrap(state.graph.node(withID: routerID)?.ports.first?.id)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeInterfaceConfiguration(
                nodeID: routerID,
                portID: routerPortID,
                ipAddress: "192.168.1.1",
                subnetMask: "255.255.255.0"
            )
        )
        try enableWebAdministration(nodeID: routerID, state: &state)
        activateRuntimeProgram(.simpleClient, nodeID: clientID, state: &state)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationStart(nodeID: routerID, port: "8081")
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeSimpleClientConnect(
                nodeID: clientID,
                destinationIPAddress: "192.168.1.1",
                port: "8081",
                protocolKind: .tcp
            )
        )
        XCTAssertEqual(state.runtimeSimpleClientByNodeID[clientID]?.connectionState, .connected)

        let body = "destinationNetwork=10.30.0.0&subnetMask=255.255.255.0&gatewayIPAddress=192.168.1.254&interfaceIPAddress=192.168.1.1"
        let request = "POST /admin/actions/routes/add HTTP/1.1\r\nHost: 192.168.1.1:8081\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeSimpleClientSend(nodeID: clientID, message: request)
        )

        XCTAssertEqual(
            state.runtimeManualRoutesByNodeID[routerID],
            [
                TopologyRuntimeManualRoute(
                    destinationNetwork: "10.30.0.0",
                    subnetMask: "255.255.255.0",
                    gateway: "192.168.1.254",
                    interfaceIPAddress: "192.168.1.1"
                )
            ]
        )
        XCTAssertEqual(state.runtimeWebServerRequestLogsByNodeID[routerID]?.last?.statusCode, 200)
        XCTAssertTrue(
            state.runtimeSimpleClientByNodeID[clientID]?.logs.contains(where: {
                $0.direction == "inbound" && $0.message.contains("HTTP/1.1 200")
            }) == true
        )
    }

    func testWebAdministrationRouteMutationsAddDeleteAndRollback() throws {
        var state = TopologyEditorState()
        let routerID = addNode(kind: .router, at: CGPoint(x: 20, y: 20), to: &state)
        try enableWebAdministration(nodeID: routerID, state: &state)
        let add = webAdministrationPOST(
            target: "/admin/actions/routes/add",
            fields: [
                "destinationNetwork": "10.30.0.0",
                "subnetMask": "255.255.255.0",
                "gatewayIPAddress": "192.168.1.254",
                "interfaceIPAddress": "192.168.1.1",
            ]
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(nodeID: routerID, request: add)
        )
        XCTAssertEqual(
            state.runtimeManualRoutesByNodeID[routerID],
            [TopologyRuntimeManualRoute(
                destinationNetwork: "10.30.0.0",
                subnetMask: "255.255.255.0",
                gateway: "192.168.1.254",
                interfaceIPAddress: "192.168.1.1"
            )]
        )
        XCTAssertEqual(state.runtimeWebAdministrationResponsesByNodeID[routerID]?.statusCode, 200)

        let committedRoutes = state.runtimeManualRoutesByNodeID[routerID]
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(nodeID: routerID, request: add)
        )
        XCTAssertEqual(state.runtimeManualRoutesByNodeID[routerID], committedRoutes)
        XCTAssertEqual(state.runtimeWebAdministrationResponsesByNodeID[routerID]?.statusCode, 409)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(
                nodeID: routerID,
                request: webAdministrationPOST(
                    target: "/admin/actions/routes/delete",
                    fields: ["id": "manual-0"]
                )
            )
        )
        XCTAssertNil(state.runtimeManualRoutesByNodeID[routerID])
        XCTAssertEqual(state.runtimeWebAdministrationResponsesByNodeID[routerID]?.statusCode, 200)
    }

    func testRunningWebAdministrationRouteAddAndDeleteChangePacketForwardingWithoutRestart() throws {
        var state = TopologyEditorState()
        let topology = makeTwoRouterTopology(state: &state)
        state.runtimeManualRoutesByNodeID[topology.secondRouterNodeID] = [
            manualRoute(destination: "10.0.0.0", gateway: "10.0.1.1", interface: "10.0.1.2")
        ]
        try enableWebAdministration(nodeID: topology.firstRouterNodeID, state: &state)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: topology.sourceNodeID, command: "ping 10.0.2.10")
        )
        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedSubnetMismatch)
        XCTAssertEqual(state.lastPingFault?.code, "forwardingRouteMissing")

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(
                nodeID: topology.firstRouterNodeID,
                request: webAdministrationPOST(
                    target: "/admin/actions/routes/add",
                    fields: [
                        "destinationNetwork": "10.0.2.0",
                        "subnetMask": "255.255.255.0",
                        "gatewayIPAddress": "10.0.1.2",
                        "interfaceIPAddress": "10.0.1.1",
                    ]
                )
            )
        )

        let installedRoute = manualRoute(
            destination: "10.0.2.0",
            gateway: "10.0.1.2",
            interface: "10.0.1.1"
        )
        XCTAssertEqual(state.runtimeWebAdministrationResponsesByNodeID[topology.firstRouterNodeID]?.statusCode, 200)
        XCTAssertEqual(state.runtimeManualRoutesByNodeID[topology.firstRouterNodeID], [installedRoute])
        XCTAssertEqual(
            state.networkRuntime.state.topologySnapshot.manualRoutesByNodeID[topology.firstRouterNodeID],
            [installedRoute]
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: topology.sourceNodeID, command: "ping 10.0.2.10")
        )
        XCTAssertEqual(state.lastPingEvent?.code, .pingSucceeded)
        XCTAssertNil(state.lastPingFault)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(
                nodeID: topology.firstRouterNodeID,
                request: webAdministrationPOST(
                    target: "/admin/actions/routes/delete",
                    fields: ["id": "manual-0"]
                )
            )
        )

        XCTAssertEqual(state.runtimeWebAdministrationResponsesByNodeID[topology.firstRouterNodeID]?.statusCode, 200)
        XCTAssertNil(state.runtimeManualRoutesByNodeID[topology.firstRouterNodeID])
        XCTAssertNil(state.networkRuntime.state.topologySnapshot.manualRoutesByNodeID[topology.firstRouterNodeID])
        XCTAssertEqual(state.simulationPhase, .running)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: topology.sourceNodeID, command: "ping 10.0.2.10")
        )
        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedSubnetMismatch)
        XCTAssertEqual(state.lastPingFault?.code, "forwardingRouteMissing")
    }

    func testWebAdministrationDHCPMutationUpdatesGatewayAndRejectsRouterTransactionally() throws {
        var state = TopologyEditorState()
        let gatewayID = addNode(kind: .gateway, at: CGPoint(x: 20, y: 20), to: &state)
        let routerID = addNode(kind: .router, at: CGPoint(x: 180, y: 20), to: &state)
        try enableWebAdministration(nodeID: gatewayID, state: &state)
        try enableWebAdministration(nodeID: routerID, state: &state)
        let request = webAdministrationPOST(
            target: "/admin/actions/dhcp/update",
            fields: [
                "isActive": "true",
                "lowerBoundIPAddress": "192.168.40.100",
                "upperBoundIPAddress": "192.168.40.199",
                "gatewayIPAddress": "192.168.40.1",
                "dnsServerIPAddress": "192.168.40.53",
                "usesOwnSettings": "false",
            ]
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(nodeID: gatewayID, request: request)
        )
        let gatewayConfiguration = try XCTUnwrap(state.runtimeDHCPServerConfigurationsByNodeID[gatewayID])
        XCTAssertTrue(gatewayConfiguration.isActive)
        XCTAssertEqual(gatewayConfiguration.lowerBoundIPAddress, "192.168.40.100")
        XCTAssertEqual(gatewayConfiguration.upperBoundIPAddress, "192.168.40.199")
        XCTAssertEqual(gatewayConfiguration.gatewayIPAddress, "192.168.40.1")
        XCTAssertEqual(gatewayConfiguration.dnsServerIPAddress, "192.168.40.53")

        let existingRouterConfiguration = TopologyDHCPServerConfiguration(
            isActive: false,
            lowerBoundIPAddress: "10.0.0.10",
            upperBoundIPAddress: "10.0.0.20"
        )
        state.runtimeDHCPServerConfigurationsByNodeID[routerID] = existingRouterConfiguration
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(nodeID: routerID, request: request)
        )
        XCTAssertEqual(state.runtimeDHCPServerConfigurationsByNodeID[routerID], existingRouterConfiguration)
        XCTAssertEqual(state.runtimeWebAdministrationResponsesByNodeID[routerID]?.statusCode, 409)
    }

    func testRunningWebAdministrationDHCPEnableDisableAndPoolChangeApplyWithoutRestart() throws {
        var state = TopologyEditorState()
        let gatewayID = addNode(kind: .gateway, at: CGPoint(x: 20, y: 20), to: &state)
        let clientID = addNode(kind: .pc, at: CGPoint(x: 220, y: 20), to: &state)
        let gateway = try XCTUnwrap(state.graph.node(withID: gatewayID))
        let lanPortID = try XCTUnwrap(gateway.ports.dropFirst().first?.id)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: gatewayID, portID: lanPortID)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .completeConnection(nodeID: clientID, portID: nil)
        )
        XCTAssertNil(state.lastValidationError)
        saveRuntimeConfiguration(
            nodeID: clientID,
            ipAddress: "192.168.0.20",
            subnetMask: "255.255.255.0",
            defaultGateway: "192.168.0.10",
            state: &state
        )
        try enableWebAdministration(nodeID: gatewayID, state: &state)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        XCTAssertNil(state.networkRuntime.state.dhcpServerSocketIDsByNodeID[gatewayID])

        let enableFirstPool = webAdministrationPOST(
            target: "/admin/actions/dhcp/update",
            fields: [
                "isActive": "true",
                "lowerBoundIPAddress": "192.168.0.100",
                "upperBoundIPAddress": "192.168.0.100",
                "gatewayIPAddress": "192.168.0.10",
                "dnsServerIPAddress": "192.168.0.53",
                "usesOwnSettings": "false",
            ]
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(nodeID: gatewayID, request: enableFirstPool)
        )

        XCTAssertEqual(state.runtimeWebAdministrationResponsesByNodeID[gatewayID]?.statusCode, 200)
        let firstListenerSocketID = try XCTUnwrap(
            state.networkRuntime.state.dhcpServerSocketIDsByNodeID[gatewayID]
        )
        XCTAssertEqual(
            state.networkRuntime.state.topologySnapshot.dhcpServerConfigurationsByNodeID[gatewayID]?.lowerBoundIPAddress,
            "192.168.0.100"
        )
        XCTAssertEqual(
            try requestDHCPLease(clientNodeID: clientID, state: &state),
            "192.168.0.100"
        )
        let clientMAC = try XCTUnwrap(
            state.networkRuntime.networkInterfaces(nodeID: clientID).first?.macAddress
        )
        XCTAssertNotNil(state.networkRuntime.state.dhcpLeasesByIPAddress.values.first {
            $0.clientMACAddress.caseInsensitiveCompare(clientMAC) == .orderedSame
                && $0.ipAddress == "192.168.0.100"
        })

        let updateActivePool = webAdministrationPOST(
            target: "/admin/actions/dhcp/update",
            fields: [
                "isActive": "true",
                "lowerBoundIPAddress": "192.168.0.200",
                "upperBoundIPAddress": "192.168.0.200",
                "gatewayIPAddress": "192.168.0.10",
                "dnsServerIPAddress": "192.168.0.53",
                "usesOwnSettings": "false",
            ]
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(nodeID: gatewayID, request: updateActivePool)
        )

        XCTAssertEqual(
            state.networkRuntime.state.dhcpServerSocketIDsByNodeID[gatewayID],
            firstListenerSocketID,
            "A pool-only edit must keep the active listener bound."
        )
        XCTAssertNotNil(state.networkRuntime.state.dhcpLeasesByIPAddress.values.first {
            $0.clientMACAddress.caseInsensitiveCompare(clientMAC) == .orderedSame
                && $0.ipAddress == "192.168.0.100"
        }, "Committed leases survive configuration edits until the client rebinds or they expire.")
        XCTAssertEqual(
            try requestDHCPLease(clientNodeID: clientID, state: &state),
            "192.168.0.200"
        )
        XCTAssertEqual(
            state.networkRuntime.state.dhcpLeasesByIPAddress.values.filter {
                $0.clientMACAddress.caseInsensitiveCompare(clientMAC) == .orderedSame
            }.map(\.ipAddress),
            ["192.168.0.200"],
            "A successful client rebind replaces that client's retained lease."
        )

        let disable = webAdministrationPOST(
            target: "/admin/actions/dhcp/update",
            fields: [
                "isActive": "false",
                "lowerBoundIPAddress": "192.168.0.200",
                "upperBoundIPAddress": "192.168.0.200",
                "gatewayIPAddress": "192.168.0.10",
                "dnsServerIPAddress": "192.168.0.53",
                "usesOwnSettings": "false",
            ]
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(nodeID: gatewayID, request: disable)
        )

        XCTAssertNil(state.networkRuntime.state.dhcpServerSocketIDsByNodeID[gatewayID])
        XCTAssertNil(state.networkRuntime.state.socketsByID[firstListenerSocketID])
        XCTAssertNil(try discoverDHCPAddress(clientNodeID: clientID, state: &state))
        XCTAssertNotNil(state.networkRuntime.state.dhcpLeasesByIPAddress.values.first {
            $0.clientMACAddress.caseInsensitiveCompare(clientMAC) == .orderedSame
                && $0.ipAddress == "192.168.0.200"
        })

        let reenableThirdPool = webAdministrationPOST(
            target: "/admin/actions/dhcp/update",
            fields: [
                "isActive": "true",
                "lowerBoundIPAddress": "192.168.0.210",
                "upperBoundIPAddress": "192.168.0.210",
                "gatewayIPAddress": "192.168.0.10",
                "dnsServerIPAddress": "192.168.0.53",
                "usesOwnSettings": "false",
            ]
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(nodeID: gatewayID, request: reenableThirdPool)
        )

        XCTAssertNotNil(state.networkRuntime.state.dhcpServerSocketIDsByNodeID[gatewayID])
        XCTAssertEqual(try discoverDHCPAddress(clientNodeID: clientID, state: &state), "192.168.0.210")
        XCTAssertEqual(state.simulationPhase, .running)
    }

    func testRunningWebAdministrationDHCPBindFailureRollsBackEditorAndRuntimeState() throws {
        var state = TopologyEditorState()
        let gatewayID = addNode(kind: .gateway, at: CGPoint(x: 20, y: 20), to: &state)
        let originalConfiguration = TopologyDHCPServerConfiguration(
            isActive: false,
            lowerBoundIPAddress: "192.168.0.20",
            upperBoundIPAddress: "192.168.0.29",
            gatewayIPAddress: "192.168.0.10",
            dnsServerIPAddress: "192.168.0.53"
        )
        state.runtimeDHCPServerConfigurationsByNodeID[gatewayID] = originalConfiguration
        try enableWebAdministration(nodeID: gatewayID, state: &state)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        let listenerConflict = try XCTUnwrap(
            state.networkRuntime.bindUDPSocket(
                nodeID: gatewayID,
                localPort: TopologyNetworkRuntimeEngine.dhcpServerPort,
                localIPAddress: "192.168.0.10"
            )
        )
        let revisionBeforeRequest = state.persistenceRevision

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(
                nodeID: gatewayID,
                request: webAdministrationPOST(
                    target: "/admin/actions/dhcp/update",
                    fields: [
                        "isActive": "true",
                        "lowerBoundIPAddress": "192.168.0.100",
                        "upperBoundIPAddress": "192.168.0.109",
                        "gatewayIPAddress": "192.168.0.10",
                        "dnsServerIPAddress": "192.168.0.53",
                        "usesOwnSettings": "false",
                    ]
                )
            )
        )

        XCTAssertEqual(state.runtimeWebAdministrationResponsesByNodeID[gatewayID]?.statusCode, 409)
        XCTAssertEqual(state.runtimeDHCPServerConfigurationsByNodeID[gatewayID], originalConfiguration)
        XCTAssertEqual(
            state.networkRuntime.state.topologySnapshot.dhcpServerConfigurationsByNodeID[gatewayID],
            originalConfiguration
        )
        XCTAssertNotNil(state.networkRuntime.state.socketsByID[listenerConflict])
        XCTAssertNil(state.networkRuntime.state.dhcpServerSocketIDsByNodeID[gatewayID])
        XCTAssertEqual(state.persistenceRevision, revisionBeforeRequest)
        XCTAssertEqual(state.lastRuntimeFault?.code, "webAdministrationHTTP409")
        XCTAssertTrue(state.lastRuntimeFault?.message.contains("UDP port 67") == true)
    }

    func testWebAdministrationPortForwardMutationsAddDeleteAndRollback() throws {
        var state = TopologyEditorState()
        let gatewayID = addNode(kind: .gateway, at: CGPoint(x: 20, y: 20), to: &state)
        try enableWebAdministration(nodeID: gatewayID, state: &state)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        let add = webAdministrationPOST(
            target: "/admin/actions/nat/port-forwards/add",
            fields: [
                "id": "web",
                "protocol": "tcp",
                "publicPort": "8080",
                "lanIPAddress": "192.168.50.10",
                "lanPort": "80",
            ]
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(nodeID: gatewayID, request: add)
        )
        XCTAssertEqual(state.runtimePortForwardingRowsByNodeID[gatewayID]?.count, 1)
        XCTAssertEqual(
            state.networkRuntime.state.topologySnapshot.portForwardingRowsByNodeID[gatewayID]?.count,
            1
        )
        XCTAssertEqual(
            state.networkRuntime.natMappings(gatewayNodeID: gatewayID).filter { $0.type == .staticEntry }.count,
            1
        )

        let committedRows = state.runtimePortForwardingRowsByNodeID[gatewayID]
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(nodeID: gatewayID, request: add)
        )
        XCTAssertEqual(state.runtimePortForwardingRowsByNodeID[gatewayID], committedRows)
        XCTAssertEqual(state.runtimeWebAdministrationResponsesByNodeID[gatewayID]?.statusCode, 409)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(
                nodeID: gatewayID,
                request: webAdministrationPOST(
                    target: "/admin/actions/nat/port-forwards/delete",
                    fields: ["id": "port-forward-0"]
                )
            )
        )
        XCTAssertNil(state.runtimePortForwardingRowsByNodeID[gatewayID])
        XCTAssertTrue(state.networkRuntime.natMappings(gatewayNodeID: gatewayID).isEmpty)
    }

    func testWebAdministrationFirewallMutationsApplySettingsRulesDeletesAndRollback() throws {
        var state = TopologyEditorState()
        let routerID = addNode(kind: .router, at: CGPoint(x: 20, y: 20), to: &state)
        try enableWebAdministration(nodeID: routerID, state: &state)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(
                nodeID: routerID,
                request: webAdministrationPOST(
                    target: "/admin/actions/firewall/update",
                    fields: [
                        "isActive": "true",
                        "defaultPolicy": "drop",
                        "dropsICMP": "true",
                        "filtersSYNSegmentsOnly": "false",
                        "filtersUDP": "true",
                    ]
                )
            )
        )
        var configuration = try XCTUnwrap(state.runtimeFirewallConfigurationsByNodeID[routerID])
        XCTAssertTrue(configuration.isActive)
        XCTAssertEqual(configuration.defaultPolicy, .drop)
        XCTAssertTrue(configuration.dropICMP)
        XCTAssertFalse(configuration.filterSYNSegmentsOnly)
        XCTAssertTrue(configuration.filterUDP)

        let addRule = webAdministrationPOST(
            target: "/admin/actions/firewall/rules/add",
            fields: [
                "id": "allow-dns",
                "sourceIPAddress": "0.0.0.0",
                "sourceSubnetMask": "0.0.0.0",
                "destinationIPAddress": "192.168.1.53",
                "destinationSubnetMask": "255.255.255.255",
                "port": "53",
                "protocol": "udp",
                "action": "accept",
            ]
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(nodeID: routerID, request: addRule)
        )
        configuration = try XCTUnwrap(state.runtimeFirewallConfigurationsByNodeID[routerID])
        XCTAssertEqual(configuration.rules.count, 1)
        XCTAssertEqual(configuration.rules[0].protocolType, .udp)
        XCTAssertEqual(configuration.rules[0].action, .accept)

        let committedConfiguration = configuration
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(nodeID: routerID, request: addRule)
        )
        XCTAssertEqual(state.runtimeFirewallConfigurationsByNodeID[routerID], committedConfiguration)
        XCTAssertEqual(state.runtimeWebAdministrationResponsesByNodeID[routerID]?.statusCode, 409)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(
                nodeID: routerID,
                request: webAdministrationPOST(
                    target: "/admin/actions/firewall/rules/delete",
                    fields: ["id": "rule-0"]
                )
            )
        )
        XCTAssertEqual(state.runtimeFirewallConfigurationsByNodeID[routerID]?.rules, [])
    }

    func testWebAdministrationClearNATMappingsAndValidationFailurePreserveConfiguration() throws {
        var state = TopologyEditorState()
        let gatewayID = addNode(kind: .gateway, at: CGPoint(x: 20, y: 20), to: &state)
        try enableWebAdministration(nodeID: gatewayID, state: &state)
        let existingRows = [TopologyGatewayPortForwardingRow(
            protocolValue: "TCP",
            publicPortValue: "443",
            lanIPAddress: "192.168.1.10",
            lanPortValue: "8443"
        )]
        state.runtimePortForwardingRowsByNodeID[gatewayID] = existingRows
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(
                nodeID: gatewayID,
                request: webAdministrationPOST(
                    target: "/admin/actions/nat/mappings/clear",
                    fields: [:]
                )
            )
        )
        XCTAssertEqual(state.runtimePortForwardingRowsByNodeID[gatewayID], existingRows)
        XCTAssertEqual(
            state.networkRuntime.natMappings(gatewayNodeID: gatewayID).filter { $0.type == .staticEntry }.count,
            1
        )
        XCTAssertEqual(state.runtimeWebAdministrationResponsesByNodeID[gatewayID]?.statusCode, 200)

        let routesBefore = state.runtimeManualRoutesByNodeID
        let dhcpBefore = state.runtimeDHCPServerConfigurationsByNodeID
        let forwardsBefore = state.runtimePortForwardingRowsByNodeID
        let firewallBefore = state.runtimeFirewallConfigurationsByNodeID
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeWebAdministrationRequest(
                nodeID: gatewayID,
                request: webAdministrationPOST(
                    target: "/admin/actions/routes/add",
                    fields: ["destinationNetwork": "invalid"]
                )
            )
        )
        XCTAssertEqual(state.runtimeManualRoutesByNodeID, routesBefore)
        XCTAssertEqual(state.runtimeDHCPServerConfigurationsByNodeID, dhcpBefore)
        XCTAssertEqual(state.runtimePortForwardingRowsByNodeID, forwardsBefore)
        XCTAssertEqual(state.runtimeFirewallConfigurationsByNodeID, firewallBefore)
        XCTAssertEqual(state.runtimeWebAdministrationResponsesByNodeID[gatewayID]?.statusCode, 400)
        XCTAssertEqual(state.lastRuntimeFault?.code, "webAdministrationHTTP400")
    }

    func testWebAdministrationTerminalClearAndLastRevokeDisableAccessSafely() throws {
        var state = TopologyEditorState()
        let routerID = addNode(kind: .router, at: CGPoint(x: 20, y: 20), to: &state)
        try enableWebAdministration(nodeID: routerID, state: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(
                nodeID: routerID,
                command: "webadmin revoke 192.168.1.0 255.255.255.0"
            )
        )
        XCTAssertEqual(
            state.runtimeWebAdministrationConfigurationsByNodeID[routerID]?.accessPolicy,
            TopologyRuntimeWebAdministrationAccessPolicy()
        )
        XCTAssertNil(state.lastRuntimeFault)

        try enableWebAdministration(nodeID: routerID, state: &state)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: routerID, command: "webadmin clear")
        )
        XCTAssertEqual(
            state.runtimeWebAdministrationConfigurationsByNodeID[routerID]?.accessPolicy,
            TopologyRuntimeWebAdministrationAccessPolicy()
        )
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testWebAdministrationTerminalCommandsRejectNonRouterGatewaySources() {
        var state = TopologyEditorState()
        let pcID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: pcID, command: "webadmin on")
        )

        XCTAssertNil(state.runtimeWebAdministrationConfigurationsByNodeID[pcID])
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeWebAdministrationRequestRejected)
        XCTAssertEqual(state.lastRuntimeFault?.code, "webAdministrationUnsupportedForNodeKind")
        XCTAssertTrue(
            state.runtimeConsoleEntriesByNodeID[pcID]?.contains(where: {
                $0.contains("Router and Gateway")
            }) == true
        )
    }

    private func enableWebAdministration(
        nodeID: UUID,
        sourceIPAddress: String = "192.168.1.10",
        state: inout TopologyEditorState
    ) throws {
        let network = try TopologyRuntimeWebAdministrationIPv4Network(
            networkAddress: "192.168.1.0",
            subnetMask: "255.255.255.0"
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeWebAdministrationPolicy(
                nodeID: nodeID,
                policy: TopologyRuntimeWebAdministrationAccessPolicy(
                    isEnabled: true,
                    allowedSourceNetworks: [network]
                )
            )
        )
        XCTAssertEqual(
            state.runtimeWebAdministrationConfigurationsByNodeID[nodeID]?.accessPolicy
                .accessDecision(for: sourceIPAddress),
            .allowed
        )
    }

    private func discoverDHCPAddress(
        clientNodeID: UUID,
        state: inout TopologyEditorState
    ) throws -> String? {
        let clientInterface = try XCTUnwrap(
            state.networkRuntime.networkInterfaces(nodeID: clientNodeID).first
        )
        let socketID = try XCTUnwrap(
            state.networkRuntime.bindUDPSocket(
                nodeID: clientNodeID,
                localPort: TopologyNetworkRuntimeEngine.dhcpClientPort,
                localIPAddress: clientInterface.ipAddress,
                remoteIPAddress: TopologyNetworkRuntimeEngine.limitedBroadcastIPAddress,
                remotePort: TopologyNetworkRuntimeEngine.dhcpServerPort
            )
        )
        defer { state.networkRuntime.closeSocket(socketID: socketID) }
        let discover = Data(
            "DHCPDISCOVER\nyiaddr=0.0.0.0\nchaddr=\(clientInterface.macAddress)".utf8
        )
        _ = state.networkRuntime.sendUDP(socketID: socketID, payload: discover)
        guard let offer = state.networkRuntime.receiveUDP(socketID: socketID),
              let fields = dhcpFields(in: offer.datagram.payload),
              fields.command == "DHCPOFFER"
        else { return nil }
        return fields.values["yiaddr"]
    }

    private func requestDHCPLease(
        clientNodeID: UUID,
        state: inout TopologyEditorState
    ) throws -> String? {
        let clientInterface = try XCTUnwrap(
            state.networkRuntime.networkInterfaces(nodeID: clientNodeID).first
        )
        let socketID = try XCTUnwrap(
            state.networkRuntime.bindUDPSocket(
                nodeID: clientNodeID,
                localPort: TopologyNetworkRuntimeEngine.dhcpClientPort,
                localIPAddress: clientInterface.ipAddress,
                remoteIPAddress: TopologyNetworkRuntimeEngine.limitedBroadcastIPAddress,
                remotePort: TopologyNetworkRuntimeEngine.dhcpServerPort
            )
        )
        defer { state.networkRuntime.closeSocket(socketID: socketID) }
        let discover = Data(
            "DHCPDISCOVER\nyiaddr=0.0.0.0\nchaddr=\(clientInterface.macAddress)".utf8
        )
        _ = state.networkRuntime.sendUDP(socketID: socketID, payload: discover)
        let offer = try XCTUnwrap(state.networkRuntime.receiveUDP(socketID: socketID))
        let offerFields = try XCTUnwrap(dhcpFields(in: offer.datagram.payload))
        XCTAssertEqual(offerFields.command, "DHCPOFFER")
        let offeredIPAddress = try XCTUnwrap(offerFields.values["yiaddr"])
        let serverIdentifier = try XCTUnwrap(offerFields.values["serverident"])
        let request = Data(
            [
                "DHCPREQUEST",
                "yiaddr=0.0.0.0",
                "chaddr=\(clientInterface.macAddress)",
                "requested=\(offeredIPAddress)",
                "serverident=\(serverIdentifier)",
            ].joined(separator: "\n").utf8
        )
        _ = state.networkRuntime.sendUDP(socketID: socketID, payload: request)
        let acknowledgement = try XCTUnwrap(state.networkRuntime.receiveUDP(socketID: socketID))
        XCTAssertEqual(dhcpFields(in: acknowledgement.datagram.payload)?.command, "DHCPACK")
        return offeredIPAddress
    }

    private func dhcpFields(in data: Data) -> (command: String, values: [String: String])? {
        guard let payload = String(data: data, encoding: .utf8) else { return nil }
        let lines = payload.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let command = lines.first else { return nil }
        let values = lines.dropFirst().reduce(into: [String: String]()) { result, line in
            let pair = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { return }
            result[String(pair[0])] = String(pair[1])
        }
        return (command, values)
    }

    private func webAdministrationPOST(
        target: String,
        sourceIPAddress: String = "192.168.1.10",
        fields: [String: String]
    ) -> TopologyRuntimeWebAdministrationRequest {
        TopologyRuntimeWebAdministrationRequest(
            method: "POST",
            target: target,
            sourceIPAddress: sourceIPAddress,
            formFields: fields
        )
    }

    private func activateRuntimeProgram(
        _ program: TopologyRuntimeInstallableProgram,
        nodeID: UUID,
        state: inout TopologyEditorState
    ) {
        if state.simulationPhase != .running {
            TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        }
        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: nodeID))
        if state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(program) != true {
            TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: program))
        }
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: program))
    }

    private func imageContainsVisibleColor(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return pixel[3] > 0 && pixel[0...2].contains(where: { $0 > 8 })
    }

    private func uuid(_ rawValue: String) -> UUID {
        UUID(uuidString: rawValue) ?? UUID()
    }

    private func tryUnwrap<T>(_ value: T?) -> T {
        guard let value else {
            XCTFail("Expected non-nil value")
            fatalError("Expected non-nil value")
        }
        return value
    }
}
