import Foundation
import Testing
@testable import Core

@Suite("A Bitbucket pipeline's steps as rows of their own")
struct BitbucketPipelineStepTests {
    private actor Calls {
        var seen: [[String]] = []
        func record(_ arguments: [String]) { seen.append(arguments) }
    }

    static let ledger = ForgeRepository(kind: .bitbucket, host: "bitbucket.org", owner: "debtges", name: "ledger")

    static func step(_ name: String, _ state: String, _ result: String? = nil, uuid: String) -> String {
        let outcome = result.map { #", "result": {"name": "\#($0)"}"# } ?? ""
        return #"{"uuid": "{\#(uuid)}", "name": "\#(name)", "state": {"name": "\#(state)"\#(outcome)}, "#
            + #""started_on": "2025-06-10T06:17:37.581560549Z", "completed_on": "2025-06-10T06:24:31.664116878Z"}"#
    }

    static let lint = "11111111-1111-4111-8111-111111111111"
    static let build = "add0ed3c-cec7-4412-85be-d9ce5e667afe"

    static func page(_ steps: String...) -> String { #"{"values": ["# + steps.joined(separator: ",") + "]}" }

    static func pipeline(_ build: Int, repository: String = "debtges/ledger", finished: Bool = true) -> CheckRun {
        CheckRun(
            name: "Pipeline #\(build) for feat/7", status: finished ? "COMPLETED" : "IN_PROGRESS",
            conclusion: finished ? "FAILURE" : nil,
            detailsURL: "https://bitbucket.org/\(repository)/addon/pipelines/home#!/results/\(build)",
            completedAt: finished ? Date(timeIntervalSince1970: TimeInterval(build)) : nil
        )
    }

    @Test("each step state becomes the check state a GitHub job would have", arguments: [
        ("PENDING", nil as String?, "QUEUED", nil as String?),
        ("READY", nil, "QUEUED", nil),
        ("IN_PROGRESS", nil, "IN_PROGRESS", nil),
        ("COMPLETED", "SUCCESSFUL", "COMPLETED", "SUCCESS"),
        ("COMPLETED", "FAILED", "COMPLETED", "FAILURE"),
        ("COMPLETED", "ERROR", "COMPLETED", "FAILURE"),
        ("COMPLETED", "STOPPED", "COMPLETED", "CANCELLED"),
        ("COMPLETED", "NOT_RUN", "COMPLETED", "SKIPPED"),
    ])
    func stateMapping(state: String, result: String?, status: String, conclusion: String?) throws {
        let steps = try Bitbucket.decode(
            BitbucketPage<BitbucketPipelineStep>.self, from: Self.page(Self.step("Lint", state, result, uuid: Self.lint))
        ).values
        let target = BitbucketPipelineTarget(repository: "debtges/ledger", buildNumber: 88)
        let row = try #require(BitbucketPipelineStep.rows(steps, of: Self.pipeline(88), in: target)?.first)

        #expect(row.status == status)
        #expect(row.conclusion == conclusion)
        #expect(row.workflowName == "Pipeline #88 for feat/7")
        #expect(row.name == "Lint")
    }

    @Test("a step in a state not measured keeps the pipeline as one row")
    func unknownStateKeepsOneRow() throws {
        let steps = try Bitbucket.decode(BitbucketPage<BitbucketPipelineStep>.self, from: Self.page(
            Self.step("Lint", "COMPLETED", "SUCCESSFUL", uuid: Self.lint), Self.step("Deploy", "PAUSED", uuid: Self.build)
        )).values
        let target = BitbucketPipelineTarget(repository: "debtges/ledger", buildNumber: 88)

        #expect(BitbucketPipelineStep.rows(steps, of: Self.pipeline(88), in: target) == nil)
        #expect(BitbucketPipelineStep.rows([], of: Self.pipeline(88), in: target) == nil)
    }

    @Test("a step's row links to that step, so its log is the one read")
    func stepLinkNamesTheStep() throws {
        let steps = try Bitbucket.decode(
            BitbucketPage<BitbucketPipelineStep>.self, from: Self.page(Self.step("Build", "COMPLETED", "FAILED", uuid: Self.build))
        ).values
        let target = BitbucketPipelineTarget(repository: "debtges/ledger", buildNumber: 88)
        let row = try #require(BitbucketPipelineStep.rows(steps, of: Self.pipeline(88), in: target)?.first)

        #expect(BitbucketPipelineTarget.parse(detailsURL: row.detailsURL)
            == BitbucketPipelineTarget(repository: "debtges/ledger", buildNumber: 88, step: "{\(Self.build)}"))
    }

    @Test("only this repository's pipelines are expanded, and other builds stay as they are")
    func targets() {
        let runs = [
            Self.pipeline(88),
            CheckRun(name: "Bamboo", status: "COMPLETED", conclusion: "SUCCESS", detailsURL: "https://bamboo.atlassian.com/browse/AUI-1"),
            Self.pipeline(89, repository: "elsewhere/ledger"),
        ]

        let targets = Bitbucket.pipelineTargets(of: runs, in: Self.ledger)

        #expect(targets == [0: BitbucketPipelineTarget(repository: "debtges/ledger", buildNumber: 88)])
    }

    @Test("a pipeline is replaced by its steps in place, and one whose steps were not read stays one row")
    func expanding() throws {
        let runs = [Self.pipeline(88), Self.pipeline(90)]
        let steps = try Bitbucket.decode(BitbucketPage<BitbucketPipelineStep>.self, from: Self.page(
            Self.step("Lint", "COMPLETED", "SUCCESSFUL", uuid: Self.lint), Self.step("Build", "COMPLETED", "FAILED", uuid: Self.build)
        )).values
        let targets = [
            0: BitbucketPipelineTarget(repository: "debtges/ledger", buildNumber: 88),
            1: BitbucketPipelineTarget(repository: "debtges/ledger", buildNumber: 90),
        ]

        let expanded = Bitbucket.expanding(runs, with: [0: steps], targets: targets)

        #expect(expanded.map(\.name) == ["Lint", "Build", "Pipeline #90 for feat/7"])
        #expect(GitHub.rollup(expanded).0 == GitHub.rollup(runs).0)
    }

    @Test("a finished pipeline's steps are asked for once, and a running one's on every read")
    func finishedStepsAreKept() async {
        let calls = Calls()
        let steps = Self.page(Self.step("Build", "COMPLETED", "FAILED", uuid: Self.build))
        let running = Self.page(Self.step("Build", "IN_PROGRESS", uuid: Self.build))
        let read: @Sendable ([CheckRun]) async -> [CheckRun] = { runs in
            await Bitbucket.$commandOverride.withValue({ arguments, _ in
                await calls.record(arguments)
                return ShellResult(status: 0, stdout: arguments[1].contains("/7101/") ? running : steps, stderr: "")
            }) {
                await Bitbucket.withPipelineSteps(runs, in: Self.ledger, context: "work", directory: "/nowhere")
            }
        }

        _ = await read([Self.pipeline(7100)])
        let again = await read([Self.pipeline(7100)])
        _ = await read([Self.pipeline(7101, finished: false)])
        _ = await read([Self.pipeline(7101, finished: false)])

        #expect(again.map(\.name) == ["Build"])
        #expect(await calls.seen.map { $0[1] } == [
            "/repositories/debtges/ledger/pipelines/7100/steps/",
            "/repositories/debtges/ledger/pipelines/7101/steps/",
            "/repositories/debtges/ledger/pipelines/7101/steps/",
        ])
    }

    @Test("steps bkt cannot read leave the pipeline as one row")
    func unreadableSteps() async {
        let runs = await Bitbucket.$commandOverride.withValue({ _, _ in
            ShellResult(status: 1, stdout: "", stderr: "Error: 403 Forbidden")
        }) {
            await Bitbucket.withPipelineSteps([Self.pipeline(7200)], in: Self.ledger, context: "work", directory: "/nowhere")
        }

        #expect(runs == [Self.pipeline(7200)])
    }
}
