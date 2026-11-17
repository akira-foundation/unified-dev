import Testing
import Foundation
@testable import Core

@Suite("Notification inbox persistence", .tags(.persistence), .scratchDirectory)
struct NotificationInboxPersistenceTests {
    private let moment = Date(timeIntervalSince1970: 1_800_000_000)

    private func seed(_ store: Store) async throws -> (Workspace, Session) {
        let repo = try await store.upsert(Repo(name: "r", path: TestScratch.unique("repo")))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "Tide tables", branch: "tide", path: TestScratch.unique("tree"), baseBranch: "main"
        ))
        let session = try await store.upsert(Session(workspaceID: workspace.id, title: "Chat"))
        return (workspace, session)
    }

    private func draft(
        _ workspace: Workspace, _ session: Session?, _ event: NotificationEvent = .turnFinished, detail: String = "Done"
    ) -> NotificationDraft {
        NotificationDraft(
            event: event, workspaceID: workspace.id, sessionID: session?.id,
            workspaceName: workspace.name, detail: detail
        )
    }

    @Test("a row keeps what it was told and survives reopening the database")
    func survivesRestart() async throws {
        let path = TestScratch.unique("inbox") + ".sqlite"
        let store = try Store(path: path)
        let (workspace, session) = try await seed(store)

        try await store.recordInboxNotification(draft(workspace, session), at: moment)

        let rows = try await Store(path: path).inboxNotifications(at: moment)
        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.event == .turnFinished)
        #expect(row.sessionID == session.id)
        #expect(row.detail == "Done")
        #expect(row.profileID == .initial)
        #expect(row.destination == .chat(workspace.id, session.id))
    }

    @Test("the same event in the same chat refreshes its row and comes back unseen")
    func repeatRefreshes() async throws {
        let store = try makeTestStore("inbox")
        let (workspace, session) = try await seed(store)
        try await store.recordInboxNotification(draft(workspace, session, detail: "First"), at: moment)
        try await store.markAllInboxNotificationsRead(at: moment)

        try await store.recordInboxNotification(
            draft(workspace, session, detail: "Second"), at: moment.addingTimeInterval(60)
        )

        let rows = try await store.inboxNotifications(at: moment)
        #expect(rows.count == 1)
        #expect(rows[0].detail == "Second")
        #expect(!rows[0].isRead)
        #expect(rows[0].createdAt == moment.addingTimeInterval(60))
    }

    @Test("another event, or a notification with no chat, gets its own row")
    func distinctSubjects() async throws {
        let store = try makeTestStore("inbox")
        let (workspace, session) = try await seed(store)

        try await store.recordInboxNotification(draft(workspace, session), at: moment)
        try await store.recordInboxNotification(draft(workspace, session, .needsInput), at: moment)
        try await store.recordInboxNotification(draft(workspace, nil), at: moment)
        try await store.recordInboxNotification(draft(workspace, nil), at: moment)

        #expect(try await store.inboxNotifications(at: moment).count == 3)
    }

    @Test("opening a chat marks only what it clears")
    func openingMarksRead() async throws {
        let store = try makeTestStore("inbox")
        let (workspace, session) = try await seed(store)
        let other = try await store.upsert(Session(workspaceID: workspace.id, title: "Other"))
        try await store.recordInboxNotification(draft(workspace, session), at: moment)
        try await store.recordInboxNotification(draft(workspace, other), at: moment)

        try await store.markInboxNotificationsRead(.chat(workspace.id, session.id), at: moment)

        let rows = try await store.inboxNotifications(at: moment)
        #expect(rows.first { $0.sessionID == session.id }?.isRead == true)
        #expect(rows.first { $0.sessionID == other.id }?.isRead == false)
    }

    @Test("a row follows its project into another profile")
    func followsTheProject() async throws {
        let store = try makeTestStore("inbox")
        let (workspace, session) = try await seed(store)
        try await store.recordInboxNotification(draft(workspace, session), at: moment)
        let profile = try await store.createProfile(
            name: "Akira", colour: "4C8DF6", symbol: "leaf", accounts: .inherits, occupiedFolders: []
        )

        try await store.move(repoID: workspace.repoID, to: profile.id)

        #expect(try await store.inboxNotifications(at: moment).first?.profileID == profile.id)
    }

    @Test("archiving keeps the row, and it opens the archive view")
    func archivedKeepsTheRow() async throws {
        let store = try makeTestStore("inbox")
        let (workspace, session) = try await seed(store)
        try await store.recordInboxNotification(draft(workspace, session), at: moment)

        try await store.update(workspaceID: workspace.id) { $0.state = .archived }

        let row = try #require(try await store.inboxNotifications(at: moment).first)
        #expect(row.destination == .archived(workspace.id, session.id))
        #expect(row.counts)
    }

    @Test("removing the workspace stops the row counting and keeps its profile")
    func removedStopsCounting() async throws {
        let store = try makeTestStore("inbox")
        let (workspace, session) = try await seed(store)
        try await store.recordInboxNotification(draft(workspace, session), at: moment)

        try await store.deleteWorkspace(id: workspace.id)

        let row = try #require(try await store.inboxNotifications(at: moment).first)
        #expect(row.destination == .gone)
        #expect(!row.counts)
        #expect(row.profileID == .initial)
    }

    @Test("deleting the chat sends the row to its workspace")
    func deletedChatGoesToTheWorkspace() async throws {
        let store = try makeTestStore("inbox")
        let (workspace, session) = try await seed(store)
        try await store.recordInboxNotification(draft(workspace, session), at: moment)

        try await store.deleteSession(id: session.id)

        #expect(try await store.inboxNotifications(at: moment).first?.destination == .chatGone(workspace.id))
    }

    @Test("rows older than the retention are pruned and younger ones stay")
    func retention() async throws {
        let store = try makeTestStore("inbox")
        let (workspace, session) = try await seed(store)
        let old = moment.addingTimeInterval(-NotificationInbox.retention - 1)
        let recent = moment.addingTimeInterval(-NotificationInbox.retention + 60)
        try await store.recordInboxNotification(draft(workspace, session, .turnFinished), at: old)
        try await store.recordInboxNotification(draft(workspace, session, .needsInput), at: recent)

        try await store.pruneInboxNotifications(at: moment)

        #expect(try await store.inboxNotifications(at: moment).map(\.event) == [.needsInput])
    }

    @Test("a long detail is stored as one capped line")
    func detailIsCapped() async throws {
        let store = try makeTestStore("inbox")
        let (workspace, session) = try await seed(store)
        let long = String(repeating: "x", count: NotificationDigest.bodyLimit + 40)

        try await store.recordInboxNotification(draft(workspace, session, detail: "  \(long)\nsecond line\n"), at: moment)

        let detail = try #require(try await store.inboxNotifications(at: moment).first?.detail)
        #expect(detail.count == NotificationDigest.bodyLimit + 1)
        #expect(!detail.contains("second line"))
    }

    @Test("two workspaces with no chat keep separate rows")
    func noChatPerWorkspace() async throws {
        let store = try makeTestStore("inbox")
        let (workspace, _) = try await seed(store)
        let other = try await store.upsert(Workspace(
            repoID: workspace.repoID, name: "Other", branch: "other",
            path: TestScratch.unique("other"), baseBranch: "main"
        ))

        try await store.recordInboxNotification(draft(workspace, nil), at: moment)
        try await store.recordInboxNotification(draft(other, nil), at: moment)

        #expect(try await store.inboxNotifications(at: moment).count == 2)
    }

    @Test("a closed chat counts as gone")
    func closedChat() async throws {
        let store = try makeTestStore("inbox")
        let (workspace, session) = try await seed(store)
        try await store.recordInboxNotification(draft(workspace, session), at: moment)

        try await store.update(sessionID: session.id) { $0.archivedAt = moment }

        #expect(try await store.inboxNotifications(at: moment).first?.destination == .chatGone(workspace.id))
    }

    @Test("an expired row is not listed even before anything prunes it")
    func expiredIsNotListed() async throws {
        let store = try makeTestStore("inbox")
        let (workspace, session) = try await seed(store)
        try await store.recordInboxNotification(draft(workspace, session), at: moment)

        let later = moment.addingTimeInterval(NotificationInbox.retention + 1)

        #expect(try await store.inboxNotifications(at: later).isEmpty)
    }

    @Test("pruning also holds the capacity")
    func pruneHoldsCapacity() async throws {
        let store = try makeTestStore("inbox")
        let (workspace, _) = try await seed(store)
        let raw = try SQLiteDatabase(path: store.path)
        for index in 0...NotificationInbox.capacity {
            _ = try raw.run(
                """
                INSERT INTO inbox_notifications (id, event, workspace_id, workspace_name, created_at)
                VALUES (?, 'turnFinished', ?, 'Tide tables', ?)
                """,
                [.text("row-\(index)"), .text(workspace.id.rawValue), .double(moment.timeIntervalSince1970 + Double(index))]
            )
        }

        try await store.pruneInboxNotifications(at: moment)

        #expect(try await store.inboxNotifications(at: moment).count == NotificationInbox.capacity)
    }

    @Test("the capacity keeps the newest rows")
    func capacity() async throws {
        let store = try makeTestStore("inbox")
        let (workspace, _) = try await seed(store)
        for index in 0...NotificationInbox.capacity {
            let session = SessionID("chat-\(index)")
            try await store.recordInboxNotification(
                NotificationDraft(
                    event: .turnFinished, workspaceID: workspace.id, sessionID: session, workspaceName: "Tide tables"
                ),
                at: moment.addingTimeInterval(TimeInterval(index))
            )
        }

        let rows = try await store.inboxNotifications(at: moment)
        #expect(rows.count == NotificationInbox.capacity)
        #expect(rows.first?.sessionID == SessionID("chat-\(NotificationInbox.capacity)"))
        #expect(!rows.contains { $0.sessionID == SessionID("chat-0") })
    }
}
