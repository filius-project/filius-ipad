import CoreGraphics
import Foundation

enum TopologyEditorToolMode: Equatable {
    case select
    case place(TopologyNodeKind)
    case connect
}

struct TopologyConnectionDraft: Equatable {
    let sourceNodeID: UUID
    let sourcePortID: UUID
}

enum TopologySimulationPhase: String, Equatable {
    case stopped
    case running
}

enum TopologyRuntimeEventCode: String, Equatable {
    case simulationStarted
    case simulationStartIgnoredAlreadyRunning
    case simulationStopped
    case simulationStopIgnoredAlreadyStopped
    case simulationTickAdvanced
    case simulationTickIgnoredWhileStopped
    case simulationSpeedChanged
    case globalPacketLossChanged
    case globalPacketLossChangeIgnoredWhileStopped
    case simulationFaultReported
    case simulationFaultRejectedMalformedPayload
    case runtimeDeviceOpened
    case runtimeDeviceCloseIgnoredAlreadyClosed
    case runtimeDeviceClosed
    case runtimeDeviceIPSaved
    case runtimeInterfaceConfigurationSaved
    case runtimeInterfaceConfigurationRejectedInvalidConfiguration
    case runtimeManualRoutesSaved
    case runtimeManualRoutesRejectedInvalidConfiguration
    case runtimeRIPConfigurationSaved
    case runtimeRIPConfigurationRejected
    case runtimeDHCPClientConfigurationSaved
    case runtimeDHCPClientConfigurationRejected
    case runtimeDHCPServerConfigurationSaved
    case runtimeDHCPServerConfigurationRejected
    case runtimeFirewallConfigurationSaved
    case runtimeFirewallConfigurationRejected
    case runtimeNATTableReset
    case runtimeSwitchSATCleared
    case runtimePortForwardingConfigurationSaved
    case runtimePortForwardingConfigurationRejected
    case runtimeWebAdministrationConfigurationSaved
    case runtimeWebAdministrationConfigurationRejected
    case runtimeWebAdministrationRequestServed
    case runtimeWebAdministrationRequestRejected
    case runtimeProgramInstalled
    case runtimeProgramUninstalled
    case runtimeProgramLaunched
    case runtimeProgramFocusedAlreadyActive
    case runtimeProgramClosed
    case runtimeProgramCloseIgnoredAlreadyDesktop
    case runtimeProgramLaunchRejectedMalformedPayload
    case runtimeProgramLaunchRejectedUnknownNode
    case runtimeProgramLaunchRejectedUnsupportedNodeKind
    case runtimeProgramLaunchRejectedNotInstalled
    case runtimeProgramCloseRejectedMalformedPayload
    case runtimeProgramCloseRejectedUnknownNode
    case runtimeDeviceIPRejectedInvalidConfiguration
    case pingSucceeded
    case pingRejectedSimulationStopped
    case pingRejectedMalformedCommand
    case pingRejectedUnknownTarget
    case pingRejectedInvalidSourceConfiguration
    case pingRejectedTopologyUnreachable
    case pingRejectedSubnetMismatch
    case traceSucceeded
    case traceRejectedSimulationStopped
    case traceRejectedMalformedCommand
    case traceRejectedUnknownTarget
    case traceRejectedInvalidSourceConfiguration
    case traceRejectedTopologyUnreachable
    case traceRejectedSubnetMismatch
    case routeSucceeded
    case routeRejectedSimulationStopped
    case routeRejectedMalformedCommand
    case routeRejectedUnknownTarget
    case routeRejectedInvalidSourceConfiguration
    case routeRejectedTopologyUnreachable
    case routeRejectedSubnetMismatch
    case hostResolveSucceeded
    case hostResolveRejectedMalformedCommand
    case hostResolveRejectedUnknownHost
    case hostResolveRejectedSimulationStopped
    case runtimeHelpDisplayed
    case runtimeHelpRejectedMalformedCommand
    case dhcpLeaseAssigned
    case dhcpLeaseReleased
    case dhcpLeaseRejectedSimulationStopped
    case dhcpLeaseRejectedMalformedCommand
    case dhcpLeaseRejectedInvalidConfiguration
    case dhcpLeaseRejectedMissingLease
    case dnsRecordRegistered
    case dnsRecordRemoved
    case dnsRecordRejectedMalformedCommand
    case dnsRecordRejectedSimulationStopped
    case dnsRecordRejectedUnknownHost
    case dnsResolveSucceeded
    case dnsResolveCacheHit
    case dnsResolveRejectedUnknownHost
    case dnsResolveRejectedUnreachable
    case dnsResolveRejectedTimeout
    case dnsResolveRejectedMissingServerConfiguration
    case dnsResolveRejectedSimulationStopped
    case dnsServerStarted
    case dnsServerStartIgnoredAlreadyRunning
    case dnsServerStopped
    case dnsServerStopIgnoredAlreadyStopped
    case dnsServerRejectedInvalidConfiguration
    case webServerConfigurationSaved
    case webServerStarted
    case webServerStartIgnoredAlreadyRunning
    case webServerStopped
    case webServerStopIgnoredAlreadyStopped
    case webServerRejectedSimulationStopped
    case webServerRejectedInvalidConfiguration
    case webServerRestarted
    case webServerRequestServed
    case webServerRequestRejected
    case webBrowserNavigationSucceeded
    case webBrowserNavigationFailed
    case webBrowserRejectedMalformedURL
    case webBrowserRejectedDNSFailure
    case webBrowserRejectedUnreachable
    case webBrowserRejectedTimeout
    case echoServerStarted
    case echoServerStartIgnoredAlreadyRunning
    case echoServerStopped
    case echoServerStopIgnoredAlreadyStopped
    case echoServerRejectedSimulationStopped
    case echoServerRejectedInvalidConfiguration
    case simpleClientConnected
    case simpleClientDisconnected
    case simpleClientMessageSent
    case simpleClientMessageReceived
    case simpleClientRejectedSimulationStopped
    case simpleClientRejectedInvalidConfiguration
    case simpleClientRejectedUnreachable
    case simpleClientRejectedNotConnected
    case emailClientConfigured
    case emailClientConfigurationRejected
    case emailClientSendSucceeded
    case emailClientSendRejected
    case emailClientRetrieveSucceeded
    case emailClientRetrieveRejected
    case emailClientMessagesDeleted
    case emailClientDeleteRejected
    case emailServerConfigured
    case emailServerStarted
    case emailServerStopped
    case emailServerRejected
    case gnutellaConfigured
    case gnutellaStarted
    case gnutellaJoined
    case gnutellaNetworkReset
    case gnutellaSearchCompleted
    case gnutellaSearchResultsCleared
    case gnutellaDownloadCompleted
    case gnutellaRejected
    case runtimeServiceActionRejectedMalformedPayload
    case runtimeServiceActionRejectedInvalidContext
    case runtimeDesktopAppActionRejectedMalformedPayload
    case runtimeDesktopAppActionRejectedInvalidContext
    case runtimeDesktopAppActionRejectedUnknownTarget
    case runtimeFileExplorerSelectionChanged
    case runtimeImageViewerSelectionChanged
    case runtimeTextEditorDraftUpdated
    case runtimeTextEditorDraftSaved
    case runtimeTextEditorDraftReset
    case runtimeVirtualFileSystemChanged
    case runtimeVirtualFileSystemOperationRejected
    case runtimeFilesystemCommandSucceeded
    case runtimeFilesystemCommandRejectedMalformed
    case runtimeFilesystemCommandRejectedPath
    case runtimeFilesystemCommandRejectedContext
    case runtimeNetworkInspectionCommandExecuted
    case runtimeNetworkInspectionCommandRejected
    case runtimeCommandRejectedUnsupported
    case protocolApplicationDefinitionCreated
    case protocolApplicationDefinitionUpdated
    case protocolApplicationDefinitionDeleted
    case protocolApplicationDefinitionRejected
    case protocolApplicationInstalled
    case protocolApplicationUninstalled
    case protocolApplicationLaunched
    case protocolApplicationClosed
    case protocolApplicationServerStarted
    case protocolApplicationServerStopped
    case protocolApplicationClientCompleted
    case protocolApplicationRuntimeRejected
}

struct TopologyRuntimeEvent: Equatable {
    let code: TopologyRuntimeEventCode
    let detail: String?
}

enum TopologyRuntimeFaultCategory: String, Equatable {
    case runtimeFault
    case malformedRuntimePayload
    case commandValidation
    case networkConfiguration
    case networkRouting
    case networkService
}

struct TopologyRuntimeFault: Equatable {
    let category: TopologyRuntimeFaultCategory
    let code: String
    let message: String
}

struct TopologyRuntimeDeviceConfiguration: Equatable {
    let ipAddress: String
    let subnetMask: String
    let defaultGateway: String
    let dnsServer: String

    init(ipAddress: String, subnetMask: String, defaultGateway: String = "", dnsServer: String = "") {
        self.ipAddress = ipAddress
        self.subnetMask = subnetMask
        self.defaultGateway = defaultGateway
        self.dnsServer = dnsServer
    }
}

struct TopologySwitchConfiguration: Equatable {
    static let defaultRetentionTimeMilliseconds: UInt64 = 300_000

    var ssid: String
    var retentionTimeMilliseconds: UInt64

    init(ssid: String, retentionTimeMilliseconds: UInt64 = defaultRetentionTimeMilliseconds) {
        self.ssid = ssid
        self.retentionTimeMilliseconds = retentionTimeMilliseconds
    }

    static func defaultConfiguration(nodeID: UUID) -> TopologySwitchConfiguration {
        let compactIdentifier = nodeID.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return TopologySwitchConfiguration(ssid: String(compactIdentifier.prefix(6)))
    }
}

enum TopologyRemoteLinkTransportMode: String, Codable, CaseIterable, Equatable, Sendable {
    case inProject
    case localNetwork
}

enum TopologyRemoteLinkLANRole: String, Codable, CaseIterable, Equatable, Sendable {
    case host
    case join
}

