import Foundation

struct TopologySimulationSpeed: Codable, Equatable, Hashable, Sendable {
    static let minimumPercent = 1
    static let maximumPercent = 100
    static let defaultPercent = 90
    static let wallClockPulseMilliseconds: UInt64 = 200
    static let wallClockPulseNanoseconds = wallClockPulseMilliseconds * 1_000_000

    let percent: Int

    init(percent: Int = Self.defaultPercent) {
        self.percent = min(Self.maximumPercent, max(Self.minimumPercent, percent))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(percent: try container.decode(Int.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(percent)
    }

    var accessibilityValue: String {
        FiliusLocalization.t("settings.speed.percent", percent)
    }

    var displayValue: String {
        "\(percent)%"
    }

    var virtualMillisecondsPerPulse: UInt64 {
        let scaled = Self.wallClockPulseMilliseconds * UInt64(percent) / UInt64(Self.maximumPercent)
        return max(1, scaled)
    }

    func nextVirtualTime(after currentTimeMilliseconds: UInt64) -> UInt64? {
        let (nextTime, overflowed) = currentTimeMilliseconds.addingReportingOverflow(virtualMillisecondsPerPulse)
        return overflowed ? nil : nextTime
    }
}

struct TopologySimulationClockDriver: Equatable, Sendable {
    struct Token: Equatable, Hashable, Sendable {
        fileprivate let generation: UInt64
    }

    enum StartResult: Equatable, Sendable {
        case started(Token)
        case alreadyRunning(Token)
        case generationExhausted
    }

    struct Pulse: Equatable, Sendable {
        let stepMilliseconds: UInt64
        let nextVirtualTimeMilliseconds: UInt64
    }

    enum PulseDecision: Equatable, Sendable {
        case advance(Pulse)
        case inactive
        case overflow
    }

    private(set) var activeToken: Token?
    private var nextGeneration: UInt64? = 1

    var isRunning: Bool {
        activeToken != nil
    }

    mutating func start() -> StartResult {
        if let activeToken {
            return .alreadyRunning(activeToken)
        }
        guard let generation = nextGeneration else {
            return .generationExhausted
        }

        let token = Token(generation: generation)
        activeToken = token
        nextGeneration = generation == UInt64.max ? nil : generation + 1
        return .started(token)
    }

    @discardableResult
    mutating func stop() -> Bool {
        guard activeToken != nil else {
            return false
        }
        activeToken = nil
        return true
    }

    func pulseDecision(
        token: Token,
        speed: TopologySimulationSpeed,
        currentVirtualTimeMilliseconds: UInt64
    ) -> PulseDecision {
        guard token == activeToken else {
            return .inactive
        }
        guard let nextTime = speed.nextVirtualTime(after: currentVirtualTimeMilliseconds) else {
            return .overflow
        }

        return .advance(
            Pulse(
                stepMilliseconds: speed.virtualMillisecondsPerPulse,
                nextVirtualTimeMilliseconds: nextTime
            )
        )
    }

    func pulse(
        token: Token,
        speed: TopologySimulationSpeed,
        currentVirtualTimeMilliseconds: UInt64
    ) -> Pulse? {
        guard case let .advance(pulse) = pulseDecision(
            token: token,
            speed: speed,
            currentVirtualTimeMilliseconds: currentVirtualTimeMilliseconds
        ) else {
            return nil
        }
        return pulse
    }
}

struct TopologyAppPreferences: Codable, Equatable {
    static let defaults = TopologyAppPreferences(
        simulationSpeed: TopologySimulationSpeed(),
        showsVirtualClock: true,
        language: .system,
        experimentalProtocolApplicationsEnabled: false,
        hasCompletedGuidedTour: false
    )

    private(set) var simulationSpeed: TopologySimulationSpeed
    var showsVirtualClock: Bool
    var language: FiliusAppLanguage
    var experimentalProtocolApplicationsEnabled: Bool
    var hasCompletedGuidedTour: Bool

    init(
        simulationSpeed: TopologySimulationSpeed = TopologySimulationSpeed(),
        showsVirtualClock: Bool = true,
        language: FiliusAppLanguage = .system,
        experimentalProtocolApplicationsEnabled: Bool = false,
        hasCompletedGuidedTour: Bool = false
    ) {
        self.simulationSpeed = simulationSpeed
        self.showsVirtualClock = showsVirtualClock
        self.language = language
        self.experimentalProtocolApplicationsEnabled = experimentalProtocolApplicationsEnabled
        self.hasCompletedGuidedTour = hasCompletedGuidedTour
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        simulationSpeed = try container.decodeIfPresent(TopologySimulationSpeed.self, forKey: .simulationSpeed)
            ?? TopologySimulationSpeed()
        showsVirtualClock = try container.decodeIfPresent(Bool.self, forKey: .showsVirtualClock) ?? true
        language = try container.decodeIfPresent(FiliusAppLanguage.self, forKey: .language) ?? .system
        experimentalProtocolApplicationsEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .experimentalProtocolApplicationsEnabled
        ) ?? false
        hasCompletedGuidedTour = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedGuidedTour) ?? false
    }

    mutating func setSimulationSpeed(percent: Int) {
        simulationSpeed = TopologySimulationSpeed(percent: percent)
    }
}

struct TopologyAppPreferencesStore {
    static let defaultStorageKey = "com.filius.pad.product-shell.preferences.v1"

