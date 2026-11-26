import Foundation

enum LostAgentAccountChoices {
    static let settingKey = "agent_accounts.lost_choices"

    static func record(stranded: String, in db: SQLiteDatabase) throws {
        let found = try db.query(stranded).compactMap { $0.string("id") }
        guard !found.isEmpty else { return }
        let earlier = try db.query("SELECT value FROM settings WHERE key = ?", [.text(settingKey)])
            .first?.string("value").map(decoded) ?? []
        let ids = earlier + found.filter { !earlier.contains($0) }
        let value = String(decoding: try JSONEncoder().encode(ids), as: UTF8.self)
        try db.run(
            "INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            [.text(settingKey), .text(value)]
        )
    }

    static func decoded(_ value: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(value.utf8))) ?? []
    }
}
