import Foundation

extension GitHub {
    static let awaitingViewerLimit = 10

    public static func pullRequestsAwaitingViewer(repoPath: String) async -> PullRequestsAwaitingViewer {
        let limit = String(awaitingViewerLimit)
        async let review = listedRequests(
            ["pr", "list", "--state", "open", "--search", "review-requested:@me", "--limit", limit, "--json", summaryFields],
            repoPath: repoPath
        )
        async let authored = listedRequests(
            ["pr", "list", "--state", "open", "--author", "@me", "--limit", limit, "--json", summaryFields],
            repoPath: repoPath
        )
        return PullRequestsAwaitingViewer(reviewRequested: await review, authored: await authored)
    }

    public static func issuesAssignedToViewer(repoPath: String) async -> [AssignedIssue] {
        let context = try? await Git.repositoryContext(in: repoPath)
        let repository = repositorySpecifier(context?.baseRemoteURL).map { ["--repo", $0] } ?? []
        let arguments = [
            "issue", "list", "--state", "open", "--assignee", "@me",
            "--limit", String(awaitingViewerLimit), "--json", "number,title",
        ] + repository
        guard let result = try? await run("gh", arguments, cwd: repoPath, timeout: .seconds(20), repositoryContext: context),
              result.ok else {
            return []
        }
        return decodeAssignedIssues(from: Data(result.stdout.utf8))
    }

    static func decodeAssignedIssues(from data: Data) -> [AssignedIssue] {
        struct Payload: Decodable {
            let number: Int?
            let title: String?
        }
        let payloads = (try? JSONDecoder().decode([Payload].self, from: data)) ?? []
        return payloads.compactMap { payload in
            guard let number = payload.number, number > 0 else { return nil }
            return AssignedIssue(number: number, title: payload.title ?? "")
        }
    }

    private static func listedRequests(_ arguments: [String], repoPath: String) async -> [PullRequestListing] {
        guard let result = try? await run("gh", arguments, cwd: repoPath, timeout: .seconds(20)), result.ok,
              let requests = try? decodePullRequestListings(from: Data(result.stdout.utf8)) else { return [] }
        return WorkspaceCheckoutPlan.offered(requests, limit: awaitingViewerLimit)
    }
}
