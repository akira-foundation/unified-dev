import Foundation

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
