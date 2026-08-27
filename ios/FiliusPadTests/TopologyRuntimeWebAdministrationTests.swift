import XCTest

@testable import FiliusPad

final class TopologyRuntimeWebAdministrationTests: XCTestCase {
  func testAccessPolicyDefaultsDisabledAndUsesCanonicalNetworks() throws {
    let disabled = TopologyRuntimeWebAdministrationAccessPolicy()
    XCTAssertEqual(disabled.accessDecision(for: "192.168.1.4"), .disabled)

    let network = try TopologyRuntimeWebAdministrationIPv4Network(
      networkAddress: "192.168.1.77",
      subnetMask: "255.255.255.0"
    )
    XCTAssertEqual(network.networkAddress, "192.168.1.0")

    let enabled = TopologyRuntimeWebAdministrationAccessPolicy(
      isEnabled: true,
      allowedSourceNetworks: [network]
    )
    XCTAssertEqual(enabled.accessDecision(for: "192.168.1.254"), .allowed)
    XCTAssertEqual(enabled.accessDecision(for: "192.168.2.1"), .sourceDenied)
    XCTAssertEqual(enabled.accessDecision(for: "not-an-ip"), .invalidSourceAddress)
  }

  func testAccessPolicyRejectsNoncontiguousSubnetMask() {
    XCTAssertThrowsError(
      try TopologyRuntimeWebAdministrationIPv4Network(
        networkAddress: "10.0.0.0",
        subnetMask: "255.0.255.0"
      )
    )
  }

  func testRendererDeniesAccessBeforeRenderingState() throws {
    let response = TopologyRuntimeWebAdministrationRenderer.render(
      request: request(method: "GET", target: "/admin", source: "10.0.0.2"),
      policy: try allowedPolicy(network: "192.168.1.0", mask: "255.255.255.0"),
      snapshot: snapshot(deviceName: "Secret Router")
    )

    XCTAssertEqual(response.statusCode, 403)
    XCTAssertFalse(response.body.contains("Secret Router"))
  }

