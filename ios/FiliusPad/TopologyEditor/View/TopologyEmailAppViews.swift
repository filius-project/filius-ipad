import SwiftUI
import UIKit

struct TopologyRuntimeEmailClientView: View {
    struct AccountFields: Equatable {
        var name: String
        var emailAddress: String
        var username: String
        var password: String
        var smtpHost: String
        var smtpPort: String
        var pop3Host: String
        var pop3Port: String

        init(name: String = "", emailAddress: String = "", username: String = "", password: String = "", smtpHost: String = "", smtpPort: String = "25", pop3Host: String = "", pop3Port: String = "110") {
            self.name = name
            self.emailAddress = emailAddress
            self.username = username
            self.password = password
            self.smtpHost = smtpHost
            self.smtpPort = smtpPort
            self.pop3Host = pop3Host
            self.pop3Port = pop3Port
        }
    }

    struct ComposeFields: Equatable {
        var to: String
        var cc: String
        var bcc: String
        var subject: String
        var body: String

        init(to: String = "", cc: String = "", bcc: String = "", subject: String = "", body: String = "") {
            self.to = to
            self.cc = cc
            self.bcc = bcc
            self.subject = subject
            self.body = body
        }
    }

    struct StateFields {
        var statusLocalizationKey: String
        var detail: String?
        var canSend: Bool
        var canRetrieve: Bool

        init(statusLocalizationKey: String = "email.client.status.idle", detail: String? = nil, canSend: Bool = true, canRetrieve: Bool = true) {
            self.statusLocalizationKey = statusLocalizationKey
            self.detail = detail
            self.canSend = canSend
            self.canRetrieve = canRetrieve
        }
    }

    struct MessageFields: Identifiable {
        let id: String
        let sender: TopologyRuntimeEmailAddress
        let to: [TopologyRuntimeEmailAddress]
        let cc: [TopologyRuntimeEmailAddress]
        let bcc: [TopologyRuntimeEmailAddress]
        let subject: String
        let body: String
        let timestamp: String
    }

    struct LogFields: Identifiable {
        let id: String
        let timestamp: String
        let message: String
    }

    private enum SectionSelection: String, CaseIterable, Identifiable {
        case account, compose, inbox, sent, logs
        var id: String { rawValue }
        var localizationKey: String { "email.client.section.\(rawValue)" }
    }

    let configuration: TopologyRuntimeEmailClientConfiguration
    let state: TopologyRuntimeEmailClientState
    let configurationFields: (TopologyRuntimeEmailClientConfiguration) -> AccountFields
    let stateFields: (TopologyRuntimeEmailClientState) -> StateFields
    let inboxMessages: (TopologyRuntimeEmailClientState) -> [TopologyRuntimeEmailMessage]
    let sentMessages: (TopologyRuntimeEmailClientState) -> [TopologyRuntimeEmailMessage]
    let logs: (TopologyRuntimeEmailClientState) -> [TopologyRuntimeEmailLogEntry]
    let messageFields: (TopologyRuntimeEmailMessage) -> MessageFields
    let addressText: (TopologyRuntimeEmailAddress) -> String
    let logFields: (TopologyRuntimeEmailLogEntry) -> LogFields
    let onSaveConfiguration: (AccountFields) -> Void
    let onSend: (ComposeFields) -> Void
    let onRetrieve: () -> Void

    @State private var account: AccountFields
    @State private var compose: ComposeFields
    @State private var selectedSection: SectionSelection = .account

    init(
        configuration: TopologyRuntimeEmailClientConfiguration,
        state: TopologyRuntimeEmailClientState,
        configurationFields: @escaping (TopologyRuntimeEmailClientConfiguration) -> AccountFields,
        stateFields: @escaping (TopologyRuntimeEmailClientState) -> StateFields,
        inboxMessages: @escaping (TopologyRuntimeEmailClientState) -> [TopologyRuntimeEmailMessage],
        sentMessages: @escaping (TopologyRuntimeEmailClientState) -> [TopologyRuntimeEmailMessage],
        logs: @escaping (TopologyRuntimeEmailClientState) -> [TopologyRuntimeEmailLogEntry],
        messageFields: @escaping (TopologyRuntimeEmailMessage) -> MessageFields,
        addressText: @escaping (TopologyRuntimeEmailAddress) -> String,
        logFields: @escaping (TopologyRuntimeEmailLogEntry) -> LogFields,
        initialCompose: ComposeFields = ComposeFields(),
        onSaveConfiguration: @escaping (AccountFields) -> Void,
        onSend: @escaping (ComposeFields) -> Void,
        onRetrieve: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.state = state
        self.configurationFields = configurationFields
        self.stateFields = stateFields
        self.inboxMessages = inboxMessages
        self.sentMessages = sentMessages
        self.logs = logs
        self.messageFields = messageFields
        self.addressText = addressText
        self.logFields = logFields
        self.onSaveConfiguration = onSaveConfiguration
        self.onSend = onSend
        self.onRetrieve = onRetrieve
        _account = State(initialValue: configurationFields(configuration))
        _compose = State(initialValue: initialCompose)
    }

