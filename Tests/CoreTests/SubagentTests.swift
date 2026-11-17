import Testing
import Foundation
@testable import Core

@Suite struct SubagentCaptureTests {
    private func events() throws -> [AgentEvent] {
        try fixtureLines("claude-api-retry.ndjson").compactMap(AgentEvent.decode(line:))
    }

    private func roster() throws -> SubagentRoster {
        var roster = SubagentRoster()
        for event in try events() {
            switch event {
            case .subagent(let signal): roster.apply(signal)
            default: break
            }
        }
        return roster
    }

    @Test func theCaptureSpawnsThreeSubagents() throws {
        let roster = try roster()
        #expect(roster.subagents.count == 3)
        #expect(roster.subagents.allSatisfy { $0.state == .failed })
    }

    @Test func noLineIsRefused() throws {
        #expect(try roster().refusals == 0)
    }

    @Test func aStartCarriesEverythingNeededToDrawARow() throws {
        let roster = try roster()
        let first = try #require(roster.subagents.first)
        #expect(first.id == SubagentID("ae8b434e1a270eeac"))
        #expect(first.toolUseID == "toolu_01Y1GvQ1JsWzGJAeaR8HKdHZ")
        #expect(first.description == "Count lines in a.txt")
        #expect(first.type == "general-purpose")
        #expect(first.spawnDepth == 1)
        #expect(first.isBackgrounded == false)
        #expect(first.prompt.hasPrefix("Read the file a.txt"))
    }

    @Test func aNotificationCarriesTheOutputFile() throws {
        let roster = try roster()
        let first = try #require(roster.subagents.first)
        #expect(first.hasOutput)
        #expect(first.outputFile?.hasSuffix("/tasks/ae8b434e1a270eeac.output") == true)
        #expect(first.summary.contains("529 Overloaded"))
    }

    @Test func progressIsMatchedByTheParentToolUseID() throws {
        let progress = try events().compactMap { event -> SubagentProgress? in
            guard case .subagent(.progressed(let progress)) = event else { return nil }
            return progress
        }
        #expect(progress.count == 33)
        #expect(progress.allSatisfy { $0.type == "general-purpose" })
        let retries = progress.compactMap(\.retry)
        #expect(retries.count == 30)
        #expect(retries.allSatisfy { $0.status == 529 && $0.category == "overloaded" })
        #expect(retries.first?.maxAttempts == 10)
    }

    @Test func aRetryingSubagentIsARowThatSaysWhy() throws {
        var roster = SubagentRoster()
        for event in try events() {
            guard case .subagent(let signal) = event else { continue }
            roster.apply(signal)
            if case .progressed(let progress) = signal, progress.retry != nil { break }
        }

        let row = try #require(SubagentRow.rows(roster).first {
            if case .retrying = $0.detail { true } else { false }
        })
        #expect(row.mark == .working)
        #expect(row.detail.text(at: .now) == "overloaded 1/10")
        #expect(row.spokenValue(at: .now) == "working, being retried, overloaded 1/10")
    }

    @Test func nothingInTheCaptureBecomesATranscriptRow() throws {
        let subagentEvents = try events().filter {
            if case .subagent = $0 { return true }
            return false
        }
        #expect(subagentEvents.count == 42)
        #expect(subagentEvents.allSatisfy { !$0.isTranscriptRow })
        #expect(subagentEvents.allSatisfy { $0.kind == .system })
    }

    @Test func theRowsSayWhatHappened() throws {
        let rows = SubagentRow.rows(try roster())
        #expect(rows.map(\.title) == [
            "Count lines in a.txt", "Count lines in a.txt", "Count lines in a.txt",
        ])
        #expect(rows.allSatisfy { $0.mark == .failed })
        #expect(rows.allSatisfy { $0.opensOutput })
        #expect(rows.allSatisfy { $0.detail.text(at: .now) == "Agent terminated early due..." })
    }
}

@Suite struct SubagentLifecycleTests {
    @Test func aSpawnedSubagentStartsRunning() {
        var roster = SubagentRoster()
        roster.apply(.started(SubagentStart(id: SubagentID("a"), description: "Look")))
        #expect(roster[SubagentID("a")]?.state == .running)
        #expect(roster.isWorking)
    }

