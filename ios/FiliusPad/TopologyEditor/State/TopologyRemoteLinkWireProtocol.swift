import CryptoKit
import Foundation

struct TopologyRemoteLinkWireFrame: Codable, Equatable, Sendable {
    let sourceMACAddress: String
    let destinationMACAddress: String
    let payload: TopologyRemoteLinkWireEthernetPayload

    init(frame: TopologyEthernetFrame) {
        self.init(
            sourceMACAddress: frame.sourceMACAddress,
            destinationMACAddress: frame.destinationMACAddress,
            payload: TopologyRemoteLinkWireEthernetPayload(payload: frame.payload)
        )
    }

    init(
        sourceMACAddress: String,
        destinationMACAddress: String,
        payload: TopologyRemoteLinkWireEthernetPayload
    ) {
        self.sourceMACAddress = sourceMACAddress
        self.destinationMACAddress = destinationMACAddress
        self.payload = payload
    }
}

enum TopologyRemoteLinkWireEthernetPayload: Codable, Equatable, Sendable {
    case arp(TopologyRemoteLinkWireARPPacket)
    case ipv4(TopologyRemoteLinkWireIPv4Packet)

    private enum CodingKeys: String, CodingKey {
        case kind
        case arp
        case ipv4
    }

    private enum Kind: String, Codable {
        case arp
        case ipv4
    }

    init(payload: TopologyEthernetPayload) {
        switch payload {
        case let .arp(packet):
            self = .arp(TopologyRemoteLinkWireARPPacket(packet: packet))
        case let .ipv4(packet):
            self = .ipv4(TopologyRemoteLinkWireIPv4Packet(packet: packet))
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .arp:
            self = .arp(try container.decode(TopologyRemoteLinkWireARPPacket.self, forKey: .arp))
        case .ipv4:
            self = .ipv4(try container.decode(TopologyRemoteLinkWireIPv4Packet.self, forKey: .ipv4))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .arp(packet):
            try container.encode(Kind.arp, forKey: .kind)
            try container.encode(packet, forKey: .arp)
        case let .ipv4(packet):
            try container.encode(Kind.ipv4, forKey: .kind)
            try container.encode(packet, forKey: .ipv4)
        }
    }
}

struct TopologyRemoteLinkWireARPPacket: Codable, Equatable, Sendable {
    let operation: TopologyARPOperation
    let senderMACAddress: String
    let senderIPAddress: String
    let targetMACAddress: String
    let targetIPAddress: String

    init(packet: TopologyARPPacket) {
        operation = packet.operation
        senderMACAddress = packet.senderMACAddress
        senderIPAddress = packet.senderIPAddress
        targetMACAddress = packet.targetMACAddress
        targetIPAddress = packet.targetIPAddress
    }
}

struct TopologyRemoteLinkWireIPv4Packet: Codable, Equatable, Sendable {
    let senderIPAddress: String
    let receiverIPAddress: String
    let timeToLive: UInt8
    let protocolNumber: TopologyIPv4Protocol
    let payload: TopologyRemoteLinkWireIPv4Payload

    init(packet: TopologyIPv4Packet) {
        self.init(
            senderIPAddress: packet.senderIPAddress,
            receiverIPAddress: packet.receiverIPAddress,
            timeToLive: packet.timeToLive,
            protocolNumber: packet.protocolNumber,
            payload: TopologyRemoteLinkWireIPv4Payload(payload: packet.payload)
        )
    }

    init(
        senderIPAddress: String,
        receiverIPAddress: String,
        timeToLive: UInt8,
        protocolNumber: TopologyIPv4Protocol,
        payload: TopologyRemoteLinkWireIPv4Payload
    ) {
        self.senderIPAddress = senderIPAddress
        self.receiverIPAddress = receiverIPAddress
        self.timeToLive = timeToLive
        self.protocolNumber = protocolNumber
        self.payload = payload
    }
}

