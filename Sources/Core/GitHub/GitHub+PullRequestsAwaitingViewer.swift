import Foundation

extension GitHub {
    static let awaitingViewerLimit = 10

    public static func pullRequestsAwaitingViewer(repoPath: String) async -> PullRequestsAwaitingViewer? {
        let limit = String(awaitingViewerLimit)
        async let review = listedRequests(
            ["pr", "list", "--state", "open", "--search", "review-requested:@me", "--limit", limit, "--json", summaryFields],
            repoPath: repoPath
        )
        async let authored = listedRequests(
            ["pr", "list", "--state", "open", "--author", "@me", "--limit", limit, "--json", summaryFields],
            repoPath: repoPath
        )
        let (readReview, readAuthored) = await (review, authored)
        guard let readReview, let readAuthored else { return nil }
        return PullRequestsAwaitingViewer(reviewRequested: readReview, authored: readAuthored)
    }

    private static func listedRequests(_ arguments: [String], repoPath: String) async -> [PullRequestListing]? {
        guard let result = try? await run("gh", arguments, cwd: repoPath, timeout: .seconds(20)), result.ok,
              let requests = try? decodePullRequestListings(from: Data(result.stdout.utf8)) else { return nil }
        return WorkspaceCheckoutPlan.offered(requests, limit: awaitingViewerLimit)
    }
}
