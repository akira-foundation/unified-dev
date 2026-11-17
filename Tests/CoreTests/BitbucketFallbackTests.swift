import Foundation
import Testing
@testable import Core

@Suite("What a Bitbucket read falls back on when the first answer is not enough")
struct BitbucketFallbackTests {
    private actor Calls {
        var seen: [[String]] = []
        func record(_ arguments: [String]) { seen.append(arguments) }
    }

    private static let signedIn = """
    {"hosts": [{"key": "api.bitbucket.org", "kind": "cloud"}],
     "contexts": [{"name": "work", "host": "api.bitbucket.org", "active": true}]}
    """

    private static let emptyPage = #"{"values": []}"#

    private func workspace(number: Int? = nil) -> Workspace {
        var workspace = Workspace(
            repoID: Repo(name: "aui", path: "/nowhere/aui").id,
            name: "upmerge", branch: "issue/10.2.x/upmerge", path: TestScratch.unique("bitbucket-fallback"),
            baseBranch: "release/10.2.x", createdAt: .distantPast
        )
        workspace.pullRequestNumber = number
        return workspace
    }

    private func read(
        _ workspace: Workspace,
        remote: String = "git@bitbucket.org:atlassian/aui.git",
        calls: Calls,
        answer: @escaping @Sendable ([String]) -> ShellResult
    ) async -> PullRequestReading? {
        await Forge.$remoteOverride.withValue({ _ in remote }) {
            await Bitbucket.$commandOverride.withValue({ arguments, _ in
                await calls.record(arguments)
                if arguments.starts(with: ["auth", "status"]) {
                    return ShellResult(status: 0, stdout: Self.signedIn, stderr: "")
                }
                return answer(arguments)
            }) {
                await Bitbucket.readingIfHosted(for: workspace, maxAge: .zero)
            }
        }
    }

    private func shown(in reading: PullRequestReading?) -> PullRequest? {
        guard case .current(let found) = reading?.pullRequest else { return nil }
        return found
    }

    @Test("a GitHub workspace is left to GitHub, and bkt is never run")
    func gitHubIsNotRead() async {
        let calls = Calls()
        let reading = await read(workspace(), remote: "git@github.com:acme/widgets.git", calls: calls) { _ in
            ShellResult(status: 0, stdout: Self.emptyPage, stderr: "")
        }

        #expect(reading == nil)
        #expect(await calls.seen.isEmpty)
    }

    @Test("builds that cannot be read leave the pull request shown, with its checks unreadable")
    func unreadableBuilds() async throws {
        let reading = await read(workspace(), calls: Calls()) { arguments in
            if arguments[1].hasSuffix("/statuses") {
                return ShellResult(status: 1, stdout: "", stderr: "Error: 403 Forbidden")
            }
            let page = "{\"values\": [\(BitbucketPullRequestTests.pullRequestJSON())]}"
            return ShellResult(status: 0, stdout: page, stderr: "")
        }

        let pullRequest = try #require(shown(in: reading))
        #expect(pullRequest.number == 5486)
        #expect(pullRequest.checks == .unavailable)
        #expect(pullRequest.hasFixableCheckFailure == nil)
        #expect(reading?.checks == .unreadable)
    }

    @Test("with nothing on the branch, the number the workspace recorded is read")
    func readsRecordedNumber() async throws {
        let calls = Calls()
        let reading = await read(workspace(number: 5486), calls: calls) { arguments in
            if arguments[1].hasSuffix("/pullrequests/5486") {
                return ShellResult(status: 0, stdout: BitbucketPullRequestTests.pullRequestJSON(), stderr: "")
            }
            if arguments[1].hasSuffix("/statuses") {
                return ShellResult(status: 0, stdout: Self.emptyPage, stderr: "")
            }
            return ShellResult(status: 0, stdout: Self.emptyPage, stderr: "")
        }

        #expect(try #require(shown(in: reading)).number == 5486)
        #expect(await calls.seen.contains { $0[1] == "/repositories/atlassian/aui/pullrequests/5486" })
    }

    @Test("a recorded number Bitbucket no longer knows reads as no pull request", arguments: [
        ShellResult(status: 1, stdout: "", stderr: "Error: 404 Not Found: pull request not found"),
        ShellResult(status: 1, stdout: "Error: 404 Not Found", stderr: ""),
    ])
    func forgottenNumber(answer: ShellResult) async {
        let reading = await read(workspace(number: 9999), calls: Calls()) { arguments in
            arguments[1].hasSuffix("/pullrequests/9999") ? answer : ShellResult(status: 0, stdout: Self.emptyPage, stderr: "")
        }

        guard case .current(let found) = reading?.pullRequest else {
            Issue.record("expected an answer, got \(String(describing: reading?.pullRequest))")
            return
        }
        #expect(found == nil)
    }

    @Test("another failure that happens to carry 404 in its text is not read as a forgotten number")
    func failureMentioningFourOhFour() async {
        let reading = await read(workspace(number: 9999), calls: Calls()) { arguments in
            arguments[1].hasSuffix("/pullrequests/9999")
                ? ShellResult(status: 1, stdout: "", stderr: "Error: 500 Internal Server Error: upstream said 404 Not Found")
                : ShellResult(status: 0, stdout: Self.emptyPage, stderr: "")
        }

        guard case .unavailable = reading?.pullRequest else {
            Issue.record("expected a failure, got \(String(describing: reading?.pullRequest))")
            return
        }
    }

    @Test("a pull request from a fork this checkout pushes to is this workspace's")
    func ownFork() async throws {
        let fork = BitbucketPullRequestTests.pullRequestJSON(id: 5490, sourceRepository: "someone/aui")
        let reading = await Forge.$otherRemotesOverride.withValue(["git@bitbucket.org:someone/aui.git"]) {
            await read(workspace(), calls: Calls()) { arguments in
                arguments[1].hasSuffix("/statuses")
                    ? ShellResult(status: 0, stdout: Self.emptyPage, stderr: "")
                    : ShellResult(status: 0, stdout: "{\"values\": [\(fork)]}", stderr: "")
            }
        }

        #expect(try #require(shown(in: reading)).number == 5490)
    }

    @Test("a build list that fails for another reason is an error, not an empty list")
    func buildsFailLoudly() async {
        let reading = await read(workspace(), calls: Calls()) { arguments in
            if arguments[1].hasSuffix("/statuses") {
                return ShellResult(status: 1, stdout: "", stderr: "Error: 502 Bad Gateway: body quoted 403 Forbidden")
            }
            return ShellResult(status: 0, stdout: "{\"values\": [\(BitbucketPullRequestTests.pullRequestJSON())]}", stderr: "")
        }

        guard case .unavailable = reading?.pullRequest else {
            Issue.record("expected a failure, got \(String(describing: reading?.pullRequest))")
            return
        }
    }

    @Test("a head that is not a hash is never put in a path")
    func refusesOddHead() async throws {
        let calls = Calls()
        let odd = BitbucketPullRequestTests.pullRequestJSON(hash: "../../user")
        let reading = await read(workspace(), calls: calls) { _ in
            ShellResult(status: 0, stdout: "{\"values\": [\(odd)]}", stderr: "")
        }

        #expect(try #require(shown(in: reading)).checks == .unavailable)
        #expect(await !calls.seen.contains { $0[1].hasSuffix("/statuses") })
    }
}
