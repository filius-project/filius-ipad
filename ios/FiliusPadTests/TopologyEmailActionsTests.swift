import XCTest
@testable import FiliusPad

final class TopologyEmailActionsTests: XCTestCase {
    private let currentUser = TopologyRuntimeEmailAddress(
        name: "Morgan User",
        mailAddress: "morgan@example.test"
    )

    func testReplyTargetsSenderAndBuildsCanonicalDraft() throws {
        let original = message(
            id: 41,
            from: address("Alice", "alice@example.test"),
            to: [currentUser],
            cc: [address("Bob", "bob@example.test")],
            bcc: [address("Hidden", "hidden@example.test")],
            subject: "Status update",
            body: "First line\r\n\r\nLast line",
            isNew: true,
            isMarkedForDeletion: true,
            isSent: true
        )

        let draft = try TopologyEmailActions.replyDraft(
            to: original,
            from: currentUser,
            mode: .reply
        )

        XCTAssertEqual(draft.id, TopologyRuntimeEmailMessage.unassignedID)
        XCTAssertEqual(draft.from, currentUser)
        XCTAssertEqual(draft.to, [address("Alice", "alice@example.test")])
        XCTAssertTrue(draft.cc.isEmpty)
        XCTAssertTrue(draft.bcc.isEmpty)
        XCTAssertEqual(draft.subject, "Re: Status update")
        XCTAssertEqual(
            draft.body,
            "\n\nAlice <alice@example.test> wrote:\n> First line\n> \n> Last line"
        )
        XCTAssertNil(draft.receivedAtMilliseconds)
        XCTAssertFalse(draft.isNew)
        XCTAssertFalse(draft.isMarkedForDeletion)
        XCTAssertFalse(draft.isSent)
    }

    func testReplyAllPreservesRecipientOrderWhileRemovingSelfDuplicatesAndBCC() throws {
        let alice = address("Alice", "alice@example.test")
        let dave = address("Dave", "dave@example.test")
        let carol = address("Carol", "carol@example.test")
        let original = message(
            id: 42,
            from: alice,
            to: [currentUser, dave, address("Alice duplicate", "ALICE@example.test")],
            cc: [address("Dave duplicate", "DAVE@example.test"), carol, currentUser],
            bcc: [address("Hidden", "hidden@example.test")],
            subject: "RE: Existing thread",
            body: "Body"
        )

        let draft = try TopologyEmailActions.replyDraft(
            to: original,
            from: currentUser,
            mode: .replyAll,
            attribution: "Alice replied:"
        )

        XCTAssertEqual(draft.to, [alice, dave])
        XCTAssertEqual(draft.cc, [carol])
        XCTAssertTrue(draft.bcc.isEmpty)
        XCTAssertEqual(draft.subject, "RE: Existing thread")
        XCTAssertEqual(draft.body, "\n\nAlice replied:\n> Body")
    }

    func testReplyAllSupportsCCOnlySentMessage() throws {
        let carol = address("Carol", "carol@example.test")
        let original = message(
            id: 43,
            from: currentUser,
            to: [currentUser],
            cc: [carol],
            subject: "CC thread",
            body: "Body"
        )

        let draft = try TopologyEmailActions.replyDraft(
            to: original,
            from: currentUser,
            mode: .replyAll
        )

        XCTAssertTrue(draft.to.isEmpty)
        XCTAssertEqual(draft.cc, [carol])
    }

    func testReplyToOwnSentMessageUsesFirstNonSelfRecipient() throws {
        let firstRecipient = address("Alice", "alice@example.test")
        let original = message(
            id: 43,
            from: currentUser,
            to: [currentUser, firstRecipient, address("Bob", "bob@example.test")],
            cc: [],
            subject: "Question",
            body: "Hello"
        )

        let draft = try TopologyEmailActions.replyDraft(
            to: original,
            from: currentUser,
            mode: .reply
        )

        XCTAssertEqual(draft.to, [firstRecipient])
    }

    func testReplyFailsWhenNoNonSelfRecipientExists() {
        let original = message(
            id: 44,
            from: currentUser,
            to: [currentUser],
            cc: [],
            subject: "Note",
            body: "Body"
        )

        XCTAssertThrowsError(
            try TopologyEmailActions.replyDraft(
                to: original,
                from: currentUser,
                mode: .reply
            )
        ) { error in
            XCTAssertEqual(error as? TopologyRuntimeEmailActionError, .noReplyRecipient)
        }
    }

