import Foundation

enum AgentKindColumns {
    static let accountTable = "agent_accounts"

    static let namesThatHoldIt: Set<String> = ["provider", "agent_kind", "account_id"]

    static let aRenameMustMigrate: Set<String> = [
        "agent_accounts.id",
        "agent_accounts.provider",
        "agent_quotas.account_id",
        "agent_quotas.provider",
        "profile_agent_accounts.account_id",
        "profile_agent_accounts.provider",
        "repo_agent_accounts.account_id",
        "repo_agent_accounts.provider",
        "session_segments.account_id",
        "session_segments.agent_kind",
        "sessions.account_id",
        "sessions.agent_kind",
        "usage_files.provider",
        "usage_turns.provider",
    ]

    static func found(in db: SQLiteDatabase) throws -> Set<String> {
        var found: Set<String> = ["\(accountTable).id"]
        let tables = try db.query("SELECT name FROM sqlite_master WHERE type = 'table'")
            .compactMap { $0.string("name") }
        for table in tables {
            for column in try db.query("PRAGMA table_info(\(table));").compactMap({ $0.string("name") })
            where namesThatHoldIt.contains(column) {
                found.insert("\(table).\(column)")
            }
            for key in try db.query("PRAGMA foreign_key_list(\(table));")
            where key.string("table") == accountTable {
                guard let column = key.string("from") else { continue }
                found.insert("\(table).\(column)")
            }
        }
        return found
    }
}