enum TopologyRemoteLinkLANJoinMethod: String, Codable, CaseIterable, Equatable, Sendable {
    case bonjour
    case manual
}

struct TopologyRemoteLinkConfiguration: Equatable {
    static let defaultLatencyMilliseconds: UInt64 = 20
    static let defaultLANPort: UInt16 = 12_345

    private static let shareCodeLowerBound = 100_000
    private static let shareCodeCount = 900_000

    var pairIdentifier: String
    var latencyMilliseconds: UInt64
    var isEnabled: Bool
    var transportMode: TopologyRemoteLinkTransportMode
    var lanRole: TopologyRemoteLinkLANRole
    var lanPort: UInt16
    var lanJoinMethod: TopologyRemoteLinkLANJoinMethod
    var lanRemoteHost: String
    var lanRemotePort: UInt16

    init(
        pairIdentifier: String,
        latencyMilliseconds: UInt64 = defaultLatencyMilliseconds,
        isEnabled: Bool = true,
        transportMode: TopologyRemoteLinkTransportMode = .inProject,
        lanRole: TopologyRemoteLinkLANRole = .host,
        lanPort: UInt16 = defaultLANPort,
        lanJoinMethod: TopologyRemoteLinkLANJoinMethod = .bonjour,
        lanRemoteHost: String = "",
        lanRemotePort: UInt16 = defaultLANPort
    ) {
        self.pairIdentifier = pairIdentifier
        self.latencyMilliseconds = latencyMilliseconds
        self.isEnabled = isEnabled
        self.transportMode = transportMode
        self.lanRole = lanRole
        self.lanPort = lanPort
        self.lanJoinMethod = lanJoinMethod
        self.lanRemoteHost = lanRemoteHost
        self.lanRemotePort = lanRemotePort
    }

    static func defaultConfiguration(
        nodeID: UUID,
        avoiding reservedPairIdentifiers: Set<String> = []
    ) -> TopologyRemoteLinkConfiguration {
        let compactIdentifier = nodeID.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let seed = Int(String(compactIdentifier.prefix(8)), radix: 16) ?? 0
        let reservedIdentifiers = Set(
            reservedPairIdentifiers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
        var candidate = shareCodeLowerBound + (seed % shareCodeCount)

        for _ in 0..<shareCodeCount {
            let shareCode = String(candidate)
            if !reservedIdentifiers.contains(shareCode) {
                return TopologyRemoteLinkConfiguration(pairIdentifier: shareCode)
            }
            candidate = shareCodeLowerBound + ((candidate - shareCodeLowerBound + 1) % shareCodeCount)
        }

        return TopologyRemoteLinkConfiguration(pairIdentifier: String(candidate))
    }
}

struct TopologyHostWirelessConfiguration: Equatable {
    var isEnabled: Bool
    var ssid: String

    init(isEnabled: Bool = false, ssid: String = "") {
        self.isEnabled = isEnabled
        self.ssid = ssid
    }
}

struct TopologyWirelessAssociation: Equatable {
    let hostNodeID: UUID
    let hostPortID: UUID
    let switchNodeID: UUID
    let switchPortID: UUID
    let ssid: String

    var runtimeLink: TopologyLink {
        TopologyLink(
            id: hostNodeID,
            sourceNodeID: hostNodeID,
            sourcePortID: hostPortID,
            targetNodeID: switchNodeID,
            targetPortID: switchPortID
        )
    }
}

struct TopologyDHCPStaticAssignment: Equatable, Identifiable {
    let id: UUID
    let macAddress: String
    let ipAddress: String

    init(id: UUID = UUID(), macAddress: String, ipAddress: String) {
        self.id = id
        self.macAddress = macAddress
        self.ipAddress = ipAddress
    }
}

struct TopologyDHCPClientConfiguration: Equatable {
    var isEnabled: Bool

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }
}

struct TopologyDHCPServerConfiguration: Equatable {
    var isActive: Bool
    var lowerBoundIPAddress: String
    var upperBoundIPAddress: String
    var gatewayIPAddress: String
    var dnsServerIPAddress: String
    var useOwnSettings: Bool
    var staticAssignments: [TopologyDHCPStaticAssignment]

    init(
        isActive: Bool = false,
        lowerBoundIPAddress: String = "0.0.0.0",
        upperBoundIPAddress: String = "0.0.0.0",
        gatewayIPAddress: String = "0.0.0.0",
        dnsServerIPAddress: String = "0.0.0.0",
        useOwnSettings: Bool = false,
        staticAssignments: [TopologyDHCPStaticAssignment] = []
    ) {
        self.isActive = isActive
        self.lowerBoundIPAddress = lowerBoundIPAddress
        self.upperBoundIPAddress = upperBoundIPAddress
        self.gatewayIPAddress = gatewayIPAddress
        self.dnsServerIPAddress = dnsServerIPAddress
        self.useOwnSettings = useOwnSettings
        self.staticAssignments = staticAssignments
    }
}

enum TopologyFirewallProtocol: Int, CaseIterable, Equatable {
    case all = -1
    case icmp = 1
    case tcp = 6
    case udp = 17

    var javaLabel: String {
        switch self {
        case .all: return "*"
        case .icmp: return "ICMP"
        case .tcp: return "TCP"
        case .udp: return "UDP"
        }
    }
}

enum TopologyFirewallAction: Int, CaseIterable, Equatable {
    case drop = 0
    case accept = 1

    var javaLabel: String {
        switch self {
        case .drop: return "verwerfen"
        case .accept: return "akzeptieren"
        }
    }
}

struct TopologyFirewallRule: Equatable {
    static let directlyConnectedSourceMarker = "999.999.999.999"
    static let allPorts = -1

    var sourceIPAddress: String
    var sourceSubnetMask: String
    var destinationIPAddress: String
    var destinationSubnetMask: String
    var port: Int
    var protocolType: TopologyFirewallProtocol
    var action: TopologyFirewallAction

    init(
        sourceIPAddress: String = "",
        sourceSubnetMask: String = "",
        destinationIPAddress: String = "",
        destinationSubnetMask: String = "",
        port: Int = TopologyFirewallRule.allPorts,
        protocolType: TopologyFirewallProtocol = .tcp,
        action: TopologyFirewallAction = .drop
    ) {
        self.sourceIPAddress = sourceIPAddress
        self.sourceSubnetMask = sourceSubnetMask
        self.destinationIPAddress = destinationIPAddress
        self.destinationSubnetMask = destinationSubnetMask
        self.port = port
        self.protocolType = protocolType
        self.action = action
    }
}

struct TopologyFirewallConfiguration: Equatable {
    static let javaPersonalDefaults = TopologyFirewallConfiguration(
        isActive: true,
        defaultPolicy: .drop,
        dropICMP: false,
        filterSYNSegmentsOnly: true,
        filterUDP: true,
        rules: []
    )

    var isActive: Bool
    var defaultPolicy: TopologyFirewallAction
    var dropICMP: Bool
    var filterSYNSegmentsOnly: Bool
    var filterUDP: Bool
    var rules: [TopologyFirewallRule]

    init(
        isActive: Bool = false,
        defaultPolicy: TopologyFirewallAction = .drop,
        dropICMP: Bool = false,
        filterSYNSegmentsOnly: Bool = true,
        filterUDP: Bool = true,
        rules: [TopologyFirewallRule] = []
    ) {
        self.isActive = isActive
        self.defaultPolicy = defaultPolicy
        self.dropICMP = dropICMP
        self.filterSYNSegmentsOnly = filterSYNSegmentsOnly
        self.filterUDP = filterUDP
        self.rules = rules
    }
}

struct TopologyGatewayPortForwardingRow: Equatable {
    var protocolValue: String
    var publicPortValue: String
    var lanIPAddress: String
    var lanPortValue: String

    init(
        protocolValue: String = "TCP",
        publicPortValue: String = "",
        lanIPAddress: String = "",
        lanPortValue: String = ""
    ) {
        self.protocolValue = protocolValue
        self.publicPortValue = publicPortValue
        self.lanIPAddress = lanIPAddress
        self.lanPortValue = lanPortValue
    }

    var runtimeProtocol: TopologyIPv4Protocol? {
        switch protocolValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "TCP", "6": return .tcp
        case "UDP", "17": return .udp
        default: return nil
        }
    }

    var runtimePublicPort: UInt16? {
        Self.validPort(publicPortValue)
    }

    var runtimeLANPort: UInt16? {
        Self.validPort(lanPortValue)
    }

    var isRuntimeValid: Bool {
        runtimeProtocol != nil
            && runtimePublicPort != nil
            && runtimeLANPort != nil
            && Self.isValidIPv4(lanIPAddress)
    }

    private static func validPort(_ value: String) -> UInt16? {
        guard let number = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...65_535).contains(number) else { return nil }
        return UInt16(number)
    }

    private static func isValidIPv4(_ value: String) -> Bool {
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        return segments.count == 4 && segments.allSatisfy { segment in
            !segment.isEmpty
                && segment.allSatisfy(\.isNumber)
                && UInt8(String(segment)) != nil
        }
    }
}
struct TopologyRuntimeInterfaceKey: Hashable {
    let nodeID: UUID
    let portID: UUID
}

struct TopologyRuntimeInterfaceConfiguration: Equatable {
    let ipAddress: String
    let subnetMask: String
}

struct TopologyDesignInterfaceConfiguration: Identifiable, Equatable {
    let id: UUID
    var ipAddress: String
    var subnetMask: String
}

struct TopologyRuntimeManualRoute: Equatable {
    let destinationNetwork: String
    let subnetMask: String
    let gateway: String
    let interfaceIPAddress: String

