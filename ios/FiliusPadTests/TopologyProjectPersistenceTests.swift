import CoreGraphics
import XCTest
@testable import FiliusPad

final class TopologyProjectPersistenceTests: XCTestCase {
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TopologyProjectPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDirectoryURL)
        }
        tempDirectoryURL = nil
    }

    func testRoundTripPreservesDurableStateAndExcludesTransientFields() throws {
        var state = TopologyEditorState()

        let pcNode = TopologyNode(
            id: uuid("11111111-1111-1111-1111-111111111111"),
            kind: .pc,
            displayName: "Arbeitsplatz Alpha",
            position: CGPoint(x: 140.25, y: 88.5),
            ports: [TopologyPortMetadata(id: uuid("11111111-1111-1111-1111-111111111112"), label: "eth0")]
        )
        let switchNode = TopologyNode(
            id: uuid("22222222-2222-2222-2222-222222222222"),
            kind: .networkSwitch,
            displayName: "Etagenverteiler",
            position: CGPoint(x: 380.5, y: 130.75)
        )
        let routerNode = TopologyNode(
            id: uuid("44444444-4444-4444-4444-444444444444"),
            kind: .router,
            displayName: "Kernrouter",
            position: CGPoint(x: 520, y: 210)
        )
        let gatewayNode = TopologyNode(
            id: uuid("55555555-5555-5555-5555-555555555555"),
            kind: .gateway,
            displayName: "Internetzugang",
            position: CGPoint(x: 680, y: 210)
        )

        let link = TopologyLink(
            id: uuid("33333333-3333-3333-3333-333333333333"),
            sourceNodeID: pcNode.id,
            sourcePortID: pcNode.ports[0].id,
            targetNodeID: switchNode.id,
            targetPortID: switchNode.ports[0].id
        )

        state.graph = TopologyGraph(nodes: [pcNode, switchNode, routerNode, gatewayNode], links: [link])
        state.seedJavaRuntimeInterfaceDefaultsForGraph()
        state.runtimeInterfaceConfigurations[
            TopologyRuntimeInterfaceKey(nodeID: routerNode.id, portID: routerNode.ports[0].id)
        ] = TopologyRuntimeInterfaceConfiguration(
            ipAddress: "10.10.0.1",
            subnetMask: "255.255.0.0"
        )
        state.viewport = ViewportTransform(offset: CGSize(width: 120.5, height: -34.25), scale: 1.75)
        state.runtimeDeviceConfigurations[pcNode.id] = TopologyRuntimeDeviceConfiguration(
            ipAddress: "192.168.50.2",
            subnetMask: "255.255.255.0",
            defaultGateway: "192.168.50.1",
            dnsServer: "192.168.50.53"
        )
        state.switchConfigurationsByNodeID[switchNode.id] = TopologySwitchConfiguration(
            ssid: "Etage-2",
            retentionTimeMilliseconds: 120_000
        )
        state.hostWirelessConfigurationsByNodeID[pcNode.id] = TopologyHostWirelessConfiguration(
            isEnabled: true,
            ssid: "Etage-2"
        )
        state.runtimeManualRoutesByNodeID[pcNode.id] = [
            TopologyRuntimeManualRoute(
                destinationNetwork: "10.0.0.0",
                subnetMask: "255.0.0.0",
                gateway: "192.168.50.1",
                interfaceIPAddress: "192.168.50.2"
            )
        ]
        state.runtimeRIPEnabledByNodeID[routerNode.id] = true
        state.runtimeManualRoutesByNodeID[routerNode.id] = [
            TopologyRuntimeManualRoute(
                destinationNetwork: "172.16.0.0",
                subnetMask: "255.255.0.0",
                gateway: "10.10.0.2",
                interfaceIPAddress: "10.10.0.1"
            ),
            TopologyRuntimeManualRoute(
                destinationNetwork: "172.16.10.0",
                subnetMask: "255.255.255.0",
                gateway: "10.10.0.3",
                interfaceIPAddress: "10.10.0.1"
            )
        ]
        state.runtimeDHCPClientConfigurationsByNodeID[pcNode.id] = TopologyDHCPClientConfiguration(isEnabled: true)
        state.runtimeDHCPServerConfigurationsByNodeID[gatewayNode.id] = TopologyDHCPServerConfiguration(
            isActive: true,
            lowerBoundIPAddress: "192.168.70.20",
            upperBoundIPAddress: "192.168.70.29",
            gatewayIPAddress: "0.0.0.0",
            dnsServerIPAddress: "192.168.70.53",
            useOwnSettings: false,
            staticAssignments: [
                TopologyDHCPStaticAssignment(
                    macAddress: "02:00:00:00:00:70",
                    ipAddress: "192.168.70.22"
                )
            ]
        )
        state.runtimeInstalledProgramsByNodeID[pcNode.id] = [.dnsServer]
        state.runtimeDNSServerConfigurationsByNodeID[pcNode.id] = TopologyRuntimeDNSServerConfiguration(
            recordsByHostname: [
                "lab.local": TopologyRuntimeDNSRecord(hostname: "lab.local", targetIPAddress: "192.168.50.2")
            ]
        )

        let protocolDefinition = TopologyProtocolApplicationDefinition(
            id: uuid("66666666-6666-6666-6666-666666666666"),
            name: "Project Protocol",
            role: .client,
            transport: .tcp,
            port: 55555,
            clientMessageTemplates: [
                .init(id: uuid("66666666-6666-6666-6666-666666666667"), name: "Greeting", message: "hello")
            ]
        )
        state.protocolApplicationDefinitionsByID[protocolDefinition.id] = protocolDefinition
        state.runtimeInstalledProtocolApplicationIDsByNodeID[pcNode.id] = [protocolDefinition.id]
        state.runtimeActiveProtocolApplicationIDByNodeID[pcNode.id] = protocolDefinition.id
        let protocolRuntimeKey = TopologyProtocolApplicationRuntimeKey(nodeID: pcNode.id, definitionID: protocolDefinition.id)
        var transientProtocolClient = TopologyProtocolApplicationClientState(socketID: nil, destinationIPAddress: "192.168.50.9")
        transientProtocolClient.appendLog(time: 19, direction: "outbound", message: "hello")
        state.runtimeProtocolApplicationClients[protocolRuntimeKey] = transientProtocolClient

        state.selectedNodeIDs = [pcNode.id, switchNode.id]
        state.activeTool = .connect
        state.pendingConnection = TopologyConnectionDraft(sourceNodeID: pcNode.id, sourcePortID: pcNode.ports[0].id)
        state.simulationPhase = .running
        state.simulationTick = 19
        state.lastRuntimeEvent = TopologyRuntimeEvent(code: .simulationTickAdvanced, detail: "step=1")
        state.lastRuntimeFault = TopologyRuntimeFault(category: .runtimeFault, code: "fault", message: "fault")
        state.openedRuntimeDeviceID = pcNode.id
        state.runtimeConsoleEntriesByNodeID[pcNode.id] = ["ping 192.168.50.1"]
        state.lastPingEvent = TopologyRuntimeEvent(code: .pingSucceeded, detail: "ok")
        state.lastPingFault = TopologyRuntimeFault(category: .networkRouting, code: "pingTargetUnknown", message: "missing")
        state.lastValidationError = .duplicateLink
        state.lastAction = "zoomCanvas"
        state.lastActionAt = Date(timeIntervalSince1970: 500)
        state.lastInteractionMode = "canvasTap:place:pc"
        state.transitionCount = 72
        state.persistenceRevision = 42

        let store = TopologyProjectStore(fileURL: tempDirectoryURL.appendingPathComponent("project.json"))
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try store.save(state: state, savedAt: savedAt)
        let encodedProject = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertFalse(encodedProject.contains("switchForwardingTablesByNodeID"))
        XCTAssertFalse(encodedProject.contains("switchForwardingUpdatedAtMillisecondsByNodeID"))

        let loaded = try store.load()

        XCTAssertEqual(loaded.graph, state.graph)
        XCTAssertEqual(loaded.viewport, state.viewport)
        XCTAssertEqual(loaded.runtimeDeviceConfigurations, state.runtimeDeviceConfigurations)
        XCTAssertEqual(loaded.switchConfigurationsByNodeID, state.switchConfigurationsByNodeID)
        XCTAssertEqual(loaded.hostWirelessConfigurationsByNodeID, state.hostWirelessConfigurationsByNodeID)
        XCTAssertEqual(loaded.runtimeInterfaceConfigurations, state.runtimeInterfaceConfigurations)
        XCTAssertEqual(loaded.runtimeManualRoutesByNodeID, state.runtimeManualRoutesByNodeID)
        XCTAssertEqual(loaded.runtimeRIPEnabledByNodeID, state.runtimeRIPEnabledByNodeID)
        XCTAssertEqual(loaded.runtimeDHCPClientConfigurationsByNodeID, state.runtimeDHCPClientConfigurationsByNodeID)
        XCTAssertEqual(loaded.runtimeDHCPServerConfigurationsByNodeID, state.runtimeDHCPServerConfigurationsByNodeID)
        XCTAssertEqual(loaded.runtimeDNSServerConfigurationsByNodeID, state.runtimeDNSServerConfigurationsByNodeID)
        XCTAssertEqual(loaded.protocolApplicationDefinitionsByID, state.protocolApplicationDefinitionsByID)
        XCTAssertEqual(loaded.runtimeInstalledProtocolApplicationIDsByNodeID, state.runtimeInstalledProtocolApplicationIDsByNodeID)
        XCTAssertEqual(loaded.persistenceRevision, 42)
        XCTAssertEqual(loaded.lastPersistedRevision, 42)
        XCTAssertEqual(loaded.lastPersistenceSaveAt, savedAt)
        XCTAssertEqual(loaded.graph.nodes.first(where: { $0.id == switchNode.id })?.ports.count, 24)
        XCTAssertEqual(loaded.graph.nodes.first(where: { $0.id == routerNode.id })?.ports.map(\.label), ["rt1"])
        XCTAssertEqual(loaded.graph.nodes.first(where: { $0.id == gatewayNode.id })?.ports.map(\.label), ["wan0", "lan0"])

        XCTAssertTrue(loaded.selectedNodeIDs.isEmpty)
        XCTAssertEqual(loaded.activeTool, .select)
        XCTAssertNil(loaded.pendingConnection)
        XCTAssertEqual(loaded.simulationPhase, .stopped)
        XCTAssertEqual(loaded.simulationTick, 0)
        XCTAssertNil(loaded.lastRuntimeEvent)
        XCTAssertNil(loaded.lastRuntimeFault)
        XCTAssertNil(loaded.openedRuntimeDeviceID)
        XCTAssertTrue(loaded.runtimeActiveProtocolApplicationIDByNodeID.isEmpty)
        XCTAssertTrue(loaded.runtimeProtocolApplicationClients.isEmpty)
        XCTAssertTrue(loaded.runtimeProtocolApplicationServers.isEmpty)
        XCTAssertTrue(loaded.runtimeConsoleEntriesByNodeID.isEmpty)
        XCTAssertNil(loaded.lastPingEvent)
        XCTAssertNil(loaded.lastPingFault)
        XCTAssertNil(loaded.lastValidationError)
        XCTAssertNil(loaded.lastAction)
        XCTAssertNil(loaded.lastActionAt)
        XCTAssertNil(loaded.lastInteractionMode)
        XCTAssertEqual(loaded.transitionCount, 0)
    }

    func testSchemaEightMigratesProtocolApplicationsToEmpty() throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("schema-8-protocol-migration.json")
        let store = TopologyProjectStore(fileURL: fileURL)
        try store.save(state: TopologyEditorState(), savedAt: Date(timeIntervalSince1970: 1_700_000_100))
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
        envelope["schemaVersion"] = 8
        var payload = try XCTUnwrap(envelope["payload"] as? [String: Any])
        payload.removeValue(forKey: "protocolApplicationDefinitions")
        payload.removeValue(forKey: "protocolApplicationInstallations")
        envelope["payload"] = payload
        try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]).write(to: fileURL)

        let loaded = try store.load()
        XCTAssertTrue(loaded.protocolApplicationDefinitionsByID.isEmpty)
        XCTAssertTrue(loaded.runtimeInstalledProtocolApplicationIDsByNodeID.isEmpty)
    }

    func testSchemaNineRejectsMissingProtocolApplicationDefinitions() throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("schema-9-missing-protocol-definitions.json")
        let store = TopologyProjectStore(fileURL: fileURL)
        try store.save(state: TopologyEditorState(), savedAt: Date(timeIntervalSince1970: 1_700_000_100))
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
        var payload = try XCTUnwrap(envelope["payload"] as? [String: Any])
        payload.removeValue(forKey: "protocolApplicationDefinitions")
        envelope["payload"] = payload
        try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]).write(to: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            self.assertPersistenceError(error, expectedOperation: .load, expectedCode: .malformedPayload)
        }
    }

    func testEmptyTopologyRoundTripSucceeds() throws {
        let store = TopologyProjectStore(fileURL: tempDirectoryURL.appendingPathComponent("empty.json"))
        try store.save(state: TopologyEditorState(), savedAt: Date(timeIntervalSince1970: 1_700_000_100))

        let loaded = try store.load()

        XCTAssertTrue(loaded.graph.nodes.isEmpty)
        XCTAssertTrue(loaded.graph.links.isEmpty)
        XCTAssertEqual(loaded.viewport, .identity)
    }

    func testLegacyRuntimeDeviceConfigurationWithoutDefaultGatewayLoadsBlank() throws {
        var state = TopologyEditorState()
        let pcNode = TopologyNode(
            id: uuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            kind: .pc,
            position: CGPoint(x: 40, y: 40)
        )
        state.graph = TopologyGraph(nodes: [pcNode], links: [])
        state.runtimeDeviceConfigurations[pcNode.id] = TopologyRuntimeDeviceConfiguration(
            ipAddress: "10.0.0.20",
            subnetMask: "255.255.255.0",
            defaultGateway: "10.0.0.1"
        )

        let fileURL = tempDirectoryURL.appendingPathComponent("legacy-device-gateway.json")
        let store = TopologyProjectStore(fileURL: fileURL)
        try store.save(state: state, savedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let data = try Data(contentsOf: fileURL)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var payload = try XCTUnwrap(envelope["payload"] as? [String: Any])
        var configurations = try XCTUnwrap(payload["runtimeDeviceConfigurations"] as? [[String: Any]])
        configurations[0].removeValue(forKey: "defaultGateway")
        payload["runtimeDeviceConfigurations"] = configurations
        envelope["payload"] = payload
        try writeJSON(envelope, to: fileURL)

        let loaded = try store.load()
        XCTAssertEqual(loaded.runtimeDeviceConfigurations[pcNode.id]?.defaultGateway, "")
    }

    func testRuntimeDeviceConfigurationRejectsUnknownFields() throws {
        var state = TopologyEditorState()
        let pcNode = TopologyNode(
            id: uuid("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
            kind: .pc,
            position: CGPoint(x: 40, y: 40)
        )
        state.graph = TopologyGraph(nodes: [pcNode], links: [])
        state.runtimeDeviceConfigurations[pcNode.id] = TopologyRuntimeDeviceConfiguration(
            ipAddress: "10.0.0.20",
            subnetMask: "255.255.255.0"
        )

        let fileURL = tempDirectoryURL.appendingPathComponent("unknown-device-config-field.json")
        let store = TopologyProjectStore(fileURL: fileURL)
        try store.save(state: state, savedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let data = try Data(contentsOf: fileURL)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var payload = try XCTUnwrap(envelope["payload"] as? [String: Any])
        var configurations = try XCTUnwrap(payload["runtimeDeviceConfigurations"] as? [[String: Any]])
        configurations[0]["unexpected"] = true
        payload["runtimeDeviceConfigurations"] = configurations
        envelope["payload"] = payload
        try writeJSON(envelope, to: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .corruptedPayload
            )
        }
    }

    func testSchemaVersionOneMigratesUnnamedNodesToDeterministicDisplayNames() throws {
        let nodeID = uuid("abababab-abab-abab-abab-abababababab")
        let portID = uuid("cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd")
        var payload = envelopeDictionary()["payload"] as! [String: Any]
        payload["graph"] = [
            "nodes": [[
                "id": nodeID.uuidString,
                "kind": TopologyNodeKind.pc.rawValue,
                "position": ["x": 40.0, "y": 60.0],
                "ports": [[
                    "id": portID.uuidString,
                    "label": "eth0",
                    "isOccupied": false
                ]]
            ]],
            "links": []
        ]

        let fileURL = tempDirectoryURL.appendingPathComponent("schema-v1-unnamed.json")
        try writeJSON(envelopeDictionary(schemaVersion: 1, payload: payload), to: fileURL)

        let loaded = try TopologyProjectStore(fileURL: fileURL).load()

        XCTAssertEqual(loaded.graph.nodes.first?.displayName, "Rechner")
        XCTAssertEqual(loaded.graph.nodes.first?.id, nodeID)
    }

    func testSchemaVersionFourSeedsDefaultRemoteLinkConfigurationWhenFieldIsMissing() throws {
        let nodeID = uuid("41414141-4141-4141-4141-414141414141")
        let portID = uuid("41414141-4141-4141-4141-414141414142")
        let payload = remoteLinkPayload(nodeID: nodeID, portID: portID)
        let fileURL = tempDirectoryURL.appendingPathComponent("schema-v4-remote-link-migration.json")
        try writeJSON(
            envelopeDictionary(schemaVersion: 4, payload: payload),
            to: fileURL
        )

        let loaded = try TopologyProjectStore(fileURL: fileURL).load()

        XCTAssertEqual(loaded.remoteLinkConfigurationsByNodeID.count, 1)
        XCTAssertEqual(
            loaded.remoteLinkConfigurationsByNodeID[nodeID],
            TopologyRemoteLinkConfiguration.defaultConfiguration(nodeID: nodeID)
        )
    }

    func testSchemaVersionFiveRejectsMissingRemoteLinkConfigurationsField() throws {
        let nodeID = uuid("51515151-5151-5151-5151-515151515151")
        let portID = uuid("51515151-5151-5151-5151-515151515152")
        let payload = remoteLinkPayload(nodeID: nodeID, portID: portID)
        let fileURL = tempDirectoryURL.appendingPathComponent("schema-v5-missing-remote-link-field.json")
        try writeJSON(
            envelopeDictionary(
                schemaVersion: 5,
                payload: payload,
                includeRemoteLinkConfigurations: false
            ),
            to: fileURL
        )

        XCTAssertThrowsError(try TopologyProjectStore(fileURL: fileURL).load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .malformedPayload
            )
            XCTAssertTrue(
                (error as? TopologyProjectPersistenceError)?.detail.contains(
                    "remoteLinkConfigurationsFieldMissing"
                ) == true
            )
        }
    }

    func testSchemaVersionFiveRejectsMissingRemoteLinkNodeConfiguration() throws {
        let nodeID = uuid("52525252-5252-5252-5252-525252525251")
        let portID = uuid("52525252-5252-5252-5252-525252525252")
        let payload = remoteLinkPayload(
            nodeID: nodeID,
            portID: portID,
            remoteLinkConfigurations: []
        )
        let fileURL = tempDirectoryURL.appendingPathComponent("schema-v5-missing-remote-link-entry.json")
        try writeJSON(envelopeDictionary(schemaVersion: 5, payload: payload), to: fileURL)

        XCTAssertThrowsError(try TopologyProjectStore(fileURL: fileURL).load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .malformedPayload
            )
            XCTAssertTrue(
                (error as? TopologyProjectPersistenceError)?.detail.contains(
                    "missingRemoteLinkConfiguration"
                ) == true
            )
        }
    }

    func testSchemaVersionFiveRejectsBlankRemoteLinkPairIdentifier() throws {
        let nodeID = uuid("53535353-5353-5353-5353-535353535351")
        let portID = uuid("53535353-5353-5353-5353-535353535352")
        let payload = remoteLinkPayload(
            nodeID: nodeID,
            portID: portID,
            remoteLinkConfigurations: [[
                "nodeID": nodeID.uuidString,
                "pairIdentifier": "  \n\t  ",
                "latencyMilliseconds": 20,
                "isEnabled": true
            ]]
        )
        let fileURL = tempDirectoryURL.appendingPathComponent("schema-v5-blank-remote-link-pair.json")
        try writeJSON(envelopeDictionary(schemaVersion: 5, payload: payload), to: fileURL)

        XCTAssertThrowsError(try TopologyProjectStore(fileURL: fileURL).load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .malformedPayload
            )
            XCTAssertTrue(
                (error as? TopologyProjectPersistenceError)?.detail.contains(
                    "remoteLinkConfigurationHasBlankPairIdentifier"
                ) == true
            )
        }
    }

    func testSchemaVersionFiveMigratesMissingDocumentationItemsToEmptyList() throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("schema-v5-documentation-migration.json")
        try writeJSON(
            envelopeDictionary(schemaVersion: 5, includeDocumentationItems: false),
            to: fileURL
        )

        let loaded = try TopologyProjectStore(fileURL: fileURL).load()

        XCTAssertTrue(loaded.documentationItems.isEmpty)
        XCTAssertEqual(loaded.workspaceMode, .design)
    }

    func testSchemaVersionSixMigratesMissingDocumentationItemsToEmptyList() throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("schema-v6-documentation-migration.json")
        try writeJSON(
            envelopeDictionary(schemaVersion: 6, includeDocumentationItems: false),
            to: fileURL
        )

        let loaded = try TopologyProjectStore(fileURL: fileURL).load()
        XCTAssertTrue(loaded.documentationItems.isEmpty)
    }

    func testSchemaVersionSevenRejectsMissingDocumentationItemsField() throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("schema-v7-missing-documentation-field.json")
        try writeJSON(
            envelopeDictionary(schemaVersion: 7, includeDocumentationItems: false),
            to: fileURL
        )

        XCTAssertThrowsError(try TopologyProjectStore(fileURL: fileURL).load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .malformedPayload
            )
            XCTAssertTrue(
                (error as? TopologyProjectPersistenceError)?.detail.contains(
                    "documentationItemsFieldMissing"
                ) == true
            )
        }
    }

    func testDocumentationItemsPersistInNativeSchemaSixRoundTrip() throws {
        var state = TopologyEditorState()
        state.documentationItems = [
            .text(
                id: uuid("61616161-6161-6161-6161-616161616161"),
                origin: CGPoint(x: 140, y: 90),
                order: 1,
                value: "DNS learning path"
            ),
            .rectangle(
                id: uuid("62626262-6262-6262-6262-626262626262"),
                origin: CGPoint(x: 120, y: 70),
                order: 0
            )
        ]
        state.persistenceRevision = 2
        let fileURL = tempDirectoryURL.appendingPathComponent("documentation-round-trip.json")
        let store = TopologyProjectStore(fileURL: fileURL)

        try store.save(state: state, saveReason: .manualSave)
        let loaded = try store.load()

        XCTAssertEqual(loaded.documentationItems, state.documentationItems.inDeterministicRenderOrder)
        XCTAssertEqual(loaded.persistenceRevision, 2)
        XCTAssertEqual(loaded.workspaceMode, .design)
        XCTAssertNil(loaded.selectedDocumentationItemID)
    }

    func testSyntheticJavaBeanDocumentationFixtureImportsAndRoundTrips() throws {
        let fixture = """
        <?xml version="1.0" encoding="UTF-8"?>
        <java version="17" class="java.beans.XMLDecoder">
         <object class="java.util.LinkedList"></object>
         <object class="java.util.LinkedList"></object>
         <object class="java.util.ArrayList">
          <void method="add"><object class="filius.gui.netzwerksicht.GUIDocuItem">
           <void property="color"><object class="java.awt.Color"><int>10</int><int>20</int><int>30</int><int>255</int></object></void>
           <void property="font"><object class="java.awt.Font"><string>Dialog</string><int>1</int><int>16</int></object></void>
           <void property="height"><int>80</int></void>
           <void property="text"><string>HTTP documentation</string></void>
           <void property="type"><int>2</int></void>
           <void property="width"><int>220</int></void>
           <void property="x"><int>100</int></void>
           <void property="y"><int>60</int></void>
          </object></void>
         </object>
        </java>
        """

        let imported = try TopologyProjectStore.importFiliusConfigurationXML(Data(fixture.utf8))
        XCTAssertEqual(imported.report.importedDocumentationItemCount, 1)
        XCTAssertEqual(imported.state.documentationItems.first?.text, "HTTP documentation")
        XCTAssertEqual(imported.state.documentationItems.first?.fontSize, 16)
        XCTAssertEqual(imported.state.documentationItems.first?.isBold, true)

        let exported = try TopologyProjectStore.exportFiliusConfigurationXMLWithReport(from: imported.state)
        XCTAssertEqual(exported.report.exportedDocumentationItemCount, 1)
        let reopened = try TopologyProjectStore.importFiliusConfigurationXML(exported.data)
        XCTAssertEqual(reopened.state.documentationItems.first?.text, "HTTP documentation")
        XCTAssertEqual(reopened.state.documentationItems.first?.frame, imported.state.documentationItems.first?.frame)
    }

    func testLoadRejectsUnsupportedSchemaVersion() throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("unsupported-schema.json")
        try writeJSON(
            envelopeDictionary(schemaVersion: 99),
            to: fileURL
        )

        let store = TopologyProjectStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .unsupportedSchemaVersion
            )
        }
    }

    func testLoadRejectsCorruptedJSONPayload() throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("corrupted.json")
        try Data("{not-json".utf8).write(to: fileURL)

        let store = TopologyProjectStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .corruptedPayload
            )
        }
    }

    func testLoadRejectsMalformedEnvelopeMissingRequiredKey() throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("missing-payload.json")

        var malformed = envelopeDictionary()
        malformed.removeValue(forKey: "payload")
        try writeJSON(malformed, to: fileURL)

        let store = TopologyProjectStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .malformedPayload
            )
        }
    }

    func testLoadLegacyPayloadWithoutRecoveryMetadataDefaultsSafely() throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("legacy-without-recovery-metadata.json")

        var legacyEnvelope = envelopeDictionary()
        legacyEnvelope.removeValue(forKey: "saveReason")

        if var payload = legacyEnvelope["payload"] as? [String: Any] {
            payload.removeValue(forKey: "persistenceRevision")
            legacyEnvelope["payload"] = payload
        }

        try writeJSON(legacyEnvelope, to: fileURL)

        let store = TopologyProjectStore(fileURL: fileURL)
        let loaded = try store.load()

        XCTAssertEqual(loaded.persistenceRevision, 0)
        XCTAssertEqual(loaded.lastPersistedRevision, 0)
    }

    func testLoadRejectsUnknownEnvelopeField() throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("unknown-envelope-field.json")
        try writeJSON(
            envelopeDictionary(extraEnvelopeFields: ["unexpected": true]),
            to: fileURL
        )

        let store = TopologyProjectStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .malformedPayload
            )
        }
    }

    func testLoadRejectsEmptyFormatIdentifier() throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("empty-format.json")
        try writeJSON(envelopeDictionary(format: "   "), to: fileURL)

        let store = TopologyProjectStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .invalidFormat
            )
        }
    }

    func testLoadRejectsUnknownFormatIdentifier() throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("unknown-format.json")
        try writeJSON(envelopeDictionary(format: "com.filius.legacy.project"), to: fileURL)

        let store = TopologyProjectStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .unsupportedFormat
            )
        }
    }

    func testLoadLegacyPayloadWithoutInterfaceConfigurationsDerivesJavaDefaults() throws {
        let router = TopologyNode(
            id: uuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            kind: .router,
            position: CGPoint(x: 120, y: 120)
        )
        let gateway = TopologyNode(
            id: uuid("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
            kind: .gateway,
            position: CGPoint(x: 320, y: 120)
        )
        var state = TopologyEditorState()
        state.graph = TopologyGraph(nodes: [router, gateway], links: [])

        let fileURL = tempDirectoryURL.appendingPathComponent("legacy-interface-migration.json")
        let store = TopologyProjectStore(fileURL: fileURL)
        try store.save(state: state, savedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let data = try Data(contentsOf: fileURL)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var payload = try XCTUnwrap(envelope["payload"] as? [String: Any])
        payload.removeValue(forKey: "runtimeInterfaceConfigurations")
        envelope["payload"] = payload
        try writeJSON(envelope, to: fileURL)

        let loaded = try store.load()

        XCTAssertEqual(
            loaded.runtimeInterfaceConfigurations[
                TopologyRuntimeInterfaceKey(nodeID: router.id, portID: router.ports[0].id)
            ],
            TopologyRuntimeInterfaceConfiguration(
                ipAddress: "192.168.0.10",
                subnetMask: "255.255.255.0"
            )
        )
        XCTAssertEqual(
            loaded.runtimeInterfaceConfigurations[
                TopologyRuntimeInterfaceKey(nodeID: gateway.id, portID: gateway.ports[0].id)
            ],
            TopologyRuntimeInterfaceConfiguration(
                ipAddress: "42.0.0.10",
                subnetMask: "255.0.0.0"
            )
        )
        XCTAssertEqual(
            loaded.runtimeInterfaceConfigurations[
                TopologyRuntimeInterfaceKey(nodeID: gateway.id, portID: gateway.ports[1].id)
            ],
            TopologyRuntimeInterfaceConfiguration(
                ipAddress: "192.168.0.10",
                subnetMask: "255.255.255.0"
            )
        )
    }

    func testLoadLegacyPayloadWithoutManualRouteTablesDefaultsToEmpty() throws {
        let node = TopologyNode(
            id: uuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            kind: .pc,
            position: CGPoint(x: 120, y: 120)
        )
        var state = TopologyEditorState()
        state.graph = TopologyGraph(nodes: [node], links: [])

        let fileURL = tempDirectoryURL.appendingPathComponent("legacy-manual-routes.json")
        let store = TopologyProjectStore(fileURL: fileURL)
        try store.save(state: state, savedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let data = try Data(contentsOf: fileURL)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var payload = try XCTUnwrap(envelope["payload"] as? [String: Any])
        payload.removeValue(forKey: "runtimeManualRouteTables")
        payload.removeValue(forKey: "runtimeRIPEnabledNodeIDs")
        envelope["payload"] = payload
        try writeJSON(envelope, to: fileURL)

        let loaded = try store.load()

        XCTAssertTrue(loaded.runtimeManualRoutesByNodeID.isEmpty)
        XCTAssertTrue(loaded.runtimeRIPEnabledByNodeID.isEmpty)
    }

    func testManualRouteTableSnapshotValidationRejectsDuplicateUnknownAndSwitchOwners() throws {
        let pc = TopologyNode(
            id: uuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            kind: .pc,
            position: CGPoint(x: 20, y: 20)
        )
        let networkSwitch = TopologyNode(
            id: uuid("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
            kind: .networkSwitch,
            position: CGPoint(x: 120, y: 20)
        )
        let route = TopologyRuntimeManualRouteSnapshot(
            destinationNetwork: "10.0.0.0",
            subnetMask: "255.0.0.0",
            gateway: "192.168.1.1",
            interfaceIPAddress: "192.168.1.2"
        )
        let graph = TopologyGraphSnapshot(graph: TopologyGraph(nodes: [pc, networkSwitch], links: []))
        let viewport = ViewportTransformSnapshot(.identity)

        let duplicate = TopologyProjectSnapshot(
            graph: graph,
            viewport: viewport,
            runtimeDeviceConfigurations: [],
            runtimeManualRouteTables: [
                TopologyRuntimeManualRouteTableSnapshot(nodeID: pc.id, routes: [route]),
                TopologyRuntimeManualRouteTableSnapshot(nodeID: pc.id, routes: [route])
            ],
            runtimeDNSRecords: [],
            runtimeInstalledPrograms: [],
            persistenceRevision: 0
        )
        XCTAssertThrowsError(try duplicate.toEditorState()) { error in
            XCTAssertEqual(error as? TopologyProjectSnapshotValidationError, .duplicateRuntimeManualRouteTable(nodeID: pc.id))
        }

        let unknownNodeID = uuid("cccccccc-cccc-cccc-cccc-cccccccccccc")
        let unknown = TopologyProjectSnapshot(
            graph: graph,
            viewport: viewport,
            runtimeDeviceConfigurations: [],
            runtimeManualRouteTables: [TopologyRuntimeManualRouteTableSnapshot(nodeID: unknownNodeID, routes: [route])],
            runtimeDNSRecords: [],
            runtimeInstalledPrograms: [],
            persistenceRevision: 0
        )
        XCTAssertThrowsError(try unknown.toEditorState()) { error in
            XCTAssertEqual(error as? TopologyProjectSnapshotValidationError, .runtimeManualRouteTableReferencesUnknownNode(nodeID: unknownNodeID))
        }

        let unsupported = TopologyProjectSnapshot(
            graph: graph,
            viewport: viewport,
            runtimeDeviceConfigurations: [],
            runtimeManualRouteTables: [TopologyRuntimeManualRouteTableSnapshot(nodeID: networkSwitch.id, routes: [route])],
            runtimeDNSRecords: [],
            runtimeInstalledPrograms: [],
            persistenceRevision: 0
        )
        XCTAssertThrowsError(try unsupported.toEditorState()) { error in
            XCTAssertEqual(
                error as? TopologyProjectSnapshotValidationError,
                .runtimeManualRouteTableReferencesUnsupportedNodeKind(nodeID: networkSwitch.id, kind: .networkSwitch)
            )
        }
    }

    func testRIPSnapshotValidationRejectsDuplicateUnknownAndNonRouterOwners() throws {
        let router = TopologyNode(
            id: uuid("11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            kind: .router,
            position: CGPoint(x: 20, y: 20)
        )
        let gateway = TopologyNode(
            id: uuid("22222222-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
            kind: .gateway,
            position: CGPoint(x: 120, y: 20)
        )
        let graph = TopologyGraphSnapshot(graph: TopologyGraph(nodes: [router, gateway], links: []))
        let viewport = ViewportTransformSnapshot(.identity)

        func snapshot(_ nodeIDs: [UUID]) -> TopologyProjectSnapshot {
            TopologyProjectSnapshot(
                graph: graph,
                viewport: viewport,
                runtimeDeviceConfigurations: [],
                runtimeRIPEnabledNodeIDs: nodeIDs,
                runtimeDNSRecords: [],
                runtimeInstalledPrograms: [],
                persistenceRevision: 0
            )
        }

        XCTAssertThrowsError(try snapshot([router.id, router.id]).toEditorState()) { error in
            XCTAssertEqual(
                error as? TopologyProjectSnapshotValidationError,
                .duplicateRuntimeRIPConfiguration(nodeID: router.id)
            )
        }

        let unknownNodeID = uuid("33333333-cccc-cccc-cccc-cccccccccccc")
        XCTAssertThrowsError(try snapshot([unknownNodeID]).toEditorState()) { error in
            XCTAssertEqual(
                error as? TopologyProjectSnapshotValidationError,
                .runtimeRIPConfigurationReferencesUnknownNode(nodeID: unknownNodeID)
            )
        }

        XCTAssertThrowsError(try snapshot([gateway.id]).toEditorState()) { error in
            XCTAssertEqual(
                error as? TopologyProjectSnapshotValidationError,
                .runtimeRIPConfigurationReferencesUnsupportedNodeKind(nodeID: gateway.id, kind: .gateway)
            )
        }
    }

    func testLoadRejectsDuplicateRuntimeInterfaceConfigurationEntries() throws {
        let nodeID = uuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        let portID = uuid("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
        let payloadWithDuplicates: [String: Any] = [
            "graph": ["nodes": [], "links": []],
            "viewport": [
                "offset": ["width": 0.0, "height": 0.0],
                "scale": 1.0
            ],
            "runtimeDeviceConfigurations": [],
            "runtimeInterfaceConfigurations": [
                [
                    "nodeID": nodeID.uuidString,
                    "portID": portID.uuidString,
                    "ipAddress": "192.168.0.10",
                    "subnetMask": "255.255.255.0"
                ],
                [
                    "nodeID": nodeID.uuidString,
                    "portID": portID.uuidString,
                    "ipAddress": "192.168.0.11",
                    "subnetMask": "255.255.255.0"
                ]
            ],
            "persistenceRevision": 0
        ]
        let fileURL = tempDirectoryURL.appendingPathComponent("duplicate-runtime-interface-config.json")
        try writeJSON(envelopeDictionary(payload: payloadWithDuplicates), to: fileURL)

        let store = TopologyProjectStore(fileURL: fileURL)
        XCTAssertThrowsError(try store.load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .corruptedPayload
            )
        }
    }

    func testLoadRejectsRuntimeInterfaceConfigurationForUnknownNode() throws {
        let router = TopologyNode(
            id: uuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            kind: .router,
            position: CGPoint(x: 120, y: 120)
        )
        let unknownNodeID = uuid("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
        let fileURL = try writeProjectWithRuntimeInterfaceEntry(
            node: router,
            entryNodeID: unknownNodeID,
            entryPortID: router.ports[0].id,
            filename: "unknown-interface-node.json"
        )

        XCTAssertThrowsError(try TopologyProjectStore(fileURL: fileURL).load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .corruptedPayload
            )
        }
    }

    func testLoadRejectsRuntimeInterfaceConfigurationForUnknownPort() throws {
        let router = TopologyNode(
            id: uuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            kind: .router,
            position: CGPoint(x: 120, y: 120)
        )
        let unknownPortID = uuid("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
        let fileURL = try writeProjectWithRuntimeInterfaceEntry(
            node: router,
            entryNodeID: router.id,
            entryPortID: unknownPortID,
            filename: "unknown-interface-port.json"
        )

        XCTAssertThrowsError(try TopologyProjectStore(fileURL: fileURL).load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .corruptedPayload
            )
        }
    }

    func testLoadRejectsRuntimeInterfaceConfigurationForPCNode() throws {
        let pc = TopologyNode(
            id: uuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            kind: .pc,
            position: CGPoint(x: 120, y: 120)
        )
        let fileURL = try writeProjectWithRuntimeInterfaceEntry(
            node: pc,
            entryNodeID: pc.id,
            entryPortID: pc.ports[0].id,
            filename: "unsupported-interface-node-kind.json"
        )

        XCTAssertThrowsError(try TopologyProjectStore(fileURL: fileURL).load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .corruptedPayload
            )
        }
    }

    func testLoadRejectsDuplicateRuntimeConfigurationEntries() throws {
        let nodeID = uuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        let payloadWithDuplicates: [String: Any] = [
            "graph": [
                "nodes": [],
                "links": []
            ],
            "viewport": [
                "offset": ["width": 0.0, "height": 0.0],
                "scale": 1.0
            ],
            "runtimeDeviceConfigurations": [
                [
                    "nodeID": nodeID.uuidString,
                    "ipAddress": "192.168.0.10",
                    "subnetMask": "255.255.255.0"
                ],
                [
                    "nodeID": nodeID.uuidString,
                    "ipAddress": "192.168.0.11",
                    "subnetMask": "255.255.255.0"
                ]
            ]
        ]

        let fileURL = tempDirectoryURL.appendingPathComponent("duplicate-runtime-config.json")
        try writeJSON(
            envelopeDictionary(payload: payloadWithDuplicates),
            to: fileURL
        )

        let store = TopologyProjectStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .malformedPayload
            )
        }
    }

    func testLoadDirectoryURLReturnsFileReadFailed() throws {
        let directoryURL = tempDirectoryURL.appendingPathComponent("read-directory", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)

        let store = TopologyProjectStore(fileURL: directoryURL)

        XCTAssertThrowsError(try store.load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .fileReadFailed
            )
        }
    }

    func testSaveDirectoryURLReturnsFileWriteFailed() throws {
        let directoryURL = tempDirectoryURL.appendingPathComponent("write-directory", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)

        let store = TopologyProjectStore(fileURL: directoryURL)

        XCTAssertThrowsError(try store.save(state: TopologyEditorState())) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .save,
                expectedCode: .fileWriteFailed
            )
        }
    }

    func testImportFiliusConfigurationXMLMapsSupportedNodeTypes() throws {
        let xml = """
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <java version=\"11.0.17\" class=\"java.beans.XMLDecoder\">
         <string>Filius version: 2.1.0 (11.10.2022)</string>
         <object class=\"java.util.LinkedList\">
          <void method=\"add\">
           <object class=\"filius.gui.netzwerksicht.GUIKnotenItem\">
            <void property=\"typ\"><string>Computer</string></void>
            <void property=\"bounds\">
             <object class=\"java.awt.Rectangle\">
              <void class=\"java.awt.Rectangle\" method=\"getField\"><string>x</string><void method=\"set\"><int>10</int></void></void>
              <void class=\"java.awt.Rectangle\" method=\"getField\"><string>y</string><void method=\"set\"><int>20</int></void></void>
             </object>
            </void>
           </object>
          </void>
          <void method=\"add\">
           <object class=\"filius.gui.netzwerksicht.GUIKnotenItem\">
            <void property=\"typ\"><string>Switch / WLAN</string></void>
            <void property=\"bounds\">
             <object class=\"java.awt.Rectangle\">
              <void class=\"java.awt.Rectangle\" method=\"getField\"><string>x</string><void method=\"set\"><int>100</int></void></void>
              <void class=\"java.awt.Rectangle\" method=\"getField\"><string>y</string><void method=\"set\"><int>200</int></void></void>
             </object>
            </void>
           </object>
          </void>
          <void method=\"add\">
           <object class=\"filius.gui.netzwerksicht.GUIKnotenItem\">
            <void property=\"typ\"><string>Router</string></void>
            <void property=\"bounds\">
             <object class=\"java.awt.Rectangle\">
              <void class=\"java.awt.Rectangle\" method=\"getField\"><string>x</string><void method=\"set\"><int>300</int></void></void>
              <void class=\"java.awt.Rectangle\" method=\"getField\"><string>y</string><void method=\"set\"><int>400</int></void></void>
             </object>
            </void>
           </object>
          </void>
         </object>
        </java>
        """

        let result = try TopologyProjectStore.importFiliusConfigurationXML(Data(xml.utf8))

        XCTAssertEqual(result.report.filiusVersion, "Filius version: 2.1.0 (11.10.2022)")
        XCTAssertEqual(result.report.importedNodeCount, 3)
        XCTAssertEqual(result.report.skippedNodeCount, 0)
        XCTAssertEqual(result.report.warnings, [])

        XCTAssertEqual(result.state.graph.nodes.count, 3)
        XCTAssertEqual(result.state.graph.nodes[0].kind, .pc)
        XCTAssertEqual(result.state.graph.nodes[0].position, CGPoint(x: 10, y: 20))
        XCTAssertEqual(result.state.graph.nodes[1].kind, .networkSwitch)
        XCTAssertEqual(result.state.graph.nodes[1].position, CGPoint(x: 100, y: 200))
        XCTAssertEqual(result.state.graph.nodes[2].kind, .router)
        XCTAssertEqual(result.state.graph.nodes[2].position, CGPoint(x: 300, y: 400))
        XCTAssertTrue(result.state.graph.links.isEmpty)
    }

    func testImportFiliusConfigurationXMLRestoresEndpointNetworkConfiguration() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <java version="11.0.17" class="java.beans.XMLDecoder">
         <string>Filius version: 2.1.0 (endpoint configuration)</string>
         <object class="java.util.LinkedList">
          <void method="add">
           <object class="filius.gui.netzwerksicht.GUIKnotenItem">
            <void property="bounds"><object class="java.awt.Rectangle"><int>10</int><int>20</int><int>70</int><int>68</int></object></void>
            <void property="knoten">
             <object class="filius.hardware.knoten.Rechner">
              <void property="netzwerkInterfaces">
               <void index="0">
                <void property="gateway"><string>10.20.0.1</string></void>
                <void property="ip"><string>10.20.30.40</string></void>
                <void property="subnetzMaske"><string>255.255.0.0</string></void>
               </void>
              </void>
             </object>
            </void>
           </object>
          </void>
         </object>
        </java>
        """

        let result = try TopologyProjectStore.importFiliusConfigurationXML(Data(xml.utf8))
        let nodeID = try XCTUnwrap(result.state.graph.nodes.first?.id)

        XCTAssertEqual(
            result.state.runtimeDeviceConfigurations[nodeID],
            TopologyRuntimeDeviceConfiguration(
                ipAddress: "10.20.30.40",
                subnetMask: "255.255.0.0",
                defaultGateway: "10.20.0.1"
            )
        )
    }

    func testImportFiliusConfigurationXMLFallsBackToKnotenClassWhenTypeLabelMissing() throws {
        let xml = """
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <java version=\"11.0.17\" class=\"java.beans.XMLDecoder\">
         <string>Filius version: 2.1.0 (legacy class fallback)</string>
         <object class=\"java.util.LinkedList\">
          <void method=\"add\">
           <object class=\"filius.gui.netzwerksicht.GUIKnotenItem\">
            <void property=\"knoten\"><object class=\"filius.hardware.knoten.Rechner\"/></void>
            <void property=\"bounds\">
             <object class=\"java.awt.Rectangle\">
              <void class=\"java.awt.Rectangle\" method=\"getField\"><string>x</string><void method=\"set\"><int>11</int></void></void>
              <void class=\"java.awt.Rectangle\" method=\"getField\"><string>y</string><void method=\"set\"><int>22</int></void></void>
             </object>
            </void>
           </object>
          </void>
          <void method=\"add\">
           <object class=\"filius.gui.netzwerksicht.GUIKnotenItem\">
            <void property=\"knoten\"><object class=\"filius.hardware.knoten.Notebook\"/></void>
            <void property=\"bounds\">
             <object class=\"java.awt.Rectangle\">
              <void class=\"java.awt.Rectangle\" method=\"getField\"><string>x</string><void method=\"set\"><int>33</int></void></void>
              <void class=\"java.awt.Rectangle\" method=\"getField\"><string>y</string><void method=\"set\"><int>44</int></void></void>
             </object>
            </void>
           </object>
          </void>
          <void method=\"add\">
           <object class=\"filius.gui.netzwerksicht.GUIKnotenItem\">
            <void property=\"knoten\"><object class=\"filius.hardware.knoten.Switch\"/></void>
            <void property=\"bounds\">
             <object class=\"java.awt.Rectangle\">
              <void class=\"java.awt.Rectangle\" method=\"getField\"><string>x</string><void method=\"set\"><int>55</int></void></void>
              <void class=\"java.awt.Rectangle\" method=\"getField\"><string>y</string><void method=\"set\"><int>66</int></void></void>
             </object>
            </void>
           </object>
          </void>
         </object>
        </java>
        """

        let result = try TopologyProjectStore.importFiliusConfigurationXML(Data(xml.utf8))

        XCTAssertEqual(result.report.filiusVersion, "Filius version: 2.1.0 (legacy class fallback)")
        XCTAssertEqual(result.report.importedNodeCount, 3)
        XCTAssertEqual(result.report.skippedNodeCount, 0)
        XCTAssertEqual(result.report.warnings, [])
        XCTAssertEqual(result.state.graph.nodes.map(\.kind), [.pc, .notebook, .networkSwitch])
        XCTAssertEqual(result.state.graph.nodes.map(\.position), [CGPoint(x: 11, y: 22), CGPoint(x: 33, y: 44), CGPoint(x: 55, y: 66)])
    }

    func testImportFiliusConfigurationXMLMapsRouterAndGatewayKnotenClasses() throws {
        let xml = """
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <java version=\"11.0.17\" class=\"java.beans.XMLDecoder\">
         <object class=\"java.util.LinkedList\">
          <void method=\"add\">
           <object class=\"filius.gui.netzwerksicht.GUIKnotenItem\">
            <void property=\"knoten\"><object class=\"filius.hardware.knoten.Rechner\"/></void>
            <void property=\"bounds\">
             <object class=\"java.awt.Rectangle\">
              <void class=\"java.awt.Rectangle\" method=\"getField\"><string>x</string><void method=\"set\"><int>5</int></void></void>
              <void class=\"java.awt.Rectangle\" method=\"getField\"><string>y</string><void method=\"set\"><int>6</int></void></void>
             </object>
            </void>
           </object>
          </void>
          <void method=\"add\">
           <object class=\"filius.gui.netzwerksicht.GUIKnotenItem\">
            <void property=\"knoten\"><object class=\"filius.hardware.knoten.Vermittlungsrechner\"/></void>
            <void property=\"bounds\">
             <object class=\"java.awt.Rectangle\">
              <void class=\"java.awt.Rectangle\" method=\"getField\"><string>x</string><void method=\"set\"><int>7</int></void></void>
              <void class=\"java.awt.Rectangle\" method=\"getField\"><string>y</string><void method=\"set\"><int>8</int></void></void>
             </object>
            </void>
           </object>
          </void>
          <void method=\"add\">
           <object class=\"filius.gui.netzwerksicht.GUIKnotenItem\">
            <void property=\"knoten\"><object class=\"filius.hardware.knoten.Gateway\"/></void>
            <void property=\"bounds\">
             <object class=\"java.awt.Rectangle\">
              <void class=\"java.awt.Rectangle\" method=\"getField\"><string>x</string><void method=\"set\"><int>9</int></void></void>
              <void class=\"java.awt.Rectangle\" method=\"getField\"><string>y</string><void method=\"set\"><int>10</int></void></void>
             </object>
            </void>
           </object>
          </void>
         </object>
        </java>
        """

        let result = try TopologyProjectStore.importFiliusConfigurationXML(Data(xml.utf8))

        XCTAssertEqual(result.report.importedNodeCount, 3)
        XCTAssertEqual(result.report.skippedNodeCount, 0)
        XCTAssertEqual(result.report.warnings, [])
        XCTAssertEqual(result.state.graph.nodes.map(\.kind), [.pc, .router, .gateway])
        XCTAssertEqual(
            result.state.graph.nodes.map(\.position),
            [CGPoint(x: 5, y: 6), CGPoint(x: 7, y: 8), CGPoint(x: 9, y: 10)]
        )
        XCTAssertEqual(result.state.graph.nodes[1].ports.map(\.label), ["rt1"])
        XCTAssertEqual(result.state.graph.nodes[2].ports.map(\.label), ["wan0", "lan0"])
    }

    func testImportFiliusConfigurationXMLPrefersTypeLabelOverKnotenClassWhenTypePresent() throws {
        let xml = """
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <java version=\"11.0.17\" class=\"java.beans.XMLDecoder\">
         <object class=\"java.util.LinkedList\">
          <void method=\"add\">
           <object class=\"filius.gui.netzwerksicht.GUIKnotenItem\">
            <void property=\"typ\"><string>Router</string></void>
            <void property=\"knoten\"><object class=\"filius.hardware.knoten.Rechner\"/></void>
            <void property=\"bounds\">
             <object class=\"java.awt.Rectangle\">
              <void class=\"java.awt.Rectangle\" method=\"getField\"><string>x</string><void method=\"set\"><int>1</int></void></void>
              <void class=\"java.awt.Rectangle\" method=\"getField\"><string>y</string><void method=\"set\"><int>2</int></void></void>
             </object>
            </void>
           </object>
          </void>
         </object>
        </java>
        """

        let result = try TopologyProjectStore.importFiliusConfigurationXML(Data(xml.utf8))

        XCTAssertEqual(result.report.importedNodeCount, 1)
        XCTAssertEqual(result.report.skippedNodeCount, 0)
        XCTAssertEqual(result.report.warnings, [])
        XCTAssertEqual(result.state.graph.nodes.map(\.kind), [.router])
        XCTAssertEqual(result.state.graph.nodes.map(\.position), [CGPoint(x: 1, y: 2)])
    }

    func testImportFiliusConfigurationXMLRejectsMalformedPayload() {
        XCTAssertThrowsError(try TopologyProjectStore.importFiliusConfigurationXML(Data("<java".utf8))) { error in
            guard let compatibilityError = error as? TopologyFLSCompatibilityError else {
                XCTFail("Expected TopologyFLSCompatibilityError, got \(type(of: error))")
                return
            }

            XCTAssertEqual(compatibilityError.code, .unsupportedConfigurationStructure)
            XCTAssertTrue(compatibilityError.detail.contains("Unterminated XML tag or attribute value"))
        }
    }

    func testImportFiliusConfigurationXMLRejectsNonXMLPayload() {
        XCTAssertThrowsError(try TopologyProjectStore.importFiliusConfigurationXML(Data("definitely-not-xml".utf8))) { error in
            guard let compatibilityError = error as? TopologyFLSCompatibilityError else {
                XCTFail("Expected TopologyFLSCompatibilityError, got \(type(of: error))")
                return
            }

            XCTAssertEqual(compatibilityError.code, .unsupportedConfigurationStructure)
            XCTAssertTrue(compatibilityError.detail.contains("missing a balanced Java root"))
        }
    }

    func testImportFiliusConfigurationXMLRejectsUnsupportedStructure() {
        let xml = """
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <configuration>
          <nodeList />
        </configuration>
        """

        XCTAssertThrowsError(try TopologyProjectStore.importFiliusConfigurationXML(Data(xml.utf8))) { error in
            guard let compatibilityError = error as? TopologyFLSCompatibilityError else {
                XCTFail("Expected TopologyFLSCompatibilityError, got \(type(of: error))")
                return
            }

            XCTAssertEqual(compatibilityError.code, .unsupportedConfigurationStructure)
            XCTAssertTrue(compatibilityError.detail.contains("Expected a Java XMLDecoder root element"))
        }
    }

    func testImportFiliusConfigurationXMLRestoresJavaXMLEncoderManualRouteOrder() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <java version="24" class="java.beans.XMLDecoder">
         <string>Filius version: 2.1.0 (manual route fixture)</string>
         <object class="java.util.LinkedList">
          <void method="add">
           <object class="filius.gui.netzwerksicht.GUIKnotenItem">
            <void property="typ"><string>Vermittlungsrechner</string></void>
            <void property="imageLabel">
             <object class="filius.gui.netzwerksicht.JSidebarButton">
              <void property="bounds"><object class="java.awt.Rectangle"><int>40</int><int>80</int><int>70</int><int>68</int></object></void>
             </object>
            </void>
            <void property="knoten">
             <object class="filius.hardware.knoten.Vermittlungsrechner">
              <void property="systemSoftware">
               <void property="weiterleitungstabelle">
                <void property="manuelleTabelle">
                 <void method="add">
                  <array class="java.lang.String" length="4">
                   <void index="0"><string>10.0.0.0</string></void>
                   <void index="1"><string>255.0.0.0</string></void>
                   <void index="2"><string>192.168.1.2</string></void>
                   <void index="3"><string>192.168.1.1</string></void>
                  </array>
                 </void>
                 <void method="add">
                  <array class="java.lang.String" length="4">
                   <void index="2"><string>192.168.1.3</string></void>
                   <void index="0"><string>10.20.0.0</string></void>
                   <void index="3"><string>192.168.1.1</string></void>
                   <void index="1"><string>255.255.0.0</string></void>
                  </array>
                 </void>
                </void>
               </void>
              </void>
             </object>
            </void>
           </object>
          </void>
         </object>
         <object class="java.util.LinkedList"/>
        </java>
        """

        let imported = try TopologyProjectStore.importFiliusConfigurationXML(Data(xml.utf8))
        let node = try XCTUnwrap(imported.state.graph.nodes.first)

        XCTAssertEqual(
            imported.state.runtimeManualRoutesByNodeID[node.id],
            [
                TopologyRuntimeManualRoute(destinationNetwork: "10.0.0.0", subnetMask: "255.0.0.0", gateway: "192.168.1.2", interfaceIPAddress: "192.168.1.1"),
                TopologyRuntimeManualRoute(destinationNetwork: "10.20.0.0", subnetMask: "255.255.0.0", gateway: "192.168.1.3", interfaceIPAddress: "192.168.1.1")
            ]
        )
        XCTAssertEqual(imported.report.warnings, [])
    }

    func testExportFiliusConfigurationXMLWritesOnlyManualRoutesAndRoundTripsOrder() throws {
        let router = TopologyNode(
            id: uuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            kind: .router,
            position: CGPoint(x: 80, y: 120)
        )
        let routes = [
            TopologyRuntimeManualRoute(destinationNetwork: "10.0.0.0", subnetMask: "255.0.0.0", gateway: "192.168.1.2", interfaceIPAddress: "192.168.1.1"),
            TopologyRuntimeManualRoute(destinationNetwork: "10.20.0.0", subnetMask: "255.255.0.0", gateway: "192.168.1.3", interfaceIPAddress: "192.168.1.1")
        ]
        var state = TopologyEditorState()
        state.graph = TopologyGraph(nodes: [router], links: [])
        state.runtimeManualRoutesByNodeID[router.id] = routes

        let exported = try TopologyProjectStore.exportFiliusConfigurationXML(from: state)
        let exportedXML = try XCTUnwrap(String(data: exported, encoding: .utf8))

        XCTAssertTrue(exportedXML.contains("property=\"manuelleTabelle\""))
        XCTAssertTrue(exportedXML.contains("<array class=\"java.lang.String\" length=\"4\">"))
        XCTAssertFalse(exportedXML.contains("<string>127.0.0.0</string>"))

        let imported = try TopologyProjectStore.importFiliusConfigurationXML(exported)
        let importedRouter = try XCTUnwrap(imported.state.graph.nodes.first(where: { $0.kind == .router }))
        XCTAssertEqual(imported.state.runtimeManualRoutesByNodeID[importedRouter.id], routes)
    }


    func testFiliusConfigurationXMLRoundTripsRouterRIPEnabledAndIgnoresGatewayRIP() throws {
        let router = TopologyNode(
            id: uuid("abababab-abab-abab-abab-abababababab"),
            kind: .router,
            position: CGPoint(x: 80, y: 120)
        )
        let gateway = TopologyNode(
            id: uuid("cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd"),
            kind: .gateway,
            position: CGPoint(x: 280, y: 120)
        )
        var state = TopologyEditorState()
        state.graph = TopologyGraph(nodes: [router, gateway], links: [])
        state.runtimeRIPEnabledByNodeID = [router.id: true, gateway.id: true]

        let exported = try TopologyProjectStore.exportFiliusConfigurationXML(from: state)
        let exportedXML = try XCTUnwrap(String(data: exported, encoding: .utf8))
        XCTAssertEqual(exportedXML.components(separatedBy: "property=\"ripEnabled\"").count - 1, 1)
        XCTAssertTrue(exportedXML.contains("<boolean>true</boolean>"))

        let imported = try TopologyProjectStore.importFiliusConfigurationXML(exported)
        let importedRouter = try XCTUnwrap(imported.state.graph.nodes.first(where: { $0.kind == .router }))
        let importedGateway = try XCTUnwrap(imported.state.graph.nodes.first(where: { $0.kind == .gateway }))
        XCTAssertEqual(imported.state.runtimeRIPEnabledByNodeID[importedRouter.id], true)
        XCTAssertNil(imported.state.runtimeRIPEnabledByNodeID[importedGateway.id])
    }

    func testNotebookIdentityPersistsInNativeAndJavaRoundTrips() throws {
        var state = TopologyEditorState()
        let notebook = TopologyNode(
            id: uuid("12121212-3434-5656-7878-909090909090"),
            kind: .notebook,
            displayName: "Notebook Lab",
            position: CGPoint(x: 88, y: 144)
        )
        state.graph = TopologyGraph(nodes: [notebook], links: [])
        state.runtimeDeviceConfigurations[notebook.id] = TopologyRuntimeDeviceConfiguration(
            ipAddress: "10.44.0.8",
            subnetMask: "255.255.255.0"
        )

        let nativeURL = tempDirectoryURL.appendingPathComponent("notebook-roundtrip.json")
        let nativeStore = TopologyProjectStore(fileURL: nativeURL)
        try nativeStore.save(state: state, savedAt: Date(timeIntervalSince1970: 4))
        let nativeState = try nativeStore.load()
        XCTAssertEqual(nativeState.graph.nodes.first?.kind, .notebook)
        XCTAssertEqual(nativeState.graph.nodes.first?.displayName, "Notebook Lab")

        let exported = try TopologyProjectStore.exportFiliusConfigurationXML(from: state)
        let xml = try XCTUnwrap(String(data: exported, encoding: .utf8))
        XCTAssertTrue(xml.contains("filius.hardware.knoten.Notebook"))
        XCTAssertTrue(xml.contains("<string>Notebook</string>"))

        let reopened = try TopologyProjectStore.importFiliusConfigurationXML(exported)
        XCTAssertEqual(reopened.state.graph.nodes.first?.kind, .notebook)
        XCTAssertEqual(reopened.state.graph.nodes.first?.displayName, "Notebook Lab")
        XCTAssertEqual(reopened.state.runtimeDeviceConfigurations[reopened.state.graph.nodes[0].id]?.ipAddress, "10.44.0.8")
    }

    func testExportFiliusConfigurationXMLRoundTripsViaCompatibilityImport() throws {
        var state = TopologyEditorState()
        state.graph = TopologyGraph(
            nodes: [
                TopologyNode(id: uuid("dddddddd-dddd-dddd-dddd-dddddddddddd"), kind: .gateway, position: CGPoint(x: 360, y: 240)),
                TopologyNode(id: uuid("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"), kind: .networkSwitch, position: CGPoint(x: 120, y: 240)),
                TopologyNode(id: uuid("cccccccc-cccc-cccc-cccc-cccccccccccc"), kind: .router, position: CGPoint(x: 240, y: 240)),
                TopologyNode(id: uuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"), kind: .pc, position: CGPoint(x: 32, y: 64))
            ],
            links: []
        )

        let exported = try TopologyProjectStore.exportFiliusConfigurationXML(
            from: state,
            filiusVersion: "Filius version: 2.1.0 (compat export)"
        )

        let exportedXML = try XCTUnwrap(String(data: exported, encoding: .utf8))
        XCTAssertTrue(exportedXML.contains("<string>Vermittlungsrechner</string>"))
        XCTAssertTrue(exportedXML.contains("<string>Gateway</string>"))

        let imported = try TopologyProjectStore.importFiliusConfigurationXML(exported)

        XCTAssertEqual(imported.report.filiusVersion, "Filius version: 2.1.0 (compat export)")
        XCTAssertEqual(imported.state.graph.nodes.count, 4)
        XCTAssertEqual(imported.state.graph.nodes.map(\.kind), [.pc, .networkSwitch, .router, .gateway])
        XCTAssertEqual(
            imported.state.graph.nodes.map(\.position),
            [CGPoint(x: 32, y: 64), CGPoint(x: 120, y: 240), CGPoint(x: 240, y: 240), CGPoint(x: 360, y: 240)]
        )
        XCTAssertEqual(imported.report.skippedNodeCount, 0)
        XCTAssertEqual(imported.report.warnings, [])
    }

    func testFiliusCompatibilityRoundTripPreservesImportedHardwareName() throws {
        var state = TopologyEditorState()
        let node = TopologyNode(
            id: uuid("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"),
            kind: .pc,
            displayName: "Labor & Client",
            position: CGPoint(x: 32, y: 64)
        )
        state.graph = TopologyGraph(nodes: [node], links: [])

        let exported = try TopologyProjectStore.exportFiliusConfigurationXML(from: state)
        let exportedXML = try XCTUnwrap(String(data: exported, encoding: .utf8))
        XCTAssertTrue(exportedXML.contains("<void property=\"name\"><string>Labor &amp; Client</string></void>"))

        let imported = try TopologyProjectStore.importFiliusConfigurationXML(exported)

        XCTAssertEqual(imported.state.graph.nodes.first?.displayName, "Labor & Client")
        XCTAssertEqual(imported.report.warnings, [])
    }

    func testExportFiliusConfigurationXMLRoundTripsLinksAndInterfaceConfigurations() throws {
        let pcA = TopologyNode(
            id: uuid("10101010-1010-1010-1010-101010101010"),
            kind: .pc,
            position: CGPoint(x: 20, y: 40)
        )
        let networkSwitch = TopologyNode(
            id: uuid("20202020-2020-2020-2020-202020202020"),
            kind: .networkSwitch,
            position: CGPoint(x: 160, y: 40)
        )
        let router = TopologyNode(
            id: uuid("30303030-3030-3030-3030-303030303030"),
            kind: .router,
            position: CGPoint(x: 300, y: 40),
            ports: [
                TopologyPortMetadata(id: uuid("31313131-3131-3131-3131-313131313131"), label: "rt1"),
                TopologyPortMetadata(id: uuid("32323232-3232-3232-3232-323232323232"), label: "rt2")
            ]
        )
        let pcB = TopologyNode(
            id: uuid("40404040-4040-4040-4040-404040404040"),
            kind: .pc,
            position: CGPoint(x: 440, y: 40)
        )

        var state = TopologyEditorState()
        state.graph = TopologyGraph(
            nodes: [pcA, networkSwitch, router, pcB],
            links: [
                TopologyLink(
                    sourceNodeID: pcA.id,
                    sourcePortID: pcA.ports[0].id,
                    targetNodeID: networkSwitch.id,
                    targetPortID: networkSwitch.ports[0].id
                ),
                TopologyLink(
                    sourceNodeID: networkSwitch.id,
                    sourcePortID: networkSwitch.ports[1].id,
                    targetNodeID: router.id,
                    targetPortID: router.ports[0].id
                ),
                TopologyLink(
                    sourceNodeID: router.id,
                    sourcePortID: router.ports[1].id,
                    targetNodeID: pcB.id,
                    targetPortID: pcB.ports[0].id
                )
            ]
        )
        state.runtimeDeviceConfigurations[pcA.id] = TopologyRuntimeDeviceConfiguration(
            ipAddress: "10.0.0.20",
            subnetMask: "255.255.255.0",
            defaultGateway: "10.0.0.1"
        )
        state.runtimeDeviceConfigurations[pcB.id] = TopologyRuntimeDeviceConfiguration(
            ipAddress: "10.0.1.20",
            subnetMask: "255.255.255.0",
            defaultGateway: "10.0.1.1"
        )
        state.runtimeInterfaceConfigurations[
            TopologyRuntimeInterfaceKey(nodeID: router.id, portID: router.ports[0].id)
        ] = TopologyRuntimeInterfaceConfiguration(ipAddress: "10.0.0.1", subnetMask: "255.255.255.0")
        state.runtimeInterfaceConfigurations[
            TopologyRuntimeInterfaceKey(nodeID: router.id, portID: router.ports[1].id)
        ] = TopologyRuntimeInterfaceConfiguration(ipAddress: "10.0.1.1", subnetMask: "255.255.255.0")

        let exported = try TopologyProjectStore.exportFiliusConfigurationXML(from: state)
        let exportedXML = try XCTUnwrap(String(data: exported, encoding: .utf8))
        XCTAssertTrue(exportedXML.contains("<object idref=\"Port"))
        XCTAssertTrue(exportedXML.contains("<object class=\"filius.hardware.NetzwerkInterface\">"))

        let imported = try TopologyProjectStore.importFiliusConfigurationXML(exported)

        XCTAssertEqual(imported.report.importedNodeCount, 4)
        XCTAssertEqual(imported.report.importedLinkCount, 3)
        XCTAssertEqual(imported.report.warnings, [])
        XCTAssertEqual(imported.state.graph.links.count, 3)
        XCTAssertEqual(imported.state.graph.nodes.first(where: { $0.kind == .networkSwitch })?.ports.count, 24)

        let importedRouter = try XCTUnwrap(imported.state.graph.nodes.first(where: { $0.kind == .router }))
        XCTAssertEqual(importedRouter.ports.map(\.label), ["rt1", "rt2"])
        let importedRouterConfigurations = importedRouter.ports.compactMap { port in
            imported.state.runtimeInterfaceConfigurations[
                TopologyRuntimeInterfaceKey(nodeID: importedRouter.id, portID: port.id)
            ]
        }
        XCTAssertEqual(
            Set(importedRouterConfigurations.map { "\($0.ipAddress)|\($0.subnetMask)" }),
            Set(["10.0.0.1|255.255.255.0", "10.0.1.1|255.255.255.0"])
        )
        XCTAssertEqual(
            Set(imported.state.runtimeDeviceConfigurations.values.map {
                "\($0.ipAddress)|\($0.subnetMask)|\($0.defaultGateway)"
            }),
            Set([
                "10.0.0.20|255.255.255.0|10.0.0.1",
                "10.0.1.20|255.255.255.0|10.0.1.1"
            ])
        )
    }

    func testSampleFLSWorkflowImportEditExportReimport() throws {
        let fixtureData = try loadSampleFLSFixture(named: "einfaches_rechnernetz_komplett.konfiguration.xml")
        let imported = try TopologyProjectStore.importFiliusConfigurationXML(fixtureData)

        XCTAssertEqual(imported.report.importedNodeCount, 12)
        XCTAssertEqual(imported.report.skippedNodeCount, 0)
        XCTAssertEqual(imported.report.warnings, [])
        XCTAssertEqual(
            Set(imported.state.graph.nodes.map(\.displayName)),
            Set([
                "Rechner 1", "Rechner 2", "Rechner 3", "Rechner 4", "Server",
                "Switch 1", "Switch 2", "Switch 3",
                "Notebook 1", "Notebook 2", "Notebook 3", "Notebook 4"
            ])
        )

        var editedState = imported.state
        let addedNode = TopologyNode(
            id: uuid("99999999-9999-9999-9999-999999999999"),
            kind: .networkSwitch,
            position: CGPoint(x: 640, y: 360)
        )
        editedState.graph.appendNode(addedNode)

        let exported = try TopologyProjectStore.exportFiliusConfigurationXML(
            from: editedState,
            filiusVersion: imported.report.filiusVersion ?? "Filius version: 2.1.0 (fixture workflow)"
        )

        let reimported = try TopologyProjectStore.importFiliusConfigurationXML(exported)

        XCTAssertEqual(reimported.report.importedNodeCount, imported.report.importedNodeCount + 1)
        XCTAssertEqual(reimported.report.skippedNodeCount, 0)
        XCTAssertEqual(reimported.report.warnings, [])

        var expectedNodeSemantics = semanticNodeSignature(imported.state.graph.nodes)
        expectedNodeSemantics.append("networkSwitch@640x360")
        expectedNodeSemantics.sort()

        XCTAssertEqual(semanticNodeSignature(reimported.state.graph.nodes), expectedNodeSemantics)
        XCTAssertEqual(
            Set(reimported.state.graph.nodes.map(\.displayName)),
            Set(imported.state.graph.nodes.map(\.displayName)).union([addedNode.displayName])
        )
    }

    func testSampleFLSImportMapsLegacyRouterClassWithoutWarnings() throws {
        let fixtureData = try loadSampleFLSFixture(named: "zwei_rechnernetze_komplett.konfiguration.xml")

        let result = try TopologyProjectStore.importFiliusConfigurationXML(fixtureData)

        XCTAssertEqual(result.report.importedNodeCount, 6)
        XCTAssertEqual(result.report.importedLinkCount, 5)
        XCTAssertEqual(result.report.skippedNodeCount, 0)
        XCTAssertEqual(result.report.warnings, [])
        XCTAssertEqual(result.state.graph.links.count, 5)

        let importedKinds = result.state.graph.nodes.reduce(into: [String: Int]()) { partialResult, node in
            partialResult[node.kind.rawValue, default: 0] += 1
        }
        XCTAssertEqual(importedKinds, ["pc": 1, "notebook": 2, "networkSwitch": 2, "router": 1])
        XCTAssertTrue(
            result.state.graph.nodes
                .filter { $0.kind == .networkSwitch }
                .allSatisfy { $0.ports.count == 24 }
        )

        let importedRouter = try XCTUnwrap(result.state.graph.nodes.first(where: { $0.kind == .router }))
        XCTAssertEqual(importedRouter.displayName, "Vermittlungsrechner")
        XCTAssertEqual(importedRouter.ports.map(\.label), ["rt1", "rt2"])
        XCTAssertEqual(
            Set(importedRouter.ports.compactMap { port in
                result.state.runtimeInterfaceConfigurations[
                    TopologyRuntimeInterfaceKey(nodeID: importedRouter.id, portID: port.id)
                ].map { "\($0.ipAddress)|\($0.subnetMask)" }
            }),
            Set(["141.99.1.1|255.255.255.0", "141.99.2.1|255.255.255.0"])
        )

        let importedConfigurations = Set(result.state.runtimeDeviceConfigurations.values.map { configuration in
            "\(configuration.ipAddress)|\(configuration.subnetMask)|\(configuration.defaultGateway)"
        })
        XCTAssertEqual(
            importedConfigurations,
            Set([
                "141.99.2.10|255.255.255.0|141.99.2.1",
                "141.99.1.10|255.255.255.0|141.99.1.1",
                "141.99.1.11|255.255.255.0|"
            ])
        )
    }

    func testSampleFLSFixtureLoaderFailsForMissingFixture() {
        XCTAssertThrowsError(try loadSampleFLSFixture(named: "does-not-exist.konfiguration.xml")) { error in
            guard case let FixtureLoadError.missingFixture(relativePath, absolutePath) = error else {
                XCTFail("Expected missingFixture error, got \(error)")
                return
            }

            XCTAssertEqual(relativePath, "ios/FiliusPadTests/Fixtures/FLS/does-not-exist.konfiguration.xml")
            XCTAssertTrue(absolutePath.hasSuffix(relativePath))
        }
    }

    func testSampleFLSFixtureMalformedXMLFailsWithCompatibilityError() throws {
        let fixtureData = try loadSampleFLSFixture(named: "einfaches_rechnernetz_komplett.konfiguration.xml")
        let fixtureXML = try XCTUnwrap(String(data: fixtureData, encoding: .utf8))
        let malformedFixtureXML = fixtureXML.replacingOccurrences(of: "</java>", with: "")

        XCTAssertThrowsError(try TopologyProjectStore.importFiliusConfigurationXML(Data(malformedFixtureXML.utf8))) { error in
            guard let compatibilityError = error as? TopologyFLSCompatibilityError else {
                XCTFail("Expected TopologyFLSCompatibilityError, got \(type(of: error))")
                return
            }

            XCTAssertEqual(compatibilityError.code, .unsupportedConfigurationStructure)
            XCTAssertTrue(compatibilityError.detail.contains("missing a balanced Java root"))
        }
    }

    func testNativeSnapshotDHCPServerMissingFieldsDecodeToJavaDefaults() throws {
        var state = TopologyEditorState()
        let node = TopologyNode(
            id: uuid("77777777-7777-7777-7777-777777777777"),
            kind: .pc,
            position: CGPoint(x: 40, y: 40)
        )
        state.graph = TopologyGraph(nodes: [node], links: [])
        state.runtimeDHCPServerConfigurationsByNodeID[node.id] = TopologyDHCPServerConfiguration(isActive: true)

        let fileURL = tempDirectoryURL.appendingPathComponent("legacy-dhcp-server.json")
        let store = TopologyProjectStore(fileURL: fileURL)
        try store.save(state: state, savedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let data = try Data(contentsOf: fileURL)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var payload = try XCTUnwrap(envelope["payload"] as? [String: Any])
        payload["runtimeDHCPServerConfigurations"] = [["nodeID": node.id.uuidString]]
        envelope["payload"] = payload
        try writeJSON(envelope, to: fileURL)

        let loaded = try store.load()
        XCTAssertEqual(
            loaded.runtimeDHCPServerConfigurationsByNodeID[node.id],
            TopologyDHCPServerConfiguration()
        )
    }

    func testFiliusDHCPPropertiesRoundTripPreservesOrderingAndInvalidPersistedRows() throws {
        var state = TopologyEditorState()
        let node = TopologyNode(
            id: uuid("88888888-8888-8888-8888-888888888888"),
            kind: .pc,
            position: CGPoint(x: 80, y: 120)
        )
        state.graph = TopologyGraph(nodes: [node], links: [])
        state.runtimeDeviceConfigurations[node.id] = TopologyRuntimeDeviceConfiguration(
            ipAddress: "10.44.0.10",
            subnetMask: "255.255.255.0",
            defaultGateway: "10.44.0.1",
            dnsServer: "10.44.0.53"
        )
        state.runtimeDHCPClientConfigurationsByNodeID[node.id] = TopologyDHCPClientConfiguration(isEnabled: true)
        state.runtimeDHCPServerConfigurationsByNodeID[node.id] = TopologyDHCPServerConfiguration(
            isActive: true,
            lowerBoundIPAddress: "10.44.0.20",
            upperBoundIPAddress: "10.44.0.30",
            gatewayIPAddress: "10.44.0.1",
            dnsServerIPAddress: "10.44.0.53",
            useOwnSettings: true,
            staticAssignments: [
                TopologyDHCPStaticAssignment(macAddress: "02:00:00:00:00:01", ipAddress: "10.44.0.21"),
                TopologyDHCPStaticAssignment(macAddress: "invalid-row", ipAddress: "999.999.999.999"),
            ]
        )

        let exported = try TopologyProjectStore.exportFiliusConfigurationXML(from: state)
        let xml = try XCTUnwrap(String(data: exported, encoding: .utf8))
        XCTAssertTrue(xml.contains("property=\"DHCPKonfiguration\""))
        XCTAssertTrue(xml.contains("property=\"DHCPServer\""))
        XCTAssertTrue(xml.contains("property=\"staticAssignedAddresses\""))

        let imported = try TopologyProjectStore.importFiliusConfigurationXML(exported)
        let importedNode = try XCTUnwrap(imported.state.graph.nodes.first(where: { $0.kind == .pc }))
        XCTAssertEqual(imported.state.runtimeDHCPClientConfigurationsByNodeID[importedNode.id]?.isEnabled, true)
        XCTAssertEqual(
            imported.state.runtimeDeviceConfigurations[importedNode.id]?.dnsServer,
            "10.44.0.53"
        )
        let server = try XCTUnwrap(imported.state.runtimeDHCPServerConfigurationsByNodeID[importedNode.id])
        XCTAssertEqual(server.lowerBoundIPAddress, "10.44.0.20")
        XCTAssertEqual(server.upperBoundIPAddress, "10.44.0.30")
        XCTAssertEqual(server.gatewayIPAddress, "10.44.0.1")
        XCTAssertEqual(server.dnsServerIPAddress, "10.44.0.53")
        XCTAssertEqual(server.useOwnSettings, true)
        XCTAssertEqual(server.staticAssignments.map(\.macAddress), ["02:00:00:00:00:01", "invalid-row"])
        XCTAssertEqual(server.staticAssignments.map(\.ipAddress), ["10.44.0.21", "999.999.999.999"])
    }

    func testNativeSnapshotFirewallRoundTripAndMissingFieldsUseJavaDefaults() throws {
        var state = TopologyEditorState()
        let router = TopologyNode(
            id: uuid("99999999-9999-9999-9999-999999999991"),
            kind: .router,
            position: CGPoint(x: 80, y: 80)
        )
        state.graph = TopologyGraph(nodes: [router], links: [])
        let configuration = TopologyFirewallConfiguration(
            isActive: true,
            defaultPolicy: .accept,
            dropICMP: true,
            filterSYNSegmentsOnly: false,
            filterUDP: false,
            rules: [
                TopologyFirewallRule(
                    sourceIPAddress: TopologyFirewallRule.directlyConnectedSourceMarker,
                    destinationIPAddress: "203.0.113.0",
                    destinationSubnetMask: "255.255.255.0",
                    port: 53,
                    protocolType: .udp,
                    action: .drop
                ),
            ]
        )
        state.runtimeFirewallConfigurationsByNodeID[router.id] = configuration
        let fileURL = tempDirectoryURL.appendingPathComponent("firewall-roundtrip.json")
        let store = TopologyProjectStore(fileURL: fileURL)
        try store.save(state: state, savedAt: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(try store.load().runtimeFirewallConfigurationsByNodeID[router.id], configuration)

        let data = try Data(contentsOf: fileURL)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var payload = try XCTUnwrap(envelope["payload"] as? [String: Any])
        payload["runtimeFirewallConfigurations"] = [["nodeID": router.id.uuidString]]
        envelope["payload"] = payload
        try writeJSON(envelope, to: fileURL)
        XCTAssertEqual(
            try store.load().runtimeFirewallConfigurationsByNodeID[router.id],
            TopologyFirewallConfiguration()
        )
    }

    func testFiliusFirewallPropertiesRoundTripPreservesRuleOrderAndJavaFields() throws {
        var state = TopologyEditorState()
        let gateway = TopologyNode(
            id: uuid("99999999-9999-9999-9999-999999999992"),
            kind: .gateway,
            position: CGPoint(x: 160, y: 120)
        )
        state.graph = TopologyGraph(nodes: [gateway], links: [])
        state.runtimeFirewallConfigurationsByNodeID[gateway.id] = TopologyFirewallConfiguration(
            isActive: true,
            defaultPolicy: .accept,
            dropICMP: true,
            filterSYNSegmentsOnly: false,
            filterUDP: false,
            rules: [
                TopologyFirewallRule(
                    sourceIPAddress: "10.0.0.0",
                    sourceSubnetMask: "255.0.0.0",
                    port: 443,
                    protocolType: .tcp,
                    action: .accept
                ),
                TopologyFirewallRule(
                    sourceIPAddress: "invalid-imported-row",
                    destinationIPAddress: "192.168.0.10",
                    destinationSubnetMask: "255.255.255.255",
                    port: TopologyFirewallRule.allPorts,
                    protocolType: .all,
                    action: .drop
                ),
            ]
        )

        let exported = try TopologyProjectStore.exportFiliusConfigurationXML(from: state)
        let xml = try XCTUnwrap(String(data: exported, encoding: .utf8))
        XCTAssertTrue(xml.contains("filius.software.nat.NatGateway"))
        XCTAssertTrue(xml.contains("property=\"activated\""))
        XCTAssertTrue(xml.contains("property=\"defaultPolicy\""))
        XCTAssertTrue(xml.contains("property=\"dropICMP\""))
        XCTAssertTrue(xml.contains("property=\"filterSYNSegmentsOnly\""))
        XCTAssertTrue(xml.contains("property=\"filterUdp\""))
        XCTAssertTrue(xml.contains("property=\"ruleset\""))

        let imported = try TopologyProjectStore.importFiliusConfigurationXML(exported)
        let importedGateway = try XCTUnwrap(imported.state.graph.nodes.first(where: { $0.kind == .gateway }))
        let firewall = try XCTUnwrap(imported.state.runtimeFirewallConfigurationsByNodeID[importedGateway.id])
        XCTAssertTrue(firewall.isActive)
        XCTAssertEqual(firewall.defaultPolicy, .accept)
        XCTAssertTrue(firewall.dropICMP)
        XCTAssertFalse(firewall.filterSYNSegmentsOnly)
        XCTAssertFalse(firewall.filterUDP)
        XCTAssertEqual(firewall.rules.map(\.sourceIPAddress), ["10.0.0.0", "invalid-imported-row"])
        XCTAssertEqual(firewall.rules.map(\.protocolType), [.tcp, .all])
        XCTAssertEqual(firewall.rules.map(\.action), [.accept, .drop])
    }

    func testNativeSnapshotPortForwardingRoundTripPreservesInvalidRowsAndOrdering() throws {
        var state = TopologyEditorState()
        let gateway = TopologyNode(
            id: uuid("99999999-9999-9999-9999-999999999993"),
            kind: .gateway,
            position: CGPoint(x: 200, y: 120)
        )
        state.graph = TopologyGraph(nodes: [gateway], links: [])
        let rows = [
            TopologyGatewayPortForwardingRow(
                protocolValue: "TCP",
                publicPortValue: "443",
                lanIPAddress: "192.168.0.10",
                lanPortValue: "8443"
            ),
            TopologyGatewayPortForwardingRow(
                protocolValue: "invalid",
                publicPortValue: "70000",
                lanIPAddress: "999.999.999.999",
                lanPortValue: "0"
            ),
        ]
        state.runtimePortForwardingRowsByNodeID[gateway.id] = rows

        let fileURL = tempDirectoryURL.appendingPathComponent("port-forwarding-roundtrip.json")
        let store = TopologyProjectStore(fileURL: fileURL)
        try store.save(state: state, savedAt: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(try store.load().runtimePortForwardingRowsByNodeID[gateway.id], rows)

        let data = try Data(contentsOf: fileURL)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var payload = try XCTUnwrap(envelope["payload"] as? [String: Any])
        payload.removeValue(forKey: "runtimePortForwardingConfigurations")
        envelope["payload"] = payload
        try writeJSON(envelope, to: fileURL)
        XCTAssertTrue(try store.load().runtimePortForwardingRowsByNodeID.isEmpty)
    }

    func testFiliusStaticNATRoundTripPreservesRawRowsAndOrder() throws {
        var state = TopologyEditorState()
        let gateway = TopologyNode(
            id: uuid("99999999-9999-9999-9999-999999999994"),
            kind: .gateway,
            position: CGPoint(x: 240, y: 160)
        )
        state.graph = TopologyGraph(nodes: [gateway], links: [])
        let rows = [
            TopologyGatewayPortForwardingRow(
                protocolValue: "TCP",
                publicPortValue: "80",
                lanIPAddress: "192.168.0.20",
                lanPortValue: "8080"
            ),
            TopologyGatewayPortForwardingRow(
                protocolValue: "17",
                publicPortValue: "53",
                lanIPAddress: "192.168.0.53",
                lanPortValue: "53"
            ),
            TopologyGatewayPortForwardingRow(
                protocolValue: "broken",
                publicPortValue: "not-a-port",
                lanIPAddress: "invalid-imported-row",
                lanPortValue: "0"
            ),
        ]
        state.runtimePortForwardingRowsByNodeID[gateway.id] = rows

        let exported = try TopologyProjectStore.exportFiliusConfigurationXML(from: state)
        let xml = try XCTUnwrap(String(data: exported, encoding: .utf8))
        XCTAssertTrue(xml.contains("property=\"staticNAT\""))
        XCTAssertTrue(xml.contains("<array class=\"java.lang.String\" length=\"4\">"))

        let imported = try TopologyProjectStore.importFiliusConfigurationXML(exported)
        let importedGateway = try XCTUnwrap(imported.state.graph.nodes.first(where: { $0.kind == .gateway }))
        XCTAssertEqual(imported.state.runtimePortForwardingRowsByNodeID[importedGateway.id], rows)
    }
    func testIntegratedRouterGatewayFLSRoundTripPreservesConfigurationAndExcludesTransientRuntimeState() throws {
        var state = TopologyEditorState()
        let router = TopologyNode(
            id: uuid("AAAAAAAA-0000-0000-0000-000000000001"),
            kind: .router,
            position: CGPoint(x: 120, y: 120),
            ports: [
                TopologyPortMetadata(id: uuid("AAAAAAAA-0000-0000-0000-000000000011"), label: "rt1"),
                TopologyPortMetadata(id: uuid("AAAAAAAA-0000-0000-0000-000000000012"), label: "rt2"),
            ]
        )
        let gateway = TopologyNode(
            id: uuid("BBBBBBBB-0000-0000-0000-000000000001"),
            kind: .gateway,
            position: CGPoint(x: 360, y: 120)
        )
        state.graph = TopologyGraph(nodes: [router, gateway], links: [])
        state.runtimeInterfaceConfigurations = [
            TopologyRuntimeInterfaceKey(nodeID: router.id, portID: router.ports[0].id):
                TopologyRuntimeInterfaceConfiguration(ipAddress: "10.60.0.1", subnetMask: "255.255.255.0"),
            TopologyRuntimeInterfaceKey(nodeID: router.id, portID: router.ports[1].id):
                TopologyRuntimeInterfaceConfiguration(ipAddress: "10.61.0.1", subnetMask: "255.255.255.0"),
            TopologyRuntimeInterfaceKey(nodeID: gateway.id, portID: gateway.ports[0].id):
                TopologyRuntimeInterfaceConfiguration(ipAddress: "203.0.113.1", subnetMask: "255.255.255.0"),
            TopologyRuntimeInterfaceKey(nodeID: gateway.id, portID: gateway.ports[1].id):
                TopologyRuntimeInterfaceConfiguration(ipAddress: "192.168.60.1", subnetMask: "255.255.255.0"),
        ]
        state.runtimeDeviceConfigurations[gateway.id] = TopologyRuntimeDeviceConfiguration(
            ipAddress: "192.168.60.1",
            subnetMask: "255.255.255.0",
            defaultGateway: "203.0.113.254",
            dnsServer: "192.168.60.53"
        )
        state.runtimeManualRoutesByNodeID[router.id] = [TopologyRuntimeManualRoute(
            destinationNetwork: "172.16.0.0",
            subnetMask: "255.255.0.0",
            gateway: "10.61.0.2",
            interfaceIPAddress: "10.61.0.1"
        )]
        state.runtimeRIPEnabledByNodeID[router.id] = true
        state.runtimeDHCPClientConfigurationsByNodeID[gateway.id] = TopologyDHCPClientConfiguration(isEnabled: true)
        state.runtimeDHCPServerConfigurationsByNodeID[gateway.id] = TopologyDHCPServerConfiguration(
            isActive: true,
            lowerBoundIPAddress: "192.168.60.20",
            upperBoundIPAddress: "192.168.60.40",
            gatewayIPAddress: "192.168.60.1",
            dnsServerIPAddress: "192.168.60.53",
            staticAssignments: [
                TopologyDHCPStaticAssignment(macAddress: "02:00:00:00:60:10", ipAddress: "192.168.60.10")
            ]
        )
        state.runtimeFirewallConfigurationsByNodeID[router.id] = TopologyFirewallConfiguration(
            isActive: true,
            defaultPolicy: .drop,
            rules: [TopologyFirewallRule(port: 520, protocolType: .udp, action: .accept)]
        )
        state.runtimeFirewallConfigurationsByNodeID[gateway.id] = TopologyFirewallConfiguration(
            isActive: true,
            defaultPolicy: .drop,
            dropICMP: true,
            rules: [TopologyFirewallRule(port: 443, protocolType: .tcp, action: .accept)]
        )
        let forwardingRows = [
            TopologyGatewayPortForwardingRow(
                protocolValue: "TCP",
                publicPortValue: "443",
                lanIPAddress: "192.168.60.10",
                lanPortValue: "8443"
            ),
            TopologyGatewayPortForwardingRow(
                protocolValue: "broken",
                publicPortValue: "invalid",
                lanIPAddress: "invalid-imported-row",
                lanPortValue: "0"
            ),
        ]
        state.runtimePortForwardingRowsByNodeID[gateway.id] = forwardingRows
        state.networkRuntime.recordTrace(
            packetIdentity: 999,
            nodeID: gateway.id,
            interfaceID: gateway.ports[0].id,
            direction: .inbound,
            layer: .network,
            operation: .rewritten,
            detail: "do-not-persist-packet-capture"
        )

        let exported = try TopologyProjectStore.exportFiliusConfigurationXML(from: state)
        let xml = try XCTUnwrap(String(data: exported, encoding: .utf8))
        for property in ["ripEnabled", "DHCPKonfiguration", "DHCPServer", "activated", "ruleset", "staticNAT", "manuelleTabelle"] {
            XCTAssertTrue(xml.contains("property=\"\(property)\""), "Missing Java property \(property)")
        }
        XCTAssertFalse(xml.contains("do-not-persist-packet-capture"))

        let imported = try TopologyProjectStore.importFiliusConfigurationXML(exported).state
        let importedRouter = try XCTUnwrap(imported.graph.nodes.first(where: { $0.kind == .router }))
        let importedGateway = try XCTUnwrap(imported.graph.nodes.first(where: { $0.kind == .gateway }))
        XCTAssertEqual(imported.runtimeRIPEnabledByNodeID[importedRouter.id], true)
        XCTAssertEqual(imported.runtimeManualRoutesByNodeID[importedRouter.id]?.first?.destinationNetwork, "172.16.0.0")
        XCTAssertEqual(imported.runtimeDHCPClientConfigurationsByNodeID[importedGateway.id]?.isEnabled, true)
        XCTAssertEqual(
            imported.runtimeDHCPServerConfigurationsByNodeID[importedGateway.id]?.staticAssignments.first?.ipAddress,
            "192.168.60.10"
        )
        XCTAssertEqual(imported.runtimeFirewallConfigurationsByNodeID[importedRouter.id]?.rules.first?.port, 520)
        XCTAssertEqual(imported.runtimeFirewallConfigurationsByNodeID[importedGateway.id]?.dropICMP, true)
        XCTAssertEqual(imported.runtimePortForwardingRowsByNodeID[importedGateway.id], forwardingRows)
        XCTAssertTrue(imported.networkRuntime.state.packetTraces.isEmpty)
    }

    func testImportFiliusTwoArchiveDocumentReadsCurrentRepositorySample() throws {
        let archiveData = try loadRepositorySampleFLSArchive(named: "Public_and_Private_Networks_2_EN.fls")

        let result = try TopologyProjectStore.importFiliusArchiveDocument(archiveData)

        XCTAssertTrue(result.project.report.filiusVersion?.contains("2.9.4") == true)
        XCTAssertGreaterThan(result.project.report.importedNodeCount, 0)
        XCTAssertGreaterThan(result.project.report.importedLinkCount, 0)
        XCTAssertTrue(result.archiveEntryPaths.contains("projekt/konfiguration.xml"))
    }

    func testImportFiliusArchiveReadsRepositoryDeflateSample() throws {
        let archiveData = try loadRepositorySampleFLSArchive(named: "zwei_rechnernetze_komplett.fls")

        let result = try TopologyProjectStore.importFiliusArchive(archiveData)

        XCTAssertEqual(result.report.importedNodeCount, 6)
        XCTAssertEqual(result.report.importedLinkCount, 5)
        XCTAssertEqual(result.report.skippedNodeCount, 0)
        XCTAssertEqual(result.state.graph.links.count, 5)
        XCTAssertEqual(
            Set(result.state.graph.nodes.map { $0.kind.rawValue }),
            Set(["pc", "notebook", "networkSwitch", "router"])
        )
    }

    func testPersistenceSaveCoordinatorRejectsStaleGenerationBeforeExecutingWrite() async throws {
        let coordinator = TopologyPersistenceSaveCoordinator()
        let staleGeneration = coordinator.currentGeneration
        let currentGeneration = coordinator.advanceGeneration()

        let staleWriteExecuted = try await coordinator.perform(generation: staleGeneration) {
            XCTFail("stale persistence operation must not execute")
        }
        let currentWriteExecuted = try await coordinator.perform(generation: currentGeneration) {}

        XCTAssertFalse(staleWriteExecuted)
        XCTAssertTrue(currentWriteExecuted)
        XCTAssertFalse(coordinator.isCurrent(staleGeneration))
        XCTAssertTrue(coordinator.isCurrent(currentGeneration))
    }

    func testDelayedAutosaveRestoreCannotOverwriteAnExternallyOpenedArchive() async {
        var lifecycle = TopologyPersistenceLifecycle()
        let restoreToken = lifecycle.beginAutosaveRestore()
        let delayedStoreRead = Task {
            try? await Task.sleep(nanoseconds: 20_000_000)
            return "stale native snapshot"
        }

        lifecycle.invalidateForExternalStateReplacement()
        _ = await delayedStoreRead.value

        XCTAssertFalse(lifecycle.canApplyAutosaveRestore(restoreToken))
        XCTAssertFalse(lifecycle.isRestoringAutosave)
        lifecycle.finishAutosaveRestore(restoreToken)
        XCTAssertFalse(lifecycle.isRestoringAutosave)
    }

    func testFiliusArchiveDocumentPreservesSupplementalEntriesAcrossExplicitSave() throws {
        var state = TopologyEditorState()
        let node = TopologyNode(
            id: uuid("11000000-0000-0000-0000-000000000001"),
            kind: .pc,
            displayName: "Archive Client",
            position: .zero
        )
        state.graph = TopologyGraph(nodes: [node], links: [])
        let supplemental = [
            TopologyProjectStore.filiusApplicationsArchivePath: Data("custom-app-catalog".utf8),
            "projekt/anwendungen/opaque.jar": Data([0, 1, 2, 3]),
        ]

        let archive = try TopologyProjectStore.exportFiliusArchiveWithReport(
            from: state,
            supplementalEntries: supplemental
        ).data
        let imported = try TopologyProjectStore.importFiliusArchiveDocument(archive)
        XCTAssertEqual(imported.supplementalEntries, supplemental)
        XCTAssertEqual(imported.archiveEntryPaths, [
            TopologyProjectStore.filiusApplicationsArchivePath,
            TopologyProjectStore.filiusConfigurationArchivePath,
            "projekt/anwendungen/opaque.jar",
        ].sorted())

        let reopenedArchive = try TopologyProjectStore.exportFiliusArchiveWithReport(
            from: imported.project.state,
            supplementalEntries: imported.supplementalEntries
        ).data
        let reopened = try TopologyProjectStore.importFiliusArchiveDocument(reopenedArchive)
        XCTAssertEqual(reopened.supplementalEntries, supplemental)
        XCTAssertEqual(reopened.project.state.graph.nodes.first?.displayName, "Archive Client")
    }

    func testExportFiliusArchiveEnforcesFinalArchiveByteLimitAndNearLimitRoundTrips() throws {
        let configurationBytes = try TopologyProjectStore.exportFiliusConfigurationXML(from: TopologyEditorState()).count

        func supplementalEntries(totalPayloadBytes: Int, prefix: String) -> [String: Data] {
            let firstPayloadSize = min(TopologyFLSArchiveLimits.maxEntryUncompressedBytes, totalPayloadBytes)
            let secondPayloadSize = totalPayloadBytes - firstPayloadSize
            return [
                "projekt/anwendungen/\(prefix)-1.bin": Data(repeating: 0xA5, count: firstPayloadSize),
                "projekt/anwendungen/\(prefix)-2.bin": Data(repeating: 0x5A, count: secondPayloadSize),
            ]
        }

        do {
            let exactExpandedLimitPayloadSize = TopologyFLSArchiveLimits.maxTotalUncompressedBytes - configurationBytes
            let exactExpandedLimitEntries = supplementalEntries(
                totalPayloadBytes: exactExpandedLimitPayloadSize,
                prefix: "exact-expanded-limit"
            )
            XCTAssertThrowsError(
                try TopologyProjectStore.exportFiliusArchiveWithReport(
                    from: TopologyEditorState(),
                    supplementalEntries: exactExpandedLimitEntries
                )
            ) { error in
                self.assertFLSArchiveError(error, expectedCode: .archiveLimitExceeded)
            }
        }

        let conservativeZIPOverhead = 64 * 1_024
        let nearLimitPayloadSize = TopologyFLSArchiveLimits.maxArchiveBytes - configurationBytes - conservativeZIPOverhead
        XCTAssertGreaterThan(nearLimitPayloadSize, 0)
        let nearLimitEntries = supplementalEntries(totalPayloadBytes: nearLimitPayloadSize, prefix: "near-limit")
        let archive = try TopologyProjectStore.exportFiliusArchiveWithReport(
            from: TopologyEditorState(),
            supplementalEntries: nearLimitEntries
        ).data

        XCTAssertLessThanOrEqual(archive.count, TopologyFLSArchiveLimits.maxArchiveBytes)
        let reopened = try TopologyProjectStore.importFiliusArchiveDocument(archive)
        for (path, payload) in nearLimitEntries {
            XCTAssertEqual(reopened.supplementalEntries[path], payload)
        }
        XCTAssertEqual(reopened.supplementalEntries[TopologyProjectStore.filiusApplicationsArchivePath], Data())
    }

    func testExportFiliusArchiveRoundTripsProjectSemantics() throws {
        var state = TopologyEditorState()
        let pc = TopologyNode(
            id: uuid("10000000-0000-0000-0000-000000000001"),
            kind: .pc,
            displayName: "Client Alpha",
            position: CGPoint(x: 80, y: 120)
        )
        let gateway = TopologyNode(
            id: uuid("20000000-0000-0000-0000-000000000002"),
            kind: .gateway,
            displayName: "Gateway Alpha",
            position: CGPoint(x: 320, y: 120)
        )
        let link = TopologyLink(
            sourceNodeID: pc.id,
            sourcePortID: pc.ports[0].id,
            targetNodeID: gateway.id,
            targetPortID: gateway.ports[1].id
        )
        state.graph = TopologyGraph(nodes: [pc, gateway], links: [link])
        state.runtimeDeviceConfigurations[pc.id] = TopologyRuntimeDeviceConfiguration(
            ipAddress: "192.168.10.20",
            subnetMask: "255.255.255.0",
            defaultGateway: "192.168.10.1",
            dnsServer: "192.168.10.53"
        )
        state.runtimeFirewallConfigurationsByNodeID[gateway.id] = TopologyFirewallConfiguration(
            isActive: true,
            defaultPolicy: .drop,
            rules: [TopologyFirewallRule(port: 443, protocolType: .tcp, action: .accept)]
        )
        state.runtimePortForwardingRowsByNodeID[gateway.id] = [
            TopologyGatewayPortForwardingRow(
                protocolValue: "TCP",
                publicPortValue: "443",
                lanIPAddress: "192.168.10.20",
                lanPortValue: "443"
            )
        ]

        let archiveData = try TopologyProjectStore.exportFiliusArchive(from: state)
        XCTAssertEqual(Array(archiveData.prefix(4)), [0x50, 0x4b, 0x03, 0x04])

        let imported = try TopologyProjectStore.importFiliusArchive(archiveData).state
        XCTAssertEqual(Set(imported.graph.nodes.map(\.displayName)), Set(["Client Alpha", "Gateway Alpha"]))
        XCTAssertEqual(imported.graph.links.count, 1)
        let importedPC = try XCTUnwrap(imported.graph.nodes.first(where: { $0.kind == .pc }))
        let importedGateway = try XCTUnwrap(imported.graph.nodes.first(where: { $0.kind == .gateway }))
        XCTAssertEqual(imported.runtimeDeviceConfigurations[importedPC.id]?.dnsServer, "192.168.10.53")
        XCTAssertEqual(imported.runtimeFirewallConfigurationsByNodeID[importedGateway.id]?.defaultPolicy, .drop)
        XCTAssertEqual(imported.runtimePortForwardingRowsByNodeID[importedGateway.id]?.first?.publicPortValue, "443")
    }

    func testImportFiliusArchiveRejectsMissingConfigurationEntry() throws {
        let archiveData = makeMinimalZIP(entries: [("projekt/other.xml", 0)])

        XCTAssertThrowsError(try TopologyProjectStore.importFiliusArchive(archiveData)) { error in
            self.assertFLSArchiveError(error, expectedCode: .missingConfiguration)
        }
    }

    func testImportFiliusArchiveRejectsUnsafeEntryPath() throws {
        let archiveData = makeMinimalZIP(entries: [("../konfiguration.xml", 0)])

        XCTAssertThrowsError(try TopologyProjectStore.importFiliusArchive(archiveData)) { error in
            self.assertFLSArchiveError(error, expectedCode: .unsafeEntryPath)
        }
    }

    func testImportFiliusArchiveRejectsNonPortableAliasEntryPath() throws {
        let archiveData = makeMinimalZIP(entries: [
            (TopologyProjectStore.filiusConfigurationArchivePath, 0),
            ("projekt/konfiguration.xml ", 0),
        ])

        XCTAssertThrowsError(try TopologyProjectStore.importFiliusArchive(archiveData)) { error in
            self.assertFLSArchiveError(error, expectedCode: .unsafeEntryPath)
            XCTAssertEqual((error as? TopologyFLSArchiveError)?.entryPath, "projekt/konfiguration.xml ")
        }
    }

    func testImportFiliusArchiveRejectsWindowsReservedAndDotComponents() throws {
        for path in ["projekt/CON.txt", "projekt/.", "projekt//opaque.bin"] {
            let archiveData = makeMinimalZIP(entries: [(path, 0)])
            XCTAssertThrowsError(try TopologyProjectStore.importFiliusArchive(archiveData), "path=\(path)") { error in
                self.assertFLSArchiveError(error, expectedCode: .unsafeEntryPath)
            }
        }
    }

    func testImportFiliusArchiveRejectsWindowsForbiddenControlsAndSuperscriptReservedNames() {
        for path in [
            "projekt/illegal?.bin",
            "projekt/control\u{0001}.bin",
            "projekt/COM\u{00B9}.txt",
            "projekt/LPT\u{00B3}.log",
        ] {
            let archiveData = makeMinimalZIP(entries: [(path, 0)])
            XCTAssertThrowsError(try TopologyProjectStore.importFiliusArchive(archiveData), "path=\(path)") { error in
                self.assertFLSArchiveError(error, expectedCode: .unsafeEntryPath)
            }
        }
    }

    func testExportFiliusArchiveCanonicalKeyRejectsUnicodeWidthAndCaseAliases() {
        XCTAssertThrowsError(try TopologyProjectStore.exportFiliusArchiveWithReport(from: TopologyEditorState(), supplementalEntries: [
            "projekt/Alpha.txt": Data("one".utf8), "projekt/\u{FF21}LPHA.TXT": Data("two".utf8)
        ])) { error in
            self.assertFLSArchiveError(error, expectedCode: .duplicateEntry)
        }
    }

    func testNewProjectReplacementRevisionStartsDirty() {
        var replacement = TopologyEditorState()
        replacement.persistenceRevision = 1
        replacement.lastPersistedRevision = 0
        XCTAssertGreaterThan(replacement.persistenceRevision, replacement.lastPersistedRevision)
    }

    func testExportFiliusArchiveRejectsNonPortableSupplementalAliasBeforeGeneratedConfigurationCanBeOverwritten() {
        XCTAssertThrowsError(
            try TopologyProjectStore.exportFiliusArchiveWithReport(
                from: TopologyEditorState(),
                supplementalEntries: ["projekt/konfiguration.xml ": Data("attacker".utf8)]
            )
        ) { error in
            self.assertFLSArchiveError(error, expectedCode: .unsafeEntryPath)
            XCTAssertEqual((error as? TopologyFLSArchiveError)?.entryPath, "projekt/konfiguration.xml ")
        }
    }

    func testImportFiliusArchiveRejectsUnsupportedCompression() throws {
        let archiveData = makeMinimalZIP(entries: [(TopologyProjectStore.filiusConfigurationArchivePath, 99)])

        XCTAssertThrowsError(try TopologyProjectStore.importFiliusArchive(archiveData)) { error in
            self.assertFLSArchiveError(error, expectedCode: .unsupportedCompression)
        }
    }

    func testImportFiliusArchiveRejectsLocalCentralFilenameConflict() {
        var archiveData = makeMinimalZIP(entries: [(TopologyProjectStore.filiusConfigurationArchivePath, 0)])
        archiveData[30] = 0x78

        XCTAssertThrowsError(try TopologyProjectStore.importFiliusArchive(archiveData)) { error in
            self.assertFLSArchiveError(error, expectedCode: .malformedArchive)
            XCTAssertTrue((error as? TopologyFLSArchiveError)?.detail.contains("local filename") == true)
        }
    }

    func testImportFiliusArchiveRejectsEncryptedEntry() {
        var archiveData = makeMinimalZIP(entries: [(TopologyProjectStore.filiusConfigurationArchivePath, 0)])
        let centralOffset = archiveData.range(of: Data([0x50, 0x4b, 0x01, 0x02]))!.lowerBound
        setUInt16LE(0x0001, at: 6, in: &archiveData)
        setUInt16LE(0x0001, at: centralOffset + 8, in: &archiveData)

        XCTAssertThrowsError(try TopologyProjectStore.importFiliusArchive(archiveData)) { error in
            self.assertFLSArchiveError(error, expectedCode: .encryptedEntry)
        }
    }

    func testImportFiliusArchiveRejectsMalformedDEFLATEPayload() {
        let archiveData = makePayloadZIP(
            path: TopologyProjectStore.filiusConfigurationArchivePath,
            method: 8,
            payload: Data([0xff]),
            uncompressedSize: 1
        )

        XCTAssertThrowsError(try TopologyProjectStore.importFiliusArchive(archiveData)) { error in
            self.assertFLSArchiveError(error, expectedCode: .malformedArchive)
            XCTAssertTrue((error as? TopologyFLSArchiveError)?.detail.contains("DEFLATE") == true)
        }
    }

    func testImportFiliusArchiveRejectsChecksumMismatch() throws {
        var archiveData = try TopologyProjectStore.exportFiliusArchive(from: TopologyEditorState())
        let xmlMarker = Data("<?xml".utf8)
        let markerRange = try XCTUnwrap(archiveData.range(of: xmlMarker))
        archiveData[markerRange.lowerBound] ^= 0x01

        XCTAssertThrowsError(try TopologyProjectStore.importFiliusArchive(archiveData)) { error in
            self.assertFLSArchiveError(error, expectedCode: .checksumMismatch)
        }
    }

    func testImportFiliusArchiveRejectsMalformedPayload() {
        XCTAssertThrowsError(try TopologyProjectStore.importFiliusArchive(Data("not-a-zip".utf8))) { error in
            self.assertFLSArchiveError(error, expectedCode: .malformedArchive)
        }
    }

    func testImportFiliusConfigurationXMLIgnoresUnknownJavaBeanClassAndKeepsSupportedNodes() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <java version="24" class="java.beans.XMLDecoder">
         <string>Filius version: unknown JavaBean fixture</string>
         <object class="java.util.LinkedList">
          <void method="add">
           <object class="com.example.UnsupportedTeachingExtension">
            <void property="payload"><string>must-not-execute</string></void>
           </object>
          </void>
          <void method="add">
           <object class="filius.gui.netzwerksicht.GUIKnotenItem">
            <void property="typ"><string>Computer</string></void>
            <void property="bounds"><object class="java.awt.Rectangle"><int>40</int><int>80</int><int>70</int><int>68</int></object></void>
           </object>
          </void>
         </object>
         <object class="java.util.LinkedList"/>
        </java>
        """

        let result = try TopologyProjectStore.importFiliusConfigurationXML(Data(xml.utf8))

        XCTAssertEqual(result.report.importedNodeCount, 1)
        XCTAssertEqual(result.report.skippedNodeCount, 0)
        XCTAssertEqual(result.state.graph.nodes.first?.kind, .pc)
        XCTAssertFalse(result.report.warnings.contains(where: { $0.contains("must-not-execute") }))
    }

    func testUnknownOnlyNodeContainerUsesCanonicalTopLevelRoleFallback() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <java version="24" class="java.beans.XMLDecoder">
         <object class="java.util.LinkedList">
          <void method="add">
           <object class="com.example.FutureTeachingNode">
            <void property="payload"><string>unknown-only-node-marker</string></void>
           </object>
          </void>
         </object>
         <object class="java.util.LinkedList"/>
        </java>
        """

        let imported = try TopologyProjectStore.importFiliusConfigurationXML(Data(xml.utf8))
        XCTAssertTrue(imported.state.graph.nodes.isEmpty)
        XCTAssertGreaterThan(imported.opaqueContent.fragmentCount, 0)

        let archive = try TopologyProjectStore.exportFiliusArchiveWithReport(
            from: imported.state,
            opaqueContent: imported.opaqueContent
        ).data
        let reopened = try TopologyProjectStore.importFiliusArchiveDocument(archive)
        let preservedData = try XCTUnwrap(reopened.project.opaqueContent.sourceConfigurationXML)
        let preservedXML = try XCTUnwrap(String(data: preservedData, encoding: .utf8))
        XCTAssertEqual(preservedXML.components(separatedBy: "unknown-only-node-marker").count - 1, 1)
    }

    func testUnknownJavaApplicationAndArchivePayloadRoundTripWhileNativeEditsWin() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("parity/m012/s01/java-xmle-opaque-payload.xml")
        let imported = try TopologyProjectStore.importFiliusConfigurationXML(Data(contentsOf: fixtureURL))
        XCTAssertEqual(imported.state.graph.nodes.count, 2)
        XCTAssertEqual(imported.state.graph.links.count, 1)
        XCTAssertEqual(imported.state.documentationItems.count, 1)

        var editedState = imported.state
        let serverIndex = try XCTUnwrap(editedState.graph.nodes.firstIndex { $0.displayName == "Original server" })
        let serverID = editedState.graph.nodes[serverIndex].id
        editedState.graph.nodes[serverIndex].displayName = "Native server edit"
        editedState.graph.nodes[serverIndex].position = CGPoint(x: 140, y: 180)
        editedState.runtimeWebServerConfigurationsByNodeID[serverID] = TopologyRuntimeWebServerConfiguration(port: 9090)
        editedState.documentationItems[0].text = "Native documentation edit"
        editedState.documentationItems[0].frame.origin = CGPoint(x: 160, y: 120)
        editedState.documentationItems[0].frame.size = CGSize(width: 260, height: 100)

        let supplementalData = Data([0xca, 0xfe, 0xba, 0xbe])
        let supplemental = ["projekt/anwendungen/opaque.jar": supplementalData]
        let firstArchive = try TopologyProjectStore.exportFiliusArchiveWithReport(
            from: editedState,
            supplementalEntries: supplemental,
            opaqueContent: imported.opaqueContent
        ).data
        XCTAssertEqual(
            firstArchive,
            try TopologyProjectStore.exportFiliusArchiveWithReport(
                from: editedState,
                supplementalEntries: supplemental,
                opaqueContent: imported.opaqueContent
            ).data
        )

        func occurrences(_ needle: String, in value: String) -> Int {
            var count = 0
            var cursor = value.startIndex
            while let range = value.range(of: needle, range: cursor..<value.endIndex) {
                count += 1
                cursor = range.upperBound
            }
            return count
        }

        func assertCycle(_ reopened: TopologyFLSArchiveImportResult, cycle: Int) throws {
            XCTAssertEqual(reopened.project.state.graph.nodes.count, 2, "cycle \(cycle)")
            XCTAssertEqual(reopened.project.state.graph.links.count, 1, "cycle \(cycle)")
            XCTAssertEqual(reopened.project.state.documentationItems.count, 1, "cycle \(cycle)")
            let server = try XCTUnwrap(reopened.project.state.graph.nodes.first { $0.displayName == "Native server edit" })
            XCTAssertEqual(server.kind, .pc, "cycle \(cycle): nested recognized GUI class changed node semantics")
            XCTAssertEqual(server.position, CGPoint(x: 140, y: 180), "cycle \(cycle)")
            XCTAssertEqual(reopened.project.state.runtimeWebServerConfigurationsByNodeID[server.id]?.port, 9090, "cycle \(cycle)")
            XCTAssertEqual(reopened.project.state.documentationItems[0].text, "Native documentation edit", "cycle \(cycle)")
            XCTAssertEqual(reopened.project.state.documentationItems[0].frame.origin, CGPoint(x: 160, y: 120), "cycle \(cycle)")
            XCTAssertEqual(reopened.supplementalEntries["projekt/anwendungen/opaque.jar"], supplementalData, "cycle \(cycle)")

            let xmlData = try XCTUnwrap(reopened.project.opaqueContent.sourceConfigurationXML)
            let xml = try XCTUnwrap(String(data: xmlData, encoding: .utf8))
            for marker in [
                "top-level-residual", "image-label-residual", "interface-residual", "webserver-residual",
                "unknown-key-recognized-class", "recognized-key-unknown-class", "unknown-application-residual",
                "terminal-working-directory-residual", "cable-hardware-residual", "cable-panel-residual", "cable-residual",
                "documentation-residual", "decoder-root-residual", "preserve-root-comment", "preserve-root-pi",
                "future-operation-before-port", "nested-recognized-documentation-must-stay-opaque", "nested-recognized-node-must-stay-opaque",
                "OpaqueIndexedBefore", "OpaqueIndexedAfter", "OpaqueCableIndexed",
            ] {
                XCTAssertEqual(occurrences(marker, in: xml), 1, "cycle \(cycle): \(marker)")
            }
            XCTAssertEqual(occurrences("id=\"LegacyDoc0\"", in: xml), 1, "cycle \(cycle)")
            XCTAssertEqual(occurrences("id=\"LegacyInterface0\"", in: xml), 1, "cycle \(cycle)")
            XCTAssertEqual(occurrences("id=\"LegacyWorkingDirectory0\"", in: xml), 1, "cycle \(cycle)")
            XCTAssertEqual(occurrences("idref=\"LegacyWorkingDirectory0\"", in: xml), 1, "cycle \(cycle)")
            XCTAssertEqual(occurrences("id=\"LegacyNode", in: xml), 2, "cycle \(cycle)")
            XCTAssertEqual(occurrences("com.example.AliasBrowserKey", in: xml), 1, "cycle \(cycle)")
            XCTAssertEqual(occurrences("recognized-key-unknown-class", in: xml), 1, "cycle \(cycle)")
            XCTAssertTrue(xml.contains("futureRoot=\"root-attribute\""), "cycle \(cycle)")
            XCTAssertTrue(xml.contains("<void property=\"port\"><int>9090</int></void>"), "cycle \(cycle)")
            XCTAssertFalse(xml.contains("<int>999</int>"), "cycle \(cycle): stale direct bounds")
            XCTAssertFalse(xml.contains("<int>998</int>"), "cycle \(cycle): stale direct bounds")
            XCTAssertFalse(xml.contains("<int>111</int><int>112</int><int>113</int><int>114</int>"), "cycle \(cycle): stale cable bounds")
            let futureOperation = try XCTUnwrap(xml.range(of: "future-operation-before-port"))
            let retainedPort = try XCTUnwrap(xml.range(of: "id=\"LegacyPort0\" property=\"port\""))
            XCTAssertLessThan(futureOperation.lowerBound, retainedPort.lowerBound, "cycle \(cycle): residual operation order")
            XCTAssertTrue(xml.contains("idref=\"LegacyPort0\""), "cycle \(cycle): cable must target retained port")
            XCTAssertFalse(xml.contains("idref=\"FutureOperation0\"/></void></array>"), "cycle \(cycle): cable must not target opaque operation")
        }

        let firstReopen = try TopologyProjectStore.importFiliusArchiveDocument(firstArchive)
        try assertCycle(firstReopen, cycle: 1)
        let secondArchive = try TopologyProjectStore.exportFiliusArchiveWithReport(
            from: firstReopen.project.state,
            supplementalEntries: firstReopen.supplementalEntries,
            opaqueContent: firstReopen.project.opaqueContent
        ).data
        let secondReopen = try TopologyProjectStore.importFiliusArchiveDocument(secondArchive)
        try assertCycle(secondReopen, cycle: 2)
    }

    func testPCSwitchAndRemoteDirectPortsRemainValidAcrossTwoArchiveCycles() throws {
        let pc = TopologyNode(id: uuid("41000000-0000-0000-0000-000000000001"), kind: .pc, position: CGPoint(x: 40, y: 80))
        let networkSwitch = TopologyNode(id: uuid("41000000-0000-0000-0000-000000000002"), kind: .networkSwitch, position: CGPoint(x: 240, y: 80))
        let remote = TopologyNode(id: uuid("41000000-0000-0000-0000-000000000003"), kind: .remoteLink, position: CGPoint(x: 440, y: 80))
        var state = TopologyEditorState()
        state.graph = TopologyGraph(nodes: [pc, networkSwitch, remote], links: [
            TopologyLink(sourceNodeID: pc.id, sourcePortID: pc.ports[0].id, targetNodeID: networkSwitch.id, targetPortID: networkSwitch.ports[0].id),
            TopologyLink(sourceNodeID: networkSwitch.id, sourcePortID: networkSwitch.ports[1].id, targetNodeID: remote.id, targetPortID: remote.ports[0].id),
        ])

        let first = try TopologyProjectStore.exportFiliusArchiveWithReport(from: state).data
        let firstReopen = try TopologyProjectStore.importFiliusArchiveDocument(first)
        XCTAssertEqual(firstReopen.project.state.graph.nodes.count, 3)
        XCTAssertEqual(firstReopen.project.state.graph.links.count, 2)
        let second = try TopologyProjectStore.exportFiliusArchiveWithReport(
            from: firstReopen.project.state,
            opaqueContent: firstReopen.project.opaqueContent
        ).data
        let secondReopen = try TopologyProjectStore.importFiliusArchiveDocument(second)
        XCTAssertEqual(secondReopen.project.state.graph.nodes.map(\.kind).sorted { $0.rawValue < $1.rawValue }, [.networkSwitch, .pc, .remoteLink])
        XCTAssertEqual(secondReopen.project.state.graph.links.count, 2)
    }

    func testUnknownApplicationSurvivesAnOtherwiseEmptyNativeSystemSoftwareBranch() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <java class="java.beans.XMLDecoder">
         <string>Filius version: unknown-only application</string>
         <object class="java.util.LinkedList"><void method="add">
          <object class="filius.gui.netzwerksicht.GUIKnotenItem">
           <void property="typ"><string>Computer</string></void>
           <void property="imageLabel"><object class="filius.gui.netzwerksicht.JSidebarButton"><void property="bounds"><object class="java.awt.Rectangle"><int>40</int><int>80</int><int>70</int><int>68</int></object></void><void property="text"><string>Host</string></void></object></void>
           <void property="knoten"><object class="filius.hardware.knoten.Rechner"><void property="name"><string>Host</string></void><void id="OnlySystem" property="systemSoftware"><void property="installierteAnwendungen"><void method="put"><string>com.example.OnlyUnknown</string><object class="com.example.OnlyUnknown" id="OnlyUnknown"><void property="marker"><string>unknown-only-survives</string></void><void property="owner"><object idref="OnlySystem"/></void><void property="self"><object idref="OnlyUnknown"/></void></object></void></void></void></object></void>
          </object>
         </void></object>
         <object class="java.util.LinkedList"/>
         <object class="java.util.ArrayList"/>
        </java>
        """
        let imported = try TopologyProjectStore.importFiliusConfigurationXML(Data(xml.utf8))
        XCTAssertTrue(imported.state.runtimeInstalledProgramsByNodeID.values.allSatisfy(\.isEmpty))

        let archive = try TopologyProjectStore.exportFiliusArchiveWithReport(
            from: imported.state,
            opaqueContent: imported.opaqueContent
        ).data
        let reopened = try TopologyProjectStore.importFiliusArchiveDocument(archive)
        let preservedData = try XCTUnwrap(reopened.project.opaqueContent.sourceConfigurationXML)
        let preserved = try XCTUnwrap(String(data: preservedData, encoding: .utf8))
        XCTAssertEqual(preserved.components(separatedBy: "unknown-only-survives").count - 1, 1)
        XCTAssertEqual(preserved.components(separatedBy: "com.example.OnlyUnknown").count - 1, 2)
    }

    func testOpaqueXMLPreservationRejectsDTDAndUnresolvedJavaBeanReferences() throws {
        let dtdXML = """
        <?xml version="1.0"?>
        <!DOCTYPE java [<!ENTITY unsafe "expanded">]>
        <java class="java.beans.XMLDecoder"><object class="java.util.LinkedList"/></java>
        """
        XCTAssertThrowsError(try TopologyProjectStore.importFiliusConfigurationXML(Data(dtdXML.utf8))) { error in
            XCTAssertEqual((error as? TopologyFLSCompatibilityError)?.code, .unsupportedConfigurationStructure)
        }

        let commentedFakeRootBeforeDTD = """
        <!-- <java class="java.beans.XMLDecoder"> -->
        <!DOCTYPE java [<!ENTITY unsafe "expanded">]>
        <java class="java.beans.XMLDecoder"><string>&unsafe;</string></java>
        """
        XCTAssertThrowsError(
            try TopologyProjectStore.importFiliusConfigurationXML(Data(commentedFakeRootBeforeDTD.utf8))
        )

        let unresolvedXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <java class="java.beans.XMLDecoder">
         <object class="java.util.LinkedList">
          <void method="add">
           <object class="com.example.Opaque"><void property="dependency"><object idref="missing"/></void></object>
          </void>
         </object>
         <object class="java.util.LinkedList"/>
         <object class="java.util.ArrayList"/>
        </java>
        """
        let imported = try TopologyProjectStore.importFiliusConfigurationXML(Data(unresolvedXML.utf8))
        XCTAssertEqual(imported.opaqueContent.fragmentCount, 1)
        XCTAssertThrowsError(
            try TopologyProjectStore.exportFiliusArchiveWithReport(
                from: imported.state,
                opaqueContent: imported.opaqueContent
            )
        ) { error in
            self.assertFLSCompatibilityError(
                error,
                expectedCode: .unsupportedConfigurationStructure,
                detailContains: "unresolved object references"
            )
        }

        var overPreamble = Data(repeating: 0x20, count: 64 * 1_024 + 1)
        overPreamble.append(Data("<java class=\"java.beans.XMLDecoder\"/>".utf8))
        XCTAssertThrowsError(try TopologyFLSOpaqueXMLPreserver.preflight(overPreamble))
        XCTAssertThrowsError(try TopologyFLSOpaqueXMLPreserver.preflight(Data("<!--".utf8)))

        let byteLimit = 32 * 1_024 * 1_024
        let nearPrefix = Data("<java class=\"java.beans.XMLDecoder\"><!--".utf8)
        let nearSuffix = Data("--></java>".utf8)
        var nearByteLimit = nearPrefix
        nearByteLimit.append(Data(repeating: 0x20, count: byteLimit - nearPrefix.count - nearSuffix.count))
        nearByteLimit.append(nearSuffix)
        XCTAssertNoThrow(try TopologyFLSOpaqueXMLPreserver.preflight(nearByteLimit))
        nearByteLimit.append(0x20)
        XCTAssertThrowsError(try TopologyFLSOpaqueXMLPreserver.preflight(nearByteLimit))

        let excessiveElements = Data(("<java class=\"java.beans.XMLDecoder\"><object class=\"java.util.LinkedList\"/>"
            + String(repeating: "<a/>", count: 200_001) + "</java>").utf8)
        XCTAssertThrowsError(try TopologyProjectStore.importFiliusConfigurationXML(excessiveElements))
    }

    func testPublicImportLexicallyHandlesUTF8AndUTF16AndRejectsWideOrOversizedTags() throws {
        enum FixtureEncoding: CaseIterable { case utf8, utf16LE, utf16BE }
        func encoded(_ xml: String, as encoding: FixtureEncoding) -> Data {
            switch encoding {
            case .utf8: return Data(xml.utf8)
            case .utf16LE:
                var data = Data([0xFF, 0xFE])
                for unit in xml.utf16 { data.append(UInt8(unit & 0xFF)); data.append(UInt8(unit >> 8)) }
                return data
            case .utf16BE:
                var data = Data([0xFE, 0xFF])
                for unit in xml.utf16 { data.append(UInt8(unit >> 8)); data.append(UInt8(unit & 0xFF)) }
                return data
            }
        }
        func document(encoding: FixtureEncoding, extra: String) -> String {
            let declaration = encoding == .utf8 ? "UTF-8" : "UTF-16"
            return """
            <?xml version="1.0" encoding="\(declaration)"?>
            <java class="java.beans.XMLDecoder">
             <string>Filius version: encoding-aware preflight</string>
             \(extra)
             <object class="java.util.LinkedList"><void method="add"><object class="filius.gui.netzwerksicht.GUIKnotenItem"><void property="typ"><string>Computer</string></void><void property="imageLabel"><object class="filius.gui.netzwerksicht.JSidebarButton"><void property="bounds"><object class="java.awt.Rectangle"><int>40</int><int>80</int><int>70</int><int>68</int></object></void><void property="text"><string>Alias host</string></void></object></void></object></void></object>
             <object class="java.util.LinkedList"/>
             <object class="java.util.ArrayList"/>
            </java>
            """
        }

        for encoding in FixtureEncoding.allCases {
            let valid = encoded(document(encoding: encoding, extra: "<\u{00E4}lias><string>opaque</string></\u{00E4}lias>"), as: encoding)
            XCTAssertEqual(try TopologyProjectStore.importFiliusConfigurationXML(valid).state.graph.nodes.count, 1)

            let attributes = (0..<65).map { "a\($0)=\"x\"" }.joined(separator: " ")
            XCTAssertThrowsError(try TopologyProjectStore.importFiliusConfigurationXML(
                encoded(document(encoding: encoding, extra: "<alias \(attributes)/>"), as: encoding)
            ))

            let oversizedName = String(repeating: "a", count: 64 * 1_024 + 1)
            XCTAssertThrowsError(try TopologyProjectStore.importFiliusConfigurationXML(
                encoded(document(encoding: encoding, extra: "<\(oversizedName)/>"), as: encoding)
            ))
        }

        let isoAttack = document(
            encoding: .utf8,
            extra: "<alias probe=\"À¢À¼\" payload=\"\(String(repeating: "x", count: 64 * 1_024))\"/>"
        ).replacingOccurrences(of: "UTF-8", with: "ISO-8859-1")
        let isoData = try XCTUnwrap(isoAttack.data(using: .isoLatin1))
        XCTAssertNotNil(isoData.range(of: Data([0xC0, 0xA2, 0xC0, 0xBC])))
        XCTAssertThrowsError(try TopologyProjectStore.importFiliusConfigurationXML(isoData))

        let invalidUTF8Sequences: [[UInt8]] = [
            [0xC0, 0xBC], [0xC0, 0xA2], [0xC1, 0xBF],
            [0xE0, 0x80, 0x80], [0xED, 0xA0, 0x80], [0xF4, 0x90, 0x80, 0x80],
        ]
        for invalid in invalidUTF8Sequences {
            var payload = Data(document(encoding: .utf8, extra: "<string>INVALID_MARKER</string>").utf8)
            let range = try XCTUnwrap(payload.range(of: Data("INVALID_MARKER".utf8)))
            payload.replaceSubrange(range, with: invalid)
            XCTAssertThrowsError(try TopologyProjectStore.importFiliusConfigurationXML(payload))
        }
    }

    func testBoundedSerializationHandlesNearLimitEscapingAndRejectsOverflowOnImportAndExport() throws {
        func payload(repeatedGreaterThan count: Int) -> Data {
            let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <java class="java.beans.XMLDecoder">
             <string>Filius version: bounded sink fixture</string>
             <string>\(String(repeating: ">", count: count))</string>
             <object class="java.util.LinkedList"><void method="add"><object class="filius.gui.netzwerksicht.GUIKnotenItem"><void property="typ"><string>Computer</string></void><void property="imageLabel"><object class="filius.gui.netzwerksicht.JSidebarButton"><void property="bounds"><object class="java.awt.Rectangle"><int>40</int><int>80</int><int>70</int><int>68</int></object></void><void property="text"><string>A</string></void></object></void></object></void></object>
             <object class="java.util.LinkedList"/>
             <object class="java.util.ArrayList"/>
            </java>
            """
            return Data(xml.utf8)
        }

        let near = try TopologyProjectStore.importFiliusConfigurationXML(payload(repeatedGreaterThan: 8_300_000))
        XCTAssertEqual(near.state.graph.nodes.count, 1)
        var expandedState = near.state
        expandedState.graph.nodes[0].displayName = String(repeating: ">", count: 100_000)
        XCTAssertThrowsError(
            try TopologyProjectStore.exportFiliusArchiveWithReport(
                from: expandedState,
                opaqueContent: near.opaqueContent
            )
        ) { error in
            self.assertFLSCompatibilityError(
                error,
                expectedCode: .unsupportedConfigurationStructure,
                detailContains: "exceeds"
            )
        }

        XCTAssertThrowsError(
            try TopologyProjectStore.importFiliusConfigurationXML(payload(repeatedGreaterThan: 8_390_000))
        ) { error in
            self.assertFLSCompatibilityError(
                error,
                expectedCode: .unsupportedConfigurationStructure,
                detailContains: "exceeds"
            )
        }

        var nativeOnly = TopologyEditorState()
        nativeOnly.graph.nodes = [TopologyNode(id: UUID(), kind: .pc, displayName: String(repeating: ">", count: 9_000_000), position: .zero)]
        XCTAssertThrowsError(try TopologyProjectStore.exportFiliusArchiveWithReport(from: nativeOnly)) { error in
            self.assertFLSArchiveError(error, expectedCode: .archiveLimitExceeded)
        }
    }

    func testImportFiliusConfigurationXMLReportsDuplicatePortReferences() throws {
        var state = TopologyEditorState()
        state.graph = TopologyGraph(
            nodes: [
                TopologyNode(id: uuid("30000000-0000-0000-0000-000000000001"), kind: .pc, position: CGPoint(x: 40, y: 80)),
                TopologyNode(id: uuid("30000000-0000-0000-0000-000000000002"), kind: .pc, position: CGPoint(x: 240, y: 80)),
            ],
            links: []
        )
        var xml = try XCTUnwrap(String(data: try TopologyProjectStore.exportFiliusConfigurationXML(from: state), encoding: .utf8))
        let marker = "<void id=\""
        var identifiers: [(range: Range<String.Index>, value: String)] = []
        var searchStart = xml.startIndex
        while let markerRange = xml.range(of: marker, range: searchStart..<xml.endIndex) {
            let valueStart = markerRange.upperBound
            guard let valueEnd = xml[valueStart...].firstIndex(of: "\"") else { break }
            let value = String(xml[valueStart..<valueEnd])
            if value.hasPrefix("Port") {
                identifiers.append((valueStart..<valueEnd, value))
            }
            searchStart = valueEnd
        }
        XCTAssertGreaterThanOrEqual(identifiers.count, 2)
        xml.replaceSubrange(identifiers[1].range, with: identifiers[0].value)

        let result = try TopologyProjectStore.importFiliusConfigurationXML(Data(xml.utf8))

        XCTAssertEqual(result.report.importedNodeCount, 2)
        XCTAssertTrue(result.report.warnings.contains(where: { $0.contains("duplicate FILIUS port reference") }))
    }

    func testImportFiliusConfigurationXMLAcceptsDeclaredISO88591Content() throws {
        let xml = """
        <?xml version="1.0" encoding="ISO-8859-1"?>
        <java version="24" class="java.beans.XMLDecoder">
         <string>Filius version: Latin-1 fixture</string>
         <object class="java.util.LinkedList">
          <void method="add">
           <object class="filius.gui.netzwerksicht.GUIKnotenItem">
            <void property="typ"><string>Computer</string></void>
            <void property="imageLabel">
             <object class="filius.gui.netzwerksicht.JSidebarButton">
              <void property="bounds"><object class="java.awt.Rectangle"><int>40</int><int>80</int><int>70</int><int>68</int></object></void>
              <void property="text"><string>B\u{00FC}ro-PC</string></void>
             </object>
            </void>
            <void property="knoten">
             <object class="filius.hardware.knoten.Rechner">
              <void property="name"><string>B\u{00FC}ro-PC</string></void>
             </object>
            </void>
           </object>
          </void>
         </object>
         <object class="java.util.LinkedList"/>
        </java>
        """
        let latin1Data = try XCTUnwrap(xml.data(using: .isoLatin1))

        let result = try TopologyProjectStore.importFiliusConfigurationXML(latin1Data)

        XCTAssertEqual(result.report.importedNodeCount, 1)
        XCTAssertEqual(result.report.skippedNodeCount, 0)
        XCTAssertEqual(result.report.warnings, [])
        XCTAssertEqual(result.state.graph.nodes.first?.displayName, "B\u{00FC}ro-PC")
        let normalizedXML = try XCTUnwrap(result.opaqueContent.sourceConfigurationXML)
        XCTAssertTrue(try XCTUnwrap(String(data: normalizedXML, encoding: .utf8)).contains("B\u{00FC}ro-PC"))
    }

    func testImportFiliusArchiveRejectsCaseVariantDuplicateCriticalEntriesBeforeExtraction() {
        let archiveData = makeMinimalZIP(entries: [
            (TopologyProjectStore.filiusConfigurationArchivePath, 0),
            ("PROJEKT/KONFIGURATION.XML", 0),
        ])

        XCTAssertThrowsError(try TopologyProjectStore.importFiliusArchive(archiveData)) { error in
            self.assertFLSArchiveError(error, expectedCode: .duplicateEntry)
        }
    }

    func testImportFiliusArchiveRejectsNonUTF8EntryNames() {
        var archiveData = makeMinimalZIP(entries: [(TopologyProjectStore.filiusConfigurationArchivePath, 0)])
        let centralOffset = archiveData.range(of: Data([0x50, 0x4b, 0x01, 0x02]))!.lowerBound
        archiveData[30] = 0xff
        archiveData[centralOffset + 46] = 0xff

        XCTAssertThrowsError(try TopologyProjectStore.importFiliusArchive(archiveData)) { error in
            self.assertFLSArchiveError(error, expectedCode: .malformedArchive)
            XCTAssertTrue((error as? TopologyFLSArchiveError)?.detail.contains("UTF-8") == true)
        }
    }

    func testImportFiliusArchiveRejectsExpandedEntryBeforeInflation() {
        var archiveData = makeMinimalZIP(entries: [(TopologyProjectStore.filiusConfigurationArchivePath, 0)])
        let centralOffset = archiveData.range(of: Data([0x50, 0x4b, 0x01, 0x02]))!.lowerBound
        let expandedSize = UInt32(128 * 1_024 * 1_024 + 1)
        setUInt32LE(expandedSize, at: 22, in: &archiveData)
        setUInt32LE(expandedSize, at: centralOffset + 24, in: &archiveData)

        XCTAssertThrowsError(try TopologyProjectStore.importFiliusArchive(archiveData)) { error in
            self.assertFLSArchiveError(error, expectedCode: .archiveLimitExceeded)
        }
    }

    func testImportFiliusArchiveRejectsDuplicateConfigurationEntries() {
        let archiveData = makeMinimalZIP(entries: [
            (TopologyProjectStore.filiusConfigurationArchivePath, 0),
            (TopologyProjectStore.filiusConfigurationArchivePath, 0),
        ])

        XCTAssertThrowsError(try TopologyProjectStore.importFiliusArchive(archiveData)) { error in
            self.assertFLSArchiveError(error, expectedCode: .duplicateEntry)
        }
    }

    func testJavaWirelessFixturePreservesSSIDAndAssociationSemantics() throws {
        let archive = try loadRepositorySampleFLSArchive(named: "Public_and_Private_Networks_2_EN.fls")
        let imported = try TopologyProjectStore.importFiliusArchive(archive)
        let accessPoint = try XCTUnwrap(imported.state.graph.nodes.first { node in
            node.kind == .networkSwitch
                && imported.state.switchConfigurationsByNodeID[node.id]?.ssid == "MyWiFi"
        })
        let wirelessHosts = imported.state.hostWirelessConfigurationsByNodeID.filter {
            $0.value.isEnabled && $0.value.ssid == "MyWiFi"
        }
        XCTAssertFalse(wirelessHosts.isEmpty)
        XCTAssertTrue(imported.state.graph.links.contains { link in
            link.sourceNodeID == accessPoint.id || link.targetNodeID == accessPoint.id
        })

        let exported = try TopologyProjectStore.exportFiliusArchive(from: imported.state)
        let reopened = try TopologyProjectStore.importFiliusArchive(exported)
        XCTAssertTrue(reopened.state.switchConfigurationsByNodeID.values.contains { $0.ssid == "MyWiFi" })
        XCTAssertTrue(reopened.state.hostWirelessConfigurationsByNodeID.values.contains {
            $0.isEnabled && $0.ssid == "MyWiFi"
        })
    }

    // MARK: - Helpers

    private enum FixtureLoadError: Error, Equatable {
        case missingFixture(relativePath: String, absolutePath: String)
        case unreadableFixture(relativePath: String, detail: String)
    }

    func testUnknownJavaFileTypePreservesZeroByteBinaryWithoutMisclassifyingInvalidText() {
        XCTAssertEqual(
            topologyImportedUnknownJavaFileBinaryContent(type: "future", content: ""),
            .binary(Data(), mediaType: "application/future")
        )
        XCTAssertEqual(
            topologyImportedUnknownJavaFileBinaryContent(type: "future", content: "  \n\t"),
            .binary(Data(), mediaType: "application/future")
        )
        XCTAssertNil(
            topologyImportedUnknownJavaFileBinaryContent(type: "future", content: "***")
        )
    }

    func testVirtualFileSystemNativeRoundTripPreservesTextBinaryImageAndDirectories() throws {
        let node = TopologyNode(id: UUID(), kind: .pc, position: CGPoint(x: 20, y: 30))
        var fileSystem = TopologyVirtualFileSystem()
        try fileSystem.createDirectory(at: "/docs")
        try fileSystem.writeTextFile(at: "/docs/note.txt", text: "hello")
        try fileSystem.writeBinaryFile(at: "/docs/blob.bin", data: Data([0, 1, 2]), mediaType: "application/octet-stream")
        try fileSystem.writeImageFile(at: "/pixel.png", data: Data([3, 4, 5]), mediaType: "image/png")
        var state = TopologyEditorState()
        state.graph = TopologyGraph(nodes: [node], links: [])
        state.virtualFileSystemsByNodeID[node.id] = fileSystem

        let fileURL = tempDirectoryURL.appendingPathComponent("virtual-filesystem.filiuspad")
        let store = TopologyProjectStore(fileURL: fileURL)
        try store.save(state: state, savedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let restored = try store.load()

        XCTAssertEqual(restored.virtualFileSystemsByNodeID[node.id], fileSystem)
    }

    func testSchemaFiveMigratesMissingVirtualFilesystemWithDeterministicDefaults() throws {
        let nodeID = uuid("A1000000-0000-0000-0000-000000000001")
        let portID = uuid("A1000000-0000-0000-0000-000000000002")
        var payload = envelopeDictionary(schemaVersion: 5)["payload"] as! [String: Any]
        payload["graph"] = [
            "nodes": [[
                "id": nodeID.uuidString,
                "kind": TopologyNodeKind.pc.rawValue,
                "displayName": "PC",
                "position": ["x": 10.0, "y": 20.0],
                "ports": [["id": portID.uuidString, "label": "eth0", "isOccupied": false]]
            ]],
            "links": []
        ]
        let fileURL = tempDirectoryURL.appendingPathComponent("schema-five-vfs.json")
        try writeJSON(envelopeDictionary(schemaVersion: 5, payload: payload), to: fileURL)

        let restored = try TopologyProjectStore(fileURL: fileURL).load()
        XCTAssertEqual(
            try restored.virtualFileSystemsByNodeID[nodeID]?.textFile(at: "/home/lab-notes.txt"),
            "Document deterministic runtime notes here."
        )
    }

    func testSchemaSixRejectsMissingVirtualFilesystemField() throws {
        var envelope = envelopeDictionary(schemaVersion: 6)
        var payload = envelope["payload"] as! [String: Any]
        payload.removeValue(forKey: "virtualFileSystems")
        envelope["payload"] = payload
        let fileURL = tempDirectoryURL.appendingPathComponent("schema-six-missing-vfs.json")
        try writeJSON(envelope, to: fileURL)

        XCTAssertThrowsError(try TopologyProjectStore(fileURL: fileURL).load()) { error in
            self.assertPersistenceError(error, expectedOperation: .load, expectedCode: .malformedPayload)
        }
    }

    func testJavaFLSFilesystemImportExportReopenPreservesSemanticFiles() throws {
        let archive = try loadRepositorySampleFLSArchive(named: "dns_server.fls")
        let imported = try TopologyProjectStore.importFiliusArchive(archive)
        XCTAssertTrue(imported.state.virtualFileSystemsByNodeID.values.contains { fileSystem in
            fileSystem.allEntries().contains { $0.name == "hosts" }
        })
        let importedDNSServers = imported.state.graph.nodes.filter { node in
            imported.state.runtimeInstalledProgramsByNodeID[node.id]?.contains(.dnsServer) == true
        }
        XCTAssertFalse(importedDNSServers.isEmpty)
        let importedWebServerRecordOwner = try XCTUnwrap(importedDNSServers.first { node in
            imported.state.runtimeDNSServerConfigurationsByNodeID[node.id]?.recordsByHostname["www.filius.de"]?.targetIPAddress == "141.99.5.10"
        })
        XCTAssertNotNil(try imported.state.virtualFileSystemsByNodeID[importedWebServerRecordOwner.id]?.textFile(at: TopologyRuntimeDNSHostsFile.path))

        let exported = try TopologyProjectStore.exportFiliusArchiveWithReport(from: imported.state)
        let reopened = try TopologyProjectStore.importFiliusArchive(exported.data)
        XCTAssertEqual(virtualFileSystemSignatures(imported.state), virtualFileSystemSignatures(reopened.state))
        XCTAssertEqual(dnsServerSignatures(imported.state), dnsServerSignatures(reopened.state))
    }

    func testSchemaSixSaveSeedsMissingPCFilesystemAndReloads() throws {
        let node = TopologyNode(id: UUID(), kind: .pc, position: CGPoint(x: 15, y: 25))
        var state = TopologyEditorState()
        state.graph = TopologyGraph(nodes: [node], links: [])
        XCTAssertNil(state.virtualFileSystemsByNodeID[node.id])

        let fileURL = tempDirectoryURL.appendingPathComponent("schema-six-seeded-vfs.json")
        let store = TopologyProjectStore(fileURL: fileURL)
        try store.save(state: state, savedAt: Date(timeIntervalSince1970: 1_700_000_001))
        let restored = try store.load()

        XCTAssertEqual(
            try restored.virtualFileSystemsByNodeID[node.id]?.textFile(at: "/home/lab-notes.txt"),
            "Document deterministic runtime notes here."
        )
    }

    func testVirtualFileSystemRejectsWhitespaceComponentsAndCaseInsensitiveSiblingCollisions() throws {
        var fileSystem = TopologyVirtualFileSystem()
        try fileSystem.createDirectory(at: "/docs")
        try fileSystem.writeTextFile(at: "/docs/Readme.txt", text: "one")

        XCTAssertThrowsError(try fileSystem.writeTextFile(at: "/docs/ note.txt", text: "two")) { error in
            XCTAssertEqual(error as? TopologyVirtualFileSystemError, .invalidPathComponent(" note.txt"))
        }
        try fileSystem.writeTextFile(at: "/DOCS/readme.TXT", text: "two", overwrite: true)
        XCTAssertEqual(try fileSystem.textFile(at: "/docs/Readme.txt"), "two")
        XCTAssertEqual(try fileSystem.entry(at: "/DOCS/README.TXT").path, "/docs/Readme.txt")
        XCTAssertThrowsError(try fileSystem.writeTextFile(at: "/docs/README.txt", text: "three", overwrite: false)) { error in
            XCTAssertEqual(
                error as? TopologyVirtualFileSystemError,
                .caseInsensitiveSiblingCollision(
                    existing: "/docs/Readme.txt",
                    attempted: "/docs/README.txt"
                )
            )
        }

        XCTAssertThrowsError(
            try TopologyVirtualFileSystem(entries: [
                TopologyVirtualFileEntry(path: "/docs", content: .directory),
                TopologyVirtualFileEntry(path: "/docs/Readme.txt", content: .text("one")),
                TopologyVirtualFileEntry(path: "/docs/readme.TXT", content: .text("two")),
            ])
        ) { error in
            XCTAssertEqual(
                error as? TopologyVirtualFileSystemError,
                .caseInsensitiveSiblingCollision(
                    existing: "/docs/Readme.txt",
                    attempted: "/docs/readme.TXT"
                )
            )
        }
    }

    func testVirtualFileSystemMutationQuotasAreExplicitAndAtomic() throws {
        var fileSystem = TopologyVirtualFileSystem()
        let oversized = Data(repeating: 0x41, count: TopologyVirtualFileSystem.maximumFileBytes + 1)

        XCTAssertThrowsError(try fileSystem.writeBinaryFile(at: "/oversized.bin", data: oversized)) { error in
            guard let fileSystemError = error as? TopologyVirtualFileSystemError,
                  case let .fileSizeQuotaExceeded(path, actualBytes, limitBytes) = fileSystemError
            else {
                return XCTFail("Expected per-file quota error, got \(error)")
            }
            XCTAssertEqual(path, "/oversized.bin")
            XCTAssertEqual(actualBytes, TopologyVirtualFileSystem.maximumFileBytes + 1)
            XCTAssertEqual(limitBytes, TopologyVirtualFileSystem.maximumFileBytes)
        }
        XCTAssertFalse(fileSystem.contains("/oversized.bin"))

        let maximumSized = Data(repeating: 0x42, count: TopologyVirtualFileSystem.maximumFileBytes)
        for index in 0..<4 {
            try fileSystem.writeBinaryFile(at: "/file-\(index).bin", data: maximumSized)
        }
        XCTAssertThrowsError(try fileSystem.writeBinaryFile(at: "/file-4.bin", data: maximumSized)) { error in
            guard let fileSystemError = error as? TopologyVirtualFileSystemError,
                  case .deviceSizeQuotaExceeded = fileSystemError
            else {
                return XCTFail("Expected per-device quota error, got \(error)")
            }
        }
        XCTAssertFalse(fileSystem.contains("/file-4.bin"))
    }

    func testNativeSaveAndJavaExportRejectProjectVirtualFileSystemQuota() throws {
        var fileSystem = TopologyVirtualFileSystem()
        let maximumSized = Data(repeating: 0x43, count: TopologyVirtualFileSystem.maximumFileBytes)
        try fileSystem.writeBinaryFile(at: "/payload.bin", data: maximumSized)

        let nodes = (0..<9).map { index in
            TopologyNode(id: UUID(), kind: .pc, position: CGPoint(x: CGFloat(index * 20), y: 20))
        }
        var state = TopologyEditorState()
        state.graph = TopologyGraph(nodes: nodes, links: [])
        for node in nodes {
            state.virtualFileSystemsByNodeID[node.id] = fileSystem
        }

        let fileURL = tempDirectoryURL.appendingPathComponent("over-project-vfs-quota.json")
        XCTAssertThrowsError(try TopologyProjectStore(fileURL: fileURL).save(state: state)) { error in
            self.assertPersistenceError(error, expectedOperation: .save, expectedCode: .encodingFailed)
        }
        XCTAssertThrowsError(try TopologyProjectStore.exportFiliusArchive(from: state)) { error in
            XCTAssertEqual((error as? TopologyFLSArchiveError)?.code, .archiveLimitExceeded)
            XCTAssertEqual((error as? TopologyFLSArchiveError)?.entryPath, TopologyProjectStore.filiusConfigurationArchivePath)
        }
        let configuration = try TopologyProjectStore.exportFiliusConfigurationXMLWithReport(from: state)
        XCTAssertTrue(configuration.report.warnings.contains { $0.contains("project quotas were exceeded") })
    }

    func testSchemaSixDecodeRejectsOversizedVirtualFile() throws {
        let nodeID = uuid("A2000000-0000-0000-0000-000000000001")
        let portID = uuid("A2000000-0000-0000-0000-000000000002")
        var envelope = envelopeDictionary(schemaVersion: 6)
        var payload = envelope["payload"] as! [String: Any]
        payload["graph"] = [
            "nodes": [[
                "id": nodeID.uuidString,
                "kind": TopologyNodeKind.pc.rawValue,
                "displayName": "PC",
                "position": ["x": 10.0, "y": 20.0],
                "ports": [["id": portID.uuidString, "label": "eth0", "isOccupied": false]]
            ]],
            "links": []
        ]
        let oversized = Data(repeating: 0x44, count: TopologyVirtualFileSystem.maximumFileBytes + 1)
        payload["virtualFileSystems"] = [[
            "nodeID": nodeID.uuidString,
            "entries": [[
                "path": "/oversized.bin",
                "kind": "binary",
                "data": oversized.base64EncodedString(),
                "mediaType": "application/octet-stream"
            ]]
        ]]
        envelope["payload"] = payload
        let fileURL = tempDirectoryURL.appendingPathComponent("schema-six-oversized-vfs.json")
        try writeJSON(envelope, to: fileURL)

        XCTAssertThrowsError(try TopologyProjectStore(fileURL: fileURL).load()) { error in
            self.assertPersistenceError(error, expectedOperation: .load, expectedCode: .malformedPayload)
        }
    }

    func testJavaExportSanitizesXML10DisallowedTextWithAttributedWarning() throws {
        let node = TopologyNode(id: UUID(), kind: .pc, position: CGPoint(x: 30, y: 30))
        var fileSystem = TopologyVirtualFileSystem()
        try fileSystem.writeTextFile(at: "/unsafe.txt", text: "before\u{0}after")
        var state = TopologyEditorState()
        state.graph = TopologyGraph(nodes: [node], links: [])
        state.virtualFileSystemsByNodeID[node.id] = fileSystem

        let exported = try TopologyProjectStore.exportFiliusConfigurationXMLWithReport(from: state)
        XCTAssertFalse(exported.data.contains(0))
        XCTAssertTrue(exported.report.warnings.contains {
            $0.contains("XML 1.0-disallowed") && $0.contains("/unsafe.txt") && $0.contains(node.displayName)
        })
        let reopened = try TopologyProjectStore.importFiliusConfigurationXML(exported.data)
        XCTAssertEqual(
            try reopened.state.virtualFileSystemsByNodeID.values.first?.textFile(at: "/unsafe.txt"),
            "before\u{FFFD}after"
        )
    }

    private func loadRepositorySampleFLSArchive(named fileName: String, file: StaticString = #filePath) throws -> Data {
        let archiveURL = repositoryRootURL(from: file)
            .appendingPathComponent("javaversion")
            .appendingPathComponent("filius-master")
            .appendingPathComponent("beispiele")
            .appendingPathComponent(fileName)
        return try Data(contentsOf: archiveURL, options: [.mappedIfSafe])
    }

    private func makePayloadZIP(
        path: String,
        method: UInt16,
        payload: Data,
        uncompressedSize: UInt32
    ) -> Data {
        let pathData = Data(path.utf8)
        var archive = Data()
        appendUInt32LE(0x04034b50, to: &archive)
        appendUInt16LE(20, to: &archive)
        appendUInt16LE(0x0800, to: &archive)
        appendUInt16LE(method, to: &archive)
        appendUInt16LE(0, to: &archive)
        appendUInt16LE(0x0021, to: &archive)
        appendUInt32LE(0, to: &archive)
        appendUInt32LE(UInt32(payload.count), to: &archive)
        appendUInt32LE(uncompressedSize, to: &archive)
        appendUInt16LE(UInt16(pathData.count), to: &archive)
        appendUInt16LE(0, to: &archive)
        archive.append(pathData)
        archive.append(payload)

        let centralOffset = UInt32(archive.count)
        appendUInt32LE(0x02014b50, to: &archive)
        appendUInt16LE(20, to: &archive)
        appendUInt16LE(20, to: &archive)
        appendUInt16LE(0x0800, to: &archive)
        appendUInt16LE(method, to: &archive)
        appendUInt16LE(0, to: &archive)
        appendUInt16LE(0x0021, to: &archive)
        appendUInt32LE(0, to: &archive)
        appendUInt32LE(UInt32(payload.count), to: &archive)
        appendUInt32LE(uncompressedSize, to: &archive)
        appendUInt16LE(UInt16(pathData.count), to: &archive)
        appendUInt16LE(0, to: &archive)
        appendUInt16LE(0, to: &archive)
        appendUInt16LE(0, to: &archive)
        appendUInt16LE(0, to: &archive)
        appendUInt32LE(0, to: &archive)
        appendUInt32LE(0, to: &archive)
        archive.append(pathData)

        appendUInt32LE(0x06054b50, to: &archive)
        appendUInt16LE(0, to: &archive)
        appendUInt16LE(0, to: &archive)
        appendUInt16LE(1, to: &archive)
        appendUInt16LE(1, to: &archive)
        appendUInt32LE(UInt32(46 + pathData.count), to: &archive)
        appendUInt32LE(centralOffset, to: &archive)
        appendUInt16LE(0, to: &archive)
        return archive
    }

    private func makeMinimalZIP(entries: [(path: String, method: UInt16)]) -> Data {
        var archive = Data()
        var centralRecords: [(pathData: Data, method: UInt16, offset: UInt32)] = []

        for entry in entries {
            let pathData = Data(entry.path.utf8)
            let offset = UInt32(archive.count)
            appendUInt32LE(0x04034b50, to: &archive)
            appendUInt16LE(20, to: &archive)
            appendUInt16LE(0x0800, to: &archive)
            appendUInt16LE(entry.method, to: &archive)
            appendUInt16LE(0, to: &archive)
            appendUInt16LE(0x0021, to: &archive)
            appendUInt32LE(0, to: &archive)
            appendUInt32LE(0, to: &archive)
            appendUInt32LE(0, to: &archive)
            appendUInt16LE(UInt16(pathData.count), to: &archive)
            appendUInt16LE(0, to: &archive)
            archive.append(pathData)
            centralRecords.append((pathData, entry.method, offset))
        }

        let centralOffset = UInt32(archive.count)
        for record in centralRecords {
            appendUInt32LE(0x02014b50, to: &archive)
            appendUInt16LE(20, to: &archive)
            appendUInt16LE(20, to: &archive)
            appendUInt16LE(0x0800, to: &archive)
            appendUInt16LE(record.method, to: &archive)
            appendUInt16LE(0, to: &archive)
            appendUInt16LE(0x0021, to: &archive)
            appendUInt32LE(0, to: &archive)
            appendUInt32LE(0, to: &archive)
            appendUInt32LE(0, to: &archive)
            appendUInt16LE(UInt16(record.pathData.count), to: &archive)
            appendUInt16LE(0, to: &archive)
            appendUInt16LE(0, to: &archive)
            appendUInt16LE(0, to: &archive)
            appendUInt16LE(0, to: &archive)
            appendUInt32LE(0, to: &archive)
            appendUInt32LE(record.offset, to: &archive)
            archive.append(record.pathData)
        }

        let centralSize = UInt32(archive.count) - centralOffset
        appendUInt32LE(0x06054b50, to: &archive)
        appendUInt16LE(0, to: &archive)
        appendUInt16LE(0, to: &archive)
        appendUInt16LE(UInt16(centralRecords.count), to: &archive)
        appendUInt16LE(UInt16(centralRecords.count), to: &archive)
        appendUInt32LE(centralSize, to: &archive)
        appendUInt32LE(centralOffset, to: &archive)
        appendUInt16LE(0, to: &archive)
        return archive
    }

    private func appendUInt16LE(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private func setUInt16LE(_ value: UInt16, at offset: Int, in data: inout Data) {
        data[offset] = UInt8(truncatingIfNeeded: value)
        data[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    }

    private func setUInt32LE(_ value: UInt32, at offset: Int, in data: inout Data) {
        data[offset] = UInt8(truncatingIfNeeded: value)
        data[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        data[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        data[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }

    private func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 24))
    }

    private func assertFLSArchiveError(
        _ error: Error,
        expectedCode: TopologyFLSArchiveErrorCode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let archiveError = error as? TopologyFLSArchiveError else {
            XCTFail("Expected TopologyFLSArchiveError, got \(type(of: error))", file: file, line: line)
            return
        }
        XCTAssertEqual(archiveError.code, expectedCode, file: file, line: line)
        XCTAssertFalse(archiveError.detail.isEmpty, file: file, line: line)
    }

    private func assertFLSCompatibilityError(
        _ error: Error,
        expectedCode: TopologyFLSCompatibilityErrorCode,
        detailContains expectedDetail: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let compatibilityError = error as? TopologyFLSCompatibilityError else {
            XCTFail("Expected TopologyFLSCompatibilityError, got \(type(of: error))", file: file, line: line)
            return
        }
        XCTAssertEqual(compatibilityError.code, expectedCode, file: file, line: line)
        XCTAssertTrue(
            compatibilityError.detail.contains(expectedDetail),
            "Expected detail containing '\(expectedDetail)', got '\(compatibilityError.detail)'",
            file: file,
            line: line
        )
    }

    private func loadSampleFLSFixture(named fileName: String, file: StaticString = #filePath) throws -> Data {
        let relativePath = "ios/FiliusPadTests/Fixtures/FLS/\(fileName)"
        let fixtureURL = repositoryRootURL(from: file)
            .appendingPathComponent("ios")
            .appendingPathComponent("FiliusPadTests")
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("FLS")
            .appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            throw FixtureLoadError.missingFixture(relativePath: relativePath, absolutePath: fixtureURL.path)
        }

        do {
            return try Data(contentsOf: fixtureURL, options: [.mappedIfSafe])
        } catch {
            throw FixtureLoadError.unreadableFixture(relativePath: relativePath, detail: String(describing: error))
        }
    }

    private func repositoryRootURL(from file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: String(describing: file))
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func semanticNodeSignature(_ nodes: [TopologyNode]) -> [String] {
        nodes
            .map { node in
                let x = Int(node.position.x.rounded())
                let y = Int(node.position.y.rounded())
                return "\(node.kind.rawValue)@\(x)x\(y)"
            }
            .sorted()
    }

    private func writeProjectWithRuntimeInterfaceEntry(
        node: TopologyNode,
        entryNodeID: UUID,
        entryPortID: UUID,
        filename: String
    ) throws -> URL {
        var state = TopologyEditorState()
        state.graph = TopologyGraph(nodes: [node], links: [])

        let fileURL = tempDirectoryURL.appendingPathComponent(filename)
        let store = TopologyProjectStore(fileURL: fileURL)
        try store.save(state: state, savedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let data = try Data(contentsOf: fileURL)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var payload = try XCTUnwrap(envelope["payload"] as? [String: Any])
        payload["runtimeInterfaceConfigurations"] = [[
            "nodeID": entryNodeID.uuidString,
            "portID": entryPortID.uuidString,
            "ipAddress": "192.168.0.10",
            "subnetMask": "255.255.255.0"
        ]]
        envelope["payload"] = payload
        try writeJSON(envelope, to: fileURL)
        return fileURL
    }

    private func dnsServerSignatures(_ state: TopologyEditorState) -> [String] {
        state.graph.nodes.compactMap { node in
            guard state.runtimeInstalledProgramsByNodeID[node.id]?.contains(.dnsServer) == true else { return nil }
            let records = state.runtimeDNSServerConfigurationsByNodeID[node.id]?.recordsByHostname.values
                .map { "\($0.hostname)=\($0.targetIPAddress)" }
                .sorted() ?? []
            let hosts = state.virtualFileSystemsByNodeID[node.id]
                .flatMap { try? $0.textFile(at: TopologyRuntimeDNSHostsFile.path) } ?? ""
            return "\(node.displayName)|\(records.joined(separator: ","))|\(hosts)"
        }.sorted()
    }

    private func virtualFileSystemSignatures(_ state: TopologyEditorState) -> [String] {
        state.graph.nodes.flatMap { node in
            (state.virtualFileSystemsByNodeID[node.id]?.allEntries() ?? []).map { entry in
                let content: String
                switch entry.content {
                case .directory:
                    content = "directory"
                case let .text(value):
                    content = "text:\(Data(value.utf8).base64EncodedString())"
                case let .binary(data, mediaType):
                    content = "binary:\(mediaType ?? ""):\(data.base64EncodedString())"
                case let .image(data, mediaType):
                    content = "image:\(mediaType):\(data.base64EncodedString())"
                }
                return "\(node.displayName)|\(entry.path)|\(content)"
            }
        }.sorted()
    }

    private func writeJSON(_ object: [String: Any], to fileURL: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: fileURL)
    }

    private func remoteLinkPayload(
        nodeID: UUID,
        portID: UUID,
        remoteLinkConfigurations: [[String: Any]]? = nil
    ) -> [String: Any] {
        var payload = envelopeDictionary(schemaVersion: 4)["payload"] as! [String: Any]
        payload["graph"] = [
            "nodes": [[
                "id": nodeID.uuidString,
                "kind": TopologyNodeKind.remoteLink.rawValue,
                "displayName": "Remote Link",
                "position": ["x": 40.0, "y": 60.0],
                "ports": [[
                    "id": portID.uuidString,
                    "label": "remote0",
                    "isOccupied": false
                ]]
            ]],
            "links": []
        ]
        if let remoteLinkConfigurations {
            payload["remoteLinkConfigurations"] = remoteLinkConfigurations
        }
        return payload
    }

    private func envelopeDictionary(
        format: String = TopologyProjectStore.formatIdentifier,
        schemaVersion: Int = TopologyProjectStore.supportedSchemaVersion,
        payload: [String: Any]? = nil,
        includeRemoteLinkConfigurations: Bool? = nil,
        includeDocumentationItems: Bool? = nil,
        extraEnvelopeFields: [String: Any] = [:]
    ) -> [String: Any] {
        let defaultPayload: [String: Any] = [
            "graph": [
                "nodes": [],
                "links": []
            ],
            "viewport": [
                "offset": ["width": 0.0, "height": 0.0],
                "scale": 1.0
            ],
            "runtimeDeviceConfigurations": [],
            "runtimeInterfaceConfigurations": [],
            "runtimeManualRouteTables": [],
            "persistenceRevision": 0
        ]
        var resolvedPayload = payload ?? defaultPayload
        let shouldIncludeRemoteLinkConfigurations = includeRemoteLinkConfigurations ?? (schemaVersion >= 5)
        if shouldIncludeRemoteLinkConfigurations, resolvedPayload["remoteLinkConfigurations"] == nil {
            resolvedPayload["remoteLinkConfigurations"] = []
        }
        if schemaVersion >= 6, resolvedPayload["virtualFileSystems"] == nil {
            let graph = resolvedPayload["graph"] as? [String: Any]
            let nodes = graph?["nodes"] as? [[String: Any]] ?? []
            resolvedPayload["virtualFileSystems"] = nodes.compactMap { node -> [String: Any]? in
                guard let nodeID = node["id"] as? String,
                      let kind = node["kind"] as? String,
                      kind == TopologyNodeKind.pc.rawValue || kind == TopologyNodeKind.notebook.rawValue
                else { return nil }
                return ["nodeID": nodeID, "entries": []] as [String: Any]
            }
        }
        let shouldIncludeDocumentationItems = includeDocumentationItems ?? (schemaVersion >= 7)
        if shouldIncludeDocumentationItems, resolvedPayload["documentationItems"] == nil {
            resolvedPayload["documentationItems"] = []
        } else if !shouldIncludeDocumentationItems {
            resolvedPayload.removeValue(forKey: "documentationItems")
        }
        if schemaVersion >= 8, resolvedPayload["runtimeDNSServerConfigurations"] == nil {
            resolvedPayload["runtimeDNSServerConfigurations"] = []
        }
        if schemaVersion >= 9 {
            if resolvedPayload["protocolApplicationDefinitions"] == nil {
                resolvedPayload["protocolApplicationDefinitions"] = []
            }
            if resolvedPayload["protocolApplicationInstallations"] == nil {
                resolvedPayload["protocolApplicationInstallations"] = []
            }
        }

        var envelope: [String: Any] = [
            "format": format,
            "schemaVersion": schemaVersion,
            "savedAt": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_700_000_000)),
            "saveReason": TopologyProjectSaveReason.autosave.rawValue,
            "payload": resolvedPayload
        ]

        for (key, value) in extraEnvelopeFields {
            envelope[key] = value
        }

        return envelope
    }

    private func assertPersistenceError(
        _ error: Error,
        expectedOperation: TopologyProjectPersistenceOperation,
        expectedCode: TopologyProjectPersistenceErrorCode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let persistenceError = error as? TopologyProjectPersistenceError else {
            XCTFail("Expected TopologyProjectPersistenceError, got \(type(of: error))", file: file, line: line)
            return
        }

        XCTAssertEqual(persistenceError.operation, expectedOperation, file: file, line: line)
        XCTAssertEqual(persistenceError.code, expectedCode, file: file, line: line)
        XCTAssertFalse(persistenceError.detail.isEmpty, file: file, line: line)
    }

    private func uuid(_ rawValue: String) -> UUID {
        UUID(uuidString: rawValue) ?? UUID()
    }
}
