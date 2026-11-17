import Testing
import Foundation
import Synchronization
@testable import Core

@Suite("Switching a chat's agent", .scratchDirectory)
struct AgentSwitchTests: HandoffTurnRunnerFixture {
    private let toCodex = ComposerControls(model: "gpt-5", effort: "high", agentKind: .codex)
    private let claudeAsk = #"{"type":"control_request","request_id":"ask-1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"ls"},"tool_use_id":"tool-1"}}"#

    private func tailReply(_ text: String) -> String {
        #"{"type":"assistant","message":{"model":"opus","role":"assistant","content":[{"type":"text","text":"\#(text)"}]}}"#
    }

    private func lingeringClaude(_ store: Store) async throws -> (Session, ProcessBox, AgentRunner) {
        let session = try await makeSession(store, agent: .claudeCode, model: "opus")
        let box = ProcessBox()
        let runner = try await claudeRunner(store, session, box)
        try await runner.send("before the switch")
        box.process.lingerOnTerminate()
        return (session, box, runner)
    }

    @Test("a switch retires the runner before it returns")
    func aSwitchRetiresTheRunnerAtOnce() async throws {
        let store = try makeTestStore("switch-retires")
        let (session, box, runner) = try await lingeringClaude(store)
        let before = try #require(try await store.activeSegment(sessionID: session.id)).id
        #expect(box.process.terminationCount == 0)

        let switched = try await AgentSwitch.retireAndSwitch(
            runner: runner, store: store, sessionID: session.id, controls: toCodex, account: nil, standings: []
        )

        #expect(box.process.terminationCount > 0)
        #expect(switched.agentKind == .codex)
        #expect(switched.model == "gpt-5")
        #expect(switched.effort == "high")
        #expect(try await store.activeSegment(sessionID: session.id)?.id != before)
        box.process.endOutput()
    }

    @Test("a switch with no runner still moves the chat")
    func aSwitchWithNoRunnerStillMoves() async throws {
        let store = try makeTestStore("switch-no-runner")
        let session = try await makeSession(store, agent: .claudeCode, model: "opus")

        let switched = try await AgentSwitch.retireAndSwitch(
            runner: nil, store: store, sessionID: session.id, controls: toCodex, account: nil, standings: []
        )

        #expect(switched.agentKind == .codex)
    }

    @Test("a switch to a default account nobody chose yet records that account")
    func aSwitchRecordsAnUnchosenDefaultAccount() async throws {
        let store = try makeTestStore("switch-unchosen-default")
        let session = try await makeSession(store, agent: .claudeCode, model: "opus")
        let codexHome = AgentAccountHome(
            provider: .codex, id: AgentAccountHome.defaultID(for: .codex),
            directory: URL(filePath: "/tmp/codex-home", directoryHint: .isDirectory), isDefault: true
        )

        let switched = try await AgentSwitch.retireAndSwitch(
            runner: nil, store: store, sessionID: session.id, controls: toCodex, account: codexHome, standings: []
        )

        #expect(switched.accountID == codexHome.id)
        #expect(try await store.activeSegment(sessionID: session.id)?.accountID == codexHome.id)
        #expect(try await store.agentAccounts().contains { $0.id == codexHome.id })
    }

    @Test("a switch carries the picker's permission and work mode")
    func aSwitchCarriesThePickersModes() async throws {
        let store = try makeTestStore("switch-modes")
        let session = try await makeSession(store, agent: .claudeCode, model: "opus")
        var controls = toCodex
        controls.permissionMode = .bypassPermissions
        controls.interactionMode = .plan

        let switched = try await AgentSwitch.retireAndSwitch(
            runner: nil, store: store, sessionID: session.id, controls: controls, account: nil, standings: []
        )

        #expect(switched.permissionMode == controls.permissionMode)
        #expect(switched.interactionMode == controls.interactionMode)
    }

