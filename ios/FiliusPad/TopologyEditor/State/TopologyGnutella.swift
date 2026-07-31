import Foundation

/// Deterministic, transport-agnostic model of Filius' educational Gnutella substitution.
/// Networking is represented as outbound messages; this file never opens a host socket.
enum TopologyGnutella {
    static let tcpPort: UInt16 = 6_346
    static let peerToPeerDirectory = "/peer2peer"
    static let defaultTTL = 8
}

enum TopologyGnutellaError: Error, Equatable, LocalizedError {
    case invalidLimits(String)
    case invalidGUID(String)
    case guidSequenceExhausted
    case invalidPeerID(String)
    case invalidHost(String)
    case invalidPort(Int)
    case invalidTTL(Int)
    case invalidHops(Int)
    case invalidFileName(String)
    case invalidMediaType(String)
    case invalidFileSize(Int)
    case fileSizeDoesNotMatchMetadata(expected: Int, actual: Int)
    case invalidSearchTerm(String)
    case packetTooLarge(actualBytes: Int, limitBytes: Int)
    case payloadTooLarge(actualBytes: Int, limitBytes: Int)
    case fieldTooLarge(name: String, actualBytes: Int, limitBytes: Int)
    case malformedPacket(String)
    case unsupportedPayload(String)
    case invalidInteger(field: String, value: String)
    case invalidPercentEncoding(String)
    case payloadLengthMismatch(declaredBytes: Int, actualBytes: Int)
    case quotaExceeded(name: String, actual: Int, limit: Int)
    case invalidDirectPath(String)
    case directTransferStatus(Int)
    case missingDirectTransferBody

    var errorDescription: String? {
        switch self {
        case let .invalidLimits(reason): return "Invalid Gnutella limits: \(reason)"
        case let .invalidGUID(value): return "Invalid deterministic Gnutella GUID: \(value)"
        case .guidSequenceExhausted: return "The injected deterministic Gnutella GUID sequence is exhausted."
        case let .invalidPeerID(value): return "Invalid Gnutella peer identifier: \(value)"
        case let .invalidHost(value): return "Invalid Gnutella peer host: \(value)"
        case let .invalidPort(value): return "Gnutella uses TCP port 6346; received port \(value)."
        case let .invalidTTL(value): return "Invalid Gnutella TTL: \(value)"
        case let .invalidHops(value): return "Invalid Gnutella hop count: \(value)"
        case let .invalidFileName(value): return "Invalid direct /peer2peer file name: \(value)"
        case let .invalidMediaType(value): return "Invalid Gnutella media type: \(value)"
        case let .invalidFileSize(value): return "Invalid Gnutella file size: \(value)"
        case let .fileSizeDoesNotMatchMetadata(expected, actual):
            return "Gnutella file metadata declares \(expected) bytes but the body contains \(actual) bytes."
        case let .invalidSearchTerm(value): return "Invalid Gnutella search term: \(value)"
        case let .packetTooLarge(actualBytes, limitBytes):
            return "Gnutella packet uses \(actualBytes) bytes; the limit is \(limitBytes) bytes."
        case let .payloadTooLarge(actualBytes, limitBytes):
            return "Gnutella payload uses \(actualBytes) bytes; the limit is \(limitBytes) bytes."
        case let .fieldTooLarge(name, actualBytes, limitBytes):
            return "Gnutella field \(name) uses \(actualBytes) bytes; the limit is \(limitBytes) bytes."
        case let .malformedPacket(reason): return "Malformed Gnutella packet: \(reason)"
        case let .unsupportedPayload(value): return "Unsupported Gnutella payload descriptor: \(value)"
        case let .invalidInteger(field, value): return "Invalid integer in Gnutella field \(field): \(value)"
        case let .invalidPercentEncoding(value): return "Invalid percent-encoded Gnutella field: \(value)"
        case let .payloadLengthMismatch(declaredBytes, actualBytes):
            return "Gnutella payload length declares \(declaredBytes) bytes but contains \(actualBytes) bytes."
        case let .quotaExceeded(name, actual, limit):
            return "Gnutella quota \(name) exceeded: \(actual) is greater than \(limit)."
        case let .invalidDirectPath(path): return "Invalid direct Gnutella path: \(path)"
        case let .directTransferStatus(status): return "Direct Gnutella download failed with status \(status)."
        case .missingDirectTransferBody: return "A successful direct Gnutella response did not contain a file body."
        }
    }
}

struct TopologyGnutellaLimits: Equatable {
    let maximumEncodedPacketBytes: Int
    let maximumPayloadBytes: Int
    let maximumFieldBytes: Int
    let maximumGUIDBytes: Int
    let maximumPeerIDBytes: Int
    let maximumHostBytes: Int
    let maximumSearchBytes: Int
    let maximumFileNameBytes: Int
    let maximumMediaTypeBytes: Int
    let maximumDirectFileBytes: Int
    let maximumQueryHitsPerPacket: Int
    let maximumSharedFiles: Int
    let maximumNeighbors: Int
    let maximumSeenRequestGUIDs: Int
    let maximumReverseRoutes: Int
    let maximumLocalRequests: Int
    let maximumStoredResults: Int
    let maximumTTL: Int
    let maximumHops: Int
    let responseTTL: Int

    static let educationalDefault = TopologyGnutellaLimits()

    private init() {
        maximumEncodedPacketBytes = 64 * 1_024
        maximumPayloadBytes = 60 * 1_024
        maximumFieldBytes = 4 * 1_024
        maximumGUIDBytes = 64
        maximumPeerIDBytes = 128
        maximumHostBytes = 255
        maximumSearchBytes = 512
        maximumFileNameBytes = 255
        maximumMediaTypeBytes = 128
        maximumDirectFileBytes = 8 * 1_024 * 1_024
        maximumQueryHitsPerPacket = 256
        maximumSharedFiles = 4_096
        maximumNeighbors = 32
        maximumSeenRequestGUIDs = 4_096
        maximumReverseRoutes = 4_096
        maximumLocalRequests = 1_024
        maximumStoredResults = 4_096
        maximumTTL = 16
        maximumHops = 255
        responseTTL = TopologyGnutella.defaultTTL
    }

