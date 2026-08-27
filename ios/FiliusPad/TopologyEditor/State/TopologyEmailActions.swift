import Foundation

/// The recipient scope used when composing a response to an existing message.
enum TopologyRuntimeEmailReplyMode: Equatable {
    case reply
    case replyAll
}

/// Client folders that support user-initiated deletion.
enum TopologyRuntimeEmailClientFolder: String, CaseIterable, Equatable {
    case inbox
    case sent
}

enum TopologyRuntimeEmailActionError: Error, Equatable, LocalizedError {
    case noReplyRecipient
    case invalidMessageIdentifier(UInt64)
    case messageNotFound(folder: TopologyRuntimeEmailClientFolder, id: UInt64)

    var errorDescription: String? {
        switch self {
        case .noReplyRecipient:
            return "The message has no recipient that can receive a reply."
        case let .invalidMessageIdentifier(id):
            return "Email message identifier \(id) is not assigned."
        case let .messageNotFound(folder, id):
            return "Email message \(id) was not found in the \(folder.rawValue) folder."
        }
    }
}

/// The atomic result of deleting one or more messages from a client folder.
struct TopologyRuntimeEmailDeletionResult: Equatable {
    var configuration: TopologyRuntimeEmailClientConfiguration
    var deletedMessages: [TopologyRuntimeEmailMessage]
}

/// Pure, deterministic operations used by the Email Client UI and reducer adapters.
enum TopologyEmailActions {
    private static let replyPrefix = "Re:"

    /// Builds an unsent reply draft while omitting BCC recipients and the sender's own address.
    static func replyDraft(
        to original: TopologyRuntimeEmailMessage,
        from sender: TopologyRuntimeEmailAddress,
        mode: TopologyRuntimeEmailReplyMode,
        attribution: String? = nil
    ) throws -> TopologyRuntimeEmailMessage {
        try sender.validate()

        let recipients = replyRecipients(to: original, from: sender, mode: mode)
        guard !(recipients.to + recipients.cc).isEmpty else {
            throw TopologyRuntimeEmailActionError.noReplyRecipient
        }

        let replyAttribution = attribution?.trimmingCharacters(in: .whitespacesAndNewlines)
        let attributionLine: String
        if let replyAttribution, !replyAttribution.isEmpty {
            attributionLine = replyAttribution
        } else {
            attributionLine = "\(original.from.javaString) wrote:"
        }
        let body = "\n\n\(attributionLine)\n\(quotedBody(original.body))"
        let draft = TopologyRuntimeEmailMessage(
            id: TopologyRuntimeEmailMessage.unassignedID,
            from: sender,
            to: recipients.to,
            cc: recipients.cc,
            bcc: [],
            subject: replySubject(original.subject),
            body: body,
            receivedAtMilliseconds: nil,
            isNew: false,
            isMarkedForDeletion: false,
            isSent: false
        )
        try draft.validate()
        return draft
    }

    /// Canonicalizes a reply subject and avoids stacking another `Re:` prefix.
    static func replySubject(_ subject: String) -> String {
        let normalized = subject
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")

        let candidate: String
        if normalized.lowercased().hasPrefix(replyPrefix.lowercased()) {
            candidate = normalized
        } else if normalized.isEmpty {
            candidate = replyPrefix
        } else {
            candidate = "\(replyPrefix) \(normalized)"
        }
        return String(candidate.prefix(256))
    }

    /// Normalizes line endings and prefixes every source line, including blank lines.
    static func quotedBody(_ body: String) -> String {
        body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { "> \($0)" }
            .joined(separator: "\n")
    }

    /// Deletes one message by stable identifier without modifying any other folder.
    static func deletingMessage(
        withID messageID: UInt64,
        from folder: TopologyRuntimeEmailClientFolder,
        configuration: TopologyRuntimeEmailClientConfiguration
    ) throws -> TopologyRuntimeEmailDeletionResult {
        try deletingMessages(withIDs: [messageID], from: folder, configuration: configuration)
    }

