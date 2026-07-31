import Foundation

// MARK: - Java-observable packet and route models

struct TopologyEthernetFrame: Equatable {
    let identity: UInt64
    let sourceMACAddress: String
    let destinationMACAddress: String
    let payload: TopologyEthernetPayload
}

enum TopologyEthernetPayload: Equatable {
    case arp(TopologyARPPacket)
    case ipv4(TopologyIPv4Packet)
}

enum TopologyARPOperation: String, Equatable {
    case request
    case reply
}

struct TopologyARPPacket: Equatable {
    let operation: TopologyARPOperation
    let senderMACAddress: String
    let senderIPAddress: String
    let targetMACAddress: String
    let targetIPAddress: String
}

enum TopologyIPv4Protocol: Int, Equatable {
    case icmp = 1
    case tcp = 6
    case udp = 17
}

struct TopologyIPv4Packet: Equatable {
    let identity: UInt64
    let senderIPAddress: String
    let receiverIPAddress: String
    let timeToLive: UInt8
    let protocolNumber: TopologyIPv4Protocol
    let payload: TopologyIPv4Payload

    func forwardingClone(decrementingTTLBy amount: UInt8 = 1) -> TopologyIPv4Packet {
        TopologyIPv4Packet(
            identity: identity,
            senderIPAddress: senderIPAddress,
            receiverIPAddress: receiverIPAddress,
            timeToLive: amount >= timeToLive ? 0 : timeToLive - amount,
            protocolNumber: protocolNumber,
            payload: payload
        )
    }
}

indirect enum TopologyIPv4Payload: Equatable {
    case icmp(TopologyICMPMessage)
    case tcp(TopologyTCPSegment)
    case udp(TopologyUDPDatagram)
}

enum TopologyICMPMessageKind: String, Equatable {
    case echoRequest
    case echoReply
    case destinationNetworkUnreachable
    case destinationHostUnreachable
    case timeExceeded
}

struct TopologyICMPMessage: Equatable {
    let kind: TopologyICMPMessageKind
    let identifier: UInt16
    let sequenceNumber: UInt16
    let data: Data
    let embeddedOriginalPacket: TopologyIPv4Packet?

    init(
        kind: TopologyICMPMessageKind,
        identifier: UInt16 = 0,
        sequenceNumber: UInt16 = 0,
        data: Data = Data(),
        embeddedOriginalPacket: TopologyIPv4Packet? = nil
    ) {
        self.kind = kind
        self.identifier = identifier
        self.sequenceNumber = sequenceNumber
        self.data = data
        self.embeddedOriginalPacket = embeddedOriginalPacket
    }
}

struct TopologyTCPFlags: OptionSet, Equatable {
    let rawValue: UInt8

    static let finish = TopologyTCPFlags(rawValue: 1 << 0)
    static let synchronize = TopologyTCPFlags(rawValue: 1 << 1)
    static let reset = TopologyTCPFlags(rawValue: 1 << 2)
    static let push = TopologyTCPFlags(rawValue: 1 << 3)
    static let acknowledgement = TopologyTCPFlags(rawValue: 1 << 4)
}

enum TopologyTCPSocketState: String, CaseIterable, Equatable, Hashable {
    case closed = "CLOSED"
    case listen = "LISTEN"
    case synReceived = "SYN_RCVD"
    case synSent = "SYN_SENT"
    case established = "ESTABLISHED"
    case closeWait = "CLOSE_WAIT"
    case lastAcknowledgement = "LAST_ACK"
    case finishWait1 = "FIN_WAIT_1"
    case finishWait2 = "FIN_WAIT_2"
    case closing = "CLOSING"
    case timeWait = "TIME_WAIT"
}

struct TopologyTCPSegment: Equatable {
    let sourcePort: UInt16
    let destinationPort: UInt16
    let sequenceNumber: UInt32
    let acknowledgementNumber: UInt32
    let flags: TopologyTCPFlags
    let payload: Data
}

struct TopologyUDPDatagram: Equatable {
    let sourcePort: UInt16
    let destinationPort: UInt16
    let payload: Data
}

struct TopologyRuntimeUDPReceivedDatagram: Equatable {
    let senderIPAddress: String
    let receiverIPAddress: String
    let datagram: TopologyUDPDatagram
    let receivedAtMilliseconds: UInt64
}

private enum TopologyRuntimeDNSWireKind: String {
    case query = "QUERY"
    case response = "RESPONSE"
}

private enum TopologyRuntimeDNSResponseCode: String {
    case noError = "NOERROR"
    case nameError = "NXDOMAIN"
}

private struct TopologyRuntimeDNSWireMessage {
    let kind: TopologyRuntimeDNSWireKind
    let transactionID: UInt64
    let hostname: String
    let responseCode: TopologyRuntimeDNSResponseCode?
    let targetIPAddress: String?
}

struct TopologyRuntimeRIPAdvertisementRoute: Equatable {
    let destinationNetwork: String
    let subnetMask: String
    let metric: Int
}

struct TopologyRuntimeRIPAdvertisement: Equatable {
    let senderIPAddress: String
    let publicIPAddress: String
    let infinity: Int
    let timeoutMilliseconds: UInt64
    let routes: [TopologyRuntimeRIPAdvertisementRoute]
}

enum TopologyRuntimeRouteOrigin: String, Equatable {
    case localHost
    case connected
    case localhost
    case manual
    case defaultGateway
    case rip
}

struct TopologyRuntimeRouteRow: Equatable {
    let destinationNetwork: String
    let subnetMask: String
    let nextHop: String
    let interfaceIPAddress: String
    let origin: TopologyRuntimeRouteOrigin
    let isEditable: Bool
    let metric: Int?
    let expiresAtMilliseconds: UInt64?
}

enum TopologyPacketTraceDirection: String, Equatable {
    case inbound
    case outbound
    case local
}

enum TopologyPacketTraceLayer: String, Equatable {
    case application
    case transport
    case network
    case dataLink
    case physical
}

enum TopologyPacketTraceOperation: String, Equatable {
    case created
    case sent
    case received
    case forwarded
    case accepted
    case dropped
    case rewritten
    case retransmitted
    case compatibilityAdapter
}

struct TopologyPacketHeaderField: Equatable {
    let name: String
    let value: String
}

struct TopologyPacketTraceEvent: Equatable, Identifiable {
    let id: UInt64
    let timeMilliseconds: UInt64
    let frameIdentity: UInt64?
    let packetIdentity: UInt64?
    let nodeID: UUID
    let interfaceID: UUID?
    let direction: TopologyPacketTraceDirection
    let layer: TopologyPacketTraceLayer
    let operation: TopologyPacketTraceOperation
    let beforeHeaders: [TopologyPacketHeaderField]
    let afterHeaders: [TopologyPacketHeaderField]
    let detail: String?
}


enum TopologyPacketCaptureIdentity: Equatable, Hashable {
    case packet(UInt64)
    case frame(UInt64)
    case trace(UInt64)
}

struct TopologyPacketCaptureTab: Equatable, Identifiable {
    let nodeID: UUID
    let interfaceID: UUID
    let interfaceLabel: String
    let ipAddress: String?
    let title: String
    let eventCount: Int

    var id: UUID { interfaceID }
}

struct TopologyPacketMessageRow: Equatable, Identifiable {
    let id: UInt64
    let number: Int
    let timeMilliseconds: UInt64
    let source: String
    let destination: String
    let protocolName: String
    let layerName: String
    let detail: String
    let trace: TopologyPacketTraceEvent

    var exchangeIdentity: TopologyPacketCaptureIdentity {
        if let packetIdentity = trace.packetIdentity { return .packet(packetIdentity) }
        if let frameIdentity = trace.frameIdentity { return .frame(frameIdentity) }
        return .trace(trace.id)
    }
}

struct TopologyPacketLayerPathStep: Equatable, Identifiable {
    let id: UInt64
    let ordinal: Int
    let timeMilliseconds: UInt64
    let nodeID: UUID
    let nodeName: String
    let interfaceID: UUID?
    let interfaceName: String?
    let direction: TopologyPacketTraceDirection
    let layer: TopologyPacketTraceLayer
    let operation: TopologyPacketTraceOperation
    let beforeHeaders: [TopologyPacketHeaderField]
    let afterHeaders: [TopologyPacketHeaderField]
    let detail: String?
}

struct TopologyPacketLayerPath: Equatable {
    let identity: TopologyPacketCaptureIdentity
    let steps: [TopologyPacketLayerPathStep]
}

// MARK: - Runtime snapshots and transient state

struct TopologyNetworkRuntimePortSnapshot: Equatable {
    let id: UUID
    let label: String
}

struct TopologyNetworkRuntimeNodeSnapshot: Equatable {
    let id: UUID
    let kind: TopologyNodeKind
    let ports: [TopologyNetworkRuntimePortSnapshot]
}

struct TopologyNetworkRuntimeLinkSnapshot: Equatable {
    let id: UUID
    let sourceNodeID: UUID
    let sourcePortID: UUID
    let targetNodeID: UUID
    let targetPortID: UUID
}

struct TopologyNetworkRuntimeTopologySnapshot: Equatable {
    let nodes: [TopologyNetworkRuntimeNodeSnapshot]
    let links: [TopologyNetworkRuntimeLinkSnapshot]
    let deviceConfigurations: [UUID: TopologyRuntimeDeviceConfiguration]
    let interfaceConfigurations: [TopologyRuntimeInterfaceKey: TopologyRuntimeInterfaceConfiguration]
    let manualRoutesByNodeID: [UUID: [TopologyRuntimeManualRoute]]
    let ripEnabledByNodeID: [UUID: Bool]
    let dhcpClientConfigurationsByNodeID: [UUID: TopologyDHCPClientConfiguration]
    let dhcpServerConfigurationsByNodeID: [UUID: TopologyDHCPServerConfiguration]
    let firewallConfigurationsByNodeID: [UUID: TopologyFirewallConfiguration]
    let portForwardingRowsByNodeID: [UUID: [TopologyGatewayPortForwardingRow]]
    let switchConfigurationsByNodeID: [UUID: TopologySwitchConfiguration]
    let remoteLinkConfigurationsByNodeID: [UUID: TopologyRemoteLinkConfiguration]
    let hostWirelessConfigurationsByNodeID: [UUID: TopologyHostWirelessConfiguration]

    static let empty = TopologyNetworkRuntimeTopologySnapshot(
        nodes: [],
        links: [],
        deviceConfigurations: [:],
        interfaceConfigurations: [:],
        manualRoutesByNodeID: [:],
        ripEnabledByNodeID: [:],
        dhcpClientConfigurationsByNodeID: [:],
        dhcpServerConfigurationsByNodeID: [:],
        firewallConfigurationsByNodeID: [:],
        portForwardingRowsByNodeID: [:],
        switchConfigurationsByNodeID: [:],
        remoteLinkConfigurationsByNodeID: [:],
        hostWirelessConfigurationsByNodeID: [:]
    )

    init(
        nodes: [TopologyNetworkRuntimeNodeSnapshot],
        links: [TopologyNetworkRuntimeLinkSnapshot],
        deviceConfigurations: [UUID: TopologyRuntimeDeviceConfiguration],
        interfaceConfigurations: [TopologyRuntimeInterfaceKey: TopologyRuntimeInterfaceConfiguration],
        manualRoutesByNodeID: [UUID: [TopologyRuntimeManualRoute]],
        ripEnabledByNodeID: [UUID: Bool] = [:],
        dhcpClientConfigurationsByNodeID: [UUID: TopologyDHCPClientConfiguration] = [:],
        dhcpServerConfigurationsByNodeID: [UUID: TopologyDHCPServerConfiguration] = [:],
        firewallConfigurationsByNodeID: [UUID: TopologyFirewallConfiguration] = [:],
        portForwardingRowsByNodeID: [UUID: [TopologyGatewayPortForwardingRow]] = [:],
        switchConfigurationsByNodeID: [UUID: TopologySwitchConfiguration] = [:],
        remoteLinkConfigurationsByNodeID: [UUID: TopologyRemoteLinkConfiguration] = [:],
        hostWirelessConfigurationsByNodeID: [UUID: TopologyHostWirelessConfiguration] = [:]
    ) {
        self.nodes = nodes.sorted { $0.id.uuidString < $1.id.uuidString }
        self.links = links.sorted { $0.id.uuidString < $1.id.uuidString }
        self.deviceConfigurations = deviceConfigurations
        self.interfaceConfigurations = interfaceConfigurations
        self.manualRoutesByNodeID = manualRoutesByNodeID
        self.ripEnabledByNodeID = ripEnabledByNodeID
        self.dhcpClientConfigurationsByNodeID = dhcpClientConfigurationsByNodeID
        self.dhcpServerConfigurationsByNodeID = dhcpServerConfigurationsByNodeID
        self.firewallConfigurationsByNodeID = firewallConfigurationsByNodeID
        self.portForwardingRowsByNodeID = portForwardingRowsByNodeID
        self.switchConfigurationsByNodeID = switchConfigurationsByNodeID
        self.remoteLinkConfigurationsByNodeID = remoteLinkConfigurationsByNodeID
        self.hostWirelessConfigurationsByNodeID = hostWirelessConfigurationsByNodeID
    }

    init(editorState: TopologyEditorState) {
        self.init(
            nodes: editorState.graph.nodes.map { node in
                TopologyNetworkRuntimeNodeSnapshot(
                    id: node.id,
                    kind: node.kind,
                    ports: node.ports.map { TopologyNetworkRuntimePortSnapshot(id: $0.id, label: $0.label) }
                )
            },
            links: (editorState.graph.links + editorState.wirelessAssociations().map(\.runtimeLink)).map { link in
                TopologyNetworkRuntimeLinkSnapshot(
                    id: link.id,
                    sourceNodeID: link.sourceNodeID,
                    sourcePortID: link.sourcePortID,
                    targetNodeID: link.targetNodeID,
                    targetPortID: link.targetPortID
                )
            },
            deviceConfigurations: editorState.runtimeDeviceConfigurations,
            interfaceConfigurations: editorState.runtimeInterfaceConfigurations,
            manualRoutesByNodeID: editorState.runtimeManualRoutesByNodeID,
            ripEnabledByNodeID: editorState.runtimeRIPEnabledByNodeID,
            dhcpClientConfigurationsByNodeID: editorState.runtimeDHCPClientConfigurationsByNodeID,
            dhcpServerConfigurationsByNodeID: editorState.runtimeDHCPServerConfigurationsByNodeID,
            firewallConfigurationsByNodeID: editorState.runtimeFirewallConfigurationsByNodeID,
            portForwardingRowsByNodeID: editorState.runtimePortForwardingRowsByNodeID,
            switchConfigurationsByNodeID: editorState.switchConfigurationsByNodeID,
            remoteLinkConfigurationsByNodeID: editorState.remoteLinkConfigurationsByNodeID,
            hostWirelessConfigurationsByNodeID: editorState.hostWirelessConfigurationsByNodeID
        )
    }
}

struct TopologyRuntimeARPCacheEntry: Equatable {
    let ipAddress: String
    let macAddress: String
    let updatedAtMilliseconds: UInt64
}

struct TopologySwitchSATEntry: Identifiable, Equatable {
    let macAddress: String
    let portID: UUID
    let portLabel: String
    let updatedAtMilliseconds: UInt64

    var id: String { macAddress }
}

struct TopologyRuntimeNetworkInterface: Equatable {
    let nodeID: UUID
    let portID: UUID
    let index: Int
    let ipAddress: String
    let subnetMask: String
    let defaultGateway: String
    let macAddress: String
}

struct TopologyRuntimeDeliveredIPv4Packet: Equatable {
    let nodeID: UUID
    let interfaceID: UUID
    let packet: TopologyIPv4Packet
}

struct TopologyRuntimeICMPObservation: Equatable {
    let nodeID: UUID
    let interfaceID: UUID?
    let packet: TopologyIPv4Packet
    let message: TopologyICMPMessage
}

enum TopologyIPv4DeliveryResult: Equatable {
    case delivered(packetIdentity: UInt64, nodeID: UUID)
    case icmpError(packetIdentity: UInt64, nodeID: UUID, kind: TopologyICMPMessageKind)
    case dropped(packetIdentity: UInt64, nodeID: UUID?)
}

enum TopologyTCPConnectionResult: Equatable {
    case connected
    case invalidSocket
    case unreachable
    case timedOut
}

enum TopologyRuntimeSocketProtocol: String, Equatable {
    case tcp
    case udp
}

struct TopologyRuntimeSocketRecord: Equatable {
    let id: UUID
    let nodeID: UUID
    let protocolKind: TopologyRuntimeSocketProtocol
    let localIPAddress: String?
    let localPort: UInt16
    var remoteIPAddress: String?
    var remotePort: UInt16?
    var tcpState: TopologyTCPSocketState?
    let parentListenerSocketID: UUID?
}

struct TopologyRuntimeTCPSessionRecord: Equatable {
    let id: UUID
    let socketID: UUID
    var state: TopologyTCPSocketState
    var sendAttempts: Int
    var nextSendSequenceNumber: UInt32
    var lastSentSequenceNumber: UInt32
    var remoteSequenceNumber: UInt32
    var lastAcknowledgedSequenceNumber: UInt32?
    var lastSentSegment: TopologyTCPSegment?
    var receiveAssembly: Data
    var receivedMessages: [Data]
}
struct TopologyRuntimeDHCPOfferRecord: Equatable {
    let clientMACAddress: String
    let offeredIPAddress: String
    let serverNodeID: UUID
    let expiresAtMilliseconds: UInt64
}

struct TopologyRuntimeDHCPLeaseRecord: Equatable {
    let clientMACAddress: String
    let ipAddress: String
    let serverNodeID: UUID
    let expiresAtMilliseconds: UInt64?
}

enum TopologyRuntimeDHCPMessageType: String, Equatable, Hashable {
    case discover = "DHCPDISCOVER"
    case request = "DHCPREQUEST"
    case acknowledgement = "DHCPACK"
    case negativeAcknowledgement = "DHCPNAK"
    case offer = "DHCPOFFER"
    case decline = "DHCPDECLINE"
}

struct TopologyRuntimeDHCPMessage: Equatable {
    let type: TopologyRuntimeDHCPMessageType
    var yourIPAddress: String = "0.0.0.0"
    var clientMACAddress: String?
    var subnetMask: String?
    var routerIPAddress: String?
    var dnsServerIPAddress: String?
    var serverIdentifier: String?
    var requestedIPAddress: String?
}

enum TopologyRuntimeDHCPClientState: String, Equatable {
    case initialize = "INIT"
    case discover = "DISCOVER"
    case validate = "VALIDATE"
    case decline = "DECLINE"
    case request = "REQUEST"
    case assignIP = "ASSIGN_IP"
    case finish = "FINISH"
}

struct TopologyRuntimeDHCPClientStatus: Equatable {
    var state: TopologyRuntimeDHCPClientState
    var errorCount: Int
    var selectedServerIPAddress: String?
    var offeredIPAddress: String?
    var succeeded: Bool
}

struct TopologyRuntimeDHCPClientContext: Equatable {
    let interfaceID: UUID
    let socketID: UUID
    let clientMACAddress: String
    let oldDeviceConfiguration: TopologyRuntimeDeviceConfiguration?
    let oldInterfaceConfiguration: TopologyRuntimeInterfaceConfiguration?
    var selectedOffer: TopologyRuntimeDHCPMessage?
}


struct TopologyRuntimeFirewallDecision: Equatable {
    let packetIdentity: UInt64
    let nodeID: UUID
    let accepted: Bool
    let ruleIndex: Int?
}

enum TopologyRuntimeNATMappingType: String, Equatable {
    case staticEntry = "StaticEntry"
    case dynamicEntry = "DynamicEntry"
    case dynamicEntryFromStatic = "DynamicEnryFromStatic"
}

struct TopologyRuntimeNATMapping: Equatable, Identifiable {
    let id: UUID
    let gatewayNodeID: UUID
    let protocolNumber: TopologyIPv4Protocol
    let remoteIPAddress: String
    let translatedPortOrIdentifier: UInt16
    let lanIPAddress: String
    let lanPortOrIdentifier: UInt16
    let type: TopologyRuntimeNATMappingType
    var updatedAtMilliseconds: UInt64

    var isDynamic: Bool { type != .staticEntry }
}

enum TopologyRemoteLinkRuntimeCondition: Equatable {
    case stopped
    case missingConfiguration
    case disabled
    case unpaired
    case ambiguous(enabledNodeCount: Int)
    case detached(partnerNodeID: UUID)
    case active(partnerNodeID: UUID)
}

struct TopologyRemoteLinkRuntimeStatus: Equatable, Identifiable {
    let nodeID: UUID
    let pairIdentifier: String?
    let latencyMilliseconds: UInt64?
    let isEnabled: Bool
    let localPortID: UUID?
    let isLocalPortAttached: Bool
    let pendingFrameCount: Int
    let condition: TopologyRemoteLinkRuntimeCondition

    var id: UUID { nodeID }
}

enum TopologyRemoteLinkRuntimeDropReason: String, Equatable {
    case missingConfiguration
    case disabled
    case unpaired
    case ambiguousPair
    case duplicateFrame
    case latencyOverflow
    case pairNoLongerActive
    case partnerLocalPortUnavailable
}

enum TopologyRemoteLinkRuntimeEvidenceKind: Equatable {
    case scheduled(deadlineMilliseconds: UInt64, latencyMilliseconds: UInt64)
    case delivered
    case dropped(reason: TopologyRemoteLinkRuntimeDropReason)
}

struct TopologyRemoteLinkRuntimeEvidence: Equatable, Identifiable {
    let id: UInt64
    let timeMilliseconds: UInt64
    let frameIdentity: UInt64
    let nodeID: UUID
    let partnerNodeID: UUID?
    let pairIdentifier: String?
    let kind: TopologyRemoteLinkRuntimeEvidenceKind
}

struct TopologyNetworkRuntimeSpeed: Equatable {
    static let minimumPercent = 1
    static let maximumPercent = 100
    static let defaultPercent = 90
    static let javaMinimumLinkDelayMilliseconds: UInt64 = 5

    let percent: Int

    init(percent: Int = Self.defaultPercent) {
        self.percent = min(Self.maximumPercent, max(Self.minimumPercent, percent))
    }

    var javaDelayFactor: UInt64 {
        UInt64(Self.maximumPercent - percent + 1)
    }

    var linkTransmissionDelayMilliseconds: UInt64 {
        Self.javaMinimumLinkDelayMilliseconds * javaDelayFactor
    }

    func scaledLinkDelay(baseMilliseconds: UInt64) -> UInt64? {
        let (delay, overflowed) = baseMilliseconds.multipliedReportingOverflow(by: javaDelayFactor)
        return overflowed ? nil : delay
    }
}

enum TopologyNetworkRuntimePhase: String, Equatable {
    case stopped
    case running
}

enum TopologyNetworkRuntimeScheduledEventKind: Equatable {
    case parityMarker(String)
    case ripBeacon(nodeID: UUID)
    case dhcpClientStart(nodeID: UUID)
    case dhcpTimeout(nodeID: UUID)
    case tcpTimeout(sessionID: UUID)
    case ethernetLinkDelivery(
        sourceNodeID: UUID,
        targetNodeID: UUID,
        targetPortID: UUID,
        latencyMilliseconds: UInt64,
        frame: TopologyEthernetFrame
    )
    case remoteLinkDelivery(
        sourceNodeID: UUID,
        partnerNodeID: UUID,
        partnerPortID: UUID,
        pairIdentifier: String,
        latencyMilliseconds: UInt64,
        frame: TopologyEthernetFrame
    )
    case natExpirySweep
}

struct TopologyNetworkRuntimeScheduledEvent: Equatable, Identifiable {
    let id: UInt64
    let deadlineMilliseconds: UInt64
    let sequenceNumber: UInt64
    let kind: TopologyNetworkRuntimeScheduledEventKind
}

enum TopologyNetworkRuntimeCompatibilityOperationKind: String, Equatable {
    case terminalCommand
    case applicationOperation
    case socketOperation
}

struct TopologyNetworkRuntimeCompatibilityOperation: Equatable {
    let kind: TopologyNetworkRuntimeCompatibilityOperationKind
    let nodeID: UUID
    let interfaceID: UUID?
    let detail: String
}

struct TopologyNetworkRuntimeScenario: Equatable {
    let name: String
    let seed: UInt64
    let advanceToMilliseconds: UInt64
    let scheduledEvents: [(deadlineMilliseconds: UInt64, kind: TopologyNetworkRuntimeScheduledEventKind)]

    static func == (lhs: TopologyNetworkRuntimeScenario, rhs: TopologyNetworkRuntimeScenario) -> Bool {
        guard
            lhs.name == rhs.name,
            lhs.seed == rhs.seed,
            lhs.advanceToMilliseconds == rhs.advanceToMilliseconds,
            lhs.scheduledEvents.count == rhs.scheduledEvents.count
        else {
            return false
        }

        return zip(lhs.scheduledEvents, rhs.scheduledEvents).allSatisfy { pair in
            pair.0.deadlineMilliseconds == pair.1.deadlineMilliseconds && pair.0.kind == pair.1.kind
        }
    }
}

enum TopologyNetworkRuntimeInput: Equatable {
    case start(
        snapshot: TopologyNetworkRuntimeTopologySnapshot,
        seed: UInt64,
        initialTimeMilliseconds: UInt64
    )
    case stop
    case advance(toMilliseconds: UInt64)
    case schedule(deadlineMilliseconds: UInt64, kind: TopologyNetworkRuntimeScheduledEventKind)
    case compatibilityOperation(TopologyNetworkRuntimeCompatibilityOperation)
}

enum TopologyNetworkRuntimeOutputKind: Equatable {
    case started
    case startIgnoredAlreadyRunning
    case stopped
    case stopIgnoredAlreadyStopped
    case advanced(fromMilliseconds: UInt64, toMilliseconds: UInt64)
    case advanceIgnoredWhileStopped
    case advanceRejectedPastTime
    case scheduleRejectedPastTime(deadlineMilliseconds: UInt64)
    case scheduled(event: TopologyNetworkRuntimeScheduledEvent)
    case fired(event: TopologyNetworkRuntimeScheduledEvent)
    case compatibilityOperationRecorded(TopologyNetworkRuntimeCompatibilityOperation)
}

struct TopologyNetworkRuntimeOutput: Equatable {
    let timeMilliseconds: UInt64
    let kind: TopologyNetworkRuntimeOutputKind
}

struct TopologyNetworkRuntimeState: Equatable {
    var phase: TopologyNetworkRuntimePhase = .stopped
    var currentTimeMilliseconds: UInt64 = 0
    var simulationSpeedPercent = TopologyNetworkRuntimeSpeed.defaultPercent
    var seed: UInt64
    var topologySnapshot: TopologyNetworkRuntimeTopologySnapshot = .empty
    var pendingEvents: [TopologyNetworkRuntimeScheduledEvent] = []
    var packetTraces: [TopologyPacketTraceEvent] = []
    var arpCachesByNodeID: [UUID: [String: TopologyRuntimeARPCacheEntry]] = [:]
    var switchForwardingTablesByNodeID: [UUID: [String: UUID]] = [:]
    var switchForwardingUpdatedAtMillisecondsByNodeID: [UUID: [String: UInt64]] = [:]
    var switchSeenFrameIdentitiesByNodeID: [UUID: Set<UInt64>] = [:]
    var remoteLinkSeenFrameIdentitiesByNodeID: [UUID: Set<UInt64>] = [:]
    var remoteLinkEvidence: [TopologyRemoteLinkRuntimeEvidence] = []
    var deliveredIPv4PacketsByNodeID: [UUID: [TopologyRuntimeDeliveredIPv4Packet]] = [:]
    var icmpObservationsByNodeID: [UUID: [TopologyRuntimeICMPObservation]] = [:]
    var socketsByID: [UUID: TopologyRuntimeSocketRecord] = [:]
    var udpReceiveQueuesBySocketID: [UUID: [TopologyRuntimeUDPReceivedDatagram]] = [:]
    var tcpSessionsByID: [UUID: TopologyRuntimeTCPSessionRecord] = [:]
    var tcpAcceptedSocketIDsByListenerID: [UUID: [UUID]] = [:]
    var ripTablesByNodeID: [UUID: [TopologyRuntimeRouteRow]] = [:]
    var dhcpOffersByIPAddress: [String: TopologyRuntimeDHCPOfferRecord] = [:]
    var dhcpLeasesByIPAddress: [String: TopologyRuntimeDHCPLeaseRecord] = [:]
    var dhcpBlacklistByServerNodeID: [UUID: [String: UInt64]] = [:]
    var dhcpLastOfferedAddressByServerNodeID: [UUID: String] = [:]
    var dhcpServerSocketIDsByNodeID: [UUID: UUID] = [:]
    var dhcpClientStatusesByNodeID: [UUID: TopologyRuntimeDHCPClientStatus] = [:]
    var dhcpClientContextsByNodeID: [UUID: TopologyRuntimeDHCPClientContext] = [:]
    var firewallDecisions: [TopologyRuntimeFirewallDecision] = []
    var natMappings: [TopologyRuntimeNATMapping] = []
    var nextEventSequenceNumber: UInt64 = 0
    var nextFrameIdentity: UInt64 = 1
    var nextPacketIdentity: UInt64 = 1
    var nextTraceIdentity: UInt64 = 1
    var nextRemoteLinkEvidenceIdentity: UInt64 = 1
    var nextSocketSequenceNumber: UInt64 = 1
    var nextNATMappingSequenceNumber: UInt64 = 1
    var nextTCPInitialSequenceValue: UInt64 = 1
    var nextDNSQuerySequenceNumber: UInt64 = 1

    init(seed: UInt64) {
        self.seed = seed
    }
}

// MARK: - Java-compatible deterministic randomness

struct TopologyJavaCompatibleRandom: Equatable {
    private static let multiplier: UInt64 = 0x5DEECE66D
    private static let addend: UInt64 = 0xB
    private static let mask: UInt64 = (1 << 48) - 1

    private(set) var seed: UInt64

    init(seed: UInt64) {
        self.seed = (seed ^ Self.multiplier) & Self.mask
    }

    mutating func next(bits: UInt64) -> UInt32 {
        precondition(bits > 0 && bits <= 32)
        seed = (seed &* Self.multiplier &+ Self.addend) & Self.mask
        return UInt32(seed >> (48 - bits))
    }

    mutating func nextInt(upperBound: Int) -> Int {
        precondition(upperBound > 0)

        if upperBound & (-upperBound) == upperBound {
            return Int((Int64(upperBound) * Int64(next(bits: 31))) >> 31)
        }

        while true {
            let bits = Int64(next(bits: 31))
            let value = bits % Int64(upperBound)
            let javaOverflowCandidate = bits - value + Int64(upperBound - 1)
            if javaOverflowCandidate <= Int64(Int32.max) {
                return Int(value)
            }
        }
    }

    mutating func nextFloat() -> Float {
        Float(next(bits: 24)) / Float(1 << 24)
    }

    mutating func nextRIPJitterMilliseconds() -> UInt64 {
        let javaFloat = nextFloat()
        return UInt64(Int(30_000.0 * (Double(javaFloat) / 3.0 + 0.84)))
    }
}

// MARK: - Deterministic runtime engine

private struct TopologyPendingARPKey: Hashable {
    let nodeID: UUID
    let ipAddress: String
}

private struct TopologyPendingIPv4Transmission: Equatable {
    let packet: TopologyIPv4Packet
    let interface: TopologyRuntimeNetworkInterface
    let operation: TopologyPacketTraceOperation
}

struct TopologyNetworkRuntimeEngine: Equatable {
    static let defaultSeed: UInt64 = 0xF11A5

    private(set) var state: TopologyNetworkRuntimeState
    private var random: TopologyJavaCompatibleRandom
    private var udpPortRandom: TopologyJavaCompatibleRandom
    private var tcpPortRandom: TopologyJavaCompatibleRandom
    private var runtimeSpeed: TopologyNetworkRuntimeSpeed
    private var isProcessingScheduledEvents = false
    private var pendingIPv4TransmissionsByARPKey: [TopologyPendingARPKey: [TopologyPendingIPv4Transmission]] = [:]

    init(seed: UInt64 = TopologyNetworkRuntimeEngine.defaultSeed) {
        state = TopologyNetworkRuntimeState(seed: seed)
        random = TopologyJavaCompatibleRandom(seed: seed)
        udpPortRandom = TopologyJavaCompatibleRandom(seed: seed ^ 0x5544_5050)
        tcpPortRandom = TopologyJavaCompatibleRandom(seed: seed ^ 0x5443_5050)
        runtimeSpeed = TopologyNetworkRuntimeSpeed()
        state.simulationSpeedPercent = runtimeSpeed.percent
    }

