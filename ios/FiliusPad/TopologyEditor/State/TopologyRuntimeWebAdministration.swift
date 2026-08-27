import Foundation

// MARK: - Access policy

/// A canonical IPv4 network used to constrain simulated web-administration access.
struct TopologyRuntimeWebAdministrationIPv4Network: Codable, Equatable, Hashable, Sendable {
  let networkAddress: String
  let subnetMask: String

  init(networkAddress: String, subnetMask: String) throws {
    let address = try TopologyRuntimeWebAdministrationIPv4.parse(networkAddress)
    let mask = try TopologyRuntimeWebAdministrationIPv4.parseContiguousMask(subnetMask)
    self.networkAddress = TopologyRuntimeWebAdministrationIPv4.string(address & mask)
    self.subnetMask = TopologyRuntimeWebAdministrationIPv4.string(mask)
  }

  func contains(_ ipAddress: String) -> Bool {
    guard let candidate = try? TopologyRuntimeWebAdministrationIPv4.parse(ipAddress),
      let network = try? TopologyRuntimeWebAdministrationIPv4.parse(networkAddress),
      let mask = try? TopologyRuntimeWebAdministrationIPv4.parseContiguousMask(subnetMask)
    else { return false }
    return candidate & mask == network
  }

  private enum CodingKeys: String, CodingKey {
    case networkAddress
    case subnetMask
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let address = try container.decode(String.self, forKey: .networkAddress)
    let mask = try container.decode(String.self, forKey: .subnetMask)
    do {
      try self.init(networkAddress: address, subnetMask: mask)
    } catch {
      throw DecodingError.dataCorruptedError(
        forKey: .networkAddress,
        in: container,
        debugDescription: "Invalid administration access network."
      )
    }
  }
}

struct TopologyRuntimeWebAdministrationAccessPolicy: Codable, Equatable, Sendable {
  let isEnabled: Bool
  let allowedSourceNetworks: [TopologyRuntimeWebAdministrationIPv4Network]

  init(
    isEnabled: Bool = false,
    allowedSourceNetworks: [TopologyRuntimeWebAdministrationIPv4Network] = []
  ) {
    self.isEnabled = isEnabled
    self.allowedSourceNetworks = Array(Set(allowedSourceNetworks)).sorted {
      if $0.networkAddress != $1.networkAddress {
        return TopologyRuntimeWebAdministrationIPv4.numericValue($0.networkAddress)
          < TopologyRuntimeWebAdministrationIPv4.numericValue($1.networkAddress)
      }
      return TopologyRuntimeWebAdministrationIPv4.numericValue($0.subnetMask)
        < TopologyRuntimeWebAdministrationIPv4.numericValue($1.subnetMask)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case isEnabled
    case allowedSourceNetworks
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      isEnabled: try container.decode(Bool.self, forKey: .isEnabled),
      allowedSourceNetworks: try container.decode(
        [TopologyRuntimeWebAdministrationIPv4Network].self,
        forKey: .allowedSourceNetworks
      )
    )
  }

  func accessDecision(for sourceIPAddress: String) -> TopologyRuntimeWebAdministrationAccessDecision
  {
    guard isEnabled else { return .disabled }
    guard (try? TopologyRuntimeWebAdministrationIPv4.parse(sourceIPAddress)) != nil else {
      return .invalidSourceAddress
    }
    return allowedSourceNetworks.contains(where: { $0.contains(sourceIPAddress) })
      ? .allowed : .sourceDenied
  }
}

enum TopologyRuntimeWebAdministrationAccessDecision: String, Codable, Equatable, Sendable {
  case allowed
  case disabled
  case invalidSourceAddress
  case sourceDenied
}

// MARK: - Request/response primitives

struct TopologyRuntimeWebAdministrationRequest: Codable, Equatable, Sendable {
  let method: String
  let target: String
  let sourceIPAddress: String
  let formFields: [String: String]

  init(
    method: String,
    target: String,
    sourceIPAddress: String,
    formFields: [String: String] = [:]
  ) {
    self.method = method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    self.target = target
    self.sourceIPAddress = sourceIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    self.formFields = formFields
  }

  private enum CodingKeys: String, CodingKey {
    case method
    case target
    case sourceIPAddress
    case formFields
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      method: try container.decode(String.self, forKey: .method),
      target: try container.decode(String.self, forKey: .target),
      sourceIPAddress: try container.decode(String.self, forKey: .sourceIPAddress),
      formFields: try container.decode([String: String].self, forKey: .formFields)
    )
  }
}

struct TopologyRuntimeWebAdministrationResponse: Codable, Equatable, Sendable {
  let statusCode: Int
  let contentType: String
  let body: String
  let detail: String
}

enum TopologyRuntimeWebAdministrationPage: String, CaseIterable, Codable, Equatable, Sendable {
  case status
  case routes
  case dhcp
  case nat
  case firewall

  var path: String {
    switch self {
    case .status: return "/admin"
    case .routes: return "/admin/routes"
    case .dhcp: return "/admin/dhcp"
    case .nat: return "/admin/nat"
    case .firewall: return "/admin/firewall"
    }
  }

  var title: String {
    switch self {
    case .status: return "Status"
    case .routes: return "Routes"
    case .dhcp: return "DHCP"
    case .nat: return "NAT"
    case .firewall: return "Firewall"
    }
  }
}

