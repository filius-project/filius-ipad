import CoreGraphics
import XCTest
@testable import FiliusPad

final class TopologyEditorDiagnosticsTests: XCTestCase {
    func testRejectedConnectAttemptExposesInspectableValidationCode() {
        var state = TopologyEditorState()

        let pcNodeID = addNode(kind: .pc, at: CGPoint(x: 40, y: 40), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: pcNodeID, portID: nil)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .completeConnection(nodeID: pcNodeID, portID: nil)
        )

        XCTAssertEqual(state.lastValidationError, .selfConnectionNotAllowed)
        XCTAssertEqual(state.lastValidationError?.rawValue, "selfConnectionNotAllowed")
        XCTAssertEqual(state.lastAction, "completeConnection")
        XCTAssertNotNil(state.lastActionAt)
    }

    func testOccupiedPortConnectAttemptKeepsGraphUnchangedAndTracksActionMetadata() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)
        let targetNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 220, y: 10), to: &state)

        connect(sourceNodeID, targetNodeID, state: &state)
        let snapshot = state.graph

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: targetNodeID, portID: nil)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .completeConnection(nodeID: sourceNodeID, portID: nil)
        )

        XCTAssertEqual(state.graph, snapshot)
        XCTAssertEqual(state.lastValidationError, .noFreePort)
        XCTAssertEqual(state.lastValidationError?.rawValue, "noFreePort")
        XCTAssertEqual(state.lastAction, "completeConnection")
        XCTAssertNotNil(state.lastActionAt)
    }

    func testSuccessfulConnectClearsPreviousValidationErrorAndKeepsInspectableCode() {
        var state = TopologyEditorState()

        let firstPCNodeID = addNode(kind: .pc, at: CGPoint(x: 40, y: 40), to: &state)
        let secondPCNodeID = addNode(kind: .pc, at: CGPoint(x: 160, y: 40), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: firstPCNodeID, portID: nil)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .completeConnection(nodeID: firstPCNodeID, portID: nil)
        )

        XCTAssertEqual(state.lastValidationError, .selfConnectionNotAllowed)
        XCTAssertEqual(state.lastValidationError?.rawValue, "selfConnectionNotAllowed")

        TopologyEditorReducer.reduce(
            state: &state,
            action: .completeConnection(nodeID: secondPCNodeID, portID: nil)
        )

        XCTAssertNil(state.lastValidationError)
        XCTAssertEqual(state.graph.links.count, 1)
        XCTAssertEqual(state.lastAction, "completeConnection")
        XCTAssertNotNil(state.lastActionAt)
    }

    func testSuccessfulActionClearsPreviousValidationError() {
        var state = TopologyEditorState()

        TopologyEditorReducer.reduce(state: &state, action: .selectNodes(in: nil))
        XCTAssertEqual(state.lastValidationError, .malformedActionPayload)

        let nodeID = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)
        TopologyEditorReducer.reduce(state: &state, action: .selectSingleNode(nodeID: nodeID))

        XCTAssertNil(state.lastValidationError)
        XCTAssertEqual(state.lastAction, "selectSingleNode")
        XCTAssertNotNil(state.lastActionAt)
    }

    func testRuntimeFaultIsInspectableAndPreservesPhaseAndTick() {
        var state = TopologyEditorState()

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .simulationTick(step: 2))

        let phaseSnapshot = state.simulationPhase
        let tickSnapshot = state.simulationTick

        TopologyEditorReducer.reduce(
            state: &state,
            action: .simulationFault(code: "runtimeDependencyDown", message: "scheduler queue unavailable")
        )

        XCTAssertEqual(state.simulationPhase, phaseSnapshot)
        XCTAssertEqual(state.simulationTick, tickSnapshot)
        XCTAssertEqual(state.lastRuntimeFault?.category, .runtimeFault)
        XCTAssertEqual(state.lastRuntimeFault?.code, "runtimeDependencyDown")
        XCTAssertEqual(state.lastRuntimeFault?.message, "scheduler queue unavailable")
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simulationFaultReported)
        XCTAssertEqual(state.lastRuntimeEvent?.detail, "runtimeDependencyDown")
        XCTAssertEqual(state.lastAction, "simulationFault")
    }

    func testMalformedRuntimeFaultPayloadDoesNotAdvanceTickAndUsesDeterministicFaultCode() {
        var state = TopologyEditorState()

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .simulationTick(step: 3))
        let phaseSnapshot = state.simulationPhase
        let tickSnapshot = state.simulationTick

        TopologyEditorReducer.reduce(
            state: &state,
            action: .simulationFault(code: nil, message: "ignored")
        )

        XCTAssertEqual(state.simulationPhase, phaseSnapshot)
        XCTAssertEqual(state.simulationTick, tickSnapshot)
        XCTAssertEqual(state.lastRuntimeFault?.category, .malformedRuntimePayload)
        XCTAssertEqual(state.lastRuntimeFault?.code, "malformedRuntimePayload")
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simulationFaultRejectedMalformedPayload)
        XCTAssertEqual(state.lastAction, "simulationFault")
    }

    func testRuntimeFaultThenRecoverClearsFaultOnNextStart() {
        var state = TopologyEditorState()

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .simulationFault(code: "runtimeDependencyDown", message: "temporary")
        )
        XCTAssertEqual(state.lastRuntimeFault?.category, .runtimeFault)

        TopologyEditorReducer.reduce(state: &state, action: .stopSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)

        XCTAssertEqual(state.simulationPhase, .running)
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simulationStarted)
        XCTAssertEqual(state.lastAction, "startSimulation")
    }

    func testPingMalformedCommandExposesInspectableFaultAndActionMetadata() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedMalformedCommand)
        XCTAssertEqual(state.lastPingEvent?.detail, "malformedPingCommand")
        XCTAssertEqual(state.lastPingFault?.category, .commandValidation)
        XCTAssertEqual(state.lastPingFault?.code, "malformedPingCommand")
        XCTAssertEqual(state.lastRuntimeEvent?.code, .pingRejectedMalformedCommand)
        XCTAssertEqual(state.lastAction, "executePing")
        XCTAssertTrue(state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.last?.contains("malformedPingCommand") ?? false)
    }

    func testEmptyRuntimeCommandPayloadRemainsInspectableAsMalformedPing() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "   "))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .pingRejectedMalformedCommand)
        XCTAssertEqual(state.lastRuntimeEvent?.detail, "malformedPingCommand")
        XCTAssertEqual(state.lastPingFault?.category, .commandValidation)
        XCTAssertEqual(state.lastPingFault?.code, "malformedPingCommand")
        XCTAssertTrue(state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.contains("/> (empty)") ?? false)
    }

    func testPingTopologyUnreachableExposesRoutingFailureWithoutMutatingIPAddressConfig() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 300, y: 20), to: &state)
        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "192.168.0.20", subnetMask: "255.255.255.0", state: &state)
        let sourceSnapshot = state.runtimeDeviceConfigurations[sourceNodeID]

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.0.20"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedTopologyUnreachable)
        XCTAssertEqual(state.lastPingEvent?.detail, "sameSubnetPathUnavailable")
        XCTAssertEqual(state.lastPingFault?.category, .networkRouting)
        XCTAssertEqual(state.lastPingFault?.code, "sameSubnetPathUnavailable")
        XCTAssertEqual(state.runtimeDeviceConfigurations[sourceNodeID], sourceSnapshot)
    }

    func testPingSuccessClearsPreviousPingFaultAndReportsAttributedDetail() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 300, y: 20), to: &state)
        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 160, y: 100), to: &state)

        connect(sourceNodeID, switchNodeID, state: &state)
        connect(targetNodeID, switchNodeID, state: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "192.168.0.20", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping"))
        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedMalformedCommand)

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.0.20"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingSucceeded)
        XCTAssertTrue(state.lastPingEvent?.detail?.contains("targetIP=192.168.0.20") ?? false)
        XCTAssertTrue(state.lastPingEvent?.detail?.contains("hops=") ?? false)
        XCTAssertTrue(state.lastPingEvent?.detail?.contains("latencyMs=") ?? false)
        XCTAssertTrue(state.lastPingEvent?.detail?.contains("path=") ?? false)
        XCTAssertNil(state.lastPingFault)
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .pingSucceeded)
    }

    func testTraceSuccessPublishesPathAwareRuntimeDiagnostics() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 160, y: 100), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 300, y: 20), to: &state)

        connect(sourceNodeID, switchNodeID, state: &state)
        connect(targetNodeID, switchNodeID, state: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "192.168.0.20", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "trace 192.168.0.20"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .traceSucceeded)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("command=trace") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("hops=2") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("path=") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("latencyMs=10") ?? false)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testUnsupportedRuntimeCommandUsesExplicitAttributableFault() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "nmap 192.168.0.20"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeCommandRejectedUnsupported)
        XCTAssertEqual(state.lastRuntimeFault?.category, .commandValidation)
        XCTAssertEqual(state.lastRuntimeFault?.code, "unsupportedRuntimeCommand")
        XCTAssertTrue(state.lastRuntimeFault?.message.contains("nmap") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("family=generic") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("token=nmap") ?? false)
    }

    func testRouteSuccessPublishesAttributedRuntimeRouteMetadata() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 160, y: 100), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 300, y: 20), to: &state)

        connect(sourceNodeID, switchNodeID, state: &state)
        connect(targetNodeID, switchNodeID, state: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.10.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "192.168.10.20", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "route 192.168.10.20"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .routeSucceeded)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("command=route") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("hops=2") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("path=") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("latencyMs=10") ?? false)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testHostAndNslookupCommandsPublishAttributedResolveDiagnostics() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let serverIPAddress = "192.168.10.53"

        startSelfResolvingDNSServer(nodeID: sourceNodeID, ipAddress: serverIPAddress, state: &state)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "dns add gateway.lab 192.168.10.1")
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsRecordRegistered)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "host gateway.lab")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .hostResolveSucceeded)
        XCTAssertEqual(
            state.lastRuntimeEvent?.detail,
            "command=host,host=gateway.lab,ip=192.168.10.1,server=\(serverIPAddress),cache=miss"
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "nslookup gateway.lab")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .hostResolveSucceeded)
        XCTAssertEqual(
            state.lastRuntimeEvent?.detail,
            "command=nslookup,host=gateway.lab,ip=192.168.10.1,server=\(serverIPAddress),cache=hit"
        )
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testHelpCommandPublishesDeterministicCatalogWithoutSimulation() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "help"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeHelpDisplayed)
        XCTAssertEqual(state.lastRuntimeEvent?.detail, "command=help;target=all")
        XCTAssertNil(state.lastRuntimeFault)

        let expectedSuffix = ["CMD help:"] + TopologyRuntimeCommandCatalog.helpLines
        XCTAssertEqual(Array(state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.suffix(expectedSuffix.count) ?? []), expectedSuffix)
    }

    func testHostResolveMalformedCommandPublishesDeterministicAttributableFault() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "host"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .hostResolveRejectedMalformedCommand)
        XCTAssertEqual(state.lastRuntimeEvent?.detail, "malformedHostResolveCommand")
        XCTAssertEqual(state.lastRuntimeFault?.category, .commandValidation)
        XCTAssertEqual(state.lastRuntimeFault?.code, "malformedHostResolveCommand")
        XCTAssertTrue(state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.last?.contains("malformedHostResolveCommand") ?? false)
    }

    func testHostResolveStoppedSimulationRetainsCommandTokenAttribution() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "nslookup gateway.lab"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .hostResolveRejectedSimulationStopped)
        XCTAssertEqual(state.lastRuntimeFault?.category, .runtimeFault)
        XCTAssertEqual(state.lastRuntimeFault?.code, "hostResolveWhileSimulationStopped")
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("phase=stopped") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("command=nslookup") ?? false)
    }

    func testHelpMalformedCommandPublishesInspectableCommandValidationFault() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "help extra"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeHelpRejectedMalformedCommand)
        XCTAssertEqual(state.lastRuntimeEvent?.detail, "malformedHelpCommand")
        XCTAssertEqual(state.lastRuntimeFault?.category, .commandValidation)
        XCTAssertEqual(state.lastRuntimeFault?.code, "malformedHelpCommand")
        XCTAssertTrue(state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.last?.contains("malformedHelpCommand") ?? false)
    }

    func testRouteHostnameSubstitutionFailurePublishesServiceAttribution() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        startSelfResolvingDNSServer(nodeID: sourceNodeID, ipAddress: "192.168.10.53", state: &state)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "route missing.lab"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .routeRejectedUnknownTarget)
        XCTAssertEqual(state.lastRuntimeEvent?.detail, "dnsNXDOMAIN")
        XCTAssertEqual(state.lastRuntimeFault?.category, .networkService)
        XCTAssertEqual(state.lastRuntimeFault?.code, "dnsNXDOMAIN")
        XCTAssertTrue(state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.last?.contains("dnsNXDOMAIN") ?? false)
    }

    func testUnsupportedRuntimeCommandTaxonomyIncludesFamilyAndTokenAttribution() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)

        let cases = [
            (command: "type file-a", token: "type", faultCode: "unsupportedRuntimeCommandFilesystem", family: "filesystem"),
            (command: "rmdir folder-a", token: "rmdir", faultCode: "unsupportedRuntimeCommandFilesystem", family: "filesystem"),
            (command: "nmap", token: "nmap", faultCode: "unsupportedRuntimeCommand", family: "generic"),
        ]

        for commandCase in cases {
            TopologyEditorReducer.reduce(
                state: &state,
                action: .executePing(nodeID: sourceNodeID, command: commandCase.command)
            )

            XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeCommandRejectedUnsupported)
            XCTAssertEqual(state.lastRuntimeFault?.category, .commandValidation)
            XCTAssertEqual(state.lastRuntimeFault?.code, commandCase.faultCode)
            XCTAssertEqual(
                state.lastRuntimeEvent?.detail,
                "unsupportedRuntimeCommand;token=\(commandCase.token);family=\(commandCase.family)"
            )
        }
    }

    func testDHCPAndDNSServiceCommandsPublishInspectableDiagnostics() {
        var state = TopologyEditorState()
        let dhcpNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let dnsNodeID = addNode(kind: .pc, at: CGPoint(x: 220, y: 20), to: &state)
        let dnsServerIPAddress = "10.40.0.53"

        startSelfResolvingDNSServer(nodeID: dnsNodeID, ipAddress: dnsServerIPAddress, state: &state)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: dhcpNodeID, command: "dhcp lease 10.40.0.10 255.255.255.0")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dhcpLeaseAssigned)
        XCTAssertEqual(state.runtimeDHCPLeaseByNodeID[dhcpNodeID]?.ipAddress, "10.40.0.10")

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: dnsNodeID, command: "dns add lab.local 10.40.0.44")
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsRecordRegistered)
        XCTAssertEqual(
            state.lastRuntimeEvent?.detail,
            "serverNode=\(dnsNodeID.uuidString),host=lab.local,ip=10.40.0.44"
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: dnsNodeID, command: "dns resolve lab.local")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsResolveSucceeded)
        XCTAssertEqual(
            state.lastRuntimeEvent?.detail,
            "host=lab.local,ip=10.40.0.44,server=\(dnsServerIPAddress),cache=miss"
        )
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertEqual(
            state.runtimeDNSServerConfigurationsByNodeID[dnsNodeID]?.recordsByHostname["lab.local"]?.targetIPAddress,
            "10.40.0.44"
        )
    }

    func testDNSResolveUnknownHostPublishesServiceFaultCategory() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        startSelfResolvingDNSServer(nodeID: sourceNodeID, ipAddress: "10.40.0.53", state: &state)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "dns resolve unknown.local")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsResolveRejectedUnknownHost)
        XCTAssertEqual(state.lastRuntimeEvent?.detail, "dnsNXDOMAIN,cache=miss")
        XCTAssertEqual(state.lastRuntimeFault?.category, .networkService)
        XCTAssertEqual(state.lastRuntimeFault?.code, "dnsNXDOMAIN")
    }

    func testDHCPReleaseAndDNSRemoveCommandsPublishInspectableDiagnostics() {
        var state = TopologyEditorState()
        let dhcpNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let dnsNodeID = addNode(kind: .pc, at: CGPoint(x: 220, y: 20), to: &state)

        startSelfResolvingDNSServer(nodeID: dnsNodeID, ipAddress: "10.40.0.53", state: &state)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: dhcpNodeID, command: "dhcp lease 10.40.0.10 255.255.255.0")
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: dhcpNodeID, command: "dhcp release")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dhcpLeaseReleased)
        XCTAssertNil(state.runtimeDHCPLeaseByNodeID[dhcpNodeID])

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: dnsNodeID, command: "dns add lab.local 10.40.0.44")
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsRecordRegistered)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: dnsNodeID, command: "dns remove lab.local")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsRecordRemoved)
        XCTAssertEqual(
            state.lastRuntimeEvent?.detail,
            "serverNode=\(dnsNodeID.uuidString),host=lab.local"
        )
        XCTAssertNil(state.runtimeDNSServerConfigurationsByNodeID[dnsNodeID]?.recordsByHostname["lab.local"])
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testHostnameCommandLookupFailuresPublishServiceFaults() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        startSelfResolvingDNSServer(nodeID: sourceNodeID, ipAddress: "10.10.0.53", state: &state)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "ping unresolved.local")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .pingRejectedUnknownTarget)
        XCTAssertEqual(state.lastRuntimeEvent?.detail, "dnsNXDOMAIN")
        XCTAssertEqual(state.lastRuntimeFault?.category, .networkService)
        XCTAssertEqual(state.lastRuntimeFault?.code, "dnsNXDOMAIN")

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "trace unresolved.local")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .traceRejectedUnknownTarget)
        XCTAssertEqual(state.lastRuntimeEvent?.detail, "dnsNXDOMAIN")
        XCTAssertEqual(state.lastRuntimeFault?.category, .networkService)
        XCTAssertEqual(state.lastRuntimeFault?.code, "dnsNXDOMAIN")
    }

    func testTraceTwentyNodeDiagnosticsContractPublishesDeterministicRouteWithoutTickMutation() {
        let phaseTag = "[M002/S03/T03 tests]"
        var state = TopologyEditorState()

        var pathNodeIDs: [UUID] = []
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        pathNodeIDs.append(sourceNodeID)

        for index in 1...18 {
            let switchNodeID = addNode(
                kind: .networkSwitch,
                at: CGPoint(x: CGFloat(20 + (index * 20)), y: index.isMultiple(of: 2) ? 20 : 120),
                to: &state
            )
            pathNodeIDs.append(switchNodeID)
        }

        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 420, y: 20), to: &state)
        pathNodeIDs.append(targetNodeID)

        for (source, destination) in zip(pathNodeIDs, pathNodeIDs.dropFirst()) {
            connect(source, destination, state: &state)
        }

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "10.30.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "10.30.0.20", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .simulationTick(step: 9))
        let tickSnapshot = state.simulationTick

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "trace 10.30.0.20"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .traceSucceeded, "\(phaseTag) expected trace success over 20-node diagnostics fixture")
        let detail = state.lastRuntimeEvent?.detail ?? ""
        let expectedPath = pathNodeIDs.map(\.uuidString).joined(separator: "->")

        XCTAssertTrue(detail.contains("command=trace"), "\(phaseTag) expected runtime event to include command attribution")
        XCTAssertTrue(detail.contains("targetIP=10.30.0.20"), "\(phaseTag) expected runtime event to include target attribution")
        XCTAssertTrue(detail.contains("hops=19"), "\(phaseTag) expected runtime event to include 19-hop depth metadata")
        XCTAssertTrue(detail.contains("latencyMs=78"), "\(phaseTag) expected runtime event to include deterministic latency metadata")
        XCTAssertTrue(detail.contains("path=\(expectedPath)"), "\(phaseTag) expected runtime event to include full path metadata")

        XCTAssertEqual(state.simulationTick, tickSnapshot, "\(phaseTag) trace command should not mutate simulation tick")
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertNil(state.lastPingEvent)
        XCTAssertNil(state.lastPingFault)
    }

    func testPersistenceFailureMetadataIsInspectableAndDismissible() {
        var state = TopologyEditorState()
        state.recordPersistenceFailure(
            operation: .load,
            code: .malformedPayload,
            detail: "Decoded snapshot failed validation"
        )

        XCTAssertEqual(state.lastPersistenceError?.operation, .load)
        XCTAssertEqual(state.lastPersistenceError?.code, .malformedPayload)
        XCTAssertEqual(state.lastPersistenceError?.detail, "Decoded snapshot failed validation")
        XCTAssertNotNil(state.lastPersistenceError?.occurredAt)

        TopologyEditorReducer.reduce(state: &state, action: .dismissPersistenceError)
        XCTAssertNil(state.lastPersistenceError)
    }

    func testPersistenceSaveAndLoadMetadataRemainInspectable() {
        var state = TopologyEditorState()
        state.persistenceRevision = 7

        state.recordPersistenceSave(revision: 7)
        XCTAssertEqual(state.lastPersistedRevision, 7)
        XCTAssertNotNil(state.lastPersistenceSaveAt)
        XCTAssertNil(state.lastPersistenceError)

        state.recordPersistenceLoad()
        XCTAssertNotNil(state.lastPersistenceLoadAt)
        XCTAssertEqual(state.lastPersistedRevision, 7)
        XCTAssertNil(state.lastPersistenceError)
    }

    func testRecoverySuccessMetadataIsInspectableAndDismissible() {
        var state = TopologyEditorState()

        state.recordRecoverySuccess(message: "Recovered autosave (revision: 9)")

        XCTAssertEqual(state.lastRecoveryMessage, "Recovered autosave (revision: 9)")
        XCTAssertEqual(state.lastRecoverySucceeded, true)
        XCTAssertTrue(state.isRecoveryNoticeVisible)
        XCTAssertNotNil(state.lastRecoveryAt)

        TopologyEditorReducer.reduce(state: &state, action: .dismissRecoveryNotice)
        XCTAssertFalse(state.isRecoveryNoticeVisible)
        XCTAssertEqual(state.lastAction, "dismissRecoveryNotice")
    }

    func testRecoveryFailureMetadataIsInspectableAndDismissible() {
        var state = TopologyEditorState()

        state.recordRecoveryFailure(message: "Recovery failed: malformedPayload")

        XCTAssertEqual(state.lastRecoveryMessage, "Recovery failed: malformedPayload")
        XCTAssertEqual(state.lastRecoverySucceeded, false)
        XCTAssertTrue(state.isRecoveryNoticeVisible)
        XCTAssertNotNil(state.lastRecoveryAt)

        TopologyEditorReducer.reduce(state: &state, action: .dismissRecoveryNotice)
        XCTAssertFalse(state.isRecoveryNoticeVisible)
        XCTAssertEqual(state.lastAction, "dismissRecoveryNotice")
    }

    func testWebAndEchoServiceLifecycleFailuresRemainInspectableFromAppShellActions() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .webServer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .webServer))

        TopologyEditorReducer.reduce(state: &state, action: .runtimeWebStart(nodeID: nodeID, port: "70000"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .webServerRejectedInvalidConfiguration)
        XCTAssertEqual(state.lastRuntimeFault?.category, .commandValidation)
        XCTAssertEqual(state.lastRuntimeFault?.code, "invalidWebServerPort")
        XCTAssertTrue(state.runtimeConsoleEntriesByNodeID[nodeID]?.last?.contains("invalidWebServerPort") ?? false)

        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .echoServer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .echoServer))
        TopologyEditorReducer.reduce(state: &state, action: .stopSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .runtimeEchoStart(nodeID: nodeID, port: "7000"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .echoServerRejectedSimulationStopped)
        XCTAssertEqual(state.lastRuntimeFault?.category, .runtimeFault)
        XCTAssertEqual(state.lastRuntimeFault?.code, "echoServerWhileSimulationStopped")
    }

    func testServiceAppMalformedInputsPublishAttributableFaultMetadata() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)

        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .dnsServer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .dnsServer))
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSAddRecord(nodeID: nodeID, hostname: "bad host", targetIPAddress: "10.20.0.22")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsRecordRejectedMalformedCommand)
        XCTAssertEqual(state.lastRuntimeFault?.category, .commandValidation)
        XCTAssertEqual(state.lastRuntimeFault?.code, "malformedDNSCommand")

        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .dhcpServer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .dhcpServer))
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDHCPLease(nodeID: nodeID, ipAddress: "10.20.0.50", subnetMask: "255.0.255.0")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dhcpLeaseRejectedMalformedCommand)
        XCTAssertEqual(state.lastRuntimeFault?.category, .commandValidation)
        XCTAssertEqual(state.lastRuntimeFault?.code, "malformedDHCPCommand")

        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .echoServer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .echoServer))
        TopologyEditorReducer.reduce(state: &state, action: .runtimeEchoStart(nodeID: nodeID, port: "70000"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .echoServerRejectedInvalidConfiguration)
        XCTAssertEqual(state.lastRuntimeFault?.category, .commandValidation)
        XCTAssertEqual(state.lastRuntimeFault?.code, "invalidEchoServerPort")
    }

    func testServiceAppErrorPathsAndInvalidLifecycleTransitionsRemainInspectable() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .dnsServer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .dnsServer))

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeDNSRemoveRecord(nodeID: nodeID, hostname: "missing.lab")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsRecordRejectedUnknownHost)
        XCTAssertEqual(state.lastRuntimeFault?.category, .networkService)
        XCTAssertEqual(state.lastRuntimeFault?.code, "dnsUnknownHost")

        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .dhcpServer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .dhcpServer))
        TopologyEditorReducer.reduce(state: &state, action: .runtimeDHCPRelease(nodeID: nodeID))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dhcpLeaseRejectedMissingLease)
        XCTAssertEqual(state.lastRuntimeFault?.category, .networkService)
        XCTAssertEqual(state.lastRuntimeFault?.code, "dhcpLeaseMissing")

        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .webServer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .webServer))
        TopologyEditorReducer.reduce(state: &state, action: .runtimeWebStop(nodeID: nodeID))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .webServerStopIgnoredAlreadyStopped)
        XCTAssertNil(state.lastRuntimeFault)

        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .echoServer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .echoServer))
        TopologyEditorReducer.reduce(state: &state, action: .runtimeEchoStop(nodeID: nodeID))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .echoServerStopIgnoredAlreadyStopped)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testDesktopSuiteSuccessDiagnosticsAreAttributedAndDoNotExposeHostPaths() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: nodeID))
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .fileExplorer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .fileExplorer))
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeFileExplorerSelectEntry(nodeID: nodeID, entryID: "runtime-events.log")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeFileExplorerSelectionChanged)
        XCTAssertEqual(state.lastRuntimeEvent?.detail, "node=\(nodeID.uuidString),entry=/var/log/runtime-events.log")
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertFalse(state.lastRuntimeEvent?.detail?.contains("C:\\") ?? true)
        XCTAssertFalse(state.lastRuntimeEvent?.detail?.contains("/Users/") ?? true)

        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .imageViewer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .imageViewer))
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeImageViewerSelectImage(nodeID: nodeID, imageID: "traffic-heatmap.png")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeImageViewerSelectionChanged)
        XCTAssertEqual(state.lastRuntimeEvent?.detail, "node=\(nodeID.uuidString),image=/images/traffic-heatmap.png")
        XCTAssertNil(state.lastRuntimeFault)

        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .textEditor))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .textEditor))
        TopologyEditorReducer.reduce(state: &state, action: .runtimeTextEditorUpdateDraft(nodeID: nodeID, text: "Parity note"))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeTextEditorDraftUpdated)
        XCTAssertEqual(state.lastRuntimeEvent?.detail, "node=\(nodeID.uuidString),chars=11")

        TopologyEditorReducer.reduce(state: &state, action: .runtimeTextEditorSaveDraft(nodeID: nodeID))
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeTextEditorDraftSaved)
        XCTAssertEqual(state.lastRuntimeEvent?.detail, "node=\(nodeID.uuidString),path=/home/lab-notes.txt,chars=11")
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testDesktopSuiteFailureDiagnosticsIdentifyTrustBoundaryReasonAndPayloadClass() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 40, y: 40), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeFileExplorerSelectEntry(nodeID: nodeID, entryID: "lab-notes.txt")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDesktopAppActionRejectedInvalidContext)
        XCTAssertEqual(
            state.lastRuntimeEvent?.detail,
            "action=runtimeFileExplorerSelectEntry,reason=simulationNotRunning,program=fileExplorer"
        )
        XCTAssertEqual(state.lastRuntimeFault?.category, .commandValidation)
        XCTAssertEqual(state.lastRuntimeFault?.code, "runtimeDesktopAppSimulationNotRunning")

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: nodeID))
        TopologyEditorReducer.reduce(state: &state, action: .installRuntimeProgram(nodeID: nodeID, program: .fileExplorer))
        TopologyEditorReducer.reduce(state: &state, action: .launchRuntimeProgram(nodeID: nodeID, program: .fileExplorer))
        TopologyEditorReducer.reduce(
            state: &state,
            action: .runtimeFileExplorerSelectEntry(nodeID: nodeID, entryID: "../../host-secret")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDesktopAppActionRejectedUnknownTarget)
        XCTAssertEqual(
            state.lastRuntimeEvent?.detail,
            "action=runtimeFileExplorerSelectEntry,reason=unknownFileEntry,targetLength=17"
        )
        XCTAssertEqual(state.lastRuntimeFault?.category, .commandValidation)
        XCTAssertEqual(state.lastRuntimeFault?.code, "runtimeDesktopAppUnknownTarget")
        XCTAssertFalse(state.lastRuntimeFault?.message.contains("C:\\") ?? true)
        XCTAssertFalse(state.lastRuntimeFault?.message.contains("/Users/") ?? true)
    }
    func testRemoteLinkVisualStateDescribesPairingAndDisabledConditions() {
        var state = TopologyEditorState()
        let first = addNode(kind: .remoteLink, at: CGPoint(x: 40, y: 40), to: &state)
        let second = addNode(kind: .remoteLink, at: CGPoint(x: 160, y: 40), to: &state)
        let third = addNode(kind: .remoteLink, at: CGPoint(x: 280, y: 40), to: &state)

        XCTAssertEqual(state.remoteLinkVisualState(for: first), .unpaired)
        XCTAssertNil(state.remoteLinkVisualState(for: UUID()))

        state.remoteLinkConfigurationsByNodeID[first] = TopologyRemoteLinkConfiguration(pairIdentifier: "classroom-a")
        state.remoteLinkConfigurationsByNodeID[second] = TopologyRemoteLinkConfiguration(pairIdentifier: "classroom-a")
        XCTAssertEqual(state.remoteLinkVisualState(for: first), .active)
        XCTAssertEqual(state.remoteLinkVisualState(for: second), .active)

        state.remoteLinkConfigurationsByNodeID[third] = TopologyRemoteLinkConfiguration(pairIdentifier: "classroom-a")
        XCTAssertEqual(state.remoteLinkVisualState(for: first), .ambiguous)

        state.remoteLinkConfigurationsByNodeID[first]?.isEnabled = false
        XCTAssertEqual(state.remoteLinkVisualState(for: first), .disabled)
        XCTAssertEqual(state.remoteLinkVisualState(for: second), .active)
    }

    // MARK: - Helpers

    @discardableResult
    private func addNode(kind: TopologyNodeKind, at position: CGPoint, to state: inout TopologyEditorState) -> UUID {
        let nodeID = UUID()
        TopologyEditorReducer.reduce(state: &state, action: .placeNode(kind: kind, at: position, nodeID: nodeID))
        return nodeID
    }

    private func connect(_ sourceNodeID: UUID, _ targetNodeID: UUID, state: inout TopologyEditorState) {
        TopologyEditorReducer.reduce(state: &state, action: .startConnection(nodeID: sourceNodeID, portID: nil))
        TopologyEditorReducer.reduce(state: &state, action: .completeConnection(nodeID: targetNodeID, portID: nil))
        XCTAssertNil(state.lastValidationError)
    }

    private func startSelfResolvingDNSServer(
        nodeID: UUID,
        ipAddress: String,
        state: inout TopologyEditorState
    ) {
        state.runtimeDeviceConfigurations[nodeID] = TopologyRuntimeDeviceConfiguration(
            ipAddress: ipAddress,
            subnetMask: "255.255.255.0",
            dnsServer: ipAddress
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .installRuntimeProgram(nodeID: nodeID, program: .dnsServer)
        )
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: nodeID))
        TopologyEditorReducer.reduce(
            state: &state,
            action: .launchRuntimeProgram(nodeID: nodeID, program: .dnsServer)
        )
        TopologyEditorReducer.reduce(state: &state, action: .runtimeDNSStart(nodeID: nodeID))

        XCTAssertEqual(state.runtimeDeviceConfigurations[nodeID]?.dnsServer, ipAddress)
        XCTAssertTrue(state.runtimeInstalledProgramsByNodeID[nodeID]?.contains(.dnsServer) == true)
        XCTAssertNotNil(state.runtimeDNSServerSocketIDByNodeID[nodeID])
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsServerStarted)
        XCTAssertEqual(
            state.lastRuntimeEvent?.detail,
            "node=\(nodeID.uuidString),ip=\(ipAddress),port=53"
        )
        XCTAssertNil(state.lastRuntimeFault)
    }

    private func saveRuntimeIP(
        nodeID: UUID,
        ipAddress: String,
        subnetMask: String,
        state: inout TopologyEditorState
    ) {
        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeDeviceIP(nodeID: nodeID, ipAddress: ipAddress, subnetMask: subnetMask)
        )
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceIPSaved)
    }
}

