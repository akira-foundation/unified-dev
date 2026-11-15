import Foundation

extension Bitbucket {
    enum ViewerRole: String, Sendable, CaseIterable {
        case reviewer = "reviewers.uuid"
        case author = "author.uuid"
    }

    static func awaitingViewerArguments(
        _ role: ViewerRole, viewer: String, in repository: ForgeRepository, context: String
    ) -> [String]? {
        guard let uuid = BitbucketPipelineStep.canonicalUUID(viewer) else { return nil }
        return [
            "api", "\(path(of: repository))/pullrequests",
            "--param", "q=state=\"OPEN\" AND \(role.rawValue)=\"\(uuid)\"",
            "--param", "sort=-updated_on", "--param", "pagelen=\(GitHub.viewerListLimit)",
            "--context", context,
        ]
    }

    static func pullRequestsAwaitingViewer(repoPath: String) async -> (found: PullRequestsAwaitingViewer, isWhole: Bool) {
        guard let (repository, context) = try? await connection(in: repoPath),
              let viewer = await viewer(in: repoPath)
        else { return (PullRequestsAwaitingViewer(), false) }
        async let review = listed(.reviewer, viewer: viewer, in: repository, context: context, repoPath: repoPath)
        async let authored = listed(.author, viewer: viewer, in: repository, context: context, repoPath: repoPath)
        let (readReview, readAuthored) = await (review, authored)
        let found = PullRequestsAwaitingViewer(reviewRequested: readReview ?? [], authored: readAuthored ?? [])
        return (found, readReview != nil && readAuthored != nil)
    }

    private static func listed(
        _ role: ViewerRole, viewer: String, in repository: ForgeRepository, context: String, repoPath: String
    ) async -> [PullRequestListing]? {
        guard let arguments = awaitingViewerArguments(role, viewer: viewer, in: repository, context: context),
              let result = try? await run(arguments, directory: repoPath), result.ok,
              let found = try? decodePullRequests(result.stdout)
        else { return nil }
        return WorkspaceCheckoutPlan.offered(found.map(\.listing), limit: GitHub.viewerListLimit)
    }
}