indirect enum TopologyRemoteLinkWireIPv4Payload: Codable, Equatable, Sendable {
    case icmp(TopologyRemoteLinkWireICMPMessage)
    case tcp(TopologyRemoteLinkWireTCPSegment)
    case udp(TopologyRemoteLinkWireUDPDatagram)

    private enum CodingKeys: String, CodingKey {
        case kind
        case icmp
        case tcp
        case udp
    }

    private enum Kind: String, Codable {
        case icmp
        case tcp
        case udp
    }

    init(payload: TopologyIPv4Payload) {
        switch payload {
        case let .icmp(message):
            self = .icmp(TopologyRemoteLinkWireICMPMessage(message: message))
        case let .tcp(segment):
            self = .tcp(TopologyRemoteLinkWireTCPSegment(segment: segment))
        case let .udp(datagram):
            self = .udp(TopologyRemoteLinkWireUDPDatagram(datagram: datagram))
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .icmp:
            self = .icmp(try container.decode(TopologyRemoteLinkWireICMPMessage.self, forKey: .icmp))
        case .tcp:
            self = .tcp(try container.decode(TopologyRemoteLinkWireTCPSegment.self, forKey: .tcp))
        case .udp:
            self = .udp(try container.decode(TopologyRemoteLinkWireUDPDatagram.self, forKey: .udp))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .icmp(message):
            try container.encode(Kind.icmp, forKey: .kind)
            try container.encode(message, forKey: .icmp)
        case let .tcp(segment):
            try container.encode(Kind.tcp, forKey: .kind)
            try container.encode(segment, forKey: .tcp)
        case let .udp(datagram):
            try container.encode(Kind.udp, forKey: .kind)
            try container.encode(datagram, forKey: .udp)
        }
    }
}

struct TopologyRemoteLinkWireICMPMessage: Codable, Equatable, Sendable {
    let kind: TopologyICMPMessageKind
    let identifier: UInt16
    let sequenceNumber: UInt16
    let data: Data
    let embeddedOriginalPacket: TopologyRemoteLinkWireIPv4Packet?

    init(message: TopologyICMPMessage) {
        kind = message.kind
        identifier = message.identifier
        sequenceNumber = message.sequenceNumber
        data = message.data
        embeddedOriginalPacket = message.embeddedOriginalPacket.map(TopologyRemoteLinkWireIPv4Packet.init(packet:))
    }
}

struct TopologyRemoteLinkWireTCPSegment: Codable, Equatable, Sendable {
    let sourcePort: UInt16
    let destinationPort: UInt16
    let sequenceNumber: UInt32
    let acknowledgementNumber: UInt32
    let flags: UInt8
    let payload: Data

    init(segment: TopologyTCPSegment) {
        sourcePort = segment.sourcePort
        destinationPort = segment.destinationPort
        sequenceNumber = segment.sequenceNumber
        acknowledgementNumber = segment.acknowledgementNumber
        flags = segment.flags.rawValue
        payload = segment.payload
    }
}

struct TopologyRemoteLinkWireUDPDatagram: Codable, Equatable, Sendable {
    let sourcePort: UInt16
    let destinationPort: UInt16
    let payload: Data

    init(datagram: TopologyUDPDatagram) {
        self.init(
            sourcePort: datagram.sourcePort,
            destinationPort: datagram.destinationPort,
            payload: datagram.payload
        )
    }

    init(sourcePort: UInt16, destinationPort: UInt16, payload: Data) {
        self.sourcePort = sourcePort
        self.destinationPort = destinationPort
        self.payload = payload
    }
}

struct TopologyRemoteLinkWireHandshake: Codable, Equatable, Sendable {
    static let challengeByteCount = 32

    let protocolVersion: UInt16
    let linkDigest: String
    let endpointID: UUID
    let endpointName: String
    let sessionID: UUID
    let challenge: Data

