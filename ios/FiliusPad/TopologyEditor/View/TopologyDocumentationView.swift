import SwiftUI

struct TopologyDocumentationPaletteView: View {
    let selectedItem: TopologyDocumentationItem?
    let activeTool: TopologyDocumentationTool
    let onSelectTool: (TopologyDocumentationTool) -> Void
    let onEditSelected: () -> Void
    let onDeleteSelected: () -> Void
    let onExportImage: () -> Void
    let onExportPDF: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(FiliusLocalization.t("ui.0401e23e6030"))
                .font(.headline)
                .padding(.top, 12)

            documentationButton(
                title: FiliusLocalization.t("documentation.tool.select"),
                systemImage: "cursorarrow",
                identifier: "documentation.tool.select",
                isSelected: activeTool == .select
            ) { onSelectTool(.select) }

            documentationButton(
                title: FiliusLocalization.t("documentation.tool.text"),
                systemImage: "textformat",
                identifier: "documentation.tool.text",
                isSelected: activeTool == .text
            ) { onSelectTool(.text) }

            documentationButton(
                title: FiliusLocalization.t("documentation.tool.rectangle"),
                systemImage: "rectangle",
                identifier: "documentation.tool.rectangle",
                isSelected: activeTool == .rectangle
            ) { onSelectTool(.rectangle) }

            Divider()

            documentationButton(
                title: FiliusLocalization.t("documentation.action.edit"),
                systemImage: "slider.horizontal.3",
                identifier: "documentation.action.edit",
                isSelected: false,
                isEnabled: selectedItem != nil,
                action: onEditSelected
            )

            documentationButton(
                title: FiliusLocalization.t("documentation.action.delete"),
                systemImage: "trash",
                identifier: "documentation.action.delete",
                isSelected: false,
                isEnabled: selectedItem != nil,
                role: .destructive,
                action: onDeleteSelected
            )

            Spacer()

            documentationButton(
                title: FiliusLocalization.t("documentation.action.exportImage"),
                systemImage: "photo",
                identifier: "documentation.action.export-image",
                isSelected: false,
                action: onExportImage
            )

            documentationButton(
                title: FiliusLocalization.t("documentation.action.exportPDF"),
                systemImage: "doc.richtext",
                identifier: "documentation.action.export-pdf",
                isSelected: false,
                action: onExportPDF
            )
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 8)
        .frame(width: 152)
        .background(Color(red: 0.86, green: 0.86, blue: 0.86))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.black.opacity(0.3)).frame(width: 1)
        }
        .accessibilityIdentifier("documentation.palette")
    }

    private func documentationButton(
        title: String,
        systemImage: String,
        identifier: String,
        isSelected: Bool,
        isEnabled: Bool = true,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 25, weight: isSelected ? .semibold : .regular))
                    .frame(height: 30)
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.38))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.25), lineWidth: 1)
            }
            .clipShape(.rect(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}

struct TopologyDocumentationLayer: View {
    let state: TopologyEditorState
    let showing: TopologyDocumentationItemKind?
    let onSelect: (UUID) -> Void
    let onDragChanged: (UUID, CGSize) -> Void
    let onDragEnded: (UUID) -> Void

    var body: some View {
        ZStack {
            ForEach(state.documentationItems.inDeterministicRenderOrder) { item in
                if (showing == nil || item.kind == showing), item.hasSafeRenderValues {
                    itemView(item)
                }
            }
        }
        .accessibilityIdentifier("canvas.documentationLayer.\(showing?.rawValue ?? "all")")
    }

    private func itemView(_ item: TopologyDocumentationItem) -> some View {
        let screenOrigin = state.viewport.worldToScreen(item.frame.origin)
        let screenSize = CGSize(
            width: item.frame.width * state.viewport.scale,
            height: item.frame.height * state.viewport.scale
        )
        let selected = state.selectedDocumentationItemID == item.id
        let isEditable = state.workspaceMode == .documentation && state.simulationPhase == .stopped

        return Button {
            guard isEditable else { return }
            onSelect(item.id)
        } label: {
            Group {
                switch item.kind {
                case .rectangle:
                    Rectangle()
                        .fill(Color(documentationColor: item.color))
                case .text:
                    Text(item.text)
                        .font(.system(
                            size: max(8, item.fontSize * state.viewport.scale),
                            weight: item.isBold ? .bold : .regular
                        ))
                        .foregroundStyle(Color(documentationColor: item.color))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(3)
                }
            }
            .frame(width: max(1, screenSize.width), height: max(1, screenSize.height))
            .contentShape(Rectangle())
            .overlay {
                if selected {
                    Rectangle()
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                }
            }
        }
        .buttonStyle(.plain)
        .position(
            x: screenOrigin.x + screenSize.width / 2,
            y: screenOrigin.y + screenSize.height / 2
        )
        .disabled(!isEditable)
        .accessibilityLabel(accessibilityLabel(for: item))
        .accessibilityValue(selected ? FiliusLocalization.t("documentation.selected") : FiliusLocalization.t("documentation.notSelected"))
        .accessibilityHint(isEditable ? FiliusLocalization.t("documentation.dragHint") : FiliusLocalization.t("documentation.elementHint"))
        .accessibilityIdentifier("canvas.documentation.item.\(item.id.uuidString)")
        .highPriorityGesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    guard isEditable else { return }
                    onDragChanged(item.id, value.translation)
                }
                .onEnded { _ in
                    guard isEditable else { return }
                    onDragEnded(item.id)
                }
        )
    }

    private func accessibilityLabel(for item: TopologyDocumentationItem) -> String {
        switch item.kind {
        case .text:
            return item.text.isEmpty
                ? FiliusLocalization.t("documentation.annotation.empty")
                : FiliusLocalization.t("documentation.annotation.text", item.text)
        case .rectangle:
            return FiliusLocalization.t("documentation.rectangle")
        }
    }
}

