import Foundation
import Testing
@testable import Core

@Suite("Where a settings value ends")
struct SettingsDocumentValueEndTests {
    @Test("a one-line triple-quoted string inside an array does not hide the tables after it")
    func tripleQuotedInsideAnArray() {
        var document = SettingsDocument(text: """
        globs = ['''it's''', "b"]

        [git]
        archive_on_merge = false
        """)

        document.set(.boolean(true), at: ["git", "archive_on_merge"])

        #expect(document.text == """
        globs = ['''it's''', "b"]

        [git]
        archive_on_merge = true
        """)
    }

    @Test("a multi-line string or a comment inside an array does not hide the tables after it")
    func multiLineArrayKeepsLaterTables() {
        for text in [TOMLFixture.multiLineArray, TOMLFixture.commentedArray] {
            var document = SettingsDocument(text: text)

            document.set(.boolean(true), at: ["git", "archive_on_merge"])

            #expect(document.text == text.replacingOccurrences(
                of: "archive_on_merge = false", with: "archive_on_merge = true"
            ))
        }
    }

    @Test("removing a key that is not there leaves an inline table as it was written")
    func removeOfAnAbsentKeyChangesNothing() {
        let text = """
        [scripts.run]
        dev = { command = "bun dev" }
        """
        var document = SettingsDocument(text: text)

        document.remove(at: ["scripts", "run", "dev", "file"])

        #expect(document.text == text)
    }
}

private enum TOMLFixture {
    static let multiLineArray = #"""
    globs = ["""
    a
    """, "b"] # two

    [git]
    archive_on_merge = false
    """#

    static let commentedArray = """
    globs = [
      "a", # the first
      "b",
    ]

    [git]
    archive_on_merge = false
    """
}
