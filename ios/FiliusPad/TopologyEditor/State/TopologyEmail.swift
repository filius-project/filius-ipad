import CryptoKit
import Foundation

private let javaEmailBodySentinels = ["&&00036&&", "&&00059&&", "&&00124&&", "&&00035&&"]

private func validateJavaEmailAccountField(_ value: String, label: String) throws {
    guard !value.contains(";"), !value.contains("\r"), !value.contains("\n") else {
        throw TopologyRuntimeEmailValidationError.javaStorageIncompatible(label)
    }
}

private func validateJavaEmailMessageField(_ value: String, label: String) throws {
    guard !value.contains(where: { ";$#\r\n".contains($0) }) else {
        throw TopologyRuntimeEmailValidationError.javaStorageIncompatible(label)
    }
}

private func validateJavaEmailAddressField(_ value: String, label: String) throws {
    guard !value.contains(where: { ";$#,\r\n".contains($0) }) else {
        throw TopologyRuntimeEmailValidationError.javaStorageIncompatible(label)
    }
}

private func validateJavaEmailBody(_ value: String) throws {
    guard !javaEmailBodySentinels.contains(where: value.contains) else {
        throw TopologyRuntimeEmailValidationError.javaStorageIncompatible("message body sentinel")
    }
}

struct TopologyRuntimeEmailAddress: Codable, Equatable, Hashable {
    var name: String?
    var mailAddress: String

    init(name: String? = nil, mailAddress: String) {
        let n = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = n?.isEmpty == true ? nil : n
        self.mailAddress = mailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init?(javaString: String) {
        let value = javaString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = value.firstIndex(of: "<"), let close = value[open...].firstIndex(of: ">"), close > open {
            self.init(name: String(value[..<open]), mailAddress: String(value[value.index(after: open)..<close]))
        } else if value.contains("@") && !value.contains("<") && !value.contains(">") {
            self.init(mailAddress: value)
        } else { return nil }
        guard (try? validate()) != nil else { return nil }
    }

    var normalizedMailAddress: String { mailAddress.lowercased() }
    var javaString: String { name.map { "\($0) <\(mailAddress)>" } ?? "<\(mailAddress)>" }

    func validate() throws {
        guard (name?.count ?? 0) <= 128, mailAddress.count <= 320,
              !mailAddress.contains(where: { $0.isWhitespace }),
              !mailAddress.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw TopologyRuntimeEmailValidationError.invalidAddress(mailAddress) }
        let parts = mailAddress.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { throw TopologyRuntimeEmailValidationError.invalidAddress(mailAddress) }
        let local = String(parts[0]), domain = String(parts[1]).lowercased()
        guard !local.isEmpty, local.count <= 64, local.first != ".", local.last != ".", !local.contains(".."),
              local.allSatisfy({ $0.isLetter || $0.isNumber || "!#$%&'*+-/=?^_`{|}~.".contains($0) }),
              Self.isValidDomain(domain)
        else { throw TopologyRuntimeEmailValidationError.invalidAddress(mailAddress) }
    }

    static func isValidDomain(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 253, !value.hasPrefix("."), !value.hasSuffix("."), !value.contains("..") else { return false }
        return value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0.count <= 63 && $0.first != "-" && $0.last != "-" && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}

struct TopologyRuntimeEmailMessage: Codable, Equatable, Identifiable {
    static let unassignedID: UInt64 = 0
    static let maximumRecipients = 100
    static let maximumBodyBytes = 65_536
    static let maximumWireBytes = 131_072

    var id: UInt64
    var from: TopologyRuntimeEmailAddress
    var to: [TopologyRuntimeEmailAddress]
    var cc: [TopologyRuntimeEmailAddress]
    var bcc: [TopologyRuntimeEmailAddress]
    var subject: String
    var body: String
    var deliveryIdentity: String?
    var receivedAtMilliseconds: UInt64?
    var isNew: Bool
    var isMarkedForDeletion: Bool
    var isSent: Bool

    init(id: UInt64 = 0, from: TopologyRuntimeEmailAddress, to: [TopologyRuntimeEmailAddress], cc: [TopologyRuntimeEmailAddress] = [], bcc: [TopologyRuntimeEmailAddress] = [], subject: String = "", body: String = "", deliveryIdentity: String? = nil, receivedAtMilliseconds: UInt64? = nil, isNew: Bool = true, isMarkedForDeletion: Bool = false, isSent: Bool = false) {
        self.id = id; self.from = from; self.to = to; self.cc = cc; self.bcc = bcc; self.subject = subject; self.body = body
        self.deliveryIdentity = deliveryIdentity; self.receivedAtMilliseconds = receivedAtMilliseconds; self.isNew = isNew; self.isMarkedForDeletion = isMarkedForDeletion; self.isSent = isSent
    }

    var envelopeRecipients: [TopologyRuntimeEmailAddress] {
        var seen = Set<String>()
        return (to + cc + bcc).filter { seen.insert($0.normalizedMailAddress).inserted }
    }

    var javaWireString: String { wireString(includingDeliveryIdentity: true) }

    fileprivate var idempotencyPayloadString: String { wireString(includingDeliveryIdentity: false) }

    private func wireString(includingDeliveryIdentity: Bool) -> String {
        var lines = ["From: \(from.javaString)"]
        if !to.isEmpty { lines.append("To: \(to.map(\.javaString).joined(separator: ", "))") }
        if !cc.isEmpty { lines.append("Cc: \(cc.map(\.javaString).joined(separator: ", "))") }
        if !subject.isEmpty { lines.append("Subject: \(subject.trimmingCharacters(in: .whitespacesAndNewlines))") }
        if includingDeliveryIdentity, let deliveryIdentity {
            lines.append("\(TopologyRuntimeEmailDeliveryIdentity.headerName): \(deliveryIdentity)")
        }
        if let receivedAtMilliseconds { lines.append("Date Received: \(receivedAtMilliseconds)") }
        return lines.joined(separator: "\r\n") + "\r\n\r\n" + body
    }

    func validate(requireRecipients: Bool = true) throws {
        try from.validate(); for address in to + cc + bcc { try address.validate() }
        guard !requireRecipients || !envelopeRecipients.isEmpty else { throw TopologyRuntimeEmailValidationError.missingRecipient }
        guard envelopeRecipients.count <= Self.maximumRecipients else { throw TopologyRuntimeEmailValidationError.tooManyRecipients }
        guard subject.count <= 256, !subject.unicodeScalars.contains(where: { CharacterSet.newlines.contains($0) }) else { throw TopologyRuntimeEmailValidationError.invalidSubject }
        guard body.lengthOfBytes(using: .utf8) <= Self.maximumBodyBytes, javaWireString.lengthOfBytes(using: .utf8) <= Self.maximumWireBytes else { throw TopologyRuntimeEmailValidationError.messageTooLarge }
        guard deliveryIdentity == nil || TopologyRuntimeEmailDeliveryIdentity.isValid(deliveryIdentity!) else {
            throw TopologyRuntimeEmailValidationError.invalidDeliveryIdentity
        }
        try validateJavaEmailAddressField(from.javaString, label: "sender")
        for address in to + cc + bcc { try validateJavaEmailAddressField(address.javaString, label: "recipient") }
        try validateJavaEmailMessageField(subject, label: "subject")
        try validateJavaEmailBody(body)
    }

    static func parseJavaWireString(_ value: String, id: UInt64 = 0) throws -> Self {
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n")
        let sections = normalized.components(separatedBy: "\n\n")
        var sender: TopologyRuntimeEmailAddress?, to: [TopologyRuntimeEmailAddress] = [], cc: [TopologyRuntimeEmailAddress] = [], subject = "", deliveryIdentity: String?
        for line in sections.first?.components(separatedBy: "\n") ?? [] {
            let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }
            let key = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            func addresses(_ raw: String) throws -> [TopologyRuntimeEmailAddress] {
                try raw.split(separator: ",").map { guard let a = TopologyRuntimeEmailAddress(javaString: String($0)) else { throw TopologyRuntimeEmailValidationError.invalidAddress(String($0)) }; return a }
            }
            if key == "from" { sender = TopologyRuntimeEmailAddress(javaString: value) }
            else if key == "to" { to = try addresses(value) }
            else if key == "cc" { cc = try addresses(value) }
            else if key == "subject" { subject = value }
            else if key == TopologyRuntimeEmailDeliveryIdentity.headerName.lowercased() { deliveryIdentity = value.lowercased() }
        }
        guard let sender else { throw TopologyRuntimeEmailValidationError.malformedMessage }
        let message = Self(id: id, from: sender, to: to, cc: cc, subject: subject, body: sections.dropFirst().joined(separator: "\n\n"), deliveryIdentity: deliveryIdentity)
        try message.validate(requireRecipients: false); return message
    }
}

enum TopologyRuntimeEmailDeliveryIdentity {
    static let headerName = "X-FiliusPad-Delivery-ID"
    private static let version = "filiuspad-email-delivery-v1"

    static func make(
        originNodeID: UUID,
        messageID: UInt64,
        message: TopologyRuntimeEmailMessage
    ) -> String {
        digest(
            fields: [
                version,
                originNodeID.uuidString.lowercased(),
                String(messageID),
                message.idempotencyPayloadString,
            ] + message.envelopeRecipients.map(\.normalizedMailAddress)
        )
    }

    static func contentSignature(
        message: TopologyRuntimeEmailMessage,
        recipients: [TopologyRuntimeEmailAddress]
    ) -> String {
        digest(
            fields: [version, message.idempotencyPayloadString]
                + recipients.map(\.normalizedMailAddress)
        )
    }

    static func isValid(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
        }
    }

    private static func digest(fields: [String]) -> String {
        var input = Data()
        for field in fields {
            let bytes = Data(field.utf8)
            var length = UInt64(bytes.count).bigEndian
            withUnsafeBytes(of: &length) { input.append(contentsOf: $0) }
            input.append(bytes)
        }
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }
}

struct TopologyRuntimeEmailClientConfiguration: Codable, Equatable {
    static let maximumMessagesPerFolder = 1_000
    var pop3Host: String; var pop3Port: Int; var smtpHost: String; var smtpPort: Int
    var username: String; var password: String; var name: String; var email: String
    var inbox: [TopologyRuntimeEmailMessage]; var sent: [TopologyRuntimeEmailMessage]; var drafts: [TopologyRuntimeEmailMessage]
    var nextMessageID: UInt64

