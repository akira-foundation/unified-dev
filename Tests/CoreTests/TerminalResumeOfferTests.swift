import Testing
import Foundation
@testable import Core

@Suite("What a reopened agent pane does with its remembered resume")
struct TerminalResumeOfferTests {
    private let refused = AgentAccountLaunch.refused(AgentAccountRefusal(provider: .claudeCode, isChoiceLost: false))
    private let runs = AgentAccountLaunch.runs(nil)

    @Test("a refused agent with nothing running in the pane forgets its resume")
    func aRefusedIdlePaneForgets() {
        #expect(TerminalResumeOffer.decide(launch: refused, isRunning: false) == .forget)
    }

    @Test("a refused agent whose pane may still run it withdraws the offer and forgets nothing", arguments: [true, nil] as [Bool?])
    func aRefusedPaneThatMayRunWithdraws(isRunning: Bool?) {
        #expect(TerminalResumeOffer.decide(launch: refused, isRunning: isRunning) == .withdraw)
    }

    @Test("an agent that runs is offered its resume when nothing runs in the pane, or when that cannot be read", arguments: [false, nil] as [Bool?])
    func aRunningLaunchOffers(isRunning: Bool?) {
        #expect(TerminalResumeOffer.decide(launch: runs, isRunning: isRunning) == .offer)
    }

    @Test("an agent that runs and is still running in the pane is remembered without an offer")
    func aRunningLaunchStillRunningRemembers() {
        #expect(TerminalResumeOffer.decide(launch: runs, isRunning: true) == .remember)
    }

    @Test("a pane with no agent chat follows only what runs in it", arguments: [(false, TerminalResumeOffer.offer), (true, .remember)])
    func aPaneWithNoAgentFollowsItsProcess(isRunning: Bool, expected: TerminalResumeOffer) {
        #expect(TerminalResumeOffer.decide(launch: nil, isRunning: isRunning) == expected)
    }
}