    /// Atomically deletes the requested stable identifiers and returns deleted messages in folder order.
    static func deletingMessages(
        withIDs messageIDs: [UInt64],
        from folder: TopologyRuntimeEmailClientFolder,
        configuration: TopologyRuntimeEmailClientConfiguration
    ) throws -> TopologyRuntimeEmailDeletionResult {
        var uniqueIDs: [UInt64] = []
        var seenIDs = Set<UInt64>()
        for id in messageIDs where seenIDs.insert(id).inserted {
            guard id != TopologyRuntimeEmailMessage.unassignedID else {
                throw TopologyRuntimeEmailActionError.invalidMessageIdentifier(id)
            }
            uniqueIDs.append(id)
        }
        guard !uniqueIDs.isEmpty else {
            return TopologyRuntimeEmailDeletionResult(configuration: configuration, deletedMessages: [])
        }

        let messages = messages(in: folder, configuration: configuration)
        let availableIDs = Set(messages.map(\.id))
        if let missingID = uniqueIDs.first(where: { !availableIDs.contains($0) }) {
            throw TopologyRuntimeEmailActionError.messageNotFound(folder: folder, id: missingID)
        }

        let requestedIDs = Set(uniqueIDs)
        let deletedMessages = messages.filter { requestedIDs.contains($0.id) }
        let retainedMessages = messages.filter { !requestedIDs.contains($0.id) }
        var updatedConfiguration = configuration
        setMessages(retainedMessages, in: folder, configuration: &updatedConfiguration)
        return TopologyRuntimeEmailDeletionResult(
            configuration: updatedConfiguration,
            deletedMessages: deletedMessages
        )
    }

    /// Deletes every message from one folder while leaving the other client folders untouched.
    static func deletingAllMessages(
        from folder: TopologyRuntimeEmailClientFolder,
        configuration: TopologyRuntimeEmailClientConfiguration
    ) -> TopologyRuntimeEmailDeletionResult {
        let deletedMessages = messages(in: folder, configuration: configuration)
        var updatedConfiguration = configuration
        setMessages([], in: folder, configuration: &updatedConfiguration)
        return TopologyRuntimeEmailDeletionResult(
            configuration: updatedConfiguration,
            deletedMessages: deletedMessages
        )
    }

    private static func replyRecipients(
        to original: TopologyRuntimeEmailMessage,
        from sender: TopologyRuntimeEmailAddress,
        mode: TopologyRuntimeEmailReplyMode
    ) -> (to: [TopologyRuntimeEmailAddress], cc: [TopologyRuntimeEmailAddress]) {
        let ownAddress = sender.normalizedMailAddress

        switch mode {
        case .reply:
            let candidates = [original.from] + original.to + original.cc
            let recipient = candidates.first { $0.normalizedMailAddress != ownAddress }
            return (recipient.map { [$0] } ?? [], [])

        case .replyAll:
            var seen = Set([ownAddress])
            let to = ([original.from] + original.to).filter {
                seen.insert($0.normalizedMailAddress).inserted
            }
            let cc = original.cc.filter {
                seen.insert($0.normalizedMailAddress).inserted
            }
            return (to, cc)
        }
    }

    private static func messages(
        in folder: TopologyRuntimeEmailClientFolder,
        configuration: TopologyRuntimeEmailClientConfiguration
    ) -> [TopologyRuntimeEmailMessage] {
        switch folder {
        case .inbox:
            return configuration.inbox
        case .sent:
            return configuration.sent
        }
    }

    private static func setMessages(
        _ messages: [TopologyRuntimeEmailMessage],
        in folder: TopologyRuntimeEmailClientFolder,
        configuration: inout TopologyRuntimeEmailClientConfiguration
    ) {
        switch folder {
        case .inbox:
            configuration.inbox = messages
        case .sent:
            configuration.sent = messages
        }
    }
}
