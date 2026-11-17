import Foundation

enum PullRequestFixColumns {
    static func migrate(_ db: SQLiteDatabase) throws {
        try db.execute(createTables)
    }

    static let createTables = """
        CREATE TABLE IF NOT EXISTS pull_request_fix_runs (
            workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
            pull_request_number INTEGER NOT NULL,
            in_a_row INTEGER NOT NULL DEFAULT 0,
            stop_announced_at REAL,
            PRIMARY KEY (workspace_id, pull_request_number)
        );
        CREATE TABLE IF NOT EXISTS pull_request_fix_attempts (
            workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
            pull_request_number INTEGER NOT NULL,
            head_commit TEXT NOT NULL,
            reason TEXT NOT NULL,
            attempted_at REAL NOT NULL,
            PRIMARY KEY (workspace_id, pull_request_number, head_commit, reason)
        );
        """

    static let run = "SELECT in_a_row, stop_announced_at FROM pull_request_fix_runs WHERE workspace_id = ? AND pull_request_number = ?"

    static let attempts = "SELECT head_commit, reason FROM pull_request_fix_attempts WHERE workspace_id = ? AND pull_request_number = ?"

    static let openRun = "INSERT OR IGNORE INTO pull_request_fix_runs (workspace_id, pull_request_number) VALUES (?, ?)"

    static let insertAttempt = """
        INSERT OR IGNORE INTO pull_request_fix_attempts
            (workspace_id, pull_request_number, head_commit, reason, attempted_at)
        VALUES (?, ?, ?, ?, ?)
        """

    static let deleteAttempt = """
        DELETE FROM pull_request_fix_attempts
        WHERE workspace_id = ? AND pull_request_number = ? AND head_commit = ? AND reason = ?
        """

    static let count = "UPDATE pull_request_fix_runs SET in_a_row = in_a_row + 1 WHERE workspace_id = ? AND pull_request_number = ?"

    static let uncount = """
        UPDATE pull_request_fix_runs SET in_a_row = MAX(in_a_row - 1, 0)
        WHERE workspace_id = ? AND pull_request_number = ?
        """

    static let forgive = """
        UPDATE pull_request_fix_runs SET in_a_row = 0, stop_announced_at = NULL
        WHERE workspace_id = ? AND pull_request_number = ?
        """

    static let announceStop = """
        UPDATE pull_request_fix_runs SET stop_announced_at = ?
        WHERE workspace_id = ? AND pull_request_number = ? AND stop_announced_at IS NULL
        """

    static func key(_ workspaceID: WorkspaceID, _ number: Int) -> [SQLValue] {
        [.text(workspaceID), .int(Int64(number))]
    }

    static func values(_ attempt: PullRequestAutoFix.Attempt) -> [SQLValue] {
        [.text(attempt.headCommit), .text(attempt.reason.rawValue)]
    }

    static func attempt(from row: Row) -> PullRequestAutoFix.Attempt? {
        guard let head = row.string("head_commit"),
              let reason = row.string("reason").flatMap(PullRequestAutoFix.Reason.init(rawValue:))
        else { return nil }
        return PullRequestAutoFix.Attempt(headCommit: head, reason: reason)
    }
}