final class TopologyDesignDeviceConfigurationDraftTests: XCTestCase {
    func testEndpointDraftTracksDirtyStateAndValidatesAddressFields() throws {
        let nodeID = UUID()
        let node = TopologyNode(id: nodeID, kind: .pc, position: CGPoint(x: 40, y: 40))
        let configuration = TopologyRuntimeDeviceConfiguration(
            ipAddress: "192.168.0.10",
            subnetMask: "255.255.255.0"
        )
        let baseline = TopologyDesignDeviceConfigurationDraft(
            node: node,
            deviceConfiguration: configuration,
            interfaceConfigurations: [],
            switchConfiguration: nil,
            remoteLinkConfiguration: nil,
            hostWirelessConfiguration: TopologyHostWirelessConfiguration(),
            availableSSIDs: []
        )

        XCTAssertTrue(baseline.isValid(for: node, availableSSIDs: []))
        var edited = baseline
        edited.displayName += " edited"
        XCTAssertNotEqual(edited, baseline)
        edited.ipAddress = "999.1.1.1"
        XCTAssertFalse(edited.isValid(for: node, availableSSIDs: []))
    }

    func testRemoteLinkDraftNormalizesSavedPairAndLatency() throws {
        let nodeID = UUID()
        let node = TopologyNode(id: nodeID, kind: .remoteLink, position: CGPoint(x: 40, y: 40))
        var draft = TopologyDesignDeviceConfigurationDraft(
            node: node,
            deviceConfiguration: nil,
            interfaceConfigurations: [],
            switchConfiguration: nil,
            remoteLinkConfiguration: .defaultConfiguration(nodeID: nodeID),
            hostWirelessConfiguration: TopologyHostWirelessConfiguration(),
            availableSSIDs: []
        )
        draft.remoteLinkPairIdentifier = "  classroom-a  "
        draft.remoteLinkLatencyMilliseconds = "125"
        draft.remoteLinkEnabled = true

        XCTAssertTrue(draft.isValid(for: node, availableSSIDs: []))
        let saved = try XCTUnwrap(draft.remoteLinkConfiguration(for: node))
        XCTAssertEqual(saved.pairIdentifier, "classroom-a")
        XCTAssertEqual(saved.latencyMilliseconds, 125)
        XCTAssertTrue(saved.isEnabled)
    }
}

