import Foundation
import Testing
@testable import Core

@Suite("Starting points for a project on Bitbucket")
struct BitbucketStartingPointTests {
    private actor Calls {
        var seen: [[String]] = []
        func record(_ arguments: [String]) { seen.append(arguments) }
    }

    static let ledger = ForgeRepository(kind: .bitbucket, host: "bitbucket.org", owner: "debtges", name: "ledger")
    static let viewer = "{2c58fd4f-96a5-40e8-af41-22da206e5c6c}"

    @Test("the open pull requests naming the viewer are asked for by uuid, with the state inside the query")
    func arguments() {
        #expect(Bitbucket.awaitingViewerArguments(.reviewer, viewer: Self.viewer, in: Self.ledger, context: "work") == [
            "api", "/repositories/debtges/ledger/pullrequests",
            "--param", "q=state=\"OPEN\" AND reviewers.uuid=\"{2c58fd4f-96a5-40e8-af41-22da206e5c6c}\"",
            "--param", "sort=-updated_on", "--param", "pagelen=10", "--context", "work",
        ])
        #expect(Bitbucket.awaitingViewerArguments(.author, viewer: Self.viewer, in: Self.ledger, context: "work")?[3]
            == "q=state=\"OPEN\" AND author.uuid=\"{2c58fd4f-96a5-40e8-af41-22da206e5c6c}\"")
    }

    @Test("a viewer that is not a uuid is never put in a query", arguments: ["557058:abc", "\" OR 1=1", ""])
    func viewerMustBeUUID(viewer: String) {
        #expect(Bitbucket.awaitingViewerArguments(.author, viewer: viewer, in: Self.ledger, context: "work") == nil)
    }

    private static func page(_ ids: [Int]) -> String {
        let values = ids.map { id in
            #"{"id": \#(id), "title": "PR \#(id)", "state": "OPEN", "source": {"branch": {"name": "feat/\#(id)"}}, "#
                + #""destination": {"branch": {"name": "main"}}}"#
        }
        return #"{"values": ["# + values.joined(separator: ",") + "]}"
    }

    private func read(user: String) async -> (StartingPointReading?, [[String]]) {
        let calls = Calls()
        let reading = await Forge.$remoteOverride.withValue({ _ in "git@bitbucket.org:debtges/ledger.git" }) {
            await Bitbucket.$commandOverride.withValue({ arguments, _ in
                if arguments.starts(with: ["auth", "status"]) {
                    return ShellResult(status: 0, stdout: BitbucketPipelineLogTests.signedIn, stderr: "")
                }
                await calls.record(arguments)
                if arguments[1] == "/user" { return ShellResult(status: 0, stdout: user, stderr: "") }
                let ids = arguments[3].contains("reviewers.uuid") ? [12, 9] : [15]
                return ShellResult(status: 0, stdout: Self.page(ids), stderr: "")
            }) {
                await StartingPointReader.load(
                    StartingPointReadingRequest(repoPath: TestScratch.unique("bitbucket-points"), asksGitHub: true),
                    from: StartingPointReader.Readings()
                )
            }
        }
        return (reading, await calls.seen)
    }

    @Test("a Bitbucket project offers the pull requests waiting on the owner and their own, and no issues")
    func readsBitbucket() async {
        let (reading, seen) = await read(user: #"{"uuid": "\#(Self.viewer)", "nickname": "kid"}"#)

        #expect(reading?.pullRequests.reviewRequested.map(\.number) == [12, 9])
        #expect(reading?.pullRequests.authored.map(\.number) == [15])
        #expect(reading?.issues.isEmpty == true)
        #expect(seen.allSatisfy { $0.first == "api" })
        #expect(!seen.contains { $0.first == "issue" })
    }

    @Test("without the viewer's uuid nothing is listed")
    func noViewer() async {
        let (reading, seen) = await read(user: #"{"nickname": "kid"}"#)

        #expect(reading?.pullRequests == PullRequestsAwaitingViewer())
        #expect(seen.map { $0[1] } == ["/user"])
    }

    @Test("one list refused keeps the other, and the reading is not kept as whole")
    func halfRefused() async {
        let readings = StartingPointReader.Readings()
        let request = StartingPointReadingRequest(repoPath: TestScratch.unique("bitbucket-half"), asksGitHub: true)
        let calls = Calls()
        let ask: @Sendable () async -> StartingPointReading? = {
            await Forge.$remoteOverride.withValue({ _ in "git@bitbucket.org:debtges/ledger.git" }) {
                await Bitbucket.$commandOverride.withValue({ arguments, _ in
                    if arguments.starts(with: ["auth", "status"]) {
                        return ShellResult(status: 0, stdout: BitbucketPipelineLogTests.signedIn, stderr: "")
                    }
                    await calls.record(arguments)
                    if arguments[1] == "/user" { return ShellResult(status: 0, stdout: #"{"uuid": "\#(Self.viewer)"}"#, stderr: "") }
                    if arguments[3].contains("reviewers.uuid") {
                        return ShellResult(status: 1, stdout: "", stderr: "Error: 429 Too Many Requests")
                    }
                    return ShellResult(status: 0, stdout: Self.page([15]), stderr: "")
                }) {
                    await StartingPointReader.load(request, from: readings)
                }
            }
        }

        let first = await ask()
        _ = await ask()

        #expect(first?.pullRequests.authored.map(\.number) == [15])
        #expect(first?.pullRequests.reviewRequested.isEmpty == true)
        #expect(await calls.seen.filter { $0[1] == "/user" }.count == 2)
    }
}