// MARK: - Read-only administration snapshot

struct TopologyRuntimeWebAdministrationInterfaceStatus: Codable, Equatable, Hashable, Sendable {
  let name: String
  let ipAddress: String
  let subnetMask: String
  let macAddress: String
  let isUp: Bool
}

struct TopologyRuntimeWebAdministrationRouteStatus: Codable, Equatable, Hashable, Sendable {
  let id: String
  let destinationNetwork: String
  let subnetMask: String
  let gatewayIPAddress: String
  let interfaceIPAddress: String
}

struct TopologyRuntimeWebAdministrationDHCPStatus: Codable, Equatable, Sendable {
  let isActive: Bool
  let lowerBoundIPAddress: String
  let upperBoundIPAddress: String
  let gatewayIPAddress: String
  let dnsServerIPAddress: String
  let usesOwnSettings: Bool
  let activeLeaseCount: Int
  let staticAssignmentCount: Int
}

struct TopologyRuntimeWebAdministrationNATMappingStatus: Codable, Equatable, Hashable, Sendable {
  let id: String
  let protocolName: String
  let publicEndpoint: String
  let privateEndpoint: String
  let state: String
}

struct TopologyRuntimeWebAdministrationPortForwardStatus: Codable, Equatable, Hashable, Sendable {
  let id: String
  let protocolName: String
  let publicPort: UInt16
  let lanIPAddress: String
  let lanPort: UInt16
}

struct TopologyRuntimeWebAdministrationFirewallRuleStatus: Codable, Equatable, Hashable, Sendable {
  let id: String
  let source: String
  let destination: String
  let protocolName: String
  let port: String
  let action: String
}

struct TopologyRuntimeWebAdministrationFirewallStatus: Codable, Equatable, Sendable {
  let isActive: Bool
  let defaultPolicy: String
  let dropsICMP: Bool
  let filtersSYNSegmentsOnly: Bool
  let filtersUDP: Bool
  let rules: [TopologyRuntimeWebAdministrationFirewallRuleStatus]
}

/// A deliberately secret-free projection of router or gateway state for read-only pages.
struct TopologyRuntimeWebAdministrationSnapshot: Codable, Equatable, Sendable {
  let deviceName: String
  let deviceKind: String
  let uptimeMilliseconds: UInt64
  let interfaces: [TopologyRuntimeWebAdministrationInterfaceStatus]
  let routes: [TopologyRuntimeWebAdministrationRouteStatus]
  let dhcp: TopologyRuntimeWebAdministrationDHCPStatus
  let natMappings: [TopologyRuntimeWebAdministrationNATMappingStatus]
  let portForwards: [TopologyRuntimeWebAdministrationPortForwardStatus]
  let firewall: TopologyRuntimeWebAdministrationFirewallStatus

  init(
    deviceName: String,
    deviceKind: String,
    uptimeMilliseconds: UInt64,
    interfaces: [TopologyRuntimeWebAdministrationInterfaceStatus],
    routes: [TopologyRuntimeWebAdministrationRouteStatus],
    dhcp: TopologyRuntimeWebAdministrationDHCPStatus,
    natMappings: [TopologyRuntimeWebAdministrationNATMappingStatus],
    portForwards: [TopologyRuntimeWebAdministrationPortForwardStatus],
    firewall: TopologyRuntimeWebAdministrationFirewallStatus
  ) {
    self.deviceName = deviceName
    self.deviceKind = deviceKind
    self.uptimeMilliseconds = uptimeMilliseconds
    self.interfaces = interfaces.sorted { ($0.name, $0.ipAddress) < ($1.name, $1.ipAddress) }
    self.routes = routes.sorted { $0.id < $1.id }
    self.dhcp = dhcp
    self.natMappings = natMappings.sorted { $0.id < $1.id }
    self.portForwards = portForwards.sorted { $0.id < $1.id }
    self.firewall = TopologyRuntimeWebAdministrationFirewallStatus(
      isActive: firewall.isActive,
      defaultPolicy: firewall.defaultPolicy,
      dropsICMP: firewall.dropsICMP,
      filtersSYNSegmentsOnly: firewall.filtersSYNSegmentsOnly,
      filtersUDP: firewall.filtersUDP,
      rules: firewall.rules.sorted { $0.id < $1.id }
    )
  }

  private enum CodingKeys: String, CodingKey {
    case deviceName
    case deviceKind
    case uptimeMilliseconds
    case interfaces
    case routes
    case dhcp
    case natMappings
    case portForwards
    case firewall
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      deviceName: try container.decode(String.self, forKey: .deviceName),
      deviceKind: try container.decode(String.self, forKey: .deviceKind),
      uptimeMilliseconds: try container.decode(UInt64.self, forKey: .uptimeMilliseconds),
      interfaces: try container.decode(
        [TopologyRuntimeWebAdministrationInterfaceStatus].self,
        forKey: .interfaces
      ),
      routes: try container.decode(
        [TopologyRuntimeWebAdministrationRouteStatus].self,
        forKey: .routes
      ),
      dhcp: try container.decode(TopologyRuntimeWebAdministrationDHCPStatus.self, forKey: .dhcp),
      natMappings: try container.decode(
        [TopologyRuntimeWebAdministrationNATMappingStatus].self,
        forKey: .natMappings
      ),
      portForwards: try container.decode(
        [TopologyRuntimeWebAdministrationPortForwardStatus].self,
        forKey: .portForwards
      ),
      firewall: try container.decode(
        TopologyRuntimeWebAdministrationFirewallStatus.self,
        forKey: .firewall
      )
    )
  }

}

