import Foundation

enum SessionSegmentColumns {
    static func migrate(_ db: SQLiteDatabase) throws {
        try db.execute(createTable)
        let existing = Set(try db.query("PRAGMA table_info(sessions);").compactMap { $0.string("name") })
        if !existing.contains("source_session_id") {
            try db.execute("ALTER TABLE sessions ADD COLUMN source_session_id TEXT REFERENCES sessions(id) ON DELETE SET NULL;")
        }
        if !existing.contains("source_through_seq") {
            try db.execute("ALTER TABLE sessions ADD COLUMN source_through_seq INTEGER;")
        }
        try db.execute(insertMissing)
    }

    static let createTable = """
        CREATE TABLE IF NOT EXISTS session_segments (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            agent_kind TEXT NOT NULL,
            account_id TEXT REFERENCES agent_accounts(id) ON DELETE SET NULL,
            agent_session_id TEXT,
            model TEXT NOT NULL,
            effort TEXT NOT NULL DEFAULT '',
            cursor_seq INTEGER NOT NULL DEFAULT -1,
            entered_seq INTEGER NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 0,
            input_tokens INTEGER NOT NULL DEFAULT 0,
            output_tokens INTEGER NOT NULL DEFAULT 0,
            cost_usd REAL NOT NULL DEFAULT 0,
            context_tokens INTEGER NOT NULL DEFAULT 0,
            source_received_seq INTEGER,
            created_at REAL NOT NULL,
            delta_prompt_seq INTEGER,
            cursor_before_delta_seq INTEGER
        );
        CREATE INDEX IF NOT EXISTS session_segments_session ON session_segments(session_id);
        CREATE UNIQUE INDEX IF NOT EXISTS session_segments_one_active
            ON session_segments(session_id) WHERE is_active = 1;
        """

    private static let forgetDelta = """
        delta_prompt_seq = NULL, cursor_before_delta_seq = NULL
        """

    private static let insertMissing = """
        INSERT INTO session_segments
            (id, session_id, agent_kind, account_id, agent_session_id, model, effort,
             cursor_seq, entered_seq, is_active, input_tokens, output_tokens, cost_usd,
             context_tokens, created_at)
        SELECT lower(hex(randomblob(16))), s.id, s.agent_kind, s.account_id, s.agent_session_id,
               s.model, s.effort,
               COALESCE((SELECT MAX(seq) FROM messages m WHERE m.session_id = s.id), -1),
               0, 1, s.input_tokens, s.output_tokens, s.cost_usd, s.context_tokens, s.created_at
        FROM sessions s
        WHERE NOT EXISTS (SELECT 1 FROM session_segments g WHERE g.session_id = s.id)
        """

    static let ensureFirst = insertMissing + " AND s.id = ?"

    static let forSession = "SELECT * FROM session_segments WHERE session_id = ? ORDER BY created_at, rowid"

    static let active = "SELECT * FROM session_segments WHERE session_id = ? AND is_active = 1"

    static let advance = "UPDATE session_segments SET cursor_seq = MAX(cursor_seq, ?) WHERE id = ?"

    static let reset = """
        UPDATE session_segments SET cursor_seq = -1, source_received_seq = NULL, \(forgetDelta)
        WHERE id = ? AND is_active = 1
        """

    static let clampCursors = "UPDATE session_segments SET cursor_seq = MIN(cursor_seq, ?) WHERE session_id = ?"

    static let seed = """
        UPDATE sessions SET
            source_session_id = ?1,
            source_through_seq = COALESCE((SELECT MAX(seq) FROM messages WHERE session_id = ?1), -1)
        WHERE id = ?2
        """

    static let seedThrough = """
        UPDATE sessions SET
            source_session_id = ?1,
            source_through_seq = MIN(?3, COALESCE((SELECT MAX(seq) FROM messages WHERE session_id = ?1), -1))
        WHERE id = ?2
        """

    static let pendingSource = """
        SELECT s.source_session_id, s.source_through_seq FROM sessions s
        JOIN session_segments g ON g.session_id = s.id AND g.is_active = 1
        WHERE s.id = ? AND s.source_session_id IS NOT NULL AND g.source_received_seq IS NULL
        """

    static let handoffDue = """
        SELECT 1 FROM session_segments g
        JOIN sessions s ON s.id = g.session_id
        WHERE g.session_id = ? AND g.is_active = 1 AND (
            (s.source_session_id IS NOT NULL AND g.source_received_seq IS NULL) OR EXISTS (
                SELECT 1 FROM messages m
                WHERE m.session_id = g.session_id AND m.seq > g.cursor_seq AND m.seq != ?
                    AND m.kind IN (\(ConversationHandoff.readableKinds.map { "'\($0.rawValue)'" }.joined(separator: ", ")))
            )
        )
        """

