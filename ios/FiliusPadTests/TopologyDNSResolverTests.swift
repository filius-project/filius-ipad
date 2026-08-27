import XCTest

@testable import FiliusPad

final class TopologyDNSResolverTests: XCTestCase {
  func testDNSNameAndIPv4NormalizationRejectMalformedInput() {
    XCTAssertEqual(
      TopologyDNSName(rawValue: "  WWW.Example.COM... \n")?.rawValue, "www.example.com")
    XCTAssertEqual(TopologyDNSName(rawValue: ".")?.absoluteString, ".")
    XCTAssertNil(TopologyDNSName(rawValue: "bad..example"))
    XCTAssertNil(TopologyDNSName(rawValue: "-bad.example"))
    XCTAssertNil(TopologyDNSName(rawValue: "bad_name.example"))

    XCTAssertEqual(TopologyDNSIPv4Address(rawValue: "010.000.001.255")?.rawValue, "10.0.1.255")
    XCTAssertNil(TopologyDNSIPv4Address(rawValue: "10.0.0.256"))
    XCTAssertNil(TopologyDNSIPv4Address(rawValue: "10.0.0"))
  }

  func testTypedRecordsRoundTripThroughCodable() throws {
    let records = [
      record("www.school.local", .address, "10.0.0.20", ttl: 120),
      record("school.local", .mailExchange, "mail.school.local", ttl: 300),
      record("school.local", .nameServer, "ns.school.local", ttl: 600),
    ]

    let encoded = try JSONEncoder().encode(records)
    let decoded = try JSONDecoder().decode([TopologyDNSResourceRecord].self, from: encoded)

    XCTAssertEqual(decoded, records)
    XCTAssertEqual(decoded.map(\.type), [.address, .mailExchange, .nameServer])
    XCTAssertEqual(decoded.map(\.target), ["10.0.0.20", "mail.school.local.", "ns.school.local."])
  }

  func testHostsFileCodecParsesJavaAndConventionalRecordOrdering() {
    let text = """
      # classroom zone
      WWW.School.Local. A 60 010.000.000.020
      school.local. MX 300 mail.school.local.
      school.local. 600 IN NS ns.school.local.
      ns.school.local. 600 IN A 10.0.0.53
      invalid record
      """

    let records = TopologyDNSHostsFileCodec.records(from: text)

    XCTAssertEqual(records.count, 4)
    XCTAssertEqual(
      records.map(\.name.rawValue),
      [
        "www.school.local",
        "school.local",
        "school.local",
        "ns.school.local",
      ])
    XCTAssertEqual(records.map(\.type), [.address, .mailExchange, .nameServer, .address])
    XCTAssertEqual(records.first?.target, "10.0.0.20")
  }

  func testHostsFileCodecPreservesUnknownLinesAndWritesCanonicalTypedRecords() {
    let existing = """
      # keep this classroom note
      school.local. MX 120 old-mail.school.local.
      custom extension line
      """
    let records = [
      record("school.local", .mailExchange, "mail.school.local", ttl: 300),
      record("mail.school.local", .address, "10.0.0.25", ttl: 300),
    ]

    let rendered = TopologyDNSHostsFileCodec.text(mirroring: records, preserving: existing)

    XCTAssertEqual(
      rendered,
      """
      # keep this classroom note
      custom extension line
      school.local. MX 300 mail.school.local.
      mail.school.local. A 300 10.0.0.25

      """
    )
  }

  func testHostsFileCodecPreservesJavaRecordOrderWhenAppendingRecords() {
    let records = [
      record("school.local", .mailExchange, "z-mail.school.local", ttl: 300),
      record("school.local", .mailExchange, "a-mail.school.local", ttl: 300),
      record("z-mail.school.local", .address, "10.0.0.40", ttl: 300),
      record("a-mail.school.local", .address, "10.0.0.41", ttl: 300),
    ]

    let rendered = TopologyDNSHostsFileCodec.text(mirroring: records, preserving: "")

    XCTAssertEqual(TopologyDNSHostsFileCodec.records(from: rendered), records)
  }

