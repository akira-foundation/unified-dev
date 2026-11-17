import Testing
import Foundation
@testable import Core

@Suite struct SubagentRetentionTests {
    private static let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func subagent(
        _ id: String,
        state: SubagentState = .running,
        finishedAt: Date? = nil,
        summary: String = ""
    ) -> Subagent {
        Subagent(id: SubagentID(id), description: "Job \(id)", type: "Explore",
                 state: state, summary: summary, outputFile: "/x", finishedAt: finishedAt,
                 startedAt: Self.start)
    }

    private func fanOut(finishedAt: Date) -> SubagentRoster {
        var subagents = (1...7).map {
            subagent("\($0)", state: .completed, finishedAt: finishedAt, summary: "done")
        }
        subagents.append(subagent("8", state: .failed, finishedAt: finishedAt, summary: "529"))
        return SubagentRoster(subagents)
    }

    private func command(
        _ id: String,
        state: SubagentState = .running,
        finishedAt: Date? = nil,
        summary: String = ""
    ) -> Subagent {
        Subagent(id: SubagentID(id), description: "agent-browser open \"/settings\"",
                 taskType: "local_bash", state: state, summary: summary,
                 outputFile: "/x", finishedAt: finishedAt)
    }

    private func ids(_ rows: [SubagentRow]) -> [String] { rows.map(\.id.rawValue) }

    @Test func aWorkingSubagentAlwaysHasARow() {
        let roster = SubagentRoster([subagent("1"), subagent("2")])
        let far = Self.start.addingTimeInterval(3_600)
        #expect(ids(SubagentRetention.rows(roster, now: far)) == ["1", "2"])
    }

    @Test func aTickIsHeldLongEnoughToBeSeen() {
        let roster = SubagentRoster([subagent("1", state: .completed, finishedAt: Self.start)])
        let midHold = Self.start.addingTimeInterval(SubagentRetention.lingerSeconds - 0.5)
        #expect(ids(SubagentRetention.rows(roster, now: midHold)) == ["1"])
    }

    @Test func aTickGoesWhenTheHoldRunsOut() {
        let roster = SubagentRoster([subagent("1", state: .completed, finishedAt: Self.start)])
        let after = Self.start.addingTimeInterval(SubagentRetention.lingerSeconds + 0.1)
        #expect(SubagentRetention.rows(roster, now: after).isEmpty)
    }

    @Test func theHoldIsWellClearOfTheReflowThatEndsIt() {
        #expect(SubagentRetention.lingerSeconds >= ProjectVisibilityMotion.seconds * 10)
    }

    @Test func aStoppedRowLeavesLikeATick() {
        let roster = SubagentRoster([subagent("1", state: .stopped, finishedAt: Self.start)])
        let after = Self.start.addingTimeInterval(SubagentRetention.lingerSeconds + 0.1)
        #expect(SubagentRetention.rows(roster, now: after).isEmpty)
    }

    @Test func aCrossStaysWhenEveryTickHasGone() {
        let roster = fanOut(finishedAt: Self.start)
        let later = Self.start.addingTimeInterval(600)
        #expect(ids(SubagentRetention.rows(roster, now: later)) == ["8"])
    }

    @Test func theScreenshotThatPromptedThisGoesFromEightRowsToOne() {
        let roster = fanOut(finishedAt: Self.start)
        #expect(SubagentRetention.rows(roster, now: Self.start).count == 8)
        let later = Self.start.addingTimeInterval(SubagentRetention.lingerSeconds + 1)
        #expect(SubagentRetention.rows(roster, now: later).count == 1)
    }

    @Test func theNextTurnStillClearsEverything() {
        var roster = fanOut(finishedAt: Self.start)
        roster.turnStarted()
        let later = Self.start.addingTimeInterval(600)
        #expect(SubagentRetention.rows(roster, now: later).isEmpty)
        #expect(SubagentRetention.failureCount(roster) == 0)
    }