/// Renders deterministic administration pages from a secret-free state projection.
enum TopologyRuntimeWebAdministrationRenderer {
  static func render(
    request: TopologyRuntimeWebAdministrationRequest,
    policy: TopologyRuntimeWebAdministrationAccessPolicy,
    snapshot: TopologyRuntimeWebAdministrationSnapshot
  ) -> TopologyRuntimeWebAdministrationResponse {
    guard policy.accessDecision(for: request.sourceIPAddress) == .allowed else {
      return response(statusCode: 403, title: "Forbidden", body: "Administration access denied.")
    }
    guard request.method == "GET" || request.method == "HEAD" else {
      return response(
        statusCode: 405,
        title: "Method Not Allowed",
        body: "Administration page rendering supports GET and HEAD; mutations use POST action endpoints."
      )
    }
    guard let path = try? TopologyRuntimeWebAdministrationSyntax.normalizedPath(request.target),
      let page = TopologyRuntimeWebAdministrationPage.allCases.first(where: { $0.path == path })
    else {
      return response(statusCode: 404, title: "Not Found", body: "Administration page not found.")
    }

    let renderedBody = renderPage(page, snapshot: snapshot)
    let body = request.method == "HEAD" ? "" : renderedBody
    return TopologyRuntimeWebAdministrationResponse(
      statusCode: 200,
      contentType: "text/html; charset=utf-8",
      body: body,
      detail: "Rendered \(page.rawValue) administration page"
    )
  }

  private static func renderPage(
    _ page: TopologyRuntimeWebAdministrationPage,
    snapshot: TopologyRuntimeWebAdministrationSnapshot
  ) -> String {
    let navigation = TopologyRuntimeWebAdministrationPage.allCases.map {
      "<a href=\"\(TopologyRuntimeWebAdministrationHTML.escape($0.path))\">\(TopologyRuntimeWebAdministrationHTML.escape($0.title))</a>"
    }.joined(separator: " | ")

    let content: String
    switch page {
    case .status:
      content = statusContent(snapshot)
    case .routes:
      content = routesContent(snapshot.routes)
    case .dhcp:
      content = dhcpContent(snapshot.dhcp)
    case .nat:
      content = natContent(mappings: snapshot.natMappings, forwards: snapshot.portForwards)
    case .firewall:
      content = firewallContent(snapshot.firewall)
    }

    return """
      <!doctype html>
      <html lang="en">
      <head><meta charset="utf-8"><title>Filius \(TopologyRuntimeWebAdministrationHTML.escape(page.title))</title></head>
      <body>
      <header><h1>\(TopologyRuntimeWebAdministrationHTML.escape(snapshot.deviceName))</h1><nav>\(navigation)</nav></header>
      <main><h2>\(TopologyRuntimeWebAdministrationHTML.escape(page.title))</h2>\(content)</main>
      </body>
      </html>
      """
  }

  private static func statusContent(_ snapshot: TopologyRuntimeWebAdministrationSnapshot) -> String
  {
    let rows = snapshot.interfaces.map {
      row([
        $0.name,
        $0.ipAddress,
        $0.subnetMask,
        $0.macAddress,
        $0.isUp ? "up" : "down",
      ])
    }.joined()
    return """
      <dl>
      <dt>Device kind</dt><dd>\(TopologyRuntimeWebAdministrationHTML.escape(snapshot.deviceKind))</dd>
      <dt>Uptime</dt><dd>\(snapshot.uptimeMilliseconds) ms</dd>
      </dl>
      \(table(headers: ["Interface", "IP address", "Subnet mask", "MAC address", "State"], rows: rows))
      """
  }

  private static func routesContent(_ routes: [TopologyRuntimeWebAdministrationRouteStatus])
    -> String
  {
    let rows = routes.map {
      row([$0.id, $0.destinationNetwork, $0.subnetMask, $0.gatewayIPAddress, $0.interfaceIPAddress])
    }.joined()
    let deleteForms = routes.map {
      form(
        action: "/admin/actions/routes/delete",
        legend: "Delete route \($0.id)",
        fields: [("id", $0.id)],
        submitLabel: "Delete"
      )
    }.joined()
    return """
      \(table(headers: ["ID", "Destination", "Subnet mask", "Gateway", "Interface"], rows: rows))
      <h3>Add route</h3>
      \(form(
        action: "/admin/actions/routes/add",
        legend: "Add route",
        fields: [
          ("destinationNetwork", ""), ("subnetMask", "255.255.255.0"),
          ("gatewayIPAddress", "0.0.0.0"), ("interfaceIPAddress", "0.0.0.0"),
        ],
        submitLabel: "Add"
      ))
      <h3>Delete routes</h3>\(deleteForms.isEmpty ? "<p>No manual routes.</p>" : deleteForms)
      """
  }

