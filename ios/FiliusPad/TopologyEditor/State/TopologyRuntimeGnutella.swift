import Foundation

enum TopologyRuntimeGnutellaStorage {
    static let nativeConfigurationPath = "/peer2peer/.filiuspad-gnutella.json"
}

struct TopologyRuntimeGnutellaConfiguration: Codable, Equatable {
    static let javaMinimumKnownPeers = 1
    static let javaDefaultMaximumKnownPeers = 3
    static let maximumKnownPeers = 32

    var maximumKnownPeers: Int

    var effectiveMaximumKnownPeers: Int {
        min(max(maximumKnownPeers, Self.javaMinimumKnownPeers), Self.maximumKnownPeers)
    }

    init(maximumKnownPeers: Int = javaDefaultMaximumKnownPeers) {
        self.maximumKnownPeers = maximumKnownPeers
    }

    func validate() throws {
        guard (Self.javaMinimumKnownPeers ... Self.maximumKnownPeers).contains(maximumKnownPeers) else {
            throw TopologyRuntimeGnutellaOperationError.invalidConfiguration(
                "Maximum known peers must be in \(Self.javaMinimumKnownPeers)...\(Self.maximumKnownPeers)."
            )
        }
    }
}

struct TopologyRuntimeGnutellaLogEntry: Equatable, Identifiable {
    let id: UInt64
    let timestampMilliseconds: UInt64
    let direction: String
    let message: String
}

struct TopologyRuntimeGnutellaSessionState: Equatable {
    var isRunning = false
    var listenerSocketID: UUID?
    var knownPeers: [TopologyGnutellaPeer] = []
    var searchResults: [TopologyGnutellaSearchResult] = []
    var activeQueryGUID: TopologyGnutellaGUID?
    var lastError: String?
    var nextLogID: UInt64 = 1
    var logs: [TopologyRuntimeGnutellaLogEntry] = []

    mutating func appendLog(timestampMilliseconds: UInt64, direction: String, message: String) {
        logs.append(
            TopologyRuntimeGnutellaLogEntry(
                id: nextLogID,
                timestampMilliseconds: timestampMilliseconds,
                direction: direction,
                message: message
            )
        )
        nextLogID &+= 1
        if logs.count > 200 {
            logs.removeFirst(logs.count - 200)
        }
    }
}

enum TopologyRuntimeGnutellaOperationError: Error, Equatable, LocalizedError {
    case simulationStopped
    case programNotInstalled
    case invalidConfiguration(String)
    case missingIPAddress
    case portInUse(Int)
    case serviceNotRunning(String)
    case unreachable(String)
    case timedOut(String)
    case protocolFailure(String)
    case resultNotFound
    case transferFailed(Int)

    var errorDescription: String? {
        switch self {
        case .simulationStopped: return "Simulation is stopped."
        case .programNotInstalled: return "Gnutella is not installed on this device."
        case let .invalidConfiguration(message): return message
        case .missingIPAddress: return "Gnutella requires a configured IP address."
        case let .portInUse(port): return "Gnutella cannot start because TCP/\(port) is already in use."
        case let .serviceNotRunning(host): return "Gnutella is not running on \(host)."
        case let .unreachable(host): return "Gnutella peer \(host) is unreachable."
        case let .timedOut(host): return "Gnutella peer \(host) timed out."
        case let .protocolFailure(message): return "Gnutella protocol error: \(message)"
        case .resultNotFound: return "The selected Gnutella search result no longer exists."
        case let .transferFailed(status): return "Gnutella download failed with HTTP status \(status)."
        }
    }
}

final class TopologyRuntimeGnutellaGUIDGenerator: TopologyGnutellaGUIDGenerating {
    private let prefix: String
    private var counter: UInt64

    init(nodeID: UUID, restartEpoch: UInt64, initialCounter: UInt64 = 1) {
        prefix = "\(nodeID.uuidString.lowercased())-\(restartEpoch)"
        counter = max(1, initialCounter)
    }

