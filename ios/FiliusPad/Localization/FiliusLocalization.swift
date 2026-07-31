import Foundation

enum FiliusAppLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case german = "de"
    case english = "en"
    case french = "fr"

    var id: String { rawValue }

    var localeIdentifier: String? {
        switch self {
        case .system: return nil
        case .german: return "de"
        case .english: return "en"
        case .french: return "fr"
        }
    }

    var localizationKey: String {
        switch self {
        case .system: return "settings.language.system"
        case .german: return "settings.language.german"
        case .english: return "settings.language.english"
        case .french: return "settings.language.french"
        }
    }

    var localizedTitle: String {
        switch self {
        case .system: return FiliusLocalization.t("settings.language.system")
        case .german: return FiliusLocalization.t("settings.language.german")
        case .english: return FiliusLocalization.t("settings.language.english")
        case .french: return FiliusLocalization.t("settings.language.french")
        }
    }
}

enum FiliusLocalization {
    static let supportedLanguageCodes = ["de", "en", "fr"]
    static let fallbackLanguageCode = "en"

    private static let lock = NSLock()
    private static var activeLanguage: FiliusAppLanguage = .system
    private static var languageBundles: [String: Bundle] = [:]
    private static var localizedFormats: [String: String] = [:]
    private static var missingFormats: Set<String> = []

    static func activate(_ language: FiliusAppLanguage) {
        lock.lock()
        activeLanguage = language
        lock.unlock()
    }

    static func currentLanguage() -> FiliusAppLanguage {
        lock.lock()
        defer { lock.unlock() }
        return activeLanguage
    }

    static func resolvedLanguageCode(
        for language: FiliusAppLanguage? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        let selection = language ?? currentLanguage()
        if let explicit = selection.localeIdentifier {
            return explicit
        }
        for identifier in preferredLanguages {
            let code = identifier
                .replacingOccurrences(of: "_", with: "-")
                .split(separator: "-")
                .first
                .map(String.init)
                .map { $0.lowercased() }
            if let code = code, supportedLanguageCodes.contains(code) {
                return code
            }
        }
        return fallbackLanguageCode
    }

    static func t(_ key: String, _ arguments: CVarArg...) -> String {
        localized(key, arguments: arguments)
    }

    static func plural(_ key: String, count: Int) -> String {
        let suffix = count == 1 ? "one" : "other"
        return localized("\(key).\(suffix)", arguments: [count])
    }

    static func localized(
        _ key: String,
        arguments: [CVarArg] = [],
        language: FiliusAppLanguage? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages,
        bundle: Bundle = .main
    ) -> String {
        let languageCode = resolvedLanguageCode(for: language, preferredLanguages: preferredLanguages)
        let format = localizedFormat(key, languageCode: languageCode, bundle: bundle)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: languageCode), arguments: arguments)
    }

    private static func localizedFormat(_ key: String, languageCode: String, bundle: Bundle) -> String {
        resolvedFormat(key: key, languageCode: languageCode, fallbackLanguageCode: fallbackLanguageCode) { code, lookupKey in
            localizedFormatIfPresent(lookupKey, languageCode: code, bundle: bundle)
        }
    }

    // Shared by the bundle lookup and the hosted production oracle so fallback behavior
    // is tested at the same resolution seam used by product strings.
    static func resolvedFormat(
        key: String,
        languageCode: String,
        fallbackLanguageCode: String,
        lookup: (String, String) -> String?
    ) -> String {
        if let value = lookup(languageCode, key) {
            return value
        }
        if languageCode != fallbackLanguageCode,
           let fallback = lookup(fallbackLanguageCode, key) {
            return fallback
        }
        return key
    }

    private static func localizedFormatIfPresent(
        _ key: String,
        languageCode: String,
        bundle: Bundle
    ) -> String? {
        let bundlePath = bundle.bundlePath
        let cacheKey = bundlePath + "\u{0}" + languageCode + "\u{0}" + key
        lock.lock()
        if let cached = localizedFormats[cacheKey] {
            lock.unlock()
            return cached
        }
        if missingFormats.contains(cacheKey) {
            lock.unlock()
            return nil
        }
        let languageBundleKey = bundlePath + "\u{0}" + languageCode
        let languageBundle: Bundle?
        if let cachedBundle = languageBundles[languageBundleKey] {
            languageBundle = cachedBundle
        } else if let path = bundle.path(forResource: languageCode, ofType: "lproj"),
                  let loadedBundle = Bundle(path: path) {
            languageBundles[languageBundleKey] = loadedBundle
            languageBundle = loadedBundle
        } else {
            languageBundle = nil
        }
        lock.unlock()

        guard let languageBundle = languageBundle else {
            lock.lock()
            missingFormats.insert(cacheKey)
            lock.unlock()
            return nil
        }
        let value = languageBundle.localizedString(forKey: key, value: nil, table: "Localizable")
        guard value != key else {
            lock.lock()
            missingFormats.insert(cacheKey)
            lock.unlock()
            return nil
        }
        lock.lock()
        localizedFormats[cacheKey] = value
        lock.unlock()
        return value
    }
}

struct FiliusLocalizationCatalog: Equatable {
    private static let stringsLineRegex = try! NSRegularExpression(
        pattern: #"^"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)";$"#
    )

    enum CatalogError: Error, Equatable {
        case unreadable
        case duplicateKey(String)
        case malformedLine(Int)
    }

    let values: [String: String]

    init(stringsFileURL: URL) throws {
        guard let source = try? String(contentsOf: stringsFileURL, encoding: .utf8) else {
            throw CatalogError.unreadable
        }
        var parsed: [String: String] = [:]
        for (offset, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("//"), !line.hasPrefix("/*") else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = Self.stringsLineRegex.firstMatch(in: line, options: [], range: range),
                  match.numberOfRanges == 3,
                  let keyRange = Range(match.range(at: 1), in: line),
                  let valueRange = Range(match.range(at: 2), in: line) else {
                throw CatalogError.malformedLine(offset + 1)
            }
            let key = Self.unescape(String(line[keyRange]))
            let value = Self.unescape(String(line[valueRange]))
            guard parsed.updateValue(value, forKey: key) == nil else {
                throw CatalogError.duplicateKey(key)
            }
        }
        values = parsed
    }

    func value(for key: String, fallback: FiliusLocalizationCatalog? = nil) -> String {
        values[key] ?? fallback?.values[key] ?? key
    }

    func formatted(
        _ key: String,
        arguments: [CVarArg],
        localeIdentifier: String,
        fallback: FiliusLocalizationCatalog? = nil
    ) -> String {
        String(
            format: value(for: key, fallback: fallback),
            locale: Locale(identifier: localeIdentifier),
            arguments: arguments
        )
    }

    func plural(
        _ key: String,
        count: Int,
        localeIdentifier: String,
        fallback: FiliusLocalizationCatalog? = nil
    ) -> String {
        let suffix = count == 1 ? "one" : "other"
        return formatted(
            "\(key).\(suffix)",
            arguments: [count],
            localeIdentifier: localeIdentifier,
            fallback: fallback
        )
    }

    private static func unescape(_ value: String) -> String {
        var result = ""
        var iterator = value.makeIterator()
        while let character = iterator.next() {
            guard character == "\\", let escaped = iterator.next() else {
                result.append(character)
                continue
            }
            switch escaped {
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "t": result.append("\t")
            case "\\": result.append("\\")
            case "\"": result.append("\"")
            default:
                result.append("\\")
                result.append(escaped)
            }
        }
        return result
    }
}

typealias L10n = FiliusLocalization
