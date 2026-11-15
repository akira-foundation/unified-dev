import Foundation
import Testing
@testable import Core

@Suite("Reading a Bitbucket workspace's pull request through bkt")
struct BitbucketReadingTests {
    private actor Calls {
        var seen: [[String]] = []
        func record(_ arguments: [String]) { seen.append(arguments) }
    }

    private static let signedIn = """
    {"active_context": "work", "hosts": [{"key": "api.bitbucket.org", "kind": "cloud",
     "base_url": "https://api.bitbucket.org/2.0", "auth_method": "oauth", "token_source": "keyring"}],
     "contexts": [{"name": "dc", "host": "bitbucket.example.com", "active": true},
                  {"name": "work", "host": "api.bitbucket.org", "active": false}]}
    """

    private func workspace() -> Workspace {
        Workspace(
            repoID: Repo(name: "ledger", path: "/nowhere/ledger").id,
            name: "upmerge", branch: "issue/10.2.x/upmerge", path: TestScratch.unique("bitbucket-worktree"),
            baseBranch: "release/10.2.x", createdAt: .distantPast
        )
    }

    private func read(
        _ answer: @escaping @Sendable ([String]) -> ShellResult, calls: Calls
    ) async -> PullRequestReading {
        await Forge.$remoteOverride.withValue({ _ in "git@bitbucket.org:atlassian/aui.git" }) {
            await Bitbucket.$commandOverride.withValue({ arguments, _ in
                await calls.record(arguments)
                return answer(arguments)
            }) {
                await Bitbucket.readPullRequestAndChecks(for: workspace(), maxAge: .zero)
            }
        }
    }

    @Test("a signed in bkt gives the pull request and its builds, through a Bitbucket Cloud context")
    func readsPullRequestAndChecks() async throws {
        let calls = Calls()
        let reading = await read({ arguments in
            if arguments.starts(with: ["auth", "status"]) { return ShellResult(status: 0, stdout: Self.signedIn, stderr: "") }
            if arguments[1].hasSuffix("/pullrequests") {
                let page = "{\"values\": [\(BitbucketPullRequestTests.pullRequestJSON())]}"
                return ShellResult(status: 0, stdout: page, stderr: "")
            }
            return ShellResult(status: 0, stdout: BitbucketPullRequestTests.statusesJSON, stderr: "")
        }, calls: calls)

        guard case .current(let found) = reading.pullRequest else {
            Issue.record("expected a pull request, got \(reading.pullRequest)")
            return
        }
        let pullRequest = try #require(found)
        #expect(pullRequest.number == 5486)
        #expect(pullRequest.checks == .failing)
        #expect(reading.checks?.runs.count == 4)

        let seen = await calls.seen
        #expect(seen.count == 4)
        #expect(seen.dropFirst().allSatisfy { $0.suffix(2) == ["--context", "work"] })
        #expect(seen[2][1] == "/repositories/atlassian/aui/commit/ec3178d4d575/statuses")
        #expect(seen[3][1] == "/repositories/atlassian/aui/pipelines/14542/steps/")
    }

    @Test("no Bitbucket Cloud sign-in reads as an authentication failure, with nothing else asked")
    func signedOut() async {
        let calls = Calls()
        let reading = await read({ _ in
            ShellResult(status: 0, stdout: #"{"hosts": null, "contexts": null}"#, stderr: "")
        }, calls: calls)

        guard case .unavailable(let failure) = reading.pullRequest else {
            Issue.record("expected a failure")
            return
        }
        #expect(failure.reason == .authentication)
        #expect(failure.message == Bitbucket.signedOutMessage)
        #expect(failure.forge == .bitbucket)
        #expect(failure.headline(hasPullRequest: false) == "Bitbucket could not refresh")
        #expect(failure.headline(hasPullRequest: true) == "Showing the last Bitbucket update")
        #expect(await calls.seen.count == 1)
    }

    @Test("a failure read from gh still names GitHub")
    func gitHubFailureHeadline() {
        let failure = GitHubReadFailure(reason: .unavailable, message: "gh: HTTP 502")

        #expect(failure.forge == .gitHub)
        #expect(failure.headline(hasPullRequest: false) == "GitHub could not refresh")
        #expect(failure.headline(hasPullRequest: true) == "Showing the last GitHub update")
    }

    @Test("a sign-in with no context of its own gets one made for it, bound to the repository's workspace")
    func createsContext() async {
        let calls = Calls()
        let bare = #"{"hosts": [{"key": "api.bitbucket.org", "kind": "cloud"}], "contexts": null}"#
        _ = await read({ arguments in
            if arguments.starts(with: ["auth", "status"]) { return ShellResult(status: 0, stdout: bare, stderr: "") }
            if arguments.first == "context" { return ShellResult(status: 0, stdout: "", stderr: "") }
            return ShellResult(status: 0, stdout: #"{"values": []}"#, stderr: "")
        }, calls: calls)

        let seen = await calls.seen
        #expect(seen[1] == [
            "context", "create", Bitbucket.appContext, "--host", "api.bitbucket.org", "--workspace", "atlassian",
        ])
        #expect(seen[2].suffix(2) == ["--context", Bitbucket.appContext])
    }

    @Test("no pull request on the branch reads as none")
    func noPullRequest() async {
        let reading = await read({ arguments in
            if arguments.starts(with: ["auth", "status"]) { return ShellResult(status: 0, stdout: Self.signedIn, stderr: "") }
            return ShellResult(status: 0, stdout: #"{"values": []}"#, stderr: "")
        }, calls: Calls())

        guard case .current(let found) = reading.pullRequest else {
            Issue.record("expected an answer")
            return
        }
        #expect(found == nil)
    }

    @Test("a branch with 401 in its name is not mistaken for a refused token")
    func branchNamedLikeAStatus() {
        let failure = Bitbucket.failure(
            ShellError(command: "bkt api q=source.branch.name=\"fix-401\"", status: 1, stderr: "HTTP 500 Internal Server Error")
        )

        #expect(failure.reason == .unavailable)
    }

    @Test("a refused token reads as a sign-in to redo", arguments: ["Error: 401 Unauthorized", "token expired", "run `bkt auth login` first"])
    func refusedToken(stderr: String) {
        let failure = Bitbucket.failure(ShellError(command: "bkt api", status: 1, stderr: stderr))

        #expect(failure.reason == .authentication)
        #expect(failure.message == Bitbucket.signedOutMessage)
    }
}
