import Foundation

public func newID() -> String { UUID().uuidString.lowercased() }

public struct Repo: Identifiable, Sendable, Hashable, Codable {
    public var id: RepoID
    public var name: String
    public var path: String
    public var defaultBranch: String
    public var accent: String
    public var sortOrder: Int
    public var collapsed: Bool
    public var hidden: Bool
    public var createdAt: Date
    public var iconPath: String?
    public var iconSource: RepoIconSource
    public var profileID: ProfileID

    public init(
        id: RepoID = .new(),
        name: String,
        path: String,
        defaultBranch: String = "main",
        accent: String = Accent.all[0],
        sortOrder: Int = 0,
        collapsed: Bool = false,
        hidden: Bool = false,
        createdAt: Date = Date(),
        iconPath: String? = nil,
        iconSource: RepoIconSource = .undetected,
        profileID: ProfileID = .initial
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.defaultBranch = defaultBranch
        self.accent = accent
        self.sortOrder = sortOrder
        self.collapsed = collapsed
        self.hidden = hidden
        self.createdAt = createdAt
        self.iconPath = iconPath
        self.iconSource = iconSource
        self.profileID = profileID
    }

    public var hasIcon: Bool { iconPath != nil && iconSource.drawsIcon }
}

public enum RepoIconSource: String, Sendable, Codable, CaseIterable, Hashable {
    case undetected
    case monogram
    case detected
    case chosen

    public var drawsIcon: Bool {
        switch self {
        case .undetected, .monogram: false
        case .detected, .chosen: true
        }
    }
}

public enum Accent {
    public static let all = [
        "4C8DF6", "22A06B", "E2725B", "9B6DE0", "D9A21B",
        "2FA8A8", "D8608C", "6C7A89", "E06C2A", "5B8C2A",
    ]

    public static func next(usedBy repos: [Repo]) -> String {
        let used = Set(repos.map(\.accent))
        return all.first { !used.contains($0) } ?? all[repos.count % all.count]
    }
}

public enum WorkspaceState: String, Sendable, Codable, CaseIterable {
    case active
    case archived
}

public enum SetupState: String, Sendable, Codable, CaseIterable, Hashable {
    case pending
    case running
    case succeeded
    case failed
    case ignored
    case skipped
}

public struct Workspace: Identifiable, Sendable, Hashable, Codable {
    public var id: WorkspaceID
    public var repoID: RepoID
    public var name: String
    public var branch: String
    public var path: String
    public var baseBranch: String
    public internal(set) var state: WorkspaceState
    public internal(set) var setupState: SetupState
    public internal(set) var setupLog: String
    public var sortOrder: Int
    public var createdAt: Date
    public var lastActivityAt: Date
    public var archivedAt: Date?
    public var additions: Int
    public var deletions: Int
    public var changedFiles: Int
    public var unread: Bool
    public var pinned: Bool
    public var colour: String?
    public var origin: WorkspaceOrigin
    public var port: Int
    public var pullRequestNumber: Int?
    public internal(set) var isOrchestrator: Bool

    init(
        id: WorkspaceID = .new(),
        repoID: RepoID,
        name: String,
        branch: String,
        path: String,
        baseBranch: String,
        state: WorkspaceState = .active,
        setupState: SetupState = .pending,
        setupLog: String = "",
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        lastActivityAt: Date = Date(),
        archivedAt: Date? = nil,
        additions: Int = 0,
        deletions: Int = 0,
        changedFiles: Int = 0,
        unread: Bool = false,
        pinned: Bool = false,
        colour: String? = nil,
        origin: WorkspaceOrigin = .user,
        port: Int = 0,
        pullRequestNumber: Int? = nil,
        isOrchestrator: Bool = false
    ) {
        self.id = id
        self.repoID = repoID
        self.name = name
        self.branch = branch
        self.path = path
        self.baseBranch = baseBranch
        self.state = state
        self.setupState = setupState
        self.setupLog = setupLog
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.archivedAt = archivedAt
        self.additions = additions
        self.deletions = deletions
        self.changedFiles = changedFiles
        self.unread = unread
        self.pinned = pinned
        self.colour = colour
        self.origin = origin
        self.port = port
        self.pullRequestNumber = pullRequestNumber
        self.isOrchestrator = isOrchestrator
    }

    public init(
        id: WorkspaceID = .new(),
        repoID: RepoID,
        name: String,
        branch: String,
        path: String,
        baseBranch: String,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        lastActivityAt: Date = Date(),
        additions: Int = 0,
        deletions: Int = 0,
        changedFiles: Int = 0,
        unread: Bool = false,
        pinned: Bool = false,
        colour: String? = nil,
        origin: WorkspaceOrigin = .user,
        isOrchestrator: Bool = false
    ) {
        self.init(
            id: id,
            repoID: repoID,
            name: name,
            branch: branch,
            path: path,
            baseBranch: baseBranch,
            state: .active,
            setupState: .pending,
            setupLog: "",
            sortOrder: sortOrder,
            createdAt: createdAt,
            lastActivityAt: lastActivityAt,
            archivedAt: nil,
            additions: additions,
            deletions: deletions,
            changedFiles: changedFiles,
            unread: unread,
            pinned: pinned,
            colour: colour,
            origin: origin,
            port: 0,
            isOrchestrator: isOrchestrator
        )
    }