    let defaults: UserDefaults
    let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = Self.defaultStorageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func load() -> TopologyAppPreferences {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(TopologyAppPreferences.self, from: data)
        else {
            return .defaults
        }
        return decoded
    }

    var hasStoredPreferences: Bool {
        defaults.object(forKey: storageKey) != nil
    }

    @discardableResult
    func persist(_ preferences: TopologyAppPreferences) -> TopologyAppPreferencesPersistenceOutcome {
        guard preferences != .defaults else {
            defaults.removeObject(forKey: storageKey)
            return .removedDefaults
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(preferences) else {
            return .encodingFailed
        }
        defaults.set(data, forKey: storageKey)
        return .stored
    }

    func restoreFactoryDefaults() -> TopologyAppPreferences {
        defaults.removeObject(forKey: storageKey)
        return .defaults
    }
}

enum TopologyAppPreferencesPersistenceOutcome: String, Equatable {
    case stored
    case removedDefaults
    case encodingFailed
}

enum TopologyProductHelpContext: String, CaseIterable, Codable {
    case design
    case documentation
    case simulation

    var title: String {
        switch self {
        case .design:
            return FiliusLocalization.t("help.design.title")
        case .documentation:
            return FiliusLocalization.t("help.documentation.title")
        case .simulation:
            return FiliusLocalization.t("help.simulation.title")
        }
    }

    var summary: String {
        switch self {
        case .design:
            return FiliusLocalization.t("help.design.summary")
        case .documentation:
            return FiliusLocalization.t("help.documentation.summary")
        case .simulation:
            return FiliusLocalization.t("help.simulation.summary")
        }
    }

    var steps: [TopologyProductHelpStep] {
        switch self {
        case .design:
            return [
                TopologyProductHelpStep(
                    id: "design-place",
                    title: FiliusLocalization.t("help.design.place.title"),
                    detail: FiliusLocalization.t("help.design.place.detail")
                ),
                TopologyProductHelpStep(
                    id: "design-configure",
                    title: FiliusLocalization.t("help.design.configure.title"),
                    detail: FiliusLocalization.t("help.design.configure.detail")
                ),
                TopologyProductHelpStep(
                    id: "design-connect",
                    title: FiliusLocalization.t("help.design.connect.title"),
                    detail: FiliusLocalization.t("help.design.connect.detail")
                ),
            ]
        case .documentation:
            return [
                TopologyProductHelpStep(
                    id: "documentation-create",
                    title: FiliusLocalization.t("help.documentation.create.title"),
                    detail: FiliusLocalization.t("help.documentation.create.detail")
                ),
                TopologyProductHelpStep(
                    id: "documentation-edit",
                    title: FiliusLocalization.t("help.documentation.edit.title"),
                    detail: FiliusLocalization.t("help.documentation.edit.detail")
                ),
                TopologyProductHelpStep(
                    id: "documentation-export",
                    title: FiliusLocalization.t("help.documentation.export.title"),
                    detail: FiliusLocalization.t("help.documentation.export.detail")
                ),
            ]
        case .simulation:
            return [
                TopologyProductHelpStep(
                    id: "simulation-open",
                    title: FiliusLocalization.t("help.simulation.open.title"),
                    detail: FiliusLocalization.t("help.simulation.open.detail")
                ),
                TopologyProductHelpStep(
                    id: "simulation-speed",
                    title: FiliusLocalization.t("help.simulation.speed.title"),
                    detail: FiliusLocalization.t("help.simulation.speed.detail")
                ),
                TopologyProductHelpStep(
                    id: "simulation-inspect",
                    title: FiliusLocalization.t("help.simulation.inspect.title"),
                    detail: FiliusLocalization.t("help.simulation.inspect.detail")
                ),
            ]
        }
    }
}

struct TopologyProductHelpStep: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let detail: String
}

struct TopologyProductMetadata: Equatable {
    static let repositoryName = "FILIUS"
    static let repositoryLicense = "GNU GPLv2 oder GNU GPLv3"
    static let repositoryLicenseEvidenceFiles = ["Readme.md", "GPLv2.txt", "GPLv3.txt"]
    static let educationalPurpose = "Netzwerksimulation für Bildungszwecke"

    let appName: String
    let version: String
    let build: String
    let bundleIdentifier: String
    let repositoryName: String
    let license: String
    let purpose: String

    static func current(bundle: Bundle = .main) -> TopologyProductMetadata {
        from(
            infoDictionary: bundle.infoDictionary ?? [:],
            bundleIdentifier: bundle.bundleIdentifier
        )
    }

    static func from(
        infoDictionary: [String: Any],
        bundleIdentifier: String?
    ) -> TopologyProductMetadata {
        let appName = nonemptyString(infoDictionary["CFBundleDisplayName"])
            ?? nonemptyString(infoDictionary["CFBundleName"])
            ?? "Filius on iPad"
        let version = nonemptyString(infoDictionary["CFBundleShortVersionString"]) ?? "Unbekannt"
        let build = nonemptyString(infoDictionary["CFBundleVersion"]) ?? "Unbekannt"
        return TopologyProductMetadata(
            appName: appName,
            version: version,
            build: build,
            bundleIdentifier: bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).nonempty
                ?? "Unbekannt",
            repositoryName: Self.repositoryName,
            license: Self.repositoryLicense,
            purpose: Self.educationalPurpose
        )
    }

    var versionDisplay: String {
        "Version \(version) (Build \(build))"
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonempty
    }
}

private extension String {
    var nonempty: String? {
        isEmpty ? nil : self
    }
}
