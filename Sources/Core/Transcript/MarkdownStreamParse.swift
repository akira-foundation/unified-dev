import Foundation

public struct MarkdownStreamParse: Sendable {
    private var settledText = ""
    private var settledBlocks: [MarkdownBlock] = []

    public init() {}

    public var settledCharacters: Int { settledText.utf8.count }

    public mutating func blocks(for text: String) -> [MarkdownBlock] {
        let normalized = MarkdownParser.normalized(text)
        if !normalized.utf8.starts(with: settledText.utf8) {
            settledText = ""
            settledBlocks = []
        }
        let tail = String(decoding: normalized.utf8.dropFirst(settledText.utf8.count), as: UTF8.self)
        let lines = tail.components(separatedBy: "\n")
        let parsed = MarkdownParser.parse(lines: lines)
        let blocks = settledBlocks + parsed.blocks
        if let cut = parsed.starts.indices.dropFirst().last(where: { Self.settles(at: parsed.starts[$0], in: lines) }) {
            let line = parsed.starts[cut]
            settledText += lines[..<line].joined(separator: "\n") + "\n"
            settledBlocks += parsed.blocks[..<cut]
        }
        return blocks
    }

    private static func settles(at line: Int, in lines: [String]) -> Bool {
        line > 0 && line < lines.count - 1 && MarkdownParser.isBlankLine(lines[line - 1])
    }
}
