import Foundation

public extension GitHub {
    internal static var summaryFields: String {
        [
            "number", "title", "author", "headRefName", "baseRefName",
            "isDraft", "state", "isCrossRepository", "headRepositoryOwner",
        ].joined(separator: ",")
    }

    static func openPullRequests(repoPath: String, limit: Int = 30) async throws -> [PullRequestListing] {
        guard await isAvailable(directory: repoPath) else { return [] }
        let result = try await run(
            "gh",
            ["pr", "list", "--state", "open", "--limit", String(limit), "--json", summaryFields],
            cwd: repoPath,
            timeout: .seconds(20)
        )
        guard result.ok else {
            if indicatesNotAGitHubRepository(stderr: result.stderr) { return [] }
            throw GitHubError("gh pr list failed: \(result.stderr.isEmpty ? result.stdout : result.stderr)")
        }
        return WorkspaceCheckoutPlan.offered(try decodePullRequestListings(from: Data(result.stdout.utf8)))
    }

    static func pullRequestSummary(number: Int, repoPath: String) async throws -> PullRequestListing {
        guard number > 0 else { throw GitHubError("\(number) is not a pull request number") }
        let result = try await run(
            "gh", ["pr", "view", String(number), "--json", summaryFields],
            cwd: repoPath,
            timeout: .seconds(20)
        )
        guard result.ok else {
            throw GitHubError(
                "Could not read pull request #\(number): "
                    + (result.stderr.isEmpty ? result.stdout : result.stderr)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return try decodePullRequestListing(from: Data(result.stdout.utf8))
    }

    static func repositorySlug(repoPath: String) async -> String? {
        if let context = try? await Git.repositoryContext(in: repoPath),
           let repository = repositorySpecifier(context.baseRemoteURL) {
            return repository.split(separator: "/").dropFirst().joined(separator: "/")
        }
        guard let result = try? await run(
            "gh", ["repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"],
            cwd: repoPath,
            timeout: .seconds(20)
        ), result.ok else { return nil }
        let slug = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return slug.isEmpty ? nil : slug
    }

    static func checkoutPullRequest(
        number: Int, into worktree: String, localBranch: String
    ) async throws {
        guard number > 0 else { throw GitHubError("\(number) is not a pull request number") }
        guard Git.isValidBranchName(localBranch) else {
            throw GitHubError("'\(localBranch)' is not a valid branch name")
        }
        let result = try await run(
            "gh", ["pr", "checkout", String(number), "--branch", localBranch],
            cwd: worktree,
            timeout: .seconds(120)
        )
        guard result.ok else {
            throw GitHubError(
                "Could not check out pull request #\(number): "
                    + (result.stderr.isEmpty ? result.stdout : result.stderr)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .suffix(400)
            )
        }
    }

    static func decodePullRequestListings(from data: Data) throws -> [PullRequestListing] {
        try payloads(from: data).map { $0.summary }
    }

    static func decodePullRequestListing(from data: Data) throws -> PullRequestListing {
        do {
            return try JSONDecoder().decode(PullRequestListPayload.self, from: data).summary
        } catch {
            throw GitHubError("Could not decode gh JSON: \(error)")
        }
    }

    static func indicatesNotAGitHubRepository(stderr: String) -> Bool {
        let text = stderr.lowercased()
        return text.contains("none of the git remotes configured for this repository")
            || text.contains("no git remotes found")
            || text.contains("could not determine base repository")
            || text.contains("not a git repository")
    }

    private static func payloads(from data: Data) throws -> [PullRequestListPayload] {
        do {
            return try JSONDecoder().decode([PullRequestListPayload].self, from: data)
        } catch {
            throw GitHubError("Could not decode gh JSON: \(error)")
        }
    }
}

public struct PullRequestListPayload: Decodable, Sendable {
    struct Login: Decodable, Sendable {
        let login: String?
    }

    let number: Int?
    let title: String?
    let author: Login?
    let headRefName: String?
    let baseRefName: String?
    let isDraft: Bool?
    let state: String?
    let isCrossRepository: Bool?
    let headRepositoryOwner: Login?

    var summary: PullRequestListing {
        PullRequestListing(
            number: number ?? 0,
            title: title ?? "",
            author: author?.login ?? "",
            headRefName: headRefName ?? "",
            baseRefName: baseRefName ?? "",
            isDraft: isDraft ?? false,
            state: state ?? "OPEN",
            isCrossRepository: isCrossRepository ?? false,
            headRepositoryOwner: headRepositoryOwner?.login
        )
    }
}
