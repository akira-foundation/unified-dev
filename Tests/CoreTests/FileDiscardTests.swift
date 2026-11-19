import Testing
@testable import Core

@Suite("What discarding a whole file says it loses")
struct FileDiscardTests {
    @Test("a tracked file is restored to the base, and its lines are counted")
    func trackedFileIsRestored() {
        let file = ChangedFile(path: "app/Handler.php", change: .modified, additions: 1, deletions: 3)

        #expect(FileDiscard.losses(of: file, base: "develop", hasDraft: false)
            == "This restores app/Handler.php to the version on develop, losing 1 added line and 3 removed lines.")
    }

    @Test("a file the base never had is deleted, and an untracked one goes to the Trash")
    func newFilesSayWhereTheyGo() {
        let added = ChangedFile(path: "a.txt", change: .added, additions: 2)
        let untracked = ChangedFile(path: "b.txt", change: .untracked)

        #expect(FileDiscard.losses(of: added, base: "main", hasDraft: false)
            == "This deletes a.txt, which did not exist on main, losing 2 added lines.")
        #expect(FileDiscard.losses(of: untracked, base: "main", hasDraft: false)
            == "This moves b.txt, which git does not track, to the Trash.")
    }

    @Test("unsaved edits are named last in the same sentence")
    func draftIsNamedLast() {
        let file = ChangedFile(path: "a.txt", change: .modified, additions: 2, deletions: 1)
        let bare = ChangedFile(path: "a.txt", change: .modified)

        #expect(FileDiscard.losses(of: file, base: "main", hasDraft: true)
            == "This restores a.txt to the version on main, losing 2 added lines, 1 removed line "
            + "and the unsaved edits open in it.")
        #expect(FileDiscard.losses(of: bare, base: "main", hasDraft: true)
            == "This restores a.txt to the version on main, losing the unsaved edits open in it.")
    }
}