    init(
        maximumEncodedPacketBytes: Int,
        maximumPayloadBytes: Int,
        maximumFieldBytes: Int,
        maximumGUIDBytes: Int,
        maximumPeerIDBytes: Int,
        maximumHostBytes: Int,
        maximumSearchBytes: Int,
        maximumFileNameBytes: Int,
        maximumMediaTypeBytes: Int,
        maximumDirectFileBytes: Int,
        maximumQueryHitsPerPacket: Int,
        maximumSharedFiles: Int,
        maximumNeighbors: Int,
        maximumSeenRequestGUIDs: Int,
        maximumReverseRoutes: Int,
        maximumLocalRequests: Int,
        maximumStoredResults: Int,
        maximumTTL: Int,
        maximumHops: Int,
        responseTTL: Int
    ) throws {
        let positiveValues = [
            maximumEncodedPacketBytes, maximumPayloadBytes, maximumFieldBytes,
            maximumGUIDBytes, maximumPeerIDBytes, maximumHostBytes, maximumSearchBytes,
            maximumFileNameBytes, maximumMediaTypeBytes, maximumDirectFileBytes,
            maximumQueryHitsPerPacket, maximumSharedFiles, maximumNeighbors,
            maximumSeenRequestGUIDs, maximumReverseRoutes, maximumLocalRequests,
            maximumStoredResults, maximumTTL, maximumHops, responseTTL,
        ]
        guard positiveValues.allSatisfy({ $0 > 0 }) else {
            throw TopologyGnutellaError.invalidLimits("all quotas must be positive")
        }
        guard maximumPayloadBytes <= maximumEncodedPacketBytes else {
            throw TopologyGnutellaError.invalidLimits("payload quota must not exceed packet quota")
        }
        guard responseTTL <= maximumTTL else {
            throw TopologyGnutellaError.invalidLimits("response TTL must not exceed maximum TTL")
        }
        self.maximumEncodedPacketBytes = maximumEncodedPacketBytes
        self.maximumPayloadBytes = maximumPayloadBytes
        self.maximumFieldBytes = maximumFieldBytes
        self.maximumGUIDBytes = maximumGUIDBytes
        self.maximumPeerIDBytes = maximumPeerIDBytes
        self.maximumHostBytes = maximumHostBytes
        self.maximumSearchBytes = maximumSearchBytes
        self.maximumFileNameBytes = maximumFileNameBytes
        self.maximumMediaTypeBytes = maximumMediaTypeBytes
        self.maximumDirectFileBytes = maximumDirectFileBytes
        self.maximumQueryHitsPerPacket = maximumQueryHitsPerPacket
        self.maximumSharedFiles = maximumSharedFiles
        self.maximumNeighbors = maximumNeighbors
        self.maximumSeenRequestGUIDs = maximumSeenRequestGUIDs
        self.maximumReverseRoutes = maximumReverseRoutes
        self.maximumLocalRequests = maximumLocalRequests
        self.maximumStoredResults = maximumStoredResults
        self.maximumTTL = maximumTTL
        self.maximumHops = maximumHops
        self.responseTTL = responseTTL
    }
}

struct TopologyGnutellaGUID: Hashable, Comparable, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String, limits: TopologyGnutellaLimits = .educationalDefault) throws {
        let byteCount = rawValue.lengthOfBytes(using: .utf8)
        let isSafeASCII = rawValue.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 45, 46, 48 ... 57, 65 ... 90, 95, 97 ... 122, 126: return true
            default: return false
            }
        }
        guard !rawValue.isEmpty, byteCount <= limits.maximumGUIDBytes, isSafeASCII else {
            throw TopologyGnutellaError.invalidGUID(rawValue)
        }
        self.rawValue = rawValue
    }

    var description: String { rawValue }
    static func < (lhs: TopologyGnutellaGUID, rhs: TopologyGnutellaGUID) -> Bool { lhs.rawValue < rhs.rawValue }
}

protocol TopologyGnutellaGUIDGenerating: AnyObject {
    func nextGUID() throws -> TopologyGnutellaGUID
}

struct TopologyGnutellaPeer: Hashable, Comparable {
    let id: String
    let host: String
    let port: UInt16

    init(
        id: String,
        host: String,
        port: UInt16 = TopologyGnutella.tcpPort,
        limits: TopologyGnutellaLimits = .educationalDefault
    ) throws {
        try Self.validateText(id, isPeerID: true, maximumBytes: limits.maximumPeerIDBytes)
        try Self.validateText(host, isPeerID: false, maximumBytes: limits.maximumHostBytes)
        guard port == TopologyGnutella.tcpPort else { throw TopologyGnutellaError.invalidPort(Int(port)) }
        self.id = id
        self.host = host
        self.port = port
    }

    static func < (lhs: TopologyGnutellaPeer, rhs: TopologyGnutellaPeer) -> Bool {
        if lhs.id == rhs.id {
            if lhs.host == rhs.host { return lhs.port < rhs.port }
            return lhs.host < rhs.host
        }
        return lhs.id < rhs.id
    }

    private static func validateText(_ value: String, isPeerID: Bool, maximumBytes: Int) throws {
        let bytes = value.lengthOfBytes(using: .utf8)
        let hasControl = value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
        guard !value.isEmpty, bytes <= maximumBytes, !hasControl else {
            throw isPeerID ? TopologyGnutellaError.invalidPeerID(value) : TopologyGnutellaError.invalidHost(value)
        }
    }
}

struct TopologyGnutellaFileMetadata: Hashable {
    let name: String
    let sizeBytes: Int
    let mediaType: String

    init(
        name: String,
        sizeBytes: Int,
        mediaType: String = "application/octet-stream",
        limits: TopologyGnutellaLimits = .educationalDefault
    ) throws {
        try topologyGnutellaValidateFileName(name, limits: limits)
        guard sizeBytes >= 0, sizeBytes <= limits.maximumDirectFileBytes else {
            throw TopologyGnutellaError.invalidFileSize(sizeBytes)
        }
        let mediaBytes = mediaType.lengthOfBytes(using: .utf8)
        let invalidMediaType = mediaType.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
        guard !mediaType.isEmpty, mediaBytes <= limits.maximumMediaTypeBytes, !invalidMediaType else {
            throw TopologyGnutellaError.invalidMediaType(mediaType)
        }
        self.name = name
        self.sizeBytes = sizeBytes
        self.mediaType = mediaType
    }
}

struct TopologyGnutellaFileResource: Equatable {
    let metadata: TopologyGnutellaFileMetadata
    let data: Data

    init(metadata: TopologyGnutellaFileMetadata, data: Data, limits: TopologyGnutellaLimits = .educationalDefault) throws {
        guard data.count <= limits.maximumDirectFileBytes else { throw TopologyGnutellaError.invalidFileSize(data.count) }
        guard metadata.sizeBytes == data.count else {
            throw TopologyGnutellaError.fileSizeDoesNotMatchMetadata(expected: metadata.sizeBytes, actual: data.count)
        }
        self.metadata = metadata
        self.data = data
    }
}

protocol TopologyGnutellaFileStore: AnyObject {
    func listPeerToPeerFiles() throws -> [TopologyGnutellaFileMetadata]
    func readPeerToPeerFile(named name: String) throws -> TopologyGnutellaFileResource?
    func writeDownloadedPeerToPeerFile(_ file: TopologyGnutellaFileResource, overwrite: Bool) throws
}

enum TopologyGnutellaPayloadDescriptor: String, CaseIterable {
    case ping = "0x00"
    case pong = "0x01"
    case query = "0x80"
    case queryHit = "0x81"
}

enum TopologyGnutellaPacketPayload: Equatable {
    case ping(origin: TopologyGnutellaPeer)
    case pong(responder: TopologyGnutellaPeer, sharedFileCount: Int, totalSharedBytes: Int)
    case query(minimumSpeedKbps: Int, searchTerm: String)
    case queryHit(responder: TopologyGnutellaPeer, speedKbps: Int, serventIdentifier: String, results: [TopologyGnutellaFileMetadata])

