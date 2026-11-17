import SwiftUI
import AppKit
import Core

struct ComposerView: View {
    @Bindable var transcript: TranscriptModel
    var model: WorkspaceModel?
    var room: ComposerRoom = ComposerRoom()
    var placeholder: String = ComposerEditor.chatPlaceholder
    var onDismiss: (() -> Void)?
    var includesReviewComments = true
    var destinationLabel: String?
    var destinations: [ComposerDestination] = []
    var onSelectDestination: ((SessionID) -> Void)?

    @Environment(AppModel.self) private var app

    private static let minTranscriptHeight: CGFloat = 120

    @State private var contentHeight = ComposerTextEditor.lineHeight
    @State private var draggedHeight: CGFloat?
    @State private var chromeHeight: CGFloat = 0
    @State private var caret = 0
    @State private var isFocused = false
    @State private var isFastMode = false
    @State private var codexFastMode: Bool?
    @State private var outputStyle = OutputStyle.defaultName
    @State private var codexContextWindow = CodexContextWindow.modelDefault
    @State private var draftSaveTask: Task<Void, Never>?
    @State private var isClearingChat = false

    var body: some View {
        VStack(spacing: 0) {
            if let destinationLabel {
                ComposerDestinationStrip(
                    label: destinationLabel,
                    destinations: destinations,
                    selected: transcript.session.id,
                    onSelect: onSelectDestination
                )
            }

            PaneDivider(
                axis: .vertical,
                length: Binding(
                    get: { Double(editorHeight) },
                    set: { draggedHeight = $0 == Double(automaticEditorHeight) ? nil : CGFloat($0) }
                ),
                bounds: Double(ComposerTextEditor.lineHeight)...Double(maxEditorHeight),
                reset: Double(automaticEditorHeight),
                label: "Message height"
            )
            .help("Drag to resize. Double-click to fit the text.")
            .opacity(0)

            TurnHistoryNotice(transcript: transcript)
            ComposerPlansView(transcript: transcript, model: model, controls: controls)
            composer
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { total in
            let chrome = PaneMeasure.chrome(total - editorHeight, knowing: chromeHeight)
            if chrome != chromeHeight { chromeHeight = chrome }
            let clearance = ceil(total) + ComposerLayout.bottomInset + ComposerLayout.textClearance
            if room.clearance != clearance { room.clearance = clearance }
        }
        .frame(maxWidth: TranscriptLayout.conversationMeasure)
        .padding(.horizontal, ComposerLayout.horizontalInset)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, ComposerLayout.bottomInset)
    }

    private var composer: some View {
        ComposerSurface(
            text: $transcript.draft,
            caret: $caret,
            isFocused: $isFocused,
            place: ComposerPlace(
                mentionRoot: transcript.cwd,
                attachmentRoot: transcript.cwd,
                attachmentKey: transcript.session.id.rawValue,
                placeholder: placeholder,
                project: transcript.cwd,
                projectQuickPrompts: model?.settings.quickPrompts ?? [],
                onOpenQuickPrompts: { [model] in model?.refreshSettings() },
                isDraftLoaded: transcript.isLoaded,
                account: transcript.accountScope,
                orchestrates: transcript.orchestrates
            ),
            editorHeight: editorHeight,
            onContentHeightChange: { contentHeight = $0 },
            controls: controls,
            onControlsChange: apply(controls:),
            send: ComposerSend(canSend: canSend, perform: send, onQuickPrompt: fire),
            conversation: ComposerConversation(
                reviewComments: reviewComments,
                onRemoveReviewComment: remove(reviewComment:),
                onOpenReviewComment: open(reviewComment:),
                replyQuotes: transcript.replyQuotes,
                onRemoveReplyQuote: transcript.removeReplyQuote(id:),
                onOpenReplyQuote: { quote in quote.sourceSeq.map(transcript.revealMessage(seq:)) },
                onOpenCommand: open(commandPath:),
                context: transcript.contextUsage,
                isRunning: transcript.isRunning,
                queues: transcript.queuesNextMessage,
                onStop: transcript.stop,
                onSideConversation: canOpenSideConversation ? openSideConversation : nil,
                onOpenInNewChat: hasSpoken ? openInNewChat : nil
            ),
            onOpenAttachment: open(attachment:),
            onEscape: escape
        )
        .task(id: transcript.session.id) { await prepare() }
        .task(id: "planning:\(transcript.session.id):\(transcript.rows.last?.seq ?? -1)") {
            if let store = app.store { await ComposerPlanningSupport.shared.refresh(from: store) }
        }
        .onChange(of: transcript.draft) { _, _ in scheduleDraftSave() }
        .onChange(of: transcript.composerFocusRequests) { _, _ in
            isFocused = true
            caret = (transcript.draft as NSString).length
        }
        .focusedValue(\.composerTranscript, isFocused ? transcript : nil)
        .onDisappear(perform: saveDraftNow)
    }