    public var hasDiff: Bool { additions > 0 || deletions > 0 }
}

public enum SessionState: String, Sendable, Codable, CaseIterable, Hashable {
    case idle
    case running
    case waiting
    case failed
    case cancelled
}

public enum PermissionMode: String, Sendable, Codable, CaseIterable {
    case auto
    case acceptEdits
    case autoReview
    case bypassPermissions
    case plan

    public var label: String { label(on: .claudeCode) }
}

public struct Session: Identifiable, Sendable, Hashable, Codable {
    public var id: SessionID
    public var workspaceID: WorkspaceID?
    public var parentSessionID: SessionID?
    public var sideConversationParentID: SessionID?
    public var title: String
    public var agentSessionID: String?
    public var model: String
    public var effort: String
    public var agentKind: AgentKind {
        didSet {
            permissionMode = permissionMode.nearest(on: agentKind)
            interactionMode = interactionMode.nearest(on: agentKind)
        }
    }
    public var interactionMode: InteractionMode {
        didSet { interactionMode = interactionMode.nearest(on: agentKind) }
    }
    public var permissionMode: PermissionMode {
        didSet { permissionMode = permissionMode.nearest(on: agentKind) }
    }
    public internal(set) var state: SessionState
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var archivedAt: Date?
    public var lastReadSeq: Int
    public var inputTokens: Int
    public var outputTokens: Int
    public var costUSD: Double
    public var contextTokens: Int
    public internal(set) var accountID: AgentAccountID?

    init(
        id: SessionID = .new(),
        workspaceID: WorkspaceID?,
        parentSessionID: SessionID? = nil,
        sideConversationParentID: SessionID? = nil,
        title: String = PaneNaming.chat,
        agentSessionID: String? = nil,
        model: String = AppDefaults.fallbackModel,
        effort: String = AppDefaults.fallbackEffort,
        agentKind: AgentKind = .claudeCode,
        permissionMode: PermissionMode = AppDefaults.fallbackPermissionMode,
        interactionMode: InteractionMode = .build,
        state: SessionState = .idle,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        archivedAt: Date? = nil,
        lastReadSeq: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        costUSD: Double = 0,
        contextTokens: Int = 0
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.parentSessionID = parentSessionID
        self.sideConversationParentID = sideConversationParentID
        self.title = title
        self.agentSessionID = agentSessionID
        self.model = model
        self.effort = effort
        self.agentKind = agentKind
        self.permissionMode = permissionMode.nearest(on: agentKind)
        self.interactionMode = interactionMode.nearest(on: agentKind)
        self.state = state
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
        self.lastReadSeq = lastReadSeq
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.contextTokens = contextTokens
    }

    public init(
        id: SessionID = .new(),
        workspaceID: WorkspaceID?,
        parentSessionID: SessionID? = nil,
        sideConversationParentID: SessionID? = nil,
        title: String = PaneNaming.chat,
        agentSessionID: String? = nil,
        model: String = AppDefaults.fallbackModel,
        effort: String = AppDefaults.fallbackEffort,
        agentKind: AgentKind = .claudeCode,
        permissionMode: PermissionMode = AppDefaults.fallbackPermissionMode,
        interactionMode: InteractionMode = .build,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastReadSeq: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        costUSD: Double = 0,
        contextTokens: Int = 0
    ) {
        self.init(
            id: id,
            workspaceID: workspaceID,
            parentSessionID: parentSessionID,
            sideConversationParentID: sideConversationParentID,
            title: title,
            agentSessionID: agentSessionID,
            model: model,
            effort: effort,
            agentKind: agentKind,
            permissionMode: permissionMode,
            interactionMode: interactionMode,
            state: .idle,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt,
            archivedAt: nil,
            lastReadSeq: lastReadSeq,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            costUSD: costUSD,
            contextTokens: contextTokens
        )
    }
}

public enum MessageKind: String, Sendable, Codable, CaseIterable {
    case user
    case assistantText
    case thinking
    case toolUse
    case toolResult
    case permissionAsk
    case result
    case error
    case system
    case notice
    case crew
    case suggestion
    case handoff

    public var opensTurn: Bool {
        self == .user || self == .crew
    }
}

public struct Message: Identifiable, Sendable, Hashable, Codable {
    public var id: Int64
    public var sessionID: SessionID
    public var seq: Int
    public var kind: MessageKind
    public var payload: Data
    public var createdAt: Date
    public var durationMS: Int?
    public var refID: String?