    init(pop3Host: String = "", pop3Port: Int = 110, smtpHost: String = "", smtpPort: Int = 25, username: String = "", password: String = "", name: String = "", email: String = "", inbox: [TopologyRuntimeEmailMessage] = [], sent: [TopologyRuntimeEmailMessage] = [], drafts: [TopologyRuntimeEmailMessage] = [], nextMessageID: UInt64 = 1) {
        self.pop3Host = pop3Host; self.pop3Port = pop3Port; self.smtpHost = smtpHost; self.smtpPort = smtpPort; self.username = username; self.password = password; self.name = name; self.email = email
        self.inbox = inbox; self.sent = sent; self.drafts = drafts; self.nextMessageID = nextMessageID
    }

    var address: TopologyRuntimeEmailAddress { .init(name: name, mailAddress: email) }
    func validate() throws {
        try Self.validateHost(pop3Host); try Self.validateHost(smtpHost); try Self.validatePort(pop3Port); try Self.validatePort(smtpPort)
        try TopologyRuntimeEmailServerAccount.validateUsername(username); try TopologyRuntimeEmailServerAccount.validatePassword(password); try address.validate()
        try validateJavaEmailAccountField(password, label: "client password")
        try validateJavaEmailAccountField(name, label: "client name")
        try validateFolderPersistence()
    }

    func validateForPersistence() throws {
        try Self.validatePort(pop3Port)
        try Self.validatePort(smtpPort)
        try validateFolderPersistence()
        let accountValues = [pop3Host, smtpHost, username, password, email]
        if accountValues.allSatisfy({ $0.isEmpty }) { return }
        try validate()
    }

    private func validateFolderPersistence() throws {
        guard inbox.count <= Self.maximumMessagesPerFolder, sent.count <= Self.maximumMessagesPerFolder, drafts.count <= Self.maximumMessagesPerFolder else { throw TopologyRuntimeEmailValidationError.mailboxQuotaExceeded }
        let all = inbox + sent + drafts; for message in all { try message.validate(requireRecipients: false) }
        let ids = all.map(\.id).filter { $0 != 0 }; guard Set(ids).count == ids.count, nextMessageID > (ids.max() ?? 0) else { throw TopologyRuntimeEmailValidationError.invalidMessageIDs }
    }
    static func validateHost(_ host: String) throws {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty, TopologyRuntimeDNSHostsFile.isValidIPv4Address(h) || TopologyRuntimeEmailAddress.isValidDomain(h.lowercased()) else { throw TopologyRuntimeEmailValidationError.invalidHost(host) }
    }
    static func validatePort(_ port: Int) throws { guard (1...65_535).contains(port) else { throw TopologyRuntimeEmailValidationError.invalidPort(port) } }
}

struct TopologyRuntimeEmailServerAccount: Codable, Equatable {
    static let maximumMailboxMessages = 1_000
    var username: String; var password: String; var name: String; var mailbox: [TopologyRuntimeEmailMessage]
    init(username: String, password: String, name: String = "", mailbox: [TopologyRuntimeEmailMessage] = []) { self.username = username; self.password = password; self.name = name; self.mailbox = mailbox }
    func emailAddress(domain: String) -> TopologyRuntimeEmailAddress { .init(name: name, mailAddress: "\(username)@\(domain)") }
    func validate(domain: String) throws {
        try Self.validateUsername(username); try Self.validatePassword(password); try emailAddress(domain: domain).validate()
        try validateJavaEmailAccountField(password, label: "server password")
        try validateJavaEmailAccountField(name, label: "server account name")
        let nameComponents = name.split(whereSeparator: { $0.isWhitespace })
        guard nameComponents.count >= 2 else {
            throw TopologyRuntimeEmailValidationError.javaStorageIncompatible("server account first and last name")
        }
        guard mailbox.count <= Self.maximumMailboxMessages else { throw TopologyRuntimeEmailValidationError.mailboxQuotaExceeded }
        let ids = mailbox.map(\.id); guard ids.allSatisfy({ $0 != 0 }), Set(ids).count == ids.count else { throw TopologyRuntimeEmailValidationError.invalidMessageIDs }
        for message in mailbox { try message.validate(requireRecipients: false) }
    }
    static func validateUsername(_ value: String) throws { guard !value.isEmpty, value.count <= 64, value.allSatisfy({ $0.isLetter || $0.isNumber || "._-".contains($0) }) else { throw TopologyRuntimeEmailValidationError.invalidAccount(value) } }
    static func validatePassword(_ value: String) throws { guard !value.isEmpty, value.count <= 256, !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw TopologyRuntimeEmailValidationError.invalidPassword } }
}

struct TopologyRuntimeEmailDeliveryReceipt: Codable, Equatable {
    let identity: String
    let contentSignature: String
}

struct TopologyRuntimeEmailServerConfiguration: Codable, Equatable {
    static let smtpPort = 25
    static let maximumDeliveryReceipts = 10_000
    var domain: String; var pop3Port: Int; var accounts: [TopologyRuntimeEmailServerAccount]; var nextMessageID: UInt64
    var deliveryReceipts: [TopologyRuntimeEmailDeliveryReceipt]?
    init(domain: String = "filius.de", pop3Port: Int = 110, accounts: [TopologyRuntimeEmailServerAccount] = [], nextMessageID: UInt64 = 1, deliveryReceipts: [TopologyRuntimeEmailDeliveryReceipt]? = nil) { self.domain = domain.lowercased(); self.pop3Port = pop3Port; self.accounts = accounts; self.nextMessageID = nextMessageID; self.deliveryReceipts = deliveryReceipts }
    func validate() throws {
        guard TopologyRuntimeEmailAddress.isValidDomain(domain), domain == domain.lowercased() else { throw TopologyRuntimeEmailValidationError.invalidDomain(domain) }
        try TopologyRuntimeEmailClientConfiguration.validatePort(pop3Port); guard accounts.count <= 100 else { throw TopologyRuntimeEmailValidationError.tooManyAccounts }
        var users = Set<String>(); var maximumID: UInt64 = 0
        for account in accounts {
            try account.validate(domain: domain); guard users.insert(account.username.lowercased()).inserted else { throw TopologyRuntimeEmailValidationError.duplicateAccount(account.username) }
            maximumID = max(maximumID, account.mailbox.map(\.id).max() ?? 0)
        }
        guard nextMessageID > maximumID else { throw TopologyRuntimeEmailValidationError.invalidMessageIDs }
        let receipts = deliveryReceipts ?? []
        guard receipts.count <= Self.maximumDeliveryReceipts,
              receipts.allSatisfy({
                  TopologyRuntimeEmailDeliveryIdentity.isValid($0.identity)
                      && TopologyRuntimeEmailDeliveryIdentity.isValid($0.contentSignature)
              }),
              Set(receipts.map(\.identity)).count == receipts.count
        else { throw TopologyRuntimeEmailValidationError.invalidDeliveryReceipts }
    }

    func deliveryReceipt(identity: String) -> TopologyRuntimeEmailDeliveryReceipt? {
        deliveryReceipts?.first { $0.identity == identity }
    }

    mutating func appendDeliveryReceipt(_ receipt: TopologyRuntimeEmailDeliveryReceipt) throws {
        if let existing = deliveryReceipt(identity: receipt.identity) {
            guard existing == receipt else { throw TopologyRuntimeEmailValidationError.deliveryIdentityConflict }
            return
        }
        // Persisted order is oldest-to-newest. Retain the most recent identities so a
        // lost final SMTP response can still be retried without duplicating delivery.
        var receipts = deliveryReceipts ?? []
        if receipts.count >= Self.maximumDeliveryReceipts {
            let evictionCount = receipts.count - Self.maximumDeliveryReceipts + 1
            receipts.removeFirst(evictionCount)
        }
        receipts.append(receipt)
        deliveryReceipts = receipts
    }
    func accountIndex(username: String) -> Int? { accounts.firstIndex { $0.username.caseInsensitiveCompare(username) == .orderedSame } }
    func accountIndex(email: String) -> Int? { accounts.firstIndex { $0.emailAddress(domain: domain).normalizedMailAddress == email.lowercased() } }
}

enum TopologyRuntimeEmailValidationError: Error, Equatable, LocalizedError {
    case invalidAddress(String), invalidHost(String), invalidPort(Int), invalidDomain(String), invalidAccount(String), invalidPassword
    case duplicateAccount(String), tooManyAccounts, missingRecipient, tooManyRecipients, invalidSubject, messageTooLarge, mailboxQuotaExceeded, invalidMessageIDs, malformedMessage
    case invalidDeliveryIdentity, invalidDeliveryReceipts, deliveryIdentityConflict
    case javaStorageIncompatible(String)
    var errorDescription: String? {
        switch self {
        case let .invalidAddress(v): return "Invalid email address: \(v)"; case let .invalidHost(v): return "Invalid email host: \(v)"; case let .invalidPort(v): return "Invalid email port: \(v)"
        case let .invalidDomain(v): return "Invalid email domain: \(v)"; case let .invalidAccount(v): return "Invalid email account: \(v)"; case .invalidPassword: return "Invalid email password."
        case let .duplicateAccount(v): return "Duplicate email account: \(v)"; case .tooManyAccounts: return "Too many email accounts."; case .missingRecipient: return "At least one recipient is required."
        case .tooManyRecipients: return "Too many email recipients."; case .invalidSubject: return "Invalid email subject."; case .messageTooLarge: return "Email message is too large."
        case .mailboxQuotaExceeded: return "Email mailbox quota exceeded."; case .invalidMessageIDs: return "Email message IDs are not deterministic."; case .malformedMessage: return "Malformed email message."
        case .invalidDeliveryIdentity: return "Invalid email delivery identity."
        case .invalidDeliveryReceipts: return "Invalid email delivery receipts."
        case .deliveryIdentityConflict: return "Email delivery identity conflicts with previously accepted content."
        case let .javaStorageIncompatible(field): return "Email field is not representable in Java storage: \(field)."
        }
    }
}