    static func bestMatching(
        targetIPAddress: String,
        routes: [TopologyRuntimeManualRoute]
    ) -> TopologyRuntimeManualRoute? {
        guard let targetAddress = parseIPv4(targetIPAddress) else {
            return nil
        }

        var bestRoute: TopologyRuntimeManualRoute?
        var bestMask: UInt32?

        for route in routes {
            guard
                let destinationNetwork = parseIPv4(route.destinationNetwork),
                let mask = parseIPv4(route.subnetMask),
                destinationNetwork == (targetAddress & mask)
            else {
                continue
            }

            if let bestMask, mask <= bestMask {
                continue
            }

            bestMask = mask
            bestRoute = route
        }

        return bestRoute
    }

    private static func parseIPv4(_ value: String) -> UInt32? {
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 4 else {
            return nil
        }

        var address = UInt32(0)
        for segment in segments {
            guard let octet = UInt8(segment) else {
                return nil
            }
            address = (address << 8) | UInt32(octet)
        }
        return address
    }
}

struct TopologyRuntimeInterfaceConfigurationItem: Identifiable, Equatable {
    let id: UUID
    let label: String
    let configuration: TopologyRuntimeInterfaceConfiguration?
}

enum TopologyRuntimeInterfaceDefaults {
    static func configurations(for node: TopologyNode) -> [(TopologyRuntimeInterfaceKey, TopologyRuntimeInterfaceConfiguration)] {
        switch node.kind {
        case .router:
            guard let port = node.ports.first else {
                return []
            }

            return [
                (
                    TopologyRuntimeInterfaceKey(nodeID: node.id, portID: port.id),
                    TopologyRuntimeInterfaceConfiguration(
                        ipAddress: "192.168.0.10",
                        subnetMask: "255.255.255.0"
                    )
                )
            ]

        case .gateway:
            guard node.ports.count >= 2 else {
                return []
            }

            return [
                (
                    TopologyRuntimeInterfaceKey(nodeID: node.id, portID: node.ports[0].id),
                    TopologyRuntimeInterfaceConfiguration(
                        ipAddress: "42.0.0.10",
                        subnetMask: "255.0.0.0"
                    )
                ),
                (
                    TopologyRuntimeInterfaceKey(nodeID: node.id, portID: node.ports[1].id),
                    TopologyRuntimeInterfaceConfiguration(
                        ipAddress: "192.168.0.10",
                        subnetMask: "255.255.255.0"
                    )
                )
            ]

        case .pc, .notebook, .networkSwitch, .remoteLink, .unsupported:
            return []
        }
    }
}

struct TopologyRuntimeDNSRecord: Equatable {
    let hostname: String
    let targetIPAddress: String
}

struct TopologyRuntimeDNSServerConfiguration: Equatable {
    /// Legacy A-record projection retained for Java-compatible callers and old archives.
    var recordsByHostname: [String: TopologyRuntimeDNSRecord]
    /// Canonical Java-compatible record order. For compatibility, `recordsByHostname` mirrors the
    /// first A record for each hostname; this ordered collection remains the source of truth.
    var additionalTypedRecords: [TopologyDNSResourceRecord]
    var recursiveResolutionEnabled: Bool
    var forwardingServerIPAddress: String?

    var typedRecords: [TopologyDNSResourceRecord] {
        var records = additionalTypedRecords
        let representedHostnames = Set(records.compactMap { record -> String? in
            record.type == .address ? record.name.rawValue : nil
        })
        for hostname in recordsByHostname.keys.sorted() where !representedHostnames.contains(hostname) {
            guard let legacy = recordsByHostname[hostname],
                  let record = TopologyDNSResourceRecord(legacyARecord: legacy)
            else { continue }
            records.append(record)
        }
        return records
    }

    init(
        recordsByHostname: [String: TopologyRuntimeDNSRecord] = [:],
        typedRecords: [TopologyDNSResourceRecord] = [],
        recursiveResolutionEnabled: Bool = false,
        forwardingServerIPAddress: String? = nil
    ) {
        self.recordsByHostname = recordsByHostname
        self.additionalTypedRecords = typedRecords
        self.recursiveResolutionEnabled = recursiveResolutionEnabled
        self.forwardingServerIPAddress = forwardingServerIPAddress
        normalizeTypedStorage()
    }

    init(
        typedRecords: [TopologyDNSResourceRecord],
        recursiveResolutionEnabled: Bool = false,
        forwardingServerIPAddress: String? = nil
    ) {
        self.init(
            recordsByHostname: [:],
            typedRecords: typedRecords,
            recursiveResolutionEnabled: recursiveResolutionEnabled,
            forwardingServerIPAddress: forwardingServerIPAddress
        )
    }

    @discardableResult
    mutating func appendLegacyAddressRecord(_ record: TopologyRuntimeDNSRecord) -> Bool {
        guard let appendedRecord = TopologyDNSResourceRecord(legacyARecord: record) else {
            return false
        }
        let alreadyExists = additionalTypedRecords.contains {
            $0.name == appendedRecord.name
                && $0.type == appendedRecord.type
                && $0.target == appendedRecord.target
        }
        guard !alreadyExists else {
            return false
        }

        additionalTypedRecords.append(appendedRecord)
        if recordsByHostname[record.hostname] == nil {
            recordsByHostname[record.hostname] = record
        }
        return true
    }

    mutating func addTypedRecord(_ record: TopologyDNSResourceRecord) {
        additionalTypedRecords.removeAll {
            $0.name == record.name && $0.type == record.type && $0.target == record.target
        }
        additionalTypedRecords.append(record)
        if record.type == .address, let legacy = record.legacyARecord,
           recordsByHostname[legacy.hostname] == nil {
            recordsByHostname[legacy.hostname] = legacy
        }
    }

    @discardableResult
    mutating func removeTypedRecord(
        hostname: String,
        recordType: TopologyDNSRecordType,
        target: String
    ) -> Bool {
        let before = additionalTypedRecords.count
        additionalTypedRecords.removeAll {
            $0.name.rawValue == hostname && $0.type == recordType && $0.target == target
        }
        var removed = before != additionalTypedRecords.count
        if recordType == .address,
           recordsByHostname[hostname]?.targetIPAddress == target {
            recordsByHostname.removeValue(forKey: hostname)
            if let replacement = additionalTypedRecords.first(where: {
                $0.name.rawValue == hostname && $0.type == .address
            })?.legacyARecord {
                recordsByHostname[hostname] = replacement
            }
            removed = true
        }
        return removed
    }

    @discardableResult
    mutating func removeLegacyAddressRecord(hostname: String) -> TopologyRuntimeDNSRecord? {
        let projectedRecord = recordsByHostname[hostname]
        guard let recordIndex = additionalTypedRecords.firstIndex(where: {
            $0.name.rawValue == hostname && $0.type == .address
        }) else {
            return recordsByHostname.removeValue(forKey: hostname)
        }

        let removedRecord = additionalTypedRecords.remove(at: recordIndex).legacyARecord ?? projectedRecord
        recordsByHostname.removeValue(forKey: hostname)
        if let promotedRecord = additionalTypedRecords.first(where: {
            $0.name.rawValue == hostname && $0.type == .address
        })?.legacyARecord {
            recordsByHostname[hostname] = promotedRecord
        }
        return removedRecord
    }

    private mutating func normalizeTypedStorage() {
        var firstAddresses: [String: TopologyRuntimeDNSRecord] = [:]
        for record in additionalTypedRecords where record.type == .address {
            guard let legacy = record.legacyARecord, firstAddresses[legacy.hostname] == nil else { continue }
            firstAddresses[legacy.hostname] = legacy
        }
        for (hostname, legacy) in firstAddresses {
            recordsByHostname[hostname] = legacy
        }

        for hostname in recordsByHostname.keys.sorted() where firstAddresses[hostname] == nil {
            guard let legacy = recordsByHostname[hostname],
                  let record = TopologyDNSResourceRecord(legacyARecord: legacy)
            else { continue }
            additionalTypedRecords.append(record)
        }
    }
}

enum TopologyRuntimeDNSHostsFile {
    static let path = "/dns/hosts"
    static let directoryPath = "/dns"
    static let defaultTTL = "3600"

    static func normalizedHostname(_ rawValue: String) -> String? {
        var hostname = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while hostname.hasSuffix(".") { hostname.removeLast() }
        guard !hostname.isEmpty, !hostname.contains(where: { $0.isWhitespace }) else { return nil }
        return hostname
    }

    static func isValidIPv4Address(_ value: String) -> Bool {
        let octets = value.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { octet in
            guard !octet.isEmpty, octet.allSatisfy(\.isNumber), let number = Int(octet) else { return false }
            return (0...255).contains(number)
        }
    }

    static func aRecord(from line: String) -> TopologyRuntimeDNSRecord? {
        let content = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let fields = content.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard fields.count >= 4, fields[1].uppercased() == "A",
              let hostname = normalizedHostname(fields[0]), isValidIPv4Address(fields[3])
        else { return nil }
        return TopologyRuntimeDNSRecord(hostname: hostname, targetIPAddress: fields[3])
    }

    static func records(from text: String) -> [String: TopologyRuntimeDNSRecord] {
        var records: [String: TopologyRuntimeDNSRecord] = [:]
        for line in text.components(separatedBy: .newlines) {
            guard let record = aRecord(from: line), records[record.hostname] == nil else { continue }
            records[record.hostname] = record
        }
        return records
    }

    static func typedRecords(from text: String) -> [TopologyDNSResourceRecord] {
        TopologyDNSHostsFileCodec.records(from: text)
    }

    static func text(
        mirroringTypedRecords records: [TopologyDNSResourceRecord],
        preserving existingText: String
    ) -> String {
        TopologyDNSHostsFileCodec.text(mirroring: records, preserving: existingText)
    }

