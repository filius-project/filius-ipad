import CoreGraphics
import Foundation

enum TopologyProjectSnapshotValidationError: Error, Equatable {
    case duplicateRuntimeDeviceConfiguration(nodeID: UUID)
    case duplicateRuntimeInterfaceConfiguration(nodeID: UUID, portID: UUID)
    case runtimeInterfaceConfigurationReferencesUnknownNode(nodeID: UUID, portID: UUID)
    case runtimeInterfaceConfigurationReferencesUnknownPort(nodeID: UUID, portID: UUID)
    case runtimeInterfaceConfigurationReferencesUnsupportedNodeKind(nodeID: UUID, kind: TopologyNodeKind)
    case duplicateRuntimeManualRouteTable(nodeID: UUID)
    case runtimeManualRouteTableReferencesUnknownNode(nodeID: UUID)
    case runtimeManualRouteTableReferencesUnsupportedNodeKind(nodeID: UUID, kind: TopologyNodeKind)
    case duplicateRuntimeRIPConfiguration(nodeID: UUID)
    case runtimeRIPConfigurationReferencesUnknownNode(nodeID: UUID)
    case runtimeRIPConfigurationReferencesUnsupportedNodeKind(nodeID: UUID, kind: TopologyNodeKind)
    case duplicateRuntimeDHCPClientConfiguration(nodeID: UUID)
    case runtimeDHCPClientConfigurationReferencesUnknownNode(nodeID: UUID)
    case runtimeDHCPClientConfigurationReferencesUnsupportedNodeKind(nodeID: UUID, kind: TopologyNodeKind)
    case duplicateRuntimeDHCPServerConfiguration(nodeID: UUID)
    case runtimeDHCPServerConfigurationReferencesUnknownNode(nodeID: UUID)
    case runtimeDHCPServerConfigurationReferencesUnsupportedNodeKind(nodeID: UUID, kind: TopologyNodeKind)
    case duplicateRuntimeFirewallConfiguration(nodeID: UUID)
    case runtimeFirewallConfigurationReferencesUnknownNode(nodeID: UUID)
    case runtimeFirewallConfigurationReferencesUnsupportedNodeKind(nodeID: UUID, kind: TopologyNodeKind)
    case runtimeFirewallConfigurationMissingInstalledProgram(nodeID: UUID)
    case duplicateRuntimePortForwardingConfiguration(nodeID: UUID)
    case runtimePortForwardingConfigurationReferencesUnknownNode(nodeID: UUID)
    case runtimePortForwardingConfigurationReferencesUnsupportedNodeKind(nodeID: UUID, kind: TopologyNodeKind)
    case duplicateSwitchConfiguration(nodeID: UUID)
    case switchConfigurationReferencesUnknownNode(nodeID: UUID)
    case switchConfigurationReferencesUnsupportedNodeKind(nodeID: UUID, kind: TopologyNodeKind)
    case duplicateRemoteLinkConfiguration(nodeID: UUID)
    case remoteLinkConfigurationsFieldMissing
    case missingRemoteLinkConfiguration(nodeID: UUID)
    case remoteLinkConfigurationHasBlankPairIdentifier(nodeID: UUID)
    case remoteLinkConfigurationHasInvalidLANPort(nodeID: UUID)
    case remoteLinkConfigurationHasBlankLANRemoteHost(nodeID: UUID)
    case remoteLinkConfigurationReferencesUnknownNode(nodeID: UUID)
    case remoteLinkConfigurationReferencesUnsupportedNodeKind(nodeID: UUID, kind: TopologyNodeKind)
    case duplicateHostWirelessConfiguration(nodeID: UUID)
    case hostWirelessConfigurationReferencesUnknownNode(nodeID: UUID)
    case hostWirelessConfigurationReferencesUnsupportedNodeKind(nodeID: UUID, kind: TopologyNodeKind)
    case duplicateRuntimeDNSRecord(hostname: String)
    case duplicateRuntimeDNSServerConfiguration(nodeID: UUID)
    case runtimeDNSServerConfigurationReferencesUnknownNode(nodeID: UUID)
    case runtimeDNSServerConfigurationReferencesUnsupportedNodeKind(nodeID: UUID, kind: TopologyNodeKind)
    case runtimeDNSServerConfigurationMissingInstalledProgram(nodeID: UUID)
    case runtimeDNSMigrationMissingOwner
    case runtimeDNSLegacyFieldUnexpected
    case invalidRuntimeDNSRecord(hostname: String)
    case runtimeDNSConfigurationsFieldMissing
    case duplicateRuntimeWebServerConfiguration(nodeID: UUID)
    case runtimeWebServerConfigurationReferencesUnknownNode(nodeID: UUID)
    case runtimeWebServerConfigurationReferencesUnsupportedNodeKind(nodeID: UUID, kind: TopologyNodeKind)
    case invalidRuntimeWebServerConfiguration(nodeID: UUID)
    case runtimeWebAdministrationConfigurationsFieldMissing
    case runtimeWebAdministrationPoliciesFieldMissing
    case duplicateRuntimeWebAdministrationConfiguration(nodeID: UUID)
    case runtimeWebAdministrationConfigurationReferencesUnknownNode(nodeID: UUID)
    case runtimeWebAdministrationConfigurationReferencesUnsupportedNodeKind(nodeID: UUID, kind: TopologyNodeKind)
    case invalidRuntimeWebAdministrationConfiguration(nodeID: UUID)
    case duplicateRuntimeWebBrowserConfiguration(nodeID: UUID)
    case runtimeWebBrowserConfigurationReferencesUnknownNode(nodeID: UUID)
    case runtimeWebBrowserConfigurationReferencesUnsupportedNodeKind(nodeID: UUID, kind: TopologyNodeKind)
    case invalidRuntimeWebBrowserConfiguration(nodeID: UUID)
    case duplicateVirtualFileSystem(nodeID: UUID)
    case virtualFileSystemsFieldMissing
    case missingVirtualFileSystem(nodeID: UUID)
    case virtualFileSystemReferencesUnknownNode(nodeID: UUID)
    case virtualFileSystemReferencesUnsupportedNodeKind(nodeID: UUID, kind: TopologyNodeKind)
    case invalidVirtualFileSystem(nodeID: UUID, detail: String)
    case invalidVirtualFileSystemProject(detail: String)
    case documentationItemsFieldMissing
    case duplicateDocumentationItem(itemID: UUID)
    case duplicateDocumentationOrder(order: Int)
    case invalidDocumentationItem(itemID: UUID)
    case protocolApplicationDefinitionsFieldMissing
    case protocolApplicationInstallationsFieldMissing
    case invalidProtocolApplicationProject(error: TopologyProtocolApplicationValidationError)
}

struct TopologyProjectSnapshot: Codable, Equatable {
    let graph: TopologyGraphSnapshot
    let viewport: ViewportTransformSnapshot
    let runtimeDeviceConfigurations: [TopologyRuntimeDeviceConfigurationSnapshot]
    let runtimeInterfaceConfigurations: [TopologyRuntimeInterfaceConfigurationSnapshot]
    let runtimeManualRouteTables: [TopologyRuntimeManualRouteTableSnapshot]
    let runtimeRIPEnabledNodeIDs: [UUID]
    let runtimeDHCPClientConfigurations: [TopologyDHCPClientConfigurationSnapshot]
    let runtimeDHCPServerConfigurations: [TopologyDHCPServerConfigurationSnapshot]
    let runtimeFirewallConfigurations: [TopologyFirewallConfigurationSnapshot]
    let runtimePortForwardingConfigurations: [TopologyGatewayPortForwardingTableSnapshot]
    let switchConfigurations: [TopologySwitchConfigurationSnapshot]
    let remoteLinkConfigurations: [TopologyRemoteLinkConfigurationSnapshot]
    let hostWirelessConfigurations: [TopologyHostWirelessConfigurationSnapshot]
    let runtimeDNSRecords: [TopologyRuntimeDNSRecordSnapshot]
    let runtimeDNSServerConfigurations: [TopologyRuntimeDNSServerConfigurationSnapshot]
    let runtimeInstalledPrograms: [TopologyRuntimeInstalledProgramSnapshot]
    let runtimeWebServerConfigurations: [TopologyRuntimeWebServerConfigurationSnapshot]
    let runtimeWebAdministrationConfigurations: [TopologyRuntimeWebAdministrationConfigurationSnapshot]
    private let legacyRuntimeWebAdministrationPolicies: [TopologyRuntimeWebAdministrationPolicySnapshot]
    let runtimeWebBrowserConfigurations: [TopologyRuntimeWebBrowserConfigurationSnapshot]
    let virtualFileSystems: [TopologyVirtualFileSystemSnapshot]
    let documentationItems: [TopologyDocumentationItemSnapshot]
    let protocolApplicationDefinitions: [TopologyProtocolApplicationDefinition]
    let protocolApplicationInstallations: [TopologyProtocolApplicationInstallationSnapshot]
    let persistenceRevision: UInt64
    private let shouldDeriveLegacyRuntimeInterfaceDefaults: Bool
    private let remoteLinkConfigurationsWerePresent: Bool
    private let virtualFileSystemsWerePresent: Bool
    private let documentationItemsWerePresent: Bool
    private let runtimeDNSConfigurationsWerePresent: Bool
    private let runtimeWebAdministrationConfigurationsWerePresent: Bool
    private let runtimeWebAdministrationPoliciesWerePresent: Bool
    private let protocolApplicationDefinitionsWerePresent: Bool
    private let protocolApplicationInstallationsWerePresent: Bool

    init(
        graph: TopologyGraphSnapshot,
        viewport: ViewportTransformSnapshot,
        runtimeDeviceConfigurations: [TopologyRuntimeDeviceConfigurationSnapshot],
        runtimeInterfaceConfigurations: [TopologyRuntimeInterfaceConfigurationSnapshot] = [],
        runtimeManualRouteTables: [TopologyRuntimeManualRouteTableSnapshot] = [],
        runtimeRIPEnabledNodeIDs: [UUID] = [],
        runtimeDHCPClientConfigurations: [TopologyDHCPClientConfigurationSnapshot] = [],
        runtimeDHCPServerConfigurations: [TopologyDHCPServerConfigurationSnapshot] = [],
        runtimeFirewallConfigurations: [TopologyFirewallConfigurationSnapshot] = [],
        runtimePortForwardingConfigurations: [TopologyGatewayPortForwardingTableSnapshot] = [],
        switchConfigurations: [TopologySwitchConfigurationSnapshot] = [],
        remoteLinkConfigurations: [TopologyRemoteLinkConfigurationSnapshot] = [],
        hostWirelessConfigurations: [TopologyHostWirelessConfigurationSnapshot] = [],
        runtimeDNSRecords: [TopologyRuntimeDNSRecordSnapshot] = [],
        runtimeDNSServerConfigurations: [TopologyRuntimeDNSServerConfigurationSnapshot] = [],
        runtimeInstalledPrograms: [TopologyRuntimeInstalledProgramSnapshot],
        runtimeWebServerConfigurations: [TopologyRuntimeWebServerConfigurationSnapshot] = [],
        runtimeWebAdministrationConfigurations: [TopologyRuntimeWebAdministrationConfigurationSnapshot] = [],
        runtimeWebBrowserConfigurations: [TopologyRuntimeWebBrowserConfigurationSnapshot] = [],
        virtualFileSystems: [TopologyVirtualFileSystemSnapshot] = [],
        documentationItems: [TopologyDocumentationItemSnapshot] = [],
        protocolApplicationDefinitions: [TopologyProtocolApplicationDefinition] = [],
        protocolApplicationInstallations: [TopologyProtocolApplicationInstallationSnapshot] = [],
        persistenceRevision: UInt64
    ) {
        self.graph = graph
        self.viewport = viewport
        self.runtimeDeviceConfigurations = runtimeDeviceConfigurations
        self.runtimeInterfaceConfigurations = runtimeInterfaceConfigurations
        self.runtimeManualRouteTables = runtimeManualRouteTables
        self.runtimeRIPEnabledNodeIDs = runtimeRIPEnabledNodeIDs
        self.runtimeDHCPClientConfigurations = runtimeDHCPClientConfigurations
        self.runtimeDHCPServerConfigurations = runtimeDHCPServerConfigurations
        self.runtimeFirewallConfigurations = runtimeFirewallConfigurations
        self.runtimePortForwardingConfigurations = runtimePortForwardingConfigurations
        self.switchConfigurations = switchConfigurations
        self.remoteLinkConfigurations = remoteLinkConfigurations
        self.hostWirelessConfigurations = hostWirelessConfigurations
        self.runtimeDNSRecords = runtimeDNSRecords
        self.runtimeDNSServerConfigurations = runtimeDNSServerConfigurations
        self.runtimeInstalledPrograms = runtimeInstalledPrograms
        self.runtimeWebServerConfigurations = runtimeWebServerConfigurations
        self.runtimeWebAdministrationConfigurations = runtimeWebAdministrationConfigurations
        legacyRuntimeWebAdministrationPolicies = []
        self.runtimeWebBrowserConfigurations = runtimeWebBrowserConfigurations
        if virtualFileSystems.isEmpty {
            self.virtualFileSystems = graph.toTopologyGraph().nodes
                .filter { $0.kind.isPCClassEndpoint }
                .map { TopologyVirtualFileSystemSnapshot(nodeID: $0.id, fileSystem: .defaultForDevice()) }
                .sorted { $0.nodeID.uuidString < $1.nodeID.uuidString }
        } else {
            self.virtualFileSystems = virtualFileSystems
        }
        self.documentationItems = documentationItems
        self.protocolApplicationDefinitions = protocolApplicationDefinitions
        self.protocolApplicationInstallations = protocolApplicationInstallations
        self.persistenceRevision = persistenceRevision
        shouldDeriveLegacyRuntimeInterfaceDefaults = false
        remoteLinkConfigurationsWerePresent = true
        virtualFileSystemsWerePresent = true
        documentationItemsWerePresent = true
        runtimeDNSConfigurationsWerePresent = true
        runtimeWebAdministrationConfigurationsWerePresent = true
        runtimeWebAdministrationPoliciesWerePresent = false
        protocolApplicationDefinitionsWerePresent = true
        protocolApplicationInstallationsWerePresent = true
    }

