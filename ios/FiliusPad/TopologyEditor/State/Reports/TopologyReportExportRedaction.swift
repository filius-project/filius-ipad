import Foundation

/// Shared output-boundary redaction used by reports and packet-capture exports.
///
/// The policy intentionally operates on rendered copies. Runtime state remains untouched,
/// while credentials, LAN link codes, and user-authored message bodies never cross an
/// export boundary accidentally.
enum TopologyReportExportRedaction {
    static let marker = "[REDACTED]"
    static let truncatedMarker = "…[TRUNCATED]"

    private static let sensitiveFieldNames: Set<String> = [
        "authorization",
        "bcc",
        "body",
        "content",
        "cookie",
        "credential",
        "credentials",
        "linkcode",
        "linkdigest",
        "message",
        "messagebody",
        "messagetext",
        "pairid",
        "pairidentifier",
        "passwd",
        "passwort",
        "password",
        "payload",
        "proxyauthorization",
        "refreshtoken",
        "secret",
        "setcookie",
        "sharedcode",
        "token",
        "accesstoken",
    ]

    static func isSensitiveFieldName(_ fieldName: String) -> Bool {
        sensitiveFieldNames.contains(normalizedFieldName(fieldName))
    }

    static func redact(fieldName: String, value: String) -> String {
        guard !isSensitiveFieldName(fieldName) else { return marker }
        return redactFreeText(value)
    }

    /// Redacts common inline secret forms and strips RFC-822-style body content after
    /// the first blank line. It deliberately keeps non-sensitive protocol diagnostics.
    static func redactFreeText(_ value: String) -> String {
        var result = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        result = redactRFC822BodyIfPresent(result)
        result = result.components(separatedBy: "\n").map(redactSensitiveLine).joined(separator: "\n")
        result = redactInlineAssignments(result)
        return result
    }

    static func bounded(_ value: String, maximumCharacters: Int) -> String {
        guard maximumCharacters >= 0, value.count > maximumCharacters else { return value }
        return String(value.prefix(maximumCharacters)) + truncatedMarker
    }

    /// Converts arbitrary user/runtime text into one physical report line while retaining
    /// enough escape information for a reader to distinguish tabs and line breaks.
    static func singleLine(fieldName: String = "", value: String) -> String {
        let redacted = redact(fieldName: fieldName, value: value)
        return redacted
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func normalizedFieldName(_ value: String) -> String {
        String(value.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }

    private static func redactRFC822BodyIfPresent(_ value: String) -> String {
        guard let separator = value.range(of: "\n\n") else { return value }
        let header = String(value[..<separator.lowerBound])
        let normalizedHeader = header.lowercased()
        let looksLikeMessage = normalizedHeader.contains("from:")
            && (normalizedHeader.contains("to:") || normalizedHeader.contains("subject:"))
        guard looksLikeMessage else { return value }
        return header + "\n\n" + marker
    }

    private static func redactSensitiveLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return line }

        for delimiter in [":", "="] {
            guard let index = trimmed.firstIndex(of: Character(delimiter)) else { continue }
            let key = String(trimmed[..<index])
            guard isSensitiveFieldName(key) else { continue }
            let prefixLength = line.distance(from: line.startIndex, to: line.range(of: trimmed)!.lowerBound)
            let indentation = String(line.prefix(prefixLength))
            return indentation + key + delimiter + " " + marker
        }
        return line
    }

    private static func redactInlineAssignments(_ value: String) -> String {
        let keyPattern = [
            "access[_ -]?token",
            "authorization",
            "cookie",
            "credential(?:s)?",
            "link[_ -]?code",
            "link[_ -]?digest",
            "message[_ -]?(?:body|text)",
            "pair[_ -]?(?:id|identifier)",
            "pass(?:word|wort|wd)",
            "proxy[_ -]?authorization",
            "refresh[_ -]?token",
            "secret",
            "shared[_ -]?code",
            "token",
        ].joined(separator: "|")
        let pattern = "(?i)\\b(" + keyPattern + ")(\\s*=\\s*)(?:\\\"[^\\\"]*\\\"|'[^']*'|[^&;\\s]+)"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(
            in: value,
            range: range,
            withTemplate: "$1$2" + marker
        )
    }
}
