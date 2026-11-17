import Foundation
import Testing
@testable import Core

@Suite("Session grants in an orchestrator", .tags(.persistence), .scratchDirectory)
struct SessionGrantsOrchestratorTests {
    private func seed(_ store: Store) async throws -> [Workspace] {
        let repo = try await store.upsert(Repo(name: "r", path: TestScratch.unique("repo")))
        var rows: [Workspace] = []
        for name in ["lead", "other"] {
            rows.append(try await store.upsert(Workspace(
                repoID: repo.id, name: name, branch: "b/\(name)",
                path: TestScratch.unique(name), baseBranch: "main"
            )))
        }
        return rows
    }

    @Test("a chat in the orchestrator has its edits refused, read live, and other chats do not")
    func grantsRefuseLive() async throws {
        let store = try makeTestStore("orchestrator")
        let rows = try await seed(store)
        let lead = SessionGrants(store: store, workspaceID: rows[0].id)
        let other = SessionGrants(store: store, workspaceID: rows[1].id)

        #expect(await lead.refusal(toolName: "Edit", input: .object([:])) == nil)
        try await store.setOrchestrator(true, workspaceID: rows[0].id)

        #expect(await lead.isOrchestrator())
        #expect(await lead.refusal(toolName: "Edit", input: .object([:])) != nil)
        #expect(await lead.refusal(toolName: "Read", input: .object([:])) == nil)
        #expect(await other.refusal(toolName: "Edit", input: .object([:])) == nil)
    }

    @Test("a read is answered only while the workspace is the orchestrator, read live")
    func readsAnsweredLive() async throws {
        let store = try makeTestStore("orchestrator")
        let rows = try await seed(store)
        try await OrchestratorUnaskedCommands.save(false, repoID: rows[0].repoID, to: store)
        let lead = SessionGrants(store: store, workspaceID: rows[0].id)
        let other = SessionGrants(store: store, workspaceID: rows[1].id)
        let read = JSONValue.object(["command": .string("git log -1")])

        #expect(await !lead.answersItself(toolName: "Bash", input: read))
        try await store.setOrchestrator(true, workspaceID: rows[0].id)

        #expect(await lead.answersItself(toolName: "Bash", input: read))
        #expect(await !other.answersItself(toolName: "Bash", input: read))
        let elsewhere = JSONValue.object(["command": .string("git log -1"), "cwd": .string("/tmp/evil")])
        let here = JSONValue.object(["command": .string("git log -1"), "cwd": .string(rows[0].path)])
        #expect(await !lead.answersItself(toolName: "Bash", input: elsewhere))
        #expect(await lead.answersItself(toolName: "Bash", input: here))
        try await store.setOrchestrator(false, workspaceID: rows[0].id)
        #expect(await !lead.answersItself(toolName: "Bash", input: read))
    }
}