    init(state inputState: TopologyEditorState) throws {
        var state = inputState
        for nodeID in state.runtimeInstalledProgramsByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString })
            where state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(.dnsServer) == true {
            if state.virtualFileSystemsByNodeID[nodeID]?.contains(TopologyRuntimeDNSHostsFile.path) == true {
                state.synchronizeRuntimeDNSConfigurationFromHostsFile(nodeID: nodeID)
            } else {
                try state.mirrorRuntimeDNSConfigurationToHostsFile(nodeID: nodeID)
            }
        }
        for nodeID in state.runtimeInstalledProgramsByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            if state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(.emailClient) == true {
                try state.persistRuntimeEmailClientConfiguration(nodeID: nodeID)
            }
            if state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(.emailServer) == true {
                try state.persistRuntimeEmailServerConfiguration(nodeID: nodeID)
            }
            if state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(.gnutella) == true {
                try state.persistRuntimeGnutellaConfiguration(nodeID: nodeID)
            }
        }
        graph = TopologyGraphSnapshot(graph: state.graph)
        viewport = ViewportTransformSnapshot(state.viewport)
        runtimeDeviceConfigurations = state.runtimeDeviceConfigurations
            .map { nodeID, configuration in
                TopologyRuntimeDeviceConfigurationSnapshot(
                    nodeID: nodeID,
                    ipAddress: configuration.ipAddress,
                    subnetMask: configuration.subnetMask,
                    defaultGateway: configuration.defaultGateway,
                    dnsServer: configuration.dnsServer
                )
            }
            .sorted { $0.nodeID.uuidString < $1.nodeID.uuidString }
        runtimeInterfaceConfigurations = state.runtimeInterfaceConfigurations
            .map { key, configuration in
                TopologyRuntimeInterfaceConfigurationSnapshot(
                    nodeID: key.nodeID,
                    portID: key.portID,
                    ipAddress: configuration.ipAddress,
                    subnetMask: configuration.subnetMask
                )
            }
            .sorted { lhs, rhs in
                if lhs.nodeID.uuidString == rhs.nodeID.uuidString {
                    return lhs.portID.uuidString < rhs.portID.uuidString
                }
                return lhs.nodeID.uuidString < rhs.nodeID.uuidString
            }
        runtimeManualRouteTables = state.runtimeManualRoutesByNodeID
            .filter { !$0.value.isEmpty }
            .map { nodeID, routes in
                TopologyRuntimeManualRouteTableSnapshot(
                    nodeID: nodeID,
                    routes: routes.map { TopologyRuntimeManualRouteSnapshot($0) }
                )
            }
            .sorted { $0.nodeID.uuidString < $1.nodeID.uuidString }
        runtimeRIPEnabledNodeIDs = state.runtimeRIPEnabledByNodeID
            .filter { $0.value }
            .map { $0.key }
            .sorted { $0.uuidString < $1.uuidString }
        runtimeDHCPClientConfigurations = state.runtimeDHCPClientConfigurationsByNodeID
            .map { nodeID, configuration in
                TopologyDHCPClientConfigurationSnapshot(nodeID: nodeID, isEnabled: configuration.isEnabled)
            }
            .sorted { $0.nodeID.uuidString < $1.nodeID.uuidString }
        runtimeFirewallConfigurations = state.runtimeFirewallConfigurationsByNodeID
            .map { nodeID, configuration in
                TopologyFirewallConfigurationSnapshot(nodeID: nodeID, configuration: configuration)
            }
            .sorted { $0.nodeID.uuidString < $1.nodeID.uuidString }
        runtimePortForwardingConfigurations = state.runtimePortForwardingRowsByNodeID
            .map { nodeID, rows in
                TopologyGatewayPortForwardingTableSnapshot(nodeID: nodeID, rows: rows)
            }
            .sorted { $0.nodeID.uuidString < $1.nodeID.uuidString }
        switchConfigurations = state.switchConfigurationsByNodeID
            .map { TopologySwitchConfigurationSnapshot(nodeID: $0.key, configuration: $0.value) }
            .sorted { $0.nodeID.uuidString < $1.nodeID.uuidString }
        remoteLinkConfigurations = state.remoteLinkConfigurationsByNodeID
            .map { TopologyRemoteLinkConfigurationSnapshot(nodeID: $0.key, configuration: $0.value) }
            .sorted { $0.nodeID.uuidString < $1.nodeID.uuidString }
        hostWirelessConfigurations = state.hostWirelessConfigurationsByNodeID
            .filter { $0.value.isEnabled }
            .map { TopologyHostWirelessConfigurationSnapshot(nodeID: $0.key, configuration: $0.value) }
            .sorted { $0.nodeID.uuidString < $1.nodeID.uuidString }
        runtimeDHCPServerConfigurations = state.runtimeDHCPServerConfigurationsByNodeID
            .map { nodeID, configuration in
                TopologyDHCPServerConfigurationSnapshot(nodeID: nodeID, configuration: configuration)
            }
            .sorted { $0.nodeID.uuidString < $1.nodeID.uuidString }
        runtimeDNSRecords = []
        runtimeDNSServerConfigurations = state.runtimeDNSServerConfigurationsByNodeID
            .map { nodeID, configuration in
                TopologyRuntimeDNSServerConfigurationSnapshot(
                    nodeID: nodeID,
                    records: configuration.typedRecords.map(TopologyRuntimeDNSRecordSnapshot.init),
                    recursiveResolutionEnabled: configuration.recursiveResolutionEnabled,
                    forwardingServerIPAddress: configuration.forwardingServerIPAddress
                )
            }
            .sorted { $0.nodeID.uuidString < $1.nodeID.uuidString }
        runtimeWebServerConfigurations = state.runtimeWebServerConfigurationsByNodeID.map { nodeID, configuration in
            TopologyRuntimeWebServerConfigurationSnapshot(nodeID: nodeID, configuration: configuration)
        }.sorted { $0.nodeID.uuidString < $1.nodeID.uuidString }
        runtimeWebAdministrationConfigurations = state.runtimeWebAdministrationConfigurationsByNodeID.map { nodeID, configuration in
            TopologyRuntimeWebAdministrationConfigurationSnapshot(nodeID: nodeID, configuration: configuration)
        }.sorted { $0.nodeID.uuidString < $1.nodeID.uuidString }
        legacyRuntimeWebAdministrationPolicies = []
        runtimeWebBrowserConfigurations = state.runtimeWebBrowserConfigurationsByNodeID.map { nodeID, configuration in
            TopologyRuntimeWebBrowserConfigurationSnapshot(nodeID: nodeID, configuration: configuration)
        }.sorted { $0.nodeID.uuidString < $1.nodeID.uuidString }
        runtimeInstalledPrograms = state.runtimeInstalledProgramsByNodeID
            .flatMap { nodeID, programs in
                programs.map { program in
                    TopologyRuntimeInstalledProgramSnapshot(nodeID: nodeID, program: program)
                }
            }
            .sorted {
                if $0.nodeID.uuidString == $1.nodeID.uuidString {
                    return $0.program.rawValue < $1.program.rawValue
                }
                return $0.nodeID.uuidString < $1.nodeID.uuidString
            }
        virtualFileSystems = state.graph.nodes
            .filter { $0.kind.isPCClassEndpoint }
            .map { node in
                TopologyVirtualFileSystemSnapshot(
                    nodeID: node.id,
                    fileSystem: state.virtualFileSystemsByNodeID[node.id] ?? .defaultForDevice()
                )
            }
            .sorted { $0.nodeID.uuidString < $1.nodeID.uuidString }
        documentationItems = state.documentationItems.inDeterministicRenderOrder
            .map(TopologyDocumentationItemSnapshot.init)
        protocolApplicationDefinitions = state.protocolApplicationDefinitionsByID.values
            .sorted { $0.id.uuidString < $1.id.uuidString }
        protocolApplicationInstallations = state.runtimeInstalledProtocolApplicationIDsByNodeID
            .flatMap { nodeID, definitionIDs in
                definitionIDs.map { TopologyProtocolApplicationInstallationSnapshot(nodeID: nodeID, definitionID: $0) }
            }
            .sorted {
                if $0.nodeID.uuidString == $1.nodeID.uuidString {
                    return $0.definitionID.uuidString < $1.definitionID.uuidString
                }
                return $0.nodeID.uuidString < $1.nodeID.uuidString
            }
        persistenceRevision = state.persistenceRevision
        shouldDeriveLegacyRuntimeInterfaceDefaults = false
        remoteLinkConfigurationsWerePresent = true
        virtualFileSystemsWerePresent = true
        documentationItemsWerePresent = true
        runtimeDNSConfigurationsWerePresent = true
        runtimeWebAdministrationConfigurationsWerePresent = true
        runtimeWebAdministrationPoliciesWerePresent = false
        protocolApplicationDefinitionsWerePresent = true
        protocolApplicationInstallationsWerePresent = true
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case graph
        case viewport
        case runtimeDeviceConfigurations
        case runtimeInterfaceConfigurations
        case runtimeManualRouteTables
        case runtimeRIPEnabledNodeIDs
        case runtimeDHCPClientConfigurations
        case runtimeDHCPServerConfigurations
        case runtimeFirewallConfigurations
        case runtimePortForwardingConfigurations
        case switchConfigurations
        case remoteLinkConfigurations
        case hostWirelessConfigurations
        case runtimeDNSRecords
        case runtimeDNSServerConfigurations
        case runtimeInstalledPrograms
        case runtimeWebServerConfigurations
        case runtimeWebAdministrationConfigurations
        case runtimeWebAdministrationPolicies
        case runtimeWebBrowserConfigurations
        case virtualFileSystems
        case documentationItems
        case protocolApplicationDefinitions
        case protocolApplicationInstallations
        case persistenceRevision
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(graph, forKey: .graph)
        try container.encode(viewport, forKey: .viewport)
        try container.encode(runtimeDeviceConfigurations, forKey: .runtimeDeviceConfigurations)
        try container.encode(runtimeInterfaceConfigurations, forKey: .runtimeInterfaceConfigurations)
        try container.encode(runtimeManualRouteTables, forKey: .runtimeManualRouteTables)
        try container.encode(runtimeRIPEnabledNodeIDs, forKey: .runtimeRIPEnabledNodeIDs)
        try container.encode(runtimeDHCPClientConfigurations, forKey: .runtimeDHCPClientConfigurations)
        try container.encode(runtimeDHCPServerConfigurations, forKey: .runtimeDHCPServerConfigurations)
        try container.encode(runtimeFirewallConfigurations, forKey: .runtimeFirewallConfigurations)
        try container.encode(runtimePortForwardingConfigurations, forKey: .runtimePortForwardingConfigurations)
        try container.encode(switchConfigurations, forKey: .switchConfigurations)
        try container.encode(remoteLinkConfigurations, forKey: .remoteLinkConfigurations)
        try container.encode(hostWirelessConfigurations, forKey: .hostWirelessConfigurations)
        try container.encode(runtimeDNSServerConfigurations, forKey: .runtimeDNSServerConfigurations)
        try container.encode(runtimeInstalledPrograms, forKey: .runtimeInstalledPrograms)
        try container.encode(runtimeWebServerConfigurations, forKey: .runtimeWebServerConfigurations)
        try container.encode(runtimeWebAdministrationConfigurations, forKey: .runtimeWebAdministrationConfigurations)
        try container.encode(runtimeWebBrowserConfigurations, forKey: .runtimeWebBrowserConfigurations)
        try container.encode(virtualFileSystems, forKey: .virtualFileSystems)
        try container.encode(documentationItems, forKey: .documentationItems)
        try container.encode(protocolApplicationDefinitions, forKey: .protocolApplicationDefinitions)
        try container.encode(protocolApplicationInstallations, forKey: .protocolApplicationInstallations)
        try container.encode(persistenceRevision, forKey: .persistenceRevision)
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyProjectSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        graph = try container.decode(TopologyGraphSnapshot.self, forKey: .graph)
        viewport = try container.decode(ViewportTransformSnapshot.self, forKey: .viewport)
        runtimeDeviceConfigurations = try container.decode(
            [TopologyRuntimeDeviceConfigurationSnapshot].self,
            forKey: .runtimeDeviceConfigurations
        )
        shouldDeriveLegacyRuntimeInterfaceDefaults = !container.contains(.runtimeInterfaceConfigurations)
        runtimeInterfaceConfigurations = try container.decodeIfPresent(
            [TopologyRuntimeInterfaceConfigurationSnapshot].self,
            forKey: .runtimeInterfaceConfigurations
        ) ?? []
        runtimeManualRouteTables = try container.decodeIfPresent(
            [TopologyRuntimeManualRouteTableSnapshot].self,
            forKey: .runtimeManualRouteTables
        ) ?? []
        runtimeRIPEnabledNodeIDs = try container.decodeIfPresent([UUID].self, forKey: .runtimeRIPEnabledNodeIDs) ?? []
        runtimeDHCPClientConfigurations = try container.decodeIfPresent(
            [TopologyDHCPClientConfigurationSnapshot].self,
            forKey: .runtimeDHCPClientConfigurations
        ) ?? []
        runtimeDHCPServerConfigurations = try container.decodeIfPresent(
            [TopologyDHCPServerConfigurationSnapshot].self,
            forKey: .runtimeDHCPServerConfigurations
        ) ?? []
        runtimeFirewallConfigurations = try container.decodeIfPresent(
            [TopologyFirewallConfigurationSnapshot].self,
            forKey: .runtimeFirewallConfigurations
        ) ?? []
        runtimePortForwardingConfigurations = try container.decodeIfPresent(
            [TopologyGatewayPortForwardingTableSnapshot].self,
            forKey: .runtimePortForwardingConfigurations
        ) ?? []
        switchConfigurations = try container.decodeIfPresent(
            [TopologySwitchConfigurationSnapshot].self,
            forKey: .switchConfigurations
        ) ?? []
        remoteLinkConfigurationsWerePresent = container.contains(.remoteLinkConfigurations)
        if remoteLinkConfigurationsWerePresent {
            remoteLinkConfigurations = try container.decode(
                [TopologyRemoteLinkConfigurationSnapshot].self,
                forKey: .remoteLinkConfigurations
            )
        } else {
            remoteLinkConfigurations = []
        }
        hostWirelessConfigurations = try container.decodeIfPresent(
            [TopologyHostWirelessConfigurationSnapshot].self,
            forKey: .hostWirelessConfigurations
        ) ?? []
        runtimeDNSConfigurationsWerePresent = container.contains(.runtimeDNSServerConfigurations)
        runtimeDNSServerConfigurations = try container.decodeIfPresent(
            [TopologyRuntimeDNSServerConfigurationSnapshot].self,
            forKey: .runtimeDNSServerConfigurations
        ) ?? []
        runtimeDNSRecords = try container.decodeIfPresent(
            [TopologyRuntimeDNSRecordSnapshot].self,
            forKey: .runtimeDNSRecords
        ) ?? []
        runtimeInstalledPrograms = try container.decodeIfPresent(
            [TopologyRuntimeInstalledProgramSnapshot].self,
            forKey: .runtimeInstalledPrograms
        ) ?? []
        runtimeWebServerConfigurations = try container.decodeIfPresent(
            [TopologyRuntimeWebServerConfigurationSnapshot].self,
            forKey: .runtimeWebServerConfigurations
        ) ?? []
        runtimeWebAdministrationConfigurationsWerePresent = container.contains(.runtimeWebAdministrationConfigurations)
        runtimeWebAdministrationConfigurations = try container.decodeIfPresent(
            [TopologyRuntimeWebAdministrationConfigurationSnapshot].self,
            forKey: .runtimeWebAdministrationConfigurations
        ) ?? []
        runtimeWebAdministrationPoliciesWerePresent = container.contains(.runtimeWebAdministrationPolicies)
        legacyRuntimeWebAdministrationPolicies = try container.decodeIfPresent(
            [TopologyRuntimeWebAdministrationPolicySnapshot].self,
            forKey: .runtimeWebAdministrationPolicies
        ) ?? []
        runtimeWebBrowserConfigurations = try container.decodeIfPresent(
            [TopologyRuntimeWebBrowserConfigurationSnapshot].self,
            forKey: .runtimeWebBrowserConfigurations
        ) ?? []
        virtualFileSystemsWerePresent = container.contains(.virtualFileSystems)
        if virtualFileSystemsWerePresent {
            virtualFileSystems = try container.decode([TopologyVirtualFileSystemSnapshot].self, forKey: .virtualFileSystems)
        } else {
            virtualFileSystems = []
        }
        documentationItemsWerePresent = container.contains(.documentationItems)
        if documentationItemsWerePresent {
            documentationItems = try container.decode(
                [TopologyDocumentationItemSnapshot].self,
                forKey: .documentationItems
            )
        } else {
            documentationItems = []
        }
        protocolApplicationDefinitionsWerePresent = container.contains(.protocolApplicationDefinitions)
        if protocolApplicationDefinitionsWerePresent {
            protocolApplicationDefinitions = try container.decode(
                [TopologyProtocolApplicationDefinition].self,
                forKey: .protocolApplicationDefinitions
            )
        } else {
            protocolApplicationDefinitions = []
        }
        protocolApplicationInstallationsWerePresent = container.contains(.protocolApplicationInstallations)
        if protocolApplicationInstallationsWerePresent {
            protocolApplicationInstallations = try container.decode(
                [TopologyProtocolApplicationInstallationSnapshot].self,
                forKey: .protocolApplicationInstallations
            )
        } else {
            protocolApplicationInstallations = []
        }
        persistenceRevision = try container.decodeIfPresent(UInt64.self, forKey: .persistenceRevision) ?? 0
    }

    func toEditorState(
        schemaVersion: Int = TopologyProjectEnvelope.currentSchemaVersion
    ) throws -> TopologyEditorState {
        if let duplicateNodeID = duplicateRuntimeConfigurationNodeID() {
            throw TopologyProjectSnapshotValidationError.duplicateRuntimeDeviceConfiguration(nodeID: duplicateNodeID)
        }

        if let duplicateKey = duplicateRuntimeInterfaceConfigurationKey() {
            throw TopologyProjectSnapshotValidationError.duplicateRuntimeInterfaceConfiguration(
                nodeID: duplicateKey.nodeID,
                portID: duplicateKey.portID
            )
        }

        if let duplicateNodeID = duplicateRuntimeManualRouteTableNodeID() {
            throw TopologyProjectSnapshotValidationError.duplicateRuntimeManualRouteTable(nodeID: duplicateNodeID)
        }

        if schemaVersion >= 7, !documentationItemsWerePresent {
            throw TopologyProjectSnapshotValidationError.documentationItemsFieldMissing
        }
        var documentationIDs: Set<UUID> = []
        var documentationOrders: Set<Int> = []
        for item in documentationItems {
            guard documentationIDs.insert(item.id).inserted else {
                throw TopologyProjectSnapshotValidationError.duplicateDocumentationItem(itemID: item.id)
            }
            guard documentationOrders.insert(item.order).inserted else {
                throw TopologyProjectSnapshotValidationError.duplicateDocumentationOrder(order: item.order)
            }
            guard item.hasValidScalarValues else {
                throw TopologyProjectSnapshotValidationError.invalidDocumentationItem(itemID: item.id)
            }
        }

        if Set(runtimeRIPEnabledNodeIDs).count != runtimeRIPEnabledNodeIDs.count,
           let duplicate = runtimeRIPEnabledNodeIDs.first(where: { id in
               runtimeRIPEnabledNodeIDs.filter { $0 == id }.count > 1
           }) {
            throw TopologyProjectSnapshotValidationError.duplicateRuntimeRIPConfiguration(nodeID: duplicate)
        }
        if let duplicate = duplicateNodeID(in: runtimeDHCPClientConfigurations.map(\.nodeID)) {
            throw TopologyProjectSnapshotValidationError.duplicateRuntimeDHCPClientConfiguration(nodeID: duplicate)
        }
        if let duplicate = duplicateNodeID(in: runtimeDHCPServerConfigurations.map(\.nodeID)) {
            throw TopologyProjectSnapshotValidationError.duplicateRuntimeDHCPServerConfiguration(nodeID: duplicate)
        }
        if let duplicate = duplicateNodeID(in: runtimeFirewallConfigurations.map(\.nodeID)) {
            throw TopologyProjectSnapshotValidationError.duplicateRuntimeFirewallConfiguration(nodeID: duplicate)
        }
        if let duplicate = duplicateNodeID(in: runtimePortForwardingConfigurations.map(\.nodeID)) {
            throw TopologyProjectSnapshotValidationError.duplicateRuntimePortForwardingConfiguration(nodeID: duplicate)
        }
        if let duplicate = duplicateNodeID(in: switchConfigurations.map(\.nodeID)) {
            throw TopologyProjectSnapshotValidationError.duplicateSwitchConfiguration(nodeID: duplicate)
        }
        if let duplicate = duplicateNodeID(in: hostWirelessConfigurations.map(\.nodeID)) {
            throw TopologyProjectSnapshotValidationError.duplicateHostWirelessConfiguration(nodeID: duplicate)
        }
        if let duplicate = duplicateNodeID(in: runtimeWebServerConfigurations.map(\.nodeID)) {
            throw TopologyProjectSnapshotValidationError.duplicateRuntimeWebServerConfiguration(nodeID: duplicate)
        }
        let restoredGraph = graph.toTopologyGraph()
        if schemaVersion == 12, !runtimeWebAdministrationPoliciesWerePresent {
            throw TopologyProjectSnapshotValidationError.runtimeWebAdministrationPoliciesFieldMissing
        }
        if schemaVersion >= 13, !runtimeWebAdministrationConfigurationsWerePresent {
            throw TopologyProjectSnapshotValidationError.runtimeWebAdministrationConfigurationsFieldMissing
        }
        let resolvedWebAdministrationConfigurations = try migratedRuntimeWebAdministrationConfigurations(
            schemaVersion: schemaVersion,
            graph: restoredGraph
        )
        if let duplicate = duplicateNodeID(in: resolvedWebAdministrationConfigurations.map(\.nodeID)) {
            throw TopologyProjectSnapshotValidationError.duplicateRuntimeWebAdministrationConfiguration(nodeID: duplicate)
        }
        if let duplicate = duplicateNodeID(in: runtimeWebBrowserConfigurations.map(\.nodeID)) {
            throw TopologyProjectSnapshotValidationError.duplicateRuntimeWebBrowserConfiguration(nodeID: duplicate)
        }
        if let duplicate = duplicateNodeID(in: virtualFileSystems.map(\.nodeID)) {
            throw TopologyProjectSnapshotValidationError.duplicateVirtualFileSystem(nodeID: duplicate)
        }
        if schemaVersion >= 9, !protocolApplicationDefinitionsWerePresent {
            throw TopologyProjectSnapshotValidationError.protocolApplicationDefinitionsFieldMissing
        }
        if schemaVersion >= 9, !protocolApplicationInstallationsWerePresent {
            throw TopologyProjectSnapshotValidationError.protocolApplicationInstallationsFieldMissing
        }
        let resolvedProtocolApplicationDefinitions = schemaVersion >= 9 ? protocolApplicationDefinitions : []
        let resolvedProtocolApplicationInstallations = schemaVersion >= 9 ? protocolApplicationInstallations : []
        do {
            try TopologyProtocolApplicationCatalog.validateDefinitions(resolvedProtocolApplicationDefinitions)
            try TopologyProtocolApplicationCatalog.validateInstallations(
                resolvedProtocolApplicationInstallations,
                definitions: resolvedProtocolApplicationDefinitions,
                graph: restoredGraph
            )
        } catch let error as TopologyProtocolApplicationValidationError {
            throw TopologyProjectSnapshotValidationError.invalidProtocolApplicationProject(error: error)
        }
        let resolvedDNSConfigurations = try resolvedRuntimeDNSServerConfigurations(
            schemaVersion: schemaVersion,
            graph: restoredGraph
        )
        try validateRuntimeDNSServerConfigurations(
            resolvedDNSConfigurations,
            in: restoredGraph,
            schemaVersion: schemaVersion
        )
        let resolvedRemoteLinkConfigurations = try resolveRemoteLinkConfigurations(
            schemaVersion: schemaVersion,
            in: restoredGraph
        )
        if let duplicate = duplicateNodeID(in: resolvedRemoteLinkConfigurations.map(\.nodeID)) {
            throw TopologyProjectSnapshotValidationError.duplicateRemoteLinkConfiguration(nodeID: duplicate)
        }
        try validateRuntimeInterfaceConfigurations(in: restoredGraph)
        try validateRuntimeManualRouteTables(in: restoredGraph)
        try validateRuntimeWebConfigurations(
            in: restoredGraph,
            administrationConfigurations: resolvedWebAdministrationConfigurations
        )

        for nodeID in runtimeRIPEnabledNodeIDs {
            guard let node = restoredGraph.node(withID: nodeID) else {
                throw TopologyProjectSnapshotValidationError.runtimeRIPConfigurationReferencesUnknownNode(nodeID: nodeID)
            }
            guard node.kind == .router else {
                throw TopologyProjectSnapshotValidationError.runtimeRIPConfigurationReferencesUnsupportedNodeKind(
                    nodeID: nodeID,
                    kind: node.kind
                )
            }
        }
        for configuration in runtimeDHCPClientConfigurations {
            guard let node = restoredGraph.node(withID: configuration.nodeID) else {
                throw TopologyProjectSnapshotValidationError.runtimeDHCPClientConfigurationReferencesUnknownNode(
                    nodeID: configuration.nodeID
                )
            }
            guard node.kind.isPCClassEndpoint || node.kind == .gateway else {
                throw TopologyProjectSnapshotValidationError.runtimeDHCPClientConfigurationReferencesUnsupportedNodeKind(
                    nodeID: configuration.nodeID,
                    kind: node.kind
                )
            }
        }
        for configuration in runtimeDHCPServerConfigurations {
            guard let node = restoredGraph.node(withID: configuration.nodeID) else {
                throw TopologyProjectSnapshotValidationError.runtimeDHCPServerConfigurationReferencesUnknownNode(
                    nodeID: configuration.nodeID
                )
            }
            guard node.kind.isPCClassEndpoint || node.kind == .gateway else {
                throw TopologyProjectSnapshotValidationError.runtimeDHCPServerConfigurationReferencesUnsupportedNodeKind(
                    nodeID: configuration.nodeID,
                    kind: node.kind
                )
            }
        }
        for configuration in runtimeFirewallConfigurations {
            guard let node = restoredGraph.node(withID: configuration.nodeID) else {
                throw TopologyProjectSnapshotValidationError.runtimeFirewallConfigurationReferencesUnknownNode(
                    nodeID: configuration.nodeID
                )
            }
            guard node.kind == .router || node.kind == .gateway || node.kind.isPCClassEndpoint else {
                throw TopologyProjectSnapshotValidationError.runtimeFirewallConfigurationReferencesUnsupportedNodeKind(
                    nodeID: configuration.nodeID,
                    kind: node.kind
                )
            }
            if node.kind.isPCClassEndpoint,
               !runtimeInstalledPrograms.contains(where: {
                   $0.nodeID == configuration.nodeID && $0.program == .firewall
               }) {
                throw TopologyProjectSnapshotValidationError.runtimeFirewallConfigurationMissingInstalledProgram(
                    nodeID: configuration.nodeID
                )
            }
        }
        for configuration in runtimePortForwardingConfigurations {
            guard let node = restoredGraph.node(withID: configuration.nodeID) else {
                throw TopologyProjectSnapshotValidationError.runtimePortForwardingConfigurationReferencesUnknownNode(
                    nodeID: configuration.nodeID
                )
            }
            guard node.kind == .gateway else {
                throw TopologyProjectSnapshotValidationError.runtimePortForwardingConfigurationReferencesUnsupportedNodeKind(
                    nodeID: configuration.nodeID,
                    kind: node.kind
                )
            }
        }
        for configuration in switchConfigurations {
            guard let node = restoredGraph.node(withID: configuration.nodeID) else {
                throw TopologyProjectSnapshotValidationError.switchConfigurationReferencesUnknownNode(nodeID: configuration.nodeID)
            }
            guard node.kind == .networkSwitch else {
                throw TopologyProjectSnapshotValidationError.switchConfigurationReferencesUnsupportedNodeKind(
                    nodeID: configuration.nodeID, kind: node.kind
                )
            }
        }
        for configuration in resolvedRemoteLinkConfigurations {
            guard !configuration.pairIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TopologyProjectSnapshotValidationError.remoteLinkConfigurationHasBlankPairIdentifier(
                    nodeID: configuration.nodeID
                )
            }
            if configuration.transportMode == .localNetwork {
                switch configuration.lanRole {
                case .host:
                    guard configuration.lanPort > 0 else {
                        throw TopologyProjectSnapshotValidationError.remoteLinkConfigurationHasInvalidLANPort(
                            nodeID: configuration.nodeID
                        )
                    }
                case .join:
                    guard configuration.lanRemotePort > 0 else {
                        throw TopologyProjectSnapshotValidationError.remoteLinkConfigurationHasInvalidLANPort(
                            nodeID: configuration.nodeID
                        )
                    }
                    if configuration.lanJoinMethod == .manual,
                       configuration.lanRemoteHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        throw TopologyProjectSnapshotValidationError.remoteLinkConfigurationHasBlankLANRemoteHost(
                            nodeID: configuration.nodeID
                        )
                    }
                }
            }
            guard let node = restoredGraph.node(withID: configuration.nodeID) else {
                throw TopologyProjectSnapshotValidationError.remoteLinkConfigurationReferencesUnknownNode(
                    nodeID: configuration.nodeID
                )
            }
            guard node.kind == .remoteLink else {
                throw TopologyProjectSnapshotValidationError.remoteLinkConfigurationReferencesUnsupportedNodeKind(
                    nodeID: configuration.nodeID,
                    kind: node.kind
                )
            }
        }
        if schemaVersion >= 5 {
            let configuredNodeIDs = Set(resolvedRemoteLinkConfigurations.map(\.nodeID))
            if let missingNode = restoredGraph.nodes
                .filter({ $0.kind == .remoteLink && !configuredNodeIDs.contains($0.id) })
                .sorted(by: { $0.id.uuidString < $1.id.uuidString })
                .first
            {
                throw TopologyProjectSnapshotValidationError.missingRemoteLinkConfiguration(nodeID: missingNode.id)
            }
        }
        for configuration in hostWirelessConfigurations {
            guard let node = restoredGraph.node(withID: configuration.nodeID) else {
                throw TopologyProjectSnapshotValidationError.hostWirelessConfigurationReferencesUnknownNode(nodeID: configuration.nodeID)
            }
            guard node.kind.isPCClassEndpoint else {
                throw TopologyProjectSnapshotValidationError.hostWirelessConfigurationReferencesUnsupportedNodeKind(
                    nodeID: configuration.nodeID, kind: node.kind
                )
            }
        }
        if schemaVersion >= 6, !virtualFileSystemsWerePresent {
            throw TopologyProjectSnapshotValidationError.virtualFileSystemsFieldMissing
        }
        for snapshot in virtualFileSystems {
            guard let node = restoredGraph.node(withID: snapshot.nodeID) else {
                throw TopologyProjectSnapshotValidationError.virtualFileSystemReferencesUnknownNode(nodeID: snapshot.nodeID)
            }
            guard node.kind.isPCClassEndpoint else {
                throw TopologyProjectSnapshotValidationError.virtualFileSystemReferencesUnsupportedNodeKind(
                    nodeID: snapshot.nodeID,
                    kind: node.kind
                )
            }
            do {
                _ = try snapshot.fileSystem()
            } catch {
                throw TopologyProjectSnapshotValidationError.invalidVirtualFileSystem(
                    nodeID: snapshot.nodeID,
                    detail: error.localizedDescription
                )
            }
        }
        if schemaVersion >= 6 {
            let configuredNodeIDs = Set(virtualFileSystems.map(\.nodeID))
            if let missingNode = restoredGraph.nodes
                .filter({ $0.kind.isPCClassEndpoint && !configuredNodeIDs.contains($0.id) })
                .sorted(by: { $0.id.uuidString < $1.id.uuidString })
                .first
            {
                throw TopologyProjectSnapshotValidationError.missingVirtualFileSystem(nodeID: missingNode.id)
            }
        }
        do {
            let decodedFileSystems = Dictionary(
                uniqueKeysWithValues: try virtualFileSystems.map { ($0.nodeID, try $0.fileSystem()) }
            )
            try TopologyVirtualFileSystem.validateProjectQuotas(decodedFileSystems)
        } catch let error as TopologyProjectSnapshotValidationError {
            throw error
        } catch {
            throw TopologyProjectSnapshotValidationError.invalidVirtualFileSystemProject(
                detail: error.localizedDescription
            )
        }
        var state = TopologyEditorState()
        state.graph = restoredGraph
        state.viewport = viewport.toViewportTransform()
        state.runtimeDeviceConfigurations = Dictionary(
            uniqueKeysWithValues: runtimeDeviceConfigurations.map { snapshot in
                (
                    snapshot.nodeID,
                    TopologyRuntimeDeviceConfiguration(
                        ipAddress: snapshot.ipAddress,
                        subnetMask: snapshot.subnetMask,
                        defaultGateway: snapshot.defaultGateway,
                        dnsServer: snapshot.dnsServer
                    )
                )
            }
        )
        state.runtimeInterfaceConfigurations = Dictionary(
            uniqueKeysWithValues: runtimeInterfaceConfigurations.map { snapshot in
                (
                    TopologyRuntimeInterfaceKey(nodeID: snapshot.nodeID, portID: snapshot.portID),
                    TopologyRuntimeInterfaceConfiguration(
                        ipAddress: snapshot.ipAddress,
                        subnetMask: snapshot.subnetMask
                    )
                )
            }
        )
        if shouldDeriveLegacyRuntimeInterfaceDefaults {
            state.seedJavaRuntimeInterfaceDefaultsForGraph()
        }
        state.runtimeRIPEnabledByNodeID = Dictionary(uniqueKeysWithValues: runtimeRIPEnabledNodeIDs.map { ($0, true) })
        state.runtimeDHCPClientConfigurationsByNodeID = Dictionary(
            uniqueKeysWithValues: runtimeDHCPClientConfigurations.map {
                ($0.nodeID, TopologyDHCPClientConfiguration(isEnabled: $0.isEnabled))
            }
        )
        state.runtimeDHCPServerConfigurationsByNodeID = Dictionary(
            uniqueKeysWithValues: runtimeDHCPServerConfigurations.map { ($0.nodeID, $0.configuration) }
        )
        state.runtimeFirewallConfigurationsByNodeID = Dictionary(
            uniqueKeysWithValues: runtimeFirewallConfigurations.map { ($0.nodeID, $0.configuration) }
        )
        state.runtimePortForwardingRowsByNodeID = Dictionary(
            uniqueKeysWithValues: runtimePortForwardingConfigurations.map { ($0.nodeID, $0.rows) }
        )
        state.switchConfigurationsByNodeID = Dictionary(
            uniqueKeysWithValues: switchConfigurations.map { ($0.nodeID, $0.configuration) }
        )
        state.remoteLinkConfigurationsByNodeID = Dictionary(
            uniqueKeysWithValues: resolvedRemoteLinkConfigurations.map { ($0.nodeID, $0.configuration) }
        )
        state.hostWirelessConfigurationsByNodeID = Dictionary(
            uniqueKeysWithValues: hostWirelessConfigurations.map { ($0.nodeID, $0.configuration) }
        )
        state.seedJavaRuntimeInterfaceDefaultsForGraph()
        state.runtimeManualRoutesByNodeID = Dictionary(
            uniqueKeysWithValues: runtimeManualRouteTables.map { table in
                (
                    table.nodeID,
                    table.routes.map { route in
                        TopologyRuntimeManualRoute(
                            destinationNetwork: route.destinationNetwork,
                            subnetMask: route.subnetMask,
                            gateway: route.gateway,
                            interfaceIPAddress: route.interfaceIPAddress
                        )
                    }
                )
            }
        )
        state.runtimeDNSServerConfigurationsByNodeID = resolvedDNSConfigurations.reduce(into: [:]) { partialResult, snapshot in
            let typedRecords = snapshot.records.compactMap(\.typedRecord)
            partialResult[snapshot.nodeID] = TopologyRuntimeDNSServerConfiguration(
                typedRecords: typedRecords,
                recursiveResolutionEnabled: snapshot.recursiveResolutionEnabled ?? false,
                forwardingServerIPAddress: snapshot.forwardingServerIPAddress
            )
        }
        state.runtimeWebServerConfigurationsByNodeID = Dictionary(
            uniqueKeysWithValues: runtimeWebServerConfigurations.compactMap { snapshot in
                if schemaVersion <= 12,
                   runtimeWebAdministrationPoliciesWerePresent,
                   let node = restoredGraph.node(withID: snapshot.nodeID),
                   node.kind == .router || node.kind == .gateway {
                    return nil
                }
                return (snapshot.nodeID, snapshot.configuration)
            }
        )
        state.runtimeWebAdministrationConfigurationsByNodeID = Dictionary(
            uniqueKeysWithValues: resolvedWebAdministrationConfigurations.map { ($0.nodeID, $0.configuration) }
        )
        state.runtimeWebBrowserConfigurationsByNodeID = Dictionary(
            uniqueKeysWithValues: runtimeWebBrowserConfigurations.map { ($0.nodeID, $0.configuration) }
        )
        state.runtimeInstalledProgramsByNodeID = runtimeInstalledPrograms.reduce(into: [:]) { partialResult, snapshot in
            var programs = partialResult[snapshot.nodeID] ?? Set<TopologyRuntimeInstallableProgram>()
            programs.insert(snapshot.program)
            partialResult[snapshot.nodeID] = programs
        }
        if schemaVersion < 8 {
            for configuration in resolvedDNSConfigurations {
                state.runtimeInstalledProgramsByNodeID[configuration.nodeID, default: []].insert(.dnsServer)
            }
        }
        state.virtualFileSystemsByNodeID = Dictionary(
            uniqueKeysWithValues: try virtualFileSystems.map { ($0.nodeID, try $0.fileSystem()) }
        )
        if schemaVersion < 6 {
            for node in restoredGraph.nodes where node.kind.isPCClassEndpoint && state.virtualFileSystemsByNodeID[node.id] == nil {
                state.virtualFileSystemsByNodeID[node.id] = .defaultForDevice()
            }
        }
        for nodeID in state.runtimeDNSServerConfigurationsByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            if schemaVersion < 8, !runtimeDNSRecords.isEmpty {
                try state.mirrorRuntimeDNSConfigurationToHostsFile(nodeID: nodeID)
            } else if state.virtualFileSystemsByNodeID[nodeID]?.contains(TopologyRuntimeDNSHostsFile.path) == true {
                state.synchronizeRuntimeDNSConfigurationFromHostsFile(nodeID: nodeID)
            } else {
                try state.mirrorRuntimeDNSConfigurationToHostsFile(nodeID: nodeID)
            }
        }
        for nodeID in state.runtimeInstalledProgramsByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString })
            where state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(.emailClient) == true
                || state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(.emailServer) == true {
            try state.synchronizeRuntimeEmailConfigurationFromFileSystem(nodeID: nodeID)
        }
        for nodeID in state.runtimeInstalledProgramsByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString })
            where state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(.gnutella) == true {
            try state.synchronizeRuntimeGnutellaConfigurationFromFileSystem(nodeID: nodeID)
        }
        state.protocolApplicationDefinitionsByID = Dictionary(
            uniqueKeysWithValues: resolvedProtocolApplicationDefinitions.map { ($0.id, $0) }
        )
        state.runtimeInstalledProtocolApplicationIDsByNodeID = resolvedProtocolApplicationInstallations.reduce(into: [:]) {
            $0[$1.nodeID, default: []].insert($1.definitionID)
        }
        state.documentationItems = documentationItems
            .map { $0.toDocumentationItem() }
            .inDeterministicRenderOrder
        state.persistenceRevision = persistenceRevision
        state.lastPersistedRevision = persistenceRevision

        return state
    }

    private func resolveRemoteLinkConfigurations(
        schemaVersion: Int,
        in graph: TopologyGraph
    ) throws -> [TopologyRemoteLinkConfigurationSnapshot] {
        if schemaVersion >= 5, !remoteLinkConfigurationsWerePresent {
            throw TopologyProjectSnapshotValidationError.remoteLinkConfigurationsFieldMissing
        }

        var resolvedConfigurations = remoteLinkConfigurations
        let configuredNodeIDs = Set(resolvedConfigurations.map(\.nodeID))
        let missingRemoteLinkNodes = graph.nodes
            .filter { $0.kind == .remoteLink && !configuredNodeIDs.contains($0.id) }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        if schemaVersion < 5 {
            resolvedConfigurations.append(contentsOf: missingRemoteLinkNodes.map { node in
                TopologyRemoteLinkConfigurationSnapshot(
                    nodeID: node.id,
                    configuration: .defaultConfiguration(nodeID: node.id)
                )
            })
        }

        return resolvedConfigurations
    }

    private func duplicateNodeID(in nodeIDs: [UUID]) -> UUID? {
        var seen: Set<UUID> = []
        for nodeID in nodeIDs where !seen.insert(nodeID).inserted { return nodeID }
        return nil
    }

    private func duplicateRuntimeConfigurationNodeID() -> UUID? {
        var seenNodeIDs: Set<UUID> = []

        for entry in runtimeDeviceConfigurations {
            if !seenNodeIDs.insert(entry.nodeID).inserted {
                return entry.nodeID
            }
        }

        return nil
    }

    private func duplicateRuntimeInterfaceConfigurationKey() -> TopologyRuntimeInterfaceKey? {
        var seenKeys: Set<TopologyRuntimeInterfaceKey> = []

        for entry in runtimeInterfaceConfigurations {
            let key = TopologyRuntimeInterfaceKey(nodeID: entry.nodeID, portID: entry.portID)
            if !seenKeys.insert(key).inserted {
                return key
            }
        }

        return nil
    }

    private func validateRuntimeInterfaceConfigurations(in graph: TopologyGraph) throws {
        for entry in runtimeInterfaceConfigurations {
            guard let node = graph.node(withID: entry.nodeID) else {
                throw TopologyProjectSnapshotValidationError.runtimeInterfaceConfigurationReferencesUnknownNode(
                    nodeID: entry.nodeID,
                    portID: entry.portID
                )
            }

            guard node.kind == .router || node.kind == .gateway else {
                throw TopologyProjectSnapshotValidationError.runtimeInterfaceConfigurationReferencesUnsupportedNodeKind(
                    nodeID: entry.nodeID,
                    kind: node.kind
                )
            }

            guard node.ports.contains(where: { $0.id == entry.portID }) else {
                throw TopologyProjectSnapshotValidationError.runtimeInterfaceConfigurationReferencesUnknownPort(
                    nodeID: entry.nodeID,
                    portID: entry.portID
                )
            }
        }
    }

    private func duplicateRuntimeManualRouteTableNodeID() -> UUID? {
        var seenNodeIDs: Set<UUID> = []

        for table in runtimeManualRouteTables {
            if !seenNodeIDs.insert(table.nodeID).inserted {
                return table.nodeID
            }
        }

        return nil
    }

    private func validateRuntimeManualRouteTables(in graph: TopologyGraph) throws {
        for table in runtimeManualRouteTables {
            guard let node = graph.node(withID: table.nodeID) else {
                throw TopologyProjectSnapshotValidationError.runtimeManualRouteTableReferencesUnknownNode(
                    nodeID: table.nodeID
                )
            }

            guard node.kind.isPCClassEndpoint || node.kind == .router || node.kind == .gateway else {
                throw TopologyProjectSnapshotValidationError.runtimeManualRouteTableReferencesUnsupportedNodeKind(
                    nodeID: table.nodeID,
                    kind: node.kind
                )
            }
        }
    }

    private func migratedRuntimeWebAdministrationConfigurations(
        schemaVersion: Int,
        graph: TopologyGraph
    ) throws -> [TopologyRuntimeWebAdministrationConfigurationSnapshot] {
        if runtimeWebAdministrationConfigurationsWerePresent {
            return runtimeWebAdministrationConfigurations
        }
        guard schemaVersion <= 12, runtimeWebAdministrationPoliciesWerePresent else { return [] }

        var legacyWebServerConfigurationsByNodeID: [UUID: TopologyRuntimeWebServerConfigurationSnapshot] = [:]
        for snapshot in runtimeWebServerConfigurations {
            guard legacyWebServerConfigurationsByNodeID[snapshot.nodeID] == nil else {
                throw TopologyProjectSnapshotValidationError.duplicateRuntimeWebServerConfiguration(
                    nodeID: snapshot.nodeID
                )
            }
            legacyWebServerConfigurationsByNodeID[snapshot.nodeID] = snapshot
        }
        let policyNodeIDs = Set(legacyRuntimeWebAdministrationPolicies.map(\.nodeID))
        var migrated = legacyRuntimeWebAdministrationPolicies.map { snapshot in
            let node = graph.node(withID: snapshot.nodeID)
            let migratedPort: Int
            if node?.kind == .router || node?.kind == .gateway {
                migratedPort = legacyWebServerConfigurationsByNodeID[snapshot.nodeID]?.port
                    ?? TopologyRuntimeWebAdministrationConfiguration.defaultPort
            } else {
                migratedPort = TopologyRuntimeWebAdministrationConfiguration.defaultPort
            }
            return TopologyRuntimeWebAdministrationConfigurationSnapshot(
                nodeID: snapshot.nodeID,
                configuration: TopologyRuntimeWebAdministrationConfiguration(
                    port: migratedPort,
                    accessPolicy: snapshot.policy
                )
            )
        }
        migrated.append(contentsOf: runtimeWebServerConfigurations.compactMap { snapshot in
            guard !policyNodeIDs.contains(snapshot.nodeID),
                  let node = graph.node(withID: snapshot.nodeID),
                  node.kind == .router || node.kind == .gateway
            else { return nil }
            return TopologyRuntimeWebAdministrationConfigurationSnapshot(
                nodeID: snapshot.nodeID,
                configuration: TopologyRuntimeWebAdministrationConfiguration(port: snapshot.port)
            )
        })
        return migrated.sorted { $0.nodeID.uuidString < $1.nodeID.uuidString }
    }

    private func validateRuntimeWebConfigurations(
        in graph: TopologyGraph,
        administrationConfigurations: [TopologyRuntimeWebAdministrationConfigurationSnapshot]
    ) throws {
        for snapshot in runtimeWebServerConfigurations {
            guard let node = graph.node(withID: snapshot.nodeID) else {
                throw TopologyProjectSnapshotValidationError.runtimeWebServerConfigurationReferencesUnknownNode(nodeID: snapshot.nodeID)
            }
            guard node.kind.isPCClassEndpoint || node.kind == .router || node.kind == .gateway else {
                throw TopologyProjectSnapshotValidationError.runtimeWebServerConfigurationReferencesUnsupportedNodeKind(
                    nodeID: snapshot.nodeID,
                    kind: node.kind
                )
            }
            let documentRoot = snapshot.documentRoot
            guard (1...65_535).contains(snapshot.port),
                  documentRoot == documentRoot.trimmingCharacters(in: .whitespacesAndNewlines),
                  !documentRoot.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  (try? TopologyVirtualFileSystem.normalizedAbsolutePath(documentRoot)) == documentRoot
            else {
                throw TopologyProjectSnapshotValidationError.invalidRuntimeWebServerConfiguration(nodeID: snapshot.nodeID)
            }
        }

        for snapshot in administrationConfigurations {
            guard let node = graph.node(withID: snapshot.nodeID) else {
                throw TopologyProjectSnapshotValidationError.runtimeWebAdministrationConfigurationReferencesUnknownNode(
                    nodeID: snapshot.nodeID
                )
            }
            guard node.kind == .router || node.kind == .gateway else {
                throw TopologyProjectSnapshotValidationError.runtimeWebAdministrationConfigurationReferencesUnsupportedNodeKind(
                    nodeID: snapshot.nodeID,
                    kind: node.kind
                )
            }
            guard (1...65_535).contains(snapshot.configuration.port) else {
                throw TopologyProjectSnapshotValidationError.invalidRuntimeWebAdministrationConfiguration(
                    nodeID: snapshot.nodeID
                )
            }
        }

        for snapshot in runtimeWebBrowserConfigurations {
            guard let node = graph.node(withID: snapshot.nodeID) else {
                throw TopologyProjectSnapshotValidationError.runtimeWebBrowserConfigurationReferencesUnknownNode(nodeID: snapshot.nodeID)
            }
            guard node.kind.isPCClassEndpoint else {
                throw TopologyProjectSnapshotValidationError.runtimeWebBrowserConfigurationReferencesUnsupportedNodeKind(
                    nodeID: snapshot.nodeID,
                    kind: node.kind
                )
            }
            guard (1...65_535).contains(snapshot.lastPort),
                  snapshot.lastPath.isEmpty || snapshot.lastPath.hasPrefix("/"),
                  !snapshot.lastHost.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  !snapshot.lastPath.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            else {
                throw TopologyProjectSnapshotValidationError.invalidRuntimeWebBrowserConfiguration(nodeID: snapshot.nodeID)
            }
        }
    }

    private func validateRuntimeDNSServerConfigurations(
        _ configurations: [TopologyRuntimeDNSServerConfigurationSnapshot],
        in graph: TopologyGraph,
        schemaVersion: Int
    ) throws {
        var nodeIDs: Set<UUID> = []
        for configuration in configurations {
            guard nodeIDs.insert(configuration.nodeID).inserted else {
                throw TopologyProjectSnapshotValidationError.duplicateRuntimeDNSServerConfiguration(nodeID: configuration.nodeID)
            }
            guard let node = graph.node(withID: configuration.nodeID) else {
                throw TopologyProjectSnapshotValidationError.runtimeDNSServerConfigurationReferencesUnknownNode(nodeID: configuration.nodeID)
            }
            guard node.kind.isPCClassEndpoint else {
                throw TopologyProjectSnapshotValidationError.runtimeDNSServerConfigurationReferencesUnsupportedNodeKind(nodeID: configuration.nodeID, kind: node.kind)
            }
            if schemaVersion >= 8, !runtimeInstalledPrograms.contains(where: { $0.nodeID == configuration.nodeID && $0.program == .dnsServer }) {
                throw TopologyProjectSnapshotValidationError.runtimeDNSServerConfigurationMissingInstalledProgram(nodeID: configuration.nodeID)
            }
            var semanticRecords: Set<TopologyDNSResourceRecord> = []
            for record in configuration.records {
                guard let typedRecord = record.typedRecord else {
                    throw TopologyProjectSnapshotValidationError.invalidRuntimeDNSRecord(hostname: record.hostname)
                }
                guard semanticRecords.insert(typedRecord).inserted else {
                    throw TopologyProjectSnapshotValidationError.duplicateRuntimeDNSRecord(hostname: typedRecord.name.rawValue)
                }
            }
            if let forwarder = configuration.forwardingServerIPAddress,
               !forwarder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               TopologyDNSIPv4Address(rawValue: forwarder) == nil {
                throw TopologyProjectSnapshotValidationError.invalidRuntimeDNSRecord(hostname: forwarder)
            }
        }
    }

    private func resolvedRuntimeDNSServerConfigurations(schemaVersion: Int, graph: TopologyGraph) throws -> [TopologyRuntimeDNSServerConfigurationSnapshot] {
        if schemaVersion >= 8, !runtimeDNSConfigurationsWerePresent {
            throw TopologyProjectSnapshotValidationError.runtimeDNSConfigurationsFieldMissing
        }
        if schemaVersion >= 8, !runtimeDNSRecords.isEmpty {
            throw TopologyProjectSnapshotValidationError.runtimeDNSLegacyFieldUnexpected
        }

        var resolved = runtimeDNSServerConfigurations
        if schemaVersion < 8, !runtimeDNSRecords.isEmpty {
            let installedOwners = runtimeInstalledPrograms
                .filter { $0.program == .dnsServer }
                .map(\.nodeID)
            let existingOwners = resolved.map(\.nodeID)
            let fallbackOwners = graph.nodes
                .filter { $0.kind.isPCClassEndpoint }
                .map(\.id)
            let owner = installedOwners.sorted { $0.uuidString < $1.uuidString }.first
                ?? existingOwners.sorted { $0.uuidString < $1.uuidString }.first
                ?? fallbackOwners.sorted { $0.uuidString < $1.uuidString }.first
            guard let owner else {
                throw TopologyProjectSnapshotValidationError.runtimeDNSMigrationMissingOwner
            }

            let existingRecords: [TopologyRuntimeDNSRecordSnapshot]
            let existingIndex = resolved.firstIndex(where: { $0.nodeID == owner })
            if let existingIndex {
                existingRecords = resolved[existingIndex].records
            } else {
                existingRecords = []
            }

            let existingHostnames = Set(
                existingRecords.map { $0.hostname.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            )
            var mergedHostnames = existingHostnames
            var mergedRecords = existingRecords
            for record in runtimeDNSRecords {
                let hostname = record.hostname.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !hostname.isEmpty else {
                    throw TopologyProjectSnapshotValidationError.invalidRuntimeDNSRecord(hostname: record.hostname)
                }
                guard mergedHostnames.insert(hostname).inserted else {
                    throw TopologyProjectSnapshotValidationError.duplicateRuntimeDNSRecord(hostname: hostname)
                }
                mergedRecords.append(TopologyRuntimeDNSRecordSnapshot(hostname: hostname, targetIPAddress: record.targetIPAddress))
            }

            let migrated = TopologyRuntimeDNSServerConfigurationSnapshot(nodeID: owner, records: mergedRecords)
            if let existingIndex {
                resolved[existingIndex] = migrated
            } else {
                resolved.append(migrated)
            }
        }
        return resolved.sorted { $0.nodeID.uuidString < $1.nodeID.uuidString }
    }
}

