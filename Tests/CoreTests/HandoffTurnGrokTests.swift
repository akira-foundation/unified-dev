import Testing
import Foundation
@testable import Core

@Suite("Handoff turn on Grok", .scratchDirectory)
struct HandoffTurnGrokTests: HandoffTurnRunnerFixture {
    @Test("Grok is spoken to with the delta and stores the owner's words")
    func grokSpeaksTheDelta() async throws {
        let store = try makeTestStore("handoff-grok")
        let session = try await enteredFromAnotherAgent(store, agent: .grok, model: "grok-4.6")
        let delivery = try await claimed(store, session, "PROMPT")
        let box = grokBox()
        let runner = try await grokRunner(store, session, box)
        defer { runner.terminateNow() }

        try await runner.sendDelivery(delivery)

        let frame = try #require(box.process.sentFrame { $0["method"]?.stringValue == "session/prompt" })
        let spoken = try #require(frame["params"]?["prompt"]?[0]?["text"]?.stringValue)
        #expect(spoken.contains("earlier words"))
        #expect(spoken.hasSuffix("\n\nPROMPT"))
        #expect(try await storedUserTexts(store, session) == ["earlier words", "PROMPT"])
    }

    @Test("Grok carries the cursor past the end of a turn that replied, and not of one that did not")
    func grokConfirmsOnTheEndOfTheTurn() async throws {
        let store = try makeTestStore("handoff-grok-end")
        let session = try await enteredFromAnotherAgent(store, agent: .grok, model: "grok-4.6")
        let delivery = try await claimed(store, session, "PROMPT")
        let box = grokBox()
        let runner = try await grokRunner(store, session, box)
        defer { runner.terminateNow() }
        try await runner.sendDelivery(delivery)
        let before = try #require(try await store.activeSegment(sessionID: session.id)).cursorSeq
        let frame = try #require(box.process.sentFrame { $0["method"]?.stringValue == "session/prompt" })
        let id = try #require(frame["id"])

        box.process.emit(#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"sess-1","update":{"sessionUpdate":"tool_call","toolCallId":"t1","title":"ls","kind":"execute","status":"in_progress"}}}"#)
        box.process.emit("{\"id\":\(id.compactJSON),\"result\":{\"stopReason\":\"end_turn\"}}")

        await waitUntil("the end of the turn to confirm", within: .seconds(60)) {
            let rows = (try? await store.messages(sessionID: session.id)) ?? []
            let cursor = (try? await store.activeSegment(sessionID: session.id))??.cursorSeq
            return rows.last?.kind == .result && cursor == rows.last?.seq
        }
        #expect(try await store.activeSegment(sessionID: session.id)?.cursorSeq != before)
    }

    @Test("a Grok turn that ends with no reply leaves the cursor")
    func grokEndWithNoReplyConfirmsNothing() async throws {
        let store = try makeTestStore("handoff-grok-silent")
        let session = try await enteredFromAnotherAgent(store, agent: .grok, model: "grok-4.6")
        let delivery = try await claimed(store, session, "PROMPT")
        let box = grokBox()
        let runner = try await grokRunner(store, session, box)
        defer { runner.terminateNow() }
        try await runner.sendDelivery(delivery)
        let before = try #require(try await store.activeSegment(sessionID: session.id)).cursorSeq
        let frame = try #require(box.process.sentFrame { $0["method"]?.stringValue == "session/prompt" })
        let id = try #require(frame["id"])

        box.process.emit("{\"id\":\(id.compactJSON),\"result\":{\"stopReason\":\"end_turn\"}}")

        await waitUntil("the turn to end", within: .seconds(60)) {
            ((try? await store.messages(sessionID: session.id)) ?? []).last?.kind == .result
        }
        #expect(try await store.activeSegment(sessionID: session.id)?.cursorSeq == before)
    }

    @Test("Grok confirms on its first reply, before the turn ends")
    func grokConfirmsOnTheFirstReply() async throws {
        let store = try makeTestStore("handoff-grok-reply")
        let session = try await enteredFromAnotherAgent(store, agent: .grok, model: "grok-4.6")
        let delivery = try await claimed(store, session, "PROMPT")
        let box = grokBox()
        let runner = try await grokRunner(store, session, box)
        defer { runner.terminateNow() }
        try await runner.sendDelivery(delivery)
        let promptSeq = try #require(try await store.delivery(id: delivery.id)?.deliveredSeq)
        let update = JSONValue.object([
            "sessionId": .string("sess-1"),
            "update": .object([
                "sessionUpdate": .string("agent_message_chunk"),
                "content": .object(["type": .string("text"), "text": .string("working")]),
            ]),
        ])

        box.process.emit(ACPOutgoing.notification(method: "session/update", params: update))
        box.process.emit(#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"sess-1","update":{"sessionUpdate":"tool_call","toolCallId":"t1","title":"ls","kind":"execute","status":"in_progress"}}}"#)

        await waitUntil("the first reply to confirm", within: .seconds(60)) {
            ((try? await store.activeSegment(sessionID: session.id))??.cursorSeq ?? -1) > promptSeq
        }
    }

    @Test("a Grok send with no delivery does not read its own row back")
    func grokWithoutDeliveryDoesNotReadItself() async throws {
        let store = try makeTestStore("handoff-grok-direct")
        let session = try await enteredFromAnotherAgent(store, agent: .grok, model: "grok-4.6")
        let box = grokBox()
        let runner = try await grokRunner(store, session, box)
        defer { runner.terminateNow() }

        try await runner.send("DIRECT")

        let frame = try #require(box.process.sentFrame { $0["method"]?.stringValue == "session/prompt" })
        let spoken = try #require(frame["params"]?["prompt"]?[0]?["text"]?.stringValue)
        #expect(spoken.components(separatedBy: "DIRECT").count == 2)
    }
}
