import Foundation

enum QuotaAccountColumn {
    static let column = "account_id"

    static let unknown = ""

    static let createTable = """
        CREATE TABLE agent_quotas (
            provider TEXT NOT NULL,
            account_id TEXT NOT NULL DEFAULT '',
            window_key TEXT NOT NULL,
            window_label TEXT NOT NULL,
            window_seconds REAL,
            used REAL,
            limit_value REAL,
            unit TEXT,
            resets_at REAL,
            observed_at REAL NOT NULL,
            PRIMARY KEY (provider, account_id, window_key)
        );
        """

    static let forget = "DELETE FROM agent_quotas WHERE provider = ? AND account_id = ?"

    static func migrate(_ db: SQLiteDatabase) throws {
        let columns = Set(try db.query("PRAGMA table_info(agent_quotas);").compactMap { $0.string("name") })
        guard !columns.contains(column) else { return }
        try db.execute("DROP TABLE IF EXISTS agent_quotas;")
        try db.execute(createTable)
    }

    static func value(_ account: AgentAccountID?) -> SQLValue {
        .text(account?.rawValue ?? unknown)
    }

    static func account(from row: Row) -> AgentAccountID? {
        guard let raw = row.string(column), raw != unknown else { return nil }
        return AgentAccountID(raw)
    }
}
