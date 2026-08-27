import Foundation
import Network

struct TopologyRemoteLinkLANEndpointConfiguration: Equatable, Sendable {
    let nodeID: UUID
    let endpointName: String
    let linkCode: String
    let role: TopologyRemoteLinkLANRole
    let listenPort: UInt16
    let joinMethod: TopologyRemoteLinkLANJoinMethod
    let remoteHost: String
    let remotePort: UInt16

    var linkDigest: String {
        TopologyRemoteLinkWireCodec.digest(for: linkCode)
    }
}

enum TopologyRemoteLinkLANBonjourSelection {
    static func matchingEndpoint(
        in endpoints: [NWEndpoint],
        servicePrefix: String
    ) -> NWEndpoint? {
        endpoints
            .sorted { String(describing: $0) < String(describing: $1) }
            .first { endpoint in
                guard case let .service(name, _, _, _) = endpoint else { return false }
                return name.lowercased().hasPrefix(servicePrefix.lowercased())
            }
    }
}

@MainActor
final class TopologyRemoteLinkLANController: ObservableObject {
    var onConnectionStateChange: ((UUID, TopologyRemoteLinkLANConnectionState) -> Void)?
    var onFrameReceived: (@MainActor (UUID, TopologyRemoteLinkWireFrame) async -> Bool)?

    private var sessionsByNodeID: [UUID: TopologyRemoteLinkLANSession] = [:]
    private let handshakeTimeoutSeconds: TimeInterval
    private let acknowledgementTimeoutSeconds: TimeInterval

    init(
        handshakeTimeoutSeconds: TimeInterval = 8,
        acknowledgementTimeoutSeconds: TimeInterval = 15
    ) {
        self.handshakeTimeoutSeconds = max(0.1, handshakeTimeoutSeconds)
        self.acknowledgementTimeoutSeconds = max(0.1, acknowledgementTimeoutSeconds)
    }

    func reconcile(endpoints: [TopologyRemoteLinkLANEndpointConfiguration]) {
        let desiredByNodeID = Dictionary(uniqueKeysWithValues: endpoints.map { ($0.nodeID, $0) })
        for nodeID in sessionsByNodeID.keys where desiredByNodeID[nodeID] == nil {
            sessionsByNodeID.removeValue(forKey: nodeID)?.stop()
            onConnectionStateChange?(nodeID, .inactive)
        }
        for endpoint in endpoints {
            if let existing = sessionsByNodeID[endpoint.nodeID], existing.configuration == endpoint {
                continue
            }
            sessionsByNodeID.removeValue(forKey: endpoint.nodeID)?.stop()
            let generation = UUID()
            let session = TopologyRemoteLinkLANSession(
                configuration: endpoint,
                generation: generation,
                handshakeTimeoutSeconds: handshakeTimeoutSeconds,
                acknowledgementTimeoutSeconds: acknowledgementTimeoutSeconds,
                stateHandler: { [weak self] nodeID, generation, state in
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.sessionsByNodeID[nodeID]?.generation == generation else { return }
                        self.onConnectionStateChange?(nodeID, state)
                    }
                },
                frameHandler: { [weak self] nodeID, generation, frame, completion in
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.sessionsByNodeID[nodeID]?.generation == generation,
                              let onFrameReceived = self.onFrameReceived
                        else {
                            completion(false)
                            return
                        }
                        let accepted = await onFrameReceived(nodeID, frame)
                        guard self.sessionsByNodeID[nodeID]?.generation == generation else {
                            completion(false)
                            return
                        }
                        completion(accepted)
                    }
                }
            )
            sessionsByNodeID[endpoint.nodeID] = session
            session.start()
        }
    }

    func send(
        _ frame: TopologyRemoteLinkWireFrame,
        from nodeID: UUID,
        completion: @escaping (TopologyRemoteLinkLANSendResult) -> Void
    ) {
        guard let session = sessionsByNodeID[nodeID] else {
            Task { @MainActor in completion(.failed(.sessionUnavailable)) }
            return
        }
        session.send(frame) { result in
            Task { @MainActor in completion(result) }
        }
    }

    func reconnect(nodeID: UUID) {
        sessionsByNodeID[nodeID]?.restart()
    }

    func stopAll() {
        let sessions = sessionsByNodeID
        sessionsByNodeID.removeAll()
        for (nodeID, session) in sessions {
            session.stop()
            onConnectionStateChange?(nodeID, .inactive)
        }
    }
}

