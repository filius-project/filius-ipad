import SwiftUI

struct TopologyContextualHelpSheet: View {
    let context: TopologyProductHelpContext

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(context.title, systemImage: contextIcon)
                            .font(.headline)
                        Text(context.summary)
                            .font(.body)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("productShell.help.context")
                } header: {
                    Text(FiliusLocalization.t("ui.98bd5cd47690"))
                }

                Section(FiliusLocalization.t("ui.7afff4b5103b")) {
                    ForEach(context.steps) { step in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title)
                                .font(.headline)
                            Text(step.detail)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("productShell.help.step.\(step.id)")
                    }
                }

                Section(FiliusLocalization.t("ui.42525a112f15")) {
                    Text(FiliusLocalization.t("ui.9edb008d2cd0"))
                }
            }
            .navigationTitle(FiliusLocalization.t("ui.b74af50bb9c6"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(FiliusLocalization.t("ui.44424b18700e")) { dismiss() }
                        .accessibilityIdentifier("productShell.help.close")
                }
            }
        }
        .accessibilityIdentifier("productShell.help.sheet")
    }

    private var contextIcon: String {
        switch context {
        case .design:
            return "hammer"
        case .documentation:
            return "text.badge.plus"
        case .simulation:
            return "play.circle"
        }
    }
}

struct TopologyProductInformationSheet: View {
    let metadata: TopologyProductMetadata

    @Environment(\.dismiss) private var dismiss
    @State private var selectedLegalDocument: TopologyLegalDocument?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(metadata.appName)
                            .font(.title2.bold())
                        Text(FiliusLocalization.t("product.version", metadata.version, metadata.build))
                            .font(.headline)
                        Text(metadata.bundleIdentifier)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("productShell.info.version")
                }

                Section(FiliusLocalization.t("ui.b744461a8078")) {
                    Text(FiliusLocalization.t("product.purpose"))
                    Text(FiliusLocalization.t("ui.b6de44cd448b"))
                }

                Section(FiliusLocalization.t("ui.a0dcbd4b0c9d")) {
                    LabeledContent(FiliusLocalization.t("ui.312386841084"), value: metadata.repositoryName)
                    LabeledContent(FiliusLocalization.t("ui.a0dcbd4b0c9d"), value: FiliusLocalization.t("product.license"))
                    LabeledContent(
                        FiliusLocalization.t("product.additionalPermission"),
                        value: FiliusLocalization.t("product.additionalPermissionEffectiveDate")
                    )
                    LabeledContent(
                        FiliusLocalization.t("product.repositoryEvidence"),
                        value: TopologyProductMetadata.repositoryLicenseEvidenceFiles.joined(separator: ", ")
                    )
                    Text(FiliusLocalization.t("product.attribution"))
                        .font(.footnote.weight(.semibold))
                    Text(FiliusLocalization.t("product.independentStatus"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(FiliusLocalization.t("product.licenseNote"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("productShell.info.license")

                Section(FiliusLocalization.t("product.legalTexts")) {
                    ForEach(TopologyLegalDocument.allCases) { document in
                        Button(document.title) {
                            selectedLegalDocument = document
                        }
                        .accessibilityIdentifier("productShell.info.legal.\(document.rawValue)")
                    }
                }
                .accessibilityIdentifier("productShell.info.legalTexts")
            }
            .navigationTitle(FiliusLocalization.t("ui.0eb5ed506e49"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(FiliusLocalization.t("ui.44424b18700e")) { dismiss() }
                        .accessibilityIdentifier("productShell.info.close")
                }
            }
        }
        .sheet(item: $selectedLegalDocument) { document in
            TopologyLegalDocumentSheet(document: document)
        }
        .accessibilityIdentifier("productShell.info.sheet")
    }
}

enum TopologyLegalDocument: String, CaseIterable, Identifiable {
    case gplV2
    case gplV3
    case applePlatformPermissionHash

    var id: String { rawValue }

    var filename: String {
        switch self {
        case .gplV2:
            return "GPLv2.txt"
        case .gplV3:
            return "GPLv3.txt"
        case .applePlatformPermissionHash:
            return "Apple-Platform-Additional-Permission.sha256"
        }
    }

    var title: String {
        switch self {
        case .gplV2:
            return FiliusLocalization.t("product.legal.gplV2")
        case .gplV3:
            return FiliusLocalization.t("product.legal.gplV3")
        case .applePlatformPermissionHash:
            return FiliusLocalization.t("product.legal.applePermissionHash")
        }
    }

    var content: String {
        let url = Bundle.main.url(forResource: filename, withExtension: nil)
            ?? Bundle.main.url(forResource: filename, withExtension: nil, subdirectory: "Legal")
        guard let url,
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return FiliusLocalization.t("product.legal.unavailable", filename)
        }
        return contents
    }
}

struct TopologyLegalDocumentSheet: View {
    let document: TopologyLegalDocument

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(document.content)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(FiliusLocalization.t("ui.44424b18700e")) { dismiss() }
                        .accessibilityIdentifier("productShell.info.legal.close")
                }
            }
        }
        .accessibilityIdentifier("productShell.info.legal.sheet.\(document.rawValue)")
    }
}

struct TopologyProductSettingsSheet: View {
    @Binding var preferences: TopologyAppPreferences
    let onShowGuidedTour: () -> Void
    let onRestoreDefaults: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(FiliusLocalization.t("ui.8e34943c353e")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(FiliusLocalization.t("ui.6899d664860e"))
                            Spacer()
                            Text(preferences.simulationSpeed.displayValue)
                                .monospacedDigit()
                                .accessibilityIdentifier("productShell.settings.speed.value")
                        }