    @Test func aFanOutThatHalfFailsDoesNotLeaveSixRowsBehind() {
        let roster = SubagentRoster((1...8).map {
            subagent("\($0)", state: $0 % 2 == 0 ? .failed : .completed, finishedAt: Self.start)
        })
        let later = Self.start.addingTimeInterval(600)
        let rows = SubagentRetention.rows(roster, now: later)
        #expect(rows.count == SubagentRetention.failureLimit)
        #expect(ids(rows) == ["2", "4", "6"])
        #expect(rows.allSatisfy { $0.mark == .failed })
    }

    @Test func theWorkspaceRowCountsEveryFailureIncludingTheCappedOnes() {
        let roster = SubagentRoster((1...8).map {
            subagent("\($0)", state: $0 % 2 == 0 ? .failed : .completed, finishedAt: Self.start)
        })
        #expect(SubagentRetention.failureCount(roster) == 4)
        let later = Self.start.addingTimeInterval(600)
        #expect(SubagentRetention.rows(roster, now: later).count < 4)
    }

    @Test func aTurnWithNoFailuresLeavesNothingOnTheWorkspaceRow() {
        var subagents = (1...7).map {
            subagent("\($0)", state: .completed, finishedAt: Self.start)
        }
        subagents.append(subagent("8"))
        #expect(SubagentRetention.failureCount(SubagentRoster(subagents)) == 0)
    }

    @Test func theRowWhoseOutputIsOpenIsNeverRemoved() {
        let roster = fanOut(finishedAt: Self.start)
        let later = Self.start.addingTimeInterval(600)
        let rows = SubagentRetention.rows(roster, now: later, opened: SubagentID("3"))
        #expect(ids(rows) == ["3", "8"])
    }

    @Test func closingThePaneLetsTheHeldRowGo() {
        let roster = fanOut(finishedAt: Self.start)
        let later = Self.start.addingTimeInterval(600)
        #expect(ids(SubagentRetention.rows(roster, now: later, opened: nil)) == ["8"])
    }

    @Test func openingAFailurePastTheCapKeepsItAndNothingElse() {
        let roster = SubagentRoster((1...6).map {
            subagent("\($0)", state: .failed, finishedAt: Self.start)
        })
        let later = Self.start.addingTimeInterval(600)
        let rows = SubagentRetention.rows(roster, now: later, opened: SubagentID("6"))
        #expect(ids(rows) == ["1", "2", "3", "6"])
    }

    @Test func theNextChangeIsWhenTheOldestHoldRunsOut() throws {
        let roster = SubagentRoster([
            subagent("1", state: .completed, finishedAt: Self.start),
            subagent("2", state: .completed, finishedAt: Self.start.addingTimeInterval(4)),
        ])
        let next = try #require(SubagentRetention.nextChange(roster, now: Self.start))
        #expect(next == Self.start.addingTimeInterval(SubagentRetention.lingerSeconds))
    }

    @Test func nothingIsScheduledWhenNothingIsOnAClock() {
        let failed = SubagentRoster([subagent("1", state: .failed, finishedAt: Self.start)])
        #expect(SubagentRetention.nextChange(failed, now: Self.start) == nil)
        #expect(SubagentRetention.nextChange(SubagentRoster(), now: Self.start) == nil)
    }

    @Test func aWorkingRowIsNotOnAClock() {
        let running = SubagentRoster([subagent("1")])
        #expect(SubagentRetention.nextChange(running, now: Self.start) == nil)
        #expect(SubagentRetention.rows(running, now: Self.start)
            == SubagentRetention.rows(running, now: Self.start.addingTimeInterval(30)))