    var simulationSpeed: TopologyNetworkRuntimeSpeed {
        runtimeSpeed
    }

    mutating func setSimulationSpeed(percent: Int) {
        runtimeSpeed = TopologyNetworkRuntimeSpeed(percent: percent)
        state.simulationSpeedPercent = runtimeSpeed.percent
    }

    @discardableResult
    mutating func handle(_ input: TopologyNetworkRuntimeInput) -> [TopologyNetworkRuntimeOutput] {
        switch input {
        case let .start(snapshot, seed, initialTimeMilliseconds):
            guard state.phase == .stopped else {
                return [output(.startIgnoredAlreadyRunning)]
            }

            state = TopologyNetworkRuntimeState(seed: seed)
            state.phase = .running
            state.currentTimeMilliseconds = initialTimeMilliseconds
            state.simulationSpeedPercent = runtimeSpeed.percent
            state.topologySnapshot = snapshot
            random = TopologyJavaCompatibleRandom(seed: seed)
            udpPortRandom = TopologyJavaCompatibleRandom(seed: seed ^ 0x5544_5050)
            tcpPortRandom = TopologyJavaCompatibleRandom(seed: seed ^ 0x5443_5050)
            isProcessingScheduledEvents = false
            pendingIPv4TransmissionsByARPKey.removeAll()
            initializeRIPState()
            initializeDHCPState()
            initializeNATState()
            return [output(.started)]

        case .stop:
            guard state.phase == .running else {
                return [output(.stopIgnoredAlreadyStopped)]
            }

            state.phase = .stopped
            isProcessingScheduledEvents = false
            pendingIPv4TransmissionsByARPKey.removeAll()
            state.pendingEvents.removeAll()
            state.arpCachesByNodeID.removeAll()
            state.switchForwardingTablesByNodeID.removeAll()
            state.switchForwardingUpdatedAtMillisecondsByNodeID.removeAll()
            state.switchSeenFrameIdentitiesByNodeID.removeAll()
            state.remoteLinkSeenFrameIdentitiesByNodeID.removeAll()
            state.deliveredIPv4PacketsByNodeID.removeAll()
            state.icmpObservationsByNodeID.removeAll()
            state.socketsByID.removeAll()
            state.udpReceiveQueuesBySocketID.removeAll()
            state.tcpSessionsByID.removeAll()
            state.tcpAcceptedSocketIDsByListenerID.removeAll()
            state.ripTablesByNodeID.removeAll()
            state.dhcpOffersByIPAddress.removeAll()
            state.dhcpLeasesByIPAddress.removeAll()
            state.dhcpBlacklistByServerNodeID.removeAll()
            state.dhcpLastOfferedAddressByServerNodeID.removeAll()
            state.dhcpServerSocketIDsByNodeID.removeAll()
            state.dhcpClientStatusesByNodeID.removeAll()
            state.dhcpClientContextsByNodeID.removeAll()
            state.firewallDecisions.removeAll()
            state.natMappings.removeAll()
            return [output(.stopped)]

        case let .advance(targetTimeMilliseconds):
            return advance(to: targetTimeMilliseconds)

        case let .schedule(deadlineMilliseconds, kind):
            guard state.phase == .running else {
                return [output(.advanceIgnoredWhileStopped)]
            }
            guard deadlineMilliseconds >= state.currentTimeMilliseconds else {
                return [output(.scheduleRejectedPastTime(deadlineMilliseconds: deadlineMilliseconds))]
            }
            let event = schedule(deadlineMilliseconds: deadlineMilliseconds, kind: kind)
            return [output(.scheduled(event: event))]

        case let .compatibilityOperation(operation):
            guard state.phase == .running else {
                return [output(.advanceIgnoredWhileStopped)]
            }
            recordCompatibilityTrace(operation)
            return [output(.compatibilityOperationRecorded(operation))]
        }
    }

    mutating func nextRIPJitterMilliseconds() -> UInt64 {
        random.nextRIPJitterMilliseconds()
    }

    mutating func allocateFrameIdentity() -> UInt64 {
        let identity = state.nextFrameIdentity
        state.nextFrameIdentity &+= 1
        return identity
    }

    mutating func allocatePacketIdentity() -> UInt64 {
        let identity = state.nextPacketIdentity
        state.nextPacketIdentity &+= 1
        return identity
    }

    mutating func recordTrace(
        frameIdentity: UInt64? = nil,
        packetIdentity: UInt64? = nil,
        nodeID: UUID,
        interfaceID: UUID? = nil,
        direction: TopologyPacketTraceDirection,
        layer: TopologyPacketTraceLayer,
        operation: TopologyPacketTraceOperation,
        beforeHeaders: [TopologyPacketHeaderField] = [],
        afterHeaders: [TopologyPacketHeaderField] = [],
        detail: String? = nil
    ) {
        let trace = TopologyPacketTraceEvent(
            id: state.nextTraceIdentity,
            timeMilliseconds: state.currentTimeMilliseconds,
            frameIdentity: frameIdentity,
            packetIdentity: packetIdentity,
            nodeID: nodeID,
            interfaceID: interfaceID,
            direction: direction,
            layer: layer,
            operation: operation,
            beforeHeaders: beforeHeaders,
            afterHeaders: afterHeaders,
            detail: detail
        )
        state.nextTraceIdentity &+= 1
        state.packetTraces.append(trace)
    }

    static func run(
        scenario: TopologyNetworkRuntimeScenario,
        snapshot: TopologyNetworkRuntimeTopologySnapshot = .empty
    ) -> TopologyNetworkRuntimeState {
        var engine = TopologyNetworkRuntimeEngine(seed: scenario.seed)
        engine.handle(
            .start(
                snapshot: snapshot,
                seed: scenario.seed,
                initialTimeMilliseconds: 0
            )
        )
        for scheduledEvent in scenario.scheduledEvents {
            engine.handle(
                .schedule(
                    deadlineMilliseconds: scheduledEvent.deadlineMilliseconds,
                    kind: scheduledEvent.kind
                )
            )
        }
        engine.handle(.advance(toMilliseconds: scenario.advanceToMilliseconds))
        return engine.state
    }

    private mutating func schedule(
        deadlineMilliseconds: UInt64,
        kind: TopologyNetworkRuntimeScheduledEventKind
    ) -> TopologyNetworkRuntimeScheduledEvent {
        let event = TopologyNetworkRuntimeScheduledEvent(
            id: state.nextEventSequenceNumber,
            deadlineMilliseconds: deadlineMilliseconds,
            sequenceNumber: state.nextEventSequenceNumber,
            kind: kind
        )
        state.nextEventSequenceNumber &+= 1
        state.pendingEvents.append(event)
        return event
    }

    private mutating func advance(to targetTimeMilliseconds: UInt64) -> [TopologyNetworkRuntimeOutput] {
        guard state.phase == .running else {
            return [output(.advanceIgnoredWhileStopped)]
        }
        guard targetTimeMilliseconds >= state.currentTimeMilliseconds else {
            return [output(.advanceRejectedPastTime)]
        }

        let startTime = state.currentTimeMilliseconds
        var outputs: [TopologyNetworkRuntimeOutput] = []
        let wasProcessingScheduledEvents = isProcessingScheduledEvents
        isProcessingScheduledEvents = true
        defer { isProcessingScheduledEvents = wasProcessingScheduledEvents }

        while let nextEventIndex = nextDueEventIndex(upTo: targetTimeMilliseconds) {
            let event = state.pendingEvents.remove(at: nextEventIndex)
            state.currentTimeMilliseconds = event.deadlineMilliseconds
            ageSwitchSATEntries()
            expireRIPRoutes()
            processScheduledRuntimeEvent(event.kind)
            outputs.append(output(.fired(event: event)))
        }

        state.currentTimeMilliseconds = targetTimeMilliseconds
        ageSwitchSATEntries()
        expireRIPRoutes()
        outputs.append(
            output(
                .advanced(
                    fromMilliseconds: startTime,
                    toMilliseconds: targetTimeMilliseconds
                )
            )
        )
        return outputs
    }

    private func nextDueEventIndex(upTo targetTimeMilliseconds: UInt64) -> Int? {
        state.pendingEvents.indices
            .filter { state.pendingEvents[$0].deadlineMilliseconds <= targetTimeMilliseconds }
            .min { lhs, rhs in
                let left = state.pendingEvents[lhs]
                let right = state.pendingEvents[rhs]
                if left.deadlineMilliseconds != right.deadlineMilliseconds {
                    return left.deadlineMilliseconds < right.deadlineMilliseconds
                }
                return left.sequenceNumber < right.sequenceNumber
            }
    }

    private mutating func recordCompatibilityTrace(_ operation: TopologyNetworkRuntimeCompatibilityOperation) {
        recordTrace(
            nodeID: operation.nodeID,
            interfaceID: operation.interfaceID,
            direction: .local,
            layer: .application,
            operation: .compatibilityAdapter,
            afterHeaders: [
                TopologyPacketHeaderField(name: "kind", value: operation.kind.rawValue),
            ],
            detail: operation.detail
        )
    }

    private func output(_ kind: TopologyNetworkRuntimeOutputKind) -> TopologyNetworkRuntimeOutput {
        TopologyNetworkRuntimeOutput(timeMilliseconds: state.currentTimeMilliseconds, kind: kind)
    }
}


// MARK: - Ethernet, ARP, IPv4, and ICMP packet runtime

extension TopologyNetworkRuntimeEngine {
    static let ethernetBroadcastMACAddress = "FF:FF:FF:FF:FF:FF"
    static let unspecifiedMACAddress = "00:00:00:00:00:00"
    static let limitedBroadcastIPAddress = "255.255.255.255"
    static let unspecifiedIPAddress = "0.0.0.0"
    static let localhostIPAddress = "127.0.0.1"

    func networkInterfaces(nodeID: UUID) -> [TopologyRuntimeNetworkInterface] {
        guard let node = state.topologySnapshot.nodes.first(where: { $0.id == nodeID }) else {
            return []
        }
        let deviceConfiguration = state.topologySnapshot.deviceConfigurations[nodeID]
        return node.ports.enumerated().compactMap { index, port in
            let configuration: TopologyRuntimeInterfaceConfiguration?
            switch node.kind {
            case .pc, .notebook:
                guard index == 0, let deviceConfiguration else { return nil }
                configuration = TopologyRuntimeInterfaceConfiguration(
                    ipAddress: deviceConfiguration.ipAddress,
                    subnetMask: deviceConfiguration.subnetMask
                )
            case .router, .gateway:
                configuration = state.topologySnapshot.interfaceConfigurations[
                    TopologyRuntimeInterfaceKey(nodeID: nodeID, portID: port.id)
                ]
            case .networkSwitch, .remoteLink, .unsupported:
                configuration = nil
            }
            guard let configuration else { return nil }
            return TopologyRuntimeNetworkInterface(
                nodeID: nodeID,
                portID: port.id,
                index: index,
                ipAddress: configuration.ipAddress,
                subnetMask: configuration.subnetMask,
                defaultGateway: deviceConfiguration?.defaultGateway ?? "",
                macAddress: Self.stableMACAddress(for: port.id)
            )
        }
    }

    static func stableMACAddress(for portID: UUID) -> String {
        let compact = portID.uuidString.replacingOccurrences(of: "-", with: "")
        let suffix = Array(compact.suffix(10))
        var octets = ["02"]
        for offset in stride(from: 0, to: suffix.count, by: 2) {
            octets.append(String(suffix[offset...min(offset + 1, suffix.count - 1)]).uppercased())
        }
        return octets.joined(separator: ":")
    }

    mutating func clearARPCache(nodeID: UUID? = nil) {
        if let nodeID {
            state.arpCachesByNodeID[nodeID] = [:]
        } else {
            state.arpCachesByNodeID.removeAll()
        }
    }

    @discardableResult
    mutating func resolveMACAddress(
        nodeID: UUID,
        targetIPAddress: String,
        preferredInterfaceID: UUID? = nil,
        maxRetries: Int = 2,
        selectInterfaceByAddress: Bool = true
    ) -> String? {
        let interfaces = networkInterfaces(nodeID: nodeID)
        guard let primaryInterface = interfaces.first else { return nil }
        if targetIPAddress == Self.localhostIPAddress { return primaryInterface.macAddress }
        if let localInterface = interfaces.first(where: { $0.ipAddress == targetIPAddress }) {
            return localInterface.macAddress
        }
        if let cached = state.arpCachesByNodeID[nodeID]?[targetIPAddress] { return cached.macAddress }

        let selectedInterface: TopologyRuntimeNetworkInterface?
        if let preferredInterfaceID {
            selectedInterface = interfaces.first(where: { $0.portID == preferredInterfaceID })
        } else if selectInterfaceByAddress {
            selectedInterface = bestInterface(matching: targetIPAddress, among: interfaces)
        } else {
            selectedInterface = interfaces.first
        }
        guard let selectedInterface else { return nil }

        for _ in 0..<max(0, maxRetries) {
            let request = TopologyARPPacket(
                operation: .request,
                senderMACAddress: selectedInterface.macAddress,
                senderIPAddress: selectedInterface.ipAddress,
                targetMACAddress: Self.unspecifiedMACAddress,
                targetIPAddress: targetIPAddress
            )
            let frame = TopologyEthernetFrame(
                identity: allocateFrameIdentity(),
                sourceMACAddress: selectedInterface.macAddress,
                destinationMACAddress: Self.ethernetBroadcastMACAddress,
                payload: .arp(request)
            )
            recordTrace(
                frameIdentity: frame.identity,
                nodeID: nodeID,
                interfaceID: selectedInterface.portID,
                direction: .outbound,
                layer: .dataLink,
                operation: .created,
                afterHeaders: ethernetHeaders(frame),
                detail: "ARP request for \(targetIPAddress)"
            )
            sendEthernetFrame(fromNodeID: nodeID, outgoingPortID: selectedInterface.portID, frame: frame)
            advanceRemoteLinkEventsUntilARPCacheResolves(nodeID: nodeID, targetIPAddress: targetIPAddress)
            if let cached = state.arpCachesByNodeID[nodeID]?[targetIPAddress] { return cached.macAddress }
        }
        return nil
    }

    private mutating func advanceRemoteLinkEventsUntilARPCacheResolves(
        nodeID: UUID,
        targetIPAddress: String
    ) {
        guard !isProcessingScheduledEvents else { return }
        advancePendingRemoteLinkEvents { engine in
            engine.state.arpCachesByNodeID[nodeID]?[targetIPAddress] != nil
        }
    }

    private mutating func advanceRemoteLinkEventsUntilICMPObservation(
        nodeID: UUID,
        observationCount: Int,
        identifier: UInt16,
        sequenceNumber: UInt16
    ) {
        guard !isProcessingScheduledEvents else { return }
        advancePendingRemoteLinkEvents { engine in
            let newObservations = (engine.state.icmpObservationsByNodeID[nodeID] ?? []).dropFirst(observationCount)
            return newObservations.contains { observation in
                observation.message.identifier == identifier
                    && observation.message.sequenceNumber == sequenceNumber
            }
        }
    }

    private mutating func advancePendingRemoteLinkEvents(
        until condition: (TopologyNetworkRuntimeEngine) -> Bool
    ) {
        let maximumEvents = 1_024
        var processedEventCount = 0
        while !condition(self), processedEventCount < maximumEvents {
            let nextDeadline = state.pendingEvents.compactMap { event -> UInt64? in
                switch event.kind {
                case .ethernetLinkDelivery, .remoteLinkDelivery:
                    return event.deadlineMilliseconds
                default:
                    return nil
                }
            }.min()
            guard let nextDeadline else { return }
            _ = advance(to: nextDeadline)
            processedEventCount += 1
        }
    }

    mutating func sendEthernetFrame(
        fromNodeID: UUID,
        outgoingPortID: UUID,
        frame: TopologyEthernetFrame
    ) {
        recordTrace(
            frameIdentity: frame.identity,
            packetIdentity: packetIdentity(in: frame),
            nodeID: fromNodeID,
            interfaceID: outgoingPortID,
            direction: .outbound,
            layer: .physical,
            operation: .sent,
            afterHeaders: ethernetHeaders(frame)
        )
        guard let endpoint = attachedEndpoint(nodeID: fromNodeID, portID: outgoingPortID) else { return }
        let latencyMilliseconds = runtimeSpeed.linkTransmissionDelayMilliseconds
        let (deadlineMilliseconds, overflowed) = state.currentTimeMilliseconds.addingReportingOverflow(
            latencyMilliseconds
        )
        guard !overflowed else {
            recordTrace(
                frameIdentity: frame.identity,
                packetIdentity: packetIdentity(in: frame),
                nodeID: fromNodeID,
                interfaceID: outgoingPortID,
                direction: .outbound,
                layer: .physical,
                operation: .dropped,
                afterHeaders: ethernetHeaders(frame),
                detail: "link transmission deadline overflow"
            )
            return
        }

        _ = schedule(
            deadlineMilliseconds: deadlineMilliseconds,
            kind: .ethernetLinkDelivery(
                sourceNodeID: fromNodeID,
                targetNodeID: endpoint.nodeID,
                targetPortID: endpoint.portID,
                latencyMilliseconds: latencyMilliseconds,
                frame: frame
            )
        )
        drainPendingNetworkDeliveryEventsIfNeeded()
    }

    private mutating func drainPendingNetworkDeliveryEventsIfNeeded() {
        guard !isProcessingScheduledEvents else { return }

        let maximumEvents = 16_384
        var processedEventCount = 0
        while processedEventCount < maximumEvents {
            let nextDeadline = state.pendingEvents.compactMap { event -> UInt64? in
                switch event.kind {
                case .ethernetLinkDelivery, .remoteLinkDelivery:
                    return event.deadlineMilliseconds
                default:
                    return nil
                }
            }.min()
            guard let nextDeadline else { return }
            _ = advance(to: nextDeadline)
            processedEventCount += 1
        }
    }

    @discardableResult
    mutating func sendIPv4Packet(
        fromNodeID: UUID,
        packet: TopologyIPv4Packet,
        preferredInterfaceID: UUID? = nil
    ) -> TopologyIPv4DeliveryResult {
        sendIPv4Packet(
            fromNodeID: fromNodeID,
            packet: packet,
            preferredInterfaceID: preferredInterfaceID,
            allowICMPErrorGeneration: true,
            operation: .sent
        )
    }

    mutating func updateDeviceConfiguration(
        nodeID: UUID,
        configuration: TopologyRuntimeDeviceConfiguration
    ) {
        guard state.phase == .running,
              state.topologySnapshot.nodes.contains(where: { $0.id == nodeID })
        else { return }

        var deviceConfigurations = state.topologySnapshot.deviceConfigurations
        deviceConfigurations[nodeID] = configuration
        replaceTopologyConfigurations(
            deviceConfigurations: deviceConfigurations,
            interfaceConfigurations: state.topologySnapshot.interfaceConfigurations
        )
    }

    mutating func sendICMPEcho(
        fromNodeID: UUID,
        targetIPAddress: String,
        timeToLive: UInt8 = 64,
        identifier: UInt16 = 1,
        sequenceNumber: UInt16 = 1,
        data: Data = Data()
    ) -> TopologyIPv4DeliveryResult {
        let interfaces = networkInterfaces(nodeID: fromNodeID)
        guard !interfaces.isEmpty else { return .dropped(packetIdentity: 0, nodeID: fromNodeID) }
        let route = routeForPacket(nodeID: fromNodeID, targetIPAddress: targetIPAddress)
        let sourceInterface: TopologyRuntimeNetworkInterface
        switch route {
        case let .local(interface): sourceInterface = interface ?? interfaces[0]
        case let .egress(interface, _): sourceInterface = interface
        case .broadcast, .unavailable: sourceInterface = interfaces[0]
        }
        let packet = TopologyIPv4Packet(
            identity: allocatePacketIdentity(),
            senderIPAddress: sourceInterface.ipAddress,
            receiverIPAddress: targetIPAddress,
            timeToLive: timeToLive,
            protocolNumber: .icmp,
            payload: .icmp(TopologyICMPMessage(
                kind: .echoRequest,
                identifier: identifier,
                sequenceNumber: sequenceNumber,
                data: data
            ))
        )
        recordTrace(
            packetIdentity: packet.identity,
            nodeID: fromNodeID,
            interfaceID: sourceInterface.portID,
            direction: .outbound,
            layer: .network,
            operation: .created,
            afterHeaders: ipv4Headers(packet),
            detail: "ICMP echo request"
        )
        let observationCount = state.icmpObservationsByNodeID[fromNodeID]?.count ?? 0
        let result = sendIPv4Packet(fromNodeID: fromNodeID, packet: packet, preferredInterfaceID: sourceInterface.portID)
        advanceRemoteLinkEventsUntilICMPObservation(
            nodeID: fromNodeID,
            observationCount: observationCount,
            identifier: identifier,
            sequenceNumber: sequenceNumber
        )
        let newObservations = Array((state.icmpObservationsByNodeID[fromNodeID] ?? []).dropFirst(observationCount))
        if let observation = newObservations.last(where: {
            $0.message.identifier == identifier && $0.message.sequenceNumber == sequenceNumber
        }) {
            switch observation.message.kind {
            case .echoReply:
                return .delivered(packetIdentity: packet.identity, nodeID: observation.nodeID)
            case .destinationNetworkUnreachable, .destinationHostUnreachable, .timeExceeded:
                return .icmpError(packetIdentity: packet.identity, nodeID: observation.nodeID, kind: observation.message.kind)
            case .echoRequest: break
            }
        }
        return result
    }

    mutating func traceICMPEcho(
        fromNodeID: UUID,
        targetIPAddress: String,
        maximumTimeToLive: UInt8 = 64,
        identifier: UInt16 = 1
    ) -> [TopologyRuntimeICMPObservation] {
        var observations: [TopologyRuntimeICMPObservation] = []
        guard maximumTimeToLive > 0 else { return observations }
        for ttl in UInt8(1)...maximumTimeToLive {
            let previousCount = state.icmpObservationsByNodeID[fromNodeID]?.count ?? 0
            _ = sendICMPEcho(
                fromNodeID: fromNodeID,
                targetIPAddress: targetIPAddress,
                timeToLive: ttl,
                identifier: identifier,
                sequenceNumber: UInt16(ttl)
            )
            let newItems = Array((state.icmpObservationsByNodeID[fromNodeID] ?? []).dropFirst(previousCount))
            guard let observation = newItems.last else { continue }
            observations.append(observation)
            if observation.message.kind == .echoReply { break }
        }
        return observations
    }

    func tracedNodePath(packetIdentity: UInt64) -> [UUID] {
        var result: [UUID] = []
        for trace in state.packetTraces where trace.packetIdentity == packetIdentity {
            guard !result.contains(trace.nodeID) else { continue }
            result.append(trace.nodeID)
        }
        return result
    }

    private enum RuntimePacketRoute {
        case local(TopologyRuntimeNetworkInterface?)
        case broadcast
        case egress(TopologyRuntimeNetworkInterface, nextHop: String)
        case unavailable
    }

    var remoteLinkRuntimeStatuses: [TopologyRemoteLinkRuntimeStatus] {
        state.topologySnapshot.nodes
            .filter { $0.kind == .remoteLink }
            .compactMap { remoteLinkRuntimeStatus(nodeID: $0.id) }
            .sorted { $0.nodeID.uuidString < $1.nodeID.uuidString }
    }

    var remoteLinkRuntimeEvidence: [TopologyRemoteLinkRuntimeEvidence] {
        state.remoteLinkEvidence
    }

    func remoteLinkRuntimeStatus(nodeID: UUID) -> TopologyRemoteLinkRuntimeStatus? {
        guard let node = nodeSnapshot(nodeID: nodeID), node.kind == .remoteLink else { return nil }
        let configuration = state.topologySnapshot.remoteLinkConfigurationsByNodeID[nodeID]
        let pairIdentifier = configuration.flatMap { normalizedRemoteLinkPairIdentifier($0.pairIdentifier) }
        let localPortID = node.ports.first?.id
        let isLocalPortAttached = localPortID.flatMap { attachedEndpoint(nodeID: nodeID, portID: $0) } != nil
        let pendingFrameCount = state.pendingEvents.reduce(into: 0) { count, event in
            guard case let .remoteLinkDelivery(sourceNodeID, _, _, _, _, _) = event.kind,
                  sourceNodeID == nodeID
            else { return }
            count += 1
        }
        return TopologyRemoteLinkRuntimeStatus(
            nodeID: nodeID,
            pairIdentifier: pairIdentifier,
            latencyMilliseconds: configuration?.latencyMilliseconds,
            isEnabled: configuration?.isEnabled == true,
            localPortID: localPortID,
            isLocalPortAttached: isLocalPortAttached,
            pendingFrameCount: pendingFrameCount,
            condition: remoteLinkCondition(nodeID: nodeID) ?? .missingConfiguration
        )
    }

    func remoteLinkStatus(nodeID: UUID) -> TopologyRemoteLinkRuntimeStatus? {
        remoteLinkRuntimeStatus(nodeID: nodeID)
    }

    func remoteLinkCondition(nodeID: UUID) -> TopologyRemoteLinkRuntimeCondition? {
        guard let node = nodeSnapshot(nodeID: nodeID), node.kind == .remoteLink else { return nil }
        guard state.phase == .running else { return .stopped }
        guard let configuration = state.topologySnapshot.remoteLinkConfigurationsByNodeID[nodeID],
              let pairIdentifier = normalizedRemoteLinkPairIdentifier(configuration.pairIdentifier)
        else { return .missingConfiguration }
        guard configuration.isEnabled else { return .disabled }

        let enabledMatches = state.topologySnapshot.nodes.compactMap { candidate -> UUID? in
            guard candidate.kind == .remoteLink,
                  let candidateConfiguration = state.topologySnapshot.remoteLinkConfigurationsByNodeID[candidate.id],
                  candidateConfiguration.isEnabled,
                  normalizedRemoteLinkPairIdentifier(candidateConfiguration.pairIdentifier) == pairIdentifier
            else { return nil }
            return candidate.id
        }.sorted { $0.uuidString < $1.uuidString }

        if enabledMatches.count == 2, let peerNodeID = enabledMatches.first(where: { $0 != nodeID }) {
            let isLocalPortAttached = node.ports.first.flatMap { attachedEndpoint(nodeID: nodeID, portID: $0.id) } != nil
            let isPartnerPortAttached = nodeSnapshot(nodeID: peerNodeID)?.ports.first.flatMap {
                attachedEndpoint(nodeID: peerNodeID, portID: $0.id)
            } != nil
            guard isLocalPortAttached, isPartnerPortAttached else {
                return .detached(partnerNodeID: peerNodeID)
            }
            return .active(partnerNodeID: peerNodeID)
        }
        if enabledMatches.count > 2 {
            return .ambiguous(enabledNodeCount: enabledMatches.count)
        }
        return .unpaired
    }

