import Foundation
import Testing
@testable import Core

@Suite("A branch published to a fork with its pull request upstream", .tags(.git), .scratchDirectory)
struct ForkPublishedBranchTests {
    private static let branch = "fix-the-parser"
    private static let upstreamURL = "https://github.com/upstream-owner/example.git"
    private static let forkURL = "https://github.com/fork-owner/example.git"
    private static let upstreamRepository = "github.com/upstream-owner/example"

    private struct Layout {
        let repo: TempRepo
        let remotes: [String]

        func cleanUp() {
            repo.cleanUp()
            for remote in remotes { try? FileManager.default.removeItem(atPath: remote) }
        }
    }

    private static func layout() async throws -> Layout {
        let upstream = try await bare("upstream")
        let fork = try await bare("fork")
        let repo = try await TempRepo(defaultBranch: "dev")
        try await git(["remote", "add", "origin", upstreamURL], in: repo)
        try await git(["remote", "add", "fork", forkURL], in: repo)
        try await git(["config", "url.\(upstream).insteadOf", upstreamURL], in: repo)
        try await git(["config", "url.\(fork).insteadOf", forkURL], in: repo)
        try await git(["push", "-q", "fork", "dev"], in: repo)
        for _ in 0..<3 { try await commit(in: repo) }
        try await git(["push", "-q", "origin", "dev"], in: repo)
        try await git(["fetch", "-q", "origin"], in: repo)
        try await git(["fetch", "-q", "fork"], in: repo)
        try await git(["remote", "set-head", "origin", "dev"], in: repo)
        try await git(["remote", "set-head", "fork", "dev"], in: repo)
        try await git(["checkout", "-q", "-b", branch, "origin/dev"], in: repo)
        for _ in 0..<2 { try await commit(in: repo) }
        try await git(["push", "-q", "-u", "fork", branch], in: repo)
        try await git(["branch", "-q", "-D", "dev"], in: repo)
        return Layout(repo: repo, remotes: [upstream, fork])
    }

    private static func bare(_ name: String) async throws -> String {
        let path = TestScratch.unique("unifieddev-\(name)") + ".git"
        try await Shell.check("git", ["init", "-q", "--bare", "-b", "dev", path], env: isolated)
        return path
    }

    private static let isolated = ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"]

    @discardableResult
    private static func git(_ arguments: [String], in repo: TempRepo) async throws -> String {
        try await Shell.check("git", arguments, cwd: repo.path, env: isolated).trimmed
    }

    private static func commit(in repo: TempRepo) async throws {
        try await git(["commit", "-q", "--allow-empty", "-m", "step"], in: repo)
    }

    private static let pullRequest =
        #"{"number":41,"title":"Fix the parser","url":"https://github.com/upstream-owner/example/pull/41","state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","reviewDecision":null,"headRefName":"fix-the-parser","baseRefName":"dev","statusCheckRollup":[],"closedAt":null,"isCrossRepository":true}"#

    private static func upstreamOnly(
        asked: AskedArguments
    ) -> @Sendable ([String], String?) async throws -> ShellResult {
        { arguments, _ in
            await asked.record(arguments)
            let inUpstream = arguments.contains(upstreamRepository)
            if arguments.starts(with: ["pr", "view"]), inUpstream,
               arguments.contains("fork-owner:\(branch)") || arguments.contains("41") {
                return ShellResult(status: 0, stdout: pullRequest, stderr: "")
            }
            if arguments.starts(with: ["pr", "list"]) {
                return ShellResult(status: 0, stdout: "[]", stderr: "")
            }
            return ShellResult(status: 1, stdout: "", stderr: "no pull requests found for branch \"\(branch)\"")
        }
    }

    @Test("the pull request is looked for upstream under the fork owner's head and found")
    func findsThePullRequestUpstream() async throws {
        let layout = try await Self.layout()
        defer { layout.cleanUp() }
        let asked = AskedArguments()

        let found = try await GitHub.$commandOverride.withValue(Self.upstreamOnly(asked: asked)) {
            try await GitHub.snapshot(forBranch: Self.branch, worktree: layout.repo.path, base: "dev", maxAge: .zero)
        }

        #expect(found?.pullRequest.number == 41)
        let calls = await asked.all
        let view = calls.first { $0.starts(with: ["pr", "view"]) } ?? []
        #expect(view.contains("fork-owner:\(Self.branch)"))
        #expect(view.contains(Self.upstreamRepository))
    }