struct TopologyGraphSnapshot: Codable, Equatable {
    let nodes: [TopologyNodeSnapshot]
    let links: [TopologyLinkSnapshot]

    init(nodes: [TopologyNodeSnapshot], links: [TopologyLinkSnapshot]) {
        self.nodes = nodes
        self.links = links
    }

    init(graph: TopologyGraph) {
        nodes = graph.nodes.map(TopologyNodeSnapshot.init)
        links = graph.links.map(TopologyLinkSnapshot.init)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case nodes
        case links
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyGraphSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodes = try container.decode([TopologyNodeSnapshot].self, forKey: .nodes)
        links = try container.decode([TopologyLinkSnapshot].self, forKey: .links)
    }

    func toTopologyGraph() -> TopologyGraph {
        TopologyGraph(
            nodes: nodes.map(\.toTopologyNode),
            links: links.map(\.toTopologyLink)
        )
    }
}

struct TopologyNodeSnapshot: Codable, Equatable {
    let id: UUID
    let kind: TopologyNodeKind
    let displayName: String?
    let hostLabelPolicy: TopologyHostLabelPolicy
    let position: TopologyPointSnapshot
    let ports: [TopologyPortSnapshot]

    init(
        id: UUID,
        kind: TopologyNodeKind,
        displayName: String? = nil,
        hostLabelPolicy: TopologyHostLabelPolicy = .manual,
        position: TopologyPointSnapshot,
        ports: [TopologyPortSnapshot]
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.hostLabelPolicy = hostLabelPolicy
        self.position = position
        self.ports = ports
    }