    var body: some View {
        Form {
            statusSection
            Section {
                Picker(FiliusLocalization.t("email.client.section.label"), selection: $selectedSection) {
                    ForEach(SectionSelection.allCases) { section in
                        Text(FiliusLocalization.t(section.localizationKey)).tag(section)
                    }
                }
                .pickerStyle(.menu)
                .frame(minHeight: 44)
                .accessibilityIdentifier("email.client.section")
            }
            selectedContent
        }
        .accessibilityIdentifier("email.client.view")
        .onChange(of: configurationFields(configuration)) { _, newValue in account = newValue }
    }

    private var currentState: StateFields { stateFields(state) }

    private var statusSection: some View {
        Section(FiliusLocalization.t("email.client.status.section")) {
            LabeledContent(FiliusLocalization.t("email.status.label"), value: FiliusLocalization.t(currentState.statusLocalizationKey))
                .accessibilityIdentifier("email.client.status")
            if let detail = currentState.detail, !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("email.client.status.detail")
            }
            Button(action: onRetrieve) {
                Label(FiliusLocalization.t("email.client.retrieve"), systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).frame(minHeight: 44)
            .disabled(!currentState.canRetrieve)
            .accessibilityIdentifier("email.client.retrieve")
        }
    }

    @ViewBuilder private var selectedContent: some View {
        switch selectedSection {
        case .account: accountSection
        case .compose: composeSection
        case .inbox: messageSection(titleKey: "email.client.inbox.title", emptyKey: "email.client.inbox.empty", messages: inboxMessages(state), identifier: "email.client.inbox")
        case .sent: messageSection(titleKey: "email.client.sent.title", emptyKey: "email.client.sent.empty", messages: sentMessages(state), identifier: "email.client.sent")
        case .logs: logSection
        }
    }

    private var accountSection: some View {
        Section(FiliusLocalization.t("email.client.account.title")) {
            emailField("email.client.account.name", text: $account.name, identifier: "email.client.account.name")
            emailField("email.client.account.address", text: $account.emailAddress, identifier: "email.client.account.address", keyboard: .emailAddress)
            emailField("email.client.account.username", text: $account.username, identifier: "email.client.account.username")
            VStack(alignment: .leading, spacing: 4) {
                Text(FiliusLocalization.t("email.client.account.password")).font(.caption).foregroundStyle(.secondary)
                SecureField(FiliusLocalization.t("email.client.account.password"), text: $account.password)
                    .textContentType(.password).textFieldStyle(.roundedBorder).frame(minHeight: 44)
                    .accessibilityIdentifier("email.client.account.password")
            }
            emailField("email.client.account.smtpHost", text: $account.smtpHost, identifier: "email.client.account.smtpHost")
            emailField("email.client.account.smtpPort", text: $account.smtpPort, identifier: "email.client.account.smtpPort", keyboard: .numberPad)
            emailField("email.client.account.pop3Host", text: $account.pop3Host, identifier: "email.client.account.pop3Host")
            emailField("email.client.account.pop3Port", text: $account.pop3Port, identifier: "email.client.account.pop3Port", keyboard: .numberPad)
            Button { onSaveConfiguration(account) } label: {
                Label(FiliusLocalization.t("email.client.account.save"), systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).frame(minHeight: 44)
            .accessibilityIdentifier("email.client.account.save")
        }
    }

    private var composeSection: some View {
        Section(FiliusLocalization.t("email.client.compose.title")) {
            emailField("email.client.compose.to", text: $compose.to, identifier: "email.client.compose.to", keyboard: .emailAddress)
            emailField("email.client.compose.cc", text: $compose.cc, identifier: "email.client.compose.cc", keyboard: .emailAddress)
            emailField("email.client.compose.bcc", text: $compose.bcc, identifier: "email.client.compose.bcc", keyboard: .emailAddress)
            emailField("email.client.compose.subject", text: $compose.subject, identifier: "email.client.compose.subject")
            VStack(alignment: .leading, spacing: 4) {
                Text(FiliusLocalization.t("email.client.compose.body")).font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $compose.body).frame(minHeight: 160)
                    .accessibilityLabel(FiliusLocalization.t("email.client.compose.body"))
                    .accessibilityIdentifier("email.client.compose.body")
            }
            Button { onSend(compose) } label: {
                Label(FiliusLocalization.t("email.client.compose.send"), systemImage: "paperplane").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).frame(minHeight: 44)
            .disabled(!currentState.canSend)
            .accessibilityIdentifier("email.client.compose.send")
        }
    }

