import Testing
import Foundation
@testable import Core

@Suite("Restarting a turn on another account")
struct AgentTurnRestartTests {
    private let defaultClaude = AccountFixture.defaultClaude
    private let work = AccountFixture.work
    private let session = Session(workspaceID: nil, agentSessionID: "agent-session-1")

    private func decide(
        session: Session? = nil,
        archiving: Bool = false,
        resolution: AgentTurnRestart.Resolution? = nil,
        target: AgentAccountHome? = nil,
        running: Bool = false,
        refusal: String? = nil,
        inTerminal: Bool = false
    ) -> Result<AgentTurnRestart, AgentTurnRestart.Refused> {
        AgentTurnRestart.decide(AgentTurnRestart.Input(
            isWorkspaceArchiving: archiving,
            session: session ?? self.session,
            resolution: resolution ?? .resolved(defaultClaude),
            target: target ?? work,
            isTurnInFlight: running,
            switchRefusal: refusal,
            usesInteractiveTerminal: inTerminal
        ))
    }

    private func sentence(_ result: Result<AgentTurnRestart, AgentTurnRestart.Refused>) -> String? {
        guard case .failure(let refused) = result else { return nil }
        return refused.sentence
    }

    private func restart(_ result: Result<AgentTurnRestart, AgentTurnRestart.Refused>) -> AgentTurnRestart? {
        guard case .success(let restart) = result else { return nil }
        return restart
    }

    @Test func aTurnThatEndedIsRestartedWithoutStoppingAnything() {
        let made = restart(decide())
        #expect(made?.steps == [.chooseAccount, .switchAgent])
        #expect(made?.destination.id == work.id)
        #expect(made?.destination.directory == work.directory)
    }

    @Test func aTurnInFlightIsStoppedAndWaitedForBeforeAnythingIsChanged() {
        #expect(restart(decide(running: true))?.steps == [.chooseAccount, .switchAgent])
    }

    @Test func anArchivingWorkspaceRefusesFirstOfAll() {
        let result = decide(archiving: true, resolution: .failed("boom"))
        #expect(sentence(result) == AgentTurnRestart.workspaceArchiving)
        #expect(AgentTurnRestart.workspaceArchiving == "The workspace is being archived.")
    }

    @Test func aFailedResolutionIsSaidWithItsReason() {
        #expect(sentence(decide(resolution: .failed("database is locked")))
            == "Unified Dev could not work out which account this chat runs under: database is locked")
    }

    @Test func anAgentWithNoAccountsIsRefusedByName() {
        #expect(sentence(decide(resolution: .resolved(nil)))
            == "Claude Code runs with this Mac's own login here, so this chat cannot be moved to another account.")
    }

    @Test func aChatThatNamesTheAccountItRunsUnderIsMoved() {
        var named = session
        named.accountID = defaultClaude.id
        #expect(restart(decide(session: named)) != nil)
    }

    @Test func aChatWhoseHistoryBelongsToAnotherAccountIsMovedLikeAnyOther() {
        var elsewhere = session
        elsewhere.accountID = AccountFixture.personal.id
        let made = restart(decide(session: elsewhere))
        #expect(made?.steps == [.chooseAccount, .switchAgent])
        #expect(made?.destination.id == work.id)
    }

    @Test func movingAChatOntoTheAccountThatHoldsItsHistoryIsRecovery() {
        var elsewhere = session
        elsewhere.accountID = AccountFixture.personal.id
        #expect(restart(decide(session: elsewhere, target: AccountFixture.personal))?.destination.id == AccountFixture.personal.id)
    }

    @Test func anAccountOfAnotherAgentIsRefusedBeforeAnythingElseAboutTheTarget() {
        let said = sentence(decide(target: AccountFixture.defaultCodex))
        #expect(said == "Codex accounts cannot run a Claude Code chat.")
    }

    @Test func choosingTheAccountTheChatAlreadyRunsOnSaysSoInsteadOfDoingNothing() {
        #expect(sentence(decide(target: defaultClaude)) == "This chat already runs on that account.")
    }

    @Test func theSameAccountIsRefusedEvenIfTheLabelWasEdited() {
        let renamed = AgentAccountHome(
            provider: .claudeCode, id: defaultClaude.id, directory: defaultClaude.directory, isDefault: true, label: "Edited"
        )
        #expect(sentence(decide(target: renamed)) == "This chat already runs on that account.")
    }

    @Test func aChatWhoseHistoryBelongsElsewhereStillMeetsTheProviderAndSameAccountRefusals() {
        var elsewhere = session
        elsewhere.accountID = AccountFixture.personal.id
        #expect(sentence(decide(session: elsewhere, target: AccountFixture.defaultCodex))
            == "Codex accounts cannot run a Claude Code chat.")
        #expect(sentence(decide(session: elsewhere, target: defaultClaude)) == "This chat already runs on that account.")
    }

    @Test func restartNoLongerResendsThePromptOrDrivesTheTurnItself() {
        for running in [false, true] {
            #expect(restart(decide(running: running))?.steps == [.chooseAccount, .switchAgent])
        }
    }

    @Test func aChatWithNoMessageToResendCanStillBeMovedAndQueuesNoResume() {
        #expect(restart(decide()) != nil)
        let noOwnerTurn = InterruptedTurnResume.Facts(
            cause: .usageLimit, hasOwnerTurn: false, outcome: .init(written: true, queueSettled: true),
            stopsAtStart: 0, stopsNow: 0, queue: []
        )
        #expect(InterruptedTurnResume.decide(noOwnerTurn) == .skip)
    }

    @Test func theRefusalsOfAProviderSwitchApplyToAnAccountSwitchToo() {
        #expect(sentence(decide(refusal: AgentSwitch.rewindHeld)) == AgentSwitch.rewindHeld)
        #expect(sentence(decide(refusal: AgentSwitch.alreadySwitching)) == AgentSwitch.alreadySwitching)
        #expect(sentence(decide(refusal: AgentSwitch.savingTurn)) == AgentSwitch.savingTurn)
    }

    @Test func aChatInATerminalIsRefusedInsteadOfGettingAnInvisibleResume() {
        #expect(sentence(decide(inTerminal: true)) == AgentTurnRestart.runsInTerminal)
        #expect(AgentTurnRestart.runsInTerminal.contains("terminal"))
    }
}