    init(_ node: TopologyNode) {
        id = node.id
        kind = node.kind
        displayName = node.displayName
        hostLabelPolicy = node.hostLabelPolicy
        position = TopologyPointSnapshot(node.position)
        ports = node.ports.map(TopologyPortSnapshot.init)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case kind
        case displayName
        case hostLabelPolicy
        case position
        case ports
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyNodeSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(TopologyNodeKind.self, forKey: .kind)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        hostLabelPolicy = try container.decodeIfPresent(TopologyHostLabelPolicy.self, forKey: .hostLabelPolicy) ?? .manual
        position = try container.decode(TopologyPointSnapshot.self, forKey: .position)
        ports = try container.decode([TopologyPortSnapshot].self, forKey: .ports)
    }

    var toTopologyNode: TopologyNode {
        TopologyNode(
            id: id,
            kind: kind,
            displayName: displayName,
            hostLabelPolicy: hostLabelPolicy,
            position: position.toCGPoint,
            ports: ports.map(\.toPortMetadata)
        )
    }
}

struct TopologyPortSnapshot: Codable, Equatable {
    let id: UUID
    let label: String
    let isOccupied: Bool
    let importedMACAddress: String?

    init(id: UUID, label: String, isOccupied: Bool, importedMACAddress: String? = nil) {
        self.id = id
        self.label = label
        self.isOccupied = isOccupied
        self.importedMACAddress = TopologyPortMetadata.canonicalMACAddress(importedMACAddress)
    }

