import Foundation

/// Central validation and serialization boundary for simulated HTTP server settings.
extension TopologyRuntimeWebServerConfiguration {
  private enum CodingKeys: String, CodingKey {
    case port
    case documentRoot
    case virtualHostConfiguration
  }

  /// Validates the listener port, canonical document root, and optional virtual-host configuration.
  func validate() throws {
    guard (1...65_535).contains(port) else {
      throw TopologyRuntimeWebVirtualHostError.invalidPort(port)
    }
    try TopologyRuntimeWebDocumentPathResolver.validateDocumentRoot(documentRoot)
    try virtualHostConfiguration?.validate()
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      port: try container.decode(Int.self, forKey: .port),
      documentRoot: try container.decode(String.self, forKey: .documentRoot),
      virtualHostConfiguration: try container.decodeIfPresent(
        TopologyRuntimeWebVirtualHostConfiguration.self,
        forKey: .virtualHostConfiguration
      )
    )

    do {
      try validate()
    } catch {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Invalid web-server configuration: \(error.localizedDescription)",
          underlyingError: error
        )
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    try validate()
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(port, forKey: .port)
    try container.encode(documentRoot, forKey: .documentRoot)
    try container.encodeIfPresent(virtualHostConfiguration, forKey: .virtualHostConfiguration)
  }
}

/// A normalized HTTP authority used to select a simulated web-server virtual host.
struct TopologyRuntimeWebHostAuthority: Codable, Equatable, Hashable, Sendable {
  let hostname: String
  let port: UInt16?

  init(hostname: String, port: UInt16? = nil) throws {
    self.hostname = try TopologyRuntimeWebVirtualHostSyntax.normalizedHostname(hostname)
    guard port != 0 else {
      throw TopologyRuntimeWebVirtualHostError.invalidPort(0)
    }
    self.port = port
  }

  init(hostHeader: String) throws {
    let parsed = try TopologyRuntimeWebVirtualHostSyntax.parseHostHeader(hostHeader)
    try self.init(hostname: parsed.hostname, port: parsed.port)
  }

  private enum CodingKeys: String, CodingKey {
    case hostname
    case port
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let hostname = try container.decode(String.self, forKey: .hostname)
    let port = try container.decodeIfPresent(UInt16.self, forKey: .port)
    do {
      try self.init(hostname: hostname, port: port)
    } catch {
      throw DecodingError.dataCorruptedError(
        forKey: .hostname,
        in: container,
        debugDescription: "Invalid virtual-host authority: \(error.localizedDescription)"
      )
    }
  }
}

/// One document root served for a normalized hostname and, optionally, one authority port.
struct TopologyRuntimeWebVirtualHost: Codable, Equatable, Hashable, Identifiable, Sendable {
  let id: String
  let authority: TopologyRuntimeWebHostAuthority
  let documentRoot: String
  let isEnabled: Bool

  init(
    id: String,
    hostname: String,
    port: UInt16? = nil,
    documentRoot: String,
    isEnabled: Bool = true
  ) throws {
    let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedID.isEmpty,
      normalizedID.count <= TopologyRuntimeWebVirtualHostLimits.maximumIdentifierLength,
      !normalizedID.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else {
      throw TopologyRuntimeWebVirtualHostError.invalidIdentifier
    }

    self.id = normalizedID
    self.authority = try TopologyRuntimeWebHostAuthority(hostname: hostname, port: port)
    self.documentRoot = try TopologyRuntimeWebDocumentPathResolver.normalizedDocumentRoot(
      documentRoot)
    self.isEnabled = isEnabled
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case authority
    case documentRoot
    case isEnabled
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(String.self, forKey: .id)
    let authority = try container.decode(TopologyRuntimeWebHostAuthority.self, forKey: .authority)
    let documentRoot = try container.decode(String.self, forKey: .documentRoot)
    let isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
    do {
      try self.init(
        id: id,
        hostname: authority.hostname,
        port: authority.port,
        documentRoot: documentRoot,
        isEnabled: isEnabled
      )
    } catch {
      throw DecodingError.dataCorruptedError(
        forKey: .documentRoot,
        in: container,
        debugDescription: "Invalid virtual host: \(error.localizedDescription)"
      )
    }
  }
}

/// A validated and deterministically ordered set of simulated HTTP virtual hosts.
struct TopologyRuntimeWebVirtualHostConfiguration: Codable, Equatable, Sendable {
  let hosts: [TopologyRuntimeWebVirtualHost]
  let defaultHostID: String

