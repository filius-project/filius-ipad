import Foundation

/// DNS record kinds supported by the Java Filius DNS server.
enum TopologyDNSRecordType: String, CaseIterable, Codable, Hashable, Sendable {
  case address = "A"
  case mailExchange = "MX"
  case nameServer = "NS"

  fileprivate var sortRank: Int {
    switch self {
    case .address: 0
    case .mailExchange: 1
    case .nameServer: 2
    }
  }
}

/// A normalized DNS name without a trailing dot. The root name is represented as `.`.
struct TopologyDNSName: RawRepresentable, Hashable, Codable, Comparable, Sendable {
  let rawValue: String

  init?(rawValue: String) {
    guard let normalized = Self.normalized(rawValue) else { return nil }
    self.rawValue = normalized
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    guard let normalized = Self(rawValue: rawValue) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid DNS name: \(rawValue)"
      )
    }
    self = normalized
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  var absoluteString: String {
    rawValue == "." ? "." : rawValue + "."
  }

  var labelCount: Int {
    rawValue == "." ? 0 : rawValue.split(separator: ".").count
  }

  func isEqualToOrSubdomain(of possibleParent: TopologyDNSName) -> Bool {
    if possibleParent.rawValue == "." {
      return true
    }
    return rawValue == possibleParent.rawValue || rawValue.hasSuffix("." + possibleParent.rawValue)
  }

  static func < (lhs: TopologyDNSName, rhs: TopologyDNSName) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  static func normalized(_ rawValue: String) -> String? {
    var candidate = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if candidate == "." {
      return candidate
    }
    while candidate.hasSuffix(".") {
      candidate.removeLast()
    }

    guard !candidate.isEmpty, candidate.utf8.count <= 253 else { return nil }
    let labels = candidate.split(separator: ".", omittingEmptySubsequences: false)
    guard !labels.isEmpty else { return nil }

    for label in labels {
      guard !label.isEmpty, label.utf8.count <= 63 else { return nil }
      let bytes = Array(label.utf8)
      guard let first = bytes.first, let last = bytes.last,
        Self.isASCIILetterOrDigit(first), Self.isASCIILetterOrDigit(last),
        bytes.allSatisfy({ Self.isASCIILetterOrDigit($0) || $0 == 45 })
      else { return nil }
    }
    return candidate
  }

  private static func isASCIILetterOrDigit(_ byte: UInt8) -> Bool {
    (48...57).contains(byte) || (97...122).contains(byte)
  }
}

/// A canonical dotted-decimal IPv4 address.
struct TopologyDNSIPv4Address: RawRepresentable, Hashable, Codable, Comparable, Sendable {
  let rawValue: String

  init?(rawValue: String) {
    let candidate = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let components = candidate.split(separator: ".", omittingEmptySubsequences: false)
    guard components.count == 4 else { return nil }

    var octets: [UInt8] = []
    octets.reserveCapacity(4)
    for component in components {
      guard !component.isEmpty,
        component.utf8.allSatisfy({ (48...57).contains($0) }),
        let value = UInt16(component), value <= 255
      else { return nil }
      octets.append(UInt8(value))
    }
    self.rawValue = octets.map(String.init).joined(separator: ".")
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    guard let normalized = Self(rawValue: rawValue) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid IPv4 address: \(rawValue)"
      )
    }
    self = normalized
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  static func < (lhs: TopologyDNSIPv4Address, rhs: TopologyDNSIPv4Address) -> Bool {
    let lhsOctets = lhs.rawValue.split(separator: ".").compactMap { UInt8($0) }
    let rhsOctets = rhs.rawValue.split(separator: ".").compactMap { UInt8($0) }
    return lhsOctets.lexicographicallyPrecedes(rhsOctets)
  }
}

enum TopologyDNSRecordData: Hashable, Sendable {
  case address(TopologyDNSIPv4Address)
  case mailExchange(TopologyDNSName)
  case nameServer(TopologyDNSName)

  var type: TopologyDNSRecordType {
    switch self {
    case .address: .address
    case .mailExchange: .mailExchange
    case .nameServer: .nameServer
    }
  }

  var presentationValue: String {
    switch self {
    case .address(let address):
      address.rawValue
    case .mailExchange(let exchange), .nameServer(let exchange):
      exchange.absoluteString
    }
  }

  fileprivate var referencedName: TopologyDNSName? {
    switch self {
    case .address:
      nil
    case .mailExchange(let name), .nameServer(let name):
      name
    }
  }
}

