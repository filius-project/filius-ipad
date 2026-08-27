import Foundation

struct TopologyPacketCaptureExportScope: Equatable {
    var nodeID: UUID?
    var interfaceID: UUID?

    init(nodeID: UUID? = nil, interfaceID: UUID? = nil) {
        self.nodeID = nodeID
        self.interfaceID = interfaceID
    }
}

struct TopologyPacketCaptureExportRecord: Equatable {
    let number: Int
    let timeMilliseconds: UInt64
    let traceID: UInt64
    let frameID: UInt64?
    let packetID: UInt64?
    let nodeID: UUID
    let nodeName: String
    let interfaceID: UUID?
    let interfaceName: String?
    let direction: String
    let layer: String
    let operation: String
    let source: String
    let destination: String
    let protocolName: String
    let beforeHeaders: String
    let afterHeaders: String
    let detail: String
}

struct TopologyPacketCaptureExportDocument: Equatable {
    let formatVersion: Int
    let scope: TopologyPacketCaptureExportScope
    let discardedBeforeCaptureCount: UInt64
    let records: [TopologyPacketCaptureExportRecord]
}

/// Produces a deterministic, versioned UTF-8 TSV representation of packet traces.
///
/// Fields use backslash escaping (`\\`, `\t`, `\n`, and `\r`). Passwords, LAN link
/// codes/digests, generic credentials/tokens, payload fields, and RFC-822 message bodies
/// are redacted before escaping. Records use the packet viewer's eligibility semantics:
/// they require an interface plus a frame or packet identity, and compatibility-adapter
/// traces are excluded. Records are ordered by simulation time and trace ID.
enum TopologyPacketCaptureTextExportFormatter {
    static let formatVersion = 2
    static let mediaType = "text/tab-separated-values; charset=utf-8"
    static let fileExtension = "tsv"

    static let columns = [
        "number",
        "time_ms",
        "trace_id",
        "frame_id",
        "packet_id",
        "node_id",
        "node_name",
        "interface_id",
        "interface_name",
        "direction",
        "layer",
        "operation",
        "source",
        "destination",
        "protocol",
        "before_headers",
        "after_headers",
        "detail",
    ]

    static func makeDocument(
        state: TopologyEditorState,
        scope: TopologyPacketCaptureExportScope = .init()
    ) -> TopologyPacketCaptureExportDocument {
        makeDocument(
            traces: state.networkRuntime.state.packetTraces,
            nodes: state.graph.nodes,
            runtimeNodes: state.networkRuntime.state.topologySnapshot.nodes,
            scope: scope,
            discardedBeforeCaptureCount: state.networkRuntime.state.discardedPacketTraceCount,
            isEligible: TopologyNetworkRuntimeEngine.isPacketCaptureEligible
        )
    }

    static func makeDocument(
        traces: [TopologyPacketTraceEvent],
        nodes: [TopologyNode] = [],
        runtimeNodes: [TopologyNetworkRuntimeNodeSnapshot] = [],
        scope: TopologyPacketCaptureExportScope = .init()
    ) -> TopologyPacketCaptureExportDocument {
        makeDocument(
            traces: traces,
            nodes: nodes,
            runtimeNodes: runtimeNodes,
            scope: scope,
            discardedBeforeCaptureCount: 0,
            isEligible: TopologyNetworkRuntimeEngine.isPacketCaptureEligible
        )
    }

    private static func makeDocument(
        traces: [TopologyPacketTraceEvent],
        nodes: [TopologyNode],
        runtimeNodes: [TopologyNetworkRuntimeNodeSnapshot],
        scope: TopologyPacketCaptureExportScope,
        discardedBeforeCaptureCount: UInt64,
        isEligible: (TopologyPacketTraceEvent) -> Bool
    ) -> TopologyPacketCaptureExportDocument {
        let filtered = traces.filter { trace in
            isEligible(trace)
                && (scope.nodeID == nil || trace.nodeID == scope.nodeID)
                && (scope.interfaceID == nil || trace.interfaceID == scope.interfaceID)
        }
        let sorted = filtered.sorted(by: traceIsOrderedBefore)
        let records = sorted.enumerated().map { offset, trace in
            makeRecord(
                trace: trace,
                number: offset + 1,
                nodes: nodes,
                runtimeNodes: runtimeNodes
            )
        }
        return TopologyPacketCaptureExportDocument(
            formatVersion: formatVersion,
            scope: scope,
            discardedBeforeCaptureCount: discardedBeforeCaptureCount,
            records: records
        )
    }

