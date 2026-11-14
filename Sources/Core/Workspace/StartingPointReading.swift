import Foundation

public struct StartingPointReading: Sendable, Hashable {
    public let pullRequests: PullRequestsAwaitingViewer
    public let issues: [AssignedIssue]
    public let branches: [RecentBranch]
    public let readAt: Date

    public init(
        pullRequests: PullRequestsAwaitingViewer = PullRequestsAwaitingViewer(),
        issues: [AssignedIssue] = [],
        branches: [RecentBranch] = [],
        readAt: Date
    ) {
        self.pullRequests = pullRequests
        self.issues = issues
        self.branches = branches
        self.readAt = readAt
    }
}

public struct StartingPointReadingRequest: Sendable, Hashable {
    public let repoPath: String
    public let asksGitHub: Bool

    public init?(repoPath: String, offersPullRequests: Bool?, pullRequests: PullRequestLoad) {
        guard let offersPullRequests, pullRequests != .loading else { return nil }
        self.repoPath = repoPath
        self.asksGitHub = offersPullRequests && pullRequests.answered
    }
}
