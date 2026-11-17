import Foundation
import Testing
@testable import Core

@Suite("Checks in flight")
struct ChecksInFlightTests {
    private func run(_ name: String, _ status: String, conclusion: String = "", workflow: String = "tests") -> String {
        """
        {"__typename":"CheckRun","completedAt":"0001-01-01T00:00:00Z","conclusion":"\(conclusion)",\
        "detailsUrl":"https://example/\(workflow)/\(name)","name":"\(name)","startedAt":"0001-01-01T00:00:00Z",\
        "status":"\(status)","workflowName":"\(workflow)"}
        """
    }

    private func runs(_ entries: [String]) throws -> [CheckRun] {
        try GitHub.decodeChecks(from: Data("""
        {"number":1,"title":"PR","url":"https://example/1","state":"OPEN","statusCheckRollup":[\(entries.joined(separator: ","))]}
        """.utf8))
    }

    @Test("one job in progress is named")
    func oneRunning() throws {
        let line = ChecksInFlight.line(try runs([
            run("build", "COMPLETED", conclusion: "SUCCESS"),
            run("test", "IN_PROGRESS"),
        ]))
        #expect(line == "Running: test")
    }

    @Test("several jobs in progress are all named while they fit")
    func severalRunning() throws {
        let line = ChecksInFlight.line(try runs([run("build", "IN_PROGRESS"), run("test", "IN_PROGRESS")]))
        #expect(line == "Running: build, test")
    }

    @Test("jobs that do not fit are counted rather than named, so the line never wraps")
    func tooManyRunning() throws {
        let names = ["lint", "build", "core suite", "browser scripts", "swiftlint"]
        let line = try #require(ChecksInFlight.line(try runs(names.map { run($0, "IN_PROGRESS") })))
        #expect(line == "Running: lint, build and 3 more")
        #expect(line.count <= ChecksInFlight.longestLine)
    }

    @Test("a single name longer than the line is still named, and what follows is counted")
    func longFirstName() throws {
        let long = "a job whose name goes on longer than the whole bar is wide"
        let line = ChecksInFlight.line(try runs([run(long, "IN_PROGRESS"), run("test", "IN_PROGRESS")]))
        #expect(line == "Running: \(long) and 1 more")
    }

    @Test("queued jobs are told apart from running ones")
    func queuedBesideRunning() throws {
        let line = ChecksInFlight.line(try runs([
            run("lint", "QUEUED"),
            run("test", "IN_PROGRESS"),
            run("browser", "QUEUED"),
        ]))
        #expect(line == "Running: test, 2 queued")
    }

    @Test("with nothing started yet, the queued jobs are the ones named")
    func onlyQueued() throws {
        let line = ChecksInFlight.line(try runs([run("lint", "QUEUED"), run("test", "QUEUED")]))
        #expect(line == "Queued: lint, test")
    }

    @Test("a job of the same name in two workflows is named once")
    func sameNameTwice() throws {
        let line = ChecksInFlight.line(try runs([
            run("test", "IN_PROGRESS", workflow: "tests"),
            run("test", "IN_PROGRESS", workflow: "nightly"),
        ]))
        #expect(line == "Running: test")
    }

    @Test("when every check has finished there is nothing to name")
    func allFinished() throws {
        let line = ChecksInFlight.line(try runs([
            run("build", "COMPLETED", conclusion: "SUCCESS"),
            run("test", "COMPLETED", conclusion: "FAILURE"),
        ]))
        #expect(line == nil)
        #expect(ChecksInFlight.line([]) == nil)
    }

    @Test("the pull request bar names the running job while checks run")
    func barNamesTheJob() throws {
        let checks = try runs([run("lint", "QUEUED"), run("test", "IN_PROGRESS")])
        let standing = PullRequestStanding.of(
            branch: "feat/534",
            baseBranch: "develop",
            pullRequest: pullRequest(checks: .pending, summary: "1 check running"),
            checkRuns: checks
        )
        #expect(standing.secondary == "Running: test, 1 queued")
    }

