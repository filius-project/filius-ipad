import XCTest

@testable import FiliusPad

final class TopologyRuntimeWebVirtualHostsTests: XCTestCase {
  func testWebServerConfigurationValidationAcceptsCanonicalVirtualHosts() throws {
    let fallback = try host(
      id: "fallback",
      hostname: "default.test",
      root: "/srv/www/default"
    )
    let virtualHosts = try TopologyRuntimeWebVirtualHostConfiguration(
      hosts: [fallback],
      defaultHostID: fallback.id
    )
    let configuration = TopologyRuntimeWebServerConfiguration(
      port: 8_080,
      documentRoot: "/srv/www",
      virtualHostConfiguration: virtualHosts
    )

    XCTAssertNoThrow(try configuration.validate())
    let encoded = try JSONEncoder().encode(configuration)
    XCTAssertEqual(
      try JSONDecoder().decode(TopologyRuntimeWebServerConfiguration.self, from: encoded),
      configuration
    )
  }

  func testWebServerConfigurationValidationRejectsPortsOutsideTCPRange() {
    for port in [Int.min, -1, 0, 65_536, Int.max] {
      let configuration = TopologyRuntimeWebServerConfiguration(port: port)

      XCTAssertThrowsError(try configuration.validate(), "Accepted port \(port)") { error in
        XCTAssertEqual(error as? TopologyRuntimeWebVirtualHostError, .invalidPort(port))
      }
    }
  }

  func testWebServerConfigurationValidationRejectsUnsafeOrNonCanonicalDocumentRoots() {
    let roots = [
      "",
      "relative",
      " //server/share",
      "/srv/www/",
      "/srv/./www",
      "/srv/../secret",
      "/srv/%2e%2e/secret",
      "/srv\\secret",
      "/srv/\nsecret",
      "/" + String(repeating: "a", count: 4_096),
    ]

    for root in roots {
      let configuration = TopologyRuntimeWebServerConfiguration(documentRoot: root)

      XCTAssertThrowsError(try configuration.validate(), "Accepted document root \(root)") { error in
        XCTAssertEqual(
          error as? TopologyRuntimeWebVirtualHostError,
          .invalidDocumentRoot(root)
        )
      }
    }
  }

  func testWebServerConfigurationCodableRejectsInvalidMutableState() throws {
    let invalidConfiguration = TopologyRuntimeWebServerConfiguration(
      port: 80,
      documentRoot: "relative"
    )
    XCTAssertThrowsError(try JSONEncoder().encode(invalidConfiguration))

    for json in [
      #"{"port":0,"documentRoot":"/www"}"#,
      #"{"port":80,"documentRoot":"/www/"}"#,
    ] {
      XCTAssertThrowsError(
        try JSONDecoder().decode(
          TopologyRuntimeWebServerConfiguration.self,
          from: Data(json.utf8)
        ),
        "Decoded invalid configuration: \(json)"
      )
    }
  }

  func testVirtualHostNormalizesAuthorityAndDocumentRoot() throws {
    let host = try TopologyRuntimeWebVirtualHost(
      id: "  docs  ",
      hostname: "Docs.Example.TEST.",
      port: 8080,
      documentRoot: " /srv/./docs/ "
    )

    XCTAssertEqual(host.id, "docs")
    XCTAssertEqual(host.authority.hostname, "docs.example.test")
    XCTAssertEqual(host.authority.port, 8080)
    XCTAssertEqual(host.documentRoot, "/srv/docs")
  }

  func testConfigurationSortsDeterministicallyAndRoundTripsCodable() throws {
    let fallback = try host(id: "fallback", hostname: "default.test", root: "/www/default")
    let agnostic = try host(id: "agnostic", hostname: "site.test", root: "/www/site")
    let explicit = try host(
      id: "explicit", hostname: "site.test", port: 8080, root: "/www/site-8080")
    let configuration = try TopologyRuntimeWebVirtualHostConfiguration(
      hosts: [agnostic, fallback, explicit],
      defaultHostID: fallback.id
    )

    XCTAssertEqual(configuration.hosts.map(\.id), ["fallback", "explicit", "agnostic"])
    let data = try JSONEncoder().encode(configuration)
    XCTAssertEqual(
      try JSONDecoder().decode(TopologyRuntimeWebVirtualHostConfiguration.self, from: data),
      configuration)
  }

  func testConfigurationRejectsDuplicateNormalizedAuthorities() throws {
    let first = try host(id: "one", hostname: "SITE.TEST", root: "/one")
    let second = try host(id: "two", hostname: "site.test.", root: "/two")

    XCTAssertThrowsError(
      try TopologyRuntimeWebVirtualHostConfiguration(hosts: [first, second], defaultHostID: "one")
    ) { error in
      XCTAssertEqual(
        error as? TopologyRuntimeWebVirtualHostError,
        .duplicateAuthority(first.authority)
      )
    }
  }

  func testConfigurationRequiresAnEnabledExplicitDefault() throws {
    let disabled = try host(
      id: "disabled", hostname: "default.test", root: "/www", isEnabled: false)

    XCTAssertThrowsError(
      try TopologyRuntimeWebVirtualHostConfiguration(hosts: [disabled], defaultHostID: "disabled")
    ) { error in
      XCTAssertEqual(error as? TopologyRuntimeWebVirtualHostError, .defaultHostDisabled("disabled"))
    }
  }