  func testLegacyARecordAdaptersPreserveExistingRuntimeAPI() {
    let legacy = TopologyRuntimeDNSServerConfiguration(recordsByHostname: [
      "www.school.local": TopologyRuntimeDNSRecord(
        hostname: "www.school.local",
        targetIPAddress: "10.0.0.20"
      )
    ])

    XCTAssertEqual(legacy.typedARecords, [record("www.school.local", .address, "10.0.0.20")])

    let adapted = TopologyRuntimeDNSServerConfiguration(typedARecords: [
      record("school.local", .mailExchange, "mail.school.local"),
      record("www.school.local", .address, "10.0.0.20"),
    ])
    XCTAssertEqual(adapted.recordsByHostname, legacy.recordsByHostname)
  }

  func testRuntimeConfigurationPreservesMultipleAddressRecordsAndJavaFileOrder() {
    let records = [
      record("service.school.local", .address, "10.0.0.20", ttl: 120),
      record("school.local", .mailExchange, "mail.school.local", ttl: 300),
      record("service.school.local", .address, "10.0.0.21", ttl: 180),
      record("school.local", .nameServer, "ns.school.local", ttl: 600),
    ]

    let configuration = TopologyRuntimeDNSServerConfiguration(typedRecords: records)

    XCTAssertEqual(configuration.recordsByHostname["service.school.local"]?.targetIPAddress, "10.0.0.20")
    XCTAssertEqual(configuration.typedRecords, records)
    XCTAssertEqual(
      configuration.typedRecords.filter {
        $0.name.rawValue == "service.school.local" && $0.type == .address
      }.map(\.target),
      ["10.0.0.20", "10.0.0.21"]
    )
  }

  func testRuntimeConfigurationPromotesNextAddressWhenPrimaryTypedRecordIsRemoved() {
    var configuration = TopologyRuntimeDNSServerConfiguration(typedRecords: [
      record("service.school.local", .address, "10.0.0.20", ttl: 120),
      record("service.school.local", .address, "10.0.0.21", ttl: 180),
    ])

    XCTAssertTrue(configuration.removeTypedRecord(
      hostname: "service.school.local",
      recordType: .address,
      target: "10.0.0.20"
    ))
    XCTAssertEqual(configuration.recordsByHostname["service.school.local"]?.targetIPAddress, "10.0.0.21")
    XCTAssertEqual(configuration.typedRecords.map(\.target), ["10.0.0.21"])
  }

  func testLegacyAddressAddAppendsInJavaOrderAndDeduplicatesSemantically() {
    var configuration = TopologyRuntimeDNSServerConfiguration(typedRecords: [
      record("service.school.local", .address, "10.0.0.20", ttl: 120),
      record("school.local", .mailExchange, "mail.school.local", ttl: 300),
      record("service.school.local", .address, "10.0.0.21", ttl: 180),
    ])

    XCTAssertTrue(configuration.appendLegacyAddressRecord(
      TopologyRuntimeDNSRecord(hostname: "service.school.local", targetIPAddress: "10.0.0.22")
    ))
    XCTAssertFalse(configuration.appendLegacyAddressRecord(
      TopologyRuntimeDNSRecord(hostname: "service.school.local", targetIPAddress: "10.0.0.21")
    ))

    XCTAssertEqual(configuration.recordsByHostname["service.school.local"]?.targetIPAddress, "10.0.0.20")
    XCTAssertEqual(
      configuration.typedRecords.map { "\($0.type.rawValue):\($0.target)" },
      [
        "A:10.0.0.20",
        "MX:mail.school.local.",
        "A:10.0.0.21",
        "A:10.0.0.22",
      ]
    )
  }

  func testLegacyHostnameRemoveDeletesOnlyFirstAddressAndPromotesNext() {
    var configuration = TopologyRuntimeDNSServerConfiguration(typedRecords: [
      record("service.school.local", .address, "10.0.0.20", ttl: 120),
      record("school.local", .mailExchange, "mail.school.local", ttl: 300),
      record("service.school.local", .address, "10.0.0.21", ttl: 180),
    ])

    XCTAssertEqual(
      configuration.removeLegacyAddressRecord(hostname: "service.school.local"),
      TopologyRuntimeDNSRecord(hostname: "service.school.local", targetIPAddress: "10.0.0.20")
    )
    XCTAssertEqual(configuration.recordsByHostname["service.school.local"]?.targetIPAddress, "10.0.0.21")
    XCTAssertEqual(
      configuration.typedRecords.map { "\($0.type.rawValue):\($0.target)" },
      ["MX:mail.school.local.", "A:10.0.0.21"]
    )
  }