    private func normalizedRemoteLinkPairIdentifier(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private struct RuntimeAttachedEndpoint {
        let nodeID: UUID
        let portID: UUID
    }

    private func attachedEndpoint(nodeID: UUID, portID: UUID) -> RuntimeAttachedEndpoint? {
        for link in state.topologySnapshot.links {
            if link.sourceNodeID == nodeID && link.sourcePortID == portID {
                return RuntimeAttachedEndpoint(nodeID: link.targetNodeID, portID: link.targetPortID)
            }
            if link.targetNodeID == nodeID && link.targetPortID == portID {
                return RuntimeAttachedEndpoint(nodeID: link.sourceNodeID, portID: link.sourcePortID)
            }
        }
        return nil
    }

    private func nodeSnapshot(nodeID: UUID) -> TopologyNetworkRuntimeNodeSnapshot? {
        state.topologySnapshot.nodes.first(where: { $0.id == nodeID })
    }

    private mutating func receiveEthernetFrame(
        _ frame: TopologyEthernetFrame,
        atNodeID nodeID: UUID,
        incomingPortID: UUID
    ) {
        recordTrace(
            frameIdentity: frame.identity,
            packetIdentity: packetIdentity(in: frame),
            nodeID: nodeID,
            interfaceID: incomingPortID,
            direction: .inbound,
            layer: .physical,
            operation: .received,
            beforeHeaders: ethernetHeaders(frame)
        )
        guard let node = nodeSnapshot(nodeID: nodeID) else { return }
        if node.kind == .networkSwitch {
            forwardFrameThroughSwitch(frame, switchNode: node, incomingPortID: incomingPortID)
            return
        }
        if node.kind == .remoteLink {
            forwardFrameThroughRemoteLink(frame, remoteLinkNode: node, incomingPortID: incomingPortID)
            return
        }

        recordTrace(
            frameIdentity: frame.identity,
            packetIdentity: packetIdentity(in: frame),
            nodeID: nodeID,
            interfaceID: incomingPortID,
            direction: .inbound,
            layer: .dataLink,
            operation: .received,
            beforeHeaders: ethernetHeaders(frame)
        )
        guard let interface = networkInterfaces(nodeID: nodeID).first(where: { $0.portID == incomingPortID }) else {
            return
        }
        let destination = frame.destinationMACAddress.uppercased()
        guard destination == interface.macAddress.uppercased()
                || destination == Self.ethernetBroadcastMACAddress else {
            recordTrace(
                frameIdentity: frame.identity,
                packetIdentity: packetIdentity(in: frame),
                nodeID: nodeID,
                interfaceID: incomingPortID,
                direction: .inbound,
                layer: .dataLink,
                operation: .dropped,
                beforeHeaders: ethernetHeaders(frame),
                detail: "destination MAC does not match interface"
            )
            return
        }
        switch frame.payload {
        case let .arp(packet):
            receiveARPPacket(packet, frameIdentity: frame.identity, nodeID: nodeID, interface: interface)
        case let .ipv4(packet):
            receiveIPv4Packet(packet, frameIdentity: frame.identity, nodeID: nodeID, interface: interface)
        }
    }

    private mutating func forwardFrameThroughRemoteLink(
        _ frame: TopologyEthernetFrame,
        remoteLinkNode: TopologyNetworkRuntimeNodeSnapshot,
        incomingPortID: UUID
    ) {
        let pairIdentifier = state.topologySnapshot.remoteLinkConfigurationsByNodeID[remoteLinkNode.id]
            .flatMap { normalizedRemoteLinkPairIdentifier($0.pairIdentifier) }
        let seen = state.remoteLinkSeenFrameIdentitiesByNodeID[remoteLinkNode.id] ?? []
        guard !seen.contains(frame.identity) else {
            dropRemoteLinkFrame(
                frame,
                nodeID: remoteLinkNode.id,
                interfaceID: incomingPortID,
                partnerNodeID: nil,
                pairIdentifier: pairIdentifier,
                reason: .duplicateFrame,
                detail: "remote link cycle suppression"
            )
            return
        }
        state.remoteLinkSeenFrameIdentitiesByNodeID[remoteLinkNode.id, default: []].insert(frame.identity)

        guard let condition = remoteLinkCondition(nodeID: remoteLinkNode.id) else { return }
        let partnerNodeID: UUID
        switch condition {
        case .stopped, .missingConfiguration:
            dropRemoteLinkFrame(
                frame,
                nodeID: remoteLinkNode.id,
                interfaceID: incomingPortID,
                partnerNodeID: nil,
                pairIdentifier: pairIdentifier,
                reason: .missingConfiguration,
                detail: "remote link configuration missing"
            )
            return
        case .disabled:
            dropRemoteLinkFrame(
                frame,
                nodeID: remoteLinkNode.id,
                interfaceID: incomingPortID,
                partnerNodeID: nil,
                pairIdentifier: pairIdentifier,
                reason: .disabled,
                detail: "remote link disabled"
            )
            return
        case .unpaired:
            dropRemoteLinkFrame(
                frame,
                nodeID: remoteLinkNode.id,
                interfaceID: incomingPortID,
                partnerNodeID: nil,
                pairIdentifier: pairIdentifier,
                reason: .unpaired,
                detail: "remote link pair unavailable"
            )
            return
        case let .detached(partnerNodeID):
            dropRemoteLinkFrame(
                frame,
                nodeID: remoteLinkNode.id,
                interfaceID: incomingPortID,
                partnerNodeID: partnerNodeID,
                pairIdentifier: pairIdentifier,
                reason: .partnerLocalPortUnavailable,
                detail: "remote link pair detached partner=\(partnerNodeID.uuidString)"
            )
            return
        case let .ambiguous(enabledNodeCount):
            dropRemoteLinkFrame(
                frame,
                nodeID: remoteLinkNode.id,
                interfaceID: incomingPortID,
                partnerNodeID: nil,
                pairIdentifier: pairIdentifier,
                reason: .ambiguousPair,
                detail: "remote link pair ambiguous: enabledNodes=\(enabledNodeCount)"
            )
            return
        case let .active(resolvedPartnerNodeID):
            partnerNodeID = resolvedPartnerNodeID
        }

        guard let configuration = state.topologySnapshot.remoteLinkConfigurationsByNodeID[remoteLinkNode.id],
              let pairIdentifier,
              let partnerNode = nodeSnapshot(nodeID: partnerNodeID),
              let partnerPortID = partnerNode.ports.first?.id
        else {
            dropRemoteLinkFrame(
                frame,
                nodeID: remoteLinkNode.id,
                interfaceID: incomingPortID,
                partnerNodeID: partnerNodeID,
                pairIdentifier: pairIdentifier,
                reason: .pairNoLongerActive,
                detail: "remote link pair no longer active"
            )
            return
        }

        guard let effectiveLatencyMilliseconds = runtimeSpeed.scaledLinkDelay(
            baseMilliseconds: configuration.latencyMilliseconds
        ) else {
            dropRemoteLinkFrame(
                frame,
                nodeID: remoteLinkNode.id,
                interfaceID: incomingPortID,
                partnerNodeID: partnerNodeID,
                pairIdentifier: pairIdentifier,
                reason: .latencyOverflow,
                detail: "remote link speed scaling overflow"
            )
            return
        }
        let (deadlineMilliseconds, overflowed) = state.currentTimeMilliseconds.addingReportingOverflow(
            effectiveLatencyMilliseconds
        )
        guard !overflowed else {
            dropRemoteLinkFrame(
                frame,
                nodeID: remoteLinkNode.id,
                interfaceID: incomingPortID,
                partnerNodeID: partnerNodeID,
                pairIdentifier: pairIdentifier,
                reason: .latencyOverflow,
                detail: "remote link latency overflow"
            )
            return
        }

        recordTrace(
            frameIdentity: frame.identity,
            packetIdentity: packetIdentity(in: frame),
            nodeID: remoteLinkNode.id,
            interfaceID: incomingPortID,
            direction: .inbound,
            layer: .dataLink,
            operation: .forwarded,
            beforeHeaders: ethernetHeaders(frame),
            afterHeaders: ethernetHeaders(frame),
            detail: "remote link scheduled pair=\(pairIdentifier) baseLatencyMs=\(configuration.latencyMilliseconds) effectiveLatencyMs=\(effectiveLatencyMilliseconds) speedPercent=\(runtimeSpeed.percent)"
        )
        _ = schedule(
            deadlineMilliseconds: deadlineMilliseconds,
            kind: .remoteLinkDelivery(
                sourceNodeID: remoteLinkNode.id,
                partnerNodeID: partnerNodeID,
                partnerPortID: partnerPortID,
                pairIdentifier: pairIdentifier,
                latencyMilliseconds: configuration.latencyMilliseconds,
                frame: frame
            )
        )
        recordRemoteLinkEvidence(
            frameIdentity: frame.identity,
            nodeID: remoteLinkNode.id,
            partnerNodeID: partnerNodeID,
            pairIdentifier: pairIdentifier,
            kind: .scheduled(
                deadlineMilliseconds: deadlineMilliseconds,
                latencyMilliseconds: configuration.latencyMilliseconds
            )
        )
    }

    private mutating func deliverRemoteLinkFrame(
        sourceNodeID: UUID,
        partnerNodeID: UUID,
        partnerPortID: UUID,
        pairIdentifier: String,
        latencyMilliseconds: UInt64,
        frame: TopologyEthernetFrame
    ) {
        guard let condition = remoteLinkCondition(nodeID: sourceNodeID) else {
            dropRemoteLinkFrame(
                frame,
                nodeID: sourceNodeID,
                interfaceID: sourceStatusLocalPortID(nodeID: sourceNodeID),
                partnerNodeID: partnerNodeID,
                pairIdentifier: pairIdentifier,
                reason: .pairNoLongerActive,
                detail: "remote link pair condition unavailable"
            )
            return
        }
        switch condition {
        case let .active(currentPartnerNodeID) where currentPartnerNodeID == partnerNodeID:
            break
        case let .detached(currentPartnerNodeID) where currentPartnerNodeID == partnerNodeID:
            dropRemoteLinkFrame(
                frame,
                nodeID: sourceNodeID,
                interfaceID: sourceStatusLocalPortID(nodeID: sourceNodeID),
                partnerNodeID: partnerNodeID,
                pairIdentifier: pairIdentifier,
                reason: .partnerLocalPortUnavailable,
                detail: "remote link pair detached partner=\(currentPartnerNodeID.uuidString)"
            )
            return
        default:
            dropRemoteLinkFrame(
                frame,
                nodeID: sourceNodeID,
                interfaceID: sourceStatusLocalPortID(nodeID: sourceNodeID),
                partnerNodeID: partnerNodeID,
                pairIdentifier: pairIdentifier,
                reason: .pairNoLongerActive,
                detail: "remote link pair no longer active"
            )
            return
        }
        guard let partnerNode = nodeSnapshot(nodeID: partnerNodeID),
              partnerNode.kind == .remoteLink,
              partnerNode.ports.contains(where: { $0.id == partnerPortID }),
              attachedEndpoint(nodeID: partnerNodeID, portID: partnerPortID) != nil
        else {
            dropRemoteLinkFrame(
                frame,
                nodeID: partnerNodeID,
                interfaceID: partnerPortID,
                partnerNodeID: sourceNodeID,
                pairIdentifier: pairIdentifier,
                reason: .partnerLocalPortUnavailable,
                detail: "remote link partner local port unavailable"
            )
            return
        }

        recordTrace(
            frameIdentity: frame.identity,
            packetIdentity: packetIdentity(in: frame),
            nodeID: partnerNodeID,
            interfaceID: partnerPortID,
            direction: .outbound,
            layer: .dataLink,
            operation: .forwarded,
            beforeHeaders: ethernetHeaders(frame),
            afterHeaders: ethernetHeaders(frame),
            detail: "remote link delivered pair=\(pairIdentifier) latencyMs=\(latencyMilliseconds)"
        )
        recordRemoteLinkEvidence(
            frameIdentity: frame.identity,
            nodeID: sourceNodeID,
            partnerNodeID: partnerNodeID,
            pairIdentifier: pairIdentifier,
            kind: .delivered
        )
        sendEthernetFrame(fromNodeID: partnerNodeID, outgoingPortID: partnerPortID, frame: frame)
    }

    private func sourceStatusLocalPortID(nodeID: UUID) -> UUID? {
        nodeSnapshot(nodeID: nodeID)?.ports.first?.id
    }

    private mutating func dropRemoteLinkFrame(
        _ frame: TopologyEthernetFrame,
        nodeID: UUID,
        interfaceID: UUID?,
        partnerNodeID: UUID?,
        pairIdentifier: String?,
        reason: TopologyRemoteLinkRuntimeDropReason,
        detail: String
    ) {
        recordTrace(
            frameIdentity: frame.identity,
            packetIdentity: packetIdentity(in: frame),
            nodeID: nodeID,
            interfaceID: interfaceID,
            direction: .local,
            layer: .dataLink,
            operation: .dropped,
            beforeHeaders: ethernetHeaders(frame),
            detail: detail
        )
        recordRemoteLinkEvidence(
            frameIdentity: frame.identity,
            nodeID: nodeID,
            partnerNodeID: partnerNodeID,
            pairIdentifier: pairIdentifier,
            kind: .dropped(reason: reason)
        )
    }

    private mutating func recordRemoteLinkEvidence(
        frameIdentity: UInt64,
        nodeID: UUID,
        partnerNodeID: UUID?,
        pairIdentifier: String?,
        kind: TopologyRemoteLinkRuntimeEvidenceKind
    ) {
        state.remoteLinkEvidence.append(
            TopologyRemoteLinkRuntimeEvidence(
                id: state.nextRemoteLinkEvidenceIdentity,
                timeMilliseconds: state.currentTimeMilliseconds,
                frameIdentity: frameIdentity,
                nodeID: nodeID,
                partnerNodeID: partnerNodeID,
                pairIdentifier: pairIdentifier,
                kind: kind
            )
        )
        state.nextRemoteLinkEvidenceIdentity &+= 1
    }

    private mutating func forwardFrameThroughSwitch(
        _ frame: TopologyEthernetFrame,
        switchNode: TopologyNetworkRuntimeNodeSnapshot,
        incomingPortID: UUID
    ) {
        let seen = state.switchSeenFrameIdentitiesByNodeID[switchNode.id] ?? []
        guard !seen.contains(frame.identity) else {
            recordTrace(
                frameIdentity: frame.identity,
                packetIdentity: packetIdentity(in: frame),
                nodeID: switchNode.id,
                interfaceID: incomingPortID,
                direction: .inbound,
                layer: .dataLink,
                operation: .dropped,
                beforeHeaders: ethernetHeaders(frame),
                detail: "switch cycle suppression"
            )
            return
        }
        state.switchSeenFrameIdentitiesByNodeID[switchNode.id, default: []].insert(frame.identity)
        ageSwitchSATEntries(nodeID: switchNode.id)

        let source = frame.sourceMACAddress.uppercased()
        state.switchForwardingTablesByNodeID[switchNode.id, default: [:]][source] = incomingPortID
        state.switchForwardingUpdatedAtMillisecondsByNodeID[switchNode.id, default: [:]][source] =
            state.currentTimeMilliseconds
        recordTrace(
            frameIdentity: frame.identity,
            packetIdentity: packetIdentity(in: frame),
            nodeID: switchNode.id,
            interfaceID: incomingPortID,
            direction: .inbound,
            layer: .dataLink,
            operation: .accepted,
            beforeHeaders: ethernetHeaders(frame),
            detail: "switch learned source MAC"
        )

        let destination = frame.destinationMACAddress.uppercased()
        let connectedPorts = switchNode.ports.filter { port in
            port.id != incomingPortID && attachedEndpoint(nodeID: switchNode.id, portID: port.id) != nil
        }.map(\.id)

        let outgoingPorts: [UUID]
        let forwardingDetail: String
        if destination == Self.ethernetBroadcastMACAddress {
            outgoingPorts = connectedPorts
            forwardingDetail = "switch broadcast flooding"
        } else if let learnedPort = state.switchForwardingTablesByNodeID[switchNode.id]?[destination] {
            if learnedPort == incomingPortID {
                recordTrace(
                    frameIdentity: frame.identity,
                    packetIdentity: packetIdentity(in: frame),
                    nodeID: switchNode.id,
                    interfaceID: incomingPortID,
                    direction: .inbound,
                    layer: .dataLink,
                    operation: .dropped,
                    beforeHeaders: ethernetHeaders(frame),
                    detail: "switch filtered destination on incoming port"
                )
                return
            }
            if attachedEndpoint(nodeID: switchNode.id, portID: learnedPort) != nil {
                outgoingPorts = [learnedPort]
                forwardingDetail = "switch learned unicast forwarding"
            } else {
                state.switchForwardingTablesByNodeID[switchNode.id]?.removeValue(forKey: destination)
                state.switchForwardingUpdatedAtMillisecondsByNodeID[switchNode.id]?.removeValue(forKey: destination)
                outgoingPorts = connectedPorts
                forwardingDetail = "switch unknown unicast flooding"
            }
        } else {
            outgoingPorts = connectedPorts
            forwardingDetail = "switch unknown unicast flooding"
        }

        for portID in outgoingPorts {
            recordTrace(
                frameIdentity: frame.identity,
                packetIdentity: packetIdentity(in: frame),
                nodeID: switchNode.id,
                interfaceID: portID,
                direction: .outbound,
                layer: .dataLink,
                operation: .forwarded,
                afterHeaders: ethernetHeaders(frame),
                detail: forwardingDetail
            )
            sendEthernetFrame(fromNodeID: switchNode.id, outgoingPortID: portID, frame: frame)
        }
    }

    mutating func clearSwitchSAT(nodeID: UUID) {
        state.switchForwardingTablesByNodeID.removeValue(forKey: nodeID)
        state.switchForwardingUpdatedAtMillisecondsByNodeID.removeValue(forKey: nodeID)
    }

    func switchSATEntries(nodeID: UUID) -> [TopologySwitchSATEntry] {
        guard let node = nodeSnapshot(nodeID: nodeID), node.kind == .networkSwitch else { return [] }
        let labelsByPortID = Dictionary(uniqueKeysWithValues: node.ports.map { ($0.id, $0.label) })
        let updatedAtByMAC = state.switchForwardingUpdatedAtMillisecondsByNodeID[nodeID] ?? [:]
        return (state.switchForwardingTablesByNodeID[nodeID] ?? [:]).map { macAddress, portID in
            TopologySwitchSATEntry(
                macAddress: macAddress,
                portID: portID,
                portLabel: labelsByPortID[portID] ?? "?",
                updatedAtMilliseconds: updatedAtByMAC[macAddress] ?? 0
            )
        }.sorted { lhs, rhs in
            if lhs.macAddress == rhs.macAddress { return lhs.portID.uuidString < rhs.portID.uuidString }
            return lhs.macAddress < rhs.macAddress
        }
    }

    private mutating func ageSwitchSATEntries() {
        for nodeID in Array(state.switchForwardingTablesByNodeID.keys) {
            ageSwitchSATEntries(nodeID: nodeID)
        }
    }

    private mutating func ageSwitchSATEntries(nodeID: UUID) {
        let retention = state.topologySnapshot.switchConfigurationsByNodeID[nodeID]?.retentionTimeMilliseconds
            ?? TopologySwitchConfiguration.defaultRetentionTimeMilliseconds
        let updatedAtByMAC = state.switchForwardingUpdatedAtMillisecondsByNodeID[nodeID] ?? [:]
        let expiredMACAddresses = updatedAtByMAC.compactMap { macAddress, updatedAt -> String? in
            guard state.currentTimeMilliseconds >= updatedAt,
                  state.currentTimeMilliseconds - updatedAt >= retention
            else { return nil }
            return macAddress
        }
        guard !expiredMACAddresses.isEmpty else { return }
        for macAddress in expiredMACAddresses {
            state.switchForwardingTablesByNodeID[nodeID]?.removeValue(forKey: macAddress)
            state.switchForwardingUpdatedAtMillisecondsByNodeID[nodeID]?.removeValue(forKey: macAddress)
        }
        if state.switchForwardingTablesByNodeID[nodeID]?.isEmpty == true {
            state.switchForwardingTablesByNodeID.removeValue(forKey: nodeID)
        }
        if state.switchForwardingUpdatedAtMillisecondsByNodeID[nodeID]?.isEmpty == true {
            state.switchForwardingUpdatedAtMillisecondsByNodeID.removeValue(forKey: nodeID)
        }
    }

    private mutating func receiveARPPacket(
        _ packet: TopologyARPPacket,
        frameIdentity: UInt64,
        nodeID: UUID,
        interface: TopologyRuntimeNetworkInterface
    ) {
        if packet.senderIPAddress != Self.unspecifiedIPAddress {
            state.arpCachesByNodeID[nodeID, default: [:]][packet.senderIPAddress] = TopologyRuntimeARPCacheEntry(
                ipAddress: packet.senderIPAddress,
                macAddress: packet.senderMACAddress,
                updatedAtMilliseconds: state.currentTimeMilliseconds
            )
            flushIPv4TransmissionsAwaitingARP(
                nodeID: nodeID,
                ipAddress: packet.senderIPAddress,
                macAddress: packet.senderMACAddress
            )
        }
        recordTrace(
            frameIdentity: frameIdentity,
            nodeID: nodeID,
            interfaceID: interface.portID,
            direction: .inbound,
            layer: .network,
            operation: .accepted,
            beforeHeaders: arpHeaders(packet)
        )
        guard packet.operation == .request, packet.targetIPAddress == interface.ipAddress else { return }

        let replyTargetIPAddress = packet.senderIPAddress == Self.unspecifiedIPAddress
            ? Self.limitedBroadcastIPAddress : packet.senderIPAddress
        let replyTargetMACAddress = packet.senderIPAddress == Self.unspecifiedIPAddress
            ? Self.ethernetBroadcastMACAddress : packet.senderMACAddress
        let reply = TopologyARPPacket(
            operation: .reply,
            senderMACAddress: interface.macAddress,
            senderIPAddress: interface.ipAddress,
            targetMACAddress: replyTargetMACAddress,
            targetIPAddress: replyTargetIPAddress
        )
        let replyFrame = TopologyEthernetFrame(
            identity: allocateFrameIdentity(),
            sourceMACAddress: interface.macAddress,
            destinationMACAddress: replyTargetMACAddress,
            payload: .arp(reply)
        )
        recordTrace(
            frameIdentity: replyFrame.identity,
            nodeID: nodeID,
            interfaceID: interface.portID,
            direction: .outbound,
            layer: .dataLink,
            operation: .created,
            afterHeaders: ethernetHeaders(replyFrame),
            detail: "ARP reply for \(interface.ipAddress)"
        )
        sendEthernetFrame(fromNodeID: nodeID, outgoingPortID: interface.portID, frame: replyFrame)
    }

    private mutating func sendIPv4Packet(
        fromNodeID: UUID,
        packet: TopologyIPv4Packet,
        preferredInterfaceID: UUID?,
        allowICMPErrorGeneration: Bool,
        operation: TopologyPacketTraceOperation
    ) -> TopologyIPv4DeliveryResult {
        let route = routeForPacket(
            nodeID: fromNodeID,
            targetIPAddress: packet.receiverIPAddress,
            preferredInterfaceID: preferredInterfaceID
        )
        switch route {
        case let .local(interface):
            guard let interface = interface ?? networkInterfaces(nodeID: fromNodeID).first else {
                return .dropped(packetIdentity: packet.identity, nodeID: fromNodeID)
            }
            receiveIPv4Packet(packet, frameIdentity: nil, nodeID: fromNodeID, interface: interface)
            return .delivered(packetIdentity: packet.identity, nodeID: fromNodeID)

        case .broadcast:
            let interfaces = networkInterfaces(nodeID: fromNodeID)
            guard !interfaces.isEmpty else { return .dropped(packetIdentity: packet.identity, nodeID: fromNodeID) }
            let broadcastPacket = TopologyIPv4Packet(
                identity: packet.identity,
                senderIPAddress: packet.senderIPAddress,
                receiverIPAddress: packet.receiverIPAddress,
                timeToLive: 1,
                protocolNumber: packet.protocolNumber,
                payload: packet.payload
            )
            for interface in interfaces {
                let frame = TopologyEthernetFrame(
                    identity: allocateFrameIdentity(),
                    sourceMACAddress: interface.macAddress,
                    destinationMACAddress: Self.ethernetBroadcastMACAddress,
                    payload: .ipv4(broadcastPacket)
                )
                recordIPv4Send(packet: broadcastPacket, frame: frame, nodeID: fromNodeID, interfaceID: interface.portID, operation: operation)
                sendEthernetFrame(fromNodeID: fromNodeID, outgoingPortID: interface.portID, frame: frame)
            }
            return .delivered(packetIdentity: packet.identity, nodeID: fromNodeID)

        case let .egress(interface, nextHop):
            guard let destinationMACAddress = resolveMACAddress(
                nodeID: fromNodeID,
                targetIPAddress: nextHop,
                preferredInterfaceID: interface.portID,
                maxRetries: 2
            ) else {
                if isProcessingScheduledEvents, hasConfiguredInterface(ipAddress: nextHop) {
                    enqueueIPv4TransmissionAwaitingARP(
                        fromNodeID: fromNodeID,
                        nextHop: nextHop,
                        packet: packet,
                        interface: interface,
                        operation: operation
                    )
                    return .delivered(packetIdentity: packet.identity, nodeID: fromNodeID)
                }
                if allowICMPErrorGeneration {
                    observeLocalICMPError(
                        nodeID: fromNodeID,
                        interfaceID: interface.portID,
                        kind: .destinationHostUnreachable,
                        originalPacket: packet
                    )
                    return .icmpError(packetIdentity: packet.identity, nodeID: fromNodeID, kind: .destinationHostUnreachable)
                }
                return .dropped(packetIdentity: packet.identity, nodeID: fromNodeID)
            }
            transmitIPv4Packet(
                fromNodeID: fromNodeID,
                packet: packet,
                interface: interface,
                destinationMACAddress: destinationMACAddress,
                operation: operation
            )
            return .delivered(packetIdentity: packet.identity, nodeID: fromNodeID)

        case .unavailable:
            if allowICMPErrorGeneration {
                observeLocalICMPError(
                    nodeID: fromNodeID,
                    interfaceID: preferredInterfaceID,
                    kind: .destinationNetworkUnreachable,
                    originalPacket: packet
                )
                return .icmpError(packetIdentity: packet.identity, nodeID: fromNodeID, kind: .destinationNetworkUnreachable)
            }
            return .dropped(packetIdentity: packet.identity, nodeID: fromNodeID)
        }
    }


    private func hasConfiguredInterface(ipAddress: String) -> Bool {
        state.topologySnapshot.nodes.contains { node in
            networkInterfaces(nodeID: node.id).contains { $0.ipAddress == ipAddress }
        }
    }

    private mutating func enqueueIPv4TransmissionAwaitingARP(
        fromNodeID: UUID,
        nextHop: String,
        packet: TopologyIPv4Packet,
        interface: TopologyRuntimeNetworkInterface,
        operation: TopologyPacketTraceOperation
    ) {
        let key = TopologyPendingARPKey(nodeID: fromNodeID, ipAddress: nextHop)
        let transmission = TopologyPendingIPv4Transmission(
            packet: packet,
            interface: interface,
            operation: operation
        )
        guard pendingIPv4TransmissionsByARPKey[key]?.contains(transmission) != true else { return }
        pendingIPv4TransmissionsByARPKey[key, default: []].append(transmission)
        recordTrace(
            packetIdentity: packet.identity,
            nodeID: fromNodeID,
            interfaceID: interface.portID,
            direction: .outbound,
            layer: .network,
            operation: .created,
            beforeHeaders: ipv4Headers(packet),
            detail: "waiting for ARP resolution of \(nextHop)"
        )
    }

    private mutating func flushIPv4TransmissionsAwaitingARP(
        nodeID: UUID,
        ipAddress: String,
        macAddress: String
    ) {
        let key = TopologyPendingARPKey(nodeID: nodeID, ipAddress: ipAddress)
        guard let transmissions = pendingIPv4TransmissionsByARPKey.removeValue(forKey: key) else { return }
        for transmission in transmissions {
            transmitIPv4Packet(
                fromNodeID: nodeID,
                packet: transmission.packet,
                interface: transmission.interface,
                destinationMACAddress: macAddress,
                operation: transmission.operation
            )
        }
    }

    private mutating func transmitIPv4Packet(
        fromNodeID: UUID,
        packet: TopologyIPv4Packet,
        interface: TopologyRuntimeNetworkInterface,
        destinationMACAddress: String,
        operation: TopologyPacketTraceOperation
    ) {
        let frame = TopologyEthernetFrame(
            identity: allocateFrameIdentity(),
            sourceMACAddress: interface.macAddress,
            destinationMACAddress: destinationMACAddress,
            payload: .ipv4(packet)
        )
        recordIPv4Send(
            packet: packet,
            frame: frame,
            nodeID: fromNodeID,
            interfaceID: interface.portID,
            operation: operation
        )
        sendEthernetFrame(fromNodeID: fromNodeID, outgoingPortID: interface.portID, frame: frame)
    }

    private mutating func receiveIPv4Packet(
        _ packet: TopologyIPv4Packet,
        frameIdentity: UInt64?,
        nodeID: UUID,
        interface: TopologyRuntimeNetworkInterface
    ) {
        recordTrace(
            frameIdentity: frameIdentity,
            packetIdentity: packet.identity,
            nodeID: nodeID,
            interfaceID: interface.portID,
            direction: .inbound,
            layer: .network,
            operation: .received,
            beforeHeaders: ipv4Headers(packet)
        )
        guard let node = nodeSnapshot(nodeID: nodeID) else { return }

        var packetForProcessing = packet
        if node.kind == .gateway, let gatewayInterfaces = gatewayInterfaces(nodeID: nodeID) {
            if interface.portID == gatewayInterfaces.wan.portID {
                if case let .icmp(message) = packet.payload,
                   message.kind == .echoRequest,
                   packet.receiverIPAddress == gatewayInterfaces.wan.ipAddress {
                    deliverIPv4Locally(packet, nodeID: nodeID, interface: interface)
                    return
                }
                if sameSubnet(
                    packet.receiverIPAddress,
                    gatewayInterfaces.lan.ipAddress,
                    mask: gatewayInterfaces.lan.subnetMask
                ) {
                    recordTrace(
                        frameIdentity: frameIdentity,
                        packetIdentity: packet.identity,
                        nodeID: nodeID,
                        interfaceID: interface.portID,
                        direction: .inbound,
                        layer: .network,
                        operation: .dropped,
                        beforeHeaders: ipv4Headers(packet),
                        detail: "WAN packet addressed directly to LAN subnet"
                    )
                    return
                }
                let decision = evaluateFirewall(
                    packet: packet,
                    atNodeID: nodeID,
                    incomingInterfaceID: interface.portID,
                    frameIdentity: frameIdentity
                )
                guard decision.accepted else { return }
                if let rewritten = rewriteGatewayNATInbound(
                    packet: packet,
                    gatewayNodeID: nodeID,
                    frameIdentity: frameIdentity,
                    incomingInterface: interface
                ) {
                    packetForProcessing = rewritten
                }
            } else {
                let decision = evaluateFirewall(
                    packet: packet,
                    atNodeID: nodeID,
                    incomingInterfaceID: interface.portID,
                    frameIdentity: frameIdentity
                )
                guard decision.accepted else { return }

                let localAddresses = Set(networkInterfaces(nodeID: nodeID).map(\.ipAddress))
                if localAddresses.contains(packet.receiverIPAddress)
                    || packet.receiverIPAddress == Self.limitedBroadcastIPAddress {
                    deliverIPv4Locally(packet, nodeID: nodeID, interface: interface)
                    return
                }
                guard packet.timeToLive > 1 else {
                    emitICMPError(
                        fromNodeID: nodeID,
                        incomingInterface: interface,
                        kind: .timeExceeded,
                        originalPacket: packet
                    )
                    return
                }
                if isGatewayOutgoingPacket(packet, interfaces: gatewayInterfaces) {
                    if case .unavailable = routeForPacket(
                        nodeID: nodeID,
                        targetIPAddress: packet.receiverIPAddress
                    ) {
                        emitICMPError(
                            fromNodeID: nodeID,
                            incomingInterface: interface,
                            kind: .destinationNetworkUnreachable,
                            originalPacket: packet
                        )
                        return
                    }
                    packetForProcessing = rewriteGatewayNATOutbound(
                        packet: packet,
                        gatewayNodeID: nodeID,
                        frameIdentity: frameIdentity,
                        incomingInterface: interface
                    )
                }
            }
        } else if node.kind == .router {
            let decision = evaluateFirewall(
                packet: packet,
                atNodeID: nodeID,
                incomingInterfaceID: interface.portID,
                frameIdentity: frameIdentity
            )
            guard decision.accepted else { return }
        }

        let localAddresses = Set(networkInterfaces(nodeID: nodeID).map(\.ipAddress))
        if localAddresses.contains(packetForProcessing.receiverIPAddress)
            || packetForProcessing.receiverIPAddress == Self.limitedBroadcastIPAddress {
            if node.kind.isPCClassEndpoint,
               state.topologySnapshot.firewallConfigurationsByNodeID[nodeID] != nil {
                let decision = evaluateFirewall(
                    packet: packetForProcessing,
                    atNodeID: nodeID,
                    incomingInterfaceID: interface.portID,
                    frameIdentity: frameIdentity
                )
                guard decision.accepted else { return }
            }
            deliverIPv4Locally(packetForProcessing, nodeID: nodeID, interface: interface)
            return
        }
        guard node.kind == .router || node.kind == .gateway else {
            recordTrace(
                frameIdentity: frameIdentity,
                packetIdentity: packetForProcessing.identity,
                nodeID: nodeID,
                interfaceID: interface.portID,
                direction: .inbound,
                layer: .network,
                operation: .dropped,
                beforeHeaders: ipv4Headers(packetForProcessing),
                detail: "IPv4 forwarding disabled"
            )
            return
        }
        guard packetForProcessing.timeToLive > 1 else {
            emitICMPError(
                fromNodeID: nodeID,
                incomingInterface: interface,
                kind: .timeExceeded,
                originalPacket: packet
            )
            return
        }

        let forwarded = packetForProcessing.forwardingClone()
        recordTrace(
            frameIdentity: frameIdentity,
            packetIdentity: forwarded.identity,
            nodeID: nodeID,
            interfaceID: interface.portID,
            direction: .outbound,
            layer: .network,
            operation: .forwarded,
            beforeHeaders: ipv4Headers(packetForProcessing),
            afterHeaders: ipv4Headers(forwarded),
            detail: "TTL decremented"
        )
        let result = sendIPv4Packet(
            fromNodeID: nodeID,
            packet: forwarded,
            preferredInterfaceID: nil,
            allowICMPErrorGeneration: false,
            operation: .forwarded
        )
        if case .dropped = result {
            switch routeForPacket(nodeID: nodeID, targetIPAddress: packetForProcessing.receiverIPAddress) {
            case .unavailable:
                emitICMPError(
                    fromNodeID: nodeID,
                    incomingInterface: interface,
                    kind: .destinationNetworkUnreachable,
                    originalPacket: packet
                )
            default:
                emitICMPError(
                    fromNodeID: nodeID,
                    incomingInterface: interface,
                    kind: .destinationHostUnreachable,
                    originalPacket: packet
                )
            }
        }
    }

    private mutating func deliverIPv4Locally(
        _ packet: TopologyIPv4Packet,
        nodeID: UUID,
        interface: TopologyRuntimeNetworkInterface
    ) {
        switch packet.payload {
        case let .icmp(message):
            switch message.kind {
            case .echoRequest:
                guard packet.receiverIPAddress != Self.limitedBroadcastIPAddress || packet.timeToLive == 1 else { return }
                let reply = TopologyIPv4Packet(
                    identity: allocatePacketIdentity(),
                    senderIPAddress: interface.ipAddress,
                    receiverIPAddress: packet.senderIPAddress,
                    timeToLive: 64,
                    protocolNumber: .icmp,
                    payload: .icmp(TopologyICMPMessage(
                        kind: .echoReply,
                        identifier: message.identifier,
                        sequenceNumber: message.sequenceNumber,
                        data: message.data
                    ))
                )
                recordTrace(
                    packetIdentity: reply.identity,
                    nodeID: nodeID,
                    interfaceID: interface.portID,
                    direction: .outbound,
                    layer: .network,
                    operation: .created,
                    afterHeaders: ipv4Headers(reply),
                    detail: "ICMP echo reply"
                )
                _ = sendIPv4Packet(
                    fromNodeID: nodeID,
                    packet: reply,
                    preferredInterfaceID: nil,
                    allowICMPErrorGeneration: false,
                    operation: .sent
                )

            case .echoReply, .destinationNetworkUnreachable, .destinationHostUnreachable, .timeExceeded:
                state.icmpObservationsByNodeID[nodeID, default: []].append(
                    TopologyRuntimeICMPObservation(
                        nodeID: nodeID,
                        interfaceID: interface.portID,
                        packet: packet,
                        message: message
                    )
                )
                recordTrace(
                    packetIdentity: packet.identity,
                    nodeID: nodeID,
                    interfaceID: interface.portID,
                    direction: .local,
                    layer: .transport,
                    operation: .accepted,
                    beforeHeaders: icmpHeaders(message),
                    detail: "ICMP observation queued"
                )
            }
        case let .udp(datagram):
            state.deliveredIPv4PacketsByNodeID[nodeID, default: []].append(
                TopologyRuntimeDeliveredIPv4Packet(nodeID: nodeID, interfaceID: interface.portID, packet: packet)
            )
            deliverUDP(packet: packet, datagram: datagram, nodeID: nodeID, interface: interface)

        case let .tcp(segment):
            state.deliveredIPv4PacketsByNodeID[nodeID, default: []].append(
                TopologyRuntimeDeliveredIPv4Packet(nodeID: nodeID, interfaceID: interface.portID, packet: packet)
            )
            deliverTCP(packet: packet, segment: segment, nodeID: nodeID, interface: interface)
        }
    }

    private mutating func emitICMPError(
        fromNodeID: UUID,
        incomingInterface: TopologyRuntimeNetworkInterface,
        kind: TopologyICMPMessageKind,
        originalPacket: TopologyIPv4Packet
    ) {
        guard originalPacket.senderIPAddress != Self.unspecifiedIPAddress,
              originalPacket.senderIPAddress != Self.limitedBroadcastIPAddress else { return }
        let embeddedPacket: TopologyIPv4Packet
        if case let .icmp(message) = originalPacket.payload,
           let nestedOriginal = message.embeddedOriginalPacket {
            embeddedPacket = nestedOriginal
        } else {
            embeddedPacket = originalPacket
        }
        let errorPacket = TopologyIPv4Packet(
            identity: allocatePacketIdentity(),
            senderIPAddress: incomingInterface.ipAddress,
            receiverIPAddress: originalPacket.senderIPAddress,
            timeToLive: 64,
            protocolNumber: .icmp,
            payload: .icmp(TopologyICMPMessage(
                kind: kind,
                identifier: icmpIdentifier(from: originalPacket),
                sequenceNumber: icmpSequenceNumber(from: originalPacket),
                embeddedOriginalPacket: embeddedPacket
            ))
        )
        recordTrace(
            packetIdentity: errorPacket.identity,
            nodeID: fromNodeID,
            interfaceID: incomingInterface.portID,
            direction: .outbound,
            layer: .network,
            operation: .created,
            afterHeaders: ipv4Headers(errorPacket),
            detail: "ICMP \(kind.rawValue)"
        )
        _ = sendIPv4Packet(
            fromNodeID: fromNodeID,
            packet: errorPacket,
            preferredInterfaceID: nil,
            allowICMPErrorGeneration: false,
            operation: .sent
        )
    }

    private mutating func observeLocalICMPError(
        nodeID: UUID,
        interfaceID: UUID?,
        kind: TopologyICMPMessageKind,
        originalPacket: TopologyIPv4Packet
    ) {
        let embeddedPacket: TopologyIPv4Packet
        if case let .icmp(message) = originalPacket.payload,
           let nestedOriginal = message.embeddedOriginalPacket {
            embeddedPacket = nestedOriginal
        } else {
            embeddedPacket = originalPacket
        }
        let message = TopologyICMPMessage(
            kind: kind,
            identifier: icmpIdentifier(from: originalPacket),
            sequenceNumber: icmpSequenceNumber(from: originalPacket),
            embeddedOriginalPacket: embeddedPacket
        )
        let packet = TopologyIPv4Packet(
            identity: allocatePacketIdentity(),
            senderIPAddress: networkInterfaces(nodeID: nodeID).first?.ipAddress ?? Self.unspecifiedIPAddress,
            receiverIPAddress: originalPacket.senderIPAddress,
            timeToLive: 64,
            protocolNumber: .icmp,
            payload: .icmp(message)
        )
        state.icmpObservationsByNodeID[nodeID, default: []].append(
            TopologyRuntimeICMPObservation(
                nodeID: nodeID,
                interfaceID: interfaceID,
                packet: packet,
                message: message
            )
        )
        recordTrace(
            packetIdentity: packet.identity,
            nodeID: nodeID,
            interfaceID: interfaceID,
            direction: .local,
            layer: .network,
            operation: .created,
            afterHeaders: ipv4Headers(packet),
            detail: "ICMP \(kind.rawValue)"
        )
    }

    private func routeForPacket(
        nodeID: UUID,
        targetIPAddress: String,
        preferredInterfaceID: UUID? = nil
    ) -> RuntimePacketRoute {
        let interfaces = networkInterfaces(nodeID: nodeID)
        if targetIPAddress == Self.limitedBroadcastIPAddress { return .broadcast }
        if targetIPAddress == Self.localhostIPAddress { return .local(interfaces.first) }
        if let local = interfaces.first(where: { $0.ipAddress == targetIPAddress }) { return .local(local) }
        if isRIPEnabledRouter(nodeID: nodeID) {
            return ripRouteForPacket(nodeID: nodeID, targetIPAddress: targetIPAddress)
        }
        if let preferredInterfaceID,
           let preferred = interfaces.first(where: { $0.portID == preferredInterfaceID }),
           sameSubnet(preferred.ipAddress, targetIPAddress, mask: preferred.subnetMask) {
            return .egress(preferred, nextHop: targetIPAddress)
        }

        let configurations = interfaces.map {
            TopologyRuntimeInterfaceConfiguration(ipAddress: $0.ipAddress, subnetMask: $0.subnetMask)
        }
        let rows = TopologyJavaRouteTable.rows(
            interfaceConfigurations: configurations,
            manualRoutes: state.topologySnapshot.manualRoutesByNodeID[nodeID] ?? [],
            defaultGateway: state.topologySnapshot.deviceConfigurations[nodeID]?.defaultGateway
        )
        guard let target = parseIPv4(targetIPAddress) else { return .unavailable }
        var selected: TopologyRuntimeRouteRow?
        var selectedMask: UInt32?
        for row in rows {
            guard let destination = parseIPv4(row.destinationNetwork),
                  let mask = parseIPv4(row.subnetMask),
                  destination == (target & mask) else { continue }
            if let selectedMask, mask <= selectedMask { continue }
            selected = row
            selectedMask = mask
        }
        guard let selected else { return .unavailable }
        if selected.interfaceIPAddress == Self.localhostIPAddress {
            return .local(interfaces.first(where: { $0.ipAddress == targetIPAddress }) ?? interfaces.first)
        }
        guard let interface = interfaces.first(where: { $0.ipAddress == selected.interfaceIPAddress }) else {
            return .unavailable
        }
        let nextHop = sameSubnet(interface.ipAddress, targetIPAddress, mask: interface.subnetMask)
            ? targetIPAddress : selected.nextHop
        return .egress(interface, nextHop: nextHop)
    }

    private func bestInterface(
        matching targetIPAddress: String,
        among interfaces: [TopologyRuntimeNetworkInterface]
    ) -> TopologyRuntimeNetworkInterface? {
        var selected: TopologyRuntimeNetworkInterface?
        var selectedMask: UInt32?
        for interface in interfaces {
            guard sameSubnet(interface.ipAddress, targetIPAddress, mask: interface.subnetMask),
                  let mask = parseIPv4(interface.subnetMask) else { continue }
            if let selectedMask, mask <= selectedMask { continue }
            selected = interface
            selectedMask = mask
        }
        return selected
    }

    private func sameSubnet(_ lhs: String, _ rhs: String, mask: String) -> Bool {
        guard let lhs = parseIPv4(lhs), let rhs = parseIPv4(rhs), let mask = parseIPv4(mask) else { return false }
        return (lhs & mask) == (rhs & mask)
    }

    private func parseIPv4(_ value: String) -> UInt32? {
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 4 else { return nil }
        var address = UInt32(0)
        for segment in segments {
            guard let octet = UInt8(segment) else { return nil }
            address = (address << 8) | UInt32(octet)
        }
        return address
    }

    private func packetIdentity(in frame: TopologyEthernetFrame) -> UInt64? {
        guard case let .ipv4(packet) = frame.payload else { return nil }
        return packet.identity
    }

    private mutating func recordIPv4Send(
        packet: TopologyIPv4Packet,
        frame: TopologyEthernetFrame,
        nodeID: UUID,
        interfaceID: UUID,
        operation: TopologyPacketTraceOperation
    ) {
        recordTrace(
            frameIdentity: frame.identity,
            packetIdentity: packet.identity,
            nodeID: nodeID,
            interfaceID: interfaceID,
            direction: .outbound,
            layer: .network,
            operation: operation,
            afterHeaders: ipv4Headers(packet)
        )
        recordTrace(
            frameIdentity: frame.identity,
            packetIdentity: packet.identity,
            nodeID: nodeID,
            interfaceID: interfaceID,
            direction: .outbound,
            layer: .dataLink,
            operation: .created,
            afterHeaders: ethernetHeaders(frame)
        )
    }

    private func ethernetHeaders(_ frame: TopologyEthernetFrame) -> [TopologyPacketHeaderField] {
        [
            TopologyPacketHeaderField(name: "sourceMAC", value: frame.sourceMACAddress),
            TopologyPacketHeaderField(name: "destinationMAC", value: frame.destinationMACAddress),
        ]
    }

    private func arpHeaders(_ packet: TopologyARPPacket) -> [TopologyPacketHeaderField] {
        [
            TopologyPacketHeaderField(name: "operation", value: packet.operation.rawValue),
            TopologyPacketHeaderField(name: "senderMAC", value: packet.senderMACAddress),
            TopologyPacketHeaderField(name: "senderIP", value: packet.senderIPAddress),
            TopologyPacketHeaderField(name: "targetMAC", value: packet.targetMACAddress),
            TopologyPacketHeaderField(name: "targetIP", value: packet.targetIPAddress),
        ]
    }

    private func ipv4Headers(_ packet: TopologyIPv4Packet) -> [TopologyPacketHeaderField] {
        [
            TopologyPacketHeaderField(name: "senderIP", value: packet.senderIPAddress),
            TopologyPacketHeaderField(name: "receiverIP", value: packet.receiverIPAddress),
            TopologyPacketHeaderField(name: "ttl", value: String(packet.timeToLive)),
            TopologyPacketHeaderField(name: "protocol", value: String(packet.protocolNumber.rawValue)),
        ]
    }

    private func icmpHeaders(_ message: TopologyICMPMessage) -> [TopologyPacketHeaderField] {
        [
            TopologyPacketHeaderField(name: "kind", value: message.kind.rawValue),
            TopologyPacketHeaderField(name: "identifier", value: String(message.identifier)),
            TopologyPacketHeaderField(name: "sequence", value: String(message.sequenceNumber)),
        ]
    }

    mutating func setFirewallConfiguration(
        nodeID: UUID,
        configuration: TopologyFirewallConfiguration
    ) {
        var configurations = state.topologySnapshot.firewallConfigurationsByNodeID
        configurations[nodeID] = configuration
        state.topologySnapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: state.topologySnapshot.nodes,
            links: state.topologySnapshot.links,
            deviceConfigurations: state.topologySnapshot.deviceConfigurations,
            interfaceConfigurations: state.topologySnapshot.interfaceConfigurations,
            manualRoutesByNodeID: state.topologySnapshot.manualRoutesByNodeID,
            ripEnabledByNodeID: state.topologySnapshot.ripEnabledByNodeID,
            dhcpClientConfigurationsByNodeID: state.topologySnapshot.dhcpClientConfigurationsByNodeID,
            dhcpServerConfigurationsByNodeID: state.topologySnapshot.dhcpServerConfigurationsByNodeID,
            firewallConfigurationsByNodeID: configurations,
            portForwardingRowsByNodeID: state.topologySnapshot.portForwardingRowsByNodeID,
            switchConfigurationsByNodeID: state.topologySnapshot.switchConfigurationsByNodeID,
            remoteLinkConfigurationsByNodeID: state.topologySnapshot.remoteLinkConfigurationsByNodeID,
            hostWirelessConfigurationsByNodeID: state.topologySnapshot.hostWirelessConfigurationsByNodeID
        )
    }
    @discardableResult
    mutating func evaluateFirewall(
        packet: TopologyIPv4Packet,
        atNodeID nodeID: UUID,
        incomingInterfaceID: UUID? = nil,
        frameIdentity: UInt64? = nil
    ) -> TopologyRuntimeFirewallDecision {
        let configuration = state.topologySnapshot.firewallConfigurationsByNodeID[nodeID]
            ?? TopologyFirewallConfiguration()

        guard configuration.isActive else {
            return recordFirewallDecision(
                packet: packet,
                frameIdentity: frameIdentity,
                nodeID: nodeID,
                interfaceID: incomingInterfaceID,
                accepted: true,
                ruleIndex: nil,
                detail: "firewall inactive"
            )
        }

        if packet.protocolNumber == .icmp {
            return recordFirewallDecision(
                packet: packet,
                frameIdentity: frameIdentity,
                nodeID: nodeID,
                interfaceID: incomingInterfaceID,
                accepted: !configuration.dropICMP,
                ruleIndex: nil,
                detail: configuration.dropICMP ? "ICMP blocked by general setting" : "ICMP bypasses ordered rules"
            )
        }

        switch packet.payload {
        case let .tcp(segment):
            if configuration.filterSYNSegmentsOnly
                && !(segment.flags.contains(.synchronize) && !segment.flags.contains(.acknowledgement)) {
                return recordFirewallDecision(
                    packet: packet,
                    frameIdentity: frameIdentity,
                    nodeID: nodeID,
                    interfaceID: incomingInterfaceID,
                    accepted: true,
                    ruleIndex: nil,
                    detail: "established TCP traffic bypasses SYN-only filtering"
                )
            }
            for (index, rule) in configuration.rules.enumerated() {
                guard firewallProtocolMatches(packet.protocolNumber, rule: rule) else { continue }
                guard firewallEndpointsMatch(
                    sourceIPAddress: packet.senderIPAddress,
                    destinationIPAddress: packet.receiverIPAddress,
                    port: Int(segment.destinationPort),
                    rule: rule,
                    nodeID: nodeID
                ) else { continue }
                return recordFirewallDecision(
                    packet: packet,
                    frameIdentity: frameIdentity,
                    nodeID: nodeID,
                    interfaceID: incomingInterfaceID,
                    accepted: rule.action == .accept,
                    ruleIndex: index,
                    detail: "TCP matched rule #\(index + 1)"
                )
            }

        case let .udp(datagram):
            guard configuration.filterUDP else {
                return recordFirewallDecision(
                    packet: packet,
                    frameIdentity: frameIdentity,
                    nodeID: nodeID,
                    interfaceID: incomingInterfaceID,
                    accepted: true,
                    ruleIndex: nil,
                    detail: "UDP filtering disabled"
                )
            }
            for (index, rule) in configuration.rules.enumerated() {
                guard firewallProtocolMatches(packet.protocolNumber, rule: rule) else { continue }
                let requestMatches = firewallEndpointsMatch(
                    sourceIPAddress: packet.senderIPAddress,
                    destinationIPAddress: packet.receiverIPAddress,
                    port: Int(datagram.destinationPort),
                    rule: rule,
                    nodeID: nodeID
                )
                let responseMatches = rule.port != TopologyFirewallRule.allPorts && firewallEndpointsMatch(
                    sourceIPAddress: packet.receiverIPAddress,
                    destinationIPAddress: packet.senderIPAddress,
                    port: Int(datagram.sourcePort),
                    rule: rule,
                    nodeID: nodeID
                )
                guard requestMatches || responseMatches else { continue }
                return recordFirewallDecision(
                    packet: packet,
                    frameIdentity: frameIdentity,
                    nodeID: nodeID,
                    interfaceID: incomingInterfaceID,
                    accepted: rule.action == .accept,
                    ruleIndex: index,
                    detail: "UDP matched rule #\(index + 1)"
                )
            }

        case .icmp:
            break
        }

        return recordFirewallDecision(
            packet: packet,
            frameIdentity: frameIdentity,
            nodeID: nodeID,
            interfaceID: incomingInterfaceID,
            accepted: configuration.defaultPolicy == .accept,
            ruleIndex: nil,
            detail: "firewall default policy"
        )
    }

