import Foundation

struct TopologyLink: Identifiable, Equatable {
    let id: UUID
    let sourceNodeID: UUID
    let sourcePortID: UUID
    let targetNodeID: UUID
    let targetPortID: UUID

    init(
        id: UUID = UUID(),
        sourceNodeID: UUID,
        sourcePortID: UUID,
        targetNodeID: UUID,
        targetPortID: UUID
    ) {
        self.id = id
        self.sourceNodeID = sourceNodeID
        self.sourcePortID = sourcePortID
        self.targetNodeID = targetNodeID
        self.targetPortID = targetPortID
    }
}

extension TopologyLink {
    static func parallelCableOffsets(
        for links: [TopologyLink],
        spacing: CGFloat = 14
    ) -> [UUID: CGFloat] {
        var linksByNodePair: [UnorderedNodePair: [TopologyLink]] = [:]
        linksByNodePair.reserveCapacity(links.count)
        for link in links {
            linksByNodePair[UnorderedNodePair(link), default: []].append(link)
        }

        var offsetsByLinkID: [UUID: CGFloat] = [:]
        offsetsByLinkID.reserveCapacity(links.count)
        for (nodePair, groupedLinks) in linksByNodePair {
            let sortedLinks = groupedLinks.sorted { $0.id.uuidString < $1.id.uuidString }
            let centerIndex = CGFloat(sortedLinks.count - 1) / 2
            for (index, link) in sortedLinks.enumerated() {
                let centeredOffset = (CGFloat(index) - centerIndex) * spacing
                let usesCanonicalDirection = link.sourceNodeID == nodePair.firstNodeID
                offsetsByLinkID[link.id] = usesCanonicalDirection ? centeredOffset : -centeredOffset
            }
        }
        return offsetsByLinkID
    }

    private struct UnorderedNodePair: Hashable {
        let firstNodeID: UUID
        let secondNodeID: UUID

        init(_ link: TopologyLink) {
            if link.sourceNodeID.uuidString < link.targetNodeID.uuidString {
                firstNodeID = link.sourceNodeID
                secondNodeID = link.targetNodeID
            } else {
                firstNodeID = link.targetNodeID
                secondNodeID = link.sourceNodeID
            }
        }
    }
}
