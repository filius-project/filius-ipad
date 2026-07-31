import Foundation

enum TopologyRuntimeTransportProtocol: String, Codable, CaseIterable, Equatable, Hashable {
    case tcp
    case udp

    var displayName: String { rawValue.uppercased() }
}

enum TopologyRuntimeSimpleClientConnectionState: String, Codable, Equatable {
    case disconnected
    case connecting
    case connected
    case failed
}

struct TopologyRuntimeSimpleClientLogEntry: Equatable, Codable, Identifiable {
    let id: UInt64
    let timestampMilliseconds: UInt64
    let direction: String
    let message: String
}

struct TopologyRuntimeSimpleClientState: Equatable {
    var protocolKind: TopologyRuntimeTransportProtocol = .tcp
    var destinationIPAddress = ""
    var destinationPort: Int = 0
    var socketID: UUID?
    var connectionState: TopologyRuntimeSimpleClientConnectionState = .disconnected
    var nextLogID: UInt64 = 1
    var logs: [TopologyRuntimeSimpleClientLogEntry] = []

    mutating func appendLog(timestampMilliseconds: UInt64, direction: String, message: String) {
        let entry = TopologyRuntimeSimpleClientLogEntry(
            id: nextLogID,
            timestampMilliseconds: timestampMilliseconds,
            direction: direction,
            message: message
        )
        nextLogID = nextLogID == UInt64.max ? UInt64.max : nextLogID + 1
        logs.append(entry)
        if logs.count > 100 {
            logs.removeFirst(logs.count - 100)
        }
    }
}

struct TopologyRuntimeEchoServerServiceState: Equatable {
    var acceptedTCPSocketIDs: Set<UUID> = []
    var datagramsReceived = 0
    var payloadsEchoed = 0
    var lastPayload = ""

    var tcpSessionsAccepted: Int { acceptedTCPSocketIDs.count }
}

struct TopologyRuntimeSimpleClientSendResult: Equatable {
    let succeeded: Bool
    let response: Data?
    let failureCode: String?
}

extension TopologyNetworkRuntimeEngine {
    static let simpleClientUDPReceiveTimeoutMilliseconds: UInt64 = 5_000

    mutating func acceptedTCPSocketIDs(listenerSocketID: UUID) -> [UUID] {
        state.tcpAcceptedSocketIDsByListenerID[listenerSocketID, default: []]
            .filter { state.socketsByID[$0]?.tcpState != .closed }
            .sorted { $0.uuidString < $1.uuidString }
    }

    @discardableResult
    mutating func closeTCPConnectionAndClean(socketID: UUID) -> Set<UUID> {
        guard state.socketsByID[socketID]?.protocolKind == .tcp else { return [] }

        var endpointIDs = [socketID]
        if let peerSocketID = peerTCPSocketID(socketID: socketID) {
            endpointIDs.append(peerSocketID)
        }

        for endpointID in endpointIDs {
            closeTCPSocket(socketID: endpointID)
        }

        while state.phase == .running {
            for endpointID in endpointIDs where state.socketsByID[endpointID]?.tcpState == .closeWait {
                closeTCPSocket(socketID: endpointID)
            }

            let unsettledSocketIDs = Set(endpointIDs.filter {
                guard let tcpState = state.socketsByID[$0]?.tcpState else { return false }
                return tcpState != .closed
            })
            guard !unsettledSocketIDs.isEmpty else { break }

            let nextDeadline = state.pendingEvents.compactMap { event -> UInt64? in
                guard case let .tcpTimeout(sessionID) = event.kind,
                      unsettledSocketIDs.contains(sessionID) else { return nil }
                return event.deadlineMilliseconds
            }.min()
            guard let nextDeadline else { break }
            _ = handle(.advance(toMilliseconds: nextDeadline))
        }

        let closedSocketIDs = Set(endpointIDs.filter { state.socketsByID[$0]?.tcpState == .closed })
        for endpointID in closedSocketIDs {
            _ = cleanClosedTCPSocket(socketID: endpointID)
        }
        return closedSocketIDs
    }