  func testDirectMXResolutionIncludesDeterministicAdditionalAddressRecord() {
    let dns = server(
      "10.0.0.53",
      records: [
        record("school.local", .mailExchange, "mail.school.local", ttl: 300),
        record("mail.school.local", .address, "10.0.0.25", ttl: 120),
      ])
    let question = question("school.local", .mailExchange)

    let result = TopologyDNSResolver().resolve(
      question,
      startingAt: "10.0.0.53",
      serversByIPAddress: ["10.0.0.53": dns]
    )

    guard case .success(let answer) = result else {
      return XCTFail("Expected successful MX resolution, got \(result)")
    }
    XCTAssertEqual(answer.records.map(\.type), [.mailExchange, .address])
    XCTAssertEqual(answer.records.map(\.target), ["mail.school.local.", "10.0.0.25"])
    XCTAssertEqual(answer.respondingServerIPAddress, "10.0.0.53")
    XCTAssertEqual(answer.trace.consultedServerIPAddresses, ["10.0.0.53"])
    XCTAssertEqual(answer.trace.responseCount, 1)
    XCTAssertFalse(answer.trace.cacheHit)
  }

  func testDirectNSResolutionIncludesGlueAfterTheAnswer() {
    let dns = server(
      "10.0.0.53",
      records: [
        record("school.local", .nameServer, "ns.school.local", ttl: 600),
        record("ns.school.local", .address, "10.0.0.53", ttl: 120),
      ])

    let result = TopologyDNSResolver().resolve(
      question("school.local", .nameServer),
      startingAt: "10.0.0.53",
      serversByIPAddress: ["10.0.0.53": dns]
    )

    guard case .success(let answer) = result else {
      return XCTFail("Expected successful NS resolution, got \(result)")
    }
    XCTAssertEqual(answer.records.map(\.type), [.nameServer, .address])
    XCTAssertEqual(answer.records.map(\.target), ["ns.school.local.", "10.0.0.53"])
  }

  func testResolverFollowsMostSpecificNSReferralDeterministically() {
    let root = server(
      "10.0.0.1",
      records: [
        record(".", .nameServer, "ns.root.local"),
        record("ns.root.local", .address, "10.0.0.2"),
        record("school.local", .nameServer, "ns.school.local"),
        record("ns.school.local", .address, "10.0.0.53"),
      ])
    let rootAuthority = server(
      "10.0.0.2",
      records: [
        record("www.school.local", .address, "10.0.0.99")
      ])
    let schoolAuthority = server(
      "10.0.0.53",
      records: [
        record("www.school.local", .address, "10.0.0.20")
      ])

    let result = TopologyDNSResolver().resolve(
      question("www.school.local", .address),
      startingAt: "10.0.0.1",
      serversByIPAddress: [
        "10.0.0.1": root,
        "10.0.0.2": rootAuthority,
        "10.0.0.53": schoolAuthority,
      ]
    )

    guard case .success(let answer) = result else {
      return XCTFail("Expected referral success, got \(result)")
    }
    XCTAssertEqual(answer.records.map(\.target), ["10.0.0.20"])
    XCTAssertEqual(answer.trace.consultedServerIPAddresses, ["10.0.0.1", "10.0.0.53"])
    XCTAssertEqual(answer.trace.hopCount, 1)
    XCTAssertEqual(answer.trace.responseCount, 2)
  }

  func testReferralConsultationsRemainClientOriginated() {
    let referral = server(
      "10.0.0.1",
      records: [
        record("school.local", .nameServer, "ns.school.local"),
        record("ns.school.local", .address, "10.0.0.53"),
      ]
    )
    let authority = server(
      "10.0.0.53",
      records: [record("www.school.local", .address, "10.0.0.20")]
    )
    var cache = TopologyDNSResolverCache()
    var consultations: [(String?, String)] = []

    let result = TopologyDNSResolver().resolve(
      question("www.school.local", .address),
      startingAt: "10.0.0.1",
      serversByIPAddress: ["10.0.0.1": referral, "10.0.0.53": authority],
      cache: &cache,
      canConsultServer: { source, destination, _ in
        consultations.append((source?.rawValue, destination.rawValue))
        return .available
      }
    )

    guard case .success = result else {
      return XCTFail("Expected referral success, got \(result)")
    }
    XCTAssertEqual(
      consultations.map { "\($0.0 ?? "client")->\($0.1)" },
      ["client->10.0.0.1", "client->10.0.0.53"]
    )
  }