    @Test("once the checks have finished the bar says what it said before")
    func barGoesBack() throws {
        let checks = try runs([run("test", "COMPLETED", conclusion: "SUCCESS")])
        let named = PullRequestStanding.of(
            branch: "feat/534",
            baseBranch: "develop",
            pullRequest: pullRequest(checks: .passing, summary: "1 check passed"),
            checkRuns: checks
        )
        let unnamed = PullRequestStanding.of(
            branch: "feat/534",
            baseBranch: "develop",
            pullRequest: pullRequest(checks: .passing, summary: "1 check passed")
        )
        #expect(named.secondary == unnamed.secondary)
    }

    @Test("without the runs read yet, the bar falls back to the count it already had")
    func barWithoutRuns() {
        let standing = PullRequestStanding.of(
            branch: "feat/534",
            baseBranch: "develop",
            pullRequest: pullRequest(checks: .pending, summary: "1 check running")
        )
        #expect(standing.secondary == "1 check running")
    }

    @Test("with several running and some queued, the queued count still fits on the line")
    func severalRunningAndQueued() throws {
        let names = ["house rules", "build", "core suite", "browser scripts"]
        let line = try #require(ChecksInFlight.line(try runs(
            names.map { run($0, "IN_PROGRESS") } + [run("lint", "QUEUED"), run("nightly", "QUEUED")]
        )))
        #expect(line == "Running: house rules and 3 more, 2 queued")
        #expect(line.hasSuffix(", 2 queued"))
    }

    @Test("with nothing started yet and more queued than fit, the rest are counted")
    func manyQueued() throws {
        let names = ["house rules", "build", "core suite", "browser scripts"]
        let line = ChecksInFlight.line(try runs(names.map { run($0, "QUEUED") }))
        #expect(line == "Queued: house rules and 3 more")
    }

    @Test(
        "every status GitHub reports for a job not yet finished is sorted into running or queued",
        arguments: [
            ("IN_PROGRESS", "Running: test"),
            ("PENDING", "Running: test"),
            ("QUEUED", "Queued: test"),
            ("WAITING", "Queued: test"),
            ("REQUESTED", "Queued: test"),
        ]
    )
    func everyStatus(status: String, expected: String) throws {
        #expect(ChecksInFlight.line(try runs([run("test", status)])) == expected)
    }

    @Test("a commit status still expected is queued, and one pending is running")
    func commitStatuses() {
        let expected = CheckRun(name: "coverage", status: "PENDING", conclusion: "EXPECTED")
        let pending = CheckRun(name: "deploy", status: "PENDING", conclusion: "PENDING")
        #expect(ChecksInFlight.line([expected]) == "Queued: coverage")
        #expect(ChecksInFlight.line([pending, expected]) == "Running: deploy, 1 queued")
    }

    @Test("a draft names its running job after the word Draft")
    func draftNamesTheJob() throws {
        let standing = PullRequestStanding.of(
            branch: "feat/534",
            baseBranch: "develop",
            pullRequest: pullRequest(checks: .pending, summary: "1 check running", isDraft: true),
            checkRuns: try runs([run("test", "IN_PROGRESS")])
        )
        #expect(standing.secondary == "Draft, Running: test")
    }

    @Test("passed checks are described as before even when a run read earlier was still going")
    func passedIgnoresStaleRuns() throws {
        let standing = PullRequestStanding.of(
            branch: "feat/534",
            baseBranch: "develop",
            pullRequest: pullRequest(checks: .passing, summary: "2 checks passed"),
            checkRuns: try runs([run("test", "IN_PROGRESS")])
        )
        #expect(!standing.secondary.contains("Running"))
    }

    private func pullRequest(checks: PullRequest.Checks, summary: String, isDraft: Bool = false) -> PullRequest {
        PullRequest(
            number: 534,
            title: "Name the running CI job",
            url: "https://example/534",
            state: "OPEN",
            isDraft: isDraft,
            mergeable: "MERGEABLE",
            checks: checks,
            checksSummary: summary,
            branch: "feat/534"
        )
    }
}