  private static func dhcpContent(_ dhcp: TopologyRuntimeWebAdministrationDHCPStatus) -> String {
    let rows = [
      row(["Active", yesNo(dhcp.isActive)]),
      row(["Pool lower bound", dhcp.lowerBoundIPAddress]),
      row(["Pool upper bound", dhcp.upperBoundIPAddress]),
      row(["Gateway", dhcp.gatewayIPAddress]),
      row(["DNS server", dhcp.dnsServerIPAddress]),
      row(["Own settings", yesNo(dhcp.usesOwnSettings)]),
      row(["Active leases", String(dhcp.activeLeaseCount)]),
      row(["Static assignments", String(dhcp.staticAssignmentCount)]),
    ].joined()
    return """
      \(table(headers: ["Setting", "Value"], rows: rows))
      <h3>Update DHCP</h3>
      <form method="post" action="/admin/actions/dhcp/update">
      \(select(name: "isActive", value: dhcp.isActive))
      \(input(name: "lowerBoundIPAddress", value: dhcp.lowerBoundIPAddress))
      \(input(name: "upperBoundIPAddress", value: dhcp.upperBoundIPAddress))
      \(input(name: "gatewayIPAddress", value: dhcp.gatewayIPAddress))
      \(input(name: "dnsServerIPAddress", value: dhcp.dnsServerIPAddress))
      \(select(name: "usesOwnSettings", value: dhcp.usesOwnSettings))
      <button type="submit">Save DHCP</button></form>
      """
  }

  private static func natContent(
    mappings: [TopologyRuntimeWebAdministrationNATMappingStatus],
    forwards: [TopologyRuntimeWebAdministrationPortForwardStatus]
  ) -> String {
    let mappingRows = mappings.map {
      row([$0.id, $0.protocolName, $0.publicEndpoint, $0.privateEndpoint, $0.state])
    }.joined()
    let forwardRows = forwards.map {
      row([$0.id, $0.protocolName, String($0.publicPort), $0.lanIPAddress, String($0.lanPort)])
    }.joined()
    let deleteForms = forwards.map {
      form(
        action: "/admin/actions/nat/port-forwards/delete",
        legend: "Delete port forward \($0.id)",
        fields: [("id", $0.id)],
        submitLabel: "Delete"
      )
    }.joined()
    return """
      <h3>Active mappings</h3>
      \(table(headers: ["ID", "Protocol", "Public endpoint", "Private endpoint", "State"], rows: mappingRows))
      \(form(action: "/admin/actions/nat/mappings/clear", legend: "Clear dynamic NAT mappings", fields: [], submitLabel: "Clear"))
      <h3>Port forwards</h3>
      \(table(headers: ["ID", "Protocol", "Public port", "LAN address", "LAN port"], rows: forwardRows))
      \(form(
        action: "/admin/actions/nat/port-forwards/add",
        legend: "Add port forward",
        fields: [("id", "forward-1"), ("protocol", "tcp"), ("publicPort", "80"), ("lanIPAddress", "0.0.0.0"), ("lanPort", "80")],
        submitLabel: "Add"
      ))
      \(deleteForms)
      """
  }

  private static func firewallContent(_ firewall: TopologyRuntimeWebAdministrationFirewallStatus)
    -> String
  {
    let settings = [
      row(["Active", yesNo(firewall.isActive)]),
      row(["Default policy", firewall.defaultPolicy]),
      row(["Drop ICMP", yesNo(firewall.dropsICMP)]),
      row(["SYN only", yesNo(firewall.filtersSYNSegmentsOnly)]),
      row(["Filter UDP", yesNo(firewall.filtersUDP)]),
    ].joined()
    let rules = firewall.rules.map {
      row([$0.id, $0.source, $0.destination, $0.protocolName, $0.port, $0.action])
    }.joined()
    let deleteForms = firewall.rules.map {
      form(
        action: "/admin/actions/firewall/rules/delete",
        legend: "Delete firewall rule \($0.id)",
        fields: [("id", $0.id)],
        submitLabel: "Delete"
      )
    }.joined()
    return """
      \(table(headers: ["Setting", "Value"], rows: settings))
      <form method="post" action="/admin/actions/firewall/update">
      \(select(name: "isActive", value: firewall.isActive))
      \(select(name: "defaultPolicy", options: ["accept", "drop"], selected: firewall.defaultPolicy.lowercased().contains("accept") ? "accept" : "drop"))
      \(select(name: "dropsICMP", value: firewall.dropsICMP))
      \(select(name: "filtersSYNSegmentsOnly", value: firewall.filtersSYNSegmentsOnly))
      \(select(name: "filtersUDP", value: firewall.filtersUDP))
      <button type="submit">Save firewall settings</button></form>
      <h3>Rules</h3>
      \(table(headers: ["ID", "Source", "Destination", "Protocol", "Port", "Action"], rows: rules))
      \(form(
        action: "/admin/actions/firewall/rules/add",
        legend: "Add firewall rule",
        fields: [
          ("id", "rule-1"), ("sourceIPAddress", "0.0.0.0"), ("sourceSubnetMask", "0.0.0.0"),
          ("destinationIPAddress", "0.0.0.0"), ("destinationSubnetMask", "0.0.0.0"),
          ("port", "-1"), ("protocol", "all"), ("action", "drop"),
        ],
        submitLabel: "Add"
      ))
      \(deleteForms)
      """
  }

