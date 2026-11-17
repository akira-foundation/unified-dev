import Foundation

public struct TranscriptChapter: Equatable, Hashable, Sendable, Identifiable {
    public var seq: Int
    public var title: String

    public var id: Int { seq }

    public init(seq: Int, title: String) {
        self.seq = seq
        self.title = title
    }

    public static let titleLimit = 60

    public init?(seq: Int, kind: MessageKind, payload: Data) {
        guard let text = MessageCopyText.plain(kind: kind, payload: payload),
              let title = Self.title(of: text) else { return nil }
        self.init(seq: seq, title: title)
    }

    public static func title(of text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line else { return nil }
        let words = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard words.count > titleLimit else { return words }
        let cut = words.prefix(titleLimit - 1)
        let whole = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return whole.trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    public static func ordered(_ chapters: [TranscriptChapter]) -> [TranscriptChapter] {
        chapters.sorted { $0.seq < $1.seq }
    }
}