  init(hosts: [TopologyRuntimeWebVirtualHost], defaultHostID: String) throws {
    guard !hosts.isEmpty else {
      throw TopologyRuntimeWebVirtualHostError.emptyConfiguration
    }

    let normalizedDefaultHostID = defaultHostID.trimmingCharacters(in: .whitespacesAndNewlines)
    var identifiers = Set<String>()
    var authorities = Set<TopologyRuntimeWebHostAuthority>()
    for host in hosts {
      guard identifiers.insert(host.id).inserted else {
        throw TopologyRuntimeWebVirtualHostError.duplicateIdentifier(host.id)
      }
      guard authorities.insert(host.authority).inserted else {
        throw TopologyRuntimeWebVirtualHostError.duplicateAuthority(host.authority)
      }
    }

    guard let defaultHost = hosts.first(where: { $0.id == normalizedDefaultHostID }) else {
      throw TopologyRuntimeWebVirtualHostError.defaultHostNotFound(normalizedDefaultHostID)
    }
    guard defaultHost.isEnabled else {
      throw TopologyRuntimeWebVirtualHostError.defaultHostDisabled(normalizedDefaultHostID)
    }

    self.hosts = hosts.sorted(by: Self.precedes)
    self.defaultHostID = normalizedDefaultHostID
  }

  var defaultHost: TopologyRuntimeWebVirtualHost {
    // Validation in every initializer guarantees this lookup succeeds.
    hosts.first(where: { $0.id == defaultHostID })!
  }

  /// Revalidates the host set, authorities, and enabled default host.
  func validate() throws {
    _ = try Self(hosts: hosts, defaultHostID: defaultHostID)
  }

  private static func precedes(
    _ lhs: TopologyRuntimeWebVirtualHost,
    _ rhs: TopologyRuntimeWebVirtualHost
  ) -> Bool {
    if lhs.authority.hostname != rhs.authority.hostname {
      return lhs.authority.hostname < rhs.authority.hostname
    }
    switch (lhs.authority.port, rhs.authority.port) {
    case (.some(let left), .some(let right)) where left != right:
      return left < right
    case (.some, .none):
      return true
    case (.none, .some):
      return false
    default:
      return lhs.id < rhs.id
    }
  }

  private enum CodingKeys: String, CodingKey {
    case hosts
    case defaultHostID
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let hosts = try container.decode([TopologyRuntimeWebVirtualHost].self, forKey: .hosts)
    let defaultHostID = try container.decode(String.self, forKey: .defaultHostID)
    do {
      try self.init(hosts: hosts, defaultHostID: defaultHostID)
    } catch {
      throw DecodingError.dataCorruptedError(
        forKey: .hosts,
        in: container,
        debugDescription: "Invalid virtual-host configuration: \(error.localizedDescription)"
      )
    }
  }
}

enum TopologyRuntimeWebVirtualHostDispatchReason: String, Codable, Equatable, Sendable {
  case exactAuthority
  case defaultHost
}

struct TopologyRuntimeWebVirtualHostDispatchResult: Codable, Equatable, Sendable {
  let host: TopologyRuntimeWebVirtualHost
  let reason: TopologyRuntimeWebVirtualHostDispatchReason
}

/// Selects one virtual host without reading from or mutating the simulated runtime.
struct TopologyRuntimeWebVirtualHostDispatcher: Sendable {
  let configuration: TopologyRuntimeWebVirtualHostConfiguration

  func dispatch(
    hostHeader: String?,
    listeningPort: UInt16
  ) throws -> TopologyRuntimeWebVirtualHostDispatchResult {
    guard listeningPort != 0 else {
      throw TopologyRuntimeWebVirtualHostError.invalidPort(0)
    }

    guard let hostHeader, !hostHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return TopologyRuntimeWebVirtualHostDispatchResult(
        host: configuration.defaultHost,
        reason: .defaultHost
      )
    }

    let requestAuthority = try TopologyRuntimeWebHostAuthority(hostHeader: hostHeader)
    let effectivePort = requestAuthority.port ?? listeningPort
    let enabledMatches = configuration.hosts.filter {
      $0.isEnabled && $0.authority.hostname == requestAuthority.hostname
    }

    if let portSpecific = enabledMatches.first(where: { $0.authority.port == effectivePort }) {
      return TopologyRuntimeWebVirtualHostDispatchResult(
        host: portSpecific,
        reason: .exactAuthority
      )
    }
    if let portAgnostic = enabledMatches.first(where: { $0.authority.port == nil }) {
      return TopologyRuntimeWebVirtualHostDispatchResult(
        host: portAgnostic,
        reason: .exactAuthority
      )
    }
    return TopologyRuntimeWebVirtualHostDispatchResult(
      host: configuration.defaultHost,
      reason: .defaultHost
    )
  }
}