  func testDispatcherPrefersPortSpecificThenPortAgnosticHost() throws {
    let fallback = try host(id: "fallback", hostname: "default.test", root: "/www/default")
    let anyPort = try host(id: "site", hostname: "site.test", root: "/www/site")
    let alternatePort = try host(
      id: "site-8080", hostname: "site.test", port: 8080, root: "/www/site-8080")
    let dispatcher = try makeDispatcher(
      hosts: [fallback, anyPort, alternatePort], defaultHostID: "fallback")

    let exact = try dispatcher.dispatch(hostHeader: "SITE.TEST:8080", listeningPort: 80)
    XCTAssertEqual(exact.host.id, "site-8080")
    XCTAssertEqual(exact.reason, .exactAuthority)

    let inheritedPort = try dispatcher.dispatch(hostHeader: "site.test", listeningPort: 8080)
    XCTAssertEqual(inheritedPort.host.id, "site-8080")

    let generic = try dispatcher.dispatch(hostHeader: "site.test:9090", listeningPort: 80)
    XCTAssertEqual(generic.host.id, "site")
  }

  func testDispatcherUsesDefaultForMissingUnknownDisabledHost() throws {
    let fallback = try host(id: "fallback", hostname: "default.test", root: "/www/default")
    let disabled = try host(
      id: "disabled", hostname: "private.test", root: "/www/private", isEnabled: false)
    let dispatcher = try makeDispatcher(hosts: [fallback, disabled], defaultHostID: "fallback")

    XCTAssertEqual(try dispatcher.dispatch(hostHeader: nil, listeningPort: 80).host.id, "fallback")
    XCTAssertEqual(
      try dispatcher.dispatch(hostHeader: "unknown.test", listeningPort: 80).host.id, "fallback")
    XCTAssertEqual(
      try dispatcher.dispatch(hostHeader: "private.test", listeningPort: 80).host.id, "fallback")
  }

  func testDispatcherRejectsMalformedHostHeaders() throws {
    let fallback = try host(id: "fallback", hostname: "default.test", root: "/www")
    let dispatcher = try makeDispatcher(hosts: [fallback], defaultHostID: "fallback")

    for header in [
      "site.test:0", "site.test:65536", "site.test/path", "user@site.test", "site.test,other.test",
      "[::1]",
    ] {
      XCTAssertThrowsError(
        try dispatcher.dispatch(hostHeader: header, listeningPort: 80), "Accepted \(header)")
    }
  }

  func testDocumentResolverReturnsCanonicalPathUnderRoot() throws {
    XCTAssertEqual(
      try TopologyRuntimeWebDocumentPathResolver.resolve(
        requestTarget: "/assets/./icons/?version=1",
        documentRoot: "/srv/www/",
        indexDocument: "home.html"
      ),
      TopologyRuntimeWebResolvedDocumentPath(
        documentRoot: "/srv/www",
        relativePath: "assets/icons/home.html",
        absolutePath: "/srv/www/assets/icons/home.html"
      )
    )
  }

  func testDocumentResolverRejectsTraversalIncludingEncodedAndRepeatedlyEncodedForms() {
    for target in ["/../secret", "/%2e%2e/secret", "/%252e%252e/secret", "/safe\\..\\secret"] {
      XCTAssertThrowsError(
        try TopologyRuntimeWebDocumentPathResolver.resolve(
          requestTarget: target,
          documentRoot: "/www"
        ),
        "Accepted traversal target \(target)"
      )
    }
  }

  func testTraversalErrorsDoNotEchoTheRejectedPath() {
    let target = "/../do-not-disclose"
    XCTAssertThrowsError(
      try TopologyRuntimeWebDocumentPathResolver.resolve(
        requestTarget: target,
        documentRoot: "/www"
      )
    ) { error in
      XCTAssertFalse(error.localizedDescription.contains("do-not-disclose"))
    }
  }

  func testDocumentResolverRejectsInvalidRootsAndTargets() {
    XCTAssertThrowsError(
      try TopologyRuntimeWebDocumentPathResolver.resolve(
        requestTarget: "relative", documentRoot: "/www")
    )
    XCTAssertThrowsError(
      try TopologyRuntimeWebDocumentPathResolver.resolve(
        requestTarget: "/", documentRoot: "relative")
    )
    XCTAssertThrowsError(
      try TopologyRuntimeWebDocumentPathResolver.resolve(
        requestTarget: "/", documentRoot: "/www/%2e%2e/secret")
    )
    XCTAssertThrowsError(
      try TopologyRuntimeWebDocumentPathResolver.resolve(
        requestTarget: "//server/share", documentRoot: "/www")
    )
  }

  func testDecodingRevalidatesVirtualHostInvariants() throws {
    let malformed = Data(
      #"{"id":"bad","authority":{"hostname":"site.test","port":80},"documentRoot":"/www/../secret","isEnabled":true}"#
        .utf8
    )
    XCTAssertThrowsError(
      try JSONDecoder().decode(TopologyRuntimeWebVirtualHost.self, from: malformed))
  }

  private func host(
    id: String,
    hostname: String,
    port: UInt16? = nil,
    root: String,
    isEnabled: Bool = true
  ) throws -> TopologyRuntimeWebVirtualHost {
    try TopologyRuntimeWebVirtualHost(
      id: id,
      hostname: hostname,
      port: port,
      documentRoot: root,
      isEnabled: isEnabled
    )
  }

  private func makeDispatcher(
    hosts: [TopologyRuntimeWebVirtualHost],
    defaultHostID: String
  ) throws -> TopologyRuntimeWebVirtualHostDispatcher {
    try TopologyRuntimeWebVirtualHostDispatcher(
      configuration: TopologyRuntimeWebVirtualHostConfiguration(
        hosts: hosts,
        defaultHostID: defaultHostID
      )
    )
  }
}