    func nextGUID() throws -> TopologyGnutellaGUID {
        let current = counter
        let (next, overflowed) = counter.addingReportingOverflow(1)
        guard !overflowed else { throw TopologyGnutellaError.guidSequenceExhausted }
        counter = next
        return try TopologyGnutellaGUID("\(prefix)-\(current)")
    }
}

private struct TopologyRuntimeGnutellaEnvelope {
    let sourceNodeID: UUID
    let message: TopologyGnutellaOutboundMessage
}

extension TopologyEditorState {
    mutating func synchronizeRuntimeGnutellaConfigurationFromFileSystem(nodeID: UUID) throws {
        let fileSystem = virtualFileSystemsByNodeID[nodeID] ?? .defaultForDevice()
        guard fileSystem.contains(TopologyRuntimeGnutellaStorage.nativeConfigurationPath) else {
            let configuration = runtimeGnutellaConfigurationsByNodeID[nodeID] ?? TopologyRuntimeGnutellaConfiguration()
            runtimeGnutellaConfigurationsByNodeID[nodeID] = configuration
            try persistRuntimeGnutellaConfiguration(nodeID: nodeID)
            return
        }
        let text = try fileSystem.textFile(at: TopologyRuntimeGnutellaStorage.nativeConfigurationPath)
        guard let data = text.data(using: .utf8) else {
            throw TopologyRuntimeGnutellaOperationError.invalidConfiguration("Gnutella configuration is not UTF-8.")
        }
        let configuration = try JSONDecoder().decode(TopologyRuntimeGnutellaConfiguration.self, from: data)
        runtimeGnutellaConfigurationsByNodeID[nodeID] = configuration
    }

    mutating func persistRuntimeGnutellaConfiguration(nodeID: UUID) throws {
        let configuration = runtimeGnutellaConfigurationsByNodeID[nodeID] ?? TopologyRuntimeGnutellaConfiguration()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(configuration)
        guard let text = String(data: data, encoding: .utf8) else {
            throw TopologyRuntimeGnutellaOperationError.invalidConfiguration("Gnutella configuration could not be encoded.")
        }
        var fileSystem = virtualFileSystemsByNodeID[nodeID] ?? .defaultForDevice()
        if !fileSystem.contains(TopologyGnutella.peerToPeerDirectory) {
            try fileSystem.createDirectory(at: TopologyGnutella.peerToPeerDirectory, recursive: true)
        }
        try fileSystem.writeTextFile(
            at: TopologyRuntimeGnutellaStorage.nativeConfigurationPath,
            text: text,
            overwrite: true
        )
        virtualFileSystemsByNodeID[nodeID] = fileSystem
    }

    mutating func saveRuntimeGnutellaConfiguration(
        nodeID: UUID,
        configuration: TopologyRuntimeGnutellaConfiguration
    ) -> Result<Void, TopologyRuntimeGnutellaOperationError> {
        do {
            try configuration.validate()
            let previousConfiguration = runtimeGnutellaConfigurationsByNodeID[nodeID]
            runtimeGnutellaConfigurationsByNodeID[nodeID] = configuration
            do {
                try persistRuntimeGnutellaConfiguration(nodeID: nodeID)
            } catch {
                if let previousConfiguration {
                    runtimeGnutellaConfigurationsByNodeID[nodeID] = previousConfiguration
                } else {
                    runtimeGnutellaConfigurationsByNodeID.removeValue(forKey: nodeID)
                }
                throw error
            }
            if runtimeGnutellaSessionsByNodeID[nodeID]?.isRunning == true {
                _ = stopRuntimeGnutella(nodeID: nodeID)
                return startRuntimeGnutella(nodeID: nodeID)
            }
            return .success(())
        } catch let error as TopologyRuntimeGnutellaOperationError {
            return .failure(error)
        } catch {
            return .failure(.invalidConfiguration(error.localizedDescription))
        }
    }