/// A validated A, MX, or NS resource record with Java-compatible TTL semantics.
struct TopologyDNSResourceRecord: Hashable, Codable, Sendable {
  static let defaultTTLSeconds: UInt32 = 3_600

  let name: TopologyDNSName
  let ttlSeconds: UInt32
  let data: TopologyDNSRecordData

  var type: TopologyDNSRecordType { data.type }
  var target: String { data.presentationValue }

  init(name: TopologyDNSName, ttlSeconds: UInt32 = defaultTTLSeconds, data: TopologyDNSRecordData) {
    self.name = name
    self.ttlSeconds = ttlSeconds
    self.data = data
  }

  init?(
    name rawName: String,
    type: TopologyDNSRecordType,
    ttlSeconds: UInt32 = defaultTTLSeconds,
    target rawTarget: String
  ) {
    guard let name = TopologyDNSName(rawValue: rawName) else { return nil }
    let data: TopologyDNSRecordData
    switch type {
    case .address:
      guard let address = TopologyDNSIPv4Address(rawValue: rawTarget) else { return nil }
      data = .address(address)
    case .mailExchange:
      guard let exchange = TopologyDNSName(rawValue: rawTarget), exchange.rawValue != "." else {
        return nil
      }
      data = .mailExchange(exchange)
    case .nameServer:
      guard let nameServer = TopologyDNSName(rawValue: rawTarget), nameServer.rawValue != "." else {
        return nil
      }
      data = .nameServer(nameServer)
    }
    self.init(name: name, ttlSeconds: ttlSeconds, data: data)
  }

  private enum CodingKeys: String, CodingKey {
    case name
    case type
    case ttlSeconds
    case target
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let name = try container.decode(String.self, forKey: .name)
    let type = try container.decode(TopologyDNSRecordType.self, forKey: .type)
    let ttl =
      try container.decodeIfPresent(UInt32.self, forKey: .ttlSeconds) ?? Self.defaultTTLSeconds
    let target = try container.decode(String.self, forKey: .target)
    guard let record = Self(name: name, type: type, ttlSeconds: ttl, target: target) else {
      throw DecodingError.dataCorruptedError(
        forKey: .target,
        in: container,
        debugDescription: "Invalid \(type.rawValue) record for \(name)"
      )
    }
    self = record
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(name.rawValue, forKey: .name)
    try container.encode(type, forKey: .type)
    try container.encode(ttlSeconds, forKey: .ttlSeconds)
    try container.encode(target, forKey: .target)
  }

  fileprivate var semanticKey: TopologyDNSRecordSemanticKey {
    TopologyDNSRecordSemanticKey(name: name, type: type, target: target)
  }
}

private struct TopologyDNSRecordSemanticKey: Hashable {
  let name: TopologyDNSName
  let type: TopologyDNSRecordType
  let target: String
}

extension TopologyDNSResourceRecord {
  /// Adapts the existing A-only runtime model without changing its public behavior.
  init?(legacyARecord: TopologyRuntimeDNSRecord, ttlSeconds: UInt32 = defaultTTLSeconds) {
    self.init(
      name: legacyARecord.hostname,
      type: .address,
      ttlSeconds: ttlSeconds,
      target: legacyARecord.targetIPAddress
    )
  }

  var legacyARecord: TopologyRuntimeDNSRecord? {
    guard case .address(let address) = data else { return nil }
    return TopologyRuntimeDNSRecord(hostname: name.rawValue, targetIPAddress: address.rawValue)
  }
}

extension TopologyRuntimeDNSServerConfiguration {
  /// A deterministic typed projection of the existing A-only configuration.
  var typedARecords: [TopologyDNSResourceRecord] {
    recordsByHostname.values
      .compactMap { TopologyDNSResourceRecord(legacyARecord: $0) }
      .sorted(by: TopologyDNSResourceRecord.deterministicOrder)
  }

  init(typedARecords: [TopologyDNSResourceRecord]) {
    var legacyRecords: [String: TopologyRuntimeDNSRecord] = [:]
    for record in typedARecords.sorted(by: TopologyDNSResourceRecord.deterministicOrder) {
      guard let legacyRecord = record.legacyARecord, legacyRecords[legacyRecord.hostname] == nil
      else { continue }
      legacyRecords[legacyRecord.hostname] = legacyRecord
    }
    self.init(recordsByHostname: legacyRecords)
  }
}

