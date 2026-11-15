import Foundation

enum BitbucketCheckoutRoute: Sendable, Equatable {
    case bkt
    case keepLocal
    case fastForward
    case diverged

    static func choose(localHasServer: Bool, serverHasLocal: Bool) -> Self {
        if localHasServer { return .keepLocal }
        return serverHasLocal ? .fastForward : .diverged
    }
}

struct BitbucketLocalCheckout: Sendable, Equatable {
    let route: BitbucketCheckoutRoute
    let remote: String

    static func remote(named base: String?) -> String {
        guard let base, Git.isValidBranchName(base), !base.contains("/") else { return "origin" }
        return base
    }

    func serverReference(of request: PullRequestListing) -> String {
        "refs/remotes/\(remote)/\(request.headRefName)"
    }

    func fetchArguments(for request: PullRequestListing) -> [String] {
        ["fetch", remote, "+refs/heads/\(request.headRefName):\(serverReference(of: request))"]
    }

    func checkoutArguments(for request: PullRequestListing, localBranch: String) -> [[String]] {
        switch route {
        case .bkt, .diverged: []
        case .keepLocal: [["checkout", localBranch, "--"]]
        case .fastForward: [["checkout", localBranch, "--"], ["merge", "--ff-only", serverReference(of: request)]]
        }
    }
}

extension Bitbucket {
    static func divergedRefusal(for request: PullRequestListing, localBranch: String) -> String {
        "Could not check out pull request #\(request.number): the local branch '\(localBranch)' does not contain "
            + "'\(request.headRefName)' as Bitbucket has it, and is not behind it either. Nothing was changed; "
            + "rebase or rename the local branch, then try again."
    }

    static func localCheckout(
        for request: PullRequestListing, into worktree: String, localBranch: String
    ) async throws -> BitbucketLocalCheckout {
        let local = "refs/heads/\(localBranch)"
        let base = try? await Git.repositoryContext(in: worktree).baseRemote
        var plan = BitbucketLocalCheckout(route: .bkt, remote: BitbucketLocalCheckout.remote(named: base))
        let found = try await Git.run(["rev-parse", "--verify", "--quiet", local], in: worktree)
        guard found.ok, !request.isCrossRepository else { return plan }
        let fetch = plan.fetchArguments(for: request)
        let fetched = try await Git.runAgainstRemote(fetch, in: worktree, timeout: .seconds(120))
        guard fetched.ok else { throw shellError(fetch, result: fetched) }
        let server = plan.serverReference(of: request)
        plan = BitbucketLocalCheckout(
            route: BitbucketCheckoutRoute.choose(
                localHasServer: await Git.isAncestor(server, of: local, in: worktree),
                serverHasLocal: await Git.isAncestor(local, of: server, in: worktree)
            ),
            remote: plan.remote
        )
        return plan
    }

    static func checkOutLocal(
        _ plan: BitbucketLocalCheckout, for request: PullRequestListing, into worktree: String, localBranch: String
    ) async throws {
        if plan.route == .diverged { throw GitHubError(divergedRefusal(for: request, localBranch: localBranch)) }
        for arguments in plan.checkoutArguments(for: request, localBranch: localBranch) {
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