    mutating func startRuntimeGnutella(nodeID: UUID) -> Result<Void, TopologyRuntimeGnutellaOperationError> {
        guard simulationPhase == .running else { return .failure(.simulationStopped) }
        guard runtimeInstalledProgramsByNodeID[nodeID]?.contains(.gnutella) == true else {
            return .failure(.programNotInstalled)
        }
        let configuration = runtimeGnutellaConfigurationsByNodeID[nodeID] ?? TopologyRuntimeGnutellaConfiguration()
        do {
            if runtimeGnutellaSessionsByNodeID[nodeID]?.isRunning == true {
                return .success(())
            }
            let localPeer = try runtimeGnutellaPeer(nodeID: nodeID)
            let adapter = try TopologyGnutellaVirtualFileSystemAdapter(
                fileSystem: virtualFileSystemsByNodeID[nodeID] ?? .defaultForDevice()
            )
            let previousEpoch = runtimeGnutellaRestartEpochByNodeID[nodeID] ?? 0
            let (restartEpoch, epochOverflowed) = previousEpoch.addingReportingOverflow(1)
            guard !epochOverflowed else {
                return .failure(.protocolFailure("Gnutella restart epoch exhausted"))
            }
            let core = try TopologyGnutellaPeerCore(
                localPeer: localPeer,
                neighborCap: configuration.effectiveMaximumKnownPeers,
                guidGenerator: TopologyRuntimeGnutellaGUIDGenerator(
                    nodeID: nodeID,
                    restartEpoch: restartEpoch
                ),
                fileStore: adapter
            )
            guard let listener = networkRuntime.openTCPServerSocket(
                nodeID: nodeID,
                localPort: TopologyGnutella.tcpPort
            ) else {
                return .failure(.portInUse(Int(TopologyGnutella.tcpPort)))
            }
            runtimeGnutellaRestartEpochByNodeID[nodeID] = restartEpoch
            runtimeGnutellaConfigurationsByNodeID[nodeID] = configuration
            runtimeGnutellaCoresByNodeID[nodeID] = core
            runtimeGnutellaFileStoresByNodeID[nodeID] = adapter
            var session = runtimeGnutellaSessionsByNodeID[nodeID] ?? TopologyRuntimeGnutellaSessionState()
            session.isRunning = true
            session.listenerSocketID = listener
            session.knownPeers = []
            session.searchResults = []
            session.activeQueryGUID = nil
            session.lastError = nil
            session.appendLog(
                timestampMilliseconds: networkRuntime.state.currentTimeMilliseconds,
                direction: "local",
                message: "Gnutella started on TCP/\(TopologyGnutella.tcpPort)"
            )
            runtimeGnutellaSessionsByNodeID[nodeID] = session
            virtualFileSystemsByNodeID[nodeID] = adapter.snapshot()
            return .success(())
        } catch {
            return .failure(.protocolFailure(error.localizedDescription))
        }
    }

    @discardableResult
    mutating func stopRuntimeGnutella(nodeID: UUID) -> Bool {
        guard var session = runtimeGnutellaSessionsByNodeID[nodeID] else { return false }
        if let listener = session.listenerSocketID {
            _ = networkRuntime.closeTCPConnectionAndClean(socketID: listener)
        }
        session.isRunning = false
        session.listenerSocketID = nil
        session.knownPeers = []
        session.searchResults = []
        session.activeQueryGUID = nil
        session.appendLog(
            timestampMilliseconds: networkRuntime.state.currentTimeMilliseconds,
            direction: "local",
            message: "Gnutella stopped"
        )
        runtimeGnutellaSessionsByNodeID[nodeID] = session
        runtimeGnutellaCoresByNodeID.removeValue(forKey: nodeID)
        runtimeGnutellaFileStoresByNodeID.removeValue(forKey: nodeID)
        return true
    }