/// Parses and writes the `/dns/hosts` format used by Java Filius while preserving unknown lines.
enum TopologyDNSHostsFileCodec {
  static func record(from line: String) -> TopologyDNSResourceRecord? {
    let content =
      line
      .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
      .first
      .map(String.init) ?? ""
    let fields = content.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard fields.count >= 4 else { return nil }

    let rawName: String
    let type: TopologyDNSRecordType
    let rawTTL: String
    let rawTarget: String

    if let parsedType = TopologyDNSRecordType(rawValue: fields[1].uppercased()) {
      rawName = fields[0]
      type = parsedType
      if fields[2].uppercased() == "IN" {
        guard fields.count >= 5 else { return nil }
        rawTTL = fields[3]
        rawTarget = fields[4]
      } else {
        rawTTL = fields[2]
        rawTarget = fields[3]
      }
    } else if fields.count >= 5,
      let parsedType = TopologyDNSRecordType(rawValue: fields[3].uppercased()),
      fields[2].uppercased() == "IN"
    {
      // Also accept conventional zone-file ordering: NAME TTL IN TYPE RDATA.
      rawName = fields[0]
      type = parsedType
      rawTTL = fields[1]
      rawTarget = fields[4]
    } else {
      return nil
    }

    guard let ttl = UInt32(rawTTL) else { return nil }
    return TopologyDNSResourceRecord(name: rawName, type: type, ttlSeconds: ttl, target: rawTarget)
  }

  static func records(from text: String) -> [TopologyDNSResourceRecord] {
    var emitted: Set<TopologyDNSRecordSemanticKey> = []
    var records: [TopologyDNSResourceRecord] = []
    for line in text.components(separatedBy: .newlines) {
      guard let record = record(from: line), emitted.insert(record.semanticKey).inserted else {
        continue
      }
      records.append(record)
    }
    return records
  }

  static func text(
    mirroring records: [TopologyDNSResourceRecord],
    preserving existingText: String
  ) -> String {
    var desiredByKey: [TopologyDNSRecordSemanticKey: TopologyDNSResourceRecord] = [:]
    for record in records
    where desiredByKey[record.semanticKey] == nil {
      desiredByKey[record.semanticKey] = record
    }

    var emitted: Set<TopologyDNSRecordSemanticKey> = []
    var output: [String] = []
    let existingLines = existingText.isEmpty ? [] : existingText.components(separatedBy: .newlines)
    for line in existingLines {
      guard let oldRecord = record(from: line) else {
        output.append(line)
        continue
      }
      guard let desired = desiredByKey[oldRecord.semanticKey],
        emitted.insert(oldRecord.semanticKey).inserted
      else {
        continue
      }
      output.append(canonicalLine(for: desired))
    }

    for record in records
    where emitted.insert(record.semanticKey).inserted {
      output.append(canonicalLine(for: record))
    }

    while output.last == "" { output.removeLast() }
    return output.isEmpty ? "" : output.joined(separator: "\n") + "\n"
  }

  private static func canonicalLine(for record: TopologyDNSResourceRecord) -> String {
    "\(record.name.absoluteString) \(record.type.rawValue) \(record.ttlSeconds) \(record.target)"
  }
}

extension TopologyDNSResourceRecord {
  static func deterministicOrder(
    _ lhs: TopologyDNSResourceRecord,
    _ rhs: TopologyDNSResourceRecord
  ) -> Bool {
    if lhs.name != rhs.name { return lhs.name < rhs.name }
    if lhs.type != rhs.type { return lhs.type.sortRank < rhs.type.sortRank }
    if lhs.target != rhs.target { return lhs.target < rhs.target }
    return lhs.ttlSeconds < rhs.ttlSeconds
  }
}

struct TopologyDNSQuestion: Hashable, Codable, Sendable {
  let name: TopologyDNSName
  let type: TopologyDNSRecordType

  init(name: TopologyDNSName, type: TopologyDNSRecordType) {
    self.name = name
    self.type = type
  }

  init?(name rawName: String, type: TopologyDNSRecordType) {
    guard let name = TopologyDNSName(rawValue: rawName) else { return nil }
    self.init(name: name, type: type)
  }
}

/// Immutable server data consumed by the deterministic resolver.
struct TopologyDNSServerSnapshot: Equatable, Sendable {
  let ipAddress: TopologyDNSIPv4Address
  let records: [TopologyDNSResourceRecord]
  let recursiveResolutionEnabled: Bool
  let forwardingServerIPAddress: TopologyDNSIPv4Address?

