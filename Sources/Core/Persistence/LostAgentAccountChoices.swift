import Foundation

enum LostAgentAccountChoices {
    static let settingKey = "agent_accounts.lost_choices"

    static func record(stranded: String, in db: SQLiteDatabase) throws {
        let found = try db.query(stranded).compactMap { $0.string("id") }
        guard !found.isEmpty else { return }
        let value = String(decoding: try JSONEncoder().encode(found), as: UTF8.self)
        try db.run(SettingsColumns.write, [.text(settingKey), .text(value)])
    }

    static func decoded(_ value: String) -> [RepoID] {
        ((try? JSONDecoder().decode([String].self, from: Data(value.utf8))) ?? []).map { RepoID($0) }
    }
}