    init(
        protocolVersion: UInt16,
        linkDigest: String,
        endpointID: UUID,
        endpointName: String,
        sessionID: UUID = UUID(),
        challenge: Data? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.linkDigest = linkDigest
        self.endpointID = endpointID
        self.endpointName = endpointName
        self.sessionID = sessionID
        self.challenge = challenge ?? Self.makeChallenge()
    }

    private static func makeChallenge() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }
}

enum TopologyRemoteLinkWireMessage: Equatable, Sendable {
    case hello(TopologyRemoteLinkWireHandshake)
    case sessionReady
    case frame(TopologyRemoteLinkWireFrame)
    case acknowledgement(UInt64)
    case keepAlive
    case disconnect
}

enum TopologyRemoteLinkWireCodecError: Error, Equatable {
    case blankLinkCode
    case recordTooLarge
    case authenticationFailed
    case malformedMessage
    case unsupportedVersion(UInt16)
    case invalidHandshake
    case invalidSession
    case sequenceExhausted
    case unexpectedSequence(expected: UInt64, received: UInt64)
}

struct TopologyRemoteLinkWireEncodedSessionRecord: Equatable, Sendable {
    let sequence: UInt64
    let record: Data
}

struct TopologyRemoteLinkWireDecodedSessionRecord: Equatable, Sendable {
    let sequence: UInt64
    let message: TopologyRemoteLinkWireMessage
}

struct TopologyRemoteLinkWireSessionCodec: Sendable {
    private static let authenticatedContext = Data("Filius Link v2 session record".utf8)

    private let key: SymmetricKey
    private let localSessionID: UUID
    private let remoteSessionID: UUID
    private var nextOutboundSequence: UInt64 = 1
    private var nextInboundSequence: UInt64 = 1

    fileprivate init(
        key: SymmetricKey,
        localSessionID: UUID,
        remoteSessionID: UUID
    ) {
        self.key = key
        self.localSessionID = localSessionID
        self.remoteSessionID = remoteSessionID
    }

    mutating func encode(_ message: TopologyRemoteLinkWireMessage) throws -> TopologyRemoteLinkWireEncodedSessionRecord {
        guard nextOutboundSequence < UInt64.max else {
            throw TopologyRemoteLinkWireCodecError.sequenceExhausted
        }
        guard case .hello = message else {
            let sequence = nextOutboundSequence
            let envelope = SessionEnvelope(
                protocolVersion: TopologyRemoteLinkWireCodec.protocolVersion,
                senderSessionID: localSessionID,
                receiverSessionID: remoteSessionID,
                sequence: sequence,
                payload: TopologyRemoteLinkWirePayloadEnvelope(message: message)
            )
            let plaintext = try PropertyListEncoder().encode(envelope)
            let sealed = try ChaChaPoly.seal(
                plaintext,
                using: key,
                authenticating: Self.authenticatedContext
            )
            let combined = sealed.combined
            guard combined.count <= TopologyRemoteLinkWireCodec.maximumRecordBytes else {
                throw TopologyRemoteLinkWireCodecError.recordTooLarge
            }
            nextOutboundSequence += 1
            return TopologyRemoteLinkWireEncodedSessionRecord(sequence: sequence, record: combined)
        }
        throw TopologyRemoteLinkWireCodecError.invalidSession
    }

