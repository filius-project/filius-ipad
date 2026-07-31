import CoreGraphics
import XCTest
@testable import FiliusPad

final class TopologyNetworkRuntimeEngineTests: XCTestCase {
    func testStableEventQueueOrdersByDeadlineThenInsertionSequence() {
        var engine = TopologyNetworkRuntimeEngine(seed: 42)
        engine.handle(
            .start(
                snapshot: .empty,
                seed: 42,
                initialTimeMilliseconds: 0
            )
        )
        engine.handle(.schedule(deadlineMilliseconds: 100, kind: .parityMarker("first-at-100")))
        engine.handle(.schedule(deadlineMilliseconds: 50, kind: .parityMarker("at-50")))
        engine.handle(.schedule(deadlineMilliseconds: 100, kind: .parityMarker("second-at-100")))

        let outputs = engine.handle(.advance(toMilliseconds: 100))
        let firedKinds = outputs.compactMap { output -> TopologyNetworkRuntimeScheduledEventKind? in
            guard case let .fired(event) = output.kind else { return nil }
            return event.kind
        }

        XCTAssertEqual(
            firedKinds,
            [
                .parityMarker("at-50"),
                .parityMarker("first-at-100"),
                .parityMarker("second-at-100"),
            ]
        )
        XCTAssertEqual(engine.state.currentTimeMilliseconds, 100)
        XCTAssertTrue(engine.state.pendingEvents.isEmpty)
    }

    func testVirtualClockRejectsPastTimeWithoutMutation() {
        var engine = TopologyNetworkRuntimeEngine(seed: 7)
        engine.handle(.start(snapshot: .empty, seed: 7, initialTimeMilliseconds: 10))
        engine.handle(.advance(toMilliseconds: 25))

        let outputs = engine.handle(.advance(toMilliseconds: 24))

        XCTAssertEqual(outputs.map(\.kind), [.advanceRejectedPastTime])
        XCTAssertEqual(engine.state.currentTimeMilliseconds, 25)
    }

    func testEventQueueRejectsPastDeadlineWithoutMutatingSequence() {
        var engine = TopologyNetworkRuntimeEngine(seed: 8)
        engine.handle(.start(snapshot: .empty, seed: 8, initialTimeMilliseconds: 25))

        let outputs = engine.handle(.schedule(deadlineMilliseconds: 24, kind: .parityMarker("past")))

        XCTAssertEqual(outputs.map(\.kind), [.scheduleRejectedPastTime(deadlineMilliseconds: 24)])
        XCTAssertTrue(engine.state.pendingEvents.isEmpty)
        XCTAssertEqual(engine.state.nextEventSequenceNumber, 0)
        XCTAssertEqual(engine.state.currentTimeMilliseconds, 25)
    }

    func testJavaCompatibleRIPJitterMatchesJavaUtilRandom() {
        var random = TopologyJavaCompatibleRandom(seed: 42)

        XCTAssertEqual(
            (0..<5).map { _ in random.nextRIPJitterMilliseconds() },
            [32_475, 25_746, 32_032, 25_679, 28_287]
        )
    }

    func testRuntimeRestartClearsTransientStateAndRestartsPacketIdentities() {
        let nodeID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        var engine = TopologyNetworkRuntimeEngine(seed: 12)
        engine.handle(.start(snapshot: .empty, seed: 12, initialTimeMilliseconds: 0))
        engine.handle(.schedule(deadlineMilliseconds: 40, kind: .parityMarker("stale")))
        XCTAssertEqual(engine.allocateFrameIdentity(), 1)
        XCTAssertEqual(engine.allocatePacketIdentity(), 1)
        engine.recordTrace(
            packetIdentity: 1,
            nodeID: nodeID,
            direction: .local,
            layer: .application,
            operation: .created
        )
        engine.handle(.stop)

        engine.handle(.start(snapshot: .empty, seed: 12, initialTimeMilliseconds: 0))

        XCTAssertTrue(engine.state.pendingEvents.isEmpty)
        XCTAssertTrue(engine.state.packetTraces.isEmpty)
        XCTAssertTrue(engine.state.arpCachesByNodeID.isEmpty)
        XCTAssertTrue(engine.state.switchForwardingTablesByNodeID.isEmpty)
        XCTAssertTrue(engine.state.switchSeenFrameIdentitiesByNodeID.isEmpty)
        XCTAssertTrue(engine.state.deliveredIPv4PacketsByNodeID.isEmpty)
        XCTAssertTrue(engine.state.icmpObservationsByNodeID.isEmpty)
        XCTAssertTrue(engine.state.socketsByID.isEmpty)
        XCTAssertTrue(engine.state.udpReceiveQueuesBySocketID.isEmpty)
        XCTAssertTrue(engine.state.tcpSessionsByID.isEmpty)
        XCTAssertTrue(engine.state.tcpAcceptedSocketIDsByListenerID.isEmpty)
        XCTAssertTrue(engine.state.ripTablesByNodeID.isEmpty)
        XCTAssertTrue(engine.state.dhcpOffersByIPAddress.isEmpty)
        XCTAssertTrue(engine.state.dhcpLeasesByIPAddress.isEmpty)
        XCTAssertTrue(engine.state.dhcpClientContextsByNodeID.isEmpty)
        XCTAssertTrue(engine.state.firewallDecisions.isEmpty)
        XCTAssertTrue(engine.state.natMappings.isEmpty)
        XCTAssertEqual(engine.allocateFrameIdentity(), 1)
        XCTAssertEqual(engine.allocatePacketIdentity(), 1)
    }

    func testNamedParityScenarioCanSeedAndAdvanceDirectlyToStableState() {
        let scenario = TopologyNetworkRuntimeScenario(
            name: "equal-deadline-order",
            seed: 1,
            advanceToMilliseconds: 1_000,
            scheduledEvents: [
                (deadlineMilliseconds: 500, kind: .parityMarker("a")),
                (deadlineMilliseconds: 500, kind: .parityMarker("b")),
            ]
        )

        let finalState = TopologyNetworkRuntimeEngine.run(scenario: scenario)

        XCTAssertEqual(finalState.currentTimeMilliseconds, 1_000)
        XCTAssertTrue(finalState.pendingEvents.isEmpty)
        XCTAssertEqual(finalState.seed, 1)
    }

    func testIPv4ForwardingClonePreservesIdentityAndDecrementsTTL() {
        let packet = TopologyIPv4Packet(
            identity: 99,
            senderIPAddress: "192.168.0.10",
            receiverIPAddress: "192.168.1.20",
            timeToLive: 2,
            protocolNumber: .icmp,
            payload: .icmp(TopologyICMPMessage(kind: .echoRequest, identifier: 3, sequenceNumber: 4))
        )

        let forwarded = packet.forwardingClone()
        let expired = forwarded.forwardingClone()

        XCTAssertEqual(forwarded.identity, 99)
        XCTAssertEqual(forwarded.timeToLive, 1)
        XCTAssertEqual(expired.identity, 99)
        XCTAssertEqual(expired.timeToLive, 0)
    }

    func testDirectCableARPRequestAndReplyPopulateBothCaches() {
        let sourceNodeID = uuid("00000000-0000-0000-0000-000000001401")
        let sourcePortID = uuid("00000000-0000-0000-0000-000000001411")
        let targetNodeID = uuid("00000000-0000-0000-0000-000000001402")
        let targetPortID = uuid("00000000-0000-0000-0000-000000001412")
        var engine = startedEngine(
            nodes: [pc(sourceNodeID, sourcePortID), pc(targetNodeID, targetPortID)],
            links: [link(sourceNodeID, sourcePortID, targetNodeID, targetPortID)],
            devices: [
                sourceNodeID: device("192.168.0.10"),
                targetNodeID: device("192.168.0.20"),
            ]
        )

        let resolved = engine.resolveMACAddress(nodeID: sourceNodeID, targetIPAddress: "192.168.0.20")

        XCTAssertEqual(resolved, TopologyNetworkRuntimeEngine.stableMACAddress(for: targetPortID))
        XCTAssertEqual(engine.state.arpCachesByNodeID[sourceNodeID]?["192.168.0.20"]?.macAddress, resolved)
        XCTAssertEqual(
            engine.state.arpCachesByNodeID[targetNodeID]?["192.168.0.10"]?.macAddress,
            TopologyNetworkRuntimeEngine.stableMACAddress(for: sourcePortID)
        )
    }

    func testPingAcrossSwitchUsesEthernetARPAndICMPPackets() {
        let sourceNodeID = uuid("00000000-0000-0000-0000-000000001421")
        let sourcePortID = uuid("00000000-0000-0000-0000-000000001431")
        let switchNodeID = uuid("00000000-0000-0000-0000-000000001422")
        let switchPortA = uuid("00000000-0000-0000-0000-000000001432")
        let switchPortB = uuid("00000000-0000-0000-0000-000000001433")
        let targetNodeID = uuid("00000000-0000-0000-0000-000000001423")
        let targetPortID = uuid("00000000-0000-0000-0000-000000001434")
        let switchNode = TopologyNetworkRuntimeNodeSnapshot(
            id: switchNodeID,
            kind: .networkSwitch,
            ports: [
                TopologyNetworkRuntimePortSnapshot(id: switchPortA, label: "sw1"),
                TopologyNetworkRuntimePortSnapshot(id: switchPortB, label: "sw2"),
            ]
        )
        var engine = startedEngine(
            nodes: [pc(sourceNodeID, sourcePortID), switchNode, pc(targetNodeID, targetPortID)],
            links: [
                link(sourceNodeID, sourcePortID, switchNodeID, switchPortA),
                link(switchNodeID, switchPortB, targetNodeID, targetPortID),
            ],
            devices: [sourceNodeID: device("192.168.0.10"), targetNodeID: device("192.168.0.20")]
        )

        let result = engine.sendICMPEcho(
            fromNodeID: sourceNodeID,
            targetIPAddress: "192.168.0.20",
            identifier: 14,
            sequenceNumber: 1
        )

        guard case .delivered = result else { return XCTFail("expected echo reply, got \(result)") }
        XCTAssertEqual(engine.state.icmpObservationsByNodeID[sourceNodeID]?.last?.message.kind, .echoReply)
        XCTAssertEqual(engine.state.switchForwardingTablesByNodeID[switchNodeID]?.count, 2)
        XCTAssertTrue(engine.state.packetTraces.contains { $0.detail == "ARP request for 192.168.0.20" })
        XCTAssertTrue(engine.state.packetTraces.contains { $0.packetIdentity != nil && $0.layer == .network })
    }

    func testRouterTTLExpiryReturnsTimeExceededWithOriginalPacket() {
        let topology = routedTopology()
        var engine = topology.engine

        let result = engine.sendICMPEcho(
            fromNodeID: topology.sourceNodeID,
            targetIPAddress: "20.0.0.2",
            timeToLive: 1,
            identifier: 140,
            sequenceNumber: 1
        )

        guard case let .icmpError(_, _, kind) = result else { return XCTFail("expected ICMP error, got \(result)") }
        XCTAssertEqual(kind, .timeExceeded)
        let observation = engine.state.icmpObservationsByNodeID[topology.sourceNodeID]?.last
        XCTAssertEqual(observation?.message.kind, .timeExceeded)
        XCTAssertEqual(observation?.message.embeddedOriginalPacket?.timeToLive, 1)
        XCTAssertEqual(observation?.message.embeddedOriginalPacket?.receiverIPAddress, "20.0.0.2")
    }

    func testRouterForwardingPreservesPacketIdentityAndDecrementsTTL() {
        let topology = routedTopology()
        var engine = topology.engine

        let result = engine.sendICMPEcho(
            fromNodeID: topology.sourceNodeID,
            targetIPAddress: "20.0.0.2",
            timeToLive: 8,
            identifier: 141,
            sequenceNumber: 1
        )

        guard case .delivered = result else { return XCTFail("expected echo reply, got \(result)") }
        let forwardingTrace = engine.state.packetTraces.first {
            $0.nodeID == topology.routerNodeID && $0.operation == .forwarded && $0.detail == "TTL decremented"
        }
        XCTAssertNotNil(forwardingTrace?.packetIdentity)
        XCTAssertEqual(forwardingTrace?.beforeHeaders.first(where: { $0.name == "ttl" })?.value, "8")
        XCTAssertEqual(forwardingTrace?.afterHeaders.first(where: { $0.name == "ttl" })?.value, "7")
    }

