import Foundation

extension GitHub {
    static let viewerListLimit = 10

    public static func pullRequestsAwaitingViewer(
        repoPath: String
    ) async -> (found: PullRequestsAwaitingViewer, isWhole: Bool) {
        let limit = String(viewerListLimit)
        async let review = listedRequests(
            ["pr", "list", "--state", "open", "--search", "review-requested:@me", "--limit", limit, "--json", summaryFields],
            repoPath: repoPath
        )
        async let authored = listedRequests(
            ["pr", "list", "--state", "open", "--author", "@me", "--limit", limit, "--json", summaryFields],
            repoPath: repoPath
        )
        let (readReview, readAuthored) = await (review, authored)
        let found = PullRequestsAwaitingViewer(reviewRequested: readReview ?? [], authored: readAuthored ?? [])
        return (found, readReview != nil && readAuthored != nil)
    }

    private static func listedRequests(_ arguments: [String], repoPath: String) async -> [PullRequestListing]? {
        guard let result = try? await run("gh", arguments, cwd: repoPath, timeout: .seconds(20)), result.ok,
              let requests = try? decodePullRequestListings(from: Data(result.stdout.utf8)) else { return nil }
        return WorkspaceCheckoutPlan.offered(requests, limit: viewerListLimit)
    }
}