struct TopologyRuntimeWebResolvedDocumentPath: Codable, Equatable, Sendable {
  let documentRoot: String
  let relativePath: String
  let absolutePath: String
}

/// Resolves HTTP request paths beneath a configured simulated document root.
///
/// This resolver is lexical by design: it does not access the host filesystem. It rejects raw,
/// percent-encoded, and repeatedly encoded parent traversal before returning a canonical path.
enum TopologyRuntimeWebDocumentPathResolver {
  static func resolve(
    requestTarget: String,
    documentRoot: String,
    indexDocument: String = "index.html"
  ) throws -> TopologyRuntimeWebResolvedDocumentPath {
    let root = try normalizedDocumentRoot(documentRoot)
    let index = try normalizedIndexDocument(indexDocument)
    let rawPath =
      requestTarget.split(
        separator: "?",
        maxSplits: 1,
        omittingEmptySubsequences: false
      ).first.map(String.init) ?? ""
    guard rawPath.hasPrefix("/"), !rawPath.hasPrefix("//") else {
      throw TopologyRuntimeWebVirtualHostError.invalidRequestPath(requestTarget)
    }

    let decodedPath = try fullyDecodedPath(rawPath)
    try validatePathText(decodedPath, original: requestTarget)

    var components: [String] = []
    for component in decodedPath.split(separator: "/", omittingEmptySubsequences: true).map(
      String.init)
    {
      switch component {
      case ".":
        continue
      case "..":
        throw TopologyRuntimeWebVirtualHostError.pathTraversal(requestTarget)
      default:
        components.append(component)
      }
    }

    if decodedPath.hasSuffix("/") || components.isEmpty {
      components.append(index)
    }
    let relativePath = components.joined(separator: "/")
    let absolutePath = root == "/" ? "/\(relativePath)" : "\(root)/\(relativePath)"
    return TopologyRuntimeWebResolvedDocumentPath(
      documentRoot: root,
      relativePath: relativePath,
      absolutePath: absolutePath
    )
  }

  /// Verifies that a document root is safe and already in canonical absolute form.
  static func validateDocumentRoot(_ value: String) throws {
    guard try normalizedDocumentRoot(value) == value else {
      throw TopologyRuntimeWebVirtualHostError.invalidDocumentRoot(value)
    }
  }

  static func normalizedDocumentRoot(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("/"),
      !trimmed.hasPrefix("//"),
      !trimmed.contains("%"),
      trimmed.utf8.count <= TopologyRuntimeWebVirtualHostLimits.maximumPathBytes,
      !trimmed.contains("\\"),
      !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else {
      throw TopologyRuntimeWebVirtualHostError.invalidDocumentRoot(value)
    }

    var components: [String] = []
    for component in trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    {
      switch component {
      case ".":
        continue
      case "..":
        throw TopologyRuntimeWebVirtualHostError.invalidDocumentRoot(value)
      default:
        components.append(component)
      }
    }
    return components.isEmpty ? "/" : "/" + components.joined(separator: "/")
  }

  private static func normalizedIndexDocument(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
      trimmed != ".",
      trimmed != "..",
      !trimmed.contains("/"),
      !trimmed.contains("\\")
    else {
      throw TopologyRuntimeWebVirtualHostError.invalidIndexDocument(value)
    }
    try validatePathText(trimmed, original: value)
    return trimmed
  }

  private static func fullyDecodedPath(_ value: String) throws -> String {
    var current = value
    for _ in 0..<TopologyRuntimeWebVirtualHostLimits.maximumPercentDecodingPasses {
      guard let decoded = current.removingPercentEncoding else {
        throw TopologyRuntimeWebVirtualHostError.invalidPercentEncoding(value)
      }
      if decoded == current {
        return decoded
      }
      current = decoded
    }
    guard current.removingPercentEncoding == current else {
      throw TopologyRuntimeWebVirtualHostError.excessivePercentEncoding(value)
    }
    return current
  }

  private static func validatePathText(_ value: String, original: String) throws {
    guard value.utf8.count <= TopologyRuntimeWebVirtualHostLimits.maximumPathBytes,
      !value.contains("\\"),
      !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else {
      throw TopologyRuntimeWebVirtualHostError.invalidRequestPath(original)
    }
  }
}

enum TopologyRuntimeWebVirtualHostError: Error, Equatable, LocalizedError {
  case emptyConfiguration
  case invalidIdentifier
  case invalidHostname(String)
  case invalidHostHeader(String)
  case invalidPort(Int)
  case duplicateIdentifier(String)
  case duplicateAuthority(TopologyRuntimeWebHostAuthority)
  case defaultHostNotFound(String)
  case defaultHostDisabled(String)
  case invalidDocumentRoot(String)
  case invalidRequestPath(String)
  case pathTraversal(String)
  case invalidIndexDocument(String)
  case invalidPercentEncoding(String)
  case excessivePercentEncoding(String)