    private func messageSection(titleKey: String, emptyKey: String, messages: [TopologyRuntimeEmailMessage], identifier: String) -> some View {
        let rows = messages.map(messageFields)
        return Section(FiliusLocalization.t(titleKey)) {
            if rows.isEmpty {
                Text(FiliusLocalization.t(emptyKey)).foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            messageAddressLine("email.message.from", addresses: [row.sender])
                            messageAddressLine("email.message.to", addresses: row.to)
                            if !row.cc.isEmpty { messageAddressLine("email.message.cc", addresses: row.cc) }
                            if !row.bcc.isEmpty { messageAddressLine("email.message.bcc", addresses: row.bcc) }
                            Divider()
                            Text(row.body.isEmpty ? FiliusLocalization.t("email.message.emptyBody") : row.body)
                                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.subject.isEmpty ? FiliusLocalization.t("email.message.noSubject") : row.subject).font(.headline)
                            Text(addressText(row.sender)).font(.caption).foregroundStyle(.secondary)
                            if !row.timestamp.isEmpty { Text(row.timestamp).font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("\(identifier).message.\(row.id)")
                }
            }
        }
    }

    private func messageAddressLine(_ key: String, addresses: [TopologyRuntimeEmailAddress]) -> some View {
        LabeledContent(FiliusLocalization.t(key), value: addresses.map(addressText).joined(separator: ", ")).font(.caption)
    }

    private var logSection: some View {
        let rows = logs(state).suffix(50).map(logFields)
        return Section(FiliusLocalization.t("email.logs.title")) {
            if rows.isEmpty {
                Text(FiliusLocalization.t("email.logs.empty")).foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        if !row.timestamp.isEmpty { Text(row.timestamp).font(.caption2).foregroundStyle(.secondary) }
                        Text(row.message).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    .accessibilityIdentifier("email.client.log.\(row.id)")
                }
            }
        }
    }

    private func emailField(_ key: String, text: Binding<String>, identifier: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(FiliusLocalization.t(key)).font(.caption).foregroundStyle(.secondary)
            TextField(FiliusLocalization.t(key), text: text)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(keyboard)
                .textFieldStyle(.roundedBorder).frame(minHeight: 44)
                .accessibilityIdentifier(identifier)
        }
    }
}

struct TopologyRuntimeEmailServerView: View {
    struct ConfigurationFields: Equatable {
        var domain: String
        var smtpPort: String
        var pop3Port: String

        init(domain: String = "", smtpPort: String = "25", pop3Port: String = "110") {
            self.domain = domain
            self.smtpPort = smtpPort
            self.pop3Port = pop3Port
        }
    }

    struct AccountDraft: Equatable {
        var username: String
        var password: String
        var firstName: String
        var lastName: String

        init(username: String = "", password: String = "", firstName: String = "", lastName: String = "") {
            self.username = username
            self.password = password
            self.firstName = firstName
            self.lastName = lastName
        }
    }

    struct AccountFields: Identifiable {
        let id: String
        let username: String
        let password: String
        let firstName: String
        let lastName: String
        let mailboxCount: Int
    }

    struct StateFields {
        var isRunning: Bool
        var statusLocalizationKey: String
        var detail: String?

        init(isRunning: Bool, statusLocalizationKey: String, detail: String? = nil) {
            self.isRunning = isRunning
            self.statusLocalizationKey = statusLocalizationKey
            self.detail = detail
        }
    }

    struct LogFields: Identifiable {
        let id: String
        let timestamp: String
        let message: String
    }

