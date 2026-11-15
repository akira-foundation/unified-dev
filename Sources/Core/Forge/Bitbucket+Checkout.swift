import Foundation

extension BitbucketPullRequestPayload {
    var listing: PullRequestListing {
        PullRequestListing(
            number: id ?? 0,
            title: title ?? "",
            author: author?.name ?? "",
            headRefName: source?.branch?.name ?? "",
            baseRefName: destination?.branch?.name ?? "",
            isDraft: draft ?? false,
            state: unifiedState,
            isCrossRepository: isFromFork ?? true,
            headRepositoryOwner: sourceRepository?.split(separator: "/").first.map(String.init)
        )
    }
}

public extension Bitbucket {
    static let pullRequestsListed = 30

    internal static func openPullRequestsArguments(in repository: ForgeRepository, context: String) -> [String] {
        [
            "api", "\(path(of: repository))/pullrequests",
            "--param", "state=OPEN", "--param", "sort=-updated_on",
            "--param", "pagelen=\(pullRequestsListed)", "--context", context,
        ]
    }

    internal static func checkoutArguments(
        number: Int, localBranch: String, in repository: ForgeRepository, context: String
    ) -> [String] {
        [
            "pr", "checkout", String(number), "--branch", localBranch,
            "--workspace", repository.owner, "--repo", repository.name, "--context", context,
        ]
    }

    internal static func trackingConfiguration(for request: PullRequestListing, localBranch: String) -> [[String]] {
        guard !request.isCrossRepository, Git.isValidBranchName(request.headRefName) else { return [] }
        return [
            ["config", "branch.\(localBranch).remote", "origin"],
            ["config", "branch.\(localBranch).merge", "refs/heads/\(request.headRefName)"],
        ]
    }

    static func openPullRequests(repoPath: String) async throws -> [PullRequestListing] {
        let (repository, context) = try await connection(in: repoPath)
        let arguments = openPullRequestsArguments(in: repository, context: context)
        let result = try await run(arguments, directory: repoPath)
        guard result.ok else { throw shellError(arguments, result: result) }
        return WorkspaceCheckoutPlan.offered(try decodePullRequests(result.stdout).map(\.listing))
    }

    static func pullRequestSummary(number: Int, repoPath: String) async throws -> PullRequestListing {
        guard number > 0 else { throw GitHubError("\(number) is not a pull request number") }
        let (repository, context) = try await connection(in: repoPath)
        let arguments = ["api", "\(path(of: repository))/pullrequests/\(number)", "--context", context]
        let result = try await run(arguments, directory: repoPath)
        guard result.ok else {
            throw GitHubError("Could not read pull request #\(number): " + (printedStatus(of: result) ?? result.stderr))
        }
        return try decodePullRequest(result.stdout).listing
    }

    internal static func checkoutRefusal(for request: PullRequestListing, localBranch: String) -> String? {
        guard request.number > 0 else { return "\(request.number) is not a pull request number" }
        guard Git.isValidBranchName(localBranch) else { return "'\(localBranch)' is not a valid branch name" }
        guard Git.isValidBranchName(request.headRefName) else {
            return "#\(request.number) comes from a branch named '\(request.headRefName)', which git cannot fetch safely"
        }
        return nil
    }

    static func checkoutPullRequest(_ request: PullRequestListing, into worktree: String, localBranch: String) async throws {
        if let refusal = checkoutRefusal(for: request, localBranch: localBranch) { throw GitHubError(refusal) }
        let (repository, context) = try await connection(in: worktree)
        let arguments = checkoutArguments(number: request.number, localBranch: localBranch, in: repository, context: context)
        let result = try await run(arguments, directory: worktree, timeout: .seconds(120))
        guard result.ok else {
            throw GitHubError(
                "Could not check out pull request #\(request.number): "
                    + (result.stderr.isEmpty ? result.stdout : result.stderr)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .suffix(400)
            )
        }
        for setting in trackingConfiguration(for: request, localBranch: localBranch) {
            _ = try? await Git.run(setting, in: worktree)
        }
    }
}
