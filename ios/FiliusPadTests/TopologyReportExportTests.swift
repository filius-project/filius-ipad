import Foundation
import XCTest
@testable import FiliusPad

final class TopologyReportExportTests: XCTestCase {
    func testEmptyProjectProducesAllStableSectionsAndVersionedCaptureHeader() {
        let state = TopologyEditorState()
        let report = TopologyDetailedReportBuilder.makeDocument(state: state)
        let text = TopologyDetailedReportTextRenderer.render(report)
        let capture = TopologyPacketCaptureTextExportFormatter.renderTSV(state: state)

        XCTAssertEqual(report.formatVersion, 4)
        XCTAssertEqual(report.sections.map(\.id), [
            "project-metadata", "links", "devices-interfaces", "applications", "routes", "dns",
            "dhcp", "nat-port-forwarding", "firewall", "web-services", "email", "remote-links",
            "packet-loss", "network-traffic-summary", "network-traffic-events",
        ])
        XCTAssertTrue(text.contains("# format-version: 4"))
        XCTAssertTrue(text.contains("[devices-interfaces] Devices and interfaces"))
        XCTAssertTrue(text.contains("Empty project — no devices or interfaces"))
        XCTAssertTrue(capture.contains("# FiliusPad packet-capture\n# format-version: 2"))
        XCTAssertTrue(capture.contains("# discarded-before-capture-count: 0"))
        XCTAssertTrue(capture.contains("# record-count: 0"))
        XCTAssertTrue(capture.contains("\nnumber\ttime_ms\ttrace_id\t"))
    }

    func testCaptureOrderingIsTimeThenTraceIDAndEscapingRoundTrips() {
        let nodeID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let interfaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let traces = [
            trace(id: 20, time: 100, nodeID: nodeID, interfaceID: interfaceID, detail: "later"),
            trace(id: 10, time: 100, nodeID: nodeID, interfaceID: interfaceID, detail: "first\tline\nnext\\slash"),
            trace(id: 5, time: 200, nodeID: nodeID, interfaceID: interfaceID, detail: "last"),
        ]

        let document = TopologyPacketCaptureTextExportFormatter.makeDocument(traces: traces)
        XCTAssertEqual(document.records.map(\.traceID), [10, 20, 5])

        let exported = TopologyPacketCaptureTextExportFormatter.renderTSV(document)
        XCTAssertTrue(exported.contains("first\\tline\\nnext\\\\slash"))
        XCTAssertEqual(
            TopologyPacketCaptureTextExportFormatter.unescapeTSVField("first\\tline\\nnext\\\\slash"),
            "first\tline\nnext\\slash"
        )
    }

    func testCaptureExportMatchesPacketViewerEligibility() {
        let nodeID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let interfaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        var engine = TopologyNetworkRuntimeEngine(seed: 101)
        engine.recordTrace(
            frameIdentity: 10,
            nodeID: nodeID,
            interfaceID: interfaceID,
            direction: .outbound,
            layer: .application,
            operation: .sent,
            detail: "frame-backed"
        )
        engine.recordTrace(
            packetIdentity: 20,
            nodeID: nodeID,
            interfaceID: interfaceID,
            direction: .inbound,
            layer: .application,
            operation: .received,
            detail: "packet-backed"
        )
        engine.recordTrace(
            frameIdentity: 30,
            packetIdentity: 31,
            nodeID: nodeID,
            interfaceID: interfaceID,
            direction: .local,
            layer: .application,
            operation: .compatibilityAdapter,
            detail: "compatibility adapter"
        )
        engine.recordTrace(
            frameIdentity: 40,
            nodeID: nodeID,
            interfaceID: nil,
            direction: .outbound,
            layer: .application,
            operation: .sent,
            detail: "no interface"
        )
        engine.recordTrace(
            nodeID: nodeID,
            interfaceID: interfaceID,
            direction: .outbound,
            layer: .application,
            operation: .sent,
            detail: "no packet identity"
        )

        let document = TopologyPacketCaptureTextExportFormatter.makeDocument(
            traces: engine.state.packetTraces
        )
        let displayedTraceIDs = engine.packetCaptureMessageRows(nodeID: nodeID).map { $0.trace.id }

        XCTAssertEqual(document.records.map(\.traceID), displayedTraceIDs)
        XCTAssertEqual(document.records.map(\.traceID), [1, 2])
        XCTAssertEqual(document.records.map(\.number), [1, 2])
        let exported = TopologyPacketCaptureTextExportFormatter.renderTSV(document)
        XCTAssertTrue(exported.contains("# record-count: 2"))
        XCTAssertTrue(exported.contains("frame-backed"))
        XCTAssertTrue(exported.contains("packet-backed"))
        XCTAssertFalse(exported.contains("compatibility adapter"))
        XCTAssertFalse(exported.contains("no interface"))
        XCTAssertFalse(exported.contains("no packet identity"))
    }

