import Testing
import Foundation
@testable import Core

private func decidedRowsSession(_ store: Store) async throws -> Session {
    let repo = try await store.upsert(Repo(name: "r", path: "/tmp/decided-\(UUID())"))
    let workspace = try await store.upsert(Workspace(
        repoID: repo.id, name: "w", branch: "b", path: "/tmp/w", baseBranch: "main"
    ))
    return try await store.upsert(Session(workspaceID: workspace.id, model: "grok-4.6", agentKind: .grok))
}

private func decidedRowsBox() -> ProcessBox {
    let box = ProcessBox()
    box.reply(to: "initialize", with: .object([:]))
    box.reply(to: "session/new", with: .object(["sessionId": .string("s")]))
    box.reply(to: "session/resume", with: .object(["sessionId": .string("s")]))
    box.ignore("session/prompt")
    return box
}

@Suite(.scratchDirectory)
struct RunnerStoredRowsTests {
    @Test("the row an event announces is handed over, equal to the stored one")
    func theAnnouncedRowArrivesWithTheEvent() async throws {
        let store = try makeTestStore("decided-rows")
        let session = try await decidedRowsSession(store)
        let box = decidedRowsBox()
        let runner = ACPRunner(
            dialect: .grok,
            workspacePath: "/tmp/w", session: session, store: store,
            segmentID: try await activeSegmentID(store, session),
            makeClient: { ACPClient(configuration: $0, makeProcess: box.factory) }
        )
        defer { runner.terminateNow() }
        let feed = try #require(runner.presentationFeed)
        let relay = try #require(runner.storedMessages)

        try await runner.send("hello")
        box.process.emit(ACPOutgoing.notification(method: "session/update", params: .object([
            "sessionId": .string("s"),
            "update": .object(["sessionUpdate": .string("agent_message_chunk"), "content": .object([
                "type": .string("text"), "text": .string("Hi there"),
            ])]),
        ])))
        let prompt = try #require(box.process.stdin.compactMap(JSONValue.parse).last { $0["method"]?.stringValue == "session/prompt" })
        box.process.emit("{\"id\":\(try #require(prompt["id"]).compactJSON),\"result\":{\"stopReason\":\"end_turn\"}}")

        await waitUntil("a stored row is announced", within: .seconds(2)) {
            feed.read(after: 0).messageSequences.contains { $0 != nil }
        }
        let seq = try #require(feed.read(after: 0).messageSequences.compactMap(\.self).last)
        let stored = try #require(try await store.messages(sessionID: session.id).first { $0.seq == seq })

        let handed = try #require(relay.take(after: seq - 1, through: seq))

        #expect(handed.map(\.id) == [stored.id])
        #expect(handed.map(\.kind) == [stored.kind])
        #expect(handed.map(\.payload) == [stored.payload])
        #expect(handed.map(\.refID) == [stored.refID])
    }
}