    private enum SectionSelection: String, CaseIterable, Identifiable {
        case configuration, accounts, logs
        var id: String { rawValue }
        var localizationKey: String { "email.server.section.\(rawValue)" }
    }

    let configuration: TopologyRuntimeEmailServerConfiguration
    let processState: TopologyRuntimeEmailServerProcessState
    let configurationFields: (TopologyRuntimeEmailServerConfiguration) -> ConfigurationFields
    let accounts: (TopologyRuntimeEmailServerConfiguration) -> [TopologyRuntimeEmailServerAccount]
    let accountFields: (TopologyRuntimeEmailServerAccount) -> AccountFields
    let stateFields: (TopologyRuntimeEmailServerProcessState) -> StateFields
    let logs: (TopologyRuntimeEmailServerProcessState) -> [TopologyRuntimeEmailLogEntry]
    let logFields: (TopologyRuntimeEmailLogEntry) -> LogFields
    let onSaveConfiguration: (ConfigurationFields) -> Void
    let onAddAccount: (AccountDraft) -> Void
    let onUpdateAccount: (String, AccountDraft) -> Void
    let onDeleteAccount: (String) -> Void
    let onMoveAccount: ((String, Int) -> Void)?
    let onStart: (ConfigurationFields) -> Void
    let onStop: () -> Void

    @State private var serverConfiguration: ConfigurationFields
    @State private var newAccount = AccountDraft()
    @State private var selectedSection: SectionSelection = .configuration

    init(
        configuration: TopologyRuntimeEmailServerConfiguration,
        processState: TopologyRuntimeEmailServerProcessState,
        configurationFields: @escaping (TopologyRuntimeEmailServerConfiguration) -> ConfigurationFields,
        accounts: @escaping (TopologyRuntimeEmailServerConfiguration) -> [TopologyRuntimeEmailServerAccount],
        accountFields: @escaping (TopologyRuntimeEmailServerAccount) -> AccountFields,
        stateFields: @escaping (TopologyRuntimeEmailServerProcessState) -> StateFields,
        logs: @escaping (TopologyRuntimeEmailServerProcessState) -> [TopologyRuntimeEmailLogEntry],
        logFields: @escaping (TopologyRuntimeEmailLogEntry) -> LogFields,
        onSaveConfiguration: @escaping (ConfigurationFields) -> Void,
        onAddAccount: @escaping (AccountDraft) -> Void,
        onUpdateAccount: @escaping (String, AccountDraft) -> Void,
        onDeleteAccount: @escaping (String) -> Void,
        onMoveAccount: ((String, Int) -> Void)? = nil,
        onStart: @escaping (ConfigurationFields) -> Void,
        onStop: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.processState = processState
        self.configurationFields = configurationFields
        self.accounts = accounts
        self.accountFields = accountFields
        self.stateFields = stateFields
        self.logs = logs
        self.logFields = logFields
        self.onSaveConfiguration = onSaveConfiguration
        self.onAddAccount = onAddAccount
        self.onUpdateAccount = onUpdateAccount
        self.onDeleteAccount = onDeleteAccount
        self.onMoveAccount = onMoveAccount
        self.onStart = onStart
        self.onStop = onStop
        _serverConfiguration = State(initialValue: configurationFields(configuration))
    }

    var body: some View {
        Form {
            lifecycleSection
            Section {
                Picker(FiliusLocalization.t("email.server.section.label"), selection: $selectedSection) {
                    ForEach(SectionSelection.allCases) { section in
                        Text(FiliusLocalization.t(section.localizationKey)).tag(section)
                    }
                }
                .pickerStyle(.menu).frame(minHeight: 44)
                .accessibilityIdentifier("email.server.section")
            }
            selectedContent
        }
        .accessibilityIdentifier("email.server.view")
        .onChange(of: configurationFields(configuration)) { _, newValue in serverConfiguration = newValue }
    }

    private var currentState: StateFields { stateFields(processState) }

