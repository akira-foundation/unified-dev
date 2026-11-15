import Foundation

enum BitbucketCheckoutRoute: Sendable, Equatable {
    case bkt
    case keepLocal
    case fastForward
    case diverged

    static func choose(localExists: Bool, isFork: Bool, localHasServer: Bool, serverHasLocal: Bool) -> Self {
        guard localExists, !isFork else { return .bkt }
        if localHasServer { return .keepLocal }
        return serverHasLocal ? .fastForward : .diverged
    }
}

extension Bitbucket {
    static func serverReference(of request: PullRequestListing) -> String {
        "refs/remotes/origin/\(request.headRefName)"
    }

    static func serverFetchArguments(for request: PullRequestListing) -> [String] {
        ["fetch", "origin", "+refs/heads/\(request.headRefName):\(serverReference(of: request))"]
    }

    static func localCheckoutArguments(
        _ route: BitbucketCheckoutRoute, for request: PullRequestListing, localBranch: String
    ) -> [[String]] {
        switch route {
        case .bkt, .diverged: []
        case .keepLocal: [["checkout", localBranch, "--"]]
        case .fastForward: [["checkout", localBranch, "--"], ["merge", "--ff-only", serverReference(of: request)]]
        }
    }

    static func divergedRefusal(for request: PullRequestListing, localBranch: String) -> String {
        "Could not check out pull request #\(request.number): the local branch '\(localBranch)' and "
            + "'\(request.headRefName)' on Bitbucket have each moved on without the other. Nothing was changed; "
            + "rebase or rename the local branch, then try again."
    }

    static func checkoutRoute(
        for request: PullRequestListing, into worktree: String, localBranch: String
    ) async throws -> BitbucketCheckoutRoute {
        let local = "refs/heads/\(localBranch)"
        let found = try await Git.run(["rev-parse", "--verify", "--quiet", local], in: worktree)
        guard found.ok, !request.isCrossRepository else { return .bkt }
        let fetch = serverFetchArguments(for: request)
        let fetched = try await Git.runAgainstRemote(fetch, in: worktree, timeout: .seconds(120))
        guard fetched.ok else { throw shellError(fetch, result: fetched) }
        let server = serverReference(of: request)
        return BitbucketCheckoutRoute.choose(
            localExists: true,
            isFork: false,
            localHasServer: await Git.isAncestor(server, of: local, in: worktree),
            serverHasLocal: await Git.isAncestor(local, of: server, in: worktree)
        )
    }

    static func checkOutLocal(
        _ route: BitbucketCheckoutRoute, for request: PullRequestListing, into worktree: String, localBranch: String
    ) async throws {
        if route == .diverged { throw GitHubError(divergedRefusal(for: request, localBranch: localBranch)) }
        for arguments in localCheckoutArguments(route, for: request, localBranch: localBranch) {
            let result = try await Git.run(arguments, in: worktree)
            guard result.ok else {
                throw GitHubError(
                    "Could not check out pull request #\(request.number): "
                        + (result.stderr.isEmpty ? result.stdout : result.stderr)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .suffix(400)
                )
            }
        }
    }
}
