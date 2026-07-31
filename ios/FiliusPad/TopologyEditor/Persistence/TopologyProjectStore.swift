import CoreGraphics
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif


/// Coordinates persistence work on a dedicated queue.
///
/// `generation` is only accessed while `lock` is held, and `queue` is immutable.
/// Those invariants make cross-concurrency-domain access safe.
final class TopologyPersistenceSaveCoordinator: @unchecked Sendable {
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var generation: UInt64 = 0

    init(queue: DispatchQueue = DispatchQueue(label: "com.filius.pad.persistence-save", qos: .utility)) {
        self.queue = queue
    }

    var currentGeneration: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    @discardableResult
    func advanceGeneration() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation = generation == UInt64.max ? 1 : generation + 1
        return generation
    }

    func isCurrent(_ token: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == token
    }

    func perform(
        generation token: UInt64,
        operation: @escaping () throws -> Void
    ) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.isCurrent(token) else {
                    continuation.resume(returning: false)
                    return
                }
                do {
                    try operation()
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

struct TopologyPersistenceLifecycle: Equatable {
    private(set) var restoreGeneration: UInt64 = 0
    private(set) var isRestoringAutosave = false

    mutating func beginAutosaveRestore() -> UInt64 {
        advanceGeneration()
        isRestoringAutosave = true
        return restoreGeneration
    }

    mutating func invalidateForExternalStateReplacement() {
        advanceGeneration()
        isRestoringAutosave = false
    }

    func canApplyAutosaveRestore(_ token: UInt64) -> Bool {
        isRestoringAutosave && restoreGeneration == token
    }

    mutating func finishAutosaveRestore(_ token: UInt64) {
        guard restoreGeneration == token else {
            return
        }
        isRestoringAutosave = false
    }

    private mutating func advanceGeneration() {
        restoreGeneration = restoreGeneration == UInt64.max ? 1 : restoreGeneration + 1
    }
}

private func remappingVirtualFileSystemRoot(
    _ fileSystem: TopologyVirtualFileSystem,
    from sourceRoot: String,
    to destinationRoot: String
) throws -> TopologyVirtualFileSystem {
    let normalizedSource = try TopologyVirtualFileSystem.normalizedAbsolutePath(sourceRoot)
    let normalizedDestination = try TopologyVirtualFileSystem.normalizedAbsolutePath(destinationRoot)
    guard normalizedSource.caseInsensitiveCompare(normalizedDestination) != .orderedSame else {
        return fileSystem
    }

    let entries = fileSystem.allEntries().filter { $0.path != "/" }
    guard let actualSourceRoot = entries.first(where: {
        $0.path.caseInsensitiveCompare(normalizedSource) == .orderedSame && $0.content.isDirectory
    })?.path else {
        return fileSystem
    }

    func isInSubtree(_ path: String, root: String) -> Bool {
        let lowercasedPath = path.lowercased()
        let lowercasedRoot = root.lowercased()
        return lowercasedPath == lowercasedRoot || lowercasedPath.hasPrefix(lowercasedRoot + "/")
    }

    var remappedEntries: [TopologyVirtualFileEntry] = []
    for entry in entries {
        if isInSubtree(entry.path, root: normalizedDestination) {
            continue
        }
        if isInSubtree(entry.path, root: actualSourceRoot) {
            let suffix = String(entry.path.dropFirst(actualSourceRoot.count))
            remappedEntries.append(
                TopologyVirtualFileEntry(path: normalizedDestination + suffix, content: entry.content)
            )
        } else {
            remappedEntries.append(entry)
        }
    }
    return try TopologyVirtualFileSystem(entries: remappedEntries)

}

enum TopologyProjectPersistenceOperation: String, Equatable {
    case load
    case save
}

enum TopologyProjectPersistenceErrorCode: String, Equatable {
    case fileNotFound
    case fileReadFailed
    case fileWriteFailed
    case encodingFailed
    case corruptedPayload
    case malformedPayload
    case invalidFormat
    case unsupportedFormat
    case unsupportedSchemaVersion
}

struct TopologyProjectPersistenceError: Error, Equatable {
    let operation: TopologyProjectPersistenceOperation
    let code: TopologyProjectPersistenceErrorCode
    let detail: String
}

enum TopologyFLSCompatibilityErrorCode: String, Equatable {
    case malformedConfigurationXML
    case unsupportedConfigurationStructure
}

struct TopologyFLSCompatibilityError: Error, Equatable {
    let code: TopologyFLSCompatibilityErrorCode
    let detail: String
}

struct TopologyFLSImportReport: Equatable {
    let filiusVersion: String?
    let importedNodeCount: Int
    let importedLinkCount: Int
    let importedDocumentationItemCount: Int
    let skippedNodeCount: Int
    let warnings: [String]
}

struct TopologyFLSOpaqueContent: Equatable {
    static let empty = TopologyFLSOpaqueContent(
        sourceConfigurationXML: nil,
        recognizedNodeIDsBySourcePath: [:],
        recognizedLinkIDsBySourcePath: [:],
        recognizedDocumentationItemIDsBySourcePath: [:],
        residualCount: 0
    )

    let sourceConfigurationXML: Data?
    let recognizedNodeIDsBySourcePath: [TopologyFLSInertXMLPath: UUID]
    let recognizedLinkIDsBySourcePath: [TopologyFLSInertXMLPath: UUID]
    let recognizedDocumentationItemIDsBySourcePath: [TopologyFLSInertXMLPath: UUID]
    let residualCount: Int

    var isEmpty: Bool { sourceConfigurationXML == nil }
    var fragmentCount: Int { residualCount }
}

struct TopologyFLSImportResult: Equatable {
    let state: TopologyEditorState
    let report: TopologyFLSImportReport
    let opaqueContent: TopologyFLSOpaqueContent
}

struct TopologyFLSExportReport: Equatable {
    let exportedNodeCount: Int
    let exportedLinkCount: Int
    let exportedDocumentationItemCount: Int
    let warnings: [String]
}

struct TopologyFLSExportResult: Equatable {
    let data: Data
    let report: TopologyFLSExportReport
}

struct TopologyProjectStore {
    static let formatIdentifier = TopologyProjectEnvelope.formatIdentifier
    static let minimumSupportedSchemaVersion = 1
    static let supportedSchemaVersion = TopologyProjectEnvelope.currentSchemaVersion

    static func virtualFileSystemsForPersistence(
        from state: TopologyEditorState
    ) -> [UUID: TopologyVirtualFileSystem] {
        Dictionary(
            uniqueKeysWithValues: state.graph.nodes
                .filter { $0.kind.isPCClassEndpoint }
                .map { node in
                    (node.id, state.virtualFileSystemsByNodeID[node.id] ?? .defaultForDevice())
                }
        )
    }

    static func validateVirtualFileSystemsForPersistence(from state: TopologyEditorState) throws {
        try TopologyVirtualFileSystem.validateProjectQuotas(virtualFileSystemsForPersistence(from: state))
    }

    let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileURL: URL,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = TopologyProjectStore.makeEncoder(),
        decoder: JSONDecoder = TopologyProjectStore.makeDecoder()
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
    }

    func save(
        state: TopologyEditorState,
        savedAt: Date = Date(),
        saveReason: TopologyProjectSaveReason = .autosave
    ) throws {
        var state = state
        do {
            for nodeID in state.runtimeInstalledProgramsByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                let programs = state.runtimeInstalledProgramsByNodeID[nodeID] ?? []
                if programs.contains(.emailClient) {
                    try state.persistRuntimeEmailClientConfiguration(nodeID: nodeID)
                }
                if programs.contains(.emailServer) {
                    try state.persistRuntimeEmailServerConfiguration(nodeID: nodeID)
                }
            }
            try Self.validateVirtualFileSystemsForPersistence(from: state)
        } catch {
            throw makeError(
                operation: .save,
                code: .encodingFailed,
                detail: "Virtual filesystem persistence validation failed (including email mirrors): \(error.localizedDescription)"
            )
        }

        do {
            let definitions = state.protocolApplicationDefinitionsByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
            let installations = state.runtimeInstalledProtocolApplicationIDsByNodeID.flatMap { nodeID, definitionIDs in
                definitionIDs.map { TopologyProtocolApplicationInstallationSnapshot(nodeID: nodeID, definitionID: $0) }
            }
            try TopologyProtocolApplicationCatalog.validateDefinitions(definitions)
            try TopologyProtocolApplicationCatalog.validateInstallations(
                installations,
                definitions: definitions,
                graph: state.graph
            )
        } catch {
            throw makeError(
                operation: .save,
                code: .encodingFailed,
                detail: "Protocol application persistence validation failed: \(error)"
            )
        }

        let snapshot: TopologyProjectSnapshot
        do {
            snapshot = try TopologyProjectSnapshot(state: state)
        } catch {
            throw makeError(
                operation: .save,
                code: .encodingFailed,
                detail: "Failed to prepare topology project snapshot, including Gnutella configuration mirroring: \(describe(error: error))"
            )
        }

        let envelope = TopologyProjectEnvelope(
            format: Self.formatIdentifier,
            schemaVersion: Self.supportedSchemaVersion,
            savedAt: savedAt,
            saveReason: saveReason,
            payload: snapshot
        )

        let data: Data
        do {
            data = try encoder.encode(envelope)
        } catch {
            throw makeError(
                operation: .save,
                code: .encodingFailed,
                detail: "Failed to encode topology project envelope: \(describe(error: error))"
            )
        }

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw makeError(
                operation: .save,
                code: .fileWriteFailed,
                detail: "Failed to write topology project data: \(describe(error: error))"
            )
        }
    }

    func load() throws -> TopologyEditorState {
        let data = try readRawData()

        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw makeError(
                operation: .load,
                code: .corruptedPayload,
                detail: "Project payload is not valid JSON: \(describe(error: error))"
            )
        }

        let envelope: TopologyProjectEnvelope
        do {
            envelope = try decoder.decode(TopologyProjectEnvelope.self, from: data)
        } catch {
            let code: TopologyProjectPersistenceErrorCode
            if let decodingError = error as? DecodingError,
               case let .dataCorrupted(context) = decodingError,
               context.codingPath.contains(where: { $0.stringValue == "payload" }) {
                code = .corruptedPayload
            } else {
                code = .malformedPayload
            }

            throw makeError(
                operation: .load,
                code: code,
                detail: "Failed to decode topology project envelope: \(describe(error: error))"
            )
        }

        let normalizedFormat = envelope.format.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFormat.isEmpty else {
            throw makeError(
                operation: .load,
                code: .invalidFormat,
                detail: "Project envelope format must be non-empty"
            )
        }

        guard normalizedFormat == Self.formatIdentifier else {
            throw makeError(
                operation: .load,
                code: .unsupportedFormat,
                detail: "Unsupported project format '\(normalizedFormat)'; expected '\(Self.formatIdentifier)'"
            )
        }

        guard (Self.minimumSupportedSchemaVersion...Self.supportedSchemaVersion).contains(envelope.schemaVersion) else {
            throw makeError(
                operation: .load,
                code: .unsupportedSchemaVersion,
                detail: "Unsupported schemaVersion \(envelope.schemaVersion); expected \(Self.minimumSupportedSchemaVersion)...\(Self.supportedSchemaVersion)"
            )
        }

        do {
            var restoredState = try envelope.payload.toEditorState(schemaVersion: envelope.schemaVersion)
            restoredState.lastPersistenceSaveAt = envelope.savedAt
            return restoredState
        } catch {
            let code: TopologyProjectPersistenceErrorCode
            if let validationError = error as? TopologyProjectSnapshotValidationError {
                switch validationError {
                case .duplicateRuntimeInterfaceConfiguration,
                     .runtimeInterfaceConfigurationReferencesUnknownNode,
                     .runtimeInterfaceConfigurationReferencesUnknownPort,
                     .runtimeInterfaceConfigurationReferencesUnsupportedNodeKind,
                     .remoteLinkConfigurationReferencesUnknownNode,
                     .remoteLinkConfigurationReferencesUnsupportedNodeKind,
                     .runtimeWebServerConfigurationReferencesUnknownNode,
                     .runtimeWebServerConfigurationReferencesUnsupportedNodeKind,
                     .runtimeWebBrowserConfigurationReferencesUnknownNode,
                     .runtimeWebBrowserConfigurationReferencesUnsupportedNodeKind,
                     .virtualFileSystemReferencesUnknownNode,
                     .virtualFileSystemReferencesUnsupportedNodeKind:
                    code = .corruptedPayload
                default:
                    code = .malformedPayload
                }
            } else {
                code = .malformedPayload
            }

            throw makeError(
                operation: .load,
                code: code,
                detail: "Decoded snapshot failed validation: \(describe(error: error))"
            )
        }
    }

    static func importFiliusConfigurationXML(_ xmlData: Data) throws -> TopologyFLSImportResult {
        try TopologyFLSOpaqueXMLPreserver.preflight(xmlData)
        let inspection = try TopologyFLSOpaqueXMLPreserver.inspect(from: xmlData)
        let parser = TopologyFLSConfigurationParser(data: xmlData, semanticPlan: inspection.semanticPlan)
        let parseResult = try parser.parse()
        let opaqueContent = try inspection.content(
            recognizedNodeIDsBySourcePath: parseResult.recognizedNodeIDsBySourcePath,
            recognizedLinkIDsBySourcePath: parseResult.recognizedLinkIDsBySourcePath,
            recognizedDocumentationItemIDsBySourcePath: parseResult.recognizedDocumentationItemIDsBySourcePath
        )

        var state = TopologyEditorState()
        state.graph = TopologyGraph(nodes: parseResult.nodes, links: parseResult.links)
        state.seedJavaRuntimeInterfaceDefaultsForGraph()
        state.runtimeDeviceConfigurations = parseResult.runtimeDeviceConfigurations
        state.switchConfigurationsByNodeID = parseResult.switchConfigurationsByNodeID
        state.remoteLinkConfigurationsByNodeID = parseResult.remoteLinkConfigurationsByNodeID
        state.hostWirelessConfigurationsByNodeID = parseResult.hostWirelessConfigurationsByNodeID
        state.seedJavaRuntimeInterfaceDefaultsForGraph()
        for (key, configuration) in parseResult.runtimeInterfaceConfigurations {
            state.runtimeInterfaceConfigurations[key] = configuration
        }
        state.runtimeManualRoutesByNodeID = parseResult.runtimeManualRoutesByNodeID
        state.runtimeRIPEnabledByNodeID = parseResult.runtimeRIPEnabledByNodeID
        state.runtimeDHCPClientConfigurationsByNodeID = parseResult.runtimeDHCPClientConfigurationsByNodeID
        state.runtimeDHCPServerConfigurationsByNodeID = parseResult.runtimeDHCPServerConfigurationsByNodeID
        state.runtimeFirewallConfigurationsByNodeID = parseResult.runtimeFirewallConfigurationsByNodeID
        state.runtimePortForwardingRowsByNodeID = parseResult.runtimePortForwardingRowsByNodeID
        state.virtualFileSystemsByNodeID = parseResult.virtualFileSystemsByNodeID
        state.runtimeInstalledProgramsByNodeID = parseResult.runtimeInstalledProgramsByNodeID
        state.runtimeWebServerConfigurationsByNodeID = parseResult.runtimeWebServerConfigurationsByNodeID
        state.runtimeEmailClientConfigurationsByNodeID = parseResult.runtimeEmailClientConfigurationsByNodeID
        state.runtimeEmailServerConfigurationsByNodeID = parseResult.runtimeEmailServerConfigurationsByNodeID
        for node in state.graph.nodes where node.kind.isPCClassEndpoint && state.virtualFileSystemsByNodeID[node.id] == nil {
            state.virtualFileSystemsByNodeID[node.id] = .defaultForDevice()
        }
        for nodeID in state.runtimeInstalledProgramsByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString })
            where state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(.dnsServer) == true {
            state.runtimeDNSServerConfigurationsByNodeID[nodeID] = TopologyRuntimeDNSServerConfiguration()
            state.synchronizeRuntimeDNSConfigurationFromHostsFile(nodeID: nodeID)
        }
        var importWarnings = parseResult.warnings
        if opaqueContent.fragmentCount > 0 {
            importWarnings.append(
                "Preserved unknown JavaBean/XML residual data inertly for the next explicit FILIUS save."
            )
        }
        for nodeID in state.runtimeInstalledProgramsByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString })
            where state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(.gnutella) == true {
            do {
                try state.synchronizeRuntimeGnutellaConfigurationFromFileSystem(nodeID: nodeID)
            } catch {
                state.runtimeGnutellaConfigurationsByNodeID[nodeID] = TopologyRuntimeGnutellaConfiguration()
                try? state.persistRuntimeGnutellaConfiguration(nodeID: nodeID)
                let nodeName = state.graph.node(withID: nodeID)?.displayName ?? nodeID.uuidString
                importWarnings.append(
                    "Gnutella configuration on '\(nodeName)' was malformed and reset to the Java-compatible default."
                )
            }
        }
        for nodeID in state.runtimeInstalledProgramsByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            let programs = state.runtimeInstalledProgramsByNodeID[nodeID] ?? []
            let nodeName = state.graph.node(withID: nodeID)?.displayName ?? nodeID.uuidString
            if programs.contains(.emailClient), state.runtimeEmailClientConfigurationsByNodeID[nodeID] != nil {
                do {
                    try state.persistRuntimeEmailClientConfiguration(nodeID: nodeID)
                } catch {
                    state.runtimeEmailClientConfigurationsByNodeID.removeValue(forKey: nodeID)
                    importWarnings.append(
                        "Email Client on '\(nodeName)' was installed, but its oversized or malformed account state was rejected before persistence."
                    )
                }
            }
            if programs.contains(.emailServer), state.runtimeEmailServerConfigurationsByNodeID[nodeID] != nil {
                do {
                    try state.persistRuntimeEmailServerConfiguration(nodeID: nodeID)
                } catch {
                    state.runtimeEmailServerConfigurationsByNodeID.removeValue(forKey: nodeID)
                    importWarnings.append(
                        "Email Server on '\(nodeName)' was installed, but its oversized or malformed account/mailbox state was rejected before persistence."
                    )
                }
            }
        }
        do {
            try validateVirtualFileSystemsForPersistence(from: state)
        } catch {
            throw TopologyFLSCompatibilityError(
                code: .unsupportedConfigurationStructure,
                detail: "Imported Java virtual filesystems exceed supported quotas: \(error.localizedDescription)"
            )
        }
        state.documentationItems = parseResult.documentationItems.inDeterministicRenderOrder

        let report = TopologyFLSImportReport(
            filiusVersion: parseResult.filiusVersion,
            importedNodeCount: parseResult.nodes.count,
            importedLinkCount: parseResult.links.count,
            importedDocumentationItemCount: parseResult.documentationItems.count,
            skippedNodeCount: parseResult.skippedNodeCount,
            warnings: importWarnings
        )

        return TopologyFLSImportResult(state: state, report: report, opaqueContent: opaqueContent)
    }

    static func exportFiliusConfigurationXML(
        from state: TopologyEditorState,
        filiusVersion: String = "Filius version: 2.1.0 (iPad compatibility export)"
    ) throws -> Data {
        try exportFiliusConfigurationXMLWithReport(from: state, filiusVersion: filiusVersion).data
    }

    static func exportFiliusConfigurationXMLWithReport(
        from inputState: TopologyEditorState,
        filiusVersion: String = "Filius version: 2.1.0 (iPad compatibility export)"
    ) throws -> TopologyFLSExportResult {
        var state = inputState
        var exportWarnings: [String] = []
        for nodeID in state.runtimeInstalledProgramsByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString })
            where state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(.dnsServer) == true {
            if state.virtualFileSystemsByNodeID[nodeID]?.contains(TopologyRuntimeDNSHostsFile.path) == true {
                state.synchronizeRuntimeDNSConfigurationFromHostsFile(nodeID: nodeID)
            } else {
                try? state.mirrorRuntimeDNSConfigurationToHostsFile(nodeID: nodeID)
            }
        }
        for nodeID in state.runtimeInstalledProgramsByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            let programs = state.runtimeInstalledProgramsByNodeID[nodeID] ?? []
            let nodeName = state.graph.node(withID: nodeID)?.displayName ?? nodeID.uuidString
            if programs.contains(.emailClient) {
                if state.runtimeEmailClientConfigurationsByNodeID[nodeID] != nil {
                    do {
                        try state.persistRuntimeEmailClientConfiguration(nodeID: nodeID)
                    } catch {
                        exportWarnings.append(
                            "Could not mirror Email Client configuration to /konten.txt on '\(nodeName)'."
                        )
                    }
                } else {
                    exportWarnings.append(
                        "Email Client on '\(nodeName)' has no account configuration; exported the installed application without an EmailKonto bean."
                    )
                }
            }
            if programs.contains(.emailServer) {
                if state.runtimeEmailServerConfigurationsByNodeID[nodeID] != nil {
                    do {
                        try state.persistRuntimeEmailServerConfiguration(nodeID: nodeID)
                    } catch {
                        exportWarnings.append(
                            "Could not mirror Email Server configuration to /mailserver/konten.txt on '\(nodeName)'."
                        )
                    }
                } else {
                    exportWarnings.append(
                        "Email Server on '\(nodeName)' has no account configuration; exported the installed application with default domain fields."
                    )
                }
            }
        }
        let sortedNodes = state.graph.nodes
            .filter { $0.kind != .unsupported }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let exportedNodeIDs = Set(sortedNodes.map(\.id))

        var portReferenceByID: [UUID: String] = [:]
        var portOwnerByID: [UUID: UUID] = [:]
        var guiReferenceByNodeID: [UUID: String] = [:]
        var nextPortReference = 0

        for (nodeIndex, node) in sortedNodes.enumerated() {
            guiReferenceByNodeID[node.id] = "GUIKnotenItem\(nodeIndex)"
            for port in node.ports {
                portReferenceByID[port.id] = "Port\(nextPortReference)"
                portOwnerByID[port.id] = node.id
                nextPortReference += 1
            }
        }

        func hardwareClass(for kind: TopologyNodeKind) -> String {
            switch kind {
            case .pc:
                return "filius.hardware.knoten.Rechner"
            case .notebook:
                return "filius.hardware.knoten.Notebook"
            case .networkSwitch:
                return "filius.hardware.knoten.Switch"
            case .router:
                return "filius.hardware.knoten.Vermittlungsrechner"
            case .gateway:
                return "filius.hardware.knoten.Gateway"
            case .remoteLink:
                return "filius.hardware.knoten.Modem"
            case .unsupported:
                return ""
            }
        }

        func typeLabel(for kind: TopologyNodeKind) -> String {
            switch kind {
            case .pc:
                return "Computer"
            case .notebook:
                return "Notebook"
            case .networkSwitch:
                return "Switch"
            case .router:
                return "Vermittlungsrechner"
            case .gateway:
                return "Gateway"
            case .remoteLink:
                return "Modem"
            case .unsupported:
                return "Unsupported"
            }
        }

        func interfaceConfiguration(
            node: TopologyNode,
            port: TopologyPortMetadata,
            index: Int
        ) -> (ipAddress: String, subnetMask: String, defaultGateway: String, dnsServer: String) {
            if node.kind.isPCClassEndpoint {
                let configuration = state.runtimeDeviceConfigurations[node.id]
                return (
                    configuration?.ipAddress ?? "192.168.0.10",
                    configuration?.subnetMask ?? "255.255.255.0",
                    configuration?.defaultGateway ?? "",
                    configuration?.dnsServer ?? ""
                )
            }

            let key = TopologyRuntimeInterfaceKey(nodeID: node.id, portID: port.id)
            if let configuration = state.runtimeInterfaceConfigurations[key] {
                let deviceConfiguration = state.runtimeDeviceConfigurations[node.id]
                let exportsGatewaySettings = node.kind == .gateway && index == 0
                return (
                    configuration.ipAddress,
                    configuration.subnetMask,
                    exportsGatewaySettings ? deviceConfiguration?.defaultGateway ?? "" : "",
                    exportsGatewaySettings ? deviceConfiguration?.dnsServer ?? "" : ""
                )
            }

            if node.kind == .gateway, index == 0 {
                return ("42.0.0.10", "255.0.0.0", "", "")
            }
            return ("192.168.0.10", "255.255.255.0", "", "")
        }

        let remoteNodesByPairIdentifier = Dictionary(grouping: sortedNodes.filter { $0.kind == .remoteLink }) { node in
            let configuration = state.remoteLinkConfigurationsByNodeID[node.id]
                ?? .defaultConfiguration(nodeID: node.id)
            let identifier = configuration.pairIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            return identifier.isEmpty ? "unpaired-\(node.id.uuidString.lowercased())" : identifier
        }
        let sortedRemotePairIdentifiers = remoteNodesByPairIdentifier.keys.sorted()
        var remotePortByPairIdentifier: [String: Int] = [:]
        var usedRemotePorts: Set<Int> = []

        func explicitJavaModemPort(from pairIdentifier: String) -> Int? {
            let prefix = "java-modem-port-"
            guard pairIdentifier.lowercased().hasPrefix(prefix) else { return nil }
            let suffix = String(pairIdentifier.dropFirst(prefix.count))
            guard let port = Int(suffix), (1...65_535).contains(port) else { return nil }
            return port
        }

        func stableRemotePort(for pairIdentifier: String) -> Int {
            var hash: UInt64 = 14_695_981_039_346_656_037
            for byte in pairIdentifier.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
            return 20_000 + Int(hash % 40_000)
        }

        for pairIdentifier in sortedRemotePairIdentifiers {
            var port = explicitJavaModemPort(from: pairIdentifier) ?? stableRemotePort(for: pairIdentifier)
            while usedRemotePorts.contains(port) {
                port = port == 65_535 ? 20_000 : port + 1
            }
            remotePortByPairIdentifier[pairIdentifier] = port
            usedRemotePorts.insert(port)
        }

        let nativeDefinitionCount = state.protocolApplicationDefinitionsByID.count
        let nativeInstallationCount = state.runtimeInstalledProtocolApplicationIDsByNodeID.values.reduce(0) { $0 + $1.count }
        if nativeDefinitionCount > 0 || nativeInstallationCount > 0 {
            exportWarnings.append(
                FiliusLocalization.t("protocol.compatibility.fls.omitted", nativeDefinitionCount, nativeInstallationCount)
            )
        }
        let shouldExportVirtualFileSystems: Bool
        do {
            try validateVirtualFileSystemsForPersistence(from: state)
            shouldExportVirtualFileSystems = true
        } catch {
            shouldExportVirtualFileSystems = false
            exportWarnings.append(
                "Skipped Java virtual filesystems because project quotas were exceeded: \(error.localizedDescription)"
            )
        }

        let lines = TopologyFLSNativeXMLSink()
        func escapedXML(_ value: String, context: String = "Java export field") -> String {
            lines.registerEscapedText(value, context: context)
        }

        func javaEmailNameComponents(_ name: String) -> (first: String, last: String) {
            let components = name.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let first = components.first else { return ("", "") }
            return (first, components.dropFirst().joined(separator: " "))
        }

        func appendJavaEmailAccountBean(
            username: String,
            password: String,
            name: String,
            emailAddress: String?,
            pop3Host: String? = nil,
            pop3Port: Int? = nil,
            smtpHost: String? = nil,
            smtpPort: Int? = nil,
            node: TopologyNode,
            indent: String,
            to lines: TopologyFLSNativeXMLSink
        ) {
            let names = javaEmailNameComponents(name)
            lines.append("\(indent)<object class=\"filius.software.email.EmailKonto\">")
            lines.append("\(indent) <void property=\"benutzername\"><string>\(escapedXML(username, context: "Email account username on '\(node.displayName)'"))</string></void>")
            if let emailAddress {
                lines.append("\(indent) <void property=\"emailAdresse\"><string>\(escapedXML(emailAddress, context: "Email account address on '\(node.displayName)'"))</string></void>")
            }
            lines.append("\(indent) <void property=\"nachname\"><string>\(escapedXML(names.last, context: "Email account last name on '\(node.displayName)'"))</string></void>")
            lines.append("\(indent) <void property=\"passwort\"><string>\(escapedXML(password, context: "Email account password on '\(node.displayName)'"))</string></void>")
            if let pop3Port {
                lines.append("\(indent) <void property=\"pop3port\"><string>\(pop3Port)</string></void>")
            }
            if let pop3Host {
                lines.append("\(indent) <void property=\"pop3server\"><string>\(escapedXML(pop3Host, context: "Email POP3 host on '\(node.displayName)'"))</string></void>")
            }
            if let smtpPort {
                lines.append("\(indent) <void property=\"smtpport\"><string>\(smtpPort)</string></void>")
            }
            if let smtpHost {
                lines.append("\(indent) <void property=\"smtpserver\"><string>\(escapedXML(smtpHost, context: "Email SMTP host on '\(node.displayName)'"))</string></void>")
            }
            lines.append("\(indent) <void property=\"vorname\"><string>\(escapedXML(names.first, context: "Email account first name on '\(node.displayName)'"))</string></void>")
            lines.append("\(indent)</object>")
        }

        func appendJavaFileSystem(
            _ fileSystem: TopologyVirtualFileSystem,
            node: TopologyNode,
            to lines: TopologyFLSNativeXMLSink
        ) {
            func appendEntry(_ entry: TopologyVirtualFileEntry, indent: String) {
                let escapedEntryName = escapedXML(
                    entry.name,
                    context: "virtual filesystem path '\(entry.path)' on node '\(node.displayName)'"
                )
                lines.append("\(indent)<void method=\"add\">")
                lines.append("\(indent) <object class=\"javax.swing.tree.DefaultMutableTreeNode\">")
                lines.append("\(indent)  <void property=\"userObject\">")
                switch entry.content {
                case .directory:
                    lines.append("\(indent)   <string>\(escapedEntryName)</string>")
                    lines.append("\(indent)  </void>")
                    for child in (try? fileSystem.entries(in: entry.path)) ?? [] {
                        appendEntry(child, indent: indent + "  ")
                    }
                case let .text(text):
                    let extensionValue = (entry.name as NSString).pathExtension.lowercased()
                    let javaType = extensionValue == "html" || extensionValue == "htm" ? "html" : "text/txt"
                    let escapedText = escapedXML(
                        text,
                        context: "virtual text file '\(entry.path)' on node '\(node.displayName)'"
                    )
                    lines.append("\(indent)   <object class=\"filius.software.system.Datei\">")
                    lines.append("\(indent)    <void property=\"dateiInhalt\"><string>\(escapedText)</string></void>")
                    lines.append("\(indent)    <void property=\"dateiTyp\"><string>\(javaType)</string></void>")
                    lines.append("\(indent)    <void property=\"name\"><string>\(escapedEntryName)</string></void>")
                    lines.append("\(indent)   </object>")
                    lines.append("\(indent)  </void>")
                case let .binary(data, mediaType):
                    let extensionValue = (entry.name as NSString).pathExtension
                    let javaType = extensionValue.isEmpty
                        ? mediaType?.split(separator: "/").last.map(String.init) ?? "binary"
                        : extensionValue
                    lines.append("\(indent)   <object class=\"filius.software.system.Datei\">")
                    lines.append("\(indent)    <void property=\"dateiInhalt\"><string>\(data.base64EncodedString())</string></void>")
                    lines.append("\(indent)    <void property=\"dateiTyp\"><string>\(escapedXML(javaType))</string></void>")
                    lines.append("\(indent)    <void property=\"name\"><string>\(escapedEntryName)</string></void>")
                    lines.append("\(indent)   </object>")
                    lines.append("\(indent)  </void>")
                case let .image(data, _):
                    let extensionValue = (entry.name as NSString).pathExtension
                    let javaType = extensionValue.isEmpty ? "image" : extensionValue
                    lines.append("\(indent)   <object class=\"filius.software.system.Datei\">")
                    lines.append("\(indent)    <void property=\"dateiInhalt\"><string>\(data.base64EncodedString())</string></void>")
                    lines.append("\(indent)    <void property=\"dateiTyp\"><string>\(escapedXML(javaType))</string></void>")
                    lines.append("\(indent)    <void property=\"name\"><string>\(escapedEntryName)</string></void>")
                    lines.append("\(indent)   </object>")
                    lines.append("\(indent)  </void>")
                }
                lines.append("\(indent) </object>")
                lines.append("\(indent)</void>")
            }

            lines.append("       <void property=\"dateisystem\">")
            lines.append("        <void property=\"arbeitsVerzeichnis\">")
            for entry in (try? fileSystem.entries(in: "/")) ?? [] {
                appendEntry(entry, indent: "         ")
            }
            lines.append("        </void>")
            lines.append("       </void>")
        }

        for pairIdentifier in sortedRemotePairIdentifiers {
            let nodes = (remoteNodesByPairIdentifier[pairIdentifier] ?? []).sorted { $0.id.uuidString < $1.id.uuidString }
            let configurations = nodes.map {
                state.remoteLinkConfigurationsByNodeID[$0.id] ?? .defaultConfiguration(nodeID: $0.id)
            }
            if nodes.count != 2 {
                exportWarnings.append(
                    "Remote Link pair '\(pairIdentifier)' contains \(nodes.count) node(s); Java Modem accepts one server connection, so pairing semantics are not preserved."
                )
            }
            if configurations.contains(where: { $0.latencyMilliseconds != TopologyRemoteLinkConfiguration.defaultLatencyMilliseconds }) {
                exportWarnings.append(
                    "Remote Link pair '\(pairIdentifier)' uses native latency; Java Modem export cannot represent latencyMilliseconds."
                )
            }
            if configurations.contains(where: { !$0.isEnabled }) {
                exportWarnings.append(
                    "Remote Link pair '\(pairIdentifier)' contains a disabled endpoint; Java Modem export cannot preserve link-up state."
                )
            }
            exportWarnings.append(
                "Remote Link pair '\(pairIdentifier)' is exported through deterministic Java Modem port \(remotePortByPairIdentifier[pairIdentifier] ?? 0); native pair semantics and cross-host identity are not represented by Java Modem."
            )
        }

        func remoteMode(for node: TopologyNode) -> Int {
            let configuration = state.remoteLinkConfigurationsByNodeID[node.id]
                ?? .defaultConfiguration(nodeID: node.id)
            let pairIdentifier = configuration.pairIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "unpaired-\(node.id.uuidString.lowercased())"
                : configuration.pairIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let nodes = (remoteNodesByPairIdentifier[pairIdentifier] ?? []).sorted { $0.id.uuidString < $1.id.uuidString }
            return nodes.first?.id == node.id ? 1 : 2
        }

        func remotePort(for node: TopologyNode) -> Int {
            let configuration = state.remoteLinkConfigurationsByNodeID[node.id]
                ?? .defaultConfiguration(nodeID: node.id)
            let pairIdentifier = configuration.pairIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "unpaired-\(node.id.uuidString.lowercased())"
                : configuration.pairIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            return remotePortByPairIdentifier[pairIdentifier] ?? 12_345
        }

        lines.append(contentsOf: [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<java version=\"11.0.17\" class=\"java.beans.XMLDecoder\">",
            " <string>\(escapedXML(filiusVersion))</string>",
            " <object class=\"java.util.LinkedList\">"
        ])

        for (nodeIndex, node) in sortedNodes.enumerated() {
            let label = node.displayName
            let x = Int(node.position.x.rounded())
            let y = Int(node.position.y.rounded())
            let guiReference = guiReferenceByNodeID[node.id] ?? "GUIKnotenItem\(nodeIndex)"

            lines.append("  <void method=\"add\">")
            lines.append("   <object id=\"\(guiReference)\" class=\"filius.gui.netzwerksicht.GUIKnotenItem\">")
            lines.append("    <void property=\"typ\"><string>\(escapedXML(typeLabel(for: node.kind)))</string></void>")
            lines.append("    <void property=\"imageLabel\">")
            lines.append("     <object class=\"filius.gui.netzwerksicht.JSidebarButton\">")
            lines.append("      <void property=\"bounds\"><object class=\"java.awt.Rectangle\"><int>\(x)</int><int>\(y)</int><int>70</int><int>68</int></object></void>")
            lines.append("      <void property=\"text\"><string>\(escapedXML(label))</string></void>")
            lines.append("     </object>")
            lines.append("    </void>")
            lines.append("    <void property=\"knoten\">")
            lines.append("     <object class=\"\(hardwareClass(for: node.kind))\">")
            lines.append("      <void property=\"name\"><string>\(escapedXML(label))</string></void>")

            if node.kind == .networkSwitch || node.kind == .remoteLink {
                lines.append("      <void property=\"anschluesse\">")
                let portsToExport = node.kind == .remoteLink ? Array(node.ports.prefix(1)) : node.ports
                for (portIndex, port) in portsToExport.enumerated() {
                    guard let portReference = portReferenceByID[port.id] else { continue }
                    lines.append("       <void id=\"\(portReference)\" index=\"\(portIndex)\"/>")
                }
                lines.append("      </void>")
            } else {
                lines.append("      <void property=\"netzwerkInterfaces\">")
                for (interfaceIndex, port) in node.ports.enumerated() {
                    guard let portReference = portReferenceByID[port.id] else { continue }
                    let configuration = interfaceConfiguration(node: node, port: port, index: interfaceIndex)
                    let constructorInterfaceCount = node.kind == .gateway ? 2 : 1
                    let usesExistingInterface = interfaceIndex < constructorInterfaceCount

                    if usesExistingInterface {
                        lines.append("       <void index=\"\(interfaceIndex)\">")
                    } else {
                        lines.append("       <void method=\"add\">")
                        lines.append("        <object class=\"filius.hardware.NetzwerkInterface\">")
                    }

                    let indent = usesExistingInterface ? "        " : "         "
                    lines.append("\(indent)<void property=\"ip\"><string>\(escapedXML(configuration.ipAddress))</string></void>")
                    lines.append("\(indent)<void property=\"subnetzMaske\"><string>\(escapedXML(configuration.subnetMask))</string></void>")
                    if !configuration.defaultGateway.isEmpty {
                        lines.append("\(indent)<void property=\"gateway\"><string>\(escapedXML(configuration.defaultGateway))</string></void>")
                    }
                    if !configuration.dnsServer.isEmpty {
                        lines.append("\(indent)<void property=\"dns\"><string>\(escapedXML(configuration.dnsServer))</string></void>")
                    }
                    if node.kind.isPCClassEndpoint, state.hostWirelessConfigurationsByNodeID[node.id]?.isEnabled == true {
                        lines.append("\(indent)<void property=\"wireless\"><boolean>true</boolean></void>")
                    }
                    lines.append("\(indent)<void id=\"\(portReference)\" property=\"port\"/>")

                    if usesExistingInterface {
                        lines.append("       </void>")
                    } else {
                        lines.append("        </object>")
                        lines.append("       </void>")
                    }
                }
                lines.append("      </void>")
            }

            let manualRoutes = state.runtimeManualRoutesByNodeID[node.id] ?? []
            let ripEnabled = node.kind == .router && state.runtimeRIPEnabledByNodeID[node.id] == true
            let dhcpClientEnabled = (node.kind.isPCClassEndpoint || node.kind == .gateway)
                && state.runtimeDHCPClientConfigurationsByNodeID[node.id]?.isEnabled == true
            let dhcpServer = (node.kind.isPCClassEndpoint || node.kind == .gateway)
                ? state.runtimeDHCPServerConfigurationsByNodeID[node.id] : nil
            let personalFirewallInstalled = node.kind.isPCClassEndpoint
                && state.runtimeInstalledProgramsByNodeID[node.id]?.contains(.firewall) == true
            let firewall: TopologyFirewallConfiguration?
            if personalFirewallInstalled {
                firewall = state.runtimeFirewallConfigurationsByNodeID[node.id]
                    ?? TopologyFirewallConfiguration.javaPersonalDefaults
            } else if node.kind == .router || node.kind == .gateway {
                firewall = state.runtimeFirewallConfigurationsByNodeID[node.id]
            } else {
                firewall = nil
            }
            let portForwardingRows = node.kind == .gateway
                ? state.runtimePortForwardingRowsByNodeID[node.id] ?? [] : []
            let switchConfiguration = node.kind == .networkSwitch
                ? state.switchConfigurationsByNodeID[node.id] ?? .defaultConfiguration(nodeID: node.id) : nil
            let remoteLinkConfiguration = node.kind == .remoteLink
                ? state.remoteLinkConfigurationsByNodeID[node.id] ?? .defaultConfiguration(nodeID: node.id) : nil
            let hostWirelessConfiguration = node.kind.isPCClassEndpoint
                ? state.hostWirelessConfigurationsByNodeID[node.id] : nil
            let dnsServerInstalled = node.kind.isPCClassEndpoint
                && state.runtimeInstalledProgramsByNodeID[node.id]?.contains(.dnsServer) == true
            let webServerInstalled = node.kind.isPCClassEndpoint
                && state.runtimeInstalledProgramsByNodeID[node.id]?.contains(.webServer) == true
            let webBrowserInstalled = node.kind.isPCClassEndpoint
                && state.runtimeInstalledProgramsByNodeID[node.id]?.contains(.webBrowser) == true
            let emailClientInstalled = node.kind.isPCClassEndpoint
                && state.runtimeInstalledProgramsByNodeID[node.id]?.contains(.emailClient) == true
            let emailServerInstalled = node.kind.isPCClassEndpoint
                && state.runtimeInstalledProgramsByNodeID[node.id]?.contains(.emailServer) == true
            let gnutellaInstalled = node.kind.isPCClassEndpoint
                && state.runtimeInstalledProgramsByNodeID[node.id]?.contains(.gnutella) == true
            let nativeVirtualFileSystem = node.kind.isPCClassEndpoint && shouldExportVirtualFileSystems
                ? state.virtualFileSystemsByNodeID[node.id] ?? .defaultForDevice() : nil
            let virtualFileSystem: TopologyVirtualFileSystem?
            if webServerInstalled, let nativeVirtualFileSystem {
                do {
                    virtualFileSystem = try remappingVirtualFileSystemRoot(
                        nativeVirtualFileSystem,
                        from: TopologyRuntimeWebServerConfiguration.defaultDocumentRoot,
                        to: "/webserver"
                    )
                } catch {
                    virtualFileSystem = nativeVirtualFileSystem
                    exportWarnings.append(
                        "Could not map native web root '/www' to Java '/webserver' on '\(node.displayName)': \(error.localizedDescription)"
                    )
                }
            } else {
                virtualFileSystem = nativeVirtualFileSystem
            }
            if !manualRoutes.isEmpty || ripEnabled || dhcpClientEnabled || dhcpServer != nil || firewall != nil
                || !portForwardingRows.isEmpty || switchConfiguration != nil || remoteLinkConfiguration != nil
                || hostWirelessConfiguration?.isEnabled == true || virtualFileSystem != nil || dnsServerInstalled || webServerInstalled || webBrowserInstalled
                || emailClientInstalled || emailServerInstalled || gnutellaInstalled || personalFirewallInstalled {
                lines.append("      <void property=\"systemSoftware\">")
                if remoteLinkConfiguration != nil {
                    let mode = remoteMode(for: node)
                    lines.append("       <void property=\"mode\"><int>\(mode)</int></void>")
                    lines.append("       <void property=\"port\"><int>\(remotePort(for: node))</int></void>")
                    if mode == 2 {
                        lines.append("       <void property=\"ipAdresse\"><string>localhost</string></void>")
                    }
                }
                if let switchConfiguration {
                    lines.append("       <void property=\"SSID\"><string>\(escapedXML(switchConfiguration.ssid))</string></void>")
                    lines.append("       <void property=\"retentionTime\"><long>\(switchConfiguration.retentionTimeMilliseconds)</long></void>")
                }
                if let hostWirelessConfiguration, hostWirelessConfiguration.isEnabled {
                    lines.append("       <void property=\"ssid\"><string>\(escapedXML(hostWirelessConfiguration.ssid))</string></void>")
                }
                if let virtualFileSystem {
                    appendJavaFileSystem(virtualFileSystem, node: node, to: lines)
                }
                if webServerInstalled || webBrowserInstalled {
                    lines.append("       <void property=\"installierteAnwendungen\">")
                    if webServerInstalled {
                        lines.append("        <void method=\"put\">")
                        lines.append("         <string>filius.software.www.WebServer</string>")
                        lines.append("         <object class=\"filius.software.www.WebServer\">")
                        lines.append("          <void property=\"port\"><int>\(state.runtimeWebServerConfigurationsByNodeID[node.id]?.port ?? 80)</int></void>")
                        lines.append("         </object>")
                        lines.append("        </void>")
                    }
                    if webBrowserInstalled {
                        lines.append("        <void method=\"put\">")
                        lines.append("         <string>filius.software.www.WebBrowser</string>")
                        lines.append("         <object class=\"filius.software.www.WebBrowser\">")
                        lines.append("         </object>")
                        lines.append("        </void>")
                    }
                    lines.append("       </void>")
                }
                if emailClientInstalled || emailServerInstalled {
                    lines.append("       <void property=\"installierteAnwendungen\">")
                    if emailClientInstalled {
                        lines.append("        <void method=\"put\">")
                        lines.append("         <string>filius.software.email.EmailAnwendung</string>")
                        lines.append("         <object class=\"filius.software.email.EmailAnwendung\">")
                        if let configuration = state.runtimeEmailClientConfigurationsByNodeID[node.id] {
                            lines.append("          <void property=\"kontoListe\">")
                            lines.append("           <void method=\"put\">")
                            lines.append("            <string>\(escapedXML(configuration.email, context: "Email Client map key on '\(node.displayName)'"))</string>")
                            appendJavaEmailAccountBean(
                                username: configuration.username,
                                password: configuration.password,
                                name: configuration.name,
                                emailAddress: configuration.email,
                                pop3Host: configuration.pop3Host,
                                pop3Port: configuration.pop3Port,
                                smtpHost: configuration.smtpHost,
                                smtpPort: configuration.smtpPort,
                                node: node,
                                indent: "            ",
                                to: lines
                            )
                            lines.append("           </void>")
                            lines.append("          </void>")
                        }
                        lines.append("         </object>")
                        lines.append("        </void>")
                    }
                    if emailServerInstalled {
                        let configuration = state.runtimeEmailServerConfigurationsByNodeID[node.id]
                            ?? TopologyRuntimeEmailServerConfiguration()
                        lines.append("        <void method=\"put\">")
                        lines.append("         <string>filius.software.email.EmailServer</string>")
                        lines.append("         <object class=\"filius.software.email.EmailServer\">")
                        lines.append("          <void property=\"mailDomain\"><string>\(escapedXML(configuration.domain, context: "Email Server domain on '\(node.displayName)'"))</string></void>")
                        if !configuration.accounts.isEmpty {
                            lines.append("          <void property=\"listeBenutzerkonten\">")
                            for account in configuration.accounts {
                                lines.append("           <void method=\"add\">")
                                appendJavaEmailAccountBean(
                                    username: account.username,
                                    password: account.password,
                                    name: account.name,
                                    emailAddress: account.emailAddress(domain: configuration.domain).mailAddress,
                                    node: node,
                                    indent: "            ",
                                    to: lines
                                )
                                lines.append("           </void>")
                            }
                            lines.append("          </void>")
                        }
                        lines.append("         </object>")
                        lines.append("        </void>")
                    }
                    lines.append("       </void>")
                }
                if gnutellaInstalled {
                    let configuration = state.runtimeGnutellaConfigurationsByNodeID[node.id]
                        ?? TopologyRuntimeGnutellaConfiguration()
                    lines.append("       <void property=\"installierteAnwendungen\">")
                    lines.append("        <void method=\"put\">")
                    lines.append("         <string>filius.software.dateiaustausch.PeerToPeerAnwendung</string>")
                    lines.append("         <object class=\"filius.software.dateiaustausch.PeerToPeerAnwendung\">")
                    lines.append("          <void property=\"maxTeilnehmerZahl\"><int>\(configuration.maximumKnownPeers)</int></void>")
                    lines.append("         </object>")
                    lines.append("        </void>")
                    lines.append("       </void>")
                }
                if dnsServerInstalled {
                    lines.append("       <void property=\"installierteAnwendungen\">")
                    lines.append("        <void method=\"put\">")
                    lines.append("         <string>filius.software.dns.DNSServer</string>")
                    lines.append("         <object class=\"filius.software.dns.DNSServer\">")
                    lines.append("          <void property=\"aktiv\"><boolean>false</boolean></void>")
                    lines.append("         </object>")
                    lines.append("        </void>")
                    lines.append("       </void>")
                }
                if ripEnabled {
                    lines.append("       <void property=\"ripEnabled\"><boolean>true</boolean></void>")
                }
                if dhcpClientEnabled {
                    lines.append("       <void property=\"DHCPKonfiguration\"><boolean>true</boolean></void>")
                }
                if let dhcpServer {
                    lines.append("       <void property=\"DHCPServer\">")
                    if dhcpServer.isActive {
                        lines.append("        <void property=\"aktiv\"><boolean>true</boolean></void>")
                    }
                    if dhcpServer.lowerBoundIPAddress != "0.0.0.0" {
                        lines.append("        <void property=\"untergrenze\"><string>\(escapedXML(dhcpServer.lowerBoundIPAddress))</string></void>")
                    }
                    if dhcpServer.upperBoundIPAddress != "0.0.0.0" {
                        lines.append("        <void property=\"obergrenze\"><string>\(escapedXML(dhcpServer.upperBoundIPAddress))</string></void>")
                    }
                    if dhcpServer.gatewayIPAddress != "0.0.0.0" {
                        lines.append("        <void property=\"gatewayip\"><string>\(escapedXML(dhcpServer.gatewayIPAddress))</string></void>")
                    }
                    if dhcpServer.dnsServerIPAddress != "0.0.0.0" {
                        lines.append("        <void property=\"dnsserverip\"><string>\(escapedXML(dhcpServer.dnsServerIPAddress))</string></void>")
                    }
                    if dhcpServer.useOwnSettings {
                        lines.append("        <void property=\"ownSettings\"><boolean>true</boolean></void>")
                    }
                    if !dhcpServer.staticAssignments.isEmpty {
                        lines.append("        <void property=\"staticAssignedAddresses\">")
                        for assignment in dhcpServer.staticAssignments {
                            lines.append("         <void method=\"add\"><string>\(escapedXML(assignment.macAddress)) \(escapedXML(assignment.ipAddress))</string></void>")
                        }
                        lines.append("        </void>")
                    }
                    lines.append("       </void>")
                }
                if let firewall {
                    let firewallClass = node.kind == .gateway
                        ? "filius.software.nat.NatGateway"
                        : "filius.software.firewall.Firewall"
                    let valueIndent: String
                    lines.append("       <void property=\"installierteAnwendungen\">")
                    if personalFirewallInstalled {
                        lines.append("        <void method=\"put\">")
                        lines.append("         <string>\(firewallClass)</string>")
                        lines.append("         <object class=\"\(firewallClass)\">")
                        valueIndent = "          "
                    } else {
                        lines.append("        <void method=\"get\">")
                        lines.append("         <string>\(firewallClass)</string>")
                        valueIndent = "         "
                    }
                    if personalFirewallInstalled {
                        if !firewall.isActive {
                            lines.append("\(valueIndent)<void property=\"activated\"><boolean>false</boolean></void>")
                        }
                    } else if firewall.isActive {
                        lines.append("\(valueIndent)<void property=\"activated\"><boolean>true</boolean></void>")
                    }
                    if firewall.defaultPolicy != .drop {
                        lines.append("\(valueIndent)<void property=\"defaultPolicy\"><short>\(firewall.defaultPolicy.rawValue)</short></void>")
                    }
                    if firewall.dropICMP {
                        lines.append("\(valueIndent)<void property=\"dropICMP\"><boolean>true</boolean></void>")
                    }
                    if !firewall.filterSYNSegmentsOnly {
                        lines.append("\(valueIndent)<void property=\"filterSYNSegmentsOnly\"><boolean>false</boolean></void>")
                    }
                    if !firewall.filterUDP {
                        lines.append("\(valueIndent)<void property=\"filterUdp\"><boolean>false</boolean></void>")
                    }
                    if !firewall.rules.isEmpty {
                        lines.append("\(valueIndent)<void property=\"ruleset\">")
                        for (ruleIndex, rule) in firewall.rules.enumerated() {
                            let reference = "FirewallRule_\(node.id.uuidString.replacingOccurrences(of: "-", with: ""))_\(ruleIndex)"
                            lines.append("\(valueIndent) <void method=\"add\">")
                            lines.append("\(valueIndent)  <object class=\"filius.software.firewall.FirewallRule\" id=\"\(reference)\">")
                            let stringFields = [
                                ("srcIP", rule.sourceIPAddress),
                                ("srcMask", rule.sourceSubnetMask),
                                ("destIP", rule.destinationIPAddress),
                                ("destMask", rule.destinationSubnetMask),
                            ]
                            for (field, value) in stringFields {
                                lines.append("\(valueIndent)   <void class=\"filius.software.firewall.FirewallRule\" method=\"getField\">")
                                lines.append("\(valueIndent)    <string>\(field)</string>")
                                lines.append("\(valueIndent)    <void method=\"set\"><object idref=\"\(reference)\"/><string>\(escapedXML(value))</string></void>")
                                lines.append("\(valueIndent)   </void>")
                            }
                            let intFields = [
                                ("port", rule.port, "int"),
                                ("protocol", rule.protocolType.rawValue, "short"),
                                ("action", rule.action.rawValue, "short"),
                            ]
                            for (field, value, numberType) in intFields {
                                lines.append("\(valueIndent)   <void class=\"filius.software.firewall.FirewallRule\" method=\"getField\">")
                                lines.append("\(valueIndent)    <string>\(field)</string>")
                                lines.append("\(valueIndent)    <void method=\"set\"><object idref=\"\(reference)\"/><\(numberType)>\(value)</\(numberType)></void>")
                                lines.append("\(valueIndent)   </void>")
                            }
                            lines.append("\(valueIndent)  </object>")
                            lines.append("\(valueIndent) </void>")
                        }
                        lines.append("\(valueIndent)</void>")
                    }
                    if personalFirewallInstalled {
                        lines.append("         </object>")
                    }
                    lines.append("        </void>")
                    lines.append("       </void>")
                }
                if !portForwardingRows.isEmpty {
                    lines.append("       <void property=\"staticNAT\">")
                    for row in portForwardingRows {
                        lines.append("        <void method=\"add\">")
                        lines.append("         <array class=\"java.lang.String\" length=\"4\">")
                        lines.append("          <void index=\"0\"><string>\(escapedXML(row.protocolValue))</string></void>")
                        lines.append("          <void index=\"1\"><string>\(escapedXML(row.publicPortValue))</string></void>")
                        lines.append("          <void index=\"2\"><string>\(escapedXML(row.lanIPAddress))</string></void>")
                        lines.append("          <void index=\"3\"><string>\(escapedXML(row.lanPortValue))</string></void>")
                        lines.append("         </array>")
                        lines.append("        </void>")
                    }
                    lines.append("       </void>")
                }
                if !manualRoutes.isEmpty {
                    lines.append("       <void property=\"weiterleitungstabelle\">")
                    lines.append("        <void property=\"manuelleTabelle\">")
                    for route in manualRoutes {
                        lines.append("         <void method=\"add\">")
                        lines.append("          <array class=\"java.lang.String\" length=\"4\">")
                        lines.append("           <void index=\"0\"><string>\(escapedXML(route.destinationNetwork))</string></void>")
                        lines.append("           <void index=\"1\"><string>\(escapedXML(route.subnetMask))</string></void>")
                        lines.append("           <void index=\"2\"><string>\(escapedXML(route.gateway))</string></void>")
                        lines.append("           <void index=\"3\"><string>\(escapedXML(route.interfaceIPAddress))</string></void>")
                        lines.append("          </array>")
                        lines.append("         </void>")
                    }
                    lines.append("        </void>")
                    lines.append("       </void>")
                }
                lines.append("      </void>")
            }
            lines.append("     </object>")
            lines.append("    </void>")
            lines.append("   </object>")
            lines.append("  </void>")
        }

        lines.append(" </object>")
        lines.append(" <object class=\"java.util.LinkedList\">")

        let sortedLinks = (state.graph.links + state.wirelessAssociations().map(\.runtimeLink))
            .filter { exportedNodeIDs.contains($0.sourceNodeID) && exportedNodeIDs.contains($0.targetNodeID) }
            .sorted { lhs, rhs in
                if lhs.id == rhs.id { return lhs.sourcePortID.uuidString < rhs.sourcePortID.uuidString }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        func isWirelessExportLink(_ link: TopologyLink) -> Bool {
            let endpointPairs = [
                (hostNodeID: link.sourceNodeID, switchNodeID: link.targetNodeID),
                (hostNodeID: link.targetNodeID, switchNodeID: link.sourceNodeID),
            ]
            return endpointPairs.contains { pair in
                guard state.graph.node(withID: pair.hostNodeID)?.kind.isPCClassEndpoint == true,
                      state.graph.node(withID: pair.switchNodeID)?.kind == .networkSwitch,
                      let host = state.hostWirelessConfigurationsByNodeID[pair.hostNodeID],
                      host.isEnabled
                else { return false }
                let accessPoint = state.switchConfigurationsByNodeID[pair.switchNodeID]
                    ?? .defaultConfiguration(nodeID: pair.switchNodeID)
                return host.ssid == accessPoint.ssid
            }
        }

        for link in sortedLinks {
            guard
                let sourcePortReference = portReferenceByID[link.sourcePortID],
                let targetPortReference = portReferenceByID[link.targetPortID],
                portOwnerByID[link.sourcePortID] == link.sourceNodeID,
                portOwnerByID[link.targetPortID] == link.targetNodeID,
                let sourceGUIReference = guiReferenceByNodeID[link.sourceNodeID],
                let targetGUIReference = guiReferenceByNodeID[link.targetNodeID]
            else {
                continue
            }

            lines.append("  <void method=\"add\">")
            lines.append("   <object class=\"filius.gui.netzwerksicht.GUIKabelItem\">")
            lines.append("    <void property=\"dasKabel\">")
            lines.append("     <object class=\"filius.hardware.Kabel\">")
            lines.append("      <void property=\"anschluesse\">")
            lines.append("       <array class=\"filius.hardware.Port\" length=\"2\">")
            lines.append("        <void index=\"0\"><object idref=\"\(sourcePortReference)\"/></void>")
            lines.append("        <void index=\"1\"><object idref=\"\(targetPortReference)\"/></void>")
            lines.append("       </array>")
            lines.append("      </void>")
            if isWirelessExportLink(link) {
                lines.append("      <void property=\"wireless\"><boolean>true</boolean></void>")
            }
            lines.append("     </object>")
            lines.append("    </void>")
            lines.append("    <void property=\"kabelpanel\">")
            lines.append("     <void property=\"ziel1\"><object idref=\"\(sourceGUIReference)\"/></void>")
            lines.append("     <void property=\"ziel2\"><object idref=\"\(targetGUIReference)\"/></void>")
            lines.append("    </void>")
            lines.append("   </object>")
            lines.append("  </void>")
        }

        lines.append(" </object>")
        lines.append(" <object class=\"java.util.ArrayList\">")

        let sortedDocumentationItems = state.documentationItems.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        var exportedDocumentationItemCount = 0
        for item in sortedDocumentationItems {
            guard item.hasSafeRenderValues,
                  let red = TopologyDocumentationItem.javaInteger(item.color.red * 255),
                  let green = TopologyDocumentationItem.javaInteger(item.color.green * 255),
                  let blue = TopologyDocumentationItem.javaInteger(item.color.blue * 255),
                  let alpha = TopologyDocumentationItem.javaInteger(item.color.alpha * 255),
                  let javaFontSize = TopologyDocumentationItem.javaInteger(item.fontSize),
                  let javaHeight = TopologyDocumentationItem.javaInteger(item.frame.height),
                  let javaWidth = TopologyDocumentationItem.javaInteger(item.frame.width),
                  let javaX = TopologyDocumentationItem.javaInteger(item.frame.origin.x),
                  let javaY = TopologyDocumentationItem.javaInteger(item.frame.origin.y)
            else {
                exportWarnings.append(
                    "Skipped documentation item '\(item.id.uuidString)' with unsupported geometry, color, or font values."
                )
                continue
            }

            let javaType = item.kind == .rectangle ? 1 : 2
            let javaFontStyle = item.isBold ? 1 : 0

            if Double(javaFontSize) != Double(item.fontSize) {
                exportWarnings.append(
                    "Documentation item '\(item.id.uuidString)' uses fractional font size \(item.fontSize); Java export rounded it to \(javaFontSize)."
                )
            }

            lines.append("  <void method=\"add\">")
            lines.append("   <object class=\"filius.gui.netzwerksicht.GUIDocuItem\">")
            lines.append("    <void property=\"color\">")
            lines.append("     <object class=\"java.awt.Color\">")
            lines.append("      <int>\(red)</int>")
            lines.append("      <int>\(green)</int>")
            lines.append("      <int>\(blue)</int>")
            lines.append("      <int>\(alpha)</int>")
            lines.append("     </object>")
            lines.append("    </void>")
            if item.kind == .text {
                lines.append("    <void property=\"font\">")
                lines.append("     <object class=\"java.awt.Font\">")
                lines.append("      <string>\(escapedXML(item.fontName, context: "Documentation font name"))</string>")
                lines.append("      <int>\(javaFontStyle)</int>")
                lines.append("      <int>\(javaFontSize)</int>")
                lines.append("     </object>")
                lines.append("    </void>")
            }
            lines.append("    <void property=\"height\"><int>\(javaHeight)</int></void>")
            if item.kind == .text {
                lines.append("    <void property=\"text\"><string>\(escapedXML(item.text, context: "Documentation text"))</string></void>")
            }
            lines.append("    <void property=\"type\"><int>\(javaType)</int></void>")
            lines.append("    <void property=\"width\"><int>\(javaWidth)</int></void>")
            lines.append("    <void property=\"x\"><int>\(javaX)</int></void>")
            lines.append("    <void property=\"y\"><int>\(javaY)</int></void>")
            lines.append("   </object>")
            lines.append("  </void>")
            exportedDocumentationItemCount += 1
        }

        lines.append(" </object>")
        lines.append("</java>")

        let data = try lines.finish()
        exportWarnings.append(contentsOf: lines.sanitizationWarnings)
        return TopologyFLSExportResult(
            data: data,
            report: TopologyFLSExportReport(
                exportedNodeCount: sortedNodes.count,
                exportedLinkCount: sortedLinks.count,
                exportedDocumentationItemCount: exportedDocumentationItemCount,
                warnings: exportWarnings
            )
        )
    }

    private func readRawData() throws -> Data {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw makeError(
                operation: .load,
                code: .fileNotFound,
                detail: "Project file was not found at configured URL"
            )
        }

        do {
            return try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            throw makeError(
                operation: .load,
                code: .fileReadFailed,
                detail: "Failed to read project file data: \(describe(error: error))"
            )
        }
    }

    private func makeError(
        operation: TopologyProjectPersistenceOperation,
        code: TopologyProjectPersistenceErrorCode,
        detail: String
    ) -> TopologyProjectPersistenceError {
        TopologyProjectPersistenceError(operation: operation, code: code, detail: detail)
    }

    private func describe(error: Error) -> String {
        if let decodingError = error as? DecodingError {
            switch decodingError {
            case let .typeMismatch(_, context):
                return "typeMismatch at \(format(codingPath: context.codingPath)): \(context.debugDescription)"
            case let .valueNotFound(_, context):
                return "valueNotFound at \(format(codingPath: context.codingPath)): \(context.debugDescription)"
            case let .keyNotFound(key, context):
                return "keyNotFound '\(key.stringValue)' at \(format(codingPath: context.codingPath)): \(context.debugDescription)"
            case let .dataCorrupted(context):
                return "dataCorrupted at \(format(codingPath: context.codingPath)): \(context.debugDescription)"
            @unknown default:
                return "unknown decoding error"
            }
        }

        if let encodingError = error as? EncodingError {
            switch encodingError {
            case let .invalidValue(_, context):
                return "invalidValue at \(format(codingPath: context.codingPath)): \(context.debugDescription)"
            @unknown default:
                return "unknown encoding error"
            }
        }

        return String(describing: error)
    }

    private func format(codingPath: [CodingKey]) -> String {
        guard !codingPath.isEmpty else {
            return "<root>"
        }

        return codingPath
            .map(\.stringValue)
            .joined(separator: ".")
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct TopologyFLSConfigurationParseResult {
    let filiusVersion: String?
    let nodes: [TopologyNode]
    let links: [TopologyLink]
    let runtimeDeviceConfigurations: [UUID: TopologyRuntimeDeviceConfiguration]
    let runtimeInterfaceConfigurations: [TopologyRuntimeInterfaceKey: TopologyRuntimeInterfaceConfiguration]
    let runtimeManualRoutesByNodeID: [UUID: [TopologyRuntimeManualRoute]]
    let runtimeRIPEnabledByNodeID: [UUID: Bool]
    let runtimeDHCPClientConfigurationsByNodeID: [UUID: TopologyDHCPClientConfiguration]
    let runtimeDHCPServerConfigurationsByNodeID: [UUID: TopologyDHCPServerConfiguration]
    let runtimeFirewallConfigurationsByNodeID: [UUID: TopologyFirewallConfiguration]
    let runtimePortForwardingRowsByNodeID: [UUID: [TopologyGatewayPortForwardingRow]]
    let switchConfigurationsByNodeID: [UUID: TopologySwitchConfiguration]
    let remoteLinkConfigurationsByNodeID: [UUID: TopologyRemoteLinkConfiguration]
    let hostWirelessConfigurationsByNodeID: [UUID: TopologyHostWirelessConfiguration]
    let virtualFileSystemsByNodeID: [UUID: TopologyVirtualFileSystem]
    let runtimeInstalledProgramsByNodeID: [UUID: Set<TopologyRuntimeInstallableProgram>]
    let runtimeWebServerConfigurationsByNodeID: [UUID: TopologyRuntimeWebServerConfiguration]
    let runtimeEmailClientConfigurationsByNodeID: [UUID: TopologyRuntimeEmailClientConfiguration]
    let runtimeEmailServerConfigurationsByNodeID: [UUID: TopologyRuntimeEmailServerConfiguration]
    let documentationItems: [TopologyDocumentationItem]
    let recognizedNodeIDsBySourcePath: [TopologyFLSInertXMLPath: UUID]
    let recognizedLinkIDsBySourcePath: [TopologyFLSInertXMLPath: UUID]
    let recognizedDocumentationItemIDsBySourcePath: [TopologyFLSInertXMLPath: UUID]
    let skippedNodeCount: Int
    let warnings: [String]
}

func topologyImportedUnknownJavaFileBinaryContent(
    type: String,
    content: String
) -> TopologyVirtualFileContent? {
    guard let data = Data(base64Encoded: content, options: [.ignoreUnknownCharacters]),
          !data.isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
        return nil
    }
    return .binary(data, mediaType: type.isEmpty ? nil : "application/\(type)")
}

