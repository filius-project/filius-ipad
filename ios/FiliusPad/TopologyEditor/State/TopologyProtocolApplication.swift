import Foundation

private struct TopologyProtocolApplicationDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

private func assertNoUnknownProtocolApplicationKeys<Key>(
    decoder: Decoder,
    allowedKeys: Key.Type,
    context: String
) throws where Key: CodingKey & CaseIterable {
    let container = try decoder.container(keyedBy: TopologyProtocolApplicationDynamicCodingKey.self)
    let allowed = Set(Key.allCases.map(\.stringValue))
    let unknown = container.allKeys.map(\.stringValue).filter { !allowed.contains($0) }.sorted()
    guard unknown.isEmpty else {
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "\(context) contains unknown keys: \(unknown.joined(separator: ", "))")
        )
    }
}

enum TopologyProtocolApplicationRole: String, Codable, CaseIterable, Equatable, Hashable {
    case client
    case server
}

struct TopologyProtocolApplicationMessageTemplate: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var message: String

    init(id: UUID = UUID(), name: String, message: String) {
        self.id = id
        self.name = name
        self.message = message
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case id, name, message }

    init(from decoder: Decoder) throws {
        try assertNoUnknownProtocolApplicationKeys(decoder: decoder, allowedKeys: CodingKeys.self, context: "TopologyProtocolApplicationMessageTemplate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        message = try container.decode(String.self, forKey: .message)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(message, forKey: .message)
    }
}

struct TopologyProtocolApplicationResponseRule: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    var request: String
    var response: String

    init(id: UUID = UUID(), request: String, response: String) {
        self.id = id
        self.request = request
        self.response = response
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case id, request, response }

    init(from decoder: Decoder) throws {
        try assertNoUnknownProtocolApplicationKeys(decoder: decoder, allowedKeys: CodingKeys.self, context: "TopologyProtocolApplicationResponseRule")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        request = try container.decode(String.self, forKey: .request)
        response = try container.decode(String.self, forKey: .response)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(request, forKey: .request)
        try container.encode(response, forKey: .response)
    }
}

struct TopologyProtocolApplicationDefinition: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var role: TopologyProtocolApplicationRole
    var transport: TopologyRuntimeTransportProtocol
    var port: UInt16
    var clientMessageTemplates: [TopologyProtocolApplicationMessageTemplate]
    var responseRules: [TopologyProtocolApplicationResponseRule]

    init(
        id: UUID = UUID(),
        name: String,
        role: TopologyProtocolApplicationRole,
        transport: TopologyRuntimeTransportProtocol,
        port: UInt16,
        clientMessageTemplates: [TopologyProtocolApplicationMessageTemplate] = [],
        responseRules: [TopologyProtocolApplicationResponseRule] = []
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.transport = transport
        self.port = port
        self.clientMessageTemplates = clientMessageTemplates
        self.responseRules = responseRules
    }

    var deterministicRules: [TopologyProtocolApplicationResponseRule] { responseRules }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, role, transport, port, clientMessageTemplates, responseRules
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownProtocolApplicationKeys(decoder: decoder, allowedKeys: CodingKeys.self, context: "TopologyProtocolApplicationDefinition")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        role = try container.decode(TopologyProtocolApplicationRole.self, forKey: .role)
        transport = try container.decode(TopologyRuntimeTransportProtocol.self, forKey: .transport)
        port = try container.decode(UInt16.self, forKey: .port)
        clientMessageTemplates = try container.decode([TopologyProtocolApplicationMessageTemplate].self, forKey: .clientMessageTemplates)
        responseRules = try container.decode([TopologyProtocolApplicationResponseRule].self, forKey: .responseRules)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(role, forKey: .role)
        try container.encode(transport, forKey: .transport)
        try container.encode(port, forKey: .port)
        try container.encode(clientMessageTemplates, forKey: .clientMessageTemplates)
        try container.encode(responseRules, forKey: .responseRules)
    }
}

struct TopologyProtocolApplicationInstallationSnapshot: Codable, Equatable, Hashable {
    let nodeID: UUID
    let definitionID: UUID

    enum CodingKeys: String, CodingKey, CaseIterable { case nodeID, definitionID }