    private var editorHeight: CGFloat {
        min(max(draggedHeight ?? automaticEditorHeight, ComposerTextEditor.lineHeight), maxEditorHeight)
    }

    private var automaticEditorHeight: CGFloat {
        min(max(contentHeight, ComposerTextEditor.lineHeight), maxEditorHeight)
    }

    private var maxEditorHeight: CGFloat {
        PaneMeasure.editorCap(
            room: room.height,
            chrome: chromeHeight + ComposerLayout.bottomInset + ComposerLayout.textClearance,
            floor: Self.minTranscriptHeight,
            atLeast: ComposerTextEditor.lineHeight
        )
    }

    private var sessionEditor: ComposerSessionEditor {
        ComposerSessionEditor(transcript: transcript, model: model)
    }

    private var controls: ComposerControls {
        ComposerControls(
            session: transcript.session,
            isFastMode: isFastMode,
            outputStyle: outputStyle,
            codexContextWindow: codexContextWindow,
            codexFastMode: codexFastMode
        )
    }

    private var hasBody: Bool {
        transcript.draft.contains { !$0.isWhitespace }
    }

    private var attachments: [PromptAttachment] {
        PromptAttachmentStore.shared.attachments(for: transcript.session.id.rawValue)
    }

    private var reviewComments: [ReviewComment] {
        includesReviewComments ? (model?.reviewComments ?? []) : []
    }

    private var canSend: Bool { hasBody || !reviewComments.isEmpty || !transcript.replyQuotes.isEmpty }

    private func escape() {
        if let onDismiss { onDismiss() } else { isFocused = false }
    }

    private func apply(controls new: ComposerControls) {
        if new.codexFastMode != codexFastMode {
            codexFastMode = new.codexFastMode
            if let store = app.store {
                let key = CodexSpeed.key(sessionID: transcript.session.id)
                let value = new.codexFastMode.map { $0 ? "1" : "0" }
                Task { try? await store.setSetting(key, value) }
            }
        }

        if new.isFastMode != isFastMode {
            isFastMode = new.isFastMode
            if let store = app.store {
                let key = ComposerControls.fastModeKey(sessionID: transcript.session.id)
                let value = new.isFastMode ? "1" : nil
                Task { try? await store.setSetting(key, value) }
            }
        }

        if new.outputStyle != outputStyle {
            outputStyle = new.outputStyle
            if let store = app.store {
                let key = ComposerControls.outputStyleKey(sessionID: transcript.session.id)
                let value = OutputStyle.isDefault(new.outputStyle) ? nil : new.outputStyle
                Task { try? await store.setSetting(key, value) }
            }
        }

        if new.codexContextWindow != codexContextWindow {
            codexContextWindow = new.codexContextWindow
            if let store = app.store {
                let key = ComposerControls.contextWindowKey(sessionID: transcript.session.id)
                let value = CodexContextWindow.stored(new.codexContextWindow)
                Task { try? await store.setSetting(key, value) }
            }
        }

        let session = transcript.session

        switch BackendChange.decide(
            from: session.agentKind,
            to: new.agentKind,
            hasSpoken: hasSpoken,
            isInteractiveTerminal: transcript.usesInteractiveTerminal
        ) {
        case .fork(let kind):
            fork(onto: kind, with: new, saying: BackendChange.interactiveForkNotice(to: kind))
            return
        case .switchInPlace:
            sessionEditor.switchAgent(to: new)
            return
        case .changeInPlace, .unchanged:
            break
        }

        guard new.model != session.model
            || new.effort != session.effort
            || new.agentKind != session.agentKind
            || new.permissionMode != session.permissionMode
            || new.interactionMode != session.interactionMode
        else { return }

        sessionEditor.apply {
            $0.model = new.model
            $0.effort = new.effort
            $0.agentKind = new.agentKind
            $0.permissionMode = new.permissionMode
            $0.interactionMode = new.interactionMode
        }
    }

