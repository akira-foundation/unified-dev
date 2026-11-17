import Foundation

public enum SearchPanelRow: Equatable, Sendable, Identifiable {
    case workspace(SearchPanelWorkspaceHit)
    case transcript(SearchPanelTranscriptHit)
    case command(SearchPanelCommandHit)
    case profile(SearchPanelProfileHit)

    public var id: String {
        switch self {
        case .workspace(let hit): "workspace:\(hit.workspace.id.rawValue)"
        case .transcript(let hit): "transcript:\(hit.result.workspaceID.rawValue)"
        case .command(let hit): "command:\(hit.item.action.rawValue)"
        case .profile(let hit): "profile:\(hit.profile.id.rawValue)"
        }
    }

    public var drillable: WorkspaceID? {
        switch self {
        case .workspace(let hit): hit.workspace.id
        case .transcript(let hit): hit.result.workspaceID
        case .command, .profile: nil
        }
    }
}

public struct SearchPanelWorkspaceHit: Equatable, Sendable, Identifiable {
    public var workspace: Workspace
    public var repo: Repo?
    public var highlights: [Int]
    public var match: String?
    public var isArchived: Bool
    public var waiting: SearchPanelWaiting?
    public var score: Int

    public var id: WorkspaceID { workspace.id }

    public init(
        workspace: Workspace,
        repo: Repo? = nil,
        highlights: [Int] = [],
        match: String? = nil,
        isArchived: Bool = false,
        waiting: SearchPanelWaiting? = nil,
        score: Int = 0
    ) {
        self.workspace = workspace
        self.repo = repo
        self.highlights = highlights
        self.match = match
        self.isArchived = isArchived
        self.waiting = waiting
        self.score = score
    }
}

public enum SearchPanelWaiting: String, Equatable, Sendable {
    case askedAQuestion
    case turnFinished

    public var label: String {
        switch self {
        case .askedAQuestion: "asked a question"
        case .turnFinished: "turn finished"
        }
    }
}

public struct SearchPanelTranscriptHit: Equatable, Sendable, Identifiable {
    public var result: TranscriptWorkspaceMatches
    public var workspace: Workspace?
    public var repo: Repo?
    public var isArchived: Bool

    public var id: WorkspaceID { result.workspaceID }

    public init(
        result: TranscriptWorkspaceMatches,
        workspace: Workspace?,
        repo: Repo?,
        isArchived: Bool
    ) {
        self.result = result
        self.workspace = workspace
        self.repo = repo
        self.isArchived = isArchived
    }
}

public struct SearchPanelCommandHit: Equatable, Sendable, Identifiable {
    public var item: MenuBarItem
    public var highlights: [Int]
    public var score: Int

    public var id: MenuBarAction { item.action }

    public init(item: MenuBarItem, highlights: [Int] = [], score: Int = 0) {
        self.item = item
        self.highlights = highlights
        self.score = score
    }
}

public struct SearchPanelProfileHit: Equatable, Sendable, Identifiable {
    public var profile: Profile
    public var highlights: [Int]
    public var score: Int
    public var keyText: String?

    public var id: ProfileID { profile.id }

    public init(profile: Profile, highlights: [Int] = [], score: Int = 0, keyText: String? = nil) {
        self.profile = profile
        self.highlights = highlights
        self.score = score
        self.keyText = keyText
    }
}
