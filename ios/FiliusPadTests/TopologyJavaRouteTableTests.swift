import CoreGraphics
import XCTest
@testable import FiliusPad

final class TopologyJavaRouteTableTests: XCTestCase {
    func testJavaColumnLabelsAndGeometryConstants() {
        XCTAssertEqual(
            TopologyJavaRouteTableColumn.allCases.map(\.title),
            ["Ziel", "Netzmaske", "Nächstes Gateway", "Über Schnittstelle"]
        )
        XCTAssertEqual(TopologyJavaRouteTable.rowHeight, 20)
        XCTAssertEqual(TopologyJavaRouteTable.rowMargin, 2)
        XCTAssertEqual(TopologyJavaRouteTable.compactViewportSize, CGSize(width: 300, height: 120))
        XCTAssertEqual(TopologyJavaRouteTable.windowSize, CGSize(width: 600, height: 400))
        XCTAssertEqual(TopologyJavaRouteTable.equalColumnWidth(for: 300), 72.5)
        XCTAssertEqual(TopologyJavaRouteTable.equalColumnWidth(for: 600), 147.5)
    }

    func testProjectionMatchesJavaMultiInterfaceOrderAndValues() {
        let manual = [
            route("172.16.0.0", "255.255.0.0", "10.0.0.2", "10.0.0.1"),
            route("203.0.113.0", "255.255.255.0", "192.168.0.2", "192.168.0.1"),
        ]
        let rows = TopologyJavaRouteTable.rows(
            interfaceConfigurations: [
                .init(ipAddress: "10.0.0.1", subnetMask: "255.255.255.0"),
                .init(ipAddress: "192.168.0.1", subnetMask: "255.255.255.0"),
            ],
            manualRoutes: manual,
            defaultGateway: "10.0.0.254"
        )

        XCTAssertEqual(
            rows.map(\.destinationNetwork),
            [
                "192.168.0.1", "10.0.0.1",
                "192.168.0.0", "10.0.0.0",
                "127.0.0.0",
                "172.16.0.0", "203.0.113.0",
                "0.0.0.0",
            ]
        )
        XCTAssertEqual(
            rows.map(\.origin),
            [.localHost, .localHost, .connected, .connected, .localhost, .manual, .manual, .defaultGateway]
        )
        XCTAssertEqual(rows.map(\.isEditable), [false, false, false, false, false, true, true, false])
        XCTAssertEqual(rows[0].subnetMask, "255.255.255.255")
        XCTAssertEqual(rows[0].nextHop, "127.0.0.1")
        XCTAssertEqual(rows[0].interfaceIPAddress, "127.0.0.1")
        XCTAssertEqual(rows[2].nextHop, "192.168.0.1")
        XCTAssertEqual(rows[4].nextHop, "127.0.0.1")
        XCTAssertEqual(rows.last?.nextHop, "10.0.0.254")
        XCTAssertEqual(rows.last?.interfaceIPAddress, "10.0.0.1")
    }

    func testDefaultRouteUsesLastMatchingInterfaceAndFallsBackToPrimary() {
        let interfaces = [
            TopologyRuntimeInterfaceConfiguration(ipAddress: "10.0.0.1", subnetMask: "255.0.0.0"),
            TopologyRuntimeInterfaceConfiguration(ipAddress: "10.1.0.1", subnetMask: "255.0.0.0"),
        ]

        let matching = TopologyJavaRouteTable.rows(
            interfaceConfigurations: interfaces,
            manualRoutes: [],
            defaultGateway: "10.2.0.1"
        )
        XCTAssertEqual(matching.last?.origin, .defaultGateway)
        XCTAssertEqual(matching.last?.interfaceIPAddress, "10.1.0.1")

        let fallback = TopologyJavaRouteTable.rows(
            interfaceConfigurations: interfaces,
            manualRoutes: [],
            defaultGateway: "192.168.0.1"
        )
        XCTAssertEqual(fallback.last?.interfaceIPAddress, "10.0.0.1")
    }

    func testGeneratedFilteringLeavesOnlyManualRows() {
        let rows = TopologyJavaRouteTable.rows(
            interfaceConfigurations: [.init(ipAddress: "10.0.0.1", subnetMask: "255.255.255.0")],
            manualRoutes: [route("172.16.0.0", "255.255.0.0", "10.0.0.2", "10.0.0.1")],
            defaultGateway: "10.0.0.254"
        )

        XCTAssertEqual(TopologyJavaRouteTable.visibleRows(rows, showAllEntries: false).map(\.origin), [.manual])
        XCTAssertEqual(TopologyJavaRouteTable.visibleRows(rows, showAllEntries: true), rows)
    }

    func testJavaValidationAcceptsLeadingZerosAndNonContiguousMask() {
        XCTAssertTrue(TopologyJavaRouteTable.isValidJavaIPAddress("001.002.003.004"))
        XCTAssertTrue(TopologyJavaRouteTable.isValidJavaSubnetMask("255.0.255.0"))
        XCTAssertFalse(TopologyJavaRouteTable.isValidJavaIPAddress("256.0.0.1"))
        XCTAssertFalse(TopologyJavaRouteTable.isValidJavaSubnetMask("255.255.255"))
        XCTAssertFalse(TopologyJavaRouteTable.isValidJavaIPAddress(" 10.0.0.1"))
    }