    init(_ port: TopologyPortMetadata) {
        id = port.id
        label = port.label
        isOccupied = port.isOccupied
        importedMACAddress = port.importedMACAddress
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case label
        case isOccupied
        case importedMACAddress
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyPortSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        isOccupied = try container.decode(Bool.self, forKey: .isOccupied)
        // Imported MAC metadata was optional before host-label parity shipped. Keep older native
        // projects loadable if that optional value is malformed; valid values are canonicalized and
        // invalid legacy metadata falls back to the deterministic generated MAC.
        importedMACAddress = TopologyPortMetadata.canonicalMACAddress(
            try container.decodeIfPresent(String.self, forKey: .importedMACAddress)
        )
    }

    var toPortMetadata: TopologyPortMetadata {
        TopologyPortMetadata(
            id: id,
            label: label,
            isOccupied: isOccupied,
            importedMACAddress: importedMACAddress
        )
    }
}

struct TopologyLinkSnapshot: Codable, Equatable {
    let id: UUID
    let sourceNodeID: UUID
    let sourcePortID: UUID
    let targetNodeID: UUID
    let targetPortID: UUID

    init(
        id: UUID,
        sourceNodeID: UUID,
        sourcePortID: UUID,
        targetNodeID: UUID,
        targetPortID: UUID
    ) {
        self.id = id
        self.sourceNodeID = sourceNodeID
        self.sourcePortID = sourcePortID
        self.targetNodeID = targetNodeID
        self.targetPortID = targetPortID
    }

