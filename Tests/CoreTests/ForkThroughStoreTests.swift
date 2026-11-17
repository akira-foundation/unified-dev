import Foundation
import Testing
@testable import Core

@Suite("Forking a chat through a message", .tags(.persistence), .scratchDirectory)
struct ForkThroughStoreTests {
    private func makeSession(_ store: Store) async throws -> Session {
        let repo = try await store.upsert(Repo(name: "r", path: TestScratch.unique("repo")))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "w", branch: "feature/w",
            path: TestScratch.unique("worktree"), baseBranch: "main"
        ))
        return try await store.upsert(Session(workspaceID: workspace.id))
    }

    private func said(_ text: String) -> Data {
        Data(#"{"type":"user","message":{"content":"\#(text)"}}"#.utf8)
    }

    @Test func aForkFromAMessageIsToldTheConversationUpToItAndNoFurther() async throws {
        let store = try makeTestStore("fork-through")
        let source = try await makeSession(store)
        let first = try await store.appendNext(sessionID: source.id, kind: .user, payload: said("light the lantern"))
        let second = try await store.appendNext(sessionID: source.id, kind: .user, payload: said("trim the wick"))
        _ = try await store.appendNext(sessionID: source.id, kind: .user, payload: said("polish the chimney"))
        let fork = try await store.upsert(Session(workspaceID: try #require(source.workspaceID)))

        try await store.seed(sessionID: fork.id, from: source.id, through: second.seq)

        let turn = try await store.handoffTurn(
            "next", sessionID: fork.id, deliveredSeq: nil, worktree: nil, contextWindow: nil
        )
        #expect(turn.contains("light the lantern") && turn.contains("trim the wick"))
        #expect(!turn.contains("polish the chimney"))
    }

    @Test func aForkThroughASeqPastTheEndIsToldEverythingUpToTheFork() async throws {
        let store = try makeTestStore("fork-past-end")
        let source = try await makeSession(store)
        let only = try await store.appendNext(sessionID: source.id, kind: .user, payload: said("light the lantern"))
        let fork = try await store.upsert(Session(workspaceID: try #require(source.workspaceID)))

        try await store.seed(sessionID: fork.id, from: source.id, through: only.seq + 50)
        _ = try await store.appendNext(sessionID: source.id, kind: .user, payload: said("said after the fork"))

        let turn = try await store.handoffTurn(
            "next", sessionID: fork.id, deliveredSeq: nil, worktree: nil, contextWindow: nil
        )
        #expect(turn.contains("light the lantern"))
        #expect(!turn.contains("said after the fork"))
        #expect(try await store.pendingSource(sessionID: fork.id) == source.id)
    }
}

@Suite("Controls carried into a new chat", .tags(.persistence), .scratchDirectory)
struct CarriedComposerControlsTests {
    @Test func aNewChatCarriesTheSourcesAgentAndItsStoredSettings() async throws {
        let store = try makeTestStore("carried-controls")
        let repo = try await store.upsert(Repo(name: "r", path: TestScratch.unique("repo")))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "w", branch: "feature/w",
            path: TestScratch.unique("worktree"), baseBranch: "main"
        ))
        let source = try await store.upsert(Session(
            workspaceID: workspace.id, model: "gpt-5", agentKind: .codex
        ))
        try await store.setSetting(ComposerControls.fastModeKey(sessionID: source.id), "1")
        try await store.setSetting(ComposerControls.outputStyleKey(sessionID: source.id), "Explanatory")
        try await store.setSetting(ComposerControls.contextWindowKey(sessionID: source.id), "400000")
        try await store.setSetting(CodexSpeed.key(sessionID: source.id), "0")

        let carried = try await ComposerControls.carried(from: source, in: store)

        #expect(carried.agentKind == .codex && carried.model == "gpt-5")
        #expect(carried.isFastMode && carried.outputStyle == "Explanatory")
        #expect(carried.codexContextWindow == 400_000 && carried.codexFastMode == false)
    }

    @Test func aSourceWithNothingStoredCarriesTheDefaults() async throws {
        let store = try makeTestStore("carried-controls-empty")
        let source = try await store.upsert(Session(workspaceID: nil))

        let carried = try await ComposerControls.carried(from: source, in: store)

        #expect(!carried.isFastMode && carried.outputStyle.isEmpty)
        #expect(carried.codexContextWindow == CodexContextWindow.modelDefault && carried.codexFastMode == nil)
    }
}