  init(
    ipAddress: TopologyDNSIPv4Address,
    records: [TopologyDNSResourceRecord],
    recursiveResolutionEnabled: Bool = false,
    forwardingServerIPAddress: TopologyDNSIPv4Address? = nil
  ) {
    var emitted: Set<TopologyDNSRecordSemanticKey> = []
    self.ipAddress = ipAddress
    self.records = records.filter { emitted.insert($0.semanticKey).inserted }
    self.recursiveResolutionEnabled = recursiveResolutionEnabled
    self.forwardingServerIPAddress = forwardingServerIPAddress
  }

  init?(
    ipAddress rawIPAddress: String,
    records: [TopologyDNSResourceRecord],
    recursiveResolutionEnabled: Bool = false,
    forwardingServerIPAddress rawForwarder: String? = nil
  ) {
    guard let ipAddress = TopologyDNSIPv4Address(rawValue: rawIPAddress) else { return nil }
    let forwarder: TopologyDNSIPv4Address?
    if let rawForwarder,
      !rawForwarder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      guard let normalizedForwarder = TopologyDNSIPv4Address(rawValue: rawForwarder) else {
        return nil
      }
      forwarder = normalizedForwarder
    } else {
      forwarder = nil
    }
    self.init(
      ipAddress: ipAddress,
      records: records,
      recursiveResolutionEnabled: recursiveResolutionEnabled,
      forwardingServerIPAddress: forwarder
    )
  }

  init?(
    ipAddress: String,
    legacyConfiguration: TopologyRuntimeDNSServerConfiguration,
    recursiveResolutionEnabled: Bool = false,
    forwardingServerIPAddress: String? = nil
  ) {
    self.init(
      ipAddress: ipAddress,
      records: legacyConfiguration.typedRecords,
      recursiveResolutionEnabled: recursiveResolutionEnabled,
      forwardingServerIPAddress: forwardingServerIPAddress
    )
  }

  fileprivate func exactRecords(for question: TopologyDNSQuestion) -> [TopologyDNSResourceRecord] {
    records.filter { $0.name == question.name && $0.type == question.type }
  }

  fileprivate func additionalAddressRecords(
    for answers: [TopologyDNSResourceRecord]
  ) -> [TopologyDNSResourceRecord] {
    let referencedNames = Set(answers.compactMap(\.data.referencedName))
    guard !referencedNames.isEmpty else { return [] }
    return records.filter { record in
      record.type == .address && referencedNames.contains(record.name)
    }
  }

  fileprivate func applicableNameServerRecords(
    for name: TopologyDNSName
  ) -> [TopologyDNSResourceRecord] {
    let candidates = records.filter { record in
      record.type == .nameServer && name.isEqualToOrSubdomain(of: record.name)
    }
    guard let mostSpecificLabelCount = candidates.map(\.name.labelCount).max() else { return [] }
    return candidates.filter { $0.name.labelCount == mostSpecificLabelCount }
  }

  fileprivate func addressRecords(for name: TopologyDNSName) -> [TopologyDNSResourceRecord] {
    records.filter { $0.name == name && $0.type == .address }
  }

  fileprivate func containsName(_ name: TopologyDNSName) -> Bool {
    records.contains { $0.name == name }
  }
}

struct TopologyDNSResolutionBudget: Equatable, Sendable {
  let maxHops: Int
  let maxResponses: Int
  let maxRecordsPerResponse: Int

  init(maxHops: Int = 16, maxResponses: Int = 32, maxRecordsPerResponse: Int = 128) {
    self.maxHops = max(0, maxHops)
    self.maxResponses = max(1, maxResponses)
    self.maxRecordsPerResponse = max(1, maxRecordsPerResponse)
  }
}

struct TopologyDNSResolutionTrace: Equatable, Sendable {
  let consultedServerIPAddresses: [String]
  let hopCount: Int
  let responseCount: Int
  let cacheHit: Bool
}

struct TopologyDNSResolvedAnswer: Equatable, Sendable {
  let question: TopologyDNSQuestion
  let records: [TopologyDNSResourceRecord]
  let respondingServerIPAddress: String
  let trace: TopologyDNSResolutionTrace
}

enum TopologyDNSConsultationResult: Equatable, Sendable {
  case available
  case unreachable
  case timedOut
}

enum TopologyDNSResolutionFailure: Equatable, Sendable {
  case invalidStartingServerAddress(String)
  case serverUnavailable(String)
  case serverTimedOut(String)
  case referralMissingAddress(nameServer: String)
  case loopDetected(serverIPAddress: String)
  case hopLimitExceeded(limit: Int)
  case responseLimitExceeded(limit: Int)
  case responseRecordLimitExceeded(serverIPAddress: String, limit: Int)
}