struct TopologyRuntimeEmailLogEntry: Codable, Equatable, Identifiable { let id: UInt64; let timestampMilliseconds: UInt64; let protocolName: String; let direction: String; let message: String }
fileprivate enum EmailSMTPPhase: Equatable { case connected, greeted, sender, recipients, data }
fileprivate struct EmailSMTPSession: Equatable { var phase: EmailSMTPPhase = .connected; var sender: TopologyRuntimeEmailAddress?; var recipients: [String] = []; var data = Data() }
fileprivate struct EmailPOP3Session: Equatable { var username: String?; var authenticated = false; var messageIDs: [UInt64] = []; var deleted = Set<UInt64>() }

struct TopologyRuntimeEmailServerProcessState: Equatable {
    var isRunning = false; var smtpListenerSocketID: UUID?; var pop3ListenerSocketID: UUID?
    fileprivate var smtpSessions: [UUID: EmailSMTPSession] = [:]; fileprivate var pop3Sessions: [UUID: EmailPOP3Session] = [:]
    var nextLogID: UInt64 = 1; var logs: [TopologyRuntimeEmailLogEntry] = []
#if targetEnvironment(simulator)
    var testingSMTPFinalDataResponsesToDrop = 0
#endif
    mutating func append(_ time: UInt64, _ proto: String, _ direction: String, _ message: String) { logs.append(.init(id: nextLogID, timestampMilliseconds: time, protocolName: proto, direction: direction, message: message)); nextLogID &+= 1; if logs.count > 100 { logs.removeFirst(logs.count - 100) } }
}

struct TopologyRuntimeEmailClientState: Equatable {
    var isBusy = false; var activeOperation: String?; var lastError: String?; var nextLogID: UInt64 = 1; var logs: [TopologyRuntimeEmailLogEntry] = []
    mutating func append(_ time: UInt64, _ proto: String, _ direction: String, _ message: String) { logs.append(.init(id: nextLogID, timestampMilliseconds: time, protocolName: proto, direction: direction, message: message)); nextLogID &+= 1; if logs.count > 100 { logs.removeFirst(logs.count - 100) } }
}

enum TopologyRuntimeEmailOperationError: Error, Equatable, LocalizedError {
    case validation(String), simulationStopped, dnsFailure(String), unreachable(String), timeout(String), protocolError(String), malformedResponse, quotaExceeded
    var errorDescription: String? { switch self { case let .validation(v): return v; case .simulationStopped: return "Simulation is stopped."; case let .dnsFailure(v): return "DNS failed: \(v)"; case let .unreachable(v): return "Email server unreachable: \(v)"; case let .timeout(v): return "Email timeout: \(v)"; case let .protocolError(v): return "Email protocol error: \(v)"; case .malformedResponse: return "Malformed email response."; case .quotaExceeded: return "Email quota exceeded." } }
}
private struct EmailRelayRequest {
    let message: TopologyRuntimeEmailMessage
    let recipients: [TopologyRuntimeEmailAddress]
}

private struct EmailMXEndpoint: Equatable {
    let preferenceOrder: Int
    let exchangerHostname: String
    let address: String
}

private struct EmailMXResolution {
    let endpoints: [EmailMXEndpoint]
    let diagnostics: [String]
}

private struct EmailOutcome {
    var response: String?
    var close = false
    var log: String
    var relays: [EmailRelayRequest] = []
}

enum TopologyRuntimeEmailStorage {
    static let clientNativePath = "/mail/.filiuspad-email-client.json"
    static let clientJavaPath = "/konten.txt"
    static let serverNativePath = "/mailserver/.filiuspad-email-server.json"
    static let serverJavaPath = "/mailserver/konten.txt"

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func nativeClientText(_ configuration: TopologyRuntimeEmailClientConfiguration) throws -> String {
        String(decoding: try encoder().encode(configuration), as: UTF8.self)
    }

    static func nativeServerText(_ configuration: TopologyRuntimeEmailServerConfiguration) throws -> String {
        String(decoding: try encoder().encode(configuration), as: UTF8.self)
    }

    static func decodeNativeClient(_ text: String) throws -> TopologyRuntimeEmailClientConfiguration {
        let configuration = try JSONDecoder().decode(TopologyRuntimeEmailClientConfiguration.self, from: Data(text.utf8))
        try configuration.validateForPersistence()
        return configuration
    }

    static func decodeNativeServer(_ text: String) throws -> TopologyRuntimeEmailServerConfiguration {
        let configuration = try JSONDecoder().decode(TopologyRuntimeEmailServerConfiguration.self, from: Data(text.utf8))
        try configuration.validate()
        return configuration
    }

    static func javaClientText(_ configuration: TopologyRuntimeEmailClientConfiguration) -> String {
        let names = splitName(configuration.name)
        return [
            configuration.pop3Host,
            configuration.smtpHost,
            String(configuration.pop3Port),
            String(configuration.smtpPort),
            configuration.username,
            configuration.password,
            names.last,
            names.first,
            configuration.email,
        ].map(javaAccountColumn).joined(separator: ";") + "\n"
    }

    static func decodeJavaClient(_ text: String) throws -> TopologyRuntimeEmailClientConfiguration {
        guard let line = text.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            throw TopologyRuntimeEmailValidationError.invalidAccount("missing client account")
        }
        let columns = line.split(separator: ";", omittingEmptySubsequences: false).map { decodeJavaAccountColumn(String($0)) }
        guard columns.count == 9,
              let pop3Port = Int(columns[2]),
              let smtpPort = Int(columns[3])
        else { throw TopologyRuntimeEmailValidationError.invalidAccount("malformed client account") }
        let configuration = TopologyRuntimeEmailClientConfiguration(
            pop3Host: columns[0],
            pop3Port: pop3Port,
            smtpHost: columns[1],
            smtpPort: smtpPort,
            username: columns[4],
            password: columns[5],
            name: [columns[7], columns[6]].filter { !$0.isEmpty }.joined(separator: " "),
            email: columns[8]
        )
        try configuration.validate()
        return configuration
    }

    static func javaServerText(_ configuration: TopologyRuntimeEmailServerConfiguration) -> String {
        configuration.accounts.map { account in
            let names = splitName(account.name)
            let messages = account.mailbox.map(javaMessageText).joined()
            return [account.username, configuration.domain, account.password, names.last, names.first]
                .map(javaAccountColumn).joined(separator: ";") + ";" + messages
        }.joined(separator: "\n") + (configuration.accounts.isEmpty ? "" : "\n")
    }

    static func decodeJavaServer(_ text: String, fallbackDomain: String = "filius.de") throws -> TopologyRuntimeEmailServerConfiguration {
        var domain = fallbackDomain.lowercased()
        var nextMessageID: UInt64 = 1
        var accounts: [TopologyRuntimeEmailServerAccount] = []
        for line in text.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let columns = line.split(separator: ";", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
            guard columns.count == 6 else { throw TopologyRuntimeEmailValidationError.invalidAccount("malformed server account") }
            let decoded = columns.prefix(5).map(decodeJavaAccountColumn)
            domain = decoded[1].lowercased()
            var mailbox: [TopologyRuntimeEmailMessage] = []
            for record in columns[5].split(separator: "#", omittingEmptySubsequences: true) {
                var message = try decodeJavaMessage(String(record), id: nextMessageID)
                message.receivedAtMilliseconds = message.receivedAtMilliseconds ?? nextMessageID
                mailbox.append(message)
                nextMessageID += 1
            }
            accounts.append(
                TopologyRuntimeEmailServerAccount(
                    username: decoded[0],
                    password: decoded[2],
                    name: [decoded[4], decoded[3]].filter { !$0.isEmpty }.joined(separator: " "),
                    mailbox: mailbox
                )
            )
        }
        let configuration = TopologyRuntimeEmailServerConfiguration(
            domain: domain,
            accounts: accounts,
            nextMessageID: nextMessageID
        )
        try configuration.validate()
        return configuration
    }

    static func validatePersistedSize(client configuration: TopologyRuntimeEmailClientConfiguration) throws {
        let nativeBytes = try nativeClientText(configuration).lengthOfBytes(using: .utf8)
        let javaBytes = javaClientText(configuration).lengthOfBytes(using: .utf8)
        guard nativeBytes <= TopologyVirtualFileSystem.maximumFileBytes,
              javaBytes <= TopologyVirtualFileSystem.maximumFileBytes
        else { throw TopologyRuntimeEmailOperationError.quotaExceeded }
    }

    static func validatePersistedSize(server configuration: TopologyRuntimeEmailServerConfiguration) throws {
        let nativeBytes = try nativeServerText(configuration).lengthOfBytes(using: .utf8)
        let javaBytes = javaServerText(configuration).lengthOfBytes(using: .utf8)
        guard nativeBytes <= TopologyVirtualFileSystem.maximumFileBytes,
              javaBytes <= TopologyVirtualFileSystem.maximumFileBytes
        else { throw TopologyRuntimeEmailOperationError.quotaExceeded }
    }

    private static func splitName(_ name: String) -> (first: String, last: String) {
        let components = name.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let first = components.first else { return ("", "") }
        return (first, components.dropFirst().joined(separator: " "))
    }

    private static func javaAccountColumn(_ value: String) -> String { value }

    private static func decodeJavaAccountColumn(_ value: String) -> String { value }

    private static func javaMessageText(_ message: TopologyRuntimeEmailMessage) -> String {
        let fields = [
            message.from.javaString,
            message.to.map(\.javaString).joined(separator: ", "),
            message.cc.map(\.javaString).joined(separator: ", "),
            message.bcc.map(\.javaString).joined(separator: ", "),
            message.receivedAtMilliseconds.map(String.init) ?? "",
            message.subject,
            encodeJavaMessageBody(message.body),
        ]
        return "#" + fields.joined(separator: "$")
    }

    private static func decodeJavaMessage(_ value: String, id: UInt64) throws -> TopologyRuntimeEmailMessage {
        let fields = value.split(separator: "$", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 7,
              let sender = TopologyRuntimeEmailAddress(javaString: fields[0])
        else { throw TopologyRuntimeEmailValidationError.malformedMessage }
        func addresses(_ raw: String) throws -> [TopologyRuntimeEmailAddress] {
            if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
            let values = raw.split(separator: ",", omittingEmptySubsequences: true)
            let decoded = values.compactMap { TopologyRuntimeEmailAddress(javaString: String($0)) }
            guard decoded.count == values.count else { throw TopologyRuntimeEmailValidationError.malformedMessage }
            return decoded
        }
        return TopologyRuntimeEmailMessage(
            id: id,
            from: sender,
            to: try addresses(fields[1]),
            cc: try addresses(fields[2]),
            bcc: try addresses(fields[3]),
            subject: fields[5],
            body: decodeJavaMessageBody(fields[6]),
            receivedAtMilliseconds: UInt64(fields[4]),
            isNew: true
        )
    }

    private static func encodeJavaMessageBody(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "&&00124&&")
            .replacingOccurrences(of: "$", with: "&&00036&&")
            .replacingOccurrences(of: ";", with: "&&00059&&")
            .replacingOccurrences(of: "#", with: "&&00035&&")
            .replacingOccurrences(of: "\r\n", with: "|")
            .replacingOccurrences(of: "\n", with: "|")
            .replacingOccurrences(of: "\r", with: "|")
    }

    private static func decodeJavaMessageBody(_ value: String) -> String {
        let pipeSentinel = "\u{001f}filius-pipe\u{001f}"
        return value.replacingOccurrences(of: "&&00124&&", with: pipeSentinel)
            .replacingOccurrences(of: "&&00036&&", with: "$")
            .replacingOccurrences(of: "&&00059&&", with: ";")
            .replacingOccurrences(of: "&&00035&&", with: "#")
            .replacingOccurrences(of: "|", with: "\n")
            .replacingOccurrences(of: pipeSentinel, with: "|")
    }
}

