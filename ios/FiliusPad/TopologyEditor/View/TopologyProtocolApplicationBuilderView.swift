import SwiftUI

struct TopologyProtocolApplicationBuilderView: View {
    let definitions: [TopologyProtocolApplicationDefinition]
    let onCreate: (TopologyProtocolApplicationDefinition) -> Void
    let onUpdate: (TopologyProtocolApplicationDefinition) -> Void
    let onDelete: (UUID) -> Void
    let onClose: () -> Void

    @State private var stage = 0
    @State private var editingExisting = false
    @State private var definitionID = UUID()
    @State private var name = ""
    @State private var role: TopologyProtocolApplicationRole = .client
    @State private var transport: TopologyRuntimeTransportProtocol = .tcp
    @State private var port = "55555"
    @State private var templates: [TopologyProtocolApplicationMessageTemplate] = []
    @State private var rules: [TopologyProtocolApplicationResponseRule] = []
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case 0: catalogStage
                case 1: configurationStage
                default: behaviorStage
                }
            }
            .navigationTitle(FiliusLocalization.t("protocol.builder.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { builderToolbar }
        }
        .accessibilityIdentifier("protocol.builder.sheet")
    }

    private var catalogStage: some View {
        List {
            Section {
                Button {
                    beginNewDefinition()
                } label: {
                    Label(FiliusLocalization.t("protocol.builder.new"), systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("protocol.builder.catalog.new")
            }

            Section(FiliusLocalization.t("protocol.builder.catalog")) {
                if definitions.isEmpty {
                    Text(FiliusLocalization.t("protocol.builder.empty"))
                        .foregroundStyle(.secondary)
                }
                ForEach(definitions) { definition in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(definition.name).font(.headline)
                                Text(FiliusLocalization.t(
                                    "protocol.builder.summary",
                                    localizedRole(definition.role),
                                    definition.transport.displayName,
                                    Int(definition.port)
                                ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button(FiliusLocalization.t("protocol.builder.edit")) {
                                beginEditing(definition)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("protocol.builder.catalog.edit.\(definition.id.uuidString)")
                        }
                        Button(FiliusLocalization.t("protocol.builder.delete"), role: .destructive) {
                            onDelete(definition.id)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .accessibilityIdentifier("protocol.builder.catalog.delete.\(definition.id.uuidString)")
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .accessibilityIdentifier("protocol.builder.stage.catalog")
    }

    private var configurationStage: some View {
        Form {
            Section(FiliusLocalization.t("protocol.builder.stage.configuration")) {
                TextField(FiliusLocalization.t("protocol.builder.name"), text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("protocol.builder.name")
                Picker(FiliusLocalization.t("protocol.builder.role"), selection: $role) {
                    Text(FiliusLocalization.t("protocol.role.client")).tag(TopologyProtocolApplicationRole.client)
                    Text(FiliusLocalization.t("protocol.role.server")).tag(TopologyProtocolApplicationRole.server)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("protocol.builder.role")
                Picker(FiliusLocalization.t("protocol.builder.transport"), selection: $transport) {
                    ForEach(TopologyRuntimeTransportProtocol.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("protocol.builder.transport")
                TextField(FiliusLocalization.t("protocol.builder.port"), text: $port)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("protocol.builder.port")
            }
            Section {
                Text(FiliusLocalization.t("protocol.builder.constrained.detail"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            validationSection
        }
        .accessibilityIdentifier("protocol.builder.stage.configuration")
    }

    @ViewBuilder
    private var behaviorStage: some View {
        Form {
            if role == .client {
                clientTemplatesSection
            } else {
                serverRulesSection
            }
            validationSection
        }
        .accessibilityIdentifier("protocol.builder.stage.behavior")
    }

    private var clientTemplatesSection: some View {
        Section(FiliusLocalization.t("protocol.builder.messages")) {
            ForEach(templates) { template in
                VStack(alignment: .leading, spacing: 6) {
                    TextField(
                        FiliusLocalization.t("protocol.builder.message.name"),
                        text: bindingForTemplate(id: template.id, keyPath: \.name)
                    )
                    .accessibilityIdentifier("protocol.builder.message.\(template.id.uuidString).name")
                    TextField(
                        FiliusLocalization.t("protocol.builder.message.body"),
                        text: bindingForTemplate(id: template.id, keyPath: \.message),
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                    .accessibilityIdentifier("protocol.builder.message.\(template.id.uuidString).body")
                    Button(FiliusLocalization.t("protocol.builder.remove"), role: .destructive) {
                        templates.removeAll { $0.id == template.id }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .accessibilityIdentifier("protocol.builder.message.\(template.id.uuidString).remove")
                }
                .accessibilityIdentifier("protocol.builder.message.\(template.id.uuidString)")
            }
            Button(FiliusLocalization.t("protocol.builder.message.add")) {
                guard templates.count < TopologyProtocolApplicationLimits.maximumTemplatesPerClient else { return }
                templates.append(.init(name: FiliusLocalization.t("protocol.builder.message.defaultName", templates.count + 1), message: ""))
            }
            .accessibilityIdentifier("protocol.builder.message.add")
        }
    }

    private var serverRulesSection: some View {
        Section(FiliusLocalization.t("protocol.builder.rules")) {
            ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                VStack(alignment: .leading, spacing: 6) {
                    Text(FiliusLocalization.t("protocol.builder.rule.number", index + 1))
                        .font(.caption.weight(.semibold))
                    TextField(
                        FiliusLocalization.t("protocol.builder.rule.request"),
                        text: bindingForRule(id: rule.id, keyPath: \.request),
                        axis: .vertical
                    )
                    TextField(
                        FiliusLocalization.t("protocol.builder.rule.response"),
                        text: bindingForRule(id: rule.id, keyPath: \.response),
                        axis: .vertical
                    )
                    HStack {
                        Button(FiliusLocalization.t("protocol.builder.rule.up")) { moveRule(id: rule.id, delta: -1) }
                            .disabled(index == 0)
                        Button(FiliusLocalization.t("protocol.builder.rule.down")) { moveRule(id: rule.id, delta: 1) }
                            .disabled(index + 1 == rules.count)
                        Spacer()
                        Button(FiliusLocalization.t("protocol.builder.remove"), role: .destructive) {
                            rules.removeAll { $0.id == rule.id }
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            Button(FiliusLocalization.t("protocol.builder.rule.add")) {
                guard rules.count < TopologyProtocolApplicationLimits.maximumRulesPerServer else { return }
                rules.append(.init(request: "", response: ""))
            }
            .accessibilityIdentifier("protocol.builder.rule.add")
        }
    }

    @ViewBuilder
    private var validationSection: some View {
        if let validationMessage {
            Section {
                Text(validationMessage)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("protocol.builder.validation")
            }
        }
    }

    @ToolbarContentBuilder
    private var builderToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if stage == 0 {
                Button(FiliusLocalization.t("protocol.builder.close"), action: onClose)
            } else {
                Button(FiliusLocalization.t("protocol.builder.back")) {
                    validationMessage = nil
                    stage -= 1
                }
            }
        }
        if stage > 0 {
            ToolbarItem(placement: .confirmationAction) {
                Button(stage == 2 ? FiliusLocalization.t("protocol.builder.save") : FiliusLocalization.t("protocol.builder.next")) {
                    advanceOrSave()
                }
                .accessibilityIdentifier(stage == 2 ? "protocol.builder.save" : "protocol.builder.next")
            }
        }
    }

    private func localizedRole(_ role: TopologyProtocolApplicationRole) -> String {
        FiliusLocalization.t(role == .client ? "protocol.role.client" : "protocol.role.server")
    }

    private func bindingForTemplate(
        id: UUID,
        keyPath: WritableKeyPath<TopologyProtocolApplicationMessageTemplate, String>
    ) -> Binding<String> {
        Binding(
            get: { templates.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" },
            set: { value in
                guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
                templates[index][keyPath: keyPath] = value
            }
        )
    }

    private func bindingForRule(
        id: UUID,
        keyPath: WritableKeyPath<TopologyProtocolApplicationResponseRule, String>
    ) -> Binding<String> {
        Binding(
            get: { rules.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" },
            set: { value in
                guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
                rules[index][keyPath: keyPath] = value
            }
        )
    }

    private func moveRule(id: UUID, delta: Int) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + delta
        guard rules.indices.contains(destination) else { return }
        rules.swapAt(index, destination)
    }

    private func beginNewDefinition() {
        editingExisting = false
        definitionID = UUID()
        name = ""
        role = .client
        transport = .tcp
        port = "55555"
        templates = [.init(name: FiliusLocalization.t("protocol.builder.message.defaultName", 1), message: "")]
        rules = []
        validationMessage = nil
        stage = 1
    }

    private func beginEditing(_ definition: TopologyProtocolApplicationDefinition) {
        editingExisting = true
        definitionID = definition.id
        name = definition.name
        role = definition.role
        transport = definition.transport
        port = String(definition.port)
        templates = definition.clientMessageTemplates
        rules = definition.responseRules
        validationMessage = nil
        stage = 1
    }

    private func advanceOrSave() {
        validationMessage = nil
        if stage == 1 {
            guard normalizedHeaderIsValid else {
                validationMessage = FiliusLocalization.t("protocol.builder.validation.header")
                return
            }
            if role == .client {
                if templates.isEmpty {
                    templates = [.init(name: FiliusLocalization.t("protocol.builder.message.defaultName", 1), message: "")]
                }
                rules = []
            } else {
                if rules.isEmpty { rules = [.init(request: "", response: "")] }
                templates = []
            }
            stage = 2
            return
        }
        saveDefinition()
    }

    private var normalizedHeaderIsValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && trimmed.lengthOfBytes(using: .utf8) <= TopologyProtocolApplicationLimits.maximumNameBytes
            && UInt16(port) != nil
            && UInt16(port) != 0
    }

    private func saveDefinition() {
        guard let normalizedPort = UInt16(port), normalizedPort > 0 else {
            validationMessage = FiliusLocalization.t("protocol.builder.validation.header")
            return
        }
        let definition = TopologyProtocolApplicationDefinition(
            id: definitionID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            role: role,
            transport: transport,
            port: normalizedPort,
            clientMessageTemplates: role == .client ? templates : [],
            responseRules: role == .server ? rules : []
        )
        var projectDefinitions = definitions.filter { $0.id != definition.id }
        projectDefinitions.append(definition)
        do {
            try TopologyProtocolApplicationCatalog.validateDefinitions(projectDefinitions)
        } catch {
            validationMessage = FiliusLocalization.t("protocol.builder.validation.behavior")
            return
        }
        if editingExisting { onUpdate(definition) } else { onCreate(definition) }
        stage = 0
        validationMessage = nil
    }
}
