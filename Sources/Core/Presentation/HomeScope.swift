import Foundation

public enum HomeScope: String, Hashable, Sendable, CaseIterable, Codable {
    case all
    case needsYou
    case running
    case live
    case archived
    case workspaces
    case transcripts

    public static func offered(searching: Bool) -> [HomeScope] {
        searching
            ? [.all, .workspaces, .transcripts, .archived]
            : [.all, .archived]
    }

    public static func resting(searching: Bool) -> HomeScope {
        .all
    }

    public func label(searching: Bool) -> String {
        switch self {
        case .all: searching ? "Everything" : "All"
        case .needsYou: "Needs you"
        case .running: "Running"
        case .live: "Live"
        case .archived: "Archived"
        case .workspaces: "Workspaces"
        case .transcripts: "Transcripts"
        }
    }

    public static func settle(_ scope: HomeScope, searching: Bool) -> HomeScope {
        offered(searching: searching).contains(scope) ? scope : resting(searching: searching)
    }

    public var showsWorkspaces: Bool { self != .transcripts }

    public var showsFootprints: Bool { self == .archived }

    public var showsTranscripts: Bool {
        switch self {
        case .all, .transcripts, .archived: true
        default: false
        }
    }

    public func includesTranscript(isArchived: Bool) -> Bool {
        switch self {
        case .archived: isArchived
        default: showsTranscripts
        }
    }

    public func includes(_ row: HomeRow, activity: HomeActivity) -> Bool {
        switch self {
        case .all, .workspaces: true
        case .needsYou: activity.needsYou(row.workspace)
        case .running: activity.isRunning(row.workspace)
        case .live: !row.isArchived
        case .archived: row.isArchived
        case .transcripts: false
        }
    }
}

public struct HomeActivity: Sendable, Equatable {
    public var running: Set<WorkspaceID>
    public var waiting: Set<WorkspaceID>

    public init(running: Set<WorkspaceID> = [], waiting: Set<WorkspaceID> = []) {
        self.running = running
        self.waiting = waiting
    }

    public func isRunning(_ workspace: Workspace) -> Bool {
        running.contains(workspace.id)
    }

    public func needsYou(_ workspace: Workspace) -> Bool {
        guard workspace.state == .active else { return false }
        return waiting.contains(workspace.id) || WorkspaceUnreadMark.isUnread(workspace)
    }
}

public struct HomeScopeCounts: Sendable, Equatable {
    public var needsYou = 0
    public var running = 0
    public var live = 0
    public var archived = 0
    public var workspaces = 0
    public var transcripts = 0
    public var transcriptWorkspaces = 0
    public var profiles = 0
    public var projects = 0
    public var liveProjects = 0
    public var archivedProjects = 0

    public init() {}

    public func badge(of scope: HomeScope, searching: Bool) -> Int? {
        guard scope == .all || scope == .archived else { return nil }
        let value = count(of: scope, searching: searching)
        return value == 0 ? nil : value
    }

    public func count(of scope: HomeScope, searching: Bool) -> Int {
        switch scope {
        case .all: searching ? workspaces + transcripts + profiles : live + archived
        case .needsYou: needsYou
        case .running: running
        case .live: live
        case .archived: archived
        case .workspaces: workspaces
        case .transcripts: transcripts
        }
    }
}