    mutating func decode(_ record: Data) throws -> TopologyRemoteLinkWireDecodedSessionRecord {
        guard !record.isEmpty, record.count <= TopologyRemoteLinkWireCodec.maximumRecordBytes else {
            throw TopologyRemoteLinkWireCodecError.recordTooLarge
        }
        let plaintext: Data
        do {
            let sealed = try ChaChaPoly.SealedBox(combined: record)
            plaintext = try ChaChaPoly.open(
                sealed,
                using: key,
                authenticating: Self.authenticatedContext
            )
        } catch {
            throw TopologyRemoteLinkWireCodecError.authenticationFailed
        }
        let envelope: SessionEnvelope
        do {
            envelope = try PropertyListDecoder().decode(SessionEnvelope.self, from: plaintext)
        } catch {
            throw TopologyRemoteLinkWireCodecError.malformedMessage
        }
        guard envelope.protocolVersion == TopologyRemoteLinkWireCodec.protocolVersion else {
            throw TopologyRemoteLinkWireCodecError.unsupportedVersion(envelope.protocolVersion)
        }
        guard envelope.senderSessionID == remoteSessionID,
              envelope.receiverSessionID == localSessionID else {
            throw TopologyRemoteLinkWireCodecError.invalidSession
        }
        guard envelope.sequence == nextInboundSequence else {
            throw TopologyRemoteLinkWireCodecError.unexpectedSequence(
                expected: nextInboundSequence,
                received: envelope.sequence
            )
        }
        let message = try envelope.payload.message()
        if case .hello = message {
            throw TopologyRemoteLinkWireCodecError.invalidSession
        }
        guard nextInboundSequence < UInt64.max else {
            throw TopologyRemoteLinkWireCodecError.sequenceExhausted
        }
        nextInboundSequence += 1
        return TopologyRemoteLinkWireDecodedSessionRecord(sequence: envelope.sequence, message: message)
    }

    private struct SessionEnvelope: Codable {
        let protocolVersion: UInt16
        let senderSessionID: UUID
        let receiverSessionID: UUID
        let sequence: UInt64
        let payload: TopologyRemoteLinkWirePayloadEnvelope
    }
}

struct TopologyRemoteLinkWireCodec: Sendable {
    static let protocolVersion: UInt16 = 2
    static let maximumRecordBytes = 1_048_576

    private static let authenticatedContext = Data("Filius Link v2 handshake".utf8)
    private static let sessionKeyContext = Data("Filius Link v2 session key".utf8)
    private let key: SymmetricKey
    private let linkDigest: String