    static let acknowledge = """
        UPDATE session_segments SET
            cursor_seq = MAX(cursor_seq, COALESCE((SELECT MAX(seq) FROM messages WHERE session_id = ?), -1))
        WHERE id = ? AND is_active = 1
        """

    private static let newestPromptSeq = """
        SELECT MAX(seq) FROM messages WHERE session_id = ?1 AND (
            kind = '\(MessageKind.user.rawValue)' OR (kind = '\(MessageKind.crew.rawValue)' AND
                CASE WHEN json_valid(CAST(payload AS TEXT)) THEN json_extract(CAST(payload AS TEXT), '$.event') END
                = '\(CrewMessage.Event.appRequest.rawValue)')
        )
        """

    static let acknowledgeCarriedDelta = """
        UPDATE session_segments SET
            delta_prompt_seq = COALESCE(delta_prompt_seq, (\(newestPromptSeq)), -1),
            cursor_before_delta_seq = CASE WHEN delta_prompt_seq IS NULL THEN cursor_seq ELSE cursor_before_delta_seq END,
            source_received_seq = COALESCE(source_received_seq, (\(newestPromptSeq)), -1),
            cursor_seq = MAX(cursor_seq, COALESCE((SELECT MAX(seq) FROM messages WHERE session_id = ?1), -1))
        WHERE id = ?2 AND is_active = 1
        """

    static let restoreDelta = """
        UPDATE session_segments SET
            cursor_seq = COALESCE(cursor_before_delta_seq, -1),
            source_received_seq = CASE WHEN source_received_seq >= ?2 THEN NULL ELSE source_received_seq END,
            \(forgetDelta)
        WHERE session_id = ?1 AND is_active = 1 AND delta_prompt_seq IS NOT NULL AND delta_prompt_seq >= ?2
        """

    static let forgetHistory = """
        UPDATE session_segments SET
            agent_session_id = NULL, cursor_seq = -1, source_received_seq = NULL, \(forgetDelta)
        WHERE account_id = ?
        """

    static let forgetActiveHistory = """
        UPDATE session_segments SET
            agent_session_id = NULL, cursor_seq = -1, source_received_seq = NULL, \(forgetDelta)
        WHERE is_active = 1 AND session_id IN (SELECT id FROM sessions WHERE account_id = ?)
        """

    static let forgetChatHistory = "UPDATE sessions SET agent_session_id = NULL WHERE account_id = ?"

    static let leave = """
        UPDATE session_segments SET
            agent_kind = ?, account_id = ?, agent_session_id = ?, model = ?, effort = ?, input_tokens = ?,
            output_tokens = ?, cost_usd = ?, context_tokens = ?, is_active = 0
        WHERE id = ?
        """

    static let parked = """
        SELECT * FROM session_segments
        WHERE session_id = ? AND is_active = 0 AND agent_kind = ? AND account_id IS ?
            AND agent_session_id IS NOT NULL
        ORDER BY created_at DESC, rowid DESC LIMIT 1
        """

    static let create = """
        INSERT INTO session_segments
            (id, session_id, agent_kind, account_id, agent_session_id, model, effort,
             cursor_seq, entered_seq, is_active, created_at)
        VALUES (?, ?, ?, ?, NULL, ?, ?, -1, 0, 0, ?)
        """

    static let enter = """
        UPDATE session_segments SET
            is_active = 1, entered_seq = ?, model = ?, effort = ?, \(forgetDelta)
        WHERE id = ?
        """

    static let adopt = """
        UPDATE sessions SET
            agent_kind = ?, model = ?, effort = ?, agent_session_id = ?, input_tokens = ?,
            output_tokens = ?, cost_usd = ?, context_tokens = ?, updated_at = ?,
            state = CASE WHEN state IN ('running', 'waiting') THEN 'idle' ELSE state END
        WHERE id = ?
        """

    static func segment(from row: Row) -> SessionSegment? {
        guard let id = row.string("id"),
              let sessionID = row.string("session_id"),
              let kind = AgentKind(rawValue: row.string("agent_kind") ?? "")
        else { return nil }
        return SessionSegment(
            id: SessionSegmentID(id),
            sessionID: SessionID(sessionID),
            agentKind: kind,
            accountID: row.string("account_id").map(AgentAccountID.init),
            agentSessionID: row.string("agent_session_id"),
            model: row.string("model") ?? "",
            effort: row.string("effort") ?? "",
            cursorSeq: Int(row.int("cursor_seq") ?? -1),
            enteredSeq: Int(row.int("entered_seq") ?? 0),
            isActive: row.bool("is_active"),
            sourceReceivedSeq: row.int("source_received_seq").map(Int.init)
        )
    }
}