struct TopologyDocumentationItemEditorSheet: View {
    let originalItem: TopologyDocumentationItem
    let onSave: (TopologyDocumentationItem) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @State private var width: Double
    @State private var height: Double
    @State private var fontSize: Double
    @State private var isBold: Bool
    @State private var colorPreset: TopologyDocumentationColorPreset?

    init(
        item: TopologyDocumentationItem,
        onSave: @escaping (TopologyDocumentationItem) -> Void,
        onCancel: @escaping () -> Void
    ) {
        originalItem = item
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: item.text)
        _width = State(initialValue: Double(item.frame.width))
        _height = State(initialValue: Double(item.frame.height))
        _fontSize = State(initialValue: Double(item.fontSize))
        _isBold = State(initialValue: item.isBold)
        _colorPreset = State(initialValue: TopologyDocumentationColorPreset.exactMatch(for: item.color))
    }

    var body: some View {
        NavigationStack {
            Form {
                if originalItem.kind == .text {
                    Section(FiliusLocalization.t("model.text")) {
                        TextEditor(text: $text)
                            .frame(minHeight: 120)
                            .accessibilityIdentifier("documentation.editor.text")
                        Stepper(FiliusLocalization.t("documentation.fontSize", Int(fontSize)), value: $fontSize, in: 8...72, step: 1)
                            .accessibilityIdentifier("documentation.editor.font-size")
                        Toggle(FiliusLocalization.t("ui.acf4dbde9afe"), isOn: $isBold)
                            .accessibilityIdentifier("documentation.editor.bold")
                    }
                }

                Section(FiliusLocalization.t("ui.0f3a847b2804")) {
                    Stepper(FiliusLocalization.t("documentation.width", Int(width)), value: $width, in: 32...2_000, step: 8)
                        .accessibilityIdentifier("documentation.editor.width")
                    Stepper(FiliusLocalization.t("documentation.height", Int(height)), value: $height, in: 24...2_000, step: 8)
                        .accessibilityIdentifier("documentation.editor.height")
                }

                Section(FiliusLocalization.t("ui.89b7957dae43")) {
                    Picker(FiliusLocalization.t("ui.89b7957dae43"), selection: $colorPreset) {
                        Text(FiliusLocalization.t("ui.0cd3a981d184"))
                            .tag(nil as TopologyDocumentationColorPreset?)
                        ForEach(TopologyDocumentationColorPreset.allCases) { preset in
                            Label(preset.title, systemImage: preset.systemImage)
                                .tag(Optional(preset))
                        }
                    }
                    .accessibilityIdentifier("documentation.editor.color")
                }
            }
            .navigationTitle(
                originalItem.kind == .text
                    ? FiliusLocalization.t("ui.349e9de6536a")
                    : FiliusLocalization.t("ui.434d7a7e7a09")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(FiliusLocalization.t("ui.07af7cb30fca"), action: onCancel)
                        .accessibilityIdentifier("documentation.editor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(FiliusLocalization.t("ui.9ed6503318b5")) {
                        onSave(editedItem)
                    }
                    .accessibilityIdentifier("documentation.editor.save")
                }
            }
        }
    }

    private var editedItem: TopologyDocumentationItem {
        TopologyDocumentationItem(
            id: originalItem.id,
            kind: originalItem.kind,
            frame: CGRect(
                origin: originalItem.frame.origin,
                size: CGSize(width: width, height: height)
            ),
            text: text,
            color: colorPreset?.color ?? originalItem.color,
            fontName: originalItem.fontName,
            fontSize: CGFloat(fontSize),
            isBold: isBold,
            order: originalItem.order
        )
    }
}

private enum TopologyDocumentationColorPreset: String, CaseIterable, Identifiable {
    case black
    case paleYellow
    case blue
    case green
    case red

    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: return FiliusLocalization.t("documentation.color.black")
        case .paleYellow: return FiliusLocalization.t("documentation.color.paleYellow")
        case .blue: return FiliusLocalization.t("documentation.color.blue")
        case .green: return FiliusLocalization.t("documentation.color.green")
        case .red: return FiliusLocalization.t("documentation.color.red")
        }
    }

    var systemImage: String { "circle.fill" }

    var color: TopologyDocumentationColor {
        switch self {
        case .black: return .black
        case .paleYellow: return .paleYellow
        case .blue: return TopologyDocumentationColor(red: 0.18, green: 0.42, blue: 0.86, alpha: 0.82)
        case .green: return TopologyDocumentationColor(red: 0.20, green: 0.68, blue: 0.36, alpha: 0.82)
        case .red: return TopologyDocumentationColor(red: 0.82, green: 0.22, blue: 0.22, alpha: 0.82)
        }
    }

    static func exactMatch(for color: TopologyDocumentationColor) -> TopologyDocumentationColorPreset? {
        allCases.first { $0.color == color }
    }
}

private extension Color {
    init(documentationColor: TopologyDocumentationColor) {
        self.init(
            red: documentationColor.red,
            green: documentationColor.green,
            blue: documentationColor.blue,
            opacity: documentationColor.alpha
        )
    }
}