    func testLargeCaptureIsBoundedAndExportsDiscardedTraceCount() throws {
        let nodeID = UUID(uuidString: "00000000-0000-0000-0000-000000000131")!
        let interfaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000132")!
        var state = TopologyEditorState()
        state.networkRuntime = TopologyNetworkRuntimeEngine(
            seed: 131,
            packetTraceRetentionPolicy: TopologyPacketTraceRetentionPolicy(
                maximumEventCount: 256,
                evictionBatchSize: 64
            )
        )

        for identity in UInt64(1)...UInt64(2_048) {
            state.networkRuntime.recordTrace(
                frameIdentity: identity,
                nodeID: nodeID,
                interfaceID: interfaceID,
                direction: .outbound,
                layer: .dataLink,
                operation: .sent,
                detail: "bounded-capture-\(identity)"
            )
        }

        XCTAssertEqual(state.networkRuntime.state.packetTraces.count, 256)
        XCTAssertEqual(state.networkRuntime.state.packetTraces.first?.id, 1_793)
        XCTAssertEqual(state.networkRuntime.state.packetTraces.last?.id, 2_048)
        XCTAssertEqual(state.networkRuntime.state.discardedPacketTraceCount, 1_792)

        let document = TopologyPacketCaptureTextExportFormatter.makeDocument(state: state)
        XCTAssertEqual(document.records.count, 256)
        XCTAssertEqual(document.discardedBeforeCaptureCount, 1_792)

        let export = TopologyPacketCaptureTextExportFormatter.renderTSV(document)
        XCTAssertTrue(export.contains("# discarded-before-capture-count: 1792"))
        XCTAssertTrue(export.contains("# record-count: 256"))
        XCTAssertFalse(export.contains("bounded-capture-1792"))
        XCTAssertTrue(export.contains("bounded-capture-1793"))

        let report = TopologyDetailedReportBuilder.makeDocument(state: state)
        let metadata = try XCTUnwrap(report.sections.first { $0.id == "project-metadata" })
        XCTAssertEqual(metadata.rows.first { $0[0] == "retainedRuntimeTraceCount" }?[1], "256")
        XCTAssertEqual(metadata.rows.first { $0[0] == "discardedRuntimeTraceCount" }?[1], "1792")
    }

    func testDetailedTrafficReportMatchesViewerAndTextExportEligibility() throws {
        var state = TopologyEditorState()
        let nodeID = UUID(uuidString: "00000000-0000-0000-0000-000000000121")!
        let interfaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000122")!
        state.networkRuntime.recordTrace(
            frameIdentity: 10,
            nodeID: nodeID,
            interfaceID: interfaceID,
            direction: .outbound,
            layer: .application,
            operation: .sent,
            detail: "viewer-export-report eligible"
        )
        state.networkRuntime.recordTrace(
            nodeID: nodeID,
            interfaceID: nil,
            direction: .outbound,
            layer: .application,
            operation: .sent,
            detail: "identity-free diagnostic"
        )
        state.networkRuntime.recordTrace(
            frameIdentity: 20,
            packetIdentity: 21,
            nodeID: nodeID,
            interfaceID: interfaceID,
            direction: .outbound,
            layer: .application,
            operation: .compatibilityAdapter,
            detail: "compatibility diagnostic"
        )

        let capture = TopologyPacketCaptureTextExportFormatter.makeDocument(state: state)
        let displayedTraceIDs = state.networkRuntime.packetCaptureMessageRows(nodeID: nodeID)
            .map { $0.trace.id }
        let report = TopologyDetailedReportBuilder.makeDocument(state: state)
        let metadata = try XCTUnwrap(report.sections.first { $0.id == "project-metadata" })
        let summary = try XCTUnwrap(report.sections.first { $0.id == "network-traffic-summary" })
        let events = try XCTUnwrap(report.sections.first { $0.id == "network-traffic-events" })

        XCTAssertEqual(capture.records.map(\.traceID), displayedTraceIDs)
        XCTAssertEqual(events.rows.map { UInt64($0[2]) }, displayedTraceIDs.map(Optional.some))
        XCTAssertEqual(events.rows.map { $0.last }, ["viewer-export-report eligible"])
        XCTAssertEqual(summary.rows.map { $0[3] }, ["1"])
        XCTAssertEqual(metadata.rows.first { $0[0] == "packetCaptureRecordCount" }?[1], "1")
        XCTAssertEqual(metadata.rows.first { $0[0] == "retainedRuntimeTraceCount" }?[1], "3")
    }

