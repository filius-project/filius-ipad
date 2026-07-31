import CoreGraphics
import Foundation

struct TopologyLinkProjection: Equatable {
    let source: CGPoint
    let target: CGPoint
}

struct TopologyGraph: Equatable {
    var nodes: [TopologyNode] = []
    var links: [TopologyLink] = []

    func nodeIndex(withID id: UUID) -> Int? {
        nodes.firstIndex(where: { $0.id == id })
    }

    func node(withID id: UUID) -> TopologyNode? {
        guard let index = nodeIndex(withID: id) else {
            return nil
        }

        return nodes[index]
    }

    func containsNode(id: UUID) -> Bool {
        nodeIndex(withID: id) != nil
    }

    func containsLink(id: UUID) -> Bool {
        links.contains(where: { $0.id == id })
    }

    func hasConnection(between firstNodeID: UUID, and secondNodeID: UUID) -> Bool {
        links.contains {
            ($0.sourceNodeID == firstNodeID && $0.targetNodeID == secondNodeID)
                || ($0.sourceNodeID == secondNodeID && $0.targetNodeID == firstNodeID)
        }
    }

    func usedPortIDs(for nodeID: UUID) -> Set<UUID> {
        Set(
            links.compactMap { link in
                if link.sourceNodeID == nodeID {
                    return link.sourcePortID
                }

                if link.targetNodeID == nodeID {
                    return link.targetPortID
                }

                return nil
            }
        )
    }

    func isPortConnected(nodeID: UUID, portID: UUID) -> Bool {
        links.contains {
            ($0.sourceNodeID == nodeID && $0.sourcePortID == portID)
                || ($0.targetNodeID == nodeID && $0.targetPortID == portID)
        }
    }

    func availablePortIDs(for nodeID: UUID) -> [UUID] {
        guard let node = node(withID: nodeID) else {
            return []
        }

        let usedPortIDs = usedPortIDs(for: nodeID)

        return node.ports
            .filter { !$0.isOccupied && !usedPortIDs.contains($0.id) }
            .map(\.id)
    }

    func adjacentNodeIDs(for nodeID: UUID) -> [UUID] {
        links.compactMap { link in
            if link.sourceNodeID == nodeID {
                return link.targetNodeID
            }

            if link.targetNodeID == nodeID {
                return link.sourceNodeID
            }

            return nil
        }
    }

    func isReachable(from sourceNodeID: UUID, to targetNodeID: UUID) -> Bool {
        guard containsNode(id: sourceNodeID), containsNode(id: targetNodeID) else {
            return false
        }

        if sourceNodeID == targetNodeID {
            return true
        }

        var visited: Set<UUID> = [sourceNodeID]
        var queue: [UUID] = [sourceNodeID]
        var cursor = 0

        while cursor < queue.count {
            let nodeID = queue[cursor]
            cursor += 1

            for neighborID in adjacentNodeIDs(for: nodeID) {
                if neighborID == targetNodeID {
                    return true
                }

                if visited.insert(neighborID).inserted {
                    queue.append(neighborID)
                }
            }
        }

        return false
    }

    func shortestPathHopCount(from sourceNodeID: UUID, to targetNodeID: UUID) -> Int? {
        guard let path = shortestPathNodeIDs(from: sourceNodeID, to: targetNodeID) else {
            return nil
        }

        return max(0, path.count - 1)
    }

    func shortestPathNodeIDs(from sourceNodeID: UUID, to targetNodeID: UUID) -> [UUID]? {
        guard containsNode(id: sourceNodeID), containsNode(id: targetNodeID) else {
            return nil
        }

        if sourceNodeID == targetNodeID {
            return [sourceNodeID]
        }

        let adjacencyByNodeID = deterministicAdjacencyMap()
        var visited: Set<UUID> = [sourceNodeID]
        var queue: [UUID] = [sourceNodeID]
        var predecessors: [UUID: UUID] = [:]
        var cursor = 0

        while cursor < queue.count {
            let nodeID = queue[cursor]
            cursor += 1

            for neighborID in adjacencyByNodeID[nodeID, default: []] where visited.insert(neighborID).inserted {
                predecessors[neighborID] = nodeID

                if neighborID == targetNodeID {
                    return buildPath(from: sourceNodeID, to: targetNodeID, predecessors: predecessors)
                }

                queue.append(neighborID)
            }
        }

        return nil
    }