    private var hasSpoken: Bool {
        BackendChange.hasSpoken(
            rowCount: transcript.rows.count,
            agentSessionID: transcript.session.agentSessionID,
            isTranscriptLoaded: transcript.isLoaded
        )
    }

    private func openInNewChat(_ controls: ComposerControls) {
        fork(onto: controls.agentKind, with: controls, saying: nil)
    }

    private func fork(onto kind: AgentKind, with controls: ComposerControls, saying notice: String?) {
        let draft = ReplyQuote.message(transcript.draft, quoting: transcript.replyQuotes)
        let source = transcript.session.id
        let from = transcript.session.agentKind

        guard let model else {
            Task { @MainActor in
                guard let made = await app.ask.openInNewChat(controls: controls, draft: draft) else { return }
                app.notice = Notice(message: BackendChange.forkNotice(title: made.title, from: from))
            }
            return
        }

        let title = BackendChange.forkedTitle(transcript.session.title, to: kind)

        Task { @MainActor in
            guard let session = await model.createSession(
                title: title,
                controls: controls,
                draft: draft,
                seededFrom: source
            ) else {
                app.notice = Notice(message: BackendChange.forkFailureNotice(to: kind), tone: .error)
                return
            }

            WorkspaceTabsStore.shared.reveal(.chat(session.id), in: model)
            app.notice = Notice(message: notice ?? BackendChange.forkNotice(title: title, from: from))
        }
    }

    private var canOpenSideConversation: Bool {
        model != nil && transcript.session.sideConversationParentID == nil && onDismiss == nil
    }

    private func openSideConversation() {
        model?.openSideConversation(from: transcript)
    }

    private func send() {
        guard canSend else { return }
        draftSaveTask?.cancel()

        if let question = SideConversation.question(in: transcript.draft) {
            guard canOpenSideConversation, let model else {
                app.notice = Notice(message: "Use /btw in a workspace chat to open a side conversation.")
                return
            }
            guard model.openSideConversation(from: transcript, question: question) else { return }
            transcript.draft = ""
            caret = 0
            saveDraftNow()
            return
        }

        if onDismiss != nil,
           ChatClearCommand.matches(transcript.draft) || ChatCloseCommand.matches(transcript.draft) {
            app.notice = Notice(message: "Use Keep and start new in the side conversation menu.")
            return
        }

        if ChatCloseCommand.matches(transcript.draft) {
            startFreshChat(closingPrevious: true)
            return
        }

        if ChatClearCommand.matches(transcript.draft) {
            startFreshChat()
            return
        }

        let worktree = transcript.cwd
        let sourceDraft = transcript.draft
        let draftText = AttachmentDraft
            .parse(sourceDraft, paths: attachments.map(\.path))
            .keeping { path in
                FileManager.default.fileExists(
                    atPath: PromptAttachment.sent(path: path).url(in: worktree).path
                )
            }

        let imageComments = Dictionary(attachments.compactMap { attachment in
            attachment.imageComment.map { (attachment.path, $0) }
        }, uniquingKeysWith: { first, _ in first })
        let quotes = transcript.replyQuotes
        let text = ReplyQuote.message(
            BrowserImageComment.expand(draftText, comments: imageComments), quoting: quotes
        )

        PromptAttachmentStore.shared.settle(
            sent: draftText, sessionID: transcript.session.id.rawValue, workspace: worktree
        )
        caret = 0
        let transcript = transcript
        let comments = reviewComments
        guard !comments.isEmpty else {
            Task {
                await transcript.submit(
                    text, clearingDraft: sourceDraft, clearingQuotes: quotes, dismissingAsks: true
                )
            }
            return
        }

        let model = model
        let template = PromptOverrides().template(for: .review)
        Task {
            let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let composed = await Task.detached(priority: .userInitiated) {
                ReviewTurn.compose(
                    message: message,
                    comments: comments,
                    worktreePath: worktree,
                    template: template
                )
            }.value
            await transcript.submit(
                composed, clearingDraft: sourceDraft, clearingQuotes: quotes, dismissingAsks: true
            )
            await model?.removeReviewComments(ids: comments.map(\.id))
        }
    }