    func testReplySubjectNormalizesWhitespaceAvoidsDuplicatePrefixAndCapsLength() {
        XCTAssertEqual(TopologyEmailActions.replySubject("  Sprint\r\nreview  "), "Re: Sprint review")
        XCTAssertEqual(TopologyEmailActions.replySubject(" re: Already prefixed "), "re: Already prefixed")
        XCTAssertEqual(TopologyEmailActions.replySubject("\n\r"), "Re:")
        XCTAssertEqual(TopologyEmailActions.replySubject(String(repeating: "x", count: 300)).count, 256)
    }

    func testQuotedBodyNormalizesEveryLineIncludingTrailingBlankLine() {
        XCTAssertEqual(
            TopologyEmailActions.quotedBody("one\rtwo\r\n\n"),
            "> one\n> two\n> \n> "
        )
    }

    func testInboxDeletionIsScopedAndPreservesFolderOrder() throws {
        let inboxFirst = message(id: 1, subject: "Inbox 1")
        let inboxSecond = message(id: 2, subject: "Inbox 2")
        let inboxThird = message(id: 3, subject: "Inbox 3")
        let sent = message(id: 4, subject: "Sent", isSent: true)
        let draft = message(id: 5, subject: "Draft")
        let configuration = configuration(
            inbox: [inboxFirst, inboxSecond, inboxThird],
            sent: [sent],
            drafts: [draft]
        )

        let result = try TopologyEmailActions.deletingMessages(
            withIDs: [3, 1, 3],
            from: .inbox,
            configuration: configuration
        )

        XCTAssertEqual(result.deletedMessages, [inboxFirst, inboxThird])
        XCTAssertEqual(result.configuration.inbox, [inboxSecond])
        XCTAssertEqual(result.configuration.sent, [sent])
        XCTAssertEqual(result.configuration.drafts, [draft])
        XCTAssertEqual(result.configuration.nextMessageID, configuration.nextMessageID)
    }

    func testDeliveryReceiptLedgerEvictsOldestDeterministicallyAndRemainsBounded() throws {
        let originalReceipts = deliveryReceiptsAtCapacity()
        var configuration = emailServerConfiguration(deliveryReceipts: originalReceipts)
        let newestReceipt = deliveryReceipt(index: TopologyRuntimeEmailServerConfiguration.maximumDeliveryReceipts)

        try configuration.appendDeliveryReceipt(newestReceipt)

        let retainedReceipts = try XCTUnwrap(configuration.deliveryReceipts)
        XCTAssertEqual(retainedReceipts.count, TopologyRuntimeEmailServerConfiguration.maximumDeliveryReceipts)
        XCTAssertEqual(retainedReceipts.first, originalReceipts[1])
        XCTAssertEqual(retainedReceipts.last, newestReceipt)
        XCTAssertNil(configuration.deliveryReceipt(identity: originalReceipts[0].identity))
        XCTAssertNoThrow(try configuration.validate())
    }

    func testDeliveryReceiptLedgerPreservesRetainedDuplicateAndConflictSemantics() throws {
        var configuration = emailServerConfiguration(deliveryReceipts: deliveryReceiptsAtCapacity())
        let newestReceipt = deliveryReceipt(index: TopologyRuntimeEmailServerConfiguration.maximumDeliveryReceipts)
        try configuration.appendDeliveryReceipt(newestReceipt)
        let retainedWindow = configuration.deliveryReceipts

        XCTAssertNoThrow(try configuration.appendDeliveryReceipt(newestReceipt))
        XCTAssertEqual(configuration.deliveryReceipts, retainedWindow)

        let conflictingReceipt = TopologyRuntimeEmailDeliveryReceipt(
            identity: newestReceipt.identity,
            contentSignature: deliveryDigest(index: 1_000_000)
        )
        XCTAssertThrowsError(try configuration.appendDeliveryReceipt(conflictingReceipt)) { error in
            XCTAssertEqual(error as? TopologyRuntimeEmailValidationError, .deliveryIdentityConflict)
        }
        XCTAssertEqual(configuration.deliveryReceipts, retainedWindow)
    }

    func testLegacyEmailServerConfigurationWithoutDeliveryReceiptsDecodes() throws {
        let legacyJSON = #"{"accounts":[{"mailbox":[],"name":"Bob Recipient","password":"secret","username":"bob"}],"domain":"recipient.test","nextMessageID":1,"pop3Port":110}"#

        let configuration = try TopologyRuntimeEmailStorage.decodeNativeServer(legacyJSON)

        XCTAssertNil(configuration.deliveryReceipts)
        XCTAssertEqual(configuration.domain, "recipient.test")
        XCTAssertEqual(configuration.accounts.map(\.username), ["bob"])
        XCTAssertNoThrow(try configuration.validate())
    }