    private func deterministicAdjacencyMap() -> [UUID: [UUID]] {
        var adjacencyByNodeID: [UUID: [UUID]] = [:]
        adjacencyByNodeID.reserveCapacity(nodes.count)

        for link in links {
            adjacencyByNodeID[link.sourceNodeID, default: []].append(link.targetNodeID)
            adjacencyByNodeID[link.targetNodeID, default: []].append(link.sourceNodeID)
        }

        for (nodeID, neighbors) in adjacencyByNodeID {
            adjacencyByNodeID[nodeID] = neighbors.sorted { $0.uuidString < $1.uuidString }
        }

        return adjacencyByNodeID
    }

    private func buildPath(from sourceNodeID: UUID, to targetNodeID: UUID, predecessors: [UUID: UUID]) -> [UUID]? {
        var path: [UUID] = [targetNodeID]
        var cursor = targetNodeID

        while cursor != sourceNodeID {
            guard let predecessor = predecessors[cursor] else {
                return nil
            }

            cursor = predecessor
            path.append(cursor)
        }

        return path.reversed()
    }

    func linkProjection(for linkID: UUID) -> TopologyLinkProjection? {
        guard let link = links.first(where: { $0.id == linkID }) else {
            return nil
        }

        return linkProjection(for: link)
    }

    func linkProjection(for link: TopologyLink) -> TopologyLinkProjection? {
        guard
            let sourceNode = node(withID: link.sourceNodeID),
            let targetNode = node(withID: link.targetNodeID)
        else {
            return nil
        }

        return TopologyLinkProjection(source: sourceNode.position, target: targetNode.position)
    }

    mutating func appendNode(_ node: TopologyNode) {
        nodes.append(node)
    }

    mutating func appendLink(_ link: TopologyLink) {
        links.append(link)
        markPortOccupied(nodeID: link.sourceNodeID, portID: link.sourcePortID)
        markPortOccupied(nodeID: link.targetNodeID, portID: link.targetPortID)
    }

    @discardableResult
    mutating func removeLinks(withIDs ids: Set<UUID>) -> [TopologyLink] {
        guard !ids.isEmpty else {
            return []
        }
        let removed = links.filter { ids.contains($0.id) }
        links.removeAll { ids.contains($0.id) }
        for link in removed {
            refreshPortOccupancy(nodeID: link.sourceNodeID, portID: link.sourcePortID)
            refreshPortOccupancy(nodeID: link.targetNodeID, portID: link.targetPortID)
        }
        return removed
    }

    @discardableResult
    mutating func removeNodes(withIDs ids: Set<UUID>) -> [TopologyLink] {
        guard !ids.isEmpty else {
            return []
        }
        let incidentLinkIDs = Set(links.filter {
            ids.contains($0.sourceNodeID) || ids.contains($0.targetNodeID)
        }.map(\.id))
        let removedLinks = removeLinks(withIDs: incidentLinkIDs)
        nodes.removeAll { ids.contains($0.id) }
        return removedLinks
    }

    private mutating func refreshPortOccupancy(nodeID: UUID, portID: UUID) {
        guard let nodeIndex = nodeIndex(withID: nodeID),
              let portIndex = nodes[nodeIndex].ports.firstIndex(where: { $0.id == portID }) else {
            return
        }
        nodes[nodeIndex].ports[portIndex].isOccupied = isPortConnected(nodeID: nodeID, portID: portID)
    }

    private mutating func markPortOccupied(nodeID: UUID, portID: UUID) {
        guard let nodeIndex = nodeIndex(withID: nodeID),
              let portIndex = nodes[nodeIndex].ports.firstIndex(where: { $0.id == portID }) else {
            return
        }
        nodes[nodeIndex].ports[portIndex].isOccupied = true
    }

    mutating func moveNode(withID id: UUID, delta: CGSize) {
        guard let index = nodeIndex(withID: id) else {
            return
        }

        let current = nodes[index].position
        nodes[index].position = CGPoint(x: current.x + delta.width, y: current.y + delta.height)
    }
}