    init(nodeID: UUID, definitionID: UUID) {
        self.nodeID = nodeID
        self.definitionID = definitionID
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownProtocolApplicationKeys(decoder: decoder, allowedKeys: CodingKeys.self, context: "TopologyProtocolApplicationInstallationSnapshot")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        definitionID = try container.decode(UUID.self, forKey: .definitionID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nodeID, forKey: .nodeID)
        try container.encode(definitionID, forKey: .definitionID)
    }
}

enum TopologyProtocolApplicationLimits {
    static let maximumDefinitions = 64
    static let maximumInstallations = 512
    static let maximumNameBytes = 64
    static let maximumTemplatesPerClient = 32
    static let maximumRulesPerServer = 64
    static let maximumMessageBytes = 4_096
    static let maximumProjectContentBytes = 131_072
    static let maximumRuntimeLogEntries = 100
    static let responseTimeoutMilliseconds: UInt64 = 5_000
}

enum TopologyProtocolApplicationValidationError: Error, Equatable {
    case tooManyDefinitions(count: Int)
    case duplicateDefinitionID(id: UUID)
    case duplicateDefinitionName(name: String)
    case invalidName(id: UUID)
    case invalidPort(id: UUID)
    case invalidClientShape(id: UUID)
    case invalidServerShape(id: UUID)
    case tooManyTemplates(definitionID: UUID, count: Int)
    case tooManyRules(definitionID: UUID, count: Int)
    case duplicateTemplateID(definitionID: UUID, templateID: UUID)
    case duplicateRuleID(definitionID: UUID, ruleID: UUID)
    case invalidTemplate(definitionID: UUID, templateID: UUID)
    case invalidRule(definitionID: UUID, ruleID: UUID)
    case oversizedMessage(definitionID: UUID, recordID: UUID)
    case oversizedProjectContent(bytes: Int)
    case tooManyInstallations(count: Int)
    case duplicateInstallation(nodeID: UUID, definitionID: UUID)
    case installationReferencesUnknownNode(nodeID: UUID, definitionID: UUID)
    case installationReferencesUnsupportedNode(nodeID: UUID, definitionID: UUID)
    case installationReferencesUnknownDefinition(nodeID: UUID, definitionID: UUID)
}