private final class TopologyFLSConfigurationParser: NSObject, XMLParserDelegate {
    private struct InterfaceCandidate {
        var ipAddress: String?
        var subnetMask: String?
        var defaultGateway: String?
        var dnsServer: String?
        var legacyPortReference: String?
    }

    private struct JavaFileCandidate {
        var name: String?
        var type: String?
        var content: String?
    }

    private struct JavaFileTreeCandidate {
        var directoryName: String?
        var file: JavaFileCandidate?
        var children: [JavaFileTreeCandidate] = []
    }

    private enum JavaEmailAccountKind: Equatable {
        case client
        case server
    }

    private enum JavaEmailMessageContainer: Equatable {
        case clientInbox
        case clientSent
        case clientDrafts
        case serverMailbox
    }

    private enum JavaEmailAddressTarget: Equatable {
        case sender
        case to
        case cc
        case bcc
    }

    private struct JavaEmailAccountCandidate: Equatable {
        var mapKey: String?
        var username: String?
        var password: String?
        var lastName: String?
        var firstName: String?
        var pop3Server: String?
        var smtpServer: String?
        var pop3Port: String?
        var smtpPort: String?
        var emailAddress: String?
        var messages: [TopologyRuntimeEmailMessage] = []
    }

    private struct JavaEmailMessageCandidate {
        var sender: TopologyRuntimeEmailAddress?
        var to: [TopologyRuntimeEmailAddress] = []
        var cc: [TopologyRuntimeEmailAddress] = []
        var bcc: [TopologyRuntimeEmailAddress] = []
        var subject = ""
        var body = ""
        var receivedAtMilliseconds: UInt64?
        var isNew = true
        var isMarkedForDeletion = false
        var isSent = false
    }