    mutating func simpleClientSend(
        socketID: UUID,
        protocolKind: TopologyRuntimeTransportProtocol,
        payload: Data
    ) -> TopologyRuntimeSimpleClientSendResult {
        switch protocolKind {
        case .tcp:
            guard state.socketsByID[socketID]?.tcpState == .established else {
                return TopologyRuntimeSimpleClientSendResult(succeeded: false, response: nil, failureCode: "notConnected")
            }
            guard sendTCP(socketID: socketID, payload: payload) else {
                return TopologyRuntimeSimpleClientSendResult(succeeded: false, response: nil, failureCode: "sendFailed")
            }
            return TopologyRuntimeSimpleClientSendResult(
                succeeded: true,
                response: receiveTCP(socketID: socketID),
                failureCode: nil
            )
        case .udp:
            guard let result = sendUDP(socketID: socketID, payload: payload) else {
                return TopologyRuntimeSimpleClientSendResult(succeeded: false, response: nil, failureCode: "unreachable")
            }
            switch result {
            case .delivered:
                return TopologyRuntimeSimpleClientSendResult(
                    succeeded: true,
                    response: nil,
                    failureCode: nil
                )
            case .icmpError:
                return TopologyRuntimeSimpleClientSendResult(succeeded: false, response: nil, failureCode: "unreachable")
            case .dropped:
                return TopologyRuntimeSimpleClientSendResult(succeeded: false, response: nil, failureCode: "dropped")
            }
        }
    }
}



extension TopologyEditorState {
    mutating func pumpEchoServer(nodeID: UUID) -> TopologyRuntimeEchoServerServiceState {
        var serviceState = runtimeEchoServerServiceStateByNodeID[nodeID] ?? TopologyRuntimeEchoServerServiceState()
        if let listenerID = runtimeEchoServerSocketIDByNodeID[nodeID] {
            for acceptedID in networkRuntime.acceptedTCPSocketIDs(listenerSocketID: listenerID) {
                serviceState.acceptedTCPSocketIDs.insert(acceptedID)
                while let payload = networkRuntime.receiveTCP(socketID: acceptedID) {
                    serviceState.payloadsEchoed += 1
                    serviceState.lastPayload = String(data: payload, encoding: .utf8) ?? "<binary \(payload.count) bytes>"
                    _ = networkRuntime.sendTCP(socketID: acceptedID, payload: payload)
                }
            }
        }
        if let udpSocketID = runtimeEchoServerUDPSocketIDByNodeID[nodeID] {
            while let received = networkRuntime.receiveUDP(socketID: udpSocketID) {
                serviceState.datagramsReceived += 1
                serviceState.payloadsEchoed += 1
                serviceState.lastPayload = String(data: received.datagram.payload, encoding: .utf8)
                    ?? "<binary \(received.datagram.payload.count) bytes>"
                _ = networkRuntime.sendUDP(
                    socketID: udpSocketID,
                    payload: received.datagram.payload,
                    destinationIPAddress: received.senderIPAddress,
                    destinationPort: received.datagram.sourcePort
                )
            }
        }
        runtimeEchoServerServiceStateByNodeID[nodeID] = serviceState
        return serviceState
    }
}

// MARK: - Deterministic HTTP over the simulated TCP runtime

struct TopologyRuntimeWebServerConfiguration: Codable, Equatable {
    static let defaultPort = 80
    static let defaultDocumentRoot = "/www"

    var port: Int = Self.defaultPort
    var documentRoot: String = Self.defaultDocumentRoot

    init(port: Int = Self.defaultPort, documentRoot: String = Self.defaultDocumentRoot) {
        self.port = port
        self.documentRoot = documentRoot
    }
}

struct TopologyRuntimeWebBrowserConfiguration: Codable, Equatable {
    var lastHost = ""
    var lastPort = 80
    var lastPath = "/"
}

struct TopologyRuntimeWebServerRequestLogEntry: Codable, Equatable, Identifiable {
    let id: UInt64
    let timestampMilliseconds: UInt64
    let remoteIPAddress: String
    let method: String
    let path: String
    let statusCode: Int
    let contentType: String?
    let detail: String

    var idValue: UInt64 { id }
}

struct TopologyRuntimeWebBrowserHistoryEntry: Equatable {
    let address: String
    let statusCode: Int?
    let title: String?
}

enum TopologyRuntimeWebBrowserConnectionState: String, Equatable {
    case idle
    case loading
    case loaded
    case failed
}

struct TopologyRuntimeWebBrowserState: Equatable {
    var connectionState: TopologyRuntimeWebBrowserConnectionState = .idle
    var address = ""
    var resolvedIPAddress = ""
    var statusCode: Int?
    var contentType: String?
    var body = ""
    var bodyData = Data()
    var errorMessage: String?
    var history: [TopologyRuntimeWebBrowserHistoryEntry] = []
    var historyIndex: Int?
    var nextHistoryID: UInt64 = 1

    var shouldRenderBodyAsHTML: Bool {
        !body.isEmpty && contentType?.lowercased().hasPrefix("text/html") == true
    }