enum TopologyProtocolApplicationCatalog {
    static func validateDefinitions(_ definitions: [TopologyProtocolApplicationDefinition]) throws {
        guard definitions.count <= TopologyProtocolApplicationLimits.maximumDefinitions else {
            throw TopologyProtocolApplicationValidationError.tooManyDefinitions(count: definitions.count)
        }
        var definitionIDs: Set<UUID> = []
        var normalizedNames: Set<String> = []
        var totalContentBytes = 0

        for definition in definitions {
            guard definitionIDs.insert(definition.id).inserted else {
                throw TopologyProtocolApplicationValidationError.duplicateDefinitionID(id: definition.id)
            }
            let trimmedName = definition.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty,
                  trimmedName == definition.name,
                  definition.name.lengthOfBytes(using: .utf8) <= TopologyProtocolApplicationLimits.maximumNameBytes else {
                throw TopologyProtocolApplicationValidationError.invalidName(id: definition.id)
            }
            let normalizedName = trimmedName.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            guard normalizedNames.insert(normalizedName).inserted else {
                throw TopologyProtocolApplicationValidationError.duplicateDefinitionName(name: definition.name)
            }
            guard definition.port > 0 else {
                throw TopologyProtocolApplicationValidationError.invalidPort(id: definition.id)
            }
            totalContentBytes += definition.name.lengthOfBytes(using: .utf8)

            switch definition.role {
            case .client:
                guard !definition.clientMessageTemplates.isEmpty, definition.responseRules.isEmpty else {
                    throw TopologyProtocolApplicationValidationError.invalidClientShape(id: definition.id)
                }
                guard definition.clientMessageTemplates.count <= TopologyProtocolApplicationLimits.maximumTemplatesPerClient else {
                    throw TopologyProtocolApplicationValidationError.tooManyTemplates(
                        definitionID: definition.id,
                        count: definition.clientMessageTemplates.count
                    )
                }
                var templateIDs: Set<UUID> = []
                for template in definition.clientMessageTemplates {
                    guard templateIDs.insert(template.id).inserted else {
                        throw TopologyProtocolApplicationValidationError.duplicateTemplateID(
                            definitionID: definition.id,
                            templateID: template.id
                        )
                    }
                    let trimmedTemplateName = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedTemplateName.isEmpty,
                          trimmedTemplateName == template.name,
                          template.name.lengthOfBytes(using: .utf8) <= TopologyProtocolApplicationLimits.maximumNameBytes,
                          !template.message.isEmpty else {
                        throw TopologyProtocolApplicationValidationError.invalidTemplate(
                            definitionID: definition.id,
                            templateID: template.id
                        )
                    }
                    let messageBytes = template.message.lengthOfBytes(using: .utf8)
                    guard messageBytes <= TopologyProtocolApplicationLimits.maximumMessageBytes else {
                        throw TopologyProtocolApplicationValidationError.oversizedMessage(
                            definitionID: definition.id,
                            recordID: template.id
                        )
                    }
                    totalContentBytes += template.name.lengthOfBytes(using: .utf8) + messageBytes
                }
            case .server:
                guard definition.clientMessageTemplates.isEmpty, !definition.responseRules.isEmpty else {
                    throw TopologyProtocolApplicationValidationError.invalidServerShape(id: definition.id)
                }
                guard definition.responseRules.count <= TopologyProtocolApplicationLimits.maximumRulesPerServer else {
                    throw TopologyProtocolApplicationValidationError.tooManyRules(
                        definitionID: definition.id,
                        count: definition.responseRules.count
                    )
                }
                var ruleIDs: Set<UUID> = []
                for rule in definition.responseRules {
                    guard ruleIDs.insert(rule.id).inserted else {
                        throw TopologyProtocolApplicationValidationError.duplicateRuleID(
                            definitionID: definition.id,
                            ruleID: rule.id
                        )
                    }
                    guard !rule.request.isEmpty else {
                        throw TopologyProtocolApplicationValidationError.invalidRule(
                            definitionID: definition.id,
                            ruleID: rule.id
                        )
                    }
                    let requestBytes = rule.request.lengthOfBytes(using: .utf8)
                    let responseBytes = rule.response.lengthOfBytes(using: .utf8)
                    guard requestBytes <= TopologyProtocolApplicationLimits.maximumMessageBytes,
                          responseBytes <= TopologyProtocolApplicationLimits.maximumMessageBytes else {
                        throw TopologyProtocolApplicationValidationError.oversizedMessage(
                            definitionID: definition.id,
                            recordID: rule.id
                        )
                    }
                    totalContentBytes += requestBytes + responseBytes
                }
            }
        }
        guard totalContentBytes <= TopologyProtocolApplicationLimits.maximumProjectContentBytes else {
            throw TopologyProtocolApplicationValidationError.oversizedProjectContent(bytes: totalContentBytes)
        }
    }

    static func validateInstallations(
        _ installations: [TopologyProtocolApplicationInstallationSnapshot],
        definitions: [TopologyProtocolApplicationDefinition],
        graph: TopologyGraph
    ) throws {
        guard installations.count <= TopologyProtocolApplicationLimits.maximumInstallations else {
            throw TopologyProtocolApplicationValidationError.tooManyInstallations(count: installations.count)
        }
        let definitionIDs = Set(definitions.map(\.id))
        var seen: Set<TopologyProtocolApplicationInstallationSnapshot> = []
        for installation in installations {
            guard seen.insert(installation).inserted else {
                throw TopologyProtocolApplicationValidationError.duplicateInstallation(
                    nodeID: installation.nodeID,
                    definitionID: installation.definitionID
                )
            }
            guard definitionIDs.contains(installation.definitionID) else {
                throw TopologyProtocolApplicationValidationError.installationReferencesUnknownDefinition(
                    nodeID: installation.nodeID,
                    definitionID: installation.definitionID
                )
            }
            guard let node = graph.node(withID: installation.nodeID) else {
                throw TopologyProtocolApplicationValidationError.installationReferencesUnknownNode(
                    nodeID: installation.nodeID,
                    definitionID: installation.definitionID
                )
            }
            guard node.kind.isPCClassEndpoint else {
                throw TopologyProtocolApplicationValidationError.installationReferencesUnsupportedNode(
                    nodeID: installation.nodeID,
                    definitionID: installation.definitionID
                )
            }
        }
    }
}

