import Testing
import Foundation
@testable import Core

@Suite("The slot of the inbox migration among the last ones", .tags(.persistence), .scratchDirectory)
struct MigrationSlotOrderTests {
    private func inboxTableExists(at path: String) throws -> Bool {
        let rows = try SQLiteDatabase(path: path).query(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'inbox_notifications';"
        )
        return !rows.isEmpty
    }

    private func storeWithoutInboxTable(rewoundBy steps: Int32) throws -> (path: String, current: Int32) {
        let path = TestScratch.unique("migration-slots") + ".sqlite"
        _ = try Store(path: path)
        let raw = try SQLiteDatabase(path: path)
        let current = try raw.readUserVersion()
        try raw.execute("DROP TABLE inbox_notifications;")
        try raw.setUserVersion(current - steps)
        return (path, current)
    }

    @Test func theFifthToLastMigrationCreatesTheInboxTable() throws {
        let seeded = try storeWithoutInboxTable(rewoundBy: 5)

        _ = try Store(path: seeded.path)

        #expect(try inboxTableExists(at: seeded.path))
        #expect(try SQLiteDatabase(path: seeded.path).readUserVersion() == seeded.current)
    }

    @Test func theLastFourMigrationsDoNotCreateTheInboxTable() throws {
        let seeded = try storeWithoutInboxTable(rewoundBy: 4)

        _ = try Store(path: seeded.path)

        #expect(try !inboxTableExists(at: seeded.path))
    }

    @Test func theLastMigrationCreatesTheChapterTable() async throws {
        let path = TestScratch.unique("migration-chapters") + ".sqlite"
        _ = try Store(path: path)
        let raw = try SQLiteDatabase(path: path)
        let current = try raw.readUserVersion()
        try raw.execute("DROP TABLE transcript_chapters;")
        try raw.setUserVersion(current - 1)

        let reopened = try Store(path: path)
        let repo = try await reopened.upsert(Repo(name: "r", path: TestScratch.unique("repo")))
        let workspace = try await reopened.upsert(Workspace(
            repoID: repo.id, name: "w", branch: "feature/w",
            path: TestScratch.unique("worktree"), baseBranch: "main"
        ))
        let session = try await reopened.upsert(Session(workspaceID: workspace.id))
        try await reopened.pin(TranscriptChapter(seq: 1, title: "one"), sessionID: session.id)

        #expect(try await reopened.chapters(sessionID: session.id) == [TranscriptChapter(seq: 1, title: "one")])
    }
}
