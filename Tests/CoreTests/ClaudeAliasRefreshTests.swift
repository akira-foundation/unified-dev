import Foundation
import Synchronization
import Testing
@testable import Core

private final class ManualClock: @unchecked Sendable {
    private let instant = Mutex(ContinuousClock.now)

    var now: ContinuousClock.Instant { instant.withLock { $0 } }
    func advance(by duration: Duration) { instant.withLock { $0 += duration } }
}

private final class InstalledVersion: @unchecked Sendable {
    private let state = Mutex<(version: String?, reads: Int)>((nil, 0))

    init(_ version: String?) { state.withLock { $0.version = version } }

    var reads: Int { state.withLock { $0.reads } }
    func change(to version: String?) { state.withLock { $0.version = version } }
    func read() -> String? {
        state.withLock { state in
            state.reads += 1
            return state.version
        }
    }
}

@Suite("When the aliases of Claude Code are asked again", .tags(.agentProtocol), .scratchDirectory)
struct ClaudeAliasRefreshTests {
    private var work: AgentAccountHome { probeAccount() }

    private func refresh(
        _ launches: ProbeLaunches,
        version: InstalledVersion,
        clock: ManualClock,
        activity: ClaudeAccountActivity = ClaudeAccountActivity(),
        answer: @escaping @Sendable (String) -> [String]
    ) -> ClaudeAliasRefresh {
        ClaudeAliasRefresh(
            probe: { _ in scriptedProbe(launches, timeout: .milliseconds(20), activity: activity, output: answer) },
            installedVersion: { _ in version.read() },
            activity: activity,
            now: { clock.now }
        )
    }