final class TopologyDenseLayoutPolicyTests: XCTestCase {
    func testDenseDataPresentationUsesCompactLayoutAtMultitaskingWidth() {
        XCTAssertTrue(TopologyDenseLayoutPolicy.usesCompactPresentation(width: 512))
        XCTAssertFalse(TopologyDenseLayoutPolicy.usesCompactPresentation(width: 760))
        XCTAssertFalse(TopologyDenseLayoutPolicy.usesCompactPresentation(width: 1_024))
    }
}

final class TopologyAppPreferencesTests: XCTestCase {
    func testExperimentalProtocolApplicationsAreDisabledByDefault() {
        XCTAssertFalse(TopologyAppPreferences.defaults.experimentalProtocolApplicationsEnabled)
        XCTAssertFalse(TopologyAppPreferences().experimentalProtocolApplicationsEnabled)
    }

    func testLegacyPreferencesWithoutExperimentalGateDecodeAsDisabled() throws {
        let preferences = try JSONDecoder().decode(
            TopologyAppPreferences.self,
            from: Data("{}".utf8)
        )

        XCTAssertFalse(preferences.experimentalProtocolApplicationsEnabled)
    }

    func testGuidedTourIsIncompleteForDefaultsAndLegacyPreferences() throws {
        XCTAssertFalse(TopologyAppPreferences.defaults.hasCompletedGuidedTour)
        let legacy = try JSONDecoder().decode(TopologyAppPreferences.self, from: Data("{}".utf8))
        XCTAssertFalse(legacy.hasCompletedGuidedTour)
    }