    var descriptor: TopologyGnutellaPayloadDescriptor {
        switch self {
        case .ping: return .ping
        case .pong: return .pong
        case .query: return .query
        case .queryHit: return .queryHit
        }
    }
}

struct TopologyGnutellaPacketBase: Equatable {
    let guid: TopologyGnutellaGUID
    let payload: TopologyGnutellaPayloadDescriptor
    let hops: Int
    let ttl: Int
    let payloadLength: Int
}

struct TopologyGnutellaPacket: Equatable {
    let guid: TopologyGnutellaGUID
    let hops: Int
    let ttl: Int
    let payload: TopologyGnutellaPacketPayload

    var descriptor: TopologyGnutellaPayloadDescriptor { payload.descriptor }
    var base: TopologyGnutellaPacketBase {
        TopologyGnutellaPacketBase(
            guid: guid,
            payload: descriptor,
            hops: hops,
            ttl: ttl,
            payloadLength: TopologyGnutellaTextCodec.encodedPayloadByteCount(payload)
        )
    }

    func forwarded(limits: TopologyGnutellaLimits = .educationalDefault) -> TopologyGnutellaPacket? {
        guard ttl > 1, hops < limits.maximumHops else { return nil }
        return TopologyGnutellaPacket(guid: guid, hops: hops + 1, ttl: ttl - 1, payload: payload)
    }
}

enum TopologyGnutellaTextCodec {
    static func encode(_ packet: TopologyGnutellaPacket, limits: TopologyGnutellaLimits = .educationalDefault) throws -> String {
        try validate(packet, limits: limits)
        let payloadFields = encodedPayloadFields(packet.payload)
        let payloadText = payloadFields.joined(separator: "//")
        let payloadBytes = payloadText.lengthOfBytes(using: .utf8)
        guard payloadBytes <= limits.maximumPayloadBytes else {
            throw TopologyGnutellaError.payloadTooLarge(actualBytes: payloadBytes, limitBytes: limits.maximumPayloadBytes)
        }
        let fields = [
            packet.guid.rawValue,
            packet.descriptor.rawValue,
            String(packet.hops),
            String(packet.ttl),
            String(payloadBytes),
        ] + payloadFields
        let encoded = fields.joined(separator: "//")
        let packetBytes = encoded.lengthOfBytes(using: .utf8)
        guard packetBytes <= limits.maximumEncodedPacketBytes else {
            throw TopologyGnutellaError.packetTooLarge(actualBytes: packetBytes, limitBytes: limits.maximumEncodedPacketBytes)
        }
        return encoded
    }

    static func decode(_ encoded: String, limits: TopologyGnutellaLimits = .educationalDefault) throws -> TopologyGnutellaPacket {
        let packetBytes = encoded.lengthOfBytes(using: .utf8)
        guard packetBytes <= limits.maximumEncodedPacketBytes else {
            throw TopologyGnutellaError.packetTooLarge(actualBytes: packetBytes, limitBytes: limits.maximumEncodedPacketBytes)
        }
        let fields = encoded.components(separatedBy: "//")
        guard fields.count >= 5 else { throw TopologyGnutellaError.malformedPacket("expected the five-field packet base") }
        let guid = try TopologyGnutellaGUID(fields[0], limits: limits)
        guard let descriptor = TopologyGnutellaPayloadDescriptor(rawValue: fields[1]) else {
            throw TopologyGnutellaError.unsupportedPayload(fields[1])
        }
        let hops = try parseInteger(fields[2], name: "hops")
        let ttl = try parseInteger(fields[3], name: "ttl")
        let declaredPayloadLength = try parseInteger(fields[4], name: "payloadLength")
        let rawPayloadFields = Array(fields.dropFirst(5))
        let rawPayloadText = rawPayloadFields.joined(separator: "//")
        let actualPayloadLength = rawPayloadText.lengthOfBytes(using: .utf8)
        guard declaredPayloadLength == actualPayloadLength else {
            throw TopologyGnutellaError.payloadLengthMismatch(declaredBytes: declaredPayloadLength, actualBytes: actualPayloadLength)
        }
        guard actualPayloadLength <= limits.maximumPayloadBytes else {
            throw TopologyGnutellaError.payloadTooLarge(actualBytes: actualPayloadLength, limitBytes: limits.maximumPayloadBytes)
        }
        let payload = try decodePayload(descriptor: descriptor, fields: rawPayloadFields, limits: limits)
        let packet = TopologyGnutellaPacket(guid: guid, hops: hops, ttl: ttl, payload: payload)
        try validate(packet, limits: limits)
        return packet
    }

    fileprivate static func encodedPayloadByteCount(_ payload: TopologyGnutellaPacketPayload) -> Int {
        encodedPayloadFields(payload).joined(separator: "//").lengthOfBytes(using: .utf8)
    }

    private static func validate(_ packet: TopologyGnutellaPacket, limits: TopologyGnutellaLimits) throws {
        guard packet.ttl >= 0, packet.ttl <= limits.maximumTTL else { throw TopologyGnutellaError.invalidTTL(packet.ttl) }
        guard packet.hops >= 0, packet.hops <= limits.maximumHops else { throw TopologyGnutellaError.invalidHops(packet.hops) }
        switch packet.payload {
        case let .ping(origin):
            try validatePeer(origin, limits: limits)
        case let .pong(responder, fileCount, totalBytes):
            try validatePeer(responder, limits: limits)
            guard fileCount >= 0, fileCount <= limits.maximumSharedFiles else {
                throw TopologyGnutellaError.quotaExceeded(name: "sharedFiles", actual: fileCount, limit: limits.maximumSharedFiles)
            }
            guard totalBytes >= 0 else { throw TopologyGnutellaError.invalidFileSize(totalBytes) }
        case let .query(minimumSpeedKbps, searchTerm):
            guard minimumSpeedKbps >= 0 else {
                throw TopologyGnutellaError.invalidInteger(field: "minimumSpeedKbps", value: String(minimumSpeedKbps))
            }
            let searchBytes = searchTerm.lengthOfBytes(using: .utf8)
            let hasControl = searchTerm.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
            guard searchBytes <= limits.maximumSearchBytes, !hasControl else {
                throw TopologyGnutellaError.invalidSearchTerm(searchTerm)
            }
        case let .queryHit(responder, speedKbps, serventIdentifier, results):
            try validatePeer(responder, limits: limits)
            guard speedKbps >= 0 else {
                throw TopologyGnutellaError.invalidInteger(field: "speedKbps", value: String(speedKbps))
            }
            try validateField(serventIdentifier, name: "serventIdentifier", maximumBytes: limits.maximumFieldBytes)
            guard !results.isEmpty, results.count <= limits.maximumQueryHitsPerPacket else {
                throw TopologyGnutellaError.quotaExceeded(name: "queryHitsPerPacket", actual: results.count, limit: limits.maximumQueryHitsPerPacket)
            }
            for result in results {
                _ = try TopologyGnutellaFileMetadata(
                    name: result.name,
                    sizeBytes: result.sizeBytes,
                    mediaType: result.mediaType,
                    limits: limits
                )
            }
        }
    }

