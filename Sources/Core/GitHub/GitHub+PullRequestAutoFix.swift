import Foundation

public struct PullRequestAutoFixFacts: Sendable {
    public let pullRequest: PullRequest
    public let localWork: LocalWork?
    public let checkedOutBranch: String?
    public let checkedOutHead: String?
    public let viewerLogin: String?
    public let commitAuthors: PullRequestAutoFix.CommitAuthors?

    static func gather(
        _ pullRequest: PullRequest,
        in path: String,
        viewer: @Sendable () async -> String?,
        authors: @Sendable () async -> PullRequestAutoFix.CommitAuthors?
    ) async -> PullRequestAutoFixFacts {
        async let localWork = try? Git.localWork(worktree: path)
        async let branch = try? Git.currentBranch(of: path)
        async let head = try? Git.run(["rev-parse", "HEAD"], in: path)
        async let viewerLogin = viewer()
        async let commitAuthors = authors()
        return await PullRequestAutoFixFacts(
            pullRequest: pullRequest,
            localWork: localWork,
            checkedOutBranch: branch,
            checkedOutHead: head.flatMap { $0.ok ? $0.trimmed : nil },
            viewerLogin: viewerLogin,
            commitAuthors: commitAuthors
        )
    }
}

private struct CommitAuthorsPayload: Decodable {
    struct Commit: Decodable {
        struct Author: Decodable {
            let login: String?
        }

        let authors: [Author]?
    }

    let headCommit: String?
    let commits: [Commit]?

    enum CodingKeys: String, CodingKey {
        case commits
        case headCommit = "headRefOid"
    }
}

public extension GitHub {
    static func decodeCommitAuthors(from data: Data) -> PullRequestAutoFix.CommitAuthors? {
        guard let payload = try? JSONDecoder().decode(CommitAuthorsPayload.self, from: data),
              let head = payload.headCommit, !head.isEmpty,
              let commits = payload.commits, !commits.isEmpty
        else { return nil }
        let logins = commits.flatMap { commit -> [String] in
            guard let authors = commit.authors, !authors.isEmpty else { return [""] }
            return authors.map { $0.login ?? "" }
        }
        return PullRequestAutoFix.CommitAuthors(headCommit: head, logins: Set(logins))
    }

    static func pullRequestAutoFixFacts(for workspace: Workspace) async -> PullRequestAutoFixFacts? {
        guard let pullRequest = try? await GitHub.pullRequest(for: workspace, maxAge: .zero) else { return nil }
        let path = workspace.path
        return await PullRequestAutoFixFacts.gather(
            pullRequest, in: path,
            viewer: { await signedInLogin(worktree: path) },
            authors: { await commitAuthors(number: pullRequest.number, worktree: path) }
        )
    }

    private static func signedInLogin(worktree: String) async -> String? {
        guard let result = try? await run("gh", ["api", "user", "--jq", ".login"], cwd: worktree, timeout: .seconds(20)),
              result.ok, !result.trimmed.isEmpty
        else { return nil }
        return result.trimmed
    }

    private static func commitAuthors(number: Int, worktree: String) async -> PullRequestAutoFix.CommitAuthors? {
        guard let result = try? await run(
            "gh", ["pr", "view", String(number), "--json", "headRefOid,commits"], cwd: worktree, timeout: .seconds(30)
        ), result.ok else { return nil }
        return decodeCommitAuthors(from: Data(result.stdout.utf8))
    }
}
