import CoreGraphics
import Darwin
import Network
import XCTest
@testable import FiliusPad

final class TopologyNetworkRuntimeEngineTests: XCTestCase {
    func testLANRemoteLinkWireCodecRoundTripsUDPFrame() throws {
        let frame = TopologyEthernetFrame(
            identity: 41,
            sourceMACAddress: "AA:BB:CC:DD:EE:01",
            destinationMACAddress: "AA:BB:CC:DD:EE:02",
            payload: .ipv4(TopologyIPv4Packet(
                identity: 42,
                senderIPAddress: "10.0.0.1",
                receiverIPAddress: "10.0.0.2",
                timeToLive: 63,
                protocolNumber: .udp,
                payload: .udp(TopologyUDPDatagram(
                    sourcePort: 1234,
                    destinationPort: 4321,
                    payload: Data("hello".utf8)
                ))
            ))
        )
        let wireFrame = TopologyRemoteLinkWireFrame(frame: frame)
        let codec = TopologyRemoteLinkWireCodec(linkCode: "classroom-link-code")
        let (local, remote) = lanRemoteLinkHandshakes(linkCode: "classroom-link-code")
        var sender = try codec.makeSessionCodec(localHandshake: local, remoteHandshake: remote)
        var receiver = try codec.makeSessionCodec(localHandshake: remote, remoteHandshake: local)

        let encoded = try sender.encode(.frame(wireFrame))
        let decoded = try receiver.decode(encoded.record)

        XCTAssertEqual(decoded.message, .frame(wireFrame))
        XCTAssertLessThan(encoded.record.count, TopologyRemoteLinkWireCodec.maximumRecordBytes)
    }

    func testLANRemoteLinkWireCodecRoundTripsEverySupportedEthernetPayload() throws {
        let embeddedPacket = TopologyIPv4Packet(
            identity: 30,
            senderIPAddress: "10.0.0.1",
            receiverIPAddress: "10.0.0.2",
            timeToLive: 1,
            protocolNumber: .udp,
            payload: .udp(TopologyUDPDatagram(sourcePort: 53, destinationPort: 54, payload: Data("dns".utf8)))
        )
        let frames = [
            TopologyEthernetFrame(
                identity: 10,
                sourceMACAddress: "AA:BB:CC:DD:EE:01",
                destinationMACAddress: TopologyNetworkRuntimeEngine.ethernetBroadcastMACAddress,
                payload: .arp(TopologyARPPacket(
                    operation: .request,
                    senderMACAddress: "AA:BB:CC:DD:EE:01",
                    senderIPAddress: "10.0.0.1",
                    targetMACAddress: TopologyNetworkRuntimeEngine.unspecifiedMACAddress,
                    targetIPAddress: "10.0.0.2"
                ))
            ),
            TopologyEthernetFrame(
                identity: 20,
                sourceMACAddress: "AA:BB:CC:DD:EE:01",
                destinationMACAddress: "AA:BB:CC:DD:EE:02",
                payload: .ipv4(TopologyIPv4Packet(
                    identity: 21,
                    senderIPAddress: "10.0.0.1",
                    receiverIPAddress: "10.0.0.2",
                    timeToLive: 63,
                    protocolNumber: .icmp,
                    payload: .icmp(TopologyICMPMessage(
                        kind: .timeExceeded,
                        identifier: 7,
                        sequenceNumber: 8,
                        data: Data("icmp".utf8),
                        embeddedOriginalPacket: embeddedPacket
                    ))
                ))
            ),
            TopologyEthernetFrame(
                identity: 40,
                sourceMACAddress: "AA:BB:CC:DD:EE:01",
                destinationMACAddress: "AA:BB:CC:DD:EE:02",
                payload: .ipv4(TopologyIPv4Packet(
                    identity: 41,
                    senderIPAddress: "10.0.0.1",
                    receiverIPAddress: "10.0.0.2",
                    timeToLive: 62,
                    protocolNumber: .tcp,
                    payload: .tcp(TopologyTCPSegment(
                        sourcePort: 1_234,
                        destinationPort: 80,
                        sequenceNumber: 99,
                        acknowledgementNumber: 100,
                        flags: [.push, .acknowledgement],
                        payload: Data("GET /".utf8)
                    ))
                ))
            ),
            TopologyEthernetFrame(
                identity: 50,
                sourceMACAddress: "AA:BB:CC:DD:EE:01",
                destinationMACAddress: "AA:BB:CC:DD:EE:02",
                payload: .ipv4(TopologyIPv4Packet(
                    identity: 51,
                    senderIPAddress: "10.0.0.1",
                    receiverIPAddress: "10.0.0.2",
                    timeToLive: 61,
                    protocolNumber: .udp,
                    payload: .udp(TopologyUDPDatagram(
                        sourcePort: 1_234,
                        destinationPort: 4_321,
                        payload: Data("hello".utf8)
                    ))
                ))
            ),
        ]
        let codec = TopologyRemoteLinkWireCodec(linkCode: "classroom-link-code")
        let (local, remote) = lanRemoteLinkHandshakes(linkCode: "classroom-link-code")
        var sender = try codec.makeSessionCodec(localHandshake: local, remoteHandshake: remote)
        var receiver = try codec.makeSessionCodec(localHandshake: remote, remoteHandshake: local)

        for frame in frames {
            let wireFrame = TopologyRemoteLinkWireFrame(frame: frame)
            let encoded = try sender.encode(.frame(wireFrame))
            XCTAssertEqual(try receiver.decode(encoded.record).message, .frame(wireFrame))
        }
    }

    func testLANRemoteLinkWireCodecRejectsWrongLinkCode() throws {
        let correctCodec = TopologyRemoteLinkWireCodec(linkCode: "correct-code")
        let handshake = TopologyRemoteLinkWireHandshake(
            protocolVersion: TopologyRemoteLinkWireCodec.protocolVersion,
            linkDigest: TopologyRemoteLinkWireCodec.digest(for: "correct-code"),
            endpointID: UUID(),
            endpointName: "Correct iPad"
        )
        let encoded = try correctCodec.encode(.hello(handshake))

        XCTAssertThrowsError(try TopologyRemoteLinkWireCodec(linkCode: "wrong-code").decode(encoded)) { error in
            XCTAssertEqual(error as? TopologyRemoteLinkWireCodecError, .authenticationFailed)
        }
    }