    static func text(
        mirroring recordsByHostname: [String: TopologyRuntimeDNSRecord],
        preserving existingText: String
    ) -> String {
        var emitted: Set<String> = []
        var output: [String] = []
        let existingLines = existingText.isEmpty ? [] : existingText.components(separatedBy: .newlines)
        for line in existingLines {
            guard let existingRecord = aRecord(from: line) else {
                output.append(line)
                continue
            }
            guard let record = recordsByHostname[existingRecord.hostname], emitted.insert(existingRecord.hostname).inserted else {
                continue
            }
            output.append("\(record.hostname). A \(defaultTTL) \(record.targetIPAddress)")
        }
        for hostname in recordsByHostname.keys.sorted() where emitted.insert(hostname).inserted {
            guard let record = recordsByHostname[hostname] else { continue }
            output.append("\(record.hostname). A \(defaultTTL) \(record.targetIPAddress)")
        }
        while output.last == "" { output.removeLast() }
        return output.isEmpty ? "" : output.joined(separator: "\n") + "\n"
    }
}

struct TopologyRuntimeDNSCacheEntry: Equatable {
    let hostname: String
    let targetIPAddress: String?
    let serverIPAddress: String
    let expiresAtMilliseconds: UInt64
}

enum TopologyRuntimeDNSResolutionResult: Equatable {
    case success(record: TopologyRuntimeDNSRecord, serverIPAddress: String, cached: Bool)
    case nxdomain(hostname: String, serverIPAddress: String, cached: Bool)
    case unreachable(serverIPAddress: String)
    case timeout(serverIPAddress: String)
    case missingServerConfiguration
    case simulationStopped
}

struct TopologyRuntimeServiceProcessState: Equatable {
    let port: Int
}

enum TopologyRuntimeInstallableProgram: String, CaseIterable, Codable, Equatable, Hashable {
    case commandPrompt
    case fileExplorer
    case imageViewer
    case textEditor
    case webServer
    case webBrowser
    case echoServer
    case simpleClient
    case dnsServer
    case dhcpServer
    case firewall
    case emailClient
    case emailServer
    case gnutella
}

enum TopologyRuntimeCommandCatalog {
    static let supportedCommandsInline = "arp, arpsend, cat, cd, cp, del, ipconfig, ls, mkdir, mv, netstat, pwd, tcpdump, touch, ping, trace/path/traceroute, route, host/nslookup, dns add/remove/resolve, help [command]"
    // Legacy parity anchor retained while the catalog grows: Supported: cat <file>, cd [directory], cp <source-file>

    static let helpSummary = "Supported: arp [-a <ipv4> | -d [ipv4]], arpsend <sender-ipv4> <target-ipv4>, ipconfig, netstat, tcpdump, cat <file>, cd [directory], cp <source-file> <destination>, del <file>, ls [directory], mkdir <directory>, mv <source-file> <destination>, pwd, touch <file>, ping <target-ipv4|hostname>, trace|path|traceroute <target-ipv4|hostname>, route <target-ipv4|hostname>, host|nslookup <hostname>, dns add <hostname> <target-ipv4>, dns remove <hostname>, dns resolve <hostname>, help [command]"

    static let substitutionBoundarySummary = "CMD filesystem commands share the persistent per-device virtual filesystem. ipconfig, netstat, arp/arpsend, and tcpdump project live deterministic interfaces, sockets, ARP cache, and packet traces; tcpdump is a bounded snapshot rather than a blocking host process. Java aliases copy/move/dir/rm remain accepted."

    static let helpLines = [
        helpSummary,
        substitutionBoundarySummary,
    ]

    static func usage(for command: String) -> String? {
        switch command.lowercased() {
        case "arp": return "Usage: arp [-a <ipv4> | -d [ipv4]]"
        case "arpsend": return "Usage: arpsend <sender-ipv4> <target-ipv4>"
        case "ipconfig": return "Usage: ipconfig"
        case "netstat": return "Usage: netstat"
        case "tcpdump": return "Usage: tcpdump"
        case "cat", "type": return "Usage: cat <file>"
        case "cd": return "Usage: cd [directory]"
        case "copy", "cp": return "Usage: cp <source-file> <destination>"
        case "del", "rm": return "Usage: del <file>"
        case "dir", "ls": return "Usage: ls [directory]"
        case "mkdir": return "Usage: mkdir <directory>"
        case "move", "mv": return "Usage: mv <source-file> <destination>"
        case "pwd": return "Usage: pwd"
        case "touch": return "Usage: touch <file>"
        case "ping": return "Usage: ping <target-ipv4|hostname>"
        case "trace", "path", "traceroute": return "Usage: trace <target-ipv4|hostname>"
        case "route": return "Usage: route <target-ipv4|hostname>"
        case "host", "nslookup": return "Usage: host <hostname>"
        case "dns": return "Usage: dns resolve <hostname> | dns add <hostname> <target-ipv4> | dns remove <hostname>"
        case "help", "?": return "Usage: help [command]"
        default: return nil
        }
    }
}

struct TopologyPersistenceFailure: Equatable {
    let operation: TopologyProjectPersistenceOperation
    let code: TopologyProjectPersistenceErrorCode
    let detail: String
    let occurredAt: Date
}


struct TopologyRuntimeWebAdministrationConfiguration: Codable, Equatable {
    static let defaultPort = 80

    var port: Int
    var accessPolicy: TopologyRuntimeWebAdministrationAccessPolicy

    init(
        port: Int = Self.defaultPort,
        accessPolicy: TopologyRuntimeWebAdministrationAccessPolicy = TopologyRuntimeWebAdministrationAccessPolicy()
    ) {
        self.port = port
        self.accessPolicy = accessPolicy
    }
}

extension TopologyEditorState {
    /// Builds the secret-free projection consumed by the router/gateway administration renderer.
    ///
    /// The projection is intentionally derived from editor/runtime state at request time so a
    /// rendered page cannot outlive a configuration change or expose credentials and payloads.
    func runtimeWebAdministrationSnapshot(for nodeID: UUID) -> TopologyRuntimeWebAdministrationSnapshot? {
        guard let node = graph.node(withID: nodeID), node.kind == .router || node.kind == .gateway else {
            return nil
        }

        let interfaces = networkRuntime.networkInterfaces(nodeID: nodeID).map { interface in
            TopologyRuntimeWebAdministrationInterfaceStatus(
                name: node.ports.first(where: { $0.id == interface.portID })?.label ?? "if\(interface.index)",
                ipAddress: interface.ipAddress,
                subnetMask: interface.subnetMask,
                macAddress: interface.macAddress,
                isUp: simulationPhase == .running
            )
        }

        var routes = (runtimeManualRoutesByNodeID[nodeID] ?? []).enumerated().map { index, route in
            TopologyRuntimeWebAdministrationRouteStatus(
                id: "manual-\(index)",
                destinationNetwork: route.destinationNetwork,
                subnetMask: route.subnetMask,
                gatewayIPAddress: route.gateway,
                interfaceIPAddress: route.interfaceIPAddress
            )
        }
        routes.append(contentsOf: (networkRuntime.state.ripTablesByNodeID[nodeID] ?? []).enumerated().map { index, route in
            TopologyRuntimeWebAdministrationRouteStatus(
                id: "rip-\(index)",
                destinationNetwork: route.destinationNetwork,
                subnetMask: route.subnetMask,
                gatewayIPAddress: route.nextHop,
                interfaceIPAddress: route.interfaceIPAddress
            )
        })

        let dhcpConfiguration = runtimeDHCPServerConfigurationsByNodeID[nodeID] ?? TopologyDHCPServerConfiguration()
        let activeLeaseCount = networkRuntime.state.dhcpLeasesByIPAddress.values.filter {
            $0.serverNodeID == nodeID
        }.count
        let dhcp = TopologyRuntimeWebAdministrationDHCPStatus(
            isActive: dhcpConfiguration.isActive,
            lowerBoundIPAddress: dhcpConfiguration.lowerBoundIPAddress,
            upperBoundIPAddress: dhcpConfiguration.upperBoundIPAddress,
            gatewayIPAddress: dhcpConfiguration.gatewayIPAddress,
            dnsServerIPAddress: dhcpConfiguration.dnsServerIPAddress,
            usesOwnSettings: dhcpConfiguration.useOwnSettings,
            activeLeaseCount: activeLeaseCount,
            staticAssignmentCount: dhcpConfiguration.staticAssignments.count
        )

        let natMappings = networkRuntime.natMappings(gatewayNodeID: nodeID).map { mapping in
            TopologyRuntimeWebAdministrationNATMappingStatus(
                id: mapping.id.uuidString,
                protocolName: String(mapping.protocolNumber.rawValue),
                publicEndpoint: "\(mapping.remoteIPAddress):\(mapping.translatedPortOrIdentifier)",
                privateEndpoint: "\(mapping.lanIPAddress):\(mapping.lanPortOrIdentifier)",
                state: mapping.type.rawValue
            )
        }

        let portForwards = (runtimePortForwardingRowsByNodeID[nodeID] ?? []).enumerated().compactMap {
            index, row -> TopologyRuntimeWebAdministrationPortForwardStatus? in
            guard row.isRuntimeValid,
                  let protocolNumber = row.runtimeProtocol,
                  let publicPort = row.runtimePublicPort,
                  let lanPort = row.runtimeLANPort else {
                return nil
            }
            return TopologyRuntimeWebAdministrationPortForwardStatus(
                id: "port-forward-\(index)",
                protocolName: String(protocolNumber.rawValue),
                publicPort: publicPort,
                lanIPAddress: row.lanIPAddress,
                lanPort: lanPort
            )
        }

        let firewallConfiguration = runtimeFirewallConfigurationsByNodeID[nodeID] ?? TopologyFirewallConfiguration()
        let firewallRules = firewallConfiguration.rules.enumerated().map { index, rule in
            TopologyRuntimeWebAdministrationFirewallRuleStatus(
                id: "rule-\(index)",
                source: "\(rule.sourceIPAddress)/\(rule.sourceSubnetMask)",
                destination: "\(rule.destinationIPAddress)/\(rule.destinationSubnetMask)",
                protocolName: rule.protocolType.javaLabel,
                port: rule.port == TopologyFirewallRule.allPorts ? "*" : String(rule.port),
                action: rule.action.javaLabel
            )
        }
        let firewall = TopologyRuntimeWebAdministrationFirewallStatus(
            isActive: firewallConfiguration.isActive,
            defaultPolicy: firewallConfiguration.defaultPolicy.javaLabel,
            dropsICMP: firewallConfiguration.dropICMP,
            filtersSYNSegmentsOnly: firewallConfiguration.filterSYNSegmentsOnly,
            filtersUDP: firewallConfiguration.filterUDP,
            rules: firewallRules
        )

        return TopologyRuntimeWebAdministrationSnapshot(
            deviceName: node.displayName,
            deviceKind: node.kind.rawValue,
            uptimeMilliseconds: networkRuntime.state.currentTimeMilliseconds,
            interfaces: interfaces,
            routes: routes,
            dhcp: dhcp,
            natMappings: natMappings,
            portForwards: portForwards,
            firewall: firewall
        )
    }

