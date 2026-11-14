import Foundation

public extension PermissionMode {
    func label(on kind: AgentKind) -> String {
        switch kind {
        case .codex: codexLabel
        case .grok: grokLabel
        case .antigravity: antigravityLabel
        case .claudeCode, .cursor, .openCode: claudeCodeLabel
        }
    }

    func summary(on kind: AgentKind) -> String {
        switch kind {
        case .codex: codexSummary
        case .grok: grokSummary
        case .antigravity: antigravitySummary
        case .claudeCode, .cursor, .openCode: claudeCodeSummary
        }
    }

    func nearest(on kind: AgentKind) -> PermissionMode {
        switch self {
        case .autoReview: kind == .codex ? self : .auto
        case .plan: kind == .codex ? .auto : self
        case .auto, .acceptEdits, .bypassPermissions: self
        }
    }

    private var claudeCodeLabel: String {
        switch self {
        case .auto: "Auto"
        case .acceptEdits: "Accept edits"
        case .autoReview: "Auto"
        case .bypassPermissions: "Bypass permissions"
        case .plan: "Plan"
        }
    }

    private var claudeCodeSummary: String {
        switch self {
        case .auto, .autoReview:
            "Claude checks each tool call for risk, runs the ones it judges lower risk, and blocks "
                + "the rest."
        case .acceptEdits: "File edits and common file commands are approved for you."
        case .bypassPermissions: "No further prompts. Everything runs."
        case .plan: "Research and propose changes without making them."
        }
    }

    private var codexLabel: String {
        switch self {
        case .auto: "Read only"
        case .acceptEdits: "Ask for approval"
        case .autoReview: "Approve for me"
        case .bypassPermissions: "Full access"
        case .plan: "Plan"
        }
    }

    private var codexSummary: String {
        switch self {
        case .auto:
            "Codex can read files in the workspace. Approval is required to edit files or reach "
                + "the internet."
        case .acceptEdits:
            "Codex can read and edit files in the workspace, and run commands. Approval is "
                + "required to reach the internet or edit other files."
        case .autoReview: "Only ask for actions detected as potentially unsafe."
        case .bypassPermissions:
            "Codex can edit files outside the workspace and reach the internet without asking."
        case .plan: "Research and propose changes without making them."
        }
    }

    private var grokLabel: String {
        switch self {
        case .auto: "Auto"
        case .acceptEdits: "Accept edits"
        case .autoReview: "Auto"
        case .bypassPermissions: "Always approve"
        case .plan: "Plan"
        }
    }

    private var grokSummary: String {
        switch self {
        case .auto, .autoReview:
            "Grok runs the calls the safety check allows, and asks about or blocks the rest."
        case .acceptEdits: "File edits run without a prompt. Other calls still ask."
        case .bypassPermissions: "No further prompts. Everything runs."
        case .plan: "Research and propose changes without making them."
        }
    }

    private var antigravityLabel: String {
        switch self {
        case .auto, .autoReview: "Auto"
        case .acceptEdits: "Accept edits"
        case .bypassPermissions: "Skip permissions"
        case .plan: "Plan"
        }
    }

    private var antigravitySummary: String {
        switch self {
        case .auto, .autoReview: "Edits and safe commands run. Irreversible actions still ask."
        case .acceptEdits: "File edits in the workspace run without a prompt. Commands still ask."
        case .bypassPermissions: "No further prompts. Everything runs."
        case .plan: "Plan carefully before making any change."
        }
    }
}

public struct PermissionModeChoice: Identifiable, Hashable, Sendable {
    public var mode: PermissionMode
    public var label: String
    public var summary: String

    public var id: PermissionMode { mode }

    public init(mode: PermissionMode, on kind: AgentKind) {
        self.mode = mode
        self.label = mode.label(on: kind)
        self.summary = mode.summary(on: kind)
    }
}