extension TopologyEditorState {
    mutating func synchronizeRuntimeEmailConfigurationFromFileSystem(nodeID: UUID) throws {
        guard let fileSystem = virtualFileSystemsByNodeID[nodeID] else { return }
        if runtimeInstalledProgramsByNodeID[nodeID]?.contains(.emailClient) == true {
            if fileSystem.contains(TopologyRuntimeEmailStorage.clientNativePath) {
                let text = try fileSystem.textFile(at: TopologyRuntimeEmailStorage.clientNativePath)
                runtimeEmailClientConfigurationsByNodeID[nodeID] = try TopologyRuntimeEmailStorage.decodeNativeClient(text)
            } else if fileSystem.contains(TopologyRuntimeEmailStorage.clientJavaPath) {
                let text = try fileSystem.textFile(at: TopologyRuntimeEmailStorage.clientJavaPath)
                runtimeEmailClientConfigurationsByNodeID[nodeID] = try TopologyRuntimeEmailStorage.decodeJavaClient(text)
            }
        }
        if runtimeInstalledProgramsByNodeID[nodeID]?.contains(.emailServer) == true {
            if fileSystem.contains(TopologyRuntimeEmailStorage.serverNativePath) {
                let text = try fileSystem.textFile(at: TopologyRuntimeEmailStorage.serverNativePath)
                runtimeEmailServerConfigurationsByNodeID[nodeID] = try TopologyRuntimeEmailStorage.decodeNativeServer(text)
            } else if fileSystem.contains(TopologyRuntimeEmailStorage.serverJavaPath) {
                let text = try fileSystem.textFile(at: TopologyRuntimeEmailStorage.serverJavaPath)
                runtimeEmailServerConfigurationsByNodeID[nodeID] = try TopologyRuntimeEmailStorage.decodeJavaServer(text)
            }
        }
    }

    private func preparedRuntimeEmailClientFileSystem(
        nodeID: UUID,
        configuration: TopologyRuntimeEmailClientConfiguration
    ) throws -> TopologyVirtualFileSystem {
        try TopologyRuntimeEmailStorage.validatePersistedSize(client: configuration)
        var fileSystem = virtualFileSystemsByNodeID[nodeID] ?? .defaultForDevice()
        if !fileSystem.contains("/mail") { try fileSystem.createDirectory(at: "/mail", recursive: true) }
        try fileSystem.writeTextFile(
            at: TopologyRuntimeEmailStorage.clientNativePath,
            text: TopologyRuntimeEmailStorage.nativeClientText(configuration)
        )
        try fileSystem.writeTextFile(
            at: TopologyRuntimeEmailStorage.clientJavaPath,
            text: TopologyRuntimeEmailStorage.javaClientText(configuration)
        )
        var candidates = virtualFileSystemsByNodeID
        candidates[nodeID] = fileSystem
        try TopologyVirtualFileSystem.validateProjectQuotas(candidates)
        return fileSystem
    }

    private func preparedRuntimeEmailServerFileSystem(
        nodeID: UUID,
        configuration: TopologyRuntimeEmailServerConfiguration
    ) throws -> TopologyVirtualFileSystem {
        try TopologyRuntimeEmailStorage.validatePersistedSize(server: configuration)
        var fileSystem = virtualFileSystemsByNodeID[nodeID] ?? .defaultForDevice()
        if !fileSystem.contains("/mailserver") { try fileSystem.createDirectory(at: "/mailserver", recursive: true) }
        try fileSystem.writeTextFile(
            at: TopologyRuntimeEmailStorage.serverNativePath,
            text: TopologyRuntimeEmailStorage.nativeServerText(configuration)
        )
        try fileSystem.writeTextFile(
            at: TopologyRuntimeEmailStorage.serverJavaPath,
            text: TopologyRuntimeEmailStorage.javaServerText(configuration)
        )
        var candidates = virtualFileSystemsByNodeID
        candidates[nodeID] = fileSystem
        try TopologyVirtualFileSystem.validateProjectQuotas(candidates)
        return fileSystem
    }

    mutating func persistRuntimeEmailClientConfiguration(nodeID: UUID) throws {
        guard let configuration = runtimeEmailClientConfigurationsByNodeID[nodeID] else { return }
        virtualFileSystemsByNodeID[nodeID] = try preparedRuntimeEmailClientFileSystem(
            nodeID: nodeID,
            configuration: configuration
        )
    }

    mutating func persistRuntimeEmailServerConfiguration(nodeID: UUID) throws {
        guard let configuration = runtimeEmailServerConfigurationsByNodeID[nodeID] else { return }
        virtualFileSystemsByNodeID[nodeID] = try preparedRuntimeEmailServerFileSystem(
            nodeID: nodeID,
            configuration: configuration
        )
    }


    mutating func saveRuntimeEmailServerConfiguration(nodeID: UUID, configuration: TopologyRuntimeEmailServerConfiguration) -> Result<Void, TopologyRuntimeEmailOperationError> {
        do {
            try configuration.validate()
            try TopologyRuntimeEmailStorage.validatePersistedSize(server: configuration)
        } catch let error as TopologyRuntimeEmailOperationError {
            return .failure(error)
        } catch {
            return .failure(.validation(error.localizedDescription))
        }
        guard runtimeEmailServerProcessesByNodeID[nodeID]?.isRunning != true else {
            return .failure(.validation("Stop the email server before changing configuration."))
        }
        let previousConfiguration = runtimeEmailServerConfigurationsByNodeID[nodeID]
        let previousFileSystem = virtualFileSystemsByNodeID[nodeID]
        runtimeEmailServerConfigurationsByNodeID[nodeID] = configuration
        do {
            try persistRuntimeEmailServerConfiguration(nodeID: nodeID)
            return .success(())
        } catch {
            runtimeEmailServerConfigurationsByNodeID[nodeID] = previousConfiguration
            virtualFileSystemsByNodeID[nodeID] = previousFileSystem
            return .failure(.quotaExceeded)
        }
    }

