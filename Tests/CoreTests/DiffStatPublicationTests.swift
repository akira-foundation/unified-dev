import Testing
import Foundation
@testable import Core

@Suite("Diff stat publication", .tags(.persistence), .scratchDirectory)
struct DiffStatPublicationTests {
    private func seeded(_ store: Store) async throws -> Workspace {
        let repo = try await store.upsert(Repo(name: "one", path: TestScratch.unique("repo")))
        let workspace = Workspace(
            repoID: repo.id, name: "work", branch: "b",
            path: TestScratch.unique("worktree"), baseBranch: "main"
        )
        try await store.upsert(workspace)
        return workspace
    }

    @Test("a diff stat write wakes nothing a project reload listens to")
    func diffStatWriteSkipsTheReloadDomains() async throws {
        let store = try makeTestStore("diffstat")
        let workspace = try await seeded(store)
        let reload = try await StoreChangeListener(
            store, interest: StoreDomain.projectsWorkspacesAndTheirAccounts
        )
        let counts = try await StoreChangeListener(store, interest: [.diffStats])

        try await store.updateDiffStat(workspaceID: workspace.id, additions: 3, deletions: 1, files: 2)

        #expect(await counts.nextBatch() == [.diffStats])
        #expect(await reload.nothingFurther())
        reload.stop()
        counts.stop()
    }

    @Test("a relabelled write inside a transaction keeps the other tables it touched")
    func relabelInsideTransactionKeepsOthers() async throws {
        let store = try makeTestStore("diffstat")
        let workspace = try await seeded(store)
        let database = try SQLiteDatabase(path: store.path)
        let listener = try await StoreChangeListener(store)

        try database.transaction {
            try database.run(
                "INSERT INTO repos (id, name, path, created_at) VALUES (?, ?, ?, ?)",
                [.text("r2"), .text("two"), .text("/tmp/two"), .double(1)]
            )
            try database.run(
                "UPDATE workspaces SET additions = 9 WHERE id = ?",
                [.text(workspace.id)],
                publishing: [.workspaces: .diffStats]
            )
        }

        #expect(await listener.nextBatch() == [.repos, .diffStats])
        listener.stop()
    }

    @Test("the counts read back are the ones written")
    func diffStatsReadBack() async throws {
        let store = try makeTestStore("diffstat")
        let workspace = try await seeded(store)

        try await store.updateDiffStat(workspaceID: workspace.id, additions: 7, deletions: 4, files: 3)

        let stats = try await store.diffStats()
        #expect(stats[workspace.id] == WorkspaceDiffStat(additions: 7, deletions: 4, files: 3))
    }

    @Test("counts that match the list are no change")
    func equalCountsAreNoChange() {
        let workspace = Workspace(
            repoID: RepoID("r"), name: "w", branch: "b", path: "/w", baseBranch: "main",
            additions: 1, deletions: 2, changedFiles: 3
        )
        let stats = [workspace.id: WorkspaceDiffStat(additions: 1, deletions: 2, files: 3)]

        #expect(WorkspaceDiffStat.changes(stats, to: [workspace]).isEmpty)
    }

    @Test("only the workspace whose counts moved is a change, and applying it touches only its counts")
    func onlyTheMovedWorkspaceChanges() {
        let still = Workspace(repoID: RepoID("r"), name: "still", branch: "a", path: "/a", baseBranch: "main")
        var moved = Workspace(repoID: RepoID("r"), name: "moved", branch: "b", path: "/b", baseBranch: "main")
        let stat = WorkspaceDiffStat(additions: 5, deletions: 6, files: 2)
        let stats = [still.id: WorkspaceDiffStat(of: still), moved.id: stat]

        let changes = WorkspaceDiffStat.changes(stats, to: [still, moved])
        changes[moved.id]?.apply(to: &moved)

        #expect(changes == [moved.id: stat])
        #expect(moved.additions == 5)
        #expect(moved.deletions == 6)
        #expect(moved.changedFiles == 2)
        #expect(moved.name == "moved")
    }

    @Test("an archived workspace's counts are not read back")
    func archivedCountsAreNotRead() async throws {
        let store = try makeTestStore("diffstat")
        let workspace = try await seeded(store)
        try await store.updateDiffStat(workspaceID: workspace.id, additions: 7, deletions: 4, files: 3)
        try await store.update(workspaceID: workspace.id) { $0.state = .archived }

        #expect(try await store.diffStats()[workspace.id] == nil)
    }

    @Test("a write after a diff stat names its own table again")
    func relabelEndsWithItsStatement() async throws {
        let store = try makeTestStore("diffstat")
        let workspace = try await seeded(store)
        try await store.updateDiffStat(workspaceID: workspace.id, additions: 3, deletions: 1, files: 2)
        let listener = try await StoreChangeListener(store)

        try await store.update(workspaceID: workspace.id) { $0.name = "renamed" }

        #expect(await listener.nextBatch() == [.workspaces])
        listener.stop()
    }

    @Test("a stat for a workspace not listed, or a listed workspace with no stat, is no change")
    func unmatchedIdsAreNoChange() {
        let listed = Workspace(
            repoID: RepoID("r"), name: "listed", branch: "a", path: "/a", baseBranch: "main", additions: 4
        )
        let gone = WorkspaceID("gone")

        let changes = WorkspaceDiffStat.changes(
            [gone: WorkspaceDiffStat(additions: 9, deletions: 9, files: 9)], to: [listed]
        )

        #expect(changes.isEmpty)
    }

    @Test("the project list feed covers every domain a reload reads, and diff stats beside them")
    func projectListFeedCoversReloadAndCounts() {
        #expect(StoreDomain.projectListFeed.isSuperset(of: StoreDomain.projectsWorkspacesAndTheirAccounts))
        #expect(StoreDomain.projectListFeed.contains(.diffStats))
    }

    @Test("a batch of counts alone is answered without a reload")
    func countsAloneSkipTheReload() {
        #expect(ProjectListRefresh(answering: [.diffStats]) == .diffStatsOnly)
    }

    @Test("a batch naming any reload domain reloads, counts or not", arguments: [
        Set<StoreDomain>([.workspaces]),
        [.repos, .diffStats],
        [.repoAgentAccounts],
        [.profileAgentAccounts, .diffStats],
    ])
    func anyReloadDomainReloads(batch: Set<StoreDomain>) {
        #expect(ProjectListRefresh(answering: batch) == .reload)
    }
}