    private mutating func recordFirewallDecision(
        packet: TopologyIPv4Packet,
        frameIdentity: UInt64?,
        nodeID: UUID,
        interfaceID: UUID?,
        accepted: Bool,
        ruleIndex: Int?,
        detail: String
    ) -> TopologyRuntimeFirewallDecision {
        let decision = TopologyRuntimeFirewallDecision(
            packetIdentity: packet.identity,
            nodeID: nodeID,
            accepted: accepted,
            ruleIndex: ruleIndex
        )
        state.firewallDecisions.append(decision)
        recordTrace(
            frameIdentity: frameIdentity,
            packetIdentity: packet.identity,
            nodeID: nodeID,
            interfaceID: interfaceID,
            direction: .inbound,
            layer: .network,
            operation: accepted ? .accepted : .dropped,
            beforeHeaders: ipv4Headers(packet),
            detail: detail
        )
        return decision
    }

    private func firewallProtocolMatches(
        _ protocolNumber: TopologyIPv4Protocol,
        rule: TopologyFirewallRule
    ) -> Bool {
        rule.protocolType == .all || rule.protocolType.rawValue == protocolNumber.rawValue
    }

    private func firewallEndpointsMatch(
        sourceIPAddress: String,
        destinationIPAddress: String,
        port: Int,
        rule: TopologyFirewallRule,
        nodeID: UUID
    ) -> Bool {
        firewallSourceMatches(sourceIPAddress, rule: rule, nodeID: nodeID)
            && firewallAddressMatches(
                destinationIPAddress,
                configuredIPAddress: rule.destinationIPAddress,
                subnetMask: rule.destinationSubnetMask
            )
            && (rule.port == TopologyFirewallRule.allPorts || rule.port == port)
    }

    private func firewallSourceMatches(
        _ sourceIPAddress: String,
        rule: TopologyFirewallRule,
        nodeID: UUID
    ) -> Bool {
        guard !rule.sourceIPAddress.isEmpty else { return true }
        if rule.sourceIPAddress == TopologyFirewallRule.directlyConnectedSourceMarker {
            return networkInterfaces(nodeID: nodeID).contains { interface in
                sameSubnet(sourceIPAddress, interface.ipAddress, mask: interface.subnetMask)
            }
        }
        return firewallAddressMatches(
            sourceIPAddress,
            configuredIPAddress: rule.sourceIPAddress,
            subnetMask: rule.sourceSubnetMask
        )
    }

    private func firewallAddressMatches(
        _ packetIPAddress: String,
        configuredIPAddress: String,
        subnetMask: String
    ) -> Bool {
        guard !configuredIPAddress.isEmpty else { return true }
        guard !subnetMask.isEmpty else { return false }
        return sameSubnet(packetIPAddress, configuredIPAddress, mask: subnetMask)
    }

    private func icmpIdentifier(from packet: TopologyIPv4Packet) -> UInt16 {
        guard case let .icmp(message) = packet.payload else { return 0 }
        return message.identifier
    }

    private func icmpSequenceNumber(from packet: TopologyIPv4Packet) -> UInt16 {
        guard case let .icmp(message) = packet.payload else { return 0 }
        return message.sequenceNumber
    }
}


// MARK: - Gateway NAT/PAT

extension TopologyNetworkRuntimeEngine {
    static let natRetentionMilliseconds: UInt64 = 300_000
    static let natExpirySweepIntervalMilliseconds: UInt64 = 1_000

    func natMappings(gatewayNodeID: UUID) -> [TopologyRuntimeNATMapping] {
        state.natMappings
            .filter { $0.gatewayNodeID == gatewayNodeID }
            .sorted { lhs, rhs in
                if lhs.type != rhs.type { return lhs.type == .staticEntry }
                if lhs.protocolNumber.rawValue != rhs.protocolNumber.rawValue {
                    return lhs.protocolNumber.rawValue < rhs.protocolNumber.rawValue
                }
                if lhs.translatedPortOrIdentifier != rhs.translatedPortOrIdentifier {
                    return lhs.translatedPortOrIdentifier < rhs.translatedPortOrIdentifier
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    mutating func clearDynamicNATMappings(gatewayNodeID: UUID? = nil) {
        state.natMappings.removeAll { mapping in
            mapping.isDynamic && (gatewayNodeID == nil || mapping.gatewayNodeID == gatewayNodeID)
        }
    }

    mutating func setStaticPortForwardingRows(
        gatewayNodeID: UUID,
        rows: [TopologyGatewayPortForwardingRow]
    ) {
        var rowsByNodeID = state.topologySnapshot.portForwardingRowsByNodeID
        if rows.isEmpty {
            rowsByNodeID.removeValue(forKey: gatewayNodeID)
        } else {
            rowsByNodeID[gatewayNodeID] = rows
        }
        state.topologySnapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: state.topologySnapshot.nodes,
            links: state.topologySnapshot.links,
            deviceConfigurations: state.topologySnapshot.deviceConfigurations,
            interfaceConfigurations: state.topologySnapshot.interfaceConfigurations,
            manualRoutesByNodeID: state.topologySnapshot.manualRoutesByNodeID,
            ripEnabledByNodeID: state.topologySnapshot.ripEnabledByNodeID,
            dhcpClientConfigurationsByNodeID: state.topologySnapshot.dhcpClientConfigurationsByNodeID,
            dhcpServerConfigurationsByNodeID: state.topologySnapshot.dhcpServerConfigurationsByNodeID,
            firewallConfigurationsByNodeID: state.topologySnapshot.firewallConfigurationsByNodeID,
            portForwardingRowsByNodeID: rowsByNodeID,
            switchConfigurationsByNodeID: state.topologySnapshot.switchConfigurationsByNodeID,
            remoteLinkConfigurationsByNodeID: state.topologySnapshot.remoteLinkConfigurationsByNodeID,
            hostWirelessConfigurationsByNodeID: state.topologySnapshot.hostWirelessConfigurationsByNodeID
        )
        state.natMappings.removeAll {
            $0.gatewayNodeID == gatewayNodeID
                && ($0.type == .staticEntry || $0.type == .dynamicEntryFromStatic)
        }
        installStaticNATMappings(gatewayNodeID: gatewayNodeID, rows: rows)
    }

    private mutating func initializeNATState() {
        state.natMappings.removeAll()
        let gateways = state.topologySnapshot.nodes.filter { $0.kind == .gateway }
        guard !gateways.isEmpty else { return }
        for gateway in gateways {
            installStaticNATMappings(
                gatewayNodeID: gateway.id,
                rows: state.topologySnapshot.portForwardingRowsByNodeID[gateway.id] ?? []
            )
        }
        _ = schedule(
            deadlineMilliseconds: state.currentTimeMilliseconds + Self.natExpirySweepIntervalMilliseconds,
            kind: .natExpirySweep
        )
    }

    private mutating func installStaticNATMappings(
        gatewayNodeID: UUID,
        rows: [TopologyGatewayPortForwardingRow]
    ) {
        for row in rows {
            guard let protocolNumber = row.runtimeProtocol,
                  let publicPort = row.runtimePublicPort,
                  let lanPort = row.runtimeLANPort,
                  row.isRuntimeValid else { continue }
            state.natMappings.removeAll {
                $0.gatewayNodeID == gatewayNodeID
                    && $0.type == .staticEntry
                    && $0.protocolNumber == protocolNumber
                    && $0.translatedPortOrIdentifier == publicPort
            }
            state.natMappings.append(TopologyRuntimeNATMapping(
                id: allocateNATMappingID(),
                gatewayNodeID: gatewayNodeID,
                protocolNumber: protocolNumber,
                remoteIPAddress: "*",
                translatedPortOrIdentifier: publicPort,
                lanIPAddress: row.lanIPAddress,
                lanPortOrIdentifier: lanPort,
                type: .staticEntry,
                updatedAtMilliseconds: state.currentTimeMilliseconds
            ))
        }
    }

    private mutating func expireDynamicNATMappings() {
        state.natMappings.removeAll { mapping in
            mapping.isDynamic
                && state.currentTimeMilliseconds >= mapping.updatedAtMilliseconds
                && state.currentTimeMilliseconds - mapping.updatedAtMilliseconds >= Self.natRetentionMilliseconds
        }
    }

    private func gatewayInterfaces(nodeID: UUID) -> (wan: TopologyRuntimeNetworkInterface, lan: TopologyRuntimeNetworkInterface)? {
        let interfaces = networkInterfaces(nodeID: nodeID)
        guard interfaces.count >= 2,
              let wan = interfaces.first(where: { $0.index == 0 }),
              let lan = interfaces.first(where: { $0.index == 1 }) else { return nil }
        return (wan, lan)
    }

    private func isGatewayOutgoingPacket(
        _ packet: TopologyIPv4Packet,
        interfaces: (wan: TopologyRuntimeNetworkInterface, lan: TopologyRuntimeNetworkInterface)
    ) -> Bool {
        !sameSubnet(packet.receiverIPAddress, interfaces.lan.ipAddress, mask: interfaces.lan.subnetMask)
            && packet.receiverIPAddress != Self.limitedBroadcastIPAddress
            && packet.receiverIPAddress != interfaces.wan.ipAddress
    }

    private mutating func rewriteGatewayNATOutbound(
        packet: TopologyIPv4Packet,
        gatewayNodeID: UUID,
        frameIdentity: UInt64?,
        incomingInterface: TopologyRuntimeNetworkInterface
    ) -> TopologyIPv4Packet {
        guard let interfaces = gatewayInterfaces(nodeID: gatewayNodeID),
              incomingInterface.portID == interfaces.lan.portID,
              isGatewayOutgoingPacket(packet, interfaces: interfaces) else { return packet }

        let endpoint = natOutboundEndpoint(packet)
        var mapping = endpoint.flatMap { endpoint in
            let candidates = state.natMappings.filter {
                $0.gatewayNodeID == gatewayNodeID
                    && $0.protocolNumber == packet.protocolNumber
                    && $0.lanIPAddress == packet.senderIPAddress
                    && $0.lanPortOrIdentifier == endpoint.portOrIdentifier
            }
            return candidates.first(where: {
                $0.isDynamic && $0.remoteIPAddress == packet.receiverIPAddress
            }) ?? candidates.first(where: { $0.type == .staticEntry }) ?? candidates.first
        }
        if mapping == nil, let endpoint, shouldCreateNATMapping(for: packet) {
            let translated: UInt16?
            switch packet.protocolNumber {
            case .tcp:
                translated = reserveFreeTCPPort(nodeID: gatewayNodeID)
            case .udp:
                translated = reserveFreeUDPPort(nodeID: gatewayNodeID)
            case .icmp:
                translated = endpoint.portOrIdentifier
            }
            if let translated {
                let created = TopologyRuntimeNATMapping(
                    id: allocateNATMappingID(),
                    gatewayNodeID: gatewayNodeID,
                    protocolNumber: packet.protocolNumber,
                    remoteIPAddress: packet.receiverIPAddress,
                    translatedPortOrIdentifier: translated,
                    lanIPAddress: packet.senderIPAddress,
                    lanPortOrIdentifier: endpoint.portOrIdentifier,
                    type: .dynamicEntry,
                    updatedAtMilliseconds: state.currentTimeMilliseconds
                )
                state.natMappings.append(created)
                mapping = created
            }
        }

        let rewritten = packetReplacingSource(
            packet,
            ipAddress: interfaces.wan.ipAddress,
            portOrIdentifier: mapping?.translatedPortOrIdentifier
        )
        recordTrace(
            frameIdentity: frameIdentity,
            packetIdentity: packet.identity,
            nodeID: gatewayNodeID,
            interfaceID: incomingInterface.portID,
            direction: .outbound,
            layer: .network,
            operation: .rewritten,
            beforeHeaders: natHeaders(packet),
            afterHeaders: natHeaders(rewritten),
            detail: mapping == nil ? "NAT source rewrite without mapping" : "NAT/PAT LAN to WAN"
        )
        return rewritten
    }

    private mutating func rewriteGatewayNATInbound(
        packet: TopologyIPv4Packet,
        gatewayNodeID: UUID,
        frameIdentity: UInt64?,
        incomingInterface: TopologyRuntimeNetworkInterface
    ) -> TopologyIPv4Packet? {
        guard let interfaces = gatewayInterfaces(nodeID: gatewayNodeID),
              incomingInterface.portID == interfaces.wan.portID,
              packet.receiverIPAddress == interfaces.wan.ipAddress,
              let lookup = natInboundLookup(packet) else { return nil }
        let exactIndex = state.natMappings.firstIndex(where: {
            $0.gatewayNodeID == gatewayNodeID
                && $0.isDynamic
                && $0.protocolNumber == lookup.protocolNumber
                && $0.remoteIPAddress == lookup.remoteIPAddress
                && $0.translatedPortOrIdentifier == lookup.translatedPortOrIdentifier
        })
        let mapping: TopologyRuntimeNATMapping
        if let exactIndex {
            state.natMappings[exactIndex].updatedAtMilliseconds = state.currentTimeMilliseconds
            mapping = state.natMappings[exactIndex]
        } else if let staticMapping = state.natMappings.last(where: {
            $0.gatewayNodeID == gatewayNodeID
                && $0.type == .staticEntry
                && $0.protocolNumber == lookup.protocolNumber
                && $0.translatedPortOrIdentifier == lookup.translatedPortOrIdentifier
        }) {
            let dynamic = TopologyRuntimeNATMapping(
                id: allocateNATMappingID(),
                gatewayNodeID: gatewayNodeID,
                protocolNumber: staticMapping.protocolNumber,
                remoteIPAddress: lookup.remoteIPAddress,
                translatedPortOrIdentifier: staticMapping.translatedPortOrIdentifier,
                lanIPAddress: staticMapping.lanIPAddress,
                lanPortOrIdentifier: staticMapping.lanPortOrIdentifier,
                type: .dynamicEntryFromStatic,
                updatedAtMilliseconds: state.currentTimeMilliseconds
            )
            state.natMappings.append(dynamic)
            mapping = dynamic
        } else {
            return nil
        }

        let rewritten = packetReplacingDestination(
            packet,
            ipAddress: mapping.lanIPAddress,
            portOrIdentifier: mapping.lanPortOrIdentifier
        )
        recordTrace(
            frameIdentity: frameIdentity,
            packetIdentity: packet.identity,
            nodeID: gatewayNodeID,
            interfaceID: incomingInterface.portID,
            direction: .inbound,
            layer: .network,
            operation: .rewritten,
            beforeHeaders: natHeaders(packet),
            afterHeaders: natHeaders(rewritten),
            detail: mapping.type == .dynamicEntryFromStatic
                ? "Static port forwarding WAN to LAN"
                : "NAT/PAT WAN to LAN"
        )
        return rewritten
    }

    private func shouldCreateNATMapping(for packet: TopologyIPv4Packet) -> Bool {
        switch packet.payload {
        case let .tcp(segment):
            return segment.flags.contains(.synchronize) && !segment.flags.contains(.acknowledgement)
        case .udp, .icmp:
            return true
        }
    }

    private func natOutboundEndpoint(_ packet: TopologyIPv4Packet) -> (portOrIdentifier: UInt16, remotePort: UInt16?)? {
        switch packet.payload {
        case let .tcp(segment):
            return (segment.sourcePort, segment.destinationPort)
        case let .udp(datagram):
            return (datagram.sourcePort, datagram.destinationPort)
        case let .icmp(message):
            return (message.identifier, nil)
        }
    }

    private func natInboundLookup(_ packet: TopologyIPv4Packet) -> (
        protocolNumber: TopologyIPv4Protocol,
        remoteIPAddress: String,
        translatedPortOrIdentifier: UInt16
    )? {
        switch packet.payload {
        case let .tcp(segment):
            return (.tcp, packet.senderIPAddress, segment.destinationPort)
        case let .udp(datagram):
            return (.udp, packet.senderIPAddress, datagram.destinationPort)
        case let .icmp(message):
            if let embedded = message.embeddedOriginalPacket {
                switch embedded.payload {
                case let .tcp(segment):
                    return (.tcp, embedded.receiverIPAddress, segment.sourcePort)
                case let .udp(datagram):
                    return (.udp, embedded.receiverIPAddress, datagram.sourcePort)
                case let .icmp(embeddedMessage):
                    return (.icmp, embedded.receiverIPAddress, embeddedMessage.identifier)
                }
            }
            return (.icmp, packet.senderIPAddress, message.identifier)
        }
    }

    private func packetReplacingSource(
        _ packet: TopologyIPv4Packet,
        ipAddress: String,
        portOrIdentifier: UInt16?
    ) -> TopologyIPv4Packet {
        TopologyIPv4Packet(
            identity: packet.identity,
            senderIPAddress: ipAddress,
            receiverIPAddress: packet.receiverIPAddress,
            timeToLive: packet.timeToLive,
            protocolNumber: packet.protocolNumber,
            payload: payloadReplacingSourcePort(packet.payload, port: portOrIdentifier)
        )
    }

    private func packetReplacingDestination(
        _ packet: TopologyIPv4Packet,
        ipAddress: String,
        portOrIdentifier: UInt16?
    ) -> TopologyIPv4Packet {
        TopologyIPv4Packet(
            identity: packet.identity,
            senderIPAddress: packet.senderIPAddress,
            receiverIPAddress: ipAddress,
            timeToLive: packet.timeToLive,
            protocolNumber: packet.protocolNumber,
            payload: payloadReplacingDestinationPort(packet.payload, port: portOrIdentifier)
        )
    }

    private func payloadReplacingSourcePort(_ payload: TopologyIPv4Payload, port: UInt16?) -> TopologyIPv4Payload {
        guard let port else { return payload }
        switch payload {
        case let .tcp(segment):
            return .tcp(TopologyTCPSegment(
                sourcePort: port,
                destinationPort: segment.destinationPort,
                sequenceNumber: segment.sequenceNumber,
                acknowledgementNumber: segment.acknowledgementNumber,
                flags: segment.flags,
                payload: segment.payload
            ))
        case let .udp(datagram):
            return .udp(TopologyUDPDatagram(
                sourcePort: port,
                destinationPort: datagram.destinationPort,
                payload: datagram.payload
            ))
        case .icmp:
            return payload
        }
    }

    private func payloadReplacingDestinationPort(_ payload: TopologyIPv4Payload, port: UInt16?) -> TopologyIPv4Payload {
        guard let port else { return payload }
        switch payload {
        case let .tcp(segment):
            return .tcp(TopologyTCPSegment(
                sourcePort: segment.sourcePort,
                destinationPort: port,
                sequenceNumber: segment.sequenceNumber,
                acknowledgementNumber: segment.acknowledgementNumber,
                flags: segment.flags,
                payload: segment.payload
            ))
        case let .udp(datagram):
            return .udp(TopologyUDPDatagram(
                sourcePort: datagram.sourcePort,
                destinationPort: port,
                payload: datagram.payload
            ))
        case .icmp:
            return payload
        }
    }

    private mutating func allocateNATMappingID() -> UUID {
        let suffix = String(format: "%012llX", state.nextNATMappingSequenceNumber)
        state.nextNATMappingSequenceNumber &+= 1
        return UUID(uuidString: "4E415400-0000-0000-0000-\(suffix)")!
    }

    private func natHeaders(_ packet: TopologyIPv4Packet) -> [TopologyPacketHeaderField] {
        var headers = ipv4Headers(packet)
        switch packet.payload {
        case let .tcp(segment):
            headers.append(contentsOf: tcpHeaders(segment))
        case let .udp(datagram):
            headers.append(contentsOf: udpHeaders(
                sourcePort: datagram.sourcePort,
                destinationPort: datagram.destinationPort,
                payloadLength: datagram.payload.count
            ))
        case let .icmp(message):
            headers.append(TopologyPacketHeaderField(name: "identifier", value: String(message.identifier)))
        }
        return headers
    }
}

// MARK: - Deterministic DNS over UDP

extension TopologyNetworkRuntimeEngine {
    static let dnsPort: UInt16 = 53
    static let dnsDefaultTimeoutMilliseconds: UInt64 = 3_000
    static let dnsPositiveCacheTTLMilliseconds: UInt64 = 60_000
    static let dnsNegativeCacheTTLMilliseconds: UInt64 = 15_000

    @discardableResult
    mutating func startDNSServer(nodeID: UUID) -> UUID? {
        guard state.phase == .running,
              state.topologySnapshot.nodes.contains(where: { $0.id == nodeID }),
              !isDNSServerRunning(nodeID: nodeID),
              let interface = networkInterfaces(nodeID: nodeID).first
        else { return nil }

        return bindUDPSocket(
            nodeID: nodeID,
            localPort: Self.dnsPort,
            localIPAddress: interface.ipAddress
        )
    }

    mutating func stopDNSServer(nodeID: UUID) {
        let socketIDs = state.socketsByID.values
            .filter { socket in
                socket.nodeID == nodeID
                    && socket.protocolKind == .udp
                    && socket.localPort == Self.dnsPort
            }
            .map(\.id)
        for socketID in socketIDs { discardSocket(socketID: socketID) }
    }

    func isDNSServerRunning(nodeID: UUID) -> Bool {
        state.socketsByID.values.contains { socket in
            socket.nodeID == nodeID
                && socket.protocolKind == .udp
                && socket.localPort == Self.dnsPort
        }
    }

    mutating func recordDNSCacheHit(
        nodeID: UUID,
        hostname: String,
        serverIPAddress: String,
        targetIPAddress: String?
    ) {
        recordTrace(
            nodeID: nodeID,
            interfaceID: networkInterfaces(nodeID: nodeID).first?.portID,
            direction: .local,
            layer: .application,
            operation: .accepted,
            afterHeaders: dnsHeaders(
                transactionID: nil,
                hostname: hostname,
                responseCode: targetIPAddress == nil ? .nameError : .noError,
                targetIPAddress: targetIPAddress,
                cacheStatus: "HIT"
            ),
            detail: "DNS cache hit server=\(serverIPAddress)"
        )
    }

    mutating func resolveDNS(
        clientNodeID: UUID,
        serverIPAddress: String,
        hostname: String,
        recordsByServerNodeID: [UUID: TopologyRuntimeDNSServerConfiguration],
        timeoutMilliseconds: UInt64 = TopologyNetworkRuntimeEngine.dnsDefaultTimeoutMilliseconds
    ) -> TopologyRuntimeDNSResolutionResult {
        guard state.phase == .running else { return .simulationStopped }
        guard let clientSocketID = bindUDPSocket(
            nodeID: clientNodeID,
            remoteIPAddress: serverIPAddress,
            remotePort: Self.dnsPort
        ) else { return .unreachable(serverIPAddress: serverIPAddress) }
        defer { discardSocket(socketID: clientSocketID) }

        let normalizedHostname = hostname.lowercased()
        let transactionID = state.nextDNSQuerySequenceNumber
        state.nextDNSQuerySequenceNumber &+= 1
        let query = TopologyRuntimeDNSWireMessage(
            kind: .query,
            transactionID: transactionID,
            hostname: normalizedHostname,
            responseCode: nil,
            targetIPAddress: nil
        )
        let delivery = sendUDP(
            socketID: clientSocketID,
            payload: encodeDNSMessage(query),
            destinationIPAddress: serverIPAddress,
            destinationPort: Self.dnsPort
        )
        let queryPacketIdentity = packetIdentity(from: delivery)
        recordTrace(
            packetIdentity: queryPacketIdentity,
            nodeID: clientNodeID,
            interfaceID: networkInterfaces(nodeID: clientNodeID).first?.portID,
            direction: .outbound,
            layer: .application,
            operation: .sent,
            afterHeaders: dnsHeaders(
                transactionID: transactionID,
                hostname: normalizedHostname,
                responseCode: nil,
                targetIPAddress: nil,
                cacheStatus: "MISS"
            ),
            detail: "DNS query server=\(serverIPAddress)"
        )
        switch delivery {
        case .some(.delivered(_, _)):
            break
        case .some(.icmpError(_, _, _)):
            return .unreachable(serverIPAddress: serverIPAddress)
        case .some(.dropped(_, _)):
            return .timeout(serverIPAddress: serverIPAddress)
        case .none:
            return .unreachable(serverIPAddress: serverIPAddress)
        }

        let serverNodeIDs = state.topologySnapshot.nodes
            .filter { node in
                networkInterfaces(nodeID: node.id).contains(where: { $0.ipAddress == serverIPAddress })
            }
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
        guard serverNodeIDs.count == 1, let serverNodeID = serverNodeIDs.first else {
            return .unreachable(serverIPAddress: serverIPAddress)
        }

        guard let serverSocketID = state.socketsByID.values
            .filter({ socket in
                socket.nodeID == serverNodeID
                    && socket.protocolKind == .udp
                    && socket.localPort == Self.dnsPort
            })
            .sorted(by: { $0.id.uuidString < $1.id.uuidString })
            .first?.id
        else {
            _ = receiveUDP(socketID: clientSocketID, timeoutMilliseconds: timeoutMilliseconds)
            return .timeout(serverIPAddress: serverIPAddress)
        }

        guard let receivedQuery = receiveUDP(socketID: serverSocketID),
              let decodedQuery = decodeDNSMessage(receivedQuery.datagram.payload),
              decodedQuery.kind == .query,
              decodedQuery.transactionID == transactionID,
              decodedQuery.hostname == normalizedHostname
        else {
            _ = receiveUDP(socketID: clientSocketID, timeoutMilliseconds: timeoutMilliseconds)
            return .timeout(serverIPAddress: serverIPAddress)
        }

        let record = recordsByServerNodeID[serverNodeID]?.recordsByHostname[normalizedHostname]
        let response = TopologyRuntimeDNSWireMessage(
            kind: .response,
            transactionID: transactionID,
            hostname: normalizedHostname,
            responseCode: record == nil ? .nameError : .noError,
            targetIPAddress: record?.targetIPAddress
        )
        let responseDelivery = sendUDP(
            socketID: serverSocketID,
            payload: encodeDNSMessage(response),
            destinationIPAddress: receivedQuery.senderIPAddress,
            destinationPort: receivedQuery.datagram.sourcePort
        )
        recordTrace(
            packetIdentity: packetIdentity(from: responseDelivery),
            nodeID: serverNodeID,
            interfaceID: networkInterfaces(nodeID: serverNodeID).first?.portID,
            direction: .outbound,
            layer: .application,
            operation: .sent,
            afterHeaders: dnsHeaders(
                transactionID: transactionID,
                hostname: normalizedHostname,
                responseCode: response.responseCode,
                targetIPAddress: response.targetIPAddress,
                cacheStatus: nil
            ),
            detail: record == nil ? "DNS response NXDOMAIN" : "DNS response NOERROR"
        )
        switch responseDelivery {
        case .some(.delivered(_, _)):
            break
        case .some(.icmpError(_, _, _)):
            return .unreachable(serverIPAddress: serverIPAddress)
        case .some(.dropped(_, _)):
            return .timeout(serverIPAddress: serverIPAddress)
        case .none:
            return .unreachable(serverIPAddress: serverIPAddress)
        }

        guard let receivedResponse = receiveUDP(
            socketID: clientSocketID,
            timeoutMilliseconds: timeoutMilliseconds
        ), let decodedResponse = decodeDNSMessage(receivedResponse.datagram.payload),
           decodedResponse.kind == .response,
           decodedResponse.transactionID == transactionID,
           decodedResponse.hostname == normalizedHostname
        else {
            return .timeout(serverIPAddress: serverIPAddress)
        }

        recordTrace(
            nodeID: clientNodeID,
            interfaceID: networkInterfaces(nodeID: clientNodeID).first?.portID,
            direction: .local,
            layer: .application,
            operation: .accepted,
            beforeHeaders: dnsHeaders(
                transactionID: transactionID,
                hostname: normalizedHostname,
                responseCode: decodedResponse.responseCode,
                targetIPAddress: decodedResponse.targetIPAddress,
                cacheStatus: "MISS"
            ),
            detail: decodedResponse.responseCode == .nameError ? "DNS NXDOMAIN received" : "DNS answer received"
        )

        if decodedResponse.responseCode == .noError, let targetIPAddress = decodedResponse.targetIPAddress {
            return .success(
                record: TopologyRuntimeDNSRecord(hostname: normalizedHostname, targetIPAddress: targetIPAddress),
                serverIPAddress: serverIPAddress,
                cached: false
            )
        }
        return .nxdomain(hostname: normalizedHostname, serverIPAddress: serverIPAddress, cached: false)
    }

    private func packetIdentity(from result: TopologyIPv4DeliveryResult?) -> UInt64? {
        guard let result else { return nil }
        switch result {
        case let .delivered(packetIdentity, _), let .icmpError(packetIdentity, _, _), let .dropped(packetIdentity, _):
            return packetIdentity
        }
    }

    private func encodeDNSMessage(_ message: TopologyRuntimeDNSWireMessage) -> Data {
        Data([
            "FILIUS-DNS/1",
            message.kind.rawValue,
            String(message.transactionID),
            message.hostname,
            message.responseCode?.rawValue ?? "-",
            message.targetIPAddress ?? "-",
        ].joined(separator: "\n").utf8)
    }

    private func decodeDNSMessage(_ data: Data) -> TopologyRuntimeDNSWireMessage? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let fields = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 6, fields[0] == "FILIUS-DNS/1",
              let kind = TopologyRuntimeDNSWireKind(rawValue: fields[1]),
              let transactionID = UInt64(fields[2])
        else { return nil }
        let responseCode = fields[4] == "-" ? nil : TopologyRuntimeDNSResponseCode(rawValue: fields[4])
        let targetIPAddress = fields[5] == "-" ? nil : fields[5]
        return TopologyRuntimeDNSWireMessage(
            kind: kind,
            transactionID: transactionID,
            hostname: fields[3],
            responseCode: responseCode,
            targetIPAddress: targetIPAddress
        )
    }

    private func dnsHeaders(
        transactionID: UInt64?,
        hostname: String,
        responseCode: TopologyRuntimeDNSResponseCode?,
        targetIPAddress: String?,
        cacheStatus: String?
    ) -> [TopologyPacketHeaderField] {
        var headers = [
            TopologyPacketHeaderField(name: "protocol", value: "DNS"),
            TopologyPacketHeaderField(name: "hostname", value: hostname),
        ]
        if let transactionID {
            headers.append(TopologyPacketHeaderField(name: "transactionID", value: String(transactionID)))
        }
        if let responseCode {
            headers.append(TopologyPacketHeaderField(name: "responseCode", value: responseCode.rawValue))
        }
        if let targetIPAddress {
            headers.append(TopologyPacketHeaderField(name: "answer", value: targetIPAddress))
        }
        if let cacheStatus {
            headers.append(TopologyPacketHeaderField(name: "cache", value: cacheStatus))
        }
        return headers
    }
}

// MARK: - UDP sockets and Router RIP

extension TopologyNetworkRuntimeEngine {
    static let udpEphemeralPortLowerBound = 49_152
    static let udpEphemeralPortUpperBoundExclusive = 65_535
    static let ripInfinity = 16
    static let ripDestinationPort: UInt16 = 520
    static let ripSourcePort: UInt16 = 521
    static let ripFirstBeaconDelayMilliseconds: UInt64 = 1_000
    static let ripTimeoutMilliseconds: UInt64 = 75_000

