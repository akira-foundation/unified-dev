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

public struct StartingPointReadingRequest: Sendable, Hashable {
    public let repoPath: String
    public let asksGitHub: Bool

    init(repoPath: String, asksGitHub: Bool) {
        self.repoPath = repoPath
        self.asksGitHub = asksGitHub
    }

    public init?(repoPath: String, offersPullRequests: Bool?, pullRequests: PullRequestLoad) {
        guard let offersPullRequests, pullRequests != .loading else { return nil }
        self.init(repoPath: repoPath, asksGitHub: offersPullRequests && pullRequests.isListed)
    }
}