    func testRuntimeEmailDeliveryContinuesAtReceiptCapacityAndPersistsRecentWindow() throws {
        var fixture = try makeMXRelayFixture(
            mxExchangers: [
                (hostname: "mail.recipient.test", address: "10.0.0.40"),
            ]
        )
        let originalReceipts = deliveryReceiptsAtCapacity()
        fixture.state.runtimeEmailServerConfigurationsByNodeID[fixture.secondTargetNodeID] =
            emailServerConfiguration(deliveryReceipts: originalReceipts)
        try startEmailServer(nodeID: fixture.secondTargetNodeID, state: &fixture.state)
        fixture.state.runtimeEmailServerProcessesByNodeID[fixture.secondTargetNodeID]?
            .testingSMTPFinalDataResponsesToDrop = 1

        let result = fixture.state.sendRuntimeEmail(
            nodeID: fixture.clientNodeID,
            message: outboundMessage()
        )

        guard case let .success(sentMessage) = result else {
            return XCTFail("Expected delivery to continue at receipt capacity, got \(result)")
        }
        let deliveryIdentity = try XCTUnwrap(sentMessage.deliveryIdentity)
        let targetConfiguration = try XCTUnwrap(
            fixture.state.runtimeEmailServerConfigurationsByNodeID[fixture.secondTargetNodeID]
        )
        let retainedReceipts = try XCTUnwrap(targetConfiguration.deliveryReceipts)
        XCTAssertEqual(targetConfiguration.accounts.first?.mailbox.count, 1)
        XCTAssertEqual(retainedReceipts.count, TopologyRuntimeEmailServerConfiguration.maximumDeliveryReceipts)
        XCTAssertEqual(retainedReceipts.first, originalReceipts[1])
        XCTAssertEqual(retainedReceipts.last?.identity, deliveryIdentity)
        XCTAssertNil(targetConfiguration.deliveryReceipt(identity: originalReceipts[0].identity))
        XCTAssertTrue(
            fixture.state.runtimeEmailServerProcessesByNodeID[fixture.secondTargetNodeID]?.logs.contains {
                $0.message == "SMTP duplicate delivery suppressed"
            } == true
        )

        let targetFileSystem = try XCTUnwrap(
            fixture.state.virtualFileSystemsByNodeID[fixture.secondTargetNodeID]
        )
        let persistedConfiguration = try TopologyRuntimeEmailStorage.decodeNativeServer(
            targetFileSystem.textFile(at: TopologyRuntimeEmailStorage.serverNativePath)
        )
        XCTAssertEqual(persistedConfiguration.deliveryReceipts, targetConfiguration.deliveryReceipts)
        XCTAssertEqual(persistedConfiguration.accounts.first?.mailbox.count, 1)
    }

    func testRuntimeEmailServerRetainedReceiptDedupesAndRejectsConflictingContent() throws {
        var fixture = try makeMXRelayFixture(mxExchangers: [])
        try configureDirectTargetDelivery(fixture: &fixture)
        try startEmailServer(nodeID: fixture.secondTargetNodeID, state: &fixture.state)
        let initialResult = fixture.state.sendRuntimeEmail(
            nodeID: fixture.clientNodeID,
            message: outboundMessage()
        )
        guard case let .success(acceptedMessage) = initialResult else {
            return XCTFail("Expected initial delivery to succeed, got \(initialResult)")
        }
        let acceptedIdentity = try XCTUnwrap(acceptedMessage.deliveryIdentity)
        let acceptedReceipt = try XCTUnwrap(
            fixture.state.runtimeEmailServerConfigurationsByNodeID[fixture.secondTargetNodeID]?
                .deliveryReceipt(identity: acceptedIdentity)
        )
        XCTAssertTrue(fixture.state.stopRuntimeEmailServer(nodeID: fixture.secondTargetNodeID))
        var receipts = Array(deliveryReceiptsAtCapacity().dropLast())
        receipts.append(acceptedReceipt)
        fixture.state.runtimeEmailServerConfigurationsByNodeID[fixture.secondTargetNodeID]?
            .deliveryReceipts = receipts
        try startEmailServer(nodeID: fixture.secondTargetNodeID, state: &fixture.state)

        fixture.state.runtimeEmailClientConfigurationsByNodeID[fixture.clientNodeID]?.sent = []
        let duplicateResult = fixture.state.sendRuntimeEmail(
            nodeID: fixture.clientNodeID,
            message: acceptedMessage
        )
        guard case .success = duplicateResult else {
            return XCTFail("Expected retained delivery identity to dedupe, got \(duplicateResult)")
        }
        fixture.state.runtimeEmailClientConfigurationsByNodeID[fixture.clientNodeID]?.sent = []
        var conflictingMessage = acceptedMessage
        conflictingMessage.body += " Conflicting content."
        let conflictResult = fixture.state.sendRuntimeEmail(
            nodeID: fixture.clientNodeID,
            message: conflictingMessage
        )

        XCTAssertEqual(
            conflictResult,
            .failure(.protocolError("554 Delivery identity conflicts with previously accepted content"))
        )
        let targetConfiguration = try XCTUnwrap(
            fixture.state.runtimeEmailServerConfigurationsByNodeID[fixture.secondTargetNodeID]
        )
        XCTAssertEqual(targetConfiguration.accounts.first?.mailbox.count, 1)
        XCTAssertEqual(targetConfiguration.deliveryReceipts, receipts)
        XCTAssertTrue(
            fixture.state.runtimeEmailServerProcessesByNodeID[fixture.secondTargetNodeID]?.logs.contains {
                $0.message == "SMTP duplicate delivery suppressed"
            } == true
        )
        XCTAssertTrue(
            fixture.state.runtimeEmailServerProcessesByNodeID[fixture.secondTargetNodeID]?.logs.contains {
                $0.message == "SMTP delivery identity conflict"
            } == true
        )
    }