                        Slider(
                            value: speedBinding,
                            in: Double(TopologySimulationSpeed.minimumPercent)...Double(TopologySimulationSpeed.maximumPercent),
                            step: 1
                        )
                        .accessibilityLabel(FiliusLocalization.t("ui.6899d664860e"))
                        .accessibilityValue(preferences.simulationSpeed.accessibilityValue)
                        .accessibilityHint(FiliusLocalization.t("ui.aa414b72d26c"))
                        .accessibilityIdentifier("productShell.settings.speed.slider")
                    }

                    Toggle(FiliusLocalization.t("ui.2f07162e3a45"), isOn: $preferences.showsVirtualClock)
                        .accessibilityIdentifier("productShell.settings.virtualClock.toggle")
                }

                Section(FiliusLocalization.t("settings.language.title")) {
                    Picker(
                        FiliusLocalization.t("settings.language.title"),
                        selection: $preferences.language
                    ) {
                        ForEach(FiliusAppLanguage.allCases) { language in
                            Text(language.localizedTitle)
                                .tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel(FiliusLocalization.t("settings.language.title"))
                    .accessibilityValue(preferences.language.localizedTitle)
                    .accessibilityIdentifier("productShell.settings.language.picker")
                }

                Section(FiliusLocalization.t("settings.experimental.title")) {
                    Toggle(
                        FiliusLocalization.t("settings.experimental.protocolApplications"),
                        isOn: $preferences.experimentalProtocolApplicationsEnabled
                    )
                    .accessibilityIdentifier("productShell.settings.experimental.protocolApplications.toggle")

                    Text(FiliusLocalization.t("settings.experimental.protocolApplications.detail"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(FiliusLocalization.t("tour.settings.section")) {
                    Button {
                        onShowGuidedTour()
                    } label: {
                        Label(FiliusLocalization.t("tour.settings.rerun"), systemImage: "questionmark.circle")
                    }
                    .accessibilityIdentifier("productShell.settings.guidedTour")
                }

                Section(FiliusLocalization.t("ui.5818989406eb")) {
                    Text(FiliusLocalization.t("ui.1f420ec6431a"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button(FiliusLocalization.t("ui.a249dcc85b13"), role: .destructive) {
                        onRestoreDefaults()
                    }
                    .accessibilityIdentifier("productShell.settings.reset")
                }
            }
            .navigationTitle(FiliusLocalization.t("ui.3e5af3d1b00c"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(FiliusLocalization.t("ui.708ad54eca23")) { dismiss() }
                        .accessibilityIdentifier("productShell.settings.close")
                }
            }
        }
        .accessibilityIdentifier("productShell.settings.sheet")
    }

    private var speedBinding: Binding<Double> {
        Binding(
            get: { Double(preferences.simulationSpeed.percent) },
            set: { preferences.setSimulationSpeed(percent: Int($0.rounded())) }
        )
    }
}

struct TopologyVirtualClockStatusView: View {
    let currentTimeMilliseconds: UInt64
    let speed: TopologySimulationSpeed

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(FiliusLocalization.t("ui.ec905c91e461"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(FiliusLocalization.t("settings.clock.display", currentTimeMilliseconds, speed.displayValue))
                .font(.caption.monospacedDigit().weight(.medium))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(FiliusLocalization.t("ui.ec905c91e461"))
        .accessibilityValue(FiliusLocalization.t("settings.speed.status", String(currentTimeMilliseconds), String(speed.percent)))
        .accessibilityIdentifier("simulation.virtualClock.status")
    }
}


struct TopologyGuidedTourView: View {
    let onSkip: () -> Void
    let onComplete: () -> Void

    @State private var selection = 0

    private let pages: [(icon: String, titleKey: String, detailKey: String)] = [
        ("network", "tour.welcome.title", "tour.welcome.detail"),
        ("folder", "tour.files.title", "tour.files.detail"),
        ("hammer", "tour.design.title", "tour.design.detail"),
        ("cursorarrow.motionlines", "tour.canvas.title", "tour.canvas.detail"),
        ("play.fill", "tour.simulation.title", "tour.simulation.detail"),
        ("desktopcomputer", "tour.runtime.title", "tour.runtime.detail"),
        ("network.badge.shield.half.filled", "tour.traffic.title", "tour.traffic.detail"),
        ("pencil.and.outline", "tour.documentation.title", "tour.documentation.detail"),
        ("keyboard", "tour.shortcuts.title", "tour.shortcuts.detail")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TabView(selection: $selection) {
                    ForEach(pages.indices, id: \.self) { index in
                        VStack(spacing: 24) {
                            Image(systemName: pages[index].icon)
                                .font(.system(size: 72, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.accentColor)
                                .frame(height: 100)
                            Text(FiliusLocalization.t(pages[index].titleKey))
                                .font(.largeTitle.bold())
                                .multilineTextAlignment(.center)
                            Text(FiliusLocalization.t(pages[index].detailKey))
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 560)
                        }
                        .padding(32)
                        .tag(index)
                        .accessibilityIdentifier("guidedTour.page.\(index)")
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                HStack {
                    Button(FiliusLocalization.t("tour.skip"), action: onSkip)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("guidedTour.skip")
                    Spacer()
                    if selection > 0 {
                        Button(FiliusLocalization.t("tour.previous")) { selection -= 1 }
                            .buttonStyle(.bordered)
                    }
                    Button(selection == pages.count - 1 ? FiliusLocalization.t("tour.done") : FiliusLocalization.t("tour.next")) {
                        if selection == pages.count - 1 { onComplete() } else { selection += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(selection == pages.count - 1 ? "guidedTour.done" : "guidedTour.next")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .navigationTitle(FiliusLocalization.t("tour.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("guidedTour.sheet")
    }
}
