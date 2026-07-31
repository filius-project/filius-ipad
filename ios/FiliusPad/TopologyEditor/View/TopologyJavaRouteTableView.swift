import SwiftUI

struct TopologyJavaRouteTableView: View {
    let interfaces: [TopologyRuntimeInterfaceConfigurationItem]
    let manualRoutes: [TopologyRuntimeManualRoute]
    let defaultGateway: String?
    let onSaveManualRoutes: ([TopologyRuntimeManualRoute]) -> Void

    @State private var drafts: [TopologyJavaRouteDraft]
    @State private var selectedDraftID: UUID?
    @State private var showAllEntries = true
    @State private var isWindowPresented = false
    @FocusState private var focusedCell: FocusedCell?

    init(
        interfaces: [TopologyRuntimeInterfaceConfigurationItem],
        manualRoutes: [TopologyRuntimeManualRoute],
        defaultGateway: String?,
        onSaveManualRoutes: @escaping ([TopologyRuntimeManualRoute]) -> Void
    ) {
        self.interfaces = interfaces
        self.manualRoutes = manualRoutes
        self.defaultGateway = defaultGateway
        self.onSaveManualRoutes = onSaveManualRoutes
        _drafts = State(initialValue: manualRoutes.map { TopologyJavaRouteDraft(route: $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FiliusLocalization.t("ui.399f306777d2"))
                .font(.subheadline.weight(.semibold))

            GeometryReader { proxy in
                if TopologyDenseLayoutPolicy.usesCompactPresentation(width: proxy.size.width) {
                    compactRouteList
                } else {
                    routeTable(
                        viewportSize: CGSize(
                            width: max(proxy.size.width, TopologyJavaRouteTable.compactViewportSize.width),
                            height: max(proxy.size.height, TopologyJavaRouteTable.compactViewportSize.height)
                        ),
                        accessibilityIdentifier: "runtime.device.router.routes.table"
                    )
                }
            }
            .frame(minHeight: 220, maxHeight: 320)

            Toggle(FiliusLocalization.t("ui.f19ab1820a24"), isOn: $showAllEntries)
                .accessibilityIdentifier("runtime.device.router.routes.showAll")

            HStack(spacing: 8) {
                Button(FiliusLocalization.t("ui.8955ab6bc1d4"), action: addBlankRow)
                    .disabled(hasPendingBlank)
                    .accessibilityIdentifier("runtime.device.router.routes.add")

                Button(FiliusLocalization.t("ui.bcab7673e6e5"), action: deleteSelectedRow)
                    .disabled(selectedDraftID == nil)
                    .accessibilityIdentifier("runtime.device.router.routes.delete")

                Button(FiliusLocalization.t("ui.9c6ec5655754")) {
                    isWindowPresented = true
                }
                .accessibilityIdentifier("runtime.device.router.routes.openWindow")
            }
            .buttonStyle(.bordered)
        }
        .accessibilityIdentifier("runtime.device.router.routes")
        .sheet(isPresented: $isWindowPresented) {
            NavigationStack {
                routeTable(
                    viewportSize: standaloneTableViewportSize,
                    accessibilityIdentifier: "runtime.device.router.routes.modal.table"
                )
                .padding(12)
                .navigationTitle(FiliusLocalization.t("ui.399f306777d2"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(FiliusLocalization.t("ui.708ad54eca23")) {
                            isWindowPresented = false
                        }
                    }
                }
            }
            .frame(
                width: TopologyJavaRouteTable.windowSize.width,
                height: TopologyJavaRouteTable.windowSize.height
            )
            .accessibilityIdentifier("runtime.device.router.routes.modal")
        }
        .onChange(of: manualRoutes) { _, newRoutes in
            synchronizeDrafts(with: newRoutes)
        }
        .onChange(of: focusedCell) { oldCell, _ in
            guard let oldCell else { return }
            commitDraft(id: oldCell.draftID)
        }
    }

    private var standaloneTableViewportSize: CGSize {
        // Java's 600x400 dialog contains only its scroll pane below the title bar.
        CGSize(
            width: TopologyJavaRouteTable.windowSize.width - 24,
            height: TopologyJavaRouteTable.windowSize.height - 68
        )
    }

    private var projectedRows: [TopologyRuntimeRouteRow] {
        TopologyJavaRouteTable.rows(
            interfaces: interfaces,
            manualRoutes: manualRoutes,
            defaultGateway: defaultGateway
        )
    }

    private var generatedPrefixRows: [TopologyRuntimeRouteRow] {
        projectedRows.filter { row in
            row.origin != .manual && row.origin != .defaultGateway
        }
    }

    private var generatedSuffixRows: [TopologyRuntimeRouteRow] {
        projectedRows.filter { $0.origin == .defaultGateway }
    }

    private var persistedDrafts: [TopologyJavaRouteDraft] {
        drafts.filter { !$0.isPendingInsertion }
    }

    private var pendingDrafts: [TopologyJavaRouteDraft] {
        drafts.filter(\.isPendingInsertion)
    }

    private var hasPendingBlank: Bool {
        drafts.contains(where: \.isPendingInsertion)
    }

    private var compactRouteList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 8) {
                if showAllEntries {
                    ForEach(Array(generatedPrefixRows.enumerated()), id: \.offset) { index, row in
                        compactGeneratedRow(row, index: index)
                    }
                }
                ForEach(persistedDrafts) { draft in
                    compactEditableRow(draft)
                }
                if showAllEntries {
                    ForEach(Array(generatedSuffixRows.enumerated()), id: \.offset) { index, row in
                        compactGeneratedRow(
                            row,
                            index: generatedPrefixRows.count + index
                        )
                    }
                }
                ForEach(pendingDrafts) { draft in
                    compactEditableRow(draft)
                }
            }
            .padding(8)
        }
        .frame(minHeight: 120, maxHeight: 260)
        .background(Color(uiColor: .systemBackground))
        .overlay(Rectangle().stroke(Color(uiColor: .separator), lineWidth: 1))
        .accessibilityIdentifier("runtime.device.router.routes.table")
    }

    private func compactGeneratedRow(
        _ row: TopologyRuntimeRouteRow,
        index: Int
    ) -> some View {
        Button {
            selectedDraftID = nil
        } label: {
            compactRouteCard(
                values: [
                    TopologyJavaRouteTableColumn.destination.title: row.destinationNetwork,
                    TopologyJavaRouteTableColumn.subnetMask.title: row.subnetMask,
                    TopologyJavaRouteTableColumn.nextGateway.title: row.nextHop,
                    TopologyJavaRouteTableColumn.interface.title: row.interfaceIPAddress
                ],
                isSelected: false
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("runtime.device.router.routes.generated.\(index).\(row.origin.rawValue)")
    }

    private func compactEditableRow(_ draft: TopologyJavaRouteDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                selectedDraftID = draft.id
            } label: {
                HStack {
                    Text("\(TopologyJavaRouteTableColumn.destination.title): \(value(for: draft.id, column: .destination))")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()
                    Image(systemName: selectedDraftID == draft.id
                        ? "checkmark.circle.fill"
                        : "circle")
                        .foregroundStyle(selectedDraftID == draft.id ? Color.accentColor : Color.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(TopologyJavaRouteTableColumn.destination.title): \(value(for: draft.id, column: .destination))")
            .accessibilityAddTraits(selectedDraftID == draft.id ? .isSelected : [])
            .accessibilityIdentifier("runtime.device.router.routes.row.\(draft.id.uuidString).select")
            compactEditableField(
                draftID: draft.id,
                column: .destination
            )
            compactEditableField(
                draftID: draft.id,
                column: .subnetMask
            )
            compactEditableField(
                draftID: draft.id,
                column: .nextGateway
            )
            compactEditableField(
                draftID: draft.id,
                column: .interface
            )
        }
        .padding(10)
        .background(
            selectedDraftID == draft.id
                ? Color.accentColor.opacity(0.18)
                : Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button(FiliusLocalization.t("ui.ffa5a8a7e21d")) {
                selectedDraftID = draft.id
                deleteSelectedRow()
            }
            Button(FiliusLocalization.t("ui.ef57c139b531"), action: addBlankRow)
                .disabled(hasPendingBlank)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.device.router.routes.row.\(draft.id.uuidString)")
    }

    private func compactRouteCard(
        values: [String: String],
        isSelected: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(TopologyJavaRouteTableColumn.allCases, id: \.rawValue) { column in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(column.title)
                        .font(.caption.weight(.semibold))
                        .frame(width: 112, alignment: .leading)
                    Text(values[column.title] ?? "—")
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        }
    }

    private func compactEditableField(
        draftID: UUID,
        column: TopologyJavaRouteTableColumn
    ) -> some View {
        let value = value(for: draftID, column: column)
        let isValid = TopologyJavaRouteTable.isValid(value, for: column)
        return TextField(column.title, text: binding(for: draftID, column: column))
            .font(.body.monospaced())
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.numbersAndPunctuation)
            .textFieldStyle(.roundedBorder)
            .focused($focusedCell, equals: FocusedCell(draftID: draftID, column: column))
            .onSubmit { commitDraft(id: draftID) }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isValid ? Color.green.opacity(0.45) : Color.red.opacity(0.55), lineWidth: 1)
            }
            .accessibilityValue(
                isValid
                    ? FiliusLocalization.t("runtime.validation.valid")
                    : FiliusLocalization.t("runtime.validation.invalid")
            )
            .accessibilityIdentifier(
                "runtime.device.router.routes.row.\(draftID.uuidString).cell.\(column.rawValue)"
            )
    }

    private func routeTable(
        viewportSize: CGSize,
        accessibilityIdentifier: String
    ) -> some View {
        let columnWidth = TopologyJavaRouteTable.equalColumnWidth(for: viewportSize.width)

        return ScrollView([.horizontal, .vertical]) {
            VStack(spacing: TopologyJavaRouteTable.rowMargin) {
                tableHeader(columnWidth: columnWidth)

                if showAllEntries {
                    ForEach(Array(generatedPrefixRows.enumerated()), id: \.offset) { index, row in
                        generatedRow(row, index: index, columnWidth: columnWidth)
                    }
                }

                ForEach(persistedDrafts) { draft in
                    editableRow(draft, columnWidth: columnWidth)
                }

                if showAllEntries {
                    ForEach(Array(generatedSuffixRows.enumerated()), id: \.offset) { index, row in
                        generatedRow(
                            row,
                            index: generatedPrefixRows.count + index,
                            columnWidth: columnWidth
                        )
                    }
                }

                ForEach(pendingDrafts) { draft in
                    editableRow(draft, columnWidth: columnWidth)
                }
            }
            .padding(TopologyJavaRouteTable.tableContentInset)
        }
        .frame(width: viewportSize.width, height: viewportSize.height, alignment: .topLeading)
        .background(Color(uiColor: .systemBackground))
        .overlay(Rectangle().stroke(Color(uiColor: .separator), lineWidth: 1))
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func tableHeader(columnWidth: CGFloat) -> some View {
        HStack(spacing: TopologyJavaRouteTable.rowMargin) {
            ForEach(TopologyJavaRouteTableColumn.allCases, id: \.rawValue) { column in
                Text(column.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .frame(
                        width: columnWidth,
                        height: TopologyJavaRouteTable.rowHeight,
                        alignment: .leading
                    )
                    .background(Color(uiColor: .secondarySystemBackground))
                    .accessibilityIdentifier("runtime.device.router.routes.header.\(column.rawValue)")
            }
        }
    }

    private func generatedRow(
        _ row: TopologyRuntimeRouteRow,
        index: Int,
        columnWidth: CGFloat
    ) -> some View {
        HStack(spacing: TopologyJavaRouteTable.rowMargin) {
            generatedCell(row.destinationNetwork, columnWidth: columnWidth)
            generatedCell(row.subnetMask, columnWidth: columnWidth)
            generatedCell(row.nextHop, columnWidth: columnWidth)
            generatedCell(row.interfaceIPAddress, columnWidth: columnWidth)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedDraftID = nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.device.router.routes.generated.\(index).\(row.origin.rawValue)")
    }

    private func generatedCell(_ value: String, columnWidth: CGFloat) -> some View {
        Text(value)
            .font(.caption2)
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
            .frame(
                width: columnWidth,
                height: TopologyJavaRouteTable.rowHeight,
                alignment: .leading
            )
            .background(Color(uiColor: .tertiarySystemBackground))
    }

    private func editableRow(_ draft: TopologyJavaRouteDraft, columnWidth: CGFloat) -> some View {
        HStack(spacing: TopologyJavaRouteTable.rowMargin) {
            editableCell(draftID: draft.id, column: .destination, columnWidth: columnWidth)
            editableCell(draftID: draft.id, column: .subnetMask, columnWidth: columnWidth)
            editableCell(draftID: draft.id, column: .nextGateway, columnWidth: columnWidth)
            editableCell(draftID: draft.id, column: .interface, columnWidth: columnWidth)
        }
        .background(selectedDraftID == draft.id ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedDraftID = draft.id
        }
        .contextMenu {
            Button(FiliusLocalization.t("ui.ffa5a8a7e21d")) {
                selectedDraftID = draft.id
                deleteSelectedRow()
            }
            Button(FiliusLocalization.t("ui.ef57c139b531"), action: addBlankRow)
                .disabled(hasPendingBlank)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.device.router.routes.row.\(draft.id.uuidString)")
    }

    private func editableCell(
        draftID: UUID,
        column: TopologyJavaRouteTableColumn,
        columnWidth: CGFloat
    ) -> some View {
        let value = value(for: draftID, column: column)
        let isValid = TopologyJavaRouteTable.isValid(value, for: column)

        return TextField(column.title, text: binding(for: draftID, column: column))
            .font(.caption2)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.numbersAndPunctuation)
            .textFieldStyle(.plain)
            .lineLimit(1)
            .padding(.horizontal, 2)
            .frame(width: columnWidth, height: TopologyJavaRouteTable.rowHeight)
            .background(isValid ? Color.green.opacity(0.24) : Color.red.opacity(0.28))
            .focused($focusedCell, equals: FocusedCell(draftID: draftID, column: column))
            .simultaneousGesture(
                TapGesture().onEnded {
                    selectedDraftID = draftID
                }
            )
            .onSubmit {
                commitDraft(id: draftID)
            }
            .accessibilityIdentifier(
                "runtime.device.router.routes.row.\(draftID.uuidString).cell.\(column.rawValue)"
            )
    }

    private func value(for draftID: UUID, column: TopologyJavaRouteTableColumn) -> String {
        drafts.first(where: { $0.id == draftID })?.value(for: column) ?? ""
    }

    private func binding(
        for draftID: UUID,
        column: TopologyJavaRouteTableColumn
    ) -> Binding<String> {
        Binding(
            get: { value(for: draftID, column: column) },
            set: { newValue in
                guard let index = drafts.firstIndex(where: { $0.id == draftID }) else {
                    return
                }
                switch column {
                case .destination:
                    drafts[index].destinationNetwork = newValue
                case .subnetMask:
                    drafts[index].subnetMask = newValue
                case .nextGateway:
                    drafts[index].nextGateway = newValue
                case .interface:
                    drafts[index].interfaceIPAddress = newValue
                }
                selectedDraftID = draftID
            }
        )
    }

    private func addBlankRow() {
        drafts = TopologyJavaRouteDraft.appendingBlankIfNeeded(to: drafts)
        guard let blank = drafts.last(where: \.isPendingInsertion) else {
            return
        }
        selectedDraftID = blank.id
        focusedCell = FocusedCell(draftID: blank.id, column: .destination)
    }

    private func deleteSelectedRow() {
        guard let selectedDraftID else {
            return
        }
        drafts.removeAll { $0.id == selectedDraftID }
        self.selectedDraftID = nil
        focusedCell = nil
        persistDraftsIfValid()
    }

    private func commitDraft(id: UUID) {
        guard
            let index = drafts.firstIndex(where: { $0.id == id }),
            drafts[index].manualRoute != nil
        else {
            return
        }

        drafts[index].isPendingInsertion = false
        persistDraftsIfValid()
    }

    private func persistDraftsIfValid() {
        let committedDrafts = drafts.filter { !$0.isPendingInsertion }
        let routes = committedDrafts.compactMap(\.manualRoute)
        guard routes.count == committedDrafts.count else {
            return
        }
        onSaveManualRoutes(routes)
    }

    private func synchronizeDrafts(with routes: [TopologyRuntimeManualRoute]) {
        drafts = routes.map { TopologyJavaRouteDraft(route: $0) }
        selectedDraftID = nil
        focusedCell = nil
    }

    private struct FocusedCell: Hashable {
        let draftID: UUID
        let column: TopologyJavaRouteTableColumn
    }
}