    static func renderTSV(_ document: TopologyPacketCaptureExportDocument) -> String {
        var lines = [
            "# FiliusPad packet-capture",
            "# format-version: \(document.formatVersion)",
            "# media-type: \(mediaType)",
            "# encoding: UTF-8",
            "# ordering: time_ms, trace_id, node_id, interface_id",
            "# escaping: backslash (\\\\, \\t, \\n, \\r)",
            "# redaction: passwords, credentials, tokens, LAN link codes/digests, payloads, message bodies",
            "# scope-node-id: \(document.scope.nodeID.map(normalizedUUID) ?? "all")",
            "# scope-interface-id: \(document.scope.interfaceID.map(normalizedUUID) ?? "all")",
            "# discarded-before-capture-count: \(document.discardedBeforeCaptureCount)",
            "# record-count: \(document.records.count)",
            columns.joined(separator: "\t"),
        ]
        lines.append(contentsOf: document.records.map(renderRecord))
        return lines.joined(separator: "\n") + "\n"
    }

    static func renderTSV(
        state: TopologyEditorState,
        scope: TopologyPacketCaptureExportScope = .init()
    ) -> String {
        renderTSV(makeDocument(state: state, scope: scope))
    }

    static func makeUTF8Data(
        state: TopologyEditorState,
        scope: TopologyPacketCaptureExportScope = .init()
    ) -> Data {
        Data(renderTSV(state: state, scope: scope).utf8)
    }