    @Test("one version of the CLI is probed once per account, and what it answered is kept for that account")
    func probesAVersionOnce() async throws {
        let store = try makeTestStore("refresh")
        let launches = ProbeLaunches()
        let clock = ManualClock()
        let subject = refresh(launches, version: InstalledVersion("2.1.309"), clock: clock) { alias in
            [probeInitLine("claude-\(alias)-5-5")]
        }

        await subject.refresh(account: work, in: store)
        clock.advance(by: ClaudeAliasRefresh.recheckInterval)
        await subject.refresh(account: work, in: store)

        #expect(launches.launches.count == ClaudeModelCatalog.builtIn.count)
        #expect(await ClaudeResolvedModel.reported(account: work, in: store) == [
            "fable": "claude-fable-5-5", "opus": "claude-opus-5-5",
            "sonnet": "claude-sonnet-5-5", "haiku": "claude-haiku-5-5",
        ])
        #expect(await ClaudeResolvedModel.reported(account: nil, in: store).isEmpty)
    }

    @Test("a CLI updated while the app is open is probed again, and its answer replaces the old one")
    func probesANewVersion() async throws {
        let store = try makeTestStore("refresh")
        let launches = ProbeLaunches()
        let clock = ManualClock()
        let version = InstalledVersion("2.1.309")
        let answers = Mutex("5-1")
        let subject = refresh(launches, version: version, clock: clock) { alias in
            [probeInitLine("claude-\(alias)-\(answers.withLock { $0 })")]
        }

        await subject.refresh(account: work, in: store)
        version.change(to: "2.1.322")
        answers.withLock { $0 = "5-2" }
        clock.advance(by: ClaudeAliasRefresh.recheckInterval)
        await subject.refresh(account: work, in: store)

        #expect(launches.launches.count == 2 * ClaudeModelCatalog.builtIn.count)
        #expect(await ClaudeResolvedModel.reported(account: work, in: store)["fable"] == "claude-fable-5-2")
    }

    @Test("the installed version is not read again within the interval")
    func readsTheVersionAtMostOncePerInterval() async throws {
        let store = try makeTestStore("refresh")
        let launches = ProbeLaunches()
        let version = InstalledVersion("2.1.309")
        let subject = refresh(launches, version: version, clock: ManualClock()) { alias in
            [probeInitLine("claude-\(alias)-5-5")]
        }

        await subject.refresh(account: work, in: store)
        version.change(to: "2.1.322")
        await subject.refresh(account: work, in: store)

        #expect(version.reads == 1)
        #expect(launches.launches.count == ClaudeModelCatalog.builtIn.count)
    }

    @Test("an account whose probe answered nothing is asked again only after the longer wait", .timeLimit(.minutes(1)))
    func retriesAnAccountThatAnsweredNothing() async throws {
        let store = try makeTestStore("refresh")
        let launches = ProbeLaunches()
        let clock = ManualClock()
        let subject = refresh(launches, version: InstalledVersion("2.1.322"), clock: clock) { _ in [] }

        await subject.refresh(account: work, in: store)
        clock.advance(by: ClaudeAliasRefresh.recheckInterval)
        await subject.refresh(account: work, in: store)
        #expect(launches.launches.count == ClaudeModelCatalog.builtIn.count)

        clock.advance(by: ClaudeAliasRefresh.retryInterval)
        await subject.refresh(account: work, in: store)
        #expect(launches.launches.count == 2 * ClaudeModelCatalog.builtIn.count)
        #expect(await ClaudeResolvedModel.reported(account: work, in: store).isEmpty)
    }

    @Test("a version that cannot be read keeps the last answer instead of probing again")
    func anUnreadableVersionKeepsTheAnswer() async throws {
        let store = try makeTestStore("refresh")
        let launches = ProbeLaunches()
        let clock = ManualClock()
        let version = InstalledVersion("2.1.322")
        let subject = refresh(launches, version: version, clock: clock) { alias in
            [probeInitLine("claude-\(alias)-5-5")]
        }

        await subject.refresh(account: work, in: store)
        version.change(to: nil)
        clock.advance(by: ClaudeAliasRefresh.recheckInterval)
        await subject.refresh(account: work, in: store)
        version.change(to: "2.1.322")
        clock.advance(by: ClaudeAliasRefresh.recheckInterval)
        await subject.refresh(account: work, in: store)

        #expect(launches.launches.count == ClaudeModelCatalog.builtIn.count)
    }

    @Test("a probe still running is not started a second time for the same account", .timeLimit(.minutes(1)))
    func neverProbesAnAccountTwiceAtOnce() async throws {
        let store = try makeTestStore("refresh")
        let launches = ProbeLaunches()
        let clock = ManualClock()
        let subject = ClaudeAliasRefresh(
            probe: { _ in scriptedProbe(launches, timeout: .seconds(30)) { _ in [] } },
            installedVersion: { _ in "2.1.322" },
            activity: ClaudeAccountActivity(),
            now: { clock.now }
        )

        let first = Task { await subject.refresh(account: work, in: store) }
        while launches.launches.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        clock.advance(by: ClaudeAliasRefresh.retryInterval)
        await subject.refresh(account: work, in: store)
        let startedWhileRunning = launches.launches.count
        launches.processes.forEach { $0.terminate() }
        first.cancel()
        await first.value

        #expect(startedWhileRunning == 1)
    }

    @Test("an account with a turn running is not probed, and is asked again at the next check")
    func skipsAnAccountWithATurnRunning() async throws {
        let store = try makeTestStore("refresh")
        let launches = ProbeLaunches()
        let clock = ManualClock()
        let activity = ClaudeAccountActivity()
        let subject = refresh(launches, version: InstalledVersion("2.1.322"), clock: clock, activity: activity) { alias in
            [probeInitLine("claude-\(alias)-5-5")]
        }

        let lease = await activity.beginRun(work.id)
        await subject.refresh(account: work, in: store)
        let launchedWhileRunning = launches.launches.count
        lease?.end()
        clock.advance(by: ClaudeAliasRefresh.recheckInterval)
        await subject.refresh(account: work, in: store)

        #expect(launchedWhileRunning == 0)
        #expect(launches.launches.count == ClaudeModelCatalog.builtIn.count)
    }

    @Test("an answer that misses an alias is kept, and the account is asked again after the longer wait")
    func aPartialAnswerIsAskedAgain() async throws {
        let store = try makeTestStore("refresh")
        let launches = ProbeLaunches()
        let clock = ManualClock()
        let subject = refresh(launches, version: InstalledVersion("2.1.322"), clock: clock) { alias in
            alias == "fable" ? [] : [probeInitLine("claude-\(alias)-5-5")]
        }

        await subject.refresh(account: work, in: store)
        clock.advance(by: ClaudeAliasRefresh.retryInterval)
        await subject.refresh(account: work, in: store)

        #expect(await ClaudeResolvedModel.reported(account: work, in: store)["opus"] == "claude-opus-5-5")
        #expect(launches.launches.count == 2 * ClaudeModelCatalog.builtIn.count)
    }

    @Test("a pin added to the account's settings is picked up without a new CLI")
    func aChangedPinIsAskedAgain() async throws {
        let store = try makeTestStore("refresh")
        let launches = ProbeLaunches()
        let clock = ManualClock()
        let account = work
        let subject = refresh(launches, version: InstalledVersion("2.1.322"), clock: clock) { alias in
            [probeInitLine("claude-\(alias)-5-5")]
        }

        await subject.refresh(account: account, in: store)
        try #"{"env":{"ANTHROPIC_DEFAULT_OPUS_MODEL":"claude-opus-4-1"}}"#
            .write(to: account.directory.appending(path: "settings.json"), atomically: true, encoding: .utf8)
        clock.advance(by: ClaudeAliasRefresh.recheckInterval)
        await subject.refresh(account: account, in: store)

        #expect(await ClaudeResolvedModel.reported(account: account, in: store)["opus"] == "claude-opus-4-1")
        #expect(launches.launches.count == 2 * ClaudeModelCatalog.builtIn.count - 1)
    }

    @Test("a pin added while the CLI version cannot be read is still picked up")
    func aChangedPinIsAskedAgainWithoutAVersion() async throws {
        let store = try makeTestStore("refresh")
        let launches = ProbeLaunches()
        let clock = ManualClock()
        let account = work
        let version = InstalledVersion("2.1.322")
        let subject = refresh(launches, version: version, clock: clock) { alias in
            [probeInitLine("claude-\(alias)-5-5")]
        }

        await subject.refresh(account: account, in: store)
        version.change(to: nil)
        try #"{"env":{"ANTHROPIC_DEFAULT_OPUS_MODEL":"claude-opus-4-1"}}"#
            .write(to: account.directory.appending(path: "settings.json"), atomically: true, encoding: .utf8)
        clock.advance(by: ClaudeAliasRefresh.recheckInterval)
        await subject.refresh(account: account, in: store)

        #expect(await ClaudeResolvedModel.reported(account: account, in: store)["opus"] == "claude-opus-4-1")
    }
}