    private static func validatePeer(_ peer: TopologyGnutellaPeer, limits: TopologyGnutellaLimits) throws {
        _ = try TopologyGnutellaPeer(id: peer.id, host: peer.host, port: peer.port, limits: limits)
    }

    private static func validateField(_ value: String, name: String, maximumBytes: Int) throws {
        let bytes = value.lengthOfBytes(using: .utf8)
        let hasControl = value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
        guard bytes <= maximumBytes, !hasControl else {
            throw TopologyGnutellaError.fieldTooLarge(name: name, actualBytes: bytes, limitBytes: maximumBytes)
        }
    }

    private static func encodedPayloadFields(_ payload: TopologyGnutellaPacketPayload) -> [String] {
        switch payload {
        case let .ping(origin):
            return [escape(origin.id), escape(origin.host), String(origin.port)]
        case let .pong(responder, sharedFileCount, totalSharedBytes):
            return [
                escape(responder.id), escape(responder.host), String(responder.port),
                String(sharedFileCount), String(totalSharedBytes),
            ]
        case let .query(minimumSpeedKbps, searchTerm):
            return [String(minimumSpeedKbps), escape(searchTerm)]
        case let .queryHit(responder, speedKbps, serventIdentifier, results):
            var fields = [
                escape(responder.id), escape(responder.host), String(responder.port),
                String(speedKbps), escape(serventIdentifier), String(results.count),
            ]
            for result in results {
                fields.append(escape(result.name))
                fields.append(String(result.sizeBytes))
                fields.append(escape(result.mediaType))
            }
            return fields
        }
    }

    private static func decodePayload(
        descriptor: TopologyGnutellaPayloadDescriptor,
        fields: [String],
        limits: TopologyGnutellaLimits
    ) throws -> TopologyGnutellaPacketPayload {
        switch descriptor {
        case .ping:
            guard fields.count == 3 else { throw TopologyGnutellaError.malformedPacket("ping requires origin id, host, and port") }
            return .ping(origin: try decodePeer(fields, start: 0, limits: limits))
        case .pong:
            guard fields.count == 5 else {
                throw TopologyGnutellaError.malformedPacket("pong requires responder id, host, port, file count, and total bytes")
            }
            return .pong(
                responder: try decodePeer(fields, start: 0, limits: limits),
                sharedFileCount: try parseInteger(fields[3], name: "sharedFileCount"),
                totalSharedBytes: try parseInteger(fields[4], name: "totalSharedBytes")
            )
        case .query:
            guard fields.count == 2 else { throw TopologyGnutellaError.malformedPacket("query requires minimum speed and a search term") }
            return .query(
                minimumSpeedKbps: try parseInteger(fields[0], name: "minimumSpeedKbps"),
                searchTerm: try unescape(fields[1], limits: limits, name: "searchTerm")
            )
        case .queryHit:
            guard fields.count >= 6 else { throw TopologyGnutellaError.malformedPacket("query hit base is incomplete") }
            let responder = try decodePeer(fields, start: 0, limits: limits)
            let speed = try parseInteger(fields[3], name: "speedKbps")
            let servent = try unescape(fields[4], limits: limits, name: "serventIdentifier")
            let count = try parseInteger(fields[5], name: "resultCount")
            guard count > 0, count <= limits.maximumQueryHitsPerPacket else {
                throw TopologyGnutellaError.quotaExceeded(name: "queryHitsPerPacket", actual: count, limit: limits.maximumQueryHitsPerPacket)
            }
            guard fields.count == 6 + (count * 3) else {
                throw TopologyGnutellaError.malformedPacket("query hit result count does not match its structured fields")
            }
            var results: [TopologyGnutellaFileMetadata] = []
            results.reserveCapacity(count)
            for index in 0 ..< count {
                let offset = 6 + (index * 3)
                results.append(
                    try TopologyGnutellaFileMetadata(
                        name: unescape(fields[offset], limits: limits, name: "fileName"),
                        sizeBytes: parseInteger(fields[offset + 1], name: "fileSize"),
                        mediaType: unescape(fields[offset + 2], limits: limits, name: "mediaType"),
                        limits: limits
                    )
                )
            }
            return .queryHit(responder: responder, speedKbps: speed, serventIdentifier: servent, results: results)
        }
    }

    private static func decodePeer(_ fields: [String], start: Int, limits: TopologyGnutellaLimits) throws -> TopologyGnutellaPeer {
        let id = try unescape(fields[start], limits: limits, name: "peerID")
        let host = try unescape(fields[start + 1], limits: limits, name: "host")
        let portValue = try parseInteger(fields[start + 2], name: "port")
        guard let port = UInt16(exactly: portValue) else { throw TopologyGnutellaError.invalidPort(portValue) }
        return try TopologyGnutellaPeer(id: id, host: host, port: port, limits: limits)
    }

    private static func parseInteger(_ value: String, name: String) throws -> Int {
        guard !value.isEmpty,
              value.unicodeScalars.allSatisfy({ (48 ... 57).contains($0.value) }),
              let parsed = Int(value)
        else {
            throw TopologyGnutellaError.invalidInteger(field: name, value: value)
        }
        return parsed
    }

    private static func escape(_ value: String) -> String {
        var output = ""
        output.reserveCapacity(value.utf8.count)
        let hex = Array("0123456789ABCDEF".utf8)
        for byte in value.utf8 {
            switch byte {
            case 45, 46, 48 ... 57, 65 ... 90, 95, 97 ... 122, 126:
                output.unicodeScalars.append(UnicodeScalar(byte))
            default:
                output.append("%")
                output.unicodeScalars.append(UnicodeScalar(hex[Int(byte >> 4)]))
                output.unicodeScalars.append(UnicodeScalar(hex[Int(byte & 0x0F)]))
            }
        }
        return output
    }

    private static func unescape(_ value: String, limits: TopologyGnutellaLimits, name: String) throws -> String {
        let source = Array(value.utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(source.count)
        var index = 0
        while index < source.count {
            if source[index] == 37 {
                guard index + 2 < source.count,
                      let high = hexadecimalValue(source[index + 1]),
                      let low = hexadecimalValue(source[index + 2])
                else {
                    throw TopologyGnutellaError.invalidPercentEncoding(value)
                }
                bytes.append((high << 4) | low)
                index += 3
            } else {
                bytes.append(source[index])
                index += 1
            }
        }
        guard let decoded = String(bytes: bytes, encoding: .utf8) else {
            throw TopologyGnutellaError.invalidPercentEncoding(value)
        }
        try validateField(decoded, name: name, maximumBytes: limits.maximumFieldBytes)
        return decoded
    }

    private static func hexadecimalValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48 ... 57: return byte - 48
        case 65 ... 70: return byte - 55
        case 97 ... 102: return byte - 87
        default: return nil
        }
    }
}

