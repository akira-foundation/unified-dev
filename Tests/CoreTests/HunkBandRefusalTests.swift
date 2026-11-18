import Testing
@testable import Core

@Suite("A hunk's band refuses what git will refuse")
struct HunkBandRefusalTests {
    private let modified = ChangedFile(path: "a.txt", change: .modified)

    private func offer(staged: HunkDiscard.Staged, whitespace: Bool = false) -> HunkDiscard.Availability {
        HunkDiscard.availability(
            file: modified, ignoringWhitespace: whitespace, blocker: nil, hasUnsavedEdits: false, staged: staged
        )
    }

    @Test("a refusal disables the band with the same words the confirmation shows")
    func refusalDisablesTheBand() throws {
        let hunk = DiffHunk(oldStart: 1, oldCount: 1, newStart: 1, newCount: 1, lines: [
            DiffLine(kind: .deletion, text: "cafe"),
            DiffLine(kind: .addition, text: "caf\u{fffd}"),
        ])
        for staged: HunkDiscard.Staged in [.divergesFromTheWorktree, .addsLinesThatAreNotUTF8] {
            let reason = try #require(HunkDiscard.refusal(staged))
            #expect(offer(staged: staged) == .disabled(reason))
            #expect(HunkDiscard.losses(of: hunk, staged: staged) == reason)
            #expect(!HunkDiscard.canConfirm(staged))
        }
        #expect(HunkDiscard.refusal(.divergesFromTheWorktree) == HunkDiscard.indexRefuses)
    }

    @Test("what git will carry out leaves the band enabled")
    func carriedOutStaysEnabled() {
        for staged: HunkDiscard.Staged in [.clean, .holdsTheHunk, .holdsAnotherVersion, .unreadable] {
            #expect(HunkDiscard.refusal(staged) == nil)
            #expect(offer(staged: staged) == .enabled)
        }
    }

    @Test("a turn in progress, unsaved edits and hidden whitespace are named before what git would refuse")
    func ownReasonsComeFirst() {
        let turn = FileBarControls.revertWhileAgentWorks
        #expect(offer(staged: .divergesFromTheWorktree, whitespace: true) == .disabled(HunkDiscard.whitespaceIsHidden))
        #expect(HunkDiscard.availability(
            file: modified, ignoringWhitespace: false, blocker: turn, hasUnsavedEdits: false,
            staged: .addsLinesThatAreNotUTF8
        ) == .disabled(turn))
        #expect(HunkDiscard.availability(
            file: modified, ignoringWhitespace: false, blocker: nil, hasUnsavedEdits: true,
            staged: .divergesFromTheWorktree
        ) == .disabled(HunkDiscard.draftIsOpen))
    }

    @Test("only an added line that decoded with a replacement character can be one that is not UTF-8")
    func suspectsOnlyReplacedAdditions() {
        func hunk(_ lines: [DiffLine]) -> DiffHunk {
            DiffHunk(oldStart: 1, oldCount: 1, newStart: 1, newCount: 1, lines: lines)
        }
        #expect(HunkDiscard.mayAddLinesThatAreNotUTF8(hunk([DiffLine(kind: .addition, text: "caf\u{fffd}")])))
        #expect(!HunkDiscard.mayAddLinesThatAreNotUTF8(hunk([DiffLine(kind: .addition, text: "caf\u{e9}")])))
        #expect(!HunkDiscard.mayAddLinesThatAreNotUTF8(hunk([DiffLine(kind: .deletion, text: "caf\u{fffd}")])))
        #expect(!HunkDiscard.mayAddLinesThatAreNotUTF8(hunk([DiffLine(kind: .context, text: "caf\u{fffd}")])))
    }
}
