import Testing
import Foundation
@testable import Core

@Suite("A runner whose segment is no longer the active one", .scratchDirectory)
struct SegmentRetiredRunnerTests: HandoffTurnRunnerFixture {
    private struct Stage {
        let store: Store
        let session: Session
        let retired: SessionSegmentID
    }

    private let claudeInit = #"{"type":"system","subtype":"init","session_id":"late-claude-id"}"#
    private let claudeCostlyResult = #"{"type":"result","subtype":"success","is_error":false,"result":"done","total_cost_usd":9,"usage":{"input_tokens":900,"output_tokens":900}}"#

    private func stage(_ store: Store, agent: AgentKind, model: String) async throws -> Stage {
        let session = try await makeSession(store, agent: agent, model: model)
        let retired = try #require(try await store.activeSegment(sessionID: session.id)).id
        return Stage(store: store, session: session, retired: retired)
    }

    private func switched(_ stage: Stage, to agent: AgentKind) async throws {
        _ = try await stage.store.switchSegment(sessionID: stage.session.id, to: SessionSegmentTarget(
            agentKind: agent, accountID: nil, model: "incoming", effort: ""
        ))
        let active = try #require(try await stage.store.activeSegment(sessionID: stage.session.id)).id
        _ = try await stage.store.update(sessionID: stage.session.id, fromSegment: active) {
            $0.agentSessionID = "incoming-native"
            $0.inputTokens = 5
            $0.outputTokens = 6
            $0.costUSD = 0.25
            $0.contextTokens = 7
        }
    }

    private func expectIncomingUntouched(_ stage: Stage, state: SessionState = .idle) async throws {
        let row = try #require(try await stage.store.session(id: stage.session.id))
        #expect(row.agentSessionID == "incoming-native")
        #expect(row.inputTokens == 5)
        #expect(row.outputTokens == 6)
        #expect(row.costUSD == 0.25)
        #expect(row.contextTokens == 7)
        #expect(row.state == state)
    }

    private func rowCount(_ stage: Stage, _ kind: MessageKind) async throws -> Int {
        try await stage.store.messages(sessionID: stage.session.id).filter { $0.kind == kind }.count
    }