struct TopologyGnutellaSearchResult: Hashable {
    let queryGUID: TopologyGnutellaGUID
    let peer: TopologyGnutellaPeer
    let speedKbps: Int
    let serventIdentifier: String
    let file: TopologyGnutellaFileMetadata
}

struct TopologyGnutellaReverseRoute: Equatable {
    let guid: TopologyGnutellaGUID
    let previousHop: TopologyGnutellaPeer
}

struct TopologyGnutellaOutboundMessage: Equatable {
    let destination: TopologyGnutellaPeer
    let packet: TopologyGnutellaPacket
}

enum TopologyGnutellaProcessingDisposition: String {
    case originated
    case acceptedRequest
    case duplicateSuppressed
    case responseDelivered
    case responseRouted
    case ttlBoundaryReached
    case orphanResponse
}

enum TopologyGnutellaProcessingEvent: Equatable {
    case discoveryStarted(guid: TopologyGnutellaGUID, bootstrap: TopologyGnutellaPeer)
    case queryStarted(guid: TopologyGnutellaGUID, searchTerm: String)
    case requestAccepted(guid: TopologyGnutellaGUID, descriptor: TopologyGnutellaPayloadDescriptor)
    case duplicateRequestSuppressed(guid: TopologyGnutellaGUID)
    case reverseRouteStored(TopologyGnutellaReverseRoute)
    case neighborAdded(TopologyGnutellaPeer)
    case neighborRejectedAtCap(TopologyGnutellaPeer)
    case localMatches(guid: TopologyGnutellaGUID, count: Int)
    case searchResultsUpdated(guid: TopologyGnutellaGUID, totalCount: Int)
    case ttlBoundary(guid: TopologyGnutellaGUID)
    case responseWithoutRoute(guid: TopologyGnutellaGUID)
}

struct TopologyGnutellaProcessingResult: Equatable {
    let disposition: TopologyGnutellaProcessingDisposition
    let outbound: [TopologyGnutellaOutboundMessage]
    let events: [TopologyGnutellaProcessingEvent]
}

final class TopologyGnutellaPeerCore: Equatable {
    enum LocalRequestKind: Equatable {
        case discovery
        case query
    }

    let localPeer: TopologyGnutellaPeer
    let neighborCap: Int
    let limits: TopologyGnutellaLimits

    private let guidGenerator: TopologyGnutellaGUIDGenerating
    private let fileStore: TopologyGnutellaFileStore
    private var neighborsByID: [String: TopologyGnutellaPeer] = [:]
    private var seenRequestGUIDs: Set<TopologyGnutellaGUID> = []
    private var seenRequestOrder: [TopologyGnutellaGUID] = []
    private var reverseRoutesByGUID: [TopologyGnutellaGUID: TopologyGnutellaPeer] = [:]
    private var reverseRouteOrder: [TopologyGnutellaGUID] = []
    private var localRequestsByGUID: [TopologyGnutellaGUID: LocalRequestKind] = [:]
    private var localRequestOrder: [TopologyGnutellaGUID] = []
    private var searchResultsByGUID: [TopologyGnutellaGUID: [TopologyGnutellaSearchResult]] = [:]

    static func == (lhs: TopologyGnutellaPeerCore, rhs: TopologyGnutellaPeerCore) -> Bool {
        lhs.localPeer == rhs.localPeer
            && lhs.neighborCap == rhs.neighborCap
            && lhs.limits == rhs.limits
            && lhs.neighborsByID == rhs.neighborsByID
            && lhs.seenRequestGUIDs == rhs.seenRequestGUIDs
            && lhs.seenRequestOrder == rhs.seenRequestOrder
            && lhs.reverseRoutesByGUID == rhs.reverseRoutesByGUID
            && lhs.reverseRouteOrder == rhs.reverseRouteOrder
            && lhs.localRequestsByGUID == rhs.localRequestsByGUID
            && lhs.localRequestOrder == rhs.localRequestOrder
            && lhs.searchResultsByGUID == rhs.searchResultsByGUID
    }

    init(
        localPeer: TopologyGnutellaPeer,
        neighborCap: Int,
        guidGenerator: TopologyGnutellaGUIDGenerating,
        fileStore: TopologyGnutellaFileStore,
        limits: TopologyGnutellaLimits = .educationalDefault
    ) throws {
        guard neighborCap > 0, neighborCap <= limits.maximumNeighbors else {
            throw TopologyGnutellaError.invalidLimits("neighbor cap must be in 1...\(limits.maximumNeighbors)")
        }
        self.localPeer = localPeer
        self.neighborCap = neighborCap
        self.guidGenerator = guidGenerator
        self.fileStore = fileStore
        self.limits = limits
    }

    var neighbors: [TopologyGnutellaPeer] { neighborsByID.values.sorted() }
    var reverseRoutes: [TopologyGnutellaReverseRoute] {
        reverseRoutesByGUID.map { TopologyGnutellaReverseRoute(guid: $0.key, previousHop: $0.value) }
            .sorted { lhs, rhs in lhs.guid == rhs.guid ? lhs.previousHop < rhs.previousHop : lhs.guid < rhs.guid }
    }
    var seenGUIDs: [TopologyGnutellaGUID] { seenRequestGUIDs.sorted() }

    @discardableResult
    func addNeighbor(_ peer: TopologyGnutellaPeer) -> Bool {
        guard peer.id != localPeer.id else { return false }
        if neighborsByID[peer.id] != nil {
            neighborsByID[peer.id] = peer
            return false
        }
        guard neighborsByID.count < neighborCap else { return false }
        neighborsByID[peer.id] = peer
        return true
    }

    func removeNeighbor(peerID: String) { neighborsByID.removeValue(forKey: peerID) }
    func reverseRoute(for guid: TopologyGnutellaGUID) -> TopologyGnutellaPeer? { reverseRoutesByGUID[guid] }
    func searchResults(for guid: TopologyGnutellaGUID) -> [TopologyGnutellaSearchResult] { searchResultsByGUID[guid] ?? [] }

    func startDiscovery(bootstrap: TopologyGnutellaPeer, ttl: Int = TopologyGnutella.defaultTTL) throws -> TopologyGnutellaProcessingResult {
        try validateOriginTTL(ttl)
        guard bootstrap.id != localPeer.id else { throw TopologyGnutellaError.invalidPeerID(bootstrap.id) }
        let guid = try guidGenerator.nextGUID()
        let packet = TopologyGnutellaPacket(guid: guid, hops: 0, ttl: ttl, payload: .ping(origin: localPeer))
        _ = try TopologyGnutellaTextCodec.encode(packet, limits: limits)
        rememberSeen(guid)
        rememberLocalRequest(guid, kind: .discovery)
        return TopologyGnutellaProcessingResult(
            disposition: .originated,
            outbound: [TopologyGnutellaOutboundMessage(destination: bootstrap, packet: packet)],
            events: [.discoveryStarted(guid: guid, bootstrap: bootstrap)]
        )
    }