  var errorDescription: String? {
    switch self {
    case .emptyConfiguration:
      return "At least one virtual host is required."
    case .invalidIdentifier:
      return "The virtual-host identifier is invalid."
    case .invalidHostname:
      return "The virtual-host hostname is invalid."
    case .invalidHostHeader:
      return "The HTTP Host header is invalid."
    case .invalidPort(let value):
      return "Invalid virtual-host port: \(value)"
    case .duplicateIdentifier(let value):
      return "Duplicate virtual-host identifier: \(value)"
    case .duplicateAuthority(let authority):
      return "Duplicate virtual-host authority: \(authority.hostname)"
    case .defaultHostNotFound(let value):
      return "The default virtual host does not exist: \(value)"
    case .defaultHostDisabled(let value):
      return "The default virtual host is disabled: \(value)"
    case .invalidDocumentRoot:
      return "The virtual-host document root is invalid."
    case .invalidRequestPath:
      return "The HTTP request path is invalid."
    case .pathTraversal:
      return "HTTP request path traversal is not allowed."
    case .invalidIndexDocument:
      return "The index document is invalid."
    case .invalidPercentEncoding:
      return "The HTTP request path contains invalid percent encoding."
    case .excessivePercentEncoding:
      return "The HTTP request path contains excessive percent encoding."
    }
  }
}

private enum TopologyRuntimeWebVirtualHostLimits {
  static let maximumIdentifierLength = 128
  static let maximumHostnameLength = 253
  static let maximumPathBytes = 4_096
  static let maximumPercentDecodingPasses = 4
}

private enum TopologyRuntimeWebVirtualHostSyntax {
  static func parseHostHeader(_ value: String) throws -> (hostname: String, port: UInt16?) {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
      trimmed.utf8.count <= TopologyRuntimeWebVirtualHostLimits.maximumHostnameLength + 6,
      !trimmed.contains(","),
      !trimmed.contains("/"),
      !trimmed.contains("\\"),
      !trimmed.contains("@"),
      !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
      !trimmed.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) })
    else {
      throw TopologyRuntimeWebVirtualHostError.invalidHostHeader(value)
    }

    // Filius currently models IPv4 networks. Bracketed IPv6 authorities are intentionally rejected.
    guard !trimmed.hasPrefix("[") else {
      throw TopologyRuntimeWebVirtualHostError.invalidHostHeader(value)
    }

    let pieces = trimmed.split(separator: ":", omittingEmptySubsequences: false)
    guard pieces.count <= 2, let hostPart = pieces.first, !hostPart.isEmpty else {
      throw TopologyRuntimeWebVirtualHostError.invalidHostHeader(value)
    }
    let port: UInt16?
    if pieces.count == 2 {
      guard let parsedPort = Int(pieces[1]), (1...65_535).contains(parsedPort) else {
        throw TopologyRuntimeWebVirtualHostError.invalidHostHeader(value)
      }
      port = UInt16(parsedPort)
    } else {
      port = nil
    }
    return (try normalizedHostname(String(hostPart)), port)
  }

  static func normalizedHostname(_ value: String) throws -> String {
    var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    while normalized.hasSuffix(".") {
      normalized.removeLast()
    }
    guard !normalized.isEmpty,
      normalized.utf8.count <= TopologyRuntimeWebVirtualHostLimits.maximumHostnameLength,
      normalized.unicodeScalars.allSatisfy({ $0.isASCII }),
      !normalized.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else {
      throw TopologyRuntimeWebVirtualHostError.invalidHostname(value)
    }

    if isValidIPv4Address(normalized) {
      return normalized
    }
    let labels = normalized.split(separator: ".", omittingEmptySubsequences: false)
    guard
      labels.allSatisfy({ label in
        guard !label.isEmpty, label.utf8.count <= 63,
          label.first != "-", label.last != "-"
        else { return false }
        return label.unicodeScalars.allSatisfy {
          CharacterSet.alphanumerics.contains($0) || $0 == "-"
        }
      })
    else {
      throw TopologyRuntimeWebVirtualHostError.invalidHostname(value)
    }
    return normalized
  }

  private static func isValidIPv4Address(_ value: String) -> Bool {
    let segments = value.split(separator: ".", omittingEmptySubsequences: false)
    guard segments.count == 4 else { return false }
    return segments.allSatisfy { segment in
      !segment.isEmpty
        && segment.allSatisfy(\.isNumber)
        && UInt8(String(segment)) != nil
        && (segment.count == 1 || segment.first != "0")
    }
  }
}