    func testCaptureScopeIsAppliedAfterPacketViewerEligibility() {
        let firstNode = UUID(uuidString: "00000000-0000-0000-0000-000000000111")!
        let secondNode = UUID(uuidString: "00000000-0000-0000-0000-000000000112")!
        let selectedInterface = UUID(uuidString: "00000000-0000-0000-0000-000000000113")!
        let otherInterface = UUID(uuidString: "00000000-0000-0000-0000-000000000114")!
        let traces = [
            trace(
                id: 1,
                time: 1,
                frameIdentity: 10,
                packetIdentity: nil,
                nodeID: firstNode,
                interfaceID: selectedInterface,
                operation: .sent,
                detail: "selected"
            ),
            trace(
                id: 2,
                time: 2,
                frameIdentity: 20,
                packetIdentity: nil,
                nodeID: firstNode,
                interfaceID: selectedInterface,
                operation: .compatibilityAdapter,
                detail: "selected but ineligible"
            ),
            trace(
                id: 3,
                time: 3,
                frameIdentity: 30,
                packetIdentity: nil,
                nodeID: firstNode,
                interfaceID: otherInterface,
                operation: .sent,
                detail: "wrong interface"
            ),
            trace(
                id: 4,
                time: 4,
                frameIdentity: 40,
                packetIdentity: nil,
                nodeID: secondNode,
                interfaceID: selectedInterface,
                operation: .sent,
                detail: "wrong node"
            ),
        ]

        let document = TopologyPacketCaptureTextExportFormatter.makeDocument(
            traces: traces,
            scope: .init(nodeID: firstNode, interfaceID: selectedInterface)
        )

        XCTAssertEqual(document.records.map(\.traceID), [1])
        XCTAssertEqual(document.records.first?.detail, "selected")
    }

    func testCaptureRedactsSecretsPayloadsAndMessageBodiesButKeepsSafeHeaders() {
        let nodeID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let trace = TopologyPacketTraceEvent(
            id: 1,
            timeMilliseconds: 7,
            frameIdentity: 3,
            packetIdentity: 4,
            nodeID: nodeID,
            interfaceID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            direction: .outbound,
            layer: .application,
            operation: .sent,
            beforeHeaders: [],
            afterHeaders: [
                .init(name: "kind", value: "SMTP"),
                .init(name: "sourceIP", value: "10.0.0.1"),
                .init(name: "password", value: "super-secret"),
                .init(name: "linkCode", value: "classroom-secret"),
                .init(name: "payload", value: "message body should not appear"),
                .init(name: "subject", value: "safe subject"),
            ],
            detail: "From: a@example.com\nTo: b@example.com\nSubject: hello\n\nprivate body"
        )

        let exported = TopologyPacketCaptureTextExportFormatter.renderTSV(
            TopologyPacketCaptureTextExportFormatter.makeDocument(traces: [trace])
        )
        XCTAssertTrue(exported.contains("[REDACTED]"))
        XCTAssertTrue(exported.contains("safe subject"))
        XCTAssertFalse(exported.contains("super-secret"))
        XCTAssertFalse(exported.contains("classroom-secret"))
        XCTAssertFalse(exported.contains("message body should not appear"))
        XCTAssertFalse(exported.contains("private body"))
    }

    func testDetailedReportIncludesTypedDNSRecordsAndRecursiveServerSettings() throws {
        let dnsNodeID = UUID(uuidString: "00000000-0000-0000-0000-000000000191")!
        var state = TopologyEditorState()
        state.graph.nodes = [
            TopologyNode(id: dnsNodeID, kind: .pc, displayName: "DNS Server", position: .zero),
        ]
        state.runtimeDNSServerConfigurationsByNodeID[dnsNodeID] = .init(
            typedRecords: [
                try XCTUnwrap(TopologyDNSResourceRecord(
                    name: "school.local", type: .mailExchange, ttlSeconds: 300,
                    target: "mail.school.local"
                )),
                try XCTUnwrap(TopologyDNSResourceRecord(
                    name: "school.local", type: .nameServer, ttlSeconds: 600,
                    target: "ns.school.local"
                )),
            ],
            recursiveResolutionEnabled: true,
            forwardingServerIPAddress: "10.0.0.53"
        )

        let report = TopologyDetailedReportBuilder.makeDocument(state: state)
        let dns = try XCTUnwrap(report.sections.first { $0.id == "dns" })

        XCTAssertEqual(dns.columns, [
            "nodeID", "nodeName", "source", "hostname", "recordType", "value",
            "resolverServerIP", "recursive", "forwarderIP", "ttlSeconds", "expiresAtMs",
        ])
        XCTAssertEqual(dns.rows.map { $0[2] }, ["server-settings", "server-record", "server-record"] )
        XCTAssertEqual(dns.rows[0][7...8], ["true", "10.0.0.53"] )
        XCTAssertEqual(dns.rows[1][3...5], ["school.local.", "MX", "mail.school.local."] )
        XCTAssertEqual(dns.rows[1][9], "300")
        XCTAssertEqual(dns.rows[2][3...5], ["school.local.", "NS", "ns.school.local."] )
        XCTAssertEqual(dns.rows[2][9], "600")
    }