    func startQuery(
        searchTerm: String,
        minimumSpeedKbps: Int = 1,
        ttl: Int = TopologyGnutella.defaultTTL
    ) throws -> TopologyGnutellaProcessingResult {
        try validateOriginTTL(ttl)
        let guid = try guidGenerator.nextGUID()
        let packet = TopologyGnutellaPacket(
            guid: guid,
            hops: 0,
            ttl: ttl,
            payload: .query(minimumSpeedKbps: minimumSpeedKbps, searchTerm: searchTerm)
        )
        _ = try TopologyGnutellaTextCodec.encode(packet, limits: limits)
        rememberSeen(guid)
        rememberLocalRequest(guid, kind: .query)
        searchResultsByGUID[guid] = []
        return TopologyGnutellaProcessingResult(
            disposition: .originated,
            outbound: fanOut(packet, excludingPeerIDs: []),
            events: [.queryStarted(guid: guid, searchTerm: searchTerm)]
        )
    }

    func receiveEncoded(_ encoded: String, from sender: TopologyGnutellaPeer) throws -> TopologyGnutellaProcessingResult {
        try receive(TopologyGnutellaTextCodec.decode(encoded, limits: limits), from: sender)
    }

    func receive(_ packet: TopologyGnutellaPacket, from sender: TopologyGnutellaPeer) throws -> TopologyGnutellaProcessingResult {
        _ = try TopologyGnutellaTextCodec.encode(packet, limits: limits)
        switch packet.payload {
        case let .ping(origin): return try receivePing(packet, origin: origin, sender: sender)
        case let .pong(responder, _, _): return receivePong(packet, responder: responder, sender: sender)
        case let .query(_, searchTerm): return try receiveQuery(packet, searchTerm: searchTerm, sender: sender)
        case let .queryHit(responder, speedKbps, serventIdentifier, results):
            return receiveQueryHit(
                packet,
                responder: responder,
                speedKbps: speedKbps,
                serventIdentifier: serventIdentifier,
                results: results,
                sender: sender
            )
        }
    }

    private func receivePing(
        _ packet: TopologyGnutellaPacket,
        origin: TopologyGnutellaPeer,
        sender: TopologyGnutellaPeer
    ) throws -> TopologyGnutellaProcessingResult {
        if seenRequestGUIDs.contains(packet.guid) { return duplicateResult(guid: packet.guid) }
        rememberSeen(packet.guid)
        var events = acceptedRequestEvents(packet: packet, sender: sender)
        if origin.id != localPeer.id {
            if addNeighbor(origin) {
                events.append(.neighborAdded(origin))
            } else if neighborsByID[origin.id] == nil {
                events.append(.neighborRejectedAtCap(origin))
            }
        }
        let files = try stableMetadata(try fileStore.listPeerToPeerFiles())
        let totalBytes = try checkedTotalBytes(files)
        let pong = TopologyGnutellaPacket(
            guid: packet.guid,
            hops: 0,
            ttl: limits.responseTTL,
            payload: .pong(responder: localPeer, sharedFileCount: files.count, totalSharedBytes: totalBytes)
        )
        var outbound = [TopologyGnutellaOutboundMessage(destination: sender, packet: pong)]
        let forwarded = packet.forwarded(limits: limits)
        if let forwarded {
            outbound += fanOut(forwarded, excludingPeerIDs: [sender.id, origin.id])
        } else {
            events.append(.ttlBoundary(guid: packet.guid))
        }
        return TopologyGnutellaProcessingResult(
            disposition: forwarded == nil ? .ttlBoundaryReached : .acceptedRequest,
            outbound: outbound,
            events: events
        )
    }

    private func receiveQuery(
        _ packet: TopologyGnutellaPacket,
        searchTerm: String,
        sender: TopologyGnutellaPeer
    ) throws -> TopologyGnutellaProcessingResult {
        if seenRequestGUIDs.contains(packet.guid) { return duplicateResult(guid: packet.guid) }
        rememberSeen(packet.guid)
        var events = acceptedRequestEvents(packet: packet, sender: sender)
        let needle = searchTerm.lowercased()
        let matching = try stableMetadata(try fileStore.listPeerToPeerFiles()).filter {
            $0.name.lowercased().contains(needle)
        }
        guard matching.count <= limits.maximumQueryHitsPerPacket else {
            throw TopologyGnutellaError.quotaExceeded(
                name: "queryHitsPerPacket",
                actual: matching.count,
                limit: limits.maximumQueryHitsPerPacket
            )
        }
        events.append(.localMatches(guid: packet.guid, count: matching.count))
        var outbound: [TopologyGnutellaOutboundMessage] = []
        if !matching.isEmpty {
            let hit = TopologyGnutellaPacket(
                guid: packet.guid,
                hops: 0,
                ttl: limits.responseTTL,
                payload: .queryHit(
                    responder: localPeer,
                    speedKbps: 2,
                    serventIdentifier: localPeer.id,
                    results: matching
                )
            )
            outbound.append(TopologyGnutellaOutboundMessage(destination: sender, packet: hit))
        }
        let forwarded = packet.forwarded(limits: limits)
        if let forwarded {
            outbound += fanOut(forwarded, excludingPeerIDs: [sender.id])
        } else {
            events.append(.ttlBoundary(guid: packet.guid))
        }
        return TopologyGnutellaProcessingResult(
            disposition: forwarded == nil ? .ttlBoundaryReached : .acceptedRequest,
            outbound: outbound,
            events: events
        )
    }

    private func receivePong(
        _ packet: TopologyGnutellaPacket,
        responder: TopologyGnutellaPeer,
        sender: TopologyGnutellaPeer
    ) -> TopologyGnutellaProcessingResult {
        if localRequestsByGUID[packet.guid] == .discovery {
            var events: [TopologyGnutellaProcessingEvent] = []
            if addNeighbor(responder) {
                events.append(.neighborAdded(responder))
            } else if neighborsByID[responder.id] == nil {
                events.append(.neighborRejectedAtCap(responder))
            }
            return TopologyGnutellaProcessingResult(disposition: .responseDelivered, outbound: [], events: events)
        }
        return routeResponse(packet, sender: sender)
    }

    private func receiveQueryHit(
        _ packet: TopologyGnutellaPacket,
        responder: TopologyGnutellaPeer,
        speedKbps: Int,
        serventIdentifier: String,
        results: [TopologyGnutellaFileMetadata],
        sender: TopologyGnutellaPeer
    ) -> TopologyGnutellaProcessingResult {
        if localRequestsByGUID[packet.guid] == .query {
            var current = searchResultsByGUID[packet.guid] ?? []
            for file in stableMetadataWithoutThrowing(results) {
                let result = TopologyGnutellaSearchResult(
                    queryGUID: packet.guid,
                    peer: responder,
                    speedKbps: speedKbps,
                    serventIdentifier: serventIdentifier,
                    file: file
                )
                if !current.contains(result) { current.append(result) }
            }
            current.sort(by: topologyGnutellaSearchResultLessThan)
            if current.count > limits.maximumStoredResults {
                current = Array(current.prefix(limits.maximumStoredResults))
            }
            searchResultsByGUID[packet.guid] = current
            return TopologyGnutellaProcessingResult(
                disposition: .responseDelivered,
                outbound: [],
                events: [.searchResultsUpdated(guid: packet.guid, totalCount: current.count)]
            )
        }
        return routeResponse(packet, sender: sender)
    }