  static func mutationResponse(
    statusCode: Int,
    title: String,
    detail: String,
    returnPath: String = "/admin"
  ) -> TopologyRuntimeWebAdministrationResponse {
    let safePath = TopologyRuntimeWebAdministrationHTML.escape(returnPath)
    let safeDetail = TopologyRuntimeWebAdministrationHTML.escape(detail)
    return TopologyRuntimeWebAdministrationResponse(
      statusCode: statusCode,
      contentType: "text/html; charset=utf-8",
      body: "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>\(TopologyRuntimeWebAdministrationHTML.escape(title))</title></head><body><h1>\(TopologyRuntimeWebAdministrationHTML.escape(title))</h1><p>\(safeDetail)</p><p><a href=\"\(safePath)\">Return to administration</a></p></body></html>",
      detail: detail
    )
  }

  private static func form(
    action: String,
    legend: String,
    fields: [(String, String)],
    submitLabel: String
  ) -> String {
    let controls = fields.map { input(name: $0.0, value: $0.1) }.joined()
    return "<form method=\"post\" action=\"\(TopologyRuntimeWebAdministrationHTML.escape(action))\"><fieldset><legend>\(TopologyRuntimeWebAdministrationHTML.escape(legend))</legend>\(controls)<button type=\"submit\">\(TopologyRuntimeWebAdministrationHTML.escape(submitLabel))</button></fieldset></form>"
  }

  private static func input(name: String, value: String) -> String {
    let escapedName = TopologyRuntimeWebAdministrationHTML.escape(name)
    let escapedValue = TopologyRuntimeWebAdministrationHTML.escape(value)
    return "<label>\(escapedName)<input name=\"\(escapedName)\" value=\"\(escapedValue)\"></label>"
  }

  private static func select(name: String, value: Bool) -> String {
    select(name: name, options: ["true", "false"], selected: value ? "true" : "false")
  }

  private static func select(name: String, options: [String], selected: String) -> String {
    let escapedName = TopologyRuntimeWebAdministrationHTML.escape(name)
    let renderedOptions = options.map { option in
      let safe = TopologyRuntimeWebAdministrationHTML.escape(option)
      return "<option value=\"\(safe)\"\(option == selected ? " selected" : "")>\(safe)</option>"
    }.joined()
    return "<label>\(escapedName)<select name=\"\(escapedName)\">\(renderedOptions)</select></label>"
  }

  private static func table(headers: [String], rows: String) -> String {
    let header = headers.map { "<th>\(TopologyRuntimeWebAdministrationHTML.escape($0))</th>" }
      .joined()
    let bodyRows = rows.isEmpty ? row(["No entries"], columnSpan: headers.count) : rows
    return "<table><thead><tr>\(header)</tr></thead><tbody>\(bodyRows)</tbody></table>"
  }

  private static func row(_ values: [String], columnSpan: Int? = nil) -> String {
    if let columnSpan {
      return
        "<tr><td colspan=\"\(columnSpan)\">\(TopologyRuntimeWebAdministrationHTML.escape(values[0]))</td></tr>"
    }
    return "<tr>"
      + values.map { "<td>\(TopologyRuntimeWebAdministrationHTML.escape($0))</td>" }.joined()
      + "</tr>"
  }

  private static func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }

  private static func response(
    statusCode: Int,
    title: String,
    body: String
  ) -> TopologyRuntimeWebAdministrationResponse {
    TopologyRuntimeWebAdministrationResponse(
      statusCode: statusCode,
      contentType: "text/html; charset=utf-8",
      body:
        "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>\(TopologyRuntimeWebAdministrationHTML.escape(title))</title></head><body><h1>\(TopologyRuntimeWebAdministrationHTML.escape(title))</h1><p>\(TopologyRuntimeWebAdministrationHTML.escape(body))</p></body></html>",
      detail: title
    )
  }
}

// MARK: - Form decoding

enum TopologyRuntimeWebAdministrationFormDecodingError: Error, Equatable, LocalizedError {
  case bodyTooLarge
  case invalidUTF8
  case invalidField
  case duplicateField(String)

  var errorDescription: String? {
    switch self {
    case .bodyTooLarge: return "Administration form body exceeds the 16 KiB limit."
    case .invalidUTF8: return "Administration form body must be UTF-8."
    case .invalidField: return "Administration form contains an invalid field."
    case .duplicateField(let name): return "Administration form field is duplicated: \(name)."
    }
  }
}

enum TopologyRuntimeWebAdministrationFormDecoder {
  static let maximumBodyBytes = 16 * 1_024

  static func decode(
    _ body: Data
  ) -> Result<[String: String], TopologyRuntimeWebAdministrationFormDecodingError> {
    guard body.count <= maximumBodyBytes else { return .failure(.bodyTooLarge) }
    guard !body.isEmpty else { return .success([:]) }
    guard let text = String(data: body, encoding: .utf8) else { return .failure(.invalidUTF8) }

    var fields: [String: String] = [:]
    for pair in text.split(separator: "&", omittingEmptySubsequences: false) {
      guard !pair.isEmpty else { continue }
      let components = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard let rawName = components.first,
        let name = decodeComponent(String(rawName)),
        !name.isEmpty,
        name.utf8.count <= 128,
        !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
      else { return .failure(.invalidField) }
      let rawValue = components.count == 2 ? String(components[1]) : ""
      guard let value = decodeComponent(rawValue), value.utf8.count <= 4_096,
        !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\t" })
      else { return .failure(.invalidField) }
      guard fields[name] == nil else { return .failure(.duplicateField(name)) }
      fields[name] = value
    }
    return .success(fields)
  }