enum TopologyDNSResolverResult: Equatable, Sendable {
  case success(TopologyDNSResolvedAnswer)
  case nameError(question: TopologyDNSQuestion, trace: TopologyDNSResolutionTrace)
  case noData(question: TopologyDNSQuestion, trace: TopologyDNSResolutionTrace)
  case failure(TopologyDNSResolutionFailure, trace: TopologyDNSResolutionTrace)

  var trace: TopologyDNSResolutionTrace {
    switch self {
    case .success(let answer): answer.trace
    case .nameError(_, let trace), .noData(_, let trace), .failure(_, let trace): trace
    }
  }
}

enum TopologyDNSCacheInvalidationScope: Equatable, Sendable {
  case all
  case server(TopologyDNSIPv4Address)
  case names(Set<TopologyDNSName>)

  static func recordsChanged(
    from previousRecords: [TopologyDNSResourceRecord],
    to currentRecords: [TopologyDNSResourceRecord],
    onServerIPAddress rawServerIPAddress: String? = nil
  ) -> TopologyDNSCacheInvalidationScope? {
    let previous = Set(previousRecords)
    let current = Set(currentRecords)
    guard previous != current else { return nil }

    if let rawServerIPAddress,
      let serverIPAddress = TopologyDNSIPv4Address(rawValue: rawServerIPAddress)
    {
      return .server(serverIPAddress)
    }

    let changedRecords = previous.symmetricDifference(current)
    let names = Set(
      changedRecords.flatMap { record -> [TopologyDNSName] in
        var result = [record.name]
        if let referencedName = record.data.referencedName {
          result.append(referencedName)
        }
        return result
      })
    return names.isEmpty ? .all : .names(names)
  }
}

struct TopologyDNSResolverCache: Equatable, Sendable {
  private struct Key: Hashable, Sendable {
    let startingServerIPAddress: TopologyDNSIPv4Address
    let question: TopologyDNSQuestion
  }

  private enum Payload: Equatable, Sendable {
    case success(records: [TopologyDNSResourceRecord], respondingServerIPAddress: String)
    case nameError
    case noData
  }

  private struct Entry: Equatable, Sendable {
    let payload: Payload
    let expiresAtMilliseconds: UInt64
    let dependentNames: Set<TopologyDNSName>
    let dependentServers: Set<TopologyDNSIPv4Address>
  }

  private var entries: [Key: Entry] = [:]

  var entryCount: Int { entries.count }

  mutating func removeExpiredEntries(at nowMilliseconds: UInt64) {
    entries = entries.filter { $0.value.expiresAtMilliseconds > nowMilliseconds }
  }

  mutating func invalidate(_ scope: TopologyDNSCacheInvalidationScope) {
    switch scope {
    case .all:
      entries.removeAll(keepingCapacity: true)
    case .server(let serverIPAddress):
      entries = entries.filter { !$0.value.dependentServers.contains(serverIPAddress) }
    case .names(let names):
      guard !names.isEmpty else { return }
      entries = entries.filter { $0.value.dependentNames.isDisjoint(with: names) }
    }
  }

  fileprivate mutating func result(
    for question: TopologyDNSQuestion,
    startingAt startingServerIPAddress: TopologyDNSIPv4Address,
    nowMilliseconds: UInt64
  ) -> TopologyDNSResolverResult? {
    let key = Key(startingServerIPAddress: startingServerIPAddress, question: question)
    guard let entry = entries[key] else { return nil }
    guard entry.expiresAtMilliseconds > nowMilliseconds else {
      entries.removeValue(forKey: key)
      return nil
    }
    let trace = TopologyDNSResolutionTrace(
      consultedServerIPAddresses: [],
      hopCount: 0,
      responseCount: 0,
      cacheHit: true
    )
    switch entry.payload {
    case .success(let records, let respondingServerIPAddress):
      return .success(
        TopologyDNSResolvedAnswer(
          question: question,
          records: records,
          respondingServerIPAddress: respondingServerIPAddress,
          trace: trace
        ))
    case .nameError:
      return .nameError(question: question, trace: trace)
    case .noData:
      return .noData(question: question, trace: trace)
    }
  }