    func testGuidedTourCompletionRoundTrips() throws {
        let preferences = TopologyAppPreferences(hasCompletedGuidedTour: true)
        let decoded = try JSONDecoder().decode(TopologyAppPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertTrue(decoded.hasCompletedGuidedTour)
    }

    func testExperimentalProtocolApplicationPreferenceRoundTrips() throws {
        let preferences = TopologyAppPreferences(experimentalProtocolApplicationsEnabled: true)
        let encoded = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(TopologyAppPreferences.self, from: encoded)

        XCTAssertTrue(decoded.experimentalProtocolApplicationsEnabled)
    }
}

final class TopologyParityAssetLoaderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TopologyParityAssetLoader.resetCacheForTesting()
    }

    func testLoadedParityAssetIsCached() throws {
        let relativePath = "hardware/router.png"

        let first = try XCTUnwrap(TopologyParityAssetLoader.load(relativePath: relativePath))
        let second = try XCTUnwrap(TopologyParityAssetLoader.load(relativePath: relativePath))

        XCTAssertTrue(first === second)
        XCTAssertEqual(
            TopologyParityAssetLoader.decodeAttemptCountForTesting(relativePath: relativePath),
            1
        )
    }

    func testMissingParityAssetIsNegativelyCached() {
        let relativePath = "missing/not-present.png"

        XCTAssertNil(TopologyParityAssetLoader.load(relativePath: relativePath))
        XCTAssertNil(TopologyParityAssetLoader.load(relativePath: relativePath))
        XCTAssertEqual(
            TopologyParityAssetLoader.decodeAttemptCountForTesting(relativePath: relativePath),
            1
        )
    }
}