    func testLANRemoteLinkWireCodecRejectsCorruptionUnsupportedVersionAndOversizedRecords() throws {
        let codec = TopologyRemoteLinkWireCodec(linkCode: "classroom-link-code")
        let validHandshake = TopologyRemoteLinkWireHandshake(
            protocolVersion: TopologyRemoteLinkWireCodec.protocolVersion,
            linkDigest: TopologyRemoteLinkWireCodec.digest(for: "classroom-link-code"),
            endpointID: UUID(),
            endpointName: "Valid iPad"
        )
        var corrupted = try codec.encode(.hello(validHandshake))
        corrupted[corrupted.startIndex] ^= 0x01
        XCTAssertThrowsError(try codec.decode(corrupted)) { error in
            XCTAssertEqual(error as? TopologyRemoteLinkWireCodecError, .authenticationFailed)
        }

        let unsupportedHandshake = TopologyRemoteLinkWireHandshake(
            protocolVersion: TopologyRemoteLinkWireCodec.protocolVersion + 1,
            linkDigest: TopologyRemoteLinkWireCodec.digest(for: "classroom-link-code"),
            endpointID: UUID(),
            endpointName: "Future iPad"
        )
        let unsupportedRecord = try codec.encode(.hello(unsupportedHandshake))
        XCTAssertThrowsError(try codec.decode(unsupportedRecord)) { error in
            XCTAssertEqual(
                error as? TopologyRemoteLinkWireCodecError,
                .unsupportedVersion(TopologyRemoteLinkWireCodec.protocolVersion + 1)
            )
        }

        let peerHandshake = TopologyRemoteLinkWireHandshake(
            protocolVersion: TopologyRemoteLinkWireCodec.protocolVersion,
            linkDigest: TopologyRemoteLinkWireCodec.digest(for: "classroom-link-code"),
            endpointID: uuid("00000000-0000-0000-0000-00000000D001"),
            endpointName: "Peer iPad"
        )
        var sessionCodec = try codec.makeSessionCodec(
            localHandshake: validHandshake,
            remoteHandshake: peerHandshake
        )
        let oversizedPayload = Data(repeating: 0x41, count: TopologyRemoteLinkWireCodec.maximumRecordBytes)
        let oversizedFrame = TopologyRemoteLinkWireFrame(frame: TopologyEthernetFrame(
            identity: 1,
            sourceMACAddress: "AA:AA:AA:AA:AA:01",
            destinationMACAddress: "AA:AA:AA:AA:AA:02",
            payload: .ipv4(TopologyIPv4Packet(
                identity: 2,
                senderIPAddress: "10.0.0.1",
                receiverIPAddress: "10.0.0.2",
                timeToLive: 64,
                protocolNumber: .udp,
                payload: .udp(TopologyUDPDatagram(sourcePort: 1, destinationPort: 2, payload: oversizedPayload))
            ))
        ))
        XCTAssertThrowsError(try sessionCodec.encode(.frame(oversizedFrame))) { error in
            XCTAssertEqual(error as? TopologyRemoteLinkWireCodecError, .recordTooLarge)
        }
    }


    func testLANRemoteLinkSessionCodecDerivesSharedKeysAndRejectsReplay() throws {
        let codec = TopologyRemoteLinkWireCodec(linkCode: "classroom-link-code")
        let host = TopologyRemoteLinkWireHandshake(
            protocolVersion: TopologyRemoteLinkWireCodec.protocolVersion,
            linkDigest: TopologyRemoteLinkWireCodec.digest(for: "classroom-link-code"),
            endpointID: uuid("00000000-0000-0000-0000-00000000D101"),
            endpointName: "Host iPad",
            sessionID: uuid("00000000-0000-0000-0000-00000000D102"),
            challenge: Data(repeating: 0x11, count: TopologyRemoteLinkWireHandshake.challengeByteCount)
        )
        let join = TopologyRemoteLinkWireHandshake(
            protocolVersion: TopologyRemoteLinkWireCodec.protocolVersion,
            linkDigest: TopologyRemoteLinkWireCodec.digest(for: "classroom-link-code"),
            endpointID: uuid("00000000-0000-0000-0000-00000000D201"),
            endpointName: "Join iPad",
            sessionID: uuid("00000000-0000-0000-0000-00000000D202"),
            challenge: Data(repeating: 0x22, count: TopologyRemoteLinkWireHandshake.challengeByteCount)
        )
        var hostSession = try codec.makeSessionCodec(localHandshake: host, remoteHandshake: join)
        var joinSession = try codec.makeSessionCodec(localHandshake: join, remoteHandshake: host)

        let ready = try hostSession.encode(.sessionReady)
        XCTAssertEqual(try joinSession.decode(ready.record).message, .sessionReady)
        XCTAssertThrowsError(try joinSession.decode(ready.record)) { error in
            XCTAssertEqual(
                error as? TopologyRemoteLinkWireCodecError,
                .unexpectedSequence(expected: 2, received: 1)
            )
        }
    }

    func testLANRemoteLinkSessionCodecRejectsRecordsFromAnotherSession() throws {
        let codec = TopologyRemoteLinkWireCodec(linkCode: "classroom-link-code")
        let host = TopologyRemoteLinkWireHandshake(
            protocolVersion: TopologyRemoteLinkWireCodec.protocolVersion,
            linkDigest: TopologyRemoteLinkWireCodec.digest(for: "classroom-link-code"),
            endpointID: uuid("00000000-0000-0000-0000-00000000D301"),
            endpointName: "Host iPad",
            sessionID: uuid("00000000-0000-0000-0000-00000000D302"),
            challenge: Data(repeating: 0x31, count: TopologyRemoteLinkWireHandshake.challengeByteCount)
        )
        let firstJoin = TopologyRemoteLinkWireHandshake(
            protocolVersion: TopologyRemoteLinkWireCodec.protocolVersion,
            linkDigest: TopologyRemoteLinkWireCodec.digest(for: "classroom-link-code"),
            endpointID: uuid("00000000-0000-0000-0000-00000000D401"),
            endpointName: "Join iPad",
            sessionID: uuid("00000000-0000-0000-0000-00000000D402"),
            challenge: Data(repeating: 0x41, count: TopologyRemoteLinkWireHandshake.challengeByteCount)
        )
        let secondJoin = TopologyRemoteLinkWireHandshake(
            protocolVersion: TopologyRemoteLinkWireCodec.protocolVersion,
            linkDigest: TopologyRemoteLinkWireCodec.digest(for: "classroom-link-code"),
            endpointID: firstJoin.endpointID,
            endpointName: firstJoin.endpointName,
            sessionID: uuid("00000000-0000-0000-0000-00000000D403"),
            challenge: Data(repeating: 0x42, count: TopologyRemoteLinkWireHandshake.challengeByteCount)
        )
        var firstHostSession = try codec.makeSessionCodec(localHandshake: host, remoteHandshake: firstJoin)
        var secondJoinSession = try codec.makeSessionCodec(localHandshake: secondJoin, remoteHandshake: host)
        let firstSessionRecord = try firstHostSession.encode(.sessionReady)

        XCTAssertThrowsError(try secondJoinSession.decode(firstSessionRecord.record)) { error in
            XCTAssertEqual(error as? TopologyRemoteLinkWireCodecError, .authenticationFailed)
        }
    }

    func testLANRemoteLinkSessionCodecRequiresStrictlyOrderedRecords() throws {
        let codec = TopologyRemoteLinkWireCodec(linkCode: "classroom-link-code")
        let host = TopologyRemoteLinkWireHandshake(
            protocolVersion: TopologyRemoteLinkWireCodec.protocolVersion,
            linkDigest: TopologyRemoteLinkWireCodec.digest(for: "classroom-link-code"),
            endpointID: uuid("00000000-0000-0000-0000-00000000D501"),
            endpointName: "Host iPad",
            sessionID: uuid("00000000-0000-0000-0000-00000000D502"),
            challenge: Data(repeating: 0x51, count: TopologyRemoteLinkWireHandshake.challengeByteCount)
        )
        let join = TopologyRemoteLinkWireHandshake(
            protocolVersion: TopologyRemoteLinkWireCodec.protocolVersion,
            linkDigest: TopologyRemoteLinkWireCodec.digest(for: "classroom-link-code"),
            endpointID: uuid("00000000-0000-0000-0000-00000000D601"),
            endpointName: "Join iPad",
            sessionID: uuid("00000000-0000-0000-0000-00000000D602"),
            challenge: Data(repeating: 0x61, count: TopologyRemoteLinkWireHandshake.challengeByteCount)
        )
        var hostSession = try codec.makeSessionCodec(localHandshake: host, remoteHandshake: join)
        var joinSession = try codec.makeSessionCodec(localHandshake: join, remoteHandshake: host)
        _ = try hostSession.encode(.sessionReady)
        let secondRecord = try hostSession.encode(.keepAlive)

        XCTAssertThrowsError(try joinSession.decode(secondRecord.record)) { error in
            XCTAssertEqual(
                error as? TopologyRemoteLinkWireCodecError,
                .unexpectedSequence(expected: 1, received: 2)
            )
        }
    }

