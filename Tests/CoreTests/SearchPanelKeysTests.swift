import Foundation
import Testing
@testable import Core

@Suite("Search panel keys")
struct SearchPanelKeysTests {
    private func context(
        mode: SearchPanelMode = .things,
        rows: Int = 5,
        highlighted: Int? = 0,
        isQueryEmpty: Bool = false,
        scope: HomeScope = .all,
        canDrill: Bool = true,
        caretAtEnd: Bool = true
    ) -> SearchPanelKeyContext {
        SearchPanelKeyContext(
            mode: mode,
            rowCount: rows,
            highlighted: highlighted,
            isQueryEmpty: isQueryEmpty,
            scope: scope,
            scopes: HomeScope.offered(searching: true),
            canDrill: canDrill,
            caretAtEnd: caretAtEnd
        )
    }

    @Test("the arrows stop at both ends rather than wrapping")
    func arrowsDoNotWrap() {
        #expect(SearchPanelKeys.outcome(for: .down, in: context(highlighted: 0)) == .move(1))
        #expect(SearchPanelKeys.outcome(for: .down, in: context(highlighted: 4)) == .handled)
        #expect(SearchPanelKeys.outcome(for: .up, in: context(highlighted: 0)) == .handled)
        #expect(SearchPanelKeys.outcome(for: .up, in: context(highlighted: 3)) == .move(2))
    }

    @Test("an arrow with nowhere to go is still the panel's")
    func arrowsAreNeverHandedBack() {
        #expect(SearchPanelKeys.outcome(for: .down, in: context(rows: 0, highlighted: nil)) == .handled)
    }

    @Test("with nothing highlighted, an arrow enters the list from the edge it came from")
    func arrowsEnterFromTheEdge() {
        #expect(SearchPanelKeys.outcome(for: .down, in: context(highlighted: nil)) == .move(0))
        #expect(SearchPanelKeys.outcome(for: .up, in: context(highlighted: nil)) == .move(4))
    }

    @Test("Tab steps the chips forward and Shift+Tab back, wrapping")
    func tabWalksTheChips() {
        let scopes = HomeScope.offered(searching: true)
        #expect(SearchPanelKeys.outcome(for: .tab, in: context(scope: .all)) == .scope(scopes[1]))
        #expect(SearchPanelKeys.outcome(for: .backTab, in: context(scope: .all)) == .scope(scopes[3]))
        #expect(SearchPanelKeys.outcome(for: .tab, in: context(scope: scopes[3])) == .scope(scopes[0]))
    }

    @Test("Tab is not the panel's in a mode")
    func tabIsHandedBackInAMode() {
        #expect(SearchPanelKeys.outcome(for: .tab, in: context(mode: .commands)) == .ignored)
        #expect(
            SearchPanelKeys.outcome(
                for: .tab, in: context(mode: .actions(WorkspaceID("w1")))
            ) == .ignored
        )
    }

    @Test("Return opens the highlighted row, and does nothing when there is none")
    func returnOpens() {
        #expect(SearchPanelKeys.outcome(for: .returnKey, in: context()) == .open)
        #expect(SearchPanelKeys.outcome(for: .returnKey, in: context(highlighted: nil)) == .handled)
    }

    @Test("Cmd+Return pushes into a row that has a menu, and is swallowed by one that has not")
    func commandReturnDrills() {
        #expect(SearchPanelKeys.outcome(for: .commandReturn, in: context()) == .drill)
        #expect(
            SearchPanelKeys.outcome(for: .commandReturn, in: context(canDrill: false)) == .handled
        )
    }

    @Test("the right arrow pushes in only from the end of the field")
    func rightNeedsTheCaretAtTheEnd() {
        #expect(SearchPanelKeys.outcome(for: .right, in: context()) == .drill)
        #expect(SearchPanelKeys.outcome(for: .right, in: context(caretAtEnd: false)) == .ignored)
        #expect(SearchPanelKeys.outcome(for: .right, in: context(canDrill: false)) == .ignored)
    }

    @Test("Escape clears a full field and closes an empty one")
    func escapeClearsThenCloses() {
        #expect(SearchPanelKeys.outcome(for: .escape, in: context(isQueryEmpty: false)) == .clearQuery)
        #expect(SearchPanelKeys.outcome(for: .escape, in: context(isQueryEmpty: true)) == .close)
    }

    @Test("Backspace on an empty field leaves a mode and is otherwise the field's")
    func backspaceLeavesAMode() {
        #expect(SearchPanelKeys.outcome(for: .backspaceOnEmpty, in: context()) == .ignored)
        #expect(
            SearchPanelKeys.outcome(for: .backspaceOnEmpty, in: context(mode: .commands)) == .leaveMode
        )
        #expect(
            SearchPanelKeys.outcome(
                for: .backspaceOnEmpty, in: context(mode: .actions(WorkspaceID("w1")))
            ) == .leaveMode
        )
    }

    @Test("the footer names the way out of every mode")
    func theFooterNamesTheWayOut() {
        let resting = SearchPanelKeys.footer(for: .things, isSearching: false)
        #expect(resting.contains { $0.key == ">" })
        let searching = SearchPanelKeys.footer(for: .things, isSearching: true)
        #expect(searching.contains { $0.label == "Scope" })
        #expect(SearchPanelKeys.footer(for: .commands, isSearching: true).contains { $0.label == "Leave commands" })
        #expect(
            SearchPanelKeys.footer(for: .actions(WorkspaceID("w1")), isSearching: true)
                .contains { $0.label == "Back" }
        )
    }

    @Test("the footer draws every key as the menu bar does, with no key spelled out in words")
    func theFooterUsesMenuGlyphs() {
        let searching = SearchPanelKeys.footer(for: .things, isSearching: true)
        #expect(searching.map(\.key) == ["\u{21A9}", "\u{2318}\u{21A9}", "\u{21E5}", "\u{238B}"])
        #expect(searching.map(\.text) == ["Open \u{21A9}", "Actions \u{2318}\u{21A9}", "Scope \u{21E5}", "Close \u{238B}"])
        let everyKey = [false, true].flatMap { SearchPanelKeys.footer(for: .things, isSearching: $0) }
            + SearchPanelKeys.footer(for: .commands, isSearching: true)
            + SearchPanelKeys.footer(for: .actions(WorkspaceID("w1")), isSearching: true)
            + SearchPanelKeys.fileSearchFooter
        #expect(everyKey.allSatisfy { !$0.key.contains { $0.isLetter } })
    }

    @Test("the file search names both arrows under one label")
    func fileSearchFooter() {
        #expect(SearchPanelKeys.fileSearchFooter.map(\.key) == ["\u{2191}\u{2193}", "\u{21A9}", "\u{238B}"])
    }
}
