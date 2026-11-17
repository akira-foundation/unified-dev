import Testing
import Foundation
import Synchronization
@testable import Core

private final class GhCalls: Sendable {
    private let count = Mutex(0)
    var made: Int { count.withLock { $0 } }
    func note() { count.withLock { $0 += 1 } }
}

private final class StoppedClock: Sendable {
    private let instant = Mutex(ContinuousClock.now)
    var now: ContinuousClock.Instant { instant.withLock { $0 } }
    func set(_ to: ContinuousClock.Instant) { instant.withLock { $0 = to } }
}

@Suite("Readers of a workspace's pull request", .scratchDirectory)
struct PullRequestReaderTests {
    private static let pending = #"""
        {"number":42,"title":"Work","url":"https://github.com/org/repo/pull/42","state":"OPEN","isDraft":false,
        "mergeable":"MERGEABLE","reviewDecision":null,"headRefName":"feature","baseRefName":"main","closedAt":null,
        "headRefOid":"abc","statusCheckRollup":[{"__typename":"CheckRun","name":"test","status":"IN_PROGRESS",
        "conclusion":null,"workflowName":"CI","detailsUrl":"https://github.com/org/repo/runs/1"}]}
        """#

    private func workspace(_ name: String) -> Workspace {
        Workspace(
            repoID: RepoID("repo"), name: name, branch: "feature",
            path: TestScratch.unique(name), baseBranch: "main"
        )
    }

    @Test func everyReaderTakesAnAnswerYoungerThanItsOwnInterval() {
        for reader in PullRequestReader.allCases {
            #expect(reader.maxAge == reader.interval)
        }
        #expect(PullRequestReader.pullRequestBar.interval == .seconds(20))
        #expect(PullRequestReader.checksTab.interval == .seconds(20))
        #expect(PullRequestReader.checksNotification.interval == .seconds(30))
    }

    @Test func tenMinutesOfAllThreeLoopsAskGitHubAsOftenAsTheBarAlone() async throws {
        let clock = StoppedClock()
        let start = clock.now
        let readings = SharedReadings<String, Int>(now: { clock.now })
        let calls = GhCalls()
        let offsets: [(PullRequestReader, Duration)] = [
            (.pullRequestBar, .zero), (.checksTab, .seconds(7)), (.checksNotification, .seconds(30)),
        ]
        var asks: [(Duration, PullRequestReader)] = []
        for (reader, offset) in offsets {
            var moment = offset
            while moment < .seconds(600) {
                asks.append((moment, reader))
                moment += reader.interval
            }
        }
        asks.sort { $0.0 < $1.0 }

        for (moment, reader) in asks {
            clock.set(start + moment)
            _ = try await readings.value(for: "selected", notOlderThan: reader.maxAge) { calls.note(); return 0 }
        }

        #expect(asks.count == 30 + 30 + 19)
        #expect(calls.made == 30)
    }

    @Test func theChecksTabReadsOnItsOwnWhenNothingElseDoes() async throws {
        let clock = StoppedClock()
        let start = clock.now
        let readings = SharedReadings<String, Int>(now: { clock.now })
        let calls = GhCalls()
        let reader = PullRequestReader.checksTab
        var moment = Duration.zero
        while moment < .seconds(60) {
            clock.set(start + moment)
            _ = try await readings.value(for: "selected", notOlderThan: reader.maxAge) { calls.note(); return 0 }
            moment += reader.interval
        }

        #expect(calls.made == 3)
    }

    @Test func aSecondReaderWithinItsIntervalRunsNoGh() async throws {
        let calls = GhCalls()
        let selected = workspace("shared-read")
        let (first, second) = await GitHub.$commandOverride.withValue({ _, _ in
            calls.note()
            return ShellResult(status: 0, stdout: Self.pending, stderr: "")
        }) {
            let first = await GitHub.readPullRequestAndChecks(
                for: selected, maxAge: PullRequestReader.pullRequestBar.maxAge
            )
            let second = await GitHub.readPullRequestAndChecks(
                for: selected, maxAge: PullRequestReader.checksNotification.maxAge
            )
            return (first, second)
        }

        guard case .current(let pullRequest?) = second.pullRequest else {
            Issue.record("The second reader should take the first one's pull request")
            return
        }
        #expect(calls.made == 1)
        #expect(pullRequest.number == 42)
        #expect(pullRequest.checks == .pending)
        #expect(second.checks?.runs.map(\.name) == ["test"])
        if case .current(let earlier?) = first.pullRequest { #expect(earlier == pullRequest) }
    }

    @Test func readersArrivingTogetherShareOneGhCall() async throws {
        let calls = GhCalls()
        let selected = workspace("together")
        await GitHub.$commandOverride.withValue({ _, _ in
            calls.note()
            try? await Task.sleep(for: .milliseconds(200))
            return ShellResult(status: 0, stdout: Self.pending, stderr: "")
        }) {
            async let bar = GitHub.readPullRequestAndChecks(for: selected, maxAge: PullRequestReader.pullRequestBar.maxAge)
            async let checks = GitHub.readPullRequestAndChecks(for: selected, maxAge: PullRequestReader.checksTab.maxAge)
            _ = await [bar.checks, checks.checks]
        }

        #expect(calls.made == 1)
    }

    @Test func aWorkspaceOnAnotherBranchOrPullRequestIsReadAgain() async throws {
        let calls = GhCalls()
        var selected = workspace("moved")
        var made: [Int] = []
        await GitHub.$commandOverride.withValue({ _, _ in
            calls.note()
            return ShellResult(status: 0, stdout: Self.pending, stderr: "")
        }) {
            _ = await GitHub.readPullRequestAndChecks(for: selected, maxAge: .seconds(20))
            made.append(calls.made)
            selected.branch = "elsewhere"
            _ = await GitHub.readPullRequestAndChecks(for: selected, maxAge: .seconds(20))
            made.append(calls.made)
            selected.pullRequestNumber = 7
            _ = await GitHub.readPullRequestAndChecks(for: selected, maxAge: .seconds(20))
            made.append(calls.made)
        }

        #expect(made[0] < made[1])
        #expect(made[1] < made[2])
    }

    @Test func aReaderAskingForAFreshAnswerRunsGhAgain() async throws {
        let calls = GhCalls()
        let selected = workspace("fresh-read")
        await GitHub.$commandOverride.withValue({ _, _ in
            calls.note()
            return ShellResult(status: 0, stdout: Self.pending, stderr: "")
        }) {
            _ = await GitHub.readPullRequestAndChecks(for: selected, maxAge: PullRequestReader.checksTab.maxAge)
            _ = await GitHub.readPullRequestAndChecks(for: selected, maxAge: .zero)
        }

        #expect(calls.made == 2)
    }

    @Test func anotherWorkspaceDoesNotTakeTheSelectedOnesAnswer() async throws {
        let calls = GhCalls()
        await GitHub.$commandOverride.withValue({ _, _ in
            calls.note()
            return ShellResult(status: 0, stdout: Self.pending, stderr: "")
        }) {
            _ = await GitHub.readPullRequestAndChecks(for: workspace("selected"), maxAge: .seconds(20))
            _ = await GitHub.readPullRequestAndChecks(for: workspace("elsewhere"), maxAge: .seconds(20))
        }

        #expect(calls.made == 2)
    }

    @Test func anAnswerReadUnderOneLoginIsNotGivenToAnother() async throws {
        let calls = GhCalls()
        let selected = workspace("rerouted")
        let own = GitHubLogin.profile(ProfileID("debtges"), directory: URL(filePath: "/support/GitHubLogins/debtges"))
        await GitHub.$commandOverride.withValue({ _, _ in
            calls.note()
            return ShellResult(status: 0, stdout: Self.pending, stderr: "")
        }) {
            _ = await GitHub.readPullRequestAndChecks(for: selected, maxAge: .seconds(20))
            await GitHub.$loginResolverOverride.withValue({ _ in own }) {
                _ = await GitHub.readPullRequestAndChecks(for: selected, maxAge: .seconds(20))
            }
        }

        #expect(calls.made == 2)
    }

    @Test func aFailedReadIsReportedWithoutChecksAndAskedAgain() async throws {
        let calls = GhCalls()
        let selected = workspace("failed-read")
        let reading = await GitHub.$commandOverride.withValue({ _, _ in
            calls.note()
            return ShellResult(status: 1, stdout: "", stderr: "error connecting to github.com")
        }) {
            _ = await GitHub.readPullRequestAndChecks(for: selected, maxAge: .seconds(20))
            return await GitHub.readPullRequestAndChecks(for: selected, maxAge: .seconds(20))
        }

        guard case .unavailable = reading.pullRequest else {
            Issue.record("A failed read should be reported as unavailable")
            return
        }
        #expect(reading.checks == nil)
        #expect(calls.made == 2)
    }

    @Test func refusedChecksAreUnreadableAndNoPullRequestHasNone() {
        let unreadable = PullRequestReading(PullRequestSnapshot(
            pullRequest: PullRequest(number: 1, title: "t", url: "u", state: "OPEN", checks: .unavailable, branch: "feature"),
            runs: []
        ))
        let none = PullRequestReading(nil)

        #expect(unreadable.checks == .unreadable)
        #expect(none.checks == .runs([]))
    }
}