    mutating func saveRuntimeEmailClientConfiguration(nodeID: UUID, configuration: TopologyRuntimeEmailClientConfiguration) -> Result<Void, TopologyRuntimeEmailOperationError> {
        do {
            try configuration.validate()
            try TopologyRuntimeEmailStorage.validatePersistedSize(client: configuration)
        } catch let error as TopologyRuntimeEmailOperationError {
            return .failure(error)
        } catch {
            return .failure(.validation(error.localizedDescription))
        }
        let previousConfiguration = runtimeEmailClientConfigurationsByNodeID[nodeID]
        let previousFileSystem = virtualFileSystemsByNodeID[nodeID]
        runtimeEmailClientConfigurationsByNodeID[nodeID] = configuration
        do {
            try persistRuntimeEmailClientConfiguration(nodeID: nodeID)
            return .success(())
        } catch {
            runtimeEmailClientConfigurationsByNodeID[nodeID] = previousConfiguration
            virtualFileSystemsByNodeID[nodeID] = previousFileSystem
            return .failure(.quotaExceeded)
        }
    }
    mutating func startRuntimeEmailServer(nodeID: UUID) -> Result<Void, TopologyRuntimeEmailOperationError> {
        guard simulationPhase == .running else { return .failure(.simulationStopped) }
        guard let config = runtimeEmailServerConfigurationsByNodeID[nodeID] else { return .failure(.validation("Missing email server configuration.")) }
        do { try config.validate() } catch { return .failure(.validation(error.localizedDescription)) }
        if runtimeEmailServerProcessesByNodeID[nodeID]?.isRunning == true { return .success(()) }
        guard let smtp = networkRuntime.openTCPServerSocket(nodeID: nodeID, localPort: 25) else { return .failure(.unreachable("TCP/25")) }
        guard let pop3 = networkRuntime.openTCPServerSocket(nodeID: nodeID, localPort: UInt16(config.pop3Port)) else { _ = networkRuntime.closeTCPConnectionAndClean(socketID: smtp); return .failure(.unreachable("TCP/\(config.pop3Port)")) }
        var process = runtimeEmailServerProcessesByNodeID[nodeID] ?? .init(); process.isRunning = true; process.smtpListenerSocketID = smtp; process.pop3ListenerSocketID = pop3; process.smtpSessions.removeAll(); process.pop3Sessions.removeAll(); process.append(networkRuntime.state.currentTimeMilliseconds, "EMAIL", "local", "Email server started"); runtimeEmailServerProcessesByNodeID[nodeID] = process; return .success(())
    }
    @discardableResult mutating func stopRuntimeEmailServer(nodeID: UUID) -> Bool {
        guard var process = runtimeEmailServerProcessesByNodeID[nodeID] else { return false }
        let ids = Array(process.smtpSessions.keys) + Array(process.pop3Sessions.keys) + [process.smtpListenerSocketID, process.pop3ListenerSocketID].compactMap { $0 }
        for id in Set(ids).sorted(by: { $0.uuidString < $1.uuidString }) { _ = networkRuntime.closeTCPConnectionAndClean(socketID: id) }
        process.isRunning = false; process.smtpListenerSocketID = nil; process.pop3ListenerSocketID = nil; process.smtpSessions.removeAll(); process.pop3Sessions.removeAll(); process.append(networkRuntime.state.currentTimeMilliseconds, "EMAIL", "local", "Email server stopped"); runtimeEmailServerProcessesByNodeID[nodeID] = process; return true
    }
    @discardableResult mutating func processRuntimeEmailServers() -> Int {
        var count = 0; for id in runtimeEmailServerProcessesByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString }) { count += processRuntimeEmailServer(nodeID: id) }; return count
    }
    @discardableResult mutating func processRuntimeEmailServer(nodeID: UUID) -> Int {
        guard var process = runtimeEmailServerProcessesByNodeID[nodeID], process.isRunning, var config = runtimeEmailServerConfigurationsByNodeID[nodeID] else { return 0 }
        var count = 0
        if let listener = process.smtpListenerSocketID {
            for socket in networkRuntime.acceptedTCPSocketIDs(listenerSocketID: listener) {
                if process.smtpSessions[socket] == nil { process.smtpSessions[socket] = .init(); sendEmailResponse(nodeID, socket, "SMTP", "220 \(config.domain) Filius SMTP ready\r\n", &process); count += 1 }
                while let data = networkRuntime.receiveTCP(socketID: socket) {
                    var session = process.smtpSessions[socket] ?? .init()
                    let configurationBeforeCommand = config
                    var outcome = handleSMTP(data, &session, &config)
                    process.smtpSessions[socket] = session
                    process.append(networkRuntime.state.currentTimeMilliseconds, "SMTP", "local", outcome.log)

                    if !outcome.relays.isEmpty {
                        runtimeEmailServerConfigurationsByNodeID[nodeID] = config
                        runtimeEmailServerProcessesByNodeID[nodeID] = process
                        var relayFailed = false
                        for relay in outcome.relays {
                            switch relayRuntimeEmail(fromNodeID: nodeID, request: relay) {
                            case let .success(detail):
                                process.append(
                                    networkRuntime.state.currentTimeMilliseconds,
                                    "SMTP",
                                    "outbound",
                                    "Remote delivery succeeded: \(detail)"
                                )
                            case let .failure(error):
                                relayFailed = true
                                process.append(networkRuntime.state.currentTimeMilliseconds, "SMTP", "outbound", "Remote delivery failed: \(error.localizedDescription)")
                            }
                        }
                        if relayFailed {
                            config = configurationBeforeCommand
                            outcome.response = "451 Requested action aborted: relay unavailable\r\n"
                        }
                    }

                    if config != configurationBeforeCommand {
                        runtimeEmailServerConfigurationsByNodeID[nodeID] = config
                        do {
                            try persistRuntimeEmailServerConfiguration(nodeID: nodeID)
                        } catch {
                            config = configurationBeforeCommand
                            runtimeEmailServerConfigurationsByNodeID[nodeID] = configurationBeforeCommand
                            outcome.response = "452 Insufficient storage\r\n"
                            process.append(networkRuntime.state.currentTimeMilliseconds, "SMTP", "local", "Mailbox persistence rejected by quota")
                        }
                    }

                    if let response = outcome.response {
                        var dropAcceptedDataResponse = false
                        let isAcceptedDataResponse = response.hasPrefix("250")
                            && outcome.log.hasPrefix("SMTP ")
                            && outcome.log.contains("delivery")
#if targetEnvironment(simulator)
                        if isAcceptedDataResponse && process.testingSMTPFinalDataResponsesToDrop > 0 {
                            process.testingSMTPFinalDataResponsesToDrop -= 1
                            dropAcceptedDataResponse = true
                            process.append(networkRuntime.state.currentTimeMilliseconds, "SMTP", "outbound", "Response 250 intentionally dropped after durable acceptance")
                        }
#endif
                        if !dropAcceptedDataResponse {
                            sendEmailResponse(nodeID, socket, "SMTP", response, &process)
                            count += 1
                        }
                    }
                    if outcome.close { networkRuntime.closeTCPSocket(socketID: socket); process.smtpSessions.removeValue(forKey: socket); break }
                }
            }
        }
        if let listener = process.pop3ListenerSocketID {
            for socket in networkRuntime.acceptedTCPSocketIDs(listenerSocketID: listener) {
                if process.pop3Sessions[socket] == nil { process.pop3Sessions[socket] = .init(); sendEmailResponse(nodeID, socket, "POP3", "+OK POP3 server ready\r\n", &process); count += 1 }
                while let data = networkRuntime.receiveTCP(socketID: socket) {
                    var session = process.pop3Sessions[socket] ?? .init()
                    let configurationBeforeCommand = config
                    var outcome = handlePOP3(data, &session, &config)
                    process.pop3Sessions[socket] = session
                    process.append(networkRuntime.state.currentTimeMilliseconds, "POP3", "local", outcome.log)
                    if config != configurationBeforeCommand {
                        runtimeEmailServerConfigurationsByNodeID[nodeID] = config
                        do {
                            try persistRuntimeEmailServerConfiguration(nodeID: nodeID)
                        } catch {
                            config = configurationBeforeCommand
                            runtimeEmailServerConfigurationsByNodeID[nodeID] = configurationBeforeCommand
                            outcome.response = "-ERR mailbox persistence failed\r\n"
                            outcome.close = false
                            process.append(networkRuntime.state.currentTimeMilliseconds, "POP3", "local", "Mailbox persistence rejected by quota")
                        }
                    }
                    if let response = outcome.response { sendEmailResponse(nodeID, socket, "POP3", response, &process); count += 1 }
                    if outcome.close { networkRuntime.closeTCPSocket(socketID: socket); process.pop3Sessions.removeValue(forKey: socket); break }
                }
            }
        }
        runtimeEmailServerConfigurationsByNodeID[nodeID] = config
        runtimeEmailServerProcessesByNodeID[nodeID] = process
        return count
    }
    mutating func resetRuntimeEmailTransientState() {
        for id in runtimeEmailServerProcessesByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString }) { _ = stopRuntimeEmailServer(nodeID: id) }
        runtimeEmailServerProcessesByNodeID.removeAll(); runtimeEmailClientStateByNodeID.removeAll()
    }
    private mutating func sendEmailResponse(_ nodeID: UUID, _ socket: UUID, _ proto: String, _ response: String, _ process: inout TopologyRuntimeEmailServerProcessState) {
        let delivered = networkRuntime.sendTCP(socketID: socket, payload: Data(response.utf8))
        let code = response.split(separator: " ").first.map(String.init) ?? ""
        networkRuntime.recordTrace(nodeID: nodeID, interfaceID: networkRuntime.networkInterfaces(nodeID: nodeID).first?.portID, direction: .outbound, layer: .application, operation: delivered ? .sent : .dropped, afterHeaders: [.init(name: "kind", value: proto), .init(name: "response", value: code)], detail: delivered ? "\(proto) response sent" : "\(proto) response delivery failed")
        process.append(networkRuntime.state.currentTimeMilliseconds, proto, "outbound", delivered ? "Response \(code)" : "Response \(code) delivery failed")
    }

    mutating func sendRuntimeEmail(nodeID: UUID, message: TopologyRuntimeEmailMessage) -> Result<TopologyRuntimeEmailMessage, TopologyRuntimeEmailOperationError> {
        guard simulationPhase == .running else { return .failure(.simulationStopped) }
        guard let config = runtimeEmailClientConfigurationsByNodeID[nodeID] else { return .failure(.validation("Missing email client configuration.")) }
        let prepared: (
            message: TopologyRuntimeEmailMessage,
            configuration: TopologyRuntimeEmailClientConfiguration,
            fileSystem: TopologyVirtualFileSystem
        )
        do {
            try config.validate()
            try message.validate()
            var candidate = config
            var persistedMessage = message
            if persistedMessage.id == 0 {
                persistedMessage.id = candidate.nextMessageID
                candidate.nextMessageID += 1
            }
            if persistedMessage.deliveryIdentity == nil {
                persistedMessage.deliveryIdentity = TopologyRuntimeEmailDeliveryIdentity.make(
                    originNodeID: nodeID,
                    messageID: persistedMessage.id,
                    message: persistedMessage
                )
            }
            persistedMessage.isNew = false
            persistedMessage.isSent = true
            persistedMessage.isMarkedForDeletion = false
            candidate.drafts.removeAll { $0.id == persistedMessage.id }
            guard candidate.sent.count < TopologyRuntimeEmailClientConfiguration.maximumMessagesPerFolder else {
                throw TopologyRuntimeEmailOperationError.quotaExceeded
            }
            candidate.sent.append(persistedMessage)
            try candidate.validate()
            prepared = (
                persistedMessage,
                candidate,
                try preparedRuntimeEmailClientFileSystem(nodeID: nodeID, configuration: candidate)
            )
        } catch let error as TopologyRuntimeEmailOperationError {
            return .failure(error)
        } catch {
            return .failure(.validation(error.localizedDescription))
        }
        setEmailClientBusy(nodeID, true, operation: "sending", error: nil)
        let result: Result<TopologyRuntimeEmailMessage, TopologyRuntimeEmailOperationError>
        do {
            let address = try resolveEmailHost(nodeID, config.smtpHost), socket = try openEmailSocket(nodeID, address, config.smtpPort)
            defer { _ = networkRuntime.closeTCPConnectionAndClean(socketID: socket) }
            guard try emailResponse(socket, pump: true).hasPrefix("220") else { throw TopologyRuntimeEmailOperationError.malformedResponse }
            try smtp("HELO filius", "250", socket); try smtp("MAIL FROM:<\(prepared.message.from.mailAddress)>", "250", socket)
            for recipient in prepared.message.envelopeRecipients { try smtp("RCPT TO:<\(recipient.mailAddress)>", "250", socket) }
            try smtp("DATA", "354", socket); try sendEmailPayload(stuffDots(prepared.message.javaWireString) + "\r\n.\r\n", socket, "SMTP", "message")
            let queued = try emailResponse(socket, pump: true); guard queued.hasPrefix("250") else { throw TopologyRuntimeEmailOperationError.protocolError(queued.trimmingCharacters(in: .whitespacesAndNewlines)) }
            try? smtp("QUIT", "221", socket)
            runtimeEmailClientConfigurationsByNodeID[nodeID] = prepared.configuration
            virtualFileSystemsByNodeID[nodeID] = prepared.fileSystem
            result = .success(prepared.message)
        } catch let error as TopologyRuntimeEmailOperationError { result = .failure(error) }
          catch { result = .failure(.protocolError(error.localizedDescription)) }
        finishEmailClient(nodeID, "SMTP", result.map { _ in "Message sent" }.failureMessage("Send failed")); return result
    }

    mutating func retrieveRuntimeEmail(nodeID: UUID, deleteFromServer: Bool = true) -> Result<[TopologyRuntimeEmailMessage], TopologyRuntimeEmailOperationError> {
        guard simulationPhase == .running else { return .failure(.simulationStopped) }
        guard var config = runtimeEmailClientConfigurationsByNodeID[nodeID] else { return .failure(.validation("Missing email client configuration.")) }
        do { try config.validate() } catch { return .failure(.validation(error.localizedDescription)) }
        setEmailClientBusy(nodeID, true, operation: "retrieving", error: nil)
        let result: Result<[TopologyRuntimeEmailMessage], TopologyRuntimeEmailOperationError>
        do {
            let address = try resolveEmailHost(nodeID, config.pop3Host), socket = try openEmailSocket(nodeID, address, config.pop3Port)
            defer { _ = networkRuntime.closeTCPConnectionAndClean(socketID: socket) }
            guard try emailResponse(socket, pump: true).hasPrefix("+OK") else { throw TopologyRuntimeEmailOperationError.malformedResponse }
            _ = try pop3("USER \(config.username)", socket); _ = try pop3("PASS \(config.password)", socket, safeName: "PASS")
            let stat = try pop3("STAT", socket), fields = stat.split(separator: " "); let count = fields.count > 1 ? (Int(fields[1]) ?? 0) : 0
            var messages: [TopologyRuntimeEmailMessage] = []
            for number in 0..<count {
                let response = try pop3("RETR \(number)", socket)
                let bodyStart: String.Index
                if let separator = response.range(of: "\r\n") {
                    bodyStart = separator.upperBound
                } else if let separator = response.range(of: "\n") {
                    bodyStart = separator.upperBound
                } else {
                    throw TopologyRuntimeEmailOperationError.malformedResponse
                }
                var wire = String(response[bodyStart...])
                if let end = wire.range(of: "\r\n.\r\n", options: .backwards) {
                    wire = String(wire[..<end.lowerBound])
                } else if let end = wire.range(of: "\n.\n", options: .backwards) {
                    wire = String(wire[..<end.lowerBound])
                }
                var message = try TopologyRuntimeEmailMessage.parseJavaWireString(unstuffDots(wire), id: config.nextMessageID)
                config.nextMessageID += 1
                message.isNew = true
                messages.append(message)
            }
            guard config.inbox.count + messages.count <= TopologyRuntimeEmailClientConfiguration.maximumMessagesPerFolder else {
                _ = try? pop3("QUIT", socket)
                throw TopologyRuntimeEmailOperationError.quotaExceeded
            }
            var persistedCandidate = config
            persistedCandidate.inbox.append(contentsOf: messages)
            try persistedCandidate.validate()
            let preparedFileSystem = try preparedRuntimeEmailClientFileSystem(
                nodeID: nodeID,
                configuration: persistedCandidate
            )
            if deleteFromServer {
                for number in 0..<count { _ = try pop3("DELE \(number)", socket) }
            }
            _ = try pop3("QUIT", socket)
            runtimeEmailClientConfigurationsByNodeID[nodeID] = persistedCandidate
            virtualFileSystemsByNodeID[nodeID] = preparedFileSystem
            result = .success(messages)
        } catch let error as TopologyRuntimeEmailOperationError { result = .failure(error) }
          catch { result = .failure(.protocolError(error.localizedDescription)) }
        finishEmailClient(nodeID, "POP3", result.map { "Retrieved \($0.count) message(s)" }.failureMessage("Retrieve failed"))
        return result
    }

    private mutating func setEmailClientBusy(_ nodeID: UUID, _ busy: Bool, operation: String?, error: String?) {
        var state = runtimeEmailClientStateByNodeID[nodeID] ?? .init()
        state.isBusy = busy
        state.activeOperation = busy ? operation : nil
        state.lastError = error
        runtimeEmailClientStateByNodeID[nodeID] = state
    }

    private mutating func finishEmailClient<T>(_ nodeID: UUID, _ proto: String, _ outcome: (Result<T, TopologyRuntimeEmailOperationError>, String)) {
        var state = runtimeEmailClientStateByNodeID[nodeID] ?? .init()
        state.isBusy = false
        state.activeOperation = nil
        state.lastError = nil
        if case let .failure(error) = outcome.0 { state.lastError = error.localizedDescription }
        state.append(networkRuntime.state.currentTimeMilliseconds, proto, "local", outcome.1)
        runtimeEmailClientStateByNodeID[nodeID] = state
    }
    private mutating func resolveEmailHost(_ nodeID: UUID, _ host: String) throws -> String {
        if TopologyRuntimeDNSHostsFile.isValidIPv4Address(host) { return host }
        switch resolveRuntimeHostname(nodeID: nodeID, hostname: host) { case let .success(record, _, _): return record.targetIPAddress; case let .nxdomain(_, server, _): throw TopologyRuntimeEmailOperationError.dnsFailure("NXDOMAIN from \(server)"); case let .unreachable(server): throw TopologyRuntimeEmailOperationError.dnsFailure(server); case let .timeout(server): throw TopologyRuntimeEmailOperationError.timeout(server); case .missingServerConfiguration: throw TopologyRuntimeEmailOperationError.dnsFailure("missing server"); case .simulationStopped: throw TopologyRuntimeEmailOperationError.simulationStopped }
    }
    private mutating func openEmailSocket(_ nodeID: UUID, _ address: String, _ port: Int) throws -> UUID {
        guard let socket = networkRuntime.openTCPClientSocket(nodeID: nodeID, remoteIPAddress: address, remotePort: UInt16(port)) else { throw TopologyRuntimeEmailOperationError.unreachable(address) }
        switch networkRuntime.connectTCPWithResult(socketID: socket) { case .connected: return socket; case .timedOut: _ = networkRuntime.closeTCPConnectionAndClean(socketID: socket); throw TopologyRuntimeEmailOperationError.timeout(address); case .unreachable, .invalidSocket: _ = networkRuntime.closeTCPConnectionAndClean(socketID: socket); throw TopologyRuntimeEmailOperationError.unreachable(address) }
    }
    private mutating func smtp(_ command: String, _ expected: String, _ socket: UUID) throws { try sendEmailPayload(command + "\r\n", socket, "SMTP", command.split(separator: " ").first.map(String.init) ?? ""); let response = try emailResponse(socket, pump: true); guard response.hasPrefix(expected) else { throw TopologyRuntimeEmailOperationError.protocolError(response.trimmingCharacters(in: .whitespacesAndNewlines)) } }
    private mutating func pop3(_ command: String, _ socket: UUID, safeName: String? = nil) throws -> String { try sendEmailPayload(command + "\r\n", socket, "POP3", safeName ?? command.split(separator: " ").first.map(String.init) ?? ""); let response = try emailResponse(socket, pump: true); guard response.hasPrefix("+OK") else { throw TopologyRuntimeEmailOperationError.protocolError(response.trimmingCharacters(in: .whitespacesAndNewlines)) }; return response }
    private mutating func sendEmailPayload(_ payload: String, _ socket: UUID, _ proto: String, _ command: String) throws {
        guard networkRuntime.sendTCP(socketID: socket, payload: Data(payload.utf8)) else { throw TopologyRuntimeEmailOperationError.timeout(proto) }
        if let node = networkRuntime.tcpSocketRecord(socketID: socket)?.nodeID { networkRuntime.recordTrace(nodeID: node, interfaceID: networkRuntime.networkInterfaces(nodeID: node).first?.portID, direction: .outbound, layer: .application, operation: .sent, afterHeaders: [.init(name: "kind", value: proto), .init(name: "command", value: command)], detail: "\(proto) command sent") }
    }
    private mutating func emailResponse(_ socket: UUID, pump: Bool) throws -> String {
        if pump, let remoteIPAddress = networkRuntime.tcpSocketRecord(socketID: socket)?.remoteIPAddress {
            let serverNodeIDs = networkRuntime.state.topologySnapshot.nodes
                .filter { node in
                    networkRuntime.networkInterfaces(nodeID: node.id).contains { $0.ipAddress == remoteIPAddress }
                }
                .map(\.id)
                .sorted { $0.uuidString < $1.uuidString }
            for serverNodeID in serverNodeIDs { _ = processRuntimeEmailServer(nodeID: serverNodeID) }
        }
        guard let data = networkRuntime.receiveTCP(socketID: socket),
              let text = String(data: data, encoding: .utf8)
        else { throw TopologyRuntimeEmailOperationError.malformedResponse }
        return text
    }

    private mutating func resolveRuntimeEmailMXEndpoints(
        fromNodeID nodeID: UUID,
        recipientDomain domain: String
    ) throws -> EmailMXResolution {
        let normalizedDomain = domain.lowercased()
        let mxResult = resolveRuntimeDNSQuestion(
            nodeID: nodeID,
            hostname: normalizedDomain,
            recordType: .mailExchange
        )
        guard case let .success(mxAnswer) = mxResult else {
            throw TopologyRuntimeEmailOperationError.dnsFailure(
                "MX \(normalizedDomain): \(runtimeEmailDNSDiagnostic(mxResult))"
            )
        }

        var seenExchangers = Set<TopologyDNSName>()
        let exchangers = mxAnswer.records.compactMap { record -> TopologyDNSName? in
            guard record.name == mxAnswer.question.name,
                  case let .mailExchange(exchanger) = record.data,
                  seenExchangers.insert(exchanger).inserted
            else { return nil }
            return exchanger
        }
        guard !exchangers.isEmpty else {
            throw TopologyRuntimeEmailOperationError.dnsFailure(
                "MX \(normalizedDomain): resolver returned no exchanger records"
            )
        }

        var endpoints: [EmailMXEndpoint] = []
        var diagnostics: [String] = []
        for (preferenceOrder, exchanger) in exchangers.enumerated() {
            var seenAddresses = Set<String>()
            var addresses = mxAnswer.records.compactMap { record -> String? in
                guard record.name == exchanger,
                      case let .address(address) = record.data,
                      seenAddresses.insert(address.rawValue).inserted
                else { return nil }
                return address.rawValue
            }
            if addresses.isEmpty {
                let addressResult = resolveRuntimeDNSQuestion(
                    nodeID: nodeID,
                    hostname: exchanger.rawValue,
                    recordType: .address
                )
                guard case let .success(addressAnswer) = addressResult else {
                    diagnostics.append(
                        "order=\(preferenceOrder),exchange=\(exchanger.rawValue),A=\(runtimeEmailDNSDiagnostic(addressResult))"
                    )
                    continue
                }
                addresses = addressAnswer.records.compactMap { record -> String? in
                    guard record.name == exchanger,
                          case let .address(address) = record.data,
                          seenAddresses.insert(address.rawValue).inserted
                    else { return nil }
                    return address.rawValue
                }
            }
            guard !addresses.isEmpty else {
                diagnostics.append(
                    "order=\(preferenceOrder),exchange=\(exchanger.rawValue),A=no-address-records"
                )
                continue
            }
            endpoints.append(contentsOf: addresses.map {
                EmailMXEndpoint(
                    preferenceOrder: preferenceOrder,
                    exchangerHostname: exchanger.rawValue,
                    address: $0
                )
            })
        }

        guard !endpoints.isEmpty else {
            let detail = diagnostics.isEmpty ? "no exchanger addresses" : diagnostics.joined(separator: "; ")
            throw TopologyRuntimeEmailOperationError.dnsFailure(
                "MX \(normalizedDomain) has no routable exchanger A records: \(detail)"
            )
        }
        return EmailMXResolution(endpoints: endpoints, diagnostics: diagnostics)
    }

    private func runtimeEmailDNSDiagnostic(_ result: TopologyDNSResolverResult) -> String {
        let trace = result.trace.consultedServerIPAddresses.isEmpty
            ? "none"
            : result.trace.consultedServerIPAddresses.joined(separator: "->")
        switch result {
        case .success(let answer):
            return "success(server=\(answer.respondingServerIPAddress),records=\(answer.records.count),consulted=\(trace))"
        case .nameError(let question, _):
            return "name-error(name=\(question.name.rawValue),consulted=\(trace))"
        case .noData(let question, _):
            return "no-data(name=\(question.name.rawValue),type=\(question.type.rawValue),consulted=\(trace))"
        case .failure(let failure, _):
            return "failure(\(runtimeEmailDNSFailureDiagnostic(failure)),consulted=\(trace))"
        }
    }

    private func runtimeEmailDNSFailureDiagnostic(_ failure: TopologyDNSResolutionFailure) -> String {
        switch failure {
        case .invalidStartingServerAddress(let address):
            return "invalid-starting-server=\(address)"
        case .serverUnavailable(let address):
            return "server-unavailable=\(address)"
        case .serverTimedOut(let address):
            return "server-timed-out=\(address)"
        case .referralMissingAddress(let nameServer):
            return "referral-missing-address=\(nameServer)"
        case .loopDetected(let serverIPAddress):
            return "loop-detected=\(serverIPAddress)"
        case .hopLimitExceeded(let limit):
            return "hop-limit=\(limit)"
        case .responseLimitExceeded(let limit):
            return "response-limit=\(limit)"
        case .responseRecordLimitExceeded(let serverIPAddress, let limit):
            return "record-limit=\(limit)@\(serverIPAddress)"
        }
    }

    private mutating func relayRuntimeEmail(
        fromNodeID nodeID: UUID,
        request: EmailRelayRequest
    ) -> Result<String, TopologyRuntimeEmailOperationError> {
        guard let domain = request.recipients.first?.mailAddress.split(separator: "@").last.map(String.init),
              request.recipients.allSatisfy({ $0.mailAddress.lowercased().hasSuffix("@\(domain.lowercased())") })
        else { return .failure(.validation("Remote relay recipients must share one domain.")) }

        do {
            let normalizedDomain = domain.lowercased()
            let resolution = try resolveRuntimeEmailMXEndpoints(
                fromNodeID: nodeID,
                recipientDomain: normalizedDomain
            )
            var attempts = resolution.diagnostics

            for endpoint in resolution.endpoints {
                let route = "order=\(endpoint.preferenceOrder),exchange=\(endpoint.exchangerHostname),address=\(endpoint.address)"
                guard !networkRuntime.networkInterfaces(nodeID: nodeID).contains(where: { $0.ipAddress == endpoint.address }) else {
                    attempts.append("\(route),failure=resolved-to-sending-server")
                    continue
                }

                var submissionAttempt = 0
                while submissionAttempt < 2 {
                    var messageBodySubmitted = false
                    do {
                        let socket = try openEmailSocket(
                            nodeID,
                            endpoint.address,
                            TopologyRuntimeEmailServerConfiguration.smtpPort
                        )
                        defer { _ = networkRuntime.closeTCPConnectionAndClean(socketID: socket) }
                        guard try emailResponse(socket, pump: true).hasPrefix("220") else {
                            throw TopologyRuntimeEmailOperationError.malformedResponse
                        }
                        try smtp("HELO \(normalizedDomain)", "250", socket)
                        try smtp("MAIL FROM:<\(request.message.from.mailAddress)>", "250", socket)
                        for recipient in request.recipients {
                            try smtp("RCPT TO:<\(recipient.mailAddress)>", "250", socket)
                        }
                        try smtp("DATA", "354", socket)
                        messageBodySubmitted = true
                        try sendEmailPayload(
                            stuffDots(request.message.javaWireString) + "\r\n.\r\n",
                            socket,
                            "SMTP",
                            "message"
                        )
                        let queued = try emailResponse(socket, pump: true)
                        guard queued.hasPrefix("250") else {
                            throw TopologyRuntimeEmailOperationError.protocolError(
                                queued.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        }
                        try? smtp("QUIT", "221", socket)
                        let precedingAttempts = attempts.isEmpty
                            ? "none"
                            : attempts.joined(separator: "; ")
                        return .success(
                            "domain=\(normalizedDomain),\(route),idempotentRetries=\(submissionAttempt),fallbacks=\(precedingAttempts)"
                        )
                    } catch {
                        let operationError: TopologyRuntimeEmailOperationError = error as? TopologyRuntimeEmailOperationError
                            ?? .protocolError(error.localizedDescription)
                        let attempt = "\(route),submission=\(submissionAttempt + 1),failure=\(operationError.localizedDescription)"
                        attempts.append(attempt)
                        guard messageBodySubmitted else { break }
                        if request.message.deliveryIdentity != nil, submissionAttempt == 0 {
                            submissionAttempt += 1
                            attempts.append("\(route),action=idempotent-retry-same-endpoint")
                            continue
                        }
                        return .failure(.protocolError(
                            "MX relay outcome is uncertain after message submission; fallback suppressed; \(attempts.joined(separator: "; "))"
                        ))
                    }
                }
            }

            return .failure(.unreachable(
                "MX routes for \(normalizedDomain) exhausted: \(attempts.joined(separator: "; "))"
            ))
        } catch let error as TopologyRuntimeEmailOperationError {
            return .failure(error)
        } catch {
            return .failure(.protocolError(error.localizedDescription))
        }
    }

}

