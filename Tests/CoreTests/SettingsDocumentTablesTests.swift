import Testing
import Foundation
@testable import Core

@Suite("Settings document, a table already written another way")
struct SettingsDocumentTablesTests {
    @Test("a key added to an inline table opens it into a table instead of defining it twice")
    func inlineTableIsOpened() {
        var document = SettingsDocument(text: """
        name = "ada"
        git = { archive_on_merge = true }
        """)

        document.set(.boolean(true), at: ["git", "delete_branch_on_archive"])

        #expect(document.text == """
        name = "ada"

        [git]
        archive_on_merge = true
        delete_branch_on_archive = true
        """)
    }

    @Test("a key already inside an inline table is changed there, not written a second time")
    func inlineKeyIsReplaced() {
        var document = SettingsDocument(text: "git = { archive_on_merge = true, delete_branch_on_archive = false } # mine\n")

        document.set(.boolean(true), at: ["git", "delete_branch_on_archive"])

        #expect(document.text == """
        # mine
        [git]
        archive_on_merge = true
        delete_branch_on_archive = true

        """)
    }

    @Test("an escaped quote and a comma inside a string stay one value")
    func escapedQuoteStaysInsideTheString() {
        var document = SettingsDocument(text: #"git = { note = "say \"hi, there\"", archive_on_merge = true }"#)

        document.set(.boolean(true), at: ["git", "delete_branch_on_archive"])

        #expect(document.text == #"""
        [git]
        note = "say \"hi, there\""
        archive_on_merge = true
        delete_branch_on_archive = true
        """#)
    }

    @Test("an inline table inside an inline table is opened one level at a time")
    func nestedInlineTablesOpenInTurn() {
        var document = SettingsDocument(text: #"scripts.run = { dev = { command = "bun dev", "file" = "a, b" } }"#)

        document.set(.string("web"), at: ["scripts", "run", "dev", "name"])

        #expect(document.text == #"""
        [scripts.run]

        [scripts.run.dev]
        command = "bun dev"
        "file" = "a, b"
        name = "web"
        """#)
    }

    @Test("a key beside dotted keys is written dotted beside them, not under a second definition")
    func dottedKeysGetADottedSibling() {
        var document = SettingsDocument(text: """
        git.archive_on_merge = true
        other = 1
        """)

        document.set(.boolean(false), at: ["git", "delete_branch_on_archive"])

        #expect(document.text == """
        git.archive_on_merge = true
        git.delete_branch_on_archive = false
        other = 1
        """)
    }

    @Test("a dotted value over several lines is passed whole before the new key")
    func dottedMultiLineValueStaysWhole() {
        var document = SettingsDocument(text: """
        git.list = [
          "a",
        ]
        """)

        document.set(.boolean(true), at: ["git", "delete_branch_on_archive"])

        #expect(document.text == """
        git.list = [
          "a",
        ]
        git.delete_branch_on_archive = true
        """)
    }

    @Test("lines inside a multi-line script are never read as keys or tables")
    func scriptLinesStayInTheScript() {
        let script = """
        [scripts]
        setup = '''
        git.archive_on_merge = true
        [git]
        '''
        """
        var document = SettingsDocument(text: script)

        document.set(.boolean(true), at: ["git", "delete_branch_on_archive"])

        #expect(document.text == script + "\n\n[git]\ndelete_branch_on_archive = true")
    }

    @Test("a table header followed by a comment still owns the keys under it")
    func headerWithACommentKeepsItsKeys() {
        var document = SettingsDocument(text: """
        [other] # note
        git = { a = 1 }
        """)

        document.set(.boolean(true), at: ["git", "b"])

        #expect(document.text == """
        [other] # note
        git = { a = 1 }

        [git]
        b = true
        """)
    }

    @Test("a dotted key inside a table gets its sibling written relative to that table")
    func dottedSiblingInsideATable() {
        var document = SettingsDocument(text: """
        [scripts]
          run.dev.command = "bun dev"
          run.dev.file = "a"
        setup = "bun install"
        """)

        document.set(.string("web"), at: ["scripts", "run", "dev", "name"])

        #expect(document.text == """
        [scripts]
          run.dev.command = "bun dev"
          run.dev.file = "a"
          run.dev.name = "web"
        setup = "bun install"
        """)
    }

    @Test("a header written inside a script is neither listed nor where a removed table stops")
    func headerInsideAScriptIsNotATable() {
        var document = SettingsDocument(text: """
        [scripts.run.dev]
        command = '''
        echo
        [scripts.run.fake]
        '''

        [scripts.run.web]
        command = "bun web"
        """)

        #expect(document.tables(under: ["scripts", "run"]) == [["scripts", "run", "dev"], ["scripts", "run", "web"]])

        document.removeTable(at: ["scripts", "run", "dev"])

        #expect(document.text == """
        [scripts.run.web]
        command = "bun web"
        """)
    }

    @Test("removing a key opens the inline table that holds it")
    func removeOpensInlineTable() {
        var document = SettingsDocument(text: """
        [scripts.run]
        dev = { command = "bun dev", name = "web" }
        """)

        document.remove(at: ["scripts", "run", "dev", "command"])

        #expect(document.text == """
        [scripts.run]

        [scripts.run.dev]
        name = "web"
        """)
    }

    @Test("an inline table in an array of tables is left where it is")
    func arrayOfTablesIsLeftAlone() {
        let text = """
        [[git]]
        remote = { name = "a" }
        """
        var document = SettingsDocument(text: text)

        document.set(.boolean(true), at: ["git", "remote", "x"])

        #expect(document.text.hasPrefix(text))
        #expect(document.text.contains("remote = { name = \"a\" }"))
    }

    @Test("a dotted key that is already the one being set is changed where it stands")
    func dottedKeyIsReplacedInPlace() {
        var document = SettingsDocument(text: "git.delete_branch_on_archive = false\n")

        document.set(.boolean(true), at: ["git", "delete_branch_on_archive"])

        #expect(document.text == "git.delete_branch_on_archive = true\n")
    }

    @Test("a sub-table's own keys are not taken into its parent")
    func subTableKeysStay() {
        var document = SettingsDocument(text: """
        [git.remote]
        name = "origin"
        """)

        document.set(.boolean(true), at: ["git", "archive_on_merge"])

        #expect(document.text == """
        [git.remote]
        name = "origin"

        [git]
        archive_on_merge = true
        """)
    }

    @Test("the global settings file reads back what was written over an inline table")
    func globalSettingsReadBack() throws {
        let file = TestScratch.unique("global-settings") + "/settings.toml"
        try FileManager.default.createDirectory(
            atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true
        )
        try "git = { archive_on_merge = true }\n".write(toFile: file, atomically: true, encoding: .utf8)

        try GlobalWorkspaceSettings.setDeleteBranchOnArchive(true, in: file)

        let written = try String(contentsOfFile: file, encoding: .utf8)
        #expect(written == "[git]\narchive_on_merge = true\ndelete_branch_on_archive = true\n")
        #expect(GlobalWorkspaceSettings.deleteBranchOnArchive(paths: [file]))
        #expect(GlobalWorkspaceSettings.archiveOnMerge(paths: [file]))
    }
}
