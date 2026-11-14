import SwiftUI
import Core

struct TranscriptRowView: View, Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row.id == rhs.row.id
            && lhs.row.seq == rhs.row.seq
            && lhs.row.kind == rhs.row.kind
            && lhs.row.isError == rhs.row.isError
            && lhs.row.refusal == rhs.row.refusal
            && lhs.row.refusalReason == rhs.row.refusalReason
            && lhs.row.durationMS == rhs.row.durationMS
            && lhs.row.resultPayload?.count == rhs.row.resultPayload?.count
            && lhs.row.parentToolUseID == rhs.row.parentToolUseID
            && lhs.isExpanded == rhs.isExpanded
            && lhs.isNested == rhs.isNested
            && lhs.subagentActions == rhs.subagentActions
            && lhs.subagentHasRun == rhs.subagentHasRun
            && lhs.home == rhs.home
            && lhs.row.permissionDecision == rhs.row.permissionDecision
            && lhs.row.permissionNote == rhs.row.permissionNote
            && lhs.row.permissionAnswers == rhs.row.permissionAnswers
            && lhs.projectName == rhs.projectName
            && lhs.suggestion == rhs.suggestion
            && lhs.chatIsSubagent == rhs.chatIsSubagent
    }

    var row: TranscriptRow
    var home: TranscriptHome
    var suggestion: WorkSuggestion?
    var chatIsSubagent = false
    var isExpanded = false
    var isNested = false
    var subagentActions: Int?
    var subagentHasRun = false
    var runActions: SubagentRunActions?
    var projectName: String?
    var onToggle: () -> Void = {}
    var onAnswer: (String, PermissionDecision) -> Void = { _, _ in }

    var body: some View {
        content
            .padding(.leading, isNested ? TranscriptLayout.nestIndent : 0)
            .overlay(alignment: .leading) {
                if isNested {
                    Rectangle()
                        .fill(Palette.border)
                        .frame(width: Metrics.hairline)
                        .padding(.leading, TranscriptLayout.inset)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch row.kind {
        case .user:
            let typed = userText
            if let review = ReviewTurn.split(typed) {
                UserTurnRowView(
                    text: review.message,
                    reviewChips: review.chips,
                    home: home
                )
            } else {
                let turn = AttachmentTrailer.split(typed)
                UserTurnRowView(
                    text: turn.body,
                    attachments: turn.paths,
                    home: home
                )
            }

        case .crew:
            if let message = CrewMessage.decode(row.payload) {
                switch SendingSlot.drawing(of: message) {
                case .workspaceMessage(let crew):
                    WorkspaceMessageRowView(message: crew)
                case .crewMessage(let crew):
                    CrewMessageRowView(message: crew)
                case .ownerTurn, .stuckRequest, nil:
                    EmptyView()
                }
            }

        case .suggestion:
            if let suggestion {
                WorkSuggestionCardView(suggestion: suggestion, chatIsSubagent: chatIsSubagent)
            }

        case .assistantText:
            if let text = assistantText, !text.isEmpty {
                ProseRowView(text: text)
            }

        case .thinking:
            if let text = thinkingText, !text.isEmpty {
                ThinkingRowView(text: text, isExpanded: isExpanded, onToggle: onToggle)
            }

        case .toolUse:
            if let use = toolUse {
                switch toolRow(for: use) {
                case let .workspaceMessage(sent):
                    WorkspaceMessageSentRowView(record: sent)
                case let .media(request):
                    MediaShowRowView(request: request, home: home)
                case let .codexImage(path):
                    MediaShowRowView(
                        request: MediaShowRequest(path: path),
                        home: home,
                        source: .codexImageView
                    )
                case .tool:
                    let run = runLink(for: use)
                    ToolRowView(
                        use: use,
                        presentation: TranscriptPresentationCache.presentation(
                            rowID: row.id,
                            use: use,
                            worktree: home.worktree
                        ),
                        home: home,
                        result: toolResult,
                        isError: row.isError,
                        refusal: row.refusal,
                        refusalReason: row.refusalReason,
                        durationMS: row.durationMS,
                        subagentActions: subagentActions,
                        onOpenRun: run.open,
                        runUnavailable: run.isUnavailable,
                        isExpanded: isExpanded,
                        onToggle: onToggle
                    )
                }
            }

        case .toolResult:
            if let result = orphanResult {
                OrphanResultRowView(result: result)
            }

        case .permissionAsk:
            if let ask = permissionAsk {
                if AgentQuestionnaire.isQuestion(toolName: ask.toolName) {
                    AgentQuestionCard(
                        ask: ask,
                        decision: row.permissionDecision,
                        answers: row.permissionAnswers,
                        isExpanded: isExpanded,
                        onToggle: onToggle,
                        onAnswer: { onAnswer(ask.requestID, $0) }
                    )
                } else {
                    PermissionAskRowView(
                        ask: ask,
                        decision: row.permissionDecision,
                        note: row.permissionNote,
                        projectName: projectName,
                        onAnswer: { onAnswer(ask.requestID, $0) }
                    )
                }
            }

        case .error:
            AgentErrorRowView(
                exit: AgentExit.read(json),
                isExpanded: isExpanded,
                onToggle: onToggle
            )

        case .notice:
            if let chrome = ClaudeChromeNotice.decode(row.payload) {
                ClaudeChromeNoticeRowView(notice: chrome)
            } else {
                RateLimitRowView(payload: row.payload)
            }

        case .system:
            if let info = initInfo {
                SessionStartRowView(info: info)
            }
            if initInfo == nil, let wake = backgroundWake {
                BackgroundWakeRowView(wake: wake)
            }

        case .handoff:
            if let mark = HandoffMark.decode(row.payload) {
                HandoffDividerView(mark: mark)
            }

        case .result:
            EmptyView()
        }
    }

    private enum ToolRow {
        case workspaceMessage(WorkspaceSayRecord)
        case media(MediaShowRequest)
        case codexImage(String)
        case tool
    }

    private func toolRow(for use: AgentToolUse) -> ToolRow {
        if let sent = sentWorkspaceMessage(use) { return .workspaceMessage(sent) }
        if let media = successfulMediaRequest(use) { return .media(media) }
        if let image = successfulCodexImageRequest(use) { return .codexImage(image.path) }
        return .tool
    }

    private func runLink(for use: AgentToolUse) -> (open: (() -> Void)?, isUnavailable: Bool) {
        guard let runActions, SubagentRunLink.isAgentCall(toolName: use.name) else { return (nil, false) }
        let isSettled = row.resultPayload != nil
        let hasRun = subagentHasRun
        let canOpen = SubagentRunLink.canOpen(
            toolUseID: row.refID, hasRecordedRows: hasRun, isSettled: isSettled, isLive: runActions.isLive
        )
        guard canOpen, let toolUseID = row.refID else { return (nil, true) }
        return ({ runActions.open(toolUseID, hasRun, isSettled) }, false)
    }

    private var event: AgentEvent? {
        TranscriptEventCache.event(rowID: row.id, payload: row.payload)
    }

    private var json: JSONValue? {
        TranscriptEventCache.json(rowID: row.id, payload: row.payload)
    }

    private var assistantText: String? {
        guard case .assistantText(let block)? = event else { return nil }
        return block.text
    }

    private var thinkingText: String? {
        guard case .thinking(let block)? = event else { return nil }
        return block.text
    }

    private var toolUse: AgentToolUse? {
        guard case .toolUse(let use)? = event else { return nil }
        return use
    }

    private func successfulMediaRequest(_ use: AgentToolUse) -> MediaShowRequest? {
        guard row.resultPayload != nil, !row.isError, row.refusal == nil else { return nil }
        return MediaShowRequest(use: use)
    }

    private func sentWorkspaceMessage(_ use: AgentToolUse) -> WorkspaceSayRecord? {
        guard WorkspaceSayRecord.isWorkspaceSay(use.name),
              let payload = row.resultPayload, !row.isError, row.refusal == nil,
              case .toolResult(let result)? = TranscriptEventCache.event(rowID: row.id, payload: payload)
        else { return nil }
        return WorkspaceSayRecord(toolName: use.name, input: use.input, resultText: result.text)
    }

    private func successfulCodexImageRequest(_ use: AgentToolUse) -> CodexImageViewRequest? {
        guard row.resultPayload != nil, !row.isError, row.refusal == nil else { return nil }
        return CodexImageViewRequest(use: use)
    }

    private var orphanResult: AgentToolResult? {
        guard case .toolResult(let result)? = event else { return nil }
        return result
    }

    private var permissionAsk: PermissionAsk? {
        guard case .permissionAsk(let ask)? = event else { return nil }
        return ask
    }

    private var initInfo: AgentInit? {
        guard case .initialized(let info)? = event else { return nil }
        return info
    }

    private var backgroundWake: BackgroundWake? {
        guard case .subagent(.reported(let report))? = event else { return nil }
        return BackgroundWake(report)
    }

    private var toolResult: AgentToolResult? {
        guard isExpanded, let payload = row.resultPayload,
              case .toolResult(let result)? = TranscriptEventCache.event(rowID: row.id, payload: payload)
        else { return nil }
        return result
    }

    private var userText: String {
        UserTurnPrompt.text(in: row.payload)
    }
}