    mutating func setRIPEnabled(nodeID: UUID, enabled: Bool) {
        var ripEnabled = state.topologySnapshot.ripEnabledByNodeID
        if enabled { ripEnabled[nodeID] = true } else { ripEnabled.removeValue(forKey: nodeID) }
        state.topologySnapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: state.topologySnapshot.nodes,
            links: state.topologySnapshot.links,
            deviceConfigurations: state.topologySnapshot.deviceConfigurations,
            interfaceConfigurations: state.topologySnapshot.interfaceConfigurations,
            manualRoutesByNodeID: state.topologySnapshot.manualRoutesByNodeID,
            ripEnabledByNodeID: ripEnabled,
            dhcpClientConfigurationsByNodeID: state.topologySnapshot.dhcpClientConfigurationsByNodeID,
            dhcpServerConfigurationsByNodeID: state.topologySnapshot.dhcpServerConfigurationsByNodeID,
            firewallConfigurationsByNodeID: state.topologySnapshot.firewallConfigurationsByNodeID,
            portForwardingRowsByNodeID: state.topologySnapshot.portForwardingRowsByNodeID,
            switchConfigurationsByNodeID: state.topologySnapshot.switchConfigurationsByNodeID,
            remoteLinkConfigurationsByNodeID: state.topologySnapshot.remoteLinkConfigurationsByNodeID,
            hostWirelessConfigurationsByNodeID: state.topologySnapshot.hostWirelessConfigurationsByNodeID
        )
        state.pendingEvents.removeAll {
            if case let .ripBeacon(eventNodeID) = $0.kind { return eventNodeID == nodeID }
            return false
        }
        state.ripTablesByNodeID.removeValue(forKey: nodeID)
        guard enabled, nodeSnapshot(nodeID: nodeID)?.kind == .router else { return }
        let interfaces = networkInterfaces(nodeID: nodeID)
        state.ripTablesByNodeID[nodeID] = interfaces.compactMap { interface in
            guard let network = networkAddress(interface.ipAddress, mask: interface.subnetMask) else { return nil }
            return TopologyRuntimeRouteRow(
                destinationNetwork: network,
                subnetMask: interface.subnetMask,
                nextHop: interface.ipAddress,
                interfaceIPAddress: interface.ipAddress,
                origin: .connected,
                isEditable: false,
                metric: 0,
                expiresAtMilliseconds: nil
            )
        }
        _ = schedule(
            deadlineMilliseconds: state.currentTimeMilliseconds + Self.ripFirstBeaconDelayMilliseconds,
            kind: .ripBeacon(nodeID: nodeID)
        )
    }
    @discardableResult
    mutating func bindUDPSocket(
        nodeID: UUID,
        localPort: UInt16? = nil,
        localIPAddress: String? = nil,
        remoteIPAddress: String? = nil,
        remotePort: UInt16? = nil
    ) -> UUID? {
        guard state.phase == .running else { return nil }
        let reservedPort: UInt16
        if let localPort {
            guard !isUDPPortReserved(nodeID: nodeID, port: localPort) else { return nil }
            reservedPort = localPort
        } else {
            guard let port = reserveFreeUDPPort(nodeID: nodeID) else { return nil }
            reservedPort = port
        }
        if let localIPAddress,
           !networkInterfaces(nodeID: nodeID).contains(where: { $0.ipAddress == localIPAddress }) {
            return nil
        }
        let socketID = deterministicSocketID(sequence: state.nextSocketSequenceNumber)
        state.nextSocketSequenceNumber &+= 1
        state.socketsByID[socketID] = TopologyRuntimeSocketRecord(
            id: socketID,
            nodeID: nodeID,
            protocolKind: .udp,
            localIPAddress: localIPAddress,
            localPort: reservedPort,
            remoteIPAddress: remoteIPAddress,
            remotePort: remotePort,
            tcpState: nil,
            parentListenerSocketID: nil
        )
        state.udpReceiveQueuesBySocketID[socketID] = []
        return socketID
    }


    private func isUDPPortReserved(nodeID: UUID, port: UInt16) -> Bool {
        state.socketsByID.values.contains {
            $0.nodeID == nodeID && $0.protocolKind == .udp && $0.localPort == port
        } || state.natMappings.contains {
            $0.gatewayNodeID == nodeID
                && $0.protocolNumber == .udp
                && $0.translatedPortOrIdentifier == port
        }
    }

    private mutating func reserveFreeUDPPort(nodeID: UUID) -> UInt16? {
        let span = Self.udpEphemeralPortUpperBoundExclusive - Self.udpEphemeralPortLowerBound
        for _ in 0..<span {
            let candidate = Self.udpEphemeralPortLowerBound + udpPortRandom.nextInt(upperBound: span)
            let port = UInt16(candidate)
            if !isUDPPortReserved(nodeID: nodeID, port: port) { return port }
        }
        return nil
    }

    mutating func closeSocket(socketID: UUID) {
        if state.socketsByID[socketID]?.protocolKind == .tcp {
            closeTCPSocket(socketID: socketID)
            return
        }
        state.socketsByID.removeValue(forKey: socketID)
        state.udpReceiveQueuesBySocketID.removeValue(forKey: socketID)
    }

    mutating func discardSocket(socketID: UUID) {
        let childSocketIDs = state.tcpAcceptedSocketIDsByListenerID.removeValue(forKey: socketID) ?? []
        for childSocketID in childSocketIDs {
            state.socketsByID.removeValue(forKey: childSocketID)
            state.tcpSessionsByID.removeValue(forKey: childSocketID)
        }
        state.socketsByID.removeValue(forKey: socketID)
        state.tcpSessionsByID.removeValue(forKey: socketID)
        state.udpReceiveQueuesBySocketID.removeValue(forKey: socketID)
        for listenerID in Array(state.tcpAcceptedSocketIDsByListenerID.keys) {
            state.tcpAcceptedSocketIDsByListenerID[listenerID]?.removeAll { $0 == socketID }
        }
    }

    mutating func receiveUDP(socketID: UUID) -> TopologyRuntimeUDPReceivedDatagram? {
        guard var queue = state.udpReceiveQueuesBySocketID[socketID], !queue.isEmpty else { return nil }
        let datagram = queue.removeFirst()
        state.udpReceiveQueuesBySocketID[socketID] = queue
        return datagram
    }

    mutating func receiveUDP(
        socketID: UUID,
        timeoutMilliseconds: UInt64
    ) -> TopologyRuntimeUDPReceivedDatagram? {
        if let datagram = receiveUDP(socketID: socketID) { return datagram }
        guard timeoutMilliseconds > 0, state.phase == .running else { return nil }
        let (deadline, overflow) = state.currentTimeMilliseconds.addingReportingOverflow(timeoutMilliseconds)
        guard !overflow else { return nil }
        _ = advance(to: deadline)
        return receiveUDP(socketID: socketID)
    }

    @discardableResult
    mutating func sendUDP(
        socketID: UUID,
        payload: Data,
        destinationIPAddress: String? = nil,
        destinationPort: UInt16? = nil
    ) -> TopologyIPv4DeliveryResult? {
        guard let socket = state.socketsByID[socketID], socket.protocolKind == .udp else { return nil }
        guard let destinationIPAddress = destinationIPAddress ?? socket.remoteIPAddress,
              let destinationPort = destinationPort ?? socket.remotePort else { return nil }
        let interfaces = networkInterfaces(nodeID: socket.nodeID)
        guard !interfaces.isEmpty else { return nil }
        let boundInterface = socket.localIPAddress.flatMap { address in
            interfaces.first(where: { $0.ipAddress == address })
        }
        let packetIdentity = allocatePacketIdentity()

        if destinationIPAddress == Self.limitedBroadcastIPAddress {
            let broadcastInterfaces = boundInterface.map { [$0] } ?? interfaces
            for interface in broadcastInterfaces {
                let packet = TopologyIPv4Packet(
                    identity: packetIdentity,
                    senderIPAddress: interface.ipAddress,
                    receiverIPAddress: destinationIPAddress,
                    timeToLive: 1,
                    protocolNumber: .udp,
                    payload: .udp(TopologyUDPDatagram(
                        sourcePort: socket.localPort,
                        destinationPort: destinationPort,
                        payload: payload
                    ))
                )
                recordTrace(
                    packetIdentity: packet.identity,
                    nodeID: socket.nodeID,
                    interfaceID: interface.portID,
                    direction: .outbound,
                    layer: .transport,
                    operation: .sent,
                    afterHeaders: udpHeaders(
                        sourcePort: socket.localPort,
                        destinationPort: destinationPort,
                        payloadLength: payload.count
                    )
                )
                sendLimitedBroadcastPacket(fromNodeID: socket.nodeID, interface: interface, packet: packet)
            }
            return .delivered(packetIdentity: packetIdentity, nodeID: socket.nodeID)
        }

        let interface: TopologyRuntimeNetworkInterface
        if let boundInterface {
            interface = boundInterface
        } else if case let .egress(routeInterface, _) = routeForPacket(
            nodeID: socket.nodeID,
            targetIPAddress: destinationIPAddress
        ) {
            interface = routeInterface
        } else {
            interface = interfaces[0]
        }
        let packet = TopologyIPv4Packet(
            identity: packetIdentity,
            senderIPAddress: interface.ipAddress,
            receiverIPAddress: destinationIPAddress,
            timeToLive: 64,
            protocolNumber: .udp,
            payload: .udp(TopologyUDPDatagram(
                sourcePort: socket.localPort,
                destinationPort: destinationPort,
                payload: payload
            ))
        )
        recordTrace(
            packetIdentity: packet.identity,
            nodeID: socket.nodeID,
            interfaceID: interface.portID,
            direction: .outbound,
            layer: .transport,
            operation: .sent,
            afterHeaders: udpHeaders(
                sourcePort: socket.localPort,
                destinationPort: destinationPort,
                payloadLength: payload.count
            )
        )
        return sendIPv4Packet(fromNodeID: socket.nodeID, packet: packet, preferredInterfaceID: interface.portID)
    }

    private mutating func initializeRIPState() {
        state.ripTablesByNodeID.removeAll()
        for node in state.topologySnapshot.nodes where node.kind == .router {
            guard state.topologySnapshot.ripEnabledByNodeID[node.id] == true else { continue }
            let interfaces = networkInterfaces(nodeID: node.id)
            state.ripTablesByNodeID[node.id] = interfaces.compactMap { interface in
                guard let network = networkAddress(interface.ipAddress, mask: interface.subnetMask) else { return nil }
                return TopologyRuntimeRouteRow(
                    destinationNetwork: network,
                    subnetMask: interface.subnetMask,
                    nextHop: interface.ipAddress,
                    interfaceIPAddress: interface.ipAddress,
                    origin: .connected,
                    isEditable: false,
                    metric: 0,
                    expiresAtMilliseconds: nil
                )
            }
            _ = schedule(
                deadlineMilliseconds: state.currentTimeMilliseconds + Self.ripFirstBeaconDelayMilliseconds,
                kind: .ripBeacon(nodeID: node.id)
            )
        }
    }

    private mutating func scheduleRIPBeacon(nodeID: UUID, deadlineMilliseconds: UInt64) {
        let existingDeadline = state.pendingEvents.compactMap { event -> UInt64? in
            guard case let .ripBeacon(eventNodeID) = event.kind, eventNodeID == nodeID else { return nil }
            return event.deadlineMilliseconds
        }.min()
        if let existingDeadline, existingDeadline <= deadlineMilliseconds { return }
        state.pendingEvents.removeAll {
            if case let .ripBeacon(eventNodeID) = $0.kind { return eventNodeID == nodeID }
            return false
        }
        _ = schedule(deadlineMilliseconds: deadlineMilliseconds, kind: .ripBeacon(nodeID: nodeID))
    }
    private mutating func processScheduledRuntimeEvent(_ kind: TopologyNetworkRuntimeScheduledEventKind) {
        switch kind {
        case let .ripBeacon(nodeID):
            guard isRIPEnabledRouter(nodeID: nodeID) else { return }
            advertiseRIPRoutes(nodeID: nodeID)
            scheduleRIPBeacon(
                nodeID: nodeID,
                deadlineMilliseconds: state.currentTimeMilliseconds + nextRIPJitterMilliseconds()
            )
        case let .dhcpClientStart(nodeID):
            _ = runDHCPClient(nodeID: nodeID)
        case let .dhcpTimeout(nodeID):
            handleDHCPClientTimeout(nodeID: nodeID)
        case let .tcpTimeout(sessionID):
            handleTCPTimeout(socketID: sessionID)
        case let .ethernetLinkDelivery(_, targetNodeID, targetPortID, _, frame):
            receiveEthernetFrame(frame, atNodeID: targetNodeID, incomingPortID: targetPortID)
        case let .remoteLinkDelivery(
            sourceNodeID,
            partnerNodeID,
            partnerPortID,
            pairIdentifier,
            latencyMilliseconds,
            frame
        ):
            deliverRemoteLinkFrame(
                sourceNodeID: sourceNodeID,
                partnerNodeID: partnerNodeID,
                partnerPortID: partnerPortID,
                pairIdentifier: pairIdentifier,
                latencyMilliseconds: latencyMilliseconds,
                frame: frame
            )
        case .natExpirySweep:
            expireDynamicNATMappings()
            if state.topologySnapshot.nodes.contains(where: { $0.kind == .gateway }) {
                _ = schedule(
                    deadlineMilliseconds: state.currentTimeMilliseconds + Self.natExpirySweepIntervalMilliseconds,
                    kind: .natExpirySweep
                )
            }
        case .parityMarker:
            break
        }
    }

    private func isRIPEnabledRouter(nodeID: UUID) -> Bool {
        nodeSnapshot(nodeID: nodeID)?.kind == .router
            && state.topologySnapshot.ripEnabledByNodeID[nodeID] == true
    }

    private mutating func advertiseRIPRoutes(nodeID: UUID) {
        guard let table = state.ripTablesByNodeID[nodeID] else { return }
        let interfaces = networkInterfaces(nodeID: nodeID)
        guard let publicIPAddress = interfaces.first?.ipAddress else { return }
        for interface in interfaces {
            let routes = table.compactMap { route -> TopologyRuntimeRIPAdvertisementRoute? in
                guard route.interfaceIPAddress != interface.ipAddress else { return nil }
                return TopologyRuntimeRIPAdvertisementRoute(
                    destinationNetwork: route.destinationNetwork,
                    subnetMask: route.subnetMask,
                    metric: route.metric ?? Self.ripInfinity
                )
            }
            let advertisement = TopologyRuntimeRIPAdvertisement(
                senderIPAddress: interface.ipAddress,
                publicIPAddress: publicIPAddress,
                infinity: Self.ripInfinity,
                timeoutMilliseconds: Self.ripTimeoutMilliseconds,
                routes: routes
            )
            let packet = TopologyIPv4Packet(
                identity: allocatePacketIdentity(),
                senderIPAddress: interface.ipAddress,
                receiverIPAddress: Self.limitedBroadcastIPAddress,
                timeToLive: 1,
                protocolNumber: .udp,
                payload: .udp(TopologyUDPDatagram(
                    sourcePort: Self.ripSourcePort,
                    destinationPort: Self.ripDestinationPort,
                    payload: encodeRIPAdvertisement(advertisement)
                ))
            )
            recordTrace(
                packetIdentity: packet.identity,
                nodeID: nodeID,
                interfaceID: interface.portID,
                direction: .outbound,
                layer: .application,
                operation: .sent,
                detail: "RIP advertisement routes=\(routes.count)"
            )
            sendLimitedBroadcastPacket(fromNodeID: nodeID, interface: interface, packet: packet)
        }
    }

    private mutating func deliverUDP(
        packet: TopologyIPv4Packet,
        datagram: TopologyUDPDatagram,
        nodeID: UUID,
        interface: TopologyRuntimeNetworkInterface
    ) {
        let ripAdvertisement: TopologyRuntimeRIPAdvertisement?
        if datagram.destinationPort == Self.ripDestinationPort,
           datagram.sourcePort == Self.ripSourcePort,
           isRIPEnabledRouter(nodeID: nodeID) {
            ripAdvertisement = decodeRIPAdvertisement(datagram.payload)
        } else {
            ripAdvertisement = nil
        }
        if let ripAdvertisement {
            receiveRIPAdvertisement(ripAdvertisement, nodeID: nodeID, receivingInterface: interface)
        }

        processDHCPDatagram(
            packet: packet,
            datagram: datagram,
            nodeID: nodeID,
            receivingInterface: interface
        )

        let matchingSockets = state.socketsByID.values
            .filter { socket in
                socket.nodeID == nodeID
                    && socket.protocolKind == .udp
                    && socket.localPort == datagram.destinationPort
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        for socket in matchingSockets {
            state.udpReceiveQueuesBySocketID[socket.id, default: []].append(
                TopologyRuntimeUDPReceivedDatagram(
                    senderIPAddress: packet.senderIPAddress,
                    receiverIPAddress: packet.receiverIPAddress,
                    datagram: datagram,
                    receivedAtMilliseconds: state.currentTimeMilliseconds
                )
            )
            var connectedSocket = socket
            connectedSocket.remoteIPAddress = packet.senderIPAddress
            connectedSocket.remotePort = datagram.sourcePort
            state.socketsByID[socket.id] = connectedSocket
        }
        let wasAcceptedByRuntimeProtocol = ripAdvertisement != nil
        recordTrace(
            packetIdentity: packet.identity,
            nodeID: nodeID,
            interfaceID: interface.portID,
            direction: .local,
            layer: .transport,
            operation: matchingSockets.isEmpty && !wasAcceptedByRuntimeProtocol ? .dropped : .accepted,
            beforeHeaders: udpHeaders(
                sourcePort: datagram.sourcePort,
                destinationPort: datagram.destinationPort,
                payloadLength: datagram.payload.count
            ),
            detail: ripAdvertisement.map { "RIP advertisement routes=\($0.routes.count)" }
                ?? (matchingSockets.isEmpty ? "UDP destination port unbound" : "UDP queued")
        )
        if datagram.destinationPort == Self.dhcpClientPort,
           state.dhcpClientContextsByNodeID[nodeID] != nil {
            advanceDHCPClient(nodeID: nodeID)
        }
    }

    private mutating func receiveRIPAdvertisement(
        _ advertisement: TopologyRuntimeRIPAdvertisement,
        nodeID: UUID,
        receivingInterface: TopologyRuntimeNetworkInterface
    ) {
        let localAddresses = Set(networkInterfaces(nodeID: nodeID).map(\.ipAddress))
        guard !localAddresses.contains(advertisement.senderIPAddress),
              sameSubnet(
                receivingInterface.ipAddress,
                advertisement.senderIPAddress,
                mask: receivingInterface.subnetMask
              ) else { return }

        var table = state.ripTablesByNodeID[nodeID] ?? []
        var triggerAdvertisement = false
        for entry in advertisement.routes {
            let receivedMetric = entry.metric >= advertisement.infinity
                || entry.metric + 1 >= Self.ripInfinity
                ? Self.ripInfinity : entry.metric + 1
            if let index = table.firstIndex(where: {
                $0.destinationNetwork == entry.destinationNetwork && $0.subnetMask == entry.subnetMask
            }) {
                let existing = table[index]
                let existingMetric = existing.metric ?? Self.ripInfinity
                if existing.nextHop != advertisement.senderIPAddress && existingMetric <= receivedMetric {
                    continue
                }
                var nextHop = existing.nextHop
                var interfaceIPAddress = existing.interfaceIPAddress
                if existingMetric > receivedMetric {
                    nextHop = advertisement.senderIPAddress
                    interfaceIPAddress = receivingInterface.ipAddress
                } else if existingMetric < receivedMetric {
                    triggerAdvertisement = true
                }
                table[index] = TopologyRuntimeRouteRow(
                    destinationNetwork: existing.destinationNetwork,
                    subnetMask: existing.subnetMask,
                    nextHop: nextHop,
                    interfaceIPAddress: interfaceIPAddress,
                    origin: existing.origin,
                    isEditable: false,
                    metric: receivedMetric,
                    expiresAtMilliseconds: state.currentTimeMilliseconds + advertisement.timeoutMilliseconds
                )
            } else if receivedMetric < Self.ripInfinity {
                table.append(
                    TopologyRuntimeRouteRow(
                        destinationNetwork: entry.destinationNetwork,
                        subnetMask: entry.subnetMask,
                        nextHop: advertisement.senderIPAddress,
                        interfaceIPAddress: receivingInterface.ipAddress,
                        origin: .rip,
                        isEditable: false,
                        metric: receivedMetric,
                        expiresAtMilliseconds: state.currentTimeMilliseconds + advertisement.timeoutMilliseconds
                    )
                )
                triggerAdvertisement = true
            }
        }
        state.ripTablesByNodeID[nodeID] = table
        if triggerAdvertisement {
            scheduleRIPBeacon(nodeID: nodeID, deadlineMilliseconds: state.currentTimeMilliseconds)
        }
    }

    private mutating func expireRIPRoutes() {
        for nodeID in state.ripTablesByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard var table = state.ripTablesByNodeID[nodeID] else { continue }
            var changed = false
            for index in table.indices {
                guard let expiry = table[index].expiresAtMilliseconds,
                      expiry < state.currentTimeMilliseconds,
                      table[index].metric != Self.ripInfinity else { continue }
                let route = table[index]
                table[index] = TopologyRuntimeRouteRow(
                    destinationNetwork: route.destinationNetwork,
                    subnetMask: route.subnetMask,
                    nextHop: route.nextHop,
                    interfaceIPAddress: route.interfaceIPAddress,
                    origin: route.origin,
                    isEditable: false,
                    metric: Self.ripInfinity,
                    expiresAtMilliseconds: expiry
                )
                changed = true
            }
            if changed { state.ripTablesByNodeID[nodeID] = table }
        }
    }