    func testDetailedReportUsesEffectiveImportedMACAddress() throws {
        let nodeID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let portID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        var state = TopologyEditorState()
        state.graph.nodes = [
            TopologyNode(
                id: nodeID,
                kind: .pc,
                displayName: "Imported PC",
                position: .zero,
                ports: [
                    TopologyPortMetadata(
                        id: portID,
                        label: "eth0",
                        importedMACAddress: "aa:bb:cc:dd:ee:ff"
                    ),
                ]
            ),
        ]

        let report = TopologyDetailedReportBuilder.makeDocument(state: state)
        let interfaces = try XCTUnwrap(
            report.sections.first { $0.id == "devices-interfaces" }
        )
        let row = try XCTUnwrap(interfaces.rows.first)

        XCTAssertEqual(row[13], "AA:BB:CC:DD:EE:FF")
        XCTAssertNotEqual(row[13], TopologyNetworkRuntimeEngine.stableMACAddress(for: portID))
    }

    func testPacketLossReportSeparatesCurrentPolicyFromRetainedDropEvidence() throws {
        var state = TopologyEditorState()
        let nodeID = UUID(uuidString: "00000000-0000-0000-0000-000000000211")!
        let interfaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000212")!
        _ = state.networkRuntime.handle(
            .start(snapshot: .empty, seed: 211, initialTimeMilliseconds: 100)
        )
        state.networkRuntime.recordTrace(
            frameIdentity: 1,
            nodeID: nodeID,
            interfaceID: interfaceID,
            direction: .outbound,
            layer: .dataLink,
            operation: .dropped,
            detail: "global packet-loss simulation"
        )
        _ = state.networkRuntime.handle(.advance(toMilliseconds: 250))
        state.networkRuntime.recordTrace(
            frameIdentity: 2,
            nodeID: nodeID,
            interfaceID: interfaceID,
            direction: .outbound,
            layer: .dataLink,
            operation: .dropped,
            detail: "global packet-loss simulation"
        )
        state.networkRuntime.recordTrace(
            frameIdentity: 3,
            nodeID: nodeID,
            interfaceID: interfaceID,
            direction: .outbound,
            layer: .dataLink,
            operation: .dropped,
            detail: "firewall policy"
        )
        state.networkRuntime.setGlobalPacketLossEnabled(false)

        let report = TopologyDetailedReportBuilder.makeDocument(
            state: state,
            context: .init(packetLossPolicyDescription: "disabled")
        )
        let packetLoss = try XCTUnwrap(report.sections.first { $0.id == "packet-loss" })

        XCTAssertEqual(packetLoss.columns, [
            "scope", "entryType", "value", "firstTimeMs", "lastTimeMs",
        ])
        XCTAssertEqual(packetLoss.rows, [
            ["global", "current-policy", "disabled", "Not applicable", "Not applicable"],
            ["global", "retained-drop-evidence", "2", "100", "250"],
        ])
    }

    func testReportRedactsEmailPasswordsRemoteLinkCodesAndProtocolMessageTemplates() {
        var state = TopologyEditorState()
        let nodeID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let node = TopologyNode(id: nodeID, kind: .pc, displayName: "Student PC", position: .zero)
        state.graph.nodes = [node]
        state.runtimeEmailClientConfigurationsByNodeID[nodeID] = TopologyRuntimeEmailClientConfiguration(
            pop3Host: "mail.example",
            smtpHost: "mail.example",
            username: "student",
            password: "email-secret",
            name: "Student Example",
            email: "student@example.com"
        )
        state.remoteLinkConfigurationsByNodeID[nodeID] = TopologyRemoteLinkConfiguration(
            pairIdentifier: "remote-secret"
        )
        let definition = TopologyProtocolApplicationDefinition(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Echo protocol",
            role: .server,
            transport: .tcp,
            port: 9000,
            clientMessageTemplates: [.init(name: "secret-template", message: "private message body")]
        )
        state.protocolApplicationDefinitionsByID[definition.id] = definition

        let text = TopologyDetailedReportTextRenderer.render(
            state: state,
            context: .init(projectName: "Classroom", packetLossPolicyDescription: "drop all")
        )

        XCTAssertTrue(text.contains("[REDACTED]"))
        XCTAssertTrue(text.contains("Student PC"))
        XCTAssertTrue(text.contains("Echo protocol"))
        XCTAssertFalse(text.contains("email-secret"))
        XCTAssertFalse(text.contains("remote-secret"))
        XCTAssertFalse(text.contains("private message body"))
    }

