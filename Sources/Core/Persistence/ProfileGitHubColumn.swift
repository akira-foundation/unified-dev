import Foundation

enum ProfileGitHubColumn {
    static let column = "github_source"
    static let sources = "SELECT id, \(column) AS source FROM profiles"
    static let setSource = "UPDATE profiles SET \(column) = ? WHERE id = ?"

    static func migrate(_ db: SQLiteDatabase) throws {
        let columns = Set(try db.query("PRAGMA table_info(profiles);").compactMap { $0.string("name") })
        guard !columns.isEmpty, !columns.contains(column) else { return }
        try db.execute(
            "ALTER TABLE profiles ADD COLUMN \(column) TEXT NOT NULL DEFAULT '\(ProfileGitHubSource.inherits.rawValue)';"
        )
    }

    static func sources(reading query: (String) throws -> [Row]) throws -> [ProfileID: ProfileGitHubSource] {
        var result: [ProfileID: ProfileGitHubSource] = [:]
        for row in try query(sources) {
            guard let id = row.string("id"), let source = ProfileGitHubSource(rawValue: row.string("source") ?? "")
            else { continue }
            result[ProfileID(id)] = source
        }
        return result
    }
}
