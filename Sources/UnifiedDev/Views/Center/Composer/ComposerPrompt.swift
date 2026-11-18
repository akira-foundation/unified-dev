import SwiftUI
import AppKit
import Core

struct ComposerPrompt<Footer: View>: View {
    @Binding var text: String
    @Binding var caret: Int
    @Binding var isFocused: Bool

    var mentionRoot: String
    var attachmentRoot: String
    var attachmentKey: String

    var reviewComments: [ReviewComment] = []
    var onRemoveReviewComment: @MainActor (ReviewCommentID) -> Void = { _ in }
    var onOpenReviewComment: @MainActor (ReviewComment) -> Void = { _ in }

    var replyQuotes: [ReplyQuote] = []
    var onRemoveReplyQuote: @MainActor (ReplyQuoteID) -> Void = { _ in }
    var onOpenReplyQuote: @MainActor (ReplyQuote) -> Void = { _ in }

    var placeholder: String = ComposerEditor.chatPlaceholder
    var editorHeight: CGFloat
    var onContentHeightChange: @MainActor (CGFloat) -> Void
    var onKey: @MainActor (ComposerKey) -> Bool
    var onOpenAttachment: @MainActor (PromptAttachment) -> Void
    var onOpenCommand: (@MainActor (String) -> Void)?
    var isFloating = false
    var isBusy = false
    var isDraftLoaded = true
    var accountHomes: ComposerAccountHomes?
    @ViewBuilder var footer: (ComposerPromptActions) -> Footer

    @Environment(AppModel.self) private var app

    @State private var hoveredPath: String?
    @State private var isDropTarget = false
    @State private var boxWidth: CGFloat = 0
    @State private var boxTop: CGFloat = 0
    @State private var windowHeight: CGFloat = .infinity

    @State private var editor = ComposerEditorHandle()

    @State private var slashCatalog = SlashCommandCatalog()
    @State private var isCommandPreviewed = false
    @State private var fileMatches: [FileMatch] = []
    @State private var menuIndex = 0
    @State private var isMenuDismissed = false
    @State private var heldKey: String?
    @State private var dropOwner = ""

    private var attachments: [PromptAttachment] {
        PromptAttachmentStore.shared.attachments(for: attachmentKey)
    }

