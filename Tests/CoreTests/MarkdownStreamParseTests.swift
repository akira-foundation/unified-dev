import Testing
import Foundation
@testable import Core

@Suite("Parsing a reply as it streams in, from the last block still open")
struct MarkdownStreamParseTests {
    static let documents: [String] = [
        """
        # Plan

        The parser reads the reply in pieces.

        ```swift
        let first = 1

        let second = 2
        ```

        - one
        - two

          still two

        - three

        | Name | Size |
        | :--- | ---: |
        | a | 1 |
        | b | 2 |

        Closing words.
        """,
        """
        1. first
        2. second

        - bullet after numbers

        > quoted line
        continued lazily

        Setext heading
        ====

            indented code

            more indented code
        back to text

        ---

        - [ ] open task
        - [x] done task

        Last paragraph with `code` and **strong** text.
        """,
        """
        Intro line
        | not | a table yet |

        | h1 | h2 |
        | -- | -- |

        after the table

        ~~~
        an unclosed fence

        with blank lines
        """,
        "First line\r\n\r\n- item\r\n- item two\r\n\r\nTail\r\n",
        """
        - outer
          - inner

          - inner loose

        - outer again

        Paragraph one.

        Paragraph two.

        Paragraph three.
        """,
    ]

    private func pieces(of text: String, sizes: [Int]) -> [String] {
        var prefixes: [String] = []
        var end = text.startIndex
        var turn = 0
        while end < text.endIndex {
            end = text.index(end, offsetBy: sizes[turn % sizes.count], limitedBy: text.endIndex) ?? text.endIndex
            prefixes.append(String(text[..<end]))
            turn += 1
        }
        return prefixes
    }

    @Test("every prefix, one character at a time, parses as the whole parser parses it", arguments: documents.indices)
    func everyCharacter(_ document: Int) {
        var stream = MarkdownStreamParse()
        for prefix in pieces(of: Self.documents[document], sizes: [1]) {
            let streamed = stream.blocks(for: prefix)
            #expect(streamed == MarkdownParser.parse(prefix), "differs at \(prefix.count) characters")
        }
    }

    @Test("pieces of uneven size end where the finished reply does", arguments: documents.indices)
    func unevenPieces(_ document: Int) {
        let text = Self.documents[document]
        var stream = MarkdownStreamParse()
        var last: [MarkdownBlock] = []
        for prefix in pieces(of: text, sizes: [7, 1, 23, 3, 64, 2]) {
            last = stream.blocks(for: prefix)
            #expect(last == MarkdownParser.parse(prefix))
        }
        #expect(last == MarkdownParser.parse(text))
    }

    @Test("a long reply settles most of itself, so a flush reads only the tail")
    func longReplySettles() {
        let section = Self.documents[0] + "\n\n"
        let text = String(repeating: section, count: 40)
        var stream = MarkdownStreamParse()
        for prefix in pieces(of: text, sizes: [50]) { _ = stream.blocks(for: prefix) }
        #expect(stream.blocks(for: text) == MarkdownParser.parse(text))
        #expect(stream.settledCharacters > text.utf8.count - section.utf8.count)
    }

    @Test("a reply replaced by another one is parsed from its start")
    func replacedReplyStartsOver() {
        var stream = MarkdownStreamParse()
        let first = "One paragraph.\n\nAnother paragraph.\n\nA third.\n"
        _ = stream.blocks(for: first)
        #expect(stream.settledCharacters > 0)
        let second = "- a different reply\n- with a list\n"
        #expect(stream.blocks(for: second) == MarkdownParser.parse(second))
    }

    @Test("a list item arriving after a blank line joins the list it continues")
    func looseListItemJoins() {
        var stream = MarkdownStreamParse()
        let before = "- one\n\n- tw"
        _ = stream.blocks(for: before)
        let after = "- one\n\n- two\n\nend\n"
        #expect(stream.blocks(for: after) == MarkdownParser.parse(after))
    }

    @Test("a table's delimiter arriving late turns the paragraph into a table")
    func lateTableDelimiter() {
        var stream = MarkdownStreamParse()
        _ = stream.blocks(for: "Intro\n\n| a | b |\n")
        let after = "Intro\n\n| a | b |\n| - | - |\n| 1 | 2 |\n"
        #expect(stream.blocks(for: after) == MarkdownParser.parse(after))
    }

    @Test("a delimiter row that stops being one gives its lines back to the paragraph above")
    func delimiterThatStopsBeingOne() {
        var stream = MarkdownStreamParse()
        let early = "Para\n| a | b |\n| --- | ---"
        #expect(stream.blocks(for: early) == MarkdownParser.parse(early))
        let later = "Para\n| a | b |\n| --- | --- x\n\nend\n"
        #expect(stream.blocks(for: later) == MarkdownParser.parse(later))
    }

    private func scalarPrefixes(of text: String) -> [String] {
        var scalars = String.UnicodeScalarView()
        return text.unicodeScalars.map { scalar in
            scalars.append(scalar)
            return String(scalars)
        }
    }

    @Test("a reply with accents and emoji is cut on the right byte")
    func nonASCIIReply() {
        let text = "Café crème 🎉 first.\n\nNaïve résumé second.\n\n- élan 🚀\n- über\n\nFin ✅.\n"
        var stream = MarkdownStreamParse()
        for prefix in pieces(of: text, sizes: [1]) {
            #expect(stream.blocks(for: prefix) == MarkdownParser.parse(prefix), "differs at \(prefix.count) characters")
        }
        #expect(stream.settledCharacters > 0)
    }

    @Test("a piece that ends between a carriage return and its line feed parses as the whole does")
    func carriageReturnSplitAcrossPieces() {
        let text = "One\r\n\r\nTwo\r\n\r\n- a\r\n- b\r\n\r\nThree\rFour\r\n"
        var stream = MarkdownStreamParse()
        for prefix in scalarPrefixes(of: text) {
            #expect(stream.blocks(for: prefix) == MarkdownParser.parse(prefix))
        }
    }

    @Test("a line of spaces counts as blank, so the blocks above it settle")
    func whitespaceLineSettles() {
        let text = "First paragraph.\n   \nSecond paragraph.\n \t \nThird.\n"
        var stream = MarkdownStreamParse()
        for prefix in pieces(of: text, sizes: [1]) {
            #expect(stream.blocks(for: prefix) == MarkdownParser.parse(prefix))
        }
        #expect(stream.settledCharacters >= "First paragraph.\n   \nSecond paragraph.\n \t \n".utf8.count)
    }

    @Test("the streamed blocks are the ones a reader expects, not only the ones the parser agrees with")
    func literalBlocks() {
        var stream = MarkdownStreamParse()
        _ = stream.blocks(for: "Intro\n\n- a\n")
        let blocks = stream.blocks(for: "Intro\n\n- a\n- b\n\n```\nx\n```\n")
        #expect(blocks == [
            .paragraph(inline: [.text("Intro")]),
            .bulletList(items: [[.paragraph(inline: [.text("a")])], [.paragraph(inline: [.text("b")])]], tight: true),
            .codeBlock(code: "x", language: Language.detect(fenceInfo: ""), info: ""),
        ])
    }
}