    @Test("the open pull request takes the Open PR button away")
    func offersNoSecondPullRequest() async throws {
        let layout = try await Self.layout()
        defer { layout.cleanUp() }
        let asked = AskedArguments()

        let found = try await GitHub.$commandOverride.withValue(Self.upstreamOnly(asked: asked)) {
            try await GitHub.pullRequest(forBranch: Self.branch, worktree: layout.repo.path, base: "dev")
        }
        let standing = PullRequestStanding.of(
            branch: Self.branch, baseBranch: "dev", ahead: 2, pullRequest: found
        )

        #expect(standing.number == 41)
        #expect(standing.button?.act != .openPullRequest)
    }

    @Test("commits ahead are counted against the upstream base, not the fork's stale copy")
    func countsAgainstTheUpstreamBase() async throws {
        let layout = try await Self.layout()
        defer { layout.cleanUp() }

        let commits = try await Git.branchCommits(worktree: layout.repo.path, base: "dev")
        let context = try await Git.repositoryContext(in: layout.repo.path)

        #expect(commits.commits.count == 2)
        #expect(context.baseRemote == "origin")
        #expect(context.baseBranch == "dev")
    }

    @Test("with no pull request yet, one is proposed upstream from the fork owner's head")
    func proposesThePullRequestUpstream() async throws {
        let layout = try await Self.layout()
        defer { layout.cleanUp() }

        let context = try await Git.repositoryContext(
            in: layout.repo.path, baseBranch: "dev", baseIsBranchName: true
        )
        let arguments = GitHub.repositoryArguments(
            ["pr", "create", "--base", "dev", "--title", "Fix", "--body", ""], context: context
        )

        #expect(arguments.suffix(4) == ["--head", "fork-owner:\(Self.branch)", "--repo", Self.upstreamRepository])
        #expect(context.publishRemote == "fork")
    }

    private static let remotes = [
        "remote.origin.url": upstreamURL,
        "remote.fork.url": forkURL,
    ]

    @Test("a workspace cut from a checkout that publishes to the fork records the upstream as its base")
    func cutFromAForkPublishedCheckout() {
        let context = GitRepositoryContext.resolve(
            config: Self.remotes.merging([
                "branch.side.remote": "fork", "branch.side.merge": "refs/heads/side",
            ]) { _, new in new },
            base: "dev", branch: "side", baseIsBranchName: true
        )

        #expect(context.baseRemote == "origin")
        #expect(context.publishRemote == "fork")
    }

    @Test("a branch that tracks its base on the fork keeps the fork as its base")
    func tracksItsBaseOnTheFork() {
        let context = GitRepositoryContext.resolve(
            config: Self.remotes.merging([
                "branch.side.remote": "fork", "branch.side.merge": "refs/heads/dev",
            ]) { _, new in new },
            base: "dev", branch: "side", baseIsBranchName: true
        )

        #expect(context.baseRemote == "fork")
    }

    @Test("a branch published to an origin fork reads its base from the upstream remote")
    func publishedToAnOriginFork() {
        let context = GitRepositoryContext.resolve(
            config: [
                "remote.origin.url": Self.forkURL, "remote.upstream.url": Self.upstreamURL,
                "branch.side.remote": "origin", "branch.side.merge": "refs/heads/side",
            ],
            base: "dev", branch: "side", baseIsBranchName: true
        )

        #expect(context.baseRemote == "upstream")
        #expect(PullRequestHead.selector(in: context) == "fork-owner:side")
    }

    @Test("a branch published straight to the upstream keeps the upstream as its base")
    func publishedStraightToTheUpstream() {
        let context = GitRepositoryContext.resolve(
            config: [
                "remote.origin.url": Self.forkURL, "remote.upstream.url": Self.upstreamURL,
                "branch.side.remote": "upstream", "branch.side.merge": "refs/heads/side",
            ],
            base: "dev", branch: "side", baseIsBranchName: true
        )

        #expect(context.baseRemote == "upstream")
        #expect(PullRequestHead.selector(in: context) == "side")
    }

    @Test("a branch that tracks another local branch keeps reading its base locally")
    func tracksALocalBranch() {
        let context = GitRepositoryContext.resolve(
            config: Self.remotes.merging([
                "branch.side.remote": ".", "branch.side.merge": "refs/heads/first",
            ]) { _, new in new },
            base: "release", branch: "side", baseIsBranchName: true
        )

        #expect(context.baseRemote == nil)
    }
}