    init(linkCode: String) {
        let normalized = linkCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let material = normalized.isEmpty ? Data([0]) : Data(normalized.utf8)
        linkDigest = Self.digest(for: normalized)
        key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: material),
            salt: Data("com.filius.pad.remote-link".utf8),
            info: Self.authenticatedContext,
            outputByteCount: 32
        )
    }

    func encode(_ message: TopologyRemoteLinkWireMessage) throws -> Data {
        guard case .hello = message else {
            throw TopologyRemoteLinkWireCodecError.invalidHandshake
        }
        let envelope = TopologyRemoteLinkWirePayloadEnvelope(message: message)
        let plaintext = try PropertyListEncoder().encode(envelope)
        let sealed = try ChaChaPoly.seal(
            plaintext,
            using: key,
            authenticating: Self.authenticatedContext
        )
        let combined = sealed.combined
        guard combined.count <= Self.maximumRecordBytes else {
            throw TopologyRemoteLinkWireCodecError.recordTooLarge
        }
        return combined
    }

    func decode(_ record: Data) throws -> TopologyRemoteLinkWireMessage {
        guard !record.isEmpty, record.count <= Self.maximumRecordBytes else {
            throw TopologyRemoteLinkWireCodecError.recordTooLarge
        }
        let plaintext: Data
        do {
            let sealed = try ChaChaPoly.SealedBox(combined: record)
            plaintext = try ChaChaPoly.open(
                sealed,
                using: key,
                authenticating: Self.authenticatedContext
            )
        } catch {
            throw TopologyRemoteLinkWireCodecError.authenticationFailed
        }
        let envelope: TopologyRemoteLinkWirePayloadEnvelope
        do {
            envelope = try PropertyListDecoder().decode(TopologyRemoteLinkWirePayloadEnvelope.self, from: plaintext)
        } catch {
            throw TopologyRemoteLinkWireCodecError.malformedMessage
        }
        guard envelope.protocolVersion == Self.protocolVersion else {
            throw TopologyRemoteLinkWireCodecError.unsupportedVersion(envelope.protocolVersion)
        }
        let message = try envelope.message()
        guard case let .hello(handshake) = message else {
            throw TopologyRemoteLinkWireCodecError.invalidHandshake
        }
        guard handshake.protocolVersion == Self.protocolVersion else {
            throw TopologyRemoteLinkWireCodecError.unsupportedVersion(handshake.protocolVersion)
        }
        return message
    }

    func makeSessionCodec(
        localHandshake: TopologyRemoteLinkWireHandshake,
        remoteHandshake: TopologyRemoteLinkWireHandshake
    ) throws -> TopologyRemoteLinkWireSessionCodec {
        guard localHandshake.protocolVersion == Self.protocolVersion,
              remoteHandshake.protocolVersion == Self.protocolVersion else {
            let version = localHandshake.protocolVersion == Self.protocolVersion
                ? remoteHandshake.protocolVersion
                : localHandshake.protocolVersion
            throw TopologyRemoteLinkWireCodecError.unsupportedVersion(version)
        }
        guard localHandshake.linkDigest == linkDigest,
              remoteHandshake.linkDigest == linkDigest,
              localHandshake.endpointID != remoteHandshake.endpointID,
              localHandshake.sessionID != remoteHandshake.sessionID,
              localHandshake.challenge.count == TopologyRemoteLinkWireHandshake.challengeByteCount,
              remoteHandshake.challenge.count == TopologyRemoteLinkWireHandshake.challengeByteCount else {
            throw TopologyRemoteLinkWireCodecError.invalidHandshake
        }

        let ordered = [localHandshake, remoteHandshake].sorted { lhs, rhs in
            let lhsKey = lhs.endpointID.uuidString + lhs.sessionID.uuidString
            let rhsKey = rhs.endpointID.uuidString + rhs.sessionID.uuidString
            return lhsKey < rhsKey
        }
        var transcript = Data(Self.sessionKeyContext)
        for handshake in ordered {
            Self.appendLengthPrefixed(Data(handshake.endpointID.uuidString.utf8), to: &transcript)
            Self.appendLengthPrefixed(Data(handshake.sessionID.uuidString.utf8), to: &transcript)
            Self.appendLengthPrefixed(handshake.challenge, to: &transcript)
        }
        let salt = Data(SHA256.hash(data: transcript))
        let sessionKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            salt: salt,
            info: Self.sessionKeyContext,
            outputByteCount: 32
        )
        return TopologyRemoteLinkWireSessionCodec(
            key: sessionKey,
            localSessionID: localHandshake.sessionID,
            remoteSessionID: remoteHandshake.sessionID
        )
    }

    static func digest(for linkCode: String) -> String {
        let normalized = linkCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func appendLengthPrefixed(_ value: Data, to output: inout Data) {
        var length = UInt32(value.count).bigEndian
        withUnsafeBytes(of: &length) { output.append(contentsOf: $0) }
        output.append(value)
    }
}

private struct TopologyRemoteLinkWirePayloadEnvelope: Codable, Equatable, Sendable {
    enum Kind: String, Codable {
        case hello
        case sessionReady
        case frame
        case acknowledgement
        case keepAlive
        case disconnect
    }

    let protocolVersion: UInt16
    let kind: Kind
    let handshake: TopologyRemoteLinkWireHandshake?
    let frame: TopologyRemoteLinkWireFrame?
    let acknowledgedSequence: UInt64?

    init(message: TopologyRemoteLinkWireMessage) {
        protocolVersion = TopologyRemoteLinkWireCodec.protocolVersion
        switch message {
        case let .hello(handshake):
            kind = .hello
            self.handshake = handshake
            frame = nil
            acknowledgedSequence = nil
        case .sessionReady:
            kind = .sessionReady
            handshake = nil
            frame = nil
            acknowledgedSequence = nil
        case let .frame(frame):
            kind = .frame
            handshake = nil
            self.frame = frame
            acknowledgedSequence = nil
        case let .acknowledgement(sequence):
            kind = .acknowledgement
            handshake = nil
            frame = nil
            acknowledgedSequence = sequence
        case .keepAlive:
            kind = .keepAlive
            handshake = nil
            frame = nil
            acknowledgedSequence = nil
        case .disconnect:
            kind = .disconnect
            handshake = nil
            frame = nil
            acknowledgedSequence = nil
        }
    }