    func testRuntimeEmailRelayPreservesJavaMXFileOrder() throws {
        var fixture = try makeMXRelayFixture(
            mxExchangers: [
                (hostname: "b-mail.recipient.test", address: "10.0.0.40"),
                (hostname: "a-mail.recipient.test", address: "10.0.0.30"),
            ]
        )
        try startEmailServer(nodeID: fixture.firstTargetNodeID, state: &fixture.state)
        try startEmailServer(nodeID: fixture.secondTargetNodeID, state: &fixture.state)
        let directMX = fixture.state.resolveRuntimeDNSQuestion(
            nodeID: fixture.relayNodeID,
            hostname: "recipient.test",
            recordType: .mailExchange
        )
        guard case .success = directMX else {
            return XCTFail("Fixture MX resolution failed: \(directMX); DNS=\(fixture.state.runtimeDNSServerConfigurationsByNodeID)")
        }

        let result = fixture.state.sendRuntimeEmail(
            nodeID: fixture.clientNodeID,
            message: outboundMessage()
        )

        guard case .success = result else {
            XCTFail("Expected MX relay success, got \(result); relayLogs=\(fixture.state.runtimeEmailServerProcessesByNodeID[fixture.relayNodeID]?.logs.map(\.message) ?? [])")
            return
        }
        XCTAssertEqual(
            fixture.state.runtimeEmailServerConfigurationsByNodeID[fixture.firstTargetNodeID]?
                .accounts.first?.mailbox.count,
            0
        )
        XCTAssertEqual(
            fixture.state.runtimeEmailServerConfigurationsByNodeID[fixture.secondTargetNodeID]?
                .accounts.first?.mailbox.count,
            1
        )
        XCTAssertTrue(
            fixture.state.runtimeEmailServerProcessesByNodeID[fixture.relayNodeID]?.logs.contains {
                $0.message.contains("Remote delivery succeeded")
                    && $0.message.contains("order=0")
                    && $0.message.contains("exchange=b-mail.recipient.test")
                    && $0.message.contains("address=10.0.0.40")
            } == true
        )
    }

    func testRuntimeEmailRelayRetriesLostFinalDataResponseWithoutAppendingDuplicate() throws {
        var fixture = try makeMXRelayFixture(
            mxExchangers: [
                (hostname: "mail.recipient.test", address: "10.0.0.40"),
            ]
        )
        try startEmailServer(nodeID: fixture.secondTargetNodeID, state: &fixture.state)
        fixture.state.runtimeEmailServerProcessesByNodeID[fixture.secondTargetNodeID]?
            .testingSMTPFinalDataResponsesToDrop = 1

        let result = fixture.state.sendRuntimeEmail(
            nodeID: fixture.clientNodeID,
            message: outboundMessage()
        )

        guard case let .success(sentMessage) = result else {
            return XCTFail("Expected the idempotent relay retry to succeed, got \(result)")
        }
        let deliveryIdentity = try XCTUnwrap(sentMessage.deliveryIdentity)
        let targetConfiguration = try XCTUnwrap(
            fixture.state.runtimeEmailServerConfigurationsByNodeID[fixture.secondTargetNodeID]
        )
        XCTAssertEqual(targetConfiguration.accounts.first?.mailbox.count, 1)
        XCTAssertEqual(targetConfiguration.accounts.first?.mailbox.first?.deliveryIdentity, deliveryIdentity)
        XCTAssertEqual(targetConfiguration.deliveryReceipts?.map(\.identity), [deliveryIdentity])
        XCTAssertTrue(
            fixture.state.runtimeEmailServerProcessesByNodeID[fixture.secondTargetNodeID]?.logs.contains {
                $0.message == "SMTP duplicate delivery suppressed"
            } == true
        )
        XCTAssertTrue(
            fixture.state.runtimeEmailServerProcessesByNodeID[fixture.relayNodeID]?.logs.contains {
                $0.message.contains("Remote delivery succeeded")
                    && $0.message.contains("idempotentRetries=1")
                    && $0.message.contains("action=idempotent-retry-same-endpoint")
            } == true
        )

        let targetFileSystem = try XCTUnwrap(
            fixture.state.virtualFileSystemsByNodeID[fixture.secondTargetNodeID]
        )
        let persistedConfiguration = try TopologyRuntimeEmailStorage.decodeNativeServer(
            targetFileSystem.textFile(at: TopologyRuntimeEmailStorage.serverNativePath)
        )
        XCTAssertEqual(persistedConfiguration.accounts.first?.mailbox.count, 1)
        XCTAssertEqual(persistedConfiguration.deliveryReceipts?.map(\.identity), [deliveryIdentity])
    }