    private func routeResponse(
        _ packet: TopologyGnutellaPacket,
        sender: TopologyGnutellaPeer
    ) -> TopologyGnutellaProcessingResult {
        guard let previousHop = reverseRoutesByGUID[packet.guid], previousHop.id != sender.id else {
            return TopologyGnutellaProcessingResult(
                disposition: .orphanResponse,
                outbound: [],
                events: [.responseWithoutRoute(guid: packet.guid)]
            )
        }
        guard let forwarded = packet.forwarded(limits: limits) else {
            return TopologyGnutellaProcessingResult(
                disposition: .ttlBoundaryReached,
                outbound: [],
                events: [.ttlBoundary(guid: packet.guid)]
            )
        }
        return TopologyGnutellaProcessingResult(
            disposition: .responseRouted,
            outbound: [TopologyGnutellaOutboundMessage(destination: previousHop, packet: forwarded)],
            events: []
        )
    }

    private func acceptedRequestEvents(
        packet: TopologyGnutellaPacket,
        sender: TopologyGnutellaPeer
    ) -> [TopologyGnutellaProcessingEvent] {
        rememberReverseRoute(packet.guid, previousHop: sender)
        return [
            .requestAccepted(guid: packet.guid, descriptor: packet.descriptor),
            .reverseRouteStored(TopologyGnutellaReverseRoute(guid: packet.guid, previousHop: sender)),
        ]
    }

    private func duplicateResult(guid: TopologyGnutellaGUID) -> TopologyGnutellaProcessingResult {
        TopologyGnutellaProcessingResult(
            disposition: .duplicateSuppressed,
            outbound: [],
            events: [.duplicateRequestSuppressed(guid: guid)]
        )
    }

    private func fanOut(
        _ packet: TopologyGnutellaPacket,
        excludingPeerIDs: Set<String>
    ) -> [TopologyGnutellaOutboundMessage] {
        neighbors
            .filter { !excludingPeerIDs.contains($0.id) }
            .map { TopologyGnutellaOutboundMessage(destination: $0, packet: packet) }
    }

    private func validateOriginTTL(_ ttl: Int) throws {
        guard ttl > 0, ttl <= limits.maximumTTL else { throw TopologyGnutellaError.invalidTTL(ttl) }
    }

    private func rememberSeen(_ guid: TopologyGnutellaGUID) {
        guard seenRequestGUIDs.insert(guid).inserted else { return }
        seenRequestOrder.append(guid)
        while seenRequestOrder.count > limits.maximumSeenRequestGUIDs {
            let evicted = seenRequestOrder.removeFirst()
            seenRequestGUIDs.remove(evicted)
            reverseRoutesByGUID.removeValue(forKey: evicted)
            reverseRouteOrder.removeAll { $0 == evicted }
        }
    }

    private func rememberReverseRoute(_ guid: TopologyGnutellaGUID, previousHop: TopologyGnutellaPeer) {
        guard reverseRoutesByGUID[guid] == nil else { return }
        reverseRoutesByGUID[guid] = previousHop
        reverseRouteOrder.append(guid)
        while reverseRouteOrder.count > limits.maximumReverseRoutes {
            let evicted = reverseRouteOrder.removeFirst()
            reverseRoutesByGUID.removeValue(forKey: evicted)
        }
    }

    private func rememberLocalRequest(_ guid: TopologyGnutellaGUID, kind: LocalRequestKind) {
        localRequestsByGUID[guid] = kind
        localRequestOrder.append(guid)
        while localRequestOrder.count > limits.maximumLocalRequests {
            let evicted = localRequestOrder.removeFirst()
            localRequestsByGUID.removeValue(forKey: evicted)
            searchResultsByGUID.removeValue(forKey: evicted)
        }
    }

    private func stableMetadata(_ values: [TopologyGnutellaFileMetadata]) throws -> [TopologyGnutellaFileMetadata] {
        guard values.count <= limits.maximumSharedFiles else {
            throw TopologyGnutellaError.quotaExceeded(name: "sharedFiles", actual: values.count, limit: limits.maximumSharedFiles)
        }
        for value in values {
            _ = try TopologyGnutellaFileMetadata(
                name: value.name,
                sizeBytes: value.sizeBytes,
                mediaType: value.mediaType,
                limits: limits
            )
        }
        return stableMetadataWithoutThrowing(values)
    }

    private func checkedTotalBytes(_ values: [TopologyGnutellaFileMetadata]) throws -> Int {
        var total = 0
        for value in values {
            let (sum, overflow) = total.addingReportingOverflow(value.sizeBytes)
            guard !overflow else { throw TopologyGnutellaError.invalidFileSize(Int.max) }
            total = sum
        }
        return total
    }
}

enum TopologyGnutellaDirectStatus: Int {
    case ok = 200
    case notFound = 404
}

struct TopologyGnutellaDirectResponse: Equatable {
    let status: TopologyGnutellaDirectStatus
    let path: String
    let file: TopologyGnutellaFileResource?
}

enum TopologyGnutellaDirectTransfer {
    static func metadata(from store: TopologyGnutellaFileStore) throws -> [TopologyGnutellaFileMetadata] {
        stableMetadataWithoutThrowing(try store.listPeerToPeerFiles())
    }

    static func serve(
        path: String,
        from store: TopologyGnutellaFileStore,
        limits: TopologyGnutellaLimits = .educationalDefault
    ) throws -> TopologyGnutellaDirectResponse {
        let name = try fileName(fromDirectPath: path, limits: limits)
        guard let file = try store.readPeerToPeerFile(named: name) else {
            return TopologyGnutellaDirectResponse(status: .notFound, path: path, file: nil)
        }
        guard file.data.count <= limits.maximumDirectFileBytes else {
            throw TopologyGnutellaError.invalidFileSize(file.data.count)
        }
        return TopologyGnutellaDirectResponse(status: .ok, path: path, file: file)
    }

    @discardableResult
    static func install(
        _ response: TopologyGnutellaDirectResponse,
        into store: TopologyGnutellaFileStore
    ) throws -> TopologyGnutellaFileMetadata {
        guard response.status == .ok else {
            throw TopologyGnutellaError.directTransferStatus(response.status.rawValue)
        }
        guard let file = response.file else { throw TopologyGnutellaError.missingDirectTransferBody }
        try store.writeDownloadedPeerToPeerFile(file, overwrite: true)
        return file.metadata
    }

    static func path(
        forFileName name: String,
        limits: TopologyGnutellaLimits = .educationalDefault
    ) throws -> String {
        try topologyGnutellaValidateFileName(name, limits: limits)
        return "\(TopologyGnutella.peerToPeerDirectory)/\(name)"
    }