    @Test func aSecondStartForTheSameIDIsLegalAndChangesNothing() {
        var roster = SubagentRoster()
        roster.apply(.started(SubagentStart(id: SubagentID("a"), description: "Look")))
        roster.apply(.started(SubagentStart(id: SubagentID("a"), description: "Different")))
        #expect(roster.subagents.count == 1)
        #expect(roster[SubagentID("a")]?.description == "Look")
        #expect(roster.refusals == 0)
    }

    @Test func aFinishedSubagentIsNeverPutBackToWork() {
        var roster = SubagentRoster()
        roster.apply(.started(SubagentStart(id: SubagentID("a"))))
        roster.apply(.reported(SubagentReport(id: SubagentID("a"), status: "completed")))
        roster.apply(.started(SubagentStart(id: SubagentID("a"))))
        roster.apply(.patched(SubagentPatch(id: SubagentID("a"), status: "running")))
        #expect(roster[SubagentID("a")]?.state == .completed)
        #expect(roster.refusals == 2)
    }

    @Test func bothEndingLinesAgreeingIsNotAnError() {
        var roster = SubagentRoster()
        roster.apply(.started(SubagentStart(id: SubagentID("a"))))
        roster.apply(.patched(SubagentPatch(id: SubagentID("a"), status: "failed", error: "boom")))
        roster.apply(.reported(SubagentReport(id: SubagentID("a"), status: "failed")))
        #expect(roster[SubagentID("a")]?.state == .failed)
        #expect(roster.refusals == 0)
    }

    @Test func twoEndingsThatDisagreeKeepTheFirst() {
        var roster = SubagentRoster()
        roster.apply(.started(SubagentStart(id: SubagentID("a"))))
        roster.apply(.patched(SubagentPatch(id: SubagentID("a"), status: "failed")))
        roster.apply(.reported(SubagentReport(id: SubagentID("a"), status: "completed")))
        #expect(roster[SubagentID("a")]?.state == .failed)
        #expect(roster.refusals == 1)
    }

    @Test func aStatusWordNobodyKnowsIsRefusedRatherThanGuessed() {
        #expect(SubagentState(reported: "throttled") == nil)
        #expect(SubagentState.running.transition(on: .reported(status: "throttled")).isRefused)
        #expect(SubagentState(reported: "KILLED") == .stopped)
        #expect(SubagentState(reported: "in_progress") == .running)
    }

    @Test func theAgentExitingStopsWhateverWasStillRunning() {
        var roster = SubagentRoster()
        roster.apply(.started(SubagentStart(id: SubagentID("a"))))
        roster.apply(.started(SubagentStart(id: SubagentID("b"))))
        roster.apply(.reported(SubagentReport(id: SubagentID("b"), status: "completed")))
        roster.agentExited()
        #expect(roster[SubagentID("a")]?.state == .stopped)
        #expect(roster[SubagentID("b")]?.state == .completed)
        #expect(!roster.isWorking)
        #expect(roster.refusals == 0)
    }
}

@Suite struct SubagentClearingTests {
    private var finishedTurn: SubagentRoster {
        var roster = SubagentRoster()
        roster.apply(.started(SubagentStart(id: SubagentID("a"), description: "One")))
        roster.apply(.reported(SubagentReport(id: SubagentID("a"), status: "completed")))
        return roster
    }

    @Test func aFinishedSubagentKeepsItsPlaceUntilTheNextTurn() {
        var roster = finishedTurn
        #expect(roster.subagents.count == 1)
        #expect(SubagentRow.rows(roster).first?.mark == .done)

        roster.turnStarted()
        #expect(roster.isEmpty)
    }

    @Test func clearingForgetsTheToolUseMapToo() {
        var roster = finishedTurn
        roster.turnStarted()
        roster.apply(.progressed(SubagentProgress(parentToolUseID: "", elapsedSeconds: 9)))
        #expect(roster.isEmpty)
    }
}

