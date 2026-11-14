import Foundation

public struct PullRequestsAwaitingViewer: Sendable, Hashable {
    public let reviewRequested: [PullRequestListing]
    public let authored: [PullRequestListing]

    public init(reviewRequested: [PullRequestListing] = [], authored: [PullRequestListing] = []) {
        self.reviewRequested = reviewRequested
        self.authored = authored
    }
}
