import Foundation

public enum SetupTool: String, Sendable, Hashable, CaseIterable, Identifiable, Codable {
    case git
    case claudeCode
    case codex
    case grok
    case antigravity
    case gitHub
    case bitbucket

    public var id: String { rawValue }

    public var agentKind: AgentKind? {
        switch self {
        case .claudeCode: .claudeCode
        case .codex: .codex
        case .grok: .grok
        case .antigravity: .antigravity
        case .git, .gitHub, .bitbucket: nil
        }
    }

    public var title: String {
        switch self {
        case .git: "Git"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .grok: "Grok"
        case .antigravity: "Antigravity"
        case .gitHub: "GitHub CLI"
        case .bitbucket: "Bitbucket CLI"
        }
    }

    public var sentenceName: String {
        switch self {
        case .gitHub: "the GitHub CLI"
        case .bitbucket: "the Bitbucket CLI"
        case .git, .claudeCode, .codex, .grok, .antigravity: title
        }
    }

    public var purpose: String {
        switch self {
        case .git:
            "Every workspace is a real git worktree, so Unified Dev builds each one with git."
        case .claudeCode:
            "The agent Unified Dev runs in a worktree, and the one most people come here for."
        case .codex:
            "OpenAI's agent. Unified Dev can drive a workspace with it instead of Claude Code."
        case .grok:
            "xAI's agent. Unified Dev can drive a workspace with it instead of Claude Code or Codex."
        case .antigravity:
            "Google's agent, with Gemini and other models. Unified Dev can drive a workspace with it too."
        case .gitHub:
            "Pull requests, checks and merges. Everything else in Unified Dev works without it."
        case .bitbucket:
            "Pull requests and builds for repositories on Bitbucket. Only needed if you use Bitbucket."
        }
    }

    public var executableName: String {
        switch self {
        case .git: "git"
        case .claudeCode, .codex, .grok, .antigravity: agentKind?.executableName ?? rawValue
        case .gitHub: "gh"
        case .bitbucket: Bitbucket.executable
        }
    }

    public var isOptional: Bool { self == .bitbucket }

    public static let displayOrder: [SetupTool] = [.git, .claudeCode, .codex, .grok, .antigravity, .gitHub, .bitbucket]
}

public enum SetupOutcome: Sendable, Hashable {
    case pending
    case ready(detail: String?)
    case needsSignIn(detail: String?)
    case missing

    public var isSettled: Bool {
        if case .pending = self { return false }
        return true
    }

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var detail: String? {
        switch self {
        case .ready(let detail), .needsSignIn(let detail): detail
        case .pending, .missing: nil
        }
    }
}

public enum SetupSeverity: Sendable, Hashable, Comparable {
    case ok
    case note
    case problem
}

public struct SetupCheck: Sendable, Hashable, Identifiable {
    public var tool: SetupTool
    public var outcome: SetupOutcome

    public var id: String { tool.rawValue }

    public init(tool: SetupTool, outcome: SetupOutcome = .pending) {
        self.tool = tool
        self.outcome = outcome
    }
}

public struct SetupFix: Sendable, Hashable {
    public var summary: String
    public var command: String?
    public var url: URL?
    public var isInteractive: Bool

    public init(summary: String, command: String? = nil, url: URL? = nil, isInteractive: Bool = false) {
        self.summary = summary
        self.command = command
        self.url = url
        self.isInteractive = isInteractive
    }
}

public enum SetupVerdict: Sendable, Hashable {
    case checking
    case ready
    case readyWithNotes
    case blocked
}

public struct SetupReport: Sendable, Hashable {
    public var checks: [SetupCheck]

    public init(checks: [SetupCheck]) {
        self.checks = checks
    }

    public static var pending: SetupReport {
        SetupReport(checks: SetupTool.displayOrder.map { SetupCheck(tool: $0) })
    }

    public func outcome(for tool: SetupTool) -> SetupOutcome {
        checks.first { $0.tool == tool }?.outcome ?? .pending
    }

    public var isSettled: Bool {
        checks.allSatisfy { $0.outcome.isSettled }
    }

    public var hasRunnableAgent: Bool {
        SetupTool.displayOrder
            .filter { $0.agentKind?.canRunWorkspaces == true }
            .contains { outcome(for: $0).isReady }
    }

    private var agentsAreStillChecking: Bool {
        SetupTool.displayOrder
            .filter { $0.agentKind?.canRunWorkspaces == true }
            .contains { !outcome(for: $0).isSettled }
    }

    public var verdict: SetupVerdict {
        guard isSettled else { return .checking }
        if !outcome(for: .git).isReady { return .blocked }
        if !hasRunnableAgent { return .blocked }
        let everythingIsReady = checks.allSatisfy { $0.outcome.isReady }
        return everythingIsReady ? .ready : .readyWithNotes
    }

    public func severity(for tool: SetupTool) -> SetupSeverity {
        let outcome = outcome(for: tool)
        if outcome.isReady { return .ok }
        if !outcome.isSettled { return .note }

        switch tool {
        case .git:
            return .problem
        case .claudeCode, .codex, .grok, .antigravity:
            if hasRunnableAgent || agentsAreStillChecking { return .note }
            return .problem
        case .gitHub, .bitbucket:
            return .note
        }
    }

    public var blocking: [SetupCheck] {
        checks.filter { severity(for: $0.tool) == .problem }
    }
}

public extension SetupReport {
    var headline: String {
        switch verdict {
        case .checking: "Looking around"
        case .ready: "You are all set"
        case .readyWithNotes: "You are ready to go"
        case .blocked: "Nearly there"
        }
    }

    var sentence: String {
        switch verdict {
        case .checking:
            return "Unified Dev is checking what this Mac already has."
        case .ready:
            return "Everything Unified Dev uses is installed and signed in. Describe a task and it will build the worktree for you."
        case .readyWithNotes:
            return readyWithNotesSentence
        case .blocked:
            return blockedSentence
        }
    }

    private var readyWithNotesSentence: String {
        let quiet = checks
            .filter { !$0.tool.isOptional && !$0.outcome.isReady && severity(for: $0.tool) == .note }
            .map(\.tool.sentenceName)

        guard !quiet.isEmpty else {
            return "Unified Dev has what it needs. Describe a task and it will build the worktree for you."
        }
        let subject = quiet.count == 1 ? "it" : "them"
        return "Unified Dev has what it needs. \(list(quiet).capitalizedFirst) \(quiet.count == 1 ? "is" : "are") not set up, so only the parts that use \(subject) are off."
    }

    private var blockedSentence: String {
        let missingGit = !outcome(for: .git).isReady
        if missingGit && !hasRunnableAgent {
            return "Unified Dev needs git and an agent before it can build a workspace. Both are below."
        }
        if missingGit {
            return "Unified Dev builds every workspace with git, and cannot find it. There is one command below."
        }
        return "Unified Dev needs one agent it can drive. Claude Code or Codex, either is enough."
    }

    private func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return "\(items.dropLast().joined(separator: ", ")) and \(items[items.count - 1])"
        }
    }
}

public enum OnboardingTrigger: Sendable, Hashable {
    case firstRun
    case blocked
    case none
}

public enum OnboardingGate {
    public static let completedKey = "onboarding.completed"

    public static func trigger(hasCompletedBefore: Bool, verdict: SetupVerdict?) -> OnboardingTrigger {
        guard hasCompletedBefore else { return .firstRun }
        return verdict == .blocked ? .blocked : .none
    }

    public static func completes(verdict: SetupVerdict?) -> Bool {
        guard let verdict else { return true }
        return verdict != .blocked && verdict != .checking
    }
}