  fileprivate mutating func store(
    _ result: TopologyDNSResolverResult,
    startingAt startingServerIPAddress: TopologyDNSIPv4Address,
    nowMilliseconds: UInt64,
    negativeTTLSeconds: UInt32,
    dependentNames: Set<TopologyDNSName>,
    dependentServers: Set<TopologyDNSIPv4Address>
  ) {
    let question: TopologyDNSQuestion
    let payload: Payload
    let ttlSeconds: UInt32

    switch result {
    case .success(let answer):
      question = answer.question
      payload = .success(
        records: answer.records,
        respondingServerIPAddress: answer.respondingServerIPAddress
      )
      guard let minimumTTL = answer.records.map(\.ttlSeconds).min(), minimumTTL > 0 else { return }
      ttlSeconds = minimumTTL
    case .nameError(let resultQuestion, _):
      question = resultQuestion
      payload = .nameError
      guard negativeTTLSeconds > 0 else { return }
      ttlSeconds = negativeTTLSeconds
    case .noData(let resultQuestion, _):
      question = resultQuestion
      payload = .noData
      guard negativeTTLSeconds > 0 else { return }
      ttlSeconds = negativeTTLSeconds
    case .failure:
      return
    }

    let delta = UInt64(ttlSeconds) * 1_000
    let expiresAt = nowMilliseconds > UInt64.max - delta ? UInt64.max : nowMilliseconds + delta
    entries[Key(startingServerIPAddress: startingServerIPAddress, question: question)] = Entry(
      payload: payload,
      expiresAtMilliseconds: expiresAt,
      dependentNames: dependentNames,
      dependentServers: dependentServers
    )
  }
}

/// Deterministic A/MX/NS resolver for simulated DNS servers.
struct TopologyDNSResolver: Sendable {
  let budget: TopologyDNSResolutionBudget
  let negativeCacheTTLSeconds: UInt32

  init(
    budget: TopologyDNSResolutionBudget = TopologyDNSResolutionBudget(),
    negativeCacheTTLSeconds: UInt32 = 60
  ) {
    self.budget = budget
    self.negativeCacheTTLSeconds = negativeCacheTTLSeconds
  }

  func resolve(
    _ question: TopologyDNSQuestion,
    startingAt rawServerIPAddress: String,
    serversByIPAddress: [String: TopologyDNSServerSnapshot],
    nowMilliseconds: UInt64 = 0,
    cache: inout TopologyDNSResolverCache,
    canConsultServer: (
      _ sourceServerIPAddress: TopologyDNSIPv4Address?,
      _ destinationServerIPAddress: TopologyDNSIPv4Address,
      _ question: TopologyDNSQuestion
    ) -> TopologyDNSConsultationResult = { _, _, _ in .available }
  ) -> TopologyDNSResolverResult {
    guard let startingServerIPAddress = TopologyDNSIPv4Address(rawValue: rawServerIPAddress) else {
      return .failure(
        .invalidStartingServerAddress(rawServerIPAddress),
        trace: TopologyDNSResolutionTrace(
          consultedServerIPAddresses: [],
          hopCount: 0,
          responseCount: 0,
          cacheHit: false
        )
      )
    }

    if let cached = cache.result(
      for: question,
      startingAt: startingServerIPAddress,
      nowMilliseconds: nowMilliseconds
    ) {
      return cached
    }

    var normalizedServers: [TopologyDNSIPv4Address: TopologyDNSServerSnapshot] = [:]
    for (rawAddress, server) in serversByIPAddress {
      if let address = TopologyDNSIPv4Address(rawValue: rawAddress) {
        normalizedServers[address] = server
      } else {
        normalizedServers[server.ipAddress] = server
      }
    }

    if question.name.rawValue == "localhost", question.type == .address,
      let localhostRecord = TopologyDNSResourceRecord(
        name: "localhost",
        type: .address,
        ttlSeconds: TopologyDNSResourceRecord.defaultTTLSeconds,
        target: "127.0.0.1"
      )
    {
      let trace = TopologyDNSResolutionTrace(
        consultedServerIPAddresses: [],
        hopCount: 0,
        responseCount: 0,
        cacheHit: false
      )
      let result = TopologyDNSResolverResult.success(
        TopologyDNSResolvedAnswer(
          question: question,
          records: [localhostRecord],
          respondingServerIPAddress: "127.0.0.1",
          trace: trace
        ))
      cache.store(
        result,
        startingAt: startingServerIPAddress,
        nowMilliseconds: nowMilliseconds,
        negativeTTLSeconds: negativeCacheTTLSeconds,
        dependentNames: [question.name],
        dependentServers: []
      )
      return result
    }

    var context = SearchContext(question: question)
    let internalResult = search(
      question: question,
      serverIPAddress: startingServerIPAddress,
      requestingServerIPAddress: nil,
      depth: 0,
      path: [],
      serversByIPAddress: normalizedServers,
      canConsultServer: canConsultServer,
      context: &context
    )
    let trace = TopologyDNSResolutionTrace(
      consultedServerIPAddresses: context.consultedServers.map(\.rawValue),
      hopCount: context.maximumDepth,
      responseCount: context.responseCount,
      cacheHit: false
    )

    let result: TopologyDNSResolverResult
    switch internalResult {
    case .success(let records, let respondingServerIPAddress):
      result = .success(
        TopologyDNSResolvedAnswer(
          question: question,
          records: records,
          respondingServerIPAddress: respondingServerIPAddress.rawValue,
          trace: trace
        ))
    case .nameError:
      result = .nameError(question: question, trace: trace)
    case .noData:
      result = .noData(question: question, trace: trace)
    case .failure(let failure):
      result = .failure(failure, trace: trace)
    }

    cache.store(
      result,
      startingAt: startingServerIPAddress,
      nowMilliseconds: nowMilliseconds,
      negativeTTLSeconds: negativeCacheTTLSeconds,
      dependentNames: context.dependentNames,
      dependentServers: context.dependentServers
    )
    return result
  }