    private func fire(
        _ prompt: QuickPromptPanelRow, insert: @MainActor (QuickPromptPanelRow) -> Void
    ) -> QuickPromptDelivery {
        let delivery = prompt.delivery(canSend: true, canOpenNewChat: model != nil)
        switch delivery {
        case .compose:
            insert(prompt)
        case .send:
            insert(prompt)
            send()
        case .composeInNewChat:
            openChat(for: prompt, sending: false)
        case .sendInNewChat:
            openChat(for: prompt, sending: true)
        }
        return delivery
    }

    private func openChat(for prompt: QuickPromptPanelRow, sending: Bool) {
        guard let model else { return }
        let text = prompt.text
        Task { @MainActor in
            guard let session = await model.createSession(title: prompt.chatTitle) else { return }
            guard sending else {
                try? await app.store?.saveDraft(sessionID: session.id, body: text)
                model.transcript(for: session).draft = text
                return
            }
            await model.transcript(for: session).submit(text)
        }
    }

    private func startFreshChat(closingPrevious: Bool = false) {
        guard !isClearingChat else { return }
        isClearingChat = true
        let previous = transcript
        let controls = controls
        Task { @MainActor in
            defer { isClearingChat = false }
            if let model {
                if !closingPrevious {
                    guard await model.clearConversation(previous.session, controls: controls) != nil else { return }
                } else {
                    let tabs = WorkspaceTabsStore.shared
                    let order = tabs.entries(in: model)
                    let owner = order.first { tab in
                        tabs.layout(of: tab).panes.contains { tabs.content(of: $0, in: tab) == .chat(previous.session.id) }
                    }
                    let pane = owner.flatMap { tab in
                        tabs.layout(of: tab).panes.first { tabs.content(of: $0, in: tab) == .chat(previous.session.id) }
                    }
                    guard let next = await model.replaceSession(previous.session, controls: controls) else { return }
                    if let owner, let pane {
                        tabs.replace(pane: pane, of: owner, with: .chat(next.id), in: model)
                    }
                    tabs.forget(.chat(previous.session.id), workspaceID: model.workspace.id)
                    tabs.reorder(order.map { entry in
                        entry == .chat(previous.session.id) ? .chat(next.id) : entry
                    }, in: model)
                    tabs.reveal(.chat(next.id), in: model, focusing: true)
                }
            } else {
                await app.ask.startFresh(controls: controls)
                guard let current = app.ask.session, current.id != previous.session.id else { return }
            }
            if ChatClearCommand.matches(previous.draft) || ChatCloseCommand.matches(previous.draft) {
                previous.draft = ""
                await previous.saveDraft()
            }
        }
    }