    mutating func resetTransientSession() {
        connectionState = .idle
        address = ""
        resolvedIPAddress = ""
        statusCode = nil
        contentType = nil
        body = ""
        bodyData = Data()
        errorMessage = nil
        history.removeAll()
        historyIndex = nil
        nextHistoryID = 1
    }
}

struct TopologyRuntimeHTTPParsedRequest: Equatable {
    let method: String
    let target: String
    let path: String
    let host: String?
    let body: Data
}

struct TopologyRuntimeHTTPResponse: Equatable {
    let statusCode: Int
    let contentType: String?
    let body: Data
    let detail: String
}

struct TopologyRuntimeHTTPAddress: Equatable {
    let host: String
    let port: UInt16
    let path: String
    let displayAddress: String
}

enum TopologyRuntimeHTTPError: Error, Equatable, LocalizedError {
    case invalidURL(String)
    case invalidPort(String)
    case unsupportedScheme(String)
    case missingHost
    case invalidHost(String)
    case malformedRequest(String)
    case dnsFailure(String)
    case timeout(String)
    case unreachable(String)
    case serverNotRunning(String)
    case responseMissing

    var errorDescription: String? {
        switch self {
        case let .invalidURL(value): return "Invalid URL: \(value)"
        case let .invalidPort(value): return "Invalid port: \(value)"
        case let .unsupportedScheme(value): return "Unsupported URL scheme: \(value)"
        case .missingHost: return "A hostname or IP address is required."
        case let .invalidHost(value): return "Invalid hostname or IP address: \(value)"
        case let .malformedRequest(value): return "Malformed HTTP request: \(value)"
        case let .dnsFailure(value): return "DNS lookup failed: \(value)"
        case let .timeout(value): return "TCP connection timed out: \(value)"
        case let .unreachable(value): return "TCP destination is unreachable: \(value)"
        case let .serverNotRunning(value): return "HTTP server is not running: \(value)"
        case .responseMissing: return "The HTTP server returned no response."
        }
    }
}

private enum TopologyRuntimeHTTPWire {
    static func request(method: String, host: String, path: String, body: Data = Data()) -> Data {
        let text = "\(method) \(path) HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\nContent-Length: \(body.count)\r\n\r\n"
        var data = Data(text.utf8)
        data.append(body)
        return data
    }

    static func response(_ response: TopologyRuntimeHTTPResponse) -> Data {
        let reason = reasonPhrase(response.statusCode)
        let contentType = response.contentType ?? "text/plain"
        let header = "HTTP/1.1 \(response.statusCode) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(response.body)
        return data
    }