    @Test("the dying runner's tail reaches the delta")
    func theDyingRunnersTailReachesTheDelta() async throws {
        let store = try makeTestStore("switch-tail")
        let (session, box, runner) = try await lingeringClaude(store)
        let process = box.process
        let tail = tailReply("words from the dying process")

        _ = try await AgentSwitch.retireAndSwitch(
            runner: runner, store: store, sessionID: session.id, controls: toCodex, account: nil, standings: []
        )
        let exited = await AgentSwitch.waitForExit(of: runner, budget: .seconds(60)) {
            process.emit(tail)
            process.endOutput()
            await Task.yield()
        }

        #expect(exited)
        let turn = try await store.handoffTurn(
            "next", sessionID: session.id, deliveredSeq: nil, worktree: nil, contextWindow: nil
        )
        #expect(turn.contains("words from the dying process"))
        #expect(try await store.session(id: session.id)?.state.isMidTurn == false)
    }

    @Test("the whole switch: a dying Claude's tail reaches a new Codex runner's first prompt, ahead of the owner's words")
    func theWholeSwitchReachesTheNextAgent() async throws {
        let store = try makeTestStore("switch-chain")
        let (session, box, runner) = try await lingeringClaude(store)
        let process = box.process

        let switched = try await AgentSwitch.retireAndSwitch(
            runner: runner, store: store, sessionID: session.id, controls: toCodex, account: nil, standings: []
        )
        let exited = await AgentSwitch.waitForExit(of: runner, budget: .seconds(60)) {
            process.emit(tailReply("words from the dying process"))
            process.endOutput()
            await Task.yield()
        }
        #expect(exited)
        #expect(switched.agentSessionID == nil)

        let delivery = try await claimed(store, switched, "WORDS FOR CODEX")
        let next = codexBox()
        let codex = try await codexRunner(store, switched, next)
        try await codex.sendDelivery(delivery)

        let sent = try #require(codexText("turn/start", next))
        #expect(sent.contains("before the switch"))
        #expect(sent.contains("words from the dying process"))
        #expect(sent.hasSuffix("\n\nWORDS FOR CODEX"))
        #expect(sent.contains(BridgeUntrustedText.opening))
        await codex.shutdown()
    }

    @Test("a cancelled runner has not stopped writing until its output ends")
    func aCancelledRunnerWritesUntilItsOutputEnds() async throws {
        let store = try makeTestStore("switch-eof")
        let (session, box, runner) = try await lingeringClaude(store)

        _ = try await AgentSwitch.retireAndSwitch(
            runner: runner, store: store, sessionID: session.id, controls: toCodex, account: nil, standings: []
        )
        await waitUntil("the runner to call itself cancelled", within: .seconds(60)) {
            await !runner.isProcessAlive
        }

        #expect(await !runner.hasStoppedWriting)
        box.process.endOutput()
        await waitUntil("the output to end", within: .seconds(60)) { await runner.hasStoppedWriting }
    }

    @Test("a process that outlives the budget does not hold the chat")
    func aProcessThatOutlivesTheBudgetIsLeftBehind() async throws {
        let store = try makeTestStore("switch-budget")
        let (session, box, runner) = try await lingeringClaude(store)
        _ = try await AgentSwitch.retireAndSwitch(
            runner: runner, store: store, sessionID: session.id, controls: toCodex, account: nil, standings: []
        )

        let exited = await AgentSwitch.waitForExit(of: runner, budget: .zero) {}

        #expect(!exited)
        box.process.endOutput()
    }

    @Test("a retired Codex runner reports it has stopped writing")
    func aRetiredCodexRunnerStops() async throws {
        let store = try makeTestStore("switch-codex")
        let session = try await makeSession(store, agent: .codex, model: "gpt-5")
        let box = codexBox()
        let runner = try await codexRunner(store, session, box)
        try await runner.send("before the switch")
        #expect(await runner.hasStoppedWriting == false)

        _ = try await AgentSwitch.retireAndSwitch(
            runner: runner, store: store, sessionID: session.id,
            controls: ComposerControls(model: "opus", agentKind: .claudeCode), account: nil, standings: []
        )
        let exited = await AgentSwitch.waitForExit(of: runner, budget: .seconds(60)) { await Task.yield() }

        #expect(exited)
    }