    /// Renders a router/gateway administration request from the current state.
    /// Returns nil for non-router/gateway nodes so callers cannot accidentally expose a
    /// generic device as an administration endpoint.
    func runtimeWebAdministrationResponse(
        for nodeID: UUID,
        request: TopologyRuntimeWebAdministrationRequest
    ) -> TopologyRuntimeWebAdministrationResponse? {
        guard let snapshot = runtimeWebAdministrationSnapshot(for: nodeID) else { return nil }
        let policy = runtimeWebAdministrationConfigurationsByNodeID[nodeID]?.accessPolicy
            ?? TopologyRuntimeWebAdministrationAccessPolicy()
        return TopologyRuntimeWebAdministrationRenderer.render(
            request: request,
            policy: policy,
            snapshot: snapshot
        )
    }
}

struct TopologyEditorState: Equatable {
    var graph = TopologyGraph()
    var selectedNodeIDs: Set<UUID> = []
    var selectedLinkIDs: Set<UUID> = []
    var workspaceMode: TopologyWorkspaceMode = .design
    var documentationTool: TopologyDocumentationTool = .select
    var documentationItems: [TopologyDocumentationItem] = []
    var selectedDocumentationItemID: UUID?
    var activeTool: TopologyEditorToolMode = .select
    var pendingConnection: TopologyConnectionDraft?
    var simulationPhase: TopologySimulationPhase = .stopped
    var simulationTick: UInt64 = 0
    var networkRuntime = TopologyNetworkRuntimeEngine()
    var lastRuntimeEvent: TopologyRuntimeEvent?
    var lastRuntimeFault: TopologyRuntimeFault?
    var openedRuntimeDeviceID: UUID?
    var runtimeDeviceConfigurations: [UUID: TopologyRuntimeDeviceConfiguration] = [:]
    var switchConfigurationsByNodeID: [UUID: TopologySwitchConfiguration] = [:]
    var remoteLinkConfigurationsByNodeID: [UUID: TopologyRemoteLinkConfiguration] = [:]
    var hostWirelessConfigurationsByNodeID: [UUID: TopologyHostWirelessConfiguration] = [:]
    var runtimeInterfaceConfigurations: [TopologyRuntimeInterfaceKey: TopologyRuntimeInterfaceConfiguration] = [:]
    var runtimeManualRoutesByNodeID: [UUID: [TopologyRuntimeManualRoute]] = [:]
    var runtimeRIPEnabledByNodeID: [UUID: Bool] = [:]
    var runtimeDHCPClientConfigurationsByNodeID: [UUID: TopologyDHCPClientConfiguration] = [:]
    var runtimeDHCPServerConfigurationsByNodeID: [UUID: TopologyDHCPServerConfiguration] = [:]
    var runtimeFirewallConfigurationsByNodeID: [UUID: TopologyFirewallConfiguration] = [:]
    var runtimePortForwardingRowsByNodeID: [UUID: [TopologyGatewayPortForwardingRow]] = [:]
    var runtimeDHCPLeaseByNodeID: [UUID: TopologyRuntimeDeviceConfiguration] = [:]
    var runtimeDNSServerConfigurationsByNodeID: [UUID: TopologyRuntimeDNSServerConfiguration] = [:]
    var runtimeDNSServerSocketIDByNodeID: [UUID: UUID] = [:]
    var runtimeDNSCacheByNodeID: [UUID: [String: TopologyRuntimeDNSCacheEntry]] = [:]
    /// Transient per-client cache for A/MX/NS answers, including recursive dependencies and TTLs.
    var runtimeTypedDNSResolverCacheByNodeID: [UUID: TopologyDNSResolverCache] = [:]
    var runtimeWebServerByNodeID: [UUID: TopologyRuntimeServiceProcessState] = [:]
    /// Persisted HTTP server configuration; the running listener and request log remain transient.
    var runtimeWebServerConfigurationsByNodeID: [UUID: TopologyRuntimeWebServerConfiguration] = [:]
    /// Persisted router/gateway HTTP administration listener and access configuration.
    var runtimeWebAdministrationConfigurationsByNodeID: [UUID: TopologyRuntimeWebAdministrationConfiguration] = [:]
    /// Transient router/gateway administration listener process state.
    var runtimeWebAdministrationByNodeID: [UUID: TopologyRuntimeServiceProcessState] = [:]
    /// Transient router/gateway administration listener socket identifiers.
    var runtimeWebAdministrationSocketIDByNodeID: [UUID: UUID] = [:]
    /// Compatibility bridge for call sites that still read or replace access policies directly.
    var runtimeWebAdministrationPoliciesByNodeID: [UUID: TopologyRuntimeWebAdministrationAccessPolicy] {
        get {
            runtimeWebAdministrationConfigurationsByNodeID.mapValues(\.accessPolicy)
        }
        set {
            let existingConfigurations = runtimeWebAdministrationConfigurationsByNodeID
            runtimeWebAdministrationConfigurationsByNodeID = newValue.reduce(into: [:]) { result, entry in
                result[entry.key] = TopologyRuntimeWebAdministrationConfiguration(
                    port: existingConfigurations[entry.key]?.port
                        ?? TopologyRuntimeWebAdministrationConfiguration.defaultPort,
                    accessPolicy: entry.value
                )
            }
        }
    }
    /// Last rendered administration response per router/gateway. This is transient request state.
    var runtimeWebAdministrationResponsesByNodeID: [UUID: TopologyRuntimeWebAdministrationResponse] = [:]
    /// Persisted browser origin defaults; TCP sessions, response body, and history are transient.
    var runtimeWebBrowserConfigurationsByNodeID: [UUID: TopologyRuntimeWebBrowserConfiguration] = [:]
    var runtimeWebServerRequestLogsByNodeID: [UUID: [TopologyRuntimeWebServerRequestLogEntry]] = [:]
    var runtimeWebBrowserStateByNodeID: [UUID: TopologyRuntimeWebBrowserState] = [:]
    var runtimeEchoServerByNodeID: [UUID: TopologyRuntimeServiceProcessState] = [:]
    var runtimeWebServerSocketIDByNodeID: [UUID: UUID] = [:]
    var runtimeEchoServerSocketIDByNodeID: [UUID: UUID] = [:]
    var runtimeEchoServerUDPSocketIDByNodeID: [UUID: UUID] = [:]
    var runtimeEchoServerServiceStateByNodeID: [UUID: TopologyRuntimeEchoServerServiceState] = [:]
    var runtimeSimpleClientByNodeID: [UUID: TopologyRuntimeSimpleClientState] = [:]
    /// Persisted Email Client accounts, folders, and deterministic message state.
    var runtimeEmailClientConfigurationsByNodeID: [UUID: TopologyRuntimeEmailClientConfiguration] = [:]
    /// Persisted Email Server domain, accounts, and mailboxes.
    var runtimeEmailServerConfigurationsByNodeID: [UUID: TopologyRuntimeEmailServerConfiguration] = [:]
    /// Transient Email Client sockets, protocol progress, and bounded logs.
    var runtimeEmailClientStateByNodeID: [UUID: TopologyRuntimeEmailClientState] = [:]
    /// Transient SMTP/POP3 listeners, sessions, and bounded logs.
    var runtimeEmailServerProcessesByNodeID: [UUID: TopologyRuntimeEmailServerProcessState] = [:]
    /// Persisted Gnutella maximum-peer configuration mirrored into the per-device VFS.
    var runtimeGnutellaConfigurationsByNodeID: [UUID: TopologyRuntimeGnutellaConfiguration] = [:]
    /// Transient Gnutella listener, peer list, search results, and bounded logs.
    var runtimeGnutellaSessionsByNodeID: [UUID: TopologyRuntimeGnutellaSessionState] = [:]
    /// Transient Foundation-only Gnutella protocol cores.
    var runtimeGnutellaCoresByNodeID: [UUID: TopologyGnutellaPeerCore] = [:]
    /// Monotonic per-node epochs keep request GUIDs unique across local core restarts.
    var runtimeGnutellaRestartEpochByNodeID: [UUID: UInt64] = [:]
    /// Transient adapters that keep the Gnutella core synchronized with the persisted VFS.
    var runtimeGnutellaFileStoresByNodeID: [UUID: TopologyGnutellaVirtualFileSystemAdapter] = [:]
    var runtimeInstalledProgramsByNodeID: [UUID: Set<TopologyRuntimeInstallableProgram>] = [:]
    var runtimeActiveProgramByNodeID: [UUID: TopologyRuntimeInstallableProgram] = [:]
    /// Project-scoped declarative protocol applications; Java's fixed software enum remains unchanged.
    var protocolApplicationDefinitionsByID: [UUID: TopologyProtocolApplicationDefinition] = [:]
    /// Persisted per-PC/Notebook installation references to project-scoped definitions.
    var runtimeInstalledProtocolApplicationIDsByNodeID: [UUID: Set<UUID>] = [:]
    /// Active custom desktop windows are transient and mutually exclusive with built-in active windows.
    var runtimeActiveProtocolApplicationIDByNodeID: [UUID: UUID] = [:]
    /// Custom client/server sockets and logs are transient runtime state.
    var runtimeProtocolApplicationClients: [TopologyProtocolApplicationRuntimeKey: TopologyProtocolApplicationClientState] = [:]
    var runtimeProtocolApplicationServers: [TopologyProtocolApplicationRuntimeKey: TopologyProtocolApplicationServerState] = [:]
    var runtimeConsoleEntriesByNodeID: [UUID: [String]] = [:]
    /// Transient terminal working directory; Java Terminal keeps this per device and it is not project data.
    var runtimeWorkingDirectoryByNodeID: [UUID: String] = [:]
    var virtualFileSystemsByNodeID: [UUID: TopologyVirtualFileSystem] = [:]
    var runtimeFileExplorerSelectionByNodeID: [UUID: String] = [:]
    var runtimeImageViewerSelectionByNodeID: [UUID: String] = [:]
    var runtimeTextEditorSelectionByNodeID: [UUID: String] = [:]
    var runtimeTextEditorDraftByNodeID: [UUID: String] = [:]
    var lastPingEvent: TopologyRuntimeEvent?
    var lastPingFault: TopologyRuntimeFault?
    var viewport = ViewportTransform.identity
    var persistenceRevision: UInt64 = 0
    var lastPersistedRevision: UInt64 = 0
    var lastPersistenceSaveAt: Date?
    var lastPersistenceLoadAt: Date?
    var lastPersistenceError: TopologyPersistenceFailure?
    var lastRecoveryMessage: String?
    var lastRecoveryAt: Date?
    var lastRecoverySucceeded: Bool?
    var isRecoveryNoticeVisible = false
    var lastValidationError: TopologyValidationErrorCode?
    var lastAction: String?
    var lastActionAt: Date?
    var lastInteractionMode: String?
    var transitionCount = 0

