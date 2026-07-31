import SwiftUI

struct TopologyRuntimeGnutellaView: View {
    let configuration: TopologyRuntimeGnutellaConfiguration
    let session: TopologyRuntimeGnutellaSessionState
    let fileSystem: TopologyVirtualFileSystem
    let onSaveConfiguration: (TopologyRuntimeGnutellaConfiguration) -> Void
    let onJoin: (String) -> Void
    let onResetNetwork: () -> Void
    let onSearch: (String) -> Void
    let onClearSearchResults: () -> Void
    let onDownload: (TopologyGnutellaSearchResult) -> Void

    private enum Tab: Hashable {
        case network
        case search
        case files
        case settings
    }

    @State private var selectedTab: Tab = .network
    @State private var bootstrapIPAddress: String
    @State private var searchTerm = ""
    @State private var maximumKnownPeers: Int

    init(
        configuration: TopologyRuntimeGnutellaConfiguration,
        session: TopologyRuntimeGnutellaSessionState,
        fileSystem: TopologyVirtualFileSystem,
        onSaveConfiguration: @escaping (TopologyRuntimeGnutellaConfiguration) -> Void,
        onJoin: @escaping (String) -> Void,
        onResetNetwork: @escaping () -> Void,
        onSearch: @escaping (String) -> Void,
        onClearSearchResults: @escaping () -> Void,
        onDownload: @escaping (TopologyGnutellaSearchResult) -> Void
    ) {
        self.configuration = configuration
        self.session = session
        self.fileSystem = fileSystem
        self.onSaveConfiguration = onSaveConfiguration
        self.onJoin = onJoin
        self.onResetNetwork = onResetNetwork
        self.onSearch = onSearch
        self.onClearSearchResults = onClearSearchResults
        self.onDownload = onDownload
        _bootstrapIPAddress = State(initialValue: "")
        _maximumKnownPeers = State(initialValue: configuration.maximumKnownPeers)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHeader

            Picker(FiliusLocalization.t("gnutella.title"), selection: $selectedTab) {
                Label(FiliusLocalization.t("gnutella.tab.network"), systemImage: "point.3.connected.trianglepath.dotted")
                    .tag(Tab.network)
                Label(FiliusLocalization.t("gnutella.tab.search"), systemImage: "magnifyingglass")
                    .tag(Tab.search)
                Label(FiliusLocalization.t("gnutella.tab.files"), systemImage: "folder")
                    .tag(Tab.files)
                Label(FiliusLocalization.t("gnutella.tab.settings"), systemImage: "gearshape")
                    .tag(Tab.settings)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("gnutella.tabs")

            Group {
                switch selectedTab {
                case .network:
                    networkTab
                case .search:
                    searchTab
                case .files:
                    filesTab
                case .settings:
                    settingsTab
                }
            }
            .frame(maxWidth: .infinity, minHeight: 330, idealHeight: 430, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: configuration.maximumKnownPeers) { _, newValue in
            maximumKnownPeers = newValue
        }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: session.isRunning ? "point.3.connected.trianglepath.dotted" : "network.slash")
                    .foregroundStyle(session.isRunning ? .green : .secondary)
                    .accessibilityHidden(true)
                Text(FiliusLocalization.t("gnutella.title"))
                    .font(.headline)
                Spacer()
                Text(session.isRunning
                     ? FiliusLocalization.t("gnutella.status.running")
                     : FiliusLocalization.t("gnutella.status.stopped"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(session.isRunning ? .green : .secondary)
            }

            if !session.isRunning {
                Label(FiliusLocalization.t("gnutella.status.startHint"), systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error = session.lastError, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("gnutella.error")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gnutella.status")
    }

    private var networkTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sectionCard(FiliusLocalization.t("gnutella.network.join.title")) {
                    Text(FiliusLocalization.t("gnutella.network.bootstrapHelp"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    TextField(FiliusLocalization.t("gnutella.network.bootstrap.placeholder"), text: $bootstrapIPAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("gnutella.bootstrap.ip")
                        .onSubmit { join() }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { networkButtons }
                        VStack(alignment: .leading, spacing: 8) { networkButtons }
                    }
                }

                sectionCard(FiliusLocalization.t("gnutella.network.knownPeers")) {
                    if session.knownPeers.isEmpty {
                        Text(FiliusLocalization.t("gnutella.network.empty"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(session.knownPeers, id: \.self) { peer in
                            HStack {
                                Text(peer.host)
                                    .font(.body.monospacedDigit())
                                Spacer()
                                Text(verbatim: "TCP \(peer.port)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            if peer != session.knownPeers.last {
                                Divider()
                            }
                        }
                    }
                }

                if !session.logs.isEmpty {
                    sectionCard(FiliusLocalization.t("gnutella.logs")) {
                        ForEach(session.logs.suffix(20)) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.message)
                                Text("\(entry.timestampMilliseconds) ms - \(entry.direction)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if entry.id != session.logs.suffix(20).last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("gnutella.network.tab")
    }

    @ViewBuilder
    private var networkButtons: some View {
        Button(FiliusLocalization.t("gnutella.network.join"), action: join)
            .buttonStyle(.borderedProminent)
            .disabled(normalizedBootstrapIPAddress.isEmpty || !session.isRunning)
            .accessibilityIdentifier("gnutella.join")
        Button(FiliusLocalization.t("gnutella.network.reset"), role: .destructive, action: onResetNetwork)
            .disabled(!session.isRunning)
            .accessibilityIdentifier("gnutella.reset.network")
    }

    private var searchTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sectionCard(FiliusLocalization.t("gnutella.search.title")) {
                    if session.knownPeers.isEmpty {
                        Label(FiliusLocalization.t("gnutella.search.joinHint"), systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    TextField(FiliusLocalization.t("gnutella.search.placeholder"), text: $searchTerm)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("gnutella.search.term")
                        .onSubmit { search() }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { searchButtons }
                        VStack(alignment: .leading, spacing: 8) { searchButtons }
                    }
                }

                sectionCard(FiliusLocalization.t("gnutella.search.results")) {
                    if session.searchResults.isEmpty {
                        Text(FiliusLocalization.t("gnutella.search.empty"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(session.searchResults, id: \.self) { result in
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    resultDescription(result)
                                    Spacer()
                                    downloadButton(result)
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    resultDescription(result)
                                    downloadButton(result)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .contain)
                            if result != session.searchResults.last {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("gnutella.search.tab")
    }

    @ViewBuilder
    private var searchButtons: some View {
        Button(FiliusLocalization.t("gnutella.search.action"), action: search)
            .buttonStyle(.borderedProminent)
            .disabled(normalizedSearchTerm.isEmpty || !session.isRunning || session.knownPeers.isEmpty)
            .accessibilityIdentifier("gnutella.search")
        Button(FiliusLocalization.t("gnutella.search.clear"), action: onClearSearchResults)
            .disabled(session.searchResults.isEmpty)
            .accessibilityIdentifier("gnutella.search.clear")
    }

    private func resultDescription(_ result: TopologyGnutellaSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(result.file.name)
                .font(.body.weight(.medium))
            Text("\(result.peer.host) - \(result.file.sizeBytes) B")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func downloadButton(_ result: TopologyGnutellaSearchResult) -> some View {
        Button {
            onDownload(result)
        } label: {
            Label(FiliusLocalization.t("gnutella.download"), systemImage: "arrow.down.circle")
        }
        .buttonStyle(.bordered)
        .disabled(!session.isRunning)
        .accessibilityIdentifier("gnutella.download.\(result.file.name)")
    }

    private var filesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sectionCard(FiliusLocalization.t("gnutella.files.sharedDirectory")) {
                    Text(TopologyGnutella.peerToPeerDirectory)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }

                sectionCard(FiliusLocalization.t("gnutella.files.shared")) {
                    let entries = sharedEntries
                    if entries.isEmpty {
                        Text(FiliusLocalization.t("gnutella.files.empty"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(entries) { entry in
                            HStack {
                                Image(systemName: entry.content.isImage ? "photo" : "doc")
                                    .accessibilityHidden(true)
                                Text(entry.name)
                                    .lineLimit(2)
                                Spacer()
                                Text("\(entry.content.byteCount) B")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            if entry.id != entries.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("gnutella.files.tab")
    }

    private var settingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sectionCard(FiliusLocalization.t("gnutella.settings.peerLimit")) {
                    Stepper(
                        value: $maximumKnownPeers,
                        in: TopologyRuntimeGnutellaConfiguration.javaMinimumKnownPeers ... TopologyRuntimeGnutellaConfiguration.maximumKnownPeers
                    ) {
                        LabeledContent(
                            FiliusLocalization.t("gnutella.settings.maximumPeers"),
                            value: String(maximumKnownPeers)
                        )
                    }
                    .accessibilityIdentifier("gnutella.settings.maximumPeers")

                    Button(FiliusLocalization.t("common.save")) {
                        onSaveConfiguration(TopologyRuntimeGnutellaConfiguration(maximumKnownPeers: maximumKnownPeers))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(maximumKnownPeers == configuration.maximumKnownPeers)
                    .accessibilityIdentifier("gnutella.settings.save")

                    Text(FiliusLocalization.t("gnutella.settings.restartHint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("gnutella.settings.tab")
    }

    private var sharedEntries: [TopologyVirtualFileEntry] {
        (try? fileSystem.entries(in: TopologyGnutella.peerToPeerDirectory))?
            .filter { $0.content.isFile && !$0.name.hasPrefix(".") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            ?? []
    }

    private var normalizedBootstrapIPAddress: String {
        let value = bootstrapIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = value.lastIndex(of: ":"),
              value[value.index(after: separator)...] == String(TopologyGnutella.tcpPort)
        else {
            return value
        }
        return String(value[..<separator])
    }

    private var normalizedSearchTerm: String {
        searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func join() {
        guard !normalizedBootstrapIPAddress.isEmpty else { return }
        onJoin(normalizedBootstrapIPAddress)
    }

    private func search() {
        guard !normalizedSearchTerm.isEmpty, !session.knownPeers.isEmpty else { return }
        onSearch(normalizedSearchTerm)
    }

    private func sectionCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