@Suite struct SubagentsOutlivingTheirTurnTests {
    private func spawned() -> SubagentRoster {
        var roster = SubagentRoster()
        roster.apply(.started(SubagentStart(
            id: SubagentID("live"), toolUseID: "toolu_live", description: "Prototype exploration",
            isBackgrounded: true, taskType: "local_agent"
        )))
        roster.apply(.started(SubagentStart(
            id: SubagentID("done"), toolUseID: "toolu_done", description: "Study conventions",
            taskType: "local_agent"
        )))
        roster.apply(.reported(SubagentReport(
            id: SubagentID("done"), status: "completed", summary: "Read it"
        )))
        return roster
    }

    @Test func aTurnEndingSaysNothingAboutASubagentStillWorking() {
        var roster = spawned()
        roster.turnStarted()
        #expect(roster[SubagentID("live")]?.state == .running)
        #expect(roster.isWorking)
    }

    @Test func theNextTurnKeepsARunningRowAndDropsAFinishedOne() {
        var roster = spawned()
        roster.turnStarted()
        #expect(roster.subagents.map(\.id) == [SubagentID("live")])

        let rows = SubagentRetention.rows(roster, now: Date())
        #expect(rows.map(\.title) == ["Prototype exploration"])
        #expect(rows.first?.mark == .working)
    }

    @Test func theEndingStillLandsAfterTheTurnBoundary() {
        var roster = spawned()
        roster.turnStarted()
        roster.apply(.reported(SubagentReport(
            id: SubagentID("live"), status: "completed", summary: "Explored", outputFile: "/tmp/a"
        )))
        #expect(roster[SubagentID("live")]?.state == .completed)
        #expect(roster[SubagentID("live")]?.outputFile == "/tmp/a")
        #expect(roster.refusals == 0)
    }

    @Test func theToolUseMapSurvivesForTheRowsThatDo() throws {
        var roster = spawned()
        roster.turnStarted()
        roster.apply(.progressed(SubagentProgress(parentToolUseID: "toolu_live", elapsedSeconds: 400)))
        #expect(roster[SubagentID("live")]?.elapsedSeconds == 400)

        roster.apply(.progressed(SubagentProgress(parentToolUseID: "toolu_done", elapsedSeconds: 9)))
        #expect(roster[SubagentID("done")] == nil)
        let finished = try #require(roster.task(SubagentID("done")))
        #expect(finished.elapsedSeconds != 9)
        #expect(roster.subagents.count == 1)
        #expect(roster.history.map(\.id) == [SubagentID("done")])
    }

    @Test func onlyTheAgentGoingAwayStopsOne() {
        var roster = spawned()
        roster.turnStarted()
        roster.agentExited()
        #expect(roster[SubagentID("live")]?.state == .stopped)
        #expect(!roster.isWorking)
    }

    @Test func aBackgroundAgentStillHasARowMinutesIntoALaterTurn() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var roster = SubagentRoster()
        roster.apply(
            .started(SubagentStart(
                id: SubagentID("a"), toolUseID: "t", description: "there-there conventions sweep",
                isBackgrounded: true, taskType: "local_agent"
            )),
            now: start
        )
        roster.turnStarted()
        roster.turnStarted()

        let sixMinutesIn = start.addingTimeInterval(6 * 60)
        let rows = SubagentRetention.rows(roster, now: sixMinutesIn)
        #expect(rows.count == 1)
        #expect(rows.first?.detail.text(at: sixMinutesIn) == "6m 0s")
    }
}

@Suite struct SubagentRowTests {
    private static let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func running(elapsed: Int, retry: AgentRetry? = nil) -> Subagent {
        Subagent(
            id: SubagentID("a"), description: "Find Store.upsert call sites", type: "Explore",
            state: .running, elapsedSeconds: elapsed, retry: retry, startedAt: Self.start
        )
    }

    @Test func aRunningRowCountsSeconds() {
        let now = Self.start
        #expect(SubagentRow(running(elapsed: 11)).detail.text(at: now) == "11s")
        #expect(SubagentRow(running(elapsed: 72)).detail.text(at: now) == "1m 12s")
        #expect(SubagentRow(running(elapsed: 0)).detail.text(at: now) == "")
        #expect(SubagentRow(running(elapsed: 0)).spokenValue(at: now) == "working")
    }