    mutating func recordPersistenceLoad(at date: Date = Date()) {
        lastPersistenceLoadAt = date
        lastPersistedRevision = persistenceRevision
        lastPersistenceError = nil
    }

    mutating func recordPersistenceSave(revision: UInt64, at date: Date = Date()) {
        lastPersistedRevision = max(lastPersistedRevision, revision)
        lastPersistenceSaveAt = date
        lastPersistenceError = nil
    }

    mutating func recordPersistenceFailure(
        operation: TopologyProjectPersistenceOperation,
        code: TopologyProjectPersistenceErrorCode,
        detail: String,
        occurredAt: Date = Date()
    ) {
        lastPersistenceError = TopologyPersistenceFailure(
            operation: operation,
            code: code,
            detail: detail,
            occurredAt: occurredAt
        )
    }

    mutating func dismissPersistenceError() {
        lastPersistenceError = nil
    }

    mutating func recordRecoverySuccess(message: String, at date: Date = Date()) {
        lastRecoveryMessage = message
        lastRecoveryAt = date
        lastRecoverySucceeded = true
        isRecoveryNoticeVisible = true
    }

    mutating func recordRecoveryFailure(message: String, at date: Date = Date()) {
        lastRecoveryMessage = message
        lastRecoveryAt = date
        lastRecoverySucceeded = false
        isRecoveryNoticeVisible = true
    }

    mutating func dismissRecoveryNotice() {
        isRecoveryNoticeVisible = false
    }
}

extension TopologyEditorState {
    mutating func seedJavaRuntimeInterfaceDefaults(for node: TopologyNode) {
        for (key, configuration) in TopologyRuntimeInterfaceDefaults.configurations(for: node)
        where runtimeInterfaceConfigurations[key] == nil {
            runtimeInterfaceConfigurations[key] = configuration
        }
        if node.kind == .networkSwitch, switchConfigurationsByNodeID[node.id] == nil {
            switchConfigurationsByNodeID[node.id] = .defaultConfiguration(nodeID: node.id)
        }
        if node.kind == .remoteLink, remoteLinkConfigurationsByNodeID[node.id] == nil {
            let reservedPairIdentifiers = Set(
                remoteLinkConfigurationsByNodeID.values.map {
                    $0.pairIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            )
            remoteLinkConfigurationsByNodeID[node.id] = .defaultConfiguration(
                nodeID: node.id,
                avoiding: reservedPairIdentifiers
            )
        }
        if node.kind.isPCClassEndpoint {
            if virtualFileSystemsByNodeID[node.id] == nil {
                virtualFileSystemsByNodeID[node.id] = .defaultForDevice()
            }
            if runtimeWorkingDirectoryByNodeID[node.id] == nil {
                runtimeWorkingDirectoryByNodeID[node.id] = "/"
            }
        }
    }

    mutating func seedJavaRuntimeInterfaceDefaultsForGraph() {
        for node in graph.nodes {
            seedJavaRuntimeInterfaceDefaults(for: node)
        }
    }

    func wirelessAssociations() -> [TopologyWirelessAssociation] {
        let explicitlyOccupiedPortIDs = Set(graph.links.flatMap { [$0.sourcePortID, $0.targetPortID] })
        var reservedSwitchPortIDs = explicitlyOccupiedPortIDs
        let switches = graph.nodes
            .filter { $0.kind == .networkSwitch }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let hosts = graph.nodes
            .filter { $0.kind.isPCClassEndpoint }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        var associations: [TopologyWirelessAssociation] = []

        for host in hosts {
            guard let configuration = hostWirelessConfigurationsByNodeID[host.id],
                  configuration.isEnabled,
                  !configuration.ssid.isEmpty,
                  let hostPort = host.ports.first,
                  !explicitlyOccupiedPortIDs.contains(hostPort.id)
            else { continue }

            guard let accessPoint = switches.first(where: { node in
                let switchConfiguration = switchConfigurationsByNodeID[node.id]
                    ?? .defaultConfiguration(nodeID: node.id)
                return switchConfiguration.ssid == configuration.ssid
                    && node.ports.contains(where: { !reservedSwitchPortIDs.contains($0.id) })
            }), let switchPort = accessPoint.ports.first(where: { !reservedSwitchPortIDs.contains($0.id) })
            else { continue }

            reservedSwitchPortIDs.insert(switchPort.id)
            associations.append(
                TopologyWirelessAssociation(
                    hostNodeID: host.id,
                    hostPortID: hostPort.id,
                    switchNodeID: accessPoint.id,
                    switchPortID: switchPort.id,
                    ssid: configuration.ssid
                )
            )
        }

        return associations
    }
}

extension TopologyEditorState {
    mutating func synchronizeRuntimeDNSConfigurationFromHostsFile(
        nodeID: UUID,
        clearWhenMissing: Bool = false
    ) {
        guard runtimeInstalledProgramsByNodeID[nodeID]?.contains(.dnsServer) == true else { return }
        let text = virtualFileSystemsByNodeID[nodeID].flatMap { try? $0.textFile(at: TopologyRuntimeDNSHostsFile.path) }
        guard text != nil || clearWhenMissing else { return }
        let typedRecords = text.map { TopologyRuntimeDNSHostsFile.typedRecords(from: $0) } ?? []
        let previous = runtimeDNSServerConfigurationsByNodeID[nodeID]
        guard previous?.typedRecords != typedRecords else { return }
        runtimeDNSServerConfigurationsByNodeID[nodeID] = TopologyRuntimeDNSServerConfiguration(
            typedRecords: typedRecords,
            recursiveResolutionEnabled: previous?.recursiveResolutionEnabled ?? false,
            forwardingServerIPAddress: previous?.forwardingServerIPAddress
        )
        invalidateRuntimeDNSCache()
    }

    mutating func mirrorRuntimeDNSConfigurationToHostsFile(nodeID: UUID) throws {
        let records = runtimeDNSServerConfigurationsByNodeID[nodeID]?.typedRecords ?? []
        var fileSystem = virtualFileSystemsByNodeID[nodeID] ?? .defaultForDevice()
        if !fileSystem.contains(TopologyRuntimeDNSHostsFile.directoryPath) {
            try fileSystem.createDirectory(at: TopologyRuntimeDNSHostsFile.directoryPath, recursive: true)
        }
        let existingText = (try? fileSystem.textFile(at: TopologyRuntimeDNSHostsFile.path)) ?? ""
        try fileSystem.writeTextFile(
            at: TopologyRuntimeDNSHostsFile.path,
            text: TopologyRuntimeDNSHostsFile.text(mirroringTypedRecords: records, preserving: existingText)
        )
        var candidateFileSystems = virtualFileSystemsByNodeID
        candidateFileSystems[nodeID] = fileSystem
        try TopologyVirtualFileSystem.validateProjectQuotas(candidateFileSystems)
        virtualFileSystemsByNodeID = candidateFileSystems
    }