    private func ripRouteForPacket(nodeID: UUID, targetIPAddress: String) -> RuntimePacketRoute {
        guard let target = parseIPv4(targetIPAddress) else { return .unavailable }
        let interfaces = networkInterfaces(nodeID: nodeID)
        var selected: TopologyRuntimeRouteRow?
        var selectedMetric: Int?
        var selectedMask: UInt32?
        for row in state.ripTablesByNodeID[nodeID] ?? [] {
            let metric = row.metric ?? Self.ripInfinity
            guard metric < Self.ripInfinity,
                  let destination = parseIPv4(row.destinationNetwork),
                  let mask = parseIPv4(row.subnetMask),
                  destination == (target & mask) else { continue }
            if let selectedMetric {
                if metric > selectedMetric { continue }
                if metric == selectedMetric, let selectedMask, mask <= selectedMask { continue }
            }
            selected = row
            selectedMetric = metric
            selectedMask = mask
        }
        guard let selected,
              let interface = interfaces.first(where: { $0.ipAddress == selected.interfaceIPAddress }) else {
            return .unavailable
        }
        let nextHop = sameSubnet(interface.ipAddress, targetIPAddress, mask: interface.subnetMask)
            ? targetIPAddress : selected.nextHop
        return .egress(interface, nextHop: nextHop)
    }

    private mutating func sendLimitedBroadcastPacket(
        fromNodeID: UUID,
        interface: TopologyRuntimeNetworkInterface,
        packet: TopologyIPv4Packet
    ) {
        let broadcastPacket = TopologyIPv4Packet(
            identity: packet.identity,
            senderIPAddress: interface.ipAddress,
            receiverIPAddress: Self.limitedBroadcastIPAddress,
            timeToLive: 1,
            protocolNumber: packet.protocolNumber,
            payload: packet.payload
        )
        let frame = TopologyEthernetFrame(
            identity: allocateFrameIdentity(),
            sourceMACAddress: interface.macAddress,
            destinationMACAddress: Self.ethernetBroadcastMACAddress,
            payload: .ipv4(broadcastPacket)
        )
        recordIPv4Send(
            packet: broadcastPacket,
            frame: frame,
            nodeID: fromNodeID,
            interfaceID: interface.portID,
            operation: .sent
        )
        sendEthernetFrame(fromNodeID: fromNodeID, outgoingPortID: interface.portID, frame: frame)
    }

    private func encodeRIPAdvertisement(_ advertisement: TopologyRuntimeRIPAdvertisement) -> Data {
        var lines = [
            advertisement.senderIPAddress,
            advertisement.publicIPAddress,
            String(advertisement.infinity),
            String(advertisement.timeoutMilliseconds),
        ]
        lines.append(contentsOf: advertisement.routes.map {
            "\($0.destinationNetwork) \($0.subnetMask) \($0.metric)"
        })
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func decodeRIPAdvertisement(_ data: Data) -> TopologyRuntimeRIPAdvertisement? {
        guard let value = String(data: data, encoding: .utf8) else { return nil }
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 4,
              parseIPv4(lines[0]) != nil,
              parseIPv4(lines[1]) != nil,
              let infinity = Int(lines[2]), infinity > 0,
              let timeout = UInt64(lines[3]), timeout > 0 else { return nil }
        var routes: [TopologyRuntimeRIPAdvertisementRoute] = []
        for line in lines.dropFirst(4) {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard fields.count == 3,
                  parseIPv4(fields[0]) != nil,
                  parseIPv4(fields[1]) != nil,
                  let metric = Int(fields[2]), metric >= 0 else { return nil }
            routes.append(
                TopologyRuntimeRIPAdvertisementRoute(
                    destinationNetwork: fields[0],
                    subnetMask: fields[1],
                    metric: metric
                )
            )
        }
        return TopologyRuntimeRIPAdvertisement(
            senderIPAddress: lines[0],
            publicIPAddress: lines[1],
            infinity: infinity,
            timeoutMilliseconds: timeout,
            routes: routes
        )
    }

    private func udpHeaders(
        sourcePort: UInt16,
        destinationPort: UInt16,
        payloadLength: Int
    ) -> [TopologyPacketHeaderField] {
        [
            TopologyPacketHeaderField(name: "sourcePort", value: String(sourcePort)),
            TopologyPacketHeaderField(name: "destinationPort", value: String(destinationPort)),
            TopologyPacketHeaderField(name: "payloadLength", value: String(payloadLength)),
        ]
    }

    private func deterministicSocketID(sequence: UInt64) -> UUID {
        let suffix = String(format: "%012llX", sequence)
        return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
    }

    private func networkAddress(_ ipAddress: String, mask: String) -> String? {
        guard let address = parseIPv4(ipAddress), let mask = parseIPv4(mask) else { return nil }
        let network = address & mask
        return [24, 16, 8, 0].map { String((network >> UInt32($0)) & 0xFF) }.joined(separator: ".")
    }
}


// MARK: - Java-compatible TCP sockets

extension TopologyNetworkRuntimeEngine {
    static let tcpMaximumSegmentSize = 1_460
    static let tcpMaximumSendAttempts = 3
    static let tcpRoundTripTimeMilliseconds: UInt64 = 2_500
    static let tcpDefaultTimeoutMilliseconds: UInt64 = UInt64(tcpMaximumSendAttempts) * tcpRoundTripTimeMilliseconds
    static let tcpEphemeralPortLowerBound = 49_152
    static let tcpEphemeralPortUpperBoundExclusive = 65_535

    @discardableResult
    mutating func openTCPServerSocket(
        nodeID: UUID,
        localPort: UInt16,
        localIPAddress: String? = nil
    ) -> UUID? {
        guard state.phase == .running,
              !isTCPPortReserved(nodeID: nodeID, port: localPort),
              localIPAddress == nil || networkInterfaces(nodeID: nodeID).contains(where: { $0.ipAddress == localIPAddress })
        else { return nil }

        let socketID = allocateSocketID()
        state.socketsByID[socketID] = TopologyRuntimeSocketRecord(
            id: socketID,
            nodeID: nodeID,
            protocolKind: .tcp,
            localIPAddress: localIPAddress,
            localPort: localPort,
            remoteIPAddress: nil,
            remotePort: nil,
            tcpState: .listen,
            parentListenerSocketID: nil
        )
        state.tcpSessionsByID[socketID] = makeTCPSession(socketID: socketID, state: .listen)
        state.tcpAcceptedSocketIDsByListenerID[socketID] = []
        recordTCPStateTransition(socketID: socketID, from: .closed, to: .listen)
        return socketID
    }

    @discardableResult
    mutating func openTCPClientSocket(
        nodeID: UUID,
        remoteIPAddress: String,
        remotePort: UInt16,
        localIPAddress: String? = nil,
        localPort: UInt16? = nil
    ) -> UUID? {
        guard state.phase == .running else { return nil }
        let resolvedLocalIPAddress: String?
        if let localIPAddress {
            guard networkInterfaces(nodeID: nodeID).contains(where: { $0.ipAddress == localIPAddress }) else { return nil }
            resolvedLocalIPAddress = localIPAddress
        } else if case let .egress(interface, _) = routeForPacket(nodeID: nodeID, targetIPAddress: remoteIPAddress) {
            resolvedLocalIPAddress = interface.ipAddress
        } else {
            resolvedLocalIPAddress = networkInterfaces(nodeID: nodeID).first?.ipAddress
        }
        guard let resolvedLocalIPAddress else { return nil }

        let reservedPort: UInt16
        if let localPort {
            guard !isTCPPortReserved(nodeID: nodeID, port: localPort) else { return nil }
            reservedPort = localPort
        } else {
            guard let port = reserveFreeTCPPort(nodeID: nodeID) else { return nil }
            reservedPort = port
        }

        let socketID = allocateSocketID()
        state.socketsByID[socketID] = TopologyRuntimeSocketRecord(
            id: socketID,
            nodeID: nodeID,
            protocolKind: .tcp,
            localIPAddress: resolvedLocalIPAddress,
            localPort: reservedPort,
            remoteIPAddress: remoteIPAddress,
            remotePort: remotePort,
            tcpState: .closed,
            parentListenerSocketID: nil
        )
        state.tcpSessionsByID[socketID] = makeTCPSession(socketID: socketID, state: .closed)
        return socketID
    }

    func isTCPPortReserved(nodeID: UUID, port: UInt16) -> Bool {
        state.socketsByID.values.contains { socket in
            socket.nodeID == nodeID
                && socket.protocolKind == .tcp
                && socket.localPort == port
                && socket.parentListenerSocketID == nil
                && socket.tcpState != .closed
        } || state.natMappings.contains {
            $0.gatewayNodeID == nodeID
                && $0.protocolNumber == .tcp
                && $0.translatedPortOrIdentifier == port
        }
    }

    @discardableResult
    mutating func connectTCP(socketID: UUID) -> Bool {
        connectTCPWithResult(socketID: socketID) == .connected
    }

    @discardableResult
    mutating func connectTCPWithResult(socketID: UUID) -> TopologyTCPConnectionResult {
        guard let socket = state.socketsByID[socketID],
              socket.protocolKind == .tcp,
              socket.parentListenerSocketID == nil,
              socket.remoteIPAddress != nil,
              socket.remotePort != nil,
              socket.tcpState == .closed,
              !state.socketsByID.values.contains(where: {
                  $0.id != socketID
                      && $0.nodeID == socket.nodeID
                      && $0.protocolKind == .tcp
                      && $0.localPort == socket.localPort
                      && $0.parentListenerSocketID == nil
                      && $0.tcpState != .closed
              }) else { return .invalidSocket }

        updateTCPState(socketID: socketID, to: .synSent)
        resetTCPSendAttempts(socketID: socketID)
        let initialDelivery = transmitTCPSegment(
            socketID: socketID,
            flags: [.synchronize],
            payload: Data(),
            acknowledgementNumber: 0,
            detail: "TCP SYN"
        )
        let waitedForTimeout = advanceTCPUntilSettled(socketID: socketID, waitingStates: [.synSent])
        if state.socketsByID[socketID]?.tcpState == .established {
            return .connected
        }
        switch initialDelivery {
        case .icmpError, .dropped, .none:
            return .unreachable
        case .delivered:
            return waitedForTimeout ? .timedOut : .unreachable
        }
    }

    @discardableResult
    mutating func sendTCP(socketID: UUID, payload: Data) -> Bool {
        guard state.socketsByID[socketID]?.tcpState == .established else { return false }
        let chunks: [Data]
        if payload.isEmpty {
            chunks = [Data()]
        } else {
            chunks = stride(from: 0, to: payload.count, by: Self.tcpMaximumSegmentSize).map { offset in
                payload.subdata(in: offset..<min(offset + Self.tcpMaximumSegmentSize, payload.count))
            }
        }

        for (index, chunk) in chunks.enumerated() {
            guard state.socketsByID[socketID]?.tcpState == .established else { return false }
            resetTCPSendAttempts(socketID: socketID)
            let flags: TopologyTCPFlags = index == chunks.count - 1 ? [.push] : []
            transmitTCPSegment(
                socketID: socketID,
                flags: flags,
                payload: chunk,
                acknowledgementNumber: 0,
                detail: "TCP data segment \(index + 1)/\(chunks.count)"
            )
            advanceTCPUntilSettled(socketID: socketID, waitingForAcknowledgement: true)
            guard let session = state.tcpSessionsByID[socketID],
                  session.state == .established,
                  session.lastSentSegment == nil else { return false }
        }
        return true
    }

    mutating func receiveTCP(socketID: UUID) -> Data? {
        guard var session = state.tcpSessionsByID[socketID], !session.receivedMessages.isEmpty else { return nil }
        let message = session.receivedMessages.removeFirst()
        state.tcpSessionsByID[socketID] = session
        return message
    }

    mutating func closeTCPSocket(socketID: UUID) {
        guard let socket = state.socketsByID[socketID], socket.protocolKind == .tcp,
              let currentState = socket.tcpState else { return }
        switch currentState {
        case .listen, .synSent:
            updateTCPState(socketID: socketID, to: .closed)
            clearTCPPendingTransmission(socketID: socketID)
        case .established, .synReceived:
            updateTCPState(socketID: socketID, to: .finishWait1)
            resetTCPSendAttempts(socketID: socketID)
            transmitTCPSegment(
                socketID: socketID,
                flags: [.finish],
                payload: Data(),
                acknowledgementNumber: 0,
                detail: "TCP FIN"
            )
        case .closeWait:
            updateTCPState(socketID: socketID, to: .lastAcknowledgement)
            resetTCPSendAttempts(socketID: socketID)
            transmitTCPSegment(
                socketID: socketID,
                flags: [.finish],
                payload: Data(),
                acknowledgementNumber: 0,
                detail: "TCP FIN after CLOSE_WAIT"
            )
        case .closed, .lastAcknowledgement, .finishWait1, .finishWait2, .closing, .timeWait:
            break
        }
    }