    func testLANRemoteLinkHandshakeCodecRejectsSessionTraffic() throws {
        let codec = TopologyRemoteLinkWireCodec(linkCode: "classroom-link-code")
        XCTAssertThrowsError(try codec.encode(.keepAlive)) { error in
            XCTAssertEqual(error as? TopologyRemoteLinkWireCodecError, .invalidHandshake)
        }
    }

    func testLANRemoteLinkBonjourSelectionCanReuseUnchangedCachedResult() {
        let expected = NWEndpoint.service(
            name: "Filius-abcdef123456-Host",
            type: "_filiuslink._tcp",
            domain: "local.",
            interface: nil
        )
        let endpoints: [NWEndpoint] = [
            .service(name: "Unrelated", type: "_filiuslink._tcp", domain: "local.", interface: nil),
            expected,
        ]

        XCTAssertEqual(
            TopologyRemoteLinkLANBonjourSelection.matchingEndpoint(
                in: endpoints,
                servicePrefix: "Filius-abcdef123456"
            ),
            expected
        )
    }

    func testLANRemoteLinkWireFrameMaterializationAllocatesFreshLocalIdentities() {
        let original = TopologyEthernetFrame(
            identity: 900,
            sourceMACAddress: "AA:BB:CC:DD:EE:01",
            destinationMACAddress: "AA:BB:CC:DD:EE:02",
            payload: .ipv4(TopologyIPv4Packet(
                identity: 901,
                senderIPAddress: "10.0.0.1",
                receiverIPAddress: "10.0.0.2",
                timeToLive: 64,
                protocolNumber: .icmp,
                payload: .icmp(TopologyICMPMessage(
                    kind: .timeExceeded,
                    identifier: 7,
                    sequenceNumber: 8,
                    embeddedOriginalPacket: TopologyIPv4Packet(
                        identity: 902,
                        senderIPAddress: "10.0.0.1",
                        receiverIPAddress: "10.0.0.2",
                        timeToLive: 1,
                        protocolNumber: .udp,
                        payload: .udp(TopologyUDPDatagram(sourcePort: 1, destinationPort: 2, payload: Data()))
                    )
                ))
            ))
        )
        var engine = TopologyNetworkRuntimeEngine(seed: 1)
        engine.handle(.start(snapshot: .empty, seed: 1, initialTimeMilliseconds: 0))

        let materialized = engine.materializeLANRemoteLinkFrame(TopologyRemoteLinkWireFrame(frame: original))

        XCTAssertEqual(materialized.identity, 1)
        guard case let .ipv4(packet) = materialized.payload else { return XCTFail("Expected IPv4") }
        XCTAssertEqual(packet.identity, 1)
        XCTAssertEqual(packet.senderIPAddress, "10.0.0.1")
        guard case let .icmp(message) = packet.payload else { return XCTFail("Expected ICMP") }
        XCTAssertEqual(message.embeddedOriginalPacket?.identity, 2)
    }

    func testLANRemoteLinkQueuesCompleteEthernetFrameWhenConnected() {
        let hostID = uuid("00000000-0000-0000-0000-00000000AA01")
        let hostPortID = uuid("00000000-0000-0000-0000-00000000AA02")
        let remoteID = uuid("00000000-0000-0000-0000-00000000AA03")
        let remotePortID = uuid("00000000-0000-0000-0000-00000000AA04")
        let snapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: [
                pc(hostID, hostPortID),
                TopologyNetworkRuntimeNodeSnapshot(
                    id: remoteID,
                    kind: .remoteLink,
                    ports: [TopologyNetworkRuntimePortSnapshot(id: remotePortID, label: "remote0")]
                ),
            ],
            links: [link(hostID, hostPortID, remoteID, remotePortID)],
            deviceConfigurations: [hostID: device("10.0.0.1")],
            interfaceConfigurations: [:],
            manualRoutesByNodeID: [:],
            remoteLinkConfigurationsByNodeID: [remoteID: TopologyRemoteLinkConfiguration(
                pairIdentifier: "shared-production-link-code",
                latencyMilliseconds: 20,
                transportMode: .localNetwork,
                lanRole: .host
            )]
        )
        var engine = TopologyNetworkRuntimeEngine(seed: 99)
        engine.handle(.start(snapshot: snapshot, seed: 99, initialTimeMilliseconds: 0))
        engine.setLANRemoteLinkConnectionState(nodeID: remoteID, connectionState: .connected(peerName: "Peer iPad"))
        let frame = TopologyEthernetFrame(
            identity: engine.allocateFrameIdentity(),
            sourceMACAddress: TopologyNetworkRuntimeEngine.stableMACAddress(for: hostPortID),
            destinationMACAddress: TopologyNetworkRuntimeEngine.ethernetBroadcastMACAddress,
            payload: .arp(TopologyARPPacket(
                operation: .request,
                senderMACAddress: TopologyNetworkRuntimeEngine.stableMACAddress(for: hostPortID),
                senderIPAddress: "10.0.0.1",
                targetMACAddress: TopologyNetworkRuntimeEngine.unspecifiedMACAddress,
                targetIPAddress: "10.0.0.2"
            ))
        )

        engine.sendEthernetFrame(fromNodeID: hostID, outgoingPortID: hostPortID, frame: frame)
        XCTAssertEqual(engine.remoteLinkRuntimeStatus(nodeID: remoteID)?.pendingFrameCount, 1)
        _ = engine.handle(.advance(toMilliseconds: 5_000))
        let outbound = engine.claimLANRemoteLinkOutboundFrames()

        XCTAssertEqual(engine.remoteLinkRuntimeStatus(nodeID: remoteID)?.pendingFrameCount, 1)
        XCTAssertEqual(outbound.count, 1)
        XCTAssertEqual(outbound.first?.nodeID, remoteID)
        XCTAssertEqual(outbound.first?.frameIdentity, frame.identity)
        XCTAssertEqual(outbound.first?.frame, TopologyRemoteLinkWireFrame(frame: frame))
        XCTAssertEqual(outbound.first?.state, .awaitingControllerAcknowledgement)
        XCTAssertFalse(engine.remoteLinkRuntimeEvidence.contains { evidence in
            evidence.frameIdentity == frame.identity && evidence.kind == .delivered
        })

        guard let transmissionID = outbound.first?.transmissionID else {
            return XCTFail("Expected a claimed LAN transmission")
        }
        engine.completeLANRemoteLinkOutboundFrame(
            nodeID: remoteID,
            transmissionID: transmissionID,
            result: .accepted(attempts: 1)
        )