@MainActor
final class TopologyEditorUndoCoordinatorTests: XCTestCase {
    private final class StateBox {
        var state = TopologyEditorState()
    }

    func testUndoAndRedoRestoreDocumentChangesWhilePreservingViewport() {
        let box = StateBox()
        let coordinator = configuredCoordinator(box: box)
        box.state.viewport = ViewportTransform(offset: CGSize(width: 40, height: -25), scale: 1.5)

        let before = box.state
        TopologyEditorReducer.reduce(
            state: &box.state,
            action: .placeNode(kind: .pc, at: CGPoint(x: 120, y: 80), nodeID: UUID())
        )
        coordinator.record(before: before, actionName: "Place Device")

        box.state.viewport = ViewportTransform(offset: CGSize(width: -10, height: 75), scale: 2)
        let currentViewport = box.state.viewport
        let revisionBeforeUndo = box.state.persistenceRevision

        coordinator.undo()

        XCTAssertTrue(box.state.graph.nodes.isEmpty)
        XCTAssertEqual(box.state.viewport, currentViewport)
        XCTAssertGreaterThan(box.state.persistenceRevision, revisionBeforeUndo)
        XCTAssertEqual(box.state.lastAction, "undo")
        XCTAssertTrue(coordinator.canRedo)

        coordinator.redo()

        XCTAssertEqual(box.state.graph.nodes.count, 1)
        XCTAssertEqual(box.state.viewport, currentViewport)
        XCTAssertEqual(box.state.lastAction, "redo")
    }