    @Test func aRetryingRowSaysItInTheRetrySurfacesWords() {
        let retry = AgentRetry(attempt: 3, maxAttempts: 10, delay: 1.1, status: 529)
        let row = SubagentRow(running(elapsed: 4, retry: retry))
        #expect(row.detail == .retrying(retry))
        #expect(row.detail.text(at: .now) == "overloaded 3/10")
        #expect(retry.headline == "Anthropic's API is overloaded")
        #expect(row.detail.text(at: .now).count <= SubagentRow.detailLimit)
        #expect(row.spokenValue(at: .now) == "working, being retried, overloaded 3/10")
    }

    @Test func theReadoutMovesWithTheAttempts() {
        let readouts = (1...4).map { attempt in
            SubagentRow(running(
                elapsed: 4,
                retry: AgentRetry(attempt: attempt, maxAttempts: 10, delay: 1, status: 529)
            )).detail.text(at: .now)
        }
        #expect(Set(readouts).count == 4)
    }

    @Test func aFinishedRowCarriesWhatItAnswered() {
        let row = SubagentRow(Subagent(
            id: SubagentID("a"), description: "Count lines", state: .completed, summary: "3 lines"
        ))
        #expect(row.mark == .done)
        #expect(row.detail == .summary("3 lines"))
        #expect(row.spokenValue(at: .now) == "finished, 3 lines")
    }

    @Test func aStoppedRowIsNotACross() {
        let row = SubagentRow(Subagent(id: SubagentID("a"), state: .stopped))
        #expect(row.mark == .stopped)
        #expect(row.spokenValue(at: .now) == "stopped")
    }

