import Foundation
import Testing
@testable import Core

@Suite("Every start of the Claude CLI under an account holds it against the alias probe", .tags(.agentProtocol), .scratchDirectory)
struct ClaudeAccountLeaseTests {
    enum Starter: String, CaseIterable, Sendable {
        case quota, liveness, namer
    }

    private func start(
        _ starter: Starter,
        account: AgentAccountHome,
        activity: ClaudeAccountActivity,
        launched: @escaping @Sendable () -> Void
    ) async {
        let factory: @Sendable (AgentLaunch) -> any AgentProcessing = { _ in
            launched()
            return SilentProcess()
        }
        switch starter {
        case .quota:
            _ = await ClaudeCodeQuotaSource(
                environment: [:], account: account, activity: activity, makeProcess: factory, loginShellReady: {}
            ).read()
        case .liveness:
            _ = await AgentAccountLiveness(environment: [:], activity: activity, makeProcess: factory).report(for: account)
        case .namer:
            let namer = WorkspaceNamer(run: { _ in
                launched()
                return Data()
            }, activity: activity)
            _ = await namer.suggest(
                task: "rename the tabs", project: "p",
                template: PromptRegistry.definition(for: .nameWorkspace).defaultTemplate, account: account
            )
        }
    }

    @Test("the account is held while the CLI runs, and free once it has ended", arguments: Starter.allCases)
    func holdsTheAccountWhileItRuns(starter: Starter) async {
        let activity = ClaudeAccountActivity()
        let account = probeAccount()
        let held = AwaitedAnswer<Bool>()

        await start(starter, account: account, activity: activity) {
            held.set(activity.isRunning(account.id) && !activity.beginProbe(account.id))
        }

        #expect(held.answer == true)
        #expect(!activity.isRunning(account.id))
    }

    @Test("a start that arrives during a probe of the same account waits for it to end", arguments: Starter.allCases)
    func waitsForAProbeInFlight(starter: Starter) async {
        let activity = ClaudeAccountActivity()
        let account = probeAccount()
        let launched = AwaitedAnswer<Bool>()
        let finished = AwaitedAnswer<Bool>()
        #expect(activity.beginProbe(account.id))

        Task {
            await start(starter, account: account, activity: activity) { launched.set(true) }
            finished.set(true)
        }
        await waitUntil("the start waits for the probe") { activity.waitingRuns(account.id) == 1 }
        let launchedDuringProbe = launched.answer != nil
        activity.endProbe(account.id)

        #expect(await finished.wait(upTo: .seconds(10)) == true)
        #expect(!launchedDuringProbe)
        #expect(launched.answer == true)
    }

    @Test("auth status keeps the account until a CLI that ignores the request to stop has been killed", .timeLimit(.minutes(1)))
    func livenessHoldsTheAccountUntilTheCLIIsGone() async {
        let activity = ClaudeAccountActivity()
        let account = probeAccount()
        let started = AwaitedAnswer<ScriptedProbe>()
        let liveness = AgentAccountLiveness(environment: [:], timeout: .milliseconds(50), activity: activity) { _ in
            let process = ScriptedProbe(printing: [], ignoresTerminate: true)
            started.set(process)
            return process
        }

        _ = await liveness.report(for: account)
        let process = started.answer

        #expect(process?.killCount == 1)
        #expect(process?.isRunning == false)
        #expect(!activity.isRunning(account.id))
    }

    @Test("another account is not held by a probe")
    func anotherAccountRunsAtOnce() async {
        let activity = ClaudeAccountActivity()
        let work = probeAccount("work")
        let client = probeAccount("client")
        let launched = AwaitedAnswer<Bool>()
        #expect(activity.beginProbe(work.id))

        await start(.quota, account: client, activity: activity) { launched.set(true) }
        activity.endProbe(work.id)

        #expect(launched.answer == true)
    }
}