  func testRendererProducesEscapedDeterministicReadOnlyStatusPage() throws {
    let response = TopologyRuntimeWebAdministrationRenderer.render(
      request: request(method: "get", target: "/admin?refresh=1", source: "192.168.1.10"),
      policy: try allowedPolicy(),
      snapshot: snapshot(deviceName: #"Gateway <west> & "lab""#)
    )

    XCTAssertEqual(response.statusCode, 200)
    XCTAssertEqual(response.contentType, "text/html; charset=utf-8")
    XCTAssertTrue(response.body.contains("Gateway &lt;west&gt; &amp; &quot;lab&quot;"))
    XCTAssertFalse(response.body.contains("Gateway <west>"))
    XCTAssertTrue(response.body.contains("eth0"))
    XCTAssertTrue(response.body.contains("192.168.1.1"))
    XCTAssertTrue(response.body.contains("10000 ms"))
    XCTAssertFalse(response.body.lowercased().contains("password"))
    XCTAssertFalse(response.body.lowercased().contains("credential"))
    XCTAssertFalse(response.body.lowercased().contains("token"))
  }

  func testRendererProvidesRoutesDHCPNATAndFirewallPages() throws {
    let expectedTerms = [
      ("/admin/routes", "10.0.0.0"),
      ("/admin/dhcp", "Active leases"),
      ("/admin/nat", "Port forwards"),
      ("/admin/firewall", "Default policy"),
    ]

    for (target, term) in expectedTerms {
      let response = TopologyRuntimeWebAdministrationRenderer.render(
        request: request(method: "GET", target: target, source: "192.168.1.10"),
        policy: try allowedPolicy(),
        snapshot: snapshot()
      )
      XCTAssertEqual(response.statusCode, 200, target)
      XCTAssertTrue(response.body.contains(term), target)
    }
  }

  func testRendererSeparatesPageRenderingFromPOSTMutationActions() throws {
    let response = TopologyRuntimeWebAdministrationRenderer.render(
      request: request(method: "POST", target: "/admin/routes", source: "192.168.1.10"),
      policy: try allowedPolicy(),
      snapshot: snapshot()
    )

    XCTAssertEqual(response.statusCode, 405)
    XCTAssertTrue(response.body.contains("POST action endpoints"))

    let routesPage = TopologyRuntimeWebAdministrationRenderer.render(
      request: request(method: "GET", target: "/admin/routes", source: "192.168.1.10"),
      policy: try allowedPolicy(),
      snapshot: snapshot()
    )
    XCTAssertTrue(routesPage.body.contains(#"method="post""#))
    XCTAssertTrue(routesPage.body.contains(#"action="/admin/actions/routes/add""#))
  }

  func testHeadRequestReturnsHeadersWithoutBody() throws {
    let response = TopologyRuntimeWebAdministrationRenderer.render(
      request: request(method: "HEAD", target: "/admin/firewall", source: "192.168.1.10"),
      policy: try allowedPolicy(),
      snapshot: snapshot()
    )

    XCTAssertEqual(response.statusCode, 200)
    XCTAssertEqual(response.body, "")
  }

  func testMutationValidatorBuildsCanonicalRouteIntentWithoutApplyingIt() throws {
    let intent = try TopologyRuntimeWebAdministrationMutationValidator.validate(
      request: request(
        method: "POST",
        target: "/admin/actions/routes/add",
        source: "192.168.1.10",
        fields: [
          "id": " route-1 ",
          "destinationNetwork": "10.0.0.0",
          "subnetMask": "255.255.255.0",
          "gatewayIPAddress": "192.168.1.254",
          "interfaceIPAddress": "192.168.1.1",
        ]
      ),
      policy: try allowedPolicy()
    )

    XCTAssertEqual(
      intent,
      .addRoute(
        TopologyRuntimeWebAdministrationRouteMutation(
          id: "route-1",
          destinationNetwork: "10.0.0.0",
          subnetMask: "255.255.255.0",
          gatewayIPAddress: "192.168.1.254",
          interfaceIPAddress: "192.168.1.1"
        )
      )
    )
  }

  func testMutationValidatorBuildsDHCPAndNATIntents() throws {
    let policy = try allowedPolicy()
    let dhcp = try TopologyRuntimeWebAdministrationMutationValidator.validate(
      request: request(
        method: "POST",
        target: "/admin/actions/dhcp/update",
        source: "192.168.1.10",
        fields: [
          "isActive": "on",
          "lowerBoundIPAddress": "192.168.1.100",
          "upperBoundIPAddress": "192.168.1.199",
          "gatewayIPAddress": "192.168.1.1",
          "dnsServerIPAddress": "192.168.1.53",
          "usesOwnSettings": "true",
        ]
      ),
      policy: policy
    )
    XCTAssertEqual(
      dhcp,
      .updateDHCP(
        TopologyRuntimeWebAdministrationDHCPMutation(
          isActive: true,
          lowerBoundIPAddress: "192.168.1.100",
          upperBoundIPAddress: "192.168.1.199",
          gatewayIPAddress: "192.168.1.1",
          dnsServerIPAddress: "192.168.1.53",
          usesOwnSettings: true
        )
      )
    )

    let forward = try TopologyRuntimeWebAdministrationMutationValidator.validate(
      request: request(
        method: "POST",
        target: "/admin/actions/nat/port-forwards/add",
        source: "192.168.1.10",
        fields: [
          "id": "web",
          "protocol": "TCP",
          "publicPort": "8080",
          "lanIPAddress": "192.168.1.20",
          "lanPort": "80",
        ]
      ),
      policy: policy
    )
    XCTAssertEqual(
      forward,
      .addPortForward(
        TopologyRuntimeWebAdministrationPortForwardMutation(
          id: "web",
          protocolKind: .tcp,
          publicPort: 8080,
          lanIPAddress: "192.168.1.20",
          lanPort: 80
        )
      )
    )
  }

  func testMutationValidatorBuildsFirewallIntents() throws {
    let policy = try allowedPolicy()
    let settings = try TopologyRuntimeWebAdministrationMutationValidator.validate(
      request: request(
        method: "POST",
        target: "/admin/actions/firewall/update",
        source: "192.168.1.10",
        fields: [
          "isActive": "true",
          "defaultPolicy": "drop",
          "dropsICMP": "false",
          "filtersSYNSegmentsOnly": "true",
          "filtersUDP": "yes",
        ]
      ),
      policy: policy
    )
    XCTAssertEqual(
      settings,
      .updateFirewall(
        TopologyRuntimeWebAdministrationFirewallSettingsMutation(
          isActive: true,
          defaultPolicy: .drop,
          dropsICMP: false,
          filtersSYNSegmentsOnly: true,
          filtersUDP: true
        )
      )
    )

    let rule = try TopologyRuntimeWebAdministrationMutationValidator.validate(
      request: request(
        method: "POST",
        target: "/admin/actions/firewall/rules/add",
        source: "192.168.1.10",
        fields: [
          "id": "allow-dns",
          "sourceIPAddress": "0.0.0.0",
          "sourceSubnetMask": "0.0.0.0",
          "destinationIPAddress": "192.168.1.53",
          "destinationSubnetMask": "255.255.255.255",
          "port": "53",
          "protocol": "udp",
          "action": "accept",
        ]
      ),
      policy: policy
    )
    XCTAssertEqual(
      rule,
      .addFirewallRule(
        TopologyRuntimeWebAdministrationFirewallRuleMutation(
          id: "allow-dns",
          sourceIPAddress: "0.0.0.0",
          sourceSubnetMask: "0.0.0.0",
          destinationIPAddress: "192.168.1.53",
          destinationSubnetMask: "255.255.255.255",
          port: 53,
          protocolKind: .udp,
          action: .accept
        )
      )
    )
  }

  func testMutationValidatorRejectsUnauthorizedMethodUnknownAndUnexpectedFields() throws {
    let policy = try allowedPolicy()
    let validFields = [
      "destinationNetwork": "10.0.0.0",
      "subnetMask": "255.255.255.0",
      "gatewayIPAddress": "192.168.1.254",
      "interfaceIPAddress": "192.168.1.1",
    ]

    XCTAssertThrowsError(
      try TopologyRuntimeWebAdministrationMutationValidator.validate(
        request: request(
          method: "POST", target: "/admin/actions/routes/add", source: "10.0.0.2",
          fields: validFields),
        policy: policy
      )
    ) { error in
      XCTAssertEqual(
        error as? TopologyRuntimeWebAdministrationMutationError, .accessDenied(.sourceDenied))
    }
    XCTAssertThrowsError(
      try TopologyRuntimeWebAdministrationMutationValidator.validate(
        request: request(
          method: "GET", target: "/admin/actions/routes/add", source: "192.168.1.10",
          fields: validFields),
        policy: policy
      )
    ) { error in
      XCTAssertEqual(error as? TopologyRuntimeWebAdministrationMutationError, .methodNotAllowed)
    }
    XCTAssertThrowsError(
      try TopologyRuntimeWebAdministrationMutationValidator.validate(
        request: request(method: "POST", target: "/admin/actions/unknown", source: "192.168.1.10"),
        policy: policy
      )
    ) { error in
      XCTAssertEqual(error as? TopologyRuntimeWebAdministrationMutationError, .unknownAction)
    }
    var fieldsWithSecret = validFields
    fieldsWithSecret["password"] = "must-not-be-accepted"
    XCTAssertThrowsError(
      try TopologyRuntimeWebAdministrationMutationValidator.validate(
        request: request(
          method: "POST", target: "/admin/actions/routes/add", source: "192.168.1.10",
          fields: fieldsWithSecret),
        policy: policy
      )
    ) { error in
      XCTAssertEqual(
        error as? TopologyRuntimeWebAdministrationMutationError, .unexpectedFields(["password"]))
      XCTAssertFalse(error.localizedDescription.contains("must-not-be-accepted"))
    }
  }

  func testMutationValidatorRejectsInvalidRouteDHCPAndFirewallValues() throws {
    let policy = try allowedPolicy()
    XCTAssertThrowsError(
      try TopologyRuntimeWebAdministrationMutationValidator.validate(
        request: request(
          method: "POST",
          target: "/admin/actions/routes/add",
          source: "192.168.1.10",
          fields: [
            "destinationNetwork": "10.0.0.1",
            "subnetMask": "255.255.255.0",
            "gatewayIPAddress": "192.168.1.254",
            "interfaceIPAddress": "192.168.1.1",
          ]
        ),
        policy: policy
      )
    )
    XCTAssertThrowsError(
      try TopologyRuntimeWebAdministrationMutationValidator.validate(
        request: request(
          method: "POST",
          target: "/admin/actions/dhcp/update",
          source: "192.168.1.10",
          fields: [
            "isActive": "true",
            "lowerBoundIPAddress": "192.168.1.200",
            "upperBoundIPAddress": "192.168.1.100",
            "gatewayIPAddress": "192.168.1.1",
            "dnsServerIPAddress": "192.168.1.53",
            "usesOwnSettings": "false",
          ]
        ),
        policy: policy
      )
    ) { error in
      XCTAssertEqual(error as? TopologyRuntimeWebAdministrationMutationError, .invalidAddressRange)
    }
    XCTAssertThrowsError(
      try TopologyRuntimeWebAdministrationMutationValidator.validate(
        request: request(
          method: "POST",
          target: "/admin/actions/firewall/rules/add",
          source: "192.168.1.10",
          fields: [
            "id": "bad-port",
            "sourceIPAddress": "0.0.0.0",
            "sourceSubnetMask": "0.0.0.0",
            "destinationIPAddress": "0.0.0.0",
            "destinationSubnetMask": "0.0.0.0",
            "port": "0",
            "protocol": "tcp",
            "action": "drop",
          ]
        ),
        policy: policy
      )
    ) { error in
      XCTAssertEqual(error as? TopologyRuntimeWebAdministrationMutationError, .invalidField("port"))
    }
  }

  func testMutationValidatorRejectsPortForNonTransportFirewallProtocols() throws {
    XCTAssertThrowsError(
      try TopologyRuntimeWebAdministrationMutationValidator.validate(
        request: request(
          method: "POST",
          target: "/admin/actions/firewall/rules/add",
          source: "192.168.1.10",
          fields: [
            "id": "icmp-with-port",
            "sourceIPAddress": "0.0.0.0",
            "sourceSubnetMask": "0.0.0.0",
            "destinationIPAddress": "0.0.0.0",
            "destinationSubnetMask": "0.0.0.0",
            "port": "53",
            "protocol": "icmp",
            "action": "drop",
          ]
        ),
        policy: try allowedPolicy()
      )
    ) { error in
      XCTAssertEqual(
        error as? TopologyRuntimeWebAdministrationMutationError,
        .invalidField("port")
      )
    }
  }


  func testMutationResponseEscapesDetailAndReturnPath() {
    let response = TopologyRuntimeWebAdministrationRenderer.mutationResponse(
      statusCode: 200,
      title: "Applied",
      detail: #"route <script>alert(1)</script>"#,
      returnPath: #"/admin/routes" onclick="alert(2)"#
    )

    XCTAssertEqual(response.statusCode, 200)
    XCTAssertTrue(response.body.contains("route &lt;script&gt;alert(1)&lt;/script&gt;"))
    XCTAssertFalse(response.body.contains("<script>"))
    XCTAssertFalse(response.body.contains(#"onclick="alert(2)"#))
  }

  func testFormDecoderDecodesURLFormFieldsAndRejectsDuplicatesOrOversizedBodies() throws {
    let body = Data("destinationNetwork=10.0.0.0&interfaceIPAddress=192.168.1.1&note=hello+lab%21".utf8)
    let decoded = try XCTUnwrap(try? TopologyRuntimeWebAdministrationFormDecoder.decode(body).get())
    XCTAssertEqual(decoded["destinationNetwork"], "10.0.0.0")
    XCTAssertEqual(decoded["interfaceIPAddress"], "192.168.1.1")
    XCTAssertEqual(decoded["note"], "hello lab!")

    XCTAssertEqual(
      TopologyRuntimeWebAdministrationFormDecoder.decode(Data("id=one&id=two".utf8)),
      .failure(.duplicateField("id"))
    )
    XCTAssertEqual(
      TopologyRuntimeWebAdministrationFormDecoder.decode(
        Data(repeating: 0x61, count: TopologyRuntimeWebAdministrationFormDecoder.maximumBodyBytes + 1)
      ),
      .failure(.bodyTooLarge)
    )
  }

  func testAccessPolicyAndSnapshotRoundTripCodable() throws {
    let policy = try allowedPolicy()
    XCTAssertEqual(
      try JSONDecoder().decode(
        TopologyRuntimeWebAdministrationAccessPolicy.self,
        from: JSONEncoder().encode(policy)
      ),
      policy
    )
    let source = snapshot()
    XCTAssertEqual(
      try JSONDecoder().decode(
        TopologyRuntimeWebAdministrationSnapshot.self,
        from: JSONEncoder().encode(source)
      ),
      source
    )
  }

  func testCodableDecodingReappliesCanonicalOrderingAndRequestNormalization() throws {
    let policyData = Data(
      #"{"isEnabled":true,"allowedSourceNetworks":[{"networkAddress":"192.168.2.0","subnetMask":"255.255.255.0"},{"networkAddress":"192.168.1.0","subnetMask":"255.255.255.0"},{"networkAddress":"192.168.1.0","subnetMask":"255.255.255.0"}]}"#
        .utf8
    )
    let policy = try JSONDecoder().decode(
      TopologyRuntimeWebAdministrationAccessPolicy.self,
      from: policyData
    )
    XCTAssertEqual(
      policy.allowedSourceNetworks.map(\.networkAddress), ["192.168.1.0", "192.168.2.0"])

    let requestData = Data(
      #"{"method":" post ","target":"/admin/actions/nat/mappings/clear","sourceIPAddress":" 192.168.1.10 ","formFields":{}}"#
        .utf8
    )
    let request = try JSONDecoder().decode(
      TopologyRuntimeWebAdministrationRequest.self,
      from: requestData
    )
    XCTAssertEqual(request.method, "POST")
    XCTAssertEqual(request.sourceIPAddress, "192.168.1.10")
  }

  private func allowedPolicy(
    network: String = "192.168.1.0",
    mask: String = "255.255.255.0"
  ) throws -> TopologyRuntimeWebAdministrationAccessPolicy {
    TopologyRuntimeWebAdministrationAccessPolicy(
      isEnabled: true,
      allowedSourceNetworks: [
        try TopologyRuntimeWebAdministrationIPv4Network(
          networkAddress: network,
          subnetMask: mask
        )
      ]
    )
  }

  private func request(
    method: String,
    target: String,
    source: String,
    fields: [String: String] = [:]
  ) -> TopologyRuntimeWebAdministrationRequest {
    TopologyRuntimeWebAdministrationRequest(
      method: method,
      target: target,
      sourceIPAddress: source,
      formFields: fields
    )
  }

  private func snapshot(
    deviceName: String = "Gateway 1"
  ) -> TopologyRuntimeWebAdministrationSnapshot {
    TopologyRuntimeWebAdministrationSnapshot(
      deviceName: deviceName,
      deviceKind: "gateway",
      uptimeMilliseconds: 10_000,
      interfaces: [
        TopologyRuntimeWebAdministrationInterfaceStatus(
          name: "eth0",
          ipAddress: "192.168.1.1",
          subnetMask: "255.255.255.0",
          macAddress: "02:00:00:00:00:01",
          isUp: true
        )
      ],
      routes: [
        TopologyRuntimeWebAdministrationRouteStatus(
          id: "route-1",
          destinationNetwork: "10.0.0.0",
          subnetMask: "255.255.255.0",
          gatewayIPAddress: "192.168.1.254",
          interfaceIPAddress: "192.168.1.1"
        )
      ],
      dhcp: TopologyRuntimeWebAdministrationDHCPStatus(
        isActive: true,
        lowerBoundIPAddress: "192.168.1.100",
        upperBoundIPAddress: "192.168.1.199",
        gatewayIPAddress: "192.168.1.1",
        dnsServerIPAddress: "192.168.1.53",
        usesOwnSettings: true,
        activeLeaseCount: 3,
        staticAssignmentCount: 1
      ),
      natMappings: [
        TopologyRuntimeWebAdministrationNATMappingStatus(
          id: "nat-1",
          protocolName: "TCP",
          publicEndpoint: "203.0.113.1:12000",
          privateEndpoint: "192.168.1.20:443",
          state: "established"
        )
      ],
      portForwards: [
        TopologyRuntimeWebAdministrationPortForwardStatus(
          id: "web",
          protocolName: "TCP",
          publicPort: 8080,
          lanIPAddress: "192.168.1.20",
          lanPort: 80
        )
      ],
      firewall: TopologyRuntimeWebAdministrationFirewallStatus(
        isActive: true,
        defaultPolicy: "drop",
        dropsICMP: false,
        filtersSYNSegmentsOnly: true,
        filtersUDP: true,
        rules: [
          TopologyRuntimeWebAdministrationFirewallRuleStatus(
            id: "allow-dns",
            source: "0.0.0.0/0",
            destination: "192.168.1.53/32",
            protocolName: "UDP",
            port: "53",
            action: "accept"
          )
        ]
      )
    )
  }
}