    func peerTCPSocketID(socketID: UUID) -> UUID? {
        guard let socket = state.socketsByID[socketID],
              socket.protocolKind == .tcp,
              let localIPAddress = socket.localIPAddress,
              let remoteIPAddress = socket.remoteIPAddress,
              let remotePort = socket.remotePort else { return nil }

        return state.socketsByID.values
            .filter { candidate in
                candidate.id != socketID
                    && candidate.protocolKind == .tcp
                    && candidate.tcpState != .listen
                    && candidate.localIPAddress == remoteIPAddress
                    && candidate.localPort == remotePort
                    && candidate.remoteIPAddress == localIPAddress
                    && candidate.remotePort == socket.localPort
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .first?.id
    }

    @discardableResult
    mutating func cleanClosedTCPSocket(socketID: UUID) -> Bool {
        guard state.socketsByID[socketID]?.protocolKind == .tcp,
              state.socketsByID[socketID]?.tcpState == .closed else { return false }

        cancelTCPTimeouts(socketID: socketID)
        state.socketsByID.removeValue(forKey: socketID)
        state.tcpSessionsByID.removeValue(forKey: socketID)
        state.tcpAcceptedSocketIDsByListenerID.removeValue(forKey: socketID)
        for listenerID in Array(state.tcpAcceptedSocketIDsByListenerID.keys) {
            state.tcpAcceptedSocketIDsByListenerID[listenerID]?.removeAll { $0 == socketID }
        }
        return true
    }

    private mutating func deliverTCP(
        packet: TopologyIPv4Packet,
        segment: TopologyTCPSegment,
        nodeID: UUID,
        interface: TopologyRuntimeNetworkInterface
    ) {
        recordTrace(
            packetIdentity: packet.identity,
            nodeID: nodeID,
            interfaceID: interface.portID,
            direction: .local,
            layer: .transport,
            operation: .accepted,
            beforeHeaders: tcpHeaders(segment),
            detail: "TCP segment received"
        )

        let exactSocketID = state.socketsByID.values
            .filter { socket in
                socket.nodeID == nodeID
                    && socket.protocolKind == .tcp
                    && socket.tcpState != .listen
                    && socket.tcpState != .closed
                    && socket.localPort == segment.destinationPort
                    && (socket.localIPAddress == nil || socket.localIPAddress == packet.receiverIPAddress)
                    && socket.remoteIPAddress == packet.senderIPAddress
                    && socket.remotePort == segment.sourcePort
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .first?.id
        if let exactSocketID {
            processIncomingTCPSegment(socketID: exactSocketID, segment: segment)
            return
        }

        let listener = state.socketsByID.values
            .filter { socket in
                socket.nodeID == nodeID
                    && socket.protocolKind == .tcp
                    && socket.tcpState == .listen
                    && socket.localPort == segment.destinationPort
                    && (socket.localIPAddress == nil || socket.localIPAddress == packet.receiverIPAddress)
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .first
        guard let listener,
              segment.flags.contains(.synchronize),
              !segment.flags.contains(.acknowledgement) else {
            recordTrace(
                packetIdentity: packet.identity,
                nodeID: nodeID,
                interfaceID: interface.portID,
                direction: .local,
                layer: .transport,
                operation: .dropped,
                beforeHeaders: tcpHeaders(segment),
                detail: "TCP destination port closed"
            )
            return
        }

        let acceptedSocketID = allocateSocketID()
        state.socketsByID[acceptedSocketID] = TopologyRuntimeSocketRecord(
            id: acceptedSocketID,
            nodeID: nodeID,
            protocolKind: .tcp,
            localIPAddress: packet.receiverIPAddress,
            localPort: segment.destinationPort,
            remoteIPAddress: packet.senderIPAddress,
            remotePort: segment.sourcePort,
            tcpState: .synReceived,
            parentListenerSocketID: listener.id
        )
        var acceptedSession = makeTCPSession(socketID: acceptedSocketID, state: .synReceived)
        acceptedSession.remoteSequenceNumber = nextTCPSequenceNumber(after: segment)
        state.tcpSessionsByID[acceptedSocketID] = acceptedSession
        state.tcpAcceptedSocketIDsByListenerID[listener.id, default: []].append(acceptedSocketID)
        recordTCPStateTransition(socketID: acceptedSocketID, from: .listen, to: .synReceived)
        resetTCPSendAttempts(socketID: acceptedSocketID)
        transmitTCPSegment(
            socketID: acceptedSocketID,
            flags: [.synchronize, .acknowledgement],
            payload: Data(),
            acknowledgementNumber: acceptedSession.remoteSequenceNumber,
            detail: "TCP SYN+ACK"
        )
    }

    private mutating func processIncomingTCPSegment(socketID: UUID, segment: TopologyTCPSegment) {
        guard let socket = state.socketsByID[socketID], let currentState = socket.tcpState else { return }
        if segment.flags.contains(.reset) {
            clearTCPPendingTransmission(socketID: socketID)
            updateTCPState(socketID: socketID, to: .closed)
            return
        }

        switch currentState {
        case .synSent:
            guard segment.flags.contains(.synchronize),
                  segment.flags.contains(.acknowledgement),
                  acknowledgeTCPIfExpected(socketID: socketID, acknowledgementNumber: segment.acknowledgementNumber)
            else {
                updateTCPState(socketID: socketID, to: .closed)
                return
            }
            if var session = state.tcpSessionsByID[socketID] {
                session.remoteSequenceNumber = nextTCPSequenceNumber(after: segment)
                state.tcpSessionsByID[socketID] = session
            }
            updateTCPState(socketID: socketID, to: .established)
            sendTCPAcknowledgement(socketID: socketID, acknowledging: segment)

        case .synReceived:
            guard segment.flags.contains(.acknowledgement),
                  acknowledgeTCPIfExpected(socketID: socketID, acknowledgementNumber: segment.acknowledgementNumber)
            else { return }
            updateTCPState(socketID: socketID, to: .established)

        case .established:
            if segment.flags.contains(.finish) {
                sendTCPAcknowledgement(socketID: socketID, acknowledging: segment)
                updateTCPState(socketID: socketID, to: .closeWait)
            } else if !segment.payload.isEmpty || segment.flags.contains(.push) {
                receiveTCPPayload(socketID: socketID, segment: segment)
            } else if segment.flags.contains(.acknowledgement) {
                _ = acknowledgeTCPIfExpected(socketID: socketID, acknowledgementNumber: segment.acknowledgementNumber)
            }

        case .finishWait1:
            let hasACK = segment.flags.contains(.acknowledgement)
            let hasFIN = segment.flags.contains(.finish)
            if hasACK { _ = acknowledgeTCPIfExpected(socketID: socketID, acknowledgementNumber: segment.acknowledgementNumber) }
            if hasACK && hasFIN {
                sendTCPAcknowledgement(socketID: socketID, acknowledging: segment)
                enterTCPTimeWait(socketID: socketID)
            } else if hasACK {
                updateTCPState(socketID: socketID, to: .finishWait2)
            } else if hasFIN {
                sendTCPAcknowledgement(socketID: socketID, acknowledging: segment)
                updateTCPState(socketID: socketID, to: .closing)
            }

        case .finishWait2:
            if segment.flags.contains(.finish) {
                sendTCPAcknowledgement(socketID: socketID, acknowledging: segment)
                enterTCPTimeWait(socketID: socketID)
            }

        case .closing:
            if segment.flags.contains(.acknowledgement),
               acknowledgeTCPIfExpected(socketID: socketID, acknowledgementNumber: segment.acknowledgementNumber) {
                enterTCPTimeWait(socketID: socketID)
            }

        case .lastAcknowledgement:
            if segment.flags.contains(.acknowledgement),
               acknowledgeTCPIfExpected(socketID: socketID, acknowledgementNumber: segment.acknowledgementNumber) {
                updateTCPState(socketID: socketID, to: .closed)
            }

        case .closeWait, .timeWait, .listen, .closed:
            break
        }
    }

    private mutating func receiveTCPPayload(socketID: UUID, segment: TopologyTCPSegment) {
        guard var session = state.tcpSessionsByID[socketID] else { return }
        let nextRemoteSequence = nextTCPSequenceNumber(after: segment)
        if nextRemoteSequence > session.remoteSequenceNumber {
            session.remoteSequenceNumber = nextRemoteSequence
            session.receiveAssembly.append(segment.payload)
            if segment.flags.contains(.push) {
                session.receivedMessages.append(session.receiveAssembly)
                session.receiveAssembly.removeAll(keepingCapacity: true)
            }
            state.tcpSessionsByID[socketID] = session
        }
        sendTCPAcknowledgement(socketID: socketID, acknowledging: segment)
    }

    private mutating func sendTCPAcknowledgement(socketID: UUID, acknowledging segment: TopologyTCPSegment) {
        transmitTCPSegment(
            socketID: socketID,
            flags: [.acknowledgement],
            payload: Data(),
            acknowledgementNumber: nextTCPSequenceNumber(after: segment),
            detail: "TCP ACK"
        )
    }

    @discardableResult
    private mutating func transmitTCPSegment(
        socketID: UUID,
        flags: TopologyTCPFlags,
        payload: Data,
        acknowledgementNumber: UInt32,
        detail: String,
        retransmission: Bool = false
    ) -> TopologyIPv4DeliveryResult? {
        guard let socket = state.socketsByID[socketID],
              let remoteIPAddress = socket.remoteIPAddress,
              let remotePort = socket.remotePort,
              var session = state.tcpSessionsByID[socketID] else { return nil }

        let segment: TopologyTCPSegment
        if retransmission, let last = session.lastSentSegment {
            segment = last
            session.sendAttempts += 1
        } else {
            segment = TopologyTCPSegment(
                sourcePort: socket.localPort,
                destinationPort: remotePort,
                sequenceNumber: session.nextSendSequenceNumber,
                acknowledgementNumber: acknowledgementNumber,
                flags: flags,
                payload: payload
            )
            session.lastSentSequenceNumber = segment.sequenceNumber
            session.nextSendSequenceNumber = nextTCPSequenceNumber(after: segment)
            if tcpSegmentRequiresAcknowledgement(segment) {
                session.lastSentSegment = segment
                session.sendAttempts = 1
            }
        }
        state.tcpSessionsByID[socketID] = session

        let interfaces = networkInterfaces(nodeID: socket.nodeID)
        let selectedInterface: TopologyRuntimeNetworkInterface?
        if let localIPAddress = socket.localIPAddress,
           let boundInterface = interfaces.first(where: { $0.ipAddress == localIPAddress }) {
            selectedInterface = boundInterface
        } else if case let .egress(routeInterface, _) = routeForPacket(
            nodeID: socket.nodeID,
            targetIPAddress: remoteIPAddress
        ) {
            selectedInterface = routeInterface
        } else {
            selectedInterface = interfaces.first
        }
        guard let interface = selectedInterface else { return nil }
        let packet = TopologyIPv4Packet(
            identity: allocatePacketIdentity(),
            senderIPAddress: interface.ipAddress,
            receiverIPAddress: remoteIPAddress,
            timeToLive: 64,
            protocolNumber: .tcp,
            payload: .tcp(segment)
        )
        recordTrace(
            packetIdentity: packet.identity,
            nodeID: socket.nodeID,
            interfaceID: interface.portID,
            direction: .outbound,
            layer: .transport,
            operation: retransmission ? .retransmitted : .sent,
            afterHeaders: tcpHeaders(segment),
            detail: retransmission ? "\(detail) retransmission attempt \(session.sendAttempts)" : detail
        )
        let delivery = sendIPv4Packet(fromNodeID: socket.nodeID, packet: packet, preferredInterfaceID: interface.portID)

        if state.tcpSessionsByID[socketID]?.lastSentSegment != nil {
            scheduleTCPTimeoutIfNeeded(socketID: socketID)
        }
        return delivery
    }

    private mutating func scheduleTCPTimeoutIfNeeded(socketID: UUID) {
        guard !state.pendingEvents.contains(where: {
            if case let .tcpTimeout(sessionID) = $0.kind { return sessionID == socketID }
            return false
        }) else { return }
        _ = schedule(
            deadlineMilliseconds: state.currentTimeMilliseconds + Self.tcpDefaultTimeoutMilliseconds,
            kind: .tcpTimeout(sessionID: socketID)
        )
    }

    private mutating func handleTCPTimeout(socketID: UUID) {
        guard let socket = state.socketsByID[socketID], let currentState = socket.tcpState else { return }
        if currentState == .timeWait {
            updateTCPState(socketID: socketID, to: .closed)
            clearTCPPendingTransmission(socketID: socketID)
            return
        }
        guard let session = state.tcpSessionsByID[socketID], let last = session.lastSentSegment else { return }
        guard session.sendAttempts < Self.tcpMaximumSendAttempts else {
            clearTCPPendingTransmission(socketID: socketID)
            updateTCPState(socketID: socketID, to: .closed)
            return
        }
        let baseDetail: String
        if last.flags.contains(.synchronize) && !last.flags.contains(.acknowledgement) {
            baseDetail = "TCP SYN"
        } else if last.flags.contains(.synchronize) {
            baseDetail = "TCP SYN+ACK"
        } else if last.flags.contains(.finish) {
            baseDetail = "TCP FIN"
        } else {
            baseDetail = "TCP data"
        }
        transmitTCPSegment(
            socketID: socketID,
            flags: last.flags,
            payload: last.payload,
            acknowledgementNumber: last.acknowledgementNumber,
            detail: baseDetail,
            retransmission: true
        )
    }

    private mutating func acknowledgeTCPIfExpected(socketID: UUID, acknowledgementNumber: UInt32) -> Bool {
        guard var session = state.tcpSessionsByID[socketID],
              session.lastSentSegment != nil,
              acknowledgementNumber == session.nextSendSequenceNumber else { return false }
        session.lastAcknowledgedSequenceNumber = acknowledgementNumber
        session.lastSentSegment = nil
        state.tcpSessionsByID[socketID] = session
        cancelTCPTimeouts(socketID: socketID)
        return true
    }

    private mutating func clearTCPPendingTransmission(socketID: UUID) {
        if var session = state.tcpSessionsByID[socketID] {
            session.lastSentSegment = nil
            state.tcpSessionsByID[socketID] = session
        }
        cancelTCPTimeouts(socketID: socketID)
    }

    private mutating func cancelTCPTimeouts(socketID: UUID) {
        state.pendingEvents.removeAll { event in
            if case let .tcpTimeout(sessionID) = event.kind { return sessionID == socketID }
            return false
        }
    }

    private mutating func enterTCPTimeWait(socketID: UUID) {
        clearTCPPendingTransmission(socketID: socketID)
        updateTCPState(socketID: socketID, to: .timeWait)
        _ = schedule(
            deadlineMilliseconds: state.currentTimeMilliseconds + Self.tcpRoundTripTimeMilliseconds,
            kind: .tcpTimeout(sessionID: socketID)
        )
    }

    @discardableResult
    private mutating func advanceTCPUntilSettled(
        socketID: UUID,
        waitingStates: Set<TopologyTCPSocketState> = [],
        waitingForAcknowledgement: Bool = false
    ) -> Bool {
        var advancedToTimeout = false
        while state.phase == .running {
            guard let socket = state.socketsByID[socketID], let socketState = socket.tcpState else { return advancedToTimeout }
            let waitingOnState = waitingStates.contains(socketState)
            let waitingOnACK = waitingForAcknowledgement && state.tcpSessionsByID[socketID]?.lastSentSegment != nil
            guard waitingOnState || waitingOnACK else { return advancedToTimeout }
            guard let deadline = state.pendingEvents.compactMap({ event -> UInt64? in
                if case let .tcpTimeout(sessionID) = event.kind, sessionID == socketID { return event.deadlineMilliseconds }
                return nil
            }).min() else { return advancedToTimeout }
            advancedToTimeout = true
            _ = advance(to: deadline)
        }
        return advancedToTimeout
    }

    private mutating func updateTCPState(socketID: UUID, to newState: TopologyTCPSocketState) {
        guard var socket = state.socketsByID[socketID], let oldState = socket.tcpState else { return }
        guard oldState != newState else { return }
        socket.tcpState = newState
        state.socketsByID[socketID] = socket
        if var session = state.tcpSessionsByID[socketID] {
            session.state = newState
            state.tcpSessionsByID[socketID] = session
        }
        recordTCPStateTransition(socketID: socketID, from: oldState, to: newState)
    }

    private mutating func recordTCPStateTransition(
        socketID: UUID,
        from oldState: TopologyTCPSocketState,
        to newState: TopologyTCPSocketState
    ) {
        guard let socket = state.socketsByID[socketID] else { return }
        recordTrace(
            nodeID: socket.nodeID,
            direction: .local,
            layer: .transport,
            operation: .accepted,
            beforeHeaders: [TopologyPacketHeaderField(name: "state", value: oldState.rawValue)],
            afterHeaders: [TopologyPacketHeaderField(name: "state", value: newState.rawValue)],
            detail: "TCP \(oldState.rawValue) -> \(newState.rawValue)"
        )
    }

    private mutating func resetTCPSendAttempts(socketID: UUID) {
        guard var session = state.tcpSessionsByID[socketID] else { return }
        session.sendAttempts = 0
        state.tcpSessionsByID[socketID] = session
    }

    private mutating func reserveFreeTCPPort(nodeID: UUID) -> UInt16? {
        let span = Self.tcpEphemeralPortUpperBoundExclusive - Self.tcpEphemeralPortLowerBound
        for _ in 0..<span {
            let candidate = Self.tcpEphemeralPortLowerBound + tcpPortRandom.nextInt(upperBound: span)
            let port = UInt16(candidate)
            if !isTCPPortReserved(nodeID: nodeID, port: port) { return port }
        }
        return nil
    }

    private mutating func allocateSocketID() -> UUID {
        let socketID = deterministicSocketID(sequence: state.nextSocketSequenceNumber)
        state.nextSocketSequenceNumber &+= 1
        return socketID
    }

    private mutating func allocateTCPInitialSequenceNumber() -> UInt32 {
        let raw = (state.nextTCPInitialSequenceValue % 4_294_967_296) * 1_000_000
        state.nextTCPInitialSequenceValue &+= 1
        return UInt32(truncatingIfNeeded: raw)
    }

    private mutating func makeTCPSession(
        socketID: UUID,
        state socketState: TopologyTCPSocketState
    ) -> TopologyRuntimeTCPSessionRecord {
        let initialSequence = allocateTCPInitialSequenceNumber()
        return TopologyRuntimeTCPSessionRecord(
            id: socketID,
            socketID: socketID,
            state: socketState,
            sendAttempts: 0,
            nextSendSequenceNumber: initialSequence,
            lastSentSequenceNumber: initialSequence,
            remoteSequenceNumber: 0,
            lastAcknowledgedSequenceNumber: nil,
            lastSentSegment: nil,
            receiveAssembly: Data(),
            receivedMessages: []
        )
    }

    private func tcpSegmentRequiresAcknowledgement(_ segment: TopologyTCPSegment) -> Bool {
        segment.flags.contains(.synchronize)
            || segment.flags.contains(.finish)
            || segment.flags.contains(.push)
            || !segment.payload.isEmpty
    }

    private func nextTCPSequenceNumber(after segment: TopologyTCPSegment) -> UInt32 {
        var next = segment.sequenceNumber
        if segment.flags.contains(.synchronize) || segment.flags.contains(.finish) { next &+= 1 }
        next &+= UInt32(truncatingIfNeeded: segment.payload.count)
        return next
    }

    private func tcpHeaders(_ segment: TopologyTCPSegment) -> [TopologyPacketHeaderField] {
        [
            TopologyPacketHeaderField(name: "sourcePort", value: String(segment.sourcePort)),
            TopologyPacketHeaderField(name: "destinationPort", value: String(segment.destinationPort)),
            TopologyPacketHeaderField(name: "sequenceNumber", value: String(segment.sequenceNumber)),
            TopologyPacketHeaderField(name: "acknowledgementNumber", value: String(segment.acknowledgementNumber)),
            TopologyPacketHeaderField(name: "flags", value: tcpFlagDescription(segment.flags)),
            TopologyPacketHeaderField(name: "payloadLength", value: String(segment.payload.count)),
        ]
    }

    private func tcpFlagDescription(_ flags: TopologyTCPFlags) -> String {
        var names: [String] = []
        if flags.contains(.finish) { names.append("FIN") }
        if flags.contains(.synchronize) { names.append("SYN") }
        if flags.contains(.reset) { names.append("RST") }
        if flags.contains(.push) { names.append("PSH") }
        if flags.contains(.acknowledgement) { names.append("ACK") }
        return names.joined(separator: "+")
    }
}
// MARK: - DHCP server and automatic client

extension TopologyNetworkRuntimeEngine {
    static let dhcpServerPort: UInt16 = 67
    static let dhcpClientPort: UInt16 = 68
    static let dhcpRoundTripTimeMilliseconds: UInt64 = 2_500
    static let dhcpOfferLifetimeMilliseconds: UInt64 = 4 * dhcpRoundTripTimeMilliseconds
    static let dhcpDynamicLeaseLifetimeMilliseconds: UInt64 = 24 * 60 * 60 * 1_000
    static let dhcpMaximumClientErrorCount = 10

    private mutating func initializeDHCPState() {
        state.dhcpOffersByIPAddress.removeAll()
        state.dhcpLeasesByIPAddress.removeAll()
        state.dhcpBlacklistByServerNodeID.removeAll()
        state.dhcpLastOfferedAddressByServerNodeID.removeAll()
        state.dhcpServerSocketIDsByNodeID.removeAll()
        state.dhcpClientStatusesByNodeID.removeAll()
        state.dhcpClientContextsByNodeID.removeAll()

        for node in state.topologySnapshot.nodes {
            guard state.topologySnapshot.dhcpServerConfigurationsByNodeID[node.id]?.isActive == true,
                  let interface = dhcpServerInterface(nodeID: node.id),
                  let socketID = bindUDPSocket(
                    nodeID: node.id,
                    localPort: Self.dhcpServerPort,
                    localIPAddress: interface.ipAddress,
                    remoteIPAddress: Self.limitedBroadcastIPAddress,
                    remotePort: Self.dhcpClientPort
                  ) else { continue }
            state.dhcpServerSocketIDsByNodeID[node.id] = socketID
        }

        for node in state.topologySnapshot.nodes {
            guard state.topologySnapshot.dhcpClientConfigurationsByNodeID[node.id]?.isEnabled == true,
                  node.kind.isPCClassEndpoint || node.kind == .gateway else { continue }
            state.dhcpClientStatusesByNodeID[node.id] = TopologyRuntimeDHCPClientStatus(
                state: .initialize,
                errorCount: 0,
                selectedServerIPAddress: nil,
                offeredIPAddress: nil,
                succeeded: false
            )
            _ = schedule(
                deadlineMilliseconds: state.currentTimeMilliseconds,
                kind: .dhcpClientStart(nodeID: node.id)
            )
        }
    }

    @discardableResult
    mutating func runDHCPClient(nodeID: UUID) -> TopologyRuntimeDHCPClientStatus? {
        guard state.phase == .running,
              state.topologySnapshot.dhcpClientConfigurationsByNodeID[nodeID]?.isEnabled == true,
              let node = nodeSnapshot(nodeID: nodeID),
              node.kind.isPCClassEndpoint || node.kind == .gateway,
              let clientInterface = dhcpClientInterface(nodeID: nodeID) else { return nil }

        if state.dhcpClientContextsByNodeID[nodeID] != nil {
            advanceDHCPClient(nodeID: nodeID)
            return state.dhcpClientStatusesByNodeID[nodeID]
        }

        let oldDeviceConfiguration = state.topologySnapshot.deviceConfigurations[nodeID]
        let oldInterfaceConfiguration = state.topologySnapshot.interfaceConfigurations[
            TopologyRuntimeInterfaceKey(nodeID: nodeID, portID: clientInterface.portID)
        ]
        setDHCPClientIPAddress(
            nodeID: nodeID,
            interfaceID: clientInterface.portID,
            ipAddress: Self.unspecifiedIPAddress
        )

        guard let resetInterface = networkInterfaces(nodeID: nodeID).first(where: { $0.portID == clientInterface.portID }),
              let socketID = bindUDPSocket(
                nodeID: nodeID,
                localPort: Self.dhcpClientPort,
                localIPAddress: resetInterface.ipAddress,
                remoteIPAddress: Self.limitedBroadcastIPAddress,
                remotePort: Self.dhcpServerPort
              ) else {
            restoreDHCPClientOldIPAddress(
                nodeID: nodeID,
                interfaceID: clientInterface.portID,
                deviceConfiguration: oldDeviceConfiguration,
                interfaceConfiguration: oldInterfaceConfiguration
            )
            return nil
        }

        state.dhcpClientContextsByNodeID[nodeID] = TopologyRuntimeDHCPClientContext(
            interfaceID: clientInterface.portID,
            socketID: socketID,
            clientMACAddress: resetInterface.macAddress,
            oldDeviceConfiguration: oldDeviceConfiguration,
            oldInterfaceConfiguration: oldInterfaceConfiguration,
            selectedOffer: nil
        )
        state.dhcpClientStatusesByNodeID[nodeID] = TopologyRuntimeDHCPClientStatus(
            state: .initialize,
            errorCount: 0,
            selectedServerIPAddress: nil,
            offeredIPAddress: nil,
            succeeded: false
        )
        advanceDHCPClient(nodeID: nodeID)
        return state.dhcpClientStatusesByNodeID[nodeID]
    }

    private mutating func advanceDHCPClient(nodeID: UUID) {
        while state.phase == .running,
              var context = state.dhcpClientContextsByNodeID[nodeID],
              var status = state.dhcpClientStatusesByNodeID[nodeID],
              status.state != .finish {
            switch status.state {
            case .initialize:
                status.state = .discover
                state.dhcpClientStatusesByNodeID[nodeID] = status

            case .discover:
                let discover = TopologyRuntimeDHCPMessage(
                    type: .discover,
                    clientMACAddress: context.clientMACAddress
                )
                _ = sendDHCPMessage(socketID: context.socketID, message: discover)
                guard let offer = receiveDHCPResponse(
                    socketID: context.socketID,
                    clientMACAddress: context.clientMACAddress,
                    serverIdentifier: nil,
                    acceptedTypes: [.offer]
                ) else {
                    state.dhcpClientStatusesByNodeID[nodeID] = status
                    scheduleDHCPTimeout(nodeID: nodeID)
                    return
                }
                context.selectedOffer = offer
                status.selectedServerIPAddress = offer.serverIdentifier
                status.offeredIPAddress = offer.yourIPAddress
                status.state = .validate
                state.dhcpClientContextsByNodeID[nodeID] = context
                state.dhcpClientStatusesByNodeID[nodeID] = status

            case .validate:
                guard let offer = context.selectedOffer else {
                    status.errorCount += 1
                    status.state = .discover
                    state.dhcpClientStatusesByNodeID[nodeID] = status
                    continue
                }
                let conflictMAC = resolveMACAddress(
                    nodeID: nodeID,
                    targetIPAddress: offer.yourIPAddress,
                    preferredInterfaceID: context.interfaceID,
                    maxRetries: 1,
                    selectInterfaceByAddress: false
                )
                status.state = conflictMAC == nil ? .request : .decline
                state.dhcpClientStatusesByNodeID[nodeID] = status

            case .decline:
                guard let offer = context.selectedOffer else {
                    status.errorCount += 1
                    status.state = .discover
                    state.dhcpClientStatusesByNodeID[nodeID] = status
                    continue
                }
                let decline = TopologyRuntimeDHCPMessage(
                    type: .decline,
                    clientMACAddress: context.clientMACAddress,
                    serverIdentifier: offer.serverIdentifier,
                    requestedIPAddress: offer.yourIPAddress
                )
                _ = sendDHCPMessage(socketID: context.socketID, message: decline)
                context.selectedOffer = nil
                status.selectedServerIPAddress = nil
                status.offeredIPAddress = nil
                status.state = .discover
                state.dhcpClientContextsByNodeID[nodeID] = context
                state.dhcpClientStatusesByNodeID[nodeID] = status

            case .request:
                guard let offer = context.selectedOffer,
                      let serverIdentifier = offer.serverIdentifier else {
                    status.errorCount += 1
                    status.state = .discover
                    state.dhcpClientStatusesByNodeID[nodeID] = status
                    continue
                }
                let request = TopologyRuntimeDHCPMessage(
                    type: .request,
                    clientMACAddress: context.clientMACAddress,
                    serverIdentifier: serverIdentifier,
                    requestedIPAddress: offer.yourIPAddress
                )
                _ = sendDHCPMessage(socketID: context.socketID, message: request)
                guard let response = receiveDHCPResponse(
                    socketID: context.socketID,
                    clientMACAddress: context.clientMACAddress,
                    serverIdentifier: serverIdentifier,
                    acceptedTypes: [.acknowledgement, .negativeAcknowledgement]
                ) else {
                    state.dhcpClientStatusesByNodeID[nodeID] = status
                    scheduleDHCPTimeout(nodeID: nodeID)
                    return
                }
                if response.type == .acknowledgement {
                    status.state = .assignIP
                } else {
                    context.selectedOffer = nil
                    status.selectedServerIPAddress = nil
                    status.offeredIPAddress = nil
                    status.state = .discover
                    state.dhcpClientContextsByNodeID[nodeID] = context
                }
                state.dhcpClientStatusesByNodeID[nodeID] = status

            case .assignIP:
                guard let offer = context.selectedOffer else {
                    status.errorCount += 1
                    status.state = .discover
                    state.dhcpClientStatusesByNodeID[nodeID] = status
                    continue
                }
                applyDHCPConfiguration(nodeID: nodeID, interfaceID: context.interfaceID, offer: offer)
                status.succeeded = true
                status.state = .finish
                state.dhcpClientStatusesByNodeID[nodeID] = status
                finishDHCPClient(nodeID: nodeID, restoreOldIPAddress: false)
                return

            case .finish:
                return
            }
        }
    }

    private mutating func scheduleDHCPTimeout(nodeID: UUID) {
        state.pendingEvents.removeAll { event in
            if case let .dhcpTimeout(eventNodeID) = event.kind { return eventNodeID == nodeID }
            return false
        }
        _ = schedule(
            deadlineMilliseconds: state.currentTimeMilliseconds + Self.dhcpRoundTripTimeMilliseconds,
            kind: .dhcpTimeout(nodeID: nodeID)
        )
    }

    private mutating func handleDHCPClientTimeout(nodeID: UUID) {
        guard state.dhcpClientContextsByNodeID[nodeID] != nil,
              var status = state.dhcpClientStatusesByNodeID[nodeID],
              status.state != .finish else { return }
        status.errorCount += 1
        if status.errorCount >= Self.dhcpMaximumClientErrorCount {
            status.state = .finish
            status.succeeded = false
            state.dhcpClientStatusesByNodeID[nodeID] = status
            finishDHCPClient(nodeID: nodeID, restoreOldIPAddress: true)
            return
        }
        state.dhcpClientStatusesByNodeID[nodeID] = status
        advanceDHCPClient(nodeID: nodeID)
    }

    private mutating func finishDHCPClient(nodeID: UUID, restoreOldIPAddress: Bool) {
        guard let context = state.dhcpClientContextsByNodeID.removeValue(forKey: nodeID) else { return }
        if restoreOldIPAddress {
            restoreDHCPClientOldIPAddress(
                nodeID: nodeID,
                interfaceID: context.interfaceID,
                deviceConfiguration: context.oldDeviceConfiguration,
                interfaceConfiguration: context.oldInterfaceConfiguration
            )
        }
        closeSocket(socketID: context.socketID)
        state.pendingEvents.removeAll { event in
            if case let .dhcpTimeout(eventNodeID) = event.kind { return eventNodeID == nodeID }
            return false
        }
    }

    private mutating func processDHCPDatagram(
        packet: TopologyIPv4Packet,
        datagram: TopologyUDPDatagram,
        nodeID: UUID,
        receivingInterface: TopologyRuntimeNetworkInterface
    ) {
        guard datagram.destinationPort == Self.dhcpServerPort,
              datagram.sourcePort == Self.dhcpClientPort,
              state.topologySnapshot.dhcpServerConfigurationsByNodeID[nodeID]?.isActive == true,
              let serverInterface = dhcpServerInterface(nodeID: nodeID),
              serverInterface.portID == receivingInterface.portID,
              let socketID = state.dhcpServerSocketIDsByNodeID[nodeID],
              let message = decodeDHCPMessage(datagram.payload),
              let clientMACAddress = message.clientMACAddress else { return }

        switch message.type {
        case .discover:
            guard let offeredIPAddress = offerDHCPAddress(serverNodeID: nodeID, clientMACAddress: clientMACAddress) else { return }
            let configuration = state.topologySnapshot.dhcpServerConfigurationsByNodeID[nodeID] ?? TopologyDHCPServerConfiguration()
            let offer = TopologyRuntimeDHCPMessage(
                type: .offer,
                yourIPAddress: offeredIPAddress,
                clientMACAddress: clientMACAddress,
                subnetMask: serverInterface.subnetMask,
                routerIPAddress: determineDHCPGateway(
                    serverNodeID: nodeID,
                    interface: serverInterface,
                    configuration: configuration
                ),
                dnsServerIPAddress: determineDHCPDNSServer(
                    serverNodeID: nodeID,
                    configuration: configuration
                ),
                serverIdentifier: serverInterface.ipAddress
            )
            _ = sendDHCPMessage(socketID: socketID, message: offer)

        case .request:
            guard let requestedIPAddress = message.requestedIPAddress,
                  let selectedServer = message.serverIdentifier else { return }
            if selectedServer.caseInsensitiveCompare(serverInterface.ipAddress) == .orderedSame {
                let accepted = requestDHCPAddress(
                    serverNodeID: nodeID,
                    clientMACAddress: clientMACAddress,
                    requestedIPAddress: requestedIPAddress
                )
                let response = TopologyRuntimeDHCPMessage(
                    type: accepted ? .acknowledgement : .negativeAcknowledgement,
                    yourIPAddress: requestedIPAddress,
                    clientMACAddress: clientMACAddress,
                    serverIdentifier: serverInterface.ipAddress
                )
                _ = sendDHCPMessage(socketID: socketID, message: response)
            } else {
                state.dhcpBlacklistByServerNodeID[nodeID, default: [:]][requestedIPAddress.lowercased()] =
                    state.currentTimeMilliseconds + Self.dhcpOfferLifetimeMilliseconds
            }

        case .decline:
            recordTrace(
                packetIdentity: packet.identity,
                nodeID: nodeID,
                interfaceID: receivingInterface.portID,
                direction: .local,
                layer: .application,
                operation: .accepted,
                detail: "DHCPDECLINE ignored by Java server worker"
            )

        case .offer, .acknowledgement, .negativeAcknowledgement:
            break
        }
    }

    private mutating func offerDHCPAddress(serverNodeID: UUID, clientMACAddress: String) -> String? {
        guard let configuration = state.topologySnapshot.dhcpServerConfigurationsByNodeID[serverNodeID] else { return nil }
        if let staticAddress = configuration.staticAssignments.first(where: {
            $0.macAddress.caseInsensitiveCompare(clientMACAddress) == .orderedSame
        })?.ipAddress {
            return staticAddress
        }
        guard let lower = parseIPv4(configuration.lowerBoundIPAddress),
              let upper = parseIPv4(configuration.upperBoundIPAddress),
              lower <= upper else { return nil }

        let firstCandidate: UInt32
        if let last = state.dhcpLastOfferedAddressByServerNodeID[serverNodeID],
           let lastValue = parseIPv4(last) {
            firstCandidate = lastValue < upper ? lastValue + 1 : lower
        } else {
            firstCandidate = lower
        }
        var candidate = firstCandidate
        repeat {
            let address = ipv4String(candidate)
            state.dhcpLastOfferedAddressByServerNodeID[serverNodeID] = address
            if isDHCPAddressAvailable(serverNodeID: serverNodeID, ipAddress: address) {
                let key = dhcpRecordKey(serverNodeID: serverNodeID, ipAddress: address)
                state.dhcpOffersByIPAddress[key] = TopologyRuntimeDHCPOfferRecord(
                    clientMACAddress: clientMACAddress,
                    offeredIPAddress: address,
                    serverNodeID: serverNodeID,
                    expiresAtMilliseconds: state.currentTimeMilliseconds + Self.dhcpOfferLifetimeMilliseconds
                )
                return address
            }
            candidate = candidate < upper ? candidate + 1 : lower
        } while candidate != firstCandidate
        return nil
    }

    private mutating func requestDHCPAddress(
        serverNodeID: UUID,
        clientMACAddress: String,
        requestedIPAddress: String
    ) -> Bool {
        cleanupDHCPAssignments(serverNodeID: serverNodeID)
        if state.dhcpBlacklistByServerNodeID[serverNodeID]?[requestedIPAddress.lowercased()] != nil { return false }
        let configuration = state.topologySnapshot.dhcpServerConfigurationsByNodeID[serverNodeID]
            ?? TopologyDHCPServerConfiguration()
        if configuration.staticAssignments.contains(where: {
            $0.macAddress.caseInsensitiveCompare(clientMACAddress) == .orderedSame
                && $0.ipAddress.caseInsensitiveCompare(requestedIPAddress) == .orderedSame
        }) {
            let key = dhcpRecordKey(serverNodeID: serverNodeID, ipAddress: requestedIPAddress)
            state.dhcpLeasesByIPAddress[key] = TopologyRuntimeDHCPLeaseRecord(
                clientMACAddress: clientMACAddress,
                ipAddress: requestedIPAddress,
                serverNodeID: serverNodeID,
                expiresAtMilliseconds: nil
            )
            return true
        }

        let key = dhcpRecordKey(serverNodeID: serverNodeID, ipAddress: requestedIPAddress)
        var accepted = false
        if let offer = state.dhcpOffersByIPAddress[key] {
            if offer.clientMACAddress.caseInsensitiveCompare(clientMACAddress) == .orderedSame {
                state.dhcpOffersByIPAddress.removeValue(forKey: key)
                accepted = true
            } else {
                return false
            }
        } else {
            accepted = isDHCPAddressAvailable(serverNodeID: serverNodeID, ipAddress: requestedIPAddress)
        }
        guard accepted else { return false }
        state.dhcpLeasesByIPAddress[key] = TopologyRuntimeDHCPLeaseRecord(
            clientMACAddress: clientMACAddress,
            ipAddress: requestedIPAddress,
            serverNodeID: serverNodeID,
            expiresAtMilliseconds: state.currentTimeMilliseconds + Self.dhcpDynamicLeaseLifetimeMilliseconds
        )
        return true
    }

    private mutating func isDHCPAddressAvailable(serverNodeID: UUID, ipAddress: String) -> Bool {
        cleanupDHCPAssignments(serverNodeID: serverNodeID)
        let normalized = ipAddress.lowercased()
        let configuration = state.topologySnapshot.dhcpServerConfigurationsByNodeID[serverNodeID]
            ?? TopologyDHCPServerConfiguration()
        if configuration.staticAssignments.contains(where: { $0.ipAddress.caseInsensitiveCompare(ipAddress) == .orderedSame }) {
            return false
        }
        if state.dhcpBlacklistByServerNodeID[serverNodeID]?[normalized] != nil { return false }
        let key = dhcpRecordKey(serverNodeID: serverNodeID, ipAddress: ipAddress)
        return state.dhcpOffersByIPAddress[key] == nil && state.dhcpLeasesByIPAddress[key] == nil
    }

    private mutating func cleanupDHCPAssignments(serverNodeID: UUID) {
        state.dhcpOffersByIPAddress = state.dhcpOffersByIPAddress.filter { _, offer in
            offer.serverNodeID != serverNodeID || offer.expiresAtMilliseconds >= state.currentTimeMilliseconds
        }
        state.dhcpLeasesByIPAddress = state.dhcpLeasesByIPAddress.filter { _, lease in
            guard lease.serverNodeID == serverNodeID, let expiry = lease.expiresAtMilliseconds else { return true }
            return expiry >= state.currentTimeMilliseconds
        }
        if var blacklist = state.dhcpBlacklistByServerNodeID[serverNodeID] {
            blacklist = blacklist.filter { $0.value >= state.currentTimeMilliseconds }
            state.dhcpBlacklistByServerNodeID[serverNodeID] = blacklist
        }
    }

    private mutating func receiveDHCPResponse(
        socketID: UUID,
        clientMACAddress: String,
        serverIdentifier: String?,
        acceptedTypes: Set<TopologyRuntimeDHCPMessageType>
    ) -> TopologyRuntimeDHCPMessage? {
        while let received = receiveUDP(socketID: socketID) {
            guard let message = decodeDHCPMessage(received.datagram.payload),
                  acceptedTypes.contains(message.type),
                  message.clientMACAddress?.caseInsensitiveCompare(clientMACAddress) == .orderedSame else { continue }
            if let serverIdentifier,
               message.serverIdentifier?.caseInsensitiveCompare(serverIdentifier) != .orderedSame { continue }
            return message
        }
        return nil
    }

    private mutating func sendDHCPMessage(socketID: UUID, message: TopologyRuntimeDHCPMessage) -> TopologyIPv4DeliveryResult? {
        guard let socket = state.socketsByID[socketID] else { return nil }
        recordTrace(
            nodeID: socket.nodeID,
            direction: .outbound,
            layer: .application,
            operation: .sent,
            detail: message.type.rawValue
        )
        return sendUDP(
            socketID: socketID,
            payload: encodeDHCPMessage(message),
            destinationIPAddress: Self.limitedBroadcastIPAddress,
            destinationPort: socket.localPort == Self.dhcpServerPort ? Self.dhcpClientPort : Self.dhcpServerPort
        )
    }

    private func encodeDHCPMessage(_ message: TopologyRuntimeDHCPMessage) -> Data {
        var lines = [message.type.rawValue, "yiaddr=\(message.yourIPAddress)"]
        if let value = message.clientMACAddress, !value.isEmpty { lines.append("chaddr=\(value)") }
        if let value = message.routerIPAddress, !value.isEmpty { lines.append("router=\(value)") }
        if let value = message.subnetMask, !value.isEmpty { lines.append("subnetmask=\(value)") }
        if let value = message.dnsServerIPAddress, !value.isEmpty { lines.append("dnsserver=\(value)") }
        if let value = message.requestedIPAddress, !value.isEmpty { lines.append("requested=\(value)") }
        if let value = message.serverIdentifier, !value.isEmpty { lines.append("serverident=\(value)") }
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func decodeDHCPMessage(_ data: Data) -> TopologyRuntimeDHCPMessage? {
        guard let value = String(data: data, encoding: .utf8) else { return nil }
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let command = lines.first,
              let type = TopologyRuntimeDHCPMessageType.allCasesValue(command) else { return nil }
        var message = TopologyRuntimeDHCPMessage(type: type)
        for line in lines.dropFirst() {
            let pair = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard pair.count == 2 else { continue }
            switch pair[0] {
            case "yiaddr": message.yourIPAddress = pair[1]
            case "chaddr": message.clientMACAddress = pair[1]
            case "router": message.routerIPAddress = pair[1]
            case "subnetmask": message.subnetMask = pair[1]
            case "dnsserver": message.dnsServerIPAddress = pair[1]
            case "requested": message.requestedIPAddress = pair[1]
            case "serverident": message.serverIdentifier = pair[1]
            default: break
            }
        }
        return message
    }

    private func dhcpServerInterface(nodeID: UUID) -> TopologyRuntimeNetworkInterface? {
        guard let node = nodeSnapshot(nodeID: nodeID) else { return nil }
        let interfaces = networkInterfaces(nodeID: nodeID)
        switch node.kind {
        case .pc, .notebook: return interfaces.first
        case .gateway: return interfaces.first(where: { $0.index == 1 })
        case .router, .networkSwitch, .remoteLink, .unsupported: return nil
        }
    }

    private func dhcpClientInterface(nodeID: UUID) -> TopologyRuntimeNetworkInterface? {
        guard let node = nodeSnapshot(nodeID: nodeID) else { return nil }
        let interfaces = networkInterfaces(nodeID: nodeID)
        switch node.kind {
        case .pc, .notebook: return interfaces.first
        case .gateway: return interfaces.first(where: { $0.index == 0 })
        case .router, .networkSwitch, .remoteLink, .unsupported: return nil
        }
    }

    private func determineDHCPGateway(
        serverNodeID: UUID,
        interface: TopologyRuntimeNetworkInterface,
        configuration: TopologyDHCPServerConfiguration
    ) -> String {
        if nodeSnapshot(nodeID: serverNodeID)?.kind == .gateway { return interface.ipAddress }
        if configuration.useOwnSettings { return configuration.gatewayIPAddress }
        let gateway = state.topologySnapshot.deviceConfigurations[serverNodeID]?.defaultGateway ?? ""
        return gateway.isEmpty ? Self.unspecifiedIPAddress : gateway
    }

    private func determineDHCPDNSServer(
        serverNodeID: UUID,
        configuration: TopologyDHCPServerConfiguration
    ) -> String {
        if nodeSnapshot(nodeID: serverNodeID)?.kind == .gateway || configuration.useOwnSettings {
            return configuration.dnsServerIPAddress
        }
        let dns = state.topologySnapshot.deviceConfigurations[serverNodeID]?.dnsServer ?? ""
        return dns.isEmpty ? Self.unspecifiedIPAddress : dns
    }

    private mutating func applyDHCPConfiguration(nodeID: UUID, interfaceID: UUID, offer: TopologyRuntimeDHCPMessage) {
        let mask = offer.subnetMask ?? "0.0.0.0"
        let gateway = offer.routerIPAddress ?? Self.unspecifiedIPAddress
        let dns = offer.dnsServerIPAddress ?? Self.unspecifiedIPAddress
        guard let node = nodeSnapshot(nodeID: nodeID) else { return }
        var devices = state.topologySnapshot.deviceConfigurations
        var interfaces = state.topologySnapshot.interfaceConfigurations
        if node.kind.isPCClassEndpoint {
            devices[nodeID] = TopologyRuntimeDeviceConfiguration(
                ipAddress: offer.yourIPAddress,
                subnetMask: mask,
                defaultGateway: gateway,
                dnsServer: dns
            )
        } else if node.kind == .gateway {
            interfaces[TopologyRuntimeInterfaceKey(nodeID: nodeID, portID: interfaceID)] =
                TopologyRuntimeInterfaceConfiguration(ipAddress: offer.yourIPAddress, subnetMask: mask)
            let current = devices[nodeID]
            devices[nodeID] = TopologyRuntimeDeviceConfiguration(
                ipAddress: current?.ipAddress ?? "",
                subnetMask: current?.subnetMask ?? "",
                defaultGateway: gateway,
                dnsServer: dns
            )
        }
        replaceTopologyConfigurations(deviceConfigurations: devices, interfaceConfigurations: interfaces)
    }

    private mutating func setDHCPClientIPAddress(nodeID: UUID, interfaceID: UUID, ipAddress: String) {
        guard let node = nodeSnapshot(nodeID: nodeID) else { return }
        var devices = state.topologySnapshot.deviceConfigurations
        var interfaces = state.topologySnapshot.interfaceConfigurations
        if node.kind.isPCClassEndpoint, let current = devices[nodeID] {
            devices[nodeID] = TopologyRuntimeDeviceConfiguration(
                ipAddress: ipAddress,
                subnetMask: current.subnetMask,
                defaultGateway: current.defaultGateway,
                dnsServer: current.dnsServer
            )
        } else if node.kind == .gateway,
                  let current = interfaces[TopologyRuntimeInterfaceKey(nodeID: nodeID, portID: interfaceID)] {
            interfaces[TopologyRuntimeInterfaceKey(nodeID: nodeID, portID: interfaceID)] =
                TopologyRuntimeInterfaceConfiguration(ipAddress: ipAddress, subnetMask: current.subnetMask)
        }
        replaceTopologyConfigurations(deviceConfigurations: devices, interfaceConfigurations: interfaces)
    }

    private mutating func restoreDHCPClientOldIPAddress(
        nodeID: UUID,
        interfaceID: UUID,
        deviceConfiguration: TopologyRuntimeDeviceConfiguration?,
        interfaceConfiguration: TopologyRuntimeInterfaceConfiguration?
    ) {
        guard let node = nodeSnapshot(nodeID: nodeID) else { return }
        var devices = state.topologySnapshot.deviceConfigurations
        var interfaces = state.topologySnapshot.interfaceConfigurations
        if node.kind.isPCClassEndpoint, let old = deviceConfiguration, let current = devices[nodeID] {
            devices[nodeID] = TopologyRuntimeDeviceConfiguration(
                ipAddress: old.ipAddress,
                subnetMask: current.subnetMask,
                defaultGateway: current.defaultGateway,
                dnsServer: current.dnsServer
            )
        } else if node.kind == .gateway, let old = interfaceConfiguration,
                  let current = interfaces[TopologyRuntimeInterfaceKey(nodeID: nodeID, portID: interfaceID)] {
            interfaces[TopologyRuntimeInterfaceKey(nodeID: nodeID, portID: interfaceID)] =
                TopologyRuntimeInterfaceConfiguration(ipAddress: old.ipAddress, subnetMask: current.subnetMask)
        }
        replaceTopologyConfigurations(deviceConfigurations: devices, interfaceConfigurations: interfaces)
    }

    private mutating func replaceTopologyConfigurations(
        deviceConfigurations: [UUID: TopologyRuntimeDeviceConfiguration],
        interfaceConfigurations: [TopologyRuntimeInterfaceKey: TopologyRuntimeInterfaceConfiguration]
    ) {
        state.topologySnapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: state.topologySnapshot.nodes,
            links: state.topologySnapshot.links,
            deviceConfigurations: deviceConfigurations,
            interfaceConfigurations: interfaceConfigurations,
            manualRoutesByNodeID: state.topologySnapshot.manualRoutesByNodeID,
            ripEnabledByNodeID: state.topologySnapshot.ripEnabledByNodeID,
            dhcpClientConfigurationsByNodeID: state.topologySnapshot.dhcpClientConfigurationsByNodeID,
            dhcpServerConfigurationsByNodeID: state.topologySnapshot.dhcpServerConfigurationsByNodeID,
            firewallConfigurationsByNodeID: state.topologySnapshot.firewallConfigurationsByNodeID,
            portForwardingRowsByNodeID: state.topologySnapshot.portForwardingRowsByNodeID,
            switchConfigurationsByNodeID: state.topologySnapshot.switchConfigurationsByNodeID,
            remoteLinkConfigurationsByNodeID: state.topologySnapshot.remoteLinkConfigurationsByNodeID,
            hostWirelessConfigurationsByNodeID: state.topologySnapshot.hostWirelessConfigurationsByNodeID
        )
    }

    private func dhcpRecordKey(serverNodeID: UUID, ipAddress: String) -> String {
        "\(serverNodeID.uuidString.lowercased())|\(ipAddress.lowercased())"
    }

    private func ipv4String(_ address: UInt32) -> String {
        [24, 16, 8, 0].map { String((address >> UInt32($0)) & 0xFF) }.joined(separator: ".")
    }
}

private extension TopologyRuntimeDHCPMessageType {
    static func allCasesValue(_ rawValue: String) -> TopologyRuntimeDHCPMessageType? {
        [discover, request, acknowledgement, negativeAcknowledgement, offer, decline]
            .first { $0.rawValue.caseInsensitiveCompare(rawValue) == .orderedSame }
    }
}

// MARK: - Static-routing compatibility adapter

struct RuntimeResolvedRoute: Equatable {
    let pathNodeIDs: [UUID]
    let forwardingNodeIDs: [UUID]
}

struct RuntimeInterfaceReference: Equatable {
    let nodeID: UUID
    let portID: UUID
    let configuration: TopologyRuntimeInterfaceConfiguration
}

enum RuntimeRouteFailureKind: Equatable {
    case subnetMismatch
    case topologyUnreachable
}

struct RuntimeRouteFailure: Equatable {
    let kind: RuntimeRouteFailureKind
    let faultCode: String
    let message: String
    let detail: String
}

enum RuntimeRouteResolutionResult: Equatable {
    case success(RuntimeResolvedRoute)
    case failure(RuntimeRouteFailure)
}

/// Preserves the S11 aggregate static-routing behavior while the packet runtime
/// replaces each compatibility path in later slices. Route processing lives
/// outside the editor reducer so the reducer only adapts visible application
/// output to deterministic runtime results.
struct TopologyNetworkRuntimeCompatibilityRouteResolver {

    private static func parseIPv4Octets(_ value: String) -> [UInt8]? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let segments = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 4 else { return nil }

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

    static func resolve(
        state: TopologyEditorState,
        sourceNodeID: UUID,
        sourceConfiguration: TopologyRuntimeDeviceConfiguration,
        targetNodeID: UUID,
        targetConfiguration: TopologyRuntimeDeviceConfiguration,
        requiresReturnPath: Bool
    ) -> RuntimeRouteResolutionResult {
        var routedState = state
        routedState.graph = graphIncludingActiveRemoteLinks(state: state)
        let outbound = resolveRuntimeRouteDirection(
            state: routedState,
            sourceNodeID: sourceNodeID,
            sourceConfiguration: sourceConfiguration,
            targetNodeID: targetNodeID,
            targetConfiguration: targetConfiguration,
            gatewayMissingCode: "sourceDefaultGatewayMissing",
            gatewayMismatchCode: "sourceDefaultGatewayMismatch",
            gatewayMissingMessage: "Configure a source default gateway for cross-subnet traffic",
            gatewayMismatchMessage: "Source default gateway does not match a reachable Router or Gateway interface"
        )
        guard case let .success(outboundRoute) = outbound else { return outbound }

        if requiresReturnPath {
            let returnPath = resolveRuntimeRouteDirection(
                state: routedState,
                sourceNodeID: targetNodeID,
                sourceConfiguration: targetConfiguration,
                targetNodeID: sourceNodeID,
                targetConfiguration: sourceConfiguration,
                gatewayMissingCode: "targetDefaultGatewayMissing",
                gatewayMismatchCode: "targetDefaultGatewayMismatch",
                gatewayMissingMessage: "Configure the target default gateway for the return path",
                gatewayMismatchMessage: "Target default gateway does not match a reachable Router or Gateway interface"
            )
            if case let .failure(failure) = returnPath { return .failure(failure) }
        }
        return .success(outboundRoute)
    }

    private static func resolveRuntimeRouteDirection(
        state: TopologyEditorState,
        sourceNodeID: UUID,
        sourceConfiguration: TopologyRuntimeDeviceConfiguration,
        targetNodeID: UUID,
        targetConfiguration: TopologyRuntimeDeviceConfiguration,
        gatewayMissingCode: String,
        gatewayMismatchCode: String,
        gatewayMissingMessage: String,
        gatewayMismatchMessage: String
    ) -> RuntimeRouteResolutionResult {
        if areInSameSubnet(source: sourceConfiguration, target: targetConfiguration) {
            guard let path = layer2Path(graph: state.graph, sourceNodeID: sourceNodeID, targetNodeID: targetNodeID) else {
                return routeFailure(.topologyUnreachable, "sameSubnetPathUnavailable", "No switch-only topology path exists between source and target")
            }
            return .success(RuntimeResolvedRoute(pathNodeIDs: path, forwardingNodeIDs: []))
        }
        guard !sourceConfiguration.defaultGateway.isEmpty else {
            return routeFailure(.subnetMismatch, gatewayMissingCode, gatewayMissingMessage)
        }
        guard let initialHop = reachableForwardingInterface(
            state: state,
            endpointNodeID: sourceNodeID,
            endpointConfiguration: sourceConfiguration,
            gatewayIPAddress: sourceConfiguration.defaultGateway
        ) else {
            return routeFailure(.subnetMismatch, gatewayMismatchCode, gatewayMismatchMessage)
        }
        guard let initialPath = layer2PathFromInterface(
            graph: state.graph,
            sourceNodeID: initialHop.nodeID,
            sourcePortID: initialHop.portID,
            targetNodeID: sourceNodeID,
            targetPortID: nil
        ) else {
            return routeFailure(.topologyUnreachable, "forwardingPathUnavailable", "The configured default gateway is not physically reachable")
        }

        var pathNodeIDs = Array(initialPath.reversed())
        var forwardingNodeIDs: [UUID] = []
        var visitedForwardingNodeIDs: Set<UUID> = []
        var currentInterface = initialHop

        while true {
            let currentNodeID = currentInterface.nodeID
            guard visitedForwardingNodeIDs.insert(currentNodeID).inserted else {
                return routeFailure(
                    .topologyUnreachable,
                    "forwardingLoopDetected",
                    "Routing loop detected while resolving the forwarding path",
                    detail: "forwardingLoopDetected;node=\(currentNodeID.uuidString)"
                )
            }
            forwardingNodeIDs.append(currentNodeID)

            guard let route = bestRuntimeRoute(state: state, forwardingNodeID: currentNodeID, targetIPAddress: targetConfiguration.ipAddress) else {
                if let diagnostic = directTargetInterfaceMismatch(state: state, forwardingNodeID: currentNodeID, targetNodeID: targetNodeID) {
                    return .failure(diagnostic)
                }
                return routeFailure(
                    .subnetMismatch,
                    "forwardingRouteMissing",
                    "No connected or manual route matches the target IP address",
                    detail: "forwardingRouteMissing;node=\(currentNodeID.uuidString)"
                )
            }
            guard let outgoing = runtimeInterface(state: state, nodeID: currentNodeID, ipAddress: route.interfaceIPAddress) else {
                return routeFailure(
                    .subnetMismatch,
                    "forwardingRouteInterfaceInvalid",
                    "The selected route references an unknown outgoing interface IP address",
                    detail: "forwardingRouteInterfaceInvalid;node=\(currentNodeID.uuidString);interface=\(route.interfaceIPAddress)"
                )
            }

            if route.gateway == outgoing.configuration.ipAddress {
                guard let targetNetwork = networkAddress(
                    ipAddress: targetConfiguration.ipAddress,
                    subnetMask: outgoing.configuration.subnetMask
                ),
                      let interfaceNetwork = networkAddress(
                        ipAddress: outgoing.configuration.ipAddress,
                        subnetMask: outgoing.configuration.subnetMask
                      ),
                      targetNetwork == interfaceNetwork,
                      let segment = layer2PathFromInterface(
                        graph: state.graph,
                        sourceNodeID: currentNodeID,
                        sourcePortID: outgoing.portID,
                        targetNodeID: targetNodeID,
                        targetPortID: nil
                      ) else {
                    return routeFailure(.topologyUnreachable, "forwardingTargetUnreachable", "The target is not reachable through the route's outgoing interface")
                }
                appendRuntimePathSegment(segment, to: &pathNodeIDs)
                return .success(RuntimeResolvedRoute(pathNodeIDs: pathNodeIDs, forwardingNodeIDs: forwardingNodeIDs))
            }

            guard let gatewayNetwork = networkAddress(
                ipAddress: route.gateway,
                subnetMask: outgoing.configuration.subnetMask
            ),
                  let interfaceNetwork = networkAddress(
                    ipAddress: outgoing.configuration.ipAddress,
                    subnetMask: outgoing.configuration.subnetMask
                  ),
                  gatewayNetwork == interfaceNetwork else {
                return routeFailure(
                    .subnetMismatch,
                    "forwardingNextHopUnreachable",
                    "The selected next-hop gateway is outside the outgoing interface subnet",
                    detail: "forwardingNextHopUnreachable;node=\(currentNodeID.uuidString);gateway=\(route.gateway)"
                )
            }

            var nextHop: RuntimeInterfaceReference?
            var nextSegment: [UUID]?
            for candidate in runtimeInterfaces(state: state, ipAddress: route.gateway) where candidate.nodeID != currentNodeID {
                if let segment = layer2PathFromInterface(
                    graph: state.graph,
                    sourceNodeID: currentNodeID,
                    sourcePortID: outgoing.portID,
                    targetNodeID: candidate.nodeID,
                    targetPortID: candidate.portID
                ) {
                    nextHop = candidate
                    nextSegment = segment
                    break
                }
            }
            guard let nextHop, let nextSegment else {
                return routeFailure(
                    .topologyUnreachable,
                    "forwardingNextHopUnreachable",
                    "The selected next-hop gateway is not reachable through the outgoing interface",
                    detail: "forwardingNextHopUnreachable;node=\(currentNodeID.uuidString);gateway=\(route.gateway)"
                )
            }
            appendRuntimePathSegment(nextSegment, to: &pathNodeIDs)
            currentInterface = nextHop
        }
    }

    private static func routeFailure(
        _ kind: RuntimeRouteFailureKind,
        _ faultCode: String,
        _ message: String,
        detail: String? = nil
    ) -> RuntimeRouteResolutionResult {
        .failure(RuntimeRouteFailure(kind: kind, faultCode: faultCode, message: message, detail: detail ?? faultCode))
    }

    private static func bestRuntimeRoute(
        state: TopologyEditorState,
        forwardingNodeID: UUID,
        targetIPAddress: String
    ) -> TopologyRuntimeManualRoute? {
        guard let node = state.graph.node(withID: forwardingNodeID) else { return nil }
        let connectedRoutes = node.ports.reversed().compactMap { port -> TopologyRuntimeManualRoute? in
            guard let configuration = state.runtimeInterfaceConfigurations[
                TopologyRuntimeInterfaceKey(nodeID: forwardingNodeID, portID: port.id)
            ], let destination = networkAddress(ipAddress: configuration.ipAddress, subnetMask: configuration.subnetMask) else {
                return nil
            }
            return TopologyRuntimeManualRoute(
                destinationNetwork: destination,
                subnetMask: configuration.subnetMask,
                gateway: configuration.ipAddress,
                interfaceIPAddress: configuration.ipAddress
            )
        }
        let routes = connectedRoutes + state.runtimeManualRoutesByNodeID[forwardingNodeID, default: []]
        return TopologyRuntimeManualRoute.bestMatching(targetIPAddress: targetIPAddress, routes: routes)
    }

    private static func reachableForwardingInterface(
        state: TopologyEditorState,
        endpointNodeID: UUID,
        endpointConfiguration: TopologyRuntimeDeviceConfiguration,
        gatewayIPAddress: String
    ) -> RuntimeInterfaceReference? {
        runtimeInterfaces(state: state, ipAddress: gatewayIPAddress).first { candidate in
            guard
                let endpointNetwork = networkAddress(
                    ipAddress: endpointConfiguration.ipAddress,
                    subnetMask: candidate.configuration.subnetMask
                ),
                let candidateNetwork = networkAddress(
                    ipAddress: candidate.configuration.ipAddress,
                    subnetMask: candidate.configuration.subnetMask
                ),
                endpointNetwork == candidateNetwork
            else {
                return false
            }
            return layer2PathFromInterface(
                graph: state.graph,
                sourceNodeID: candidate.nodeID,
                sourcePortID: candidate.portID,
                targetNodeID: endpointNodeID,
                targetPortID: nil
            ) != nil
        }
    }

    private static func runtimeInterfaces(state: TopologyEditorState, ipAddress: String) -> [RuntimeInterfaceReference] {
        state.graph.nodes
            .filter { $0.kind == .router || $0.kind == .gateway }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .flatMap { node in
                node.ports.compactMap { port in
                    let key = TopologyRuntimeInterfaceKey(nodeID: node.id, portID: port.id)
                    guard let configuration = state.runtimeInterfaceConfigurations[key], configuration.ipAddress == ipAddress else { return nil }
                    return RuntimeInterfaceReference(nodeID: node.id, portID: port.id, configuration: configuration)
                }
            }
    }

    private static func runtimeInterface(state: TopologyEditorState, nodeID: UUID, ipAddress: String) -> RuntimeInterfaceReference? {
        guard let node = state.graph.node(withID: nodeID) else { return nil }
        for port in node.ports {
            let key = TopologyRuntimeInterfaceKey(nodeID: nodeID, portID: port.id)
            if let configuration = state.runtimeInterfaceConfigurations[key], configuration.ipAddress == ipAddress {
                return RuntimeInterfaceReference(nodeID: nodeID, portID: port.id, configuration: configuration)
            }
        }
        return nil
    }

    private static func directTargetInterfaceMismatch(
        state: TopologyEditorState,
        forwardingNodeID: UUID,
        targetNodeID: UUID
    ) -> RuntimeRouteFailure? {
        guard let node = state.graph.node(withID: forwardingNodeID) else { return nil }
        for port in node.ports where layer2PathFromInterface(
            graph: state.graph,
            sourceNodeID: forwardingNodeID,
            sourcePortID: port.id,
            targetNodeID: targetNodeID,
            targetPortID: nil
        ) != nil {
            let prefix = node.kind == .router ? "router" : "gateway"
            let label = node.kind == .router ? "Router" : "Gateway"
            return RuntimeRouteFailure(
                kind: .subnetMismatch,
                faultCode: "\(prefix)EgressSubnetMismatch",
                message: "\(label) egress interface is not on the target subnet",
                detail: "\(prefix)EgressSubnetMismatch"
            )
        }
        return nil
    }

    private static func appendRuntimePathSegment(_ segment: [UUID], to path: inout [UUID]) {
        guard !segment.isEmpty else { return }
        if path.last == segment.first {
            path.append(contentsOf: segment.dropFirst())
        } else {
            path.append(contentsOf: segment)
        }
    }

    private static func graphIncludingActiveRemoteLinks(state: TopologyEditorState) -> TopologyGraph {
        let remoteNodesByID = Dictionary(
            uniqueKeysWithValues: state.graph.nodes.filter { $0.kind == .remoteLink }.map { ($0.id, $0) }
        )
        var enabledNodesByPairIdentifier: [String: [TopologyNode]] = [:]
        for (nodeID, configuration) in state.remoteLinkConfigurationsByNodeID where configuration.isEnabled {
            let pairIdentifier = configuration.pairIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pairIdentifier.isEmpty, let node = remoteNodesByID[nodeID] else { continue }
            enabledNodesByPairIdentifier[pairIdentifier, default: []].append(node)
        }

        var links = state.graph.links
        for pairIdentifier in enabledNodesByPairIdentifier.keys.sorted() {
            let nodes = enabledNodesByPairIdentifier[pairIdentifier, default: []]
                .sorted { $0.id.uuidString < $1.id.uuidString }
            guard nodes.count == 2,
                  let sourcePortID = nodes[0].ports.first?.id,
                  let targetPortID = nodes[1].ports.first?.id
            else { continue }
            links.append(
                TopologyLink(
                    id: nodes[0].id,
                    sourceNodeID: nodes[0].id,
                    sourcePortID: sourcePortID,
                    targetNodeID: nodes[1].id,
                    targetPortID: targetPortID
                )
            )
        }
        return TopologyGraph(nodes: state.graph.nodes, links: links)
    }

    private static func layer2Path(graph: TopologyGraph, sourceNodeID: UUID, targetNodeID: UUID) -> [UUID]? {
        guard graph.containsNode(id: sourceNodeID), graph.containsNode(id: targetNodeID) else { return nil }
        if sourceNodeID == targetNodeID { return [sourceNodeID] }
        var queue = [sourceNodeID]
        var cursor = 0
        var visited: Set<UUID> = [sourceNodeID]
        var predecessor: [UUID: UUID] = [:]
        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            for neighbor in graph.adjacentNodeIDs(for: current).sorted(by: { $0.uuidString < $1.uuidString }) {
                if neighbor == targetNodeID {
                    predecessor[neighbor] = current
                    return buildRuntimePath(sourceNodeID: sourceNodeID, targetNodeID: targetNodeID, predecessor: predecessor)
                }
                guard let node = graph.node(withID: neighbor),
                      (node.kind == .networkSwitch || node.kind == .remoteLink),
                      visited.insert(neighbor).inserted
                else { continue }
                predecessor[neighbor] = current
                queue.append(neighbor)
            }
        }
        return nil
    }

    private static func layer2PathFromInterface(
        graph: TopologyGraph,
        sourceNodeID: UUID,
        sourcePortID: UUID,
        targetNodeID: UUID,
        targetPortID: UUID?
    ) -> [UUID]? {
        guard let firstLink = graph.links.first(where: {
            ($0.sourceNodeID == sourceNodeID && $0.sourcePortID == sourcePortID)
                || ($0.targetNodeID == sourceNodeID && $0.targetPortID == sourcePortID)
        }) else { return nil }
        let firstNodeID = firstLink.sourceNodeID == sourceNodeID ? firstLink.targetNodeID : firstLink.sourceNodeID
        if firstNodeID == targetNodeID {
            guard targetPortID == nil || portID(on: targetNodeID, for: firstLink) == targetPortID else { return nil }
            return [sourceNodeID, targetNodeID]
        }
        guard let firstNode = graph.node(withID: firstNodeID),
              firstNode.kind == .networkSwitch || firstNode.kind == .remoteLink
        else { return nil }

        var queue = [firstNodeID]
        var cursor = 0
        var visited: Set<UUID> = [sourceNodeID, firstNodeID]
        var predecessor: [UUID: UUID] = [firstNodeID: sourceNodeID]
        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            let links = graph.links.filter { $0.sourceNodeID == current || $0.targetNodeID == current }
                .sorted { $0.id.uuidString < $1.id.uuidString }
            for link in links {
                let neighbor = link.sourceNodeID == current ? link.targetNodeID : link.sourceNodeID
                if neighbor == targetNodeID {
                    guard targetPortID == nil || portID(on: targetNodeID, for: link) == targetPortID else { continue }
                    predecessor[neighbor] = current
                    return buildRuntimePath(sourceNodeID: sourceNodeID, targetNodeID: targetNodeID, predecessor: predecessor)
                }
                guard let node = graph.node(withID: neighbor),
                      (node.kind == .networkSwitch || node.kind == .remoteLink),
                      visited.insert(neighbor).inserted
                else { continue }
                predecessor[neighbor] = current
                queue.append(neighbor)
            }
        }
        return nil
    }

    private static func buildRuntimePath(
        sourceNodeID: UUID,
        targetNodeID: UUID,
        predecessor: [UUID: UUID]
    ) -> [UUID]? {
        var reversed = [targetNodeID]
        var cursor = targetNodeID
        while cursor != sourceNodeID {
            guard let previous = predecessor[cursor] else { return nil }
            reversed.append(previous)
            cursor = previous
        }
        return Array(reversed.reversed())
    }

    private static func portID(on nodeID: UUID, for link: TopologyLink) -> UUID? {
        if link.sourceNodeID == nodeID { return link.sourcePortID }
        if link.targetNodeID == nodeID { return link.targetPortID }
        return nil
    }

    private static func configurationsShareSubnet(
        endpoint: TopologyRuntimeDeviceConfiguration,
        interface: TopologyRuntimeInterfaceConfiguration
    ) -> Bool {
        address(interface.ipAddress, isInSubnetOf: endpoint.ipAddress, mask: endpoint.subnetMask)
            && address(endpoint.ipAddress, isInSubnetOf: interface.ipAddress, mask: interface.subnetMask)
    }

    private static func address(_ address: String, isInSubnetOf networkAddress: String, mask: String) -> Bool {
        guard let addressPrefix = networkPrefix(ipAddress: address, subnetMask: mask),
              let networkPrefix = networkPrefix(ipAddress: networkAddress, subnetMask: mask) else {
            return false
        }

        return addressPrefix == networkPrefix
    }

    private static func areInSameSubnet(
        source: TopologyRuntimeDeviceConfiguration,
        target: TopologyRuntimeDeviceConfiguration
    ) -> Bool {
        address(target.ipAddress, isInSubnetOf: source.ipAddress, mask: source.subnetMask)
            && address(source.ipAddress, isInSubnetOf: target.ipAddress, mask: target.subnetMask)
    }

}



// MARK: - Packet capture and Java message/layer viewer projections

extension TopologyNetworkRuntimeEngine {
    func arpCacheEntries(nodeID: UUID) -> [TopologyRuntimeARPCacheEntry] {
        (state.arpCachesByNodeID[nodeID] ?? [:]).values.sorted { lhs, rhs in
            lhs.ipAddress == rhs.ipAddress
                ? lhs.macAddress < rhs.macAddress
                : lhs.ipAddress < rhs.ipAddress
        }
    }