private extension Result where Success == String, Failure == TopologyRuntimeEmailOperationError {
    func failureMessage(_ failure: String) -> (Self, String) { switch self { case let .success(message): return (self, message); case .failure: return (self, failure) } }
}


private func handleSMTP(_ data: Data, _ session: inout EmailSMTPSession, _ config: inout TopologyRuntimeEmailServerConfiguration) -> EmailOutcome {
    if session.phase == .data {
        session.data.append(data); guard session.data.count <= TopologyRuntimeEmailMessage.maximumWireBytes else { session = .init(phase: .greeted); return .init(response: "552 Message too large\r\n", log: "SMTP quota rejection") }
        guard let wire = terminatedSMTP(session.data) else { return .init(response: nil, log: "SMTP DATA buffered") }
        defer { session = .init(phase: .greeted) }
        do {
            var message = try TopologyRuntimeEmailMessage.parseJavaWireString(unstuffDots(wire), id: TopologyRuntimeEmailMessage.unassignedID)
            guard let sender = session.sender else {
                return .init(response: "503 Bad sequence of commands\r\n", log: "SMTP sender missing")
            }
            message.from = sender
            message.bcc = []
            message.receivedAtMilliseconds = nil
            message.isNew = true
            message.isSent = false
            let recipientAddresses = session.recipients.compactMap { TopologyRuntimeEmailAddress(javaString: $0) }
            guard recipientAddresses.count == session.recipients.count else {
                return .init(response: "501 Malformed recipient address\r\n", log: "SMTP malformed recipient")
            }
            let localRecipients = recipientAddresses.filter { $0.mailAddress.lowercased().hasSuffix("@\(config.domain)") }
            let remoteRecipients = recipientAddresses.filter { !$0.mailAddress.lowercased().hasSuffix("@\(config.domain)") }
            let remoteGroups = Dictionary(grouping: remoteRecipients) { recipient in
                recipient.mailAddress.split(separator: "@").last.map { String($0).lowercased() } ?? ""
            }
            guard remoteGroups.count <= 1 else {
                return .init(
                    response: "451 Requested action aborted: multiple remote domains require separate messages\r\n",
                    log: "SMTP multi-domain relay rejected"
                )
            }
            let localIndexes = localRecipients.compactMap { config.accountIndex(email: $0.mailAddress) }
            guard localIndexes.count == localRecipients.count else {
                return .init(response: "550 No such user here\r\n", log: "SMTP unknown local recipient")
            }
            let deliveryReceipt = message.deliveryIdentity.map {
                TopologyRuntimeEmailDeliveryReceipt(
                    identity: $0,
                    contentSignature: TopologyRuntimeEmailDeliveryIdentity.contentSignature(
                        message: message,
                        recipients: recipientAddresses
                    )
                )
            }
            if let deliveryReceipt,
               let existingReceipt = config.deliveryReceipt(identity: deliveryReceipt.identity)
            {
                guard existingReceipt == deliveryReceipt else {
                    return .init(
                        response: "554 Delivery identity conflicts with previously accepted content\r\n",
                        log: "SMTP delivery identity conflict"
                    )
                }
                return .init(
                    response: "250 Message already accepted for delivery\r\n",
                    log: "SMTP duplicate delivery suppressed"
                )
            }
            guard localIndexes.allSatisfy({ config.accounts[$0].mailbox.count < TopologyRuntimeEmailServerAccount.maximumMailboxMessages }) else {
                return .init(response: "452 Insufficient storage\r\n", log: "SMTP mailbox quota")
            }
            var candidate = config
            for index in localIndexes {
                var delivered = message
                delivered.id = candidate.nextMessageID
                candidate.nextMessageID += 1
                candidate.accounts[index].mailbox.append(delivered)
            }
            do {
                if let deliveryReceipt { try candidate.appendDeliveryReceipt(deliveryReceipt) }
                try candidate.validate()
                try TopologyRuntimeEmailStorage.validatePersistedSize(server: candidate)
            } catch let error as TopologyRuntimeEmailValidationError where error == .deliveryIdentityConflict {
                return .init(
                    response: "554 Delivery identity conflicts with previously accepted content\r\n",
                    log: "SMTP delivery identity conflict"
                )
            } catch {
                return .init(response: "452 Insufficient storage\r\n", log: "SMTP persistence quota")
            }
            config = candidate
            let relays = remoteGroups.keys.sorted().compactMap { domain -> EmailRelayRequest? in
                guard !domain.isEmpty, let recipients = remoteGroups[domain] else { return nil }
                return EmailRelayRequest(message: message, recipients: recipients)
            }
            return .init(
                response: "250 Message accepted for delivery\r\n",
                log: relays.isEmpty ? "SMTP local delivery" : "SMTP local/relay delivery",
                relays: relays
            )
        } catch { return .init(response: "501 Malformed message data\r\n", log: "SMTP malformed DATA") }
    }
    guard let text = String(data: data, encoding: .utf8) else { return .init(response: "501 Command must be UTF-8\r\n", log: "SMTP invalid UTF-8") }
    let line = text.trimmingCharacters(in: .whitespacesAndNewlines), upper = line.uppercased()
    if upper == "QUIT" { return .init(response: "221 Bye\r\n", close: true, log: "SMTP QUIT") }
    if upper.hasPrefix("HELO") { guard line.split(separator: " ", maxSplits: 1).count == 2 else { return .init(response: "501 HELO requires a hostname\r\n", log: "SMTP 501 HELO") }; session = .init(phase: .greeted); return .init(response: "250 Hello\r\n", log: "SMTP HELO") }
    if upper.hasPrefix("MAIL FROM") { guard session.phase == .greeted else { return .init(response: "503 Bad sequence of commands\r\n", log: "SMTP 503 MAIL") }; guard let address = pathAddress(line, "MAIL FROM:") else { return .init(response: "501 Invalid sender address\r\n", log: "SMTP 501 MAIL") }; session.sender = address; session.recipients = []; session.phase = .sender; return .init(response: "250 Sender OK\r\n", log: "SMTP MAIL") }
    if upper.hasPrefix("RCPT TO") {
        guard session.phase == .sender || session.phase == .recipients else { return .init(response: "503 Bad sequence of commands\r\n", log: "SMTP 503 RCPT") }
        guard let address = pathAddress(line, "RCPT TO:") else { return .init(response: "501 Invalid recipient address\r\n", log: "SMTP 501 RCPT") }
        let isLocal = address.mailAddress.lowercased().hasSuffix("@\(config.domain)")
        if isLocal, config.accountIndex(email: address.mailAddress) == nil {
            return .init(response: "550 No such user here\r\n", log: "SMTP unknown recipient")
        }
        if !session.recipients.contains(where: { $0.caseInsensitiveCompare(address.mailAddress) == .orderedSame }) {
            session.recipients.append(address.mailAddress)
        }
        session.phase = .recipients
        return .init(response: "250 Recipient OK\r\n", log: isLocal ? "SMTP local RCPT" : "SMTP relay RCPT")
    }
    if upper == "DATA" { guard session.phase == .recipients, !session.recipients.isEmpty else { return .init(response: "503 Bad sequence of commands\r\n", log: "SMTP 503 DATA") }; session.phase = .data; session.data.removeAll(); return .init(response: "354 End data with <CRLF>.<CRLF>\r\n", log: "SMTP DATA") }
    return .init(response: "501 Command unrecognized\r\n", log: "SMTP 501 command")
}