    @Test func anAgentOpensWhateverItIsDoingAndACommandNeedsItsFile() {
        #expect(SubagentRow(Subagent(id: SubagentID("a"))).opensOutput)
        #expect(SubagentRow(Subagent(id: SubagentID("a"), state: .failed)).opensOutput)

        let command = Subagent(id: SubagentID("b"), taskType: "local_bash")
        #expect(!SubagentRow(command).opensOutput)
        #expect(SubagentRow(
            Subagent(id: SubagentID("b"), taskType: "local_bash", outputFile: "/tmp/x")
        ).opensOutput)
    }

    @Test func aRunningRowCountsItsOwnSecondsWhenNoTickDoes() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let silent = Subagent(id: SubagentID("a"), startedAt: start)
        let later = start.addingTimeInterval(42)
        #expect(SubagentRow(silent).detail.text(at: later) == "42s")

        let ticked = Subagent(id: SubagentID("a"), elapsedSeconds: 90, startedAt: start)
        let fiveIn = start.addingTimeInterval(5)
        #expect(SubagentRow(ticked).detail.text(at: fiveIn) == "1m 35s")
        #expect(ticked.secondsElapsed(at: fiveIn) == 95)

        let done = Subagent(
            id: SubagentID("a"), state: .completed,
            finishedAt: start.addingTimeInterval(8), startedAt: start
        )
        #expect(done.secondsElapsed(at: start.addingTimeInterval(600)) == 8)
    }

    @Test func aWorkingRowIsTheSameRowAsTheSecondsGoBy() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let working = Subagent(id: SubagentID("a"), description: "Read the store", startedAt: start)
        let first = SubagentRow(working)
        let later = SubagentRow(working)

        #expect(first == later)
        #expect(first.detail.workingSince == start)
        #expect(later.detail.text(at: start.addingTimeInterval(3)) == "3s")
        #expect(later.detail.text(at: start.addingTimeInterval(64)) == "1m 4s")
        #expect(later.spokenValue(at: start.addingTimeInterval(64)) == "working, 1m 4s")
    }

    @Test func aClockAheadOfOursMovesTheRowOnceAndThenHoldsIt() {
        let start = Self.start
        var roster = SubagentRoster()
        roster.apply(.started(SubagentStart(id: SubagentID("a"), toolUseID: "toolu_a")), now: start)
        let before = SubagentRetention.rows(roster, now: start.addingTimeInterval(5))

        roster.apply(.progressed(SubagentProgress(parentToolUseID: "toolu_a", elapsedSeconds: 90)),
                     now: start.addingTimeInterval(5))
        let ticked = SubagentRetention.rows(roster, now: start.addingTimeInterval(5))
        let later = SubagentRetention.rows(roster, now: start.addingTimeInterval(64))

        roster.apply(.progressed(SubagentProgress(parentToolUseID: "toolu_a", elapsedSeconds: 150)),
                     now: start.addingTimeInterval(64.4))
        let again = SubagentRetention.rows(roster, now: start.addingTimeInterval(64.4))

        #expect(before != ticked)
        #expect(ticked == later)
        #expect(ticked == again)
        #expect(later.first?.detail.text(at: start.addingTimeInterval(64)) == "2m 29s")
    }

    @Test func aTickLessThanASecondAheadIsNotAMove() {
        let start = Self.start
        let ahead = { (seconds: Double) -> Date? in
            var roster = SubagentRoster()
            roster.apply(.started(SubagentStart(id: SubagentID("a"), toolUseID: "toolu_a")), now: start)
            roster.apply(.progressed(SubagentProgress(parentToolUseID: "toolu_a", elapsedSeconds: 10)),
                         now: start.addingTimeInterval(10 - seconds))
            return roster[SubagentID("a")]?.workingSince
        }

        #expect(ahead(0.9) == start)
        #expect(ahead(1) == start.addingTimeInterval(-1))
        #expect(ahead(2) == start.addingTimeInterval(-2))
    }

    @Test func aResumedSubagentCountsFromWhenItResumed() {
        let start = Self.start
        var roster = SubagentRoster()
        roster.apply(.started(SubagentStart(id: SubagentID("a"), toolUseID: "toolu_a")), now: start)
        roster.apply(.reported(SubagentReport(id: SubagentID("a"), status: "completed")),
                     now: start.addingTimeInterval(20))
        roster.apply(.started(SubagentStart(id: SubagentID("a"), toolUseID: "toolu_a", resumesExisting: true)),
                     now: start.addingTimeInterval(100))

        let resumed = roster[SubagentID("a")]
        #expect(resumed?.state == .running)
        #expect(resumed?.workingSince == start.addingTimeInterval(100))
        #expect(resumed?.secondsElapsed(at: start.addingTimeInterval(103)) == 3)
    }

    @Test func aClockBehindOursLeavesTheRowAlone() {
        let start = Self.start
        var roster = SubagentRoster()
        roster.apply(.started(SubagentStart(id: SubagentID("a"), toolUseID: "toolu_a")), now: start)
        let before = SubagentRetention.rows(roster, now: start.addingTimeInterval(10))

        roster.apply(.progressed(SubagentProgress(parentToolUseID: "toolu_a", elapsedSeconds: 7)),
                     now: start.addingTimeInterval(10))

        #expect(SubagentRetention.rows(roster, now: start.addingTimeInterval(10)) == before)
        #expect(before.first?.detail.text(at: start.addingTimeInterval(10)) == "10s")
    }

    @Test func aFinishedRowHasNoClock() {
        let row = SubagentRow(Subagent(id: SubagentID("a"), state: .completed, summary: "done"))
        #expect(row.detail.workingSince == nil)
    }

    @Test func aRowWithNoDescriptionFallsBackToItsType() {
        #expect(SubagentRow(Subagent(id: SubagentID("a"), type: "Explore")).title == "Explore")
        #expect(SubagentRow(Subagent(id: SubagentID("a"))).title == "Subagent")
    }

    @Test func aSummaryIsCutOnAWordAndOnlyEverCut() {
        #expect(SubagentRow.shorten("3 lines") == "3 lines")
        #expect(SubagentRow.shorten("first\nsecond") == "first")
        #expect(SubagentRow.shorten(String(repeating: "x", count: 40)).hasSuffix("..."))
        #expect(SubagentRow.shorten("the quick brown fox jumps over it") == "the quick brown fox jumps...")
    }

    @Test func depthGreaterThanOneIsDrawnFlatAndInSpawnOrder() {
        let roster = SubagentRoster([
            Subagent(id: SubagentID("a"), description: "Parent", spawnDepth: 1),
            Subagent(id: SubagentID("b"), description: "Child", spawnDepth: 2),
            Subagent(id: SubagentID("c"), description: "Grandchild", spawnDepth: 3),
        ])
        #expect(SubagentRow.rows(roster).map(\.title) == ["Parent", "Child", "Grandchild"])
    }
}