  private static func decodeComponent(_ value: String) -> String? {
    value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
  }
}

// MARK: - Typed mutation intents

struct TopologyRuntimeWebAdministrationRouteMutation: Codable, Equatable, Sendable {
  let id: String?
  let destinationNetwork: String
  let subnetMask: String
  let gatewayIPAddress: String
  let interfaceIPAddress: String
}

struct TopologyRuntimeWebAdministrationDHCPMutation: Codable, Equatable, Sendable {
  let isActive: Bool
  let lowerBoundIPAddress: String
  let upperBoundIPAddress: String
  let gatewayIPAddress: String
  let dnsServerIPAddress: String
  let usesOwnSettings: Bool
}

enum TopologyRuntimeWebAdministrationTransportProtocol: String, Codable, Equatable, Sendable {
  case tcp
  case udp
}

struct TopologyRuntimeWebAdministrationPortForwardMutation: Codable, Equatable, Sendable {
  let id: String
  let protocolKind: TopologyRuntimeWebAdministrationTransportProtocol
  let publicPort: UInt16
  let lanIPAddress: String
  let lanPort: UInt16
}

enum TopologyRuntimeWebAdministrationFirewallProtocol: String, Codable, Equatable, Sendable {
  case all
  case icmp
  case tcp
  case udp
}

enum TopologyRuntimeWebAdministrationFirewallAction: String, Codable, Equatable, Sendable {
  case accept
  case drop
}

struct TopologyRuntimeWebAdministrationFirewallSettingsMutation: Codable, Equatable, Sendable {
  let isActive: Bool
  let defaultPolicy: TopologyRuntimeWebAdministrationFirewallAction
  let dropsICMP: Bool
  let filtersSYNSegmentsOnly: Bool
  let filtersUDP: Bool
}

struct TopologyRuntimeWebAdministrationFirewallRuleMutation: Codable, Equatable, Sendable {
  let id: String
  let sourceIPAddress: String
  let sourceSubnetMask: String
  let destinationIPAddress: String
  let destinationSubnetMask: String
  let port: Int
  let protocolKind: TopologyRuntimeWebAdministrationFirewallProtocol
  let action: TopologyRuntimeWebAdministrationFirewallAction
}

enum TopologyRuntimeWebAdministrationMutationIntent: Codable, Equatable, Sendable {
  case addRoute(TopologyRuntimeWebAdministrationRouteMutation)
  case deleteRoute(id: String)
  case updateDHCP(TopologyRuntimeWebAdministrationDHCPMutation)
  case addPortForward(TopologyRuntimeWebAdministrationPortForwardMutation)
  case deletePortForward(id: String)
  case clearNATMappings
  case updateFirewall(TopologyRuntimeWebAdministrationFirewallSettingsMutation)
  case addFirewallRule(TopologyRuntimeWebAdministrationFirewallRuleMutation)
  case deleteFirewallRule(id: String)
}

enum TopologyRuntimeWebAdministrationMutationError: Error, Equatable, LocalizedError {
  case accessDenied(TopologyRuntimeWebAdministrationAccessDecision)
  case methodNotAllowed
  case unknownAction
  case missingFields([String])
  case unexpectedFields([String])
  case invalidField(String)
  case invalidAddressRange

  var errorDescription: String? {
    switch self {
    case .accessDenied:
      return "Administration access denied."
    case .methodNotAllowed:
      return "Administration mutations require POST."
    case .unknownAction:
      return "Unknown administration action."
    case .missingFields(let fields):
      return "Missing required administration fields: \(fields.sorted().joined(separator: ", "))."
    case .unexpectedFields(let fields):
      return "Unexpected administration fields: \(fields.sorted().joined(separator: ", "))."
    case .invalidField(let field):
      return "Invalid administration field: \(field)."
    case .invalidAddressRange:
      return "The DHCP lower bound must not exceed the upper bound."
    }
  }
}