    func testWebSectionReportsServerVirtualHostsAdministrationBrowserAndLogsDeterministically() throws {
        let serverID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let routerID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
        let browserID = UUID(uuidString: "00000000-0000-0000-0000-000000000030")!
        let server = TopologyNode(
            id: serverID,
            kind: .pc,
            displayName: "Web Server",
            position: .zero
        )
        let router = TopologyNode(
            id: routerID,
            kind: .router,
            displayName: "Classroom Router",
            position: .zero
        )
        let browser = TopologyNode(
            id: browserID,
            kind: .notebook,
            displayName: "Student Browser",
            position: .zero
        )
        let virtualHosts = try TopologyRuntimeWebVirtualHostConfiguration(
            hosts: [
                TopologyRuntimeWebVirtualHost(
                    id: "default-site",
                    hostname: "z.example.test",
                    documentRoot: "/www/default"
                ),
                TopologyRuntimeWebVirtualHost(
                    id: "alpha-site",
                    hostname: "alpha.example.test",
                    port: 8081,
                    documentRoot: "/www/alpha",
                    isEnabled: false
                ),
            ],
            defaultHostID: "default-site"
        )
        let allowedNetworks = [
            try TopologyRuntimeWebAdministrationIPv4Network(
                networkAddress: "192.168.50.99",
                subnetMask: "255.255.255.0"
            ),
            try TopologyRuntimeWebAdministrationIPv4Network(
                networkAddress: "10.42.7.9",
                subnetMask: "255.255.0.0"
            ),
        ]

        var state = TopologyEditorState()
        state.graph.nodes = [browser, router, server]
        state.runtimeWebAdministrationConfigurationsByNodeID[routerID] = .init(
            port: 9090,
            accessPolicy: .init(
                isEnabled: true,
                allowedSourceNetworks: allowedNetworks
            )
        )
        state.runtimeWebServerConfigurationsByNodeID[serverID] = .init(
            port: 8080,
            documentRoot: "/www",
            virtualHostConfiguration: virtualHosts
        )
        state.runtimeWebServerByNodeID[serverID] = .init(port: 8080)
        state.runtimeWebAdministrationByNodeID[routerID] = .init(port: 9090)
        state.runtimeWebAdministrationResponsesByNodeID[routerID] = .init(
            statusCode: 200,
            contentType: "text/html; charset=utf-8",
            body: "response body is intentionally excluded",
            detail: "Status overview"
        )
        state.runtimeWebBrowserConfigurationsByNodeID[browserID] = .init(
            lastHost: "alpha.example.test",
            lastPort: 8081,
            lastPath: "/status"
        )
        var browserState = TopologyRuntimeWebBrowserState()
        browserState.connectionState = .loaded
        browserState.resolvedIPAddress = "10.42.0.10"
        browserState.statusCode = 200
        browserState.contentType = "text/html"
        browserState.history = [
            .init(address: "http://alpha.example.test:8081/status", statusCode: 200, title: "Status")
        ]
        browserState.historyIndex = 0
        state.runtimeWebBrowserStateByNodeID[browserID] = browserState
        state.runtimeWebServerRequestLogsByNodeID[routerID] = [
            .init(
                id: 1,
                timestampMilliseconds: 200,
                remoteIPAddress: "10.42.0.20",
                method: "GET",
                path: "/admin/routes",
                statusCode: 200,
                contentType: "text/html; charset=utf-8",
                detail: "Routes"
            )
        ]
        state.runtimeWebServerRequestLogsByNodeID[serverID] = [
            .init(
                id: 2,
                timestampMilliseconds: 100,
                remoteIPAddress: "10.42.0.30",
                method: "HEAD",
                path: "/index.html",
                statusCode: 204,
                contentType: "text/html",
                detail: "alpha-site"
            )
        ]

        let section = try XCTUnwrap(webSection(in: state))
        XCTAssertEqual(section.columns, [
            "nodeID", "nodeName", "entryType", "entryID", "timeMs", "port",
            "documentRoot", "configurationState", "listenerState", "hostOrRemoteIP",
            "networkMaskOrPath", "method", "statusCode", "contentType", "detail",
        ])
        XCTAssertEqual(section.rows.map { $0[2] }, [
            "web-server",
            "virtual-host", "virtual-host",
            "administration-configuration", "administration-policy",
            "administration-listener", "administration-allowed-network",
            "administration-allowed-network",
            "browser",
            "web-request-log", "administration-request-log",
        ])

        let serverRow = try XCTUnwrap(section.rows.first { $0[2] == "web-server" })
        XCTAssertEqual(serverRow[0], serverID.uuidString.lowercased())
        XCTAssertEqual(serverRow[5], "8080")
        XCTAssertEqual(serverRow[6], "/www")
        XCTAssertEqual(serverRow[8], "running on port 8080")
        XCTAssertEqual(serverRow[14], "virtualHostCount=2; defaultHost=default-site")

        let hostRows = section.rows.filter { $0[2] == "virtual-host" }
        XCTAssertEqual(hostRows.map { $0[3] }, ["alpha-site", "default-site"])
        XCTAssertEqual(hostRows.map { $0[8] }, ["not-default", "default"])
        XCTAssertEqual(hostRows.map { $0[7] }, ["disabled", "enabled"])
        XCTAssertEqual(hostRows.map { $0[9] }, ["alpha.example.test", "z.example.test"])

        let configurationRow = try XCTUnwrap(
            section.rows.first { $0[2] == "administration-configuration" }
        )
        XCTAssertEqual(configurationRow[10], "/admin")
        XCTAssertEqual(configurationRow[11], "GET,HEAD,POST")
        XCTAssertEqual(
            configurationRow[14],
            "serviceRole=router/gateway administration; capability=read-write; mutationMethod=POST"
        )

        let policyRow = try XCTUnwrap(section.rows.first { $0[2] == "administration-policy" })
        XCTAssertEqual(policyRow[3], "explicit")
        XCTAssertEqual(policyRow[7], "enabled")
        XCTAssertEqual(policyRow[14], "allowedNetworkCount=2; emptyAllowList=deny-all")

        let listenerRow = try XCTUnwrap(section.rows.first { $0[2] == "administration-listener" })
        XCTAssertEqual(listenerRow[5], "9090")
        XCTAssertEqual(listenerRow[8], "running on port 9090")
        XCTAssertEqual(listenerRow[10], "/admin")
        XCTAssertEqual(listenerRow[11], "GET,HEAD,POST")
        XCTAssertEqual(listenerRow[12], "200")
        XCTAssertEqual(listenerRow[14], "lastResponse=Status overview")

        let networkRows = section.rows.filter { $0[2] == "administration-allowed-network" }
        XCTAssertEqual(networkRows.map { [$0[3], $0[9], $0[10]] }, [
            ["network-001", "10.42.0.0", "255.255.0.0"],
            ["network-002", "192.168.50.0", "255.255.255.0"],
        ])

        let browserRow = try XCTUnwrap(section.rows.first { $0[2] == "browser" })
        XCTAssertEqual(browserRow[5], "8081")
        XCTAssertEqual(browserRow[8], "loaded")
        XCTAssertEqual(browserRow[9], "alpha.example.test")
        XCTAssertEqual(browserRow[10], "/status")
        XCTAssertEqual(browserRow[12], "200")
        XCTAssertTrue(browserRow[14].contains("resolvedIP=10.42.0.10"))
        XCTAssertTrue(browserRow[14].contains("historyCount=1"))

        let logRows = section.rows.filter { $0[2].hasSuffix("request-log") }
        XCTAssertEqual(logRows.map { $0[4] }, ["100", "200"])
        XCTAssertEqual(logRows.map { $0[2] }, ["web-request-log", "administration-request-log"])
        XCTAssertEqual(logRows.map { $0[5] }, ["8080", "9090"])
        XCTAssertEqual(logRows.map { $0[10] }, ["/index.html", "/admin/routes"])

        var reorderedState = state
        reorderedState.graph.nodes = [server, browser, router]
        reorderedState.runtimeWebServerConfigurationsByNodeID = [:]
        reorderedState.runtimeWebServerConfigurationsByNodeID[serverID] = state.runtimeWebServerConfigurationsByNodeID[serverID]
        reorderedState.runtimeWebAdministrationConfigurationsByNodeID = [:]
        reorderedState.runtimeWebAdministrationConfigurationsByNodeID[routerID] =
            state.runtimeWebAdministrationConfigurationsByNodeID[routerID]
        reorderedState.runtimeWebServerRequestLogsByNodeID = [:]
        reorderedState.runtimeWebServerRequestLogsByNodeID[serverID] = state.runtimeWebServerRequestLogsByNodeID[serverID]
        reorderedState.runtimeWebServerRequestLogsByNodeID[routerID] = state.runtimeWebServerRequestLogsByNodeID[routerID]
        XCTAssertEqual(webSection(in: reorderedState), section)
    }