  func testRecursiveForwardingIsOptIn() {
    let upstream = server(
      "10.0.0.53",
      records: [
        record("www.school.local", .address, "10.0.0.20")
      ])
    let disabled = server(
      "10.0.0.1",
      records: [],
      recursive: false,
      forwarder: "10.0.0.53"
    )
    let enabled = server(
      "10.0.0.2",
      records: [],
      recursive: true,
      forwarder: "10.0.0.53"
    )
    let resolver = TopologyDNSResolver()
    let query = question("www.school.local", .address)

    let disabledResult = resolver.resolve(
      query,
      startingAt: "10.0.0.1",
      serversByIPAddress: ["10.0.0.1": disabled, "10.0.0.53": upstream]
    )
    guard case .nameError = disabledResult else {
      return XCTFail("Expected non-recursive server to stop locally, got \(disabledResult)")
    }

    let enabledResult = resolver.resolve(
      query,
      startingAt: "10.0.0.2",
      serversByIPAddress: ["10.0.0.2": enabled, "10.0.0.53": upstream]
    )
    guard case .success(let answer) = enabledResult else {
      return XCTFail("Expected recursive forwarder success, got \(enabledResult)")
    }
    XCTAssertEqual(answer.records.map(\.target), ["10.0.0.20"])
    XCTAssertEqual(answer.trace.consultedServerIPAddresses, ["10.0.0.2", "10.0.0.53"])
  }

  func testResolverConsultationPolicyCanRejectAnUnreachableForwarder() {
    let local = server(
      "10.0.0.1",
      records: [],
      recursive: true,
      forwarder: "10.0.0.53"
    )
    let upstream = server(
      "10.0.0.53",
      records: [record("www.school.local", .address, "10.0.0.20")]
    )
    var cache = TopologyDNSResolverCache()
    var consultations: [(String?, String)] = []

    let result = TopologyDNSResolver().resolve(
      question("www.school.local", .address),
      startingAt: "10.0.0.1",
      serversByIPAddress: ["10.0.0.1": local, "10.0.0.53": upstream],
      cache: &cache,
      canConsultServer: { source, destination, _ in
        consultations.append((source?.rawValue, destination.rawValue))
        return destination.rawValue == "10.0.0.53" ? .unreachable : .available
      }
    )

    guard case .failure(let failure, let trace) = result else {
      return XCTFail("Expected unreachable forwarder failure, got \(result)")
    }
    XCTAssertEqual(failure, .serverUnavailable("10.0.0.53"))
    XCTAssertEqual(
      consultations.map { "\($0.0 ?? "client")->\($0.1)" },
      ["client->10.0.0.1", "10.0.0.1->10.0.0.53"]
    )
    XCTAssertEqual(trace.consultedServerIPAddresses, ["10.0.0.1"])
    XCTAssertEqual(trace.responseCount, 1)
    XCTAssertEqual(cache.entryCount, 0)
  }

  func testResolverDistinguishesNoDataFromNameError() {
    let dns = server(
      "10.0.0.53",
      records: [
        record("school.local", .mailExchange, "mail.school.local")
      ])
    let resolver = TopologyDNSResolver()

    let noData = resolver.resolve(
      question("school.local", .address),
      startingAt: "10.0.0.53",
      serversByIPAddress: ["10.0.0.53": dns]
    )
    guard case .noData = noData else {
      return XCTFail("Expected NOERROR/NODATA, got \(noData)")
    }

    let missing = resolver.resolve(
      question("missing.school.local", .address),
      startingAt: "10.0.0.53",
      serversByIPAddress: ["10.0.0.53": dns]
    )
    guard case .nameError = missing else {
      return XCTFail("Expected NXDOMAIN, got \(missing)")
    }
  }

  func testDelegatedNoDataRemainsNoDataWhenAnotherReferralIsUnavailable() {
    let parent = server(
      "10.0.0.1",
      records: [
        record("school.local", .nameServer, "ns1.school.local"),
        record("ns1.school.local", .address, "10.0.0.53"),
        record("school.local", .nameServer, "ns2.school.local"),
        record("ns2.school.local", .address, "10.0.0.54"),
      ])
    let authority = server(
      "10.0.0.53",
      records: [record("mail.school.local", .mailExchange, "mx.school.local")]
    )

    let result = TopologyDNSResolver().resolve(
      question("mail.school.local", .address),
      startingAt: "10.0.0.1",
      serversByIPAddress: ["10.0.0.1": parent, "10.0.0.53": authority]
    )

    guard case .noData = result else {
      return XCTFail("Expected delegated NODATA to survive unavailable alternate referral, got \(result)")
    }
  }