    init(_ link: TopologyLink) {
        id = link.id
        sourceNodeID = link.sourceNodeID
        sourcePortID = link.sourcePortID
        targetNodeID = link.targetNodeID
        targetPortID = link.targetPortID
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case sourceNodeID
        case sourcePortID
        case targetNodeID
        case targetPortID
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyLinkSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceNodeID = try container.decode(UUID.self, forKey: .sourceNodeID)
        sourcePortID = try container.decode(UUID.self, forKey: .sourcePortID)
        targetNodeID = try container.decode(UUID.self, forKey: .targetNodeID)
        targetPortID = try container.decode(UUID.self, forKey: .targetPortID)
    }

    var toTopologyLink: TopologyLink {
        TopologyLink(
            id: id,
            sourceNodeID: sourceNodeID,
            sourcePortID: sourcePortID,
            targetNodeID: targetNodeID,
            targetPortID: targetPortID
        )
    }
}

struct TopologyDHCPClientConfigurationSnapshot: Codable, Equatable {
    let nodeID: UUID
    let isEnabled: Bool

    enum CodingKeys: String, CodingKey, CaseIterable {
        case nodeID
        case isEnabled
    }

    init(nodeID: UUID, isEnabled: Bool) {
        self.nodeID = nodeID
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyDHCPClientConfigurationSnapshot"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
    }
}

struct TopologyDHCPStaticAssignmentSnapshot: Codable, Equatable {
    let id: UUID
    let macAddress: String
    let ipAddress: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case macAddress
        case ipAddress
    }

    init(id: UUID, macAddress: String, ipAddress: String) {
        self.id = id
        self.macAddress = macAddress
        self.ipAddress = ipAddress
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyDHCPStaticAssignmentSnapshot"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        macAddress = try container.decode(String.self, forKey: .macAddress)
        ipAddress = try container.decode(String.self, forKey: .ipAddress)
    }
}

struct TopologyDHCPServerConfigurationSnapshot: Codable, Equatable {
    let nodeID: UUID
    let isActive: Bool
    let lowerBoundIPAddress: String
    let upperBoundIPAddress: String
    let gatewayIPAddress: String
    let dnsServerIPAddress: String
    let useOwnSettings: Bool
    let staticAssignments: [TopologyDHCPStaticAssignmentSnapshot]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case nodeID
        case isActive
        case lowerBoundIPAddress
        case upperBoundIPAddress
        case gatewayIPAddress
        case dnsServerIPAddress
        case useOwnSettings
        case staticAssignments
    }

    init(
        nodeID: UUID,
        isActive: Bool,
        lowerBoundIPAddress: String,
        upperBoundIPAddress: String,
        gatewayIPAddress: String,
        dnsServerIPAddress: String,
        useOwnSettings: Bool,
        staticAssignments: [TopologyDHCPStaticAssignmentSnapshot]
    ) {
        self.nodeID = nodeID
        self.isActive = isActive
        self.lowerBoundIPAddress = lowerBoundIPAddress
        self.upperBoundIPAddress = upperBoundIPAddress
        self.gatewayIPAddress = gatewayIPAddress
        self.dnsServerIPAddress = dnsServerIPAddress
        self.useOwnSettings = useOwnSettings
        self.staticAssignments = staticAssignments
    }

    init(nodeID: UUID, configuration: TopologyDHCPServerConfiguration) {
        self.init(
            nodeID: nodeID,
            isActive: configuration.isActive,
            lowerBoundIPAddress: configuration.lowerBoundIPAddress,
            upperBoundIPAddress: configuration.upperBoundIPAddress,
            gatewayIPAddress: configuration.gatewayIPAddress,
            dnsServerIPAddress: configuration.dnsServerIPAddress,
            useOwnSettings: configuration.useOwnSettings,
            staticAssignments: configuration.staticAssignments.map {
                TopologyDHCPStaticAssignmentSnapshot(id: $0.id, macAddress: $0.macAddress, ipAddress: $0.ipAddress)
            }
        )
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyDHCPServerConfigurationSnapshot"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        lowerBoundIPAddress = try container.decodeIfPresent(String.self, forKey: .lowerBoundIPAddress) ?? "0.0.0.0"
        upperBoundIPAddress = try container.decodeIfPresent(String.self, forKey: .upperBoundIPAddress) ?? "0.0.0.0"
        gatewayIPAddress = try container.decodeIfPresent(String.self, forKey: .gatewayIPAddress) ?? "0.0.0.0"
        dnsServerIPAddress = try container.decodeIfPresent(String.self, forKey: .dnsServerIPAddress) ?? "0.0.0.0"
        useOwnSettings = try container.decodeIfPresent(Bool.self, forKey: .useOwnSettings) ?? false
        staticAssignments = try container.decodeIfPresent(
            [TopologyDHCPStaticAssignmentSnapshot].self,
            forKey: .staticAssignments
        ) ?? []
    }

    var configuration: TopologyDHCPServerConfiguration {
        TopologyDHCPServerConfiguration(
            isActive: isActive,
            lowerBoundIPAddress: lowerBoundIPAddress,
            upperBoundIPAddress: upperBoundIPAddress,
            gatewayIPAddress: gatewayIPAddress,
            dnsServerIPAddress: dnsServerIPAddress,
            useOwnSettings: useOwnSettings,
            staticAssignments: staticAssignments.map {
                TopologyDHCPStaticAssignment(id: $0.id, macAddress: $0.macAddress, ipAddress: $0.ipAddress)
            }
        )
    }
}