    private struct JavaEmailAddressCandidate {
        var name: String? = nil
        var mailAddress: String? = nil
        var target: JavaEmailAddressTarget
        var identifier: String?
    }

    private struct NodeCandidate {
        var typeName: String?
        var knotenClassName: String?
        var displayName: String?
        var x: Int?
        var y: Int?
        var interfaces: [InterfaceCandidate] = []
        var switchPortReferencesByIndex: [Int: String] = [:]
        var manualRoutes: [TopologyRuntimeManualRoute] = []
        var ripEnabled = false
        var dhcpClientEnabled = false
        var dhcpServerConfiguration = TopologyDHCPServerConfiguration()
        var firewallConfiguration = TopologyFirewallConfiguration()
        var hasFirewallConfiguration = false
        var portForwardingRows: [TopologyGatewayPortForwardingRow] = []
        var switchSSID: String?
        var switchRetentionTimeMilliseconds: UInt64?
        var hostWirelessSSID: String?
        var modemMode: Int?
        var modemIPAddress: String?
        var modemPort: Int?
        var fileSystemRoots: [JavaFileTreeCandidate] = []
        var hasFileSystem = false
        var hasDNSServerApplication = false
        var hasPersonalFirewallApplication = false
        var hasWebServerApplication = false
        var hasWebBrowserApplication = false
        var hasEmailClientApplication = false
        var hasEmailServerApplication = false
        var hasGnutellaApplication = false
        var gnutellaMaximumKnownPeers: Int?
        var emailClientAccounts: [JavaEmailAccountCandidate] = []
        var emailClientInbox: [TopologyRuntimeEmailMessage] = []
        var emailClientSent: [TopologyRuntimeEmailMessage] = []
        var emailClientDrafts: [TopologyRuntimeEmailMessage] = []
        var emailServerDomain: String?
        var emailServerAccounts: [JavaEmailAccountCandidate] = []
        var webServerPort: Int?
    }