struct TopologyProtocolApplicationRuntimeKey: Equatable, Hashable {
    let nodeID: UUID
    let definitionID: UUID
}

struct TopologyProtocolApplicationRuntimeLogEntry: Equatable, Identifiable {
    let id: UInt64
    let timestampMilliseconds: UInt64
    let direction: String
    let message: String
}

struct TopologyProtocolApplicationClientState: Equatable {
    var socketID: UUID?
    var destinationIPAddress: String
    var nextLogID: UInt64 = 1
    var logs: [TopologyProtocolApplicationRuntimeLogEntry] = []

    mutating func appendLog(time: UInt64, direction: String, message: String) {
        logs.append(.init(id: nextLogID, timestampMilliseconds: time, direction: direction, message: message))
        nextLogID = nextLogID == UInt64.max ? UInt64.max : nextLogID + 1
        if logs.count > TopologyProtocolApplicationLimits.maximumRuntimeLogEntries {
            logs.removeFirst(logs.count - TopologyProtocolApplicationLimits.maximumRuntimeLogEntries)
        }
    }
}

struct TopologyProtocolApplicationServerState: Equatable {
    var socketID: UUID
    var nextLogID: UInt64 = 1
    var logs: [TopologyProtocolApplicationRuntimeLogEntry] = []

    mutating func appendLog(time: UInt64, direction: String, message: String) {
        logs.append(.init(id: nextLogID, timestampMilliseconds: time, direction: direction, message: message))
        nextLogID = nextLogID == UInt64.max ? UInt64.max : nextLogID + 1
        if logs.count > TopologyProtocolApplicationLimits.maximumRuntimeLogEntries {
            logs.removeFirst(logs.count - TopologyProtocolApplicationLimits.maximumRuntimeLogEntries)
        }
    }
}

enum TopologyProtocolApplicationRuntimeError: Error, Equatable {
    case simulationStopped
    case unknownDefinition
    case wrongRole
    case notInstalled
    case invalidNode
    case invalidDestination
    case unknownTemplate
    case portInUse
    case unreachable
    case sendFailed
}

struct TopologyProtocolApplicationClientExecutionResult: Equatable {
    let response: String?
    let timedOut: Bool
}

func receiveProtocolApplicationTCPResponse<Runtime>(
    runtime: inout Runtime,
    receive: (inout Runtime) -> Data?,
    advanceToTimeout: (inout Runtime) -> Void
) -> Data? {
    if let immediate = receive(&runtime) {
        return immediate
    }
    advanceToTimeout(&runtime)
    return receive(&runtime)
}

