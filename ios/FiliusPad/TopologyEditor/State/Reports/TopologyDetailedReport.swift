import CoreGraphics
import Foundation

struct TopologyDetailedReportContext: Equatable {
    var projectName: String?
    var sourceDescription: String
    var packetLossPolicyDescription: String

    init(
        projectName: String? = nil,
        sourceDescription: String = "TopologyEditorState",
        packetLossPolicyDescription: String = "Not configured"
    ) {
        self.projectName = projectName
        self.sourceDescription = sourceDescription
        self.packetLossPolicyDescription = packetLossPolicyDescription
    }
}

struct TopologyDetailedReportSection: Equatable, Identifiable {
    let id: String
    let title: String
    let columns: [String]
    let rows: [[String]]
    let emptyMessage: String
}

struct TopologyDetailedReportDocument: Equatable {
    let formatVersion: Int
    let title: String
    let sections: [TopologyDetailedReportSection]
}

/// Builds a deterministic, rendering-independent report snapshot from editor/runtime state.
///
/// The model contains configuration and traffic metadata only. Password values, LAN link
/// codes/digests, protocol message templates, virtual-file contents, browser response bodies,
/// and email message bodies are intentionally excluded or represented by `[REDACTED]`.
/// Traffic sections use the same eligibility rules as the packet viewer and TSV export so
/// displayed, reported, and exported packet counts remain consistent. Historical global
/// packet-loss evidence is summarized separately from the currently active policy.
enum TopologyDetailedReportBuilder {
    static let formatVersion = 4

    static func makeDocument(
        state: TopologyEditorState,
        context: TopologyDetailedReportContext = .init()
    ) -> TopologyDetailedReportDocument {
        let nodes = state.graph.nodes.sorted(by: nodeIsOrderedBefore)
        let trafficDocument = TopologyPacketCaptureTextExportFormatter.makeDocument(state: state)
        let title = context.projectName
            .map { "FiliusPad Detailed Report — \(TopologyReportExportRedaction.redactFreeText($0))" }
            ?? "FiliusPad Detailed Report"

        return TopologyDetailedReportDocument(
            formatVersion: formatVersion,
            title: title,
            sections: [
                projectMetadataSection(
                    state: state,
                    context: context,
                    captureDocument: trafficDocument
                ),
                linksSection(state: state, nodes: nodes),
                devicesAndInterfacesSection(state: state, nodes: nodes),
                applicationsSection(state: state),
                routesSection(state: state),
                dnsSection(state: state),
                dhcpSection(state: state),
                natAndPortForwardingSection(state: state),
                firewallSection(state: state),
                webSection(state: state),
                emailSection(state: state),
                remoteLinksSection(state: state),
                packetLossSection(state: state, context: context),
                trafficSummarySection(captureDocument: trafficDocument),
                trafficEventsSection(captureDocument: trafficDocument),
            ]
        )
    }

    private static func projectMetadataSection(
        state: TopologyEditorState,
        context: TopologyDetailedReportContext,
        captureDocument: TopologyPacketCaptureExportDocument
    ) -> TopologyDetailedReportSection {
        let values: [(String, String)] = [
            ("projectName", context.projectName ?? "Not specified"),
            ("source", context.sourceDescription),
            ("nodeCount", String(state.graph.nodes.count)),
            ("linkCount", String(state.graph.links.count)),
            ("documentationItemCount", String(state.documentationItems.count)),
            ("simulationPhase", state.simulationPhase.rawValue),
            ("simulationTickMilliseconds", String(state.simulationTick)),
            ("simulationSpeedPercent", String(state.networkRuntime.state.simulationSpeedPercent)),
            ("persistenceRevision", String(state.persistenceRevision)),
            ("lastPersistedRevision", String(state.lastPersistedRevision)),
            ("packetCaptureRecordCount", String(captureDocument.records.count)),
            ("retainedRuntimeTraceCount", String(state.networkRuntime.state.packetTraces.count)),
            ("discardedRuntimeTraceCount", String(state.networkRuntime.state.discardedPacketTraceCount)),
        ]
        return section(
            id: "project-metadata",
            title: "Project metadata",
            columns: ["key", "value"],
            rows: values.map { [$0.0, redacted($0.0, $0.1)] },
            emptyMessage: "No project metadata"
        )
    }

