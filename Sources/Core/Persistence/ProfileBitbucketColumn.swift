import Foundation

enum ProfileBitbucketColumn {
    static let column = "bitbucket_source"
    static let sources = "SELECT id, \(column) AS source FROM profiles"
    static let setSource = "UPDATE profiles SET \(column) = ? WHERE id = ?"

    static func migrate(_ db: SQLiteDatabase) throws {
        let columns = Set(try db.query("PRAGMA table_info(profiles);").compactMap { $0.string("name") })
        guard !columns.isEmpty, !columns.contains(column) else { return }
        try db.execute(
            "ALTER TABLE profiles ADD COLUMN \(column) TEXT NOT NULL DEFAULT '\(ProfileGitHubSource.inherits.rawValue)';"
        )
        guard columns.contains(ProfileGitHubColumn.column) else { return }
        try db.execute("UPDATE profiles SET \(column) = \(ProfileGitHubColumn.column);")
    }

    static func sources(reading query: (String) throws -> [Row]) throws -> [ProfileID: ProfileGitHubSource] {
        try ProfileGitHubColumn.sources(reading: query, select: sources)
    }
}