    func testRuntimeEmailRelayDeliversGenuineDistinctMessagesWithIdenticalContent() throws {
        var fixture = try makeMXRelayFixture(
            mxExchangers: [
                (hostname: "mail.recipient.test", address: "10.0.0.40"),
            ]
        )
        try startEmailServer(nodeID: fixture.secondTargetNodeID, state: &fixture.state)

        let firstResult = fixture.state.sendRuntimeEmail(
            nodeID: fixture.clientNodeID,
            message: outboundMessage()
        )
        let secondResult = fixture.state.sendRuntimeEmail(
            nodeID: fixture.clientNodeID,
            message: outboundMessage()
        )

        guard case let .success(firstSentMessage) = firstResult,
              case let .success(secondSentMessage) = secondResult
        else {
            return XCTFail("Expected both distinct sends to succeed: first=\(firstResult), second=\(secondResult)")
        }
        let firstIdentity = try XCTUnwrap(firstSentMessage.deliveryIdentity)
        let secondIdentity = try XCTUnwrap(secondSentMessage.deliveryIdentity)
        XCTAssertNotEqual(firstSentMessage.id, secondSentMessage.id)
        XCTAssertNotEqual(firstIdentity, secondIdentity)

        let targetConfiguration = try XCTUnwrap(
            fixture.state.runtimeEmailServerConfigurationsByNodeID[fixture.secondTargetNodeID]
        )
        XCTAssertEqual(targetConfiguration.accounts.first?.mailbox.count, 2)
        XCTAssertEqual(
            Set(targetConfiguration.accounts.first?.mailbox.compactMap(\.deliveryIdentity) ?? []),
            Set([firstIdentity, secondIdentity])
        )
        XCTAssertEqual(
            Set(targetConfiguration.deliveryReceipts?.map(\.identity) ?? []),
            Set([firstIdentity, secondIdentity])
        )
    }

    func testRuntimeEmailRelayFallsBackAcrossMXExchangersAndRecordsAttemptDiagnostics() throws {
        var fixture = try makeMXRelayFixture(
            mxExchangers: [
                (hostname: "a-unavailable.recipient.test", address: "10.0.0.30"),
                (hostname: "b-mail.recipient.test", address: "10.0.0.40"),
            ]
        )
        try startEmailServer(nodeID: fixture.secondTargetNodeID, state: &fixture.state)

        let result = fixture.state.sendRuntimeEmail(
            nodeID: fixture.clientNodeID,
            message: outboundMessage()
        )

        guard case .success = result else {
            XCTFail("Expected MX fallback success, got \(result); relayLogs=\(fixture.state.runtimeEmailServerProcessesByNodeID[fixture.relayNodeID]?.logs.map(\.message) ?? [])")
            return
        }
        XCTAssertEqual(
            fixture.state.runtimeEmailServerConfigurationsByNodeID[fixture.secondTargetNodeID]?
                .accounts.first?.mailbox.count,
            1
        )
        let successLog = try XCTUnwrap(
            fixture.state.runtimeEmailServerProcessesByNodeID[fixture.relayNodeID]?.logs.last {
                $0.message.contains("Remote delivery succeeded")
            }
        )
        XCTAssertTrue(successLog.message.contains("exchange=b-mail.recipient.test"))
        XCTAssertTrue(successLog.message.contains("order=1"))
        XCTAssertTrue(successLog.message.contains("exchange=a-unavailable.recipient.test"))
        XCTAssertTrue(successLog.message.contains("failure="))
        XCTAssertTrue(successLog.message.contains("10.0.0.30"))
    }