    @Test("a runner that never started has nothing to wait for")
    func aRunnerThatNeverStartedHasNothingToWaitFor() async throws {
        let store = try makeTestStore("switch-never-started")
        let session = try await makeSession(store, agent: .claudeCode, model: "opus")
        let runner = try await claudeRunner(store, session, ProcessBox())

        #expect(await runner.hasStoppedWriting)
    }

    @Test("a retired runner closes the question it was holding")
    func aRetiredRunnerClosesItsOwnQuestion() async throws {
        let store = try makeTestStore("switch-ask")
        let (session, box, runner) = try await lingeringClaude(store)
        box.process.emit(claudeAsk)
        await waitUntil("the question to be stored", within: .seconds(60)) {
            ((try? await store.pendingPermissionAsks(sessionID: session.id)) ?? []).count == 1
        }

        _ = try await AgentSwitch.retireAndSwitch(
            runner: runner, store: store, sessionID: session.id, controls: toCodex, account: nil, standings: []
        )
        box.process.endOutput()

        await waitUntil("the question to be closed", within: .seconds(60)) {
            ((try? await store.pendingPermissionAsks(sessionID: session.id)) ?? []).isEmpty
        }
        #expect(try await store.pendingPermissionAsks(sessionID: session.id).isEmpty)
    }