    var body: some View {
        let draft = command
        let menu = ComposerMenu.resolve(draft: draft.body, caret: caret)
        let openMenu = isMenuDismissed ? ComposerMenu.none : menu
        let named = draft.name.flatMap { slashCatalog.command(named: $0) }
        let attachments = self.attachments
        let typedLineBottom = typedLineBottom(hasCommand: draft.name != nil)
        let placement = menuPlacement(typedLineBottom: typedLineBottom)
        let guide = floatingGuide(isBelow: placement.isBelow, typedLineBottom: typedLineBottom)

        return VStack(alignment: .leading, spacing: Metrics.spacingWide) {
            if !reviewComments.isEmpty {
                ChipFlow(spacing: Metrics.spacingSmall, lineSpacing: Metrics.spacingSmall) {
                    ForEach(reviewComments) { comment in
                        ReviewCommentChip(
                            comment: comment,
                            onRemove: { onRemoveReviewComment(comment.id) },
                            onOpen: { onOpenReviewComment(comment) }
                        )
                    }
                }
            }

            if !replyQuotes.isEmpty {
                ChipFlow(spacing: Metrics.spacingSmall, lineSpacing: Metrics.spacingSmall) {
                    ForEach(replyQuotes) { quote in
                        ReplyQuoteCard(
                            quote: quote,
                            onRemove: { onRemoveReplyQuote(quote.id) },
                            onOpen: { onOpenReplyQuote(quote) }
                        )
                    }
                }
            }

            if let name = draft.name {
                HStack(alignment: .top, spacing: Metrics.spacingSmall) {
                    SlashCommandChip(
                        name: name,
                        command: named,
                        onRemove: removeCommand,
                        onOpen: { path in
                            if let onOpenCommand {
                                onOpenCommand(path)
                            } else {
                                Reveal.inEditor(path, repo: nil)
                            }
                        },
                        onHover: { isCommandPreviewed = $0 }
                    )

                    promptEditor(attachments: attachments)
                }
            } else {
                promptEditor(attachments: attachments)
            }

            footer(ComposerPromptActions(attach: attachFiles, insert: insert(quickPrompt:)))
        }
        .composerBox(
            isFocused: $isFocused,
            isDropTarget: isDropTarget,
            isFloating: isFloating,
            isBusy: isBusy
        )
        .composerDropDestination(
            isTargeted: $isDropTarget,
            onReceive: receiveDrop,
            onFailure: attachmentFailed
        )
        .focusedValue(\.isTypingProse, isFocused)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            boxWidth = frame.width
            boxTop = frame.minY
        }
        .background { WindowHeightReader { windowHeight = $0 } }
        .overlay(alignment: .topLeading) {
            AttachmentCardOverlay(
                attachment: openMenu == .none
                    ? hoveredAttachment(in: draft, among: attachments)
                    : nil,
                worktree: attachmentRoot,
                availableWidth: boxWidth
            )
            .alignmentGuide(.top, computeValue: guide)
        }
        .overlay(alignment: .topLeading) {
            SlashCommandCardOverlay(
                name: openMenu == .none && isCommandPreviewed ? draft.name : nil,
                command: named,
                availableWidth: boxWidth,
                availableHeight: placement.room
            )
            .alignmentGuide(.top, computeValue: guide)
        }
        .overlay(alignment: .topLeading) {
            ComposerMenuOverlay(
                menu: openMenu,
                commands: slashResults(in: openMenu),
                commandsAreLoaded: slashCatalog.isLoaded,
                files: fileMatches,
                selectedIndex: menuIndex,
                maxHeight: placement.menuHeight,
                availableWidth: boxWidth,
                onPickCommand: pick(command:),
                onPickFile: pick(file:),
                onHighlight: { menuIndex = $0 }
            )
            .alignmentGuide(.top, computeValue: guide)
        }
        .onChange(of: attachmentKey, initial: true) { dropOwner = attachmentKey }
        .task(id: attachmentKey) {
            PromptAttachmentStore.shared.load(sessionID: attachmentKey)
            adoptAttachmentsNobodyRemoved()
            applyCaptureDraft()
            applyCaptureAttachments()
        }
        .task(id: SlashCatalogKey(root: mentionRoot, homes: accountHomes)) {
            guard let accountHomes else { return }
            let catalog = SlashCommandCatalog.shared(for: mentionRoot)
            catalog.claudeAccount = accountHomes.claude
            catalog.account = accountHomes.codex
            catalog.refused = accountHomes.refused
            slashCatalog = catalog
            await catalog.load(workspacePath: mentionRoot)
        }
        .task(id: openMenu.kind == .slash) {
            guard openMenu.kind == .slash, accountHomes != nil else { return }
            await slashCatalog.refreshIfStale(workspacePath: mentionRoot)
        }
        .task(id: openMenu.mention?.query) { await refreshFileMatches() }
        .onChange(of: isDraftLoaded) { _, _ in adoptAttachmentsNobodyRemoved() }
        .onChange(of: text) { _, _ in
            menuIndex = 0
            releaseAttachmentsTheDraftDropped()
        }
        .onChange(of: menu) { old, new in
            menuIndex = 0
            if old.kind != new.kind { isMenuDismissed = false }
        }
    }

    private func promptEditor(attachments: [PromptAttachment]) -> some View {
        ComposerEditor(
            text: promptBody,
            caret: $caret,
            isFocused: $isFocused,
            height: editorHeight,
            onContentHeightChange: onContentHeightChange,
            onKey: handle(key:),
            onBackspaceAtStart: backspaceCommand,
            onAttach: attach(sources:replacing:),
            onAttachmentFailure: attachmentFailed,
            attachmentPaths: attachments.map(\.path),
            onOpenAttachment: open(path:),
            onHoverAttachment: { hoveredPath = $0 },
            attachmentRoot: attachmentRoot,
            folderRoot: mentionRoot,
            dropOwner: { currentDropOwner },
            handle: editor,
            placeholder: placeholder
        )
    }

    private func adoptAttachmentsNobodyRemoved() {
        guard isDraftLoaded else { return }
        heldKey = attachmentKey
        var draft = command
        let missing = PromptAttachmentStore.shared.hold(draft.body, sessionID: attachmentKey, mounting: true)
        guard !missing.isEmpty else { return }

        let written = AttachmentDraft.inserting(
            missing, into: draft.body, at: (draft.body as NSString).length
        )
        draft.body = written.text
        text = draft.text
        caret = written.caret
    }

    private func releaseAttachmentsTheDraftDropped() {
        guard isDraftLoaded else { return }
        guard heldKey == attachmentKey else { return adoptAttachmentsNobodyRemoved() }
        PromptAttachmentStore.shared.hold(command.body, sessionID: attachmentKey, mounting: false)
    }

    private func applyCaptureDraft() {
        #if DEBUG
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--composer-draft"), index + 1 < arguments.count,
              text.isEmpty else { return }
        text = arguments[index + 1]
        caret = (SlashCommandDraft.parse(text).body as NSString).length
        isFocused = true
        isCommandPreviewed = arguments.contains("--composer-preview")
        #endif
    }

    private func applyCaptureAttachments() {
        #if DEBUG
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--composer-attach"),
              index + 1 < arguments.count else { return }

        let files = arguments[index + 1]
            .split(separator: ",")
            .map { AttachmentSource.file(URL(filePath: String($0))) }
        let at = arguments.firstIndex(of: "--composer-caret")
            .map { $0 + 1 }
            .flatMap { $0 < arguments.count ? Int(arguments[$0]) : nil } ?? caret

        Task {
            try? await Task.sleep(for: .seconds(2))
            await add(files, replacing: NSRange(location: at, length: 0))
            print("[composer-draft] \(text)")
        }
        #endif
    }

    private func hoveredAttachment(
        in draft: SlashCommandDraft, among attachments: [PromptAttachment]
    ) -> PromptAttachment? {
        guard let hoveredPath else { return nil }
        let files = AttachmentDraft.parse(draft.body, paths: attachments.map(\.path))
        guard files.paths.contains(hoveredPath) else { return nil }
        return attachment(for: hoveredPath, among: attachments)
    }

    private func attachment(
        for path: String, among attachments: [PromptAttachment]
    ) -> PromptAttachment {
        attachments.first { $0.path == path } ?? .sent(path: path)
    }

    var currentDropOwner: String { dropOwner }

    var command: SlashCommandDraft {
        SlashCommandDraft.parse(text)
    }

    private var promptBody: Binding<String> {
        Binding {
            SlashCommandDraft.parse(text).body
        } set: { edited in
            var draft = SlashCommandDraft.parse(text)
            draft.body = edited
            text = draft.text
        }
    }

    private var menu: ComposerMenu {
        ComposerMenu.resolve(draft: command.body, caret: caret)
    }

    private var activeMenu: ComposerMenu {
        isMenuDismissed ? .none : menu
    }

    private var isMenuOpen: Bool { activeMenu != .none }

    private func slashResults(in menu: ComposerMenu) -> [SlashCommandMatch] {
        guard let token = menu.slash else { return [] }
        return slashCatalog.matches(token.query)
    }

    private var menuCount: Int {
        switch activeMenu {
        case .slash: slashResults(in: activeMenu).count
        case .mention: fileMatches.count
        case .none: 0
        }
    }

    private func menuPlacement(typedLineBottom: CGFloat) -> MenuLayout.Placement {
        MenuLayout.placement(
            above: boxTop - Metrics.spacing * 2,
            below: windowHeight - boxTop - typedLineBottom - Metrics.spacing * 2
        )
    }

    private func typedLineBottom(hasCommand: Bool) -> CGFloat {
        Metrics.gutter
            + (hasCommand ? AttachmentChip.height + Metrics.spacingWide : 0)
            + ComposerTextEditor.lineHeight
    }

    private func floatingGuide(
        isBelow: Bool, typedLineBottom: CGFloat
    ) -> @Sendable (ViewDimensions) -> CGFloat {
        let drop = typedLineBottom + Metrics.spacing
        return { isBelow ? -drop : $0[.bottom] + Metrics.spacing }
    }

    private func refreshFileMatches() async {
        guard let token = activeMenu.mention else {
            fileMatches = []
            return
        }
        let paths = await FileIndex.shared.files(workspacePath: mentionRoot)
        let query = token.query
        fileMatches = await Task.detached(priority: .userInitiated) {
            FileMatch.search(paths, query: query, limit: 200)
        }.value
    }

    private func pick(command picked: SlashCommand) {
        guard let token = activeMenu.slash else { return }
        let insertion = command.picking(command: picked.name, token: token)
        text = insertion.draft.text
        caret = insertion.caret
        isFocused = true
    }

    private func removeCommand() {
        let draft = command
        text = draft.removingCommand().text
        caret = 0
        isCommandPreviewed = false
        isFocused = true
    }

    private func backspaceCommand() -> Bool {
        let draft = command
        guard let after = draft.backspacingCommand() else { return false }
        text = after.text
        caret = draft.caretAfterBackspace
        isCommandPreviewed = false
        return true
    }

    private func insert(quickPrompt: QuickPromptPanelRow) {
        var draft = command
        let insertion = QuickPromptInsertion.inserting(quickPrompt.text, into: draft.body, at: caret)
        draft.body = insertion.text
        text = draft.text
        caret = insertion.caret
        isFocused = true
    }

    private func pick(file: FileMatch) {
        guard let token = activeMenu.mention else { return }
        let replacement = "@\(file.path) "
        var draft = command
        let updated = NSMutableString(string: draft.body)
        updated.replaceCharacters(
            in: NSRange(location: token.start, length: token.length),
            with: replacement
        )
        draft.body = updated as String
        text = draft.text
        caret = token.start + (replacement as NSString).length
        isFocused = true
    }

    private func pickHighlighted() {
        switch activeMenu {
        case .slash:
            let results = slashResults(in: activeMenu)
            guard results.indices.contains(menuIndex) else { return }
            pick(command: results[menuIndex].command)
        case .mention:
            guard fileMatches.indices.contains(menuIndex) else { return }
            pick(file: fileMatches[menuIndex])
        case .none:
            break
        }
    }

    private func handle(key: ComposerKey) -> Bool {
        if isMenuOpen, menuCount > 0 {
            switch key {
            case .up:
                menuIndex = (menuIndex - 1 + menuCount) % menuCount
                return true
            case .down:
                menuIndex = (menuIndex + 1) % menuCount
                return true
            case .returnKey, .tab:
                pickHighlighted()
                return true
            case .escape:
                isMenuDismissed = true
                return true
            case .commandReturn:
                return onKey(key)
            }
        }

        if key == .escape, isMenuOpen {
            isMenuDismissed = true
            return true
        }

        return onKey(key)
    }

    @discardableResult
    func attach(sources: [AttachmentSource], replacing range: NSRange) -> Bool {
        guard !sources.isEmpty else { return false }
        Task { await add(sources, replacing: range) }
        return true
    }

    private func add(_ sources: [AttachmentSource], replacing range: NSRange) async {
        let added = await PromptAttachmentStore.shared.add(
            sources,
            sessionID: attachmentKey,
            workspace: attachmentRoot
        )
        write(added.paths, replacing: range)
        isFocused = true
        guard !added.failures.isEmpty else { return }
        app.alert = AppAlert(
            title: added.failures.count == 1
                ? "That file was not attached"
                : "Some files were not attached",
            message: added.failures.joined(separator: "\n\n")
        )
    }

    func attachmentFailed(_ message: String) {
        app.alert = AppAlert(title: "Not everything was attached", message: message)
    }

    private func write(_ paths: [String], replacing range: NSRange) {
        guard !paths.isEmpty else { return }
        var draft = command
        guard !editor.insert(paths, replacing: range, into: draft.body) else { return }

        let body = draft.body as NSString
        let start = min(max(range.location, 0), body.length)
        let length = min(max(range.length, 0), body.length - start)
        let cleared = body.replacingCharacters(in: NSRange(location: start, length: length), with: "")

        let written = AttachmentDraft.inserting(paths, into: cleared, at: start)
        draft.body = written.text
        text = draft.text
        caret = written.caret
    }

    private func open(path: String) {
        hoveredPath = nil
        onOpenAttachment(attachment(for: path, among: attachments))
    }

    private func attachFiles() {
        Task { await pickFiles() }
    }

    private func pickFiles() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(filePath: mentionRoot)

        guard await panel.present() == .OK else { return }

        await add(panel.urls.map { .file($0) }, replacing: NSRange(location: caret, length: 0))
    }
}

private struct SlashCatalogKey: Equatable {
    var root: String
    var homes: ComposerAccountHomes?
}
