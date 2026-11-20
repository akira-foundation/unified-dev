import Testing
import Foundation
@testable import Core

@Suite("Where a relaunched agent is pointed")
struct AgentAccountSwitchDestinationTests {
    private let defaultClaude = AccountFixture.defaultClaude
    private let work = AccountFixture.work
    private let session = Session(workspaceID: nil, agentSessionID: "agent-session-1")

    @Test func theRelaunchReadsItsDirectoryFromThePlanAndNotFromTheAccountItWasHanded() {
        let elsewhere = URL(filePath: "/elsewhere/work", directoryHint: .isDirectory)
        let plan = AgentAccountSwitch(
            relaunch: true, directory: elsewhere, losesTurnInFlight: false, refusal: nil
        )
        let destination = plan.destination(of: work)
        #expect(destination?.directory == elsewhere)
        #expect(destination?.id == work.id)
        #expect(destination?.provider == work.provider)
        #expect(destination?.isDefault == work.isDefault)
    }

    @Test func aPlanBuiltFromTheAccountsPointsAtTheTargetAndNotTheSource() {
        let plan = AgentAccountSwitch.plan(session: session, from: defaultClaude, to: work, isTurnInFlight: false)
        #expect(plan.destination(of: work)?.directory == work.directory)
        #expect(plan.destination(of: work)?.directory != defaultClaude.directory)
    }

    @Test func aDefaultAccountFromTheEnvironmentStillReadsItsIdentityInsideItsDirectory() throws {
        let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)
        let alternate = URL(filePath: "/Users/someone/.claude-alt", directoryHint: .isDirectory)
        let inherited = try #require(SpendAccounts.defaultHomes(
            home: home, environment: ["CLAUDE_CONFIG_DIR": alternate.path]
        ).first { $0.provider == .claudeCode })
        let plan = AgentAccountSwitch.plan(session: session, from: work, to: inherited, isTurnInFlight: false)

        let destination = plan.destination(of: inherited)

        #expect(destination?.identityPath == alternate.appending(path: ".claude.json"))
    }

    @Test func aPlanThatDoesNotRelaunchHasNoDestination() {
        let same = AgentAccountSwitch.plan(session: session, from: work, to: work, isTurnInFlight: false)
        let refused = AgentAccountSwitch.plan(
            session: session, from: defaultClaude, to: AccountFixture.defaultCodex, isTurnInFlight: false
        )
        #expect(same.destination(of: work) == nil)
        #expect(refused.destination(of: AccountFixture.defaultCodex) == nil)
    }

    @Test func aRefusalNeverYieldsADestinationEvenIfTheRelaunchFlagWereSet() {
        let plan = AgentAccountSwitch(
            relaunch: true,
            directory: work.directory,
            losesTurnInFlight: false,
            refusal: .otherProvider
        )
        #expect(plan.destination(of: work) == nil)
    }
}