    @Test("Claude: a late init, reply and result write nothing over the new agent")
    func claudeLateEvents() async throws {
        let stage = try await stage(try makeTestStore("retired-claude"), agent: .claudeCode, model: "opus")
        let box = ProcessBox()
        let runner = AgentRunner(
            workspacePath: "/tmp/w", session: stage.session, store: stage.store, segmentID: stage.retired, makeProcess: box.factory
        )
        try await runner.send("before the switch")
        try await switched(stage, to: .codex)
        let before = try await cursor(stage.store, stage.session)

        await runner.ingest(try #require(AgentEvent.decode(line: claudeInit)))
        await runner.ingest(claudeReply("late words"))
        await runner.ingest(try #require(AgentEvent.decode(line: claudeCostlyResult)))

        try await expectIncomingUntouched(stage)
        #expect(try await cursor(stage.store, stage.session) == before)
        runner.terminateNow()
    }

    @Test("Codex: a late end of a failed turn writes nothing over the new agent")
    func codexLateResult() async throws {
        let stage = try await stage(try makeTestStore("retired-codex"), agent: .codex, model: "gpt-5")
        let box = codexBox()
        let runner = CodexRunner(
            workspacePath: "/tmp/w", session: stage.session, store: stage.store, segmentID: stage.retired,
            makeClient: { CodexClient(configuration: $0, makeProcess: box.factory) }
        )
        try await runner.send("before the switch")
        try await switched(stage, to: .claudeCode)
        let before = try await cursor(stage.store, stage.session)

        emitCodexReply(box)
        box.process.emit(#"{"method":"turn/completed","params":{"threadId":"\#(handoffThreadID)","turn":{"id":"\#(handoffTurnID)","status":"failed","items":[]}}}"#)
        let turnID = UUID().uuidString
        box.process.emit(#"{"method":"item/completed","params":{"threadId":"\#(handoffThreadID)","turnId":"\#(turnID)","item":{"id":"sentinel","type":"agentMessage","text":"after the end"}}}"#)
        await waitUntil("the event after the end of the turn to be stored", within: .seconds(5)) {
            ((try? await rowCount(stage, .assistantText)) ?? 0) >= 2
        }

        try await expectIncomingUntouched(stage)
        #expect(try await cursor(stage.store, stage.session) == before)
        await runner.shutdown()
    }

    @Test("Grok: a late end of a turn writes nothing over the new agent")
    func grokLateResult() async throws {
        let stage = try await stage(try makeTestStore("retired-grok"), agent: .grok, model: "grok-4.6")
        let box = grokBox()
        let runner = ACPRunner(
            dialect: .grok,
            workspacePath: "/tmp/w", session: stage.session, store: stage.store, segmentID: stage.retired,
            makeClient: { ACPClient(configuration: $0, makeProcess: box.factory) }
        )
        defer { runner.terminateNow() }
        try await runner.send("before the switch")
        try await switched(stage, to: .claudeCode)
        let before = try await cursor(stage.store, stage.session)
        let frame = try #require(box.process.sentFrame { $0["method"]?.stringValue == "session/prompt" })
        let id = try #require(frame["id"])

        box.process.emit(#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"sess-1","update":{"sessionUpdate":"tool_call","toolCallId":"t1","title":"ls","kind":"execute","status":"in_progress"}}}"#)
        box.process.emit("{\"id\":\(id.compactJSON),\"result\":{\"stopReason\":\"end_turn\",\"_meta\":{\"usage\":{\"inputTokens\":900,\"outputTokens\":900}}}}")
        box.process.emit(#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"sess-1","update":{"sessionUpdate":"tool_call","toolCallId":"sentinel","title":"ls","kind":"execute","status":"in_progress"}}}"#)
        await waitUntil("the event after the end of the turn to be stored", within: .seconds(5)) {
            let rows = (try? await stage.store.messages(sessionID: stage.session.id)) ?? []
            return rows.contains { $0.kind == .result } && rows.last?.kind == .toolUse
        }

        try await expectIncomingUntouched(stage)
        #expect(try await cursor(stage.store, stage.session) == before)
    }

    @Test("a runner built on a segment that has gone refuses to send, starts nothing and stops")
    func claudeBuiltTooLate() async throws {
        let stage = try await stage(try makeTestStore("late-claude"), agent: .claudeCode, model: "opus")
        try await switched(stage, to: .codex)
        let delivery = try await claimed(stage.store, stage.session, "PROMPT")
        let box = ProcessBox()
        let runner = AgentRunner(
            workspacePath: "/tmp/w", session: stage.session, store: stage.store, segmentID: stage.retired, makeProcess: box.factory
        )

        await #expect(throws: ProviderIdleError.self) { try await runner.sendDelivery(delivery) }

        #expect(box.processes.isEmpty)
        #expect(try await stage.store.delivery(id: delivery.id)?.state == .claimed)
        try await expectIncomingUntouched(stage)
    }

    @Test("a live runner whose segment has gone stops its process when it is next asked to send")
    func claudeLiveRunnerStops() async throws {
        let stage = try await stage(try makeTestStore("stop-claude"), agent: .claudeCode, model: "opus")
        let box = ProcessBox()
        let runner = AgentRunner(
            workspacePath: "/tmp/w", session: stage.session, store: stage.store,
            segmentID: stage.retired, makeProcess: box.factory
        )
        try await runner.send("before the switch")
        try await switched(stage, to: .codex)
        #expect(box.process.isRunning)

        await #expect(throws: ProviderIdleError.self) { try await runner.send("too late") }

        #expect(!box.process.isRunning)
    }

    @Test("Codex built on a segment that has gone refuses to send and opens nothing")
    func codexBuiltTooLate() async throws {
        let stage = try await stage(try makeTestStore("late-codex"), agent: .codex, model: "gpt-5")
        try await switched(stage, to: .claudeCode)
        let box = codexBox()
        let runner = CodexRunner(
            workspacePath: "/tmp/w", session: stage.session, store: stage.store, segmentID: stage.retired,
            makeClient: { CodexClient(configuration: $0, makeProcess: box.factory) }
        )

        await #expect(throws: ProviderIdleError.self) { try await runner.send("too late") }

        #expect(box.processes.isEmpty)
        try await expectIncomingUntouched(stage)
    }

    @Test("Grok built on a segment that has gone refuses to send and opens nothing")
    func grokBuiltTooLate() async throws {
        let stage = try await stage(try makeTestStore("late-grok"), agent: .grok, model: "grok-4.6")
        try await switched(stage, to: .claudeCode)
        let box = grokBox()
        let runner = ACPRunner(
            dialect: .grok,
            workspacePath: "/tmp/w", session: stage.session, store: stage.store, segmentID: stage.retired,
            makeClient: { ACPClient(configuration: $0, makeProcess: box.factory) }
        )

        await #expect(throws: ProviderIdleError.self) { try await runner.send("too late") }

        #expect(box.processes.isEmpty)
        try await expectIncomingUntouched(stage)
    }
}
