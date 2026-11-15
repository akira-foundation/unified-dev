import Foundation
import Testing
@testable import Core

@Suite("Starting a Bitbucket workspace over a local branch of the same name")
struct BitbucketLocalBranchTests {
    @Test("the route follows where the local branch stands against the server's", arguments: [
        (true, true, BitbucketCheckoutRoute.keepLocal),
        (true, false, .keepLocal),
        (false, true, .fastForward),
        (false, false, .diverged),
    ])
    func route(localHasServer: Bool, serverHasLocal: Bool, expected: BitbucketCheckoutRoute) {
        #expect(BitbucketCheckoutRoute.choose(localHasServer: localHasServer, serverHasLocal: serverHasLocal) == expected)
    }

    private actor Calls {
        var seen: [[String]] = []
        func record(_ arguments: [String]) { seen.append(arguments) }
    }

    private static let request = PullRequestListing(number: 7, title: "Ledger", headRefName: "feat/7", baseRefName: "main")

    @Test("the base remote's branch is fetched into its tracking ref, and a fast forward merges only that")
    func arguments() {
        let plan = BitbucketLocalCheckout(route: .fastForward, remote: "bitbucket")

        #expect(plan.fetchArguments(for: Self.request) == [
            "fetch", "bitbucket", "+refs/heads/feat/7:refs/remotes/bitbucket/feat/7",
        ])
        #expect(plan.checkoutArguments(for: Self.request, localBranch: "feat/7") == [
            ["checkout", "feat/7", "--"], ["merge", "--ff-only", "refs/remotes/bitbucket/feat/7"],
        ])
        #expect(BitbucketLocalCheckout(route: .keepLocal, remote: "origin").checkoutArguments(
            for: Self.request, localBranch: "feat/7"
        ) == [["checkout", "feat/7", "--"]])
        #expect(BitbucketLocalCheckout(route: .diverged, remote: "origin").checkoutArguments(
            for: Self.request, localBranch: "feat/7"
        ).isEmpty)
    }

    @Test("a remote name git could read as an option is never fetched from", arguments: [
        ("upstream", "upstream"), ("-x", "origin"), (nil as String?, "origin"), ("", "origin"),
    ])
    func remoteName(base: String?, used: String) {
        #expect(BitbucketLocalCheckout.remote(named: base) == used)
    }

    private struct Fixture {
        let clone: String
        let worktree: String
        let remote: String

        static func git(_ arguments: [String], in directory: String) async throws {
            try await Shell.check(
                "git",
                ["-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false"] + arguments,
                cwd: directory
            )
        }

        static func make(_ label: String, remote: String = "origin") async throws -> Fixture {
            let root = TestScratch.unique(label)
            let server = root + "/server.git"
            let clone = root + "/clone"
            try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
            try await Shell.check("git", ["init", "-q", "--bare", "-b", "main", server], cwd: root)
            try await Shell.check("git", ["clone", "-q", "-o", remote, server, clone], cwd: root)
            try await git(["commit", "-q", "--allow-empty", "-m", "base"], in: clone)
            try await git(["push", "-q", remote, "HEAD:main"], in: clone)
            try await git(["checkout", "-q", "-b", "feat/7"], in: clone)
            try await git(["commit", "-q", "--allow-empty", "-m", "shared"], in: clone)
            try await git(["push", "-q", remote, "feat/7"], in: clone)
            try await git(["checkout", "-q", "main"], in: clone)
            return Fixture(clone: clone, worktree: root + "/worktree", remote: remote)
        }

        func commitOnServer(_ message: String) async throws {
            try await Self.git(["checkout", "-q", "--detach", "\(remote)/feat/7"], in: clone)
            try await Self.git(["commit", "-q", "--allow-empty", "-m", message], in: clone)
            try await Self.git(["push", "-q", "-f", remote, "HEAD:refs/heads/feat/7"], in: clone)
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

        func config(_ key: String) async throws -> String {
            try await Shell.check("git", ["config", "--get", key], cwd: worktree).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
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
        #expect(try await fixture.config("branch.feat/7.remote") == "origin")
        #expect(try await fixture.config("branch.feat/7.merge") == "refs/heads/feat/7")
    }

    @Test("a repository whose remote is not called origin is fetched from that remote and tracks it")
    func baseRemoteIsUsed() async throws {
        let fixture = try await Fixture.make("bitbucket-named-remote", remote: "bitbucket")
        try await fixture.commitOnServer("from the server")
        try await fixture.addWorktree()

        try await checkOut(in: fixture)

        #expect(try await fixture.subject(of: "HEAD") == "from the server")
        #expect(try await fixture.config("branch.feat/7.remote") == "bitbucket")
    }

    @Test("a fork's pull request over a local branch of the same name is left to bkt")
    func forkGoesToBkt() async throws {
        let fixture = try await Fixture.make("bitbucket-fork-local")
        try await fixture.commitLocally("local only")
        try await fixture.addWorktree()
        let fork = PullRequestListing(
            number: 7, title: "Ledger", headRefName: "feat/7", baseRefName: "main",
            isCrossRepository: true, headRepositoryOwner: "someone"
        )
        let calls = Calls()
        try await Forge.$remoteOverride.withValue({ _ in "git@bitbucket.org:debtges/ledger.git" }) {
            try await Bitbucket.$commandOverride.withValue({ arguments, _ in
                if arguments.starts(with: ["auth", "status"]) {
                    return ShellResult(status: 0, stdout: BitbucketPipelineLogTests.signedIn, stderr: "")
                }
                await calls.record(arguments)
                return ShellResult(status: 0, stdout: "", stderr: "")
            }) {
                try await Bitbucket.checkoutPullRequest(fork, into: fixture.worktree, localBranch: "feat/7")
            }
        }

        #expect(await calls.seen.map { Array($0.prefix(2)) } == [["pr", "checkout"]])
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
