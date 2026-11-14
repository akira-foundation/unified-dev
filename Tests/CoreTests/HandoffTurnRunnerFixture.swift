import Testing
import Foundation
@testable import Core

let handoffThreadID = "01a02144-3b7e-7233-97f2-73ebd5105085"
let handoffTurnID = "01a02144-3bab-7fe3-a92c-6eec594d84fd"

protocol HandoffTurnRunnerFixture {}

extension HandoffTurnRunnerFixture {
    func makeSession(_ store: Store, agent: AgentKind, model: String) async throws -> Session {
        let repo = try await store.upsert(Repo(name: "r", path: TestScratch.unique("repo")))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "w", branch: "b", path: TestScratch.unique("worktree"), baseBranch: "main"
        ))
        return try await store.upsert(Session(workspaceID: workspace.id, model: model, agentKind: agent))
    }

    func enteredFromAnotherAgent(
        _ store: Store, agent: AgentKind, model: String, from origin: AgentKind? = nil
    ) async throws -> Session {
        let start: AgentKind = origin ?? (agent == .claudeCode ? .codex : .claudeCode)
        let session = try await makeSession(store, agent: start, model: "first")
        let json = JSONValue.object(["type": .string("user"), "message": .object(["content": .string("earlier words")])])
        try await store.appendNext(sessionID: session.id, kind: .user, payload: Data(json.compactJSON.utf8))
        return try await store.switchSegment(sessionID: session.id, to: SessionSegmentTarget(
            agentKind: agent, accountID: nil, model: model, effort: ""
        ))
    }

    func spoke(_ store: Store, _ session: Session, owner: String, reply: String, native: String) async throws {
        let line = JSONValue.object(["type": .string("user"), "message": .object(["content": .string(owner)])])
        try await store.appendNext(sessionID: session.id, kind: .user, payload: Data(line.compactJSON.utf8))
        let answer = #"{"type":"assistant","message":{"model":"m","role":"assistant","content":[{"type":"text","text":"\#(reply)"}]}}"#
        try await store.appendNext(sessionID: session.id, kind: .assistantText, payload: Data(answer.utf8))
        let active = try #require(try await store.activeSegment(sessionID: session.id))
        try await store.acknowledgeHandoff(sessionID: session.id, fromSegment: active.id, carriedDelta: false)
        try #require(try await store.update(sessionID: session.id) { $0.agentSessionID = native } != nil)
    }

    func toSegment(_ agent: AgentKind, _ model: String) -> SessionSegmentTarget {
        SessionSegmentTarget(agentKind: agent, accountID: nil, model: model, effort: "")
    }

    func claimed(_ store: Store, _ session: Session, _ body: String) async throws -> Delivery {
        let delivery = try await store.enqueueDelivery(Delivery(targetSessionID: session.id, body: body))
        let claimed = try await store.claimDelivery(id: delivery.id)
        #expect(claimed)
        return delivery
    }

    func cursor(_ store: Store, _ session: Session) async throws -> Int {
        try #require(try await store.activeSegment(sessionID: session.id)).cursorSeq
    }

    func storedUserTexts(_ store: Store, _ session: Session) async throws -> [String] {
        try await store.messages(sessionID: session.id)
            .filter { $0.kind == .user }
            .compactMap { MessageCopyText.markdown(kind: .user, payload: $0.payload) }
    }

    func claudeRunner(_ store: Store, _ session: Session, _ box: ProcessBox) async throws -> AgentRunner {
        AgentRunner(workspacePath: "/tmp/w", session: session, store: store, segmentID: try await activeSegmentID(store, session), makeProcess: box.factory)
    }

    func claudeReply(_ text: String) -> AgentEvent {
        let line = #"{"type":"assistant","message":{"model":"opus","role":"assistant","content":[{"type":"text","text":"\#(text)"}]}}"#
        return AgentEvent.decode(line: line) ?? .unknown(Data())
    }

    var claudeResult: AgentEvent {
        let line = #"{"type":"result","subtype":"success","is_error":false,"result":"done","session_id":"s"}"#
        return AgentEvent.decode(line: line) ?? .unknown(Data())
    }

    func codexRunner(_ store: Store, _ session: Session, _ box: ProcessBox) async throws -> CodexRunner {
        CodexRunner(workspacePath: "/tmp/w", session: session, store: store, segmentID: try await activeSegmentID(store, session), makeClient: { configuration in
            CodexClient(configuration: configuration, makeProcess: box.factory)
        })
    }

    func codexBox() -> ProcessBox {
        let box = ProcessBox()
        box.reply(to: "thread/start", with: .object([
            "thread": .object(["id": .string(handoffThreadID)]), "model": .string("gpt-5"),
        ]))
        box.reply(to: "turn/start", with: .object([
            "turn": .object(["id": .string(handoffTurnID), "status": .string("inProgress"), "items": .array([])]),
        ]))
        box.reply(to: "turn/steer", with: .object([:]))
        return box
    }

    func codexText(_ method: String, _ box: ProcessBox) -> String? {
        box.process.sentFrame { $0["method"]?.stringValue == method }?["params"]?["input"]?[0]?["text"]?.stringValue
    }

    func emitCodexReply(_ box: ProcessBox) {
        box.process.emit(#"{"method":"item/completed","params":{"threadId":"\#(handoffThreadID)","turnId":"\#(handoffTurnID)","item":{"id":"text","type":"agentMessage","text":"working"}}}"#)
    }

    func grokRunner(_ store: Store, _ session: Session, _ box: ProcessBox) async throws -> ACPRunner {
        ACPRunner(dialect: .grok, workspacePath: "/tmp/w", session: session, store: store, segmentID: try await activeSegmentID(store, session), makeClient: { configuration in
            ACPClient(configuration: configuration, makeProcess: box.factory)
        })
    }

    func grokBox() -> ProcessBox {
        let box = ProcessBox()
        box.reply(to: "initialize", with: .object(["_meta": .object([:])]))
        box.reply(to: "session/new", with: .object(["sessionId": .string("sess-1")]))
        box.reply(to: "session/set_config_option", with: .object([:]))
        box.ignore("session/prompt")
        return box
    }
}
