import Foundation
import Testing
@testable import Core

@Suite("A start refused after the worktree was cut", .tags(.git, .destructive), .scratchDirectory)
struct WorkspaceStartRefusalTests {
    @Test("a second orchestrator arriving before the cut is refused after it and leaves nothing behind")
    func aRefusalLeavesNoWorktreeBranchOrRow() async throws {
        let repo = try await TempRepo()
        defer { repo.cleanUp() }
        let store = try makeTestStore("start-refusal")
        let manager = WorkspaceManager(store: store)
        let registered = try await manager.addRepository(at: repo.path)
        let other = try await manager.start(WorkspaceStartRequest(
            repo: registered, prompt: "Other work", origin: .user
        ))
        let id = WorkspaceID.new()
        let request = WorkspaceStartRequest(
            id: id, repo: registered, prompt: "Lead the work", origin: .user, orchestrates: true
        )
        let branchesBefore = try await Git.branches(of: repo.path)
        let worktreesBefore = try await Git.worktrees(of: repo.path).count

        await #expect(throws: WorkspaceError.self) {
            try await manager.start(request, namer: {
                _ = try? await store.setOrchestrator(true, workspaceID: other.workspace.id)
                return nil
            })
        }

        #expect(try await store.workspace(id: id) == nil)
        #expect(try await Git.branches(of: repo.path) == branchesBefore)
        #expect(try await Git.worktrees(of: repo.path).count == worktreesBefore)
    }

    @Test("only a branch the start cut itself is deleted when it is refused")
    func aCheckedOutBranchIsNotTheStartsToDelete() throws {
        let repo = Repo(name: "unified-dev", path: "/tmp/unified-dev", defaultBranch: "main")
        let cut = WorkspaceStartRequest(repo: repo, prompt: "Lead the work", origin: .user)
        let checkedOut = WorkspaceStartRequest(
            repo: repo, prompt: "Lead the work", origin: .user,
            checkout: .branch(ExistingBranch(name: "owners-branch", isLocal: true))
        )

        #expect(cut.cutsItsOwnBranch)
        #expect(checkedOut.cutsItsOwnBranch == false)
    }
}