@Suite struct SubagentTranscriptTests {
    private static let session = SessionID("s1")

    @Test func aFailedSubagentStillLeftAReadableFile() throws {
        let text = try fixtureLines("subagent-output-529.jsonl").joined(separator: "\n")
        let transcript = SubagentTranscript.parse(text, sessionID: Self.session)
        #expect(transcript.prompt.hasPrefix("Read the file a.txt"))
        #expect(transcript.messages.map(\.kind) == [.assistantText])
        let answer = try #require(transcript.messages.last)
        #expect(String(decoding: answer.payload, as: UTF8.self).contains("529 Overloaded"))
    }

    @Test func toolCallsAndResultsAreKept() {
        let text = """
        {"type":"assistant","uuid":"u1","message":{"role":"assistant","content":[\
        {"type":"thinking","thinking":"weighing it"}]}}
        {"type":"assistant","uuid":"u2","message":{"role":"assistant","content":[\
        {"type":"tool_use","id":"toolu_1","name":"Read","input":{"file_path":"/a.txt"}}]}}
        {"type":"user","uuid":"u3","message":{"role":"user","content":[\
        {"type":"tool_result","tool_use_id":"toolu_1","content":[{"type":"text","text":"three lines"}]}]}}
        {"type":"assistant","uuid":"u4","message":{"role":"assistant","content":[{"type":"text","text":"3"}]}}
        """
        let transcript = SubagentTranscript.parse(text, sessionID: Self.session)
        #expect(transcript.messages.map(\.kind) == [.thinking, .toolUse, .toolResult, .assistantText])
        #expect(transcript.messages[1].refID == "toolu_1")
        #expect(transcript.messages[2].refID == "toolu_1")
    }

    @Test func everyRowDecodesToTheEventItsBucketPromises() throws {
        let text = """
        {"type":"assistant","uuid":"u1","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}
        {"type":"assistant","uuid":"u2","message":{"role":"assistant","content":[\
        {"type":"tool_use","id":"toolu_1","name":"Bash","input":{"command":"ls"}}]}}
        {"type":"user","uuid":"u3","message":{"role":"user","content":[\
        {"type":"tool_result","tool_use_id":"toolu_1","content":"a.txt"}]}}
        """
        for message in SubagentTranscript.parse(text, sessionID: Self.session).messages {
            let event = try #require(
                AgentEvent.decode(line: String(decoding: message.payload, as: UTF8.self))
            )
            #expect(event.kind == message.kind)
        }
    }

    @Test func aMessageCarryingSeveralBlocksBecomesSeveralRows() throws {
        let text = """
        {"type":"assistant","uuid":"u1","session_id":"s","message":{"role":"assistant","content":[\
        {"type":"text","text":"Reading it"},\
        {"type":"tool_use","id":"toolu_1","name":"Read","input":{"file_path":"/a.txt"}}]}}
        """
        let transcript = SubagentTranscript.parse(text, sessionID: Self.session)
        #expect(transcript.messages.map(\.kind) == [.assistantText, .toolUse])
        for message in transcript.messages {
            let json = try #require(JSONValue.parse(message.payload))
            #expect(json["uuid"]?.stringValue == "u1")
            #expect(json["session_id"]?.stringValue == "s")
            #expect(json["message"]?["content"]?.arrayValue?.count == 1)
        }
    }

    @Test func aLineThatWillNotParseIsSkippedRatherThanEndingTheRead() {
        let transcript = SubagentTranscript.parse("""
        not json at all
        {"type":"summary","summary":"something new"}
        {"type":"attachment","attachment":{"type":"skill_listing","content":"a page of skills"}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}
        """, sessionID: Self.session)
        #expect(transcript.messages.count == 1)
        #expect(transcript.messages[0].kind == .assistantText)
    }

    @Test func anEmptyFileIsEmptyRatherThanAFailure() {
        #expect(SubagentTranscript.parse("", sessionID: Self.session).isEmpty)
    }

    @Test func aRowThatWasNeverStoredIsNumberedBelowEveryRowThatWas() {
        let line = #"{"type":"assistant","uuid":"u1","message":{"content":[{"type":"text","text":"ok"}]}}"#
        let transcript = SubagentTranscript.parse(line, sessionID: Self.session)
        #expect(transcript.messages.allSatisfy { $0.id < 0 })
    }

    @Test func aRowKeepsItsNumberAcrossAReRead() {
        let payload = Data(#"{"type":"assistant","uuid":"u1"}"#.utf8)
        #expect(SubagentTranscript.rowID(for: payload) == SubagentTranscript.rowID(for: payload))
        #expect(SubagentTranscript.rowID(for: payload) != SubagentTranscript.rowID(for: Data("x".utf8)))
    }

    @Test func twoIdenticalLinesStillGetTwoIdentities() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"same"}]}}"#
        let transcript = SubagentTranscript.parse(
            [line, line].joined(separator: "\n"), sessionID: Self.session
        )
        #expect(transcript.messages.count == 2)
        #expect(transcript.messages[0].id != transcript.messages[1].id)
    }
}