    private static func fileName(
        fromDirectPath path: String,
        limits: TopologyGnutellaLimits
    ) throws -> String {
        let prefix = TopologyGnutella.peerToPeerDirectory + "/"
        guard path.hasPrefix(prefix) else { throw TopologyGnutellaError.invalidDirectPath(path) }
        let name = String(path.dropFirst(prefix.count))
        do {
            try topologyGnutellaValidateFileName(name, limits: limits)
        } catch {
            throw TopologyGnutellaError.invalidDirectPath(path)
        }
        return name
    }
}

/// Value-box adapter for the existing virtual filesystem. Store `snapshot()` back into editor state after writes.
final class TopologyGnutellaVirtualFileSystemAdapter: TopologyGnutellaFileStore, Equatable {
    private var fileSystem: TopologyVirtualFileSystem
    private let limits: TopologyGnutellaLimits

    static func == (
        lhs: TopologyGnutellaVirtualFileSystemAdapter,
        rhs: TopologyGnutellaVirtualFileSystemAdapter
    ) -> Bool {
        lhs.fileSystem == rhs.fileSystem && lhs.limits == rhs.limits
    }

    init(
        fileSystem: TopologyVirtualFileSystem,
        limits: TopologyGnutellaLimits = .educationalDefault
    ) throws {
        var candidate = fileSystem
        if !candidate.contains(TopologyGnutella.peerToPeerDirectory) {
            try candidate.createDirectory(at: TopologyGnutella.peerToPeerDirectory, recursive: true)
        }
        let directory = try candidate.entry(at: TopologyGnutella.peerToPeerDirectory)
        guard directory.content.isDirectory else {
            throw TopologyVirtualFileSystemError.expectedDirectory(directory.path)
        }
        self.fileSystem = candidate
        self.limits = limits
    }

    func snapshot() -> TopologyVirtualFileSystem { fileSystem }

    func replaceSnapshot(_ snapshot: TopologyVirtualFileSystem) throws {
        var candidate = snapshot
        if !candidate.contains(TopologyGnutella.peerToPeerDirectory) {
            try candidate.createDirectory(at: TopologyGnutella.peerToPeerDirectory, recursive: true)
        }
        let directory = try candidate.entry(at: TopologyGnutella.peerToPeerDirectory)
        guard directory.content.isDirectory else {
            throw TopologyVirtualFileSystemError.expectedDirectory(directory.path)
        }
        fileSystem = candidate
    }

    func listPeerToPeerFiles() throws -> [TopologyGnutellaFileMetadata] {
        try fileSystem.entries(in: TopologyGnutella.peerToPeerDirectory)
            .filter { $0.content.isFile && !$0.name.hasPrefix(".") }
            .map { entry in
                try TopologyGnutellaFileMetadata(
                    name: entry.name,
                    sizeBytes: entry.content.byteCount,
                    mediaType: mediaType(for: entry.content),
                    limits: limits
                )
            }
            .sorted(by: topologyGnutellaMetadataLessThan)
    }

    func readPeerToPeerFile(named name: String) throws -> TopologyGnutellaFileResource? {
        try topologyGnutellaValidateFileName(name, limits: limits)
        let path = "\(TopologyGnutella.peerToPeerDirectory)/\(name)"
        guard fileSystem.contains(path) else { return nil }
        let entry = try fileSystem.entry(at: path)
        guard entry.content.isFile else { return nil }
        let data: Data
        switch entry.content {
        case .directory: return nil
        case let .text(value): data = Data(value.utf8)
        case let .binary(value, _), let .image(value, _): data = value
        }
        let metadata = try TopologyGnutellaFileMetadata(
            name: entry.name,
            sizeBytes: data.count,
            mediaType: mediaType(for: entry.content),
            limits: limits
        )
        return try TopologyGnutellaFileResource(metadata: metadata, data: data, limits: limits)
    }

    func writeDownloadedPeerToPeerFile(_ file: TopologyGnutellaFileResource, overwrite: Bool) throws {
        let path = try TopologyGnutellaDirectTransfer.path(forFileName: file.metadata.name, limits: limits)
        let mediaType = file.metadata.mediaType.lowercased()
        if mediaType.hasPrefix("image/") {
            try fileSystem.writeImageFile(
                at: path,
                data: file.data,
                mediaType: file.metadata.mediaType,
                overwrite: overwrite
            )
        } else if mediaType.hasPrefix("text/"), let text = String(data: file.data, encoding: .utf8) {
            try fileSystem.writeTextFile(at: path, text: text, overwrite: overwrite)
        } else {
            try fileSystem.writeBinaryFile(
                at: path,
                data: file.data,
                mediaType: file.metadata.mediaType,
                overwrite: overwrite
            )
        }
    }

    private func mediaType(for content: TopologyVirtualFileContent) -> String {
        switch content {
        case .directory: return "application/x-directory"
        case .text: return "text/plain; charset=utf-8"
        case let .binary(_, mediaType): return mediaType ?? "application/octet-stream"
        case let .image(_, mediaType): return mediaType
        }
    }
}

private func topologyGnutellaValidateFileName(
    _ name: String,
    limits: TopologyGnutellaLimits
) throws {
    let bytes = name.lengthOfBytes(using: .utf8)
    let hasControl = name.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    guard !name.isEmpty,
          name != ".",
          name != "..",
          !name.contains("/"),
          !name.contains("\\"),
          bytes <= limits.maximumFileNameBytes,
          !hasControl
    else {
        throw TopologyGnutellaError.invalidFileName(name)
    }
}

private func topologyGnutellaMetadataLessThan(
    _ lhs: TopologyGnutellaFileMetadata,
    _ rhs: TopologyGnutellaFileMetadata
) -> Bool {
    let lhsFolded = lhs.name.lowercased()
    let rhsFolded = rhs.name.lowercased()
    if lhsFolded != rhsFolded { return lhsFolded < rhsFolded }
    if lhs.name != rhs.name { return lhs.name < rhs.name }
    if lhs.sizeBytes != rhs.sizeBytes { return lhs.sizeBytes < rhs.sizeBytes }
    return lhs.mediaType < rhs.mediaType
}

private func stableMetadataWithoutThrowing(
    _ values: [TopologyGnutellaFileMetadata]
) -> [TopologyGnutellaFileMetadata] {
    values.sorted(by: topologyGnutellaMetadataLessThan)
}

private func topologyGnutellaSearchResultLessThan(
    _ lhs: TopologyGnutellaSearchResult,
    _ rhs: TopologyGnutellaSearchResult
) -> Bool {
    if lhs.file != rhs.file { return topologyGnutellaMetadataLessThan(lhs.file, rhs.file) }
    if lhs.peer != rhs.peer { return lhs.peer < rhs.peer }
    if lhs.speedKbps != rhs.speedKbps { return lhs.speedKbps < rhs.speedKbps }
    return lhs.serventIdentifier < rhs.serventIdentifier
}