struct TopologyFirewallRuleSnapshot: Codable, Equatable {
    let sourceIPAddress: String
    let sourceSubnetMask: String
    let destinationIPAddress: String
    let destinationSubnetMask: String
    let port: Int
    let protocolNumber: Int
    let actionNumber: Int

    enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceIPAddress
        case sourceSubnetMask
        case destinationIPAddress
        case destinationSubnetMask
        case port
        case protocolNumber
        case actionNumber
    }

    init(_ rule: TopologyFirewallRule) {
        sourceIPAddress = rule.sourceIPAddress
        sourceSubnetMask = rule.sourceSubnetMask
        destinationIPAddress = rule.destinationIPAddress
        destinationSubnetMask = rule.destinationSubnetMask
        port = rule.port
        protocolNumber = rule.protocolType.rawValue
        actionNumber = rule.action.rawValue
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyFirewallRuleSnapshot"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceIPAddress = try container.decodeIfPresent(String.self, forKey: .sourceIPAddress) ?? ""
        sourceSubnetMask = try container.decodeIfPresent(String.self, forKey: .sourceSubnetMask) ?? ""
        destinationIPAddress = try container.decodeIfPresent(String.self, forKey: .destinationIPAddress) ?? ""
        destinationSubnetMask = try container.decodeIfPresent(String.self, forKey: .destinationSubnetMask) ?? ""
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? TopologyFirewallRule.allPorts
        protocolNumber = try container.decodeIfPresent(Int.self, forKey: .protocolNumber)
            ?? TopologyFirewallProtocol.tcp.rawValue
        actionNumber = try container.decodeIfPresent(Int.self, forKey: .actionNumber)
            ?? TopologyFirewallAction.drop.rawValue
    }

    var rule: TopologyFirewallRule {
        TopologyFirewallRule(
            sourceIPAddress: sourceIPAddress,
            sourceSubnetMask: sourceSubnetMask,
            destinationIPAddress: destinationIPAddress,
            destinationSubnetMask: destinationSubnetMask,
            port: port,
            protocolType: TopologyFirewallProtocol(rawValue: protocolNumber) ?? .tcp,
            action: TopologyFirewallAction(rawValue: actionNumber) ?? .drop
        )
    }
}

struct TopologyFirewallConfigurationSnapshot: Codable, Equatable {
    let nodeID: UUID
    let isActive: Bool
    let defaultPolicyNumber: Int
    let dropICMP: Bool
    let filterSYNSegmentsOnly: Bool
    let filterUDP: Bool
    let rules: [TopologyFirewallRuleSnapshot]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case nodeID
        case isActive
        case defaultPolicyNumber
        case dropICMP
        case filterSYNSegmentsOnly
        case filterUDP
        case rules
    }

    init(nodeID: UUID, configuration: TopologyFirewallConfiguration) {
        self.nodeID = nodeID
        isActive = configuration.isActive
        defaultPolicyNumber = configuration.defaultPolicy.rawValue
        dropICMP = configuration.dropICMP
        filterSYNSegmentsOnly = configuration.filterSYNSegmentsOnly
        filterUDP = configuration.filterUDP
        rules = configuration.rules.map(TopologyFirewallRuleSnapshot.init)
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyFirewallConfigurationSnapshot"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        defaultPolicyNumber = try container.decodeIfPresent(Int.self, forKey: .defaultPolicyNumber)
            ?? TopologyFirewallAction.drop.rawValue
        dropICMP = try container.decodeIfPresent(Bool.self, forKey: .dropICMP) ?? false
        filterSYNSegmentsOnly = try container.decodeIfPresent(Bool.self, forKey: .filterSYNSegmentsOnly) ?? true
        filterUDP = try container.decodeIfPresent(Bool.self, forKey: .filterUDP) ?? true
        rules = try container.decodeIfPresent([TopologyFirewallRuleSnapshot].self, forKey: .rules) ?? []
    }

    var configuration: TopologyFirewallConfiguration {
        TopologyFirewallConfiguration(
            isActive: isActive,
            defaultPolicy: TopologyFirewallAction(rawValue: defaultPolicyNumber) ?? .drop,
            dropICMP: dropICMP,
            filterSYNSegmentsOnly: filterSYNSegmentsOnly,
            filterUDP: filterUDP,
            rules: rules.map(\.rule)
        )
    }
}

struct TopologySwitchConfigurationSnapshot: Codable, Equatable {
    let nodeID: UUID
    let ssid: String
    let retentionTimeMilliseconds: UInt64

    enum CodingKeys: String, CodingKey, CaseIterable {
        case nodeID
        case ssid
        case retentionTimeMilliseconds
    }

    init(nodeID: UUID, configuration: TopologySwitchConfiguration) {
        self.nodeID = nodeID
        ssid = configuration.ssid
        retentionTimeMilliseconds = configuration.retentionTimeMilliseconds
    }

    var configuration: TopologySwitchConfiguration {
        TopologySwitchConfiguration(ssid: ssid, retentionTimeMilliseconds: retentionTimeMilliseconds)
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologySwitchConfigurationSnapshot"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        ssid = try container.decode(String.self, forKey: .ssid)
        retentionTimeMilliseconds = try container.decodeIfPresent(
            UInt64.self, forKey: .retentionTimeMilliseconds
        ) ?? TopologySwitchConfiguration.defaultRetentionTimeMilliseconds
    }
}

struct TopologyRemoteLinkConfigurationSnapshot: Codable, Equatable {
    let nodeID: UUID
    let pairIdentifier: String
    let latencyMilliseconds: UInt64
    let isEnabled: Bool
    let transportMode: TopologyRemoteLinkTransportMode
    let lanRole: TopologyRemoteLinkLANRole
    let lanPort: UInt16
    let lanJoinMethod: TopologyRemoteLinkLANJoinMethod
    let lanRemoteHost: String
    let lanRemotePort: UInt16

    enum CodingKeys: String, CodingKey, CaseIterable {
        case nodeID
        case pairIdentifier
        case latencyMilliseconds
        case isEnabled
        case transportMode
        case lanRole
        case lanPort
        case lanJoinMethod
        case lanRemoteHost
        case lanRemotePort
    }

    init(nodeID: UUID, configuration: TopologyRemoteLinkConfiguration) {
        self.nodeID = nodeID
        pairIdentifier = configuration.pairIdentifier
        latencyMilliseconds = configuration.latencyMilliseconds
        isEnabled = configuration.isEnabled
        transportMode = configuration.transportMode
        lanRole = configuration.lanRole
        lanPort = configuration.lanPort
        lanJoinMethod = configuration.lanJoinMethod
        lanRemoteHost = configuration.lanRemoteHost
        lanRemotePort = configuration.lanRemotePort
    }

    var configuration: TopologyRemoteLinkConfiguration {
        TopologyRemoteLinkConfiguration(
            pairIdentifier: pairIdentifier,
            latencyMilliseconds: latencyMilliseconds,
            isEnabled: isEnabled,
            transportMode: transportMode,
            lanRole: lanRole,
            lanPort: lanPort,
            lanJoinMethod: lanJoinMethod,
            lanRemoteHost: lanRemoteHost,
            lanRemotePort: lanRemotePort
        )
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyRemoteLinkConfigurationSnapshot"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        pairIdentifier = try container.decode(String.self, forKey: .pairIdentifier)
        latencyMilliseconds = try container.decodeIfPresent(
            UInt64.self,
            forKey: .latencyMilliseconds
        ) ?? TopologyRemoteLinkConfiguration.defaultLatencyMilliseconds
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        transportMode = try container.decodeIfPresent(TopologyRemoteLinkTransportMode.self, forKey: .transportMode) ?? .inProject
        lanRole = try container.decodeIfPresent(TopologyRemoteLinkLANRole.self, forKey: .lanRole) ?? .host
        lanPort = try container.decodeIfPresent(UInt16.self, forKey: .lanPort) ?? TopologyRemoteLinkConfiguration.defaultLANPort
        lanJoinMethod = try container.decodeIfPresent(TopologyRemoteLinkLANJoinMethod.self, forKey: .lanJoinMethod) ?? .bonjour
        lanRemoteHost = try container.decodeIfPresent(String.self, forKey: .lanRemoteHost) ?? ""
        lanRemotePort = try container.decodeIfPresent(UInt16.self, forKey: .lanRemotePort) ?? TopologyRemoteLinkConfiguration.defaultLANPort
    }
}

struct TopologyHostWirelessConfigurationSnapshot: Codable, Equatable {
    let nodeID: UUID
    let isEnabled: Bool
    let ssid: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case nodeID
        case isEnabled
        case ssid
    }

    init(nodeID: UUID, configuration: TopologyHostWirelessConfiguration) {
        self.nodeID = nodeID
        isEnabled = configuration.isEnabled
        ssid = configuration.ssid
    }

    var configuration: TopologyHostWirelessConfiguration {
        TopologyHostWirelessConfiguration(isEnabled: isEnabled, ssid: ssid)
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyHostWirelessConfigurationSnapshot"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        ssid = try container.decode(String.self, forKey: .ssid)
    }
}

struct TopologyRuntimeDeviceConfigurationSnapshot: Codable, Equatable {
    let nodeID: UUID
    let ipAddress: String
    let subnetMask: String
    let defaultGateway: String
    let dnsServer: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case nodeID
        case ipAddress
        case subnetMask
        case defaultGateway
        case dnsServer
    }

    init(nodeID: UUID, ipAddress: String, subnetMask: String, defaultGateway: String = "", dnsServer: String = "") {
        self.nodeID = nodeID
        self.ipAddress = ipAddress
        self.subnetMask = subnetMask
        self.defaultGateway = defaultGateway
        self.dnsServer = dnsServer
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyRuntimeDeviceConfigurationSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        ipAddress = try container.decode(String.self, forKey: .ipAddress)
        subnetMask = try container.decode(String.self, forKey: .subnetMask)
        defaultGateway = try container.decodeIfPresent(String.self, forKey: .defaultGateway) ?? ""
        dnsServer = try container.decodeIfPresent(String.self, forKey: .dnsServer) ?? ""
    }
}

struct TopologyRuntimeInterfaceConfigurationSnapshot: Codable, Equatable {
    let nodeID: UUID
    let portID: UUID
    let ipAddress: String
    let subnetMask: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case nodeID
        case portID
        case ipAddress
        case subnetMask
    }

    init(nodeID: UUID, portID: UUID, ipAddress: String, subnetMask: String) {
        self.nodeID = nodeID
        self.portID = portID
        self.ipAddress = ipAddress
        self.subnetMask = subnetMask
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyRuntimeInterfaceConfigurationSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        portID = try container.decode(UUID.self, forKey: .portID)
        ipAddress = try container.decode(String.self, forKey: .ipAddress)
        subnetMask = try container.decode(String.self, forKey: .subnetMask)
    }
}

struct TopologyRuntimeManualRouteTableSnapshot: Codable, Equatable {
    let nodeID: UUID
    let routes: [TopologyRuntimeManualRouteSnapshot]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case nodeID
        case routes
    }

    init(nodeID: UUID, routes: [TopologyRuntimeManualRouteSnapshot]) {
        self.nodeID = nodeID
        self.routes = routes
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyRuntimeManualRouteTableSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        routes = try container.decode([TopologyRuntimeManualRouteSnapshot].self, forKey: .routes)
    }
}

struct TopologyRuntimeManualRouteSnapshot: Codable, Equatable {
    let destinationNetwork: String
    let subnetMask: String
    let gateway: String
    let interfaceIPAddress: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case destinationNetwork
        case subnetMask
        case gateway
        case interfaceIPAddress
    }

    init(
        destinationNetwork: String,
        subnetMask: String,
        gateway: String,
        interfaceIPAddress: String
    ) {
        self.destinationNetwork = destinationNetwork
        self.subnetMask = subnetMask
        self.gateway = gateway
        self.interfaceIPAddress = interfaceIPAddress
    }

    init(_ route: TopologyRuntimeManualRoute) {
        self.init(
            destinationNetwork: route.destinationNetwork,
            subnetMask: route.subnetMask,
            gateway: route.gateway,
            interfaceIPAddress: route.interfaceIPAddress
        )
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyRuntimeManualRouteSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        destinationNetwork = try container.decode(String.self, forKey: .destinationNetwork)
        subnetMask = try container.decode(String.self, forKey: .subnetMask)
        gateway = try container.decode(String.self, forKey: .gateway)
        interfaceIPAddress = try container.decode(String.self, forKey: .interfaceIPAddress)
    }
}

struct TopologyGatewayPortForwardingRowSnapshot: Codable, Equatable {
    let protocolValue: String
    let publicPortValue: String
    let lanIPAddress: String
    let lanPortValue: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolValue
        case publicPortValue
        case lanIPAddress
        case lanPortValue
    }

    init(_ row: TopologyGatewayPortForwardingRow) {
        protocolValue = row.protocolValue
        publicPortValue = row.publicPortValue
        lanIPAddress = row.lanIPAddress
        lanPortValue = row.lanPortValue
    }

    var row: TopologyGatewayPortForwardingRow {
        TopologyGatewayPortForwardingRow(
            protocolValue: protocolValue,
            publicPortValue: publicPortValue,
            lanIPAddress: lanIPAddress,
            lanPortValue: lanPortValue
        )
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyGatewayPortForwardingRowSnapshot"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protocolValue = try container.decodeIfPresent(String.self, forKey: .protocolValue) ?? "TCP"
        publicPortValue = try container.decodeIfPresent(String.self, forKey: .publicPortValue) ?? ""
        lanIPAddress = try container.decodeIfPresent(String.self, forKey: .lanIPAddress) ?? ""
        lanPortValue = try container.decodeIfPresent(String.self, forKey: .lanPortValue) ?? ""
    }
}

