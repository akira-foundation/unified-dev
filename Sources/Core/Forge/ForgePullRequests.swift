import Foundation

extension PullRequestSnapshot {
    var readableRuns: [CheckRun]? { pullRequest.checks == .unavailable ? nil : runs }
}

public enum ForgePullRequests {
    public static func pullRequest(for workspace: Workspace, maxAge: Duration = .zero) async throws -> PullRequest? {
        switch await Forge.kind(forDirectory: workspace.path) {
        case .gitHub: try await GitHub.pullRequest(for: workspace, maxAge: maxAge)
        case .bitbucket: try await Bitbucket.snapshot(for: workspace, maxAge: maxAge)?.pullRequest
        }
    }

    public static func checks(for workspace: Workspace) async throws -> [CheckRun]? {
        switch await Forge.kind(forDirectory: workspace.path) {
        case .gitHub:
            return try await GitHub.checks(for: workspace)
        case .bitbucket:
            guard let found = try await Bitbucket.snapshot(for: workspace, maxAge: .zero) else { return [] }
            return found.readableRuns
        }
    }

    public static func headAndChecks(for workspace: Workspace) async throws -> (head: String?, runs: [CheckRun])? {
        switch await Forge.kind(forDirectory: workspace.path) {
        case .gitHub:
            return try await GitHub.headAndChecks(for: workspace)
        case .bitbucket:
            guard let found = try await Bitbucket.snapshot(for: workspace, maxAge: .zero),
                  let runs = found.readableRuns
            else { return nil }
            return (found.pullRequest.headCommit, runs)
        }
    }

    public static func access(directory: String) async -> GitHubAccess {
        switch await Forge.kind(forDirectory: directory) {
        case .gitHub: await GitHub.access(directory: directory)
        case .bitbucket: await Bitbucket.access(directory: directory)
        }
    }

    public static func failedLog(of run: CheckRun, worktree: String) async -> String? {
        if let target = CheckFailureHandoff.logTarget(detailsURL: run.detailsURL) {
            return try? await GitHub.checkRunLog(target, worktree: worktree)
        }
        if let target = BitbucketPipelineTarget.parse(detailsURL: run.detailsURL) {
            return try? await Bitbucket.pipelineLog(target, worktree: worktree)
        }
        return nil
    }

    public static func openPullRequests(repoPath: String) async throws -> [PullRequestListing] {
        switch await Forge.kind(forDirectory: repoPath) {
        case .gitHub: try await GitHub.openPullRequests(repoPath: repoPath)
        case .bitbucket: try await Bitbucket.openPullRequests(repoPath: repoPath)
        }
    }

    public static func pullRequestSummary(number: Int, repoPath: String) async throws -> PullRequestListing {
        switch await Forge.kind(forDirectory: repoPath) {
        case .gitHub: try await GitHub.pullRequestSummary(number: number, repoPath: repoPath)
        case .bitbucket: try await Bitbucket.pullRequestSummary(number: number, repoPath: repoPath)
        }
    }

    public static func repositorySlug(repoPath: String) async -> String? {
        switch await Forge.kind(forDirectory: repoPath) {
        case .gitHub: await GitHub.repositorySlug(repoPath: repoPath)
        case .bitbucket: await Forge.repository(forDirectory: repoPath).map { "\($0.owner)/\($0.name)" }
        }
    }

    public static func checkout(
        _ request: PullRequestListing, repoPath: String, into worktree: String, localBranch: String
    ) async throws {
        switch await Forge.kind(forDirectory: repoPath) {
        case .gitHub:
            try await GitHub.checkoutPullRequest(number: request.number, into: worktree, localBranch: localBranch)
        case .bitbucket:
            try await Bitbucket.checkoutPullRequest(request, into: worktree, localBranch: localBranch)
        }
    }

    public static func autoFixFacts(for workspace: Workspace) async -> PullRequestAutoFixFacts? {
        switch await Forge.kind(forDirectory: workspace.path) {
        case .gitHub: return await GitHub.pullRequestAutoFixFacts(for: workspace)
        case .bitbucket:
            guard let pullRequest = try? await Bitbucket.snapshot(for: workspace, maxAge: .zero)?.pullRequest
            else { return nil }
            let path = workspace.path
            return await PullRequestAutoFixFacts.gather(
                pullRequest, in: path,
                viewer: { await Bitbucket.viewer(in: path) },
                authors: { await Bitbucket.commitAuthors(of: pullRequest, in: path) }
            )
        }
    }
}