    func testWebSectionReportsRouterWebServerIndependentlyFromAdministration() throws {
        let routerID = UUID(uuidString: "00000000-0000-0000-0000-000000000035")!
        var state = TopologyEditorState()
        state.graph.nodes = [
            TopologyNode(
                id: routerID,
                kind: .router,
                displayName: "Dual-role Router",
                position: .zero
            ),
        ]
        state.runtimeWebServerConfigurationsByNodeID[routerID] = .init(
            port: 8080,
            documentRoot: "/www/router"
        )
        state.runtimeWebServerByNodeID[routerID] = .init(port: 8080)
        state.runtimeWebAdministrationConfigurationsByNodeID[routerID] = .init(
            port: 9090,
            accessPolicy: .init(isEnabled: true)
        )
        state.runtimeWebAdministrationByNodeID[routerID] = .init(port: 9090)

        let section = try XCTUnwrap(webSection(in: state))
        let serverRow = try XCTUnwrap(section.rows.first { $0[2] == "web-server" })
        let administrationRow = try XCTUnwrap(
            section.rows.first { $0[2] == "administration-configuration" }
        )
        let administrationListener = try XCTUnwrap(
            section.rows.first { $0[2] == "administration-listener" }
        )

        XCTAssertEqual(serverRow[0], routerID.uuidString.lowercased())
        XCTAssertEqual(serverRow[5], "8080")
        XCTAssertEqual(serverRow[6], "/www/router")
        XCTAssertEqual(serverRow[8], "running on port 8080")
        XCTAssertEqual(administrationRow[5], "9090")
        XCTAssertEqual(administrationListener[8], "running on port 9090")
    }

