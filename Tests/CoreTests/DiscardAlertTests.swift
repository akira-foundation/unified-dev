import Testing
@testable import Core

@Suite("What the discard alert asks, and which button destroys")
struct DiscardAlertTests {
    private let hunk = DiffHunk(oldStart: 1, oldCount: 2, newStart: 1, newCount: 3, lines: [
        DiffLine(kind: .context, text: "a"),
        DiffLine(kind: .deletion, text: "b"),
        DiffLine(kind: .addition, text: "B"),
        DiffLine(kind: .addition, text: "C"),
    ])

    private let file = ChangedFile(path: "src/hull.txt", change: .modified, additions: 4, deletions: 2)

    @Test("a hunk asks with a title and one sentence, Discard destroys and Cancel cancels")
    func hunkAsks() {
        let alert = DiscardAlert.hunk(hunk, path: "src/hull.txt", staged: .clean)

        #expect(alert.title == "Discard this hunk in src/hull.txt?")
        #expect(alert.body == "This puts back 1 removed line and takes out 2 added lines, "
            + "and leaves the rest of the file as it is.")
        #expect(alert.note == nil)
        #expect(alert.actions == [
            DiscardAlert.Action(label: "Discard", role: .destructive),
            DiscardAlert.Action(label: "Cancel", role: .cancel),
        ])
        #expect(alert.returnKey == DiscardAlert.confirm)
        #expect(alert.canConfirm)
    }

    @Test("staged changes the discard leaves behind come as a second line, and only then")
    func stagedNoteIsASecondLine() {
        let staged = DiscardAlert.hunk(hunk, path: "src/hull.txt", staged: .holdsAnotherVersion)
        let unread = DiscardAlert.hunk(hunk, path: "src/hull.txt", staged: .unreadable)

        #expect(staged.note == HunkDiscard.stagedStays)
        #expect(staged.body == staged.message + "\n\n" + HunkDiscard.stagedStays)
        #expect(unread.note == HunkDiscard.stagedUnknown)
        #expect(DiscardAlert.hunk(hunk, path: "src/hull.txt", staged: .holdsTheHunk).note == nil)
        #expect(staged.canConfirm && unread.canConfirm)
    }

    @Test("a discard git will refuse has no destructive button, only one that closes the alert")
    func refusedHasNoDestructiveButton() {
        for staged: HunkDiscard.Staged in [.divergesFromTheWorktree, .addsLinesThatAreNotUTF8] {
            let alert = DiscardAlert.hunk(hunk, path: "src/hull.txt", staged: staged)

            #expect(alert.title == HunkDiscard.question(path: "src/hull.txt", staged: staged))
            #expect(alert.body == HunkDiscard.refusal(staged))
            #expect(alert.actions == [DiscardAlert.Action(label: "OK", role: .cancel)])
            #expect(!alert.actions.contains { $0.role == .destructive })
            #expect(alert.returnKey == DiscardAlert.dismiss)
            #expect(!alert.canConfirm)
        }
    }

    @Test("a whole file asks with its path and one sentence, with Discard destructive")
    func fileAsks() {
        let alert = DiscardAlert.file(file, base: "main", hasDraft: false)

        #expect(alert.title == "Discard all changes in src/hull.txt?")
        #expect(alert.body == "This restores src/hull.txt to the version on main, losing 4 added lines and 2 removed lines.")
        #expect(alert.actions == [DiscardAlert.confirm, DiscardAlert.cancel])
        #expect(alert.returnKey == DiscardAlert.confirm)
    }

    @Test("no alert says there is no undo, because the destructive button already does")
    func noUndoWordingIsGone() {
        let alerts = [
            DiscardAlert.file(file, base: "main", hasDraft: true),
            DiscardAlert.file(ChangedFile(path: "notes.txt", change: .untracked), base: "main", hasDraft: false),
        ] + [HunkDiscard.Staged.clean, .holdsTheHunk, .holdsAnotherVersion, .unreadable, .divergesFromTheWorktree]
            .map { DiscardAlert.hunk(hunk, path: "src/hull.txt", staged: $0) }

        for alert in alerts {
            #expect(!alert.body.lowercased().contains("no undo"))
            #expect(!alert.body.lowercased().contains("cannot be undone"))
        }
    }
}