/// Validates web form fields into a typed intent. It never mutates topology or runtime state.
enum TopologyRuntimeWebAdministrationMutationValidator {
  static func validate(
    request: TopologyRuntimeWebAdministrationRequest,
    policy: TopologyRuntimeWebAdministrationAccessPolicy
  ) throws -> TopologyRuntimeWebAdministrationMutationIntent {
    let decision = policy.accessDecision(for: request.sourceIPAddress)
    guard decision == .allowed else {
      throw TopologyRuntimeWebAdministrationMutationError.accessDenied(decision)
    }
    guard request.method == "POST" else {
      throw TopologyRuntimeWebAdministrationMutationError.methodNotAllowed
    }
    guard let path = try? TopologyRuntimeWebAdministrationSyntax.normalizedPath(request.target)
    else {
      throw TopologyRuntimeWebAdministrationMutationError.unknownAction
    }

    switch path {
    case "/admin/actions/routes/add":
      try validateFieldSet(
        request.formFields,
        required: ["destinationNetwork", "subnetMask", "gatewayIPAddress", "interfaceIPAddress"],
        optional: ["id"]
      )
      let destination = try ipv4Field("destinationNetwork", in: request.formFields)
      let mask = try maskField("subnetMask", in: request.formFields)
      let gateway = try ipv4Field("gatewayIPAddress", in: request.formFields)
      let interfaceAddress = try ipv4Field("interfaceIPAddress", in: request.formFields)
      guard
        TopologyRuntimeWebAdministrationIPv4.numericValue(destination)
          & TopologyRuntimeWebAdministrationIPv4.numericValue(mask)
          == TopologyRuntimeWebAdministrationIPv4.numericValue(destination)
      else {
        throw TopologyRuntimeWebAdministrationMutationError.invalidField("destinationNetwork")
      }
      let id = try request.formFields["id"].map { try identifier($0, field: "id") }
      return .addRoute(
        TopologyRuntimeWebAdministrationRouteMutation(
          id: id,
          destinationNetwork: destination,
          subnetMask: mask,
          gatewayIPAddress: gateway,
          interfaceIPAddress: interfaceAddress
        )
      )

    case "/admin/actions/routes/delete":
      try validateFieldSet(request.formFields, required: ["id"])
      return .deleteRoute(id: try identifierField("id", in: request.formFields))

    case "/admin/actions/dhcp/update":
      try validateFieldSet(
        request.formFields,
        required: [
          "isActive", "lowerBoundIPAddress", "upperBoundIPAddress",
          "gatewayIPAddress", "dnsServerIPAddress", "usesOwnSettings",
        ]
      )
      let lower = try ipv4Field("lowerBoundIPAddress", in: request.formFields)
      let upper = try ipv4Field("upperBoundIPAddress", in: request.formFields)
      guard
        TopologyRuntimeWebAdministrationIPv4.numericValue(lower)
          <= TopologyRuntimeWebAdministrationIPv4.numericValue(upper)
      else {
        throw TopologyRuntimeWebAdministrationMutationError.invalidAddressRange
      }
      return .updateDHCP(
        TopologyRuntimeWebAdministrationDHCPMutation(
          isActive: try boolField("isActive", in: request.formFields),
          lowerBoundIPAddress: lower,
          upperBoundIPAddress: upper,
          gatewayIPAddress: try ipv4Field("gatewayIPAddress", in: request.formFields),
          dnsServerIPAddress: try ipv4Field("dnsServerIPAddress", in: request.formFields),
          usesOwnSettings: try boolField("usesOwnSettings", in: request.formFields)
        )
      )

    case "/admin/actions/nat/port-forwards/add":
      try validateFieldSet(
        request.formFields,
        required: ["id", "protocol", "publicPort", "lanIPAddress", "lanPort"]
      )
      return .addPortForward(
        TopologyRuntimeWebAdministrationPortForwardMutation(
          id: try identifierField("id", in: request.formFields),
          protocolKind: try enumField("protocol", in: request.formFields),
          publicPort: try portField("publicPort", in: request.formFields),
          lanIPAddress: try ipv4Field("lanIPAddress", in: request.formFields),
          lanPort: try portField("lanPort", in: request.formFields)
        )
      )

    case "/admin/actions/nat/port-forwards/delete":
      try validateFieldSet(request.formFields, required: ["id"])
      return .deletePortForward(id: try identifierField("id", in: request.formFields))

    case "/admin/actions/nat/mappings/clear":
      try validateFieldSet(request.formFields, required: [])
      return .clearNATMappings

    case "/admin/actions/firewall/update":
      try validateFieldSet(
        request.formFields,
        required: [
          "isActive", "defaultPolicy", "dropsICMP", "filtersSYNSegmentsOnly", "filtersUDP",
        ]
      )
      return .updateFirewall(
        TopologyRuntimeWebAdministrationFirewallSettingsMutation(
          isActive: try boolField("isActive", in: request.formFields),
          defaultPolicy: try enumField("defaultPolicy", in: request.formFields),
          dropsICMP: try boolField("dropsICMP", in: request.formFields),
          filtersSYNSegmentsOnly: try boolField("filtersSYNSegmentsOnly", in: request.formFields),
          filtersUDP: try boolField("filtersUDP", in: request.formFields)
        )
      )

    case "/admin/actions/firewall/rules/add":
      try validateFieldSet(
        request.formFields,
        required: [
          "id", "sourceIPAddress", "sourceSubnetMask", "destinationIPAddress",
          "destinationSubnetMask", "port", "protocol", "action",
        ]
      )
      let portText = request.formFields["port"] ?? ""
      guard let port = Int(portText), port == -1 || (1...65_535).contains(port) else {
        throw TopologyRuntimeWebAdministrationMutationError.invalidField("port")
      }
      let protocolKind: TopologyRuntimeWebAdministrationFirewallProtocol = try enumField(
        "protocol",
        in: request.formFields
      )
      guard (protocolKind == .tcp || protocolKind == .udp) || port == -1 else {
        throw TopologyRuntimeWebAdministrationMutationError.invalidField("port")
      }
      return .addFirewallRule(
        TopologyRuntimeWebAdministrationFirewallRuleMutation(
          id: try identifierField("id", in: request.formFields),
          sourceIPAddress: try ipv4Field("sourceIPAddress", in: request.formFields),
          sourceSubnetMask: try maskField("sourceSubnetMask", in: request.formFields),
          destinationIPAddress: try ipv4Field("destinationIPAddress", in: request.formFields),
          destinationSubnetMask: try maskField("destinationSubnetMask", in: request.formFields),
          port: port,
          protocolKind: protocolKind,
          action: try enumField("action", in: request.formFields)
        )
      )

    case "/admin/actions/firewall/rules/delete":
      try validateFieldSet(request.formFields, required: ["id"])
      return .deleteFirewallRule(id: try identifierField("id", in: request.formFields))

    default:
      throw TopologyRuntimeWebAdministrationMutationError.unknownAction
    }
  }