    mutating func resolveRuntimeHostname(
        nodeID: UUID,
        hostname: String,
        timeoutMilliseconds: UInt64 = TopologyNetworkRuntimeEngine.dnsDefaultTimeoutMilliseconds
    ) -> TopologyRuntimeDNSResolutionResult {
        guard simulationPhase == .running else { return .simulationStopped }
        let normalizedHostname = hostname.lowercased()
        guard let configuredServerIPAddress = runtimeDeviceConfigurations[nodeID]?.dnsServer
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !configuredServerIPAddress.isEmpty, configuredServerIPAddress != "0.0.0.0"
        else { return .missingServerConfiguration }

        if let cached = runtimeDNSCacheByNodeID[nodeID]?[normalizedHostname],
           cached.serverIPAddress == configuredServerIPAddress,
           cached.expiresAtMilliseconds > networkRuntime.state.currentTimeMilliseconds {
            networkRuntime.recordDNSCacheHit(
                nodeID: nodeID,
                hostname: normalizedHostname,
                serverIPAddress: configuredServerIPAddress,
                targetIPAddress: cached.targetIPAddress
            )
            if let targetIPAddress = cached.targetIPAddress {
                return .success(
                    record: TopologyRuntimeDNSRecord(
                        hostname: normalizedHostname,
                        targetIPAddress: targetIPAddress
                    ),
                    serverIPAddress: configuredServerIPAddress,
                    cached: true
                )
            }
            return .nxdomain(
                hostname: normalizedHostname,
                serverIPAddress: configuredServerIPAddress,
                cached: true
            )
        }

        runtimeDNSCacheByNodeID[nodeID]?.removeValue(forKey: normalizedHostname)
        let result = resolveRuntimeDNSQuestion(
            nodeID: nodeID, hostname: normalizedHostname, recordType: .address,
            timeoutMilliseconds: timeoutMilliseconds
        )
        let resolution: TopologyRuntimeDNSResolutionResult
        switch result {
        case .success(let answer):
            guard case .address(let address)? = answer.records.first(where: { $0.type == .address })?.data
            else {
                resolution = .nxdomain(
                    hostname: normalizedHostname,
                    serverIPAddress: configuredServerIPAddress,
                    cached: answer.trace.cacheHit
                )
                break
            }
            resolution = .success(
                record: TopologyRuntimeDNSRecord(
                    hostname: normalizedHostname, targetIPAddress: address.rawValue
                ),
                serverIPAddress: configuredServerIPAddress,
                cached: answer.trace.cacheHit
            )
        case .nameError, .noData:
            resolution = .nxdomain(
                hostname: normalizedHostname,
                serverIPAddress: configuredServerIPAddress,
                cached: result.trace.cacheHit
            )
        case .failure(let failure, _):
            switch failure {
            case .serverUnavailable(let serverIPAddress):
                resolution = .unreachable(serverIPAddress: serverIPAddress)
            case .serverTimedOut(let serverIPAddress):
                resolution = .timeout(serverIPAddress: serverIPAddress)
            case .invalidStartingServerAddress:
                resolution = .unreachable(serverIPAddress: configuredServerIPAddress)
            case .referralMissingAddress, .loopDetected, .hopLimitExceeded,
                    .responseLimitExceeded, .responseRecordLimitExceeded:
                resolution = .timeout(serverIPAddress: configuredServerIPAddress)
            }
        }

        simulationTick = networkRuntime.state.currentTimeMilliseconds
        let expiresAt: UInt64
        switch resolution {
        case let .success(record, _, false):
            expiresAt = simulationTick &+ TopologyNetworkRuntimeEngine.dnsPositiveCacheTTLMilliseconds
            runtimeDNSCacheByNodeID[nodeID, default: [:]][normalizedHostname] = TopologyRuntimeDNSCacheEntry(
                hostname: normalizedHostname,
                targetIPAddress: record.targetIPAddress,
                serverIPAddress: configuredServerIPAddress,
                expiresAtMilliseconds: expiresAt
            )
        case .nxdomain(_, _, false):
            expiresAt = simulationTick &+ TopologyNetworkRuntimeEngine.dnsNegativeCacheTTLMilliseconds
            runtimeDNSCacheByNodeID[nodeID, default: [:]][normalizedHostname] = TopologyRuntimeDNSCacheEntry(
                hostname: normalizedHostname,
                targetIPAddress: nil,
                serverIPAddress: configuredServerIPAddress,
                expiresAtMilliseconds: expiresAt
            )
        case .success, .nxdomain, .unreachable, .timeout, .missingServerConfiguration, .simulationStopped:
            break
        }
        return resolution
    }

    /// Resolves an A, MX, or NS question through running DNS services on the simulated network.
    /// The pure resolver owns deterministic record/referral selection; each consultation is gated
    /// by a real UDP exchange so routing, service state, firewall/NAT behavior, and packet loss apply.
    mutating func resolveRuntimeDNSQuestion(
        nodeID: UUID,
        hostname: String,
        recordType: TopologyDNSRecordType,
        timeoutMilliseconds: UInt64 = TopologyNetworkRuntimeEngine.dnsDefaultTimeoutMilliseconds
    ) -> TopologyDNSResolverResult {
        let emptyTrace = TopologyDNSResolutionTrace(
            consultedServerIPAddresses: [], hopCount: 0, responseCount: 0, cacheHit: false
        )
        guard simulationPhase == .running else {
            guard TopologyDNSQuestion(name: hostname, type: recordType) != nil else {
                return .failure(.invalidStartingServerAddress(hostname), trace: emptyTrace)
            }
            return .failure(.serverUnavailable("simulationStopped"), trace: emptyTrace)
        }
        guard let serverIPAddress = runtimeDeviceConfigurations[nodeID]?.dnsServer
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !serverIPAddress.isEmpty, serverIPAddress != "0.0.0.0",
              let question = TopologyDNSQuestion(name: hostname, type: recordType)
        else {
            return .failure(.serverUnavailable("missingConfiguration"), trace: emptyTrace)
        }

        for serverNodeID in runtimeInstalledProgramsByNodeID.keys
        where runtimeInstalledProgramsByNodeID[serverNodeID]?.contains(.dnsServer) == true {
            synchronizeRuntimeDNSConfigurationFromHostsFile(nodeID: serverNodeID)
        }

        var serverNodeIDByIPAddress: [String: UUID] = [:]
        let runningServerNodeIDs = runtimeDNSServerSocketIDByNodeID.keys.sorted {
            $0.uuidString < $1.uuidString
        }
        let servers = runningServerNodeIDs.reduce(
            into: [String: TopologyDNSServerSnapshot]()
        ) { partialResult, serverNodeID in
            let configuration = runtimeDNSServerConfigurationsByNodeID[serverNodeID]
                ?? TopologyRuntimeDNSServerConfiguration()
            guard networkRuntime.isDNSServerRunning(nodeID: serverNodeID),
                  let ipAddress = runtimeDeviceConfigurations[serverNodeID]?.ipAddress,
                  let snapshot = TopologyDNSServerSnapshot(
                    ipAddress: ipAddress,
                    records: configuration.typedRecords,
                    recursiveResolutionEnabled: configuration.recursiveResolutionEnabled,
                    forwardingServerIPAddress: configuration.forwardingServerIPAddress
                  )
            else { return }
            partialResult[ipAddress] = snapshot
            serverNodeIDByIPAddress[ipAddress] = serverNodeID
        }

        var resolverCache = runtimeTypedDNSResolverCacheByNodeID.removeValue(forKey: nodeID)
            ?? TopologyDNSResolverCache()
        let result = TopologyDNSResolver().resolve(
            question,
            startingAt: serverIPAddress,
            serversByIPAddress: servers,
            nowMilliseconds: networkRuntime.state.currentTimeMilliseconds,
            cache: &resolverCache,
            canConsultServer: { sourceServerIPAddress, destinationServerIPAddress, question in
                let sourceNodeID: UUID
                if let sourceServerIPAddress {
                    guard let recursiveSourceNodeID = serverNodeIDByIPAddress[sourceServerIPAddress.rawValue]
                    else { return .unreachable }
                    sourceNodeID = recursiveSourceNodeID
                } else {
                    sourceNodeID = nodeID
                }
                return networkRuntime.consultDNSServerWithResult(
                    clientNodeID: sourceNodeID,
                    serverIPAddress: destinationServerIPAddress.rawValue,
                    question: question,
                    timeoutMilliseconds: timeoutMilliseconds
                )
            }
        )
        runtimeTypedDNSResolverCacheByNodeID[nodeID] = resolverCache
        simulationTick = networkRuntime.state.currentTimeMilliseconds
        return result
    }

    func displayLabel(for node: TopologyNode) -> String {
        guard node.kind.isPCClassEndpoint else { return node.displayName }
        let activeIPCandidates = [
            runtimeDHCPLeaseByNodeID[node.id]?.ipAddress,
            runtimeDeviceConfigurations[node.id]?.ipAddress,
        ]
        let ipAddress = activeIPCandidates.lazy.compactMap { candidate -> String? in
            guard let normalized = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  TopologyRuntimeDNSHostsFile.isValidIPv4Address(normalized)
            else { return nil }
            return normalized
        }.first
        let macAddress = node.ports.first?.effectiveMACAddress

        switch node.hostLabelPolicy {
        case .manual:
            return node.displayName
        case .ipAddress:
            return ipAddress ?? node.displayName
        case .macAddress:
            return macAddress ?? node.displayName
        case .ipAndMAC:
            if let ipAddress, let macAddress { return "\(ipAddress) (\(macAddress))" }
            return ipAddress ?? macAddress ?? node.displayName
        }
    }