    func testWebSectionReportsSecureDefaultAdministrationRowsForUnconfiguredGateway() throws {
        let gatewayID = UUID(uuidString: "00000000-0000-0000-0000-000000000040")!
        var state = TopologyEditorState()
        state.graph.nodes = [
            TopologyNode(id: gatewayID, kind: .gateway, displayName: "Internet Gateway", position: .zero)
        ]

        let section = try XCTUnwrap(webSection(in: state))
        XCTAssertEqual(section.rows.map { $0[2] }, [
            "administration-configuration", "administration-policy",
            "administration-listener", "administration-allowed-network",
        ])
        XCTAssertEqual(section.rows[0][5], "Not configured")
        XCTAssertEqual(section.rows[0][11], "GET,HEAD,POST")
        XCTAssertEqual(
            section.rows[0][14],
            "serviceRole=router/gateway administration; capability=read-write; mutationMethod=POST"
        )
        XCTAssertEqual(section.rows[1][3], "default")
        XCTAssertEqual(section.rows[1][7], "disabled")
        XCTAssertEqual(section.rows[2][8], "stopped")
        XCTAssertEqual(section.rows[2][11], "GET,HEAD,POST")
        XCTAssertEqual(section.rows[3][14], "policy disabled; no sources allowed")
    }

    func testWebSectionPreservesRedactionAndExcludesResponseAndBrowserBodies() throws {
        let serverID = UUID(uuidString: "00000000-0000-0000-0000-000000000050")!
        let routerID = UUID(uuidString: "00000000-0000-0000-0000-000000000060")!
        let browserID = UUID(uuidString: "00000000-0000-0000-0000-000000000070")!
        let virtualHosts = try TopologyRuntimeWebVirtualHostConfiguration(
            hosts: [
                TopologyRuntimeWebVirtualHost(
                    id: "token=virtual-host-secret",
                    hostname: "private.example.test",
                    documentRoot: "/www/private"
                )
            ],
            defaultHostID: "token=virtual-host-secret"
        )

        var state = TopologyEditorState()
        state.graph.nodes = [
            TopologyNode(id: serverID, kind: .pc, displayName: "Server", position: .zero),
            TopologyNode(id: routerID, kind: .router, displayName: "Router", position: .zero),
            TopologyNode(id: browserID, kind: .notebook, displayName: "Browser", position: .zero),
        ]
        state.runtimeWebServerConfigurationsByNodeID[serverID] = .init(
            virtualHostConfiguration: virtualHosts
        )
        state.runtimeWebAdministrationConfigurationsByNodeID[routerID] = .init(port: 8088)
        state.runtimeWebAdministrationResponsesByNodeID[routerID] = .init(
            statusCode: 403,
            contentType: "text/html",
            body: "admin-response-body-secret",
            detail: "cookie=admin-cookie-secret"
        )
        state.runtimeWebBrowserConfigurationsByNodeID[browserID] = .init(
            lastHost: "private.example.test",
            lastPort: 80,
            lastPath: "/login?token=browser-config-secret"
        )
        var browserState = TopologyRuntimeWebBrowserState()
        browserState.connectionState = .failed
        browserState.body = "browser-response-body-secret"
        browserState.bodyData = Data("browser-data-secret".utf8)
        browserState.errorMessage = "refresh_token=browser-error-secret"
        state.runtimeWebBrowserStateByNodeID[browserID] = browserState
        state.runtimeWebServerRequestLogsByNodeID[serverID] = [
            .init(
                id: 1,
                timestampMilliseconds: 1,
                remoteIPAddress: "10.0.0.2",
                method: "GET",
                path: "/private?access_token=request-path-secret",
                statusCode: 401,
                contentType: "text/plain",
                detail: "authorization=request-detail-secret"
            )
        ]

        let text = TopologyDetailedReportTextRenderer.render(state: state)
        XCTAssertTrue(text.contains("[REDACTED]"))
        for secret in [
            "virtual-host-secret",
            "admin-response-body-secret",
            "admin-cookie-secret",
            "browser-config-secret",
            "browser-response-body-secret",
            "browser-data-secret",
            "browser-error-secret",
            "request-path-secret",
            "request-detail-secret",
        ] {
            XCTAssertFalse(text.contains(secret), "Report leaked \(secret)")
        }
    }