        let mixed = SubagentRoster([
            subagent("1"),
            subagent("2", state: .completed, finishedAt: Self.start.addingTimeInterval(-2)),
        ])
        #expect(SubagentRetention.nextChange(mixed, now: Self.start)
            == Self.start.addingTimeInterval(SubagentRetention.lingerSeconds - 2))
    }

    @Test func anOpenedRowIsNotOnAClockEither() {
        let roster = SubagentRoster([subagent("1", state: .completed, finishedAt: Self.start)])
        #expect(SubagentRetention.nextChange(roster, now: Self.start, opened: SubagentID("1")) == nil)
    }

    @Test func aSubagentIsTimedFromTheLineThatEndedIt() {
        var roster = SubagentRoster()
        roster.apply(.started(SubagentStart(id: SubagentID("1"), toolUseID: "t")), now: Self.start)
        #expect(roster[SubagentID("1")]?.finishedAt == nil)
        let ending = Self.start.addingTimeInterval(9)
        roster.apply(.reported(SubagentReport(id: SubagentID("1"), status: "completed")), now: ending)
        #expect(roster[SubagentID("1")]?.finishedAt == ending)
    }

    @Test func aSecondEndingLineDoesNotRestartTheHold() {
        var roster = SubagentRoster()
        roster.apply(.started(SubagentStart(id: SubagentID("1"), toolUseID: "t")), now: Self.start)
        let first = Self.start.addingTimeInterval(3)
        roster.apply(.patched(SubagentPatch(id: SubagentID("1"), status: "completed")), now: first)
        roster.apply(
            .reported(SubagentReport(id: SubagentID("1"), status: "completed", summary: "ok")),
            now: first.addingTimeInterval(2)
        )
        #expect(roster[SubagentID("1")]?.finishedAt == first)
    }

    @Test func theAgentExitingTimesWhateverItStopped() {
        var roster = SubagentRoster()
        roster.apply(.started(SubagentStart(id: SubagentID("1"), toolUseID: "t")), now: Self.start)
        let end = Self.start.addingTimeInterval(30)
        roster.agentExited(now: end)
        #expect(roster[SubagentID("1")]?.state == .stopped)
        #expect(roster[SubagentID("1")]?.finishedAt == end)
    }

    @Test func theCapturedFanOutKeepsItsThreeCrosses() throws {
        var roster = SubagentRoster()
        var now = Self.start
        for event in try fixtureLines("claude-api-retry.ndjson")
            .compactMap(AgentEvent.decode(line:)) {
            now = now.addingTimeInterval(0.1)
            switch event {
            case .subagent(let signal): roster.apply(signal, now: now)
            default: break
            }
        }
        #expect(roster.subagents.count == 3)
        #expect(SubagentRetention.failureCount(roster) == 3)
        let later = now.addingTimeInterval(600)
        #expect(SubagentRetention.rows(roster, now: later).count == 3)
    }

    @Test func aBackgroundedShellCommandNeverHasARow() {
        let roster = SubagentRoster([
            command("1"),
            command("2", state: .failed, finishedAt: Self.start, summary: "exit 1"),
            command("3", state: .completed, finishedAt: Self.start, summary: "exit 0"),
        ])
        #expect(SubagentRetention.rows(roster, now: Self.start).isEmpty)
    }

    @Test func evenAnOpenedCommandHasNoRow() {
        let roster = SubagentRoster([command("1", state: .failed, finishedAt: Self.start)])
        #expect(SubagentRetention.rows(roster, now: Self.start, opened: SubagentID("1")).isEmpty)
    }

    @Test func theAgentsBesideItKeepTheirRows() {
        let roster = SubagentRoster([subagent("1"), command("2"), subagent("3")])
        #expect(ids(SubagentRetention.rows(roster, now: Self.start)) == ["1", "3"])
    }

    @Test func aFailedCommandIsNotCountedOnTheWorkspaceRow() {
        let roster = SubagentRoster([
            command("1", state: .failed, finishedAt: Self.start),
            command("2", state: .failed, finishedAt: Self.start),
            subagent("3", state: .failed, finishedAt: Self.start),
        ])
        #expect(SubagentRetention.failureCount(roster) == 1)
    }

    @Test func aCommandPutsNothingOnTheClock() {
        let roster = SubagentRoster([
            command("1", state: .completed, finishedAt: Self.start, summary: "exit 0"),
        ])
        #expect(SubagentRetention.nextChange(roster, now: Self.start) == nil)
    }
}

@Suite struct SubagentRemovalMotionTests {
    @Test func aRowLeavingUsesThePanesOneLength() {
        #expect(ProjectVisibilityMotion.subagentRemoval(reduceMotion: false)
            == .reflow(seconds: ProjectVisibilityMotion.seconds))
    }

    @Test func reduceMotionDropsItRatherThanSlowingIt() {
        #expect(ProjectVisibilityMotion.subagentRemoval(reduceMotion: true) == .instant)
    }
}