    mutating func removeARPCacheEntry(nodeID: UUID, ipAddress: String) {
        state.arpCachesByNodeID[nodeID]?.removeValue(forKey: ipAddress)
        if state.arpCachesByNodeID[nodeID]?.isEmpty == true {
            state.arpCachesByNodeID.removeValue(forKey: nodeID)
        }
    }

    mutating func clearARPCache(nodeID: UUID) {
        state.arpCachesByNodeID.removeValue(forKey: nodeID)
    }

    func socketRecords(nodeID: UUID) -> [TopologyRuntimeSocketRecord] {
        state.socketsByID.values
            .filter { $0.nodeID == nodeID }
            .sorted { lhs, rhs in
                if lhs.protocolKind != rhs.protocolKind { return lhs.protocolKind.rawValue < rhs.protocolKind.rawValue }
                if lhs.localPort != rhs.localPort { return lhs.localPort < rhs.localPort }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    @discardableResult
    mutating func sendARPReply(
        fromNodeID nodeID: UUID,
        senderIPAddress: String,
        targetIPAddress: String
    ) -> Bool {
        guard state.phase == .running,
              let interface = networkInterfaces(nodeID: nodeID).first
        else { return false }

        guard let targetMACAddress = resolveMACAddress(
            nodeID: nodeID,
            targetIPAddress: targetIPAddress,
            preferredInterfaceID: interface.portID
        ) else { return false }
        let packet = TopologyARPPacket(
            operation: .reply,
            senderMACAddress: interface.macAddress,
            senderIPAddress: senderIPAddress,
            targetMACAddress: targetMACAddress,
            targetIPAddress: targetIPAddress
        )
        let frame = TopologyEthernetFrame(
            identity: allocateFrameIdentity(),
            sourceMACAddress: interface.macAddress,
            destinationMACAddress: targetMACAddress,
            payload: .arp(packet)
        )
        recordTrace(
            frameIdentity: frame.identity,
            nodeID: nodeID,
            interfaceID: interface.portID,
            direction: .outbound,
            layer: .dataLink,
            operation: .created,
            afterHeaders: ethernetHeaders(frame) + arpHeaders(packet),
            detail: "ARP reply \(senderIPAddress) is-at \(interface.macAddress) to \(targetIPAddress)"
        )
        sendEthernetFrame(fromNodeID: nodeID, outgoingPortID: interface.portID, frame: frame)
        return true
    }

    func packetCaptureMessageRows(nodeID: UUID) -> [TopologyPacketMessageRow] {
        packetMessageRows(nodeID: nodeID).filter { row in
            let trace = row.trace
            return trace.interfaceID != nil
                && trace.operation != .compatibilityAdapter
                && (trace.frameIdentity != nil || trace.packetIdentity != nil)
        }
    }

    func packetCaptureTabs(nodeID: UUID) -> [TopologyPacketCaptureTab] {
        guard let node = state.topologySnapshot.nodes.first(where: { $0.id == nodeID }) else { return [] }
        let counts = Dictionary(grouping: state.packetTraces.filter { $0.nodeID == nodeID && $0.interfaceID != nil }) {
            $0.interfaceID!
        }.mapValues { $0.count }

        return node.ports.compactMap { port in
            guard let eventCount = counts[port.id] else { return nil }
            let networkInterface = networkInterfaces(nodeID: nodeID).first(where: { $0.portID == port.id })
            let ipAddress = networkInterface?.ipAddress.nilIfJavaUnconfiguredAddress
            let nodeName = Self.packetViewerNodeName(for: node.kind)
            let title = ipAddress.map { "\(nodeName) - \($0)" } ?? "\(nodeName) - \(port.label)"
            return TopologyPacketCaptureTab(
                nodeID: nodeID,
                interfaceID: port.id,
                interfaceLabel: port.label,
                ipAddress: ipAddress,
                title: title,
                eventCount: eventCount
            )
        }
    }

    func packetMessageRows(nodeID: UUID, interfaceID: UUID? = nil) -> [TopologyPacketMessageRow] {
        let traces = state.packetTraces
            .filter { trace in
                trace.nodeID == nodeID && (interfaceID == nil || trace.interfaceID == interfaceID)
            }
            .sorted { lhs, rhs in
                lhs.timeMilliseconds == rhs.timeMilliseconds ? lhs.id < rhs.id : lhs.timeMilliseconds < rhs.timeMilliseconds
            }

        return traces.enumerated().map { offset, trace in
            let headers = Self.effectiveHeaders(for: trace)
            return TopologyPacketMessageRow(
                id: trace.id,
                number: offset + 1,
                timeMilliseconds: trace.timeMilliseconds,
                source: Self.headerValue(named: ["senderIP", "sourceMAC", "senderMAC"], in: headers) ?? "-",
                destination: Self.headerValue(named: ["receiverIP", "destinationMAC", "targetIP", "targetMAC"], in: headers) ?? "-",
                protocolName: Self.protocolName(for: trace, headers: headers),
                layerName: Self.germanLayerName(trace.layer),
                detail: trace.detail ?? Self.germanOperationName(trace.operation),
                trace: trace
            )
        }
    }

    func packetLayerPath(
        identity: TopologyPacketCaptureIdentity,
        localNodeID: UUID? = nil
    ) -> TopologyPacketLayerPath {
        let traces = state.packetTraces
            .filter { trace in
                guard localNodeID == nil || trace.nodeID == localNodeID else { return false }
                switch identity {
                case let .packet(value): return trace.packetIdentity == value
                case let .frame(value): return trace.frameIdentity == value
                case let .trace(value): return trace.id == value
                }
            }
            .sorted { lhs, rhs in
                lhs.timeMilliseconds == rhs.timeMilliseconds ? lhs.id < rhs.id : lhs.timeMilliseconds < rhs.timeMilliseconds
            }

        return TopologyPacketLayerPath(
            identity: identity,
            steps: traces.enumerated().map { offset, trace in
                TopologyPacketLayerPathStep(
                    id: trace.id,
                    ordinal: offset + 1,
                    timeMilliseconds: trace.timeMilliseconds,
                    nodeID: trace.nodeID,
                    nodeName: packetViewerNodeName(nodeID: trace.nodeID),
                    interfaceID: trace.interfaceID,
                    interfaceName: packetViewerInterfaceName(nodeID: trace.nodeID, interfaceID: trace.interfaceID),
                    direction: trace.direction,
                    layer: trace.layer,
                    operation: trace.operation,
                    beforeHeaders: trace.beforeHeaders,
                    afterHeaders: trace.afterHeaders,
                    detail: trace.detail
                )
            }
        )
    }

    mutating func clearPacketCapture(nodeID: UUID? = nil, interfaceID: UUID? = nil) {
        state.packetTraces.removeAll { trace in
            let nodeMatches = nodeID == nil || trace.nodeID == nodeID
            let interfaceMatches = interfaceID == nil || trace.interfaceID == interfaceID
            return nodeMatches && interfaceMatches
        }
    }

    private func packetViewerNodeName(nodeID: UUID) -> String {
        guard let node = state.topologySnapshot.nodes.first(where: { $0.id == nodeID }) else {
            return nodeID.uuidString
        }
        return Self.packetViewerNodeName(for: node.kind)
    }

    private func packetViewerInterfaceName(nodeID: UUID, interfaceID: UUID?) -> String? {
        guard let interfaceID,
              let node = state.topologySnapshot.nodes.first(where: { $0.id == nodeID }),
              let port = node.ports.first(where: { $0.id == interfaceID }) else { return nil }
        if let ipAddress = networkInterfaces(nodeID: nodeID)
            .first(where: { $0.portID == interfaceID })?.ipAddress.nilIfJavaUnconfiguredAddress {
            return "\(port.label) - \(ipAddress)"
        }
        return port.label
    }

    private static func packetViewerNodeName(for kind: TopologyNodeKind) -> String {
        switch kind {
        case .pc: return "Rechner"
        case .notebook: return "Notebook"
        case .networkSwitch: return "Switch"
        case .router: return "Vermittlungsrechner"
        case .gateway: return "Gateway"
        case .remoteLink: return "Remote Link"
        case .unsupported: return "Gerät"
        }
    }

    private static func effectiveHeaders(for trace: TopologyPacketTraceEvent) -> [TopologyPacketHeaderField] {
        trace.afterHeaders.isEmpty ? trace.beforeHeaders : trace.afterHeaders
    }

    private static func headerValue(named names: [String], in headers: [TopologyPacketHeaderField]) -> String? {
        for name in names {
            if let value = headers.last(where: { $0.name == name })?.value { return value }
        }
        return nil
    }

    private static func protocolName(
        for trace: TopologyPacketTraceEvent,
        headers: [TopologyPacketHeaderField]
    ) -> String {
        if let kind = headerValue(named: ["kind"], in: headers) {
            let uppercased = kind.uppercased()
            if ["ARP", "ICMP", "TCP", "UDP", "DHCP", "DNS", "HTTP", "SMTP", "POP3"].contains(uppercased) {
                return uppercased
            }
            if kind.contains("echo") || kind.contains("unreachable") || kind.contains("timeExceeded") { return "ICMP" }
        }
        if let protocolNumber = headerValue(named: ["protocol"], in: headers) {
            switch protocolNumber {
            case "1": return "ICMP"
            case "6": return "TCP"
            case "17": return "UDP"
            default: return "IP"
            }
        }
        if headerValue(named: ["sourcePort", "destinationPort"], in: headers) != nil {
            return trace.detail?.uppercased().contains("TCP") == true ? "TCP" : "UDP"
        }
        switch trace.layer {
        case .physical, .dataLink: return "Ethernet"
        case .network: return "IP"
        case .transport: return "Transport"
        case .application: return "Anwendung"
        }
    }

    private static func germanLayerName(_ layer: TopologyPacketTraceLayer) -> String {
        switch layer {
        case .physical, .dataLink: return "Netzzugang"
        case .network: return "Vermittlung"
        case .transport: return "Transport"
        case .application: return "Anwendung"
        }
    }

    private static func germanOperationName(_ operation: TopologyPacketTraceOperation) -> String {
        switch operation {
        case .created: return "Erzeugt"
        case .sent: return "Gesendet"
        case .received: return "Empfangen"
        case .forwarded: return "Weitergeleitet"
        case .accepted: return "Akzeptiert"
        case .dropped: return "Verworfen"
        case .rewritten: return "Umschreibung"
        case .retransmitted: return "Erneut gesendet"
        case .compatibilityAdapter: return "Kompatibilitätsadapter"
        }
    }
}

private extension String {
    var nilIfJavaUnconfiguredAddress: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value == TopologyNetworkRuntimeEngine.unspecifiedIPAddress ? nil : value
    }
}