    func testMissingRouterRouteReturnsNetworkUnreachable() {
        let topology = routedTopology()
        var snapshot = topology.engine.state.topologySnapshot
        let sourceToRouterLink = snapshot.links.first {
            $0.sourceNodeID == topology.sourceNodeID || $0.targetNodeID == topology.sourceNodeID
        }
        snapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: snapshot.nodes,
            links: sourceToRouterLink.map { [$0] } ?? [],
            deviceConfigurations: snapshot.deviceConfigurations,
            interfaceConfigurations: snapshot.interfaceConfigurations,
            manualRoutesByNodeID: snapshot.manualRoutesByNodeID
        )
        var engine = TopologyNetworkRuntimeEngine(seed: 14)
        engine.handle(.start(snapshot: snapshot, seed: 14, initialTimeMilliseconds: 0))

        let result = engine.sendICMPEcho(
            fromNodeID: topology.sourceNodeID,
            targetIPAddress: "30.0.0.2",
            identifier: 142,
            sequenceNumber: 1
        )

        guard case let .icmpError(_, _, kind) = result else { return XCTFail("expected ICMP error, got \(result)") }
        XCTAssertEqual(kind, .destinationNetworkUnreachable)
    }

    func testUnresolvedConnectedTargetReturnsHostUnreachable() {
        let sourceNodeID = uuid("00000000-0000-0000-0000-000000001481")
        let sourcePortID = uuid("00000000-0000-0000-0000-000000001491")
        var engine = startedEngine(
            nodes: [pc(sourceNodeID, sourcePortID)],
            links: [],
            devices: [sourceNodeID: device("192.168.50.10")]
        )

        let result = engine.sendICMPEcho(
            fromNodeID: sourceNodeID,
            targetIPAddress: "192.168.50.99",
            identifier: 143,
            sequenceNumber: 1
        )

        guard case let .icmpError(_, _, kind) = result else { return XCTFail("expected ICMP error, got \(result)") }
        XCTAssertEqual(kind, .destinationHostUnreachable)
    }
    func testRIPStartsWithLocalMetricZeroRoutesAndFirstBeaconAtOneSecond() {
        let fixture = ripTopology()
        let table = fixture.engine.state.ripTablesByNodeID[fixture.routerAID] ?? []

        XCTAssertEqual(table.count, 2)
        XCTAssertTrue(table.allSatisfy { $0.metric == 0 && $0.expiresAtMilliseconds == nil })
        XCTAssertTrue(fixture.engine.state.pendingEvents.contains {
            $0.deadlineMilliseconds == 1_000 && $0.kind == .ripBeacon(nodeID: fixture.routerAID)
        })
    }

    func testRIPConvergesAcrossRoutersWithSplitHorizonAndSeededBeacons() {
        var fixture = ripTopology()
        fixture.engine.handle(.advance(toMilliseconds: 2_000))

        let routerATable = fixture.engine.state.ripTablesByNodeID[fixture.routerAID] ?? []
        let routerBTable = fixture.engine.state.ripTablesByNodeID[fixture.routerBID] ?? []
        XCTAssertEqual(routerATable.first(where: { $0.destinationNetwork == "172.16.0.0" })?.metric, 1)
        XCTAssertEqual(routerBTable.first(where: { $0.destinationNetwork == "192.168.0.0" })?.metric, 1)
        XCTAssertFalse(fixture.engine.state.packetTraces.filter { $0.detail?.hasPrefix("RIP advertisement") == true }.isEmpty)

        let advertisementPayloads = (fixture.engine.state.deliveredIPv4PacketsByNodeID[fixture.routerBID] ?? [])
            .compactMap { delivered -> String? in
                guard delivered.packet.senderIPAddress == "10.0.0.1",
                      case let .udp(datagram) = delivered.packet.payload else { return nil }
                return String(data: datagram.payload, encoding: .utf8)
            }
        XCTAssertTrue(advertisementPayloads.contains { $0.contains("192.168.0.0 255.255.255.0 0") })
        XCTAssertFalse(advertisementPayloads.contains { $0.contains("10.0.0.0 255.255.255.0 0") })

        let nextBeaconDeadlines = fixture.engine.state.pendingEvents.compactMap { event -> UInt64? in
            guard case .ripBeacon = event.kind else { return nil }
            return event.deadlineMilliseconds
        }
        XCTAssertTrue(nextBeaconDeadlines.allSatisfy { (26_200...36_200).contains($0) })
    }

    func testRIPExpiryMarksLearnedRouteInfinityWithoutDeletingIt() {
        var fixture = ripTopology()
        fixture.engine.handle(.advance(toMilliseconds: 2_000))
        let learnedRoute = fixture.engine.state.ripTablesByNodeID[fixture.routerAID]?
            .first(where: { $0.destinationNetwork == "172.16.0.0" })
        let expiry = try! XCTUnwrap(learnedRoute?.expiresAtMilliseconds)
        fixture.engine.setRIPEnabled(nodeID: fixture.routerBID, enabled: false)
        fixture.engine.handle(.advance(toMilliseconds: expiry + 1))

        let route = fixture.engine.state.ripTablesByNodeID[fixture.routerAID]?
            .first(where: { $0.destinationNetwork == "172.16.0.0" })
        XCTAssertEqual(route?.metric, TopologyNetworkRuntimeEngine.ripInfinity)
    }

    func testGatewayNeverInitializesOrExecutesRIP() {
        let gatewayID = uuid("00000000-0000-0000-0000-0000000015A1")
        let wanID = uuid("00000000-0000-0000-0000-0000000015A2")
        let lanID = uuid("00000000-0000-0000-0000-0000000015A3")
        let gateway = TopologyNetworkRuntimeNodeSnapshot(
            id: gatewayID,
            kind: .gateway,
            ports: [
                TopologyNetworkRuntimePortSnapshot(id: wanID, label: "wan0"),
                TopologyNetworkRuntimePortSnapshot(id: lanID, label: "lan0"),
            ]
        )
        let snapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: [gateway],
            links: [],
            deviceConfigurations: [:],
            interfaceConfigurations: [
                TopologyRuntimeInterfaceKey(nodeID: gatewayID, portID: wanID):
                    TopologyRuntimeInterfaceConfiguration(ipAddress: "42.0.0.10", subnetMask: "255.0.0.0"),
                TopologyRuntimeInterfaceKey(nodeID: gatewayID, portID: lanID):
                    TopologyRuntimeInterfaceConfiguration(ipAddress: "192.168.0.1", subnetMask: "255.255.255.0"),
            ],
            manualRoutesByNodeID: [:],
            ripEnabledByNodeID: [gatewayID: true]
        )
        var engine = TopologyNetworkRuntimeEngine(seed: 15)
        engine.handle(.start(snapshot: snapshot, seed: 15, initialTimeMilliseconds: 0))

        XCTAssertNil(engine.state.ripTablesByNodeID[gatewayID])
        XCTAssertFalse(engine.state.pendingEvents.contains { $0.kind == .ripBeacon(nodeID: gatewayID) })
    }

    func testUDPSocketBindingDeliveryAndPortRelease() {
        let sourceNodeID = uuid("00000000-0000-0000-0000-0000000015B1")
        let sourcePortID = uuid("00000000-0000-0000-0000-0000000015B2")
        let targetNodeID = uuid("00000000-0000-0000-0000-0000000015B3")
        let targetPortID = uuid("00000000-0000-0000-0000-0000000015B4")
        var engine = startedEngine(
            nodes: [pc(sourceNodeID, sourcePortID), pc(targetNodeID, targetPortID)],
            links: [link(sourceNodeID, sourcePortID, targetNodeID, targetPortID)],
            devices: [sourceNodeID: device("192.168.5.10"), targetNodeID: device("192.168.5.20")]
        )
        let automatic = engine.bindUDPSocket(nodeID: targetNodeID)
        let automaticPort = automatic.flatMap { engine.state.socketsByID[$0]?.localPort }
        XCTAssertNotNil(automatic)
        XCTAssertTrue(automaticPort.map { (49_152..<65_535).contains(Int($0)) } ?? false)

        let receiver = engine.bindUDPSocket(nodeID: targetNodeID, localPort: 9000)
        let sender = engine.bindUDPSocket(
            nodeID: sourceNodeID,
            localPort: 8000,
            remoteIPAddress: "192.168.5.20",
            remotePort: 9000
        )
        XCTAssertNotNil(receiver)
        XCTAssertNotNil(sender)
        XCTAssertNil(engine.bindUDPSocket(nodeID: targetNodeID, localPort: 9000))

        _ = engine.sendUDP(socketID: sender!, payload: Data("hello".utf8))
        let received = engine.receiveUDP(socketID: receiver!)
        XCTAssertEqual(String(data: received?.datagram.payload ?? Data(), encoding: .utf8), "hello")
        XCTAssertEqual(received?.senderIPAddress, "192.168.5.10")

        engine.closeSocket(socketID: receiver!)
        XCTAssertNotNil(engine.bindUDPSocket(nodeID: targetNodeID, localPort: 9000))
    }

    func testUDPEphemeralAllocationDoesNotPerturbSeededRIPJitter() {
        let nodeID = uuid("00000000-0000-0000-0000-0000000015F1")
        let portID = uuid("00000000-0000-0000-0000-0000000015F2")
        let nodes = [pc(nodeID, portID)]
        let devices = [nodeID: device("192.168.10.10")]
        var socketEngine = startedEngine(nodes: nodes, links: [], devices: devices)
        var ripOnlyEngine = startedEngine(nodes: nodes, links: [], devices: devices)

        XCTAssertNotNil(socketEngine.bindUDPSocket(nodeID: nodeID))
        XCTAssertEqual(socketEngine.nextRIPJitterMilliseconds(), ripOnlyEngine.nextRIPJitterMilliseconds())
    }

    func testUDPBroadcastUsesEveryInterfaceAndReceiverRepliesToLastPeer() {
        let routerID = uuid("00000000-0000-0000-0000-0000000015E1")
        let routerPortA = uuid("00000000-0000-0000-0000-0000000015E2")
        let routerPortB = uuid("00000000-0000-0000-0000-0000000015E3")
        let pcAID = uuid("00000000-0000-0000-0000-0000000015E4")
        let pcAPort = uuid("00000000-0000-0000-0000-0000000015E5")
        let pcBID = uuid("00000000-0000-0000-0000-0000000015E6")
        let pcBPort = uuid("00000000-0000-0000-0000-0000000015E7")
        let router = TopologyNetworkRuntimeNodeSnapshot(
            id: routerID,
            kind: .router,
            ports: [
                TopologyNetworkRuntimePortSnapshot(id: routerPortA, label: "rt1"),
                TopologyNetworkRuntimePortSnapshot(id: routerPortB, label: "rt2"),
            ]
        )
        let snapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: [router, pc(pcAID, pcAPort), pc(pcBID, pcBPort)],
            links: [
                link(routerID, routerPortA, pcAID, pcAPort),
                link(routerID, routerPortB, pcBID, pcBPort),
            ],
            deviceConfigurations: [pcAID: device("10.0.0.2"), pcBID: device("20.0.0.2")],
            interfaceConfigurations: [
                TopologyRuntimeInterfaceKey(nodeID: routerID, portID: routerPortA):
                    TopologyRuntimeInterfaceConfiguration(ipAddress: "10.0.0.1", subnetMask: "255.255.255.0"),
                TopologyRuntimeInterfaceKey(nodeID: routerID, portID: routerPortB):
                    TopologyRuntimeInterfaceConfiguration(ipAddress: "20.0.0.1", subnetMask: "255.255.255.0"),
            ],
            manualRoutesByNodeID: [:]
        )
        var engine = TopologyNetworkRuntimeEngine(seed: 15)
        engine.handle(.start(snapshot: snapshot, seed: 15, initialTimeMilliseconds: 0))
        let sender = try! XCTUnwrap(engine.bindUDPSocket(nodeID: routerID, localPort: 8000))
        let receiverA = try! XCTUnwrap(engine.bindUDPSocket(nodeID: pcAID, localPort: 9000))
        let receiverB = try! XCTUnwrap(engine.bindUDPSocket(nodeID: pcBID, localPort: 9000))

        _ = engine.sendUDP(
            socketID: sender,
            payload: Data("broadcast".utf8),
            destinationIPAddress: "255.255.255.255",
            destinationPort: 9000
        )

        XCTAssertEqual(engine.receiveUDP(socketID: receiverA)?.senderIPAddress, "10.0.0.1")
        XCTAssertEqual(engine.receiveUDP(socketID: receiverB)?.senderIPAddress, "20.0.0.1")
        XCTAssertEqual(engine.state.socketsByID[receiverA]?.remoteIPAddress, "10.0.0.1")
        XCTAssertEqual(engine.state.socketsByID[receiverA]?.remotePort, 8000)

        _ = engine.sendUDP(socketID: receiverA, payload: Data("reply".utf8))
        XCTAssertEqual(String(data: engine.receiveUDP(socketID: sender)?.datagram.payload ?? Data(), encoding: .utf8), "reply")
    }

    func testRIPEnabledRouterUsesOnlyDynamicTableAndDisableRestoresStaticLookup() {
        let routerID = uuid("00000000-0000-0000-0000-0000000015C1")
        let routerPortID = uuid("00000000-0000-0000-0000-0000000015C2")
        let neighborID = uuid("00000000-0000-0000-0000-0000000015C3")
        let neighborPortID = uuid("00000000-0000-0000-0000-0000000015C4")
        let router = TopologyNetworkRuntimeNodeSnapshot(
            id: routerID,
            kind: .router,
            ports: [TopologyNetworkRuntimePortSnapshot(id: routerPortID, label: "rt1")]
        )
        let snapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: [router, pc(neighborID, neighborPortID)],
            links: [link(routerID, routerPortID, neighborID, neighborPortID)],
            deviceConfigurations: [neighborID: device("10.0.0.2")],
            interfaceConfigurations: [
                TopologyRuntimeInterfaceKey(nodeID: routerID, portID: routerPortID):
                    TopologyRuntimeInterfaceConfiguration(ipAddress: "10.0.0.1", subnetMask: "255.255.255.0")
            ],
            manualRoutesByNodeID: [
                routerID: [TopologyRuntimeManualRoute(
                    destinationNetwork: "203.0.113.0",
                    subnetMask: "255.255.255.0",
                    gateway: "10.0.0.2",
                    interfaceIPAddress: "10.0.0.1"
                )]
            ],
            ripEnabledByNodeID: [routerID: true]
        )
        var engine = TopologyNetworkRuntimeEngine(seed: 15)
        engine.handle(.start(snapshot: snapshot, seed: 15, initialTimeMilliseconds: 0))
        let packet = TopologyIPv4Packet(
            identity: engine.allocatePacketIdentity(),
            senderIPAddress: "10.0.0.1",
            receiverIPAddress: "203.0.113.20",
            timeToLive: 64,
            protocolNumber: .udp,
            payload: .udp(TopologyUDPDatagram(sourcePort: 6000, destinationPort: 7000, payload: Data()))
        )

        XCTAssertEqual(
            engine.sendIPv4Packet(fromNodeID: routerID, packet: packet),
            .icmpError(
                packetIdentity: packet.identity,
                nodeID: routerID,
                kind: .destinationNetworkUnreachable
            )
        )

        engine.setRIPEnabled(nodeID: routerID, enabled: false)
        let staticResult = engine.sendIPv4Packet(fromNodeID: routerID, packet: packet)
        guard case .delivered = staticResult else {
            return XCTFail("expected static route delivery after disabling RIP, got \(staticResult)")
        }
    }

    func testUDPReceiveTimeoutAdvancesVirtualClockAndReturnsNil() {
        let nodeID = uuid("00000000-0000-0000-0000-0000000015D1")
        let portID = uuid("00000000-0000-0000-0000-0000000015D2")
        var engine = startedEngine(nodes: [pc(nodeID, portID)], links: [], devices: [nodeID: device("10.1.0.1")])
        let socketID = try! XCTUnwrap(engine.bindUDPSocket(nodeID: nodeID, localPort: 9999))

        XCTAssertNil(engine.receiveUDP(socketID: socketID, timeoutMilliseconds: 250))
        XCTAssertEqual(engine.state.currentTimeMilliseconds, 250)
    }

    func testDHCPAutomaticClientCompletesDiscoverOfferRequestAckAndAppliesConfiguration() {
        let serverID = uuid("00000000-0000-0000-0000-000000001601")
        let serverPortID = uuid("00000000-0000-0000-0000-000000001602")
        let clientID = uuid("00000000-0000-0000-0000-000000001603")
        let clientPortID = uuid("00000000-0000-0000-0000-000000001604")
        let snapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: [pc(serverID, serverPortID), pc(clientID, clientPortID)],
            links: [link(serverID, serverPortID, clientID, clientPortID)],
            deviceConfigurations: [
                serverID: device("192.168.50.1"),
                clientID: device("169.254.1.2", mask: "0.0.0.0"),
            ],
            interfaceConfigurations: [:],
            manualRoutesByNodeID: [:],
            dhcpClientConfigurationsByNodeID: [clientID: TopologyDHCPClientConfiguration(isEnabled: true)],
            dhcpServerConfigurationsByNodeID: [
                serverID: TopologyDHCPServerConfiguration(
                    isActive: true,
                    lowerBoundIPAddress: "192.168.50.20",
                    upperBoundIPAddress: "192.168.50.29",
                    gatewayIPAddress: "192.168.50.1",
                    dnsServerIPAddress: "192.168.50.53",
                    useOwnSettings: true
                )
            ]
        )
        var engine = TopologyNetworkRuntimeEngine(seed: 16)
        engine.handle(.start(snapshot: snapshot, seed: 16, initialTimeMilliseconds: 0))

        engine.handle(.advance(toMilliseconds: 1_000))

        let configuration = engine.state.topologySnapshot.deviceConfigurations[clientID]
        XCTAssertEqual(configuration?.ipAddress, "192.168.50.20")
        XCTAssertEqual(configuration?.subnetMask, "255.255.255.0")
        XCTAssertEqual(configuration?.defaultGateway, "192.168.50.1")
        XCTAssertEqual(configuration?.dnsServer, "192.168.50.53")
        XCTAssertEqual(engine.state.dhcpClientStatusesByNodeID[clientID]?.state, .finish)
        XCTAssertEqual(engine.state.dhcpClientStatusesByNodeID[clientID]?.errorCount, 0)
        XCTAssertEqual(engine.state.dhcpClientStatusesByNodeID[clientID]?.succeeded, true)
        guard let leaseExpiry = engine.state.dhcpLeasesByIPAddress.values.first?.expiresAtMilliseconds else {
            return XCTFail("expected a finite dynamic DHCP lease")
        }
        XCTAssertGreaterThan(leaseExpiry, engine.state.currentTimeMilliseconds)
        if leaseExpiry >= engine.state.currentTimeMilliseconds {
            XCTAssertLessThanOrEqual(
                leaseExpiry - engine.state.currentTimeMilliseconds,
                TopologyNetworkRuntimeEngine.dhcpDynamicLeaseLifetimeMilliseconds
            )
        }
        let applicationDetails = engine.state.packetTraces.compactMap(\.detail)
        XCTAssertTrue(applicationDetails.contains("DHCPDISCOVER"))
        XCTAssertTrue(applicationDetails.contains("DHCPOFFER"))
        XCTAssertTrue(applicationDetails.contains("DHCPREQUEST"))
        XCTAssertTrue(applicationDetails.contains("DHCPACK"))
    }

    func testDHCPStaticAssignmentIsCaseInsensitiveAndHasNonExpiringLease() {
        let serverID = uuid("00000000-0000-0000-0000-000000001611")
        let serverPortID = uuid("00000000-0000-0000-0000-000000001612")
        let clientID = uuid("00000000-0000-0000-0000-000000001613")
        let clientPortID = uuid("00000000-0000-0000-0000-000000001614")
        let clientMAC = TopologyNetworkRuntimeEngine.stableMACAddress(for: clientPortID).lowercased()
        let snapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: [pc(serverID, serverPortID), pc(clientID, clientPortID)],
            links: [link(serverID, serverPortID, clientID, clientPortID)],
            deviceConfigurations: [serverID: device("10.0.0.1"), clientID: device("0.0.0.0")],
            interfaceConfigurations: [:],
            manualRoutesByNodeID: [:],
            dhcpClientConfigurationsByNodeID: [clientID: TopologyDHCPClientConfiguration(isEnabled: true)],
            dhcpServerConfigurationsByNodeID: [
                serverID: TopologyDHCPServerConfiguration(
                    isActive: true,
                    lowerBoundIPAddress: "10.0.0.20",
                    upperBoundIPAddress: "10.0.0.20",
                    staticAssignments: [TopologyDHCPStaticAssignment(macAddress: clientMAC, ipAddress: "10.0.0.99")]
                )
            ]
        )
        var engine = TopologyNetworkRuntimeEngine(seed: 16)
        engine.handle(.start(snapshot: snapshot, seed: 16, initialTimeMilliseconds: 0))

        engine.handle(.advance(toMilliseconds: 1_000))

        XCTAssertEqual(engine.state.topologySnapshot.deviceConfigurations[clientID]?.ipAddress, "10.0.0.99")
        XCTAssertNil(engine.state.dhcpLeasesByIPAddress.values.first?.expiresAtMilliseconds)
    }

    func testDHCPClientRetriesTenTimeoutsAndRestoresOnlyOldIPAddress() {
        let clientID = uuid("00000000-0000-0000-0000-000000001621")
        let clientPortID = uuid("00000000-0000-0000-0000-000000001622")
        let oldConfiguration = TopologyRuntimeDeviceConfiguration(
            ipAddress: "169.254.5.7",
            subnetMask: "255.255.0.0",
            defaultGateway: "169.254.0.1",
            dnsServer: "169.254.0.53"
        )
        let snapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: [pc(clientID, clientPortID)],
            links: [],
            deviceConfigurations: [clientID: oldConfiguration],
            interfaceConfigurations: [:],
            manualRoutesByNodeID: [:],
            dhcpClientConfigurationsByNodeID: [clientID: TopologyDHCPClientConfiguration(isEnabled: true)]
        )
        var engine = TopologyNetworkRuntimeEngine(seed: 16)
        engine.handle(.start(snapshot: snapshot, seed: 16, initialTimeMilliseconds: 0))

        engine.handle(.advance(toMilliseconds: 0))
        XCTAssertEqual(engine.state.topologySnapshot.deviceConfigurations[clientID]?.ipAddress, "0.0.0.0")
        XCTAssertEqual(engine.state.dhcpClientStatusesByNodeID[clientID]?.state, .discover)
        XCTAssertEqual(engine.state.dhcpClientStatusesByNodeID[clientID]?.errorCount, 0)

        engine.handle(.advance(toMilliseconds: 25_000))

        XCTAssertEqual(engine.state.dhcpClientStatusesByNodeID[clientID]?.state, .finish)
        XCTAssertEqual(engine.state.dhcpClientStatusesByNodeID[clientID]?.errorCount, 10)
        XCTAssertEqual(engine.state.dhcpClientStatusesByNodeID[clientID]?.succeeded, false)
        XCTAssertEqual(engine.state.topologySnapshot.deviceConfigurations[clientID], oldConfiguration)
        XCTAssertNil(engine.state.dhcpClientContextsByNodeID[clientID])
        XCTAssertTrue(engine.state.socketsByID.isEmpty)
    }

    func testTCPThreeWayHandshakeCreatesEstablishedClientAndAcceptedServerSocket() throws {
        let clientID = uuid("00000000-0000-0000-0000-000000001701")
        let clientPortID = uuid("00000000-0000-0000-0000-000000001711")
        let serverID = uuid("00000000-0000-0000-0000-000000001702")
        let serverPortID = uuid("00000000-0000-0000-0000-000000001712")
        var engine = startedEngine(
            nodes: [pc(clientID, clientPortID), pc(serverID, serverPortID)],
            links: [link(clientID, clientPortID, serverID, serverPortID)],
            devices: [clientID: device("10.17.0.1"), serverID: device("10.17.0.2")]
        )

        let listenerID = try XCTUnwrap(engine.openTCPServerSocket(nodeID: serverID, localPort: 8080))
        let clientSocketID = try XCTUnwrap(engine.openTCPClientSocket(
            nodeID: clientID,
            remoteIPAddress: "10.17.0.2",
            remotePort: 8080
        ))

        XCTAssertTrue(engine.connectTCP(socketID: clientSocketID))
        let acceptedSocketID = try XCTUnwrap(engine.state.tcpAcceptedSocketIDsByListenerID[listenerID]?.first)
        XCTAssertEqual(engine.state.socketsByID[clientSocketID]?.tcpState, .established)
        XCTAssertEqual(engine.state.socketsByID[acceptedSocketID]?.tcpState, .established)
        XCTAssertTrue(engine.state.packetTraces.contains { $0.detail == "TCP SYN_SENT -> ESTABLISHED" })
        XCTAssertTrue(engine.state.packetTraces.contains { $0.detail == "TCP SYN_RCVD -> ESTABLISHED" })
    }

    func testTCPSendSegmentsAtJavaMSSAndReassemblesOnePushTerminatedMessage() throws {
        let clientID = uuid("00000000-0000-0000-0000-000000001721")
        let clientPortID = uuid("00000000-0000-0000-0000-000000001731")
        let serverID = uuid("00000000-0000-0000-0000-000000001722")
        let serverPortID = uuid("00000000-0000-0000-0000-000000001732")
        var engine = startedEngine(
            nodes: [pc(clientID, clientPortID), pc(serverID, serverPortID)],
            links: [link(clientID, clientPortID, serverID, serverPortID)],
            devices: [clientID: device("10.18.0.1"), serverID: device("10.18.0.2")]
        )
        let listenerID = try XCTUnwrap(engine.openTCPServerSocket(nodeID: serverID, localPort: 8081))
        let clientSocketID = try XCTUnwrap(engine.openTCPClientSocket(
            nodeID: clientID,
            remoteIPAddress: "10.18.0.2",
            remotePort: 8081
        ))
        XCTAssertTrue(engine.connectTCP(socketID: clientSocketID))
        let acceptedSocketID = try XCTUnwrap(engine.state.tcpAcceptedSocketIDsByListenerID[listenerID]?.first)
        let payload = Data((0..<3_001).map { UInt8($0 % 251) })

        XCTAssertTrue(engine.sendTCP(socketID: clientSocketID, payload: payload))
        XCTAssertEqual(engine.receiveTCP(socketID: acceptedSocketID), payload)
        let payloadLengths = engine.state.packetTraces.compactMap { trace -> Int? in
            guard trace.detail?.hasPrefix("TCP data") == true else { return nil }
            return trace.afterHeaders.first(where: { $0.name == "payloadLength" }).flatMap { Int($0.value) }
        }
        XCTAssertEqual(payloadLengths, [1_460, 1_460, 81])
    }

    func testTCPConnectionTimeoutRetransmitsAtMostThreeTimesAndReleasesPort() throws {
        let clientID = uuid("00000000-0000-0000-0000-000000001741")
        let clientPortID = uuid("00000000-0000-0000-0000-000000001751")
        var engine = startedEngine(
            nodes: [pc(clientID, clientPortID)],
            links: [],
            devices: [clientID: device("10.19.0.1")]
        )
        let socketID = try XCTUnwrap(engine.openTCPClientSocket(
            nodeID: clientID,
            remoteIPAddress: "10.19.0.99",
            remotePort: 80
        ))
        let localPort = try XCTUnwrap(engine.state.socketsByID[socketID]?.localPort)

        XCTAssertFalse(engine.connectTCP(socketID: socketID))
        XCTAssertEqual(engine.state.tcpSessionsByID[socketID]?.sendAttempts, 3)
        XCTAssertEqual(engine.state.socketsByID[socketID]?.tcpState, .closed)
        XCTAssertFalse(engine.isTCPPortReserved(nodeID: clientID, port: localPort))
        XCTAssertEqual(
            engine.state.packetTraces.filter { $0.detail?.contains("TCP SYN retransmission") == true }.count,
            2
        )
    }

    func testTCPFINCloseUsesJavaStatesAndTimeWaitReleasesBothConnectionPorts() throws {
        let clientID = uuid("00000000-0000-0000-0000-000000001761")
        let clientPortID = uuid("00000000-0000-0000-0000-000000001771")
        let serverID = uuid("00000000-0000-0000-0000-000000001762")
        let serverPortID = uuid("00000000-0000-0000-0000-000000001772")
        var engine = startedEngine(
            nodes: [pc(clientID, clientPortID), pc(serverID, serverPortID)],
            links: [link(clientID, clientPortID, serverID, serverPortID)],
            devices: [clientID: device("10.20.0.1"), serverID: device("10.20.0.2")]
        )
        let listenerID = try XCTUnwrap(engine.openTCPServerSocket(nodeID: serverID, localPort: 9090))
        let clientSocketID = try XCTUnwrap(engine.openTCPClientSocket(
            nodeID: clientID,
            remoteIPAddress: "10.20.0.2",
            remotePort: 9090
        ))
        XCTAssertTrue(engine.connectTCP(socketID: clientSocketID))
        let serverSocketID = try XCTUnwrap(engine.state.tcpAcceptedSocketIDsByListenerID[listenerID]?.first)

        engine.closeTCPSocket(socketID: clientSocketID)
        XCTAssertEqual(engine.state.socketsByID[clientSocketID]?.tcpState, .finishWait2)
        XCTAssertEqual(engine.state.socketsByID[serverSocketID]?.tcpState, .closeWait)
        engine.closeTCPSocket(socketID: serverSocketID)
        XCTAssertEqual(engine.state.socketsByID[clientSocketID]?.tcpState, .timeWait)
        XCTAssertEqual(engine.state.socketsByID[serverSocketID]?.tcpState, .closed)

        engine.handle(.advance(toMilliseconds: engine.state.currentTimeMilliseconds + TopologyNetworkRuntimeEngine.tcpRoundTripTimeMilliseconds))
        XCTAssertEqual(engine.state.socketsByID[clientSocketID]?.tcpState, .closed)
        XCTAssertEqual(engine.state.socketsByID[listenerID]?.tcpState, .listen)
    }
    func testReducerProjectsLifecycleClockAndCompatibilityTraceThroughEngine() {
        var state = TopologyEditorState()
        let nodeID = UUID(uuidString: "00000000-0000-0000-0000-000000000120")!

        TopologyEditorReducer.reduce(
            state: &state,
            action: .placeNode(kind: .pc, at: CGPoint(x: 20, y: 20), nodeID: nodeID)
        )
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .simulationTick(step: 25))
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: nodeID, command: "help"))

        XCTAssertEqual(state.networkRuntime.state.phase, .running)
        XCTAssertEqual(state.networkRuntime.state.currentTimeMilliseconds, 25)
        XCTAssertEqual(state.simulationTick, 25)
        XCTAssertEqual(state.networkRuntime.state.topologySnapshot.nodes.map(\.id), [nodeID])
        XCTAssertEqual(state.networkRuntime.state.packetTraces.count, 1)
        XCTAssertEqual(state.networkRuntime.state.packetTraces.first?.operation, .compatibilityAdapter)
        XCTAssertEqual(state.networkRuntime.state.packetTraces.first?.detail, "help")
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeHelpDisplayed)
    }
    private struct RoutedFixture {
        let engine: TopologyNetworkRuntimeEngine
        let sourceNodeID: UUID
        let routerNodeID: UUID
    }

    private func routedTopology() -> RoutedFixture {
        let sourceNodeID = uuid("00000000-0000-0000-0000-000000001451")
        let sourcePortID = uuid("00000000-0000-0000-0000-000000001461")
        let routerNodeID = uuid("00000000-0000-0000-0000-000000001452")
        let routerPortA = uuid("00000000-0000-0000-0000-000000001462")
        let routerPortB = uuid("00000000-0000-0000-0000-000000001463")
        let targetNodeID = uuid("00000000-0000-0000-0000-000000001453")
        let targetPortID = uuid("00000000-0000-0000-0000-000000001464")
        let router = TopologyNetworkRuntimeNodeSnapshot(
            id: routerNodeID,
            kind: .router,
            ports: [
                TopologyNetworkRuntimePortSnapshot(id: routerPortA, label: "rt1"),
                TopologyNetworkRuntimePortSnapshot(id: routerPortB, label: "rt2"),
            ]
        )
        let interfaces = [
            TopologyRuntimeInterfaceKey(nodeID: routerNodeID, portID: routerPortA):
                TopologyRuntimeInterfaceConfiguration(ipAddress: "10.0.0.1", subnetMask: "255.255.255.0"),
            TopologyRuntimeInterfaceKey(nodeID: routerNodeID, portID: routerPortB):
                TopologyRuntimeInterfaceConfiguration(ipAddress: "20.0.0.1", subnetMask: "255.255.255.0"),
        ]
        let snapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: [pc(sourceNodeID, sourcePortID), router, pc(targetNodeID, targetPortID)],
            links: [
                link(sourceNodeID, sourcePortID, routerNodeID, routerPortA),
                link(routerNodeID, routerPortB, targetNodeID, targetPortID),
            ],
            deviceConfigurations: [
                sourceNodeID: device("10.0.0.2", gateway: "10.0.0.1"),
                routerNodeID: device("10.0.0.1"),
                targetNodeID: device("20.0.0.2", gateway: "20.0.0.1"),
            ],
            interfaceConfigurations: interfaces,
            manualRoutesByNodeID: [:]
        )
        var engine = TopologyNetworkRuntimeEngine(seed: 14)
        engine.handle(.start(snapshot: snapshot, seed: 14, initialTimeMilliseconds: 0))
        return RoutedFixture(engine: engine, sourceNodeID: sourceNodeID, routerNodeID: routerNodeID)
    }

    func testGatewayUDPNATCreatesPATMappingRewritesReplyAndSupportsResetAndExpiry() throws {
        var fixture = gatewayNATTopology()
        let remoteSocketID = try XCTUnwrap(fixture.engine.bindUDPSocket(
            nodeID: fixture.remoteNodeID,
            localPort: 53,
            localIPAddress: "203.0.113.2"
        ))
        let clientSocketID = try XCTUnwrap(fixture.engine.bindUDPSocket(
            nodeID: fixture.clientNodeID,
            localPort: 40_000,
            localIPAddress: "192.168.0.2",
            remoteIPAddress: "203.0.113.2",
            remotePort: 53
        ))

        _ = fixture.engine.sendUDP(socketID: clientSocketID, payload: Data("query".utf8))
        let request = try XCTUnwrap(fixture.engine.receiveUDP(socketID: remoteSocketID))
        let mapping = try XCTUnwrap(fixture.engine.natMappings(gatewayNodeID: fixture.gatewayNodeID).first)
        XCTAssertEqual(mapping.protocolNumber, .udp)
        XCTAssertEqual(mapping.remoteIPAddress, "203.0.113.2")
        XCTAssertEqual(mapping.lanIPAddress, "192.168.0.2")
        XCTAssertEqual(mapping.lanPortOrIdentifier, 40_000)
        XCTAssertEqual(request.senderIPAddress, "203.0.113.1")
        XCTAssertEqual(request.datagram.sourcePort, mapping.translatedPortOrIdentifier)

        _ = fixture.engine.sendUDP(socketID: remoteSocketID, payload: Data("reply".utf8))
        let response = try XCTUnwrap(fixture.engine.receiveUDP(socketID: clientSocketID))
        XCTAssertEqual(response.receiverIPAddress, "192.168.0.2")
        XCTAssertEqual(response.datagram.destinationPort, 40_000)
        XCTAssertTrue(fixture.engine.state.packetTraces.contains {
            $0.operation == .rewritten && $0.detail == "NAT/PAT LAN to WAN"
        })
        XCTAssertTrue(fixture.engine.state.packetTraces.contains {
            $0.operation == .rewritten && $0.detail == "NAT/PAT WAN to LAN"
        })

        fixture.engine.clearDynamicNATMappings(gatewayNodeID: fixture.gatewayNodeID)
        XCTAssertTrue(fixture.engine.natMappings(gatewayNodeID: fixture.gatewayNodeID).isEmpty)
        _ = fixture.engine.sendUDP(socketID: clientSocketID, payload: Data("again".utf8))
        let recreatedMapping = try XCTUnwrap(
            fixture.engine.natMappings(gatewayNodeID: fixture.gatewayNodeID).first
        )
        let retentionDeadline = recreatedMapping.updatedAtMilliseconds
            + TopologyNetworkRuntimeEngine.natRetentionMilliseconds
        let sweepInterval = TopologyNetworkRuntimeEngine.natExpirySweepIntervalMilliseconds
        let expirySweepDeadline = ((retentionDeadline + sweepInterval - 1) / sweepInterval) * sweepInterval
        fixture.engine.handle(.advance(toMilliseconds: expirySweepDeadline))
        XCTAssertTrue(fixture.engine.natMappings(gatewayNodeID: fixture.gatewayNodeID).isEmpty)
    }

    func testGatewayTCPNATCreatesMappingOnlyForOpeningSYNAndEstablishesSession() throws {
        var fixture = gatewayNATTopology()
        let listenerID = try XCTUnwrap(fixture.engine.openTCPServerSocket(
            nodeID: fixture.remoteNodeID,
            localPort: 443,
            localIPAddress: "203.0.113.2"
        ))
        let clientSocketID = try XCTUnwrap(fixture.engine.openTCPClientSocket(
            nodeID: fixture.clientNodeID,
            remoteIPAddress: "203.0.113.2",
            remotePort: 443,
            localIPAddress: "192.168.0.2",
            localPort: 40_001
        ))

        XCTAssertTrue(fixture.engine.connectTCP(socketID: clientSocketID))
        let mapping = try XCTUnwrap(fixture.engine.natMappings(gatewayNodeID: fixture.gatewayNodeID).first)
        XCTAssertEqual(mapping.protocolNumber, .tcp)
        XCTAssertNotEqual(mapping.translatedPortOrIdentifier, 40_001)
        let acceptedID = try XCTUnwrap(fixture.engine.state.tcpAcceptedSocketIDsByListenerID[listenerID]?.first)
        XCTAssertEqual(fixture.engine.state.socketsByID[clientSocketID]?.tcpState, .established)
        XCTAssertEqual(fixture.engine.state.socketsByID[acceptedID]?.tcpState, .established)
        XCTAssertEqual(fixture.engine.state.socketsByID[acceptedID]?.remoteIPAddress, "203.0.113.1")
        XCTAssertEqual(fixture.engine.state.socketsByID[acceptedID]?.remotePort, mapping.translatedPortOrIdentifier)
        XCTAssertEqual(fixture.engine.natMappings(gatewayNodeID: fixture.gatewayNodeID).count, 1)
    }

    func testGatewayICMPNATKeysMappingByIdentifierAndAnswersWANPingBeforeFirewall() {
        var natFixture = gatewayNATTopology()
        _ = natFixture.engine.sendICMPEcho(
            fromNodeID: natFixture.clientNodeID,
            targetIPAddress: "203.0.113.2",
            identifier: 77
        )
        let mapping = natFixture.engine.natMappings(gatewayNodeID: natFixture.gatewayNodeID).first
        XCTAssertEqual(mapping?.protocolNumber, .icmp)
        XCTAssertEqual(mapping?.translatedPortOrIdentifier, 77)
        XCTAssertEqual(mapping?.lanPortOrIdentifier, 77)

        var pingFixture = gatewayNATTopology(firewallConfiguration: TopologyFirewallConfiguration(
            isActive: true,
            defaultPolicy: .drop,
            dropICMP: true
        ))
        _ = pingFixture.engine.sendICMPEcho(
            fromNodeID: pingFixture.remoteNodeID,
            targetIPAddress: "203.0.113.1",
            identifier: 88
        )
        XCTAssertEqual(
            pingFixture.engine.state.icmpObservationsByNodeID[pingFixture.remoteNodeID]?.last?.message.kind,
            .echoReply
        )
    }
    func testGatewayStaticUDPPortForwardingUsesLastValidConflictAndResetPreservesStaticRows() throws {
        let rows = [
            TopologyGatewayPortForwardingRow(
                protocolValue: "UDP",
                publicPortValue: "53",
                lanIPAddress: "192.168.0.2",
                lanPortValue: "5300"
            ),
            TopologyGatewayPortForwardingRow(
                protocolValue: "17",
                publicPortValue: "53",
                lanIPAddress: "192.168.0.2",
                lanPortValue: "5353"
            ),
            TopologyGatewayPortForwardingRow(
                protocolValue: "invalid",
                publicPortValue: "70000",
                lanIPAddress: "broken",
                lanPortValue: "0"
            ),
        ]
        var fixture = gatewayNATTopology(portForwardingRows: rows)
        let forwardedSocketID = try XCTUnwrap(fixture.engine.bindUDPSocket(
            nodeID: fixture.clientNodeID,
            localPort: 5353,
            localIPAddress: "192.168.0.2",
            remoteIPAddress: "203.0.113.2",
            remotePort: 50_000
        ))
        let remoteSocketID = try XCTUnwrap(fixture.engine.bindUDPSocket(
            nodeID: fixture.remoteNodeID,
            localPort: 50_000,
            localIPAddress: "203.0.113.2",
            remoteIPAddress: "203.0.113.1",
            remotePort: 53
        ))

        let initialMappings = fixture.engine.natMappings(gatewayNodeID: fixture.gatewayNodeID)
        XCTAssertEqual(initialMappings.filter { $0.type == .staticEntry }.count, 1)
        XCTAssertEqual(initialMappings.first?.lanPortOrIdentifier, 5353)

        _ = fixture.engine.sendUDP(socketID: remoteSocketID, payload: Data("request".utf8))
        let forwarded = try XCTUnwrap(fixture.engine.receiveUDP(socketID: forwardedSocketID))
        XCTAssertEqual(forwarded.receiverIPAddress, "192.168.0.2")
        XCTAssertEqual(forwarded.datagram.destinationPort, 5353)
        XCTAssertTrue(fixture.engine.natMappings(gatewayNodeID: fixture.gatewayNodeID).contains {
            $0.type == .dynamicEntryFromStatic && $0.remoteIPAddress == "203.0.113.2"
        })

        _ = fixture.engine.sendUDP(socketID: forwardedSocketID, payload: Data("reply".utf8))
        let reply = try XCTUnwrap(fixture.engine.receiveUDP(socketID: remoteSocketID))
        XCTAssertEqual(reply.senderIPAddress, "203.0.113.1")
        XCTAssertEqual(reply.datagram.sourcePort, 53)

        fixture.engine.clearDynamicNATMappings(gatewayNodeID: fixture.gatewayNodeID)
        let resetMappings = fixture.engine.natMappings(gatewayNodeID: fixture.gatewayNodeID)
        XCTAssertEqual(resetMappings.count, 1)
        XCTAssertEqual(resetMappings.first?.type, .staticEntry)
    }

    func testGatewayStaticTCPPortForwardingAcceptsNumericProtocolAndCreatesReplyMapping() throws {
        var fixture = gatewayNATTopology(portForwardingRows: [
            TopologyGatewayPortForwardingRow(
                protocolValue: "6",
                publicPortValue: "443",
                lanIPAddress: "192.168.0.2",
                lanPortValue: "8443"
            ),
        ])
        let listenerID = try XCTUnwrap(fixture.engine.openTCPServerSocket(
            nodeID: fixture.clientNodeID,
            localPort: 8443,
            localIPAddress: "192.168.0.2"
        ))
        let remoteClientID = try XCTUnwrap(fixture.engine.openTCPClientSocket(
            nodeID: fixture.remoteNodeID,
            remoteIPAddress: "203.0.113.1",
            remotePort: 443,
            localIPAddress: "203.0.113.2",
            localPort: 50_001
        ))

        XCTAssertTrue(fixture.engine.connectTCP(socketID: remoteClientID))
        let acceptedID = try XCTUnwrap(fixture.engine.state.tcpAcceptedSocketIDsByListenerID[listenerID]?.first)
        XCTAssertEqual(fixture.engine.state.socketsByID[acceptedID]?.localPort, 8443)
        XCTAssertEqual(fixture.engine.state.socketsByID[remoteClientID]?.tcpState, .established)
        XCTAssertTrue(fixture.engine.natMappings(gatewayNodeID: fixture.gatewayNodeID).contains {
            $0.type == .dynamicEntryFromStatic && $0.protocolNumber == .tcp
        })
    }
    func testFirewallInactiveAcceptsWhileActiveICMPDropBypassesOrderedRules() {
        let routerID = uuid("00000000-0000-0000-0000-000000001801")
        let portID = uuid("00000000-0000-0000-0000-000000001811")
        let router = TopologyNetworkRuntimeNodeSnapshot(
            id: routerID,
            kind: .router,
            ports: [TopologyNetworkRuntimePortSnapshot(id: portID, label: "rt1")]
        )
        let packet = TopologyIPv4Packet(
            identity: 18,
            senderIPAddress: "203.0.113.10",
            receiverIPAddress: "10.0.0.1",
            timeToLive: 64,
            protocolNumber: .icmp,
            payload: .icmp(TopologyICMPMessage(kind: .echoRequest))
        )
        var inactive = TopologyNetworkRuntimeEngine(seed: 18)
        inactive.handle(.start(snapshot: TopologyNetworkRuntimeTopologySnapshot(
            nodes: [router],
            links: [],
            deviceConfigurations: [:],
            interfaceConfigurations: [
                TopologyRuntimeInterfaceKey(nodeID: routerID, portID: portID):
                    TopologyRuntimeInterfaceConfiguration(ipAddress: "10.0.0.1", subnetMask: "255.255.255.0"),
            ],
            manualRoutesByNodeID: [:],
            firewallConfigurationsByNodeID: [routerID: TopologyFirewallConfiguration()]
        ), seed: 18, initialTimeMilliseconds: 0))

        XCTAssertTrue(inactive.evaluateFirewall(packet: packet, atNodeID: routerID).accepted)

        var active = TopologyNetworkRuntimeEngine(seed: 18)
        active.handle(.start(snapshot: TopologyNetworkRuntimeTopologySnapshot(
            nodes: [router],
            links: [],
            deviceConfigurations: [:],
            interfaceConfigurations: [
                TopologyRuntimeInterfaceKey(nodeID: routerID, portID: portID):
                    TopologyRuntimeInterfaceConfiguration(ipAddress: "10.0.0.1", subnetMask: "255.255.255.0"),
            ],
            manualRoutesByNodeID: [:],
            firewallConfigurationsByNodeID: [routerID: TopologyFirewallConfiguration(
                isActive: true,
                defaultPolicy: .accept,
                dropICMP: true,
                rules: [TopologyFirewallRule(protocolType: .icmp, action: .accept)]
            )]
        ), seed: 18, initialTimeMilliseconds: 0))

        XCTAssertFalse(active.evaluateFirewall(packet: packet, atNodeID: routerID).accepted)
        XCTAssertEqual(active.state.firewallDecisions.last?.ruleIndex, nil)
        XCTAssertEqual(active.state.packetTraces.last?.operation, .dropped)
    }

    func testFirewallFirstMatchingTCPRuleWinsAndEstablishedTrafficBypassesSYNOnlyRules() {
        let fixture = firewallEngine(configuration: TopologyFirewallConfiguration(
            isActive: true,
            defaultPolicy: .drop,
            filterSYNSegmentsOnly: true,
            rules: [
                TopologyFirewallRule(port: 443, protocolType: .tcp, action: .accept),
                TopologyFirewallRule(port: 443, protocolType: .tcp, action: .drop),
            ]
        ))
        var engine = fixture.engine
        let syn = TopologyIPv4Packet(
            identity: 181,
            senderIPAddress: "203.0.113.10",
            receiverIPAddress: "10.0.0.1",
            timeToLive: 64,
            protocolNumber: .tcp,
            payload: .tcp(TopologyTCPSegment(
                sourcePort: 50_000,
                destinationPort: 443,
                sequenceNumber: 1,
                acknowledgementNumber: 0,
                flags: [.synchronize],
                payload: Data()
            ))
        )
        let established = TopologyIPv4Packet(
            identity: 182,
            senderIPAddress: "203.0.113.10",
            receiverIPAddress: "10.0.0.1",
            timeToLive: 64,
            protocolNumber: .tcp,
            payload: .tcp(TopologyTCPSegment(
                sourcePort: 50_000,
                destinationPort: 22,
                sequenceNumber: 2,
                acknowledgementNumber: 2,
                flags: [.acknowledgement],
                payload: Data()
            ))
        )

        let synDecision = engine.evaluateFirewall(packet: syn, atNodeID: fixture.routerID)
        XCTAssertTrue(synDecision.accepted)
        XCTAssertEqual(synDecision.ruleIndex, 0)
        XCTAssertTrue(engine.evaluateFirewall(packet: established, atNodeID: fixture.routerID).accepted)
    }

    func testFirewallUDPReverseResponseUsesExplicitSourcePortAndDirectNetworkMarker() {
        let fixture = firewallEngine(configuration: TopologyFirewallConfiguration(
            isActive: true,
            defaultPolicy: .drop,
            rules: [
                TopologyFirewallRule(
                    sourceIPAddress: TopologyFirewallRule.directlyConnectedSourceMarker,
                    destinationIPAddress: "8.8.8.8",
                    destinationSubnetMask: "255.255.255.255",
                    port: 53,
                    protocolType: .udp,
                    action: .accept
                ),
            ]
        ))
        var engine = fixture.engine
        let request = TopologyIPv4Packet(
            identity: 183,
            senderIPAddress: "10.0.0.20",
            receiverIPAddress: "8.8.8.8",
            timeToLive: 64,
            protocolNumber: .udp,
            payload: .udp(TopologyUDPDatagram(sourcePort: 50_001, destinationPort: 53, payload: Data()))
        )
        let response = TopologyIPv4Packet(
            identity: 184,
            senderIPAddress: "8.8.8.8",
            receiverIPAddress: "10.0.0.20",
            timeToLive: 64,
            protocolNumber: .udp,
            payload: .udp(TopologyUDPDatagram(sourcePort: 53, destinationPort: 50_001, payload: Data()))
        )

        XCTAssertTrue(engine.evaluateFirewall(packet: request, atNodeID: fixture.routerID).accepted)
        XCTAssertTrue(engine.evaluateFirewall(packet: response, atNodeID: fixture.routerID).accepted)
    }

    func testPacketViewerGroupsForwardingClonesAndPreservesRepeatedLayerPathSteps() throws {
        let routerID = UUID(uuidString: "00000000-0000-0000-0000-000000002101")!
        let gatewayID = UUID(uuidString: "00000000-0000-0000-0000-000000002102")!
        let routerPortID = UUID(uuidString: "00000000-0000-0000-0000-000000002111")!
        let gatewayPortID = UUID(uuidString: "00000000-0000-0000-0000-000000002112")!
        let snapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: [
                TopologyNetworkRuntimeNodeSnapshot(
                    id: routerID,
                    kind: .router,
                    ports: [TopologyNetworkRuntimePortSnapshot(id: routerPortID, label: "rt1")]
                ),
                TopologyNetworkRuntimeNodeSnapshot(
                    id: gatewayID,
                    kind: .gateway,
                    ports: [TopologyNetworkRuntimePortSnapshot(id: gatewayPortID, label: "wan0")]
                ),
            ],
            links: [],
            deviceConfigurations: [:],
            interfaceConfigurations: [
                TopologyRuntimeInterfaceKey(nodeID: routerID, portID: routerPortID):
                    TopologyRuntimeInterfaceConfiguration(ipAddress: "10.0.0.1", subnetMask: "255.255.255.0"),
                TopologyRuntimeInterfaceKey(nodeID: gatewayID, portID: gatewayPortID):
                    TopologyRuntimeInterfaceConfiguration(ipAddress: "10.0.0.2", subnetMask: "255.255.255.0"),
            ],
            manualRoutesByNodeID: [:]
        )
        var engine = TopologyNetworkRuntimeEngine(seed: 21)
        engine.handle(.start(snapshot: snapshot, seed: 21, initialTimeMilliseconds: 0))
        let originalHeaders = [
            TopologyPacketHeaderField(name: "senderIP", value: "10.0.0.10"),
            TopologyPacketHeaderField(name: "receiverIP", value: "203.0.113.8"),
            TopologyPacketHeaderField(name: "ttl", value: "64"),
            TopologyPacketHeaderField(name: "protocol", value: "6"),
        ]
        let rewrittenHeaders = [
            TopologyPacketHeaderField(name: "senderIP", value: "198.51.100.1"),
            TopologyPacketHeaderField(name: "receiverIP", value: "203.0.113.8"),
            TopologyPacketHeaderField(name: "ttl", value: "63"),
            TopologyPacketHeaderField(name: "protocol", value: "6"),
        ]
        engine.recordTrace(
            frameIdentity: 31,
            packetIdentity: 77,
            nodeID: routerID,
            interfaceID: routerPortID,
            direction: .outbound,
            layer: .network,
            operation: .forwarded,
            afterHeaders: originalHeaders
        )
        engine.recordTrace(
            frameIdentity: 32,
            packetIdentity: 77,
            nodeID: gatewayID,
            interfaceID: gatewayPortID,
            direction: .inbound,
            layer: .network,
            operation: .rewritten,
            beforeHeaders: originalHeaders,
            afterHeaders: rewrittenHeaders,
            detail: "NAT LAN to WAN"
        )
        engine.recordTrace(
            frameIdentity: 32,
            packetIdentity: 77,
            nodeID: gatewayID,
            interfaceID: gatewayPortID,
            direction: .inbound,
            layer: .network,
            operation: .dropped,
            afterHeaders: rewrittenHeaders,
            detail: "Firewall default DROP"
        )

        let globalPath = engine.packetLayerPath(identity: .packet(77))
        XCTAssertEqual(globalPath.steps.map(\.nodeID), [routerID, gatewayID, gatewayID])
        XCTAssertEqual(globalPath.steps.map(\.ordinal), [1, 2, 3])
        XCTAssertEqual(globalPath.steps[1].beforeHeaders, originalHeaders)
        XCTAssertEqual(globalPath.steps[1].afterHeaders, rewrittenHeaders)
        XCTAssertEqual(globalPath.steps.last?.operation, .dropped)

        let localPath = engine.packetLayerPath(identity: .packet(77), localNodeID: gatewayID)
        XCTAssertEqual(localPath.steps.count, 2)
        XCTAssertEqual(localPath.steps.map(\.operation), [.rewritten, .dropped])
    }

    func testPacketViewerBuildsJavaInterfaceTabsAndMessageColumns() throws {
        let routerID = UUID(uuidString: "00000000-0000-0000-0000-000000002201")!
        let firstPortID = UUID(uuidString: "00000000-0000-0000-0000-000000002211")!
        let secondPortID = UUID(uuidString: "00000000-0000-0000-0000-000000002212")!
        let snapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: [TopologyNetworkRuntimeNodeSnapshot(
                id: routerID,
                kind: .router,
                ports: [
                    TopologyNetworkRuntimePortSnapshot(id: firstPortID, label: "rt1"),
                    TopologyNetworkRuntimePortSnapshot(id: secondPortID, label: "rt2"),
                ]
            )],
            links: [],
            deviceConfigurations: [:],
            interfaceConfigurations: [
                TopologyRuntimeInterfaceKey(nodeID: routerID, portID: firstPortID):
                    TopologyRuntimeInterfaceConfiguration(ipAddress: "10.1.0.1", subnetMask: "255.255.255.0"),
                TopologyRuntimeInterfaceKey(nodeID: routerID, portID: secondPortID):
                    TopologyRuntimeInterfaceConfiguration(ipAddress: "10.2.0.1", subnetMask: "255.255.255.0"),
            ],
            manualRoutesByNodeID: [:]
        )
        var engine = TopologyNetworkRuntimeEngine(seed: 22)
        engine.handle(.start(snapshot: snapshot, seed: 22, initialTimeMilliseconds: 0))
        engine.recordTrace(
            frameIdentity: 1,
            packetIdentity: 2,
            nodeID: routerID,
            interfaceID: secondPortID,
            direction: .outbound,
            layer: .network,
            operation: .sent,
            afterHeaders: [
                TopologyPacketHeaderField(name: "senderIP", value: "10.2.0.1"),
                TopologyPacketHeaderField(name: "receiverIP", value: "10.2.0.9"),
                TopologyPacketHeaderField(name: "protocol", value: "17"),
            ],
            detail: "RIP advertisement"
        )

        let tabs = engine.packetCaptureTabs(nodeID: routerID)
        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(tabs[0].interfaceID, secondPortID)
        XCTAssertEqual(tabs[0].title, "Vermittlungsrechner - 10.2.0.1")
        XCTAssertEqual(tabs[0].eventCount, 1)

        let rows = engine.packetMessageRows(nodeID: routerID, interfaceID: secondPortID)
        XCTAssertEqual(rows.map(\.number), [1])
        XCTAssertEqual(rows[0].source, "10.2.0.1")
        XCTAssertEqual(rows[0].destination, "10.2.0.9")
        XCTAssertEqual(rows[0].protocolName, "UDP")
        XCTAssertEqual(rows[0].layerName, "Vermittlung")
        XCTAssertEqual(rows[0].detail, "RIP advertisement")
        XCTAssertEqual(rows[0].exchangeIdentity, .packet(2))
    }

    func testPacketCaptureResetCanClearOneInterfaceOrAllWithoutRenumberingRuntimeIdentities() {
        let nodeID = UUID(uuidString: "00000000-0000-0000-0000-000000002301")!
        let firstPortID = UUID(uuidString: "00000000-0000-0000-0000-000000002311")!
        let secondPortID = UUID(uuidString: "00000000-0000-0000-0000-000000002312")!
        var engine = TopologyNetworkRuntimeEngine(seed: 23)
        engine.handle(.start(snapshot: .empty, seed: 23, initialTimeMilliseconds: 0))
        engine.recordTrace(nodeID: nodeID, interfaceID: firstPortID, direction: .inbound, layer: .dataLink, operation: .received)
        engine.recordTrace(nodeID: nodeID, interfaceID: secondPortID, direction: .outbound, layer: .network, operation: .sent)

        engine.clearPacketCapture(nodeID: nodeID, interfaceID: firstPortID)
        XCTAssertEqual(engine.state.packetTraces.map(\.interfaceID), [secondPortID])
        XCTAssertEqual(engine.allocatePacketIdentity(), 1)

        engine.clearPacketCapture()
        XCTAssertTrue(engine.state.packetTraces.isEmpty)
        XCTAssertEqual(engine.allocatePacketIdentity(), 2)
    }

    func testIntegratedGatewayOrderDropsBeforeNATChecksRouteBeforeMappingAndAcceptsBeforeRewrite() throws {
        var dropped = gatewayNATTopology(firewallConfiguration: TopologyFirewallConfiguration(
            isActive: true,
            defaultPolicy: .drop,
            filterUDP: true
        ))
        let droppedRemoteSocketID = try XCTUnwrap(dropped.engine.bindUDPSocket(
            nodeID: dropped.remoteNodeID,
            localPort: 53,
            localIPAddress: "203.0.113.2"
        ))
        let droppedClientSocketID = try XCTUnwrap(dropped.engine.bindUDPSocket(
            nodeID: dropped.clientNodeID,
            localPort: 40_100,
            localIPAddress: "192.168.0.2",
            remoteIPAddress: "203.0.113.2",
            remotePort: 53
        ))
        _ = dropped.engine.sendUDP(socketID: droppedClientSocketID, payload: Data("blocked".utf8))
        XCTAssertNil(dropped.engine.receiveUDP(socketID: droppedRemoteSocketID))
        XCTAssertTrue(dropped.engine.natMappings(gatewayNodeID: dropped.gatewayNodeID).isEmpty)
        XCTAssertTrue(dropped.engine.state.packetTraces.contains {
            $0.nodeID == dropped.gatewayNodeID && $0.operation == .dropped
        })
        XCTAssertFalse(dropped.engine.state.packetTraces.contains {
            $0.nodeID == dropped.gatewayNodeID && $0.detail == "NAT/PAT LAN to WAN"
        })

        var routeFailure = gatewayNATTopology(firewallConfiguration: TopologyFirewallConfiguration(
            isActive: true,
            defaultPolicy: .accept,
            filterUDP: true
        ))
        let unroutableSocketID = try XCTUnwrap(routeFailure.engine.bindUDPSocket(
            nodeID: routeFailure.clientNodeID,
            localPort: 40_101,
            localIPAddress: "192.168.0.2",
            remoteIPAddress: "198.51.100.20",
            remotePort: 53
        ))
        _ = routeFailure.engine.sendUDP(socketID: unroutableSocketID, payload: Data("no-route".utf8))
        XCTAssertTrue(routeFailure.engine.natMappings(gatewayNodeID: routeFailure.gatewayNodeID).isEmpty)
        XCTAssertEqual(
            routeFailure.engine.state.icmpObservationsByNodeID[routeFailure.clientNodeID]?.last?.message.kind,
            .destinationNetworkUnreachable
        )

        var accepted = gatewayNATTopology(firewallConfiguration: TopologyFirewallConfiguration(
            isActive: true,
            defaultPolicy: .drop,
            filterUDP: true,
            rules: [TopologyFirewallRule(port: 53, protocolType: .udp, action: .accept)]
        ))
        let acceptedRemoteSocketID = try XCTUnwrap(accepted.engine.bindUDPSocket(
            nodeID: accepted.remoteNodeID,
            localPort: 53,
            localIPAddress: "203.0.113.2"
        ))
        let acceptedClientSocketID = try XCTUnwrap(accepted.engine.bindUDPSocket(
            nodeID: accepted.clientNodeID,
            localPort: 40_102,
            localIPAddress: "192.168.0.2",
            remoteIPAddress: "203.0.113.2",
            remotePort: 53
        ))
        _ = accepted.engine.sendUDP(socketID: acceptedClientSocketID, payload: Data("allowed".utf8))
        XCTAssertNotNil(accepted.engine.receiveUDP(socketID: acceptedRemoteSocketID))
        XCTAssertEqual(accepted.engine.natMappings(gatewayNodeID: accepted.gatewayNodeID).count, 1)
        let rewrite = try XCTUnwrap(accepted.engine.state.packetTraces.first {
            $0.nodeID == accepted.gatewayNodeID && $0.detail == "NAT/PAT LAN to WAN"
        })
        let firewallAccept = try XCTUnwrap(accepted.engine.state.packetTraces.first {
            $0.nodeID == accepted.gatewayNodeID
                && $0.packetIdentity == rewrite.packetIdentity
                && $0.operation == .accepted
        })
        XCTAssertLessThan(firewallAccept.id, rewrite.id)
        let path = accepted.engine.packetLayerPath(identity: .packet(try XCTUnwrap(rewrite.packetIdentity)))
        XCTAssertTrue(path.steps.contains { $0.operation == .accepted })
        XCTAssertTrue(path.steps.contains { $0.operation == .rewritten })
    }

    func testIntegratedCompetingDHCPServersSelectOneAndBlacklistTheOtherOffer() throws {
        let serverAID = uuid("00000000-0000-0000-0000-000000002501")
        let serverAPortID = uuid("00000000-0000-0000-0000-000000002511")
        let serverBID = uuid("00000000-0000-0000-0000-000000002502")
        let serverBPortID = uuid("00000000-0000-0000-0000-000000002512")
        let clientID = uuid("00000000-0000-0000-0000-000000002503")
        let clientPortID = uuid("00000000-0000-0000-0000-000000002513")
        let switchID = uuid("00000000-0000-0000-0000-000000002504")
        let switchPorts = (1...3).map { index in
            TopologyNetworkRuntimePortSnapshot(
                id: uuid(String(format: "00000000-0000-0000-0000-%012d", 25_520 + index)),
                label: "sw\(index)"
            )
        }
        let networkSwitch = TopologyNetworkRuntimeNodeSnapshot(id: switchID, kind: .networkSwitch, ports: switchPorts)
        let snapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: [pc(serverAID, serverAPortID), pc(serverBID, serverBPortID), pc(clientID, clientPortID), networkSwitch],
            links: [
                link(serverAID, serverAPortID, switchID, switchPorts[0].id),
                link(serverBID, serverBPortID, switchID, switchPorts[1].id),
                link(clientID, clientPortID, switchID, switchPorts[2].id),
            ],
            deviceConfigurations: [
                serverAID: device("10.55.0.1"),
                serverBID: device("10.55.0.2"),
                clientID: device("0.0.0.0", mask: "0.0.0.0"),
            ],
            interfaceConfigurations: [:],
            manualRoutesByNodeID: [:],
            dhcpClientConfigurationsByNodeID: [clientID: TopologyDHCPClientConfiguration(isEnabled: true)],
            dhcpServerConfigurationsByNodeID: [
                serverAID: TopologyDHCPServerConfiguration(
                    isActive: true,
                    lowerBoundIPAddress: "10.55.0.20",
                    upperBoundIPAddress: "10.55.0.20",
                    gatewayIPAddress: "10.55.0.1",
                    dnsServerIPAddress: "10.55.0.53",
                    useOwnSettings: true
                ),
                serverBID: TopologyDHCPServerConfiguration(
                    isActive: true,
                    lowerBoundIPAddress: "10.55.0.30",
                    upperBoundIPAddress: "10.55.0.30",
                    gatewayIPAddress: "10.55.0.2",
                    dnsServerIPAddress: "10.55.0.54",
                    useOwnSettings: true
                ),
            ]
        )
        var engine = TopologyNetworkRuntimeEngine(seed: 22)
        engine.handle(.start(snapshot: snapshot, seed: 22, initialTimeMilliseconds: 0))
        engine.handle(.advance(toMilliseconds: 1_000))

        XCTAssertEqual(engine.state.dhcpClientStatusesByNodeID[clientID]?.state, .finish)
        XCTAssertEqual(engine.state.dhcpClientStatusesByNodeID[clientID]?.succeeded, true)
        let lease = try XCTUnwrap(engine.state.dhcpLeasesByIPAddress.values.first)
        XCTAssertEqual(engine.state.topologySnapshot.deviceConfigurations[clientID]?.ipAddress, lease.ipAddress)
        let competingServerID = lease.serverNodeID == serverAID ? serverBID : serverAID
        XCTAssertNotNil(engine.state.dhcpBlacklistByServerNodeID[competingServerID]?[lease.ipAddress.lowercased()])
        XCTAssertGreaterThanOrEqual(
            engine.state.packetTraces.filter { $0.detail == "DHCPOFFER" }.count,
            2
        )
    }

    func testIntegratedRIPConvergenceIsVisibleInViewerAndRestartClearsOnlyLearnedState() {
        var fixture = ripTopology()
        fixture.engine.handle(.advance(toMilliseconds: 2_000))
        let snapshot = fixture.engine.state.topologySnapshot
        XCTAssertEqual(
            fixture.engine.state.ripTablesByNodeID[fixture.routerAID]?
                .first(where: { $0.destinationNetwork == "172.16.0.0" })?.metric,
            1
        )
        XCTAssertFalse(fixture.engine.packetCaptureTabs(nodeID: fixture.routerAID).isEmpty)
        XCTAssertTrue(fixture.engine.packetMessageRows(nodeID: fixture.routerAID).contains {
            $0.protocolName == "UDP"
                && $0.trace.operation == .accepted
                && $0.detail.hasPrefix("RIP advertisement")
        })

        fixture.engine.handle(.stop)
        fixture.engine.handle(.start(snapshot: snapshot, seed: 15, initialTimeMilliseconds: 0))

        XCTAssertNil(
            fixture.engine.state.ripTablesByNodeID[fixture.routerAID]?
                .first(where: { $0.destinationNetwork == "172.16.0.0" })
        )
        XCTAssertTrue(fixture.engine.state.packetTraces.isEmpty)
        XCTAssertTrue(fixture.engine.state.pendingEvents.contains {
            $0.deadlineMilliseconds == 1_000 && $0.kind == .ripBeacon(nodeID: fixture.routerAID)
        })
    }

    private struct GatewayNATFixture {
        var engine: TopologyNetworkRuntimeEngine
        let clientNodeID: UUID
        let gatewayNodeID: UUID
        let remoteNodeID: UUID
    }

    private func gatewayNATTopology(
        firewallConfiguration: TopologyFirewallConfiguration = TopologyFirewallConfiguration(),
        portForwardingRows: [TopologyGatewayPortForwardingRow] = []
    ) -> GatewayNATFixture {
        let clientNodeID = uuid("00000000-0000-0000-0000-000000001901")
        let clientPortID = uuid("00000000-0000-0000-0000-000000001911")
        let gatewayNodeID = uuid("00000000-0000-0000-0000-000000001902")
        let gatewayWANPortID = uuid("00000000-0000-0000-0000-000000001912")
        let gatewayLANPortID = uuid("00000000-0000-0000-0000-000000001913")
        let remoteNodeID = uuid("00000000-0000-0000-0000-000000001903")
        let remotePortID = uuid("00000000-0000-0000-0000-000000001914")
        let gateway = TopologyNetworkRuntimeNodeSnapshot(
            id: gatewayNodeID,
            kind: .gateway,
            ports: [
                TopologyNetworkRuntimePortSnapshot(id: gatewayWANPortID, label: "wan0"),
                TopologyNetworkRuntimePortSnapshot(id: gatewayLANPortID, label: "lan0"),
            ]
        )
        let snapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: [pc(clientNodeID, clientPortID), gateway, pc(remoteNodeID, remotePortID)],
            links: [
                link(clientNodeID, clientPortID, gatewayNodeID, gatewayLANPortID),
                link(gatewayNodeID, gatewayWANPortID, remoteNodeID, remotePortID),
            ],
            deviceConfigurations: [
                clientNodeID: device("192.168.0.2", gateway: "192.168.0.1"),
                gatewayNodeID: device("192.168.0.1"),
                remoteNodeID: device("203.0.113.2", gateway: "203.0.113.1"),
            ],
            interfaceConfigurations: [
                TopologyRuntimeInterfaceKey(nodeID: gatewayNodeID, portID: gatewayWANPortID):
                    TopologyRuntimeInterfaceConfiguration(ipAddress: "203.0.113.1", subnetMask: "255.255.255.0"),
                TopologyRuntimeInterfaceKey(nodeID: gatewayNodeID, portID: gatewayLANPortID):
                    TopologyRuntimeInterfaceConfiguration(ipAddress: "192.168.0.1", subnetMask: "255.255.255.0"),
            ],
            manualRoutesByNodeID: [:],
            firewallConfigurationsByNodeID: [gatewayNodeID: firewallConfiguration],
            portForwardingRowsByNodeID: [gatewayNodeID: portForwardingRows]
        )
        var engine = TopologyNetworkRuntimeEngine(seed: 19)
        engine.handle(.start(snapshot: snapshot, seed: 19, initialTimeMilliseconds: 0))
        return GatewayNATFixture(
            engine: engine,
            clientNodeID: clientNodeID,
            gatewayNodeID: gatewayNodeID,
            remoteNodeID: remoteNodeID
        )
    }
    private func firewallEngine(
        configuration: TopologyFirewallConfiguration
    ) -> (engine: TopologyNetworkRuntimeEngine, routerID: UUID) {
        let routerID = uuid("00000000-0000-0000-0000-000000001802")
        let portID = uuid("00000000-0000-0000-0000-000000001812")
        let router = TopologyNetworkRuntimeNodeSnapshot(
            id: routerID,
            kind: .router,
            ports: [TopologyNetworkRuntimePortSnapshot(id: portID, label: "rt1")]
        )
        let snapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: [router],
            links: [],
            deviceConfigurations: [:],
            interfaceConfigurations: [
                TopologyRuntimeInterfaceKey(nodeID: routerID, portID: portID):
                    TopologyRuntimeInterfaceConfiguration(ipAddress: "10.0.0.1", subnetMask: "255.255.255.0"),
            ],
            manualRoutesByNodeID: [:],
            firewallConfigurationsByNodeID: [routerID: configuration]
        )
        var engine = TopologyNetworkRuntimeEngine(seed: 18)
        engine.handle(.start(snapshot: snapshot, seed: 18, initialTimeMilliseconds: 0))
        return (engine, routerID)
    }

    private struct RIPFixture {
        var engine: TopologyNetworkRuntimeEngine
        let routerAID: UUID
        let routerBID: UUID
    }

    private func ripTopology() -> RIPFixture {
        let routerAID = uuid("00000000-0000-0000-0000-000000001501")
        let routerAShared = uuid("00000000-0000-0000-0000-000000001511")
        let routerALAN = uuid("00000000-0000-0000-0000-000000001512")
        let routerBID = uuid("00000000-0000-0000-0000-000000001502")
        let routerBShared = uuid("00000000-0000-0000-0000-000000001513")
        let routerBLAN = uuid("00000000-0000-0000-0000-000000001514")
        let routerA = TopologyNetworkRuntimeNodeSnapshot(
            id: routerAID,
            kind: .router,
            ports: [
                TopologyNetworkRuntimePortSnapshot(id: routerAShared, label: "rt1"),
                TopologyNetworkRuntimePortSnapshot(id: routerALAN, label: "rt2"),
            ]
        )
        let routerB = TopologyNetworkRuntimeNodeSnapshot(
            id: routerBID,
            kind: .router,
            ports: [
                TopologyNetworkRuntimePortSnapshot(id: routerBShared, label: "rt1"),
                TopologyNetworkRuntimePortSnapshot(id: routerBLAN, label: "rt2"),
            ]
        )
        let snapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: [routerA, routerB],
            links: [link(routerAID, routerAShared, routerBID, routerBShared)],
            deviceConfigurations: [:],
            interfaceConfigurations: [
                TopologyRuntimeInterfaceKey(nodeID: routerAID, portID: routerAShared):
                    TopologyRuntimeInterfaceConfiguration(ipAddress: "10.0.0.1", subnetMask: "255.255.255.0"),
                TopologyRuntimeInterfaceKey(nodeID: routerAID, portID: routerALAN):
                    TopologyRuntimeInterfaceConfiguration(ipAddress: "192.168.0.1", subnetMask: "255.255.255.0"),
                TopologyRuntimeInterfaceKey(nodeID: routerBID, portID: routerBShared):
                    TopologyRuntimeInterfaceConfiguration(ipAddress: "10.0.0.2", subnetMask: "255.255.255.0"),
                TopologyRuntimeInterfaceKey(nodeID: routerBID, portID: routerBLAN):
                    TopologyRuntimeInterfaceConfiguration(ipAddress: "172.16.0.1", subnetMask: "255.255.0.0"),
            ],
            manualRoutesByNodeID: [:],
            ripEnabledByNodeID: [routerAID: true, routerBID: true]
        )
        var engine = TopologyNetworkRuntimeEngine(seed: 15)
        engine.handle(.start(snapshot: snapshot, seed: 15, initialTimeMilliseconds: 0))
        return RIPFixture(engine: engine, routerAID: routerAID, routerBID: routerBID)
    }
    func testSwitchLearnsFloodsForwardsFiltersAndAgesSAT() {
        let hostAID = uuid("00000000-0000-0000-0000-000000001A01")
        let hostAPortID = uuid("00000000-0000-0000-0000-000000001A11")
        let hostBID = uuid("00000000-0000-0000-0000-000000001A02")
        let hostBPortID = uuid("00000000-0000-0000-0000-000000001A12")
        let hostCID = uuid("00000000-0000-0000-0000-000000001A03")
        let hostCPortID = uuid("00000000-0000-0000-0000-000000001A13")
        let switchID = uuid("00000000-0000-0000-0000-000000001A04")
        let switchPorts = (1...3).map { index in
            TopologyNetworkRuntimePortSnapshot(
                id: uuid(String(format: "00000000-0000-0000-0000-%012X", 0x1A20 + index)),
                label: "sw\(index)"
            )
        }
        let networkSwitch = TopologyNetworkRuntimeNodeSnapshot(id: switchID, kind: .networkSwitch, ports: switchPorts)
        let snapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: [pc(hostAID, hostAPortID), pc(hostBID, hostBPortID), pc(hostCID, hostCPortID), networkSwitch],
            links: [
                link(hostAID, hostAPortID, switchID, switchPorts[0].id),
                link(hostBID, hostBPortID, switchID, switchPorts[1].id),
                link(hostCID, hostCPortID, switchID, switchPorts[2].id),
            ],
            deviceConfigurations: [:],
            interfaceConfigurations: [:],
            manualRoutesByNodeID: [:],
            switchConfigurationsByNodeID: [
                switchID: TopologySwitchConfiguration(ssid: "Classroom", retentionTimeMilliseconds: 1_000),
            ]
        )
        var engine = TopologyNetworkRuntimeEngine(seed: 20)
        engine.handle(.start(snapshot: snapshot, seed: 20, initialTimeMilliseconds: 0))
        let macA = TopologyNetworkRuntimeEngine.stableMACAddress(for: hostAPortID)
        let macB = TopologyNetworkRuntimeEngine.stableMACAddress(for: hostBPortID)
        let payload = TopologyEthernetPayload.arp(TopologyARPPacket(
            operation: .request,
            senderMACAddress: macA,
            senderIPAddress: "192.0.2.1",
            targetMACAddress: TopologyNetworkRuntimeEngine.unspecifiedMACAddress,
            targetIPAddress: "192.0.2.200"
        ))

        let unknownFrameID = engine.allocateFrameIdentity()
        engine.sendEthernetFrame(
            fromNodeID: hostAID,
            outgoingPortID: hostAPortID,
            frame: TopologyEthernetFrame(
                identity: unknownFrameID,
                sourceMACAddress: macA,
                destinationMACAddress: "02:00:00:00:00:FE",
                payload: payload
            )
        )
        XCTAssertEqual(
            engine.state.packetTraces.filter { $0.nodeID == switchID && $0.detail == "switch unknown unicast flooding" }.count,
            2
        )

        let learnedFrameID = engine.allocateFrameIdentity()
        engine.sendEthernetFrame(
            fromNodeID: hostBID,
            outgoingPortID: hostBPortID,
            frame: TopologyEthernetFrame(
                identity: learnedFrameID,
                sourceMACAddress: macB,
                destinationMACAddress: macA,
                payload: payload
            )
        )
        XCTAssertEqual(
            engine.state.packetTraces.filter { $0.nodeID == switchID && $0.detail == "switch learned unicast forwarding" }.count,
            1
        )

        let filteredFrameID = engine.allocateFrameIdentity()
        engine.sendEthernetFrame(
            fromNodeID: hostAID,
            outgoingPortID: hostAPortID,
            frame: TopologyEthernetFrame(
                identity: filteredFrameID,
                sourceMACAddress: macA,
                destinationMACAddress: macA,
                payload: payload
            )
        )
        XCTAssertTrue(engine.state.packetTraces.contains {
            $0.nodeID == switchID && $0.detail == "switch filtered destination on incoming port"
        })
        XCTAssertEqual(engine.switchSATEntries(nodeID: switchID).count, 2)

        let retention = UInt64(1_000)
        let updateTimes = try! XCTUnwrap(
            engine.state.switchForwardingUpdatedAtMillisecondsByNodeID[switchID]
        ).values
        let expirationDeadlines = updateTimes.map { $0 + retention }
        let firstExpiration = try! XCTUnwrap(expirationDeadlines.min())
        let lastExpiration = try! XCTUnwrap(expirationDeadlines.max())

        engine.handle(.advance(toMilliseconds: firstExpiration - 1))
        XCTAssertEqual(engine.switchSATEntries(nodeID: switchID).count, 2)
        engine.handle(.advance(toMilliseconds: lastExpiration))
        XCTAssertTrue(engine.switchSATEntries(nodeID: switchID).isEmpty)
    }

    func testWirelessSSIDAssociationUsesAvailableSwitchPort() {
        var state = TopologyEditorState()
        let wirelessHost = TopologyNode(
            id: uuid("00000000-0000-0000-0000-000000001B01"),
            kind: .pc,
            position: .zero
        )
        let wiredHost = TopologyNode(
            id: uuid("00000000-0000-0000-0000-000000001B02"),
            kind: .pc,
            position: .zero
        )
        let networkSwitch = TopologyNode(
            id: uuid("00000000-0000-0000-0000-000000001B03"),
            kind: .networkSwitch,
            position: .zero
        )
        state.graph = TopologyGraph(
            nodes: [wirelessHost, wiredHost, networkSwitch],
            links: [TopologyLink(
                sourceNodeID: wiredHost.id,
                sourcePortID: wiredHost.ports[0].id,
                targetNodeID: networkSwitch.id,
                targetPortID: networkSwitch.ports[0].id
            )]
        )
        state.runtimeDeviceConfigurations = [
            wirelessHost.id: device("192.168.7.10"),
            wiredHost.id: device("192.168.7.20"),
        ]
        state.switchConfigurationsByNodeID[networkSwitch.id] = TopologySwitchConfiguration(ssid: "Classroom")
        state.hostWirelessConfigurationsByNodeID[wirelessHost.id] = TopologyHostWirelessConfiguration(
            isEnabled: true, ssid: "Classroom"
        )

        let snapshot = TopologyNetworkRuntimeTopologySnapshot(editorState: state)
        XCTAssertEqual(snapshot.links.count, 2)
        XCTAssertTrue(snapshot.links.contains {
            $0.sourceNodeID == wirelessHost.id && $0.targetNodeID == networkSwitch.id
        })
        var engine = TopologyNetworkRuntimeEngine(seed: 21)
        engine.handle(.start(snapshot: snapshot, seed: 21, initialTimeMilliseconds: 0))
        let result = engine.sendICMPEcho(fromNodeID: wirelessHost.id, targetIPAddress: "192.168.7.20")
        guard case .delivered = result else { return XCTFail("expected wireless echo delivery, got \(result)") }
        XCTAssertEqual(engine.state.icmpObservationsByNodeID[wirelessHost.id]?.last?.message.kind, .echoReply)
    }

    private func startedEngine(
        nodes: [TopologyNetworkRuntimeNodeSnapshot],
        links: [TopologyNetworkRuntimeLinkSnapshot],
        devices: [UUID: TopologyRuntimeDeviceConfiguration]
    ) -> TopologyNetworkRuntimeEngine {
        let snapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: nodes,
            links: links,
            deviceConfigurations: devices,
            interfaceConfigurations: [:],
            manualRoutesByNodeID: [:]
        )
        var engine = TopologyNetworkRuntimeEngine(seed: 14)
        engine.handle(.start(snapshot: snapshot, seed: 14, initialTimeMilliseconds: 0))
        return engine
    }

    private func pc(_ nodeID: UUID, _ portID: UUID) -> TopologyNetworkRuntimeNodeSnapshot {
        TopologyNetworkRuntimeNodeSnapshot(
            id: nodeID,
            kind: .pc,
            ports: [TopologyNetworkRuntimePortSnapshot(id: portID, label: "eth0")]
        )
    }

    private func link(
        _ sourceNodeID: UUID,
        _ sourcePortID: UUID,
        _ targetNodeID: UUID,
        _ targetPortID: UUID
    ) -> TopologyNetworkRuntimeLinkSnapshot {
        TopologyNetworkRuntimeLinkSnapshot(
            id: UUID(),
            sourceNodeID: sourceNodeID,
            sourcePortID: sourcePortID,
            targetNodeID: targetNodeID,
            targetPortID: targetPortID
        )
    }

    private func device(
        _ ipAddress: String,
        mask: String = "255.255.255.0",
        gateway: String = ""
    ) -> TopologyRuntimeDeviceConfiguration {
        TopologyRuntimeDeviceConfiguration(ipAddress: ipAddress, subnetMask: mask, defaultGateway: gateway)
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}