// Session state is confined to `queue`; callbacks cross executors only through Sendable values.
private final class TopologyRemoteLinkLANSession: @unchecked Sendable {
    static let serviceType = "_filiuslink._tcp"
    static let maximumQueuedFrames = 256

    let configuration: TopologyRemoteLinkLANEndpointConfiguration
    let generation: UUID

    private let queue: DispatchQueue
    private let handshakeCodec: TopologyRemoteLinkWireCodec
    private let endpointID = UUID()
    private let handshakeTimeoutSeconds: TimeInterval
    private let acknowledgementTimeoutSeconds: TimeInterval
    private let stateHandler: @Sendable (UUID, UUID, TopologyRemoteLinkLANConnectionState) -> Void
    private let frameHandler: @Sendable (
        UUID,
        UUID,
        TopologyRemoteLinkWireFrame,
        @escaping @Sendable (Bool) -> Void
    ) -> Void
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var cachedBonjourEndpoints: [NWEndpoint] = []
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var localHandshake: TopologyRemoteLinkWireHandshake?
    private var remoteHandshake: TopologyRemoteLinkWireHandshake?
    private var sessionCodec: TopologyRemoteLinkWireSessionCodec?
    private var didSendSessionReady = false
    private var didValidateHandshake = false
    private var stopped = true
    private var reconnectAttempt = 0
    private var reconnectWorkItem: DispatchWorkItem?
    private var handshakeTimeoutWorkItem: DispatchWorkItem?
    private var pendingSends: [PendingSend] = []
    private var inFlightSends: [UUID: PendingSend] = [:]
    private var sendIDByWireSequence: [UInt64: UUID] = [:]
    private var acknowledgementTimeoutsBySendID: [UUID: DispatchWorkItem] = [:]

    private struct PendingSend {
        let id: UUID
        let frame: TopologyRemoteLinkWireFrame
        let completion: @Sendable (TopologyRemoteLinkLANSendResult) -> Void
    }

    init(
        configuration: TopologyRemoteLinkLANEndpointConfiguration,
        generation: UUID,
        handshakeTimeoutSeconds: TimeInterval,
        acknowledgementTimeoutSeconds: TimeInterval,
        stateHandler: @escaping @Sendable (UUID, UUID, TopologyRemoteLinkLANConnectionState) -> Void,
        frameHandler: @escaping @Sendable (
            UUID,
            UUID,
            TopologyRemoteLinkWireFrame,
            @escaping @Sendable (Bool) -> Void
        ) -> Void
    ) {
        self.configuration = configuration
        self.generation = generation
        handshakeCodec = TopologyRemoteLinkWireCodec(linkCode: configuration.linkCode)
        self.handshakeTimeoutSeconds = handshakeTimeoutSeconds
        self.acknowledgementTimeoutSeconds = acknowledgementTimeoutSeconds
        queue = DispatchQueue(label: "com.filius.pad.remote-link.\(configuration.nodeID.uuidString)")
        self.stateHandler = stateHandler
        self.frameHandler = frameHandler
    }

    func start() {
        queue.async { [weak self] in self?.startOnQueue() }
    }

