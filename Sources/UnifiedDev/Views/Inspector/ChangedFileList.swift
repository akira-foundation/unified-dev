import SwiftUI
import Core

struct ChangedFileList: View {
    let model: WorkspaceModel

    @Binding var query: String

    @State private var pendingRevert: ChangedFile?
    @State private var revertAlert: RevertAlert?
    @State private var groups: [ChangedFileGroup] = []
    @State private var treeRows: [ChangedFileTreeRow] = []
    @State private var collapsed: Set<String> = []
    @State private var filtered: [ChangedFile]?
    @State private var filterCollapsed: Set<String> = []
    @State private var previewURL: URL?
    @State private var quickLookArm = 0
    @State private var cursor: String?
    @State private var rowPaths: [String] = []
    @State private var rowTitles: [String] = []
    @State private var keyboard = ListKeyboard()
    @State private var hasKeyboard = false

    @AppStorage(ChangedFilePresentation.storageKey)
    private var isTree = ChangedFilePresentation.defaultsToTree

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if let summary = model.viewedSummary {
                viewedBand(summary)
                Hairline()
            }

            ScrollViewReader { proxy in
                Group {
                    if model.changedFiles.isEmpty {
                        empty
                    } else {
                        files
                    }
                }
                .onChange(of: cursor) { _, path in
                    guard hasKeyboard || followsReviewScroll, let path else { return }
                    proxy.scrollTo(path)
                }
            }
            .listKeyboard(
                hasKeyboard: $hasKeyboard,
                previewing: previewURL,
                armToken: quickLookArm,
                onKey: handle
            )
        }
        .onChange(of: query) { _, _ in rebuild() }
        .onChange(of: model.changedFiles, initial: true) { _, _ in
            rebuild()
            refreshPreview()
        }
        .onChange(of: model.selectedFilePath, initial: true) { _, path in
            if let path, path != cursor {
                if followsReviewScroll {
                    let parents = closedFolders.filter { path.hasPrefix($0 + "/") }
                    if !parents.isEmpty {
                        if filtered == nil { collapsed.subtract(parents) } else { filterCollapsed.subtract(parents) }
                        rebuild()
                    }
                }
                cursor = path
            }
        }
        .onChange(of: cursor) { _, _ in refreshPreview() }
        .onChange(of: hasKeyboard) { _, focused in
            if !focused { keyboard.forgetTyping() }
        }
        .onChange(of: isTree) { _, _ in rebuild() }
        .alert(
            revertAlert?.title ?? "",
            isPresented: $revertAlert.isPresent(),
            presenting: revertAlert
        ) { _ in
        } message: { alert in
            Text(alert.message)
        }
    }

    private var followsReviewScroll: Bool {
        CenterTabStore.shared.review(for: model.workspace.id)?.showsAllFiles == true
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.files) { file in
                            row(file)
                        }
                    } header: {
                        header(group)
                    }
                }
            }
            .padding(.vertical, InspectorLayout.tight)
        }
    }

    private var tree: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(treeRows) { item in
                    treeRow(item)
                }
            }
            .padding(.vertical, InspectorLayout.tight)
        }
    }

    @ViewBuilder
    private var files: some View {
        if let filtered, filtered.isEmpty {
            noMatches
        } else {
            arrangedFiles
        }
    }

    @ViewBuilder
    private var arrangedFiles: some View {
        if isTree {
            tree
        } else {
            list
        }
    }

    @ViewBuilder
    private var empty: some View {
        if model.isLoadingChanges || !model.hasReadChanges {
            LoadingView("Reading the worktree")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            settledEmpty
        }
    }

    @ViewBuilder
    private var settledEmpty: some View {
        if let problem = model.changesError {
            EmptyStateView(
                glyph: "exclamationmark.triangle",
                title: "Could not read the changes",
                message: problem,
                actionTitle: "Try again",
                action: refresh
            )
        } else {
            EmptyStateView(
                glyph: "checkmark.circle",
                title: "No changes yet",
                message: model.diffScope.emptyMessage(base: model.workspace.baseBranch)
            )
        }
    }

    private var noMatches: some View {
        EmptyStateView(
            glyph: "magnifyingglass",
            title: "No files match",
            message: "Nothing in this diff matches \(query)."
        )
    }

    private func header(_ group: ChangedFileGroup) -> some View {
        HStack(spacing: Metrics.spacingSmall) {
            Text(group.directory.isEmpty ? "Repository root" : group.directory)
                .font(Typo.caption)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 0)
            Text("\(group.files.count)")
                .font(Typo.micro)
                .monospacedDigit()
        }
        .foregroundStyle(Palette.textTertiary)
        .padding(.horizontal, InspectorLayout.inset)
        .padding(.vertical, Metrics.spacingSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func treeRow(_ item: ChangedFileTreeRow) -> some View {
        if let file = item.node.file {
            row(file, depth: item.depth)
        } else {
            HoverRow(isSelected: cursor == item.node.path, isFocused: hasKeyboard) {
                ChangedFolderRow(
                    name: item.node.name,
                    path: item.node.path,
                    isExpanded: !closedFolders.contains(item.node.path),
                    depth: item.depth,
                    fullPath: fullPath(item.node.path),
                    action: { activate(folder: item.node.path) },
                    onOpenTerminal: {
                        FolderTerminalTab.open(folder: fullPath(item.node.path), in: model)
                    }
                )
                .equatable()
            }
            .padding(.horizontal, Metrics.spacingSmall)
        }
    }

    private func row(_ file: ChangedFile, depth: Int = 0) -> some View {
        let isSelected = cursor == file.path

        return HoverRow(isSelected: isSelected, isFocused: hasKeyboard) {
            ChangedFileRow(
                file: file,
                isSelected: isSelected,
                isViewed: model.isViewed(file),
                fullPath: fullPath(file.path),
                depth: depth,
                revertBlocker: model.revertBlocker,
                onSelect: { move(to: file.path, opening: true) },
                onRevert: { askToRevert(file) },
                onOpenPage: { BrowserTab.openFile(fullPath(file.path), in: model) },
                onSplitPage: { BrowserTab.splitFile(fullPath(file.path), in: model, axis: $0) },
                onSetViewed: { setViewed($0, file: file) }
            )
            .equatable()
        }
        .padding(.horizontal, Metrics.spacingSmall)
        .discardConfirmation(
            isPresented: Binding(
                get: { pendingRevert?.id == file.id },
                set: { if !$0 { pendingRevert = nil } }
            ),
            alert: {
                DiscardAlert.file(
                    file, base: model.workspace.baseBranch,
                    hasDraft: FileRevert.hasUnsavedEdits(at: fullPath(file.path))
                )
            },
            onConfirm: { revert(file) }
        )
    }

    private func viewedBand(_ summary: String) -> some View {
        HStack(spacing: InspectorLayout.gap) {
            Image(systemName: "checkmark.circle")
                .font(Typo.micro)
                .foregroundStyle(Palette.positive)
                .accessibilityHidden(true)

            Text(summary)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button("Clear", action: clearViewed)
                .buttonStyle(.glass)
                .font(Typo.caption)
                .foregroundStyle(Palette.accent)
                .help("Take every viewed mark off this workspace")
        }
        .padding(.horizontal, InspectorLayout.inset)
        .padding(.vertical, Metrics.spacingSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setViewed(_ isViewed: Bool, file: ChangedFile) {
        let model = model
        Task { await model.setViewed(isViewed, file: file) }
    }

    private func clearViewed() {
        let model = model
        Task { await model.clearViewedFiles() }
    }

    private func rebuild() {
        let narrowed = ChangedFileFilter.apply(
            to: model.changedFiles, needle: FileNeedle.canonical(query)
        )
        filtered = narrowed
        if narrowed == nil { filterCollapsed = [] }

        let shown = narrowed ?? model.changedFiles
        let closed = closedFolders

        if isTree {
            adopt(ChangedFileTree.rows(
                from: ChangedFileTree.build(from: shown),
                collapsed: closed
            ))
        } else {
            groups = ChangedFileGroup.build(from: shown)
            treeRows = []
            let files = groups.flatMap(\.files)
            rowPaths = files.map(\.path)
            rowTitles = files.map(\.filename)
            forgetMissingCursor()
        }
    }

    private var shownFiles: [ChangedFile] { filtered ?? model.changedFiles }

    private var closedFolders: Set<String> { filtered == nil ? collapsed : filterCollapsed }

    private func adopt(_ rows: [ChangedFileTreeRow]) {
        treeRows = rows
        groups = []
        rowPaths = rows.map(\.node.path)
        rowTitles = rows.map(\.node.name)
        forgetMissingCursor()
    }

    private func forgetMissingCursor() {
        if let cursor, !rowPaths.contains(cursor) { self.cursor = nil }
    }

    private func toggle(_ path: String) {
        var next = closedFolders
        if next.contains(path) {
            next.remove(path)
        } else {
            next.insert(path)
        }

        let rows = ChangedFileTree.rows(
            from: ChangedFileTree.build(from: shownFiles),
            collapsed: next
        )
        let motion = TreeDisclosureMotion.rows(
            changing: abs(rows.count - treeRows.count), reduceMotion: reduceMotion
        )

        withAnimation(motion.animation) {
            if filtered == nil {
                collapsed = next
            } else {
                filterCollapsed = next
            }
            adopt(rows)
        }
    }

    private func handle(key: ListKey) -> Bool {
        let index = cursor.flatMap { rowPaths.firstIndex(of: $0) }

        if isTree, key == .left || key == .right {
            switch TreeNavigation.step(key, at: index, in: treeShape) {
            case .expand(let row), .collapse(let row):
                activate(folder: treeRows[row].node.path)
            case .move(let row):
                move(to: rowPaths[row])
            case .none:
                break
            }
            return true
        }

        switch keyboard.outcome(for: key, titles: rowTitles, current: index) {
        case .move(let row):
            move(to: rowPaths[row])
            return true
        case .activate:
            guard let index else { return false }
            activate(row: index)
            return true
        case .handled:
            return true
        case .ignored:
            return false
        }
    }

    private var treeShape: [TreeRow] {
        let closed = closedFolders
        return treeRows.map {
            TreeRow(
                depth: $0.depth,
                isDirectory: $0.node.file == nil,
                isExpanded: !closed.contains($0.node.path)
            )
        }
    }

    private func move(to path: String, opening: Bool = false) {
        cursor = path

        if let file = model.changedFiles.first(where: { $0.path == path }) {
            model.selectedFilePath = file.path
            if opening {
                FileReview.open(path: file.path, in: model)
            } else {
                FileReview.select(path: file.path, in: model)
            }
        }

        quickLookArm += 1
    }

    private func activate(row index: Int) {
        if isTree, treeRows.indices.contains(index), treeRows[index].node.file == nil {
            activate(folder: treeRows[index].node.path)
            return
        }
        move(to: rowPaths[index], opening: true)
    }

    private func activate(folder path: String) {
        cursor = path
        toggle(path)
        quickLookArm += 1
    }

    private func escape() {
        guard query.isEmpty else {
            query = ""
            return
        }
        enterList()
    }

    private func enterList() {
        guard cursor == nil, let first = firstFilePath else {
            quickLookArm += 1
            return
        }
        move(to: first)
    }

    private var firstFilePath: String? {
        guard isTree else { return rowPaths.first }
        return treeRows.first(where: { $0.node.file != nil })?.node.path
    }

    private func fullPath(_ relative: String) -> String {
        (model.workspace.path as NSString).appendingPathComponent(relative)
    }

    private func refreshPreview() {
        previewURL = cursor.flatMap { QuickLookTarget.url(for: fullPath($0)) }
    }

    private func refresh() {
        Task { await model.refreshChanges() }
    }

    private func askToRevert(_ file: ChangedFile) {
        if let revertBlocker = model.revertBlocker {
            revertAlert = RevertAlert(.refused(revertBlocker), filename: file.filename)
        } else {
            pendingRevert = file
        }
    }

    private func revert(_ file: ChangedFile) {
        Task {
            revertAlert = await model.revert(file)
        }
    }
}