    static func escapeTSVField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    static func unescapeTSVField(_ value: String) -> String {
        var result = ""
        var isEscaping = false
        for character in value {
            if isEscaping {
                switch character {
                case "t": result.append("\t")
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "\\": result.append("\\")
                default:
                    result.append("\\")
                    result.append(character)
                }
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else {
                result.append(character)
            }
        }
        if isEscaping { result.append("\\") }
        return result
    }

    private static func makeRecord(
        trace: TopologyPacketTraceEvent,
        number: Int,
        nodes: [TopologyNode],
        runtimeNodes: [TopologyNetworkRuntimeNodeSnapshot]
    ) -> TopologyPacketCaptureExportRecord {
        let effectiveHeaders = trace.afterHeaders.isEmpty ? trace.beforeHeaders : trace.afterHeaders
        let redactedBeforeHeaders = redactedHeaderSummary(trace.beforeHeaders)
        let redactedAfterHeaders = redactedHeaderSummary(trace.afterHeaders)
        let detail = TopologyReportExportRedaction.bounded(
            TopologyReportExportRedaction.redactFreeText(trace.detail ?? ""),
            maximumCharacters: 512
        )

        return TopologyPacketCaptureExportRecord(
            number: number,
            timeMilliseconds: trace.timeMilliseconds,
            traceID: trace.id,
            frameID: trace.frameIdentity,
            packetID: trace.packetIdentity,
            nodeID: trace.nodeID,
            nodeName: nodeName(for: trace.nodeID, nodes: nodes, runtimeNodes: runtimeNodes),
            interfaceID: trace.interfaceID,
            interfaceName: interfaceName(
                for: trace.interfaceID,
                nodeID: trace.nodeID,
                nodes: nodes,
                runtimeNodes: runtimeNodes
            ),
            direction: trace.direction.rawValue,
            layer: trace.layer.rawValue,
            operation: trace.operation.rawValue,
            source: redactedHeaderValue(
                names: ["senderIP", "sourceMAC", "senderMAC"],
                headers: effectiveHeaders
            ) ?? "-",
            destination: redactedHeaderValue(
                names: ["receiverIP", "destinationMAC", "targetIP", "targetMAC"],
                headers: effectiveHeaders
            ) ?? "-",
            protocolName: protocolName(for: trace, headers: effectiveHeaders),
            beforeHeaders: redactedBeforeHeaders,
            afterHeaders: redactedAfterHeaders,
            detail: detail
        )
    }

    private static func renderRecord(_ record: TopologyPacketCaptureExportRecord) -> String {
        [
            String(record.number),
            String(record.timeMilliseconds),
            String(record.traceID),
            record.frameID.map(String.init) ?? "",
            record.packetID.map(String.init) ?? "",
            normalizedUUID(record.nodeID),
            record.nodeName,
            record.interfaceID.map(normalizedUUID) ?? "",
            record.interfaceName ?? "",
            record.direction,
            record.layer,
            record.operation,
            record.source,
            record.destination,
            record.protocolName,
            record.beforeHeaders,
            record.afterHeaders,
            record.detail,
        ].map(escapeTSVField).joined(separator: "\t")
    }

    private static func traceIsOrderedBefore(
        _ lhs: TopologyPacketTraceEvent,
        _ rhs: TopologyPacketTraceEvent
    ) -> Bool {
        if lhs.timeMilliseconds != rhs.timeMilliseconds {
            return lhs.timeMilliseconds < rhs.timeMilliseconds
        }
        if lhs.id != rhs.id { return lhs.id < rhs.id }
        let lhsNode = normalizedUUID(lhs.nodeID)
        let rhsNode = normalizedUUID(rhs.nodeID)
        if lhsNode != rhsNode { return lhsNode < rhsNode }
        let lhsInterface = lhs.interfaceID.map(normalizedUUID) ?? ""
        let rhsInterface = rhs.interfaceID.map(normalizedUUID) ?? ""
        if lhsInterface != rhsInterface { return lhsInterface < rhsInterface }
        if lhs.layer.rawValue != rhs.layer.rawValue { return lhs.layer.rawValue < rhs.layer.rawValue }
        return lhs.operation.rawValue < rhs.operation.rawValue
    }

    private static func redactedHeaderSummary(_ headers: [TopologyPacketHeaderField]) -> String {
        headers.enumerated()
            .map { offset, field in
                (
                    offset: offset,
                    name: TopologyReportExportRedaction.singleLine(value: field.name),
                    value: TopologyReportExportRedaction.singleLine(
                        fieldName: field.name,
                        value: TopologyReportExportRedaction.bounded(field.value, maximumCharacters: 512)
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.name != rhs.name { return lhs.name < rhs.name }
                if lhs.value != rhs.value { return lhs.value < rhs.value }
                return lhs.offset < rhs.offset
            }
            .map { "\(escapeHeaderComponent($0.name))=\(escapeHeaderComponent($0.value))" }
            .joined(separator: "; ")
    }

    private static func redactedHeaderValue(
        names: [String],
        headers: [TopologyPacketHeaderField]
    ) -> String? {
        for name in names {
            guard let field = headers.last(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                continue
            }
            return TopologyReportExportRedaction.redact(fieldName: field.name, value: field.value)
        }
        return nil
    }

    private static func protocolName(
        for trace: TopologyPacketTraceEvent,
        headers: [TopologyPacketHeaderField]
    ) -> String {
        if let kind = redactedHeaderValue(names: ["kind"], headers: headers) {
            let uppercased = kind.uppercased()
            if ["ARP", "ICMP", "TCP", "UDP", "DHCP", "DNS", "HTTP", "SMTP", "POP3"].contains(uppercased) {
                return uppercased
            }
            if kind.localizedCaseInsensitiveContains("echo")
                || kind.localizedCaseInsensitiveContains("unreachable")
                || kind.localizedCaseInsensitiveContains("timeExceeded") {
                return "ICMP"
            }
        }
        if let protocolNumber = redactedHeaderValue(names: ["protocol"], headers: headers) {
            switch protocolNumber {
            case "1": return "ICMP"
            case "6": return "TCP"
            case "17": return "UDP"
            default: return "IP"
            }
        }
        if redactedHeaderValue(names: ["sourcePort", "destinationPort"], headers: headers) != nil {
            return trace.detail?.localizedCaseInsensitiveContains("TCP") == true ? "TCP" : "UDP"
        }
        switch trace.layer {
        case .physical, .dataLink: return "Ethernet"
        case .network: return "IP"
        case .transport: return "Transport"
        case .application: return "Application"
        }
    }

    private static func nodeName(
        for nodeID: UUID,
        nodes: [TopologyNode],
        runtimeNodes: [TopologyNetworkRuntimeNodeSnapshot]
    ) -> String {
        if let node = nodes.first(where: { $0.id == nodeID }) {
            return TopologyReportExportRedaction.redactFreeText(node.displayName)
        }
        if let node = runtimeNodes.first(where: { $0.id == nodeID }) {
            return TopologyNode.defaultDisplayName(for: node.kind)
        }
        return normalizedUUID(nodeID)
    }

    private static func interfaceName(
        for interfaceID: UUID?,
        nodeID: UUID,
        nodes: [TopologyNode],
        runtimeNodes: [TopologyNetworkRuntimeNodeSnapshot]
    ) -> String? {
        guard let interfaceID else { return nil }
        if let label = nodes.first(where: { $0.id == nodeID })?.ports.first(where: { $0.id == interfaceID })?.label {
            return TopologyReportExportRedaction.redactFreeText(label)
        }
        return runtimeNodes.first(where: { $0.id == nodeID })?.ports.first(where: { $0.id == interfaceID })?.label
    }

    private static func escapeHeaderComponent(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "=", with: "\\=")
    }

    private static func normalizedUUID(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }
}