    func restart() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopOnQueue(reportInactive: false)
            self.startOnQueue()
        }
    }

    func stop() {
        queue.async { self.stopOnQueue(reportInactive: true) }
    }

    func send(
        _ frame: TopologyRemoteLinkWireFrame,
        completion: @escaping @Sendable (TopologyRemoteLinkLANSendResult) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else {
                completion(.failed(.sessionStopped))
                return
            }
            guard !self.stopped else {
                completion(.failed(.sessionStopped))
                return
            }
            let admittedFrameCount = self.pendingSends.count + self.inFlightSends.count
            guard admittedFrameCount < Self.maximumQueuedFrames else {
                completion(.failed(.controllerQueueFull(limit: Self.maximumQueuedFrames)))
                return
            }
            self.pendingSends.append(PendingSend(id: UUID(), frame: frame, completion: completion))
            self.flushPendingSendsIfReady()
        }
    }

    private func startOnQueue() {
        guard stopped else { return }
        stopped = false
        reconnectAttempt = 0
        switch configuration.role {
        case .host:
            startListener()
        case .join:
            startJoiner()
        }
    }

    private func stopOnQueue(reportInactive: Bool) {
        guard !stopped
                || listener != nil
                || browser != nil
                || connection != nil
                || !pendingSends.isEmpty
                || !inFlightSends.isEmpty
        else { return }
        if didValidateHandshake { sendSessionControl(.disconnect) }
        stopped = true
        failPendingSends(.sessionStopped)
        failInFlightSends(.sessionStopped)
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        handshakeTimeoutWorkItem?.cancel()
        handshakeTimeoutWorkItem = nil
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
        cachedBonjourEndpoints.removeAll(keepingCapacity: false)
        detachConnection()
        if reportInactive { report(.inactive) }
    }

    private func makeParameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 3
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        parameters.serviceClass = .responsiveData
        return parameters
    }

    private func startListener() {
        do {
            guard let port = NWEndpoint.Port(rawValue: configuration.listenPort) else {
                report(.failed(message: "Invalid listening port"))
                return
            }
            let listener = try NWListener(using: makeParameters(), on: port)
            listener.service = NWListener.Service(name: serviceName, type: Self.serviceType)
            listener.stateUpdateHandler = { [weak self] state in
                self?.queue.async { self?.handleListenerState(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.queue.async { self?.accept(connection) }
            }
            self.listener = listener
            report(.listening)
            listener.start(queue: queue)
        } catch {
            report(.failed(message: error.localizedDescription))
            scheduleReconnect()
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        guard !stopped else { return }
        switch state {
        case .ready:
            reconnectAttempt = 0
            report(connection == nil ? .listening : .connecting)
        case let .failed(error):
            report(.failed(message: error.localizedDescription))
            listener = nil
            scheduleReconnect()
        case .cancelled:
            if !stopped {
                listener = nil
                report(.failed(message: "Listener stopped"))
                scheduleReconnect()
            }
        default:
            break
        }
    }

    private func accept(_ candidate: NWConnection) {
        guard !stopped else {
            candidate.cancel()
            return
        }
        guard connection == nil else {
            candidate.cancel()
            return
        }
        attach(candidate)
    }

    private func startJoiner() {
        switch configuration.joinMethod {
        case .bonjour:
            startBrowser()
        case .manual:
            connectManually()
        }
    }

    private func startBrowser() {
        cachedBonjourEndpoints.removeAll(keepingCapacity: false)
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: makeParameters())
        browser.stateUpdateHandler = { [weak self] state in
            self?.queue.async { self?.handleBrowserState(state) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.queue.async { self?.handleBrowseResults(results) }
        }
        self.browser = browser
        report(.browsing)
        browser.start(queue: queue)
    }

    private func handleBrowserState(_ state: NWBrowser.State) {
        guard !stopped else { return }
        switch state {
        case .ready:
            if connection == nil {
                connectToCachedBonjourResult()
            }
        case let .failed(error):
            report(.failed(message: error.localizedDescription))
            browser = nil
            cachedBonjourEndpoints.removeAll(keepingCapacity: false)
            scheduleReconnect()
        case .cancelled:
            if !stopped {
                browser = nil
                cachedBonjourEndpoints.removeAll(keepingCapacity: false)
                report(.reconnecting)
                scheduleReconnect()
            }
        default:
            break
        }
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        cachedBonjourEndpoints = results.map(\.endpoint)
        connectToCachedBonjourResult()
    }

    private func connectToCachedBonjourResult() {
        guard !stopped, connection == nil else { return }
        guard let matching = TopologyRemoteLinkLANBonjourSelection.matchingEndpoint(
            in: cachedBonjourEndpoints,
            servicePrefix: servicePrefix
        ) else {
            report(.browsing)
            return
        }
        attach(NWConnection(to: matching, using: makeParameters()))
    }

    private func connectManually() {
        let host = configuration.remoteHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, let port = NWEndpoint.Port(rawValue: configuration.remotePort) else {
            report(.failed(message: "A valid host and port are required"))
            return
        }
        attach(NWConnection(host: NWEndpoint.Host(host), port: port, using: makeParameters()))
    }

    private func attach(_ newConnection: NWConnection) {
        guard !stopped, connection == nil else {
            newConnection.cancel()
            return
        }
        connection = newConnection
        resetHandshakeState()
        localHandshake = TopologyRemoteLinkWireHandshake(
            protocolVersion: TopologyRemoteLinkWireCodec.protocolVersion,
            linkDigest: configuration.linkDigest,
            endpointID: endpointID,
            endpointName: configuration.endpointName
        )
        report(.connecting)
        newConnection.stateUpdateHandler = { [weak self, weak newConnection] state in
            guard let newConnection else { return }
            self?.queue.async { self?.handleConnectionState(state, connection: newConnection) }
        }
        scheduleHandshakeTimeout(for: newConnection)
        newConnection.start(queue: queue)
    }

    private func handleConnectionState(_ state: NWConnection.State, connection candidate: NWConnection) {
        guard connection === candidate, !stopped else { return }
        switch state {
        case .ready:
            reconnectAttempt = 0
            sendHello()
            receiveMore()
        case let .failed(error):
            handleConnectionEnded(message: error.localizedDescription)
        case .cancelled:
            handleConnectionEnded(message: "Connection closed")
        case .waiting:
            report(.connecting)
        default:
            break
        }
    }

    private func scheduleHandshakeTimeout(for candidate: NWConnection) {
        handshakeTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak candidate] in
            guard let self, let candidate,
                  self.connection === candidate,
                  !self.didValidateHandshake,
                  !self.stopped else { return }
            self.report(.failed(message: "LAN remote-link handshake timed out"))
            self.handleConnectionEnded(message: "Handshake timed out")
        }
        handshakeTimeoutWorkItem = workItem
        queue.asyncAfter(deadline: .now() + handshakeTimeoutSeconds, execute: workItem)
    }

    private func sendHello() {
        guard let localHandshake else {
            handleConnectionEnded(message: "Missing local handshake state")
            return
        }
        sendHandshakeMessage(.hello(localHandshake))
    }

    private func flushPendingSendsIfReady() {
        guard didValidateHandshake, connection != nil, !stopped, !pendingSends.isEmpty else { return }
        let sends = pendingSends
        pendingSends.removeAll(keepingCapacity: true)
        for pending in sends {
            sendFrame(pending)
        }
    }

    private func sendFrame(_ pending: PendingSend) {
        guard let connection, didValidateHandshake, !stopped else {
            pending.completion(.failed(.sessionStopped))
            return
        }
        do {
            let encoded = try encodeSessionRecord(.frame(pending.frame))
            let framed = Self.frame(record: encoded.record)
            inFlightSends[pending.id] = pending
            sendIDByWireSequence[encoded.sequence] = pending.id
            scheduleAcknowledgementTimeout(for: pending.id, sequence: encoded.sequence, connection: connection)
            connection.send(content: framed, completion: .contentProcessed { [weak self, weak connection] error in
                guard let self else { return }
                self.queue.async {
                    guard let connection,
                          self.connection === connection,
                          self.inFlightSends[pending.id] != nil,
                          let error else { return }
                    self.completeInFlightSend(
                        id: pending.id,
                        result: .failed(.transportFailed(
                            message: error.localizedDescription,
                            attempts: 1
                        ))
                    )
                    self.handleConnectionSendFailure(error, connection: connection)
                }
            })
        } catch {
            pending.completion(.failed(.encodingFailed(message: error.localizedDescription)))
        }
    }

    private func scheduleAcknowledgementTimeout(
        for sendID: UUID,
        sequence: UInt64,
        connection candidate: NWConnection
    ) {
        let workItem = DispatchWorkItem { [weak self, weak candidate] in
            guard let self, let candidate,
                  self.connection === candidate,
                  self.sendIDByWireSequence[sequence] == sendID else { return }
            self.completeInFlightSend(
                id: sendID,
                result: .failed(.transportFailed(
                    message: "Peer acknowledgement timed out",
                    attempts: 1
                ))
            )
            self.handleConnectionEnded(message: "Peer acknowledgement timed out")
        }
        acknowledgementTimeoutsBySendID[sendID] = workItem
        queue.asyncAfter(deadline: .now() + acknowledgementTimeoutSeconds, execute: workItem)
    }

    private func completeInFlightSend(id: UUID, result: TopologyRemoteLinkLANSendResult) {
        guard let pending = inFlightSends.removeValue(forKey: id) else { return }
        acknowledgementTimeoutsBySendID.removeValue(forKey: id)?.cancel()
        if let sequence = sendIDByWireSequence.first(where: { $0.value == id })?.key {
            sendIDByWireSequence.removeValue(forKey: sequence)
        }
        pending.completion(result)
    }

    private func failPendingSends(_ failure: TopologyRemoteLinkLANSendFailure) {
        let sends = pendingSends
        pendingSends.removeAll(keepingCapacity: false)
        for pending in sends { pending.completion(.failed(failure)) }
    }

    private func failInFlightSends(_ failure: TopologyRemoteLinkLANSendFailure) {
        let sendIDs = Array(inFlightSends.keys)
        for sendID in sendIDs {
            completeInFlightSend(id: sendID, result: .failed(failure))
        }
    }

    private static func frame(record: Data) -> Data {
        var length = UInt32(record.count).bigEndian
        var framed = withUnsafeBytes(of: &length) { Data($0) }
        framed.append(record)
        return framed
    }

    private func sendHandshakeMessage(_ message: TopologyRemoteLinkWireMessage) {
        guard let connection else { return }
        do {
            let framed = Self.frame(record: try handshakeCodec.encode(message))
            connection.send(content: framed, completion: .contentProcessed { [weak self, weak connection] error in
                guard let self, let connection, let error else { return }
                self.queue.async { self.handleConnectionSendFailure(error, connection: connection) }
            })
        } catch {
            handleConnectionEnded(message: error.localizedDescription)
        }
    }

    private func sendSessionControl(_ message: TopologyRemoteLinkWireMessage) {
        guard let connection else { return }
        do {
            let framed = Self.frame(record: try encodeSessionRecord(message).record)
            connection.send(content: framed, completion: .contentProcessed { [weak self, weak connection] error in
                guard let self, let connection, let error else { return }
                self.queue.async { self.handleConnectionSendFailure(error, connection: connection) }
            })
        } catch {
            handleConnectionEnded(message: error.localizedDescription)
        }
    }

    private func encodeSessionRecord(
        _ message: TopologyRemoteLinkWireMessage
    ) throws -> TopologyRemoteLinkWireEncodedSessionRecord {
        guard var codec = sessionCodec else {
            throw TopologyRemoteLinkWireCodecError.invalidSession
        }
        let encoded = try codec.encode(message)
        sessionCodec = codec
        return encoded
    }

    private func decodeSessionRecord(_ record: Data) throws -> TopologyRemoteLinkWireDecodedSessionRecord {
        guard var codec = sessionCodec else {
            throw TopologyRemoteLinkWireCodecError.invalidSession
        }
        let decoded = try codec.decode(record)
        sessionCodec = codec
        return decoded
    }

    private func handleConnectionSendFailure(_ error: NWError, connection candidate: NWConnection) {
        guard connection === candidate else { return }
        handleConnectionEnded(message: error.localizedDescription)
    }

    private func receiveMore() {
        guard let connection, !stopped else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            self.queue.async {
                guard self.connection === connection, !self.stopped else { return }
                if let data { self.receiveBuffer.append(data) }
                do {
                    try self.processReceiveBuffer()
                } catch {
                    self.handleConnectionEnded(message: error.localizedDescription)
                    return
                }
                if let error {
                    self.handleConnectionEnded(message: error.localizedDescription)
                } else if isComplete {
                    self.handleConnectionEnded(message: "Peer disconnected")
                } else {
                    self.receiveMore()
                }
            }
        }
    }

    private func processReceiveBuffer() throws {
        while receiveBuffer.count >= 4 {
            let length = receiveBuffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length > 0, length <= UInt32(TopologyRemoteLinkWireCodec.maximumRecordBytes) else {
                throw TopologyRemoteLinkWireCodecError.recordTooLarge
            }
            let totalLength = 4 + Int(length)
            guard receiveBuffer.count >= totalLength else { return }
            let record = receiveBuffer.subdata(in: 4..<totalLength)
            receiveBuffer.removeSubrange(0..<totalLength)
            if sessionCodec == nil {
                try handleHandshakeMessage(handshakeCodec.decode(record))
            } else {
                let decoded = try decodeSessionRecord(record)
                try handleSessionMessage(decoded.message, sequence: decoded.sequence)
            }
        }
    }

    private func handleHandshakeMessage(_ message: TopologyRemoteLinkWireMessage) throws {
        guard case let .hello(handshake) = message,
              remoteHandshake == nil,
              let localHandshake else {
            throw TopologyRemoteLinkWireCodecError.invalidHandshake
        }
        guard handshake.protocolVersion == TopologyRemoteLinkWireCodec.protocolVersion else {
            throw TopologyRemoteLinkWireCodecError.unsupportedVersion(handshake.protocolVersion)
        }
        guard handshake.linkDigest == configuration.linkDigest else {
            throw TopologyRemoteLinkWireCodecError.authenticationFailed
        }
        sessionCodec = try handshakeCodec.makeSessionCodec(
            localHandshake: localHandshake,
            remoteHandshake: handshake
        )
        remoteHandshake = handshake
        didSendSessionReady = true
        sendSessionControl(.sessionReady)
    }

    private func handleSessionMessage(
        _ message: TopologyRemoteLinkWireMessage,
        sequence: UInt64
    ) throws {
        switch message {
        case .sessionReady:
            guard didSendSessionReady, !didValidateHandshake, let remoteHandshake else {
                throw TopologyRemoteLinkWireCodecError.invalidHandshake
            }
            didValidateHandshake = true
            handshakeTimeoutWorkItem?.cancel()
            handshakeTimeoutWorkItem = nil
            report(.connected(peerName: remoteHandshake.endpointName))
            flushPendingSendsIfReady()
        case let .frame(frame):
            guard didValidateHandshake,
                  let receivingConnection = connection
            else { throw TopologyRemoteLinkWireCodecError.authenticationFailed }
            frameHandler(configuration.nodeID, generation, frame) { [weak self, weak receivingConnection] accepted in
                guard let self else { return }
                self.queue.async {
                    guard accepted,
                          let receivingConnection,
                          self.connection === receivingConnection,
                          self.didValidateHandshake,
                          !self.stopped
                    else { return }
                    self.sendSessionControl(.acknowledgement(sequence))
                }
            }
        case let .acknowledgement(acknowledgedSequence):
            guard didValidateHandshake,
                  let sendID = sendIDByWireSequence[acknowledgedSequence] else {
                throw TopologyRemoteLinkWireCodecError.unexpectedSequence(
                    expected: sendIDByWireSequence.keys.min() ?? acknowledgedSequence,
                    received: acknowledgedSequence
                )
            }
            completeInFlightSend(id: sendID, result: .accepted(attempts: 1))
        case .keepAlive:
            guard didValidateHandshake else { throw TopologyRemoteLinkWireCodecError.authenticationFailed }
        case .disconnect:
            guard didValidateHandshake else { throw TopologyRemoteLinkWireCodecError.authenticationFailed }
            handleConnectionEnded(message: "Peer disconnected")
        case .hello:
            throw TopologyRemoteLinkWireCodecError.invalidHandshake
        }
    }

    private func handleConnectionEnded(message: String) {
        guard connection != nil else { return }
        handshakeTimeoutWorkItem?.cancel()
        handshakeTimeoutWorkItem = nil
        if !inFlightSends.isEmpty {
            failInFlightSends(stopped ? .sessionStopped : .transportFailed(message: message, attempts: 1))
        }
        detachConnection()
        guard !stopped else { return }
        switch configuration.role {
        case .host:
            report(.listening)
        case .join:
            report(.reconnecting)
            scheduleReconnect()
        }
    }

    private func detachConnection() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        resetHandshakeState()
    }

    private func resetHandshakeState() {
        receiveBuffer.removeAll(keepingCapacity: true)
        localHandshake = nil
        remoteHandshake = nil
        sessionCodec = nil
        didSendSessionReady = false
        didValidateHandshake = false
    }

    private func scheduleReconnect() {
        guard !stopped else { return }
        reconnectWorkItem?.cancel()
        reconnectAttempt = min(reconnectAttempt + 1, 5)
        let delay = min(pow(2.0, Double(reconnectAttempt - 1)), 15.0)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped, self.connection == nil else { return }
            switch self.configuration.role {
            case .host:
                if self.listener == nil { self.startListener() }
            case .join:
                if self.configuration.joinMethod == .manual {
                    self.connectManually()
                } else if self.browser == nil {
                    self.startBrowser()
                } else {
                    self.connectToCachedBonjourResult()
                }
            }
        }
        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func report(_ state: TopologyRemoteLinkLANConnectionState) {
        stateHandler(configuration.nodeID, generation, state)
    }

    private var servicePrefix: String {
        "Filius-\(configuration.linkDigest.prefix(12))"
    }

    private var serviceName: String {
        let sanitizedName = configuration.endpointName
            .replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression)
        return String("\(servicePrefix)-\(sanitizedName)".prefix(63))
    }
}
