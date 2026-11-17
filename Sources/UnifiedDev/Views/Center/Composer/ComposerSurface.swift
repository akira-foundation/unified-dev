import SwiftUI
import Core

struct ComposerPlace {
    var mentionRoot: String
    var attachmentRoot: String
    var attachmentKey: String
    var placeholder: String
    var project: String?
    var projectQuickPrompts: [ProjectQuickPrompt] = []
    var onOpenQuickPrompts: (@MainActor () -> Void)?
    var isDraftLoaded = true
    var account: AccountScope = .none
    var orchestrates = false
}

struct ComposerSend {
    var intent: ComposerIntent = .send
    var canSend: Bool
    var perform: @MainActor () -> Void
    var onQuickPrompt: @MainActor (QuickPromptPanelRow, @MainActor (QuickPromptPanelRow) -> Void) -> Void
    var usesCLIChat: Binding<Bool>?
    var supportsCLIChat: Bool = true
}

struct ComposerConversation {
    var reviewComments: [ReviewComment] = []
    var onRemoveReviewComment: @MainActor (ReviewCommentID) -> Void = { _ in }
    var onOpenReviewComment: @MainActor (ReviewComment) -> Void = { _ in }
    var replyQuotes: [ReplyQuote] = []
    var onRemoveReplyQuote: @MainActor (ReplyQuoteID) -> Void = { _ in }
    var onOpenReplyQuote: @MainActor (ReplyQuote) -> Void = { _ in }
    var onOpenCommand: (@MainActor (String) -> Void)?
    var context: ContextWindowUsage?
    var isRunning = false
    var queues = false
    var onStop: @MainActor () -> Void = {}
    var onSideConversation: (@MainActor () -> Void)?
    var onOpenInNewChat: (@MainActor (ComposerControls) -> Void)?
}

struct ComposerSurface: View {
    @Binding var text: String
    @Binding var caret: Int
    @Binding var isFocused: Bool
    var place: ComposerPlace
    var editorHeight: CGFloat
    var onContentHeightChange: @MainActor (CGFloat) -> Void
    var controls: ComposerControls
    var onControlsChange: @MainActor (ComposerControls) -> Void
    var send: ComposerSend
    var conversation = ComposerConversation()
    var onOpenAttachment: @MainActor (PromptAttachment) -> Void
    var onEscape: @MainActor () -> Void

    @Environment(AppModel.self) private var app
    @State private var loaded: ComposerAccountReading?
    @State private var settingsCloseRequests = ComposerSettingsCloseRequests()

    var body: some View {
        ComposerPrompt(
            text: $text,
            caret: $caret,
            isFocused: $isFocused,
            mentionRoot: place.mentionRoot,
            attachmentRoot: place.attachmentRoot,
            attachmentKey: place.attachmentKey,
            reviewComments: conversation.reviewComments,
            onRemoveReviewComment: conversation.onRemoveReviewComment,
            onOpenReviewComment: conversation.onOpenReviewComment,
            replyQuotes: conversation.replyQuotes,
            onRemoveReplyQuote: conversation.onRemoveReplyQuote,
            onOpenReplyQuote: conversation.onOpenReplyQuote,
            placeholder: place.placeholder,
            editorHeight: editorHeight,
            onContentHeightChange: onContentHeightChange,
            onKey: handle(key:),
            onOpenAttachment: onOpenAttachment,
            onOpenCommand: conversation.onOpenCommand,
            isFloating: true,
            isBusy: conversation.isRunning,
            isDraftLoaded: place.isDraftLoaded,
            accountHomes: reading?.homes
        ) { actions in
            ComposerFooterView(
                controls: controls,
                onChange: onControlsChange,
                onOpenInNewChat: conversation.onOpenInNewChat,
                context: conversation.context,
                isRunning: conversation.isRunning,
                queues: conversation.queues,
                canSend: send.canSend,
                intent: send.intent,
                project: place.project,
                onAttach: actions.attach,
                onQuickPrompt: { fire($0, insert: actions.insert) },
                projectQuickPrompts: place.projectQuickPrompts,
                onOpenQuickPrompts: place.onOpenQuickPrompts,
                onSend: performSend,
                onStop: conversation.onStop,
                onSideConversation: conversation.onSideConversation,
                orchestrates: place.orchestrates,
                usesCLIChat: send.usesCLIChat,
                supportsCLIChat: send.supportsCLIChat,
                account: reading?.section,
                accountHomes: reading?.homes,
                settingsCloseRequests: settingsCloseRequests
            )
        }
        .task(id: accountKey) {
            let key = accountKey
            let found = await app.composerAccounts(for: key)
            guard !Task.isCancelled else { return }
            loaded = found
        }
    }

    private var accountKey: ComposerAccountKey {
        app.composerAccountKey(for: place.account, provider: controls.agentKind)
    }

    private var reading: ComposerAccountReading? {
        loaded.flatMap { $0.key == accountKey ? $0 : nil }
    }

    private func performSend() {
        settingsCloseRequests.note(.pressedSend(canSend: send.canSend))
        send.perform()
    }

    private func fire(_ prompt: QuickPromptPanelRow, insert: @MainActor (QuickPromptPanelRow) -> Void) {
        let delivery = prompt.delivery(canSend: send.canSend, canOpenNewChat: true)
        settingsCloseRequests.note(.firedQuickPrompt(delivery))
        send.onQuickPrompt(prompt, insert)
    }

    private func handle(key: ComposerKey) -> Bool {
        switch key {
        case .returnKey, .commandReturn:
            performSend()
            return true
        case .escape:
            onEscape()
            return true
        case .up, .down, .tab:
            return false
        }
    }
}