    func message() throws -> TopologyRemoteLinkWireMessage {
        switch kind {
        case .hello:
            guard let handshake else { throw TopologyRemoteLinkWireCodecError.malformedMessage }
            return .hello(handshake)
        case .sessionReady:
            return .sessionReady
        case .frame:
            guard let frame else { throw TopologyRemoteLinkWireCodecError.malformedMessage }
            return .frame(frame)
        case .acknowledgement:
            guard let acknowledgedSequence else { throw TopologyRemoteLinkWireCodecError.malformedMessage }
            return .acknowledgement(acknowledgedSequence)
        case .keepAlive:
            return .keepAlive
        case .disconnect:
            return .disconnect
        }
    }
}


extension TopologyNetworkRuntimeEngine {
    mutating func materializeLANRemoteLinkFrame(_ wireFrame: TopologyRemoteLinkWireFrame) -> TopologyEthernetFrame {
        TopologyEthernetFrame(
            identity: allocateFrameIdentity(),
            sourceMACAddress: wireFrame.sourceMACAddress,
            destinationMACAddress: wireFrame.destinationMACAddress,
            payload: materializeLANRemoteLinkEthernetPayload(wireFrame.payload)
        )
    }

    private mutating func materializeLANRemoteLinkEthernetPayload(
        _ payload: TopologyRemoteLinkWireEthernetPayload
    ) -> TopologyEthernetPayload {
        switch payload {
        case let .arp(packet):
            return .arp(TopologyARPPacket(
                operation: packet.operation,
                senderMACAddress: packet.senderMACAddress,
                senderIPAddress: packet.senderIPAddress,
                targetMACAddress: packet.targetMACAddress,
                targetIPAddress: packet.targetIPAddress
            ))
        case let .ipv4(packet):
            return .ipv4(materializeLANRemoteLinkIPv4Packet(packet))
        }
    }

    private mutating func materializeLANRemoteLinkIPv4Packet(
        _ packet: TopologyRemoteLinkWireIPv4Packet
    ) -> TopologyIPv4Packet {
        TopologyIPv4Packet(
            identity: allocatePacketIdentity(),
            senderIPAddress: packet.senderIPAddress,
            receiverIPAddress: packet.receiverIPAddress,
            timeToLive: packet.timeToLive,
            protocolNumber: packet.protocolNumber,
            payload: materializeLANRemoteLinkIPv4Payload(packet.payload)
        )
    }

    private mutating func materializeLANRemoteLinkIPv4Payload(
        _ payload: TopologyRemoteLinkWireIPv4Payload
    ) -> TopologyIPv4Payload {
        switch payload {
        case let .icmp(message):
            return .icmp(TopologyICMPMessage(
                kind: message.kind,
                identifier: message.identifier,
                sequenceNumber: message.sequenceNumber,
                data: message.data,
                embeddedOriginalPacket: message.embeddedOriginalPacket.map { materializeLANRemoteLinkIPv4Packet($0) }
            ))
        case let .tcp(segment):
            return .tcp(TopologyTCPSegment(
                sourcePort: segment.sourcePort,
                destinationPort: segment.destinationPort,
                sequenceNumber: segment.sequenceNumber,
                acknowledgementNumber: segment.acknowledgementNumber,
                flags: TopologyTCPFlags(rawValue: segment.flags),
                payload: segment.payload
            ))
        case let .udp(datagram):
            return .udp(TopologyUDPDatagram(
                sourcePort: datagram.sourcePort,
                destinationPort: datagram.destinationPort,
                payload: datagram.payload
            ))
        }
    }
}