    static func reasonPhrase(_ statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        default: return "HTTP Error"
        }
    }

    static func parseRequest(_ data: Data) -> Result<TopologyRuntimeHTTPParsedRequest, TopologyRuntimeHTTPError> {
        guard let raw = String(data: data, encoding: .utf8) else {
            return .failure(.malformedRequest("request is not UTF-8"))
        }
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let pieces = normalized.components(separatedBy: "\n\n")
        let headerLines = pieces.first?.components(separatedBy: "\n") ?? []
        guard let startLine = headerLines.first else {
            return .failure(.malformedRequest("empty request"))
        }
        let tokens = startLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count == 3, tokens[2].hasPrefix("HTTP/1.") else {
            return .failure(.malformedRequest("invalid request line"))
        }
        let target = tokens[1]
        guard target.hasPrefix("/") else {
            return .failure(.malformedRequest("request target must be an absolute path"))
        }
        let headers = headerLines.dropFirst().reduce(into: [String: String]()) { result, line in
            let fields = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2 else { return }
            result[String(fields[0]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] =
                String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let bodyText = pieces.dropFirst().joined(separator: "\n\n")
        let body = Data(bodyText.utf8)
        let rawPath = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "/"
        guard let decodedPath = rawPath.removingPercentEncoding else {
            return .failure(.malformedRequest("invalid percent escape"))
        }
        guard decodedPath.hasPrefix("/"),
              !decodedPath.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else {
            return .failure(.malformedRequest("invalid path"))
        }
        return .success(
            TopologyRuntimeHTTPParsedRequest(
                method: tokens[0].uppercased(),
                target: target,
                path: decodedPath,
                host: headers["host"],
                body: body
            )
        )
    }
}

extension TopologyRuntimeHTTPAddress {
    static func parse(_ rawValue: String, fallback: TopologyRuntimeWebBrowserConfiguration?) -> Result<TopologyRuntimeHTTPAddress, TopologyRuntimeHTTPError> {
        let raw = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) else {
            return .failure(.invalidURL(rawValue))
        }

        let candidate: String
        if raw.hasPrefix("/") {
            guard let fallback, !fallback.lastHost.isEmpty else { return .failure(.missingHost) }
            candidate = "http://\(fallback.lastHost):\(fallback.lastPort)\(raw)"
        } else if raw.contains("://") {
            candidate = raw
        } else if raw.contains("/") || raw.contains(":") {
            candidate = "http://\(raw)"
        } else {
            candidate = "http://\(raw)/"
        }

        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(), scheme == "http"
        else {
            let scheme = URLComponents(string: candidate)?.scheme ?? ""
            return .failure(scheme.isEmpty ? .invalidURL(rawValue) : .unsupportedScheme(scheme))
        }
        guard let host = components.host?.lowercased(), !host.isEmpty else { return .failure(.missingHost) }
        guard isValidHost(host) else { return .failure(.invalidHost(host)) }
        let port = components.port ?? fallback?.lastPort ?? 80
        guard (1...65_535).contains(port), let portValue = UInt16(exactly: port) else {
            return .failure(.invalidPort(String(port)))
        }
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        guard let decodedPath = path.removingPercentEncoding,
              decodedPath.hasPrefix("/"),
              !decodedPath.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else {
            return .failure(.invalidURL(rawValue))
        }
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        let display = "http://\(host):\(portValue)\(path)\(query)"
        return .success(TopologyRuntimeHTTPAddress(host: host, port: portValue, path: path + query, displayAddress: display))
    }

    private static func isValidHost(_ host: String) -> Bool {
        if TopologyRuntimeDNSHostsFile.isValidIPv4Address(host) { return true }
        guard host.count <= 253, !host.hasPrefix("."), !host.hasSuffix("."), !host.contains("..") else { return false }
        return host.split(separator: ".").allSatisfy { label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" &&
                label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}

extension TopologyRuntimeHTTPResponse {
    static func serve(
        request: TopologyRuntimeHTTPParsedRequest,
        fileSystem: TopologyVirtualFileSystem,
        configuration: TopologyRuntimeWebServerConfiguration
    ) -> TopologyRuntimeHTTPResponse {
        guard request.method == "GET" || request.method == "HEAD" else {
            return TopologyRuntimeHTTPResponse(statusCode: 405, contentType: "text/plain", body: Data("Method Not Allowed\n".utf8), detail: "method=\(request.method)")
        }
        guard let safePath = safeDocumentPath(request.path, configuration: configuration) else {
            return TopologyRuntimeHTTPResponse(statusCode: 400, contentType: "text/plain", body: Data("Bad Request\n".utf8), detail: "unsafePath")
        }
        let entry: TopologyVirtualFileEntry
        do {
            entry = try fileSystem.entry(at: safePath)
        } catch let error as TopologyVirtualFileSystemError {
            if case .itemNotFound = error {
                return TopologyRuntimeHTTPResponse(statusCode: 404, contentType: "text/plain", body: Data("Not Found\n".utf8), detail: "path=\(safePath)")
            }
            return TopologyRuntimeHTTPResponse(statusCode: 500, contentType: "text/plain", body: Data("Internal Server Error\n".utf8), detail: "vfs=\(error.localizedDescription)")
        } catch {
            return TopologyRuntimeHTTPResponse(statusCode: 500, contentType: "text/plain", body: Data("Internal Server Error\n".utf8), detail: "vfs=\(error.localizedDescription)")
        }
        guard entry.content.isFile else {
            return TopologyRuntimeHTTPResponse(statusCode: 500, contentType: "text/plain", body: Data("Internal Server Error\n".utf8), detail: "directoryDocument")
        }
        let content: Data
        let mediaType: String
        switch entry.content {
        case let .text(text):
            content = Data(text.utf8)
            mediaType = mimeType(for: entry.path, fallback: "text/plain")
        case let .binary(data, declaredType):
            content = data
            mediaType = mimeType(for: entry.path, fallback: declaredType ?? "application/octet-stream")
        case let .image(data, declaredType):
            content = data
            mediaType = declaredType
        case .directory:
            return TopologyRuntimeHTTPResponse(statusCode: 500, contentType: "text/plain", body: Data("Internal Server Error\n".utf8), detail: "directoryDocument")
        }
        return TopologyRuntimeHTTPResponse(
            statusCode: 200,
            contentType: mediaType,
            body: request.method == "HEAD" ? Data() : content,
            detail: "path=\(safePath),bytes=\(content.count)"
        )
    }

    private static func safeDocumentPath(_ rawPath: String, configuration: TopologyRuntimeWebServerConfiguration) -> String? {
        guard rawPath.hasPrefix("/"),
              !rawPath.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        let pathPart = rawPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "/"
        let components = pathPart.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.contains(where: { $0 == "." || $0 == ".." || $0.contains("\\") }) else { return nil }
        let relative = components.joined(separator: "/")
        let root = configuration.documentRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedRoot = try? TopologyVirtualFileSystem.normalizedAbsolutePath(root),
              !normalizedRoot.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return nil }
        let requested = relative.isEmpty ? "index.html" : relative
        return normalizedRoot == "/" ? "/\(requested)" : "\(normalizedRoot)/\(requested)"
    }

    private static func mimeType(for path: String, fallback: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "js": return "text/javascript"
        case "txt", "log", "csv", "json", "xml": return "text/plain"
        case "png": return "image/png"
        case "bmp": return "image/bmp"
        case "gif": return "image/gif"
        case "jpg", "jpeg": return "image/jpeg"
        default: return fallback
        }
    }
}

