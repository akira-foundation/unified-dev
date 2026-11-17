import Testing
import Foundation
@testable import Core

@Suite(.scratchDirectory) struct StoreSessionsByIDTests {
    private func makeWorkspace(_ store: Store) async throws -> Workspace {
        let repo = try await store.upsert(Repo(name: "r", path: "/tmp/r-\(UUID().uuidString)"))
        return try await store.upsert(Workspace(
            repoID: repo.id, name: "w", branch: "b", path: "/tmp/w", baseBranch: "main"
        ))
    }

    @Test func readsEverySessionAskedForInOneCall() async throws {
        let store = try makeTestStore("sessions-by-id")
        let workspace = try await makeWorkspace(store)
        let first = try await store.upsert(Session(workspaceID: workspace.id, model: "opus"))
        let second = try await store.upsert(Session(workspaceID: workspace.id, model: "sonnet"))
        _ = try await store.upsert(Session(workspaceID: workspace.id, model: "haiku"))

        let found = try await store.sessions(ids: [first.id, second.id, first.id, SessionID("missing")])

        #expect(Set(found.keys) == [first.id, second.id])
        #expect(found[first.id]?.model == "opus")
        #expect(found[second.id]?.model == "sonnet")
    }

    @Test func asksNothingForNoIDs() async throws {
        let store = try makeTestStore("sessions-by-id-empty")
        let found = try await store.sessions(ids: [])
        #expect(found.isEmpty)
    }
}