    private func scheduleDraftSave() {
        draftSaveTask?.cancel()
        let transcript = transcript
        draftSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await transcript.saveDraft()
        }
    }

    private func saveDraftNow() {
        draftSaveTask?.cancel()
        let transcript = transcript
        Task { await transcript.saveDraft() }
    }

    private func open(attachment: PromptAttachment) {
        guard let model else { return }
        FileReview.open(path: attachment.path, in: model)
    }

    private func open(commandPath path: String) {
        guard let model else { return }
        FileReview.open(path: path, in: model)
    }

    private func open(reviewComment comment: ReviewComment) {
        guard let model else { return }
        FileReview.open(path: comment.filePath, in: model)
    }

    private func remove(reviewComment id: ReviewCommentID) {
        guard let model else { return }
        Task { await model.removeReviewComment(id: id) }
    }

    private func repairModel() {
        let session = transcript.session
        let hasSpoken = !(session.agentSessionID ?? "").isEmpty
        guard let repair = ModelIdentifier.correction(
            model: session.model,
            on: session.agentKind,
            hasSpoken: hasSpoken,
            models: ComposerModelCatalog.shared.models
        ) else { return }

        sessionEditor.apply {
            $0.model = repair.model
            if let kind = repair.kind, kind != $0.agentKind {
                $0.agentKind = kind
                $0.permissionMode = $0.permissionMode.nearest(on: kind)
            }
        }
    }

    private func prepare() async {
        defer {
            SwitchTrace.mark("composer.prepared", workspace: transcript.workspace?.id)
            SwitchTrace.markOnScreen("composer.prepared", workspace: transcript.workspace?.id)
        }
        caret = (transcript.draft as NSString).length

        repairModel()

        guard let store = app.store else { return }
        let sessionID = transcript.session.id
        let storedFastMode = (try? await store.setting(
            ComposerControls.fastModeKey(sessionID: sessionID)
        )) == "1"
        let storedCodexSpeed = CodexSpeed.override(stored: try? await store.setting(
            CodexSpeed.key(sessionID: sessionID)
        ))
        let storedStyle = (try? await store.setting(
            ComposerControls.outputStyleKey(sessionID: sessionID)
        )) ?? OutputStyle.defaultName
        let storedContextWindow = CodexContextWindow.normalised(try? await store.setting(
            ComposerControls.contextWindowKey(sessionID: sessionID)
        ))
        guard !Task.isCancelled else { return }
        isFastMode = storedFastMode
        codexFastMode = storedCodexSpeed
        outputStyle = storedStyle
        codexContextWindow = storedContextWindow

        let appliedKey = ComposerControls.defaultsAppliedKey(sessionID: sessionID)
        let wasPrepared = (try? await store.setting(appliedKey)) == "1"
        let spoken = wasPrepared ? 0 : ((try? await store.messageCount(sessionID: sessionID)) ?? 1)
        guard ComposerDefaults.applies(
            wasPrepared: wasPrepared, agentSessionID: transcript.session.agentSessionID, messageCount: spoken
        ) else { return }

        let appDefaults = await AppDefaults.loadForNewSessions(from: store)

        var repoSettings = RepoSettings()
        if let workspace = transcript.workspace, let repo = app.repo(for: workspace) {
            let path = repo.path
            repoSettings = await Task.detached(priority: .utility) {
                SettingsLoader.load(repo: path)
            }.value
        }
        guard !Task.isCancelled else { return }

        let resolved = ComposerDefaults.resolve(
            repo: repoSettings,
            app: appDefaults,
            hasWorktree: transcript.workspace != nil,
            running: transcript.session.agentKind,
            models: ComposerModelCatalog.shared.models
        )

        if appDefaults.fastMode != isFastMode {
            isFastMode = appDefaults.fastMode
            try? await store.setSetting(
                ComposerControls.fastModeKey(sessionID: sessionID),
                appDefaults.fastMode ? "1" : nil
            )
            guard !Task.isCancelled else { return }
        }

        if appDefaults.outputStyle != outputStyle {
            outputStyle = appDefaults.outputStyle
            try? await store.setSetting(
                ComposerControls.outputStyleKey(sessionID: sessionID),
                OutputStyle.isDefault(appDefaults.outputStyle) ? nil : appDefaults.outputStyle
            )
            guard !Task.isCancelled else { return }
        }

        if appDefaults.codexContextWindow != codexContextWindow {
            codexContextWindow = appDefaults.codexContextWindow
            try? await store.setSetting(
                ComposerControls.contextWindowKey(sessionID: sessionID),
                CodexContextWindow.stored(appDefaults.codexContextWindow)
            )
            guard !Task.isCancelled else { return }
        }

        let session = transcript.session
        if session.model != resolved.model
            || session.effort != resolved.effort
            || session.agentKind != resolved.backend
            || session.permissionMode != resolved.permissionMode
            || session.interactionMode != resolved.interactionMode {
            sessionEditor.apply(implementationMode: appDefaults.permissionMode) {
                $0.model = resolved.model
                $0.effort = resolved.effort
                $0.agentKind = resolved.backend
                $0.permissionMode = resolved.permissionMode
                $0.interactionMode = resolved.interactionMode
            }
        }

        try? await store.setSetting(appliedKey, "1")
    }
}
