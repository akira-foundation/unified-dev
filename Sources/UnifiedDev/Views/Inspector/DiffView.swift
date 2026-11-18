import SwiftUI
import Core

struct DiffView: View {
    let model: WorkspaceModel
    let file: ChangedFile
    let embeddedWidth: CGFloat?
    let defersDistantBlocks: Bool
    let isCollapsed: Bool
    var onScrollFocus: (() -> Void)?
    let navigationTarget: Bool
    var onNavigationLayout: ((Bool) -> Void)?
    var onPrepared: (() -> Void)?
    var onToggleCollapsed: (() -> Void)?

    private static let largeDiffLimit = 5_000
    private static let gapStep = 24
    private static let collapseThreshold = 8
    private static let keptContext = 3
    private static let leadingCentre = UnitPoint(x: 0, y: 0.5)

    @AppStorage(DiffLayoutSetting.storageKey) private var isSideBySide = false
    @AppStorage(DiffWhitespaceSetting.storageKey) private var ignoresWhitespace = false

    @State private var phase: Phase = .loading
    @State private var rows: [DiffRow] = []
    @State private var pendingDiffNavigation = false
    @State private var rowRevision = 0
    @State private var wrappedPresentation: WrappedPresentation?
    @State private var standaloneHeights = RowMeasurements<[CGFloat]>()

    private struct WrapRequest: Equatable {
        var width: CGFloat?
        var revision: Int
        var collapsed: Bool
    }

    private struct WrappedPresentation {
        var revision: Int
        var document: DiffDocument
        var rows: [DiffRow]
        var width: CGFloat
        var heights: [String: [CGFloat]]
        var codeHeight: CGFloat
    }
    @State private var findText = ""
    @State private var findIndex = 0
    @State private var findRevision = 0
    @FocusState private var findFocused: Bool
    @State private var expandedRuns: Set<Int> = []
    @State private var revealedGaps: [Int: Int] = [:]
    @State private var fileLines: [String]?

    @State private var placements: [ReviewPlacement] = []
    @State private var commentedSpots: Set<ReviewSpot> = []
    @State private var priming: Task<Void, Never>?
    private var draft: ReviewDraft? { model.reviewDrafts[file.path] }
    private var draftSelection: ReviewSelection? { draft?.selection }
    private var draftEditorSpot: ReviewSpot? {
        draftSelection.map { ReviewSpot(side: $0.side, line: $0.end) }
    }

    @State private var rangeDrag: ReviewSelection?

    @State private var discarding: PendingDiscard?

    @State private var source: FileDiff?
    @State private var preparedWhitespace: Bool?
    @State private var mode: FileViewMode
    @State private var showsMarkdownPreview = false
    @State private var isEditable = false
    @State private var presented: String?
    @State private var revertAlert: RevertAlert?
    @State private var pendingHunk: DiffHunk?
    @State private var stagedHunk: HunkDiscard.Staged = .clean
    @State private var refusedHunks: [DiffHunk: HunkDiscard.Staged] = [:]
    private let session = FileEditSession.shared
    private let edits = DiffEditSession.shared
    @State private var editProblem: String?
    @State private var discardingEdit: DiffEditRegion?

    init(
        model: WorkspaceModel, file: ChangedFile, embeddedWidth: CGFloat? = nil,
        defersDistantBlocks: Bool = false, isCollapsed: Bool = false,
        onScrollFocus: (() -> Void)? = nil, navigationTarget: Bool = false,
        onNavigationLayout: ((Bool) -> Void)? = nil, onPrepared: (() -> Void)? = nil,
        onToggleCollapsed: (() -> Void)? = nil
    ) {
        self.model = model
        self.file = file
        self.embeddedWidth = embeddedWidth
        self.defersDistantBlocks = defersDistantBlocks
        self.isCollapsed = isCollapsed
        self.onScrollFocus = onScrollFocus
        self.navigationTarget = navigationTarget
        self.onNavigationLayout = onNavigationLayout
        self.onPrepared = onPrepared
        self.onToggleCollapsed = onToggleCollapsed
        let absolute = (model.workspace.path as NSString).appendingPathComponent(file.path)
        _mode = State(initialValue: FileEditSession.shared.isDirty(absolute)
            || SourceEditorState.file(absolute).prefersEditing
            || (embeddedWidth == nil && SourceEditorState.file(absolute).request != nil) ? .edit : .diff)

        let held = model.heldDiff(
            for: file,
            ignoringWhitespace: UserDefaults.standard.bool(forKey: DiffWhitespaceSetting.storageKey)
        )
        let opening: Phase = held.map { .ready($0.document) } ?? .loading
        _phase = State(initialValue: opening)
        _source = State(initialValue: held?.source)
        _preparedWhitespace = State(initialValue: held == nil ? nil
            : UserDefaults.standard.bool(forKey: DiffWhitespaceSetting.storageKey))
        _fileLines = State(initialValue: held?.lines)
        _presented = State(initialValue: held == nil ? nil : file.path)
    }

    private enum Phase {
        case loading
        case notice(symbol: String, title: String, detail: String)
        case gated(FileDiff, changed: Int, ignoringWhitespace: Bool)
        case ready(DiffDocument)
        case image(ImageDiffSides)
    }

    private struct LoadID: Hashable {
        var language: Language
        var workspaceID: WorkspaceID
        var file: ChangedFile
        var scope: DiffScope
        var isCollapsed: Bool
        var ignoringWhitespace: Bool
        var imageRevision: String?
    }

    private struct PendingDiscard: Equatable {
        var target: Target
        var question: ReviewCommentDiscard

        enum Target: Equatable {
            case draft
            case edit(ReviewCommentID)
        }
    }

    private var effectiveLanguage: Language {
        SourceEditorState.file(absolutePath).languageOverride ?? Language.detect(path: file.path)
    }

    private var presentedLanguage: Language? {
        if case let .ready(document) = phase { return document.language }
        return nil
    }

    private var absolutePath: String {
        (model.workspace.path as NSString).appendingPathComponent(file.path)
    }

