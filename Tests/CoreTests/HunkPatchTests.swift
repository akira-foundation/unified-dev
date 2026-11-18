import Foundation
import Testing
@testable import Core

@Suite("Cutting one hunk out of a patch")
struct HunkPatchTests {
    private func isolated(_ hunk: DiffHunk, from patch: String) -> String? {
        HunkPatch.isolate(hunk, from: Data(patch.utf8)).map { String(decoding: $0, as: UTF8.self) }
    }

    private func oldSide(_ line: String) -> String? {
        HunkPatch.oldSide(of: Array(line.utf8)).map { String(decoding: $0, as: UTF8.self) }
    }

    private static let renamed = """
        diff --git a/old.txt b/new.txt
        similarity index 90%
        rename from old.txt
        rename to new.txt
        index 1111111..2222222 100644
        --- a/old.txt
        +++ b/new.txt
        @@ -1,2 +1,2 @@
        -a
        +A
         b
        @@ -9,2 +9,2 @@
         i
        -j
        +J

        """

    @Test("the last hunk keeps its lines and gets a plain header named after the destination")
    func lastHunk() throws {
        let hunk = try #require(DiffParser.parse(Self.renamed).first?.hunks.last)
        #expect(isolated(hunk, from: Self.renamed) == """
            diff --git a/new.txt b/new.txt
            --- a/new.txt
            +++ b/new.txt
            @@ -9,2 +9,2 @@
             i
            -j
            +J

            """)
    }

    @Test("the first hunk stops where the next one starts")
    func firstHunk() throws {
        let hunk = try #require(DiffParser.parse(Self.renamed).first?.hunks.first)
        #expect(isolated(hunk, from: Self.renamed) == """
            diff --git a/new.txt b/new.txt
            --- a/new.txt
            +++ b/new.txt
            @@ -1,2 +1,2 @@
            -a
            +A
             b

            """)
    }

    @Test("a hunk whose coordinates or lines moved is not found")
    func movedHunk() throws {
        let hunk = try #require(DiffParser.parse(Self.renamed).first?.hunks.last)
        var shifted = hunk
        shifted.oldStart = 10
        var edited = hunk
        edited.lines[1].text = "k"
        #expect(isolated(shifted, from: Self.renamed) == nil)
        #expect(isolated(edited, from: Self.renamed) == nil)
    }

    @Test("the no newline marker travels with its hunk")
    func noNewlineMarker() throws {
        let patch = """
            diff --git a/f.txt b/f.txt
            index 1111111..2222222 100644
            --- a/f.txt
            +++ b/f.txt
            @@ -1,2 +1,2 @@
             a
            -b
            \\ No newline at end of file
            +B
            \\ No newline at end of file

            """
        let hunk = try #require(DiffParser.parse(patch).first?.hunks.first)
        #expect(isolated(hunk, from: patch) == """
            diff --git a/f.txt b/f.txt
            --- a/f.txt
            +++ b/f.txt
            @@ -1,2 +1,2 @@
             a
            -b
            \\ No newline at end of file
            +B
            \\ No newline at end of file

            """)
    }

    @Test("a patch of two files is not cut")
    func twoFiles() throws {
        let one = """
            diff --git a/a.txt b/a.txt
            --- a/a.txt
            +++ b/a.txt
            @@ -1 +1 @@
            -a
            +A

            """
        let two = one + one.replacingOccurrences(of: "a.txt", with: "b.txt")
        let hunk = try #require(DiffParser.parse(one).first?.hunks.first)
        #expect(isolated(hunk, from: two) == nil)
    }

    private static let third = """
        diff --git a/f.txt b/f.txt
        index 1111111..2222222 100644
        --- a/f.txt
        +++ b/f.txt
        @@ -2,3 +2,3 @@
         two
        -three
        +THREE
         four

        """

    @Test("a name with a space is named in the header without git's trailing tab")
    func spacedHeader() throws {
        let patch = """
            diff --git a/sneaky b/decoy.txt b/sneaky b/decoy.txt
            index 1111111..2222222 100644
            --- a/sneaky b/decoy.txt\t
            +++ b/sneaky b/decoy.txt\t
            @@ -1,2 +1,2 @@
             a
            -b
            +B

            """
        let hunk = try #require(DiffParser.parse(patch).first?.hunks.first)
        #expect(isolated(hunk, from: patch) == """
            diff --git a/sneaky b/decoy.txt b/sneaky b/decoy.txt
            --- a/sneaky b/decoy.txt\t
            +++ b/sneaky b/decoy.txt\t
            @@ -1,2 +1,2 @@
             a
            -b
            +B

            """)
    }

    @Test("a name git quotes is quoted the same way in the header")
    func quotedHeader() throws {
        let patch = """
            diff --git "a/say \\"hi\\".txt" "b/say \\"hi\\".txt"
            index 1111111..2222222 100644
            --- "a/say \\"hi\\".txt"\t
            +++ "b/say \\"hi\\".txt"\t
            @@ -1,2 +1,2 @@
             a
            -b
            +B

            """
        let hunk = try #require(DiffParser.parse(patch).first?.hunks.first)
        #expect(isolated(hunk, from: patch) == """
            diff --git "a/say \\"hi\\".txt" "b/say \\"hi\\".txt"
            --- "a/say \\"hi\\".txt"\t
            +++ "b/say \\"hi\\".txt"\t
            @@ -1,2 +1,2 @@
             a
            -b
            +B

            """)
    }

    @Test("bytes that are not UTF-8 reach the isolated patch exactly as git wrote them")
    func isolateKeepsBytesThatAreNotUTF8() throws {
        let latin = Data(Self.renamed.utf8.map { $0 == UInt8(ascii: "j") ? 0xE9 : $0 })
        let hunk = try #require(DiffParser.parse(String(decoding: latin, as: UTF8.self)).first?.hunks.last)
        let expected = """
            diff --git a/new.txt b/new.txt
            --- a/new.txt
            +++ b/new.txt
            @@ -9,2 +9,2 @@
             i
            -j
            +J

            """

        #expect(HunkPatch.isolate(hunk, from: latin) == Data(expected.utf8.map { $0 == UInt8(ascii: "j") ? 0xE9 : $0 }))
    }

    @Test("only an added line that is not UTF-8 makes a hunk one that cannot be checked")
    func addedLinesThatAreNotUTF8() {
        let removed = Data("diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1 +1 @@\n-caf".utf8) + Data([0xE9, 0x0A])
            + Data("+cafe\n".utf8)
        let added = Data("diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1 +1 @@\n-cafe\n+caf".utf8) + Data([0xE9, 0x0A])
        let header = Data("diff --git a/f b/f\n--- a/f\n+++ b/caf".utf8) + Data([0xE9, 0x0A])
            + Data("@@ -1 +1 @@\n-a\n+b\n".utf8)

        #expect(!HunkPatch.addsLinesThatAreNotUTF8(removed))
        #expect(HunkPatch.addsLinesThatAreNotUTF8(added))
        #expect(!HunkPatch.addsLinesThatAreNotUTF8(header))
        #expect(!HunkPatch.addsLinesThatAreNotUTF8(Data("@@ -1 +1 @@\n-a\n+caf\u{e9}\n".utf8)))
    }

    @Test("an added line that is not UTF-8 in another hunk is context once anchored, so it does not refuse")
    func otherHunkAddingLinesThatAreNotUTF8() throws {
        let whole = Data("diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1,3 +1,3 @@\n-a\n+A\n b\n-c\n+caf".utf8)
            + Data([0xE9, 0x0A])
        let narrow = "diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1 +1 @@\n-a\n+A\n@@ -3 +3 @@\n-c\n+caf\u{fffd}\n"
        let hunk = try #require(DiffParser.parse(narrow).first?.hunks.first)

        let anchored = try #require(HunkPatch.anchor(hunk, in: whole))

        #expect(HunkPatch.addsLinesThatAreNotUTF8(whole))
        #expect(!HunkPatch.addsLinesThatAreNotUTF8(anchored))
    }

    @Test("a quoted destination keeps its quotes and git's trailing tab")
    func quotedPaths() {
        #expect(oldSide("+++ \"b/moved \\303\\251.txt\"\t") == "--- \"a/moved \\303\\251.txt\"\t")
        #expect(oldSide("+++ \"b/say \\\"hi\\\".txt\"") == "--- \"a/say \\\"hi\\\".txt\"")
        #expect(oldSide("+++ b/plain.txt") == "--- a/plain.txt")
        #expect(oldSide("+++ b/my file.txt\t") == "--- a/my file.txt\t")
        #expect(oldSide("+++ /dev/null") == nil)
    }
}
