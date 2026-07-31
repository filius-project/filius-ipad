import Foundation

enum TopologyProjectSaveReason: String, Codable, Equatable {
    case autosave
    case manualSave
}

struct TopologyProjectEnvelope: Codable, Equatable {
    static let formatIdentifier = "com.filius.pad.project"
    static let currentSchemaVersion = 9

    let format: String
    let schemaVersion: Int
    let savedAt: Date
    let saveReason: TopologyProjectSaveReason
    let payload: TopologyProjectSnapshot

    init(
        format: String = TopologyProjectEnvelope.formatIdentifier,
        schemaVersion: Int = TopologyProjectEnvelope.currentSchemaVersion,
        savedAt: Date,
        saveReason: TopologyProjectSaveReason = .autosave,
        payload: TopologyProjectSnapshot
    ) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.saveReason = saveReason
        self.payload = payload
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case format
        case schemaVersion
        case savedAt
        case saveReason
        case payload
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyProjectEnvelope"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        saveReason = try container.decodeIfPresent(TopologyProjectSaveReason.self, forKey: .saveReason) ?? .autosave
        payload = try container.decode(TopologyProjectSnapshot.self, forKey: .payload)
    }
}

struct TopologyProjectAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

func assertNoUnknownKeys<Key: CodingKey & CaseIterable>(
    decoder: Decoder,
    allowedKeys: Key.Type,
    context: String
) throws {
    let dynamicContainer = try decoder.container(keyedBy: TopologyProjectAnyCodingKey.self)
    let knownKeyNames = Set(allowedKeys.allCases.map(\.stringValue))
    let unknownKeys = dynamicContainer.allKeys
        .map(\.stringValue)
        .filter { !knownKeyNames.contains($0) }
        .sorted()

    guard unknownKeys.isEmpty else {
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "\(context) contains unknown keys: \(unknownKeys.joined(separator: ", "))"
            )
        )
    }
}