    private struct CableCandidate {
        let sourcePath: TopologyFLSInertXMLPath
        var legacyPortReferences: [String] = []
    }

    private struct DocumentationCandidate {
        let sourcePath: TopologyFLSInertXMLPath
        var type: Int?
        var text = ""
        var x: Int?
        var y: Int?
        var width: Int?
        var height: Int?
        var color: TopologyDocumentationColor?
        var fontName = "Dialog"
        var fontStyle = 0
        var fontSize = 12
    }

    private struct DocumentationFont {
        let name: String
        let style: Int
        let size: Int
    }

    private struct LegacyPortEndpoint {
        let nodeID: UUID
        let portID: UUID
    }

    private struct VoidContext {
        let property: String?
        let method: String?
        let index: Int?
    }

    private let data: Data
    private let semanticPlan: TopologyFLSSemanticSourcePlan

    private var elementPathStack: [TopologyFLSInertXMLPath] = []
    private var nextElementChildIndexStack: [Int] = []
    private var objectClassStack: [String?] = []
    private var objectIdentifierStack: [String?] = []
    private var voidStack: [VoidContext] = []
    private var propertyStack: [String] = []

    private var currentNode: NodeCandidate?
    private var currentInterfaceIndex: Int?
    private var currentCable: CableCandidate?
    private var currentDocumentation: DocumentationCandidate?
    private var nodes: [TopologyNode] = []
    private var links: [TopologyLink] = []
    private var runtimeDeviceConfigurations: [UUID: TopologyRuntimeDeviceConfiguration] = [:]
    private var runtimeInterfaceConfigurations: [TopologyRuntimeInterfaceKey: TopologyRuntimeInterfaceConfiguration] = [:]
    private var runtimeManualRoutesByNodeID: [UUID: [TopologyRuntimeManualRoute]] = [:]
    private var runtimeRIPEnabledByNodeID: [UUID: Bool] = [:]
    private var runtimeDHCPClientConfigurationsByNodeID: [UUID: TopologyDHCPClientConfiguration] = [:]
    private var runtimeDHCPServerConfigurationsByNodeID: [UUID: TopologyDHCPServerConfiguration] = [:]
    private var runtimeFirewallConfigurationsByNodeID: [UUID: TopologyFirewallConfiguration] = [:]
    private var runtimePortForwardingRowsByNodeID: [UUID: [TopologyGatewayPortForwardingRow]] = [:]
    private var switchConfigurationsByNodeID: [UUID: TopologySwitchConfiguration] = [:]
    private var remoteLinkConfigurationsByNodeID: [UUID: TopologyRemoteLinkConfiguration] = [:]
    private var hostWirelessConfigurationsByNodeID: [UUID: TopologyHostWirelessConfiguration] = [:]
    private var virtualFileSystemsByNodeID: [UUID: TopologyVirtualFileSystem] = [:]
    private var runtimeInstalledProgramsByNodeID: [UUID: Set<TopologyRuntimeInstallableProgram>] = [:]
    private var runtimeWebServerConfigurationsByNodeID: [UUID: TopologyRuntimeWebServerConfiguration] = [:]
    private var runtimeEmailClientConfigurationsByNodeID: [UUID: TopologyRuntimeEmailClientConfiguration] = [:]
    private var runtimeEmailServerConfigurationsByNodeID: [UUID: TopologyRuntimeEmailServerConfiguration] = [:]
    private var documentationItems: [TopologyDocumentationItem] = []
    private var legacyDocumentationColorsByReference: [String: TopologyDocumentationColor] = [:]
    private var legacyDocumentationFontsByReference: [String: DocumentationFont] = [:]
    private var legacyDocumentationIntegersByReference: [String: Int] = [:]
    private var currentDocumentationColorComponents: [Int]?
    private var currentDocumentationFontValues: [Int]?
    private var currentDocumentationFontName: String?
    private var boxedIntegerValueStack: [Int?] = []
    private var legacyPortEndpointByReference: [String: LegacyPortEndpoint] = [:]
    private var cableCandidates: [CableCandidate] = []
    private var warnings: [String] = []
    private var skippedNodeCount = 0
    private var currentSourceNodePath: TopologyFLSInertXMLPath?
    private var recognizedNodeIDsBySourcePath: [TopologyFLSInertXMLPath: UUID] = [:]
    private var recognizedLinkIDsBySourcePath: [TopologyFLSInertXMLPath: UUID] = [:]
    private var recognizedDocumentationItemIDsBySourcePath: [TopologyFLSInertXMLPath: UUID] = [:]

    private var currentTextBuffer = ""
    private var ignoredRecognizedGUISubtreeDepth = 0
    private var parsingString = false
    private var parsingInt = false
    private var parsingShort = false
    private var parsingLong = false
    private var currentFirewallRule: TopologyFirewallRule?
    private var firewallFieldNameStack: [String?] = []
    private var firewallGetFieldDepth = 0
    private var firewallSetDepth = 0
    private var currentManualRouteValuesByIndex: [Int: String]?
    private var currentStaticNATValuesByIndex: [Int: String]?
    private var javaFileTreeStack: [JavaFileTreeCandidate] = []
    private var currentJavaFile: JavaFileCandidate?
    private var currentEmailAccount: JavaEmailAccountCandidate?
    private var currentEmailAccountKind: JavaEmailAccountKind?
    private var pendingEmailClientMapKey: String?
    private var currentEmailMessage: JavaEmailMessageCandidate?
    private var currentEmailMessageContainer: JavaEmailMessageContainer?
    private var currentEmailAddress: JavaEmailAddressCandidate?
    private var currentEmailAddressVoidDepth: Int?
    private var emailAddressesByReference: [String: TopologyRuntimeEmailAddress] = [:]

    private var rectangleFieldNameStack: [String?] = []
    private var rectangleGetFieldDepth = 0
    private var rectangleSetDepth = 0
    private var directBoundsIntIndexStack: [Int] = []

    private var filiusVersion: String?
    private var sawXMLDecoderRoot = false
    private var sawNodeListContainer = false

    init(data: Data, semanticPlan: TopologyFLSSemanticSourcePlan) {
        self.data = data
        self.semanticPlan = semanticPlan
    }

    func parse() throws -> TopologyFLSConfigurationParseResult {
        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            let message = parser.parserError?.localizedDescription ?? "unknown XML parser error"
            throw TopologyFLSCompatibilityError(
                code: .malformedConfigurationXML,
                detail: "Failed to parse konfiguration.xml at line \(parser.lineNumber): \(message)"
            )
        }

        guard sawXMLDecoderRoot else {
            throw TopologyFLSCompatibilityError(
                code: .unsupportedConfigurationStructure,
                detail: "Unsupported configuration root: expected <java class=\"java.beans.XMLDecoder\">"
            )
        }

        guard sawNodeListContainer else {
            throw TopologyFLSCompatibilityError(
                code: .unsupportedConfigurationStructure,
                detail: "Unsupported configuration payload: expected node container <object class=\"java.util.LinkedList\">"
            )
        }

        resolveCableCandidates()