    mutating func resetRuntimeGnutellaTransientState() {
        for nodeID in runtimeGnutellaSessionsByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            _ = stopRuntimeGnutella(nodeID: nodeID)
        }
        runtimeGnutellaSessionsByNodeID.removeAll()
        runtimeGnutellaCoresByNodeID.removeAll()
        runtimeGnutellaRestartEpochByNodeID.removeAll()
        runtimeGnutellaFileStoresByNodeID.removeAll()
    }

    mutating func joinRuntimeGnutella(
        nodeID: UUID,
        bootstrapIPAddress: String
    ) -> Result<[TopologyGnutellaPeer], TopologyRuntimeGnutellaOperationError> {
        do {
            let core = try requireRuntimeGnutellaCore(nodeID: nodeID)
            guard let bootstrapNodeID = runtimeGnutellaNodeID(ipAddress: bootstrapIPAddress),
                  let bootstrapCore = runtimeGnutellaCoresByNodeID[bootstrapNodeID]
            else {
                throw TopologyRuntimeGnutellaOperationError.serviceNotRunning(bootstrapIPAddress)
            }
            try synchronizeRuntimeGnutellaFileStore(nodeID: nodeID)
            let result = try core.startDiscovery(bootstrap: bootstrapCore.localPeer)
            try deliverRuntimeGnutella(sourceNodeID: nodeID, initialResult: result)
            refreshRuntimeGnutellaSession(nodeID: nodeID)
            appendRuntimeGnutellaLog(nodeID: nodeID, direction: "outbound", message: "Joined via \(bootstrapIPAddress)")
            return .success(runtimeGnutellaSessionsByNodeID[nodeID]?.knownPeers ?? [])
        } catch let error as TopologyRuntimeGnutellaOperationError {
            setRuntimeGnutellaFailure(nodeID: nodeID, error: error)
            return .failure(error)
        } catch {
            let mapped = TopologyRuntimeGnutellaOperationError.protocolFailure(error.localizedDescription)
            setRuntimeGnutellaFailure(nodeID: nodeID, error: mapped)
            return .failure(mapped)
        }
    }

    mutating func resetRuntimeGnutellaNetwork(nodeID: UUID) -> Result<Void, TopologyRuntimeGnutellaOperationError> {
        guard runtimeGnutellaSessionsByNodeID[nodeID]?.isRunning == true else {
            return .failure(.serviceNotRunning(runtimeGnutellaHost(nodeID: nodeID) ?? nodeID.uuidString))
        }
        _ = stopRuntimeGnutella(nodeID: nodeID)
        let result = startRuntimeGnutella(nodeID: nodeID)
        if case .success = result {
            appendRuntimeGnutellaLog(nodeID: nodeID, direction: "local", message: "Known peer list reset")
        }
        return result
    }

    mutating func searchRuntimeGnutella(
        nodeID: UUID,
        searchTerm: String
    ) -> Result<[TopologyGnutellaSearchResult], TopologyRuntimeGnutellaOperationError> {
        do {
            let core = try requireRuntimeGnutellaCore(nodeID: nodeID)
            try synchronizeRuntimeGnutellaFileStore(nodeID: nodeID)
            let result = try core.startQuery(searchTerm: searchTerm)
            let guid = result.events.compactMap { event -> TopologyGnutellaGUID? in
                if case let .queryStarted(guid, _) = event { return guid }
                return nil
            }.first
            if var session = runtimeGnutellaSessionsByNodeID[nodeID] {
                session.activeQueryGUID = guid
                session.searchResults = []
                session.lastError = nil
                runtimeGnutellaSessionsByNodeID[nodeID] = session
            }
            try deliverRuntimeGnutella(sourceNodeID: nodeID, initialResult: result)
            refreshRuntimeGnutellaSession(nodeID: nodeID)
            appendRuntimeGnutellaLog(nodeID: nodeID, direction: "outbound", message: "Search: \(searchTerm)")
            return .success(runtimeGnutellaSessionsByNodeID[nodeID]?.searchResults ?? [])
        } catch let error as TopologyRuntimeGnutellaOperationError {
            setRuntimeGnutellaFailure(nodeID: nodeID, error: error)
            return .failure(error)
        } catch {
            let mapped = TopologyRuntimeGnutellaOperationError.protocolFailure(error.localizedDescription)
            setRuntimeGnutellaFailure(nodeID: nodeID, error: mapped)
            return .failure(mapped)
        }
    }

    mutating func clearRuntimeGnutellaSearchResults(nodeID: UUID) {
        guard var session = runtimeGnutellaSessionsByNodeID[nodeID] else { return }
        session.activeQueryGUID = nil
        session.searchResults = []
        session.lastError = nil
        runtimeGnutellaSessionsByNodeID[nodeID] = session
    }

    mutating func downloadRuntimeGnutella(
        nodeID: UUID,
        result: TopologyGnutellaSearchResult
    ) -> Result<TopologyGnutellaFileMetadata, TopologyRuntimeGnutellaOperationError> {
        do {
            _ = try requireRuntimeGnutellaCore(nodeID: nodeID)
            guard let ownerNodeID = runtimeGnutellaNodeID(ipAddress: result.peer.host),
                  runtimeGnutellaSessionsByNodeID[ownerNodeID]?.isRunning == true,
                  let ownerStore = runtimeGnutellaFileStoresByNodeID[ownerNodeID],
                  let localStore = runtimeGnutellaFileStoresByNodeID[nodeID]
            else {
                throw TopologyRuntimeGnutellaOperationError.serviceNotRunning(result.peer.host)
            }
            try synchronizeRuntimeGnutellaFileStore(nodeID: ownerNodeID)
            try synchronizeRuntimeGnutellaFileStore(nodeID: nodeID)
            let path = try TopologyGnutellaDirectTransfer.path(forFileName: result.file.name)
            let socket = try openRuntimeGnutellaConnection(sourceNodeID: nodeID, destination: result.peer)
            defer { _ = networkRuntime.closeTCPConnectionAndClean(socketID: socket) }
            guard let accepted = networkRuntime.peerTCPSocketID(socketID: socket) else {
                throw TopologyRuntimeGnutellaOperationError.protocolFailure("Missing accepted TCP socket")
            }
            let request = "GET \(path) HTTP/1.1\r\nHost: \(result.peer.host)\r\nConnection: close\r\n\r\n"
            guard networkRuntime.sendTCP(socketID: socket, payload: Data(request.utf8)),
                  networkRuntime.receiveTCP(socketID: accepted) != nil
            else {
                throw TopologyRuntimeGnutellaOperationError.timedOut(result.peer.host)
            }
            let served = try TopologyGnutellaDirectTransfer.serve(path: path, from: ownerStore)
            let responseData = try runtimeGnutellaHTTPData(response: served)
            guard networkRuntime.sendTCP(socketID: accepted, payload: responseData),
                  let received = networkRuntime.receiveTCP(socketID: socket)
            else {
                throw TopologyRuntimeGnutellaOperationError.timedOut(result.peer.host)
            }
            let response = try runtimeGnutellaHTTPResponse(data: received, path: path)
            guard response.status == .ok else {
                throw TopologyRuntimeGnutellaOperationError.transferFailed(response.status.rawValue)
            }
            let metadata = try TopologyGnutellaDirectTransfer.install(response, into: localStore)
            virtualFileSystemsByNodeID[nodeID] = localStore.snapshot()
            appendRuntimeGnutellaLog(nodeID: nodeID, direction: "inbound", message: "Downloaded \(metadata.name) from \(result.peer.host)")
            return .success(metadata)
        } catch let error as TopologyRuntimeGnutellaOperationError {
            setRuntimeGnutellaFailure(nodeID: nodeID, error: error)
            return .failure(error)
        } catch let error as TopologyGnutellaError {
            let mapped: TopologyRuntimeGnutellaOperationError
            if case let .directTransferStatus(status) = error {
                mapped = .transferFailed(status)
            } else {
                mapped = .protocolFailure(error.localizedDescription)
            }
            setRuntimeGnutellaFailure(nodeID: nodeID, error: mapped)
            return .failure(mapped)
        } catch {
            let mapped = TopologyRuntimeGnutellaOperationError.protocolFailure(error.localizedDescription)
            setRuntimeGnutellaFailure(nodeID: nodeID, error: mapped)
            return .failure(mapped)
        }
    }

    private mutating func requireRuntimeGnutellaCore(nodeID: UUID) throws -> TopologyGnutellaPeerCore {
        guard simulationPhase == .running else { throw TopologyRuntimeGnutellaOperationError.simulationStopped }
        guard runtimeInstalledProgramsByNodeID[nodeID]?.contains(.gnutella) == true else {
            throw TopologyRuntimeGnutellaOperationError.programNotInstalled
        }
        guard runtimeGnutellaSessionsByNodeID[nodeID]?.isRunning == true,
              let core = runtimeGnutellaCoresByNodeID[nodeID]
        else {
            throw TopologyRuntimeGnutellaOperationError.serviceNotRunning(runtimeGnutellaHost(nodeID: nodeID) ?? nodeID.uuidString)
        }
        return core
    }

    private func runtimeGnutellaHost(nodeID: UUID) -> String? {
        networkRuntime.networkInterfaces(nodeID: nodeID)
            .map(\.ipAddress)
            .first { !$0.isEmpty && $0 != "0.0.0.0" }
    }

    private func runtimeGnutellaNodeID(ipAddress: String) -> UUID? {
        graph.nodes
            .map(\.id)
            .filter { runtimeInstalledProgramsByNodeID[$0]?.contains(.gnutella) == true }
            .sorted(by: { $0.uuidString < $1.uuidString })
            .first { nodeID in
                networkRuntime.networkInterfaces(nodeID: nodeID).contains { $0.ipAddress == ipAddress }
            }
    }

    private func runtimeGnutellaPeer(nodeID: UUID) throws -> TopologyGnutellaPeer {
        guard let host = runtimeGnutellaHost(nodeID: nodeID) else {
            throw TopologyRuntimeGnutellaOperationError.missingIPAddress
        }
        return try TopologyGnutellaPeer(id: nodeID.uuidString.lowercased(), host: host)
    }

    private mutating func synchronizeRuntimeGnutellaFileStore(nodeID: UUID) throws {
        guard let adapter = runtimeGnutellaFileStoresByNodeID[nodeID] else {
            throw TopologyRuntimeGnutellaOperationError.serviceNotRunning(runtimeGnutellaHost(nodeID: nodeID) ?? nodeID.uuidString)
        }
        try adapter.replaceSnapshot(virtualFileSystemsByNodeID[nodeID] ?? .defaultForDevice())
        virtualFileSystemsByNodeID[nodeID] = adapter.snapshot()
    }

    private mutating func deliverRuntimeGnutella(
        sourceNodeID: UUID,
        initialResult: TopologyGnutellaProcessingResult
    ) throws {
        var queue = initialResult.outbound.map { TopologyRuntimeGnutellaEnvelope(sourceNodeID: sourceNodeID, message: $0) }
        var cursor = 0
        let deliveryLimit = TopologyGnutellaLimits.educationalDefault.maximumSeenRequestGUIDs
        while cursor < queue.count {
            guard cursor < deliveryLimit else {
                throw TopologyRuntimeGnutellaOperationError.protocolFailure("Delivery quota exceeded")
            }
            let envelope = queue[cursor]
            cursor += 1
            guard let sourceCore = runtimeGnutellaCoresByNodeID[envelope.sourceNodeID] else {
                continue
            }
            guard let destinationNodeID = runtimeGnutellaNodeID(ipAddress: envelope.message.destination.host),
                  let destinationCore = runtimeGnutellaCoresByNodeID[destinationNodeID],
                  runtimeGnutellaSessionsByNodeID[destinationNodeID]?.isRunning == true
            else {
                removeUnavailableRuntimeGnutellaNeighbor(
                    sourceNodeID: envelope.sourceNodeID,
                    peer: envelope.message.destination
                )
                continue
            }
            try synchronizeRuntimeGnutellaFileStore(nodeID: destinationNodeID)
            do {
                let socket = try openRuntimeGnutellaConnection(
                    sourceNodeID: envelope.sourceNodeID,
                    destination: envelope.message.destination
                )
                defer { _ = networkRuntime.closeTCPConnectionAndClean(socketID: socket) }
                guard let accepted = networkRuntime.peerTCPSocketID(socketID: socket) else {
                    throw TopologyRuntimeGnutellaOperationError.protocolFailure("Missing accepted TCP socket")
                }
                let encoded = try TopologyGnutellaTextCodec.encode(envelope.message.packet)
                guard networkRuntime.sendTCP(socketID: socket, payload: Data(encoded.utf8)),
                      let received = networkRuntime.receiveTCP(socketID: accepted),
                      let receivedText = String(data: received, encoding: .utf8)
                else {
                    throw TopologyRuntimeGnutellaOperationError.timedOut(envelope.message.destination.host)
                }
                networkRuntime.recordTrace(
                    nodeID: destinationNodeID,
                    interfaceID: networkRuntime.networkInterfaces(nodeID: destinationNodeID).first?.portID,
                    direction: .inbound,
                    layer: .application,
                    operation: .received,
                    afterHeaders: [
                        .init(name: "kind", value: "Gnutella"),
                        .init(name: "descriptor", value: envelope.message.packet.descriptor.rawValue),
                        .init(name: "guid", value: envelope.message.packet.guid.rawValue),
                    ],
                    detail: "Gnutella packet received"
                )
                let result = try destinationCore.receiveEncoded(receivedText, from: sourceCore.localPeer)
                refreshRuntimeGnutellaSession(nodeID: destinationNodeID)
                queue.append(contentsOf: result.outbound.map {
                    TopologyRuntimeGnutellaEnvelope(sourceNodeID: destinationNodeID, message: $0)
                })
            } catch let error as TopologyRuntimeGnutellaOperationError {
                switch error {
                case .unreachable, .timedOut, .serviceNotRunning:
                    // A peer can disappear while a flood is in progress. Remove only
                    // transport-level failures; protocol and validation failures must
                    // remain visible to the caller instead of being silently swallowed.
                    removeUnavailableRuntimeGnutellaNeighbor(
                        sourceNodeID: envelope.sourceNodeID,
                        peer: envelope.message.destination
                    )
                    continue
                default:
                    throw error
                }
            }
        }
    }

    private mutating func removeUnavailableRuntimeGnutellaNeighbor(
        sourceNodeID: UUID,
        peer: TopologyGnutellaPeer
    ) {
        runtimeGnutellaCoresByNodeID[sourceNodeID]?.removeNeighbor(peerID: peer.id)
        refreshRuntimeGnutellaSession(nodeID: sourceNodeID)
        appendRuntimeGnutellaLog(
            nodeID: sourceNodeID,
            direction: "local",
            message: "Removed unavailable peer \(peer.host)"
        )
    }

    private mutating func openRuntimeGnutellaConnection(
        sourceNodeID: UUID,
        destination: TopologyGnutellaPeer
    ) throws -> UUID {
        guard let socket = networkRuntime.openTCPClientSocket(
            nodeID: sourceNodeID,
            remoteIPAddress: destination.host,
            remotePort: destination.port
        ) else {
            throw TopologyRuntimeGnutellaOperationError.unreachable(destination.host)
        }
        switch networkRuntime.connectTCPWithResult(socketID: socket) {
        case .connected:
            networkRuntime.recordTrace(
                nodeID: sourceNodeID,
                interfaceID: networkRuntime.networkInterfaces(nodeID: sourceNodeID).first?.portID,
                direction: .outbound,
                layer: .application,
                operation: .sent,
                afterHeaders: [
                    .init(name: "kind", value: "Gnutella"),
                    .init(name: "destination", value: destination.host),
                    .init(name: "port", value: String(destination.port)),
                ],
                detail: "Gnutella TCP connection established"
            )
            return socket
        case .timedOut:
            _ = networkRuntime.closeTCPConnectionAndClean(socketID: socket)
            throw TopologyRuntimeGnutellaOperationError.timedOut(destination.host)
        case .unreachable, .invalidSocket:
            _ = networkRuntime.closeTCPConnectionAndClean(socketID: socket)
            throw TopologyRuntimeGnutellaOperationError.unreachable(destination.host)
        }
    }

    private mutating func refreshRuntimeGnutellaSession(nodeID: UUID) {
        guard let core = runtimeGnutellaCoresByNodeID[nodeID],
              var session = runtimeGnutellaSessionsByNodeID[nodeID]
        else { return }
        session.knownPeers = core.neighbors
        if let guid = session.activeQueryGUID {
            session.searchResults = core.searchResults(for: guid)
        }
        session.lastError = nil
        runtimeGnutellaSessionsByNodeID[nodeID] = session
    }

    private mutating func appendRuntimeGnutellaLog(nodeID: UUID, direction: String, message: String) {
        guard var session = runtimeGnutellaSessionsByNodeID[nodeID] else { return }
        session.appendLog(
            timestampMilliseconds: networkRuntime.state.currentTimeMilliseconds,
            direction: direction,
            message: message
        )
        runtimeGnutellaSessionsByNodeID[nodeID] = session
    }

    private mutating func setRuntimeGnutellaFailure(
        nodeID: UUID,
        error: TopologyRuntimeGnutellaOperationError
    ) {
        guard var session = runtimeGnutellaSessionsByNodeID[nodeID] else { return }
        session.lastError = error.localizedDescription
        session.appendLog(
            timestampMilliseconds: networkRuntime.state.currentTimeMilliseconds,
            direction: "error",
            message: error.localizedDescription
        )
        runtimeGnutellaSessionsByNodeID[nodeID] = session
    }

    private func runtimeGnutellaHTTPData(response: TopologyGnutellaDirectResponse) throws -> Data {
        switch response.status {
        case .notFound:
            return Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n".utf8)
        case .ok:
            guard let file = response.file else { throw TopologyGnutellaError.missingDirectTransferBody }
            var data = Data(
                "HTTP/1.1 200 OK\r\nContent-Type: \(file.metadata.mediaType)\r\nContent-Length: \(file.data.count)\r\nX-Filius-File-Name: \(file.metadata.name)\r\n\r\n".utf8
            )
            data.append(file.data)
            return data
        }
    }

    private func runtimeGnutellaHTTPResponse(
        data: Data,
        path: String
    ) throws -> TopologyGnutellaDirectResponse {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator),
              let header = String(data: data[..<range.lowerBound], encoding: .utf8)
        else {
            throw TopologyRuntimeGnutellaOperationError.protocolFailure("Malformed HTTP response")
        }
        let lines = header.components(separatedBy: "\r\n")
        guard let statusLine = lines.first,
              let status = Int(statusLine.split(separator: " ").dropFirst().first ?? "")
        else {
            throw TopologyRuntimeGnutellaOperationError.protocolFailure("Missing HTTP status")
        }
        if status == TopologyGnutellaDirectStatus.notFound.rawValue {
            return TopologyGnutellaDirectResponse(status: .notFound, path: path, file: nil)
        }
        guard status == TopologyGnutellaDirectStatus.ok.rawValue else {
            throw TopologyRuntimeGnutellaOperationError.transferFailed(status)
        }
        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let index = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<index]).lowercased()
            let value = String(line[line.index(after: index)...]).trimmingCharacters(in: .whitespaces)
            fields[name] = value
        }
        guard let name = fields["x-filius-file-name"],
              let mediaType = fields["content-type"],
              let declaredLength = fields["content-length"].flatMap(Int.init)
        else {
            throw TopologyRuntimeGnutellaOperationError.protocolFailure("Missing HTTP file metadata")
        }
        let body = Data(data[range.upperBound...])
        guard body.count == declaredLength else {
            throw TopologyRuntimeGnutellaOperationError.protocolFailure("HTTP body length mismatch")
        }
        let metadata = try TopologyGnutellaFileMetadata(name: name, sizeBytes: body.count, mediaType: mediaType)
        let file = try TopologyGnutellaFileResource(metadata: metadata, data: body)
        return TopologyGnutellaDirectResponse(status: .ok, path: path, file: file)
    }
}