    var body: some View {
        observedBody
        .focusedValue(\.sourceFind, mode == .diff ? SourceFindAction(path: absolutePath) { action in
            switch action {
            case .nextMatch: stepFind(1)
            case .previousMatch: stepFind(-1)
            default: findFocused = true
            }
        } : nil)
        .onChange(of: mode) { old, mode in
            showsMarkdownPreview = false
            let state = SourceEditorState.file(absolutePath)
            state.prefersEditing = mode == .edit
            if old == .diff, mode == .edit, state.request == nil {
                state.go(to: CodeLocation(path: file.path, line: state.diffLine))
            }
            if mode == .diff {
                state.request = nil
                state.diffRow = rows.first { $0.sourceLines.contains { $0.newNumber == state.line } }?.id ?? state.diffRow
            }
        }
        .onChange(of: SourceEditorState.file(absolutePath).revision) { _, _ in
            showsMarkdownPreview = false
            if isEditable, embeddedWidth == nil { mode = .edit }
        }
        .onChange(of: SourceEditorState.file(absolutePath).diffRevision, initial: true) { _, _ in
            let state = SourceEditorState.file(absolutePath)
            guard state.diffRequest != nil, embeddedWidth != nil || state.request == nil else { return }
            showsMarkdownPreview = false
            mode = .diff
            pendingDiffNavigation = true
            if case let .ready(document) = phase {
                expandedRuns.formUnion(document.file.hunks.flatMap(\.lines).map(\.index))
                rebuild()
            }
        }
        .overlay(alignment: .bottomLeading) {
            if mode == .diff, let message = SourceEditorState.file(absolutePath).message {
                Text(message).font(Typo.caption).padding(8).background(Palette.surfaceSunken)
            }
        }
    }

    private var observedBody: some View {
        let tracksFile = navigationTarget && SourceEditorState.file(absolutePath).diffRequest == nil
        return Group {
            if embeddedWidth != nil {
                Section {
                    if !isCollapsed {
                        fileContent
                            .onGeometryChange(for: CGRect?.self) { proxy in
                                tracksFile ? proxy.frame(in: .scrollView(axis: .vertical)) : nil
                            } action: { frame in
                                if let frame {
                                    onNavigationLayout?(abs(frame.minY - InspectorLayout.reviewHeaderHeight) <= 1)
                                }
                            }
                            .onGeometryChange(for: Bool.self) { proxy in
                                let frame = proxy.frame(in: .scrollView(axis: .vertical))
                                let edge = InspectorLayout.reviewHeaderHeight
                                return frame.minY <= edge && frame.maxY > edge
                            } action: { active in
                                if active { onScrollFocus?() }
                            }
                            .overlay(alignment: .bottom) { Hairline() }
                    }
                } header: {
                    fileHeader
                        .onGeometryChange(for: Bool.self) { proxy in
                            let frame = proxy.frame(in: .scrollView(axis: .vertical))
                            return isCollapsed && frame.minY <= 0 && frame.maxY > 0
                        } action: { active in
                            if active { onScrollFocus?() }
                        }
                        .overlay(alignment: .bottom) { Hairline() }
                }
            } else {
                VStack(spacing: 0) {
                    fileHeader
                    Hairline()
                    fileContent
                }
            }
        }
        .background {
            if embeddedWidth == nil { shortcut }
        }
        .task(id: LoadID(
            language: effectiveLanguage,
            workspaceID: model.workspace.id, file: file, scope: model.diffScope,
            isCollapsed: isCollapsed, ignoringWhitespace: ignoresWhitespace,
            imageRevision: ImageDiff.isOffered(path: file.path, isBinary: file.isBinary)
                ? model.viewedRevisions[file.path] : nil
        )) {
            guard !isCollapsed else {
                priming?.cancel()
                return
            }
            await load()
        }
        .task(id: WrapRequest(width: embeddedWidth, revision: rowRevision, collapsed: isCollapsed)) {
            await prepareWrappedRows()
        }
        .onChange(of: isSideBySide) { _, _ in rebuild() }
        .onChange(of: fileComments) { _, _ in rebuild() }
        .onChange(of: draftSelection) { _, _ in rebuild() }
        .onChange(of: model.changesGeneration) { _, _ in refreshWorktreeCopy() }
        .onChange(of: isEditable) { _, editable in
            if !editable { mode = .diff }
        }
        .onDisappear {
            priming?.cancel()
            if case .image = phase {
                phase = .loading
                presented = nil
            }
            if navigationTarget { onNavigationLayout?(false) }
        }
        .alert(
            revertAlert?.title ?? "",
            isPresented: $revertAlert.isPresent(),
            presenting: revertAlert
        ) { _ in
        } message: { alert in
            Text(alert.message)
        }
        .confirmation($discarding) { pending in
            pending.question.confirmation
        } onConfirm: { pending in
            switch pending.target {
            case .draft:
                discardDraft()
            case let .edit(id):
                closeEdit(of: id)
            }
        }
    }

    private var fileHeader: some View {
        FileHeaderBar(
            model: model, file: file, session: session, diff: source,
            mode: $mode, isEditable: isEditable, onRevert: revert,
            isCollapsed: isCollapsed, onToggleCollapsed: onToggleCollapsed,
            showsMarkdownPreview: showsMarkdownPreview,
            onToggleMarkdownPreview: markdownPreviewAction
        )
    }

    private var markdownPreviewAction: (() -> Void)? {
        guard MarkdownPreview.isOffered(path: file.path, isBinary: file.isBinary, change: file.change) else {
            return nil
        }
        return {
            let collapsed = isCollapsed
            if collapsed { onToggleCollapsed?() }
            showsMarkdownPreview = MarkdownPreview.isShown(afterToggling: showsMarkdownPreview, collapsed: collapsed)
        }
    }

    @ViewBuilder
    private var fileContent: some View {
        MarkdownPreviewContent(
            path: absolutePath, revision: model.changesGeneration,
            height: embeddedWidth == nil ? nil : 480,
            isPresented: $showsMarkdownPreview
        ) {
            sourceContent
        }
        .markdownLinkActions(TranscriptLink.actions(for: model, opensSourceLinks: false))
    }

