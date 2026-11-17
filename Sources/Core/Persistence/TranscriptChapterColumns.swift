import Foundation

enum TranscriptChapterColumns {
    static let createTable = """
        CREATE TABLE IF NOT EXISTS transcript_chapters (
            session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            seq INTEGER NOT NULL,
            title TEXT NOT NULL,
            PRIMARY KEY (session_id, seq)
        );
        """

    static let forSession = "SELECT seq, title FROM transcript_chapters WHERE session_id = ? ORDER BY seq"

    static let pin = """
        INSERT INTO transcript_chapters (session_id, seq, title) VALUES (?, ?, ?)
        ON CONFLICT(session_id, seq) DO UPDATE SET title = excluded.title
        """

    static let unpin = "DELETE FROM transcript_chapters WHERE session_id = ? AND seq = ?"

    static let unpinFrom = "DELETE FROM transcript_chapters WHERE session_id = ? AND seq >= ?"

    static func chapter(from row: Row) -> TranscriptChapter? {
        guard let seq = row.int("seq"), let title = row.string("title") else { return nil }
        return TranscriptChapter(seq: Int(seq), title: title)
    }
}