private func handlePOP3(_ data: Data, _ session: inout EmailPOP3Session, _ config: inout TopologyRuntimeEmailServerConfiguration) -> EmailOutcome {
    guard let text = String(data: data, encoding: .utf8) else { return .init(response: "-ERR command must be UTF-8\r\n", log: "POP3 invalid UTF-8") }
    let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", maxSplits: 1).map(String.init), command = parts.first?.uppercased() ?? "", arg = parts.count > 1 ? parts[1] : nil
    if command == "QUIT" { if session.authenticated, let user = session.username, let index = config.accountIndex(username: user) { config.accounts[index].mailbox.removeAll { session.deleted.contains($0.id) } }; return .init(response: "+OK goodbye\r\n", close: true, log: "POP3 QUIT commit") }
    if command == "USER" { guard let arg, let index = config.accountIndex(username: arg) else { session = .init(); return .init(response: "-ERR authentication failed\r\n", log: "POP3 USER rejected") }; session = .init(username: config.accounts[index].username); return .init(response: "+OK user accepted\r\n", log: "POP3 USER") }
    if command == "PASS" { guard let user = session.username, let index = config.accountIndex(username: user) else { return .init(response: "-ERR USER required\r\n", log: "POP3 PASS sequence") }; guard let arg, arg == config.accounts[index].password else { session.authenticated = false; session.messageIDs = []; return .init(response: "-ERR authentication failed\r\n", log: "POP3 password rejected") }; session.authenticated = true; session.messageIDs = config.accounts[index].mailbox.map(\.id); session.deleted = []; return .init(response: "+OK mailbox locked and ready\r\n", log: "POP3 authentication succeeded") }
    guard session.authenticated, let user = session.username, let index = config.accountIndex(username: user) else { return .init(response: "-ERR authorization required\r\n", log: "POP3 authorization required") }
    func message(_ number: Int) -> TopologyRuntimeEmailMessage? { guard session.messageIDs.indices.contains(number) else { return nil }; let id = session.messageIDs[number]; guard !session.deleted.contains(id) else { return nil }; return config.accounts[index].mailbox.first { $0.id == id } }
    let visible = session.messageIDs.filter { !session.deleted.contains($0) }.compactMap { id in config.accounts[index].mailbox.first { $0.id == id } }
    if command == "STAT" { return .init(response: "+OK \(visible.count) \(visible.reduce(0) { $0 + $1.javaWireString.lengthOfBytes(using: .utf8) })\r\n", log: "POP3 STAT") }
    if command == "LIST" { if let arg { guard let n = Int(arg), let m = message(n) else { return .init(response: "-ERR no such message\r\n", log: "POP3 LIST missing") }; return .init(response: "+OK \(n) \(m.javaWireString.lengthOfBytes(using: .utf8))\r\n", log: "POP3 LIST") }; var response = "+OK \(visible.count) messages\r\n"; for n in session.messageIDs.indices { if let m = message(n) { response += "\(n) \(m.javaWireString.lengthOfBytes(using: .utf8))\r\n" } }; return .init(response: response + ".\r\n", log: "POP3 LIST") }
    if command == "RETR" { guard let arg, let n = Int(arg), let m = message(n) else { return .init(response: "-ERR no such message\r\n", log: "POP3 RETR missing") }; if let i = config.accounts[index].mailbox.firstIndex(where: { $0.id == m.id }) { config.accounts[index].mailbox[i].isNew = false }; return .init(response: "+OK \(m.javaWireString.lengthOfBytes(using: .utf8)) octets\r\n\(stuffDots(m.javaWireString))\r\n.\r\n", log: "POP3 RETR") }
    if command == "DELE" { guard let arg, let n = Int(arg), let m = message(n) else { return .init(response: "-ERR no such message\r\n", log: "POP3 DELE missing") }; session.deleted.insert(m.id); return .init(response: "+OK message marked for delete\r\n", log: "POP3 DELE") }
    if command == "RSET" { session.deleted.removeAll(); return .init(response: "+OK deletion marks cleared\r\n", log: "POP3 RSET") }
    return .init(response: "-ERR unknown command\r\n", log: "POP3 unknown command")
}

private func pathAddress(_ line: String, _ prefix: String) -> TopologyRuntimeEmailAddress? { guard line.uppercased().hasPrefix(prefix) else { return nil }; return .init(javaString: String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)) }
private func terminatedSMTP(_ data: Data) -> String? { guard let raw = String(data: data, encoding: .utf8) else { return nil }; if let r = raw.range(of: "\r\n.\r\n") { return String(raw[..<r.lowerBound]) }; if let r = raw.range(of: "\n.\n") { return String(raw[..<r.lowerBound]) }; return nil }
private func stuffDots(_ value: String) -> String { value.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map { $0.hasPrefix(".") ? "." + String($0) : String($0) }.joined(separator: "\r\n") }
private func unstuffDots(_ value: String) -> String { value.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map { $0.hasPrefix("..") ? String($0.dropFirst()) : String($0) }.joined(separator: "\n") }
