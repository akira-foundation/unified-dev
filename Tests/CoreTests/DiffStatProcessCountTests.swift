import Foundation
import Testing
@testable import Core

@Suite("How many processes one diff refresh starts", .tags(.git, .destructive), .scratchDirectory)
struct DiffStatProcessCountTests {
    private func fixture() async throws -> (TempRepo, WorkspaceManager, Workspace) {
        let repo = try await TempRepo()
        let store = try makeTestStore("process-count")
        let manager = WorkspaceManager(store: store)
        let registered = try await manager.addRepository(at: repo.path)
        let created = try await manager.createWorkspace(repo: registered, prompt: "Count the processes")
        let workspace = try #require(try await store.workspace(id: created.id))
        return (repo, manager, workspace)
    }

    @Test("a refresh with its baseline known starts four git processes")
    func refreshStartsFour() async throws {
        let (repo, manager, workspace) = try await fixture()
        defer { repo.cleanUp() }
        try Data("one\ntwo\n".utf8).write(to: URL(fileURLWithPath: workspace.path + "/notes.txt"))
        #expect(await manager.refreshDiffStat(workspace: workspace))

        let tally = SpawnTally()
        let refreshed = await Shell.$spawnTally.withValue(tally) {
            await manager.refreshDiffStat(workspace: workspace)
        }

        #expect(refreshed)
        #expect(tally.count == 4)
    }

    @Test("the counts read a rename, an edit, a binary and an untracked file as git does")
    func countsReadEachKindOfChange() async throws {
        let repo = try await TempRepo()
        defer { repo.cleanUp() }
        try repo.write("moved.txt", "a\nb\nc\nd\ne\nf\n")
        try repo.write("kept.txt", "one\n")
        try Data([0, 1, 2, 3]).write(to: URL(fileURLWithPath: repo.path + "/blob.bin"))
        try await repo.commit("Seed the base")
        let store = try makeTestStore("process-count")
        let manager = WorkspaceManager(store: store)
        let registered = try await manager.addRepository(at: repo.path)
        let created = try await manager.createWorkspace(repo: registered, prompt: "Count the kinds")
        let workspace = try #require(try await store.workspace(id: created.id))
        let tree = TempRepo(existing: workspace.path)
        try await Shell.check("git", ["mv", "moved.txt", "renamed.txt"], cwd: workspace.path)
        try tree.write("kept.txt", "one\ntwo\n")
        try Data([4, 5, 6, 0]).write(to: URL(fileURLWithPath: workspace.path + "/blob.bin"))
        try tree.write("new.txt", "fresh\nlines\n")

        let files = try await Git.changedFiles(worktree: workspace.path, base: workspace.baseBranch)
        let stat = try await Git.diffStat(worktree: workspace.path, base: workspace.baseBranch)

        #expect(files.first { $0.path == "renamed.txt" }?.change == .renamed)
        #expect(stat.files == 4)
        #expect(stat.additions == 3)
        #expect(stat.deletions == 0)
        #expect(stat.files == files.count)
        #expect(stat.additions == files.reduce(0) { $0 + $1.additions })
    }
}
