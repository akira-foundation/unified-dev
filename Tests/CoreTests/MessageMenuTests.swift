import Testing
@testable import Core

@Suite("Message menu")
struct MessageMenuTests {
    private func items(
        selection: Bool = false, text: Bool = true, chapter: Bool = false, fork: Bool = false
    ) -> [[MessageMenuItem]] {
        MessageMenu.sections(for: MessageMenuContext(
            hasSelection: selection, hasText: text, isChapter: chapter, canFork: fork
        ))
    }

    private func enabled(_ sections: [[MessageMenuItem]]) -> [MessageMenuAction] {
        sections.flatMap { $0 }.filter(\.isEnabled).map(\.action)
    }

    @Test func withoutASelectionOnlyTheMessageCanBeCopied() {
        #expect(enabled(items()) == [.copyMessage, .copyMessageAsMarkdown, .pinChapter])
    }

    @Test func aSelectionCanBeCopiedAndAttached() {
        let actions = enabled(items(selection: true))
        #expect(actions.contains(.copy) && actions.contains(.attachSelection))
    }

    @Test func theSectionsKeepTheirOrder() {
        let actions = items(selection: true, fork: true).map { $0.map(\.action) }
        #expect(actions == [
            [.copy], [.copyMessage, .copyMessageAsMarkdown], [.attachSelection], [.pinChapter, .forkFromHere],
        ])
    }

    @Test func aChapterOffersToBeUnpinned() {
        let actions = items(chapter: true).flatMap { $0 }.map(\.action)
        #expect(actions.contains(.unpinChapter) && !actions.contains(.pinChapter))
    }

    @Test func aMessageWithNoTextCannotBePinned() {
        #expect(!enabled(items(text: false)).contains(.pinChapter))
    }

    @Test func aChapterWithNoTextCanStillBeUnpinned() {
        #expect(enabled(items(text: false, chapter: true)).contains(.unpinChapter))
    }

    @Test func forkingIsOfferedOnlyWhereAChatCanBranch() {
        #expect(!items().flatMap { $0 }.contains { $0.action == .forkFromHere })
        #expect(enabled(items(fork: true)).contains(.forkFromHere))
    }

    @Test func onlyCopyAndAttachCarryShortcuts() {
        let shortcuts = [MessageMenuAction.copy, .copyMessage, .copyMessageAsMarkdown, .attachSelection,
                         .pinChapter, .unpinChapter, .forkFromHere].filter { !$0.keyEquivalent.isEmpty }
        #expect(shortcuts == [.copy, .attachSelection])
        #expect(MessageMenuAction.attachSelection.needsShift && !MessageMenuAction.copy.needsShift)
    }

    @Test func aForkIsNamedAfterItsSource() {
        #expect(MessageMenu.forkTitle(of: " Notes ") == "Notes (fork)")
        #expect(MessageMenu.forkTitle(of: "  ") == "Fork")
    }
}