  func testForwardedNoDataRemainsNoData() {
    let forwarder = server(
      "10.0.0.53",
      records: [record("mail.school.local", .mailExchange, "mx.school.local")]
    )
    let recursive = server(
      "10.0.0.1",
      records: [],
      recursive: true,
      forwarder: "10.0.0.53"
    )

    let result = TopologyDNSResolver().resolve(
      question("mail.school.local", .address),
      startingAt: "10.0.0.1",
      serversByIPAddress: ["10.0.0.1": recursive, "10.0.0.53": forwarder]
    )

    guard case .noData = result else {
      return XCTFail("Expected forwarded NODATA, got \(result)")
    }
  }

  func testResolverDetectsRecursiveForwardingLoop() {
    let first = server("10.0.0.1", records: [], recursive: true, forwarder: "10.0.0.2")
    let second = server("10.0.0.2", records: [], recursive: true, forwarder: "10.0.0.1")

    let result = TopologyDNSResolver().resolve(
      question("loop.school.local", .address),
      startingAt: "10.0.0.1",
      serversByIPAddress: ["10.0.0.1": first, "10.0.0.2": second]
    )

    guard case .failure(let failure, let trace) = result else {
      return XCTFail("Expected loop failure, got \(result)")
    }
    XCTAssertEqual(failure, .loopDetected(serverIPAddress: "10.0.0.1"))
    XCTAssertEqual(trace.consultedServerIPAddresses, ["10.0.0.1", "10.0.0.2"])
    XCTAssertEqual(trace.responseCount, 2)
  }

  func testResolverEnforcesHopResponseAndRecordBudgets() {
    let first = server(
      "10.0.0.1",
      records: [
        record(".", .nameServer, "ns.second.local"),
        record("ns.second.local", .address, "10.0.0.2"),
      ])
    let second = server(
      "10.0.0.2",
      records: [
        record(".", .nameServer, "ns.third.local"),
        record("ns.third.local", .address, "10.0.0.3"),
      ])
    let third = server(
      "10.0.0.3",
      records: [
        record("www.school.local", .address, "10.0.0.20")
      ])
    let servers = ["10.0.0.1": first, "10.0.0.2": second, "10.0.0.3": third]
    let query = question("www.school.local", .address)

    let hopLimited = TopologyDNSResolver(
      budget: TopologyDNSResolutionBudget(maxHops: 1, maxResponses: 10, maxRecordsPerResponse: 10)
    ).resolve(query, startingAt: "10.0.0.1", serversByIPAddress: servers)
    guard case .failure(let hopFailure, _) = hopLimited else {
      return XCTFail("Expected hop limit failure, got \(hopLimited)")
    }
    XCTAssertEqual(hopFailure, .hopLimitExceeded(limit: 1))

    let responseLimited = TopologyDNSResolver(
      budget: TopologyDNSResolutionBudget(maxHops: 10, maxResponses: 1, maxRecordsPerResponse: 10)
    ).resolve(query, startingAt: "10.0.0.1", serversByIPAddress: servers)
    guard case .failure(let responseFailure, _) = responseLimited else {
      return XCTFail("Expected response limit failure, got \(responseLimited)")
    }
    XCTAssertEqual(responseFailure, .responseLimitExceeded(limit: 1))

    let oversized = server(
      "10.0.0.53",
      records: [
        record("www.school.local", .address, "10.0.0.20"),
        record("www.school.local", .address, "10.0.0.21"),
      ])
    let recordLimited = TopologyDNSResolver(
      budget: TopologyDNSResolutionBudget(maxHops: 10, maxResponses: 10, maxRecordsPerResponse: 1)
    ).resolve(query, startingAt: "10.0.0.53", serversByIPAddress: ["10.0.0.53": oversized])
    guard case .failure(let recordFailure, _) = recordLimited else {
      return XCTFail("Expected record limit failure, got \(recordLimited)")
    }
    XCTAssertEqual(
      recordFailure,
      .responseRecordLimitExceeded(serverIPAddress: "10.0.0.53", limit: 1)
    )
  }