    func testRuntimeEmailRelayRequiresMXAndReportsDeterministicDNSFailure() throws {
        var fixture = try makeMXRelayFixture(
            mxExchangers: [],
            directDomainAddress: "10.0.0.40"
        )
        try startEmailServer(nodeID: fixture.secondTargetNodeID, state: &fixture.state)

        let result = fixture.state.sendRuntimeEmail(
            nodeID: fixture.clientNodeID,
            message: outboundMessage()
        )

        guard case let .failure(error) = result else {
            return XCTFail("Expected missing-MX delivery failure, got \(result)")
        }
        XCTAssertEqual(
            error,
            .protocolError("451 Requested action aborted: relay unavailable")
        )
        XCTAssertEqual(
            fixture.state.runtimeEmailServerConfigurationsByNodeID[fixture.secondTargetNodeID]?
                .accounts.first?.mailbox.count,
            0
        )
        let failureLog = try XCTUnwrap(
            fixture.state.runtimeEmailServerProcessesByNodeID[fixture.relayNodeID]?.logs.last {
                $0.message.contains("Remote delivery failed")
            }
        )
        XCTAssertTrue(failureLog.message.contains("DNS failed: MX recipient.test"))
        XCTAssertTrue(failureLog.message.contains("no-data(name=recipient.test,type=MX"))
        XCTAssertTrue(failureLog.message.contains("consulted=10.0.0.53"))
    }

    func testSentDeletionDoesNotDeleteMatchingInboxSelection() throws {
        let inbox = message(id: 10, subject: "Inbox")
        let sent = message(id: 11, subject: "Sent", isSent: true)
        let configuration = configuration(inbox: [inbox], sent: [sent])

        let result = try TopologyEmailActions.deletingMessage(
            withID: 11,
            from: .sent,
            configuration: configuration
        )

        XCTAssertEqual(result.deletedMessages, [sent])
        XCTAssertEqual(result.configuration.inbox, [inbox])
        XCTAssertTrue(result.configuration.sent.isEmpty)
    }

    func testMissingDeletionIsAtomicAndReportsRequestedFolder() {
        let configuration = configuration(
            inbox: [message(id: 20, subject: "Inbox")],
            sent: [message(id: 21, subject: "Sent", isSent: true)]
        )

        XCTAssertThrowsError(
            try TopologyEmailActions.deletingMessages(
                withIDs: [20, 999],
                from: .inbox,
                configuration: configuration
            )
        ) { error in
            XCTAssertEqual(
                error as? TopologyRuntimeEmailActionError,
                .messageNotFound(folder: .inbox, id: 999)
            )
        }
        XCTAssertEqual(configuration.inbox.map(\.id), [20])
        XCTAssertEqual(configuration.sent.map(\.id), [21])
    }

    func testUnassignedDeletionIdentifierIsRejected() {
        let configuration = configuration(inbox: [message(id: 1, subject: "Inbox")])

        XCTAssertThrowsError(
            try TopologyEmailActions.deletingMessage(
                withID: TopologyRuntimeEmailMessage.unassignedID,
                from: .inbox,
                configuration: configuration
            )
        ) { error in
            XCTAssertEqual(
                error as? TopologyRuntimeEmailActionError,
                .invalidMessageIdentifier(TopologyRuntimeEmailMessage.unassignedID)
            )
        }
    }

    func testDeleteAllClearsOnlyRequestedFolder() {
        let inbox = [message(id: 31, subject: "Inbox")]
        let sent = [message(id: 32, subject: "Sent", isSent: true)]
        let configuration = configuration(inbox: inbox, sent: sent)

        let result = TopologyEmailActions.deletingAllMessages(
            from: .sent,
            configuration: configuration
        )

        XCTAssertEqual(result.deletedMessages, sent)
        XCTAssertEqual(result.configuration.inbox, inbox)
        XCTAssertTrue(result.configuration.sent.isEmpty)
    }

    private struct MXRelayFixture {
        var state: TopologyEditorState
        let clientNodeID: UUID
        let relayNodeID: UUID
        let firstTargetNodeID: UUID
        let secondTargetNodeID: UUID
    }