extension TopologyEditorState {
    var sortedProtocolApplicationDefinitions: [TopologyProtocolApplicationDefinition] {
        protocolApplicationDefinitionsByID.values.sorted {
            if $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedSame {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    mutating func startProtocolApplicationServer(
        nodeID: UUID,
        definitionID: UUID
    ) -> TopologyProtocolApplicationRuntimeError? {
        guard simulationPhase == .running else { return .simulationStopped }
        guard graph.node(withID: nodeID)?.kind.isPCClassEndpoint == true else { return .invalidNode }
        guard runtimeInstalledProtocolApplicationIDsByNodeID[nodeID]?.contains(definitionID) == true else { return .notInstalled }
        guard let definition = protocolApplicationDefinitionsByID[definitionID] else { return .unknownDefinition }
        guard definition.role == .server else { return .wrongRole }
        let key = TopologyProtocolApplicationRuntimeKey(nodeID: nodeID, definitionID: definitionID)
        if runtimeProtocolApplicationServers[key] != nil { return nil }

        let socketID: UUID?
        switch definition.transport {
        case .tcp:
            socketID = networkRuntime.openTCPServerSocket(nodeID: nodeID, localPort: definition.port)
        case .udp:
            socketID = networkRuntime.bindUDPSocket(nodeID: nodeID, localPort: definition.port)
        }
        guard let socketID else { return .portInUse }
        var server = TopologyProtocolApplicationServerState(socketID: socketID)
        server.appendLog(
            time: networkRuntime.state.currentTimeMilliseconds,
            direction: "system",
            message: FiliusLocalization.t("protocol.runtime.server.started", definition.transport.displayName, Int(definition.port))
        )
        runtimeProtocolApplicationServers[key] = server
        return nil
    }

    mutating func stopProtocolApplicationServer(nodeID: UUID, definitionID: UUID) {
        let key = TopologyProtocolApplicationRuntimeKey(nodeID: nodeID, definitionID: definitionID)
        guard let server = runtimeProtocolApplicationServers.removeValue(forKey: key) else { return }
        var closedSocketIDs: Set<UUID> = []
        if networkRuntime.state.socketsByID[server.socketID]?.protocolKind == .tcp {
            for acceptedID in (networkRuntime.state.tcpAcceptedSocketIDsByListenerID[server.socketID] ?? []).sorted(by: { $0.uuidString < $1.uuidString }) {
                closedSocketIDs.formUnion(networkRuntime.closeTCPConnectionAndClean(socketID: acceptedID))
            }
            closedSocketIDs.formUnion(networkRuntime.closeTCPConnectionAndClean(socketID: server.socketID))
        } else {
            networkRuntime.closeSocket(socketID: server.socketID)
            closedSocketIDs.insert(server.socketID)
        }
        clearProtocolClientSocketReferences(closedSocketIDs)
        clearSimpleClientSocketReferences(closedSocketIDs)
        simulationTick = max(simulationTick, networkRuntime.state.currentTimeMilliseconds)
    }

    @discardableResult
    mutating func processProtocolApplicationServers() -> Int {
        let keys = runtimeProtocolApplicationServers.keys.sorted {
            if $0.definitionID.uuidString == $1.definitionID.uuidString {
                return $0.nodeID.uuidString < $1.nodeID.uuidString
            }
            return $0.definitionID.uuidString < $1.definitionID.uuidString
        }
        var processedCount = 0
        for key in keys {
            guard let definition = protocolApplicationDefinitionsByID[key.definitionID],
                  definition.role == .server,
                  var server = runtimeProtocolApplicationServers[key] else { continue }
            switch definition.transport {
            case .tcp:
                for acceptedID in (networkRuntime.state.tcpAcceptedSocketIDsByListenerID[server.socketID] ?? []).sorted(by: { $0.uuidString < $1.uuidString }) {
                    while let payload = networkRuntime.receiveTCP(socketID: acceptedID) {
                        processedCount += 1
                        if let response = protocolApplicationResponse(
                            for: payload,
                            definition: definition,
                            key: key,
                            server: &server
                        ), networkRuntime.sendTCP(socketID: acceptedID, payload: response) {
                            recordProtocolApplicationResponse(
                                response,
                                definition: definition,
                                key: key,
                                server: &server
                            )
                        }
                    }
                }
            case .udp:
                while let received = networkRuntime.receiveUDP(socketID: server.socketID) {
                    processedCount += 1
                    if let response = protocolApplicationResponse(
                        for: received.datagram.payload,
                        definition: definition,
                        key: key,
                        server: &server
                    ), networkRuntime.sendUDP(
                        socketID: server.socketID,
                        payload: response,
                        destinationIPAddress: received.senderIPAddress,
                        destinationPort: received.datagram.sourcePort
                    ) != nil {
                        recordProtocolApplicationResponse(
                            response,
                            definition: definition,
                            key: key,
                            server: &server
                        )
                    }
                }
            }
            runtimeProtocolApplicationServers[key] = server
        }
        simulationTick = max(simulationTick, networkRuntime.state.currentTimeMilliseconds)
        return processedCount
    }

    mutating func executeProtocolApplicationClientMessage(
        nodeID: UUID,
        definitionID: UUID,
        destinationIPAddress: String,
        templateID: UUID
    ) -> Result<TopologyProtocolApplicationClientExecutionResult, TopologyProtocolApplicationRuntimeError> {
        guard simulationPhase == .running else { return .failure(.simulationStopped) }
        guard graph.node(withID: nodeID)?.kind.isPCClassEndpoint == true else { return .failure(.invalidNode) }
        guard runtimeInstalledProtocolApplicationIDsByNodeID[nodeID]?.contains(definitionID) == true else { return .failure(.notInstalled) }
        guard let definition = protocolApplicationDefinitionsByID[definitionID] else { return .failure(.unknownDefinition) }
        guard definition.role == .client else { return .failure(.wrongRole) }
        guard TopologyJavaRouteTable.isValidJavaIPAddress(destinationIPAddress) else { return .failure(.invalidDestination) }
        guard let template = definition.clientMessageTemplates.first(where: { $0.id == templateID }) else {
            return .failure(.unknownTemplate)
        }

        let key = TopologyProtocolApplicationRuntimeKey(nodeID: nodeID, definitionID: definitionID)
        var client = runtimeProtocolApplicationClients[key]
            ?? TopologyProtocolApplicationClientState(socketID: nil, destinationIPAddress: destinationIPAddress)
        if client.destinationIPAddress != destinationIPAddress, let oldSocketID = client.socketID {
            closeProtocolApplicationClientSocket(socketID: oldSocketID, transport: definition.transport)
            client.socketID = nil
        }
        client.destinationIPAddress = destinationIPAddress

        let socketID: UUID
        switch definition.transport {
        case .tcp:
            if let existing = client.socketID,
               networkRuntime.state.socketsByID[existing]?.tcpState == .established,
               networkRuntime.state.socketsByID[existing]?.remoteIPAddress == destinationIPAddress,
               networkRuntime.state.socketsByID[existing]?.remotePort == definition.port {
                socketID = existing
            } else {
                if let existing = client.socketID {
                    closeProtocolApplicationClientSocket(socketID: existing, transport: .tcp)
                }
                guard let opened = networkRuntime.openTCPClientSocket(
                    nodeID: nodeID,
                    remoteIPAddress: destinationIPAddress,
                    remotePort: definition.port
                ) else {
                    client.appendLog(
                        time: networkRuntime.state.currentTimeMilliseconds,
                        direction: "error",
                        message: FiliusLocalization.t("protocol.runtime.unreachable")
                    )
                    runtimeProtocolApplicationClients[key] = client
                    return .failure(.unreachable)
                }
                guard networkRuntime.connectTCP(socketID: opened) else {
                    networkRuntime.discardSocket(socketID: opened)
                    client.appendLog(
                        time: networkRuntime.state.currentTimeMilliseconds,
                        direction: "error",
                        message: FiliusLocalization.t("protocol.runtime.unreachable")
                    )
                    runtimeProtocolApplicationClients[key] = client
                    return .failure(.unreachable)
                }
                socketID = opened
                client.socketID = opened
            }
        case .udp:
            if let existing = client.socketID { networkRuntime.closeSocket(socketID: existing) }
            guard let opened = networkRuntime.bindUDPSocket(
                nodeID: nodeID,
                remoteIPAddress: destinationIPAddress,
                remotePort: definition.port
            ) else { return .failure(.portInUse) }
            socketID = opened
            client.socketID = opened
        }

        let payload = Data(template.message.utf8)
        client.appendLog(time: networkRuntime.state.currentTimeMilliseconds, direction: "outbound", message: template.message)
        networkRuntime.recordTrace(
            nodeID: nodeID,
            interfaceID: networkRuntime.networkInterfaces(nodeID: nodeID).first?.portID,
            direction: .outbound,
            layer: .application,
            operation: .sent,
            afterHeaders: protocolApplicationTraceHeaders(definition: definition, lifecycle: "request"),
            detail: FiliusLocalization.t("protocol.runtime.trace.request")
        )
        let sendResult = networkRuntime.simpleClientSend(
            socketID: socketID,
            protocolKind: definition.transport,
            payload: payload
        )
        guard sendResult.succeeded else {
            client.appendLog(
                time: networkRuntime.state.currentTimeMilliseconds,
                direction: "error",
                message: FiliusLocalization.t("protocol.runtime.sendFailed")
            )
            runtimeProtocolApplicationClients[key] = client
            return .failure(.sendFailed)
        }

        _ = processProtocolApplicationServers()
        for serverNodeID in runtimeEchoServerByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            _ = pumpEchoServer(nodeID: serverNodeID)
        }
        for serverNodeID in runtimeWebServerByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            _ = processWebServerRequests(nodeID: serverNodeID)
        }

        let responseData: Data?
        if let immediate = sendResult.response {
            responseData = immediate
        } else {
            switch definition.transport {
            case .tcp:
                responseData = receiveProtocolApplicationTCPResponse(
                    runtime: &networkRuntime,
                    receive: { runtime in
                        runtime.receiveTCP(socketID: socketID)
                    },
                    advanceToTimeout: { runtime in
                        let deadline = runtime.state.currentTimeMilliseconds.addingReportingOverflow(
                            TopologyProtocolApplicationLimits.responseTimeoutMilliseconds
                        )
                        if !deadline.overflow {
                            _ = runtime.handle(.advance(toMilliseconds: deadline.partialValue))
                        }
                    }
                )
            case .udp:
                responseData = networkRuntime.receiveUDP(
                    socketID: socketID,
                    timeoutMilliseconds: TopologyProtocolApplicationLimits.responseTimeoutMilliseconds
                )?.datagram.payload
            }
        }
        simulationTick = max(simulationTick, networkRuntime.state.currentTimeMilliseconds)

        if let responseData {
            let response = String(data: responseData, encoding: .utf8) ?? FiliusLocalization.t("protocol.runtime.binary", responseData.count)
            client.appendLog(time: networkRuntime.state.currentTimeMilliseconds, direction: "inbound", message: response)
            networkRuntime.recordTrace(
                nodeID: nodeID,
                interfaceID: networkRuntime.networkInterfaces(nodeID: nodeID).first?.portID,
                direction: .inbound,
                layer: .application,
                operation: .received,
                afterHeaders: protocolApplicationTraceHeaders(definition: definition, lifecycle: "response"),
                detail: FiliusLocalization.t("protocol.runtime.trace.response")
            )
            runtimeProtocolApplicationClients[key] = client
            return .success(.init(response: response, timedOut: false))
        }

        client.appendLog(
            time: networkRuntime.state.currentTimeMilliseconds,
            direction: "timeout",
            message: FiliusLocalization.t("protocol.runtime.timeout")
        )
        runtimeProtocolApplicationClients[key] = client
        return .success(.init(response: nil, timedOut: true))
    }

    mutating func stopProtocolApplicationClient(nodeID: UUID, definitionID: UUID) {
        let key = TopologyProtocolApplicationRuntimeKey(nodeID: nodeID, definitionID: definitionID)
        guard let client = runtimeProtocolApplicationClients.removeValue(forKey: key) else { return }
        if let socketID = client.socketID,
           let definition = protocolApplicationDefinitionsByID[definitionID] {
            closeProtocolApplicationClientSocket(socketID: socketID, transport: definition.transport)
        }
    }

    mutating func stopProtocolApplicationRuntime(definitionID: UUID) {
        let serverKeys = runtimeProtocolApplicationServers.keys
            .filter { $0.definitionID == definitionID }
            .sorted { $0.nodeID.uuidString < $1.nodeID.uuidString }
        for key in serverKeys {
            stopProtocolApplicationServer(nodeID: key.nodeID, definitionID: definitionID)
        }
        let clientKeys = runtimeProtocolApplicationClients.keys.filter { $0.definitionID == definitionID }
        for key in clientKeys {
            if let socketID = runtimeProtocolApplicationClients[key]?.socketID,
               let definition = protocolApplicationDefinitionsByID[definitionID] {
                closeProtocolApplicationClientSocket(socketID: socketID, transport: definition.transport)
            }
            runtimeProtocolApplicationClients.removeValue(forKey: key)
        }
    }

    mutating func resetProtocolApplicationRuntime() {
        runtimeActiveProtocolApplicationIDByNodeID.removeAll()
        runtimeProtocolApplicationClients.removeAll()
        runtimeProtocolApplicationServers.removeAll()
    }

    private mutating func protocolApplicationResponse(
        for payload: Data,
        definition: TopologyProtocolApplicationDefinition,
        key: TopologyProtocolApplicationRuntimeKey,
        server: inout TopologyProtocolApplicationServerState
    ) -> Data? {
        let request = String(data: payload, encoding: .utf8)
        server.appendLog(
            time: networkRuntime.state.currentTimeMilliseconds,
            direction: "inbound",
            message: request ?? FiliusLocalization.t("protocol.runtime.binary", payload.count)
        )
        networkRuntime.recordTrace(
            nodeID: key.nodeID,
            interfaceID: networkRuntime.networkInterfaces(nodeID: key.nodeID).first?.portID,
            direction: .inbound,
            layer: .application,
            operation: .received,
            afterHeaders: protocolApplicationTraceHeaders(definition: definition, lifecycle: "request"),
            detail: FiliusLocalization.t("protocol.runtime.trace.requestReceived")
        )
        guard let request,
              let rule = definition.deterministicRules.first(where: { $0.request == request }) else {
            server.appendLog(
                time: networkRuntime.state.currentTimeMilliseconds,
                direction: "unmatched",
                message: FiliusLocalization.t("protocol.runtime.unmatched")
            )
            return nil
        }
        return Data(rule.response.utf8)
    }

    private mutating func recordProtocolApplicationResponse(
        _ response: Data,
        definition: TopologyProtocolApplicationDefinition,
        key: TopologyProtocolApplicationRuntimeKey,
        server: inout TopologyProtocolApplicationServerState
    ) {
        let responseText = String(data: response, encoding: .utf8) ?? FiliusLocalization.t("protocol.runtime.binary", response.count)
        server.appendLog(time: networkRuntime.state.currentTimeMilliseconds, direction: "outbound", message: responseText)
        networkRuntime.recordTrace(
            nodeID: key.nodeID,
            interfaceID: networkRuntime.networkInterfaces(nodeID: key.nodeID).first?.portID,
            direction: .outbound,
            layer: .application,
            operation: .sent,
            afterHeaders: protocolApplicationTraceHeaders(definition: definition, lifecycle: "response"),
            detail: FiliusLocalization.t("protocol.runtime.trace.firstMatchResponse")
        )
    }

    private func protocolApplicationTraceHeaders(
        definition: TopologyProtocolApplicationDefinition,
        lifecycle: String
    ) -> [TopologyPacketHeaderField] {
        [
            .init(name: "kind", value: "DECLARATIVE_PROTOCOL"),
            .init(name: "definitionID", value: definition.id.uuidString.lowercased()),
            .init(name: "transport", value: definition.transport.displayName),
            .init(name: "port", value: String(definition.port)),
            .init(name: "lifecycle", value: lifecycle),
        ]
    }

    private mutating func closeProtocolApplicationClientSocket(
        socketID: UUID,
        transport: TopologyRuntimeTransportProtocol
    ) {
        switch transport {
        case .tcp:
            _ = networkRuntime.closeTCPConnectionAndClean(socketID: socketID)
        case .udp:
            networkRuntime.closeSocket(socketID: socketID)
        }
        simulationTick = max(simulationTick, networkRuntime.state.currentTimeMilliseconds)
    }

    private mutating func clearSimpleClientSocketReferences(_ socketIDs: Set<UUID>) {
        guard !socketIDs.isEmpty else { return }
        for nodeID in runtimeSimpleClientByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard var client = runtimeSimpleClientByNodeID[nodeID],
                  let socketID = client.socketID,
                  socketIDs.contains(socketID) else { continue }
            client.socketID = nil
            client.connectionState = .disconnected
            client.appendLog(
                timestampMilliseconds: networkRuntime.state.currentTimeMilliseconds,
                direction: "system",
                message: FiliusLocalization.t("protocol.runtime.disconnected")
            )
            runtimeSimpleClientByNodeID[nodeID] = client
        }
    }

    private mutating func clearProtocolClientSocketReferences(_ socketIDs: Set<UUID>) {
        guard !socketIDs.isEmpty else { return }
        let keys = runtimeProtocolApplicationClients.keys.sorted {
            if $0.definitionID.uuidString == $1.definitionID.uuidString {
                return $0.nodeID.uuidString < $1.nodeID.uuidString
            }
            return $0.definitionID.uuidString < $1.definitionID.uuidString
        }
        for key in keys {
            guard var client = runtimeProtocolApplicationClients[key],
                  let socketID = client.socketID,
                  socketIDs.contains(socketID) else { continue }
            client.socketID = nil
            client.appendLog(
                time: networkRuntime.state.currentTimeMilliseconds,
                direction: "system",
                message: FiliusLocalization.t("protocol.runtime.disconnected")
            )
            runtimeProtocolApplicationClients[key] = client
        }
    }
}
