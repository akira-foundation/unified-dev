import Testing
@testable import Core

@Suite("When a hunk can be discarded")
struct HunkDiscardTests {
    private func offer(
        _ change: ChangedFile.Change, binary: Bool = false, whitespace: Bool = false,
        blocker: String? = nil, unsaved: Bool = false
    ) -> HunkDiscard.Availability {
        HunkDiscard.availability(
            file: ChangedFile(path: "a.txt", change: change, isBinary: binary),
            ignoringWhitespace: whitespace, blocker: blocker, hasUnsavedEdits: unsaved
        )
    }

    @Test("only a change within a file offers a hunk discard")
    func changesWithinAFile() {
        #expect(offer(.modified) == .enabled)
        #expect(offer(.renamed) == .enabled)
        #expect(offer(.copied) == .hidden)
        #expect(offer(.added) == .hidden)
        #expect(offer(.deleted) == .hidden)
        #expect(offer(.untracked) == .hidden)
        #expect(offer(.typechange) == .hidden)
        #expect(offer(.modified, binary: true) == .hidden)
    }

    @Test("a submodule bump is hidden, because reversing it writes nothing")
    func gitlinksAreHidden() {
        let file = ChangedFile(path: "sub", change: .modified)
        let gitlink = FileDiff(
            oldPath: "sub", newPath: "sub", oldMode: HunkDiscard.gitlinkMode,
            newMode: HunkDiscard.gitlinkMode
        )
        let ordinary = FileDiff(oldPath: "a.txt", newPath: "a.txt", oldMode: "100644", newMode: "100644")

        #expect(!HunkDiscard.offers(file, in: gitlink))
        #expect(HunkDiscard.offers(file, in: ordinary))
        #expect(HunkDiscard.offers(file))
    }