  func resolve(
    _ question: TopologyDNSQuestion,
    startingAt serverIPAddress: String,
    serversByIPAddress: [String: TopologyDNSServerSnapshot],
    nowMilliseconds: UInt64 = 0
  ) -> TopologyDNSResolverResult {
    var cache = TopologyDNSResolverCache()
    return resolve(
      question,
      startingAt: serverIPAddress,
      serversByIPAddress: serversByIPAddress,
      nowMilliseconds: nowMilliseconds,
      cache: &cache
    )
  }

  private struct SearchContext {
    let question: TopologyDNSQuestion
    var consultedServers: [TopologyDNSIPv4Address] = []
    var dependentNames: Set<TopologyDNSName>
    var dependentServers: Set<TopologyDNSIPv4Address> = []
    var responseCount = 0
    var maximumDepth = 0

    init(question: TopologyDNSQuestion) {
      self.question = question
      self.dependentNames = [question.name]
    }
  }

  private enum SearchResult {
    case success(
      records: [TopologyDNSResourceRecord], respondingServerIPAddress: TopologyDNSIPv4Address)
    case nameError
    case noData
    case failure(TopologyDNSResolutionFailure)
  }

  private func search(
    question: TopologyDNSQuestion,
    serverIPAddress: TopologyDNSIPv4Address,
    requestingServerIPAddress: TopologyDNSIPv4Address?,
    depth: Int,
    path: Set<TopologyDNSIPv4Address>,
    serversByIPAddress: [TopologyDNSIPv4Address: TopologyDNSServerSnapshot],
    canConsultServer: (
      _ sourceServerIPAddress: TopologyDNSIPv4Address?,
      _ destinationServerIPAddress: TopologyDNSIPv4Address,
      _ question: TopologyDNSQuestion
    ) -> TopologyDNSConsultationResult,
    context: inout SearchContext
  ) -> SearchResult {
    context.maximumDepth = max(context.maximumDepth, depth)
    guard depth <= budget.maxHops else {
      return .failure(.hopLimitExceeded(limit: budget.maxHops))
    }
    guard !path.contains(serverIPAddress) else {
      return .failure(.loopDetected(serverIPAddress: serverIPAddress.rawValue))
    }
    guard context.responseCount < budget.maxResponses else {
      return .failure(.responseLimitExceeded(limit: budget.maxResponses))
    }
    switch canConsultServer(requestingServerIPAddress, serverIPAddress, question) {
    case .available:
      break
    case .unreachable:
      return .failure(.serverUnavailable(serverIPAddress.rawValue))
    case .timedOut:
      return .failure(.serverTimedOut(serverIPAddress.rawValue))
    }
    guard let server = serversByIPAddress[serverIPAddress] else {
      return .failure(.serverUnavailable(serverIPAddress.rawValue))
    }

    context.consultedServers.append(serverIPAddress)
    context.dependentServers.insert(serverIPAddress)
    context.responseCount += 1
    var nextPath = path
    nextPath.insert(serverIPAddress)

    let exactAnswers = uniqueInOrder(server.exactRecords(for: question))
    if !exactAnswers.isEmpty {
      let additionalRecords = uniqueInOrder(server.additionalAddressRecords(for: exactAnswers))
      let responseRecords = uniqueInOrder(exactAnswers + additionalRecords)
      guard responseRecords.count <= budget.maxRecordsPerResponse else {
        return .failure(
          .responseRecordLimitExceeded(
            serverIPAddress: serverIPAddress.rawValue,
            limit: budget.maxRecordsPerResponse
          ))
      }
      recordDependencies(responseRecords, context: &context)
      return .success(records: responseRecords, respondingServerIPAddress: serverIPAddress)
    }

    let referrals = uniqueInOrder(server.applicableNameServerRecords(for: question.name))
    let referralGlue = uniqueInOrder(
      referrals.flatMap { referral -> [TopologyDNSResourceRecord] in
        guard case .nameServer(let nameServer) = referral.data else { return [] }
        return server.addressRecords(for: nameServer)
      })
    let referralResponse = uniqueInOrder(referrals + referralGlue)
    guard referralResponse.count <= budget.maxRecordsPerResponse else {
      return .failure(
        .responseRecordLimitExceeded(
          serverIPAddress: serverIPAddress.rawValue,
          limit: budget.maxRecordsPerResponse
        ))
    }
    recordDependencies(referralResponse, context: &context)

    var branchFailures: [TopologyDNSResolutionFailure] = []
    var authoritativeNegative: SearchResult?
    if !referrals.isEmpty {
      let candidates = referralCandidates(referrals: referrals, on: server)
      if candidates.isEmpty {
        if let firstReferral = referrals.first,
          case .nameServer(let nameServer) = firstReferral.data
        {
          branchFailures.append(.referralMissingAddress(nameServer: nameServer.absoluteString))
        }
      } else {
        for candidate in candidates {
          let branch = search(
            question: question,
            serverIPAddress: candidate,
            requestingServerIPAddress: nil,
            depth: depth + 1,
            path: nextPath,
            serversByIPAddress: serversByIPAddress,
            canConsultServer: canConsultServer,
            context: &context
          )
          switch branch {
          case .success:
            return branch
          case .failure(let failure):
            branchFailures.append(failure)
          case .noData:
            authoritativeNegative = branch
          case .nameError:
            if authoritativeNegative == nil { authoritativeNegative = branch }
          }
          if case .responseLimitExceeded = branchFailures.last {
            return .failure(branchFailures.last!)
          }
        }
      }
    }

    if server.recursiveResolutionEnabled,
      let forwarder = server.forwardingServerIPAddress
    {
      let forwarded = search(
        question: question,
        serverIPAddress: forwarder,
        requestingServerIPAddress: serverIPAddress,
        depth: depth + 1,
        path: nextPath,
        serversByIPAddress: serversByIPAddress,
        canConsultServer: canConsultServer,
        context: &context
      )
      switch forwarded {
      case .success:
        return forwarded
      case .failure(let failure):
        branchFailures.append(failure)
      case .noData:
        authoritativeNegative = forwarded
      case .nameError:
        if authoritativeNegative == nil { authoritativeNegative = forwarded }
      }
    }

    if let authoritativeNegative { return authoritativeNegative }
    if !branchFailures.isEmpty, !referrals.isEmpty || server.recursiveResolutionEnabled {
      return .failure(branchFailures[0])
    }
    return server.containsName(question.name) ? .noData : .nameError
  }