@Suite struct SubagentReorderTests {
    private let project = RepoID("p")

    private var rows: [SidebarReorder.Row] {
        [
            .project(project),
            .workspace(id: WorkspaceID("a"), projectID: project),
            .subagent(projectID: project),
            .subagent(projectID: project),
            .workspace(id: WorkspaceID("b"), projectID: project),
        ]
    }

    @Test func aSubagentRowIsNeverSomethingToPickUp() {
        let moved = SidebarReorder.destination(rows: rows, from: IndexSet(integer: 2), to: 1)
        #expect(moved == .nothing)
    }

    @Test func draggingTheSecondWorkspaceAboveTheFirstCountsWorkspacesAndNotRows() {
        let moved = SidebarReorder.destination(rows: rows, from: IndexSet(integer: 4), to: 1)
        #expect(moved == .workspace(
            projectID: project, from: IndexSet(integer: 1), to: 0, landedOutside: false
        ))
    }

    @Test func aDropBelowTheLastWorkspacesChildrenIsInsideTheProject() {
        let rows: [SidebarReorder.Row] = [
            .project(project),
            .workspace(id: WorkspaceID("a"), projectID: project),
            .workspace(id: WorkspaceID("b"), projectID: project),
            .subagent(projectID: project),
        ]
        let moved = SidebarReorder.destination(rows: rows, from: IndexSet(integer: 1), to: 4)
        #expect(moved == .workspace(
            projectID: project, from: IndexSet(integer: 0), to: 2, landedOutside: false
        ))
    }

    @Test func aPaneWithNoSubagentsBehavesExactlyAsItDid() {
        let rows: [SidebarReorder.Row] = [
            .project(project),
            .workspace(id: WorkspaceID("a"), projectID: project),
            .workspace(id: WorkspaceID("b"), projectID: project),
        ]
        #expect(SidebarReorder.destination(rows: rows, from: IndexSet(integer: 2), to: 1)
            == .workspace(projectID: project, from: IndexSet(integer: 1), to: 0, landedOutside: false))
    }
    @Test func aBackgroundCommandIsNotTheAgentWorking() {
        var roster = SubagentRoster()
        roster.apply(.started(SubagentStart(id: SubagentID("serve"), description: "Serve the app", taskType: "local_bash")))
        #expect(!roster.isWorking)
        #expect(roster.isAnythingRunning)
        #expect(roster.runningCommands.map(\.id) == [SubagentID("serve")])

        roster.apply(.started(SubagentStart(id: SubagentID("audit"), description: "Audit", taskType: "local_agent")))
        #expect(roster.isWorking)
        #expect(roster.runningCommands.map(\.id) == [SubagentID("serve")])
    }

    @Test func anUnknownTaskTypeStillCountsAsWorking() {
        var roster = SubagentRoster()
        roster.apply(.started(SubagentStart(id: SubagentID("new"), taskType: "remote_something")))
        #expect(roster.isWorking)
        #expect(roster.runningCommands.isEmpty)
    }
}
