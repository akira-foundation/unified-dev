import SwiftUI
import AppKit
import Core

struct NewWorkspaceComposer: View {
    var repo: Repo
    var draft: WorkspaceDraft

    @Environment(AppModel.self) private var app

    @State private var caret = 0
    @State private var isFocused = false
    @State private var contentHeight = ComposerTextEditor.lineHeight
    @State private var isAskingToDiscard = false

    private static let placeholder = "Describe the task, @mention files, run /commands"
    private static let minimumLines: CGFloat = 3
    private static let maximumLines: CGFloat = 14

    private var staging: String { AttachmentStaging.directory(draftID: draft.attachmentKey) }

    private var isCreating: Bool { app.drafts.isCreating(repo.id) }

    private var controls: ComposerControls {
        draft.controls?.applied(to: ComposerControls()) ?? ComposerControls()
    }

    private var supportsCLIChat: Bool {
        WorkspaceStartMode.chat(usesCLI: true, agent: controls.agentKind).cliAgentKind != nil
    }

    private var editorHeight: CGFloat {
        let line = ComposerTextEditor.lineHeight
        return min(max(contentHeight, line * Self.minimumLines), line * Self.maximumLines)
    }

    var body: some View {
        ComposerSurface(
            text: Binding(
                get: { app.drafts.draft(for: repo.id)?.prompt ?? draft.prompt },
                set: { text in app.editDraft(repo.id) { $0.prompt = text } }
            ),
            caret: $caret,
            isFocused: $isFocused,
            place: ComposerPlace(
                mentionRoot: repo.path,
                attachmentRoot: staging,
                attachmentKey: draft.attachmentKey,
                placeholder: Self.placeholder,
                project: repo.path,
                account: AccountScope(workspaceID: nil, repoID: repo.id)
            ),
            editorHeight: editorHeight,
            onContentHeightChange: { contentHeight = $0 },
            controls: controls,
            onControlsChange: { chosen in
                app.editDraft(repo.id) {
                    $0.controls = WorkspaceDraftControls(chosen, usesCLIChat: $0.controls?.usesCLIChat ?? false)
                }
            },
            send: ComposerSend(
                intent: ComposerIntent(StartingPointLabel.action(for: draft.startingPoint)),
                canSend: !isCreating,
                perform: create,
                onQuickPrompt: quickPrompt,
                usesCLIChat: usesCLIChat,
                supportsCLIChat: supportsCLIChat
            ),
            onOpenAttachment: { NSWorkspace.shared.open($0.url(in: staging)) },
            onEscape: escape
        )
        .frame(maxWidth: TranscriptLayout.conversationMeasure)
        .padding(.horizontal, ComposerLayout.horizontalInset)
        .popover(isPresented: $isAskingToDiscard, arrowEdge: .top) {
            WorkspaceDraftDiscardQuestion(
                onDiscard: {
                    isAskingToDiscard = false
                    app.discardDraft(repo.id)
                },
                onKeep: { isAskingToDiscard = false }
            )
        }
        .disabled(isCreating)
        .task(id: draft.attachmentKey) {
            PromptAttachmentStore.shared.load(sessionID: draft.attachmentKey)
            caret = (draft.prompt as NSString).length
            isFocused = !app.drafts.consumeQuietArrival(repo.id)
        }
        .onChange(of: app.drafts.quietArrivals.contains(repo.id)) { _, arrived in
            guard arrived, app.drafts.consumeQuietArrival(repo.id) else { return }
            isFocused = false
        }
    }

    private var usesCLIChat: Binding<Bool> {
        Binding(
            get: { (draft.controls?.usesCLIChat ?? false) && supportsCLIChat },
            set: { value in
                let current = controls
                app.editDraft(repo.id) { $0.controls = WorkspaceDraftControls(current, usesCLIChat: value) }
            }
        )
    }

    private func quickPrompt(
        _ row: QuickPromptPanelRow, insert: @MainActor (QuickPromptPanelRow) -> Void
    ) -> QuickPromptDelivery {
        insert(row)
        let delivery = row.delivery(canSend: true, canOpenNewChat: false)
        switch delivery {
        case .send, .sendInNewChat: create()
        case .compose, .composeInNewChat: break
        }
        return delivery
    }

    private func escape() {
        switch WorkspaceDraftDiscard.onEscape(hasContent: app.drafts.holdsWork(repo.id), isCreating: isCreating) {
        case .ignore: break
        case .discard: app.discardDraft(repo.id)
        case .confirm: isAskingToDiscard = true
        }
    }

    private func create() {
        guard !isCreating else { return }
        let key = draft.attachmentKey
        let directory = staging
        let ready = PromptAttachmentStore.shared.attachments(for: key).filter {
            FileManager.default.fileExists(atPath: $0.url(in: directory).path)
        }
        let staged = StagedAttachments(directory: directory, attachments: ready)
        let repoID = repo.id
        Task { await app.createFromDraft(repoID, staged: staged) }
    }
}