    func testUndoHistoryIsBounded() {
        let box = StateBox()
        let coordinator = configuredCoordinator(box: box, limit: 2)

        for index in 0..<3 {
            let before = box.state
            TopologyEditorReducer.reduce(
                state: &box.state,
                action: .placeNode(
                    kind: .pc,
                    at: CGPoint(x: CGFloat(index * 40), y: 0),
                    nodeID: UUID()
                )
            )
            coordinator.record(before: before, actionName: "Place Device")
        }

        coordinator.undo()
        coordinator.undo()

        XCTAssertEqual(box.state.graph.nodes.count, 1)
        XCTAssertFalse(coordinator.canUndo)
    }

    func testGroupedNodeMovementUndoesAsOneOperation() throws {
        let box = StateBox()
        let nodeID = UUID()
        TopologyEditorReducer.reduce(
            state: &box.state,
            action: .placeNode(kind: .pc, at: CGPoint(x: 20, y: 30), nodeID: nodeID)
        )
        let originalPosition = try XCTUnwrap(box.state.graph.node(withID: nodeID)?.position)
        let coordinator = configuredCoordinator(box: box)

        coordinator.beginGrouping()
        for delta in [CGSize(width: 5, height: 0), CGSize(width: 7, height: 3)] {
            let before = box.state
            TopologyEditorReducer.reduce(state: &box.state, action: .moveSelectedNodes(delta: delta))
            coordinator.record(before: before, actionName: "Move Device")
        }
        coordinator.endGrouping(actionName: "Move Device")

        coordinator.undo()

        XCTAssertEqual(box.state.graph.node(withID: nodeID)?.position, originalPosition)
        XCTAssertFalse(coordinator.canUndo)
    }