    private var lifecycleSection: some View {
        Section(FiliusLocalization.t("email.server.status.section")) {
            LabeledContent(FiliusLocalization.t("email.status.label"), value: FiliusLocalization.t(currentState.statusLocalizationKey))
                .accessibilityIdentifier("email.server.status")
            if let detail = currentState.detail, !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("email.server.status.detail")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { lifecycleButtons }
                VStack(spacing: 8) { lifecycleButtons }
            }
        }
    }

    @ViewBuilder private var lifecycleButtons: some View {
        Button { onStart(serverConfiguration) } label: {
            Label(FiliusLocalization.t("email.server.start"), systemImage: "play.fill").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).controlSize(.large).frame(minHeight: 44)
        .disabled(currentState.isRunning).accessibilityIdentifier("email.server.start")
        Button(action: onStop) {
            Label(FiliusLocalization.t("email.server.stop"), systemImage: "stop.fill").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered).controlSize(.large).frame(minHeight: 44)
        .disabled(!currentState.isRunning).accessibilityIdentifier("email.server.stop")
    }

    @ViewBuilder private var selectedContent: some View {
        switch selectedSection {
        case .configuration: configurationSection
        case .accounts: accountsSection
        case .logs: logSection
        }
    }

    private var configurationSection: some View {
        Section(FiliusLocalization.t("email.server.configuration.title")) {
            serverField("email.server.domain", text: $serverConfiguration.domain, identifier: "email.server.domain")
            serverField("email.server.smtpPort", text: $serverConfiguration.smtpPort, identifier: "email.server.smtpPort", keyboard: .numberPad)
            serverField("email.server.pop3Port", text: $serverConfiguration.pop3Port, identifier: "email.server.pop3Port", keyboard: .numberPad)
            Button { onSaveConfiguration(serverConfiguration) } label: {
                Label(FiliusLocalization.t("email.server.configuration.save"), systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).frame(minHeight: 44)
            .disabled(currentState.isRunning)
            .accessibilityIdentifier("email.server.configuration.save")
        }
    }

    private var accountsSection: some View {
        let rows = accounts(configuration).enumerated().map { IndexedAccount(index: $0.offset, fields: accountFields($0.element)) }
        return Group {
            Section(FiliusLocalization.t("email.server.account.add.title")) {
                accountEditorFields(draft: $newAccount, identifierPrefix: "email.server.account.add")
                Button {
                    onAddAccount(newAccount)
                    newAccount = AccountDraft()
                } label: {
                    Label(FiliusLocalization.t("email.server.account.add"), systemImage: "plus.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).frame(minHeight: 44)
                .accessibilityIdentifier("email.server.account.add")
            }
            Section(FiliusLocalization.t("email.server.accounts.title")) {
                if rows.isEmpty {
                    Text(FiliusLocalization.t("email.server.accounts.empty")).foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { row in
                        EmailServerAccountEditor(
                            fields: row.fields,
                            index: row.index,
                            accountCount: rows.count,
                            onUpdate: onUpdateAccount,
                            onDelete: onDeleteAccount,
                            onMove: onMoveAccount
                        )
                    }
                }
            }
        }
    }

    private var logSection: some View {
        let rows = logs(processState).suffix(50).map(logFields)
        return Section(FiliusLocalization.t("email.logs.title")) {
            if rows.isEmpty {
                Text(FiliusLocalization.t("email.logs.empty")).foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        if !row.timestamp.isEmpty { Text(row.timestamp).font(.caption2).foregroundStyle(.secondary) }
                        Text(row.message).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    .accessibilityIdentifier("email.server.log.\(row.id)")
                }
            }
        }
    }

    private func accountEditorFields(draft: Binding<AccountDraft>, identifierPrefix: String) -> some View {
        Group {
            serverField("email.server.account.username", text: draft.username, identifier: "\(identifierPrefix).username")
            VStack(alignment: .leading, spacing: 4) {
                Text(FiliusLocalization.t("email.server.account.password")).font(.caption).foregroundStyle(.secondary)
                SecureField(FiliusLocalization.t("email.server.account.password"), text: draft.password)
                    .textContentType(.password).textFieldStyle(.roundedBorder).frame(minHeight: 44)
                    .accessibilityIdentifier("\(identifierPrefix).password")
            }
            serverField("email.server.account.firstName", text: draft.firstName, identifier: "\(identifierPrefix).firstName")
            serverField("email.server.account.lastName", text: draft.lastName, identifier: "\(identifierPrefix).lastName")
        }
    }

    private func serverField(_ key: String, text: Binding<String>, identifier: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(FiliusLocalization.t(key)).font(.caption).foregroundStyle(.secondary)
            TextField(FiliusLocalization.t(key), text: text)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(keyboard)
                .textFieldStyle(.roundedBorder).frame(minHeight: 44)
                .accessibilityIdentifier(identifier)
        }
    }

    private struct IndexedAccount: Identifiable {
        let index: Int
        let fields: AccountFields
        var id: String { fields.id }
    }
}