    @Test("the refusal the write path uses is the reason the control shows")
    func theRefusalMatchesTheAvailability() {
        let turn = FileBarControls.revertWhileAgentWorks
        let modified = ChangedFile(path: "a.txt", change: .modified)
        let added = ChangedFile(path: "a.txt", change: .added)

        #expect(HunkDiscard.refusal(
            file: modified, ignoringWhitespace: false, blocker: nil, hasUnsavedEdits: false
        ) == nil)
        #expect(HunkDiscard.refusal(
            file: modified, ignoringWhitespace: false, blocker: turn, hasUnsavedEdits: false
        ) == turn)
        #expect(HunkDiscard.refusal(
            file: modified, ignoringWhitespace: false, blocker: nil, hasUnsavedEdits: true
        ) == HunkDiscard.draftIsOpen)
        #expect(HunkDiscard.refusal(
            file: modified, ignoringWhitespace: true, blocker: nil, hasUnsavedEdits: false
        ) == HunkDiscard.whitespaceIsHidden)
        #expect(HunkDiscard.refusal(
            file: added, ignoringWhitespace: false, blocker: nil, hasUnsavedEdits: false
        ) == HunkDiscardRefusal.notOffered.errorDescription)
    }

    @Test("a turn in progress, unsaved edits and hidden whitespace disable it with a reason, in that order")
    func disabledWithAReason() {
        let turn = FileBarControls.revertWhileAgentWorks
        #expect(offer(.modified, blocker: turn) == .disabled(turn))
        #expect(offer(.modified, unsaved: true) == .disabled(HunkDiscard.draftIsOpen))
        #expect(offer(.modified, whitespace: true) == .disabled(HunkDiscard.whitespaceIsHidden))
        #expect(offer(.modified, whitespace: true, blocker: turn, unsaved: true) == .disabled(turn))
        #expect(offer(.modified, whitespace: true, unsaved: true) == .disabled(HunkDiscard.draftIsOpen))
        #expect(offer(.added, blocker: turn) == .hidden)
    }

    @Test("the question names the path")
    func question() {
        #expect(HunkDiscard.question(path: "app/Handler.php") == "Discard this hunk in app/Handler.php?")
    }

    @Test("the losses count what is put back and what is taken out")
    func losses() {
        let hunk = DiffHunk(oldStart: 1, oldCount: 2, newStart: 1, newCount: 3, lines: [
            DiffLine(kind: .context, text: "a"),
            DiffLine(kind: .deletion, text: "b"),
            DiffLine(kind: .addition, text: "B"),
            DiffLine(kind: .addition, text: "C"),
        ])
        #expect(HunkDiscard.losses(of: hunk, staged: .clean)
            == "This puts back 1 removed line and takes out 2 added lines, "
            + "and leaves the rest of the file as it is.")
    }

    @Test("a hunk that only removes, or only adds, says just that")
    func lossesWithOneClause() {
        let removalsOnly = DiffHunk(oldStart: 1, oldCount: 2, newStart: 1, newCount: 1, lines: [
            DiffLine(kind: .context, text: "a"),
            DiffLine(kind: .deletion, text: "b"),
        ])
        let additionsOnly = DiffHunk(oldStart: 1, oldCount: 1, newStart: 1, newCount: 2, lines: [
            DiffLine(kind: .context, text: "a"),
            DiffLine(kind: .addition, text: "B"),
        ])

        #expect(HunkDiscard.losses(of: removalsOnly, staged: .clean).hasPrefix("This puts back 1 removed line, "))
        #expect(!HunkDiscard.losses(of: removalsOnly, staged: .clean).contains("takes out"))
        #expect(HunkDiscard.losses(of: additionsOnly, staged: .clean).hasPrefix("This takes out 1 added line, "))
        #expect(!HunkDiscard.losses(of: additionsOnly, staged: .clean).contains("puts back"))
    }

    @Test("the losses are one sentence and leave the no undo wording to the destructive button")
    func lossesAreOneSentence() {
        let hunk = DiffHunk(oldStart: 1, oldCount: 1, newStart: 1, newCount: 1, lines: [
            DiffLine(kind: .deletion, text: "b"),
        ])
        let sentence = HunkDiscard.losses(of: hunk, staged: .holdsAnotherVersion)

        #expect(!sentence.lowercased().contains("undo"))
        #expect(!sentence.contains("\n"))
        #expect(sentence.filter { $0 == "." }.count == 1)
    }

    @Test("a hunk with nothing counted still says what happens")
    func lossesWithoutCounts() {
        let hunk = DiffHunk(oldStart: 1, oldCount: 1, newStart: 1, newCount: 1, lines: [
            DiffLine(kind: .context, text: "a"),
        ])
        #expect(HunkDiscard.losses(of: hunk, staged: .clean)
            == "This undoes the change, and leaves the rest of the file as it is.")
    }

    @Test("a staged version of the same region is a note of its own, and only when there is one")
    func noteForAStagedVersion() {
        #expect(HunkDiscard.note(.holdsAnotherVersion)
            == "This file has staged changes that this does not touch. They stay in the index, so "
            + "your next commit still carries them, even where they cover these same lines. "
            + "Unstage them with git restore --staged if you do not want them.")
        #expect(HunkDiscard.note(.unreadable) == HunkDiscard.stagedUnknown)
        for staged: HunkDiscard.Staged in [.clean, .holdsTheHunk, .divergesFromTheWorktree, .addsLinesThatAreNotUTF8] {
            #expect(HunkDiscard.note(staged) == nil)
        }
    }

    @Test("an index that has moved apart from the working file promises a refusal, not a discard")
    func lossesWhenTheIndexWillRefuse() {
        let hunk = DiffHunk(oldStart: 1, oldCount: 1, newStart: 1, newCount: 1, lines: [
            DiffLine(kind: .deletion, text: "b"),
            DiffLine(kind: .addition, text: "B"),
        ])
        let sentence = HunkDiscard.losses(of: hunk, staged: .divergesFromTheWorktree)

        #expect(sentence
            == "This file has staged changes over these lines that do not match the working file, "
            + "so git refuses to discard this hunk and nothing would be written. Unstage the "
            + "file with git restore --staged, or commit what is staged, and then discard the hunk.")
        #expect(!sentence.contains("puts back"))
        #expect(!sentence.contains("takes out"))
        #expect(!sentence.lowercased().contains("undo"))
    }

    @Test("a discard git will refuse is not offered as a button, and its title does not ask")
    func refusedDiscardIsNotConfirmed() {
        #expect(!HunkDiscard.canConfirm(.divergesFromTheWorktree))
        #expect(HunkDiscard.question(path: "src/hull.txt", staged: .divergesFromTheWorktree)
            == "This hunk in src/hull.txt cannot be discarded yet")
        for staged: HunkDiscard.Staged in [.clean, .holdsTheHunk, .holdsAnotherVersion, .unreadable] {
            #expect(HunkDiscard.canConfirm(staged))
            #expect(HunkDiscard.question(path: "src/hull.txt", staged: staged) == "Discard this hunk in src/hull.txt?")
        }
    }

    @Test("a hunk whose added lines cannot be checked is not offered as a button, and says why")
    func uncheckableAddedLinesAreNotConfirmed() {
        let hunk = DiffHunk(oldStart: 1, oldCount: 1, newStart: 1, newCount: 1, lines: [
            DiffLine(kind: .deletion, text: "cafe"),
            DiffLine(kind: .addition, text: "caf\u{fffd}"),
        ])

        #expect(!HunkDiscard.canConfirm(.addsLinesThatAreNotUTF8))
        #expect(HunkDiscard.question(path: "src/hull.txt", staged: .addsLinesThatAreNotUTF8)
            == "This hunk in src/hull.txt cannot be discarded")
        #expect(HunkDiscard.losses(of: hunk, staged: .addsLinesThatAreNotUTF8)
            == "This hunk adds lines that are not UTF-8, so Unified Dev cannot check that they are still "
            + "the ones shown here. Discard the whole file to put it back the way git has it.")
    }

    @Test("an index nobody could read says so rather than promising a clean discard")
    func noteForAnUnreadableIndex() {
        #expect(HunkDiscard.note(.unreadable)
            == "Unified Dev could not read what the index holds for this file. If anything is staged "
            + "here, this leaves it as it is, and your next commit still carries it.")
        #expect(HunkDiscard.note(.unreadable) != HunkDiscard.stagedStays)
    }

    @Test("every refusal says nothing was discarded, and git's words follow when there are some")
    func refusals() {
        let staged = HunkDiscardRefusal.indexDiffers.errorDescription ?? ""
        #expect(staged.contains("Nothing was discarded."))
        #expect(staged.contains("git restore --staged"))
        let changed = HunkDiscardRefusal.changed.errorDescription ?? ""
        let bare = HunkDiscardRefusal.doesNotApply("").errorDescription ?? ""
        let detailed = HunkDiscardRefusal.doesNotApply("error: patch failed").errorDescription ?? ""
        #expect(changed.hasSuffix("Nothing was discarded."))
        #expect(bare == "The hunk no longer applies cleanly, so nothing was discarded.")
        #expect(detailed == bare + "\n\nerror: patch failed")
        #expect(HunkDiscardRefusal.notOffered.errorDescription?.isEmpty == false)
        #expect(HunkDiscardRefusal.addsLinesThatAreNotUTF8.errorDescription
            == "This hunk adds lines that are not UTF-8, so Unified Dev cannot check that they are still "
            + "the ones shown here. Nothing was discarded. Discard the whole file to put it back the way "
            + "git has it.")
    }
}
