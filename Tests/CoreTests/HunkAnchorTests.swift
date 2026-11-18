import Foundation
import Testing
@testable import Core

@Suite("Anchoring a hunk patch to the whole file")
struct HunkAnchorTests {
    private func anchored(_ hunk: DiffHunk, in whole: String) -> String? {
        HunkPatch.anchor(hunk, in: Data(whole.utf8)).map { String(decoding: $0, as: UTF8.self) }
    }

    private static let whole = """
        diff --git a/f.txt b/f.txt
        index 1111111..2222222 100644
        --- a/f.txt
        +++ b/f.txt
        @@ -1,5 +1,5 @@
         one
        -two
        +TWO
         three
        -four
        +FOUR
         five

        """

    private static let narrow = """
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -2,1 +2,1 @@
        -two
        +TWO
        @@ -4,1 +4,1 @@
        -four
        +FOUR

        """

    @Test("bytes that are not UTF-8 reach the anchored patch exactly as git wrote them")
    func keepsBytesThatAreNotUTF8() throws {
        let latin = Data(Self.whole.utf8.map { $0 == UInt8(ascii: "v") ? 0xE9 : $0 })
        let hunk = try #require(DiffParser.parse(Self.narrow).first?.hunks.first)
        let expected = """
            diff --git a/f.txt b/f.txt
            --- a/f.txt
            +++ b/f.txt
            @@ -1,5 +1,5 @@
             one
            -two
            +TWO
             three
             FOUR
             five

            """

        #expect(HunkPatch.anchor(hunk, in: latin) == Data(expected.utf8.map { $0 == UInt8(ascii: "v") ? 0xE9 : $0 }))
    }

    @Test("anchoring keeps the chosen hunk and turns every other change into context")
    func anchoredFirstHunk() throws {
        let hunk = try #require(DiffParser.parse(Self.narrow).first?.hunks.first)

        #expect(anchored(hunk, in: Self.whole) == """
            diff --git a/f.txt b/f.txt
            --- a/f.txt
            +++ b/f.txt
            @@ -1,5 +1,5 @@
             one
            -two
            +TWO
             three
             FOUR
             five

            """)
    }

    @Test("the hunk below is found by the lines above it, not by its text alone")
    func anchoredSecondHunk() throws {
        let hunk = try #require(DiffParser.parse(Self.narrow).first?.hunks.last)

        #expect(anchored(hunk, in: Self.whole) == """
            diff --git a/f.txt b/f.txt
            --- a/f.txt
            +++ b/f.txt
            @@ -1,5 +1,5 @@
             one
             TWO
             three
            -four
            +FOUR
             five

            """)
    }

    @Test("a hunk that only deletes is found at the line git names")
    func anchoredDeletion() throws {
        let narrow = """
            diff --git a/f.txt b/f.txt
            --- a/f.txt
            +++ b/f.txt
            @@ -3,1 +2,0 @@
            -three

            """
        let whole = """
            diff --git a/f.txt b/f.txt
            --- a/f.txt
            +++ b/f.txt
            @@ -1,4 +1,3 @@
             one
             two
            -three
             four

            """
        let hunk = try #require(DiffParser.parse(narrow).first?.hunks.first)
        #expect(hunk.newCount == 0)

        #expect(anchored(hunk, in: whole) == """
            diff --git a/f.txt b/f.txt
            --- a/f.txt
            +++ b/f.txt
            @@ -1,4 +1,3 @@
             one
             two
            -three
             four

            """)
    }

    @Test("a file emptied of every line keeps git's zero line numbers")
    func anchoredEmptiedFile() throws {
        let whole = """
            diff --git a/f.txt b/f.txt
            --- a/f.txt
            +++ b/f.txt
            @@ -1,2 +0,0 @@
            -one
            -two

            """
        let hunk = try #require(DiffParser.parse(whole).first?.hunks.first)

        #expect(anchored(hunk, in: whole) == whole)
    }

    @Test("the no newline marker of a line nobody is restoring goes with it")
    func anchoredNoNewlineMarkers() throws {
        let narrow = """
            diff --git a/f.txt b/f.txt
            --- a/f.txt
            +++ b/f.txt
            @@ -1,1 +1,1 @@
            -one
            +ONE

            """
        let whole = """
            diff --git a/f.txt b/f.txt
            --- a/f.txt
            +++ b/f.txt
            @@ -1,2 +1,2 @@
            -one
            +ONE
            -two
            \\ No newline at end of file
            +TWO
            \\ No newline at end of file

            """
        let hunk = try #require(DiffParser.parse(narrow).first?.hunks.first)

        #expect(anchored(hunk, in: whole) == """
            diff --git a/f.txt b/f.txt
            --- a/f.txt
            +++ b/f.txt
            @@ -1,2 +1,2 @@
            -one
            +ONE
             TWO
            \\ No newline at end of file

            """)
    }

    @Test("a patch git did not merge into one hunk cannot be anchored")
    func anchorNeedsOneHunk() throws {
        let hunk = try #require(DiffParser.parse(Self.narrow).first?.hunks.first)

        #expect(anchored(hunk, in: Self.narrow) == nil)
    }
}
