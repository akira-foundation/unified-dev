import Foundation
import Testing
@testable import Core

@Suite("Starting a Bitbucket workspace over a local branch of the same name")
struct BitbucketLocalBranchTests {
    @Test("the route follows where the local branch stands against the server's", arguments: [
        (false, false, false, false, BitbucketCheckoutRoute.bkt),
        (true, true, true, true, .bkt),
        (true, false, true, true, .keepLocal),
        (true, false, true, false, .keepLocal),
        (true, false, false, true, .fastForward),
        (true, false, false, false, .diverged),
    ])
    func route(localExists: Bool, isFork: Bool, localHasServer: Bool, serverHasLocal: Bool, expected: BitbucketCheckoutRoute) {
        #expect(BitbucketCheckoutRoute.choose(
            localExists: localExists, isFork: isFork, localHasServer: localHasServer, serverHasLocal: serverHasLocal
        ) == expected)
    }

    private actor Calls {
        var seen: [[String]] = []
        func record(_ arguments: [String]) { seen.append(arguments) }
    }

    private static let request = PullRequestListing(number: 7, title: "Ledger", headRefName: "feat/7", baseRefName: "main")

    @Test("the server's branch is fetched into its remote tracking ref, and a fast forward merges only that")
    func arguments() {
        #expect(Bitbucket.serverFetchArguments(for: Self.request) == [
            "fetch", "origin", "+refs/heads/feat/7:refs/remotes/origin/feat/7",
        ])
        #expect(Bitbucket.localCheckoutArguments(.keepLocal, for: Self.request, localBranch: "feat/7") == [
            ["checkout", "feat/7", "--"],
        ])
        #expect(Bitbucket.localCheckoutArguments(.fastForward, for: Self.request, localBranch: "feat/7") == [
            ["checkout", "feat/7", "--"], ["merge", "--ff-only", "refs/remotes/origin/feat/7"],
        ])
        #expect(Bitbucket.localCheckoutArguments(.diverged, for: Self.request, localBranch: "feat/7").isEmpty)
    }

    private struct Fixture {
        let clone: String
        let worktree: String

        static func git(_ arguments: [String], in directory: String) async throws {
            try await Shell.check(
                "git",
                ["-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false"] + arguments,
                cwd: directory
            )
        }

        static func make(_ label: String) async throws -> Fixture {
            let root = TestScratch.unique(label)
            let server = root + "/server.git"
            let clone = root + "/clone"
            try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
            try await Shell.check("git", ["init", "-q", "--bare", "-b", "main", server], cwd: root)
            try await Shell.check("git", ["clone", "-q", server, clone], cwd: root)
            try await git(["commit", "-q", "--allow-empty", "-m", "base"], in: clone)
            try await git(["push", "-q", "origin", "HEAD:main"], in: clone)
            try await git(["checkout", "-q", "-b", "feat/7"], in: clone)
            try await git(["commit", "-q", "--allow-empty", "-m", "shared"], in: clone)
            try await git(["push", "-q", "origin", "feat/7"], in: clone)
            try await git(["checkout", "-q", "main"], in: clone)
            return Fixture(clone: clone, worktree: root + "/worktree")
        }

        func commitOnServer(_ message: String) async throws {
            try await Self.git(["checkout", "-q", "--detach", "origin/feat/7"], in: clone)
            try await Self.git(["commit", "-q", "--allow-empty", "-m", message], in: clone)
            try await Self.git(["push", "-q", "-f", "origin", "HEAD:refs/heads/feat/7"], in: clone)
            try await Self.git(["checkout", "-q", "main"], in: clone)
        }

        func commitLocally(_ message: String) async throws {
            try await Self.git(["checkout", "-q", "feat/7"], in: clone)
            try await Self.git(["commit", "-q", "--allow-empty", "-m", message], in: clone)
            try await Self.git(["checkout", "-q", "main"], in: clone)
        }

        func addWorktree() async throws {
            try await Self.git(["worktree", "add", "-q", "--detach", worktree, "main"], in: clone)
        }

        func subject(of reference: String) async throws -> String {
            try await Shell.check("git", ["log", "-1", "--format=%s", reference], cwd: worktree).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func checkOut(in fixture: Fixture) async throws {
        try await Bitbucket.$commandOverride.withValue({ arguments, _ in
            Issue.record("bkt was asked \(arguments)")
            return ShellResult(status: 1, stdout: "", stderr: "")
        }) {
            try await Bitbucket.checkoutPullRequest(Self.request, into: fixture.worktree, localBranch: "feat/7")
        }
    }

    @Test("a local branch ahead of the server is checked out as it stands, without bkt")
    func aheadIsKept() async throws {
        let fixture = try await Fixture.make("bitbucket-ahead")
        try await fixture.commitLocally("local only")
        try await fixture.addWorktree()

        try await checkOut(in: fixture)

        #expect(try await fixture.subject(of: "HEAD") == "local only")
        #expect(try await Shell.check("git", ["branch", "--show-current"], cwd: fixture.worktree).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines) == "feat/7")
    }

    @Test("a local branch behind the server is fast forwarded to it")
    func behindIsFastForwarded() async throws {
        let fixture = try await Fixture.make("bitbucket-behind")
        try await fixture.commitOnServer("from the server")
        try await fixture.addWorktree()

        try await checkOut(in: fixture)

        #expect(try await fixture.subject(of: "HEAD") == "from the server")
    }

    @Test("a local branch that has moved apart from the server is refused and left alone")
    func divergedIsRefused() async throws {
        let fixture = try await Fixture.make("bitbucket-diverged")
        try await fixture.commitLocally("local only")
        try await fixture.commitOnServer("from the server")
        try await fixture.addWorktree()

        await #expect(throws: GitHubError.self) { try await checkOut(in: fixture) }

        #expect(try await fixture.subject(of: "refs/heads/feat/7") == "local only")
        #expect(try await Shell.check("git", ["branch", "--show-current"], cwd: fixture.worktree).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("with no local branch of that name, bkt does the checkout as before")
    func absentGoesToBkt() async throws {
        let fixture = try await Fixture.make("bitbucket-absent")
        try await Fixture.git(["branch", "-q", "-D", "feat/7"], in: fixture.clone)
        try await fixture.addWorktree()
        let calls = Calls()
        try await Forge.$remoteOverride.withValue({ _ in "git@bitbucket.org:debtges/ledger.git" }) {
            try await Bitbucket.$commandOverride.withValue({ arguments, _ in
                if arguments.starts(with: ["auth", "status"]) {
                    return ShellResult(status: 0, stdout: BitbucketPipelineLogTests.signedIn, stderr: "")
                }
                await calls.record(arguments)
                return ShellResult(status: 0, stdout: "", stderr: "")
            }) {
                try await Bitbucket.checkoutPullRequest(Self.request, into: fixture.worktree, localBranch: "feat/7")
            }
        }

        #expect(await calls.seen == [
            ["pr", "checkout", "7", "--branch", "feat/7", "--workspace", "debtges", "--repo", "ledger", "--context", "work"],
        ])
        #expect(try await Shell.check("git", ["branch", "--show-current"], cwd: fixture.worktree).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
