import Foundation

enum InboxNotificationColumns {
    static let createTable = """
        CREATE TABLE IF NOT EXISTS inbox_notifications (
            id TEXT PRIMARY KEY,
            event TEXT NOT NULL,
            workspace_id TEXT NOT NULL,
            session_id TEXT,
            workspace_name TEXT NOT NULL,
            detail TEXT NOT NULL DEFAULT '',
            profile_id TEXT,
            created_at REAL NOT NULL,
            read_at REAL
        );
        CREATE INDEX IF NOT EXISTS inbox_notifications_workspace
            ON inbox_notifications(workspace_id, read_at);
        """

    private static let listed = """
        SELECT n.*, w.state AS workspace_state, s.id AS live_session,
               COALESCE(r.profile_id, n.profile_id) AS owner_profile
        FROM inbox_notifications n
        LEFT JOIN workspaces w ON w.id = n.workspace_id
        LEFT JOIN repos r ON r.id = w.repo_id
        LEFT JOIN sessions s ON s.id = n.session_id AND s.archived_at IS NULL
        """

    static let all = "\(listed) WHERE n.created_at >= ? ORDER BY n.created_at DESC, n.rowid DESC"

    static let unreadInWorkspace = "\(listed) WHERE n.workspace_id = ? AND n.read_at IS NULL"

    private static let sameSubject = """
        SELECT id FROM inbox_notifications WHERE workspace_id = ? AND session_id IS ? AND event = ? LIMIT 1
        """

    private static let refresh = """
        UPDATE inbox_notifications SET workspace_name = ?, detail = ?, created_at = ?, read_at = NULL WHERE id = ?
        """

    private static let insert = """
        INSERT INTO inbox_notifications
            (id, event, workspace_id, session_id, workspace_name, detail, profile_id, created_at, read_at)
        VALUES (?, ?, ?, ?, ?, ?,
            (SELECT r.profile_id FROM workspaces w JOIN repos r ON r.id = w.repo_id WHERE w.id = ?), ?, NULL)
        """

    static let markRead = "UPDATE inbox_notifications SET read_at = ? WHERE id = ? AND read_at IS NULL"

    static let markAllRead = "UPDATE inbox_notifications SET read_at = ? WHERE read_at IS NULL"

    private static let expire = "DELETE FROM inbox_notifications WHERE created_at < ?"

    private static let trim = """
        DELETE FROM inbox_notifications WHERE id NOT IN (
            SELECT id FROM inbox_notifications ORDER BY created_at DESC, rowid DESC LIMIT ?
        )
        """

    static func record(_ draft: NotificationDraft, at moment: Date, in db: SQLiteDatabase) throws {
        let detail = NotificationDigest.cap(draft.detail.trimmingCharacters(in: .whitespacesAndNewlines))
        let session: SQLValue = draft.sessionID.map { .text($0.rawValue) } ?? .null
        let existing = try db.query(
            sameSubject, [.text(draft.workspaceID), session, .text(draft.event.rawValue)]
        ).first?.string("id")
        if let existing {
            try db.run(refresh, [
                .text(draft.workspaceName), .text(detail), .double(moment.timeIntervalSince1970), .text(existing),
            ])
        } else {
            try db.run(insert, [
                .text(newID()), .text(draft.event.rawValue), .text(draft.workspaceID), session,
                .text(draft.workspaceName), .text(detail), .text(draft.workspaceID),
                .double(moment.timeIntervalSince1970),
            ])
        }
        try prune(at: moment, in: db)
    }

    static func cutoff(at moment: Date) -> Double {
        moment.addingTimeInterval(-NotificationInbox.retention).timeIntervalSince1970
    }

    static func prune(at moment: Date, in db: SQLiteDatabase) throws {
        try db.run(expire, [.double(cutoff(at: moment))])
        try db.run(trim, [.int(Int64(NotificationInbox.capacity))])
    }

    static func notification(from row: Row) -> InboxNotification? {
        guard let event = row.string("event").flatMap(NotificationEvent.init(rawValue:)),
              let id = row.string("id"),
              let workspaceID = row.string("workspace_id"),
              let createdAt = row.date("created_at")
        else { return nil }
        let sessionID = row.string("session_id").map(SessionID.init)
        return InboxNotification(
            id: InboxNotificationID(id),
            event: event,
            workspaceID: WorkspaceID(workspaceID),
            sessionID: sessionID,
            workspaceName: row.string("workspace_name") ?? "",
            detail: row.string("detail") ?? "",
            createdAt: createdAt,
            readAt: row.date("read_at"),
            profileID: row.string("owner_profile").map(ProfileID.init),
            workspaceState: row.string("workspace_state").flatMap(WorkspaceState.init(rawValue:)),
            chatExists: sessionID == nil || row.string("live_session") != nil
        )
    }
}
