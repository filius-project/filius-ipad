import CoreGraphics
import Foundation

enum TopologyNodeKind: String, CaseIterable {
    case pc
    case notebook
    case networkSwitch
    case router
    case gateway
    case remoteLink
    case unsupported

    var isPCClassEndpoint: Bool {
        self == .pc || self == .notebook
    }
}

struct TopologyPortMetadata: Identifiable, Equatable {
    let id: UUID
    var label: String
    var isOccupied: Bool

    init(id: UUID = UUID(), label: String, isOccupied: Bool = false) {
        self.id = id
        self.label = label
        self.isOccupied = isOccupied
    }
}

struct TopologyNode: Identifiable, Equatable {
    let id: UUID
    var kind: TopologyNodeKind
    var displayName: String
    var position: CGPoint
    var ports: [TopologyPortMetadata]

    init(
        id: UUID,
        kind: TopologyNodeKind,
        displayName: String? = nil,
        position: CGPoint,
        ports: [TopologyPortMetadata]? = nil
    ) {
        self.id = id
        self.kind = kind
        let normalizedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = normalizedDisplayName.flatMap { $0.isEmpty ? nil : $0 }
            ?? TopologyNode.defaultDisplayName(for: kind)
        self.position = position
        self.ports = ports ?? TopologyNode.defaultPorts(for: kind)
    }

    static func defaultDisplayName(for kind: TopologyNodeKind) -> String {
        switch kind {
        case .pc:
            return "Rechner"
        case .notebook:
            return "Notebook"
        case .networkSwitch:
            return "Switch"
        case .router:
            return "Vermittlungsrechner"
        case .gateway:
            return "Gateway"
        case .remoteLink:
            return "Remote Link"
        case .unsupported:
            return "Unbekanntes Gerät"
        }
    }

    static func defaultPorts(for kind: TopologyNodeKind) -> [TopologyPortMetadata] {
        switch kind {
        case .pc, .notebook:
            return [TopologyPortMetadata(label: "eth0")]
        case .networkSwitch:
            // Java Switch constructs exactly 24 physical ports.
            return (1...24).map { index in
                TopologyPortMetadata(label: "sw\(index)")
            }
        case .router:
            // Java Vermittlungsrechner starts with one configurable network interface.
            return [TopologyPortMetadata(label: "rt1")]
        case .gateway:
            // Java Gateway has fixed WAN (index 0) and LAN (index 1) interfaces.
            return [
                TopologyPortMetadata(label: "wan0"),
                TopologyPortMetadata(label: "lan0")
            ]
        case .remoteLink:
            // The native Remote Link exposes one local physical attachment, matching Java Modem.
            return [TopologyPortMetadata(label: "remote0")]
        case .unsupported:
            return []
        }
    }
}