        XCTAssertEqual(engine.remoteLinkRuntimeStatus(nodeID: remoteID)?.pendingFrameCount, 0)
        XCTAssertTrue(engine.remoteLinkRuntimeEvidence.contains { evidence in
            evidence.frameIdentity == frame.identity && evidence.kind == .delivered
        })
    }

    @MainActor
    func testLANRemoteLinkControllerHandshakeTimeoutReleasesHostForNextPeer() async throws {
        let port = try availableLoopbackPort()
        let controller = TopologyRemoteLinkLANController(
            handshakeTimeoutSeconds: 0.2,
            acknowledgementTimeoutSeconds: 1
        )
        let nodeID = uuid("00000000-0000-0000-0000-00000000AC10")
        let firstTimedOut = expectation(description: "first unauthenticated peer times out")
        let secondTimedOut = expectation(description: "second unauthenticated peer times out")
        var timeoutCount = 0
        controller.onConnectionStateChange = { observedNodeID, state in
            guard observedNodeID == nodeID,
                  case let .failed(message) = state,
                  message.contains("handshake timed out") else { return }
            timeoutCount += 1
            if timeoutCount == 1 {
                firstTimedOut.fulfill()
            } else if timeoutCount == 2 {
                secondTimedOut.fulfill()
            }
        }
        controller.reconcile(endpoints: [TopologyRemoteLinkLANEndpointConfiguration(
            nodeID: nodeID,
            endpointName: "Timeout Host",
            linkCode: "timeout-link",
            role: .host,
            listenPort: port,
            joinMethod: .bonjour,
            remoteHost: "",
            remotePort: port
        )])
        try await Task.sleep(for: .milliseconds(100))

        let firstPeer = NWConnection(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        firstPeer.start(queue: DispatchQueue(label: "test.remote-link.timeout.first"))
        await fulfillment(of: [firstTimedOut], timeout: 2)
        firstPeer.cancel()

        let secondPeer = NWConnection(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        secondPeer.start(queue: DispatchQueue(label: "test.remote-link.timeout.second"))
        await fulfillment(of: [secondTimedOut], timeout: 2)
        secondPeer.cancel()
        controller.stopAll()

        XCTAssertEqual(timeoutCount, 2)
    }

    @MainActor
    func testLANRemoteLinkControllerCompletesFrameOnceAfterPeerAcknowledgement() async throws {
        let port = try availableLoopbackPort()
        let host = TopologyRemoteLinkLANController(
            handshakeTimeoutSeconds: 1,
            acknowledgementTimeoutSeconds: 1
        )
        let join = TopologyRemoteLinkLANController(
            handshakeTimeoutSeconds: 1,
            acknowledgementTimeoutSeconds: 1
        )
        let hostID = uuid("00000000-0000-0000-0000-00000000AC20")
        let joinID = uuid("00000000-0000-0000-0000-00000000AC21")
        let hostConnected = expectation(description: "host connected")
        let joinConnected = expectation(description: "join connected")
        let frameReceived = expectation(description: "peer received frame")
        let sendCompleted = expectation(description: "send completed exactly once")
        sendCompleted.assertForOverFulfill = true
        var receivedFrame: TopologyRemoteLinkWireFrame?
        var sendResults: [TopologyRemoteLinkLANSendResult] = []

        host.onConnectionStateChange = { nodeID, state in
            if nodeID == hostID, case .connected = state { hostConnected.fulfill() }
        }
        join.onConnectionStateChange = { nodeID, state in
            if nodeID == joinID, case .connected = state { joinConnected.fulfill() }
        }
        join.onFrameReceived = { nodeID, frame in
            guard nodeID == joinID else { return false }
            receivedFrame = frame
            frameReceived.fulfill()
            return true
        }
        host.reconcile(endpoints: [TopologyRemoteLinkLANEndpointConfiguration(
            nodeID: hostID,
            endpointName: "Host iPad",
            linkCode: "ack-link",
            role: .host,
            listenPort: port,
            joinMethod: .bonjour,
            remoteHost: "",
            remotePort: port
        )])
        join.reconcile(endpoints: [TopologyRemoteLinkLANEndpointConfiguration(
            nodeID: joinID,
            endpointName: "Join iPad",
            linkCode: "ack-link",
            role: .join,
            listenPort: port,
            joinMethod: .manual,
            remoteHost: "127.0.0.1",
            remotePort: port
        )])
        await fulfillment(of: [hostConnected, joinConnected], timeout: 3)

        let wireFrame = TopologyRemoteLinkWireFrame(
            sourceMACAddress: "AA:BB:CC:DD:EE:01",
            destinationMACAddress: "AA:BB:CC:DD:EE:02",
            payload: .ipv4(TopologyRemoteLinkWireIPv4Packet(
                senderIPAddress: "10.0.0.1",
                receiverIPAddress: "10.0.0.2",
                timeToLive: 64,
                protocolNumber: .udp,
                payload: .udp(TopologyRemoteLinkWireUDPDatagram(
                    sourcePort: 1_234,
                    destinationPort: 4_321,
                    payload: Data("acknowledge me".utf8)
                ))
            ))
        )
        host.send(wireFrame, from: hostID) { result in
            sendResults.append(result)
            sendCompleted.fulfill()
        }
        await fulfillment(of: [frameReceived, sendCompleted], timeout: 3)
        try await Task.sleep(for: .milliseconds(250))
        host.stopAll()
        join.stopAll()

        XCTAssertEqual(receivedFrame, wireFrame)
        XCTAssertEqual(sendResults, [.accepted(attempts: 1)])
    }

    @MainActor
    func testLANRemoteLinkControllerDoesNotAcknowledgeDelayedApplicationAfterReceiverStops() async throws {
        let port = try availableLoopbackPort()
        let sender = TopologyRemoteLinkLANController(
            handshakeTimeoutSeconds: 1,
            acknowledgementTimeoutSeconds: 1
        )
        let receiver = TopologyRemoteLinkLANController(
            handshakeTimeoutSeconds: 1,
            acknowledgementTimeoutSeconds: 1
        )
        let senderID = uuid("00000000-0000-0000-0000-00000000AC40")
        let receiverID = uuid("00000000-0000-0000-0000-00000000AC41")
        let senderConnected = expectation(description: "sender connected")
        let receiverConnected = expectation(description: "receiver connected")
        let applicationDeliveryStarted = expectation(description: "application delivery started")
        let sendCompleted = expectation(description: "send completed without false success")
        sendCompleted.assertForOverFulfill = true
        var applicationContinuation: CheckedContinuation<Bool, Never>?
        var sendResults: [TopologyRemoteLinkLANSendResult] = []

        sender.onConnectionStateChange = { nodeID, state in
            if nodeID == senderID, case .connected = state { senderConnected.fulfill() }
        }
        receiver.onConnectionStateChange = { nodeID, state in
            if nodeID == receiverID, case .connected = state { receiverConnected.fulfill() }
        }
        receiver.onFrameReceived = { nodeID, _ in
            guard nodeID == receiverID else { return false }
            applicationDeliveryStarted.fulfill()
            return await withCheckedContinuation { continuation in
                applicationContinuation = continuation
            }
        }
        sender.reconcile(endpoints: [TopologyRemoteLinkLANEndpointConfiguration(
            nodeID: senderID,
            endpointName: "Delayed Sender",
            linkCode: "delayed-application-link",
            role: .host,
            listenPort: port,
            joinMethod: .bonjour,
            remoteHost: "",
            remotePort: port
        )])
        receiver.reconcile(endpoints: [TopologyRemoteLinkLANEndpointConfiguration(
            nodeID: receiverID,
            endpointName: "Delayed Receiver",
            linkCode: "delayed-application-link",
            role: .join,
            listenPort: port,
            joinMethod: .manual,
            remoteHost: "127.0.0.1",
            remotePort: port
        )])
        await fulfillment(of: [senderConnected, receiverConnected], timeout: 3)

        let wireFrame = TopologyRemoteLinkWireFrame(
            sourceMACAddress: "AA:BB:CC:DD:EE:40",
            destinationMACAddress: "AA:BB:CC:DD:EE:41",
            payload: .ipv4(TopologyRemoteLinkWireIPv4Packet(
                senderIPAddress: "10.0.0.40",
                receiverIPAddress: "10.0.0.41",
                timeToLive: 64,
                protocolNumber: .udp,
                payload: .udp(TopologyRemoteLinkWireUDPDatagram(
                    sourcePort: 4_040,
                    destinationPort: 4_041,
                    payload: Data("delay before acceptance".utf8)
                ))
            ))
        )
        sender.send(wireFrame, from: senderID) { result in
            sendResults.append(result)
            sendCompleted.fulfill()
        }
        await fulfillment(of: [applicationDeliveryStarted], timeout: 3)

        receiver.stopAll()
        applicationContinuation?.resume(returning: true)
        applicationContinuation = nil

        await fulfillment(of: [sendCompleted], timeout: 3)
        try await Task.sleep(for: .milliseconds(250))
        sender.stopAll()

        XCTAssertEqual(sendResults.count, 1)
        guard case .failed = sendResults[0] else {
            return XCTFail("A stopped receiver must not acknowledge delayed application delivery")
        }
    }

    @MainActor
    func testLANRemoteLinkControllerCompletesInFlightSendExactlyOnceWhenStoppedBeforeAcknowledgement() async throws {
        let port = try availableLoopbackPort()
        let controller = TopologyRemoteLinkLANController(
            handshakeTimeoutSeconds: 1,
            acknowledgementTimeoutSeconds: 2
        )
        let nodeID = uuid("00000000-0000-0000-0000-00000000AC30")
        let connected = expectation(description: "host authenticates raw peer")
        controller.onConnectionStateChange = { observedNodeID, state in
            if observedNodeID == nodeID, case .connected = state { connected.fulfill() }
        }
        controller.reconcile(endpoints: [TopologyRemoteLinkLANEndpointConfiguration(
            nodeID: nodeID,
            endpointName: "Exactly Once Host",
            linkCode: "exactly-once-link",
            role: .host,
            listenPort: port,
            joinMethod: .bonjour,
            remoteHost: "",
            remotePort: port
        )])
        try await Task.sleep(for: .milliseconds(100))

        let peerReady = expectation(description: "raw peer connected")
        let rawPeer = NWConnection(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        rawPeer.stateUpdateHandler = { state in
            if case .ready = state { peerReady.fulfill() }
        }
        rawPeer.start(queue: DispatchQueue(label: "test.remote-link.exactly-once.peer"))
        await fulfillment(of: [peerReady], timeout: 2)

        let handshakeCodec = TopologyRemoteLinkWireCodec(linkCode: "exactly-once-link")
        let peerHandshake = TopologyRemoteLinkWireHandshake(
            protocolVersion: TopologyRemoteLinkWireCodec.protocolVersion,
            linkDigest: TopologyRemoteLinkWireCodec.digest(for: "exactly-once-link"),
            endpointID: uuid("00000000-0000-0000-0000-00000000AC31"),
            endpointName: "Raw Peer",
            sessionID: uuid("00000000-0000-0000-0000-00000000AC32"),
            challenge: Data(repeating: 0xAC, count: TopologyRemoteLinkWireHandshake.challengeByteCount)
        )
        try await sendRemoteLinkRecord(handshakeCodec.encode(.hello(peerHandshake)), over: rawPeer)
        let hostHelloRecord = try await receiveRemoteLinkRecord(over: rawPeer)
        guard case let .hello(hostHandshake) = try handshakeCodec.decode(hostHelloRecord) else {
            rawPeer.cancel()
            controller.stopAll()
            return XCTFail("Expected host handshake")
        }
        var peerSession = try handshakeCodec.makeSessionCodec(
            localHandshake: peerHandshake,
            remoteHandshake: hostHandshake
        )
        try await sendRemoteLinkRecord(try peerSession.encode(.sessionReady).record, over: rawPeer)
        let hostReadyRecord = try await receiveRemoteLinkRecord(over: rawPeer)
        XCTAssertEqual(try peerSession.decode(hostReadyRecord).message, .sessionReady)
        await fulfillment(of: [connected], timeout: 2)

        let completion = expectation(description: "in-flight send completes once")
        completion.assertForOverFulfill = true
        var results: [TopologyRemoteLinkLANSendResult] = []
        let frame = TopologyRemoteLinkWireFrame(
            sourceMACAddress: "AA:BB:CC:DD:EE:03",
            destinationMACAddress: "AA:BB:CC:DD:EE:04",
            payload: .ipv4(TopologyRemoteLinkWireIPv4Packet(
                senderIPAddress: "10.0.0.3",
                receiverIPAddress: "10.0.0.4",
                timeToLive: 64,
                protocolNumber: .udp,
                payload: .udp(TopologyRemoteLinkWireUDPDatagram(
                    sourcePort: 5_000,
                    destinationPort: 5_001,
                    payload: Data("stop before ack".utf8)
                ))
            ))
        )
        controller.send(frame, from: nodeID) { result in
            results.append(result)
            completion.fulfill()
        }
        let frameRecord = try await receiveRemoteLinkRecord(over: rawPeer)
        XCTAssertEqual(try peerSession.decode(frameRecord).message, .frame(frame))

        controller.stopAll()
        await fulfillment(of: [completion], timeout: 2)
        try await Task.sleep(for: .milliseconds(250))
        rawPeer.cancel()

        XCTAssertEqual(results, [.failed(.sessionStopped)])
    }

    @MainActor
    func testLANRemoteLinkControllerReportsMissingSessionInsteadOfDroppingSilently() async {
        let controller = TopologyRemoteLinkLANController()
        let completion = expectation(description: "missing session completion")
        let nodeID = uuid("00000000-0000-0000-0000-00000000AC01")
        let frame = TopologyRemoteLinkWireFrame(frame: TopologyEthernetFrame(
            identity: 1,
            sourceMACAddress: "AA:AA:AA:AA:AA:01",
            destinationMACAddress: "AA:AA:AA:AA:AA:02",
            payload: .arp(TopologyARPPacket(
                operation: .request,
                senderMACAddress: "AA:AA:AA:AA:AA:01",
                senderIPAddress: "10.0.0.1",
                targetMACAddress: TopologyNetworkRuntimeEngine.unspecifiedMACAddress,
                targetIPAddress: "10.0.0.2"
            ))
        ))
        var observedResult: TopologyRemoteLinkLANSendResult?

        controller.send(frame, from: nodeID) { result in
            observedResult = result
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 1.0)

        XCTAssertEqual(observedResult, .failed(.sessionUnavailable))
    }

    @MainActor
    func testLANRemoteLinkControllerCompletesQueuedPreHandshakeFrameWhenSessionStops() async {
        let controller = TopologyRemoteLinkLANController()
        let nodeID = uuid("00000000-0000-0000-0000-00000000AC02")
        controller.reconcile(endpoints: [TopologyRemoteLinkLANEndpointConfiguration(
            nodeID: nodeID,
            endpointName: "Test iPad",
            linkCode: "test-link",
            role: .join,
            listenPort: 55555,
            joinMethod: .manual,
            remoteHost: "",
            remotePort: 55555
        )])
        let completion = expectation(description: "queued frame receives terminal result")
        let frame = TopologyRemoteLinkWireFrame(frame: TopologyEthernetFrame(
            identity: 2,
            sourceMACAddress: "AA:AA:AA:AA:AA:01",
            destinationMACAddress: "AA:AA:AA:AA:AA:02",
            payload: .arp(TopologyARPPacket(
                operation: .request,
                senderMACAddress: "AA:AA:AA:AA:AA:01",
                senderIPAddress: "10.0.0.1",
                targetMACAddress: TopologyNetworkRuntimeEngine.unspecifiedMACAddress,
                targetIPAddress: "10.0.0.2"
            ))
        ))
        var observedResult: TopologyRemoteLinkLANSendResult?

        controller.send(frame, from: nodeID) { result in
            observedResult = result
            completion.fulfill()
        }
        controller.stopAll()
        await fulfillment(of: [completion], timeout: 1.0)

        XCTAssertEqual(observedResult, .failed(.sessionStopped))
    }

    func testLANRemoteLinkSendFailureIsObservableAndNotRetriedByRuntime() {
        var fixture = lanRemoteLinkOutboundFixture()
        fixture.engine.sendEthernetFrame(
            fromNodeID: fixture.hostID,
            outgoingPortID: fixture.hostPortID,
            frame: fixture.frame
        )
        _ = fixture.engine.handle(.advance(toMilliseconds: 5_000))
        let firstClaim = fixture.engine.claimLANRemoteLinkOutboundFrames(limit: 1)
        XCTAssertEqual(firstClaim.count, 1)
        XCTAssertTrue(fixture.engine.claimLANRemoteLinkOutboundFrames(limit: 1).isEmpty)

        guard let transmissionID = firstClaim.first?.transmissionID else {
            return XCTFail("Expected a claimed LAN transmission")
        }
        fixture.engine.completeLANRemoteLinkOutboundFrame(
            nodeID: fixture.remoteID,
            transmissionID: transmissionID,
            result: .failed(.transportFailed(message: "connection reset", attempts: 1))
        )

        XCTAssertEqual(fixture.engine.remoteLinkRuntimeStatus(nodeID: fixture.remoteID)?.pendingFrameCount, 0)
        XCTAssertTrue(fixture.engine.claimLANRemoteLinkOutboundFrames().isEmpty)
        XCTAssertTrue(fixture.engine.remoteLinkRuntimeEvidence.contains { evidence in
            evidence.frameIdentity == fixture.frame.identity
                && evidence.kind == .dropped(reason: .lanDeliveryFailed)
        })
        XCTAssertTrue(fixture.engine.state.packetTraces.contains { trace in
            trace.frameIdentity == fixture.frame.identity
                && trace.operation == .dropped
                && trace.detail?.contains("connection reset") == true
        })
    }

    func testLANRemoteLinkClaimIsBoundedAndDoesNotDuplicateAwaitingFrames() {
        var fixture = lanRemoteLinkOutboundFixture()
        let secondFrame = TopologyEthernetFrame(
            identity: fixture.engine.allocateFrameIdentity(),
            sourceMACAddress: fixture.frame.sourceMACAddress,
            destinationMACAddress: fixture.frame.destinationMACAddress,
            payload: fixture.frame.payload
        )
        fixture.engine.sendEthernetFrame(
            fromNodeID: fixture.hostID,
            outgoingPortID: fixture.hostPortID,
            frame: fixture.frame
        )
        fixture.engine.sendEthernetFrame(
            fromNodeID: fixture.hostID,
            outgoingPortID: fixture.hostPortID,
            frame: secondFrame
        )
        _ = fixture.engine.handle(.advance(toMilliseconds: 5_000))

        let firstClaim = fixture.engine.claimLANRemoteLinkOutboundFrames(limit: 1)
        let secondClaim = fixture.engine.claimLANRemoteLinkOutboundFrames(limit: 1)
        let exhaustedClaim = fixture.engine.claimLANRemoteLinkOutboundFrames(limit: 1)

        XCTAssertEqual(firstClaim.count, 1)
        XCTAssertEqual(secondClaim.count, 1)
        XCTAssertNotEqual(firstClaim.first?.transmissionID, secondClaim.first?.transmissionID)
        XCTAssertTrue(exhaustedClaim.isEmpty)
        XCTAssertEqual(fixture.engine.remoteLinkRuntimeStatus(nodeID: fixture.remoteID)?.pendingFrameCount, 2)
    }

    func testLANRemoteLinkTransmissionIdentifiersAreNotReusedAcrossSimulationRuns() throws {
        var fixture = lanRemoteLinkOutboundFixture()
        fixture.engine.sendEthernetFrame(
            fromNodeID: fixture.hostID,
            outgoingPortID: fixture.hostPortID,
            frame: fixture.frame
        )
        _ = fixture.engine.handle(.advance(toMilliseconds: 5_000))
        let firstTransmissionID = try XCTUnwrap(
            fixture.engine.claimLANRemoteLinkOutboundFrames(limit: 1).first?.transmissionID
        )

        let snapshot = fixture.engine.state.topologySnapshot
        _ = fixture.engine.handle(.stop)
        _ = fixture.engine.handle(.start(snapshot: snapshot, seed: 99, initialTimeMilliseconds: 0))
        fixture.engine.setLANRemoteLinkConnectionState(
            nodeID: fixture.remoteID,
            connectionState: .connected(peerName: "Peer iPad")
        )
        let secondFrame = TopologyEthernetFrame(
            identity: fixture.engine.allocateFrameIdentity(),
            sourceMACAddress: fixture.frame.sourceMACAddress,
            destinationMACAddress: fixture.frame.destinationMACAddress,
            payload: fixture.frame.payload
        )
        fixture.engine.sendEthernetFrame(
            fromNodeID: fixture.hostID,
            outgoingPortID: fixture.hostPortID,
            frame: secondFrame
        )
        _ = fixture.engine.handle(.advance(toMilliseconds: 5_000))
        let secondTransmissionID = try XCTUnwrap(
            fixture.engine.claimLANRemoteLinkOutboundFrames(limit: 1).first?.transmissionID
        )

        XCTAssertGreaterThan(secondTransmissionID, firstTransmissionID)
        fixture.engine.completeLANRemoteLinkOutboundFrame(
            nodeID: fixture.remoteID,
            transmissionID: firstTransmissionID,
            result: .accepted(attempts: 1)
        )
        XCTAssertEqual(fixture.engine.remoteLinkRuntimeStatus(nodeID: fixture.remoteID)?.pendingFrameCount, 1)
    }

    func testLANRemoteLinkPendingScheduleIsBoundedBeforeControllerQueueing() {
        var fixture = lanRemoteLinkOutboundFixture()
        for _ in 0...TopologyNetworkRuntimeEngine.maximumPendingLANRemoteLinkTransmissionsPerNode {
            let frame = TopologyEthernetFrame(
                identity: fixture.engine.allocateFrameIdentity(),
                sourceMACAddress: fixture.frame.sourceMACAddress,
                destinationMACAddress: fixture.frame.destinationMACAddress,
                payload: fixture.frame.payload
            )
            fixture.engine.sendEthernetFrame(
                fromNodeID: fixture.hostID,
                outgoingPortID: fixture.hostPortID,
                frame: frame
            )
        }

        let scheduledCount = fixture.engine.state.pendingEvents.filter { event in
            guard case let .lanRemoteLinkTransmission(nodeID, _, _, _) = event.kind else { return false }
            return nodeID == fixture.remoteID
        }.count
        let queuedCount = fixture.engine.state.lanRemoteLinkOutboundFrames.filter {
            $0.nodeID == fixture.remoteID
        }.count
        XCTAssertEqual(
            scheduledCount + queuedCount,
            TopologyNetworkRuntimeEngine.maximumPendingLANRemoteLinkTransmissionsPerNode
        )
        XCTAssertTrue(fixture.engine.remoteLinkRuntimeEvidence.contains { evidence in
            evidence.nodeID == fixture.remoteID
                && evidence.kind == .dropped(reason: .lanOutboundQueueOverflow)
        })
    }

    func testGlobalPacketLossDropsEveryPhysicalDeliveryUntilDisabled() {
        let firstNodeID = uuid("00000000-0000-0000-0000-000000000101")
        let firstPortID = uuid("00000000-0000-0000-0000-000000000102")
        let secondNodeID = uuid("00000000-0000-0000-0000-000000000103")
        let secondPortID = uuid("00000000-0000-0000-0000-000000000104")
        var engine = startedEngine(
            nodes: [pc(firstNodeID, firstPortID), pc(secondNodeID, secondPortID)],
            links: [link(firstNodeID, firstPortID, secondNodeID, secondPortID)],
            devices: [
                firstNodeID: device("10.0.0.1"),
                secondNodeID: device("10.0.0.2"),
            ]
        )
        let frame = TopologyEthernetFrame(
            identity: engine.allocateFrameIdentity(),
            sourceMACAddress: TopologyNetworkRuntimeEngine.stableMACAddress(for: firstPortID),
            destinationMACAddress: TopologyNetworkRuntimeEngine.ethernetBroadcastMACAddress,
            payload: .arp(TopologyARPPacket(
                operation: .request,
                senderMACAddress: TopologyNetworkRuntimeEngine.stableMACAddress(for: firstPortID),
                senderIPAddress: "10.0.0.1",
                targetMACAddress: TopologyNetworkRuntimeEngine.unspecifiedMACAddress,
                targetIPAddress: "10.0.0.2"
            ))
        )

        engine.setGlobalPacketLossEnabled(true)
        engine.sendEthernetFrame(fromNodeID: firstNodeID, outgoingPortID: firstPortID, frame: frame)

        XCTAssertTrue(engine.state.globalPacketLossEnabled)
        XCTAssertTrue(engine.state.arpCachesByNodeID[secondNodeID]?.isEmpty ?? true)
        XCTAssertTrue(engine.state.packetTraces.contains { trace in
            trace.frameIdentity == frame.identity
                && trace.nodeID == secondNodeID
                && trace.operation == .dropped
                && trace.detail == "global packet-loss simulation"
        })

        engine.setGlobalPacketLossEnabled(false)
        engine.sendEthernetFrame(fromNodeID: firstNodeID, outgoingPortID: firstPortID, frame: frame)

        XCTAssertFalse(engine.state.globalPacketLossEnabled)
        XCTAssertEqual(
            engine.state.arpCachesByNodeID[secondNodeID]?["10.0.0.1"]?.macAddress,
            TopologyNetworkRuntimeEngine.stableMACAddress(for: firstPortID)
        )
    }

    func testTypedDNSConsultationRequiresReachableRunningServer() {
        let clientNodeID = uuid("00000000-0000-0000-0000-00000000D101")
        let clientPortID = uuid("00000000-0000-0000-0000-00000000D102")
        let serverNodeID = uuid("00000000-0000-0000-0000-00000000D103")
        let serverPortID = uuid("00000000-0000-0000-0000-00000000D104")
        let nodes = [pc(clientNodeID, clientPortID), pc(serverNodeID, serverPortID)]
        let devices = [
            clientNodeID: device("10.0.0.10"),
            serverNodeID: device("10.0.0.53"),
        ]
        guard let question = TopologyDNSQuestion(name: "school.local", type: .mailExchange) else {
            return XCTFail("Expected valid DNS question")
        }

        var disconnected = startedEngine(nodes: nodes, links: [], devices: devices)
        XCTAssertNotNil(disconnected.startDNSServer(nodeID: serverNodeID))
        XCTAssertFalse(disconnected.consultDNSServer(
            clientNodeID: clientNodeID,
            serverIPAddress: "10.0.0.53",
            question: question,
            timeoutMilliseconds: 1
        ))

        var stopped = startedEngine(
            nodes: nodes,
            links: [link(clientNodeID, clientPortID, serverNodeID, serverPortID)],
            devices: devices
        )
        XCTAssertFalse(stopped.consultDNSServer(
            clientNodeID: clientNodeID,
            serverIPAddress: "10.0.0.53",
            question: question,
            timeoutMilliseconds: 1
        ))

        var connected = startedEngine(
            nodes: nodes,
            links: [link(clientNodeID, clientPortID, serverNodeID, serverPortID)],
            devices: devices
        )
        XCTAssertNotNil(connected.startDNSServer(nodeID: serverNodeID))
        XCTAssertTrue(connected.consultDNSServer(
            clientNodeID: clientNodeID,
            serverIPAddress: "10.0.0.53",
            question: question,
            timeoutMilliseconds: 1
        ))
        XCTAssertTrue(connected.state.packetTraces.contains { trace in
            trace.nodeID == clientNodeID
                && trace.operation == .accepted
                && trace.detail == "DNS response typed received"
                && trace.beforeHeaders.contains {
                    $0.name == "recordType" && $0.value == TopologyDNSRecordType.mailExchange.rawValue
                }
        })
    }

    func testTypedDNSConsultationHonorsGlobalPacketLoss() {
        let clientNodeID = uuid("00000000-0000-0000-0000-00000000D201")
        let clientPortID = uuid("00000000-0000-0000-0000-00000000D202")
        let serverNodeID = uuid("00000000-0000-0000-0000-00000000D203")
        let serverPortID = uuid("00000000-0000-0000-0000-00000000D204")
        var engine = startedEngine(
            nodes: [pc(clientNodeID, clientPortID), pc(serverNodeID, serverPortID)],
            links: [link(clientNodeID, clientPortID, serverNodeID, serverPortID)],
            devices: [
                clientNodeID: device("10.0.0.10"),
                serverNodeID: device("10.0.0.53"),
            ]
        )
        guard let question = TopologyDNSQuestion(name: "school.local", type: .nameServer) else {
            return XCTFail("Expected valid DNS question")
        }
        XCTAssertNotNil(engine.startDNSServer(nodeID: serverNodeID))
        engine.setGlobalPacketLossEnabled(true)

        XCTAssertFalse(engine.consultDNSServer(
            clientNodeID: clientNodeID,
            serverIPAddress: "10.0.0.53",
            question: question,
            timeoutMilliseconds: 1
        ))
        XCTAssertTrue(engine.state.packetTraces.contains { trace in
            trace.operation == .dropped && trace.detail == "global packet-loss simulation"
        })
    }

    func testGlobalPacketLossResetsAcrossStopAndRestart() {
        var engine = TopologyNetworkRuntimeEngine(seed: 42)
        engine.handle(.start(snapshot: .empty, seed: 42, initialTimeMilliseconds: 0))
        engine.setGlobalPacketLossEnabled(true)
        XCTAssertTrue(engine.state.globalPacketLossEnabled)

        engine.handle(.stop)
        XCTAssertFalse(engine.state.globalPacketLossEnabled)

        engine.handle(.start(snapshot: .empty, seed: 42, initialTimeMilliseconds: 0))
        XCTAssertFalse(engine.state.globalPacketLossEnabled)
    }

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

    func testPacketTraceRetentionEvictsOldestEventsInConfiguredBatches() {
        let nodeID = UUID(uuidString: "00000000-0000-0000-0000-000000002001")!
        let interfaceID = UUID(uuidString: "00000000-0000-0000-0000-000000002002")!
        var engine = TopologyNetworkRuntimeEngine(
            seed: 20,
            packetTraceRetentionPolicy: TopologyPacketTraceRetentionPolicy(
                maximumEventCount: 3,
                evictionBatchSize: 2
            )
        )

        for identity in UInt64(1)...UInt64(6) {
            engine.recordTrace(
                frameIdentity: identity,
                nodeID: nodeID,
                interfaceID: interfaceID,
                direction: .outbound,
                layer: .dataLink,
                operation: .sent,
                detail: "trace-\(identity)"
            )
        }

        XCTAssertEqual(engine.state.packetTraces.map(\.id), [5, 6])
        XCTAssertEqual(engine.state.packetTraces.map(\.detail), ["trace-5", "trace-6"])
        XCTAssertEqual(engine.state.discardedPacketTraceCount, 4)
        XCTAssertEqual(engine.state.nextTraceIdentity, 7)
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
            nodeID: routerID,
            interfaceID: secondPortID,
            direction: .outbound,
            layer: .application,
            operation: .sent,
            detail: "identity-free diagnostic"
        )
        engine.recordTrace(
            frameIdentity: 99,
            nodeID: routerID,
            interfaceID: secondPortID,
            direction: .outbound,
            layer: .application,
            operation: .compatibilityAdapter,
            detail: "compatibility diagnostic"
        )
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

        let rows = engine.packetCaptureMessageRows(nodeID: routerID)
        XCTAssertEqual(rows.map(\.number), [3])
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

    private func lanRemoteLinkOutboundFixture() -> (
        engine: TopologyNetworkRuntimeEngine,
        hostID: UUID,
        hostPortID: UUID,
        remoteID: UUID,
        frame: TopologyEthernetFrame
    ) {
        let hostID = uuid("00000000-0000-0000-0000-00000000AB01")
        let hostPortID = uuid("00000000-0000-0000-0000-00000000AB02")
        let remoteID = uuid("00000000-0000-0000-0000-00000000AB03")
        let remotePortID = uuid("00000000-0000-0000-0000-00000000AB04")
        let snapshot = TopologyNetworkRuntimeTopologySnapshot(
            nodes: [
                pc(hostID, hostPortID),
                TopologyNetworkRuntimeNodeSnapshot(
                    id: remoteID,
                    kind: .remoteLink,
                    ports: [TopologyNetworkRuntimePortSnapshot(id: remotePortID, label: "remote0")]
                ),
            ],
            links: [link(hostID, hostPortID, remoteID, remotePortID)],
            deviceConfigurations: [hostID: device("10.0.0.1")],
            interfaceConfigurations: [:],
            manualRoutesByNodeID: [:],
            remoteLinkConfigurationsByNodeID: [remoteID: TopologyRemoteLinkConfiguration(
                pairIdentifier: "shared-production-link-code",
                latencyMilliseconds: 20,
                transportMode: .localNetwork,
                lanRole: .host
            )]
        )
        var engine = TopologyNetworkRuntimeEngine(seed: 99)
        engine.handle(.start(snapshot: snapshot, seed: 99, initialTimeMilliseconds: 0))
        engine.setLANRemoteLinkConnectionState(nodeID: remoteID, connectionState: .connected(peerName: "Peer iPad"))
        let frame = TopologyEthernetFrame(
            identity: engine.allocateFrameIdentity(),
            sourceMACAddress: TopologyNetworkRuntimeEngine.stableMACAddress(for: hostPortID),
            destinationMACAddress: TopologyNetworkRuntimeEngine.ethernetBroadcastMACAddress,
            payload: .arp(TopologyARPPacket(
                operation: .request,
                senderMACAddress: TopologyNetworkRuntimeEngine.stableMACAddress(for: hostPortID),
                senderIPAddress: "10.0.0.1",
                targetMACAddress: TopologyNetworkRuntimeEngine.unspecifiedMACAddress,
                targetIPAddress: "10.0.0.2"
            ))
        )
        return (engine, hostID, hostPortID, remoteID, frame)
    }

    private func sendRemoteLinkRecord(_ record: Data, over connection: NWConnection) async throws {
        var length = UInt32(record.count).bigEndian
        var framed = withUnsafeBytes(of: &length) { Data($0) }
        framed.append(record)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: framed, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receiveRemoteLinkRecord(over connection: NWConnection) async throws -> Data {
        let header = try await receiveRemoteLinkBytes(count: 4, over: connection)
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= UInt32(TopologyRemoteLinkWireCodec.maximumRecordBytes) else {
            throw TopologyRemoteLinkWireCodecError.recordTooLarge
        }
        return try await receiveRemoteLinkBytes(count: Int(length), over: connection)
    }

    private func receiveRemoteLinkBytes(count: Int, over connection: NWConnection) async throws -> Data {
        var received = Data()
        while received.count < count {
            let remaining = count - received.count
            let chunk = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, isComplete, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if isComplete {
                        continuation.resume(throwing: POSIXError(.ECONNRESET))
                    } else {
                        continuation.resume(throwing: POSIXError(.EIO))
                    }
                }
            }
            received.append(chunk)
        }
        return received
    }

    private func availableLoopbackPort() throws -> UInt16 {
        let socketDescriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else { throw POSIXError(.ENFILE) }
        defer { Darwin.close(socketDescriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(0).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EADDRINUSE) }
        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(socketDescriptor, $0, &length)
            }
        }
        guard nameResult == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL) }
        return UInt16(bigEndian: boundAddress.sin_port)
    }

    private func lanRemoteLinkHandshakes(
        linkCode: String
    ) -> (TopologyRemoteLinkWireHandshake, TopologyRemoteLinkWireHandshake) {
        let digest = TopologyRemoteLinkWireCodec.digest(for: linkCode)
        return (
            TopologyRemoteLinkWireHandshake(
                protocolVersion: TopologyRemoteLinkWireCodec.protocolVersion,
                linkDigest: digest,
                endpointID: uuid("00000000-0000-0000-0000-00000000E101"),
                endpointName: "Sender iPad",
                sessionID: uuid("00000000-0000-0000-0000-00000000E102"),
                challenge: Data(repeating: 0x71, count: TopologyRemoteLinkWireHandshake.challengeByteCount)
            ),
            TopologyRemoteLinkWireHandshake(
                protocolVersion: TopologyRemoteLinkWireCodec.protocolVersion,
                linkDigest: digest,
                endpointID: uuid("00000000-0000-0000-0000-00000000E201"),
                endpointName: "Receiver iPad",
                sessionID: uuid("00000000-0000-0000-0000-00000000E202"),
                challenge: Data(repeating: 0x72, count: TopologyRemoteLinkWireHandshake.challengeByteCount)
            )
        )
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}