        return TopologyFLSConfigurationParseResult(
            filiusVersion: filiusVersion,
            nodes: nodes,
            links: links,
            runtimeDeviceConfigurations: runtimeDeviceConfigurations,
            runtimeInterfaceConfigurations: runtimeInterfaceConfigurations,
            runtimeManualRoutesByNodeID: runtimeManualRoutesByNodeID,
            runtimeRIPEnabledByNodeID: runtimeRIPEnabledByNodeID,
            runtimeDHCPClientConfigurationsByNodeID: runtimeDHCPClientConfigurationsByNodeID,
            runtimeDHCPServerConfigurationsByNodeID: runtimeDHCPServerConfigurationsByNodeID,
            runtimeFirewallConfigurationsByNodeID: runtimeFirewallConfigurationsByNodeID,
            runtimePortForwardingRowsByNodeID: runtimePortForwardingRowsByNodeID,
            switchConfigurationsByNodeID: switchConfigurationsByNodeID,
            remoteLinkConfigurationsByNodeID: remoteLinkConfigurationsByNodeID,
            hostWirelessConfigurationsByNodeID: hostWirelessConfigurationsByNodeID,
            virtualFileSystemsByNodeID: virtualFileSystemsByNodeID,
            runtimeInstalledProgramsByNodeID: runtimeInstalledProgramsByNodeID,
            runtimeWebServerConfigurationsByNodeID: runtimeWebServerConfigurationsByNodeID,
            runtimeEmailClientConfigurationsByNodeID: runtimeEmailClientConfigurationsByNodeID,
            runtimeEmailServerConfigurationsByNodeID: runtimeEmailServerConfigurationsByNodeID,
            documentationItems: documentationItems.inDeterministicRenderOrder,
            recognizedNodeIDsBySourcePath: recognizedNodeIDsBySourcePath,
            recognizedLinkIDsBySourcePath: recognizedLinkIDsBySourcePath,
            recognizedDocumentationItemIDsBySourcePath: recognizedDocumentationItemIDsBySourcePath,
            skippedNodeCount: skippedNodeCount,
            warnings: warnings
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let elementPath: TopologyFLSInertXMLPath
        if elementPathStack.isEmpty {
            elementPath = TopologyFLSInertXMLPath(elementIndices: [])
        } else {
            let index = nextElementChildIndexStack[nextElementChildIndexStack.count - 1]
            nextElementChildIndexStack[nextElementChildIndexStack.count - 1] += 1
            elementPath = TopologyFLSInertXMLPath(
                elementIndices: elementPathStack.last!.elementIndices + [index]
            )
        }
        elementPathStack.append(elementPath)
        nextElementChildIndexStack.append(0)
        currentTextBuffer = ""

        if ignoredRecognizedGUISubtreeDepth > 0 {
            ignoredRecognizedGUISubtreeDepth += 1
            return
        }
        if elementName == "object", let className = attributeDict["class"] {
            let planned = semanticPlan.nodeObjectPaths.contains(elementPath)
                || semanticPlan.cableObjectPaths.contains(elementPath)
                || semanticPlan.documentationObjectPaths.contains(elementPath)
            if !planned, [
                "filius.gui.netzwerksicht.GUIKnotenItem",
                "filius.gui.netzwerksicht.GUIKabelItem",
                "filius.gui.netzwerksicht.GUIDocuItem",
            ].contains(className) {
                ignoredRecognizedGUISubtreeDepth = 1
                return
            }
        }

        switch elementName {
        case "java":
            if attributeDict["class"] == "java.beans.XMLDecoder" {
                sawXMLDecoderRoot = true
            }

        case "object":
            let objectClass = attributeDict["class"]
            objectClassStack.append(objectClass)
            objectIdentifierStack.append(attributeDict["id"])

            if objectClass == "java.util.LinkedList", elementPath == semanticPlan.nodeContainerPath {
                sawNodeListContainer = true
            }

            if objectClass == "filius.gui.netzwerksicht.GUIKnotenItem",
               semanticPlan.nodeObjectPaths.contains(elementPath)
            {
                currentSourceNodePath = elementPath
                currentNode = NodeCandidate()
                currentInterfaceIndex = nil
                javaFileTreeStack = []
                currentJavaFile = nil
                currentEmailAccount = nil
                currentEmailAccountKind = nil
                pendingEmailClientMapKey = nil
                currentEmailMessage = nil
                currentEmailMessageContainer = nil
                currentEmailAddress = nil
                currentEmailAddressVoidDepth = nil
            } else if currentNode != nil,
                      objectClass == "javax.swing.tree.DefaultMutableTreeNode",
                      propertyStack.contains("dateisystem")
            {
                javaFileTreeStack.append(JavaFileTreeCandidate())
            } else if currentNode != nil,
                      objectClass == "filius.software.system.Datei",
                      propertyStack.contains("dateisystem")
            {
                currentJavaFile = JavaFileCandidate()
            } else if currentNode != nil,
                      objectClass == "filius.software.dateiaustausch.PeerToPeerAnwendung",
                      propertyStack.contains("installierteAnwendungen")
            {
                currentNode?.hasGnutellaApplication = true
            } else if currentNode != nil,
                      objectClass == "filius.software.email.EmailAnwendung",
                      propertyStack.contains("installierteAnwendungen")
            {
                currentNode?.hasEmailClientApplication = true
                pendingEmailClientMapKey = nil
            } else if currentNode != nil,
                      objectClass == "filius.software.email.EmailServer",
                      propertyStack.contains("installierteAnwendungen")
            {
                currentNode?.hasEmailServerApplication = true
            } else if currentNode != nil,
                      objectClass == "filius.software.email.EmailKonto",
                      propertyStack.contains("installierteAnwendungen")
            {
                let enclosingClasses = objectClassStack.dropLast().compactMap { $0 }
                if enclosingClasses.contains("filius.software.email.EmailAnwendung") {
                    currentEmailAccountKind = .client
                    currentEmailAccount = JavaEmailAccountCandidate(mapKey: pendingEmailClientMapKey)
                } else if enclosingClasses.contains("filius.software.email.EmailServer") {
                    currentEmailAccountKind = .server
                    currentEmailAccount = JavaEmailAccountCandidate()
                }
            } else if currentNode != nil,
                      objectClass == "filius.software.email.Email",
                      propertyStack.contains("installierteAnwendungen"),
                      let container = currentJavaEmailMessageContainer()
            {
                currentEmailMessage = JavaEmailMessageCandidate()
                currentEmailMessageContainer = container
            } else if currentEmailMessage != nil,
                      objectClass == "filius.software.email.AddressEntry",
                      let target = currentJavaEmailAddressTarget()
            {
                currentEmailAddress = JavaEmailAddressCandidate(
                    target: target,
                    identifier: attributeDict["id"]
                )
                currentEmailAddressVoidDepth = nil
            } else if currentEmailMessage != nil,
                      let reference = attributeDict["idref"],
                      let address = emailAddressesByReference[reference],
                      let target = currentJavaEmailAddressTarget()
            {
                applyJavaEmailAddress(address, target: target)
            } else if currentNode != nil,
                      objectClass == "filius.software.www.WebServer",
                      propertyStack.contains("installierteAnwendungen")
            {
                currentNode?.hasWebServerApplication = true
            } else if currentNode != nil,
                      objectClass == "filius.software.www.WebBrowser",
                      propertyStack.contains("installierteAnwendungen")
            {
                currentNode?.hasWebBrowserApplication = true
            } else if currentNode != nil,
                      objectClass == "filius.software.dns.DNSServer",
                      propertyStack.contains("installierteAnwendungen")
            {
                currentNode?.hasDNSServerApplication = true
            } else if currentNode != nil,
                      objectClass == "filius.software.firewall.Firewall",
                      propertyStack.contains("installierteAnwendungen")
            {
                currentNode?.hasPersonalFirewallApplication = true
                currentNode?.hasFirewallConfiguration = true
                currentNode?.firewallConfiguration = .javaPersonalDefaults
            } else if objectClass == "filius.gui.netzwerksicht.GUIKabelItem",
                      semanticPlan.cableObjectPaths.contains(elementPath)
            {
                currentCable = CableCandidate(sourcePath: elementPath)
            } else if objectClass == "filius.gui.netzwerksicht.GUIDocuItem",
                      semanticPlan.documentationObjectPaths.contains(elementPath)
            {
                currentDocumentation = DocumentationCandidate(sourcePath: elementPath)
            } else if currentDocumentation != nil,
                      propertyStack.last == "color",
                      objectClass == "java.awt.Color"
            {
                currentDocumentationColorComponents = []
            } else if currentDocumentation != nil,
                      propertyStack.last == "color",
                      let reference = attributeDict["idref"],
                      let color = legacyDocumentationColorsByReference[reference]
            {
                currentDocumentation?.color = color
            } else if currentDocumentation != nil,
                      propertyStack.last == "font",
                      objectClass == "java.awt.Font" || objectClass == "javax.swing.plaf.FontUIResource"
            {
                currentDocumentationFontValues = []
                currentDocumentationFontName = nil
            } else if currentDocumentation != nil,
                      propertyStack.last == "font",
                      let reference = attributeDict["idref"],
                      let font = legacyDocumentationFontsByReference[reference]
            {
                currentDocumentation?.fontName = font.name
                currentDocumentation?.fontStyle = font.style
                currentDocumentation?.fontSize = font.size
            } else if currentDocumentation != nil,
                      propertyStack.last == "type",
                      let reference = attributeDict["idref"],
                      let number = legacyDocumentationIntegersByReference[reference]
            {
                currentDocumentation?.type = number
            } else if currentNode != nil,
                      objectClass == "filius.hardware.NetzwerkInterface",
                      propertyStack.contains("netzwerkInterfaces")
            {
                beginCurrentInterface(at: nil)
            } else if currentNode != nil,
                      objectClass == "filius.software.firewall.FirewallRule",
                      propertyStack.contains("ruleset")
            {
                currentFirewallRule = TopologyFirewallRule()
                currentNode?.hasFirewallConfiguration = true
            } else if currentNode != nil,
                      objectClass == "java.awt.Rectangle",
                      propertyStack.contains("bounds")
            {
                directBoundsIntIndexStack.append(0)
            } else if currentNode != nil,
                      propertyStack.last == "knoten",
                      let objectClass,
                      !objectClass.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                currentNode?.knotenClassName = objectClass
            }

            if objectClass == "java.lang.Integer" {
                boxedIntegerValueStack.append(nil)
            }

            if currentNode != nil,
               let property = propertyStack.last,
               attributeDict["idref"] != nil,
               property == "activated" || property == "dropICMP"
            {
                currentNode?.hasFirewallConfiguration = true
                if property == "activated" {
                    currentNode?.firewallConfiguration.isActive = true
                } else {
                    currentNode?.firewallConfiguration.dropICMP = true
                }
            }

            if currentCable != nil,
               propertyStack.contains("dasKabel"),
               propertyStack.contains("anschluesse"),
               let endpointContext = voidStack.last,
               endpointContext.property == nil,
               endpointContext.method == nil,
               endpointContext.index != nil,
               attributeDict.count == 1,
               let reference = attributeDict["idref"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !reference.isEmpty
            {
                currentCable?.legacyPortReferences.append(reference)
            }

        case "array":
            if currentNode != nil,
               propertyStack.contains("manuelleTabelle"),
               attributeDict["class"] == "java.lang.String"
            {
                currentManualRouteValuesByIndex = [:]
            } else if currentNode != nil,
                      propertyStack.contains("staticNAT"),
                      attributeDict["class"] == "java.lang.String"
            {
                currentStaticNATValuesByIndex = [:]
            }

        case "void":
            let context = VoidContext(
                property: attributeDict["property"],
                method: attributeDict["method"],
                index: attributeDict["index"].flatMap { Int($0) }
            )
            if currentNode != nil, context.property == "dateisystem" {
                currentNode?.hasFileSystem = true
            }

            if let identifier = attributeDict["id"],
               let property = context.property,
               let boxedValue = boxedDocumentationInteger(for: property)
            {
                legacyDocumentationIntegersByReference[identifier] = boxedValue
            }

            if currentNode != nil,
               propertyStack.last == "netzwerkInterfaces",
               let indexValue = attributeDict["index"],
               let index = Int(indexValue)
            {
                beginCurrentInterface(at: index)
            }

            if currentNode != nil,
               context.property == "port",
               propertyStack.contains("netzwerkInterfaces"),
               let reference = attributeDict["id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !reference.isEmpty
            {
                updateCurrentInterface { interface in
                    interface.legacyPortReference = reference
                }
            } else if currentNode != nil,
                      propertyStack.contains("anschluesse"),
                      let indexValue = attributeDict["index"],
                      let index = Int(indexValue),
                      let reference = attributeDict["id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !reference.isEmpty
            {
                currentNode?.switchPortReferencesByIndex[index] = reference
            }

            voidStack.append(context)

            if let property = context.property {
                propertyStack.append(property)
            }

            if currentEmailMessage != nil,
               let property = context.property,
               let identifier = attributeDict["id"],
               let target = javaEmailAddressTarget(for: property)
            {
                currentEmailAddress = JavaEmailAddressCandidate(
                    target: target,
                    identifier: identifier
                )
                currentEmailAddressVoidDepth = voidStack.count
            }

            if context.method == "getField", propertyStack.contains("bounds") {
                rectangleGetFieldDepth += 1
                rectangleFieldNameStack.append(nil)
            }

            if context.method == "set", propertyStack.contains("bounds") {
                rectangleSetDepth += 1
            }
            if context.property == "ruleset" {
                currentNode?.hasFirewallConfiguration = true
            }
            if context.method == "getField", propertyStack.contains("ruleset") {
                firewallGetFieldDepth += 1
                firewallFieldNameStack.append(nil)
            }
            if context.method == "set", propertyStack.contains("ruleset") {
                firewallSetDepth += 1
            }

        case "string":
            parsingString = true

        case "int":
            parsingInt = true
        case "short":
            parsingShort = true
        case "long":
            parsingLong = true

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentTextBuffer.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let elementPath = elementPathStack.last
        defer {
            if !elementPathStack.isEmpty { elementPathStack.removeLast() }
            if !nextElementChildIndexStack.isEmpty { nextElementChildIndexStack.removeLast() }
        }
        if ignoredRecognizedGUISubtreeDepth > 0 {
            ignoredRecognizedGUISubtreeDepth -= 1
            currentTextBuffer = ""
            return
        }
        let rawValue = currentTextBuffer
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "string":
            parsingString = false

            if filiusVersion == nil, elementPath == semanticPlan.versionStringPath,
               value.hasPrefix("Filius version:")
            {
                filiusVersion = value
            }

            if currentManualRouteValuesByIndex != nil, let index = voidStack.last?.index {
                currentManualRouteValuesByIndex?[index] = value
            } else if currentStaticNATValuesByIndex != nil, let index = voidStack.last?.index {
                currentStaticNATValuesByIndex?[index] = value
            }

            if currentNode != nil, propertyStack.contains("dateisystem"), let property = propertyStack.last {
                if currentJavaFile != nil {
                    switch property {
                    case "name": currentJavaFile?.name = value
                    case "dateiTyp": currentJavaFile?.type = value
                    case "dateiInhalt": currentJavaFile?.content = currentTextBuffer
                    default: break
                    }
                } else if property == "userObject", !javaFileTreeStack.isEmpty {
                    javaFileTreeStack[javaFileTreeStack.count - 1].directoryName = value
                }
            }

            if currentNode != nil,
               currentEmailAccount == nil,
               propertyStack.last == "kontoListe",
               voidStack.last?.method == "put"
            {
                pendingEmailClientMapKey = value
            }

            if currentEmailAddress != nil, let property = propertyStack.last {
                if property == "mailAddress" {
                    currentEmailAddress?.mailAddress = value
                } else if property == "name" {
                    currentEmailAddress?.name = value
                }
            } else if currentEmailMessage != nil, let property = propertyStack.last {
                switch property {
                case "betreff":
                    currentEmailMessage?.subject = value
                case "text":
                    currentEmailMessage?.body = currentTextBuffer
                case "dateReceived":
                    currentEmailMessage?.receivedAtMilliseconds = UInt64(value)
                case "absender":
                    if let address = TopologyRuntimeEmailAddress(javaString: value) {
                        currentEmailMessage?.sender = address
                    }
                default:
                    if let target = currentJavaEmailAddressTarget(),
                       let address = TopologyRuntimeEmailAddress(javaString: value)
                    {
                        applyJavaEmailAddress(address, target: target)
                    }
                }
            }

            if currentEmailAccount != nil, currentEmailMessage == nil, let property = propertyStack.last {
                switch property {
                case "benutzername": currentEmailAccount?.username = value
                case "passwort": currentEmailAccount?.password = rawValue
                case "nachname": currentEmailAccount?.lastName = value
                case "vorname": currentEmailAccount?.firstName = value
                case "pop3server": currentEmailAccount?.pop3Server = value
                case "smtpserver": currentEmailAccount?.smtpServer = value
                case "pop3port": currentEmailAccount?.pop3Port = value
                case "smtpport": currentEmailAccount?.smtpPort = value
                case "emailAdresse": currentEmailAccount?.emailAddress = value
                default: break
                }
            } else if currentNode?.hasEmailServerApplication == true,
                      currentEmailAccount == nil,
                      propertyStack.last == "mailDomain"
            {
                currentNode?.emailServerDomain = value
            }

            if currentDocumentation != nil, let property = propertyStack.last {
                if property == "text" {
                    currentDocumentation?.text = value
                } else if property == "font", currentDocumentationFontValues != nil {
                    currentDocumentationFontName = value
                }
            }

            if currentNode != nil, let property = propertyStack.last {
                if property == "typ" {
                    currentNode?.typeName = value
                } else if property == "name", propertyStack.dropLast().last == "knoten" {
                    currentNode?.displayName = value
                } else if property == "text",
                          propertyStack.dropLast().last == "imageLabel",
                          currentNode?.displayName == nil
                {
                    currentNode?.displayName = value
                } else if property == "SSID" {
                    currentNode?.switchSSID = value
                } else if property == "ssid" {
                    currentNode?.hostWirelessSSID = value
                } else if property == "ipAdresse", propertyStack.contains("systemSoftware") {
                    currentNode?.modemIPAddress = value
                } else if propertyStack.contains("netzwerkInterfaces") {
                    updateCurrentInterface { interface in
                        switch property {
                        case "ip" where interface.ipAddress == nil:
                            interface.ipAddress = value
                        case "subnetzMaske" where interface.subnetMask == nil:
                            interface.subnetMask = value
                        case "gateway" where interface.defaultGateway == nil:
                            interface.defaultGateway = value
                        case "dns" where interface.dnsServer == nil:
                            interface.dnsServer = value
                        default:
                            break
                        }
                    }
                }
            }

            if currentNode != nil, propertyStack.contains("DHCPServer"), let property = propertyStack.last {
                switch property {
                case "untergrenze": currentNode?.dhcpServerConfiguration.lowerBoundIPAddress = value
                case "obergrenze": currentNode?.dhcpServerConfiguration.upperBoundIPAddress = value
                case "gatewayip": currentNode?.dhcpServerConfiguration.gatewayIPAddress = value
                case "dnsserverip": currentNode?.dhcpServerConfiguration.dnsServerIPAddress = value
                case "staticAssignedAddresses":
                    let pair = value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                    if pair.count >= 2 {
                        currentNode?.dhcpServerConfiguration.staticAssignments.append(
                            TopologyDHCPStaticAssignment(macAddress: pair[0], ipAddress: pair[1])
                        )
                    }
                default: break
                }
            }

            if rectangleGetFieldDepth > 0, propertyStack.contains("bounds") {
                if !rectangleFieldNameStack.isEmpty {
                    rectangleFieldNameStack[rectangleFieldNameStack.count - 1] = value
                }
            }
            if firewallGetFieldDepth > 0, propertyStack.contains("ruleset") {
                if firewallSetDepth == 0, !firewallFieldNameStack.isEmpty {
                    firewallFieldNameStack[firewallFieldNameStack.count - 1] = value
                } else if firewallSetDepth > 0, let fieldName = firewallFieldNameStack.last.flatMap({ $0 }) {
                    updateCurrentFirewallRule(fieldName: fieldName, stringValue: value)
                }
            }

        case "boolean":
            if currentEmailMessage != nil, let property = propertyStack.last {
                let enabled = value.lowercased() == "true"
                switch property {
                case "neu": currentEmailMessage?.isNew = enabled
                case "delete": currentEmailMessage?.isMarkedForDeletion = enabled
                case "versendet": currentEmailMessage?.isSent = enabled
                default: break
                }
            }
            if currentNode != nil, let property = propertyStack.last {
                let enabled = value.lowercased() == "true"
                switch property {
                case "ripEnabled": currentNode?.ripEnabled = enabled
                case "DHCPKonfiguration": currentNode?.dhcpClientEnabled = enabled
                case "aktiv" where propertyStack.contains("DHCPServer"):
                    currentNode?.dhcpServerConfiguration.isActive = enabled
                case "ownSettings" where propertyStack.contains("DHCPServer"):
                    currentNode?.dhcpServerConfiguration.useOwnSettings = enabled
                case "activated" where propertyStack.contains("firewall") || propertyStack.contains("installierteAnwendungen"):
                    currentNode?.hasFirewallConfiguration = true
                    currentNode?.firewallConfiguration.isActive = enabled
                case "dropICMP":
                    currentNode?.hasFirewallConfiguration = true
                    currentNode?.firewallConfiguration.dropICMP = enabled
                case "filterSYNSegmentsOnly", "allowRelatedPackets":
                    currentNode?.hasFirewallConfiguration = true
                    currentNode?.firewallConfiguration.filterSYNSegmentsOnly = enabled
                case "filterUdp":
                    currentNode?.hasFirewallConfiguration = true
                    currentNode?.firewallConfiguration.filterUDP = enabled
                default: break
                }
            }
        case "long":
            parsingLong = false
            if currentNode != nil, propertyStack.last == "retentionTime", let milliseconds = UInt64(value) {
                currentNode?.switchRetentionTimeMilliseconds = milliseconds
            }

        case "int":
            parsingInt = false

            if let number = Int(value), !boxedIntegerValueStack.isEmpty {
                boxedIntegerValueStack[boxedIntegerValueStack.count - 1] = number
            }

            if currentDocumentation != nil, let number = Int(value), let property = propertyStack.last {
                switch property {
                case "type": currentDocumentation?.type = number
                case "x": currentDocumentation?.x = number
                case "y": currentDocumentation?.y = number
                case "width": currentDocumentation?.width = number
                case "height": currentDocumentation?.height = number
                case "color" where currentDocumentationColorComponents != nil:
                    currentDocumentationColorComponents?.append(number)
                case "font" where currentDocumentationFontValues != nil:
                    currentDocumentationFontValues?.append(number)
                default: break
                }
            } else if currentNode != nil,
                      propertyStack.contains("installierteAnwendungen"),
                      objectClassStack.last == "filius.software.dateiaustausch.PeerToPeerAnwendung",
                      propertyStack.last == "maxTeilnehmerZahl",
                      let number = Int(value)
            {
                currentNode?.gnutellaMaximumKnownPeers = number
            } else if currentNode != nil,
                      propertyStack.contains("installierteAnwendungen"),
                      objectClassStack.last == "filius.software.www.WebServer",
                      propertyStack.last == "port",
                      let number = Int(value)
            {
                currentNode?.webServerPort = number
            } else if currentNode != nil,
               propertyStack.contains("systemSoftware"),
               let property = propertyStack.last,
               let number = Int(value),
               property == "mode" || property == "port"
            {
                if property == "mode" {
                    currentNode?.modemMode = number
                } else {
                    currentNode?.modemPort = number
                }
            } else if currentNode != nil,
               rectangleSetDepth > 0,
               propertyStack.contains("bounds"),
               let number = Int(value),
               let fieldName = rectangleFieldNameStack.last.flatMap({ $0 })
            {
                if fieldName == "x" {
                    currentNode?.x = number
                } else if fieldName == "y" {
                    currentNode?.y = number
                }
            } else if currentNode != nil,
                      propertyStack.contains("bounds"),
                      let number = Int(value),
                      !directBoundsIntIndexStack.isEmpty
            {
                let lastIndex = directBoundsIntIndexStack.count - 1
                let componentIndex = directBoundsIntIndexStack[lastIndex]

                if componentIndex == 0 {
                    currentNode?.x = number
                } else if componentIndex == 1 {
                    currentNode?.y = number
                }

                directBoundsIntIndexStack[lastIndex] = componentIndex + 1
            } else if firewallSetDepth > 0,
                      propertyStack.contains("ruleset"),
                      let number = Int(value),
                      let fieldName = firewallFieldNameStack.last.flatMap({ $0 }) {
                updateCurrentFirewallRule(fieldName: fieldName, intValue: number)
            }

        case "short":
            parsingShort = false
            guard let number = Int(value) else { break }
            if firewallSetDepth > 0,
               propertyStack.contains("ruleset"),
               let fieldName = firewallFieldNameStack.last.flatMap({ $0 }) {
                updateCurrentFirewallRule(fieldName: fieldName, intValue: number)
            } else if let property = propertyStack.last {
                currentNode?.hasFirewallConfiguration = true
                if property == "defaultPolicy", let action = TopologyFirewallAction(rawValue: number) {
                    currentNode?.firewallConfiguration.defaultPolicy = action
                }
            }

        case "array":
            if let valuesByIndex = currentManualRouteValuesByIndex {
                currentManualRouteValuesByIndex = nil
                if let destinationNetwork = valuesByIndex[0],
                   let subnetMask = valuesByIndex[1],
                   let gateway = valuesByIndex[2],
                   let interfaceIPAddress = valuesByIndex[3],
                   valuesByIndex.count == 4
                {
                    currentNode?.manualRoutes.append(
                        TopologyRuntimeManualRoute(
                            destinationNetwork: destinationNetwork,
                            subnetMask: subnetMask,
                            gateway: gateway,
                            interfaceIPAddress: interfaceIPAddress
                        )
                    )
                } else {
                    let foundIndexes = valuesByIndex.keys.sorted().map { String($0) }.joined(separator: ", ")
                    warnings.append(
                        "Ignored malformed FILIUS manual route: expected string indexes 0 through 3, found [\(foundIndexes)]"
                    )
                }
            }

            if let valuesByIndex = currentStaticNATValuesByIndex {
                currentStaticNATValuesByIndex = nil
                if let protocolValue = valuesByIndex[0],
                   let publicPortValue = valuesByIndex[1],
                   let lanIPAddress = valuesByIndex[2],
                   let lanPortValue = valuesByIndex[3],
                   valuesByIndex.count == 4
                {
                    currentNode?.portForwardingRows.append(TopologyGatewayPortForwardingRow(
                        protocolValue: protocolValue,
                        publicPortValue: publicPortValue,
                        lanIPAddress: lanIPAddress,
                        lanPortValue: lanPortValue
                    ))
                } else {
                    let foundIndexes = valuesByIndex.keys.sorted().map { String($0) }.joined(separator: ", ")
                    warnings.append(
                        "Ignored malformed FILIUS static NAT row: expected string indexes 0 through 3, found [\(foundIndexes)]"
                    )
                }
            }

        case "void":
            if currentEmailAddressVoidDepth == voidStack.count {
                finalizeCurrentJavaEmailAddress()
            }
            if let context = voidStack.popLast() {
                if context.method == "getField", rectangleGetFieldDepth > 0 {
                    rectangleGetFieldDepth -= 1
                    if !rectangleFieldNameStack.isEmpty {
                        _ = rectangleFieldNameStack.popLast()
                    }
                }

                if context.method == "set", rectangleSetDepth > 0 {
                    rectangleSetDepth -= 1
                }
                if context.method == "getField", firewallGetFieldDepth > 0, propertyStack.contains("ruleset") {
                    firewallGetFieldDepth -= 1
                    if !firewallFieldNameStack.isEmpty {
                        _ = firewallFieldNameStack.popLast()
                    }
                }
                if context.method == "set", firewallSetDepth > 0, propertyStack.contains("ruleset") {
                    firewallSetDepth -= 1
                }

                if context.property != nil, !propertyStack.isEmpty {
                    _ = propertyStack.popLast()
                }
            }

        case "object":
            let closedClass = objectClassStack.popLast().flatMap { $0 }
            let closedIdentifier = objectIdentifierStack.popLast().flatMap { $0 }
            if closedClass == "java.awt.Color", let components = currentDocumentationColorComponents {
                if let color = documentationColor(fromJavaComponents: components) {
                    currentDocumentation?.color = color
                    if let closedIdentifier { legacyDocumentationColorsByReference[closedIdentifier] = color }
                } else {
                    warnings.append("Ignored unsupported Java documentation color encoding.")
                }
                currentDocumentationColorComponents = nil
            }
            if (closedClass == "java.awt.Font" || closedClass == "javax.swing.plaf.FontUIResource"),
               let values = currentDocumentationFontValues
            {
                let font = DocumentationFont(
                    name: currentDocumentationFontName ?? "Dialog",
                    style: values.count >= 2 ? values[values.count - 2] : 0,
                    size: values.last ?? 12
                )
                currentDocumentation?.fontName = font.name
                currentDocumentation?.fontSize = font.size
                currentDocumentation?.fontStyle = font.style
                if let closedIdentifier {
                    legacyDocumentationFontsByReference[closedIdentifier] = font
                }
                currentDocumentationFontValues = nil
                currentDocumentationFontName = nil
            }
            if closedClass == "java.lang.Integer", !boxedIntegerValueStack.isEmpty {
                let boxedValue = boxedIntegerValueStack.removeLast()
                if let boxedValue {
                    if let closedIdentifier {
                        legacyDocumentationIntegersByReference[closedIdentifier] = boxedValue
                    }
                    if currentDocumentation != nil, let property = propertyStack.last {
                        applyDocumentationInteger(boxedValue, property: property)
                    }
                }
            }
            if closedClass == "java.awt.Rectangle", !directBoundsIntIndexStack.isEmpty {
                _ = directBoundsIntIndexStack.popLast()
            }
            if closedClass == "filius.software.firewall.FirewallRule", let rule = currentFirewallRule {
                currentNode?.firewallConfiguration.rules.append(rule)
                currentNode?.hasFirewallConfiguration = true
                currentFirewallRule = nil
            }
            if closedClass == "filius.software.email.AddressEntry" {
                finalizeCurrentJavaEmailAddress()
            } else if closedClass == "filius.software.email.Email" {
                finalizeCurrentJavaEmailMessage()
            } else if closedClass == "filius.software.email.EmailKonto" {
                finalizeCurrentJavaEmailAccount()
            }
            if closedClass == "filius.software.system.Datei", let file = currentJavaFile {
                if !javaFileTreeStack.isEmpty {
                    javaFileTreeStack[javaFileTreeStack.count - 1].file = file
                }
                currentJavaFile = nil
            } else if closedClass == "javax.swing.tree.DefaultMutableTreeNode",
                      propertyStack.contains("dateisystem"),
                      let completed = javaFileTreeStack.popLast()
            {
                if javaFileTreeStack.isEmpty {
                    currentNode?.fileSystemRoots.append(completed)
                } else {
                    javaFileTreeStack[javaFileTreeStack.count - 1].children.append(completed)
                }
            }
            if closedClass == "filius.gui.netzwerksicht.GUIKnotenItem",
               elementPath == currentSourceNodePath
            {
                finalizeCurrentNodeCandidate()
            } else if closedClass == "filius.gui.netzwerksicht.GUIKabelItem",
                      elementPath == currentCable?.sourcePath
            {
                finalizeCurrentCableCandidate()
            } else if closedClass == "filius.gui.netzwerksicht.GUIDocuItem",
                      elementPath == currentDocumentation?.sourcePath
            {
                finalizeCurrentDocumentationCandidate()
            }

        default:
            break
        }

        currentTextBuffer = ""
    }

    private func boxedDocumentationInteger(for property: String) -> Int? {
        guard property == "maxLayerOfOperation" else { return nil }

        switch currentNode?.knotenClassName {
        case "filius.hardware.knoten.Gateway", "filius.hardware.knoten.Vermittlungsrechner":
            return 2
        case "filius.hardware.knoten.Rechner", "filius.hardware.knoten.Notebook":
            return 4
        default:
            return nil
        }
    }

    private func applyDocumentationInteger(_ value: Int, property: String) {
        switch property {
        case "type": currentDocumentation?.type = value
        case "x": currentDocumentation?.x = value
        case "y": currentDocumentation?.y = value
        case "width": currentDocumentation?.width = value
        case "height": currentDocumentation?.height = value
        default: break
        }
    }

    private func documentationColor(fromJavaComponents components: [Int]) -> TopologyDocumentationColor? {
        let rgba: [Int]
        switch components.count {
        case 1:
            rgba = [0, 0, 0, components[0]]
        case 3:
            rgba = [components[0], components[1], components[2], 255]
        case 4...:
            rgba = Array(components.suffix(4))
        default:
            return nil
        }
        guard rgba.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return TopologyDocumentationColor(
            red: Double(rgba[0]) / 255,
            green: Double(rgba[1]) / 255,
            blue: Double(rgba[2]) / 255,
            alpha: Double(rgba[3]) / 255
        )
    }

    private func finalizeCurrentDocumentationCandidate() {
        guard let candidate = currentDocumentation else { return }
        defer { currentDocumentation = nil }
        guard let type = candidate.type,
              let x = candidate.x,
              let y = candidate.y,
              let width = candidate.width,
              let height = candidate.height,
              width > 0,
              height > 0
        else {
            warnings.append("Skipped malformed Java GUIDocuItem with missing type or geometry.")
            return
        }
        let kind: TopologyDocumentationItemKind
        switch type {
        case 1: kind = .rectangle
        case 2: kind = .text
        default:
            warnings.append("Skipped unsupported Java GUIDocuItem type \(type); supported values are RECT=1 and TEXT=2.")
            return
        }
        let frame = CGRect(x: x, y: y, width: width, height: height)
        guard TopologyDocumentationItem.isSafeFrame(frame) else {
            warnings.append("Skipped Java GUIDocuItem with geometry outside the supported editor bounds.")
            return
        }
        let order = documentationItems.nextDocumentationOrder
        let seed = "java-doc|\(order)|\(type)|\(x)|\(y)|\(width)|\(height)|\(candidate.text)"
        let color = candidate.color ?? (kind == .text ? .black : .paleYellow)
        if candidate.color == nil {
            warnings.append("Java GUIDocuItem \(order + 1) omitted a supported color; applied the native deterministic default.")
        }
        let item = TopologyDocumentationItem(
            id: deterministicDocumentationUUID(seed: seed),
            kind: kind,
            frame: frame,
            text: candidate.text,
            color: color,
            fontName: candidate.fontName,
            fontSize: CGFloat(candidate.fontSize),
            isBold: candidate.fontStyle & 1 == 1,
            order: order
        )
        documentationItems.append(item)
        recognizedDocumentationItemIDsBySourcePath[candidate.sourcePath] = item.id
    }

    private func updateCurrentFirewallRule(fieldName: String, stringValue: String) {
        guard var rule = currentFirewallRule else { return }
        switch fieldName {
        case "srcIP": rule.sourceIPAddress = stringValue
        case "srcMask": rule.sourceSubnetMask = stringValue
        case "destIP": rule.destinationIPAddress = stringValue
        case "destMask": rule.destinationSubnetMask = stringValue
        default: return
        }
        currentFirewallRule = rule
    }

    private func updateCurrentFirewallRule(fieldName: String, intValue: Int) {
        guard var rule = currentFirewallRule else { return }
        switch fieldName {
        case "port":
            rule.port = intValue
        case "protocol":
            guard let protocolType = TopologyFirewallProtocol(rawValue: intValue) else { return }
            rule.protocolType = protocolType
        case "action":
            guard let action = TopologyFirewallAction(rawValue: intValue) else { return }
            rule.action = action
        default:
            return
        }
        currentFirewallRule = rule
    }

    private func beginCurrentInterface(at requestedIndex: Int?) {
        guard var candidate = currentNode else {
            return
        }

        let index = requestedIndex ?? candidate.interfaces.count
        guard index >= 0 else {
            return
        }

        while candidate.interfaces.count <= index {
            candidate.interfaces.append(InterfaceCandidate())
        }

        currentNode = candidate
        currentInterfaceIndex = index
    }

    private func updateCurrentInterface(_ update: (inout InterfaceCandidate) -> Void) {
        guard
            var candidate = currentNode,
            let currentInterfaceIndex,
            candidate.interfaces.indices.contains(currentInterfaceIndex)
        else {
            return
        }

        update(&candidate.interfaces[currentInterfaceIndex])
        currentNode = candidate
    }

    private func javaEmailAddressTarget(for property: String) -> JavaEmailAddressTarget? {
        switch property {
        case "absender": return .sender
        case "empfaenger": return .to
        case "cc": return .cc
        case "bcc": return .bcc
        default: return nil
        }
    }

    private func currentJavaEmailAddressTarget() -> JavaEmailAddressTarget? {
        for property in propertyStack.reversed() {
            if let target = javaEmailAddressTarget(for: property) {
                return target
            }
        }
        return nil
    }

    private func currentJavaEmailMessageContainer() -> JavaEmailMessageContainer? {
        if propertyStack.contains("empfangeneNachrichten") { return .clientInbox }
        if propertyStack.contains("gesendeteNachrichten") { return .clientSent }
        if propertyStack.contains("erstellteNachrichten") { return .clientDrafts }
        if propertyStack.contains("nachrichten"), currentEmailAccountKind == .server { return .serverMailbox }
        return nil
    }

    private func applyJavaEmailAddress(_ address: TopologyRuntimeEmailAddress, target: JavaEmailAddressTarget) {
        guard currentEmailMessage != nil else { return }
        switch target {
        case .sender:
            currentEmailMessage?.sender = address
        case .to:
            currentEmailMessage?.to.append(address)
        case .cc:
            currentEmailMessage?.cc.append(address)
        case .bcc:
            currentEmailMessage?.bcc.append(address)
        }
    }

    private func finalizeCurrentJavaEmailAddress() {
        guard let candidate = currentEmailAddress else { return }
        currentEmailAddress = nil
        currentEmailAddressVoidDepth = nil
        guard let mailAddress = candidate.mailAddress else { return }
        let address = TopologyRuntimeEmailAddress(name: candidate.name, mailAddress: mailAddress)
        guard (try? address.validate()) != nil else { return }
        if let identifier = candidate.identifier {
            emailAddressesByReference[identifier] = address
        }
        applyJavaEmailAddress(address, target: candidate.target)
    }

    private func finalizeCurrentJavaEmailMessage() {
        guard let candidate = currentEmailMessage, let container = currentEmailMessageContainer else { return }
        currentEmailMessage = nil
        currentEmailMessageContainer = nil
        currentEmailAddress = nil
        currentEmailAddressVoidDepth = nil
        guard let sender = candidate.sender else {
            warnings.append(
                "Ignored malformed Java email message with no sender on '\(currentNode?.displayName ?? "unnamed FILIUS node")'."
            )
            return
        }
        var message = TopologyRuntimeEmailMessage(
            from: sender,
            to: candidate.to,
            cc: candidate.cc,
            bcc: candidate.bcc,
            subject: candidate.subject,
            body: candidate.body,
            receivedAtMilliseconds: candidate.receivedAtMilliseconds,
            isNew: candidate.isNew,
            isMarkedForDeletion: candidate.isMarkedForDeletion,
            isSent: candidate.isSent
        )
        if container == .clientSent { message.isSent = true }
        guard (try? message.validate(requireRecipients: false)) != nil else {
            warnings.append(
                "Ignored malformed Java email message on '\(currentNode?.displayName ?? "unnamed FILIUS node")'."
            )
            return
        }
        switch container {
        case .clientInbox:
            currentNode?.emailClientInbox.append(message)
        case .clientSent:
            currentNode?.emailClientSent.append(message)
        case .clientDrafts:
            currentNode?.emailClientDrafts.append(message)
        case .serverMailbox:
            currentEmailAccount?.messages.append(message)
        }
    }

    private func finalizeCurrentJavaEmailAccount() {
        guard let account = currentEmailAccount, let kind = currentEmailAccountKind else { return }
        currentEmailAccount = nil
        currentEmailAccountKind = nil
        switch kind {
        case .client:
            currentNode?.emailClientAccounts.append(account)
            pendingEmailClientMapKey = nil
        case .server:
            currentNode?.emailServerAccounts.append(account)
        }
    }

    private func javaEmailAccountsMatch(
        _ lhs: JavaEmailAccountCandidate,
        _ rhs: JavaEmailAccountCandidate
    ) -> Bool {
        lhs.username == rhs.username
            && lhs.password == rhs.password
            && lhs.lastName == rhs.lastName
            && lhs.firstName == rhs.firstName
            && lhs.pop3Server == rhs.pop3Server
            && lhs.smtpServer == rhs.smtpServer
            && lhs.pop3Port == rhs.pop3Port
            && lhs.smtpPort == rhs.smtpPort
            && lhs.emailAddress == rhs.emailAddress
    }

    private func assignedJavaEmailMessages(
        _ messages: [TopologyRuntimeEmailMessage],
        nextID: inout UInt64,
        sent: Bool? = nil
    ) -> [TopologyRuntimeEmailMessage] {
        messages.map { source in
            var message = source
            message.id = nextID
            if let sent { message.isSent = sent }
            nextID += 1
            return message
        }
    }

    private func javaEmailClientConfiguration(
        from account: JavaEmailAccountCandidate,
        inbox: [TopologyRuntimeEmailMessage],
        sent: [TopologyRuntimeEmailMessage],
        drafts: [TopologyRuntimeEmailMessage]
    ) -> TopologyRuntimeEmailClientConfiguration? {
        guard let username = account.username,
              let password = account.password,
              let pop3Host = account.pop3Server,
              let smtpHost = account.smtpServer,
              let email = account.emailAddress,
              let pop3Port = Int(account.pop3Port ?? "110"),
              let smtpPort = Int(account.smtpPort ?? "25")
        else { return nil }
        var nextMessageID: UInt64 = 1
        let resolvedInbox = assignedJavaEmailMessages(inbox, nextID: &nextMessageID)
        let resolvedSent = assignedJavaEmailMessages(sent, nextID: &nextMessageID, sent: true)
        let resolvedDrafts = assignedJavaEmailMessages(drafts, nextID: &nextMessageID, sent: false)
        let configuration = TopologyRuntimeEmailClientConfiguration(
            pop3Host: pop3Host,
            pop3Port: pop3Port,
            smtpHost: smtpHost,
            smtpPort: smtpPort,
            username: username,
            password: password,
            name: [account.firstName, account.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "),
            email: email,
            inbox: resolvedInbox,
            sent: resolvedSent,
            drafts: resolvedDrafts,
            nextMessageID: nextMessageID
        )
        guard (try? configuration.validate()) != nil else { return nil }
        return configuration
    }

    private func importedJavaEmailClientFileConfiguration(
        fileSystem: TopologyVirtualFileSystem,
        node: TopologyNode
    ) -> (configuration: TopologyRuntimeEmailClientConfiguration, preservesMessages: Bool)? {
        if fileSystem.contains(TopologyRuntimeEmailStorage.clientNativePath) {
            do {
                return (
                    try TopologyRuntimeEmailStorage.decodeNativeClient(
                        fileSystem.textFile(at: TopologyRuntimeEmailStorage.clientNativePath)
                    ),
                    true
                )
            } catch {
                warnings.append(
                    "Ignored malformed native Email Client storage on '\(node.displayName)'; attempted Java /konten.txt fallback."
                )
            }
        }
        if fileSystem.contains(TopologyRuntimeEmailStorage.clientJavaPath) {
            do {
                return (
                    try TopologyRuntimeEmailStorage.decodeJavaClient(
                        fileSystem.textFile(at: TopologyRuntimeEmailStorage.clientJavaPath)
                    ),
                    false
                )
            } catch {
                warnings.append("Ignored malformed Java /konten.txt Email Client storage on '\(node.displayName)'.")
            }
        }
        return nil
    }

    private func importedJavaEmailServerFileConfiguration(
        fileSystem: TopologyVirtualFileSystem,
        fallbackDomain: String,
        node: TopologyNode
    ) -> TopologyRuntimeEmailServerConfiguration? {
        if fileSystem.contains(TopologyRuntimeEmailStorage.serverNativePath) {
            do {
                return try TopologyRuntimeEmailStorage.decodeNativeServer(
                    fileSystem.textFile(at: TopologyRuntimeEmailStorage.serverNativePath)
                )
            } catch {
                warnings.append(
                    "Ignored malformed native Email Server storage on '\(node.displayName)'; attempted Java /mailserver/konten.txt fallback."
                )
            }
        }
        if fileSystem.contains(TopologyRuntimeEmailStorage.serverJavaPath) {
            do {
                return try TopologyRuntimeEmailStorage.decodeJavaServer(
                    fileSystem.textFile(at: TopologyRuntimeEmailStorage.serverJavaPath),
                    fallbackDomain: fallbackDomain
                )
            } catch {
                warnings.append("Ignored malformed Java /mailserver/konten.txt Email Server storage on '\(node.displayName)'.")
            }
        }
        return nil
    }

    private func registerJavaEmailConfigurations(candidate: NodeCandidate, node: TopologyNode) {
        guard node.kind.isPCClassEndpoint else {
            if candidate.hasEmailClientApplication || candidate.hasEmailServerApplication {
                warnings.append("Ignored Java email applications on unsupported node kind '\(node.kind.rawValue)' at '\(node.displayName)'.")
            }
            return
        }
        let fileSystem = virtualFileSystemsByNodeID[node.id] ?? .defaultForDevice()

        if candidate.hasEmailClientApplication {
            runtimeInstalledProgramsByNodeID[node.id, default: []].insert(.emailClient)
            for (index, account) in candidate.emailClientAccounts.enumerated() {
                let mapKey = account.mapKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let username = account.username?.lowercased() ?? ""
                let emailAddress = account.emailAddress?.lowercased() ?? ""
                if mapKey.isEmpty || (mapKey.lowercased() != username && mapKey.lowercased() != emailAddress) {
                    warnings.append(
                        "Email Client on '\(node.displayName)' has inconsistent kontoListe map entry #\(index + 1); account bean values remain authoritative."
                    )
                }
                if candidate.emailClientAccounts[..<index].contains(where: { javaEmailAccountsMatch($0, account) }) {
                    warnings.append(
                        "Email Client on '\(node.displayName)' ignored duplicate kontoListe account entry #\(index + 1)."
                    )
                } else if !mapKey.isEmpty,
                          candidate.emailClientAccounts[..<index].contains(where: {
                              $0.mapKey?.caseInsensitiveCompare(mapKey) == .orderedSame && !javaEmailAccountsMatch($0, account)
                          })
                {
                    warnings.append(
                        "Email Client on '\(node.displayName)' has an inconsistent duplicate kontoListe key at entry #\(index + 1); the first deterministic account entry is used."
                    )
                }
            }

            let beanConfigurations = candidate.emailClientAccounts.compactMap {
                javaEmailClientConfiguration(
                    from: $0,
                    inbox: candidate.emailClientInbox,
                    sent: candidate.emailClientSent,
                    drafts: candidate.emailClientDrafts
                )
            }
            if beanConfigurations.count < candidate.emailClientAccounts.count {
                warnings.append("Email Client on '\(node.displayName)' ignored one or more malformed EmailKonto bean entries.")
            }
            if beanConfigurations.count > 1,
               beanConfigurations.dropFirst().contains(where: { $0 != beanConfigurations[0] })
            {
                warnings.append(
                    "Email Client on '\(node.displayName)' contains multiple inconsistent valid accounts; imported the first deterministic EmailKonto entry."
                )
            }

            let fileConfiguration = importedJavaEmailClientFileConfiguration(fileSystem: fileSystem, node: node)
            var resolved = beanConfigurations.first ?? fileConfiguration?.configuration
            if beanConfigurations.isEmpty,
               var fileOnlyConfiguration = fileConfiguration?.configuration,
               fileConfiguration?.preservesMessages == false
            {
                var nextMessageID: UInt64 = 1
                fileOnlyConfiguration.inbox = assignedJavaEmailMessages(
                    candidate.emailClientInbox,
                    nextID: &nextMessageID
                )
                fileOnlyConfiguration.sent = assignedJavaEmailMessages(
                    candidate.emailClientSent,
                    nextID: &nextMessageID,
                    sent: true
                )
                fileOnlyConfiguration.drafts = assignedJavaEmailMessages(
                    candidate.emailClientDrafts,
                    nextID: &nextMessageID,
                    sent: false
                )
                fileOnlyConfiguration.nextMessageID = nextMessageID
                resolved = fileOnlyConfiguration
            }
            if var beanConfiguration = beanConfigurations.first, let fileConfiguration {
                if beanConfiguration.pop3Host != fileConfiguration.configuration.pop3Host
                    || beanConfiguration.pop3Port != fileConfiguration.configuration.pop3Port
                    || beanConfiguration.smtpHost != fileConfiguration.configuration.smtpHost
                    || beanConfiguration.smtpPort != fileConfiguration.configuration.smtpPort
                    || beanConfiguration.username != fileConfiguration.configuration.username
                    || beanConfiguration.password != fileConfiguration.configuration.password
                    || beanConfiguration.name != fileConfiguration.configuration.name
                    || beanConfiguration.email != fileConfiguration.configuration.email
                {
                    warnings.append(
                        "Email Client on '\(node.displayName)' has inconsistent EmailKonto bean and /konten.txt account fields; imported the first deterministic bean account."
                    )
                }
                if fileConfiguration.preservesMessages {
                    beanConfiguration.inbox = fileConfiguration.configuration.inbox
                    beanConfiguration.sent = fileConfiguration.configuration.sent
                    beanConfiguration.drafts = fileConfiguration.configuration.drafts
                    beanConfiguration.nextMessageID = fileConfiguration.configuration.nextMessageID
                }
                resolved = beanConfiguration
            }
            if let resolved, (try? resolved.validate()) != nil {
                runtimeEmailClientConfigurationsByNodeID[node.id] = resolved
            } else {
                warnings.append("Email Client on '\(node.displayName)' was installed without a valid importable account configuration.")
            }
        }

        if candidate.hasEmailServerApplication {
            runtimeInstalledProgramsByNodeID[node.id, default: []].insert(.emailServer)
            let candidateDomain = candidate.emailServerDomain?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let fallbackDomain = candidateDomain.flatMap {
                TopologyRuntimeEmailAddress.isValidDomain($0) ? $0 : nil
            } ?? "filius.de"
            if candidateDomain != nil, candidateDomain != fallbackDomain {
                warnings.append("Email Server on '\(node.displayName)' ignored an invalid mailDomain bean value.")
            }
            let fileConfiguration = importedJavaEmailServerFileConfiguration(
                fileSystem: fileSystem,
                fallbackDomain: fallbackDomain,
                node: node
            )
            let resolvedDomain = candidateDomain.flatMap {
                TopologyRuntimeEmailAddress.isValidDomain($0) ? $0 : nil
            } ?? fileConfiguration?.domain ?? fallbackDomain
            if let fileConfiguration, candidateDomain != nil, fileConfiguration.domain != resolvedDomain {
                warnings.append(
                    "Email Server on '\(node.displayName)' has inconsistent mailDomain bean and /mailserver/konten.txt values; imported the bean domain."
                )
            }

            var accounts: [TopologyRuntimeEmailServerAccount] = []
            var seenUsernames = Set<String>()
            let fileAccountsByUsername = Dictionary(
                uniqueKeysWithValues: (fileConfiguration?.accounts ?? []).map { ($0.username.lowercased(), $0) }
            )
            for (index, account) in candidate.emailServerAccounts.enumerated() {
                guard let username = account.username,
                      let password = account.password
                else {
                    warnings.append("Email Server on '\(node.displayName)' ignored malformed EmailKonto bean entry #\(index + 1).")
                    continue
                }
                let normalizedUsername = username.lowercased()
                guard seenUsernames.insert(normalizedUsername).inserted else {
                    warnings.append("Email Server on '\(node.displayName)' ignored duplicate EmailKonto bean entry #\(index + 1).")
                    continue
                }
                let beanName = [account.firstName, account.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                var serverAccount = TopologyRuntimeEmailServerAccount(
                    username: username,
                    password: password,
                    name: beanName,
                    mailbox: account.messages
                )
                if let fileAccount = fileAccountsByUsername[normalizedUsername] {
                    if fileAccount.username != serverAccount.username
                        || fileAccount.password != serverAccount.password
                        || fileAccount.name != serverAccount.name
                    {
                        warnings.append(
                            "Email Server on '\(node.displayName)' has inconsistent EmailKonto bean and /mailserver/konten.txt fields at account entry #\(index + 1); imported bean account fields."
                        )
                    }
                    serverAccount.mailbox = fileAccount.mailbox
                }
                guard (try? serverAccount.emailAddress(domain: resolvedDomain).validate()) != nil,
                      (try? TopologyRuntimeEmailServerAccount.validateUsername(serverAccount.username)) != nil,
                      (try? TopologyRuntimeEmailServerAccount.validatePassword(serverAccount.password)) != nil
                else {
                    warnings.append("Email Server on '\(node.displayName)' ignored malformed EmailKonto bean entry #\(index + 1).")
                    continue
                }
                accounts.append(serverAccount)
            }
            if candidate.emailServerAccounts.isEmpty, let fileConfiguration {
                accounts = fileConfiguration.accounts
                seenUsernames = Set(accounts.map { $0.username.lowercased() })
            } else if let fileConfiguration {
                for fileAccount in fileConfiguration.accounts.sorted(by: {
                    let lhs = ($0.username.lowercased(), $0.username)
                    let rhs = ($1.username.lowercased(), $1.username)
                    return lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
                }) where seenUsernames.insert(fileAccount.username.lowercased()).inserted {
                    accounts.append(fileAccount)
                    warnings.append(
                        "Email Server on '\(node.displayName)' preserved a /mailserver/konten.txt account that was absent from the EmailKonto bean list."
                    )
                }
            }

            var nextMessageID: UInt64 = 1
            for accountIndex in accounts.indices {
                accounts[accountIndex].mailbox = assignedJavaEmailMessages(
                    accounts[accountIndex].mailbox,
                    nextID: &nextMessageID
                )
            }
            let configuration = TopologyRuntimeEmailServerConfiguration(
                domain: resolvedDomain,
                pop3Port: fileConfiguration?.pop3Port ?? 110,
                accounts: accounts,
                nextMessageID: nextMessageID
            )
            if (try? configuration.validate()) != nil {
                runtimeEmailServerConfigurationsByNodeID[node.id] = configuration
            } else {
                warnings.append("Email Server on '\(node.displayName)' was installed without a valid importable account configuration.")
            }
        }
    }

    private func finalizeCurrentNodeCandidate() {
        guard let candidate = currentNode else {
            return
        }
        currentNode = nil
        currentInterfaceIndex = nil
        let sourceNodePath = currentSourceNodePath
        currentSourceNodePath = nil

        let normalizedTypeName = candidate.typeName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedClassName = candidate.knotenClassName?.trimmingCharacters(in: .whitespacesAndNewlines)

        let nodeKind: TopologyNodeKind
        if let typeName = normalizedTypeName, !typeName.isEmpty {
            guard let mapped = mapLegacyNodeType(typeName) else {
                skippedNodeCount += 1
                warnings.append("Skipped unsupported FILIUS node type '\(typeName)' in konfiguration.xml")
                return
            }
            nodeKind = mapped
        } else if let className = normalizedClassName, !className.isEmpty {
            guard let mapped = mapLegacyNodeClass(className) else {
                skippedNodeCount += 1
                warnings.append("Skipped unsupported FILIUS node class '\(className)' in konfiguration.xml")
                return
            }
            nodeKind = mapped
        } else {
            skippedNodeCount += 1
            warnings.append("Skipped FILIUS node with missing type label in konfiguration.xml")
            return
        }

        guard let x = candidate.x, let y = candidate.y else {
            skippedNodeCount += 1
            warnings.append("Skipped FILIUS node with missing bounds coordinates")
            return
        }

        let ports = importedPorts(for: nodeKind, candidate: candidate)
        let node = TopologyNode(
            id: UUID(),
            kind: nodeKind,
            displayName: candidate.displayName,
            position: CGPoint(x: x, y: y),
            ports: ports
        )
        nodes.append(node)
        if let sourceNodePath {
            recognizedNodeIDsBySourcePath[sourceNodePath] = node.id
        }

        registerLegacyPortReferences(candidate: candidate, node: node)
        registerRuntimeConfigurations(candidate: candidate, node: node)
        registerRemoteLinkConfiguration(candidate: candidate, node: node)
        registerSwitchAndWirelessConfigurations(candidate: candidate, node: node)
        registerVirtualFileSystem(candidate: candidate, node: node)
        registerJavaEmailConfigurations(candidate: candidate, node: node)
        if node.kind.isPCClassEndpoint, candidate.hasWebServerApplication {
            var fileSystem = virtualFileSystemsByNodeID[node.id] ?? .defaultForDevice()
            do {
                fileSystem = try remappingVirtualFileSystemRoot(
                    fileSystem,
                    from: "/webserver",
                    to: TopologyRuntimeWebServerConfiguration.defaultDocumentRoot
                )
            } catch {
                warnings.append(
                    "Could not map Java web root '/webserver' to native '/www' on '\(node.displayName)': \(error.localizedDescription)"
                )
            }
            if !fileSystem.contains(TopologyRuntimeWebServerConfiguration.defaultDocumentRoot) {
                try? fileSystem.createDirectory(at: TopologyRuntimeWebServerConfiguration.defaultDocumentRoot, recursive: true)
            }
            if !fileSystem.contains("/www/index.html"), let rootIndex = try? fileSystem.textFile(at: "/index.html") {
                try? fileSystem.writeTextFile(at: "/www/index.html", text: rootIndex)
            }
            virtualFileSystemsByNodeID[node.id] = fileSystem
        }
        if node.kind.isPCClassEndpoint, candidate.hasGnutellaApplication {
            runtimeInstalledProgramsByNodeID[node.id, default: []].insert(.gnutella)
            let importedMaximum = candidate.gnutellaMaximumKnownPeers
                ?? TopologyRuntimeGnutellaConfiguration.javaDefaultMaximumKnownPeers
            let configuration = TopologyRuntimeGnutellaConfiguration(maximumKnownPeers: importedMaximum)
            var fileSystem = virtualFileSystemsByNodeID[node.id] ?? .defaultForDevice()
            if let data = try? JSONEncoder().encode(configuration),
               let encoded = String(data: data, encoding: .utf8) {
                try? fileSystem.createDirectory(at: TopologyGnutella.peerToPeerDirectory, recursive: true)
                try? fileSystem.writeTextFile(
                    at: TopologyRuntimeGnutellaStorage.nativeConfigurationPath,
                    text: encoded,
                    overwrite: true
                )
                virtualFileSystemsByNodeID[node.id] = fileSystem
            }
        }
        if node.kind.isPCClassEndpoint, candidate.hasDNSServerApplication {
            runtimeInstalledProgramsByNodeID[node.id, default: []].insert(.dnsServer)
        }
        if node.kind.isPCClassEndpoint, candidate.hasPersonalFirewallApplication {
            runtimeInstalledProgramsByNodeID[node.id, default: []].insert(.firewall)
            runtimeFirewallConfigurationsByNodeID[node.id] = candidate.firewallConfiguration
        }
        if node.kind.isPCClassEndpoint, candidate.hasWebServerApplication {
            runtimeInstalledProgramsByNodeID[node.id, default: []].insert(.webServer)
            runtimeWebServerConfigurationsByNodeID[node.id] = TopologyRuntimeWebServerConfiguration(port: candidate.webServerPort ?? TopologyRuntimeWebServerConfiguration.defaultPort)
        }
        if node.kind.isPCClassEndpoint, candidate.hasWebBrowserApplication {
            runtimeInstalledProgramsByNodeID[node.id, default: []].insert(.webBrowser)
        }
        registerManualRoutes(candidate: candidate, node: node)
        if node.kind == .router, candidate.ripEnabled {
            runtimeRIPEnabledByNodeID[node.id] = true
        }
        if (node.kind.isPCClassEndpoint || node.kind == .gateway), candidate.dhcpClientEnabled {
            runtimeDHCPClientConfigurationsByNodeID[node.id] = TopologyDHCPClientConfiguration(isEnabled: true)
        }
        if (node.kind.isPCClassEndpoint || node.kind == .gateway),
           candidate.dhcpServerConfiguration != TopologyDHCPServerConfiguration() {
            runtimeDHCPServerConfigurationsByNodeID[node.id] = candidate.dhcpServerConfiguration
        }
        if (node.kind == .router || node.kind == .gateway), candidate.hasFirewallConfiguration {
            runtimeFirewallConfigurationsByNodeID[node.id] = candidate.firewallConfiguration
        }
        if node.kind == .gateway, !candidate.portForwardingRows.isEmpty {
            runtimePortForwardingRowsByNodeID[node.id] = candidate.portForwardingRows
        }
    }

    private func importedPorts(for nodeKind: TopologyNodeKind, candidate: NodeCandidate) -> [TopologyPortMetadata] {
        switch nodeKind {
        case .pc, .notebook:
            return [TopologyPortMetadata(label: "eth0")]
        case .networkSwitch:
            let highestReferencedIndex = candidate.switchPortReferencesByIndex.keys.max() ?? -1
            let count = max(24, highestReferencedIndex + 1)
            return (1...count).map { TopologyPortMetadata(label: "sw\($0)") }
        case .router:
            let count = max(1, candidate.interfaces.count)
            return (1...count).map { TopologyPortMetadata(label: "rt\($0)") }
        case .gateway:
            let count = max(2, candidate.interfaces.count)
            return (0..<count).map { index in
                if index == 0 {
                    return TopologyPortMetadata(label: "wan0")
                }
                if index == 1 {
                    return TopologyPortMetadata(label: "lan0")
                }
                return TopologyPortMetadata(label: "gw\(index)")
            }
        case .remoteLink:
            return [TopologyPortMetadata(label: "remote0")]
        case .unsupported:
            return []
        }
    }

    private func registerLegacyPortReferences(candidate: NodeCandidate, node: TopologyNode) {
        if node.kind == .networkSwitch || node.kind == .remoteLink {
            for (index, reference) in candidate.switchPortReferencesByIndex where node.ports.indices.contains(index) {
                registerLegacyPortReference(reference, nodeID: node.id, portID: node.ports[index].id)
            }
            return
        }

        for (index, interface) in candidate.interfaces.enumerated() where node.ports.indices.contains(index) {
            guard let reference = interface.legacyPortReference else {
                continue
            }
            registerLegacyPortReference(reference, nodeID: node.id, portID: node.ports[index].id)
        }
    }

    private func registerLegacyPortReference(_ reference: String, nodeID: UUID, portID: UUID) {
        if legacyPortEndpointByReference[reference] != nil {
            warnings.append("Ignored duplicate FILIUS port reference '\(reference)'")
            return
        }
        legacyPortEndpointByReference[reference] = LegacyPortEndpoint(nodeID: nodeID, portID: portID)
    }

    private func registerRuntimeConfigurations(candidate: NodeCandidate, node: TopologyNode) {
        if node.kind.isPCClassEndpoint {
            let interface = candidate.interfaces.first ?? InterfaceCandidate()
            let ipAddress = normalizedOrDefault(interface.ipAddress, defaultValue: "192.168.0.10")
            let subnetMask = normalizedOrDefault(interface.subnetMask, defaultValue: "255.255.255.0")
            let defaultGateway = interface.defaultGateway?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            runtimeDeviceConfigurations[node.id] = TopologyRuntimeDeviceConfiguration(
                ipAddress: ipAddress,
                subnetMask: subnetMask,
                defaultGateway: defaultGateway,
                dnsServer: interface.dnsServer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
            return
        }

        guard node.kind == .router || node.kind == .gateway else {
            return
        }

        for (index, port) in node.ports.enumerated() {
            let interface = candidate.interfaces.indices.contains(index)
                ? candidate.interfaces[index]
                : InterfaceCandidate()
            let defaultIPAddress = node.kind == .gateway && index == 0 ? "42.0.0.10" : "192.168.0.10"
            let defaultSubnetMask = node.kind == .gateway && index == 0 ? "255.0.0.0" : "255.255.255.0"
            let configuration = TopologyRuntimeInterfaceConfiguration(
                ipAddress: normalizedOrDefault(interface.ipAddress, defaultValue: defaultIPAddress),
                subnetMask: normalizedOrDefault(interface.subnetMask, defaultValue: defaultSubnetMask)
            )
            runtimeInterfaceConfigurations[
                TopologyRuntimeInterfaceKey(nodeID: node.id, portID: port.id)
            ] = configuration
        }
        if node.kind == .gateway, let wan = candidate.interfaces.first {
            let wanKey = TopologyRuntimeInterfaceKey(nodeID: node.id, portID: node.ports[0].id)
            let wanConfiguration = runtimeInterfaceConfigurations[wanKey]
            runtimeDeviceConfigurations[node.id] = TopologyRuntimeDeviceConfiguration(
                ipAddress: wanConfiguration?.ipAddress ?? "",
                subnetMask: wanConfiguration?.subnetMask ?? "",
                defaultGateway: wan.defaultGateway?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                dnsServer: wan.dnsServer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
    }

    private func registerRemoteLinkConfiguration(candidate: NodeCandidate, node: TopologyNode) {
        guard node.kind == .remoteLink else { return }

        let defaultPort = 12_345
        let port: Int
        if let requestedPort = candidate.modemPort, (1...65_535).contains(requestedPort) {
            port = requestedPort
        } else {
            port = defaultPort
            if let requestedPort = candidate.modemPort {
                warnings.append(
                    "Java Modem '\(node.displayName)' declared invalid port \(requestedPort); using deterministic compatibility port \(defaultPort)."
                )
            }
        }

        let mode = candidate.modemMode ?? 2
        let modeName: String
        switch mode {
        case 1: modeName = "SERVER"
        case 2: modeName = "CLIENT"
        default:
            modeName = "UNKNOWN"
            warnings.append(
                "Java Modem '\(node.displayName)' declared unknown firmware mode \(mode); treating it as CLIENT for compatibility metadata."
            )
        }
        let ipAddress = normalizedOrDefault(candidate.modemIPAddress, defaultValue: "localhost")
        let pairIdentifier = "java-modem-port-\(port)"
        remoteLinkConfigurationsByNodeID[node.id] = TopologyRemoteLinkConfiguration(
            pairIdentifier: pairIdentifier,
            latencyMilliseconds: TopologyRemoteLinkConfiguration.defaultLatencyMilliseconds,
            isEnabled: true
        )
        warnings.append(
            "Imported Java Modem '\(node.displayName)' as Remote Link pair '\(pairIdentifier)' (mode=\(modeName) [\(mode)], ip=\(ipAddress), port=\(port)); host socket transport was replaced by deterministic in-project pairing by normalized port, and cross-host identity is not preserved."
        )
    }

    private func registerSwitchAndWirelessConfigurations(candidate: NodeCandidate, node: TopologyNode) {
        if node.kind == .networkSwitch {
            let defaultConfiguration = TopologySwitchConfiguration.defaultConfiguration(nodeID: node.id)
            let ssid = candidate.switchSSID?.trimmingCharacters(in: .whitespacesAndNewlines)
            switchConfigurationsByNodeID[node.id] = TopologySwitchConfiguration(
                ssid: ssid?.isEmpty == false ? ssid! : defaultConfiguration.ssid,
                retentionTimeMilliseconds: candidate.switchRetentionTimeMilliseconds
                    ?? TopologySwitchConfiguration.defaultRetentionTimeMilliseconds
            )
        }
        if node.kind.isPCClassEndpoint,
           let ssid = candidate.hostWirelessSSID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ssid.isEmpty {
            hostWirelessConfigurationsByNodeID[node.id] = TopologyHostWirelessConfiguration(
                isEnabled: true,
                ssid: ssid
            )
        }
    }

    private func registerVirtualFileSystem(candidate: NodeCandidate, node: TopologyNode) {
        guard node.kind.isPCClassEndpoint, candidate.hasFileSystem else { return }
        var fileSystem = TopologyVirtualFileSystem()

        func importedContent(for file: JavaFileCandidate, path: String) -> TopologyVirtualFileContent {
            let type = file.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            let content = file.content ?? ""
            let extensionValue = (path as NSString).pathExtension.lowercased()
            let imageTypes = Set(["png", "jpg", "jpeg", "gif", "bmp", "image"])
            let textTypes = Set(["", "text", "txt", "text/txt", "html", "htm", "css", "xml", "csv", "conf", "log"])

            if imageTypes.contains(type) || imageTypes.contains(extensionValue) {
                if let data = Data(base64Encoded: content, options: [.ignoreUnknownCharacters]) {
                    let mediaSubtype = type == "image" || type.isEmpty ? (extensionValue.isEmpty ? "png" : extensionValue) : type
                    return .image(data, mediaType: "image/\(mediaSubtype == "jpg" ? "jpeg" : mediaSubtype)")
                }
                warnings.append("Java file '\(path)' declared image type '\(type)' but was not valid Base64; imported as UTF-8 binary data.")
                return .binary(Data(content.utf8), mediaType: type.isEmpty ? nil : "application/\(type)")
            }
            if textTypes.contains(type) {
                return .text(content)
            }
            if let binaryContent = topologyImportedUnknownJavaFileBinaryContent(type: type, content: content) {
                warnings.append("Java file '\(path)' used unknown type '\(type)'; preserved as binary data.")
                return binaryContent
            }
            warnings.append("Java file '\(path)' used unknown type '\(type)'; preserved as UTF-8 text.")
            return .text(content)
        }

        func append(_ candidate: JavaFileTreeCandidate, parentPath: String) {
            if let file = candidate.file {
                guard let rawName = file.name,
                      !rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !rawName.contains("/"),
                      !rawName.contains("\\")
                else {
                    warnings.append("Ignored Java filesystem file with missing or unsafe name on '\(node.displayName)'.")
                    return
                }
                let rawPath = parentPath == "/" ? "/\(rawName)" : "\(parentPath)/\(rawName)"
                do {
                    let path = try TopologyVirtualFileSystem.normalizedAbsolutePath(rawPath)
                    let content = importedContent(for: file, path: path)
                    switch content {
                    case let .text(value):
                        try fileSystem.writeTextFile(at: path, text: value, overwrite: false)
                    case let .binary(data, mediaType):
                        try fileSystem.writeBinaryFile(at: path, data: data, mediaType: mediaType, overwrite: false)
                    case let .image(data, mediaType):
                        try fileSystem.writeImageFile(at: path, data: data, mediaType: mediaType, overwrite: false)
                    case .directory:
                        break
                    }
                } catch {
                    warnings.append("Ignored Java filesystem file '\(rawPath)' on '\(node.displayName)': \(error.localizedDescription)")
                }
                return
            }

            guard let rawName = candidate.directoryName,
                  !rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !rawName.contains("/"),
                  !rawName.contains("\\")
            else {
                warnings.append("Ignored Java filesystem directory with missing or unsafe name on '\(node.displayName)'.")
                return
            }
            let rawPath = parentPath == "/" ? "/\(rawName)" : "\(parentPath)/\(rawName)"
            do {
                let path = try TopologyVirtualFileSystem.normalizedAbsolutePath(rawPath)
                try fileSystem.createDirectory(at: path, recursive: true)
                for child in candidate.children {
                    append(child, parentPath: path)
                }
            } catch {
                warnings.append("Ignored Java filesystem directory '\(rawPath)' on '\(node.displayName)': \(error.localizedDescription)")
            }
        }

        for root in candidate.fileSystemRoots {
            append(root, parentPath: "/")
        }
        virtualFileSystemsByNodeID[node.id] = fileSystem
    }

    private func registerManualRoutes(candidate: NodeCandidate, node: TopologyNode) {
        guard !candidate.manualRoutes.isEmpty else {
            return
        }

        guard node.kind.isPCClassEndpoint || node.kind == .router || node.kind == .gateway else {
            warnings.append("Ignored FILIUS manual routes for unsupported node kind '\(node.kind.rawValue)'")
            return
        }

        runtimeManualRoutesByNodeID[node.id] = candidate.manualRoutes
    }

    private func normalizedOrDefault(_ value: String?, defaultValue: String) -> String {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines), !normalized.isEmpty else {
            return defaultValue
        }
        return normalized
    }

    private func finalizeCurrentCableCandidate() {
        guard let candidate = currentCable else {
            return
        }
        currentCable = nil
        cableCandidates.append(candidate)
    }

    private func resolveCableCandidates() {
        var occupiedPortIDs: Set<UUID> = []

        for (index, candidate) in cableCandidates.enumerated() {
            guard candidate.legacyPortReferences.count == 2 else {
                warnings.append(
                    "Skipped FILIUS cable \(index + 1): expected two port references, found \(candidate.legacyPortReferences.count)"
                )
                continue
            }

            let sourceReference = candidate.legacyPortReferences[0]
            let targetReference = candidate.legacyPortReferences[1]
            guard
                let source = legacyPortEndpointByReference[sourceReference],
                let target = legacyPortEndpointByReference[targetReference]
            else {
                warnings.append(
                    "Skipped FILIUS cable \(index + 1): unresolved port references '\(sourceReference)' and '\(targetReference)'"
                )
                continue
            }

            guard source.nodeID != target.nodeID else {
                warnings.append("Skipped FILIUS cable \(index + 1): self-connections are unsupported")
                continue
            }

            guard !occupiedPortIDs.contains(source.portID), !occupiedPortIDs.contains(target.portID) else {
                warnings.append("Skipped FILIUS cable \(index + 1): a referenced port is already connected")
                continue
            }

            occupiedPortIDs.insert(source.portID)
            occupiedPortIDs.insert(target.portID)
            let link = TopologyLink(
                sourceNodeID: source.nodeID,
                sourcePortID: source.portID,
                targetNodeID: target.nodeID,
                targetPortID: target.portID
            )
            links.append(link)
            recognizedLinkIDsBySourcePath[candidate.sourcePath] = link.id
        }
    }

    private func mapLegacyNodeType(_ value: String) -> TopologyNodeKind? {
        switch normalizeLegacyNodeToken(value) {
        case "computer", "rechner":
            return .pc
        case "laptop", "notebook":
            return .notebook
        case "switch", "switchhub", "switch hub", "switch wlan", "wlan switch":
            return .networkSwitch
        case "vermittlungsrechner", "router":
            return .router
        case "gateway":
            return .gateway
        case "modem", "remotelink", "remote link":
            return .remoteLink
        default:
            return nil
        }
    }

    private func mapLegacyNodeClass(_ value: String) -> TopologyNodeKind? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        let classToken: String
        if trimmedValue.lowercased().hasPrefix("filius.hardware.knoten.") {
            classToken = String(trimmedValue.split(separator: ".").last ?? "")
        } else {
            classToken = trimmedValue
        }

        switch classToken.lowercased() {
        case "rechner":
            return .pc
        case "notebook":
            return .notebook
        case "switch":
            return .networkSwitch
        case "vermittlungsrechner":
            return .router
        case "gateway":
            return .gateway
        case "modem", "remotelink", "remote link":
            return .remoteLink
        default:
            return nil
        }
    }

    private func normalizeLegacyNodeToken(_ value: String) -> String {
        let trimmedLowercased = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let spaceNormalized = trimmedLowercased.map { character in
            if character.isLetter || character.isNumber {
                return character
            }
            return Character(" ")
        }

        return String(spaceNormalized)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

private final class TopologyFLSNativeXMLSink {
    private struct EscapedValue { let value: String; let context: String }
    private let limit = 32 * 1_024 * 1_024
    private var data = Data()
    private var firstLine = true
    private var nextToken = 0
    private var values: [String: EscapedValue] = [:]
    private var storedError: TopologyFLSCompatibilityError?
    private(set) var sanitizationWarnings: [String] = []

    func registerEscapedText(_ value: String, context: String) -> String {
        nextToken += 1
        let token = "\u{E000}FLS\(nextToken)\u{E001}"
        values[token] = EscapedValue(value: value, context: context)
        return token
    }

    func append(contentsOf lines: [String]) { for line in lines { append(line) } }

    func append(_ line: String) {
        guard storedError == nil else { return }
        do {
            if !firstLine { try appendRaw("\n".utf8) }
            firstLine = false
            var cursor = line.startIndex
            while let start = line[cursor...].firstIndex(of: "\u{E000}") {
                try appendRaw(line[cursor..<start].utf8)
                guard let endMarker = line[start...].firstIndex(of: "\u{E001}") else {
                    try appendRaw(line[start...].utf8); cursor = line.endIndex; break
                }
                let end = line.index(after: endMarker)
                let token = String(line[start..<end])
                guard let escaped = values.removeValue(forKey: token) else {
                    try appendRaw(line[start..<end].utf8); cursor = end; continue
                }
                try appendEscaped(escaped)
                cursor = end
            }
            if cursor < line.endIndex { try appendRaw(line[cursor...].utf8) }
        } catch let error as TopologyFLSCompatibilityError { storedError = error }
        catch { storedError = TopologyFLSCompatibilityError(code: .unsupportedConfigurationStructure, detail: error.localizedDescription) }
    }

    func finish() throws -> Data {
        if let storedError { throw storedError }
        guard values.isEmpty else {
            throw TopologyFLSCompatibilityError(code: .unsupportedConfigurationStructure, detail: "Native XML serialization left unresolved escaped fields.")
        }
        return data
    }

    private func appendEscaped(_ escaped: EscapedValue) throws {
        var replacements = 0
        for scalar in escaped.value.unicodeScalars {
            let value = scalar.value
            let allowed = value == 0x9 || value == 0xA || value == 0xD
                || (0x20...0xD7FF).contains(value) || (0xE000...0xFFFD).contains(value)
                || (0x10000...0x10FFFF).contains(value)
            if !allowed {
                replacements += 1
                try appendRaw(String(Unicode.Scalar(0xFFFD)!).utf8)
            } else if value == 0x26 { try appendRaw("&amp;".utf8) }
            else if value == 0x3C { try appendRaw("&lt;".utf8) }
            else if value == 0x3E { try appendRaw("&gt;".utf8) }
            else { try appendRaw(String(scalar).utf8) }
        }
        if replacements > 0 {
            sanitizationWarnings.append("Sanitized \(replacements) XML 1.0-disallowed scalar(s) in \(escaped.context).")
        }
    }

    private func appendRaw<C: Collection>(_ bytes: C) throws where C.Element == UInt8 {
        let (next, overflow) = data.count.addingReportingOverflow(bytes.count)
        guard !overflow, next <= limit else {
            throw TopologyFLSCompatibilityError(
                code: .unsupportedConfigurationStructure,
                detail: "Native FILIUS XML serialization exceeds \(limit) bytes."
            )
        }
        data.append(contentsOf: bytes)
    }
}