    private func makeMXRelayFixture(
        mxExchangers: [(hostname: String, address: String)],
        directDomainAddress: String? = nil
    ) throws -> MXRelayFixture {
        let clientNodeID = UUID(uuidString: "00000000-0000-0000-0000-00000000E101")!
        let relayNodeID = UUID(uuidString: "00000000-0000-0000-0000-00000000E102")!
        let dnsNodeID = UUID(uuidString: "00000000-0000-0000-0000-00000000E103")!
        let firstTargetNodeID = UUID(uuidString: "00000000-0000-0000-0000-00000000E104")!
        let secondTargetNodeID = UUID(uuidString: "00000000-0000-0000-0000-00000000E105")!
        let switchNodeID = UUID(uuidString: "00000000-0000-0000-0000-00000000E106")!
        let endpointIDs = [clientNodeID, relayNodeID, dnsNodeID, firstTargetNodeID, secondTargetNodeID]
        let endpoints = endpointIDs.enumerated().map { index, nodeID in
            TopologyNode(
                id: nodeID,
                kind: .pc,
                displayName: "Email endpoint \(index)",
                position: CGPoint(x: CGFloat(index * 120), y: 20)
            )
        }
        let networkSwitch = TopologyNode(
            id: switchNodeID,
            kind: .networkSwitch,
            displayName: "Email switch",
            position: CGPoint(x: 240, y: 160)
        )
        let links = try endpoints.enumerated().map { index, endpoint in
            TopologyLink(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", 0xE200 + index))!,
                sourceNodeID: endpoint.id,
                sourcePortID: try XCTUnwrap(endpoint.ports.first?.id),
                targetNodeID: networkSwitch.id,
                targetPortID: networkSwitch.ports[index].id
            )
        }

        var records: [TopologyDNSResourceRecord] = try mxExchangers.flatMap { exchanger in
            [
                try XCTUnwrap(TopologyDNSResourceRecord(
                    name: "recipient.test",
                    type: .mailExchange,
                    target: exchanger.hostname
                )),
                try XCTUnwrap(TopologyDNSResourceRecord(
                    name: exchanger.hostname,
                    type: .address,
                    target: exchanger.address
                )),
            ]
        }
        if let directDomainAddress {
            records.append(try XCTUnwrap(TopologyDNSResourceRecord(
                name: "recipient.test",
                type: .address,
                target: directDomainAddress
            )))
        }

        var state = TopologyEditorState()
        state.graph = TopologyGraph(nodes: endpoints + [networkSwitch], links: links)
        state.runtimeDeviceConfigurations = [
            clientNodeID: .init(
                ipAddress: "10.0.0.10",
                subnetMask: "255.255.255.0",
                dnsServer: "10.0.0.53"
            ),
            relayNodeID: .init(
                ipAddress: "10.0.0.20",
                subnetMask: "255.255.255.0",
                dnsServer: "10.0.0.53"
            ),
            dnsNodeID: .init(
                ipAddress: "10.0.0.53",
                subnetMask: "255.255.255.0",
                dnsServer: "10.0.0.53"
            ),
            firstTargetNodeID: .init(
                ipAddress: "10.0.0.30",
                subnetMask: "255.255.255.0",
                dnsServer: "10.0.0.53"
            ),
            secondTargetNodeID: .init(
                ipAddress: "10.0.0.40",
                subnetMask: "255.255.255.0",
                dnsServer: "10.0.0.53"
            ),
        ]
        state.runtimeDNSServerConfigurationsByNodeID[dnsNodeID] =
            TopologyRuntimeDNSServerConfiguration(typedRecords: records)
        state.runtimeEmailClientConfigurationsByNodeID[clientNodeID] =
            TopologyRuntimeEmailClientConfiguration(
                pop3Host: "10.0.0.20",
                smtpHost: "10.0.0.20",
                username: "alice",
                password: "secret",
                name: "Alice Sender",
                email: "alice@relay.test"
            )
        state.runtimeEmailServerConfigurationsByNodeID[relayNodeID] =
            TopologyRuntimeEmailServerConfiguration(
                domain: "relay.test",
                accounts: [
                    TopologyRuntimeEmailServerAccount(
                        username: "alice",
                        password: "secret",
                        name: "Alice Sender"
                    )
                ]
            )
        let targetConfiguration = TopologyRuntimeEmailServerConfiguration(
            domain: "recipient.test",
            accounts: [
                TopologyRuntimeEmailServerAccount(
                    username: "bob",
                    password: "secret",
                    name: "Bob Recipient"
                )
            ]
        )
        state.runtimeEmailServerConfigurationsByNodeID[firstTargetNodeID] = targetConfiguration
        state.runtimeEmailServerConfigurationsByNodeID[secondTargetNodeID] = targetConfiguration

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        state.runtimeInstalledProgramsByNodeID[dnsNodeID, default: []].insert(.dnsServer)
        state.runtimeActiveProgramByNodeID[dnsNodeID] = .dnsServer
        state.runtimeDNSServerConfigurationsByNodeID[dnsNodeID] =
            TopologyRuntimeDNSServerConfiguration(typedRecords: records)
        TopologyEditorReducer.reduce(state: &state, action: .runtimeDNSStart(nodeID: dnsNodeID))
        XCTAssertNotNil(state.runtimeDNSServerSocketIDByNodeID[dnsNodeID])
        XCTAssertTrue(state.networkRuntime.isDNSServerRunning(nodeID: dnsNodeID))
        try startEmailServer(nodeID: relayNodeID, state: &state)
        return MXRelayFixture(
            state: state,
            clientNodeID: clientNodeID,
            relayNodeID: relayNodeID,
            firstTargetNodeID: firstTargetNodeID,
            secondTargetNodeID: secondTargetNodeID
        )
    }