    func testNewEditAfterUndoClearsRedoHistory() {
        let box = StateBox()
        let coordinator = configuredCoordinator(box: box)

        let firstBefore = box.state
        TopologyEditorReducer.reduce(
            state: &box.state,
            action: .placeNode(kind: .pc, at: .zero, nodeID: UUID())
        )
        coordinator.record(before: firstBefore, actionName: "Place Device")
        coordinator.undo()
        XCTAssertTrue(coordinator.canRedo)

        let replacementBefore = box.state
        TopologyEditorReducer.reduce(
            state: &box.state,
            action: .placeNode(kind: .notebook, at: .zero, nodeID: UUID())
        )
        coordinator.record(before: replacementBefore, actionName: "Place Device")

        XCTAssertFalse(coordinator.canRedo)
    }

    func testUndoActionPolicyExcludesRuntimeAndViewportActions() {
        XCTAssertNil(TopologyEditorAction.simulationTick(step: 1).undoActionNameKey)
        XCTAssertNil(TopologyEditorAction.panCanvas(delta: CGSize(width: 2, height: 3)).undoActionNameKey)
        XCTAssertNil(TopologyEditorAction.zoomCanvas(scaleDelta: 1.2, anchor: .zero).undoActionNameKey)
        XCTAssertNotNil(TopologyEditorAction.placeNode(kind: .pc, at: .zero, nodeID: UUID()).undoActionNameKey)
        XCTAssertNotNil(TopologyEditorAction.saveDesignDeviceConfiguration(
            nodeID: UUID(),
            displayName: "PC",
            deviceConfiguration: nil,
            interfaceConfigurations: nil,
            switchConfiguration: nil,
            remoteLinkConfiguration: nil,
            hostWirelessConfiguration: nil
        ).undoActionNameKey)
    }

    private func configuredCoordinator(
        box: StateBox,
        limit: Int = 20
    ) -> TopologyEditorUndoCoordinator {
        let coordinator = TopologyEditorUndoCoordinator(limit: limit)
        coordinator.configure(
            currentState: { box.state },
            replaceState: { box.state = $0 }
        )
        return coordinator
    }
}
