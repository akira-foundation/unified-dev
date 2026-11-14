import Foundation

public struct StartingPointReading: Sendable, Hashable {
    public let pullRequests: PullRequestsAwaitingViewer
    public let issues: [AssignedIssue]
    public let branches: [RecentBranch]

    public init(
        pullRequests: PullRequestsAwaitingViewer = PullRequestsAwaitingViewer(),
        issues: [AssignedIssue] = [],
        branches: [RecentBranch] = []
    ) {
        self.pullRequests = pullRequests
        self.issues = issues
        self.branches = branches
    }
}