    @Test("a question no runner holds is closed as stopped")
    func aQuestionNoRunnerHoldsIsClosedAsStopped() async throws {
        let store = try makeTestStore("switch-stale-ask")
        let session = try await makeSession(store, agent: .claudeCode, model: "opus")
        let ask = try #require(AgentEvent.decode(line: claudeAsk).flatMap { event -> PermissionAsk? in
            if case .permissionAsk(let ask) = event { return ask }
            return nil
        })
        try await store.appendPermissionAsk(sessionID: session.id, ask: ask)

        await AgentSwitch.denyAsks([ask.requestID], in: store)

        #expect(try await store.pendingPermissionAsks(sessionID: session.id).isEmpty)
    }

    @Test("a send already past its first check does not reach a process once the chat has moved")
    func aSendPastItsFirstCheckStopsBeforeWriting() async throws {
        let path = TestScratch.unique("switch-send-race") + ".sqlite"
        let store = try Store(path: path)
        let session = try await makeSession(store, agent: .claudeCode, model: "opus")
        let box = ProcessBox()
        let factory = box.factory
        let chat = session.id.rawValue
        let runner = try await AgentRunner(
            workspacePath: "/tmp/w", session: session, store: store,
            segmentID: activeSegmentID(store, session),
            makeProcess: { launch in
                let raw = try? SQLiteDatabase(path: path)
                try? raw?.execute("""
                    UPDATE session_segments SET is_active = 0 WHERE session_id = '\(chat)';
                    INSERT INTO session_segments (id, session_id, agent_kind, model, is_active, created_at)
                    VALUES ('moved', '\(chat)', 'codex', 'gpt-5', 1, 0);
                    """)
                return factory(launch)
            }
        )

        await #expect(throws: ProviderIdleError.retired) { try await runner.send("too late") }

        #expect(box.process.stdin.isEmpty)
        #expect(box.process.terminationCount > 0)
    }

    @Test("the second signal still goes when the modes cannot be written")
    func theSecondSignalSurvivesAFailedPreferenceWrite() async throws {
        let path = TestScratch.unique("switch-second-signal") + ".sqlite"
        let store = try Store(path: path)
        let session = try await makeSession(store, agent: .claudeCode, model: "opus")
        let raw = try SQLiteDatabase(path: path)
        try raw.execute("""
            CREATE TRIGGER refuse_modes BEFORE UPDATE OF permission_mode ON sessions
            BEGIN SELECT RAISE(ABORT, 'refused'); END;
            """)
        let runner = SignalCountingRunner()

        await #expect(throws: (any Error).self) {
            try await AgentSwitch.retireAndSwitch(
                runner: runner, store: store, sessionID: session.id, controls: toCodex, account: nil, standings: []
            )
        }

        #expect(runner.signals == 2)
    }

    @Test("a queue that could not be settled says the chat moved and the messages are waiting")
    func aQueueFailureSaysWhatHappened() {
        let sentence = AgentSwitch.queueFailure(to: .codex, detail: "The disk is full.")
        #expect(sentence.contains("Codex"))
        #expect(sentence.contains("queued"))
        #expect(sentence.contains("The disk is full."))
    }

    @Test("a Grok runner mid-close has not stopped writing, even if a second close has finished")
    func aGrokRunnerMidCloseHasNotStopped() async throws {
        let store = try makeTestStore("switch-grok-close")
        let session = try await makeSession(store, agent: .grok, model: "grok-4")
        let box = grokBox()
        box.ignore("session/close")
        let runner = try await grokRunner(store, session, box)
        try await runner.send("before the switch")
        let process = box.process

        let first = Task { await runner.shutdown() }
        await waitUntil("the close to be on its way", within: .seconds(60)) {
            process.sentMethods.contains("session/close")
        }
        await runner.shutdown()

        #expect(await !runner.hasStoppedWriting)
        process.endOutput()
        await first.value
        #expect(await runner.hasStoppedWriting)
    }

    @Test("a retired Codex runner writes nothing after it says it has stopped")
    func aRetiredCodexRunnerIsDoneWhenItSaysSo() async throws {
        let store = try makeTestStore("switch-codex-tail")
        let session = try await makeSession(store, agent: .codex, model: "gpt-5")
        let box = codexBox()
        let runner = try await codexRunner(store, session, box)
        try await runner.send("before the switch")
        let process = box.process
        for index in 0..<300 {
            process.emit(#"{"method":"item/completed","params":{"threadId":"\#(handoffThreadID)","turnId":"\#(handoffTurnID)","item":{"id":"tail-\#(index)","type":"agentMessage","text":"tail \#(index)"}}}"#)
        }
        await waitUntil("the tail to start landing", within: .seconds(60)) {
            ((try? await store.messages(sessionID: session.id)) ?? []).contains { $0.kind == .assistantText }
        }

        _ = try await AgentSwitch.retireAndSwitch(
            runner: runner, store: store, sessionID: session.id,
            controls: ComposerControls(model: "opus", agentKind: .claudeCode), account: nil, standings: []
        )
        let exited = await AgentSwitch.waitForExit(of: runner, budget: .seconds(60)) { await Task.yield() }
        let atExit = try await store.messages(sessionID: session.id).count
        for _ in 0..<2_000 { await Task.yield() }

        #expect(exited)
        #expect(try await store.messages(sessionID: session.id).count == atExit)
    }

    @Test("a running turn is stopped, its questions denied, and it is closed before the queue moves")
    func aDirectSwitchLeavesNothingWorking() {
        let steps = AgentSwitch.steps(for: AgentSwitch.Turn(isRunning: true, hasActiveTurn: true, hasOpenAsks: true))

        #expect(steps == [
            .stopTurn, .denyOpenAsks, .retireRunnerAndSwitch, .endSubagents, .waitForRetiredRunner, .closeTurn, .drainQueue,
        ])
    }

    @Test("a turn the app still thinks is open is closed even with nothing running")
    func anOpenTurnWithNothingRunningIsClosed() {
        let steps = AgentSwitch.steps(for: AgentSwitch.Turn(isRunning: false, hasActiveTurn: true, hasOpenAsks: false))

        #expect(steps == [.stopTurn, .retireRunnerAndSwitch, .endSubagents, .waitForRetiredRunner, .closeTurn, .drainQueue])
    }

    @Test("a stale question on an idle chat is still denied")
    func aStaleQuestionOnAnIdleChatIsDenied() {
        let steps = AgentSwitch.steps(for: AgentSwitch.Turn(isRunning: false, hasActiveTurn: false, hasOpenAsks: true))

        #expect(steps == [.denyOpenAsks, .retireRunnerAndSwitch, .endSubagents, .waitForRetiredRunner, .drainQueue])
    }

    @Test("an idle chat has no turn to stop or close, and its background subagents still end")
    func anIdleChatOnlySwitches() {
        let steps = AgentSwitch.steps(for: AgentSwitch.Turn(isRunning: false, hasActiveTurn: false, hasOpenAsks: false))

        #expect(steps == [.retireRunnerAndSwitch, .endSubagents, .waitForRetiredRunner, .drainQueue])
    }

    private func facts(
        archiving: Bool = false, held: Bool = false, saving: Bool = false, catchingUp: Bool = false, switching: Bool = false
    ) -> AgentSwitch.Facts {
        AgentSwitch.Facts(
            isArchiving: archiving, isRewindHeld: held, isSavingTurn: saving,
            isCatchingUp: catchingUp, isAlreadySwitching: switching
        )
    }

    @Test("a failed switch says where it was going and why")
    func aFailedSwitchSaysWhy() {
        let sentence = AgentSwitch.failure(to: .codex, detail: "The disk is full.")
        #expect(sentence == "Could not move this chat to Codex. The disk is full.")
    }

    @Test("a retired Grok runner reports it has stopped writing")
    func aRetiredGrokRunnerStops() async throws {
        let store = try makeTestStore("switch-grok")
        let session = try await makeSession(store, agent: .grok, model: "grok-4")
        let box = grokBox()
        let runner = try await grokRunner(store, session, box)
        try await runner.send("before the switch")
        #expect(await runner.hasStoppedWriting == false)

        _ = try await AgentSwitch.retireAndSwitch(
            runner: runner, store: store, sessionID: session.id, controls: toCodex, account: nil, standings: []
        )
        let exited = await AgentSwitch.waitForExit(of: runner, budget: .seconds(60)) { await Task.yield() }

        #expect(exited)
    }

    @Test("a chat with nothing in the way can switch")
    func aChatWithNothingInTheWayCanSwitch() {
        #expect(AgentSwitch.refusal(facts()) == nil)
    }

    @Test("each thing in the way refuses in its own words", arguments: [
        (AgentSwitch.Facts(isArchiving: true, isRewindHeld: false, isSavingTurn: false, isCatchingUp: false, isAlreadySwitching: false), AgentTurnRestart.workspaceArchiving),
        (AgentSwitch.Facts(isArchiving: false, isRewindHeld: true, isSavingTurn: false, isCatchingUp: false, isAlreadySwitching: false), AgentSwitch.rewindHeld),
        (AgentSwitch.Facts(isArchiving: false, isRewindHeld: false, isSavingTurn: true, isCatchingUp: false, isAlreadySwitching: false), AgentSwitch.savingTurn),
        (AgentSwitch.Facts(isArchiving: false, isRewindHeld: false, isSavingTurn: false, isCatchingUp: true, isAlreadySwitching: false), AgentSwitch.catchingUp),
        (AgentSwitch.Facts(isArchiving: false, isRewindHeld: false, isSavingTurn: false, isCatchingUp: false, isAlreadySwitching: true), AgentSwitch.alreadySwitching),
    ])
    func eachObstacleRefuses(facts: AgentSwitch.Facts, sentence: String) {
        #expect(AgentSwitch.refusal(facts) == sentence)
    }
}

private actor SignalCountingRunner: SessionRunner {
    private let count = Mutex(0)

    nonisolated var signals: Int { count.withLock { $0 } }
    nonisolated var agentKind: AgentKind { .claudeCode }
    nonisolated var events: AsyncStream<AgentEvent> { AsyncStream { $0.finish() } }
    var isProcessAlive: Bool { false }
    var hasStoppedWriting: Bool { true }

    func send(_ text: String, recording: Data?) async throws {}
    nonisolated func cancelNow() {}
    nonisolated func terminateNow() { count.withLock { $0 += 1 } }
    func answer(requestID: String, decision: PermissionDecision) async {}
}