    private static func linksSection(
        state: TopologyEditorState,
        nodes: [TopologyNode]
    ) -> TopologyDetailedReportSection {
        let nodeNames = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.displayName) })
        let rows = state.graph.links.sorted(by: linkIsOrderedBefore).map { link in
            [
                normalizedUUID(link.id),
                normalizedUUID(link.sourceNodeID),
                redacted("nodeName", nodeNames[link.sourceNodeID] ?? "Unknown device"),
                normalizedUUID(link.sourcePortID),
                normalizedUUID(link.targetNodeID),
                redacted("nodeName", nodeNames[link.targetNodeID] ?? "Unknown device"),
                normalizedUUID(link.targetPortID),
            ]
        }
        return section(
            id: "links",
            title: "Links",
            columns: ["linkID", "sourceNodeID", "sourceName", "sourcePortID", "targetNodeID", "targetName", "targetPortID"],
            rows: rows,
            emptyMessage: "No links configured"
        )
    }

    private static func devicesAndInterfacesSection(
        state: TopologyEditorState,
        nodes: [TopologyNode]
    ) -> TopologyDetailedReportSection {
        var rows: [[String]] = []
        let wirelessAssociations = state.wirelessAssociations()

        for node in nodes {
            if node.ports.isEmpty {
                rows.append(deviceInterfaceRow(
                    state: state,
                    node: node,
                    port: nil,
                    wirelessAssociations: wirelessAssociations
                ))
            } else {
                for port in node.ports.sorted(by: portIsOrderedBefore) {
                    rows.append(deviceInterfaceRow(
                        state: state,
                        node: node,
                        port: port,
                        wirelessAssociations: wirelessAssociations
                    ))
                }
            }
        }

        return section(
            id: "devices-interfaces",
            title: "Devices and interfaces",
            columns: [
                "nodeID", "name", "kind", "positionX", "positionY", "portID", "portLabel",
                "connected", "wireless", "ipAddress", "subnetMask", "defaultGateway", "dnsServer", "macAddress",
            ],
            rows: rows,
            emptyMessage: "Empty project — no devices or interfaces"
        )
    }

    private static func deviceInterfaceRow(
        state: TopologyEditorState,
        node: TopologyNode,
        port: TopologyPortMetadata?,
        wirelessAssociations: [TopologyWirelessAssociation]
    ) -> [String] {
        let portID = port?.id
        let deviceConfiguration = state.runtimeDeviceConfigurations[node.id]
        let interfaceConfiguration: TopologyRuntimeInterfaceConfiguration?
        switch node.kind {
        case .pc, .notebook:
            interfaceConfiguration = deviceConfiguration.map {
                TopologyRuntimeInterfaceConfiguration(ipAddress: $0.ipAddress, subnetMask: $0.subnetMask)
            }
        case .router, .gateway:
            interfaceConfiguration = portID.flatMap {
                state.runtimeInterfaceConfigurations[TopologyRuntimeInterfaceKey(nodeID: node.id, portID: $0)]
            }
        case .networkSwitch, .remoteLink, .unsupported:
            interfaceConfiguration = nil
        }
        let isWireless = portID.map { candidate in
            wirelessAssociations.contains { association in
                (association.hostNodeID == node.id && association.hostPortID == candidate)
                    || (association.switchNodeID == node.id && association.switchPortID == candidate)
            }
        } ?? false
        let isConnected = portID.map {
            state.graph.isPortConnected(nodeID: node.id, portID: $0) || isWireless
        } ?? false

        return [
            normalizedUUID(node.id),
            redacted("nodeName", node.displayName),
            node.kind.rawValue,
            decimal(node.position.x),
            decimal(node.position.y),
            portID.map(normalizedUUID) ?? "Not configured",
            port.map { redacted("portLabel", $0.label) } ?? "Not configured",
            bool(isConnected),
            bool(isWireless),
            interfaceConfiguration?.ipAddress ?? "Not configured",
            interfaceConfiguration?.subnetMask ?? "Not configured",
            deviceConfiguration?.defaultGateway.nilIfBlank ?? "Not configured",
            deviceConfiguration?.dnsServer.nilIfBlank ?? "Not configured",
            port?.effectiveMACAddress ?? "Not configured",
        ]
    }

    private static func applicationsSection(state: TopologyEditorState) -> TopologyDetailedReportSection {
        var rows: [[String]] = []
        for nodeID in state.runtimeInstalledProgramsByNodeID.keys.sorted(by: uuidIsOrderedBefore) {
            let programs = state.runtimeInstalledProgramsByNodeID[nodeID] ?? []
            for program in programs.sorted(by: { $0.rawValue < $1.rawValue }) {
                rows.append([
                    normalizedUUID(nodeID),
                    nodeDisplayName(nodeID, state: state),
                    "built-in",
                    program.rawValue,
                    "installed",
                    "Not applicable",
                    "Not applicable",
                    "Not applicable",
                ])
            }
        }
        for nodeID in state.runtimeInstalledProtocolApplicationIDsByNodeID.keys.sorted(by: uuidIsOrderedBefore) {
            for definitionID in (state.runtimeInstalledProtocolApplicationIDsByNodeID[nodeID] ?? []).sorted(by: uuidIsOrderedBefore) {
                let definition = state.protocolApplicationDefinitionsByID[definitionID]
                rows.append([
                    normalizedUUID(nodeID),
                    nodeDisplayName(nodeID, state: state),
                    "custom",
                    redacted("applicationName", definition?.name ?? "Missing definition"),
                    "installed",
                    definition?.role.rawValue ?? "Not configured",
                    definition?.transport.rawValue ?? "Not configured",
                    definition.map { String($0.port) } ?? "Not configured",
                ])
            }
        }
        for definition in state.protocolApplicationDefinitionsByID.values.sorted(by: protocolDefinitionIsOrderedBefore) {
            rows.append([
                "project",
                "Project definition",
                "custom-definition",
                redacted("applicationName", definition.name),
                "templates=\(definition.clientMessageTemplates.count); responses=\(definition.responseRules.count)",
                definition.role.rawValue,
                definition.transport.rawValue,
                String(definition.port),
            ])
        }
        return section(
            id: "applications",
            title: "Applications and configuration",
            columns: ["nodeID", "nodeName", "type", "application", "status", "role", "transport", "port"],
            rows: rows,
            emptyMessage: "No applications configured"
        )
    }

    private static func routesSection(state: TopologyEditorState) -> TopologyDetailedReportSection {
        var rows: [[String]] = []
        for nodeID in state.runtimeManualRoutesByNodeID.keys.sorted(by: uuidIsOrderedBefore) {
            let routes = state.runtimeManualRoutesByNodeID[nodeID] ?? []
            for route in routes.sorted(by: manualRouteIsOrderedBefore) {
                rows.append([
                    normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state), "manual",
                    route.destinationNetwork, route.subnetMask, route.gateway,
                    route.interfaceIPAddress, "manual", "Not configured", "Not configured",
                ])
            }
        }
        for nodeID in state.networkRuntime.state.ripTablesByNodeID.keys.sorted(by: uuidIsOrderedBefore) {
            for route in (state.networkRuntime.state.ripTablesByNodeID[nodeID] ?? []).sorted(by: routeRowIsOrderedBefore) {
                rows.append([
                    normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state), "runtime",
                    route.destinationNetwork, route.subnetMask, route.nextHop,
                    route.interfaceIPAddress, route.origin.rawValue,
                    route.metric.map(String.init) ?? "Not configured",
                    route.expiresAtMilliseconds.map(String.init) ?? "Not configured",
                ])
            }
        }
        return section(
            id: "routes",
            title: "Routes",
            columns: ["nodeID", "nodeName", "table", "destination", "subnetMask", "nextHop", "interfaceIP", "origin", "metric", "expiresAtMs"],
            rows: rows,
            emptyMessage: "No manual or learned routes configured"
        )
    }

    private static func dnsSection(state: TopologyEditorState) -> TopologyDetailedReportSection {
        var rows: [[String]] = []
        for nodeID in state.runtimeDNSServerConfigurationsByNodeID.keys.sorted(by: uuidIsOrderedBefore) {
            let configuration = state.runtimeDNSServerConfigurationsByNodeID[nodeID] ?? .init()
            let recursive = bool(configuration.recursiveResolutionEnabled)
            let forwarder = configuration.forwardingServerIPAddress?.nilIfBlank ?? "Not configured"
            rows.append([
                normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state), "server-settings",
                "Not applicable", "Not applicable", "configured", "Not applicable", recursive,
                forwarder, "Not applicable", "Not applicable",
            ])
            for record in configuration.typedRecords.sorted(by: TopologyDNSResourceRecord.deterministicOrder) {
                rows.append([
                    normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state), "server-record",
                    record.name.absoluteString, record.type.rawValue, record.target, "Not applicable",
                    recursive, forwarder, String(record.ttlSeconds), "Not applicable",
                ])
            }
        }
        for nodeID in state.runtimeDNSCacheByNodeID.keys.sorted(by: uuidIsOrderedBefore) {
            for entry in (state.runtimeDNSCacheByNodeID[nodeID] ?? [:]).values.sorted(by: dnsCacheEntryIsOrderedBefore) {
                rows.append([
                    normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state), "client-cache",
                    entry.hostname, "A", entry.targetIPAddress ?? "NXDOMAIN", entry.serverIPAddress,
                    "Not applicable", "Not applicable", "Not applicable",
                    String(entry.expiresAtMilliseconds),
                ])
            }
        }
        return section(
            id: "dns",
            title: "DNS records, recursive resolution, and cache",
            columns: [
                "nodeID", "nodeName", "source", "hostname", "recordType", "value",
                "resolverServerIP", "recursive", "forwarderIP", "ttlSeconds", "expiresAtMs",
            ],
            rows: rows,
            emptyMessage: "No DNS records, server settings, or cache entries configured"
        )
    }

    private static func dhcpSection(state: TopologyEditorState) -> TopologyDetailedReportSection {
        var rows: [[String]] = []
        for nodeID in state.runtimeDHCPClientConfigurationsByNodeID.keys.sorted(by: uuidIsOrderedBefore) {
            let configuration = state.runtimeDHCPClientConfigurationsByNodeID[nodeID] ?? .init()
            let lease = state.runtimeDHCPLeaseByNodeID[nodeID]
            rows.append([
                normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state), "client",
                bool(configuration.isEnabled), lease?.ipAddress ?? "Not configured",
                lease?.subnetMask ?? "Not configured", lease?.defaultGateway ?? "Not configured",
                lease?.dnsServer ?? "Not configured", "Not applicable", "Not applicable",
            ])
        }
        for nodeID in state.runtimeDHCPServerConfigurationsByNodeID.keys.sorted(by: uuidIsOrderedBefore) {
            let configuration = state.runtimeDHCPServerConfigurationsByNodeID[nodeID] ?? .init()
            rows.append([
                normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state), "server",
                bool(configuration.isActive), configuration.lowerBoundIPAddress,
                configuration.upperBoundIPAddress, configuration.gatewayIPAddress,
                configuration.dnsServerIPAddress, bool(configuration.useOwnSettings),
                String(configuration.staticAssignments.count),
            ])
            for assignment in configuration.staticAssignments.sorted(by: dhcpAssignmentIsOrderedBefore) {
                rows.append([
                    normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state), "static-assignment",
                    bool(configuration.isActive), assignment.ipAddress, "Not applicable", "Not applicable",
                    "Not applicable", assignment.macAddress, normalizedUUID(assignment.id),
                ])
            }
        }
        return section(
            id: "dhcp",
            title: "DHCP",
            columns: ["nodeID", "nodeName", "role", "active", "addressOrLowerBound", "subnetOrUpperBound", "gateway", "dnsServer", "ownSettingsOrMAC", "assignmentCountOrID"],
            rows: rows,
            emptyMessage: "No DHCP clients, servers, or leases configured"
        )
    }

    private static func natAndPortForwardingSection(state: TopologyEditorState) -> TopologyDetailedReportSection {
        var rows: [[String]] = []
        for nodeID in state.runtimePortForwardingRowsByNodeID.keys.sorted(by: uuidIsOrderedBefore) {
            for row in (state.runtimePortForwardingRowsByNodeID[nodeID] ?? []).sorted(by: portForwardingIsOrderedBefore) {
                rows.append([
                    normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state), "port-forward",
                    row.protocolValue, row.publicPortValue, row.lanIPAddress, row.lanPortValue,
                    bool(row.isRuntimeValid), "Not applicable", "Not applicable",
                ])
            }
        }
        for mapping in state.networkRuntime.state.natMappings.sorted(by: natMappingIsOrderedBefore) {
            rows.append([
                normalizedUUID(mapping.gatewayNodeID), nodeDisplayName(mapping.gatewayNodeID, state: state), "nat-mapping",
                String(mapping.protocolNumber.rawValue), String(mapping.translatedPortOrIdentifier),
                mapping.lanIPAddress, String(mapping.lanPortOrIdentifier), "true",
                mapping.remoteIPAddress, mapping.type.rawValue,
            ])
        }
        return section(
            id: "nat-port-forwarding",
            title: "NAT and port forwarding",
            columns: ["nodeID", "nodeName", "entryType", "protocol", "publicPortOrIdentifier", "lanIP", "lanPortOrIdentifier", "valid", "remoteIP", "mappingType"],
            rows: rows,
            emptyMessage: "No NAT mappings or port-forwarding rules configured"
        )
    }

    private static func firewallSection(state: TopologyEditorState) -> TopologyDetailedReportSection {
        var rows: [[String]] = []
        for nodeID in state.runtimeFirewallConfigurationsByNodeID.keys.sorted(by: uuidIsOrderedBefore) {
            let configuration = state.runtimeFirewallConfigurationsByNodeID[nodeID] ?? .init()
            rows.append([
                normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state), "configuration", "Not applicable",
                "Not applicable", "Not applicable", "Not applicable", "Not applicable",
                configuration.defaultPolicy.javaLabel, bool(configuration.isActive),
                "dropICMP=\(bool(configuration.dropICMP)); SYNOnly=\(bool(configuration.filterSYNSegmentsOnly)); UDP=\(bool(configuration.filterUDP))",
            ])
            for (index, rule) in configuration.rules.enumerated() {
                rows.append([
                    normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state), "rule", String(index + 1),
                    rule.sourceIPAddress, rule.sourceSubnetMask, rule.destinationIPAddress,
                    rule.destinationSubnetMask, rule.action.javaLabel, rule.protocolType.javaLabel,
                    rule.port == TopologyFirewallRule.allPorts ? "all ports" : String(rule.port),
                ])
            }
        }
        let decisionGroups = Dictionary(grouping: state.networkRuntime.state.firewallDecisions) {
            FirewallDecisionKey(nodeID: $0.nodeID, accepted: $0.accepted, ruleIndex: $0.ruleIndex)
        }
        for key in decisionGroups.keys.sorted(by: firewallDecisionKeyIsOrderedBefore) {
            rows.append([
                normalizedUUID(key.nodeID), nodeDisplayName(key.nodeID, state: state), "runtime-decisions",
                key.ruleIndex.map { String($0 + 1) } ?? "default", "Not applicable", "Not applicable",
                "Not applicable", "Not applicable", key.accepted ? "accepted" : "dropped",
                "Not applicable", "count=\(decisionGroups[key]?.count ?? 0)",
            ])
        }
        return section(
            id: "firewall",
            title: "Firewall",
            columns: ["nodeID", "nodeName", "entryType", "rule", "sourceIP", "sourceMask", "destinationIP", "destinationMask", "action", "protocolOrActive", "portOrOptions"],
            rows: rows,
            emptyMessage: "No firewall configuration or decisions recorded"
        )
    }

    private static func webSection(state: TopologyEditorState) -> TopologyDetailedReportSection {
        var rows: [[String]] = []
        let administrationNodeIDs = Set(
            state.graph.nodes.compactMap { node in
                node.kind == .router || node.kind == .gateway ? node.id : nil
            }
        )
        .union(state.runtimeWebAdministrationConfigurationsByNodeID.keys)
        .union(state.runtimeWebAdministrationByNodeID.keys)
        .union(state.runtimeWebAdministrationResponsesByNodeID.keys)

        // Ordinary web servers are reported independently from router/gateway administration,
        // even though the current runtime uses the same listener storage for both service roles.
        for nodeID in state.runtimeWebServerConfigurationsByNodeID.keys
            .sorted(by: uuidIsOrderedBefore) {
            guard let configuration = state.runtimeWebServerConfigurationsByNodeID[nodeID] else {
                continue
            }
            let virtualHosts = configuration.virtualHostConfiguration
            let defaultHostID = virtualHosts.map {
                redacted("virtualHostID", $0.defaultHostID)
            } ?? "Not configured"
            rows.append([
                normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state), "web-server",
                "server", "Not applicable", String(configuration.port),
                redacted("documentRoot", configuration.documentRoot), "configured",
                webListenerState(nodeID: nodeID, state: state), "Not applicable",
                "Not applicable", "Not applicable", "Not applicable", "Not applicable",
                "virtualHostCount=\(virtualHosts?.hosts.count ?? 0); defaultHost=\(defaultHostID)",
            ])
        }

        // Virtual hosts remain separate rows so disabled hosts and the selected default are
        // visible without parsing a summary field. Hosts are ordered by normalized authority.
        for nodeID in state.runtimeWebServerConfigurationsByNodeID.keys.sorted(by: uuidIsOrderedBefore) {
            guard let configuration = state.runtimeWebServerConfigurationsByNodeID[nodeID],
                  let virtualHosts = configuration.virtualHostConfiguration else {
                continue
            }
            for host in virtualHosts.hosts.sorted(by: webVirtualHostIsOrderedBefore) {
                rows.append([
                    normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state), "virtual-host",
                    redacted("virtualHostID", host.id), "Not applicable",
                    host.authority.port.map(String.init) ?? "listener port",
                    redacted("documentRoot", host.documentRoot), host.isEnabled ? "enabled" : "disabled",
                    host.id == virtualHosts.defaultHostID ? "default" : "not-default",
                    redacted("host", host.authority.hostname), "Not applicable", "Not applicable",
                    "Not applicable", "Not applicable",
                    "parentService=web server",
                ])
            }
        }

        // Every router/gateway receives explicit configuration, policy, listener, and allowed-
        // network rows. This also makes secure defaults (disabled and deny-all) reportable.
        for nodeID in administrationNodeIDs.sorted(by: uuidIsOrderedBefore) {
            let configuration = state.runtimeWebAdministrationConfigurationsByNodeID[nodeID]
            let policy = configuration?.accessPolicy
                ?? TopologyRuntimeWebAdministrationAccessPolicy()
            let policySource = configuration == nil ? "default" : "explicit"
            let response = state.runtimeWebAdministrationResponsesByNodeID[nodeID]

            rows.append([
                normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state),
                "administration-configuration", "admin", "Not applicable",
                configuration.map { String($0.port) } ?? "Not configured", "Not applicable",
                configuration == nil ? "not configured" : "configured", "Not applicable",
                "Not applicable", "/admin", "GET,HEAD,POST", "Not applicable",
                "text/html; charset=utf-8",
                "serviceRole=router/gateway administration; capability=read-write; mutationMethod=POST",
            ])
            rows.append([
                normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state),
                "administration-policy", policySource, "Not applicable", "Not applicable",
                "Not applicable", policy.isEnabled ? "enabled" : "disabled", "Not applicable",
                "Not applicable", "Not applicable", "Not applicable", "Not applicable",
                "Not applicable",
                "allowedNetworkCount=\(policy.allowedSourceNetworks.count); emptyAllowList=deny-all",
            ])
            rows.append([
                normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state),
                "administration-listener", "listener", "Not applicable",
                state.runtimeWebAdministrationByNodeID[nodeID].map { String($0.port) }
                    ?? configuration.map { String($0.port) } ?? "Not configured",
                "Not applicable", policy.isEnabled ? "policy enabled" : "policy disabled",
                webAdministrationListenerState(nodeID: nodeID, state: state),
                "Not applicable", "/admin",
                "GET,HEAD,POST", response.map { String($0.statusCode) } ?? "Not applicable",
                response?.contentType ?? "Not applicable",
                response.map {
                    "lastResponse=" + redacted(
                        "detail",
                        TopologyReportExportRedaction.bounded($0.detail, maximumCharacters: 256)
                    )
                } ?? "No administration response recorded",
            ])

            if policy.allowedSourceNetworks.isEmpty {
                rows.append([
                    normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state),
                    "administration-allowed-network", "none", "Not applicable", "Not applicable",
                    "Not applicable", "none configured", "Not applicable", "Not configured",
                    "Not configured", "Not applicable", "Not applicable", "Not applicable",
                    policy.isEnabled ? "deny all sources" : "policy disabled; no sources allowed",
                ])
            } else {
                for (index, network) in policy.allowedSourceNetworks
                    .sorted(by: webAdministrationNetworkIsOrderedBefore)
                    .enumerated() {
                    rows.append([
                        normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state),
                        "administration-allowed-network",
                        String(format: "network-%03d", index + 1), "Not applicable",
                        "Not applicable", "Not applicable", "allowed", "Not applicable",
                        network.networkAddress, network.subnetMask, "Not applicable",
                        "Not applicable", "Not applicable", "source allow list entry",
                    ])
                }
            }
        }

        let browserNodeIDs = Set(state.runtimeWebBrowserConfigurationsByNodeID.keys)
            .union(state.runtimeWebBrowserStateByNodeID.keys)
        for nodeID in browserNodeIDs.sorted(by: uuidIsOrderedBefore) {
            let configuration = state.runtimeWebBrowserConfigurationsByNodeID[nodeID]
            let runtimeState = state.runtimeWebBrowserStateByNodeID[nodeID]
            var detail = [
                "resolvedIP=\(runtimeState?.resolvedIPAddress.nilIfBlank ?? "Not configured")",
                "historyCount=\(runtimeState?.history.count ?? 0)",
                "historyIndex=\(runtimeState?.historyIndex.map(String.init) ?? "Not configured")",
            ]
            if let errorMessage = runtimeState?.errorMessage?.nilIfBlank {
                detail.append(
                    "error=" + redacted(
                        "error",
                        TopologyReportExportRedaction.bounded(errorMessage, maximumCharacters: 256)
                    )
                )
            }
            rows.append([
                normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state), "browser",
                "browser", "Not applicable",
                configuration.map { String($0.lastPort) } ?? "Not configured", "Not applicable",
                configuration == nil ? "transient only" : "configured",
                runtimeState?.connectionState.rawValue ?? "not started",
                configuration?.lastHost.nilIfBlank.map { redacted("host", $0) } ?? "Not configured",
                configuration?.lastPath.nilIfBlank.map { redacted("path", $0) } ?? "Not configured",
                "Not applicable", runtimeState?.statusCode.map(String.init) ?? "Not applicable",
                runtimeState?.contentType ?? "Not applicable",
                redacted("detail", detail.joined(separator: "; ")),
            ])
        }

        var requestLogs: [(nodeID: UUID, entry: TopologyRuntimeWebServerRequestLogEntry)] = []
        for (nodeID, entries) in state.runtimeWebServerRequestLogsByNodeID {
            requestLogs.append(contentsOf: entries.map { (nodeID: nodeID, entry: $0) })
        }
        requestLogs.sort(by: webRequestLogIsOrderedBefore)
        for record in requestLogs {
            let entry = record.entry
            let isAdministrationRequest = isWebAdministrationPath(entry.path)
            let requestPort = isAdministrationRequest
                ? state.runtimeWebAdministrationConfigurationsByNodeID[record.nodeID]?.port
                : state.runtimeWebServerConfigurationsByNodeID[record.nodeID]?.port
            rows.append([
                normalizedUUID(record.nodeID), nodeDisplayName(record.nodeID, state: state),
                isAdministrationRequest ? "administration-request-log" : "web-request-log",
                String(entry.id), String(entry.timestampMilliseconds),
                requestPort.map(String.init) ?? "Not configured", "Not applicable",
                "response", "Not applicable", redacted("remoteIPAddress", entry.remoteIPAddress),
                redacted("path", entry.path), redacted("method", entry.method),
                String(entry.statusCode), entry.contentType ?? "Not configured",
                redacted(
                    "detail",
                    TopologyReportExportRedaction.bounded(entry.detail, maximumCharacters: 256)
                ),
            ])
        }

        return section(
            id: "web-services",
            title: "Web services and administration",
            columns: [
                "nodeID", "nodeName", "entryType", "entryID", "timeMs", "port",
                "documentRoot", "configurationState", "listenerState", "hostOrRemoteIP",
                "networkMaskOrPath", "method", "statusCode", "contentType", "detail",
            ],
            rows: rows,
            emptyMessage: "No web server, virtual-host, browser, or administration configuration"
        )
    }

    private static func emailSection(state: TopologyEditorState) -> TopologyDetailedReportSection {
        var rows: [[String]] = []
        for nodeID in state.runtimeEmailClientConfigurationsByNodeID.keys.sorted(by: uuidIsOrderedBefore) {
            let configuration = state.runtimeEmailClientConfigurationsByNodeID[nodeID] ?? .init()
            rows.append([
                normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state), "client",
                redacted("email", configuration.email), redacted("username", configuration.username),
                TopologyReportExportRedaction.marker, configuration.pop3Host, String(configuration.pop3Port),
                configuration.smtpHost, String(configuration.smtpPort), String(configuration.inbox.count),
                String(configuration.sent.count), String(configuration.drafts.count), "Not applicable",
            ])
        }
        for nodeID in state.runtimeEmailServerConfigurationsByNodeID.keys.sorted(by: uuidIsOrderedBefore) {
            let configuration = state.runtimeEmailServerConfigurationsByNodeID[nodeID] ?? .init()
            if configuration.accounts.isEmpty {
                rows.append([
                    normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state), "server",
                    configuration.domain, "Not configured", "Not configured", "Not applicable",
                    String(configuration.pop3Port), "Not applicable", String(TopologyRuntimeEmailServerConfiguration.smtpPort),
                    "Not applicable", "Not applicable", "Not applicable", "0",
                ])
            } else {
                for account in configuration.accounts.sorted(by: emailServerAccountIsOrderedBefore) {
                    rows.append([
                        normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state), "server-account",
                        "\(account.username)@\(configuration.domain)", redacted("username", account.username),
                        TopologyReportExportRedaction.marker, "Not applicable", String(configuration.pop3Port),
                        "Not applicable", String(TopologyRuntimeEmailServerConfiguration.smtpPort),
                        "Not applicable", "Not applicable", "Not applicable", String(account.mailbox.count),
                    ])
                }
            }
        }
        return section(
            id: "email",
            title: "Email",
            columns: ["nodeID", "nodeName", "role", "addressOrDomain", "username", "password", "pop3Host", "pop3Port", "smtpHost", "smtpPort", "inboxCount", "sentCount", "draftCount", "serverMailboxCount"],
            rows: rows,
            emptyMessage: "No email clients, servers, accounts, or messages configured"
        )
    }

    private static func remoteLinksSection(state: TopologyEditorState) -> TopologyDetailedReportSection {
        var rows: [[String]] = []
        for nodeID in state.remoteLinkConfigurationsByNodeID.keys.sorted(by: uuidIsOrderedBefore) {
            let configuration = state.remoteLinkConfigurationsByNodeID[nodeID]!
            let runtimeStatus = state.networkRuntime.remoteLinkRuntimeStatus(nodeID: nodeID)
            rows.append([
                normalizedUUID(nodeID), nodeDisplayName(nodeID, state: state),
                TopologyReportExportRedaction.marker, String(configuration.latencyMilliseconds),
                bool(configuration.isEnabled), configuration.transportMode.rawValue,
                configuration.lanRole.rawValue, String(configuration.lanPort),
                configuration.lanJoinMethod.rawValue,
                configuration.lanRemoteHost.nilIfBlank ?? "Not configured",
                String(configuration.lanRemotePort),
                runtimeStatus.map(remoteLinkConditionDescription) ?? "Not available",
            ])
        }
        return section(
            id: "remote-links",
            title: "Remote Links",
            columns: ["nodeID", "nodeName", "linkCodeOrPairIdentifier", "latencyMs", "enabled", "transport", "lanRole", "lanPort", "joinMethod", "remoteHost", "remotePort", "runtimeState"],
            rows: rows,
            emptyMessage: "No Remote Links configured"
        )
    }

    private static func packetLossSection(
        state: TopologyEditorState,
        context: TopologyDetailedReportContext
    ) -> TopologyDetailedReportSection {
        let retainedDrops = state.networkRuntime.state.packetTraces.filter { trace in
            trace.operation == .dropped
                && trace.detail == "global packet-loss simulation"
        }
        let firstDropTime = retainedDrops.map(\.timeMilliseconds).min().map(String.init)
            ?? "Not applicable"
        let lastDropTime = retainedDrops.map(\.timeMilliseconds).max().map(String.init)
            ?? "Not applicable"
        let configuredDescription = context.packetLossPolicyDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let currentPolicy = configuredDescription.isEmpty || configuredDescription == "Not configured"
            ? (state.networkRuntime.state.globalPacketLossEnabled ? "drop all frames" : "disabled")
            : configuredDescription

        return section(
            id: "packet-loss",
            title: "Global packet-loss policy and evidence",
            columns: ["scope", "entryType", "value", "firstTimeMs", "lastTimeMs"],
            rows: [
                [
                    "global", "current-policy", redacted("policy", currentPolicy),
                    "Not applicable", "Not applicable",
                ],
                [
                    "global", "retained-drop-evidence", String(retainedDrops.count),
                    firstDropTime, lastDropTime,
                ],
            ],
            emptyMessage: "Packet-loss policy and evidence unavailable"
        )
    }

    private static func trafficSummarySection(
        captureDocument: TopologyPacketCaptureExportDocument
    ) -> TopologyDetailedReportSection {
        let groups = Dictionary(grouping: captureDocument.records) {
            TrafficSummaryKey(protocolName: $0.protocolName, layer: $0.layer, operation: $0.operation)
        }
        let sortedKeys = groups.keys.sorted(by: trafficSummaryKeyIsOrderedBefore)
        var rows: [[String]] = []
        rows.reserveCapacity(sortedKeys.count)
        for key in sortedKeys {
            let records = groups[key] ?? []
            let times = records.map(\.timeMilliseconds)
            let firstTime = times.min().map { String($0) } ?? "Not applicable"
            let lastTime = times.max().map { String($0) } ?? "Not applicable"
            let dropCount = records.filter {
                $0.operation == TopologyPacketTraceOperation.dropped.rawValue
            }.count
            rows.append([
                key.protocolName,
                key.layer,
                key.operation,
                String(records.count),
                firstTime,
                lastTime,
                String(dropCount),
            ])
        }
        return section(
            id: "network-traffic-summary",
            title: "Network traffic summary",
            columns: ["protocol", "layer", "operation", "eventCount", "firstTimeMs", "lastTimeMs", "dropCount"],
            rows: rows,
            emptyMessage: "No network traffic captured"
        )
    }

    private static func trafficEventsSection(
        captureDocument: TopologyPacketCaptureExportDocument
    ) -> TopologyDetailedReportSection {
        let rows = captureDocument.records.map { record in
            [
                String(record.number), String(record.timeMilliseconds), String(record.traceID),
                record.nodeName, record.interfaceName ?? "Not configured", record.direction,
                record.layer, record.operation, record.source, record.destination,
                record.protocolName, record.detail.isEmpty ? "Not specified" : record.detail,
            ]
        }
        return section(
            id: "network-traffic-events",
            title: "Network traffic events",
            columns: ["number", "timeMs", "traceID", "nodeName", "interfaceName", "direction", "layer", "operation", "source", "destination", "protocol", "detail"],
            rows: rows,
            emptyMessage: "No network traffic captured"
        )
    }

    private static func section(
        id: String,
        title: String,
        columns: [String],
        rows: [[String]],
        emptyMessage: String
    ) -> TopologyDetailedReportSection {
        TopologyDetailedReportSection(
            id: id,
            title: title,
            columns: columns,
            rows: rows.map { row in
                row.map { TopologyReportExportRedaction.redactFreeText($0) }
            },
            emptyMessage: emptyMessage
        )
    }

    private static func redacted(_ fieldName: String, _ value: String) -> String {
        TopologyReportExportRedaction.redact(fieldName: fieldName, value: value)
    }

    private static func nodeDisplayName(_ nodeID: UUID, state: TopologyEditorState) -> String {
        redacted("nodeName", state.graph.node(withID: nodeID)?.displayName ?? normalizedUUID(nodeID))
    }

    private static func remoteLinkConditionDescription(_ status: TopologyRemoteLinkRuntimeStatus) -> String {
        switch status.condition {
        case .stopped: return "stopped"
        case .missingConfiguration: return "missing configuration"
        case .disabled: return "disabled"
        case .unpaired: return "unpaired"
        case let .ambiguous(enabledNodeCount): return "ambiguous (enabled nodes: \(enabledNodeCount))"
        case .detached: return "detached"
        case .detachedLAN: return "LAN detached"
        case .waitingForPeer: return "waiting for peer"
        case .connecting: return "connecting"
        case let .connectionFailed(message): return redacted("error", message)
        case .active: return "active"
        case let .activeLAN(peerName): return "LAN active with \(redacted("peerName", peerName))"
        }
    }

    private static func decimal(_ value: CGFloat) -> String {
        guard value.isFinite else { return "Not finite" }
        return String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), Double(value))
    }

    private static func bool(_ value: Bool) -> String { value ? "true" : "false" }
    private static func normalizedUUID(_ value: UUID) -> String { value.uuidString.lowercased() }

    private static func nodeIsOrderedBefore(_ lhs: TopologyNode, _ rhs: TopologyNode) -> Bool {
        normalizedUUID(lhs.id) < normalizedUUID(rhs.id)
    }

    private static func portIsOrderedBefore(_ lhs: TopologyPortMetadata, _ rhs: TopologyPortMetadata) -> Bool {
        normalizedUUID(lhs.id) < normalizedUUID(rhs.id)
    }

    private static func linkIsOrderedBefore(_ lhs: TopologyLink, _ rhs: TopologyLink) -> Bool {
        normalizedUUID(lhs.id) < normalizedUUID(rhs.id)
    }

    private static func uuidIsOrderedBefore(_ lhs: UUID, _ rhs: UUID) -> Bool {
        normalizedUUID(lhs) < normalizedUUID(rhs)
    }

    private static func protocolDefinitionIsOrderedBefore(
        _ lhs: TopologyProtocolApplicationDefinition,
        _ rhs: TopologyProtocolApplicationDefinition
    ) -> Bool {
        normalizedUUID(lhs.id) < normalizedUUID(rhs.id)
    }

    private static func manualRouteIsOrderedBefore(
        _ lhs: TopologyRuntimeManualRoute,
        _ rhs: TopologyRuntimeManualRoute
    ) -> Bool {
        [lhs.destinationNetwork, lhs.subnetMask, lhs.gateway, lhs.interfaceIPAddress]
            .lexicographicallyPrecedes([rhs.destinationNetwork, rhs.subnetMask, rhs.gateway, rhs.interfaceIPAddress])
    }

    private static func routeRowIsOrderedBefore(
        _ lhs: TopologyRuntimeRouteRow,
        _ rhs: TopologyRuntimeRouteRow
    ) -> Bool {
        [lhs.destinationNetwork, lhs.subnetMask, lhs.nextHop, lhs.interfaceIPAddress, lhs.origin.rawValue]
            .lexicographicallyPrecedes([rhs.destinationNetwork, rhs.subnetMask, rhs.nextHop, rhs.interfaceIPAddress, rhs.origin.rawValue])
    }


    private static func dnsCacheEntryIsOrderedBefore(
        _ lhs: TopologyRuntimeDNSCacheEntry,
        _ rhs: TopologyRuntimeDNSCacheEntry
    ) -> Bool {
        if lhs.hostname != rhs.hostname { return lhs.hostname < rhs.hostname }
        if lhs.serverIPAddress != rhs.serverIPAddress { return lhs.serverIPAddress < rhs.serverIPAddress }
        return lhs.expiresAtMilliseconds < rhs.expiresAtMilliseconds
    }

    private static func dhcpAssignmentIsOrderedBefore(
        _ lhs: TopologyDHCPStaticAssignment,
        _ rhs: TopologyDHCPStaticAssignment
    ) -> Bool {
        if lhs.ipAddress != rhs.ipAddress { return lhs.ipAddress < rhs.ipAddress }
        if lhs.macAddress != rhs.macAddress { return lhs.macAddress < rhs.macAddress }
        return normalizedUUID(lhs.id) < normalizedUUID(rhs.id)
    }

    private static func portForwardingIsOrderedBefore(
        _ lhs: TopologyGatewayPortForwardingRow,
        _ rhs: TopologyGatewayPortForwardingRow
    ) -> Bool {
        [lhs.protocolValue, lhs.publicPortValue, lhs.lanIPAddress, lhs.lanPortValue]
            .lexicographicallyPrecedes([rhs.protocolValue, rhs.publicPortValue, rhs.lanIPAddress, rhs.lanPortValue])
    }

    private static func natMappingIsOrderedBefore(
        _ lhs: TopologyRuntimeNATMapping,
        _ rhs: TopologyRuntimeNATMapping
    ) -> Bool {
        if normalizedUUID(lhs.gatewayNodeID) != normalizedUUID(rhs.gatewayNodeID) {
            return normalizedUUID(lhs.gatewayNodeID) < normalizedUUID(rhs.gatewayNodeID)
        }
        if lhs.protocolNumber.rawValue != rhs.protocolNumber.rawValue {
            return lhs.protocolNumber.rawValue < rhs.protocolNumber.rawValue
        }
        if lhs.translatedPortOrIdentifier != rhs.translatedPortOrIdentifier {
            return lhs.translatedPortOrIdentifier < rhs.translatedPortOrIdentifier
        }
        return normalizedUUID(lhs.id) < normalizedUUID(rhs.id)
    }

    private static func webVirtualHostIsOrderedBefore(
        _ lhs: TopologyRuntimeWebVirtualHost,
        _ rhs: TopologyRuntimeWebVirtualHost
    ) -> Bool {
        if lhs.authority.hostname != rhs.authority.hostname {
            return lhs.authority.hostname < rhs.authority.hostname
        }
        switch (lhs.authority.port, rhs.authority.port) {
        case let (.some(left), .some(right)) where left != right:
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return lhs.id < rhs.id
        }
    }

    private static func webAdministrationNetworkIsOrderedBefore(
        _ lhs: TopologyRuntimeWebAdministrationIPv4Network,
        _ rhs: TopologyRuntimeWebAdministrationIPv4Network
    ) -> Bool {
        let leftAddress = ipv4NumericSortValue(lhs.networkAddress)
        let rightAddress = ipv4NumericSortValue(rhs.networkAddress)
        if leftAddress != rightAddress { return leftAddress < rightAddress }
        return ipv4NumericSortValue(lhs.subnetMask) < ipv4NumericSortValue(rhs.subnetMask)
    }

    private static func ipv4NumericSortValue(_ value: String) -> UInt32 {
        value.split(separator: ".").reduce(UInt32(0)) { partial, octet in
            (partial << 8) | UInt32(octet)!
        }
    }

    private static func webRequestLogIsOrderedBefore(
        _ lhs: (nodeID: UUID, entry: TopologyRuntimeWebServerRequestLogEntry),
        _ rhs: (nodeID: UUID, entry: TopologyRuntimeWebServerRequestLogEntry)
    ) -> Bool {
        if lhs.entry.timestampMilliseconds != rhs.entry.timestampMilliseconds {
            return lhs.entry.timestampMilliseconds < rhs.entry.timestampMilliseconds
        }
        if lhs.entry.id != rhs.entry.id {
            return lhs.entry.id < rhs.entry.id
        }
        return normalizedUUID(lhs.nodeID) < normalizedUUID(rhs.nodeID)
    }

    private static func webListenerState(nodeID: UUID, state: TopologyEditorState) -> String {
        guard let process = state.runtimeWebServerByNodeID[nodeID] else { return "stopped" }
        return "running on port \(process.port)"
    }

    private static func webAdministrationListenerState(
        nodeID: UUID,
        state: TopologyEditorState
    ) -> String {
        guard let process = state.runtimeWebAdministrationByNodeID[nodeID] else {
            return "stopped"
        }
        return "running on port \(process.port)"
    }

    private static func isWebAdministrationPath(_ path: String) -> Bool {
        path == "/admin" || path.hasPrefix("/admin/")
    }

    private static func emailServerAccountIsOrderedBefore(
        _ lhs: TopologyRuntimeEmailServerAccount,
        _ rhs: TopologyRuntimeEmailServerAccount
    ) -> Bool {
        lhs.username.caseInsensitiveCompare(rhs.username) == .orderedAscending
    }

    private struct FirewallDecisionKey: Hashable {
        let nodeID: UUID
        let accepted: Bool
        let ruleIndex: Int?
    }

    private static func firewallDecisionKeyIsOrderedBefore(
        _ lhs: FirewallDecisionKey,
        _ rhs: FirewallDecisionKey
    ) -> Bool {
        if normalizedUUID(lhs.nodeID) != normalizedUUID(rhs.nodeID) {
            return normalizedUUID(lhs.nodeID) < normalizedUUID(rhs.nodeID)
        }
        if lhs.accepted != rhs.accepted { return !lhs.accepted && rhs.accepted }
        return (lhs.ruleIndex ?? -1) < (rhs.ruleIndex ?? -1)
    }

    private struct TrafficSummaryKey: Hashable {
        let protocolName: String
        let layer: String
        let operation: String
    }

    private static func trafficSummaryKeyIsOrderedBefore(
        _ lhs: TrafficSummaryKey,
        _ rhs: TrafficSummaryKey
    ) -> Bool {
        [lhs.protocolName, lhs.layer, lhs.operation]
            .lexicographicallyPrecedes([rhs.protocolName, rhs.layer, rhs.operation])
    }
}