    private func configureDirectTargetDelivery(fixture: inout MXRelayFixture) throws {
        var clientConfiguration = try XCTUnwrap(
            fixture.state.runtimeEmailClientConfigurationsByNodeID[fixture.clientNodeID]
        )
        clientConfiguration.smtpHost = "10.0.0.40"
        fixture.state.runtimeEmailClientConfigurationsByNodeID[fixture.clientNodeID] = clientConfiguration
    }

    private func emailServerConfiguration(
        deliveryReceipts: [TopologyRuntimeEmailDeliveryReceipt]
    ) -> TopologyRuntimeEmailServerConfiguration {
        TopologyRuntimeEmailServerConfiguration(
            domain: "recipient.test",
            accounts: [
                TopologyRuntimeEmailServerAccount(
                    username: "bob",
                    password: "secret",
                    name: "Bob Recipient"
                )
            ],
            deliveryReceipts: deliveryReceipts
        )
    }

    private func deliveryReceiptsAtCapacity() -> [TopologyRuntimeEmailDeliveryReceipt] {
        (0..<TopologyRuntimeEmailServerConfiguration.maximumDeliveryReceipts).map(deliveryReceipt(index:))
    }

    private func deliveryReceipt(index: Int) -> TopologyRuntimeEmailDeliveryReceipt {
        TopologyRuntimeEmailDeliveryReceipt(
            identity: deliveryDigest(index: index + 1),
            contentSignature: deliveryDigest(
                index: TopologyRuntimeEmailServerConfiguration.maximumDeliveryReceipts + index + 1
            )
        )
    }

    private func deliveryDigest(index: Int) -> String {
        String(format: "%064llx", UInt64(index))
    }

    private func startEmailServer(nodeID: UUID, state: inout TopologyEditorState) throws {
        switch state.startRuntimeEmailServer(nodeID: nodeID) {
        case .success:
            break
        case .failure(let error):
            XCTFail("Failed to start email server \(nodeID): \(error.localizedDescription)")
            throw error
        }
    }

    private func outboundMessage() -> TopologyRuntimeEmailMessage {
        TopologyRuntimeEmailMessage(
            from: TopologyRuntimeEmailAddress(
                name: "Alice Sender",
                mailAddress: "alice@relay.test"
            ),
            to: [TopologyRuntimeEmailAddress(
                name: "Bob Recipient",
                mailAddress: "bob@recipient.test"
            )],
            subject: "MX routing",
            body: "Delivery must follow the recipient domain MX records."
        )
    }

    private func configuration(
        inbox: [TopologyRuntimeEmailMessage] = [],
        sent: [TopologyRuntimeEmailMessage] = [],
        drafts: [TopologyRuntimeEmailMessage] = []
    ) -> TopologyRuntimeEmailClientConfiguration {
        TopologyRuntimeEmailClientConfiguration(
            pop3Host: "mail.example.test",
            smtpHost: "mail.example.test",
            username: "morgan",
            password: "secret",
            name: "Morgan User",
            email: currentUser.mailAddress,
            inbox: inbox,
            sent: sent,
            drafts: drafts,
            nextMessageID: 100
        )
    }

    private func message(
        id: UInt64,
        from: TopologyRuntimeEmailAddress? = nil,
        to: [TopologyRuntimeEmailAddress]? = nil,
        cc: [TopologyRuntimeEmailAddress] = [],
        bcc: [TopologyRuntimeEmailAddress] = [],
        subject: String,
        body: String = "Body",
        isNew: Bool = false,
        isMarkedForDeletion: Bool = false,
        isSent: Bool = false
    ) -> TopologyRuntimeEmailMessage {
        TopologyRuntimeEmailMessage(
            id: id,
            from: from ?? address("Alice", "alice@example.test"),
            to: to ?? [currentUser],
            cc: cc,
            bcc: bcc,
            subject: subject,
            body: body,
            receivedAtMilliseconds: 1_000,
            isNew: isNew,
            isMarkedForDeletion: isMarkedForDeletion,
            isSent: isSent
        )
    }

    private func address(_ name: String, _ email: String) -> TopologyRuntimeEmailAddress {
        TopologyRuntimeEmailAddress(name: name, mailAddress: email)
    }
}