private struct EmailServerAccountEditor: View {
    let fields: TopologyRuntimeEmailServerView.AccountFields
    let index: Int
    let accountCount: Int
    let onUpdate: (String, TopologyRuntimeEmailServerView.AccountDraft) -> Void
    let onDelete: (String) -> Void
    let onMove: ((String, Int) -> Void)?

    @State private var draft: TopologyRuntimeEmailServerView.AccountDraft

    init(
        fields: TopologyRuntimeEmailServerView.AccountFields,
        index: Int,
        accountCount: Int,
        onUpdate: @escaping (String, TopologyRuntimeEmailServerView.AccountDraft) -> Void,
        onDelete: @escaping (String) -> Void,
        onMove: ((String, Int) -> Void)?
    ) {
        self.fields = fields
        self.index = index
        self.accountCount = accountCount
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.onMove = onMove
        _draft = State(initialValue: .init(username: fields.username, password: fields.password, firstName: fields.firstName, lastName: fields.lastName))
    }

    var body: some View {
        DisclosureGroup {
            field("email.server.account.username", text: $draft.username, identifier: "email.server.account.\(fields.id).username")
            VStack(alignment: .leading, spacing: 4) {
                Text(FiliusLocalization.t("email.server.account.password")).font(.caption).foregroundStyle(.secondary)
                SecureField(FiliusLocalization.t("email.server.account.password"), text: $draft.password)
                    .textContentType(.password).textFieldStyle(.roundedBorder).frame(minHeight: 44)
                    .accessibilityIdentifier("email.server.account.\(fields.id).password")
            }
            field("email.server.account.firstName", text: $draft.firstName, identifier: "email.server.account.\(fields.id).firstName")
            field("email.server.account.lastName", text: $draft.lastName, identifier: "email.server.account.\(fields.id).lastName")
            LabeledContent(FiliusLocalization.t("email.server.account.mailbox"), value: "\(fields.mailboxCount)")
                .accessibilityIdentifier("email.server.account.\(fields.id).mailboxCount")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actionButtons }
                VStack(spacing: 8) { actionButtons }
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(fields.username.isEmpty ? FiliusLocalization.t("email.server.account.untitled") : fields.username).font(.headline)
                Text(FiliusLocalization.plural("email.server.mailbox.count", count: fields.mailboxCount))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("email.server.account.\(fields.id)")
        .onChange(of: fields.username) { _, _ in
            draft = .init(username: fields.username, password: fields.password, firstName: fields.firstName, lastName: fields.lastName)
        }
    }

    @ViewBuilder private var actionButtons: some View {
        Button { onUpdate(fields.id, draft) } label: {
            Label(FiliusLocalization.t("email.server.account.save"), systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).controlSize(.large).frame(minHeight: 44)
        .accessibilityIdentifier("email.server.account.\(fields.id).save")

        if let onMove {
            Button { onMove(fields.id, index - 1) } label: {
                Label(FiliusLocalization.t("email.server.account.moveUp"), systemImage: "arrow.up").labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered).controlSize(.large).frame(minWidth: 44, minHeight: 44).disabled(index == 0)
            .accessibilityLabel(FiliusLocalization.t("email.server.account.moveUp"))
            .accessibilityIdentifier("email.server.account.\(fields.id).moveUp")
            Button { onMove(fields.id, index + 1) } label: {
                Label(FiliusLocalization.t("email.server.account.moveDown"), systemImage: "arrow.down").labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered).controlSize(.large).frame(minWidth: 44, minHeight: 44).disabled(index + 1 >= accountCount)
            .accessibilityLabel(FiliusLocalization.t("email.server.account.moveDown"))
            .accessibilityIdentifier("email.server.account.\(fields.id).moveDown")
        }

        Button(role: .destructive) { onDelete(fields.id) } label: {
            Label(FiliusLocalization.t("email.server.account.delete"), systemImage: "trash").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered).controlSize(.large).frame(minHeight: 44)
        .accessibilityIdentifier("email.server.account.\(fields.id).delete")
    }

    private func field(_ key: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(FiliusLocalization.t(key)).font(.caption).foregroundStyle(.secondary)
            TextField(FiliusLocalization.t(key), text: text)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .textFieldStyle(.roundedBorder).frame(minHeight: 44)
                .accessibilityIdentifier(identifier)
        }
    }
}
