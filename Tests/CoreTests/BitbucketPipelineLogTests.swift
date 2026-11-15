import Foundation
import Testing
@testable import Core

@Suite("A failed Bitbucket Pipelines build's log")
struct BitbucketPipelineLogTests {
    private actor Calls {
        var seen: [[String]] = []
        func record(_ arguments: [String]) { seen.append(arguments) }
    }

    static let signedIn = """
    {"hosts": [{"key": "api.bitbucket.org", "kind": "cloud"}],
     "contexts": [{"name": "work", "host": "api.bitbucket.org", "active": true}]}
    """

    static let steps = """
    {"page": 1, "values": [
      {"uuid": "{11111111-1111-4111-8111-111111111111}", "name": "Lint",
       "state": {"name": "COMPLETED", "result": {"name": "SUCCESSFUL"}}},
      {"uuid": "{add0ed3c-cec7-4412-85be-d9ce5e667afe}", "name": "Build and deploy",
       "state": {"name": "COMPLETED", "result": {"name": "FAILED"}}}
    ]}
    """

    @Test("the build number is read from the old and the new results link, with its step when named", arguments: [
        ("https://bitbucket.org/atlassian/aui/addon/pipelines/home#!/results/14542", 14542, nil as String?),
        ("https://bitbucket.org/debtges/ledger/pipelines/results/88", 88, nil),
        (
            "https://bitbucket.org/debtges/ledger/pipelines/results/88/steps/%7BADD0ED3C-CEC7-4412-85BE-D9CE5E667AFE%7D",
            88, "{add0ed3c-cec7-4412-85be-d9ce5e667afe}"
        ),
        ("https://bitbucket.org/acme/results/addon/pipelines/home#!/results/7", 7, nil),
        ("https://bitbucket.org/results/steps/pipelines/results/9", 9, nil),
    ])
    func parsesTarget(url: String, build: Int, step: String?) {
        #expect(BitbucketPipelineTarget.parse(detailsURL: url) == BitbucketPipelineTarget(buildNumber: build, step: step))
    }

    @Test("a link that is not a Pipelines run on Bitbucket has no log to read", arguments: [
        "https://github.com/acme/widgets/actions/runs/1/job/2",
        "https://bamboo.atlassian.com/browse/AUI-1",
        "https://bitbucket.org/debtges/ledger/pipelines/results/latest",
        "",
    ])
    func noTarget(url: String) {
        #expect(BitbucketPipelineTarget.parse(detailsURL: url) == nil)
    }

    @Test("a build that is neither a Pipelines run nor a GitHub Actions run has no log, and asks nothing")
    func unreadableLogAsksNothing() async {
        let log = await Bitbucket.$commandOverride.withValue({ arguments, _ in
            Issue.record("bkt was asked \(arguments)")
            return ShellResult(status: 1, stdout: "", stderr: "")
        }) {
            await ForgePullRequests.failedLog(
                of: CheckRun(name: "AUI", status: "COMPLETED", detailsURL: "https://bamboo.atlassian.com/browse/AUI-1"),
                worktree: "/nowhere"
            )
        }

        #expect(log == nil)
    }

    @Test("only the failed steps are read, unless the link names one")
    func choosesFailedSteps() throws {
        let steps = try Bitbucket.decode(BitbucketPage<BitbucketPipelineStep>.self, from: Self.steps).values

        #expect(BitbucketPipelineStep.failing(steps, named: nil).map(\.name) == ["Build and deploy"])
        #expect(BitbucketPipelineStep.failing(steps, named: "{11111111-1111-4111-8111-111111111111}").map(\.name) == ["Lint"])
    }