  func testCacheHonorsTTLAndExplicitRecordInvalidation() {
    let oldRecord = record("www.school.local", .address, "10.0.0.20", ttl: 2)
    let newRecord = record("www.school.local", .address, "10.0.0.21", ttl: 2)
    let oldServer = server("10.0.0.53", records: [oldRecord])
    let newServer = server("10.0.0.53", records: [newRecord])
    let query = question("www.school.local", .address)
    let resolver = TopologyDNSResolver()
    var cache = TopologyDNSResolverCache()

    let first = resolver.resolve(
      query,
      startingAt: "10.0.0.53",
      serversByIPAddress: ["10.0.0.53": oldServer],
      nowMilliseconds: 0,
      cache: &cache
    )
    XCTAssertEqual(successTargets(first), ["10.0.0.20"])
    XCTAssertEqual(cache.entryCount, 1)

    let cached = resolver.resolve(
      query,
      startingAt: "10.0.0.53",
      serversByIPAddress: ["10.0.0.53": newServer],
      nowMilliseconds: 1_000,
      cache: &cache
    )
    XCTAssertEqual(successTargets(cached), ["10.0.0.20"])
    XCTAssertTrue(cached.trace.cacheHit)

    let invalidation = TopologyDNSCacheInvalidationScope.recordsChanged(
      from: [oldRecord],
      to: [newRecord],
      onServerIPAddress: "10.0.0.53"
    )
    XCTAssertEqual(invalidation, .server(ipv4("10.0.0.53")))
    if let invalidation { cache.invalidate(invalidation) }

    let refreshed = resolver.resolve(
      query,
      startingAt: "10.0.0.53",
      serversByIPAddress: ["10.0.0.53": newServer],
      nowMilliseconds: 1_000,
      cache: &cache
    )
    XCTAssertEqual(successTargets(refreshed), ["10.0.0.21"])
    XCTAssertFalse(refreshed.trace.cacheHit)

    let expired = resolver.resolve(
      query,
      startingAt: "10.0.0.53",
      serversByIPAddress: ["10.0.0.53": oldServer],
      nowMilliseconds: 3_001,
      cache: &cache
    )
    XCTAssertEqual(successTargets(expired), ["10.0.0.20"])
    XCTAssertFalse(expired.trace.cacheHit)
  }

  func testMissingReferralGlueIsReportedWithoutUnboundedSearch() {
    let dns = server(
      "10.0.0.1",
      records: [
        record("school.local", .nameServer, "ns.school.local")
      ])

    let result = TopologyDNSResolver().resolve(
      question("www.school.local", .address),
      startingAt: "10.0.0.1",
      serversByIPAddress: ["10.0.0.1": dns]
    )

    guard case .failure(let failure, let trace) = result else {
      return XCTFail("Expected missing-glue failure, got \(result)")
    }
    XCTAssertEqual(failure, .referralMissingAddress(nameServer: "ns.school.local."))
    XCTAssertEqual(trace.responseCount, 1)
  }

  private func record(
    _ name: String,
    _ type: TopologyDNSRecordType,
    _ target: String,
    ttl: UInt32 = TopologyDNSResourceRecord.defaultTTLSeconds
  ) -> TopologyDNSResourceRecord {
    guard
      let record = TopologyDNSResourceRecord(
        name: name,
        type: type,
        ttlSeconds: ttl,
        target: target
      )
    else {
      fatalError("Invalid test DNS record: \(name) \(type.rawValue) \(target)")
    }
    return record
  }

  private func question(_ name: String, _ type: TopologyDNSRecordType) -> TopologyDNSQuestion {
    guard let question = TopologyDNSQuestion(name: name, type: type) else {
      fatalError("Invalid test DNS question: \(name)")
    }
    return question
  }

  private func server(
    _ ipAddress: String,
    records: [TopologyDNSResourceRecord],
    recursive: Bool = false,
    forwarder: String? = nil
  ) -> TopologyDNSServerSnapshot {
    guard
      let server = TopologyDNSServerSnapshot(
        ipAddress: ipAddress,
        records: records,
        recursiveResolutionEnabled: recursive,
        forwardingServerIPAddress: forwarder
      )
    else {
      fatalError("Invalid test DNS server: \(ipAddress)")
    }
    return server
  }

  private func ipv4(_ rawValue: String) -> TopologyDNSIPv4Address {
    guard let address = TopologyDNSIPv4Address(rawValue: rawValue) else {
      fatalError("Invalid test IPv4 address: \(rawValue)")
    }
    return address
  }

  private func successTargets(_ result: TopologyDNSResolverResult) -> [String]? {
    guard case .success(let answer) = result else { return nil }
    return answer.records.map(\.target)
  }
}
