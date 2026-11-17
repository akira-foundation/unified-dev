import Foundation

public enum PullRequestReader: Sendable, CaseIterable {
    case pullRequestBar
    case checksTab
    case checksNotification

    public var interval: Duration {
        switch self {
        case .pullRequestBar, .checksTab: .seconds(20)
        case .checksNotification: .seconds(30)
        }
    }

    public var maxAge: Duration { interval }
}

public enum CheckRunsRead: Sendable, Hashable {
    case runs([CheckRun])
    case unreadable

    public var runs: [CheckRun] {
        guard case .runs(let runs) = self else { return [] }
        return runs
    }
}

public struct PullRequestReading: Sendable {
    public let pullRequest: PullRequestRead
    public let checks: CheckRunsRead?

    public init(pullRequest: PullRequestRead, checks: CheckRunsRead?) {
        self.pullRequest = pullRequest
        self.checks = checks
    }

    init(_ snapshot: PullRequestSnapshot?) {
        guard let snapshot else {
            self.init(pullRequest: .current(nil), checks: .runs([]))
            return
        }
        self.init(
            pullRequest: .current(snapshot.pullRequest),
            checks: snapshot.pullRequest.checks == .unavailable ? .unreadable : .runs(snapshot.runs)
        )
    }
}

struct WorkspacePullRequestKey: Hashable, Sendable {
    let workspace: WorkspaceID
    let path: String
    let branch: String
    let baseBranch: String
    let pullRequestNumber: Int?
    let createdAt: Date
    let login: GitHubLogin

    init(_ workspace: Workspace, login: GitHubLogin) {
        self.workspace = workspace.id
        path = workspace.path
        branch = workspace.branch
        baseBranch = workspace.baseBranch
        pullRequestNumber = workspace.pullRequestNumber
        createdAt = workspace.createdAt
        self.login = login
    }
}

public extension GitHub {
    static func readPullRequestAndChecks(for workspace: Workspace, maxAge: Duration) async -> PullRequestReading {
        do {
            return PullRequestReading(try await snapshot(for: workspace, maxAge: maxAge))
        } catch {
            return PullRequestReading(pullRequest: .unavailable(.classify(error)), checks: nil)
        }
    }

    internal static let workspaceReadings = SharedReadings<WorkspacePullRequestKey, PullRequestSnapshot?>()

    internal static func snapshot(for workspace: Workspace, maxAge: Duration) async throws -> PullRequestSnapshot? {
        try await workspaceReadings.value(
            for: WorkspacePullRequestKey(workspace, login: await login(forDirectory: workspace.path)),
            notOlderThan: maxAge
        ) {
            try await snapshot(for: workspace, onBranch: await headBranch(of: workspace), maxAge: .zero)
        }
    }
}