    @Test("bkt is asked for the steps, then for each failed step's log, through the context")
    func readsLog() async throws {
        let calls = Calls()
        let log = try await Forge.$remoteOverride.withValue({ _ in "git@bitbucket.org:debtges/ledger.git" }) {
            try await Bitbucket.$commandOverride.withValue({ arguments, _ in
                await calls.record(arguments)
                if arguments.starts(with: ["auth", "status"]) { return ShellResult(status: 0, stdout: Self.signedIn, stderr: "") }
                if arguments.first == "api" { return ShellResult(status: 0, stdout: Self.steps, stderr: "") }
                return ShellResult(status: 0, stdout: "+ npm test\n1 failing\n", stderr: "")
            }) {
                try await Bitbucket.pipelineLog(BitbucketPipelineTarget(buildNumber: 88), worktree: "/nowhere")
            }
        }

        #expect(log == "+ npm test\n1 failing\n")
        let seen = await calls.seen
        #expect(seen[1] == [
            "api", "/repositories/debtges/ledger/pipelines/88/steps/", "--param", "pagelen=100", "--context", "work",
        ])
        #expect(seen[2] == [
            "pipeline", "logs", "88", "--step", "{add0ed3c-cec7-4412-85be-d9ce5e667afe}",
            "--workspace", "debtges", "--repo", "ledger", "--context", "work",
        ])
        #expect(seen.count == 3)
    }

    @Test("no more than three failed steps are read, however many failed")
    func readsThreeStepsAtMost() async throws {
        let failed = (1...5).map { index in
            #"{"uuid": "{0000000\#(index)-1111-4111-8111-111111111111}", "name": "Step \#(index)", "#
                + #""state": {"name": "COMPLETED", "result": {"name": "FAILED"}}}"#
        }
        let page = #"{"values": ["# + failed.joined(separator: ",") + "]}"
        let calls = Calls()
        let log = try await Forge.$remoteOverride.withValue({ _ in "git@bitbucket.org:debtges/ledger.git" }) {
            try await Bitbucket.$commandOverride.withValue({ arguments, _ in
                await calls.record(arguments)
                if arguments.starts(with: ["auth", "status"]) { return ShellResult(status: 0, stdout: Self.signedIn, stderr: "") }
                if arguments.first == "api" { return ShellResult(status: 0, stdout: page, stderr: "") }
                return ShellResult(status: 0, stdout: "failed\n", stderr: "")
            }) {
                try await Bitbucket.pipelineLog(BitbucketPipelineTarget(buildNumber: 88), worktree: "/nowhere")
            }
        }

        let logged = await calls.seen.filter { $0.starts(with: ["pipeline", "logs"]) }
        #expect(logged.count == 3)
        #expect(log.contains("== Step 3 =="))
        #expect(!log.contains("== Step 4 =="))
    }

    @Test("a step whose log cannot be read does not lose the others")
    func unreadableStepIsSkipped() async throws {
        let page = """
        {"values": [
          {"uuid": "{11111111-1111-4111-8111-111111111111}", "name": "Lint",
           "state": {"name": "COMPLETED", "result": {"name": "ERROR"}}},
          {"uuid": "{add0ed3c-cec7-4412-85be-d9ce5e667afe}", "name": "Test",
           "state": {"name": "COMPLETED", "result": {"name": "FAILED"}}}
        ]}
        """
        let log = try await Forge.$remoteOverride.withValue({ _ in "git@bitbucket.org:debtges/ledger.git" }) {
            try await Bitbucket.$commandOverride.withValue({ arguments, _ in
                if arguments.starts(with: ["auth", "status"]) { return ShellResult(status: 0, stdout: Self.signedIn, stderr: "") }
                if arguments.first == "api" { return ShellResult(status: 0, stdout: page, stderr: "") }
                if arguments.contains("{11111111-1111-4111-8111-111111111111}") {
                    return ShellResult(status: 1, stdout: "", stderr: "404 Not Found")
                }
                return ShellResult(status: 0, stdout: "1 failing\n", stderr: "")
            }) {
                try await Bitbucket.pipelineLog(BitbucketPipelineTarget(buildNumber: 88), worktree: "/nowhere")
            }
        }

        #expect(log == "1 failing\n")
    }

    @Test("several failed steps are joined under their names")
    func joinsLogs() {
        #expect(Bitbucket.joinedLog([("Lint", "a"), ("Test", "b")]) == "== Lint ==\na\n\n== Test ==\nb")
        #expect(Bitbucket.joinedLog([("Lint", "a")]) == "a")
    }

    @Test("a Bitbucket build's handoff names Bitbucket and the pipeline, not GitHub")
    func handoffWording() {
        let text = CheckFailureHandoff.request(
            [CheckFailureHandoff.Mention(name: "Pipeline #88")], number: 7, host: .bitbucket
        )

        #expect(text.contains("came from Bitbucket and from whoever wrote the pipeline"))
        #expect(text.contains("The Bitbucket build \"Pipeline #88\" failed."))
        #expect(!text.contains("GitHub"))
        #expect(text.contains("never edit bitbucket-pipelines.yml, skip or loosen a test or relax a lint rule to turn the build green"))
        #expect(text.contains("then wait for its builds, thirty minutes at most"))
        #expect(!text.contains("workflow"))
        #expect(CheckFailureHandoff.request([CheckFailureHandoff.Mention(name: "test")], number: 7)
            .contains("The GitHub check \"test\""))
    }
}