struct TopologyGatewayPortForwardingTableSnapshot: Codable, Equatable {
    let nodeID: UUID
    let rowSnapshots: [TopologyGatewayPortForwardingRowSnapshot]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case nodeID
        case rows
    }

    init(nodeID: UUID, rows: [TopologyGatewayPortForwardingRow]) {
        self.nodeID = nodeID
        rowSnapshots = rows.map(TopologyGatewayPortForwardingRowSnapshot.init)
    }

    var rows: [TopologyGatewayPortForwardingRow] {
        rowSnapshots.map(\.row)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nodeID, forKey: .nodeID)
        try container.encode(rowSnapshots, forKey: .rows)
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyGatewayPortForwardingTableSnapshot"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        rowSnapshots = try container.decodeIfPresent(
            [TopologyGatewayPortForwardingRowSnapshot].self,
            forKey: .rows
        ) ?? []
    }
}
struct TopologyRuntimeDNSServerConfigurationSnapshot: Codable, Equatable {
    let nodeID: UUID
    let records: [TopologyRuntimeDNSRecordSnapshot]
    let recursiveResolutionEnabled: Bool?
    let forwardingServerIPAddress: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case nodeID
        case records
        case recursiveResolutionEnabled
        case forwardingServerIPAddress
    }

    init(
        nodeID: UUID,
        records: [TopologyRuntimeDNSRecordSnapshot],
        recursiveResolutionEnabled: Bool = false,
        forwardingServerIPAddress: String? = nil
    ) {
        self.nodeID = nodeID
        self.records = records
        self.recursiveResolutionEnabled = recursiveResolutionEnabled
        self.forwardingServerIPAddress = forwardingServerIPAddress
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(decoder: decoder, allowedKeys: CodingKeys.self, context: "TopologyRuntimeDNSServerConfigurationSnapshot")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        records = try container.decode([TopologyRuntimeDNSRecordSnapshot].self, forKey: .records)
        recursiveResolutionEnabled = try container.decodeIfPresent(Bool.self, forKey: .recursiveResolutionEnabled)
        forwardingServerIPAddress = try container.decodeIfPresent(String.self, forKey: .forwardingServerIPAddress)
    }
}

struct TopologyRuntimeDNSRecordSnapshot: Codable, Equatable {
    let hostname: String
    let targetIPAddress: String
    let type: TopologyDNSRecordType?
    let ttlSeconds: UInt32?
    let target: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case hostname
        case targetIPAddress
        case type
        case ttlSeconds
        case target
    }

    init(hostname: String, targetIPAddress: String) {
        self.hostname = hostname
        self.targetIPAddress = targetIPAddress
        self.type = nil
        self.ttlSeconds = nil
        self.target = nil
    }

    init(_ record: TopologyDNSResourceRecord) {
        self.hostname = record.name.rawValue
        self.targetIPAddress = record.type == .address ? record.target : ""
        self.type = record.type
        self.ttlSeconds = record.ttlSeconds
        self.target = record.target
    }

    var typedRecord: TopologyDNSResourceRecord? {
        let effectiveType = type ?? .address
        let effectiveTarget = target ?? targetIPAddress
        return TopologyDNSResourceRecord(
            name: hostname,
            type: effectiveType,
            ttlSeconds: ttlSeconds ?? TopologyDNSResourceRecord.defaultTTLSeconds,
            target: effectiveTarget
        )
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyRuntimeDNSRecordSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        hostname = try container.decode(String.self, forKey: .hostname)
        targetIPAddress = try container.decodeIfPresent(String.self, forKey: .targetIPAddress) ?? ""
        type = try container.decodeIfPresent(TopologyDNSRecordType.self, forKey: .type)
        ttlSeconds = try container.decodeIfPresent(UInt32.self, forKey: .ttlSeconds)
        target = try container.decodeIfPresent(String.self, forKey: .target)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hostname, forKey: .hostname)
        if let type {
            try container.encode(type, forKey: .type)
            try container.encode(ttlSeconds ?? TopologyDNSResourceRecord.defaultTTLSeconds, forKey: .ttlSeconds)
            try container.encode(target ?? targetIPAddress, forKey: .target)
            if type == .address {
                try container.encode(target ?? targetIPAddress, forKey: .targetIPAddress)
            }
        } else {
            try container.encode(targetIPAddress, forKey: .targetIPAddress)
        }
    }
}

struct TopologyRuntimeWebServerConfigurationSnapshot: Codable, Equatable {
    let nodeID: UUID
    let port: Int
    let documentRoot: String
    let virtualHostConfiguration: TopologyRuntimeWebVirtualHostConfiguration?

    init(nodeID: UUID, configuration: TopologyRuntimeWebServerConfiguration) {
        self.nodeID = nodeID
        port = configuration.port
        documentRoot = configuration.documentRoot
        virtualHostConfiguration = configuration.virtualHostConfiguration
    }

    var configuration: TopologyRuntimeWebServerConfiguration {
        TopologyRuntimeWebServerConfiguration(
            port: port,
            documentRoot: documentRoot,
            virtualHostConfiguration: virtualHostConfiguration
        )
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case nodeID, port, documentRoot, virtualHostConfiguration
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(decoder: decoder, allowedKeys: CodingKeys.self, context: "TopologyRuntimeWebServerConfigurationSnapshot")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        port = try container.decode(Int.self, forKey: .port)
        documentRoot = try container.decode(String.self, forKey: .documentRoot)
        virtualHostConfiguration = try container.decodeIfPresent(
            TopologyRuntimeWebVirtualHostConfiguration.self,
            forKey: .virtualHostConfiguration
        )
    }
}

struct TopologyRuntimeWebAdministrationConfigurationSnapshot: Codable, Equatable {
    let nodeID: UUID
    let configuration: TopologyRuntimeWebAdministrationConfiguration

    init(nodeID: UUID, configuration: TopologyRuntimeWebAdministrationConfiguration) {
        self.nodeID = nodeID
        self.configuration = configuration
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case nodeID, configuration
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyRuntimeWebAdministrationConfigurationSnapshot"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        configuration = try container.decode(
            TopologyRuntimeWebAdministrationConfiguration.self,
            forKey: .configuration
        )
    }
}

struct TopologyRuntimeWebAdministrationPolicySnapshot: Codable, Equatable {
    let nodeID: UUID
    let policy: TopologyRuntimeWebAdministrationAccessPolicy

    init(nodeID: UUID, policy: TopologyRuntimeWebAdministrationAccessPolicy) {
        self.nodeID = nodeID
        self.policy = policy
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case nodeID, policy
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyRuntimeWebAdministrationPolicySnapshot"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        policy = try container.decode(TopologyRuntimeWebAdministrationAccessPolicy.self, forKey: .policy)
    }
}

struct TopologyRuntimeWebBrowserConfigurationSnapshot: Codable, Equatable {
    let nodeID: UUID
    let lastHost: String
    let lastPort: Int
    let lastPath: String

    init(nodeID: UUID, configuration: TopologyRuntimeWebBrowserConfiguration) {
        self.nodeID = nodeID
        lastHost = configuration.lastHost
        lastPort = configuration.lastPort
        lastPath = configuration.lastPath
    }

    var configuration: TopologyRuntimeWebBrowserConfiguration {
        TopologyRuntimeWebBrowserConfiguration(lastHost: lastHost, lastPort: lastPort, lastPath: lastPath)
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case nodeID, lastHost, lastPort, lastPath }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(decoder: decoder, allowedKeys: CodingKeys.self, context: "TopologyRuntimeWebBrowserConfigurationSnapshot")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        lastHost = try container.decode(String.self, forKey: .lastHost)
        lastPort = try container.decode(Int.self, forKey: .lastPort)
        lastPath = try container.decode(String.self, forKey: .lastPath)
    }
}

struct TopologyRuntimeInstalledProgramSnapshot: Codable, Equatable {
    let nodeID: UUID
    let program: TopologyRuntimeInstallableProgram

    enum CodingKeys: String, CodingKey, CaseIterable {
        case nodeID
        case program
    }

    init(nodeID: UUID, program: TopologyRuntimeInstallableProgram) {
        self.nodeID = nodeID
        self.program = program
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyRuntimeInstalledProgramSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        program = try container.decode(TopologyRuntimeInstallableProgram.self, forKey: .program)
    }
}

struct ViewportTransformSnapshot: Codable, Equatable {
    let offset: TopologySizeSnapshot
    let scale: Double

    init(offset: TopologySizeSnapshot, scale: Double) {
        self.offset = offset
        self.scale = scale
    }

    init(_ viewportTransform: ViewportTransform) {
        offset = TopologySizeSnapshot(viewportTransform.offset)
        scale = Double(viewportTransform.scale)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case offset
        case scale
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "ViewportTransformSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        offset = try container.decode(TopologySizeSnapshot.self, forKey: .offset)
        scale = try container.decode(Double.self, forKey: .scale)
    }

    func toViewportTransform() -> ViewportTransform {
        ViewportTransform(offset: offset.toCGSize, scale: CGFloat(scale))
    }
}

struct TopologyPointSnapshot: Codable, Equatable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        x = Double(point.x)
        y = Double(point.y)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case x
        case y
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyPointSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
    }

    var toCGPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

struct TopologySizeSnapshot: Codable, Equatable {
    let width: Double
    let height: Double

    init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    init(_ size: CGSize) {
        width = Double(size.width)
        height = Double(size.height)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case width
        case height
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologySizeSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
    }

    var toCGSize: CGSize {
        CGSize(width: width, height: height)
    }
}

extension TopologyNodeKind: Codable {}


enum TopologyVirtualFileSnapshotKind: String, Codable, Equatable {
    case directory
    case text
    case binary
    case image
}

struct TopologyVirtualFileEntrySnapshot: Codable, Equatable {
    let path: String
    let kind: TopologyVirtualFileSnapshotKind
    let text: String?
    let data: Data?
    let mediaType: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case path
        case kind
        case text
        case data
        case mediaType
    }

    init(entry: TopologyVirtualFileEntry) {
        path = entry.path
        switch entry.content {
        case .directory:
            kind = .directory
            text = nil
            data = nil
            mediaType = nil
        case let .text(value):
            kind = .text
            text = value
            data = nil
            mediaType = "text/plain; charset=utf-8"
        case let .binary(value, type):
            kind = .binary
            text = nil
            data = value
            mediaType = type
        case let .image(value, type):
            kind = .image
            text = nil
            data = value
            mediaType = type
        }
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyVirtualFileEntrySnapshot"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        kind = try container.decode(TopologyVirtualFileSnapshotKind.self, forKey: .kind)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        data = try container.decodeIfPresent(Data.self, forKey: .data)
        mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType)
    }

    func entry() throws -> TopologyVirtualFileEntry {
        let normalizedPath = try TopologyVirtualFileSystem.normalizedAbsolutePath(path)
        let content: TopologyVirtualFileContent
        switch kind {
        case .directory:
            guard text == nil, data == nil else {
                throw TopologyVirtualFileSystemError.expectedDirectory(normalizedPath)
            }
            content = .directory
        case .text:
            guard let text, data == nil else {
                throw TopologyVirtualFileSystemError.expectedTextFile(normalizedPath)
            }
            content = .text(text)
        case .binary:
            guard let data, text == nil else {
                throw TopologyVirtualFileSystemError.expectedFile(normalizedPath)
            }
            content = .binary(data, mediaType: mediaType)
        case .image:
            guard let data, text == nil, let mediaType, !mediaType.isEmpty else {
                throw TopologyVirtualFileSystemError.expectedImageFile(normalizedPath)
            }
            content = .image(data, mediaType: mediaType)
        }
        return TopologyVirtualFileEntry(path: normalizedPath, content: content)
    }
}

struct TopologyVirtualFileSystemSnapshot: Codable, Equatable {
    let nodeID: UUID
    let entries: [TopologyVirtualFileEntrySnapshot]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case nodeID
        case entries
    }

    init(nodeID: UUID, fileSystem: TopologyVirtualFileSystem) {
        self.nodeID = nodeID
        entries = fileSystem.allEntries()
            .filter { $0.path != "/" }
            .map(TopologyVirtualFileEntrySnapshot.init)
            .sorted { $0.path < $1.path }
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyVirtualFileSystemSnapshot"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        entries = try container.decode([TopologyVirtualFileEntrySnapshot].self, forKey: .entries)
    }

    func fileSystem() throws -> TopologyVirtualFileSystem {
        try TopologyVirtualFileSystem(entries: entries.map { try $0.entry() })
    }
}
