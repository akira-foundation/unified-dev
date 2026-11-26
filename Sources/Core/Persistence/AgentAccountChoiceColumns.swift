import Foundation

enum AgentAccountChoiceColumns {
    struct Table: Sendable {
        let name: String
        let owner: String
        let parent: String

        var createTable: String {
            """
            CREATE TABLE IF NOT EXISTS \(name) (
                \(owner) TEXT NOT NULL REFERENCES \(parent)(id) ON DELETE CASCADE,
                provider TEXT NOT NULL,
                account_id TEXT NOT NULL REFERENCES agent_accounts(id) ON DELETE CASCADE,
                PRIMARY KEY (\(owner), provider)
            );
            """
        }

        var all: String { "SELECT \(owner) AS owner, provider, account_id FROM \(name)" }

        var choose: String {
            """
            INSERT INTO \(name) (\(owner), provider, account_id) VALUES (?, ?, ?)
            ON CONFLICT(\(owner), provider) DO UPDATE SET account_id = excluded.account_id
            """
        }

        var clear: String { "DELETE FROM \(name) WHERE \(owner) = ? AND provider = ?" }

        var carry: String {
            """
            INSERT OR IGNORE INTO \(name) (\(owner), provider, account_id)
            SELECT \(parent).id, agent_accounts.provider, \(parent).account_id
            FROM \(parent) JOIN agent_accounts ON agent_accounts.id = \(parent).account_id
            WHERE \(parent).account_id IS NOT NULL;
            """
        }

        var strangers: String {
            """
            SELECT DISTINCT account_id AS id FROM \(parent)
            WHERE account_id IS NOT NULL
              AND account_id NOT IN (SELECT id FROM agent_accounts);
            """
        }

        var stranded: String {
            """
            SELECT id FROM \(parent)
            WHERE account_id IS NOT NULL
              AND account_id NOT IN (SELECT id FROM agent_accounts)
            ORDER BY id;
            """
        }

        var drop: String { "ALTER TABLE \(parent) DROP COLUMN account_id;" }
    }

    static let repos = Table(name: "repo_agent_accounts", owner: "repo_id", parent: "repos")

    static let workspaceChoiceTable = "workspace_agent_accounts"

    private static let workspaces = Table(
        name: workspaceChoiceTable, owner: "workspace_id", parent: "workspaces"
    )

    static let profiles = Table(name: "profile_agent_accounts", owner: "profile_id", parent: "profiles")

    static let repoProfiles = "SELECT id, \(ProfileColumns.column) AS profile_id FROM repos"

    static func migrate(_ db: SQLiteDatabase, defaults: [AgentAccountHome]? = nil) throws {
        try db.transaction { try move(db, defaults: defaults) }
    }

    static func move(_ db: SQLiteDatabase, defaults: [AgentAccountHome]? = nil) throws {
        var homes = defaults
        if try columns(of: workspaces.parent, in: db).contains("account_id") {
            try registerDefaults(named: workspaces, in: db, homes: &homes)
            try recordOnChats(
                choices: """
                SELECT workspaces.id AS workspace_id, agent_accounts.provider, workspaces.account_id
                FROM workspaces JOIN agent_accounts ON agent_accounts.id = workspaces.account_id
                """,
                in: db
            )
            try db.execute(workspaces.drop)
        }
        try db.execute(repos.createTable)
        guard try columns(of: repos.parent, in: db).contains("account_id") else { return }
        try registerDefaults(named: repos, in: db, homes: &homes)
        try LostAgentAccountChoices.record(stranded: repos.stranded, in: db)
        try db.execute(repos.carry)
        try db.execute(repos.drop)
    }

    static func forgetWorkspaceChoices(_ db: SQLiteDatabase) throws {
        if try !columns(of: workspaceChoiceTable, in: db).isEmpty {
            try recordOnChats(
                choices: "SELECT workspace_id, provider, account_id FROM \(workspaceChoiceTable)", in: db
            )
        }
        try db.execute("DROP TABLE IF EXISTS \(workspaceChoiceTable);")
    }

    private static func registerDefaults(
        named table: Table, in db: SQLiteDatabase, homes: inout [AgentAccountHome]?
    ) throws {
        for id in try db.query(table.strangers).compactMap({ $0.string("id") }) {
            guard let provider = AgentAccountHome.provider(ofDefaultID: AgentAccountID(id)) else { continue }
            if homes == nil { homes = SpendAccounts.defaultHomes() }
            guard let home = homes?.first(where: { $0.provider == provider }) else { continue }
            try db.run(AgentAccountColumns.insertIfMissing, AgentAccountColumns.values(AgentAccountRow(
                id: home.id, provider: provider, directory: home.directory.path, isDefault: true
            )))
        }
    }

    private static func recordOnChats(choices: String, in db: SQLiteDatabase) throws {
        let chosen = """
            SELECT choice.account_id FROM (\(choices)) AS choice
            JOIN agent_accounts ON agent_accounts.id = choice.account_id
            WHERE choice.workspace_id = sessions.workspace_id AND choice.provider = sessions.agent_kind
            """
        try db.execute("""
            UPDATE sessions SET account_id = (\(chosen))
            WHERE account_id IS NULL AND COALESCE(agent_session_id, '') <> '' AND EXISTS (\(chosen));
            """)
        guard try !columns(of: "session_segments", in: db).isEmpty else { return }
        let segmentChosen = """
            SELECT choice.account_id FROM (\(choices)) AS choice
            JOIN agent_accounts ON agent_accounts.id = choice.account_id
            JOIN sessions ON sessions.workspace_id = choice.workspace_id
            WHERE sessions.id = session_segments.session_id AND choice.provider = session_segments.agent_kind
            """
        try db.execute("""
            UPDATE session_segments SET account_id = (\(segmentChosen))
            WHERE is_active = 1 AND account_id IS NULL AND COALESCE(agent_session_id, '') <> ''
              AND EXISTS (\(segmentChosen));
            """)
    }

    private static func columns(of table: String, in db: SQLiteDatabase) throws -> Set<String> {
        Set(try db.query("PRAGMA table_info(\(table));").compactMap { $0.string("name") })
    }

    static func book(reading query: (String) throws -> [Row]) throws -> AgentAccountChoiceBook {
        var book = AgentAccountChoiceBook()
        for row in try query(repos.all) {
            guard let read = read(row) else { continue }
            book.record(read.account, of: read.provider, forRepo: RepoID(read.owner))
        }
        for row in try query(profiles.all) {
            guard let read = read(row) else { continue }
            book.record(read.account, of: read.provider, forProfile: ProfileID(read.owner))
        }
        for row in try query(repoProfiles) {
            guard let repo = row.string("id"), let profile = row.string("profile_id") else { continue }
            book.repoProfiles[RepoID(repo)] = ProfileID(profile)
        }
        book.accounts = try ProfileAccountColumns.accounts(reading: query)
        return book
    }

    private static func read(_ row: Row) -> (owner: String, provider: AgentKind, account: AgentAccountID)? {
        guard let owner = row.string("owner"),
              let provider = AgentKind(rawValue: row.string("provider") ?? ""),
              let account = row.string("account_id")
        else { return nil }
        return (owner, provider, AgentAccountID(account))
    }
}