extension TopologyRuntimeHTTPResponse {
    var renderedBody: String {
        guard contentType?.lowercased().hasPrefix("text/html") == true else {
            return String(data: body, encoding: .utf8) ?? "[binary \(body.count) bytes]"
        }
        var value = String(data: body, encoding: .utf8) ?? ""
        value = value.replacingOccurrences(of: "(?is)<script.*?</script>", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?is)<style.*?</style>", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?i)</(p|div|h[1-6]|li|br|tr)>", with: "\n", options: .regularExpression)
        value = value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return value
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension TopologyNetworkRuntimeEngine {
    func tcpSocketRecord(socketID: UUID) -> TopologyRuntimeSocketRecord? {
        state.socketsByID[socketID]
    }
}

extension TopologyRuntimeHTTPWire {
    static func parseResponse(_ data: Data) -> Result<(statusCode: Int, contentType: String?, body: Data), TopologyRuntimeHTTPError> {
        guard let rawHeaderEnd = data.range(of: Data([13, 10, 13, 10])) else {
            return .failure(.malformedRequest("HTTP response has no header terminator"))
        }
        let headerData = data.subdata(in: data.startIndex..<rawHeaderEnd.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return .failure(.malformedRequest("HTTP response headers are not UTF-8"))
        }
        let lines = headerText.components(separatedBy: "\r\n")
        let statusTokens = lines.first?.split(separator: " ", maxSplits: 2).map(String.init) ?? []
        guard statusTokens.count >= 2, statusTokens[0].hasPrefix("HTTP/1."), let statusCode = Int(statusTokens[1]) else {
            return .failure(.malformedRequest("invalid HTTP response status line"))
        }
        var contentType: String?
        for line in lines.dropFirst() {
            let fields = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2 else { continue }
            if fields[0].lowercased() == "content-type" { contentType = String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        let bodyStart = rawHeaderEnd.upperBound
        return .success((statusCode, contentType, data.subdata(in: bodyStart..<data.endIndex)))
    }
}

extension TopologyEditorState {
    mutating func resetTransientHTTPRuntime() {
        runtimeWebServerRequestLogsByNodeID.removeAll()
        runtimeWebBrowserStateByNodeID.removeAll()
    }

    mutating func appendWebServerLog(
        nodeID: UUID,
        remoteIPAddress: String,
        method: String,
        path: String,
        response: TopologyRuntimeHTTPResponse
    ) {
        let nextID = (runtimeWebServerRequestLogsByNodeID[nodeID]?.map(\.id).max() ?? 0) + 1
        let entry = TopologyRuntimeWebServerRequestLogEntry(
            id: nextID,
            timestampMilliseconds: networkRuntime.state.currentTimeMilliseconds,
            remoteIPAddress: remoteIPAddress,
            method: method,
            path: path,
            statusCode: response.statusCode,
            contentType: response.contentType,
            detail: response.detail
        )
        runtimeWebServerRequestLogsByNodeID[nodeID, default: []].append(entry)
        if runtimeWebServerRequestLogsByNodeID[nodeID, default: []].count > 100 {
            runtimeWebServerRequestLogsByNodeID[nodeID]?.removeFirst()
        }
    }

    mutating func processWebServerRequests(nodeID: UUID) -> Int {
        guard let listenerID = runtimeWebServerSocketIDByNodeID[nodeID],
              let configuration = runtimeWebServerConfigurationsByNodeID[nodeID] else { return 0 }
        let accepted = networkRuntime.acceptedTCPSocketIDs(listenerSocketID: listenerID)
        var processed = 0
        for acceptedID in accepted {
            guard let requestData = networkRuntime.receiveTCP(socketID: acceptedID) else { continue }
            let remoteSocketID = networkRuntime.peerTCPSocketID(socketID: acceptedID)
            let remoteIPAddress = remoteSocketID.flatMap { networkRuntime.tcpSocketRecord(socketID: $0)?.localIPAddress } ?? "unknown"
            networkRuntime.recordTrace(
                nodeID: nodeID,
                interfaceID: networkRuntime.networkInterfaces(nodeID: nodeID).first?.portID,
                direction: .local,
                layer: .application,
                operation: .received,
                afterHeaders: [
                    TopologyPacketHeaderField(name: "kind", value: "HTTP"),
                    TopologyPacketHeaderField(name: "lifecycle", value: "requestReceived"),
                    TopologyPacketHeaderField(name: "payloadLength", value: String(requestData.count)),
                ],
                detail: "HTTP request accepted on TCP socket \(acceptedID.uuidString)"
            )
            let response: TopologyRuntimeHTTPResponse
            switch TopologyRuntimeHTTPWire.parseRequest(requestData) {
            case let .failure(error):
                response = TopologyRuntimeHTTPResponse(statusCode: 400, contentType: "text/plain", body: Data("Bad Request\n".utf8), detail: error.localizedDescription)
                appendWebServerLog(nodeID: nodeID, remoteIPAddress: remoteIPAddress, method: "?", path: "?", response: response)
            case let .success(request):
                response = TopologyRuntimeHTTPResponse.serve(
                    request: request,
                    fileSystem: virtualFileSystemsByNodeID[nodeID] ?? .defaultForDevice(),
                    configuration: configuration
                )
                appendWebServerLog(nodeID: nodeID, remoteIPAddress: remoteIPAddress, method: request.method, path: request.path, response: response)
            }
            let responseData = TopologyRuntimeHTTPWire.response(response)
            networkRuntime.recordTrace(
                nodeID: nodeID,
                interfaceID: networkRuntime.networkInterfaces(nodeID: nodeID).first?.portID,
                direction: .outbound,
                layer: .application,
                operation: .created,
                afterHeaders: [
                    TopologyPacketHeaderField(name: "kind", value: "HTTP"),
                    TopologyPacketHeaderField(name: "statusCode", value: String(response.statusCode)),
                    TopologyPacketHeaderField(name: "contentType", value: response.contentType ?? ""),
                    TopologyPacketHeaderField(name: "lifecycle", value: "responseCreated"),
                    TopologyPacketHeaderField(name: "payloadLength", value: String(responseData.count)),
                ],
                detail: "HTTP response \(response.statusCode)"
            )
            if networkRuntime.sendTCP(socketID: acceptedID, payload: responseData) {
                networkRuntime.recordTrace(
                    nodeID: nodeID,
                    interfaceID: networkRuntime.networkInterfaces(nodeID: nodeID).first?.portID,
                    direction: .outbound,
                    layer: .application,
                    operation: .sent,
                    afterHeaders: [
                        TopologyPacketHeaderField(name: "kind", value: "HTTP"),
                        TopologyPacketHeaderField(name: "statusCode", value: String(response.statusCode)),
                        TopologyPacketHeaderField(name: "lifecycle", value: "responseSent"),
                    ],
                    detail: "HTTP response sent over TCP"
                )
                processed += 1
                networkRuntime.closeTCPSocket(socketID: acceptedID)
            }
        }
        return processed
    }

    mutating func navigateWebBrowser(
        nodeID: UUID,
        rawAddress: String,
        historyIndex targetHistoryIndex: Int? = nil
    ) -> Result<TopologyRuntimeWebBrowserState, TopologyRuntimeHTTPError> {
        var browserState = runtimeWebBrowserStateByNodeID[nodeID] ?? TopologyRuntimeWebBrowserState()
        browserState.connectionState = .loading
        browserState.address = rawAddress
        browserState.resolvedIPAddress = ""
        browserState.statusCode = nil
        browserState.contentType = nil
        browserState.body = ""
        browserState.bodyData = Data()
        browserState.errorMessage = nil
        runtimeWebBrowserStateByNodeID[nodeID] = browserState
        let browserConfiguration = runtimeWebBrowserConfigurationsByNodeID[nodeID]
        let address: TopologyRuntimeHTTPAddress
        switch TopologyRuntimeHTTPAddress.parse(rawAddress, fallback: browserConfiguration) {
        case let .failure(error):
            browserState.connectionState = .failed
            browserState.errorMessage = error.localizedDescription
            browserState.statusCode = nil
            browserState.body = ""
            runtimeWebBrowserStateByNodeID[nodeID] = browserState
            return .failure(error)
        case let .success(parsed):
            address = parsed
        }

        let destinationIPAddress: String
        if TopologyRuntimeDNSHostsFile.isValidIPv4Address(address.host) {
            destinationIPAddress = address.host
        } else {
            switch resolveRuntimeHostname(nodeID: nodeID, hostname: address.host) {
            case let .success(record, _, _): destinationIPAddress = record.targetIPAddress
            case let .nxdomain(_, server, _):
                let error = TopologyRuntimeHTTPError.dnsFailure("NXDOMAIN from \(server)")
                browserState.connectionState = .failed
                browserState.errorMessage = error.localizedDescription
                runtimeWebBrowserStateByNodeID[nodeID] = browserState
                return .failure(error)
            case let .unreachable(server):
                let error = TopologyRuntimeHTTPError.dnsFailure("DNS server \(server) unreachable")
                browserState.connectionState = .failed
                browserState.errorMessage = error.localizedDescription
                runtimeWebBrowserStateByNodeID[nodeID] = browserState
                return .failure(error)
            case let .timeout(server):
                let error = TopologyRuntimeHTTPError.timeout("DNS server \(server)")
                browserState.connectionState = .failed
                browserState.errorMessage = error.localizedDescription
                runtimeWebBrowserStateByNodeID[nodeID] = browserState
                return .failure(error)
            case .missingServerConfiguration:
                let error = TopologyRuntimeHTTPError.dnsFailure("no DNS server configured")
                browserState.connectionState = .failed
                browserState.errorMessage = error.localizedDescription
                runtimeWebBrowserStateByNodeID[nodeID] = browserState
                return .failure(error)
            case .simulationStopped:
                let error = TopologyRuntimeHTTPError.unreachable("simulation stopped")
                browserState.connectionState = .failed
                browserState.errorMessage = error.localizedDescription
                runtimeWebBrowserStateByNodeID[nodeID] = browserState
                return .failure(error)
            }
        }

        guard let socketID = networkRuntime.openTCPClientSocket(
            nodeID: nodeID,
            remoteIPAddress: destinationIPAddress,
            remotePort: address.port
        ) else {
            let error = TopologyRuntimeHTTPError.unreachable("cannot allocate TCP socket")
            browserState.connectionState = .failed
            browserState.errorMessage = error.localizedDescription
            runtimeWebBrowserStateByNodeID[nodeID] = browserState
            return .failure(error)
        }
        let connectionResult = networkRuntime.connectTCPWithResult(socketID: socketID)
        guard connectionResult == .connected else {
            let error: TopologyRuntimeHTTPError
            switch connectionResult {
            case .timedOut:
                error = .timeout("\(destinationIPAddress):\(address.port)")
            case .unreachable, .invalidSocket:
                error = .unreachable("\(destinationIPAddress):\(address.port)")
            case .connected:
                error = .unreachable("unexpected connected result for \(destinationIPAddress):\(address.port)")
            }
            _ = networkRuntime.closeTCPConnectionAndClean(socketID: socketID)
            browserState.connectionState = .failed
            browserState.errorMessage = error.localizedDescription
            browserState.resolvedIPAddress = destinationIPAddress
            runtimeWebBrowserStateByNodeID[nodeID] = browserState
            return .failure(error)
        }
        let requestData = TopologyRuntimeHTTPWire.request(method: "GET", host: address.host, path: address.path)
        networkRuntime.recordTrace(
            nodeID: nodeID,
            interfaceID: networkRuntime.networkInterfaces(nodeID: nodeID).first?.portID,
            direction: .outbound,
            layer: .application,
            operation: .created,
            afterHeaders: [
                TopologyPacketHeaderField(name: "kind", value: "HTTP"),
                TopologyPacketHeaderField(name: "method", value: "GET"),
                TopologyPacketHeaderField(name: "path", value: address.path),
                TopologyPacketHeaderField(name: "lifecycle", value: "requestCreated"),
            ],
            detail: "HTTP GET \(address.displayAddress)"
        )
        guard networkRuntime.sendTCP(socketID: socketID, payload: requestData) else {
            _ = networkRuntime.closeTCPConnectionAndClean(socketID: socketID)
            let error = TopologyRuntimeHTTPError.timeout("request delivery")
            browserState.connectionState = .failed
            browserState.errorMessage = error.localizedDescription
            runtimeWebBrowserStateByNodeID[nodeID] = browserState
            return .failure(error)
        }
        networkRuntime.recordTrace(
            nodeID: nodeID,
            interfaceID: networkRuntime.networkInterfaces(nodeID: nodeID).first?.portID,
            direction: .outbound,
            layer: .application,
            operation: .sent,
            afterHeaders: [
                TopologyPacketHeaderField(name: "kind", value: "HTTP"),
                TopologyPacketHeaderField(name: "method", value: "GET"),
                TopologyPacketHeaderField(name: "lifecycle", value: "requestSent"),
            ],
            detail: "HTTP request sent over TCP"
        )
        for serverNodeID in runtimeWebServerByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            _ = processWebServerRequests(nodeID: serverNodeID)
        }
        guard let responseData = networkRuntime.receiveTCP(socketID: socketID) else {
            _ = networkRuntime.closeTCPConnectionAndClean(socketID: socketID)
            let error = TopologyRuntimeHTTPError.responseMissing
            browserState.connectionState = .failed
            browserState.errorMessage = error.localizedDescription
            runtimeWebBrowserStateByNodeID[nodeID] = browserState
            return .failure(error)
        }
        networkRuntime.recordTrace(
            nodeID: nodeID,
            interfaceID: networkRuntime.networkInterfaces(nodeID: nodeID).first?.portID,
            direction: .inbound,
            layer: .application,
            operation: .received,
            afterHeaders: [
                TopologyPacketHeaderField(name: "kind", value: "HTTP"),
                TopologyPacketHeaderField(name: "lifecycle", value: "responseReceived"),
                TopologyPacketHeaderField(name: "payloadLength", value: String(responseData.count)),
            ],
            detail: "HTTP response received over TCP"
        )
        let parsedResponse: (statusCode: Int, contentType: String?, body: Data)
        switch TopologyRuntimeHTTPWire.parseResponse(responseData) {
        case let .failure(error):
            _ = networkRuntime.closeTCPConnectionAndClean(socketID: socketID)
            browserState.connectionState = .failed
            browserState.errorMessage = error.localizedDescription
            runtimeWebBrowserStateByNodeID[nodeID] = browserState
            return .failure(error)
        case let .success(value): parsedResponse = value
        }
        _ = networkRuntime.closeTCPConnectionAndClean(socketID: socketID)
        browserState.connectionState = .loaded
        browserState.address = address.displayAddress
        browserState.resolvedIPAddress = destinationIPAddress
        browserState.statusCode = parsedResponse.statusCode
        browserState.contentType = parsedResponse.contentType
        browserState.bodyData = parsedResponse.body
        browserState.body = TopologyRuntimeHTTPResponse(
            statusCode: parsedResponse.statusCode,
            contentType: parsedResponse.contentType,
            body: parsedResponse.body,
            detail: "browser"
        ).renderedBody
        browserState.errorMessage = parsedResponse.statusCode == 200 ? nil : "HTTP \(parsedResponse.statusCode) \(TopologyRuntimeHTTPWire.reasonPhrase(parsedResponse.statusCode))"
        runtimeWebBrowserConfigurationsByNodeID[nodeID] = TopologyRuntimeWebBrowserConfiguration(
            lastHost: address.host,
            lastPort: Int(address.port),
            lastPath: address.path
        )
        if let targetHistoryIndex {
            guard browserState.history.indices.contains(targetHistoryIndex) else {
                let error = TopologyRuntimeHTTPError.invalidURL("history index \(targetHistoryIndex)")
                browserState.connectionState = .failed
                browserState.errorMessage = error.localizedDescription
                runtimeWebBrowserStateByNodeID[nodeID] = browserState
                return .failure(error)
            }
            browserState.historyIndex = targetHistoryIndex
            browserState.history[targetHistoryIndex] = TopologyRuntimeWebBrowserHistoryEntry(
                address: address.displayAddress,
                statusCode: parsedResponse.statusCode,
                title: nil
            )
        } else {
            if browserState.historyIndex.map({ $0 + 1 < browserState.history.count }) == true {
                browserState.history.removeLast(browserState.history.count - (browserState.historyIndex! + 1))
            }
            browserState.history.append(TopologyRuntimeWebBrowserHistoryEntry(address: address.displayAddress, statusCode: parsedResponse.statusCode, title: nil))
            browserState.historyIndex = browserState.history.count - 1
        }
        runtimeWebBrowserStateByNodeID[nodeID] = browserState
        return .success(browserState)
    }
}