    func testReportRowsAreDeterministicAcrossGraphInsertionOrder() {
        let firstNode = TopologyNode(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            kind: .pc,
            displayName: "First",
            position: CGPoint(x: 1, y: 2),
            ports: [TopologyPortMetadata(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                label: "eth0"
            )]
        )
        let secondNode = TopologyNode(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            kind: .pc,
            displayName: "Second",
            position: CGPoint(x: 3, y: 4),
            ports: [TopologyPortMetadata(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
                label: "eth0"
            )]
        )
        var firstState = TopologyEditorState()
        firstState.graph.nodes = [secondNode, firstNode]
        firstState.runtimeDeviceConfigurations = [
            firstNode.id: .init(ipAddress: "10.0.0.1", subnetMask: "255.255.255.0"),
            secondNode.id: .init(ipAddress: "10.0.0.2", subnetMask: "255.255.255.0"),
        ]
        var secondState = firstState
        secondState.graph.nodes = [firstNode, secondNode]

        let firstText = TopologyDetailedReportTextRenderer.render(state: firstState)
        let secondText = TopologyDetailedReportTextRenderer.render(state: secondState)
        XCTAssertEqual(firstText, secondText)

        let section = TopologyDetailedReportBuilder.makeDocument(state: firstState).sections.first {
            $0.id == "devices-interfaces"
        }
        let firstColumn = section?.rows.compactMap { $0.first }
        XCTAssertEqual(
            firstColumn,
            [firstNode.id.uuidString.lowercased(), secondNode.id.uuidString.lowercased()]
        )
    }

    func testCaptureScopeIncludesOnlySelectedNodeAndInterface() {
        let firstNode = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondNode = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let interfaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let traces = [
            trace(id: 1, time: 1, nodeID: firstNode, interfaceID: interfaceID, detail: "match"),
            trace(id: 2, time: 2, nodeID: firstNode, interfaceID: nil, detail: "wrong-interface"),
            trace(id: 3, time: 3, nodeID: secondNode, interfaceID: interfaceID, detail: "wrong-node"),
        ]

        let document = TopologyPacketCaptureTextExportFormatter.makeDocument(
            traces: traces,
            scope: .init(nodeID: firstNode, interfaceID: interfaceID)
        )
        XCTAssertEqual(document.records.map(\.traceID), [1])
    }

    private func webSection(in state: TopologyEditorState) -> TopologyDetailedReportSection? {
        TopologyDetailedReportBuilder.makeDocument(state: state).sections.first {
            $0.id == "web-services"
        }
    }

    private func trace(
        id: UInt64,
        time: UInt64,
        frameIdentity: UInt64? = 1,
        packetIdentity: UInt64? = nil,
        nodeID: UUID,
        interfaceID: UUID?,
        operation: TopologyPacketTraceOperation = .sent,
        detail: String
    ) -> TopologyPacketTraceEvent {
        TopologyPacketTraceEvent(
            id: id,
            timeMilliseconds: time,
            frameIdentity: frameIdentity,
            packetIdentity: packetIdentity,
            nodeID: nodeID,
            interfaceID: interfaceID,
            direction: .outbound,
            layer: .application,
            operation: operation,
            beforeHeaders: [],
            afterHeaders: [.init(name: "kind", value: "HTTP")],
            detail: detail
        )
    }
}
