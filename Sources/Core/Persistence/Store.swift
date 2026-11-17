import Foundation
import Synchronization

public actor Store {
    private let db: SQLiteDatabase
    public nonisolated let path: String
    let gitHubLoginBook: Mutex<ProfileGitHubLogins>
    private var gitHubRouteCache: (signature: String, routes: GitHubLoginRoutes)?

    public static let primaryBundleIdentifier = "io.akira.unifieddev"
    public static let devBundleIdentifier = "io.akira.unifieddev.dev"
    public static let databaseOverride = "UD_DB_PATH"

    public static func databaseDirectoryName(forBundleIdentifier identifier: String?) -> String {
        switch identifier {
        case primaryBundleIdentifier: "Unified Dev"
        case devBundleIdentifier: "Unified Dev (Dev)"
        case .some(let other) where !other.isEmpty: "Unified Dev (\(other))"
        default: "Unified Dev (unbundled)"
        }
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let name = databaseDirectoryName(forBundleIdentifier: Bundle.main.bundleIdentifier)
        return base.appendingPathComponent(name, isDirectory: true)
    }

    public static func defaultPath() throws -> String {
        if let override = LaunchOverride.value(databaseOverride) {
            let directory = (override as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            return override
        }

        let directory = defaultDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("unifieddev.sqlite")

        return destination.path
    }

    public init(path: String) throws {
        let database = try SQLiteDatabase(path: path)
        try Self.migrate(database)
        try database.transaction { try Self.seedOceans(database) }
        let sources = try ProfileGitHubColumn.sources { try database.query($0) }
        let support = URL(filePath: path).deletingLastPathComponent()
        self.path = path
        self.db = database
        self.gitHubLoginBook = Mutex(ProfileGitHubLogins(sources: sources, root: ProfileGitHubLogins.root(support: support)))
    }

    private nonisolated static func seedOceans(_ db: SQLiteDatabase) throws {
        for ocean in OceanCatalog.all {
            try db.run(
                "INSERT OR IGNORE INTO oceans (slug, name, latitude, longitude) VALUES (?, ?, ?, ?)",
                [
                    .text(ocean.slug), .text(ocean.name),
                    .double(ocean.latitude), .double(ocean.longitude),
                ]
            )
        }
    }

    public static func inMemory() throws -> Store {
        try Store(path: ":memory:")
    }

    public nonisolated func changes(
        of domains: Set<StoreDomain> = Set(StoreDomain.allCases)
    ) -> StoreChanges {
        StoreChanges(hub: db.changes, interest: domains)
    }

    nonisolated var changeHub: StoreChangeHub { db.changes }

    public enum StoreTrouble: Error, Sendable {
        case rebuildLostRows(table: String, before: Int64, after: Int64)
    }

    private typealias Migration = @Sendable (SQLiteDatabase) throws -> Void

    private nonisolated static func sql(_ statements: String) -> Migration {
        { try $0.execute(statements) }
    }

    private nonisolated static func repairSchema(_ db: SQLiteDatabase) throws {
        let required: [(table: String, column: String, add: String, index: String?)] = [
            (
                "sessions", "parent_session_id",
                "ALTER TABLE sessions ADD COLUMN parent_session_id TEXT;",
                "CREATE INDEX IF NOT EXISTS sessions_parent ON sessions(parent_session_id);"
            ),
            (
                "sessions", "side_conversation_parent_id",
                "ALTER TABLE sessions ADD COLUMN side_conversation_parent_id TEXT;",
                "CREATE INDEX IF NOT EXISTS sessions_side_parent ON sessions(side_conversation_parent_id);"
            ),
            (
                "deliveries", "crew_payload",
                "ALTER TABLE deliveries ADD COLUMN crew_payload BLOB;",
                nil
            ),
            ("workspaces", OrchestratorColumns.column, OrchestratorColumns.addColumn, OrchestratorColumns.uniqueIndex),
            ("workspaces", PullRequestSeenOpenColumn.column, PullRequestSeenOpenColumn.addColumn, nil),
            (
                "review_comments", "span",
                "ALTER TABLE review_comments ADD COLUMN span INTEGER NOT NULL DEFAULT 1;",
                nil
            ),
        ]

        for wanted in required {
            let columns = try db.query("PRAGMA table_info(\(wanted.table));")
            let names = Set(columns.compactMap { $0.string("name") })
            guard !names.isEmpty, !names.contains(wanted.column) else { continue }
            try db.execute(wanted.add)
            if let index = wanted.index { try db.execute(index) }
        }

        try AgentAccountColumns.migrate(db)
        try AgentAccountChoiceColumns.migrate(db)
        try ProfileColumns.migrate(db)
        try ProfileAccountColumns.repair(db)
        try PullRequestFixColumns.migrate(db)
    }

    private nonisolated static func migrate(_ db: SQLiteDatabase) throws {
        let current = Int(try db.readUserVersion())
        let beforeAccounts: [Migration] = [
            sql("""
            CREATE TABLE IF NOT EXISTS repos (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                path TEXT NOT NULL UNIQUE,
                default_branch TEXT NOT NULL DEFAULT 'main',
                accent TEXT NOT NULL DEFAULT '4C8DF6',
                sort_order INTEGER NOT NULL DEFAULT 0,
                collapsed INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS workspaces (
                id TEXT PRIMARY KEY,
                repo_id TEXT NOT NULL REFERENCES repos(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                branch TEXT NOT NULL,
                path TEXT NOT NULL,
                base_branch TEXT NOT NULL,
                state TEXT NOT NULL DEFAULT 'active',
                setup_state TEXT NOT NULL DEFAULT 'pending',
                setup_log TEXT NOT NULL DEFAULT '',
                sort_order INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                last_activity_at REAL NOT NULL,
                archived_at REAL,
                additions INTEGER NOT NULL DEFAULT 0,
                deletions INTEGER NOT NULL DEFAULT 0,
                changed_files INTEGER NOT NULL DEFAULT 0,
                unread INTEGER NOT NULL DEFAULT 0,
                pinned INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS workspaces_repo ON workspaces(repo_id, state);

            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                agent_session_id TEXT,
                model TEXT NOT NULL DEFAULT 'opus',
                effort TEXT NOT NULL DEFAULT 'high',
                permission_mode TEXT NOT NULL DEFAULT 'acceptEdits',
                state TEXT NOT NULL DEFAULT 'idle',
                sort_order INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                archived_at REAL,
                last_read_seq INTEGER NOT NULL DEFAULT 0,
                input_tokens INTEGER NOT NULL DEFAULT 0,
                output_tokens INTEGER NOT NULL DEFAULT 0,
                cost_usd REAL NOT NULL DEFAULT 0,
                context_tokens INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS sessions_workspace ON sessions(workspace_id);

            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                seq INTEGER NOT NULL,
                kind TEXT NOT NULL,
                payload BLOB NOT NULL,
                created_at REAL NOT NULL,
                duration_ms INTEGER,
                ref_id TEXT
            );
            CREATE INDEX IF NOT EXISTS messages_session ON messages(session_id, seq);
            CREATE INDEX IF NOT EXISTS messages_ref ON messages(session_id, ref_id);

            CREATE TABLE IF NOT EXISTS terminal_tabs (
                id TEXT PRIMARY KEY,
                workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                sort_order INTEGER NOT NULL DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS drafts (
                session_id TEXT PRIMARY KEY,
                body TEXT NOT NULL
            );
            """),

            { db in
                let duplicates = try db.query("""
                    SELECT id, session_id FROM messages
                    WHERE id NOT IN (SELECT MIN(id) FROM messages GROUP BY session_id, seq)
                    ORDER BY session_id, id
                    """)

                var nextBySession: [String: Int64] = [:]
                for row in duplicates {
                    guard let id = row.int("id"), let sessionID = row.string("session_id") else { continue }
                    let seq: Int64
                    if let known = nextBySession[sessionID] {
                        seq = known
                    } else {
                        seq = (try db.query(
                            "SELECT COALESCE(MAX(seq), -1) AS m FROM messages WHERE session_id = ?",
                            [.text(sessionID)]
                        ).first?.int("m") ?? -1) + 1
                    }
                    try db.run("UPDATE messages SET seq = ? WHERE id = ?", [.int(seq), .int(id)])
                    nextBySession[sessionID] = seq + 1
                }

                try db.execute(
                    "CREATE UNIQUE INDEX IF NOT EXISTS messages_session_seq ON messages(session_id, seq);"
                )
            },

            sql("""
            CREATE TABLE IF NOT EXISTS review_comments (
                id TEXT PRIMARY KEY,
                workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                file_path TEXT NOT NULL,
                side TEXT NOT NULL DEFAULT 'new',
                line INTEGER NOT NULL,
                line_text TEXT NOT NULL DEFAULT '',
                context_before TEXT NOT NULL DEFAULT '[]',
                context_after TEXT NOT NULL DEFAULT '[]',
                body TEXT NOT NULL,
                created_at REAL NOT NULL,
                attached INTEGER NOT NULL DEFAULT 1
            );
            CREATE INDEX IF NOT EXISTS review_comments_workspace
                ON review_comments(workspace_id, file_path, line);
            """),

            { db in
                let existing = Set(try db.query("PRAGMA table_info(repos);").compactMap { $0.string("name") })
                if !existing.contains("icon_path") {
                    try db.execute("ALTER TABLE repos ADD COLUMN icon_path TEXT;")
                }
                if !existing.contains("icon_source") {
                    try db.execute(
                        "ALTER TABLE repos ADD COLUMN icon_source TEXT NOT NULL DEFAULT 'undetected';"
                    )
                }
            },

            sql("""
            CREATE TABLE IF NOT EXISTS permission_grants (
                id TEXT PRIMARY KEY,
                repo_id TEXT NOT NULL REFERENCES repos(id) ON DELETE CASCADE,
                tool_name TEXT NOT NULL,
                rule_content TEXT NOT NULL DEFAULT '',
                granted_at REAL NOT NULL,
                last_used_at REAL,
                use_count INTEGER NOT NULL DEFAULT 0,
                granted_for TEXT NOT NULL DEFAULT ''
            );
            CREATE UNIQUE INDEX IF NOT EXISTS permission_grants_rule
                ON permission_grants(repo_id, tool_name, rule_content);

            CREATE TABLE IF NOT EXISTS permission_asks (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                tool_use_id TEXT NOT NULL DEFAULT '',
                payload BLOB NOT NULL,
                created_at REAL NOT NULL,
                resolved_at REAL,
                decision TEXT
            );
            CREATE INDEX IF NOT EXISTS permission_asks_pending
                ON permission_asks(session_id, resolved_at);
            """),

            { db in
                let existing = Set(
                    try db.query("PRAGMA table_info(sessions);").compactMap { $0.string("name") }
                )
                if !existing.contains("agent_kind") {
                    try db.execute(
                        "ALTER TABLE sessions ADD COLUMN agent_kind TEXT NOT NULL DEFAULT 'claudeCode';"
                    )
                }
            },

            { db in
                let existing = Set(
                    try db.query("PRAGMA table_info(workspaces);").compactMap { $0.string("name") }
                )
                if !existing.contains("colour") {
                    try db.execute("ALTER TABLE workspaces ADD COLUMN colour TEXT;")
                }
            },

            { db in
                let existing = Set(
                    try db.query("PRAGMA table_info(workspaces);").compactMap { $0.string("name") }
                )
                if !existing.contains("parent_workspace_id") {
                    try db.execute("ALTER TABLE workspaces ADD COLUMN parent_workspace_id TEXT;")
                }
                if !existing.contains("spawn_tool_use_id") {
                    try db.execute("ALTER TABLE workspaces ADD COLUMN spawn_tool_use_id TEXT;")
                }
                try db.execute(
                    """
                    CREATE INDEX IF NOT EXISTS workspaces_parent
                        ON workspaces(parent_workspace_id);
                    """
                )
                try db.execute(
                    """
                    CREATE INDEX IF NOT EXISTS workspaces_spawn_tool_use
                        ON workspaces(spawn_tool_use_id);
                    """
                )
            },

            sql("""
            CREATE TABLE IF NOT EXISTS deliveries (
                id TEXT PRIMARY KEY,
                target_session_id TEXT NOT NULL,
                source_workspace_id TEXT,
                kind TEXT NOT NULL DEFAULT 'owner',
                verdict TEXT,
                body TEXT NOT NULL,
                created_at REAL NOT NULL,
                delivered_at REAL,
                delivered_seq INTEGER
            );
            CREATE INDEX IF NOT EXISTS deliveries_pending
                ON deliveries(target_session_id, delivered_at);
            """),

            { db in
                try db.execute("""
                    CREATE TABLE IF NOT EXISTS oceans (
                        slug TEXT PRIMARY KEY,
                        name TEXT NOT NULL,
                        latitude REAL NOT NULL,
                        longitude REAL NOT NULL,
                        used_at REAL
                    );
                    """)
                try seedOceans(db)
            },

            { db in
                let known = Set(OceanCatalog.all.map(\.slug))
                for row in try db.query("SELECT slug FROM oceans WHERE used_at IS NULL") {
                    guard let slug = row.string("slug"), !known.contains(slug) else { continue }
                    try db.run("DELETE FROM oceans WHERE slug = ?", [.text(slug)])
                }
            },
            { db in
                try db.execute("""
                    CREATE VIRTUAL TABLE IF NOT EXISTS message_search USING fts5(
                        body,
                        tokenize = 'porter unicode61 remove_diacritics 2'
                    );

                    CREATE TRIGGER IF NOT EXISTS messages_search_delete
                    AFTER DELETE ON messages BEGIN
                        DELETE FROM message_search WHERE rowid = old.id;
                    END;
                    """)

                let highest = try db.query("SELECT COALESCE(MAX(id), 0) AS m FROM messages")
                    .first?.int("m") ?? 0
                try db.run(
                    "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                    [.text(Self.backfillCursorKey), .text(String(highest + 1))]
                )
            },

            sql("""
            CREATE TABLE IF NOT EXISTS workspace_notes (
                workspace_id TEXT PRIMARY KEY REFERENCES workspaces(id) ON DELETE CASCADE,
                body TEXT NOT NULL,
                updated_at REAL NOT NULL
            );
            """),

            { db in
                let existing = Set(
                    try db.query("PRAGMA table_info(workspaces);").compactMap { $0.string("name") }
                )
                if !existing.contains("port") {
                    try db.execute(
                        "ALTER TABLE workspaces ADD COLUMN port INTEGER NOT NULL DEFAULT 0;"
                    )
                }
            },

            { db in
                try db.execute("DELETE FROM message_search;")
                let highest = try db.query("SELECT COALESCE(MAX(id), 0) AS m FROM messages")
                    .first?.int("m") ?? 0
                try db.run(
                    "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                    [.text(Self.backfillCursorKey), .text(String(highest + 1))]
                )
            },

            sql("""
            CREATE TABLE IF NOT EXISTS agent_quotas (
                provider TEXT NOT NULL,
                window_key TEXT NOT NULL,
                window_label TEXT NOT NULL,
                window_seconds REAL,
                used REAL,
                limit_value REAL,
                unit TEXT,
                resets_at REAL,
                observed_at REAL NOT NULL,
                PRIMARY KEY (provider, window_key)
            );
            """),

            { db in
                let existing = Set(
                    try db.query("PRAGMA table_info(repos);").compactMap { $0.string("name") }
                )
                if !existing.contains("hidden") {
                    try db.execute("ALTER TABLE repos ADD COLUMN hidden INTEGER NOT NULL DEFAULT 0;")
                }
            },

            sql("""
            CREATE TABLE IF NOT EXISTS quick_prompt (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                symbol TEXT NOT NULL,
                text TEXT NOT NULL,
                sort_order INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL
            );
            """),

            { db in
                let existing = Set(
                    try db.query("PRAGMA table_info(quick_prompt);").compactMap { $0.string("name") }
                )
                if !existing.contains("sends_immediately") {
                    try db.execute("""
                        ALTER TABLE quick_prompt
                        ADD COLUMN sends_immediately INTEGER NOT NULL DEFAULT 0;
                        """)
                }
                if !existing.contains("opens_new_chat") {
                    try db.execute("""
                        ALTER TABLE quick_prompt
                        ADD COLUMN opens_new_chat INTEGER NOT NULL DEFAULT 0;
                        """)
                }
            },

            { db in
                let columns = try db.query("PRAGMA table_info(sessions);")
                let workspaceColumn = columns.first { $0.string("name") == "workspace_id" }
                guard workspaceColumn?.int("notnull") == 1 else { return }
                let carried = columns.compactMap { $0.string("name") }.contains("account_id")
                    ? ", account_id"
                    : ""

                let before = try db.query("SELECT COUNT(*) AS n FROM messages").first?.int("n") ?? 0
                try db.execute("""
                    CREATE TABLE sessions_rebuilt (
                        id TEXT PRIMARY KEY,
                        workspace_id TEXT REFERENCES workspaces(id) ON DELETE CASCADE,
                        title TEXT NOT NULL,
                        agent_session_id TEXT,
                        model TEXT NOT NULL DEFAULT 'opus',
                        effort TEXT NOT NULL DEFAULT 'high',
                        agent_kind TEXT NOT NULL DEFAULT 'claudeCode',
                        permission_mode TEXT NOT NULL DEFAULT 'acceptEdits',
                        state TEXT NOT NULL DEFAULT 'idle',
                        sort_order INTEGER NOT NULL DEFAULT 0,
                        created_at REAL NOT NULL,
                        updated_at REAL NOT NULL,
                        archived_at REAL,
                        last_read_seq INTEGER NOT NULL DEFAULT 0,
                        input_tokens INTEGER NOT NULL DEFAULT 0,
                        output_tokens INTEGER NOT NULL DEFAULT 0,
                        cost_usd REAL NOT NULL DEFAULT 0,
                        context_tokens INTEGER NOT NULL DEFAULT 0,
                        account_id TEXT REFERENCES agent_accounts(id) ON DELETE SET NULL
                    );

                    INSERT INTO sessions_rebuilt (
                        id, workspace_id, title, agent_session_id, model, effort, agent_kind,
                        permission_mode, state, sort_order, created_at, updated_at, archived_at,
                        last_read_seq, input_tokens, output_tokens, cost_usd, context_tokens\(carried)
                    )
                    SELECT
                        id, workspace_id, title, agent_session_id, model, effort, agent_kind,
                        permission_mode, state, sort_order, created_at, updated_at, archived_at,
                        last_read_seq, input_tokens, output_tokens, cost_usd, context_tokens\(carried)
                    FROM sessions;

                    DROP TABLE sessions;
                    ALTER TABLE sessions_rebuilt RENAME TO sessions;
                    CREATE INDEX IF NOT EXISTS sessions_workspace ON sessions(workspace_id);
                    """)

                let after = try db.query("SELECT COUNT(*) AS n FROM messages").first?.int("n") ?? 0
                guard after == before else {
                    throw StoreTrouble.rebuildLostRows(table: "messages", before: before, after: after)
                }
            },

            { db in
                let columns = try db.query("PRAGMA table_info(sessions);")
                let names = Set(columns.compactMap { $0.string("name") })
                if !names.contains("parent_session_id") {
                    try db.execute("ALTER TABLE sessions ADD COLUMN parent_session_id TEXT;")
                }
                try db.execute(
                    "CREATE INDEX IF NOT EXISTS sessions_parent ON sessions(parent_session_id);"
                )
            },

            { db in
                let names = Set(
                    try db.query("PRAGMA table_info(deliveries);").compactMap { $0.string("name") }
                )
                if !names.contains("crew_payload") {
                    try db.execute("ALTER TABLE deliveries ADD COLUMN crew_payload BLOB;")
                }
            },

            { db in
                let names = Set(
                    try db.query("PRAGMA table_info(workspaces);").compactMap { $0.string("name") }
                )
                if !names.contains("pull_request_number") {
                    try db.execute(
                        "ALTER TABLE workspaces ADD COLUMN pull_request_number INTEGER;"
                    )
                }
            },

            { db in
                let names = Set(
                    try db.query("PRAGMA table_info(review_comments);")
                        .compactMap { $0.string("name") }
                )
                if !names.contains("span") {
                    try db.execute(
                        "ALTER TABLE review_comments ADD COLUMN span INTEGER NOT NULL DEFAULT 1;"
                    )
                }
            },

            sql("""
            CREATE TABLE IF NOT EXISTS reviewed_files (
                workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                file_path TEXT NOT NULL,
                fingerprint TEXT NOT NULL,
                viewed_at REAL NOT NULL,
                PRIMARY KEY (workspace_id, file_path)
            );
            """),
            { db in
                let names = Set(try db.query("PRAGMA table_info(sessions);").compactMap { $0.string("name") })
                if !names.contains("side_conversation_parent_id") {
                    try db.execute("ALTER TABLE sessions ADD COLUMN side_conversation_parent_id TEXT;")
                }
                try db.execute("CREATE INDEX IF NOT EXISTS sessions_side_parent ON sessions(side_conversation_parent_id);")
                try db.execute("""
                CREATE TRIGGER IF NOT EXISTS sessions_keep_side_conversations
                AFTER UPDATE OF archived_at ON sessions
                WHEN NEW.archived_at IS NOT NULL
                BEGIN
                    UPDATE sessions SET side_conversation_parent_id = NULL
                    WHERE side_conversation_parent_id = NEW.id;
                END;
                """)
            },
            { db in
                for (table, column, definition) in [
                    ("sessions", "interaction_mode", "TEXT NOT NULL DEFAULT 'build'"),
                    ("deliveries", "interaction_mode", "TEXT"),
                    ("deliveries", "delivery_state", "TEXT NOT NULL DEFAULT 'pending'"),
                    ("deliveries", "provider_turn_id", "TEXT"),
                ] {
                    let columns = Set(try db.query("PRAGMA table_info(\(table));").compactMap { $0.string("name") })
                    if !columns.contains(column) {
                        try db.execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition);")
                        if column == "delivery_state" {
                            try db.execute("UPDATE deliveries SET delivery_state = 'accepted' WHERE delivered_at IS NOT NULL;")
                        }
                    }
                }
            },
            sql("""
            CREATE TABLE IF NOT EXISTS workspace_messages (
                id TEXT PRIMARY KEY,
                source_workspace_id TEXT,
                source_workspace_name TEXT NOT NULL DEFAULT '',
                source_project_name TEXT NOT NULL DEFAULT '',
                source_session_id TEXT,
                source_chat TEXT NOT NULL DEFAULT '',
                target_workspace_id TEXT,
                target_workspace_name TEXT NOT NULL DEFAULT '',
                target_project_name TEXT NOT NULL DEFAULT '',
                target_session_id TEXT,
                target_chat TEXT NOT NULL DEFAULT '',
                reply_session_id TEXT,
                body TEXT NOT NULL,
                delivery_id TEXT,
                state TEXT NOT NULL,
                created_at REAL NOT NULL,
                delivered_at REAL
            );
            CREATE INDEX IF NOT EXISTS workspace_messages_delivery ON workspace_messages(delivery_id);
            CREATE INDEX IF NOT EXISTS workspace_messages_route
                ON workspace_messages(source_workspace_id, target_workspace_id, state);
            """),
            sql("""
            UPDATE workspace_messages
            SET state = 'delivered',
                delivered_at = COALESCE(
                    delivered_at,
                    (SELECT deliveries.delivered_at FROM deliveries WHERE deliveries.id = delivery_id)
                )
            WHERE state = 'queued'
              AND delivery_id IN (SELECT id FROM deliveries WHERE delivery_state = 'accepted');

            UPDATE workspace_messages SET state = 'cancelled'
            WHERE state = 'queued'
              AND (delivery_id IS NULL OR delivery_id NOT IN (SELECT id FROM deliveries));
            """),
            sql("""
            CREATE TABLE IF NOT EXISTS workspace_drafts (
                repo_id TEXT PRIMARY KEY REFERENCES repos(id) ON DELETE CASCADE,
                starting_point TEXT NOT NULL,
                prompt TEXT NOT NULL DEFAULT '',
                controls TEXT,
                attachment_key TEXT NOT NULL,
                updated_at REAL NOT NULL
            );
            """),
            { db in
                let columns = Set(try db.query("PRAGMA table_info(workspace_drafts);").compactMap { $0.string("name") })
                guard !columns.contains("creating_as") else { return }
                try db.execute("ALTER TABLE workspace_drafts ADD COLUMN creating_as TEXT;")
            },
            sql(WorkSuggestionColumns.createTable),
            WorkspaceDoneWatchColumns.migrate,
            sql(SpendColumns.createTables),
            OrchestratorColumns.migrate,
            PullRequestSeenOpenColumn.migrate,
            sql(TranscriptPlaceColumns.createTable),
        ]
        let migrations: [Migration] = beforeAccounts + [
            AgentAccountColumns.migrate,
            { try AgentAccountChoiceColumns.move($0) },
            SessionSegmentColumns.migrate,
            sql(ReplyQuoteColumns.createTable),
            ProfileColumns.migrate,
            CanvasDeliveryColumn.migrate,
            AgentAccountChoiceColumns.forgetWorkspaceChoices,
            ProfileAccountColumns.migrate,
            { try PreAccountChatOwners.record($0, predatingAccounts: current <= beforeAccounts.count) },
            sql(InboxNotificationColumns.createTable),
            { try UndatedArchives.stamp($0) },
            ProfileGitHubColumn.migrate,
            QuotaAccountColumn.migrate,
            sql(TranscriptChapterColumns.createTable),
        ]

        guard current >= 0, current <= migrations.count else {
            throw SQLiteError(message: "Unsupported database schema version \(current)", sql: nil)
        }

        try repairSchema(db)

        guard current < migrations.count else { return }

        try db.execute("PRAGMA foreign_keys = OFF;")
        defer { try? db.execute("PRAGMA foreign_keys = ON;") }

        try db.transaction {
            for index in current..<migrations.count {
                try migrations[index](db)
            }
            try db.setUserVersion(Int32(migrations.count))
        }
    }

    public func agentAccounts() throws -> [AgentAccountRow] {
        try db.query(AgentAccountColumns.all).compactMap(AgentAccountColumns.account(from:))
    }

    public func add(_ account: AgentAccountRow) throws {
        try db.run(AgentAccountColumns.insert, AgentAccountColumns.values(account))
    }

    public func addIfMissing(_ account: AgentAccountRow) throws {
        try db.run(AgentAccountColumns.insertIfMissing, AgentAccountColumns.values(account))
    }

    public func forgetAgentAccount(_ id: AgentAccountID) throws {
        let stored = try db.query("SELECT is_default, provider FROM agent_accounts WHERE id = ?", [.text(id)]).first
        guard !AgentAccountHome.isDefaultID(id), stored?.bool("is_default") != true else {
            throw AgentAccountError.isDefault(id)
        }
        try db.transaction {
            let prefix = AgentSessionSettlement.lostAccountKeyPrefix
            try db.run(
                "DELETE FROM settings WHERE key LIKE ? || '%' AND substr(key, ?) NOT IN (SELECT id FROM sessions)",
                [.text(prefix), .int(Int64(prefix.count + 1))]
            )
            try db.run(
                "INSERT OR REPLACE INTO settings (key, value) SELECT ? || id, '1' FROM sessions WHERE account_id = ?",
                [.text(prefix), .text(id)]
            )
            try db.run(SessionSegmentColumns.forgetActiveHistory, [.text(id)])
            try db.run(SessionSegmentColumns.forgetChatHistory, [.text(id)])
            for table in AgentAccountColumns.pointingTables {
                try db.run(AgentAccountColumns.release(table), [.text(id)])
            }
            try db.run(SessionSegmentColumns.forgetHistory, [.text(id)])
            try db.run(AgentAccountColumns.release("session_segments"), [.text(id)])
            try db.run(AgentAccountColumns.delete, [.text(id)])
            if let provider = stored?.string("provider") {
                try db.run(QuotaAccountColumn.forget, [.text(provider), .text(id)])
            }
            for key in ClaudeResolvedModel.settingKeys(account: id) {
                try db.run("DELETE FROM settings WHERE key = ?", [.text(key)])
            }
        }
    }

    public func segments(sessionID: SessionID) throws -> [SessionSegment] {
        try db.query(SessionSegmentColumns.forSession, [.text(sessionID)])
            .compactMap(SessionSegmentColumns.segment(from:))
    }

    public func activeSegment(sessionID: SessionID) throws -> SessionSegment? {
        try db.query(SessionSegmentColumns.active, [.text(sessionID)])
            .compactMap(SessionSegmentColumns.segment(from:)).first
    }

    public func runnerSeat(sessionID: SessionID) throws -> RunnerSeat? {
        guard let session = try session(id: sessionID),
              let segment = try activeSegment(sessionID: sessionID) else { return nil }
        return RunnerSeat(
            session: session,
            segmentID: segment.id,
            lostItsAccount: try setting(AgentSessionSettlement.lostAccountKey(sessionID: sessionID)) != nil
        )
    }

    public func advanceCursor(segmentID: SessionSegmentID, toSeq: Int) throws {
        try db.run(SessionSegmentColumns.advance, [.int(Int64(toSeq)), .text(segmentID)])
    }

    public func resetCursor(segmentID: SessionSegmentID) throws {
        try db.run(SessionSegmentColumns.reset, [.text(segmentID)])
    }

    public func seed(sessionID: SessionID, from source: SessionID, through seq: Int? = nil) throws {
        guard let seq else {
            try db.run(SessionSegmentColumns.seed, [.text(source), .text(sessionID)])
            return
        }
        try db.run(SessionSegmentColumns.seedThrough, [.text(source), .text(sessionID), .int(Int64(seq))])
    }

    public func pendingSource(sessionID: SessionID) throws -> SessionID? {
        try pendingSourceRead(sessionID: sessionID)?.id
    }

    func pendingSourceRead(sessionID: SessionID) throws -> (id: SessionID, throughSeq: Int)? {
        guard let row = try db.query(SessionSegmentColumns.pendingSource, [.text(sessionID)]).first,
              let id = row.string("source_session_id").map(SessionID.init) else { return nil }
        return (id, Int(row.int("source_through_seq") ?? -1))
    }

    @discardableResult
    public func switchSegment(sessionID: SessionID, to target: SessionSegmentTarget) throws -> Session {
        try db.transaction {
            guard let current = try session(id: sessionID) else {
                throw SQLiteError(message: "no such chat to switch", sql: nil)
            }
            try db.run(SessionSegmentColumns.ensureFirst, [.text(sessionID)])
            guard let active = try activeSegment(sessionID: sessionID) else {
                throw SQLiteError(message: "chat has no active segment", sql: nil)
            }
            if current.agentKind == target.agentKind, current.accountID == target.accountID {
                return current
            }
            try db.run(SessionSegmentColumns.leave, [
                .text(current.agentKind.rawValue), .text(current.accountID),
                current.agentSessionID.map { .text($0) } ?? .null,
                .text(current.model), .text(current.effort),
                .int(Int64(current.inputTokens)), .int(Int64(current.outputTokens)),
                .double(current.costUSD), .int(Int64(current.contextTokens)),
                .text(active.id),
            ])
            let entering = try enteringSegment(sessionID: sessionID, target: target)
            try db.run(SessionSegmentColumns.adopt, [
                .text(target.agentKind.rawValue), .text(target.model), .text(target.effort),
                entering.agentSessionID.map { .text($0) } ?? .null,
                .int(entering.inputTokens), .int(entering.outputTokens),
                .double(entering.costUSD), .int(entering.contextTokens),
                .double(Date().timeIntervalSince1970), .text(sessionID),
            ])
            try db.run(AgentAccountColumns.choose("sessions"), [.text(target.accountID), .text(sessionID)])
            try setSetting(ComposerControls.defaultsAppliedKey(sessionID: sessionID), "1")
            try setSetting(AgentSessionSettlement.lostAccountKey(sessionID: sessionID), nil)
            let divider = try insertNext(
                sessionID: sessionID,
                kind: .handoff,
                payload: HandoffMark.continued(
                    agent: target.agentKind, model: target.model, from: current.agentKind, account: target.accountName
                ).payload
            )
            try db.run(SessionSegmentColumns.enter, [
                .int(Int64(divider.seq)), .text(target.model), .text(target.effort), .text(entering.id),
            ])
            guard let switched = try session(id: sessionID) else {
                throw SQLiteError(message: "chat vanished during the switch", sql: nil)
            }
            return switched
        }
    }

    private struct EnteringSegment {
        var id: SessionSegmentID
        var agentSessionID: String?
        var inputTokens: Int64
        var outputTokens: Int64
        var costUSD: Double
        var contextTokens: Int64
    }

    private func enteringSegment(sessionID: SessionID, target: SessionSegmentTarget) throws -> EnteringSegment {
        let rows = try db.query(SessionSegmentColumns.parked, [
            .text(sessionID), .text(target.agentKind.rawValue), .text(target.accountID),
        ])
        if let row = rows.first, let id = row.string("id").map(SessionSegmentID.init) {
            return EnteringSegment(
                id: id,
                agentSessionID: row.string("agent_session_id"),
                inputTokens: row.int("input_tokens") ?? 0,
                outputTokens: row.int("output_tokens") ?? 0,
                costUSD: row.double("cost_usd") ?? 0,
                contextTokens: row.int("context_tokens") ?? 0
            )
        }
        let id = SessionSegmentID(newID())
        try db.run(SessionSegmentColumns.create, [
            .text(id), .text(sessionID), .text(target.agentKind.rawValue), .text(target.accountID),
            .text(target.model), .text(target.effort), .double(Date().timeIntervalSince1970),
        ])
        return EnteringSegment(id: id, agentSessionID: nil, inputTokens: 0, outputTokens: 0, costUSD: 0, contextTokens: 0)
    }

    private func insertNext(sessionID: SessionID, kind: MessageKind, payload: Data) throws -> Message {
        var message = Message(
            sessionID: sessionID, seq: try nextSeqLocked(sessionID: sessionID), kind: kind, payload: payload
        )
        message.id = try insert(message)
        return message
    }

    public func agentAccountChoices() throws -> AgentAccountChoiceBook {
        try AgentAccountChoiceColumns.book { try db.query($0) }
    }

    public func chooseAgentAccount(_ chosen: ChosenAgentAccount, forRepo id: RepoID) throws {
        try choose(chosen, owner: id.rawValue, in: AgentAccountChoiceColumns.repos)
    }

    public func chooseAgentAccount(_ chosen: ChosenAgentAccount, forProfile id: ProfileID) throws {
        try choose(chosen, owner: id.rawValue, in: AgentAccountChoiceColumns.profiles)
    }

    public func profileAccounts() throws -> ProfileAccounts {
        try ProfileAccountColumns.accounts { try db.query($0) }
    }

    @discardableResult
    public func setAccountSource(_ source: ProfileAccountSource, for profile: ProfileID) throws -> [RepoID] {
        try db.transaction { try writeAccountSource(source, for: profile) }
    }

    func gitHubLoginRoutes() throws -> GitHubLoginRoutes {
        let rows = try db.query(
            """
            SELECT path, profile_id FROM repos
            UNION ALL
            SELECT workspaces.path, repos.profile_id FROM workspaces JOIN repos ON repos.id = workspaces.repo_id
            ORDER BY 1, 2
            """
        )
        let pairs = rows.compactMap { row -> (String, String)? in
            guard let path = row.string("path"), let profile = row.string("profile_id") else { return nil }
            return (path, profile)
        }
        let signature = pairs.map { $0.0 + "\u{0}" + $0.1 }.joined(separator: "\n")
        if let cached = gitHubRouteCache, cached.signature == signature { return cached.routes }
        let routes = GitHubLoginRoutes(routes: pairs.flatMap { path, profile -> [GitHubLoginRoutes.Route] in
            let resolved = URL(filePath: path).resolvingSymlinksInPath().path
            return Set([path, resolved]).map { GitHubLoginRoutes.Route(path: $0, profile: ProfileID(profile)) }
        })
        gitHubRouteCache = (signature, routes)
        return routes
    }

    func refreshGitHubLogins() throws {
        let sources = try ProfileGitHubColumn.sources { try db.query($0) }
        gitHubLoginBook.withLock { $0 = ProfileGitHubLogins(sources: sources, root: $0.root) }
    }

    func writeGitHubSource(_ source: ProfileGitHubSource, for profile: ProfileID) throws {
        try db.run(ProfileGitHubColumn.setSource, [.text(source.rawValue), .text(profile)])
        try refreshGitHubLogins()
    }

    func writeAccountSource(_ source: ProfileAccountSource, for profile: ProfileID) throws -> [RepoID] {
        guard profile != .initial else { return [] }
        try db.run(ProfileAccountColumns.setSource, [.text(source.rawValue), .text(profile)])
        return try clearStrayChoices(in: profile)
    }

    func clearStrayChoices(in profile: ProfileID, only repo: RepoID? = nil) throws -> [RepoID] {
        let book = try agentAccountChoices()
        var cleared: [RepoID] = []
        for (id, owner) in book.repoProfiles.sorted(by: { $0.key.rawValue < $1.key.rawValue })
        where owner == profile && (repo == nil || repo == id) {
            let stray = book.accounts.strayChoices(book.repos[id] ?? [:], in: profile)
            for provider in stray {
                try db.run(AgentAccountChoiceColumns.repos.clear, [.text(id), .text(provider.rawValue)])
            }
            if !stray.isEmpty { cleared.append(id) }
        }
        return cleared
    }

    func returnAccountsToInitial(from profile: ProfileID) throws {
        try db.run(ProfileAccountColumns.returnToInitial, [.text(profile)])
    }

    public func pullRequestFixLedger(
        workspaceID: WorkspaceID, number: Int
    ) throws -> PullRequestAutoFix.Ledger {
        let key = PullRequestFixColumns.key(workspaceID, number)
        let run = try db.query(PullRequestFixColumns.run, key).first
        let tried = try db.query(PullRequestFixColumns.attempts, key).compactMap(PullRequestFixColumns.attempt)
        return PullRequestAutoFix.Ledger(
            inARow: run?.int("in_a_row").map(Int.init) ?? 0,
            tried: Set(tried),
            stopAnnounced: run?.date("stop_announced_at") != nil
        )
    }

    public func claimPullRequestFix(
        _ attempt: PullRequestAutoFix.Attempt,
        workspaceID: WorkspaceID,
        number: Int,
        at date: Date = Date()
    ) throws -> Bool {
        let key = PullRequestFixColumns.key(workspaceID, number)
        return try inTransaction {
            _ = try db.run(PullRequestFixColumns.openRun, key)
            let inARow = try db.query(PullRequestFixColumns.run, key).first?.int("in_a_row") ?? 0
            guard inARow < PullRequestAutoFix.attemptsInARow else { return false }
            let values = PullRequestFixColumns.values(attempt)
            _ = try db.run(PullRequestFixColumns.insertAttempt, key + values + [.double(date.timeIntervalSince1970)])
            guard db.changedRowCount > 0 else { return false }
            _ = try db.run(PullRequestFixColumns.count, key)
            return true
        }
    }

    public func releasePullRequestFix(
        _ attempt: PullRequestAutoFix.Attempt, workspaceID: WorkspaceID, number: Int
    ) throws {
        let key = PullRequestFixColumns.key(workspaceID, number)
        try inTransaction {
            _ = try db.run(PullRequestFixColumns.deleteAttempt, key + PullRequestFixColumns.values(attempt))
            guard db.changedRowCount > 0 else { return }
            _ = try db.run(PullRequestFixColumns.uncount, key)
        }
    }

    public func forgivePullRequestFixRun(workspaceID: WorkspaceID, number: Int) throws {
        _ = try db.run(PullRequestFixColumns.forgive, PullRequestFixColumns.key(workspaceID, number))
    }

    public func claimPullRequestFixStopNotice(
        workspaceID: WorkspaceID, number: Int, at date: Date = Date()
    ) throws -> Bool {
        let key = PullRequestFixColumns.key(workspaceID, number)
        return try inTransaction {
            _ = try db.run(PullRequestFixColumns.openRun, key)
            _ = try db.run(PullRequestFixColumns.announceStop, [.double(date.timeIntervalSince1970)] + key)
            return db.changedRowCount > 0
        }
    }

    func inTransaction<T>(_ work: () throws -> T) throws -> T {
        try db.transaction(work)
    }

    private func choose(
        _ chosen: ChosenAgentAccount,
        owner: String,
        in table: AgentAccountChoiceColumns.Table
    ) throws {
        guard let account = chosen.home?.id else {
            try db.run(table.clear, [.text(owner), .text(chosen.provider.rawValue)])
            return
        }
        try db.run(table.choose, [.text(owner), .text(chosen.provider.rawValue), .text(account)])
    }

    public func update(sessionID: SessionID, accountID: AgentAccountID?) throws {
        try db.run(AgentAccountColumns.choose("sessions"), [.text(accountID), .text(sessionID)])
    }

    public func profiles() throws -> [Profile] {
        try db.query(ProfileColumns.all).map(ProfileColumns.profile(from:))
    }

    public func profile(id: ProfileID) throws -> Profile? {
        try db.query(ProfileColumns.one, [.text(id)]).first.map(ProfileColumns.profile(from:))
    }

    func insertProfileRow(_ profile: Profile) throws {
        try db.run(ProfileColumns.insert, ProfileColumns.values(profile))
    }

    func writeProfileRow(_ profile: Profile) throws {
        try db.run(ProfileColumns.update, ProfileColumns.updateValues(profile))
    }

    func removeProfileRow(id: ProfileID) throws {
        try db.run(ProfileColumns.delete, [.text(id)])
    }

    func projectCount(profileID: ProfileID) throws -> Int {
        Int(try db.query(ProfileColumns.repoCount, [.text(profileID)]).first?.int("total") ?? 0)
    }

    public func repos() throws -> [Repo] {
        try db.query("SELECT * FROM repos ORDER BY sort_order, created_at").map(Self.repo(from:))
    }

    public func projectActivity() throws -> [RepoID: Date] {
        let rows = try db.query(
            """
            SELECT repo_id, MAX(last_activity_at) AS activity FROM workspaces
            WHERE parent_workspace_id IS NULL
            GROUP BY repo_id
            """
        )

        return rows.reduce(into: [:]) { activity, row in
            guard let id = row.string("repo_id"), let last = row.date("activity") else { return }
            activity[RepoID(id)] = last
        }
    }

    public func repo(id: RepoID) throws -> Repo? {
        try db.query("SELECT * FROM repos WHERE id = ?", [.text(id)]).first.map(Self.repo(from:))
    }

    public func repo(path: String) throws -> Repo? {
        try db.query("SELECT * FROM repos WHERE path = ?", [.text(path)]).first.map(Self.repo(from:))
    }

    @discardableResult
    public func upsert(_ repo: Repo) throws -> Repo {
        try db.run(
            """
            INSERT INTO repos (
                id, name, path, default_branch, accent, sort_order, collapsed, hidden, created_at,
                icon_path, icon_source, profile_id
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, COALESCE((SELECT id FROM profiles WHERE id = ?), ?))
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                path = excluded.path,
                default_branch = excluded.default_branch,
                accent = excluded.accent,
                sort_order = excluded.sort_order,
                collapsed = excluded.collapsed,
                hidden = excluded.hidden,
                icon_path = excluded.icon_path,
                icon_source = excluded.icon_source,
                profile_id = excluded.profile_id
            """,
            [
                .text(repo.id), .text(repo.name), .text(repo.path), .text(repo.defaultBranch),
                .text(repo.accent), .int(Int64(repo.sortOrder)), .int(repo.collapsed ? 1 : 0),
                .int(repo.hidden ? 1 : 0),
                .double(repo.createdAt.timeIntervalSince1970),
                repo.iconPath.map { SQLValue.text($0) } ?? .null,
                .text(repo.iconSource.rawValue),
                .text(repo.profileID),
                .text(ProfileID.initial.rawValue),
            ]
        )
        return try self.repo(id: repo.id) ?? repo
    }

    @discardableResult
    public func update(
        repoID: RepoID,
        _ change: @Sendable (inout Repo) -> Void
    ) throws -> Repo? {
        guard var row = try repo(id: repoID) else { return nil }
        change(&row)
        row.id = repoID
        return try upsert(row)
    }

    public func reorderProjects(_ changes: [SidebarReorder.ProjectChange]) throws {
        guard !changes.isEmpty else { return }
        try db.transaction {
            for change in changes {
                try db.run(
                    "UPDATE repos SET sort_order = ? WHERE id = ?",
                    [.int(Int64(change.sortOrder)), .text(change.id)]
                )
            }
        }
    }

    public func deleteRepo(id: RepoID) throws {
        try requireRepoCanBeRemoved(id: id)
        try db.run("DELETE FROM repos WHERE id = ?", [.text(id)])
    }

    public func requireRepoCanBeRemoved(id: RepoID) throws {
        for workspace in try workspaces(repoID: id, includeArchived: true) {
            try requireWorkspaceCanBeRemoved(id: workspace.id)
        }
    }

    public func requireWorkspaceCanBeRemoved(id: WorkspaceID) throws {
        guard try pendingCheckpointRewind(workspaceID: id) == nil else { throw WorkspaceError.recoveryPending }
    }

    public func workspaces(includeArchived: Bool = false) throws -> [Workspace] {
        let sql = includeArchived
            ? "SELECT * FROM workspaces ORDER BY sort_order, created_at"
            : "SELECT * FROM workspaces WHERE state = 'active' ORDER BY sort_order, created_at"
        return try db.query(sql).map(Self.workspace(from:))
    }

    public func workspaces(repoID: RepoID, includeArchived: Bool = false) throws -> [Workspace] {
        let sql = includeArchived
            ? "SELECT * FROM workspaces WHERE repo_id = ? ORDER BY sort_order, created_at"
            : "SELECT * FROM workspaces WHERE repo_id = ? AND state = 'active' ORDER BY sort_order, created_at"
        return try db.query(sql, [.text(repoID)]).map(Self.workspace(from:))
    }

    public func workspacePaths() throws -> [String] {
        try db.query("SELECT path FROM workspaces").compactMap { $0.string("path") }
    }

    public func workspace(id: WorkspaceID) throws -> Workspace? {
        try db.query("SELECT * FROM workspaces WHERE id = ?", [.text(id)]).first.map(Self.workspace(from:))
    }

    @discardableResult
    public func upsert(_ workspace: Workspace) throws -> Workspace {
        try db.run(
            """
            INSERT INTO workspaces (
                id, repo_id, name, branch, path, base_branch, state, setup_state, setup_log,
                sort_order, created_at, last_activity_at, archived_at,
                additions, deletions, changed_files, unread, pinned, colour,
                parent_workspace_id, spawn_tool_use_id, port, pull_request_number, is_orchestrator
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                branch = excluded.branch,
                path = excluded.path,
                base_branch = excluded.base_branch,
                state = excluded.state,
                setup_state = excluded.setup_state,
                setup_log = excluded.setup_log,
                sort_order = excluded.sort_order,
                last_activity_at = excluded.last_activity_at,
                archived_at = excluded.archived_at,
                additions = excluded.additions,
                deletions = excluded.deletions,
                changed_files = excluded.changed_files,
                unread = excluded.unread,
                pinned = excluded.pinned,
                colour = excluded.colour,
                parent_workspace_id = excluded.parent_workspace_id,
                spawn_tool_use_id = excluded.spawn_tool_use_id,
                port = excluded.port,
                pull_request_number = excluded.pull_request_number,
                is_orchestrator = excluded.is_orchestrator
            """,
            [
                .text(workspace.id), .text(workspace.repoID), .text(workspace.name),
                .text(workspace.branch), .text(workspace.path), .text(workspace.baseBranch),
                .text(workspace.state.rawValue), .text(workspace.setupState.rawValue),
                .text(workspace.setupLog), .int(Int64(workspace.sortOrder)),
                .double(workspace.createdAt.timeIntervalSince1970),
                .double(workspace.lastActivityAt.timeIntervalSince1970),
                workspace.archivedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
                .int(Int64(workspace.additions)), .int(Int64(workspace.deletions)),
                .int(Int64(workspace.changedFiles)),
                .int(workspace.unread ? 1 : 0),
                .int(OrchestratorRole.pinned(workspace.pinned, isOrchestrator: workspace.isOrchestrator) ? 1 : 0),
                workspace.colour.map { .text($0) } ?? .null,
                workspace.origin.parentWorkspaceID.map { .text($0) } ?? .null,
                workspace.origin.spawnToolUseID.map { .text($0) } ?? .null,
                .int(Int64(workspace.port)),
                workspace.pullRequestNumber.map { .int(Int64($0)) } ?? .null,
                .int(workspace.isOrchestrator ? 1 : 0),
            ]
        )
        return workspace
    }

    @discardableResult
    public func update(
        workspaceID: WorkspaceID,
        _ change: @Sendable (inout Workspace) -> Void
    ) throws -> Workspace? {
        guard var row = try workspace(id: workspaceID) else { return nil }
        change(&row)
        row.id = workspaceID
        return try upsert(row)
    }

    public func reorderWorkspaces(_ changes: [SidebarReorder.Change]) throws {
        guard !changes.isEmpty else { return }
        try db.transaction {
            for change in changes {
                try db.run(
                    """
                    UPDATE workspaces SET sort_order = ?,
                        pinned = CASE WHEN is_orchestrator = 1 THEN 1 ELSE ? END
                    WHERE id = ?
                    """,
                    [
                        .int(Int64(change.sortOrder)), .int(change.pinned ? 1 : 0),
                        .text(change.id),
                    ]
                )
            }
        }
    }

    public func deleteWorkspace(id: WorkspaceID) throws {
        try requireWorkspaceCanBeRemoved(id: id)
        try db.run("DELETE FROM workspaces WHERE id = ?", [.text(id)])
    }

    public func archivedFootprints() async throws -> [ArchivedWorkspaceFootprint] {
        try await archivedFootprints(betweenBatches: { await Task.yield() })
    }

    func archivedFootprints(
        betweenBatches pause: @Sendable () async -> Void
    ) async throws -> [ArchivedWorkspaceFootprint] {
        let rows = try db.query("""
            SELECT w.*, r.name AS repo_name
            FROM workspaces w
            JOIN repos r ON r.id = w.repo_id
            WHERE w.state = 'archived'
            """)
        guard !rows.isEmpty else { return [] }

        var sessions: [String: Int] = [:]
        for row in try db.query("SELECT workspace_id, COUNT(*) AS n FROM sessions GROUP BY workspace_id") {
            sessions[row.string("workspace_id") ?? ""] = Int(row.int("n") ?? 0)
        }

        let messages = try await archivedTranscriptSizes(betweenBatches: pause)

        var comments: [String: (count: Int, bytes: Int)] = [:]
        for row in try db.query("""
            SELECT workspace_id, COUNT(*) AS n,
                   COALESCE(SUM(LENGTH(body) + LENGTH(line_text) + LENGTH(context_before)
                                 + LENGTH(context_after) + LENGTH(file_path)), 0) AS bytes
            FROM review_comments GROUP BY workspace_id
            """) {
            comments[row.string("workspace_id") ?? ""] = (Int(row.int("n") ?? 0), Int(row.int("bytes") ?? 0))
        }

        var notes: [String: Int] = [:]
        for row in try db.query("SELECT workspace_id, LENGTH(body) AS bytes FROM workspace_notes") {
            notes[row.string("workspace_id") ?? ""] = Int(row.int("bytes") ?? 0)
        }

        var asks: [String: Int] = [:]
        for row in try db.query("""
            SELECT s.workspace_id AS wid, COALESCE(SUM(LENGTH(p.payload)), 0) AS bytes
            FROM permission_asks p JOIN sessions s ON s.id = p.session_id
            GROUP BY s.workspace_id
            """) {
            asks[row.string("wid") ?? ""] = Int(row.int("bytes") ?? 0)
        }

        return rows.map { row in
            let workspace = Self.workspace(from: row)
            let key = workspace.id.rawValue
            let comment = comments[key] ?? (0, 0)
            let note = notes[key] ?? 0
            return ArchivedWorkspaceFootprint(
                workspace: workspace,
                repoName: row.string("repo_name") ?? "",
                sessionCount: sessions[key] ?? 0,
                messageCount: messages[key]?.count ?? 0,
                transcriptBytes: messages[key]?.bytes ?? 0,
                otherBytes: comment.1 + note + (asks[key] ?? 0) + workspace.setupLog.utf8.count,
                reviewCommentCount: comment.0,
                hasNote: note > 0
            )
        }
    }

    private func archivedTranscriptSizes(
        betweenBatches pause: @Sendable () async -> Void
    ) async throws -> [String: (count: Int, bytes: Int)] {
        var sizes: [String: (count: Int, bytes: Int)] = [:]
        for session in try db.query("""
            SELECT s.id AS sid, s.workspace_id AS wid
            FROM sessions s JOIN workspaces w ON w.id = s.workspace_id
            WHERE w.state = 'archived'
            """) {
            let total = try await transcriptSize(of: session.string("sid") ?? "", betweenBatches: pause)
            let workspaceID = session.string("wid") ?? ""
            let sum = sizes[workspaceID] ?? (0, 0)
            sizes[workspaceID] = (sum.count + total.count, sum.bytes + total.bytes)
        }
        return sizes
    }

    private func transcriptSize(
        of sessionID: String,
        betweenBatches pause: @Sendable () async -> Void
    ) async throws -> (count: Int, bytes: Int) {
        var total = (count: 0, bytes: 0)
        var lastSeq = Int64.min
        while true {
            let batch = try db.query("""
                SELECT COUNT(*) AS n, COALESCE(SUM(size), 0) AS bytes, MAX(seq) AS last FROM (
                    SELECT seq, LENGTH(payload) AS size FROM messages
                    WHERE session_id = ? AND seq > ? ORDER BY seq LIMIT ?
                )
                """,
                [.text(sessionID), .int(lastSeq), .int(Int64(ArchivedWorkspaceFootprint.measuringBatch))]
            ).first
            let read = Int(batch?.int("n") ?? 0)
            total.count += read
            total.bytes += Int(batch?.int("bytes") ?? 0)
            lastSeq = batch?.int("last") ?? lastSeq
            await pause()
            if read < ArchivedWorkspaceFootprint.measuringBatch { return total }
        }
    }

    @discardableResult
    public func deleteArchivedWorkspaces(ids: [WorkspaceID]) throws -> [WorkspaceID] {
        guard !ids.isEmpty else { return [] }
        return try db.transaction {
            var deleted: [WorkspaceID] = []
            for id in ids {
                let isArchived = try db.query(
                    "SELECT 1 AS ok FROM workspaces WHERE id = ? AND state = 'archived' AND is_orchestrator = 0",
                    [.text(id)]
                ).first != nil
                guard isArchived else { continue }
                try requireWorkspaceCanBeRemoved(id: id)

                try db.run(
                    "DELETE FROM drafts WHERE session_id IN (SELECT id FROM sessions WHERE workspace_id = ?)",
                    [.text(id)]
                )
                try db.run(
                    """
                    UPDATE workspace_messages SET state = 'cancelled'
                    WHERE state = 'queued' AND delivery_id IN (
                        SELECT id FROM deliveries
                        WHERE source_workspace_id = ?
                           OR target_session_id IN (SELECT id FROM sessions WHERE workspace_id = ?)
                    )
                    """,
                    [.text(id), .text(id)]
                )
                try db.run(
                    """
                    DELETE FROM deliveries
                    WHERE source_workspace_id = ?
                       OR target_session_id IN (SELECT id FROM sessions WHERE workspace_id = ?)
                    """,
                    [.text(id), .text(id)]
                )
                try db.run("DELETE FROM workspaces WHERE id = ?", [.text(id)])
                deleted.append(id)
            }
            return deleted
        }
    }

    public func workspacesHoldingUndeliveredMessages() throws -> Set<WorkspaceID> {
        let rows = try db.query("""
            SELECT DISTINCT d.source_workspace_id AS id
            FROM deliveries d
            JOIN sessions s ON s.id = d.target_session_id
            JOIN workspaces target ON target.id = s.workspace_id
            WHERE d.delivered_at IS NULL
              AND d.source_workspace_id IS NOT NULL
              AND s.archived_at IS NULL
              AND target.state = 'active'
            """)
        return Set(rows.compactMap { $0.string("id").map { WorkspaceID($0) } })
    }

    public func databaseSize() throws -> DatabaseSize {
        let pageSize = Int(try db.query("PRAGMA page_size;").first?.int("page_size") ?? 0)
        let pages = Int(try db.query("PRAGMA page_count;").first?.int("page_count") ?? 0)
        let free = Int(try db.query("PRAGMA freelist_count;").first?.int("freelist_count") ?? 0)
        return DatabaseSize(pageSize: pageSize, pageCount: pages, freePageCount: free)
    }

    public func compactDatabase() throws {
        try db.execute("VACUUM;")
        try db.execute("PRAGMA wal_checkpoint(TRUNCATE);")
    }

    public func updateDiffStat(workspaceID: WorkspaceID, additions: Int, deletions: Int, files: Int) throws {
        let current = try db.query(
            "SELECT additions, deletions, changed_files FROM workspaces WHERE id = ?",
            [.text(workspaceID)]
        ).first
        if let current,
           current.int("additions") == Int64(additions),
           current.int("deletions") == Int64(deletions),
           current.int("changed_files") == Int64(files) {
            return
        }
        try db.run(
            "UPDATE workspaces SET additions = ?, deletions = ?, changed_files = ? WHERE id = ?",
            [.int(Int64(additions)), .int(Int64(deletions)), .int(Int64(files)), .text(workspaceID)],
            publishing: [.workspaces: .diffStats]
        )
    }

    public func diffStats() throws -> [WorkspaceID: WorkspaceDiffStat] {
        let rows = try db.query("SELECT id, additions, deletions, changed_files FROM workspaces WHERE state = 'active'")
        var stats: [WorkspaceID: WorkspaceDiffStat] = [:]
        for row in rows {
            guard let id = row.string("id") else { continue }
            stats[WorkspaceID(id)] = WorkspaceDiffStat(
                additions: Int(row.int("additions") ?? 0),
                deletions: Int(row.int("deletions") ?? 0),
                files: Int(row.int("changed_files") ?? 0)
            )
        }
        return stats
    }

    public func updateCheckedOutBranch(_ branch: String, observed: Workspace) throws {
        guard observed.state == .active, branch != observed.branch,
              branch != "HEAD", Git.isValidBranchName(branch),
              let current = try workspace(id: observed.id),
              current.state == .active, current.path == observed.path,
              current.branch == observed.branch, branch != current.baseBranch,
              let project = try repo(id: current.repoID), branch != project.defaultBranch else { return }
        try db.run(
            "UPDATE workspaces SET branch = ? WHERE id = ?",
            [.text(branch), .text(observed.id)]
        )
    }

    public func recordPullRequestNumber(_ number: Int, workspaceID: WorkspaceID) throws {
        guard number > 0 else { return }
        guard let current = try db.query(
            "SELECT pull_request_number FROM workspaces WHERE id = ?", [.text(workspaceID)]
        ).first else { return }
        if current.int("pull_request_number").map(Int.init) == number { return }

        try db.run(
            "UPDATE workspaces SET pull_request_number = ? WHERE id = ?",
            [.int(Int64(number)), .text(workspaceID)]
        )
    }

    public func recordPullRequestSeenOpen(_ number: Int?, workspaceID: WorkspaceID) throws {
        guard let current = try db.query(
            "SELECT pull_request_seen_open, state FROM workspaces WHERE id = ?", [.text(workspaceID)]
        ).first else { return }
        if number != nil, current.string("state") == WorkspaceState.archived.rawValue { return }
        if current.int("pull_request_seen_open").map(Int.init) == number { return }

        try db.run(
            "UPDATE workspaces SET pull_request_seen_open = ? WHERE id = ?",
            [number.map { .int(Int64($0)) } ?? .null, .text(workspaceID)]
        )
    }

    public func takePullRequestSeenOpen(_ number: Int, workspaceID: WorkspaceID) throws -> Bool {
        guard try pullRequestSeenOpen(workspaceID: workspaceID) == number else { return false }
        try recordPullRequestSeenOpen(nil, workspaceID: workspaceID)
        return true
    }

    public func pullRequestSeenOpen(workspaceID: WorkspaceID) throws -> Int? {
        try db.query(
            "SELECT pull_request_seen_open FROM workspaces WHERE id = ?", [.text(workspaceID)]
        ).first?.int("pull_request_seen_open").map(Int.init)
    }

    public func touch(workspaceID: WorkspaceID, unread: Bool? = nil, at moment: Date = Date()) throws {
        if let unread {
            try db.run(
                "UPDATE workspaces SET last_activity_at = ?, unread = ? WHERE id = ?",
                [.double(moment.timeIntervalSince1970), .int(unread ? 1 : 0), .text(workspaceID)]
            )
        } else {
            try db.run(
                "UPDATE workspaces SET last_activity_at = ? WHERE id = ?",
                [.double(moment.timeIntervalSince1970), .text(workspaceID)]
            )
        }
    }

    public func recoverInterruptedSetups() throws {
        let event = SetupEvent.runInterrupted
        var sources: [SetupState] = []
        var destination: SetupState?
        for state in SetupState.allCases {
            guard case .moves(let next) = state.transition(on: event) else { continue }
            sources.append(state)
            destination = next
        }
        guard let destination, !sources.isEmpty, let note = event.note else { return }

        let placeholders = sources.map { _ in "?" }.joined(separator: ", ")
        try db.run(
            """
            UPDATE workspaces
            SET setup_state = ?,
                setup_log = CASE WHEN setup_log = '' THEN ? ELSE setup_log || char(10) || ? END
            WHERE setup_state IN (\(placeholders))
            """,
            [.text(destination.rawValue), .text(note), .text(note)]
                + sources.map { SQLValue.text($0.rawValue) }
        )
    }

    public func workspaces(startedBy parentWorkspaceID: WorkspaceID, includeArchived: Bool = false) throws -> [Workspace] {
        let sql = includeArchived
            ? "SELECT * FROM workspaces WHERE parent_workspace_id = ? ORDER BY created_at"
            : "SELECT * FROM workspaces WHERE parent_workspace_id = ? AND state = 'active' ORDER BY created_at"
        return try db.query(sql, [.text(parentWorkspaceID)]).map(Self.workspace(from:))
    }

    public func countWorkspaces(startedBy parentWorkspaceID: WorkspaceID) throws -> Int {
        let rows = try db.query(
            "SELECT COUNT(*) AS n FROM workspaces WHERE parent_workspace_id = ?",
            [.text(parentWorkspaceID)]
        )
        return Int(rows.first?.int("n") ?? 0)
    }

    public func workspacesStartedByOwnerClient(since: Date) throws -> [Workspace] {
        try db.query(
            """
            SELECT * FROM workspaces
            WHERE parent_workspace_id IS NULL AND spawn_tool_use_id IS NOT NULL
              AND created_at >= ?
            ORDER BY created_at
            """,
            [.double(since.timeIntervalSince1970)]
        ).map(Self.workspace(from:))
    }

    public func workspaces(spawnToolUseID: String) throws -> [Workspace] {
        try db.query(
            "SELECT * FROM workspaces WHERE spawn_tool_use_id = ? ORDER BY created_at",
            [.text(spawnToolUseID)]
        ).map(Self.workspace(from:))
    }

    public func nextWorkspaceSortOrder(repoID: RepoID) throws -> Int {
        let rows = try db.query(
            "SELECT COALESCE(MAX(sort_order), -1) AS m FROM workspaces WHERE repo_id = ?",
            [.text(repoID)]
        )
        return Int(rows.first?.int("m") ?? -1) + 1
    }

    public func openSideConversation(parentID: SessionID, streamingText: String = "") throws -> Session {
        try db.transaction {
            guard let parent = try session(id: parentID), let workspaceID = parent.workspaceID,
                  parent.archivedAt == nil, parent.sideConversationParentID == nil,
                  let workspace = try workspace(id: workspaceID), workspace.state == .active else {
                throw SQLiteError(message: "This chat cannot start a side conversation.", sql: nil)
            }
            for leftover in try sessions(workspaceID: workspaceID) where leftover.sideConversationParentID == parentID {
                _ = try update(sessionID: leftover.id) { $0.sideConversationParentID = nil }
            }
            let recent = try db.query(
                "SELECT * FROM messages WHERE session_id = ? ORDER BY seq DESC LIMIT 300",
                [.text(parentID)]
            ).map(Self.message(from:)).reversed()
            let snapshot = SideConversation.Snapshot(
                parentID: parentID, title: parent.title,
                context: SideConversation.context(
                    messages: Array(recent), streamingText: streamingText,
                    inheritedContext: try sideConversationSnapshot(sessionID: parentID)?.context ?? ""
                )
            )
            let next = Session(
                workspaceID: workspaceID, sideConversationParentID: parentID,
                title: PaneNaming.nextTitle(
                    base: "Side conversation", taken: try sessions(workspaceID: workspaceID).map(\.title)
                ),
                model: parent.model, effort: parent.effort,
                agentKind: parent.agentKind, permissionMode: parent.permissionMode,
                sortOrder: try sessions(workspaceID: workspaceID).count
            )
            try writeSession(next)
            try setSetting(SideConversation.contextKey(next.id), String(decoding: JSONEncoder().encode(snapshot), as: UTF8.self))
            for keys in [
                (ComposerControls.fastModeKey(sessionID: parentID), ComposerControls.fastModeKey(sessionID: next.id)),
                (ComposerControls.outputStyleKey(sessionID: parentID), ComposerControls.outputStyleKey(sessionID: next.id)),
                (ComposerControls.contextWindowKey(sessionID: parentID), ComposerControls.contextWindowKey(sessionID: next.id))
            ] { try setSetting(keys.1, setting(keys.0)) }
            try setSetting(
                PlanApproval.modeKey(sessionID: next.id),
                planImplementationMode(sessionID: parentID, hasWorktree: true).rawValue
            )
            try setSetting(ComposerControls.defaultsAppliedKey(sessionID: next.id), "1")
            return next
        }
    }

    public func sideConversationSnapshot(sessionID: SessionID) throws -> SideConversation.Snapshot? {
        guard let stored = try setting(SideConversation.contextKey(sessionID)) else { return nil }
        return try JSONDecoder().decode(SideConversation.Snapshot.self, from: Data(stored.utf8))
    }

    public func sideConversationTurn(_ text: String, sessionID: SessionID) throws -> String {
        guard try setting(SideConversation.contextDeliveredKey(sessionID)) != "1",
              let snapshot = try sideConversationSnapshot(sessionID: sessionID) else { return text }
        return try SideConversation.firstTurn(text, snapshot: snapshot)
    }

    public func acknowledgeSideConversationContext(sessionID: SessionID) throws {
        try setSetting(SideConversation.contextDeliveredKey(sessionID), "1")
    }

    public func handoffIsDue(sessionID: SessionID, deliveredSeq: Int?) throws -> Bool {
        try !db.query(
            SessionSegmentColumns.handoffDue,
            [.text(sessionID), .int(Int64(deliveredSeq ?? -1))]
        ).isEmpty
    }

    public func acknowledgeHandoff(
        sessionID: SessionID, fromSegment segment: SessionSegmentID, carriedDelta: Bool
    ) throws {
        if carriedDelta {
            try db.run(SessionSegmentColumns.acknowledgeCarriedDelta, [.text(sessionID), .text(segment)])
        } else {
            try db.run(SessionSegmentColumns.acknowledge, [.text(sessionID), .text(segment)])
        }
    }

    func handoffRows(
        sessionID: SessionID, afterSeq: Int, excludingSeq: Int?, throughSeq: Int = .max
    ) throws -> [Message] {
        try db.query(
            """
            SELECT id, session_id, seq, kind, \(ConversationHandoff.boundedPayload) AS payload,
                   created_at, duration_ms, ref_id
            FROM messages
            WHERE id IN (
                SELECT id FROM messages
                WHERE session_id = ? AND seq > ? AND seq <= ? AND seq != ?
                    AND kind IN (\(ConversationHandoff.storedKindList))
                ORDER BY seq DESC LIMIT ?
            )
            ORDER BY seq
            """,
            [
                .text(sessionID), .int(Int64(afterSeq)), .int(Int64(throughSeq)), .int(Int64(excludingSeq ?? -1)),
                .int(Int64(ConversationHandoff.rowLimit)),
            ]
        ).map(Self.message(from:))
    }

    public func keepSideConversation(sessionID: SessionID) throws -> Session? {
        try update(sessionID: sessionID) { row in
            row.sideConversationParentID = nil
        }
    }

    @discardableResult
    public func closeSideConversation(sessionID: SessionID) throws -> Bool {
        guard let row = try session(id: sessionID), row.sideConversationParentID != nil,
              row.archivedAt == nil else { return false }
        _ = try update(sessionID: sessionID) { $0.archivedAt = Date() }
        return true
    }

    public func sessions(workspaceID: WorkspaceID) throws -> [Session] {
        try db.query(
            "SELECT * FROM sessions WHERE workspace_id = ? AND archived_at IS NULL ORDER BY sort_order, created_at",
            [.text(workspaceID)]
        ).map(Self.session(from:))
    }

    public func crew(of parentID: SessionID) throws -> [Session] {
        try db.query(
            "SELECT * FROM sessions WHERE parent_session_id = ? AND archived_at IS NULL ORDER BY created_at",
            [.text(parentID)]
        ).map(Self.session(from:))
    }

    public func crew(inWorkspace workspaceID: WorkspaceID) throws -> [Session] {
        try db.query(
            "SELECT * FROM sessions WHERE workspace_id = ? AND parent_session_id IS NOT NULL AND archived_at IS NULL ORDER BY created_at",
            [.text(workspaceID)]
        ).map(Self.session(from:))
    }

    public func crewByWorkspace() throws -> [WorkspaceID: [Session]] {
        let members = try db.query(
            """
            SELECT * FROM sessions
            WHERE parent_session_id IS NOT NULL AND archived_at IS NULL
            ORDER BY created_at
            """
        ).map(Self.session(from:))

        var grouped: [WorkspaceID: [Session]] = [:]
        for member in members {
            guard let workspaceID = member.workspaceID else { continue }
            grouped[workspaceID, default: []].append(member)
        }
        return grouped
    }

    public func sessionsWithoutWorkspace() throws -> [Session] {
        try db.query(
            """
            SELECT * FROM sessions
            WHERE workspace_id IS NULL AND archived_at IS NULL
            ORDER BY sort_order, created_at
            """
        ).map(Self.session(from:))
    }

    public func session(id: SessionID) throws -> Session? {
        try db.query("SELECT * FROM sessions WHERE id = ?", [.text(id)]).first.map(Self.session(from:))
    }

    public func sessions(ids: [SessionID]) throws -> [SessionID: Session] {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [:] }
        let placeholders = unique.map { _ in "?" }.joined(separator: ", ")
        let rows = try db.query(
            "SELECT * FROM sessions WHERE id IN (\(placeholders))", unique.map { SQLValue.text($0) }
        ).map(Self.session(from:))
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func sessionActivity(includingArchivedWorkspaces: Bool = false) throws -> [SessionActivity] {
        let states = AgentTurns.Kind.allCases.map(\.sessionState)
        let placeholders = states.map { _ in "?" }.joined(separator: ", ")
        let workspaceStates = includingArchivedWorkspaces ? WorkspaceState.allCases : [.active]
        let workspacePlaceholders = workspaceStates.map { _ in "?" }.joined(separator: ", ")
        return try db.query(
            """
            SELECT s.id AS id, s.workspace_id AS workspace_id, s.state AS state
            FROM sessions s
            JOIN workspaces w ON w.id = s.workspace_id
            WHERE s.archived_at IS NULL AND w.state IN (\(workspacePlaceholders)) AND s.state IN (\(placeholders))
            """,
            workspaceStates.map { SQLValue.text($0.rawValue) } + states.map { SQLValue.text($0.rawValue) }
        ).map { row in
            SessionActivity(
                sessionID: SessionID(row.string("id") ?? newID()),
                workspaceID: WorkspaceID(row.string("workspace_id") ?? ""),
                state: SessionState(rawValue: row.string("state") ?? "idle") ?? .idle
            )
        }
    }

    @discardableResult
    public func upsert(_ session: Session) throws -> Session {
        try db.transaction { try writeSession(session) }
        return session
    }

    private func writeSession(_ session: Session) throws {
        if session.archivedAt != nil { try requireSessionCanClose(id: session.id) }
        try rememberImplementationMode(for: session)
        try db.run(
            """
            INSERT INTO sessions (
                id, workspace_id, parent_session_id, side_conversation_parent_id, title, agent_session_id, model, effort,
                agent_kind, permission_mode, interaction_mode, state, sort_order, created_at, updated_at,
                archived_at, last_read_seq, input_tokens, output_tokens, cost_usd, context_tokens, account_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                side_conversation_parent_id = excluded.side_conversation_parent_id,
                title = excluded.title,
                agent_session_id = excluded.agent_session_id,
                model = excluded.model,
                effort = excluded.effort,
                agent_kind = excluded.agent_kind,
                permission_mode = excluded.permission_mode,
                interaction_mode = excluded.interaction_mode,
                state = excluded.state,
                sort_order = excluded.sort_order,
                updated_at = excluded.updated_at,
                archived_at = excluded.archived_at,
                last_read_seq = excluded.last_read_seq,
                input_tokens = excluded.input_tokens,
                output_tokens = excluded.output_tokens,
                cost_usd = excluded.cost_usd,
                context_tokens = excluded.context_tokens
            """,
            [
                .text(session.id), .text(session.workspaceID),
                session.parentSessionID.map { .text($0) } ?? .null,
                session.sideConversationParentID.map { .text($0) } ?? .null,
                .text(session.title),
                session.agentSessionID.map { .text($0) } ?? .null,
                .text(session.model), .text(session.effort), .text(session.agentKind.rawValue),
                .text(session.permissionMode.rawValue), .text(session.interactionMode.rawValue),
                .text(session.state.rawValue), .int(Int64(session.sortOrder)),
                .double(session.createdAt.timeIntervalSince1970),
                .double(session.updatedAt.timeIntervalSince1970),
                session.archivedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
                .int(Int64(session.lastReadSeq)),
                .int(Int64(session.inputTokens)), .int(Int64(session.outputTokens)),
                .double(session.costUSD), .int(Int64(session.contextTokens)),
                .text(session.accountID),
            ]
        )
        try db.run(SessionSegmentColumns.ensureFirst, [.text(session.id)])
    }

    @discardableResult
    public func update(
        sessionID: SessionID,
        fromSegment segment: SessionSegmentID,
        _ change: @Sendable (inout Session) -> Void
    ) throws -> Session? {
        guard try activeSegment(sessionID: sessionID)?.id == segment else { return nil }
        return try update(sessionID: sessionID, change)
    }

    @discardableResult
    public func update(
        sessionID: SessionID,
        _ change: @Sendable (inout Session) -> Void
    ) throws -> Session? {
        guard var row = try session(id: sessionID) else { return nil }
        change(&row)
        row.id = sessionID
        try writeSession(row)
        return row
    }

    public func updateSessionPreferences(
        id: SessionID,
        title: String? = nil,
        model: String? = nil,
        effort: String? = nil,
        permissionMode: PermissionMode? = nil,
        interactionMode: InteractionMode? = nil,
        implementationMode: PermissionMode? = nil,
        agentKind: AgentKind? = nil
    ) throws {
        if permissionMode == .plan, let implementationMode {
            try setSetting(PlanApproval.modeKey(sessionID: id), PlanApproval.implementationMode(implementationMode).rawValue)
        }
        if let permissionMode, var session = try session(id: id) {
            session.permissionMode = permissionMode
            try rememberImplementationMode(for: session)
        }
        try db.run(
            """
            UPDATE sessions SET
                title = COALESCE(?, title),
                model = COALESCE(?, model),
                effort = COALESCE(?, effort),
                permission_mode = COALESCE(?, permission_mode),
                interaction_mode = COALESCE(?, interaction_mode),
                agent_kind = COALESCE(?, agent_kind),
                updated_at = ?
            WHERE id = ?
            """,
            [
                title.map { .text($0) } ?? .null,
                model.map { .text($0) } ?? .null,
                effort.map { .text($0) } ?? .null,
                permissionMode.map { .text($0.rawValue) } ?? .null,
                interactionMode.map { .text($0.rawValue) } ?? .null,
                agentKind.map { .text($0.rawValue) } ?? .null,
                .double(Date().timeIntervalSince1970),
                .text(id),
            ]
        )
    }

    public func reorderSessions(ids: [SessionID]) throws {
        try db.transaction {
            for (order, id) in ids.enumerated() {
                try db.run(
                    "UPDATE sessions SET sort_order = ? WHERE id = ?",
                    [.int(Int64(order)), .text(id)]
                )
            }
        }
    }

    public func updateLastReadSeq(sessionID: SessionID, seq: Int) throws {
        try db.run(
            "UPDATE sessions SET last_read_seq = ? WHERE id = ?",
            [.int(Int64(seq)), .text(sessionID)]
        )
    }

    public func deleteSession(id: SessionID) throws {
        try requireSessionCanClose(id: id)
        try db.run("DELETE FROM sessions WHERE id = ?", [.text(id)])
        try setSetting(AgentSessionSettlement.lostAccountKey(sessionID: id), nil)
    }

    public func requireSessionCanClose(id: SessionID) throws {
        if let journal = try checkpointRewind(sessionID: id), journal.stage != .complete {
            throw SnapshotFailure("Resolve this conversation's interrupted rewind before closing it.")
        }
    }

    public func resetRunningSessions() throws {
        var sources: [SessionState] = []
        var destination: SessionState?
        for state in SessionState.allCases {
            guard case .moves(let next) = state.transition(on: .appRelaunched) else { continue }
            sources.append(state)
            destination = next
        }
        guard let destination, !sources.isEmpty else { return }

        let placeholders = sources.map { _ in "?" }.joined(separator: ", ")
        let stateValues = sources.map { SQLValue.text($0.rawValue) }

        let lost = try db.query(
            """
            SELECT member.title AS title,
                   member.workspace_id AS workspace_id,
                   member.parent_session_id AS parent_session_id
            FROM sessions AS member
            JOIN sessions AS parent ON parent.id = member.parent_session_id
            WHERE member.state IN (\(placeholders))
              AND member.archived_at IS NULL
              AND parent.archived_at IS NULL
            ORDER BY member.created_at
            """,
            stateValues
        )

        try db.run(
            "UPDATE sessions SET state = ? WHERE state IN (\(placeholders))",
            [.text(destination.rawValue)] + stateValues
        )

        for row in lost {
            guard let parentID = row.string("parent_session_id") else { continue }
            _ = try? enqueueDelivery(Delivery(
                targetSessionID: SessionID(parentID),
                sourceWorkspaceID: row.string("workspace_id").map(WorkspaceID.init),
                kind: .report,
                crew: CrewMessage.failed(
                    name: row.string("title") ?? "",
                    reason: "Unified Dev was restarted while it was working, so its turn was lost. "
                        + "Nothing it had not already reported got through."
                )
            ))
        }
    }

    public func pendingCheckpointRewind(workspaceID: WorkspaceID) throws -> CheckpointRewind? {
        for row in try db.query("SELECT id FROM sessions WHERE workspace_id = ?", [.text(workspaceID)]) {
            guard let id = row.string("id"), let journal = try checkpointRewind(sessionID: SessionID(id)),
                  journal.stage != .complete else { continue }
            return journal
        }
        return nil
    }

    public func prepareTranscriptRewind(_ checkpoint: TurnCheckpoint) throws -> TranscriptRewindBackup {
        if let active = try activeSegment(sessionID: checkpoint.sessionID), checkpoint.startSeq < active.enteredSeq {
            throw ConversationRewindError.crossesHandoff
        }
        let removed = try db.query(
            "SELECT * FROM messages WHERE session_id = ? AND seq >= ? ORDER BY seq",
            [.text(checkpoint.sessionID), .int(Int64(checkpoint.startSeq))]
        ).map(Self.message(from:))
        guard let first = removed.first, first.seq == checkpoint.startSeq,
              first.kind == .user || AppRequest.isHidden(kind: first.kind, payload: first.payload) else {
            throw SnapshotFailure("The original user message is unavailable for this rewind.")
        }
        let backup = TranscriptRewindBackup(
            checkpointID: checkpoint.id, messages: removed, prompt: UserTurnPrompt.text(in: first.payload),
            originalDraft: try draft(sessionID: checkpoint.sessionID)
        )
        let encoded = try JSONEncoder().encode(backup)
        guard encoded.count <= 50 * 1_024 * 1_024 else {
            throw SnapshotFailure("This rewind exceeds the transcript backup limit. Choose a more recent message.")
        }
        try setSetting(TranscriptRewindBackup.key(sessionID: checkpoint.sessionID), String(decoding: encoded, as: UTF8.self))
        return backup
    }

    public func transcriptRewindBackup(sessionID: SessionID) throws -> TranscriptRewindBackup? {
        guard let value = try setting(TranscriptRewindBackup.key(sessionID: sessionID)) else { return nil }
        return try JSONDecoder().decode(TranscriptRewindBackup.self, from: Data(value.utf8))
    }

    @discardableResult
    public func completeTranscriptRewind(sessionID: SessionID) throws -> String {
        try db.transaction {
            guard var journal = try checkpointRewind(sessionID: sessionID) else {
                throw SnapshotFailure("The rewind recovery record is unavailable.")
            }
            if journal.stage == .complete { return try draft(sessionID: sessionID) }
            guard journal.stage == .providerReverted,
                  let backup = try transcriptRewindBackup(sessionID: sessionID),
                  backup.checkpointID == journal.checkpoint.id else {
                throw SnapshotFailure("The agent has not confirmed this rewind.")
            }
            let seq = journal.checkpoint.startSeq
            for message in backup.messages where message.kind == .permissionAsk {
                if let ask = PermissionAsk.decode(payload: message.payload) {
                    try db.run("DELETE FROM permission_asks WHERE id = ? AND session_id = ?", [.text(ask.requestID), .text(sessionID)])
                }
            }
            try db.run("DELETE FROM messages WHERE session_id = ? AND seq >= ?", [.text(sessionID), .int(Int64(seq))])
            try db.run(WorkSuggestionColumns.deleteAnchored, [.text(sessionID), .int(Int64(seq))])
            try db.run("DELETE FROM transcript_places WHERE session_id = ? AND anchor_seq >= ?", [.text(sessionID), .int(Int64(seq))])
            try db.run(TranscriptChapterColumns.unpinFrom, [.text(sessionID), .int(Int64(seq))])
            try db.run("UPDATE deliveries SET delivered_seq = NULL WHERE target_session_id = ? AND delivered_seq >= ?", [
                .text(sessionID), .int(Int64(seq)),
            ])
            let current = try draft(sessionID: sessionID)
            let restored = current.isEmpty || backup.prompt.isEmpty ? current + backup.prompt : current + "\n\n" + backup.prompt
            try saveDraft(sessionID: sessionID, body: restored)
            try db.run("UPDATE sessions SET last_read_seq = MIN(last_read_seq, ?), context_tokens = 0 WHERE id = ?", [
                .int(Int64(seq - 1)), .text(sessionID),
            ])
            try db.run(SessionSegmentColumns.restoreDelta, [.text(sessionID), .int(Int64(seq))])
            try db.run(SessionSegmentColumns.clampCursors, [.int(Int64(seq - 1)), .text(sessionID)])
            let retired = try removeTurnCheckpoints(sessionID: sessionID, fromSeq: seq)
            try queueRetiredCheckpoints(retired, sessionID: sessionID)
            journal.stage = .complete
            journal.failure = nil
            try saveCheckpointRewind(journal)
            return restored
        }
    }

    public func messages(sessionID: SessionID, afterSeq: Int = -1, limit: Int = 100_000) throws -> [Message] {
        try db.query(
            "SELECT * FROM messages WHERE session_id = ? AND seq > ? ORDER BY seq LIMIT ?",
            [.text(sessionID), .int(Int64(afterSeq)), .int(Int64(limit))]
        ).map(Self.message(from:))
    }

    public func messageCount(sessionID: SessionID) throws -> Int {
        Int(try db.query(
            "SELECT COUNT(*) AS c FROM messages WHERE session_id = ?",
            [.text(sessionID)]
        ).first?.int("c") ?? 0)
    }

    public func nextSeq(sessionID: SessionID) throws -> Int {
        let rows = try db.query(
            "SELECT COALESCE(MAX(seq), -1) AS m FROM messages WHERE session_id = ?",
            [.text(sessionID)]
        )
        return Int(rows.first?.int("m") ?? -1) + 1
    }

    @discardableResult
    public func append(_ message: Message) throws -> Message {
        var stored = message
        stored.id = try insert(message)
        return stored
    }

    @discardableResult
    public func appendNext(
        sessionID: SessionID,
        kind: MessageKind,
        payload: Data,
        durationMS: Int? = nil,
        refID: String? = nil,
        createdAt: Date = Date()
    ) throws -> Message {
        var lastError: Error?
        for _ in 0..<Self.seqAllocationAttempts {
            do {
                return try db.transaction {
                    let seq = try nextSeqLocked(sessionID: sessionID)
                    var message = Message(
                        sessionID: sessionID,
                        seq: seq,
                        kind: kind,
                        payload: payload,
                        createdAt: createdAt,
                        durationMS: durationMS,
                        refID: refID
                    )
                    message.id = try insert(message)
                    return message
                }
            } catch let error as SQLiteError where Self.isSeqConflict(error) {
                lastError = error
            }
        }
        throw lastError ?? SQLiteError(message: "could not allocate a sequence number", sql: nil)
    }

    private static let seqAllocationAttempts = 16

    private static func isSeqConflict(_ error: SQLiteError) -> Bool {
        error.message.contains("UNIQUE constraint failed: messages.session_id")
    }

    private func nextSeqLocked(sessionID: SessionID) throws -> Int {
        let rows = try db.query(
            "SELECT COALESCE(MAX(seq), -1) AS m FROM messages WHERE session_id = ?",
            [.text(sessionID)]
        )
        return Int(rows.first?.int("m") ?? -1) + 1
    }

    private func insert(_ message: Message) throws -> Int64 {
        let id = try db.run(
            """
            INSERT INTO messages (session_id, seq, kind, payload, created_at, duration_ms, ref_id)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(message.sessionID), .int(Int64(message.seq)), .text(message.kind.rawValue),
                .blob(message.payload), .double(message.createdAt.timeIntervalSince1970),
                message.durationMS.map { .int(Int64($0)) } ?? .null,
                message.refID.map { .text($0) } ?? .null,
            ]
        )
        try indexMessage(id: id, kind: message.kind, payload: message.payload)
        return id
    }

    private func indexMessage(id: Int64, kind: MessageKind, payload: Data) throws {
        guard let body = TranscriptSearchText.indexable(kind: kind, payload: payload) else { return }
        try db.run(
            "INSERT INTO message_search (rowid, body) VALUES (?, ?)",
            [.int(id), .text(body)]
        )
    }

    static let backfillCursorKey = "transcriptSearchBackfillCursor"

    public static let backfillBatch = 1_000

    public struct BackfillProgress: Sendable, Hashable {
        public var scanned: Int
        public var remaining: Int
        public var isFinished: Bool { remaining == 0 }
    }

    @discardableResult
    public func indexOlderTranscripts(batch: Int = backfillBatch) throws -> BackfillProgress {
        let cursor = Int64(try setting(Self.backfillCursorKey) ?? "") ?? 0
        guard cursor > 0 else { return BackfillProgress(scanned: 0, remaining: 0) }

        return try db.transaction {
            let rows = try db.query(
                "SELECT id, kind, payload FROM messages WHERE id < ? ORDER BY id DESC LIMIT ?",
                [.int(cursor), .int(Int64(batch))]
            )

            var lowest = cursor
            for row in rows {
                guard let id = row.int("id") else { continue }
                lowest = min(lowest, id)
                let kind = MessageKind(rawValue: row.string("kind") ?? "") ?? .system
                guard let body = TranscriptSearchText.indexable(
                    kind: kind, payload: row.data("payload") ?? Data()
                ) else { continue }
                try db.run(
                    "INSERT OR REPLACE INTO message_search (rowid, body) VALUES (?, ?)",
                    [.int(id), .text(body)]
                )
            }

            let next = rows.count < batch ? 0 : lowest
            try db.run(
                "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                [.text(Self.backfillCursorKey), .text(String(next))]
            )

            let remaining = next == 0 ? 0 : Int(try db.query(
                "SELECT COUNT(*) AS c FROM messages WHERE id < ?", [.int(next)]
            ).first?.int("c") ?? 0)
            return BackfillProgress(scanned: rows.count, remaining: remaining)
        }
    }

    public func isTranscriptIndexIncomplete() throws -> Bool {
        (Int64(try setting(Self.backfillCursorKey) ?? "") ?? 0) > 0
    }

    public func searchTranscripts(
        _ query: String,
        limit: Int = TranscriptSearch.candidateLimit
    ) throws -> [TranscriptWorkspaceMatches] {
        guard let expression = TranscriptSearch.matchExpression(for: query) else { return [] }

        let rows = try db.query(
            """
            SELECT ms.rowid AS message_id, m.session_id, m.seq, m.kind, m.created_at,
                   s.workspace_id, s.title,
                   snippet(message_search, 0, ?, ?, '…', 14) AS marked,
                   bm25(message_search) AS score
            FROM message_search ms
            JOIN messages m ON m.id = ms.rowid
            JOIN sessions s ON s.id = m.session_id
            WHERE message_search MATCH ?
            ORDER BY score
            LIMIT ?
            """,
            [
                .text(TranscriptSearch.openMark), .text(TranscriptSearch.closeMark),
                .text(expression), .int(Int64(limit)),
            ]
        )

        let matches = rows.map { row in
            TranscriptMatch(
                messageID: row.int("message_id") ?? 0,
                workspaceID: WorkspaceID(row.string("workspace_id") ?? ""),
                sessionID: SessionID(row.string("session_id") ?? ""),
                sessionTitle: row.string("title") ?? "Session",
                seq: Int(row.int("seq") ?? 0),
                kind: MessageKind(rawValue: row.string("kind") ?? "") ?? .system,
                createdAt: row.date("created_at") ?? Date(),
                snippet: TranscriptSearch.snippet(from: row.string("marked") ?? ""),
                score: row.double("score") ?? 0
            )
        }

        var totals: [WorkspaceID: Int] = [:]
        for row in try db.query(
            """
            SELECT s.workspace_id AS workspace_id, COUNT(*) AS c
            FROM message_search ms
            JOIN messages m ON m.id = ms.rowid
            JOIN sessions s ON s.id = m.session_id
            WHERE message_search MATCH ?
            GROUP BY s.workspace_id
            """,
            [.text(expression)]
        ) {
            totals[WorkspaceID(row.string("workspace_id") ?? "")] = Int(row.int("c") ?? 0)
        }

        return TranscriptSearch.group(matches, totals: totals)
    }

    func forgetTranscriptIndexForTesting() throws {
        try db.execute("DELETE FROM message_search;")
        try rewindTranscriptBackfillForTesting()
    }

    func rewindTranscriptBackfillForTesting() throws {
        let highest = try db.query("SELECT COALESCE(MAX(id), 0) AS m FROM messages").first?.int("m") ?? 0
        try db.run(
            "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
            [.text(Self.backfillCursorKey), .text(String(highest + 1))]
        )
    }

    public func message(sessionID: SessionID, refID: String) throws -> Message? {
        try db.query(
            "SELECT * FROM messages WHERE session_id = ? AND ref_id = ? ORDER BY seq DESC LIMIT 1",
            [.text(sessionID), .text(refID)]
        ).first.map(Self.message(from:))
    }

    public func draft(sessionID: SessionID) throws -> String {
        try db.query("SELECT body FROM drafts WHERE session_id = ?", [.text(sessionID)])
            .first?.string("body") ?? ""
    }

    public func saveDraft(sessionID: SessionID, body: String) throws {
        if body.isEmpty {
            try db.run("DELETE FROM drafts WHERE session_id = ?", [.text(sessionID)])
        } else {
            try db.run(
                "INSERT INTO drafts (session_id, body) VALUES (?, ?) ON CONFLICT(session_id) DO UPDATE SET body = excluded.body",
                [.text(sessionID), .text(body)]
            )
        }
    }

    public func chapters(sessionID: SessionID) throws -> [TranscriptChapter] {
        try db.query(TranscriptChapterColumns.forSession, [.text(sessionID)])
            .compactMap(TranscriptChapterColumns.chapter(from:))
    }

    public func pin(_ chapter: TranscriptChapter, sessionID: SessionID) throws {
        try db.run(TranscriptChapterColumns.pin, [.text(sessionID), .int(Int64(chapter.seq)), .text(chapter.title)])
    }

    public func unpinChapter(seq: Int, sessionID: SessionID) throws {
        try db.run(TranscriptChapterColumns.unpin, [.text(sessionID), .int(Int64(seq))])
    }

    public func replyQuotes(sessionID: SessionID) throws -> [ReplyQuote] {
        try db.query(
            "SELECT * FROM reply_quotes WHERE session_id = ? ORDER BY rowid", [.text(sessionID)]
        ).compactMap(ReplyQuoteColumns.quote(from:))
    }

    public func add(_ quote: ReplyQuote, sessionID: SessionID) throws {
        try db.run(
            "INSERT INTO reply_quotes (id, session_id, quoted, summary, source_seq) VALUES (?, ?, ?, ?, ?)",
            [
                .text(quote.id), .text(sessionID), .text(quote.quoted), .text(quote.summary),
                quote.sourceSeq.map { .int(Int64($0)) } ?? .null,
            ]
        )
    }

    public func removeReplyQuotes(ids: [ReplyQuoteID]) throws {
        for id in ids {
            try db.run("DELETE FROM reply_quotes WHERE id = ?", [.text(id)])
        }
    }

    public func workspaceDrafts() throws -> [WorkspaceDraft] {
        try db.query("SELECT * FROM workspace_drafts ORDER BY updated_at")
            .map(Self.workspaceDraft(from:))
    }

    public func workspaceDraft(repoID: RepoID) throws -> WorkspaceDraft? {
        try db.query("SELECT * FROM workspace_drafts WHERE repo_id = ?", [.text(repoID)])
            .first.map(Self.workspaceDraft(from:))
    }

    @discardableResult
    public func insert(_ draft: WorkspaceDraft) throws -> WorkspaceDraft {
        try db.run(
            """
            INSERT INTO workspace_drafts (
                repo_id, starting_point, prompt, controls, attachment_key, updated_at, creating_as
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            try Self.workspaceDraftColumns(draft)
        )
        return draft
    }

    @discardableResult
    public func update(
        workspaceDraftFor repoID: RepoID,
        _ change: @Sendable (inout WorkspaceDraft) -> Void
    ) throws -> WorkspaceDraft? {
        guard var row = try workspaceDraft(repoID: repoID) else { return nil }
        change(&row)
        row.repoID = repoID
        let columns = try Self.workspaceDraftColumns(row)
        try db.run(
            """
            UPDATE workspace_drafts
            SET starting_point = ?, prompt = ?, controls = ?, attachment_key = ?, updated_at = ?, creating_as = ?
            WHERE repo_id = ?
            """,
            Array(columns.dropFirst()) + [columns[0]]
        )
        return row
    }

    @discardableResult
    public func moveWorkspaceDraft(from source: RepoID, to target: RepoID) throws -> WorkspaceDraft? {
        try db.transaction {
            guard var row = try workspaceDraft(repoID: source) else { return nil }
            row.repoID = target
            try db.run("DELETE FROM workspace_drafts WHERE repo_id = ?", [.text(source)])
            try insert(row)
            return row
        }
    }

    public func deleteWorkspaceDraft(repoID: RepoID) throws {
        try db.run("DELETE FROM workspace_drafts WHERE repo_id = ?", [.text(repoID)])
    }

    public func note(workspaceID: WorkspaceID) throws -> WorkspaceNote? {
        try db.query(
            "SELECT * FROM workspace_notes WHERE workspace_id = ?", [.text(workspaceID)]
        ).first.map {
            WorkspaceNote(
                workspaceID: WorkspaceID($0.string("workspace_id") ?? workspaceID.rawValue),
                body: $0.string("body") ?? "",
                updatedAt: $0.date("updated_at") ?? Date()
            )
        }
    }

    public func saveNote(workspaceID: WorkspaceID, body: String, at date: Date = Date()) throws {
        let storable = WorkspaceNote.storable(body)
        if storable.isEmpty {
            try db.run("DELETE FROM workspace_notes WHERE workspace_id = ?", [.text(workspaceID)])
        } else {
            try db.run(
                """
                INSERT INTO workspace_notes (workspace_id, body, updated_at) VALUES (?, ?, ?)
                ON CONFLICT(workspace_id)
                DO UPDATE SET body = excluded.body, updated_at = excluded.updated_at
                """,
                [.text(workspaceID), .text(storable), .double(date.timeIntervalSince1970)]
            )
        }
    }

    public func quotas(at now: Date = Date()) throws -> [AgentQuota] {
        let cutoff = now.timeIntervalSince1970
        let stale = try db.query(
            "SELECT COUNT(*) AS n FROM agent_quotas WHERE resets_at IS NOT NULL AND resets_at <= ?",
            [.double(cutoff)]
        ).first?.int("n") ?? 0
        if stale > 0 {
            try db.run(
                "DELETE FROM agent_quotas WHERE resets_at IS NOT NULL AND resets_at <= ?",
                [.double(cutoff)]
            )
        }
        return try db.query("SELECT * FROM agent_quotas").compactMap(Self.quota(from:))
    }

    public func recordQuotas(_ quotas: [AgentQuota]) throws {
        for quota in quotas {
            let (used, limit, unit) = Self.columns(for: quota.measure)
            try db.run(
                """
                INSERT INTO agent_quotas
                    (provider, account_id, window_key, window_label, window_seconds,
                     used, limit_value, unit, resets_at, observed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(provider, account_id, window_key) DO UPDATE SET
                    window_label = excluded.window_label,
                    window_seconds = excluded.window_seconds,
                    used = excluded.used,
                    limit_value = excluded.limit_value,
                    unit = excluded.unit,
                    resets_at = excluded.resets_at,
                    observed_at = excluded.observed_at
                WHERE excluded.observed_at >= agent_quotas.observed_at
                """,
                [
                    .text(quota.provider.rawValue),
                    QuotaAccountColumn.value(quota.account),
                    .text(quota.window.key),
                    .text(quota.window.label),
                    quota.window.duration.map { SQLValue.double($0) } ?? .null,
                    used.map { SQLValue.double($0) } ?? .null,
                    limit.map { SQLValue.double($0) } ?? .null,
                    unit.map { SQLValue.text($0) } ?? .null,
                    quota.resetsAt.map { SQLValue.double($0.timeIntervalSince1970) } ?? .null,
                    .double(quota.observedAt.timeIntervalSince1970),
                ]
            )
        }
    }

    static let fractionUnit = "fraction"

    private static func columns(for measure: QuotaMeasure) -> (Double?, Double?, String?) {
        switch measure {
        case .fraction(let value): (value, 1, fractionUnit)
        case .counted(let used, let limit, let unit): (used, limit, unit)
        case .unknown: (nil, nil, nil)
        }
    }

    private static func quota(from row: Row) -> AgentQuota? {
        guard let provider = row.string("provider").flatMap(AgentKind.init(rawValue:)),
              let key = row.string("window_key") else { return nil }
        let measure: QuotaMeasure
        if let used = row.double("used") {
            let unit = row.string("unit") ?? fractionUnit
            measure = unit == fractionUnit
                ? .fraction(used)
                : .counted(used: used, limit: row.double("limit_value"), unit: unit)
        } else {
            measure = .unknown
        }
        return AgentQuota(
            provider: provider,
            window: QuotaWindow(
                key: key,
                label: row.string("window_label") ?? QuotaWindow.humanised(key),
                duration: row.double("window_seconds")
            ),
            measure: measure,
            resetsAt: row.double("resets_at").map { Date(timeIntervalSince1970: $0) },
            observedAt: row.double("observed_at").map { Date(timeIntervalSince1970: $0) } ?? Date(),
            account: QuotaAccountColumn.account(from: row)
        )
    }

    @discardableResult
    public func enqueueDelivery(
        _ delivery: Delivery, clearingDraftMatching draft: String?,
        clearingQuotes quotes: [ReplyQuoteID] = [], sourcePlan: PlanArtefact? = nil
    ) throws -> Delivery {
        try db.transaction {
            let queued = try enqueueDelivery(delivery)
            if let sourcePlan { try queuePlanSource(sourcePlan, delivery: queued) }
            if let draft, try self.draft(sessionID: delivery.targetSessionID) == draft {
                try saveDraft(sessionID: delivery.targetSessionID, body: "")
            }
            try removeReplyQuotes(ids: quotes)
            return queued
        }
    }

    public func pendingDeliveries(sessionID: SessionID) throws -> [Delivery] {
        try db.query(
            """
            SELECT * FROM deliveries
            WHERE target_session_id = ? AND delivery_state IN ('pending', 'uncertain')
            ORDER BY created_at, rowid
            """,
            [.text(sessionID)]
        ).map(Self.delivery(from:))
    }

    @discardableResult
    public func enqueueDelivery(_ delivery: Delivery) throws -> Delivery {
        var delivery = delivery
        if delivery.kind == .owner, delivery.interactionMode == nil {
            delivery.interactionMode = try session(id: delivery.targetSessionID)?.interactionMode
        }
        try db.run(
            """
            INSERT INTO deliveries
                (id, target_session_id, source_workspace_id, kind, verdict, body, crew_payload,
                 created_at, delivered_at, delivered_seq, delivery_state, interaction_mode, provider_turn_id,
                 canvas_document_path)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(delivery.id),
                .text(delivery.targetSessionID),
                delivery.sourceWorkspaceID.map { .text($0) } ?? .null,
                .text(delivery.kind.rawValue),
                delivery.verdict.map { .text($0) } ?? .null,
                .text(delivery.body),
                delivery.crewPayload.map { .blob($0) } ?? .null,
                .double(delivery.createdAt.timeIntervalSince1970),
                delivery.deliveredAt.map { .double($0.timeIntervalSince1970) } ?? .null,
                delivery.deliveredSeq.map { .int(Int64($0)) } ?? .null,
                .text(delivery.state.rawValue),
                delivery.interactionMode.map { .text($0.rawValue) } ?? .null,
                delivery.providerTurnID.map { .text($0) } ?? .null,
                delivery.canvasDocumentPath.map { .text($0) } ?? .null,
            ]
        )
        return delivery
    }

    public func sessionsHoldingCanvasComments(workspaceID: WorkspaceID) throws -> [SessionID] {
        try db.query(
            """
            SELECT DISTINCT deliveries.target_session_id AS id FROM deliveries
            JOIN sessions ON sessions.id = deliveries.target_session_id
            WHERE sessions.workspace_id = ? AND sessions.archived_at IS NULL
              AND deliveries.kind = ? AND deliveries.delivery_state IN ('pending', 'uncertain')
            """,
            [.text(workspaceID), .text(Delivery.Kind.canvasComment.rawValue)]
        ).compactMap { $0.string("id").map(SessionID.init) }
    }

    public func cancelQueuedCanvasComments(workspaceID: WorkspaceID) throws -> [Delivery] {
        try db.transaction {
            let queued = try db.query(
                """
                SELECT deliveries.* FROM deliveries
                JOIN sessions ON sessions.id = deliveries.target_session_id
                WHERE sessions.workspace_id = ?
                  AND deliveries.kind = ? AND deliveries.delivery_state IN ('pending', 'uncertain')
                ORDER BY deliveries.created_at, deliveries.rowid
                """,
                [.text(workspaceID), .text(Delivery.Kind.canvasComment.rawValue)]
            ).map(Self.delivery(from:))
            for delivery in queued {
                try db.run("DELETE FROM deliveries WHERE id = ?", [.text(delivery.id)])
            }
            return queued
        }
    }

    public func rewriteQueuedDelivery(id: DeliveryID, body: String) throws {
        try db.run("UPDATE deliveries SET body = ? WHERE id = ? AND delivery_state = 'pending'", [.text(body), .text(id)])
    }

    public func claimDelivery(id: DeliveryID) throws -> Bool {
        try db.transaction {
            guard let row = try db.query("SELECT * FROM deliveries WHERE id = ?", [.text(id)]).first,
                  row.string("delivery_state") == "pending" else { return false }
            let delivery = Self.delivery(from: row)
            var seq = delivery.deliveredSeq
            if seq == nil {
                let recorded = Self.recordedRow(for: delivery)
                let next = try nextSeqLocked(sessionID: delivery.targetSessionID)
                _ = try insert(Message(sessionID: delivery.targetSessionID, seq: next,
                    kind: recorded.kind, payload: recorded.payload, createdAt: delivery.createdAt))
                seq = next
            }
            try db.run("UPDATE deliveries SET delivery_state = 'claimed', delivered_seq = ? WHERE id = ?", [
                seq.map { .int(Int64($0)) } ?? .null, .text(id),
            ])
            return true
        }
    }

    private static func recordedRow(for delivery: Delivery) -> (kind: MessageKind, payload: Data) {
        if let crew = delivery.crewPayload { return (.crew, crew) }
        if delivery.kind == .interruptedTurnResume { return (.handoff, HandoffMark.resuming.payload) }
        return (.user, Data(JSONValue.object([
            "type": .string("user"),
            "message": .object(["role": .string("user"), "content": .array([
                .object(["type": .string("text"), "text": .string(delivery.body)]),
            ])]),
        ]).compactJSON.utf8))
    }

    public func beginDeliveryDispatch(id: DeliveryID) throws {
        try db.run("UPDATE deliveries SET delivery_state = 'uncertain' WHERE id = ? AND delivery_state = 'claimed'", [.text(id)])
        guard db.changedRowCount == 1 else { throw DeliveryDispatchError.notClaimed }
    }

    public func acceptDelivery(id: DeliveryID, providerTurnID: String? = nil) throws {
        try db.transaction {
            let now = Date().timeIntervalSince1970
            try db.run("UPDATE deliveries SET delivery_state = 'accepted', delivered_at = ?, provider_turn_id = ? WHERE id = ? AND delivery_state = 'uncertain'", [
                .double(now), providerTurnID.map { .text($0) } ?? .null, .text(id),
            ])
            guard db.changedRowCount == 1 else { return }
            if let accepted = try delivery(id: id) { try acceptPlanSource(delivery: accepted) }
            try db.run(
                "UPDATE workspace_messages SET state = 'delivered', delivered_at = ? WHERE delivery_id = ? AND state = 'queued'",
                [.double(now), .text(id)]
            )
        }
    }

    public func delivery(id: DeliveryID) throws -> Delivery? {
        try db.query("SELECT * FROM deliveries WHERE id = ?", [.text(id)]).first.map(Self.delivery(from:))
    }

    public func recoverDeliveryClaims() throws {
        try db.run("UPDATE deliveries SET delivery_state = 'pending' WHERE delivery_state = 'claimed'")
    }

    @discardableResult
    public func dropUnstartedResumes(sessionID: SessionID? = nil, onlyWaiting: Bool = false) throws -> Int {
        try db.run(
            """
            DELETE FROM deliveries
            WHERE kind = ? AND (? IS NULL OR target_session_id = ?)
              AND (delivery_state = 'pending' OR (? = 0 AND delivery_state != 'accepted'))
            """,
            [
                .text(Delivery.Kind.interruptedTurnResume.rawValue),
                sessionID.map { .text($0) } ?? .null,
                sessionID.map { .text($0) } ?? .null,
                .int(onlyWaiting ? 1 : 0),
            ]
        )
        return db.changedRowCount
    }

    public func hasOwnerTurn(sessionID: SessionID) throws -> Bool {
        try !db.query(
            "SELECT 1 AS found FROM messages WHERE session_id = ? AND kind IN ('\(MessageKind.user.rawValue)', '\(MessageKind.crew.rawValue)') LIMIT 1",
            [.text(sessionID)]
        ).isEmpty
    }

    public func releaseDeliveryClaim(id: DeliveryID) throws {
        try db.run("UPDATE deliveries SET delivery_state = 'pending' WHERE id = ? AND delivery_state = 'claimed'", [.text(id)])
    }

    @discardableResult
    public func markDelivered(id: DeliveryID, seq: Int? = nil, at date: Date = Date()) throws -> Bool {
        try db.run(
            "UPDATE deliveries SET delivered_at = ?, delivered_seq = ?, delivery_state = 'accepted' WHERE id = ? AND delivery_state = 'pending'",
            [.double(date.timeIntervalSince1970), seq.map { .int(Int64($0)) } ?? .null, .text(id)]
        )
        let marked = db.changedRowCount == 1
        if marked {
            try db.run(
                """
                UPDATE workspace_messages SET state = 'delivered', delivered_at = ?
                WHERE delivery_id = ? AND state = 'queued'
                """,
                [.double(date.timeIntervalSince1970), .text(id)]
            )
        }
        return marked
    }

    public func settleQueue(rewriting modes: [DeliveryID: InteractionMode], taking: [Delivery]) throws -> [Delivery] {
        try db.transaction {
            for (id, mode) in modes {
                try db.run(
                    "UPDATE deliveries SET interaction_mode = ? WHERE id = ? AND delivery_state = 'pending'",
                    [.text(mode.rawValue), .text(id)]
                )
            }
            return try taking.filter { try cancelDelivery(id: $0.id) }
        }
    }

    @discardableResult
    public func cancelDelivery(id: DeliveryID) throws -> Bool {
        try db.run("DELETE FROM deliveries WHERE id = ? AND delivery_state IN ('pending', 'uncertain')", [.text(id)])
        let removed = db.changedRowCount == 1
        if removed {
            try db.run(
                "UPDATE workspace_messages SET state = 'cancelled' WHERE delivery_id = ? AND state = 'queued'",
                [.text(id)]
            )
        }
        return removed
    }

    public func restoreDelivery(id: DeliveryID) throws {
        try db.run(
            "UPDATE deliveries SET delivered_at = NULL, delivery_state = 'pending', provider_turn_id = NULL WHERE id = ?",
            [.text(id)]
        )
        try db.run(
            """
            UPDATE workspace_messages SET state = 'queued', delivered_at = NULL
            WHERE delivery_id = ? AND state = 'delivered'
            """,
            [.text(id)]
        )
    }

    @discardableResult
    public func enqueueWorkspaceMessage(
        _ message: WorkspaceMessage, into chat: Session
    ) throws -> WorkspaceMessage {
        try db.transaction {
            let delivery = try enqueueDelivery(Delivery(
                targetSessionID: chat.id,
                sourceWorkspaceID: message.source.workspaceID,
                kind: .message,
                crew: message.crewMessage,
                createdAt: message.createdAt
            ))
            try db.run(
                """
                INSERT INTO workspace_messages
                    (id, source_workspace_id, source_workspace_name, source_project_name,
                     source_session_id, source_chat, target_workspace_id, target_workspace_name,
                     target_project_name, target_session_id, target_chat, reply_session_id, body,
                     delivery_id, state, created_at, delivered_at, notify_when_done)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'queued', ?, NULL, ?)
                """,
                [
                    .text(message.id),
                    message.source.workspaceID.map { .text($0) } ?? .null,
                    .text(message.source.workspace),
                    .text(message.source.project),
                    message.source.sessionID.map { .text($0) } ?? .null,
                    .text(message.source.chat),
                    message.target.workspaceID.map { .text($0) } ?? .null,
                    .text(message.target.workspace),
                    .text(message.target.project),
                    .text(chat.id),
                    .text(chat.title),
                    message.replySessionID.map { .text($0) } ?? .null,
                    .text(message.text),
                    .text(delivery.id),
                    .double(message.createdAt.timeIntervalSince1970),
                    .int(message.notifyWhenDone ? 1 : 0),
                ]
            )
            if let watch = WorkspaceDoneWatchColumns.messageWatch(message, into: chat) {
                try addWorkspaceDoneWatch(watch)
            }
            return try workspaceMessage(id: message.id) ?? message
        }
    }

    public func recordInboxNotification(_ draft: NotificationDraft, at moment: Date = Date()) throws {
        try db.transaction { try InboxNotificationColumns.record(draft, at: moment, in: db) }
    }

    public func inboxNotifications(at moment: Date = Date()) throws -> [InboxNotification] {
        try db.query(InboxNotificationColumns.all, [.double(InboxNotificationColumns.cutoff(at: moment))])
            .compactMap(InboxNotificationColumns.notification(from:))
    }

    public func markInboxNotificationRead(id: InboxNotificationID, at moment: Date = Date()) throws {
        try db.run(InboxNotificationColumns.markRead, [.double(moment.timeIntervalSince1970), .text(id)])
    }

    public func markInboxNotificationsRead(_ opening: InboxOpening, at moment: Date = Date()) throws {
        let unread = try db.query(InboxNotificationColumns.unreadInWorkspace, [.text(opening.workspaceID)])
            .compactMap(InboxNotificationColumns.notification(from:))
        try db.transaction {
            for row in unread where NotificationInbox.clears(row, by: opening) {
                try markInboxNotificationRead(id: row.id, at: moment)
            }
        }
    }

    public func markAllInboxNotificationsRead(at moment: Date = Date()) throws {
        try db.run(InboxNotificationColumns.markAllRead, [.double(moment.timeIntervalSince1970)])
    }

    public func pruneInboxNotifications(at moment: Date = Date()) throws {
        try db.transaction { try InboxNotificationColumns.prune(at: moment, in: db) }
    }

    public func addWorkspaceDoneWatch(_ watch: WorkspaceDoneWatch) throws {
        try db.run(WorkspaceDoneWatchColumns.insert, WorkspaceDoneWatchColumns.values(watch))
    }

    public func unspentWorkspaceDoneWatches(targetWorkspaceID: WorkspaceID) throws -> [WorkspaceDoneWatch] {
        try db.query(WorkspaceDoneWatchColumns.unspentForTarget, [.text(targetWorkspaceID)])
            .map(WorkspaceDoneWatchColumns.watch(from:))
    }

    public func workspaceDoneWatch(id: WorkspaceDoneWatchID) throws -> WorkspaceDoneWatch? {
        try db.query(WorkspaceDoneWatchColumns.byID, [.text(id)]).first.map(WorkspaceDoneWatchColumns.watch(from:))
    }

    @discardableResult
    public func claimWorkspaceDoneWatch(id: WorkspaceDoneWatchID, at date: Date = Date()) throws -> Bool {
        try db.run(WorkspaceDoneWatchColumns.claim, [.double(date.timeIntervalSince1970), .text(id)])
        return db.changedRowCount == 1
    }

    public func workspaceMessage(id: WorkspaceMessageID) throws -> WorkspaceMessage? {
        try db.query("SELECT * FROM workspace_messages WHERE id = ?", [.text(id)])
            .first.map(Self.workspaceMessage(from:))
    }

    public func workspaceMessage(deliveryID: DeliveryID) throws -> WorkspaceMessage? {
        try db.query("SELECT * FROM workspace_messages WHERE delivery_id = ?", [.text(deliveryID)])
            .first.map(Self.workspaceMessage(from:))
    }

    public func latestWorkspaceMessage(
        from source: WorkspaceID, to target: WorkspaceID
    ) throws -> WorkspaceMessage? {
        try db.query(
            """
            SELECT * FROM workspace_messages
            WHERE source_workspace_id = ? AND target_workspace_id = ? AND state = 'delivered'
            ORDER BY delivered_at DESC, created_at DESC, rowid DESC LIMIT 1
            """,
            [.text(source), .text(target)]
        ).first.map(Self.workspaceMessage(from:))
    }

    public func workspaceMessages(
        from source: WorkspaceID, to target: WorkspaceID, since: Date
    ) throws -> [WorkspaceMessage] {
        try db.query(
            """
            SELECT * FROM workspace_messages
            WHERE source_workspace_id = ? AND target_workspace_id = ? AND state != 'cancelled'
              AND created_at >= ?
            ORDER BY created_at DESC, rowid DESC
            """,
            [.text(source), .text(target), .double(since.timeIntervalSince1970)]
        ).map(Self.workspaceMessage(from:))
    }

    @discardableResult
    public func cancelWorkspaceMessage(id: WorkspaceMessageID) throws -> WorkspaceMessage? {
        try db.transaction {
            guard let message = try workspaceMessage(id: id), message.state == .queued,
                  let deliveryID = message.deliveryID
            else { return nil }
            try db.run(
                "DELETE FROM deliveries WHERE id = ? AND delivery_state = 'pending'", [.text(deliveryID)]
            )
            guard db.changedRowCount == 1 else { return nil }
            try db.run(
                "UPDATE workspace_messages SET state = 'cancelled' WHERE id = ? AND state = 'queued'",
                [.text(id)]
            )
            return try workspaceMessage(id: id)
        }
    }

    public func addWorkSuggestion(
        _ suggestion: WorkSuggestion, limit: Int = WorkSuggestion.undecidedLimit
    ) throws -> WorkSuggestionAdmission {
        try db.transaction {
            let undecided = try undecidedWorkSuggestions(beside: suggestion)
            guard undecided < limit else { return .full(undecided: undecided) }
            let card = Message(
                sessionID: suggestion.sessionID,
                seq: try nextSeqLocked(sessionID: suggestion.sessionID),
                kind: .suggestion,
                payload: WorkSuggestionCardPayload.encode(suggestion.id)
            )
            _ = try insert(card)
            try db.run(WorkSuggestionColumns.insert, WorkSuggestionColumns.values(suggestion.anchored(at: card.seq)))
            return .added(try workSuggestion(id: suggestion.id) ?? suggestion)
        }
    }

    private func undecidedWorkSuggestions(beside suggestion: WorkSuggestion) throws -> Int {
        let rows = if let workspaceID = suggestion.workspaceID {
            try db.query(WorkSuggestionColumns.undecidedInWorkspace, [.text(workspaceID)])
        } else {
            try db.query(WorkSuggestionColumns.undecidedInChat, [.text(suggestion.sessionID)])
        }
        return Int(rows.first?.int("c") ?? 0)
    }

    public func workSuggestion(id: WorkSuggestionID) throws -> WorkSuggestion? {
        try db.query("SELECT * FROM work_suggestions WHERE id = ?", [.text(id)])
            .first.map(WorkSuggestionColumns.suggestion(from:))
    }

    public func workSuggestions(sessionID: SessionID) throws -> [WorkSuggestion] {
        try db.query(
            "SELECT * FROM work_suggestions WHERE session_id = ? ORDER BY created_at, rowid",
            [.text(sessionID)]
        ).map(WorkSuggestionColumns.suggestion(from:))
    }

    public func undecidedWorkSuggestionCounts() throws -> [WorkspaceID: Int] {
        var counts: [WorkspaceID: Int] = [:]
        for row in try db.query(WorkSuggestionColumns.undecidedByWorkspace) {
            guard let id = row.string("w") else { continue }
            counts[WorkspaceID(id)] = Int(row.int("c") ?? 0)
        }
        return counts
    }

    public func claimWorkSuggestion(id: WorkSuggestionID) throws -> WorkSuggestionClaim {
        try db.transaction {
            try db.run(
                "UPDATE work_suggestions SET state = 'starting', failure = NULL WHERE id = ? AND state = 'pending'",
                [.text(id)]
            )
            let claimed = db.changedRowCount == 1
            guard let suggestion = try workSuggestion(id: id) else { return .missing }
            return claimed ? .claimed(suggestion) : .taken(suggestion)
        }
    }

    @discardableResult
    public func settleWorkSuggestion(
        id: WorkSuggestionID, as state: WorkSuggestion.State, at date: Date = Date()
    ) throws -> WorkSuggestion? {
        let encoded = WorkSuggestionColumns.encode(state)
        try db.run(
            """
            UPDATE work_suggestions
            SET state = ?, started_id = ?, started_name = ?, failure = NULL, decided_at = ?
            WHERE id = ? AND state = 'starting'
            """,
            [.text(encoded.kind), encoded.id, encoded.name, .double(date.timeIntervalSince1970), .text(id)]
        )
        return try workSuggestion(id: id)
    }

    public func releaseWorkSuggestion(id: WorkSuggestionID, failure: String) throws {
        try db.run(
            "UPDATE work_suggestions SET state = 'pending', failure = ? WHERE id = ? AND state = 'starting'",
            [.text(failure), .text(id)]
        )
    }

    public func noteWorkSuggestionFailure(id: WorkSuggestionID, failure: String) throws {
        try db.run(
            "UPDATE work_suggestions SET failure = ? WHERE id = ? AND state = 'pending'",
            [.text(failure), .text(id)]
        )
    }

    @discardableResult
    public func dismissWorkSuggestion(id: WorkSuggestionID, at date: Date = Date()) throws -> WorkSuggestion? {
        try db.run(
            "UPDATE work_suggestions SET state = 'dismissed', decided_at = ? WHERE id = ? AND state = 'pending'",
            [.double(date.timeIntervalSince1970), .text(id)]
        )
        return try workSuggestion(id: id)
    }

    public func withdrawWorkSuggestion(
        id: WorkSuggestionID, by sessionID: SessionID, at date: Date = Date()
    ) throws -> WorkSuggestionWithdrawal {
        try db.transaction {
            guard let found = try workSuggestion(id: id) else { return .missing }
            guard found.sessionID == sessionID else { return .notYours }
            try db.run(
                "UPDATE work_suggestions SET state = 'withdrawn', decided_at = ? WHERE id = ? AND state = 'pending'",
                [.double(date.timeIntervalSince1970), .text(id)]
            )
            guard db.changedRowCount == 1, let withdrawn = try workSuggestion(id: id) else {
                return .alreadyDecided(found)
            }
            return .withdrawn(withdrawn)
        }
    }

    @discardableResult
    public func retargetRemoteWorkSuggestions(slug: String, to repoID: RepoID) throws -> Int {
        guard let project = try repo(id: repoID) else { return 0 }
        let waiting = try db.query(
            "SELECT * FROM work_suggestions WHERE target_kind = 'remote' AND target_value = ? COLLATE NOCASE AND state = 'pending'",
            [.text(slug)]
        ).map(WorkSuggestionColumns.suggestion(from:))
        var adopted = 0
        for suggestion in waiting
        where WorkSuggestionProfile.admits(project: project.profileID, from: try workSuggestionSource(suggestion)) {
            try db.run(
                "UPDATE work_suggestions SET target_kind = 'project', target_value = ? WHERE id = ? AND state = 'pending'",
                [.text(repoID), .text(suggestion.id)]
            )
            adopted += db.changedRowCount
        }
        return adopted
    }

    @discardableResult
    public func releaseWorkSuggestionClaims() throws -> Int {
        try db.run("UPDATE work_suggestions SET state = 'pending' WHERE state = 'starting'")
        return db.changedRowCount
    }

    public func reviewComments(workspaceID: WorkspaceID) throws -> [ReviewComment] {
        try db.query(
            "SELECT * FROM review_comments WHERE workspace_id = ? ORDER BY file_path, line, created_at, id",
            [.text(workspaceID)]
        ).map(Self.reviewComment(from:))
    }

    public func reviewComments(workspaceID: WorkspaceID, filePath: String) throws -> [ReviewComment] {
        try db.query(
            """
            SELECT * FROM review_comments WHERE workspace_id = ? AND file_path = ?
            ORDER BY line, created_at, id
            """,
            [.text(workspaceID), .text(filePath)]
        ).map(Self.reviewComment(from:))
    }

    public func attachedReviewComments(workspaceID: WorkspaceID) throws -> [ReviewComment] {
        try db.query(
            """
            SELECT * FROM review_comments WHERE workspace_id = ? AND attached = 1
            ORDER BY file_path, line, created_at, id
            """,
            [.text(workspaceID)]
        ).map(Self.reviewComment(from:))
    }

    @discardableResult
    public func upsert(_ comment: ReviewComment) throws -> ReviewComment {
        try db.run(
            """
            INSERT INTO review_comments (
                id, workspace_id, file_path, side, line, line_text,
                context_before, context_after, body, created_at, attached, span
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                file_path = excluded.file_path,
                side = excluded.side,
                line = excluded.line,
                line_text = excluded.line_text,
                context_before = excluded.context_before,
                context_after = excluded.context_after,
                body = excluded.body,
                attached = excluded.attached,
                span = excluded.span
            """,
            [
                .text(comment.id), .text(comment.workspaceID), .text(comment.filePath),
                .text(comment.side.rawValue), .int(Int64(comment.anchor.line)),
                .text(comment.anchor.text),
                .text(Self.encodeContext(comment.anchor.before)),
                .text(Self.encodeContext(comment.anchor.after)),
                .text(comment.body), .double(comment.createdAt.timeIntervalSince1970),
                .int(comment.isAttached ? 1 : 0), .int(Int64(comment.anchor.span)),
            ]
        )
        return comment
    }

    public func updateReviewCommentBody(id: ReviewCommentID, body: String) throws {
        try db.run("UPDATE review_comments SET body = ? WHERE id = ?", [.text(body), .text(id)])
    }

    public func setReviewCommentAttached(id: ReviewCommentID, attached: Bool) throws {
        try db.run(
            "UPDATE review_comments SET attached = ? WHERE id = ?",
            [.int(attached ? 1 : 0), .text(id)]
        )
    }

    public func detachReviewComments(workspaceID: WorkspaceID) throws {
        try db.run(
            "UPDATE review_comments SET attached = 0 WHERE workspace_id = ?",
            [.text(workspaceID)]
        )
    }

    public func deleteReviewComment(id: ReviewCommentID) throws {
        try db.run("DELETE FROM review_comments WHERE id = ?", [.text(id)])
    }

    public func reviewedFiles(workspaceID: WorkspaceID) throws -> [ReviewedFile] {
        try db.query(
            "SELECT * FROM reviewed_files WHERE workspace_id = ? ORDER BY file_path",
            [.text(workspaceID)]
        ).map(Self.reviewedFile(from:))
    }

    public func markReviewed(_ mark: ReviewedFile) throws {
        try db.run(
            """
            INSERT INTO reviewed_files (workspace_id, file_path, fingerprint, viewed_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(workspace_id, file_path) DO UPDATE SET
                fingerprint = excluded.fingerprint,
                viewed_at = excluded.viewed_at
            """,
            [
                .text(mark.workspaceID), .text(mark.path), .text(mark.fingerprint),
                .double(mark.viewedAt.timeIntervalSince1970),
            ]
        )
    }

    public func clearReviewed(workspaceID: WorkspaceID, path: String) throws {
        try db.run(
            "DELETE FROM reviewed_files WHERE workspace_id = ? AND file_path = ?",
            [.text(workspaceID), .text(path)]
        )
    }

    public func clearReviewed(workspaceID: WorkspaceID) throws {
        try db.run("DELETE FROM reviewed_files WHERE workspace_id = ?", [.text(workspaceID)])
    }

    public func deleteReviewComments(workspaceID: WorkspaceID) throws {
        try db.run("DELETE FROM review_comments WHERE workspace_id = ?", [.text(workspaceID)])
    }

    public func quickPrompts() throws -> [QuickPrompt] {
        try db.query("SELECT * FROM quick_prompt ORDER BY sort_order, created_at, id")
            .map(Self.quickPrompt(from:))
    }

    public func quickPrompt(id: QuickPromptID) throws -> QuickPrompt? {
        try db.query("SELECT * FROM quick_prompt WHERE id = ?", [.text(id)])
            .first.map(Self.quickPrompt(from:))
    }

    @discardableResult
    public func insert(_ prompt: QuickPrompt) throws -> QuickPrompt {
        var row = prompt
        row.sortOrder = try nextQuickPromptOrder()
        try insertQuickPromptRow(row)
        return row
    }

    @discardableResult
    public func update(
        quickPromptID: QuickPromptID,
        _ change: @Sendable (inout QuickPrompt) -> Void
    ) throws -> QuickPrompt? {
        guard var row = try quickPrompt(id: quickPromptID) else { return nil }
        change(&row)
        try db.run(
            """
            UPDATE quick_prompt
            SET name = ?, symbol = ?, text = ?, sends_immediately = ?, opens_new_chat = ?
            WHERE id = ?
            """,
            [
                .text(row.name), .text(row.symbol), .text(row.text),
                .int(row.sendsImmediately ? 1 : 0), .int(row.opensNewChat ? 1 : 0),
                .text(quickPromptID),
            ]
        )
        row.id = quickPromptID
        return row
    }

    public func deleteQuickPrompt(id: QuickPromptID) throws {
        try db.run("DELETE FROM quick_prompt WHERE id = ?", [.text(id)])
    }

    @discardableResult
    public func seedQuickPrompts(now: Date = Date()) throws -> [QuickPrompt] {
        let installed = Int(try setting(QuickPromptSeed.versionKey) ?? "") ?? 0
        let pending = QuickPromptSeed.pending(installed: installed)
        guard !pending.isEmpty else { return try quickPrompts() }

        var order = try nextQuickPromptOrder()
        for entry in pending {
            try insertQuickPromptRow(entry.prompt(sortOrder: order, now: now))
            order += 1
        }
        try setSetting(QuickPromptSeed.versionKey, String(QuickPromptSeed.version))
        return try quickPrompts()
    }

    private func nextQuickPromptOrder() throws -> Int {
        let highest = try db.query("SELECT COALESCE(MAX(sort_order), -1) AS m FROM quick_prompt")
            .first?.int("m") ?? -1
        return Int(highest) + 1
    }

    private func insertQuickPromptRow(_ prompt: QuickPrompt) throws {
        try db.run(
            """
            INSERT INTO quick_prompt (
                id, name, symbol, text, sends_immediately, opens_new_chat, sort_order, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(prompt.id), .text(prompt.name), .text(prompt.symbol), .text(prompt.text),
                .int(prompt.sendsImmediately ? 1 : 0), .int(prompt.opensNewChat ? 1 : 0),
                .int(Int64(prompt.sortOrder)),
                .double(prompt.createdAt.timeIntervalSince1970),
            ]
        )
    }

    public func permissionGrants(repoID: RepoID) throws -> [PermissionGrant] {
        try db.query(
            "SELECT * FROM permission_grants WHERE repo_id = ? ORDER BY granted_at DESC, id",
            [.text(repoID)]
        ).map(Self.permissionGrant(from:))
    }

    public func permissionGrants() throws -> [PermissionGrant] {
        try db.query("SELECT * FROM permission_grants ORDER BY repo_id, granted_at DESC, id")
            .map(Self.permissionGrant(from:))
    }

    @discardableResult
    public func upsert(_ grant: PermissionGrant) throws -> PermissionGrant {
        try db.run(
            """
            INSERT INTO permission_grants (
                id, repo_id, tool_name, rule_content, granted_at, last_used_at, use_count, granted_for
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(repo_id, tool_name, rule_content) DO NOTHING
            """,
            [
                .text(grant.id), .text(grant.repoID), .text(grant.toolName),
                .text(grant.ruleContent ?? ""),
                .double(grant.grantedAt.timeIntervalSince1970),
                grant.lastUsedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
                .int(Int64(grant.useCount)), .text(grant.grantedFor),
            ]
        )
        let stored = try db.query(
            "SELECT * FROM permission_grants WHERE repo_id = ? AND tool_name = ? AND rule_content = ?",
            [.text(grant.repoID), .text(grant.toolName), .text(grant.ruleContent ?? "")]
        ).first
        return stored.map(Self.permissionGrant(from:)) ?? grant
    }

    public func recordPermissionGrantUse(id: PermissionGrantID, at date: Date = Date()) throws {
        try db.run(
            "UPDATE permission_grants SET use_count = use_count + 1, last_used_at = ? WHERE id = ?",
            [.double(date.timeIntervalSince1970), .text(id)]
        )
    }

    public func deletePermissionGrant(id: PermissionGrantID) throws {
        try db.run("DELETE FROM permission_grants WHERE id = ?", [.text(id)])
    }

    public func deletePermissionGrants(repoID: RepoID) throws {
        try db.run("DELETE FROM permission_grants WHERE repo_id = ?", [.text(repoID)])
    }

    public func appendPermissionAsk(sessionID: SessionID, ask: PermissionAsk, at date: Date = Date()) throws {
        try db.run(
            """
            INSERT INTO permission_asks (id, session_id, tool_use_id, payload, created_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO NOTHING
            """,
            [
                .text(ask.requestID), .text(sessionID), .text(ask.toolUseID),
                .blob(ask.raw), .double(date.timeIntervalSince1970),
            ]
        )
    }

    public func resolvePermissionAsk(
        id: String, decision: String, answers: [String: String] = [:], at date: Date = Date()
    ) throws {
        try db.run(
            """
            UPDATE permission_asks
            SET resolved_at = ?, decision = ?, payload = COALESCE(?, payload)
            WHERE id = ? AND resolved_at IS NULL
            """,
            [
                .double(date.timeIntervalSince1970),
                .text(decision),
                try answered(id: id, answers: answers).map { SQLValue.blob($0) } ?? .null,
                .text(id),
            ]
        )
    }

    private func answered(id: String, answers: [String: String]) throws -> Data? {
        guard !answers.isEmpty else { return nil }
        guard let stored = try db.query(
            "SELECT payload FROM permission_asks WHERE id = ? AND resolved_at IS NULL", [.text(id)]
        ).first?.data("payload") else { return nil }
        return AnsweredAsk.payload(of: stored, answers: answers)
    }

    public func pendingPermissionAsks(sessionID: SessionID) throws -> [PendingPermissionAsk] {
        try db.query(
            """
            SELECT * FROM permission_asks
            WHERE session_id = ? AND resolved_at IS NULL
            ORDER BY created_at, id
            """,
            [.text(sessionID)]
        ).compactMap(Self.pendingPermissionAsk(from:))
    }

    public func pendingPermissionAsks() throws -> [PendingPermissionAsk] {
        try db.query(
            "SELECT * FROM permission_asks WHERE resolved_at IS NULL ORDER BY created_at, id"
        ).compactMap(Self.pendingPermissionAsk(from:))
    }

    public func permissionAskDecisions(sessionID: SessionID) throws -> [String: String] {
        var decisions: [String: String] = [:]
        for row in try db.query(
            "SELECT id, decision FROM permission_asks WHERE session_id = ? AND decision IS NOT NULL",
            [.text(sessionID)]
        ) {
            guard let id = row.string("id"), let decision = row.string("decision") else { continue }
            decisions[id] = decision
        }
        return decisions
    }

    public func permissionAskAnswers(sessionID: SessionID) throws -> [String: [String: String]] {
        var answers: [String: [String: String]] = [:]
        for row in try db.query(
            "SELECT id, payload FROM permission_asks WHERE session_id = ? AND decision = ?",
            [.text(sessionID), .text(PermissionDecision.answeredName)]
        ) {
            guard let id = row.string("id"), let payload = row.data("payload") else { continue }
            let given = AnsweredAsk.answers(in: payload)
            guard !given.isEmpty else { continue }
            answers[id] = given
        }
        return answers
    }

    @discardableResult
    public func abandonPendingPermissionAsks(decision: String = "abandoned", at date: Date = Date()) throws -> Int {
        let pending = try db.query(
            "SELECT COUNT(*) AS n FROM permission_asks WHERE resolved_at IS NULL"
        ).first?.int("n") ?? 0
        try db.run(
            "UPDATE permission_asks SET resolved_at = ?, decision = ? WHERE resolved_at IS NULL",
            [.double(date.timeIntervalSince1970), .text(decision)]
        )
        return Int(pending)
    }

    private func rememberImplementationMode(for session: Session) throws {
        let key = PlanApproval.modeKey(sessionID: session.id)
        let remembered = try setting(key)
        let mode: PermissionMode
        if session.permissionMode != .plan {
            mode = PlanApproval.implementationMode(session.permissionMode)
        } else {
            guard remembered == nil else { return }
            mode = try planImplementationMode(sessionID: session.id, hasWorktree: session.workspaceID != nil)
        }
        if remembered != mode.rawValue { try setSetting(key, mode.rawValue) }
    }

    public func planImplementationMode(sessionID: SessionID, hasWorktree: Bool) throws -> PermissionMode {
        if let session = try session(id: sessionID), session.permissionMode != .plan {
            return PlanApproval.implementationMode(session.permissionMode)
        }
        if let raw = try setting(PlanApproval.modeKey(sessionID: sessionID)),
           let mode = PermissionMode(rawValue: raw) {
            return PlanApproval.implementationMode(mode)
        }
        guard hasWorktree else { return AskConversation.permissionMode }
        let configured = try setting(AppDefaults.Key.permissionMode).flatMap(PermissionMode.init(rawValue:))
        return PlanApproval.implementationMode(configured ?? AppDefaults.fallbackPermissionMode)
    }

    public func transcriptCursors(forPaths paths: [String]) throws -> [String: TranscriptCursor] {
        guard !paths.isEmpty else { return [:] }
        let placeholders = paths.map { _ in "?" }.joined(separator: ", ")
        let rows = try db.query(
            "SELECT * FROM usage_files WHERE path IN (\(placeholders))", paths.map(SQLValue.text)
        ).map(SpendColumns.cursor(from:))
        return Dictionary(rows.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func transcriptCursorPaths(after path: String, limit: Int) throws -> [String] {
        try db.query(
            "SELECT path FROM usage_files WHERE path > ? ORDER BY path LIMIT ?",
            [.text(path), .int(Int64(limit))]
        ).compactMap { $0.string("path") }
    }

    public func forgetTranscriptCursors(paths: [String]) throws {
        guard !paths.isEmpty else { return }
        let placeholders = paths.map { _ in "?" }.joined(separator: ", ")
        try db.run("DELETE FROM usage_files WHERE path IN (\(placeholders))", paths.map(SQLValue.text))
    }

    public func forgetSpend(ofFile path: String) throws {
        try db.run(SpendColumns.forget, [.text(path)])
    }

    public func record(
        _ turns: [SpendTurn],
        reaching cursor: TranscriptCursor,
        replacing path: String? = nil,
        at date: Date = Date()
    ) throws {
        try db.transaction {
            if let path { try db.run(SpendColumns.forget, [.text(path)]) }
            for turn in turns {
                try db.run(SpendColumns.add, SpendColumns.values(turn))
            }
            try db.run(SpendColumns.rememberFile, SpendColumns.values(cursor, at: date))
        }
    }

    public func pruneSpend(before day: Date) throws {
        try db.run(SpendColumns.prune, [.double(day.timeIntervalSince1970)])
    }

    public func forgetEverySpendTurn() throws {
        try db.transaction {
            try db.run(SpendColumns.forgetEveryTurn, [])
            try db.run(SpendColumns.forgetEveryCursor, [])
        }
    }

    public func spendDays(since day: Date) throws -> [SpendDay] {
        try db.query(SpendColumns.since, [.double(day.timeIntervalSince1970)])
            .map(SpendColumns.day(from:))
    }

    public func setting(_ key: String) throws -> String? {
        try db.query("SELECT value FROM settings WHERE key = ?", [.text(key)]).first?.string("value")
    }

    public func transcriptPlace(sessionID: SessionID) throws -> TranscriptPlace? {
        guard let row = try db.query(
            "SELECT * FROM transcript_places WHERE session_id = ?", [.text(sessionID)]
        ).first, let seq = row.int("anchor_seq"), let count = row.int("row_count") else { return nil }
        return TranscriptPlace(
            anchorSeq: Int(seq),
            anchorDelta: row.double("anchor_delta") ?? 0,
            isAtLiveEnd: row.bool("is_at_live_end"),
            rowCount: Int(count)
        )
    }

    public func setTranscriptPlace(_ place: TranscriptPlace, sessionID: SessionID) throws {
        try db.run(
            """
            INSERT INTO transcript_places (session_id, anchor_seq, anchor_delta, is_at_live_end, row_count)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(session_id) DO UPDATE SET
                anchor_seq = excluded.anchor_seq,
                anchor_delta = excluded.anchor_delta,
                is_at_live_end = excluded.is_at_live_end,
                row_count = excluded.row_count
            """,
            [
                .text(sessionID), .int(Int64(place.anchorSeq)), .double(place.anchorDelta),
                .int(place.isAtLiveEnd ? 1 : 0), .int(Int64(place.rowCount)),
            ]
        )
    }

    public func saveComposerControls(_ controls: ComposerControls, sessionID: SessionID) throws {
        try db.transaction {
            for (key, value) in controls.settings(sessionID: sessionID) {
                try setSetting(key, value)
            }
        }
    }

    public func replaceWorkspaceConversation(id: SessionID, controls: ComposerControls) throws -> Session {
        try db.transaction {
            guard let current = try session(id: id), let workspaceID = current.workspaceID,
                  current.archivedAt == nil else {
                throw SQLiteError(message: "This conversation is no longer current.", sql: nil)
            }
            var next = Session(workspaceID: workspaceID, title: current.title, sortOrder: current.sortOrder)
            next.model = controls.model
            next.effort = controls.effort
            next.agentKind = controls.agentKind
            next.permissionMode = controls.permissionMode
            next.interactionMode = controls.interactionMode
            try writeSession(next)
            for (key, value) in controls.settings(sessionID: next.id) {
                try setSetting(key, value)
            }
            _ = try update(sessionID: id) { $0.archivedAt = Date() }
            return next
        }
    }

    public func replaceAskConversation(
        id: SessionID, controls: ComposerControls, draft: String = ""
    ) throws -> Session {
        try db.transaction {
            guard let current = try session(id: id), current.workspaceID == nil,
                  current.archivedAt == nil else {
                throw SQLiteError(message: "This conversation is no longer current.", sql: nil)
            }
            var next = AskConversation.newSession(sortOrder: current.sortOrder)
            next.model = controls.model
            next.effort = controls.effort
            next.agentKind = controls.agentKind
            next.permissionMode = controls.permissionMode
            next.interactionMode = controls.interactionMode
            try writeSession(next)
            for (key, value) in controls.settings(sessionID: next.id) {
                try setSetting(key, value)
            }
            try saveDraft(sessionID: next.id, body: draft)
            let directory = try setting(AskTabs.directoryKey(id))
                ?? AskConversation.directory(besideDatabaseAt: path)
            try setSetting(AskTabs.directoryKey(next.id), directory)
            try setSetting(AskTabs.selectionKey, next.id.rawValue)
            _ = try update(sessionID: id) { $0.archivedAt = Date() }
            return next
        }
    }

    public func createAskConversation(
        directory: String, controls: ComposerControls? = nil, draft: String = ""
    ) throws -> Session {
        try db.transaction {
            let existing = try sessionsWithoutWorkspace()
            var next = AskConversation.newSession(sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1)
            if let controls {
                next.model = controls.model
                next.effort = controls.effort
                next.agentKind = controls.agentKind
                next.permissionMode = controls.permissionMode
            next.interactionMode = controls.interactionMode
            }
            try writeSession(next)
            if let controls {
                for (key, value) in controls.settings(sessionID: next.id) { try setSetting(key, value) }
            }
            try saveDraft(sessionID: next.id, body: draft)
            try setSetting(AskTabs.directoryKey(next.id), directory)
            try setSetting(AskTabs.selectionKey, next.id.rawValue)
            return next
        }
    }

    public func closeAskConversation(id: SessionID, selected: SessionID?) throws -> SessionID? {
        try db.transaction {
            let sessions = try sessionsWithoutWorkspace()
            guard sessions.count > 1, sessions.contains(where: { $0.id == id }) else { return selected }
            let next = AskTabs.selectionAfterClosing(id, selected: selected, sessions: sessions)
            _ = try update(sessionID: id) { $0.archivedAt = Date() }
            try setSetting(AskTabs.selectionKey, next?.rawValue)
            return next
        }
    }

    public func setSetting(_ key: String, _ value: String?) throws {
        if let value {
            try db.run(
                "INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                [.text(key), .text(value)]
            )
        } else {
            try db.run("DELETE FROM settings WHERE key = ?", [.text(key)])
        }
    }

    public func terminalTabs() throws -> [TerminalTab] {
        try db.query(
            "SELECT * FROM terminal_tabs ORDER BY workspace_id, sort_order"
        ).map {
            TerminalTab(
                id: TerminalTabID($0.string("id") ?? newID()),
                workspaceID: WorkspaceID($0.string("workspace_id") ?? ""),
                title: $0.string("title") ?? "Terminal",
                sortOrder: Int($0.int("sort_order") ?? 0)
            )
        }
    }

    public func upsert(_ tab: TerminalTab) throws {
        try db.run(
            """
            INSERT INTO terminal_tabs (id, workspace_id, title, sort_order) VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET title = excluded.title, sort_order = excluded.sort_order
            """,
            [.text(tab.id), .text(tab.workspaceID), .text(tab.title), .int(Int64(tab.sortOrder))]
        )
    }

    public func deleteTerminalTab(id: TerminalTabID) throws {
        try db.run("DELETE FROM terminal_tabs WHERE id = ?", [.text(id)])
    }

    public func oceans() throws -> [Ocean] {
        try db.query("SELECT * FROM oceans ORDER BY name").map(Self.ocean(from:))
    }

    public func unusedOceanCount() throws -> Int {
        Int(try db.query("SELECT COUNT(*) AS n FROM oceans WHERE used_at IS NULL").first?.int("n") ?? 0)
    }

    public func claimOcean(now: Date = Date()) throws -> OceanPick? {
        guard let slug = OceanCatalog.all.randomElement()?.slug,
              let row = try db.query("SELECT * FROM oceans WHERE slug = ?", [.text(slug)]).first else {
            return nil
        }
        var ocean = Self.ocean(from: row)
        guard ocean.usedAt == nil else {
            return OceanPick(
                ocean: ocean, isFirstUse: false, remainingUndiscovered: try unusedOceanCount()
            )
        }
        ocean.usedAt = now
        try db.run(
            "UPDATE oceans SET used_at = ? WHERE slug = ?",
            [.double(now.timeIntervalSince1970), .text(ocean.slug)]
        )
        return OceanPick(
            ocean: ocean, isFirstUse: true, remainingUndiscovered: try unusedOceanCount()
        )
    }

    private static func workspaceDraftColumns(_ draft: WorkspaceDraft) throws -> [SQLValue] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let startingPoint = String(decoding: try encoder.encode(draft.startingPoint), as: UTF8.self)
        let controls = try draft.controls.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
        return [
            .text(draft.repoID),
            .text(startingPoint),
            .text(draft.prompt),
            controls.map { SQLValue.text($0) } ?? .null,
            .text(draft.attachmentKey),
            .double(draft.updatedAt.timeIntervalSince1970),
            draft.creatingAs.map { SQLValue.text($0) } ?? .null,
        ]
    }

    private static func workspaceDraft(from row: Row) throws -> WorkspaceDraft {
        let decoder = JSONDecoder()
        let startingPoint = try decoder.decode(
            WorkspaceStartingPoint.self, from: Data((row.string("starting_point") ?? "").utf8)
        )
        let controls = try row.string("controls").map {
            try decoder.decode(WorkspaceDraftControls.self, from: Data($0.utf8))
        }
        return WorkspaceDraft(
            repoID: RepoID(row.string("repo_id") ?? ""),
            startingPoint: startingPoint,
            prompt: row.string("prompt") ?? "",
            controls: controls,
            attachmentKey: row.string("attachment_key") ?? "",
            updatedAt: row.date("updated_at") ?? Date(timeIntervalSince1970: 0),
            creatingAs: row.string("creating_as").map(WorkspaceID.init)
        )
    }

    private static func repo(from row: Row) -> Repo {
        Repo(
            id: RepoID(row.string("id") ?? newID()),
            name: row.string("name") ?? "",
            path: row.string("path") ?? "",
            defaultBranch: row.string("default_branch") ?? "main",
            accent: row.string("accent") ?? Accent.all[0],
            sortOrder: Int(row.int("sort_order") ?? 0),
            collapsed: row.bool("collapsed"),
            hidden: row.bool("hidden"),
            createdAt: row.date("created_at") ?? Date(),
            iconPath: row.string("icon_path"),
            iconSource: RepoIconSource(rawValue: row.string("icon_source") ?? "") ?? .undetected,
            profileID: ProfileID(row.string(ProfileColumns.column) ?? ProfileID.initial.rawValue)
        )
    }

    private static func workspace(from row: Row) -> Workspace {
        Workspace(
            id: WorkspaceID(row.string("id") ?? newID()),
            repoID: RepoID(row.string("repo_id") ?? ""),
            name: row.string("name") ?? "",
            branch: row.string("branch") ?? "",
            path: row.string("path") ?? "",
            baseBranch: row.string("base_branch") ?? "main",
            state: WorkspaceState(rawValue: row.string("state") ?? "active") ?? .active,
            setupState: SetupState(rawValue: row.string("setup_state") ?? "pending") ?? .pending,
            setupLog: row.string("setup_log") ?? "",
            sortOrder: Int(row.int("sort_order") ?? 0),
            createdAt: row.date("created_at") ?? Date(),
            lastActivityAt: row.date("last_activity_at") ?? Date(),
            archivedAt: row.date("archived_at"),
            additions: Int(row.int("additions") ?? 0),
            deletions: Int(row.int("deletions") ?? 0),
            changedFiles: Int(row.int("changed_files") ?? 0),
            unread: row.bool("unread"),
            pinned: row.bool("pinned"),
            colour: row.string("colour"),
            origin: WorkspaceOrigin(
                parentWorkspaceID: row.string("parent_workspace_id"),
                spawnToolUseID: row.string("spawn_tool_use_id")
            ),
            port: Int(row.int("port") ?? 0),
            pullRequestNumber: row.int("pull_request_number").map(Int.init),
            isOrchestrator: row.bool("is_orchestrator")
        )
    }

    private static func delivery(from row: Row) -> Delivery {
        Delivery(
            id: DeliveryID(row.string("id") ?? newID()),
            targetSessionID: SessionID(row.string("target_session_id") ?? ""),
            sourceWorkspaceID: row.string("source_workspace_id").map(WorkspaceID.init),
            kind: Delivery.Kind(rawValue: row.string("kind") ?? "") ?? .owner,
            verdict: row.string("verdict"),
            body: row.string("body") ?? "",
            crewPayload: row.data("crew_payload"),
            createdAt: row.date("created_at") ?? Date(),
            deliveredAt: row.date("delivered_at"),
            deliveredSeq: row.int("delivered_seq").map(Int.init),
            state: Delivery.State(rawValue: row.string("delivery_state") ?? ""),
            interactionMode: row.string("interaction_mode").flatMap(InteractionMode.init(rawValue:)),
            providerTurnID: row.string("provider_turn_id"),
            canvasDocumentPath: row.string("canvas_document_path")
        )
    }

    private static func workspaceMessage(from row: Row) -> WorkspaceMessage {
        WorkspaceMessage(
            stored: WorkspaceMessageID(row.string("id") ?? newID()),
            source: WorkspaceMessageEnd(
                workspaceID: row.string("source_workspace_id").map(WorkspaceID.init),
                workspace: row.string("source_workspace_name") ?? "",
                project: row.string("source_project_name") ?? "",
                sessionID: row.string("source_session_id").map(SessionID.init),
                chat: row.string("source_chat") ?? ""
            ),
            target: WorkspaceMessageEnd(
                workspaceID: row.string("target_workspace_id").map(WorkspaceID.init),
                workspace: row.string("target_workspace_name") ?? "",
                project: row.string("target_project_name") ?? "",
                sessionID: row.string("target_session_id").map(SessionID.init),
                chat: row.string("target_chat") ?? ""
            ),
            replySessionID: row.string("reply_session_id").map(SessionID.init),
            text: row.string("body") ?? "",
            deliveryID: row.string("delivery_id").map(DeliveryID.init),
            state: WorkspaceMessage.State(rawValue: row.string("state") ?? "") ?? .cancelled,
            createdAt: row.date("created_at") ?? Date(),
            deliveredAt: row.date("delivered_at"),
            notifyWhenDone: row.bool("notify_when_done")
        )
    }

    private static func permissionGrant(from row: Row) -> PermissionGrant {
        let content = row.string("rule_content") ?? ""
        return PermissionGrant(
            id: PermissionGrantID(row.string("id") ?? newID()),
            repoID: RepoID(row.string("repo_id") ?? ""),
            toolName: row.string("tool_name") ?? "",
            ruleContent: content.isEmpty ? nil : content,
            grantedAt: row.date("granted_at") ?? Date(),
            lastUsedAt: row.date("last_used_at"),
            useCount: Int(row.int("use_count") ?? 0),
            grantedFor: row.string("granted_for") ?? ""
        )
    }

    private static func pendingPermissionAsk(from row: Row) -> PendingPermissionAsk? {
        guard let id = row.string("id"),
              let payload = row.data("payload"),
              let ask = PermissionAsk.decode(payload: payload)
        else {
            return nil
        }
        return PendingPermissionAsk(
            requestID: id,
            sessionID: SessionID(row.string("session_id") ?? ""),
            ask: ask,
            askedAt: row.date("created_at") ?? Date()
        )
    }

    private static func session(from row: Row) -> Session {
        var session = Session(
            id: SessionID(row.string("id") ?? newID()),
            workspaceID: row.string("workspace_id").map(WorkspaceID.init),
            parentSessionID: row.string("parent_session_id").map(SessionID.init),
            sideConversationParentID: row.string("side_conversation_parent_id").map(SessionID.init),
            title: row.string("title") ?? "Session",
            agentSessionID: row.string("agent_session_id"),
            model: row.string("model") ?? "opus",
            effort: row.string("effort") ?? "high",
            agentKind: AgentKind(rawValue: row.string("agent_kind") ?? "") ?? .claudeCode,
            permissionMode: PermissionMode(rawValue: row.string("permission_mode") ?? "") ?? .acceptEdits,
            interactionMode: InteractionMode(rawValue: row.string("interaction_mode") ?? "") ?? .build,
            state: SessionState(rawValue: row.string("state") ?? "idle") ?? .idle,
            sortOrder: Int(row.int("sort_order") ?? 0),
            createdAt: row.date("created_at") ?? Date(),
            updatedAt: row.date("updated_at") ?? Date(),
            archivedAt: row.date("archived_at"),
            lastReadSeq: Int(row.int("last_read_seq") ?? 0),
            inputTokens: Int(row.int("input_tokens") ?? 0),
            outputTokens: Int(row.int("output_tokens") ?? 0),
            costUSD: row.double("cost_usd") ?? 0,
            contextTokens: Int(row.int("context_tokens") ?? 0)
        )
        session.accountID = row.string("account_id").map(AgentAccountID.init)
        return session
    }

    private static func quickPrompt(from row: Row) -> QuickPrompt {
        QuickPrompt(
            id: QuickPromptID(row.string("id") ?? newID()),
            name: row.string("name") ?? "",
            symbol: row.string("symbol") ?? QuickPrompt.defaultSymbol,
            text: row.string("text") ?? "",
            sendsImmediately: row.int("sends_immediately") == 1,
            opensNewChat: row.int("opens_new_chat") == 1,
            sortOrder: Int(row.int("sort_order") ?? 0),
            createdAt: row.date("created_at") ?? Date()
        )
    }

    private static func reviewComment(from row: Row) -> ReviewComment {
        ReviewComment(
            id: ReviewCommentID(row.string("id") ?? newID()),
            workspaceID: WorkspaceID(row.string("workspace_id") ?? ""),
            filePath: row.string("file_path") ?? "",
            side: ReviewCommentSide(rawValue: row.string("side") ?? "") ?? .new,
            anchor: ReviewCommentAnchor(
                line: Int(row.int("line") ?? 1),
                text: row.string("line_text") ?? "",
                before: decodeContext(row.string("context_before")),
                after: decodeContext(row.string("context_after")),
                span: Int(row.int("span") ?? 1)
            ),
            body: row.string("body") ?? "",
            createdAt: row.date("created_at") ?? Date(),
            isAttached: row.bool("attached")
        )
    }

    private static func reviewedFile(from row: Row) -> ReviewedFile {
        ReviewedFile(
            workspaceID: WorkspaceID(row.string("workspace_id") ?? ""),
            path: row.string("file_path") ?? "",
            fingerprint: row.string("fingerprint") ?? "",
            viewedAt: row.date("viewed_at") ?? Date()
        )
    }

    private static func encodeContext(_ lines: [String]) -> String {
        guard let data = try? JSONEncoder().encode(lines) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeContext(_ raw: String?) -> [String] {
        guard let raw, let data = raw.data(using: .utf8),
              let lines = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return lines
    }

    private static func message(from row: Row) -> Message {
        Message(
            id: row.int("id") ?? 0,
            sessionID: SessionID(row.string("session_id") ?? ""),
            seq: Int(row.int("seq") ?? 0),
            kind: MessageKind(rawValue: row.string("kind") ?? "") ?? .system,
            payload: row.data("payload") ?? Data(),
            createdAt: row.date("created_at") ?? Date(),
            durationMS: row.int("duration_ms").map(Int.init),
            refID: row.string("ref_id")
        )
    }

    private static func ocean(from row: Row) -> Ocean {
        Ocean(
            name: row.string("name") ?? "",
            slug: row.string("slug") ?? "",
            latitude: row.double("latitude") ?? 0,
            longitude: row.double("longitude") ?? 0,
            usedAt: row.date("used_at")
        )
    }
}