  private func referralCandidates(
    referrals: [TopologyDNSResourceRecord],
    on server: TopologyDNSServerSnapshot
  ) -> [TopologyDNSIPv4Address] {
    var emitted: Set<TopologyDNSIPv4Address> = []
    var candidates: [TopologyDNSIPv4Address] = []
    for referral in referrals {
      guard case .nameServer(let nameServer) = referral.data else { continue }
      for glue in server.addressRecords(for: nameServer) {
        guard case .address(let address) = glue.data, emitted.insert(address).inserted else {
          continue
        }
        candidates.append(address)
      }
    }
    return candidates
  }

  private func recordDependencies(
    _ records: [TopologyDNSResourceRecord],
    context: inout SearchContext
  ) {
    for record in records {
      context.dependentNames.insert(record.name)
      if let referencedName = record.data.referencedName {
        context.dependentNames.insert(referencedName)
      }
    }
  }

  private func uniqueSorted(
    _ records: [TopologyDNSResourceRecord]
  ) -> [TopologyDNSResourceRecord] {
    uniqueInOrder(records.sorted(by: TopologyDNSResourceRecord.deterministicOrder))
  }

  private func uniqueInOrder(
    _ records: [TopologyDNSResourceRecord]
  ) -> [TopologyDNSResourceRecord] {
    var emitted: Set<TopologyDNSRecordSemanticKey> = []
    return records.filter { emitted.insert($0.semanticKey).inserted }
  }
}