enum TopologyDetailedReportTextRenderer {
    static let mediaType = "text/plain; charset=utf-8"
    static let fileExtension = "txt"

    static func render(_ document: TopologyDetailedReportDocument) -> String {
        var lines = [
            "# FiliusPad detailed-report",
            "# format-version: \(document.formatVersion)",
            "# encoding: UTF-8",
            "# ordering: stable section order; UUID and semantic field ordering within sections",
            "# redaction: passwords, credentials, tokens, LAN link codes/digests, payloads, protocol templates, file contents, browser bodies, message bodies",
            "title: \(singleLine(document.title))",
        ]

        for section in document.sections {
            lines.append("")
            lines.append("[\(section.id)] \(singleLine(section.title))")
            lines.append(section.columns.map(singleLine).joined(separator: "\t"))
            if section.rows.isEmpty {
                lines.append("(empty)\t\(singleLine(section.emptyMessage))")
            } else {
                lines.append(contentsOf: section.rows.map { row in
                    normalizedRow(row, columnCount: section.columns.count)
                        .map(singleLine)
                        .joined(separator: "\t")
                })
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func render(
        state: TopologyEditorState,
        context: TopologyDetailedReportContext = .init()
    ) -> String {
        render(TopologyDetailedReportBuilder.makeDocument(state: state, context: context))
    }

    static func makeUTF8Data(
        state: TopologyEditorState,
        context: TopologyDetailedReportContext = .init()
    ) -> Data {
        Data(render(state: state, context: context).utf8)
    }

    private static func normalizedRow(_ row: [String], columnCount: Int) -> [String] {
        if row.count == columnCount { return row }
        if row.count < columnCount {
            return row + Array(repeating: "Not configured", count: columnCount - row.count)
        }
        return Array(row.prefix(columnCount))
    }

    private static func singleLine(_ value: String) -> String {
        TopologyReportExportRedaction.singleLine(value: value)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