  private static func validateFieldSet(
    _ fields: [String: String],
    required: Set<String>,
    optional: Set<String> = []
  ) throws {
    let provided = Set(fields.keys)
    let missing = required.subtracting(provided)
    guard missing.isEmpty else {
      throw TopologyRuntimeWebAdministrationMutationError.missingFields(missing.sorted())
    }
    let unexpected = provided.subtracting(required.union(optional))
    guard unexpected.isEmpty else {
      throw TopologyRuntimeWebAdministrationMutationError.unexpectedFields(unexpected.sorted())
    }
  }

  private static func ipv4Field(_ name: String, in fields: [String: String]) throws -> String {
    guard let value = fields[name],
      let parsed = try? TopologyRuntimeWebAdministrationIPv4.parse(value)
    else {
      throw TopologyRuntimeWebAdministrationMutationError.invalidField(name)
    }
    return TopologyRuntimeWebAdministrationIPv4.string(parsed)
  }

  private static func maskField(_ name: String, in fields: [String: String]) throws -> String {
    guard let value = fields[name],
      let parsed = try? TopologyRuntimeWebAdministrationIPv4.parseContiguousMask(value)
    else {
      throw TopologyRuntimeWebAdministrationMutationError.invalidField(name)
    }
    return TopologyRuntimeWebAdministrationIPv4.string(parsed)
  }

  private static func boolField(_ name: String, in fields: [String: String]) throws -> Bool {
    switch fields[name]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "true", "1", "on", "yes": return true
    case "false", "0", "off", "no": return false
    default: throw TopologyRuntimeWebAdministrationMutationError.invalidField(name)
    }
  }

  private static func portField(_ name: String, in fields: [String: String]) throws -> UInt16 {
    guard let text = fields[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
      let value = Int(text), (1...65_535).contains(value)
    else {
      throw TopologyRuntimeWebAdministrationMutationError.invalidField(name)
    }
    return UInt16(value)
  }

  private static func identifierField(_ name: String, in fields: [String: String]) throws -> String
  {
    guard let value = fields[name] else {
      throw TopologyRuntimeWebAdministrationMutationError.invalidField(name)
    }
    return try identifier(value, field: name)
  }

  private static func identifier(_ value: String, field: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty,
      normalized.utf8.count <= 128,
      normalized.unicodeScalars.allSatisfy({
        CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" || $0 == "."
      })
    else {
      throw TopologyRuntimeWebAdministrationMutationError.invalidField(field)
    }
    return normalized
  }

  private static func enumField<Value: RawRepresentable>(
    _ name: String,
    in fields: [String: String]
  ) throws -> Value where Value.RawValue == String {
    guard let rawValue = fields[name]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      let value = Value(rawValue: rawValue)
    else {
      throw TopologyRuntimeWebAdministrationMutationError.invalidField(name)
    }
    return value
  }
}

private enum TopologyRuntimeWebAdministrationSyntax {
  static func normalizedPath(_ target: String) throws -> String {
    let path =
      target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
      .first.map(String.init) ?? ""
    guard path.hasPrefix("/"),
      !path.hasPrefix("//"),
      !path.contains("%"),
      !path.contains("\\"),
      path.utf8.count <= 1_024,
      !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else {
      throw TopologyRuntimeWebAdministrationMutationError.unknownAction
    }
    return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
  }
}

private enum TopologyRuntimeWebAdministrationIPv4 {
  static func parse(_ value: String) throws -> UInt32 {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let segments = normalized.split(separator: ".", omittingEmptySubsequences: false)
    guard segments.count == 4 else {
      throw TopologyRuntimeWebAdministrationMutationError.invalidField("ipAddress")
    }

    var result = UInt32(0)
    for segment in segments {
      guard !segment.isEmpty,
        segment.allSatisfy(\.isNumber),
        segment.count == 1 || segment.first != "0",
        let octet = UInt8(segment)
      else {
        throw TopologyRuntimeWebAdministrationMutationError.invalidField("ipAddress")
      }
      result = (result << 8) | UInt32(octet)
    }
    return result
  }

  static func parseContiguousMask(_ value: String) throws -> UInt32 {
    let mask = try parse(value)
    let inverted = ~mask
    guard inverted & (inverted &+ 1) == 0 else {
      throw TopologyRuntimeWebAdministrationMutationError.invalidField("subnetMask")
    }
    return mask
  }

  static func string(_ value: UInt32) -> String {
    [24, 16, 8, 0].map { String((value >> UInt32($0)) & 0xff) }.joined(separator: ".")
  }

  static func numericValue(_ value: String) -> UInt32 {
    (try? parse(value)) ?? 0
  }
}

private enum TopologyRuntimeWebAdministrationHTML {
  static func escape(_ value: String) -> String {
    var result = ""
    result.reserveCapacity(value.count)
    for character in value {
      switch character {
      case "&": result += "&amp;"
      case "<": result += "&lt;"
      case ">": result += "&gt;"
      case "\"": result += "&quot;"
      case "'": result += "&#39;"
      default: result.append(character)
      }
    }
    return result
  }
}