    func testDraftCommitsOnlyWhenAllFourCellsAreValid() {
        var draft = TopologyJavaRouteDraft.blank(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!
        )
        draft.destinationNetwork = "10.0.0.0"
        draft.subnetMask = "255.0.255.0"
        draft.nextGateway = "10.0.0.2"

        XCTAssertNil(draft.manualRoute)

        draft.interfaceIPAddress = "10.0.0.1"
        XCTAssertEqual(
            draft.manualRoute,
            route("10.0.0.0", "255.0.255.0", "10.0.0.2", "10.0.0.1")
        )
    }

    func testOnlyOnePendingBlankDraftCanExist() {
        let first = TopologyJavaRouteDraft.appendingBlankIfNeeded(to: [])
        let second = TopologyJavaRouteDraft.appendingBlankIfNeeded(to: first)

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second, first)
        XCTAssertTrue(second[0].isPendingInsertion)
    }

    func testReducerSavesReplacesAndRemovesManualRoutesInOrder() {
        let nodeID = UUID(uuidString: "00000000-0000-0000-0000-000000000130")!
        var state = TopologyEditorState()
        state.graph.appendNode(TopologyNode(id: nodeID, kind: .router, position: .zero))
        let first = route("10.0.0.0", "255.0.255.0", "192.168.0.2", "192.168.0.1")
        let second = route("172.16.0.0", "255.255.0.0", "192.168.0.3", "192.168.0.1")

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeManualRoutes(nodeID: nodeID, routes: [first, second])
        )

        XCTAssertEqual(state.runtimeManualRoutesByNodeID[nodeID], [first, second])
        XCTAssertEqual(state.persistenceRevision, 1)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeManualRoutesSaved)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeManualRoutes(nodeID: nodeID, routes: [second])
        )
        XCTAssertEqual(state.runtimeManualRoutesByNodeID[nodeID], [second])
        XCTAssertEqual(state.persistenceRevision, 2)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeManualRoutes(nodeID: nodeID, routes: [])
        )
        XCTAssertNil(state.runtimeManualRoutesByNodeID[nodeID])
        XCTAssertEqual(state.persistenceRevision, 3)
    }

    func testReducerRejectsMalformedUnknownUnsupportedAndInvalidSaves() {
        let routerID = UUID(uuidString: "00000000-0000-0000-0000-000000000131")!
        let gatewayID = UUID(uuidString: "00000000-0000-0000-0000-000000000132")!
        var state = TopologyEditorState()
        state.graph.appendNode(TopologyNode(id: routerID, kind: .router, position: .zero))
        state.graph.appendNode(TopologyNode(id: gatewayID, kind: .gateway, position: .zero))

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeManualRoutes(nodeID: nil, routes: nil)
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simulationFaultRejectedMalformedPayload)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeManualRoutes(nodeID: UUID(), routes: [])
        )
        XCTAssertEqual(state.lastValidationError, .nodeNotFound)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeManualRoutesRejectedInvalidConfiguration)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeManualRoutes(nodeID: gatewayID, routes: [])
        )
        XCTAssertEqual(state.lastRuntimeFault?.code, "manualRoutesUnsupportedForNodeKind")

        let invalid = route("10.0.0", "255.255.255.0", "10.0.0.2", "10.0.0.1")
        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeManualRoutes(nodeID: routerID, routes: [invalid])
        )
        XCTAssertEqual(state.lastRuntimeFault?.code, "invalidManualRoute")
        XCTAssertNil(state.runtimeManualRoutesByNodeID[routerID])
        XCTAssertEqual(state.persistenceRevision, 0)
    }

    func testGreatestNumericMaskAndFirstRowTieRemainStable() {
        let broad = route("10.0.0.0", "255.0.0.0", "1.1.1.1", "10.0.0.1")
        let firstSpecific = route("10.1.0.0", "255.255.0.0", "2.2.2.2", "10.0.0.1")
        let tiedSpecific = route("10.1.0.0", "255.255.0.0", "3.3.3.3", "10.0.0.1")

        XCTAssertEqual(
            TopologyRuntimeManualRoute.bestMatching(
                targetIPAddress: "10.1.2.3",
                routes: [broad, firstSpecific, tiedSpecific]
            ),
            firstSpecific
        )
    }

    func testStaticProjectionNeverIncludesLearnedRIPRows() {
        let rows = TopologyJavaRouteTable.rows(
            interfaceConfigurations: [.init(ipAddress: "10.0.0.1", subnetMask: "255.255.255.0")],
            manualRoutes: [],
            defaultGateway: nil
        )

        XCTAssertFalse(rows.contains(where: { $0.origin == .rip }))
    }

    private func route(
        _ destination: String,
        _ mask: String,
        _ gateway: String,
        _ interface: String
    ) -> TopologyRuntimeManualRoute {
        TopologyRuntimeManualRoute(
            destinationNetwork: destination,
            subnetMask: mask,
            gateway: gateway,
            interfaceIPAddress: interface
        )
    }
}