    public init(
        id: Int64 = 0,
        sessionID: SessionID,
        seq: Int,
        kind: MessageKind,
        payload: Data,
        createdAt: Date = Date(),
        durationMS: Int? = nil,
        refID: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.seq = seq
        self.kind = kind
        self.payload = payload
        self.createdAt = createdAt
        self.durationMS = durationMS
        self.refID = refID
    }
}

public struct TerminalTab: Identifiable, Sendable, Hashable, Codable {
    public var id: TerminalTabID
    public var workspaceID: WorkspaceID
    public var title: String
    public var sortOrder: Int

    public init(id: TerminalTabID = .new(), workspaceID: WorkspaceID, title: String, sortOrder: Int = 0) {
        self.id = id
        self.workspaceID = workspaceID
        self.title = title
        self.sortOrder = sortOrder
    }
}

public struct PullRequest: Sendable, Hashable, Codable {
    public enum Checks: String, Sendable, Codable {
        case none
        case pending
        case passing
        case failing
        case unavailable
    }

    public var number: Int
    public var title: String
    public var url: String
    public var state: String
    public var isDraft: Bool
    public var mergeable: String?
    public var checks: Checks
    public var checksSummary: String
    public var reviewDecision: String?
    public var branch: String
    public var baseBranch: String
    public var closedAt: Date?
    public var headCommit: String?
    public var author: String?
    public var isFromFork: Bool?
    public var hasUnfinishedChecks: Bool?
    public var hasFixableCheckFailure: Bool?

    public init(
        number: Int,
        title: String,
        url: String,
        state: String,
        isDraft: Bool = false,
        mergeable: String? = nil,
        checks: Checks = .none,
        checksSummary: String = "",
        reviewDecision: String? = nil,
        branch: String = "",
        baseBranch: String = "",
        closedAt: Date? = nil,
        headCommit: String? = nil,
        author: String? = nil,
        isFromFork: Bool? = nil,
        hasUnfinishedChecks: Bool? = nil,
        hasFixableCheckFailure: Bool? = nil
    ) {
        self.number = number
        self.title = title
        self.url = url
        self.state = state
        self.isDraft = isDraft
        self.mergeable = mergeable
        self.checks = checks
        self.checksSummary = checksSummary
        self.reviewDecision = reviewDecision
        self.branch = branch
        self.baseBranch = baseBranch
        self.closedAt = closedAt
        self.headCommit = headCommit
        self.author = author
        self.isFromFork = isFromFork
        self.hasUnfinishedChecks = hasUnfinishedChecks
        self.hasFixableCheckFailure = hasFixableCheckFailure
    }

    public func targetBranch(or fallback: String) -> String {
        baseBranch.isEmpty ? fallback : baseBranch
    }
}

public enum AgentKind: String, Sendable, Codable, CaseIterable, Identifiable {
    case claudeCode
    case codex
    case grok
    case antigravity
    case cursor
    case openCode

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .grok: "Grok"
        case .antigravity: "Antigravity"
        case .cursor: "Cursor"
        case .openCode: "OpenCode"
        }
    }

    public var offersOutputStyle: Bool { self == .claudeCode }

    public var executableName: String {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .grok: "grok"
        case .antigravity: "agy"
        case .cursor: "cursor-agent"
        case .openCode: "opencode"
        }
    }

    public var configPath: String {
        let home = NSHomeDirectory()
        switch self {
        case .claudeCode: return "\(home)/.claude/settings.json"
        case .codex: return "\(home)/.codex/config.toml"
        case .grok: return "\(home)/.grok/config.toml"
        case .antigravity: return "\(home)/.gemini/config"
        case .cursor: return "\(home)/.cursor"
        case .openCode: return "\(home)/.opencode"
        }
    }

    public var loginCommand: String {
        ([executableName] + loginArguments).joined(separator: " ")
    }

    public var loginArguments: [String] {
        switch self {
        case .claudeCode: ["auth", "login"]
        case .codex, .grok, .cursor: ["login"]
        case .antigravity: []
        case .openCode: ["auth", "login"]
        }
    }

    public var canRunWorkspaces: Bool {
        switch self {
        case .claudeCode, .codex, .grok, .antigravity: true
        case .cursor, .openCode: false
        }
    }

    public var announcesModelEfforts: Bool {
        switch self {
        case .codex, .grok: true
        case .claudeCode, .antigravity, .cursor, .openCode: false
        }
    }

    public var acceptsMidTurnMessage: Bool {
        switch self {
        case .claudeCode, .codex: true
        case .grok, .antigravity, .cursor, .openCode: false
        }
    }

    public static var runnable: [AgentKind] { allCases.filter(\.canRunWorkspaces) }

    public static var runnableSentence: String {
        let names = runnable.map(\.label)
        guard let last = names.last else { return "no agent Unified Dev can run" }
        guard names.count > 1 else { return last }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }
}