    @ViewBuilder
    private var sourceContent: some View {
        switch mode {
        case .diff:
            content
                .frame(maxWidth: .infinity, maxHeight: embeddedWidth == nil ? .infinity : nil)
                .alert(
                    "Cannot edit these lines",
                    isPresented: $editProblem.isPresent(),
                    presenting: editProblem
                ) { _ in
                } message: { problem in
                    Text(problem)
                }
                .confirmation($discardingEdit) { _ in
                    Confirmation(
                        title: DiffEdit.Discard.title,
                        message: DiffEdit.Discard.message,
                        confirmLabel: DiffEdit.Discard.confirmLabel,
                        cancelLabel: DiffEdit.Discard.cancelLabel
                    )
                } onConfirm: { _ in
                    closeEdit()
                }
        case .edit:
            FileEditPane(model: model, path: file.path, session: session)
                .frame(height: embeddedWidth == nil ? nil : 400)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var shortcut: some View {
        Button("Toggle Diff and Edit") {
            guard isEditable else { return }
            mode = mode == .diff ? .edit : .diff
        }
        .keyboardShortcut("e", modifiers: .command)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            LoadingView("Reading the diff")
                .frame(
                    maxWidth: .infinity, minHeight: loadingMinHeight,
                    maxHeight: .infinity
                )
        case let .notice(symbol, title, detail):
            placeholder(symbol: symbol, title: title, detail: detail)
        case let .gated(fileDiff, changed, ignoringWhitespace):
            gate(fileDiff, changed: changed, ignoringWhitespace: ignoringWhitespace)
        case let .ready(document):
            diff(document)
        case let .image(sides):
            ImageDiffView(filename: file.filename, sides: sides, isEmbedded: embeddedWidth != nil)
        }
    }

    private func load() async {
        priming?.cancel()
        let ignoringWhitespace = ignoresWhitespace
        if let preparedWhitespace, preparedWhitespace != ignoringWhitespace {
            expandedRuns = []
            revealedGaps = [:]
        }

        if case let .ready(document) = phase, rows.isEmpty {
            rebuild()
            prime(document)
        }
        if presented != file.path {
            phase = .loading
            rows = []
            expandedRuns = []
            revealedGaps = [:]
            fileLines = nil
            source = nil
            isEditable = false
        }

        let patch = await model.patch(for: file)
        guard !Task.isCancelled else { return }
        let path = file.path
        let parsed = await Task.detached(priority: .userInitiated) {
            DiffDocument.parse(patch: patch, path: path)
        }.value

        guard !Task.isCancelled else { return }

        presented = file.path

        guard let parsed else {
            phase = .notice(
                symbol: "doc.plaintext",
                title: "No diff",
                detail: "Git reported no changes for this file."
            )
            return
        }
        if showsImage(of: parsed) || parsed != source || preparedWhitespace != ignoringWhitespace || presentedLanguage != effectiveLanguage {
            await apply(parsed, ignoringWhitespace: ignoringWhitespace)
            guard !Task.isCancelled else { return }
            source = parsed
            preparedWhitespace = ignoringWhitespace
        }

        let absolute = absolutePath
        let binary = file.isBinary
        let editable = await Task.detached(priority: .utility) {
            !binary && FileEditor.isEditable(absolute)
        }.value
        guard !Task.isCancelled else { return }
        isEditable = editable
        if case let .ready(document) = phase { await checkHunks(in: document.file) }
    }

    private func checkHunks(in diff: FileDiff) async {
        let found = await model.hunkRefusals(for: file, in: diff)
        guard !Task.isCancelled, found != refusedHunks else { return }
        refusedHunks = found
    }

    private func apply(_ raw: FileDiff, ignoringWhitespace: Bool) async {
        let fileDiff = ignoringWhitespace ? raw.ignoringWhitespace() : raw

        if ignoringWhitespace, fileDiff.hunks.isEmpty, !raw.hunks.isEmpty {
            phase = .notice(
                symbol: "paragraphsign",
                title: "Only whitespace changed",
                detail: "Every change to \(file.filename) is indentation or trailing space."
            )
            return
        }
        if showsImage(of: fileDiff) {
            let sides = await model.imageSides(for: file)
            guard !Task.isCancelled else { return }
            if !sides.columns.isEmpty {
                phase = .image(sides)
                return
            }
        }
        if let notice = Self.notice(for: fileDiff, file: file) {
            phase = notice
            return
        }

        let changed = fileDiff.additions + fileDiff.deletions
        if changed > Self.largeDiffLimit {
            phase = .gated(fileDiff, changed: changed, ignoringWhitespace: ignoringWhitespace)
            return
        }
        await present(fileDiff, raw: raw, ignoringWhitespace: ignoringWhitespace)
    }

    private var loadingMinHeight: CGFloat? {
        guard embeddedWidth != nil else { return nil }
        return ImageDiff.isOffered(path: file.path, isBinary: file.isBinary) ? ImageDiffView.embeddedHeight : 120
    }

    private func showsImage(of fileDiff: FileDiff) -> Bool {
        ImageDiff.isOffered(path: file.path, isBinary: fileDiff.isBinary || file.isBinary)
    }

    private func revert() {
        Task {
            revertAlert = await model.revert(file)
        }
    }

    private func ask(_ hunk: DiffHunk, in diff: FileDiff) {
        Task {
            stagedHunk = await model.stagedHunk(hunk, of: file, in: diff)
            pendingHunk = hunk
        }
    }

    private func discard(_ hunk: DiffHunk, in diff: FileDiff) {
        Task { revertAlert = await model.discard(hunk, of: file, in: diff) }
    }

    private func present(
        _ fileDiff: FileDiff, raw: FileDiff? = nil, ignoringWhitespace: Bool? = nil
    ) async {
        let whitespace = ignoringWhitespace ?? ignoresWhitespace
        guard whitespace == ignoresWhitespace else { return }
        let path = file.path
        let worktree = model.workspace.path
        let language = effectiveLanguage
        let prepared = await Task.detached(priority: .userInitiated) {
            (
                document: DiffDocument.prepare(file: fileDiff, path: path, language: language),
                lines: WorkspaceModel.contents(of: path, in: worktree)
                    .map(ReviewCommentAnchor.split)
            )
        }.value

        guard !Task.isCancelled, whitespace == ignoresWhitespace, language == effectiveLanguage else { return }

        let document = prepared.document
        fileLines = prepared.lines
        phase = .ready(document)
        if SourceEditorState.file(absolutePath).diffRequest != nil {
            expandedRuns.formUnion(document.file.hunks.flatMap(\.lines).map(\.index))
        }
        model.holdDiff(
            DiffPresentation(source: raw ?? source ?? fileDiff, document: document, lines: prepared.lines),
            for: file,
            ignoringWhitespace: whitespace
        )
        rebuild()
        prime(document)
    }

    private static let primeLimit = 600

    private func prime(_ document: DiffDocument) {
        let language = document.language
        let lines = document.linesToPrime(limit: Self.primeLimit)
        priming?.cancel()
        priming = Task.detached(priority: .utility) {
            for line in lines {
                guard !Task.isCancelled else { return }
                _ = SyntaxCache.attributed(line: DiffLineDisplay.text(line.text), language: language, carry: line.carry)
            }
        }
    }

    private static func notice(for fileDiff: FileDiff, file: ChangedFile) -> Phase? {
        if fileDiff.isBinary || file.isBinary {
            return .notice(
                symbol: "shippingbox",
                title: "Binary file",
                detail: "\(file.filename) changed. Binary content is not shown."
            )
        }
        guard fileDiff.hunks.isEmpty else { return nil }

        if fileDiff.isRename {
            let from = fileDiff.oldPath ?? file.oldPath ?? "somewhere else"
            return .notice(
                symbol: "arrow.uturn.right",
                title: "Renamed",
                detail: "Moved from \(from) with no change to its contents."
            )
        }
        if fileDiff.isModeChangeOnly {
            let from = fileDiff.oldMode ?? "unknown"
            let to = fileDiff.newMode ?? "unknown"
            return .notice(
                symbol: "lock.shield",
                title: "Mode changed",
                detail: "File mode went from \(from) to \(to). The contents are identical."
            )
        }
        if fileDiff.isNew {
            return .notice(
                symbol: "doc.badge.plus",
                title: "New empty file",
                detail: "\(file.filename) was added with no content."
            )
        }
        if fileDiff.isDeleted {
            return .notice(
                symbol: "trash",
                title: "Deleted",
                detail: "\(file.filename) was removed."
            )
        }
        return .notice(
            symbol: "equal.circle",
            title: "No textual changes",
            detail: "Git found nothing to show for \(file.filename)."
        )
    }

    private func placeholder(symbol: String, title: String, detail: String) -> some View {
        EmptyStateView(glyph: symbol, title: title, message: detail)
            .frame(minHeight: embeddedWidth == nil ? nil : 160)
    }

    private func gate(_ fileDiff: FileDiff, changed: Int, ignoringWhitespace: Bool) -> some View {
        EmptyStateView(
            glyph: "doc.text.magnifyingglass",
            title: "\(changed.formatted()) changed lines",
            message: "Highlighting a diff this size takes a moment.",
            actionTitle: "Show anyway",
            action: { Task { await present(fileDiff, ignoringWhitespace: ignoringWhitespace) } }
        )
        .frame(minHeight: embeddedWidth == nil ? nil : 160)
    }

    @ViewBuilder
    private func diff(_ document: DiffDocument) -> some View {
        if let embeddedWidth {
            if let prepared = wrappedPresentation {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(prepared.rows) { row in
                        let tracksRow = isDiffDestination(row) && navigationTarget
                        Group {
                            if let heights = prepared.heights[row.id], defersDistantBlocks {
                                ReviewDiffBlock(height: heights.reduce(0, +)) {
                                    rowView(row, document: prepared.document, width: prepared.width, wrappedHeights: heights)
                                }
                            } else {
                                rowView(row, document: prepared.document, width: prepared.width)
                            }
                        }
                        .id(diffDestinationID(row))
                        .onGeometryChange(for: CGRect?.self) { proxy in
                            tracksRow ? proxy.frame(in: .scrollView(axis: .vertical)) : nil
                        } action: { frame in
                            if frame != nil { onNavigationLayout?(true) }
                        }
                    }
                }
                .id(prepared.document.file)
                .frame(width: embeddedWidth, alignment: .leading)
                .frame(minHeight: prepared.codeHeight, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
                .clipped()
                .disabled(prepared.revision != rowRevision)
                .allowsHitTesting(prepared.revision == rowRevision)
            } else {
                LoadingView("Laying out the diff")
                    .frame(width: embeddedWidth, height: 120)
            }
        } else {
            standaloneDiff(document)
        }
    }

    private var findMatches: [DiffLine] {
        guard !findText.isEmpty else { return [] }
        return source?.hunks.flatMap(\.lines).filter { $0.text.localizedCaseInsensitiveContains(findText) } ?? []
    }

    private var selectedFind: DiffLine? {
        let matches = findMatches
        return matches.isEmpty ? nil : matches[min(findIndex, matches.count - 1)]
    }

    private var diffFindBar: some View {
        HStack(spacing: InspectorLayout.gap) {
            Button { SourceNavigation.shared.move(-1, in: model) } label: { Image(systemName: "chevron.left") }
                .disabled(SourceNavigation.shared.histories[model.workspace.id]?.canGoBack != true).help("Go back")
            Button { SourceNavigation.shared.move(1, in: model) } label: { Image(systemName: "chevron.right") }
                .disabled(SourceNavigation.shared.histories[model.workspace.id]?.canGoForward != true).help("Go forward")
            TextField("Find in diff", text: $findText).textFieldStyle(.roundedBorder).focused($findFocused)
                .onSubmit { stepFind(1) }
            Text("\(findMatches.isEmpty ? 0 : min(findIndex + 1, findMatches.count))/\(findMatches.count)")
                .font(Typo.caption).monospacedDigit()
            Button { stepFind(-1) } label: { Image(systemName: "chevron.up") }.disabled(findMatches.isEmpty).help("Previous match")
            Button { stepFind(1) } label: { Image(systemName: "chevron.down") }.disabled(findMatches.isEmpty).help("Next match")
            Button("Open source") {
                FileReview.open(location: CodeLocation(path: file.path,
                    line: selectedFind?.newNumber ?? SourceEditorState.file(absolutePath).diffLine), in: model)
            }.disabled(!isEditable)
        }
        .buttonStyle(.borderless).controlSize(.small)
        .padding(.horizontal, InspectorLayout.inset).frame(height: InspectorLayout.barHeight)
        .onChange(of: findText) { _, _ in
            findIndex = 0
            rebuild()
            findRevision += 1
        }
    }

    private func stepFind(_ delta: Int) {
        guard !findMatches.isEmpty else { return }
        findIndex = (findIndex + delta + findMatches.count) % findMatches.count
        findRevision += 1
    }

    private func isDiffDestination(_ row: DiffRow) -> Bool {
        guard let destination = SourceEditorState.file(absolutePath).diffRequest else { return false }
        return row.sourceLines.contains { $0.kind != .deletion && $0.newNumber == destination.line }
    }

    private func diffDestinationID(_ row: DiffRow) -> String {
        if isDiffDestination(row), let destination = SourceEditorState.file(absolutePath).diffRequest {
            return "\(file.path):definition:\(destination.line)"
        }
        return "\(file.path):\(row.id)"
    }

    private func standaloneDiff(_ document: DiffDocument) -> some View {
        VStack(spacing: 0) {
            diffFindBar
            GeometryReader { proxy in
                let width = proxy.size.width
                let selectedIndex = selectedFind?.index
                ScrollViewReader { reader in
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(rows) { row in
                                rowView(row, document: document, width: width,
                                        wrappedHeights: standaloneHeights.measurement(
                                            for: row.id, revision: rowRevision, width: width
                                        ) { wrappedHeights(for: row, width: width) })
                                    .background(row.sourceLines.contains { $0.index == selectedIndex }
                                        ? Color.accentColor.opacity(0.16) : .clear)
                                    .contextMenu {
                                        if let line = row.sourceLines.compactMap(\.newNumber).first {
                                            Button("Open source at line \(line)") {
                                                FileReview.open(location: CodeLocation(path: file.path, line: line), in: model)
                                            }
                                        }
                                    }
                                    .id(row.id)
                            }
                        }
                        .scrollTargetLayout()
                        .id(document.file)
                        .frame(width: width, alignment: .leading)
                    }
                    .scrollPosition(id: Binding(get: { SourceEditorState.file(absolutePath).diffRow }, set: { id in
                        let state = SourceEditorState.file(absolutePath)
                        state.diffRow = id
                        if let line = rows.first(where: { $0.id == id })?.sourceLines.compactMap(\.newNumber).first {
                            state.diffLine = line
                        }
                    }), anchor: .topLeading)
                    .defaultScrollAnchor(.topLeading)
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: SourceEditorState.file(absolutePath).diffRevision, initial: true) { _, _ in
                        if let row = rows.first(where: isDiffDestination) { reader.scrollTo(row.id, anchor: Self.leadingCentre) }
                    }
                    .onChange(of: rowRevision) { _, _ in
                        if pendingDiffNavigation, let row = rows.first(where: isDiffDestination) {
                            reader.scrollTo(row.id, anchor: Self.leadingCentre)
                        }
                    }
                    .onScrollPhaseChange { _, phase in
                        if phase == .tracking || phase == .interacting || phase == .decelerating { pendingDiffNavigation = false }
                    }
                    .onChange(of: findRevision) { _, _ in
                        if let match = selectedFind, let row = rows.first(where: { $0.sourceLines.contains { $0.index == match.index } }) {
                            reader.scrollTo(row.id, anchor: Self.leadingCentre)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(
        _ row: DiffRow, document: DiffDocument, width: CGFloat, wrappedHeights: [CGFloat]? = nil
    ) -> some View {
        if let wrappedHeights {
            wrappedRow(row, document: document, width: width, heights: wrappedHeights)
        } else {
            switch row {
            case let .header(hunkIndex, text):
                let hunk = document.file.hunks.indices.contains(hunkIndex) ? document.file.hunks[hunkIndex] : nil
                DiffHunkHeaderView(
                    text: text, width: width, path: file.path,
                    discard: hunk == nil
                        ? .hidden
                        : model.hunkDiscard(
                            for: file, in: document.file, ignoringWhitespace: ignoresWhitespace,
                            staged: hunk.flatMap { refusedHunks[$0] } ?? .clean
                        ),
                    hunk: hunk,
                    isConfirming: Binding(
                        get: { hunk != nil && pendingHunk == hunk },
                        set: { pendingHunk = $0 ? hunk : nil }
                    ),
                    staged: stagedHunk,
                    onAsk: { if let hunk { ask(hunk, in: document.file) } },
                    onRecheck: {
                        if let hunk, refusedHunks[hunk] != nil { Task { await checkHunks(in: document.file) } }
                    },
                    onDiscard: { if let asked = pendingHunk { discard(asked, in: document.file) } }
                )

            case let .runExpander(runID, hidden):
                DiffExpanderView(title: "Expand \(Counted.of(hidden, "line"))", width: width) {
                    expandedRuns.insert(runID)
                    rebuild()
                }

            case let .gapExpander(gapID, hidden):
                DiffExpanderView(
                    title: "Expand \(Counted.of(min(hidden, Self.gapStep), "line"))", width: width
                ) {
                    revealedGaps[gapID, default: 0] += min(hidden, Self.gapStep)
                    rebuild()
                }

            case let .line(line):
                side(line, document: document, numbers: .both, width: width)

            case let .commentBand(placement):
                ReviewCommentBandView(
                    placement: placement,
                    width: width,
                    editing: editBinding(for: placement.comment.id),
                    onBeginEdit: { beginEdit(of: placement.comment) },
                    onCommitEdit: { commitEdit(of: placement.comment) },
                    onCancelEdit: { cancelEdit(of: placement.comment) },
                    onRemove: {
                        let model = model
                        Task { await model.removeReviewComment(id: placement.comment.id) }
                    }
                )

            case .commentEditor:
                ReviewCommentEditorView(
                    text: Binding(
                        get: { model.reviewText.drafts[file.path] ?? "" },
                        set: { model.reviewText.drafts[file.path] = $0 }
                    ),
                    width: width,
                    onCommit: commitDraft,
                    onCancel: cancelDraft
                )

            case let .lineEditor(region):
                DiffEditBandView(
                    region: region,
                    text: edits.binding(for: absolutePath),
                    language: document.language,
                    status: edits.editor(for: absolutePath)?.status ?? .editing,
                    width: width,
                    onSave: saveEdit,
                    onCancel: cancelEdit
                )

            case let .pair(pair):
                HStack(spacing: 0) {
                    let half = (width - Metrics.hairline) / 2
                    side(pair.left, document: document, numbers: .old, width: half)
                    Hairline(axis: .vertical)
                    side(pair.right, document: document, numbers: .new, width: half)
                }

            case let .lineRun(lines):
                run(lines.map(Optional.some), document: document, numbers: .both, width: width)

            case let .pairRun(pairs):
                HStack(spacing: 0) {
                    let half = (width - Metrics.hairline) / 2
                    run(pairs.map(\.left), document: document, numbers: .old, width: half)
                    Hairline(axis: .vertical)
                    run(pairs.map(\.right), document: document, numbers: .new, width: half)
                }
            }
        }
    }

    private func prepareWrappedRows() async {
        guard let width = embeddedWidth, !isCollapsed, case let .ready(document) = phase else { return }
        let currentRows = rows
        let revision = rowRevision
        var heights: [String: [CGFloat]] = [:]
        for row in currentRows {
            guard !Task.isCancelled else { return }
            if let measured = wrappedHeights(for: row, width: width) { heights[row.id] = measured }
            await Task.yield()
        }
        guard !Task.isCancelled else { return }
        wrappedPresentation = WrappedPresentation(
            revision: revision, document: document, rows: currentRows, width: width, heights: heights,
            codeHeight: heights.values.reduce(0) { $0 + $1.reduce(0, +) }
        )
        onPrepared?()
        #if DEBUG
        if CommandLine.arguments.contains("--review-run-probe") {
            ReviewRunProbe.preparedLayouts[file.path] = "rows=\(currentRows.count), blocks=\(heights.count), height=\(heights.values.flatMap { $0 }.reduce(0, +)), width=\(width)"
        }
        #endif
    }

    private func wrappedHeights(for row: DiffRow, width: CGFloat) -> [CGFloat]? {
        func height(_ line: DiffLine?, numbers: DiffGutter.Numbers, width: CGFloat) -> CGFloat {
            let codeWidth = floor(max(1, width - DiffGutter.width(for: numbers)
                - CodeMetrics.markerWidth - CodeMetrics.gutterPadding))
            return WrappedCodeLayout.height(of: DiffLineDisplay.text(line?.text ?? ""), width: codeWidth)
        }
        func pairHeight(_ pair: SideBySideRow) -> CGFloat {
            let half = (width - Metrics.hairline) / 2
            return max(height(pair.left, numbers: .old, width: half),
                       height(pair.right, numbers: .new, width: half))
        }
        switch row {
        case let .line(line) where line.kind != .noNewline:
            return [height(line, numbers: .both, width: width)]
        case let .lineRun(lines):
            return lines.map { height($0, numbers: .both, width: width) }
        case let .pair(pair) where pair.left?.kind != .noNewline && pair.right?.kind != .noNewline:
            return [pairHeight(pair)]
        case let .pairRun(pairs):
            return pairs.map(pairHeight)
        default:
            return nil
        }
    }

    @ViewBuilder
    private func wrappedRow(_ row: DiffRow, document: DiffDocument, width: CGFloat, heights: [CGFloat]) -> some View {
        switch row {
        case let .line(line):
            run([line], document: document, numbers: .both, width: width, wrappedHeights: heights)
        case let .lineRun(lines):
            run(lines, document: document, numbers: .both, width: width, wrappedHeights: heights)
        case let .pair(pair):
            wrappedPairs([pair], document: document, width: width, heights: heights)
        case let .pairRun(pairs):
            wrappedPairs(pairs, document: document, width: width, heights: heights)
        default:
            EmptyView()
        }
    }

    private func wrappedPairs(
        _ pairs: [SideBySideRow], document: DiffDocument, width: CGFloat, heights: [CGFloat]
    ) -> some View {
        let half = (width - Metrics.hairline) / 2
        return HStack(spacing: 0) {
            run(pairs.map(\.left), document: document, numbers: .old, width: half, wrappedHeights: heights)
            Hairline(axis: .vertical)
            run(pairs.map(\.right), document: document, numbers: .new, width: half, wrappedHeights: heights)
        }
    }

    private func isCurrent(_ displayed: DiffDocument) -> Bool {
        guard case let .ready(current) = phase else { return false }
        return current.file == displayed.file
    }

    private func run(
        _ lines: [DiffLine?],
        document: DiffDocument,
        numbers: DiffLineView.Numbers,
        width: CGFloat,
        wrappedHeights: [CGFloat]? = nil
    ) -> some View {
        DiffRunView(
            lines: lines.map { line in
                DiffRunLine(
                    line: line,
                    carry: line.flatMap { document.carries[$0.index] } ?? LexState(),
                    emphasis: line.flatMap { document.emphasis[$0.index] } ?? [],
                    isCommented: isCommented(line, numbers: numbers)
                )
            },
            language: document.language,
            numbers: numbers,
            width: width,
            wrappedHeights: wrappedHeights,
            lookupRevision: rowRevision,
            onLookup: { view, offset, references, automatic, newTab in
                guard isCurrent(document), let fileLines else { return }
                SourceActions.lookupInDiff(at: offset, view: view, lines: lines, source: fileLines.joined(separator: "\n"),
                    path: file.path, model: model, references: references, automatic: automatic, newTab: newTab) { location, newTab in
                    guard isCurrent(document) else { return }
                    SourceEditorState.file(absolutePath).navigationTask = Task {
                        await FileReview.openFromDiff(location, in: model, newTab: newTab)
                    }
                }
            },
            destination: SourceEditorState.file(absolutePath).diffRequest,
            onComment: { if isCurrent(document) { beginDraft(at: $0) } },
            onDragComment: { if isCurrent(document) { extendDrag(from: $0, to: $1) } },
            onEndCommentDrag: {
                if isCurrent(document) { finishDrag() } else { rangeDrag = nil }
            },
            onEdit: { if isCurrent(document) { beginEdit(at: $0) } }
        )
        .equatable()
    }

    @ViewBuilder
    private func side(
        _ line: DiffLine?,
        document: DiffDocument,
        numbers: DiffLineView.Numbers,
        width: CGFloat
    ) -> some View {
        if line?.kind == .noNewline {
            DiffLineView(line: line, language: document.language, numbers: numbers, width: width)
        } else {
            run([line], document: document, numbers: numbers, width: width)
        }
    }

    private var fileComments: [ReviewComment] {
        model.reviewComments.filter { $0.filePath == file.path }
    }

    private func spots(of line: DiffLine, numbers: DiffLineView.Numbers) -> [ReviewSpot] {
        var result: [ReviewSpot] = []
        if numbers != .new, let old = line.oldNumber {
            result.append(ReviewSpot(side: .old, line: old))
        }
        if numbers != .old, let new = line.newNumber {
            result.append(ReviewSpot(side: .new, line: new))
        }
        return result
    }

    private func isCommented(_ line: DiffLine?, numbers: DiffLineView.Numbers) -> Bool {
        guard let line else { return false }
        let rowSpots = spots(of: line, numbers: numbers)
        if rowSpots.contains(where: { commentedSpots.contains($0) }) { return true }
        guard let rangeDrag else { return false }
        return rowSpots.contains { rangeDrag.contains($0) }
    }

    private func beginDraft(at spot: ReviewSpot) {
        beginDraft(selection: ReviewSelection(spot))
    }

    private func beginDraft(selection: ReviewSelection) {
        guard case let .ready(document) = phase,
              let anchor = ReviewCapture.anchor(
                at: selection, hunks: document.file.hunks, fileLines: fileLines
              )
        else { return }
        model.reviewDrafts[file.path] = ReviewDraft(selection: selection, anchor: anchor)
    }

    private func extendDrag(from anchor: ReviewSpot, to target: ReviewSpot) {
        guard let selection = ReviewSelection(from: anchor, to: target) else { return }
        if rangeDrag != selection { rangeDrag = selection }
    }

    private func finishDrag() {
        guard let selection = rangeDrag else { return }
        rangeDrag = nil
        beginDraft(selection: selection)
    }

    private func cancelDraft() {
        guard let question = ReviewCommentDiscard.needed(
            closing: model.reviewText.drafts[file.path] ?? "", replacing: nil
        ) else {
            discardDraft()
            return
        }
        discarding = PendingDiscard(target: .draft, question: question)
    }

    private func discardDraft() {
        model.reviewDrafts[file.path] = nil
        model.reviewText.drafts[file.path] = nil
    }

    private func commitDraft() {
        guard let draft else { return }
        let body = (model.reviewText.drafts[file.path] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            discardDraft()
            return
        }
        discardDraft()
        let model = model
        let path = file.path
        Task {
            await model.addReviewComment(
                filePath: path, selection: draft.selection, anchor: draft.anchor, body: body
            )
        }
    }

    private var editRegion: DiffEditRegion? { edits.editor(for: absolutePath)?.region }

    private func beginEdit(at line: Int) {
        guard case let .ready(document) = phase else { return }

        guard !session.isDirty(absolutePath) else {
            editProblem = "\(file.filename) has unsaved changes open in Edit mode. "
                + "Save or discard those first."
            return
        }

        let hunks = document.file.hunks
        let path = absolutePath
        Task {
            if let problem = await edits.begin(path: path, at: line, hunks: hunks) {
                editProblem = problem
            }
            rebuild()
        }
    }

    private func saveEdit() {
        let path = absolutePath
        Task {
            let saved = await edits.save(path: path)
            rebuild()
            guard saved else { return }
            model.forgetHeldDiff(for: file.path)
            await model.refreshChanges()
            await load()
        }
    }

    private func cancelEdit() {
        guard let region = editRegion else { return }
        guard DiffEdit.Discard.needed(closing: edits.text(for: absolutePath), of: region) else {
            closeEdit()
            return
        }
        discardingEdit = region
    }

    private func closeEdit() {
        edits.close(path: absolutePath)
        rebuild()
    }

    private func editBinding(for id: ReviewCommentID) -> Binding<String>? {
        guard model.reviewEdits.contains(id) else { return nil }
        return Binding(
            get: { model.reviewText.edits[id] ?? "" },
            set: { model.reviewText.edits[id] = $0 }
        )
    }

    private func beginEdit(of comment: ReviewComment) {
        guard !model.reviewEdits.contains(comment.id) else { return }
        model.reviewText.edits[comment.id] = comment.body
        model.reviewEdits.insert(comment.id)
    }

    private func cancelEdit(of comment: ReviewComment) {
        guard let question = ReviewCommentDiscard.needed(
            closing: model.reviewText.edits[comment.id] ?? "", replacing: comment.body
        ) else {
            closeEdit(of: comment.id)
            return
        }
        discarding = PendingDiscard(target: .edit(comment.id), question: question)
    }

    private func closeEdit(of id: ReviewCommentID) {
        model.reviewEdits.remove(id)
        model.reviewText.edits[id] = nil
    }

    private func commitEdit(of comment: ReviewComment) {
        guard let typed = model.reviewText.edits[comment.id] else { return }
        switch ReviewCommentEdit.outcome(typed: typed, replacing: comment.body) {
        case .refused:
            return
        case .unchanged:
            closeEdit(of: comment.id)
        case let .save(body):
            closeEdit(of: comment.id)
            let model = model
            Task { await model.editReviewComment(id: comment.id, body: body) }
        }
    }

    private func appendAnnotations(_ rows: inout [DiffRow], spots rowSpots: [ReviewSpot]) {
        for spot in rowSpots {
            for placement in placements where placement.band == spot {
                rows.append(.commentBand(placement))
            }
            if draftEditorSpot == spot {
                rows.append(.commentEditor(spot))
            }
            if let region = editRegion, spot.side == .new, spot.line == region.lastLine {
                rows.append(.lineEditor(region))
            }
        }
    }

    private func appendUnplacedComments(_ rows: inout [DiffRow]) {
        for placement in placements where placement.band == nil {
            rows.append(.commentBand(placement))
        }
    }

    private func refreshWorktreeCopy() {
        let isEditing = edits.isOpen(absolutePath)
        guard case .ready = phase, !fileComments.isEmpty || draftSelection != nil || isEditing else {
            return
        }
        let contents = model.contents(of: file.path)
        if isEditing { edits.recheck(path: absolutePath, contents: contents) }
        let fresh = contents.map(ReviewCommentAnchor.split)
        guard fresh != fileLines else { return }
        fileLines = fresh
        rebuild()
    }

    private func revealedContextLines(_ document: DiffDocument) -> [Int: String] {
        guard let fileLines else { return [:] }
        var revealed: [Int: String] = [:]
        let hunks = document.file.hunks
        for index in hunks.indices {
            guard let gap = DiffGap.between(hunks: hunks, at: index) else { continue }
            for number in DiffGap.revealed(revealedGaps[index] ?? 0, in: gap)
            where number >= 1 && number - 1 < fileLines.count {
                revealed[number] = fileLines[number - 1]
            }
        }
        return revealed
    }

    private func rebuild() {
        rowRevision += 1
        guard case let .ready(document) = phase else {
            rows = []
            placements = []
            commentedSpots = []
            return
        }
        placements = ReviewPlacements.place(
            fileComments,
            in: document.file,
            currentLines: fileLines,
            revealedNewLines: revealedContextLines(document)
        )
        var spots = Set(placements.flatMap(\.covered))
        if let draftSelection { spots.formUnion(draftSelection.spots) }
        commentedSpots = spots
        rows = DiffRow.grouped(isSideBySide ? splitRows(document) : unifiedRows(document),
                               stoppingAt: SourceEditorState.file(absolutePath).diffRequest?.line)

        if let draftEditorSpot, !rows.contains(where: {
            if case .commentEditor = $0 { return true } else { return false }
        }) {
            rows.insert(.commentEditor(draftEditorSpot), at: 0)
        }

        if let region = editRegion, !rows.contains(where: {
            if case .lineEditor = $0 { return true } else { return false }
        }) {
            rows.insert(.lineEditor(region), at: 0)
        }
    }

    private func unifiedRows(_ document: DiffDocument) -> [DiffRow] {
        var rows: [DiffRow] = []
        appendUnplacedComments(&rows)

        for (hunkIndex, hunk) in document.file.hunks.enumerated() {
            appendGap(&rows, document: document, hunkIndex: hunkIndex, hunk: hunk, split: false)
            appendHeading(&rows, document: document, hunkIndex: hunkIndex)

            let lines = hunk.lines
            for chunk in Self.chunks(
                count: lines.count,
                isContext: { lines[$0].kind == .context },
                runID: { lines[$0].index },
                expanded: findText.isEmpty ? expandedRuns : Set(document.file.hunks.flatMap(\.lines).map(\.index))
            ) {
                switch chunk {
                case let .visible(range):
                    for offset in range {
                        rows.append(.line(lines[offset]))
                        appendAnnotations(&rows, spots: spots(of: lines[offset], numbers: .both))
                    }
                case let .hidden(runID, count):
                    rows.append(.runExpander(runID: runID, hidden: count))
                }
            }
        }
        return rows
    }

    private func splitRows(_ document: DiffDocument) -> [DiffRow] {
        var rows: [DiffRow] = []
        appendUnplacedComments(&rows)

        for (hunkIndex, hunk) in document.file.hunks.enumerated() {
            appendGap(&rows, document: document, hunkIndex: hunkIndex, hunk: hunk, split: true)
            appendHeading(&rows, document: document, hunkIndex: hunkIndex)

            var single = document.file
            single.hunks = [hunk]
            let pairs = single.sideBySide()

            for chunk in Self.chunks(
                count: pairs.count,
                isContext: { pairs[$0].left?.kind == .context },
                runID: { pairs[$0].left?.index ?? pairs[$0].index },
                expanded: findText.isEmpty ? expandedRuns : Set(document.file.hunks.flatMap(\.lines).map(\.index))
            ) {
                switch chunk {
                case let .visible(range):
                    for offset in range {
                        rows.append(.pair(pairs[offset]))
                        var rowSpots: [ReviewSpot] = []
                        if let left = pairs[offset].left {
                            rowSpots += spots(of: left, numbers: .old)
                        }
                        if let right = pairs[offset].right {
                            rowSpots += spots(of: right, numbers: .new)
                        }
                        appendAnnotations(&rows, spots: rowSpots)
                    }
                case let .hidden(runID, count):
                    rows.append(.runExpander(runID: runID, hidden: count))
                }
            }
        }
        return rows
    }

    private func appendGap(
        _ rows: inout [DiffRow],
        document: DiffDocument,
        hunkIndex: Int,
        hunk: DiffHunk,
        split: Bool
    ) {
        guard let fileLines else { return }

        guard let gap = DiffGap.between(hunks: document.file.hunks, at: hunkIndex) else { return }

        let requested = revealedGaps[hunkIndex] ?? 0
        let hidden = DiffGap.hidden(requested, in: gap)
        if hidden > 0 {
            rows.append(.gapExpander(gapID: hunkIndex, hidden: hidden))
        }
        let revealed = DiffGap.revealed(requested, in: gap)
        guard !revealed.isEmpty else { return }

        let offset = hunk.oldStart - hunk.newStart
        for number in revealed {
            guard number >= 1, number - 1 < fileLines.count else { continue }
            let line = DiffLine(
                kind: .context,
                text: fileLines[number - 1],
                oldNumber: number + offset,
                newNumber: number,
                index: -number - 1
            )
            if split {
                rows.append(.pair(SideBySideRow(left: line, right: line, index: line.index)))
            } else {
                rows.append(.line(line))
            }
            appendAnnotations(&rows, spots: spots(of: line, numbers: .new))
        }
    }

    private func appendHeading(
        _ rows: inout [DiffRow],
        document: DiffDocument,
        hunkIndex: Int
    ) {
        guard let text = DiffHunkHeading.text(
            for: document.file.hunks, at: hunkIndex, revealed: revealedGaps[hunkIndex] ?? 0,
            carriesActions: HunkDiscard.offers(file, in: document.file)
        ) else { return }
        rows.append(.header(hunk: hunkIndex, text: text))
    }

    private enum Chunk {
        case visible(Range<Int>)
        case hidden(runID: Int, count: Int)
    }

    private static func chunks(
        count: Int,
        isContext: (Int) -> Bool,
        runID: (Int) -> Int,
        expanded: Set<Int>
    ) -> [Chunk] {
        var chunks: [Chunk] = []
        var pending = 0
        var index = 0

        while index < count {
            guard isContext(index) else {
                index += 1
                continue
            }
            var end = index
            while end < count, isContext(end) { end += 1 }

            let length = end - index
            let id = runID(index)
            if length > collapseThreshold, !expanded.contains(id) {
                chunks.append(.visible(pending..<(index + keptContext)))
                chunks.append(.hidden(runID: id, count: length - keptContext * 2))
                pending = end - keptContext
            }
            index = end
        }

        if pending < count { chunks.append(.visible(pending..<count)) }
        return chunks
    }
}