    mutating func invalidateRuntimeDNSCache(hostname: String? = nil) {
        if let hostname {
            let normalizedHostname = hostname.lowercased()
            for nodeID in Array(runtimeDNSCacheByNodeID.keys) {
                runtimeDNSCacheByNodeID[nodeID]?.removeValue(forKey: normalizedHostname)
            }
            if let name = TopologyDNSName(rawValue: normalizedHostname) {
                for nodeID in Array(runtimeTypedDNSResolverCacheByNodeID.keys) {
                    runtimeTypedDNSResolverCacheByNodeID[nodeID]?.invalidate(.names([name]))
                }
            }
        } else {
            runtimeDNSCacheByNodeID.removeAll()
            runtimeTypedDNSResolverCacheByNodeID.removeAll()
        }
    }
}

enum TopologyEditorAction: Equatable {
    case placeNode(kind: TopologyNodeKind, at: CGPoint, nodeID: UUID?)
    case selectSingleNode(nodeID: UUID?)
    case selectSingleLink(linkID: UUID?)
    case selectNodes(in: CGRect?)
    case clearSelection
    case deleteSelection
    case deleteLink(linkID: UUID?)
    case cancelConnection
    case setWorkspaceMode(mode: TopologyWorkspaceMode)
    case setDocumentationTool(tool: TopologyDocumentationTool)
    case createDocumentationItem(kind: TopologyDocumentationItemKind, at: CGPoint, itemID: UUID?)
    case selectDocumentationItem(itemID: UUID?)
    case moveSelectedDocumentationItem(delta: CGSize?)
    case updateDocumentationItem(item: TopologyDocumentationItem?)
    case deleteSelectedDocumentationItem
    case addRouterInterface(nodeID: UUID?, portID: UUID?)
    case removeRouterInterface(nodeID: UUID?, portID: UUID?, confirmed: Bool?)
    case setActiveTool(mode: TopologyEditorToolMode)
    case saveDesignDeviceConfiguration(
        nodeID: UUID?,
        displayName: String?,
        hostLabelPolicy: TopologyHostLabelPolicy?,
        deviceConfiguration: TopologyRuntimeDeviceConfiguration?,
        interfaceConfigurations: [TopologyDesignInterfaceConfiguration]?,
        switchConfiguration: TopologySwitchConfiguration?,
        remoteLinkConfiguration: TopologyRemoteLinkConfiguration?,
        hostWirelessConfiguration: TopologyHostWirelessConfiguration?
    )
    case startConnection(nodeID: UUID?, portID: UUID?)
    case completeConnection(nodeID: UUID?, portID: UUID?)
    case startSimulation
    case stopSimulation
    case setSimulationSpeed(percent: Int?)
    case setGlobalPacketLoss(enabled: Bool?)
    case simulationTick(step: UInt64?)
    case simulationFault(code: String?, message: String?)
    case setLANRemoteLinkConnectionState(nodeID: UUID?, connectionState: TopologyRemoteLinkLANConnectionState?)
    case completeLANRemoteLinkOutboundFrame(
        nodeID: UUID?,
        transmissionID: UInt64?,
        result: TopologyRemoteLinkLANSendResult?
    )
    case receiveLANRemoteLinkFrame(nodeID: UUID?, frame: TopologyRemoteLinkWireFrame?)
    case openRuntimeDevice(nodeID: UUID?)
    case closeRuntimeDevice
    case saveRuntimeDeviceIP(nodeID: UUID?, ipAddress: String?, subnetMask: String?)
    case saveRuntimeDeviceConfiguration(nodeID: UUID?, ipAddress: String?, subnetMask: String?, defaultGateway: String?)
    case saveRuntimeInterfaceConfiguration(nodeID: UUID?, portID: UUID?, ipAddress: String?, subnetMask: String?)
    case saveRuntimeManualRoutes(nodeID: UUID?, routes: [TopologyRuntimeManualRoute]?)
    case setRuntimeRIPEnabled(nodeID: UUID?, enabled: Bool?)
    case setRuntimeDHCPClientEnabled(nodeID: UUID?, enabled: Bool?)
    case saveRuntimeDHCPServerConfiguration(nodeID: UUID?, configuration: TopologyDHCPServerConfiguration?)
    case saveRuntimeFirewallConfiguration(nodeID: UUID?, configuration: TopologyFirewallConfiguration?)
    case resetRuntimeNATTable(nodeID: UUID?)
    case clearRuntimeSwitchSAT(nodeID: UUID?)
    case resetRuntimePacketCapture(nodeID: UUID?, interfaceID: UUID?)
    case saveRuntimePortForwardingRows(nodeID: UUID?, rows: [TopologyGatewayPortForwardingRow]?)
    case saveRuntimeWebAdministrationConfiguration(nodeID: UUID?, configuration: TopologyRuntimeWebAdministrationConfiguration?)
    case saveRuntimeWebAdministrationPolicy(nodeID: UUID?, policy: TopologyRuntimeWebAdministrationAccessPolicy?)
    case runtimeWebAdministrationRequest(nodeID: UUID?, request: TopologyRuntimeWebAdministrationRequest?)
    case installRuntimeProgram(nodeID: UUID?, program: TopologyRuntimeInstallableProgram?)
    case uninstallRuntimeProgram(nodeID: UUID?, program: TopologyRuntimeInstallableProgram?)
    case launchRuntimeProgram(nodeID: UUID?, program: TopologyRuntimeInstallableProgram?)
    case closeRuntimeProgram(nodeID: UUID?)
    case createProtocolApplication(definition: TopologyProtocolApplicationDefinition?)
    case updateProtocolApplication(definition: TopologyProtocolApplicationDefinition?)
    case deleteProtocolApplication(definitionID: UUID?)
    case installProtocolApplication(nodeID: UUID?, definitionID: UUID?)
    case uninstallProtocolApplication(nodeID: UUID?, definitionID: UUID?)
    case launchProtocolApplication(nodeID: UUID?, definitionID: UUID?)
    case closeProtocolApplication(nodeID: UUID?)
    case runtimeProtocolServerStart(nodeID: UUID?, definitionID: UUID?)
    case runtimeProtocolServerStop(nodeID: UUID?, definitionID: UUID?)
    case runtimeProtocolClientSend(nodeID: UUID?, definitionID: UUID?, destinationIPAddress: String?, templateID: UUID?)
    case runtimeDHCPLease(nodeID: UUID?, ipAddress: String?, subnetMask: String?)
    case runtimeDHCPRelease(nodeID: UUID?)
    case runtimeDNSStart(nodeID: UUID?)
    case runtimeDNSStop(nodeID: UUID?)
    case runtimeDNSAddRecord(nodeID: UUID?, hostname: String?, targetIPAddress: String?)
    case runtimeDNSAddTypedRecord(nodeID: UUID?, hostname: String?, recordType: TopologyDNSRecordType?, target: String?, ttlSeconds: UInt32?)
    case runtimeDNSRemoveRecord(nodeID: UUID?, hostname: String?)
    case runtimeDNSRemoveTypedRecord(nodeID: UUID?, hostname: String?, recordType: TopologyDNSRecordType?, target: String?)
    case runtimeDNSSetRecursion(nodeID: UUID?, enabled: Bool?, forwardingServerIPAddress: String?)
    case runtimeDNSResolveRecord(nodeID: UUID?, hostname: String?)
    case runtimeDNSResolveTypedRecord(nodeID: UUID?, hostname: String?, recordType: TopologyDNSRecordType?)
    case saveRuntimeWebServerConfiguration(nodeID: UUID?, configuration: TopologyRuntimeWebServerConfiguration?)
    case runtimeWebStart(nodeID: UUID?, port: String?)
    case runtimeWebStop(nodeID: UUID?)
    case runtimeWebRestart(nodeID: UUID?, port: String?)
    case runtimeWebAdministrationStart(nodeID: UUID?, port: String?)
    case runtimeWebAdministrationStop(nodeID: UUID?)
    case runtimeWebBrowserNavigate(nodeID: UUID?, address: String?)
    case runtimeWebBrowserBack(nodeID: UUID?)
    case runtimeWebBrowserForward(nodeID: UUID?)
    case runtimeWebBrowserReset(nodeID: UUID?)
    case runtimeEchoStart(nodeID: UUID?, port: String?)
    case runtimeEchoStop(nodeID: UUID?)
    case runtimeSimpleClientConnect(nodeID: UUID?, destinationIPAddress: String?, port: String?, protocolKind: TopologyRuntimeTransportProtocol?)
    case runtimeSimpleClientSend(nodeID: UUID?, message: String?)
    case runtimeSimpleClientDisconnect(nodeID: UUID?)
    case saveRuntimeEmailClientConfiguration(nodeID: UUID?, configuration: TopologyRuntimeEmailClientConfiguration?)
    case saveRuntimeEmailServerConfiguration(nodeID: UUID?, configuration: TopologyRuntimeEmailServerConfiguration?)
    case saveAndStartRuntimeEmailServer(nodeID: UUID?, configuration: TopologyRuntimeEmailServerConfiguration?)
    case runtimeEmailServerStart(nodeID: UUID?)
    case runtimeEmailServerStop(nodeID: UUID?)
    case runtimeEmailClientSend(nodeID: UUID?, message: TopologyRuntimeEmailMessage?)
    case runtimeEmailClientRetrieve(nodeID: UUID?)
    case runtimeEmailClientDeleteMessages(
        nodeID: UUID?,
        folder: TopologyRuntimeEmailClientFolder?,
        messageIDs: [UInt64]?
    )
    case saveRuntimeGnutellaConfiguration(nodeID: UUID?, configuration: TopologyRuntimeGnutellaConfiguration?)
    case runtimeGnutellaJoin(nodeID: UUID?, bootstrapIPAddress: String?)
    case runtimeGnutellaResetNetwork(nodeID: UUID?)
    case runtimeGnutellaSearch(nodeID: UUID?, searchTerm: String?)
    case runtimeGnutellaClearSearchResults(nodeID: UUID?)
    case runtimeGnutellaDownload(nodeID: UUID?, result: TopologyGnutellaSearchResult?)
    case runtimeFileExplorerSelectEntry(nodeID: UUID?, entryID: String?)
    case runtimeImageViewerSelectImage(nodeID: UUID?, imageID: String?)
    case runtimeTextEditorSelectFile(nodeID: UUID?, path: String?)
    case runtimeTextEditorUpdateDraft(nodeID: UUID?, text: String?)
    case runtimeTextEditorSaveDraft(nodeID: UUID?)
    case runtimeTextEditorResetDraft(nodeID: UUID?)
    case runtimeFileSystemCreateDirectory(nodeID: UUID?, path: String?)
    case runtimeFileSystemCreateTextFile(nodeID: UUID?, path: String?, text: String?)
    case runtimeFileSystemCopyItem(nodeID: UUID?, sourcePath: String?, destinationPath: String?)
    case runtimeFileSystemMoveItem(nodeID: UUID?, sourcePath: String?, destinationPath: String?)
    case runtimeFileSystemRenameItem(nodeID: UUID?, path: String?, newName: String?)
    case runtimeFileSystemDeleteItem(nodeID: UUID?, path: String?, recursive: Bool?)
    case executePing(nodeID: UUID?, command: String?)
    case moveSelectedNodes(delta: CGSize?)
    case panCanvas(delta: CGSize?)
    case zoomCanvas(scaleDelta: CGFloat?, anchor: CGPoint?)
    case setInteractionMode(mode: String?)
    case dismissRecoveryNotice
    case dismissPersistenceError
}
