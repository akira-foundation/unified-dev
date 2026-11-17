import Foundation
import Testing
@testable import Core

@Suite("Search panel commands")
struct SearchPanelCommandsTests {
    @Test("an empty query is the whole catalogue in table order")
    func anEmptyQueryIsTheWholeBar() {
        let ranked = SearchPanelCommands.rank("")
        #expect(ranked.count == MenuBarCatalogue.commands.count)
        #expect(ranked.map(\.item.action) == MenuBarCatalogue.commands.map(\.action))
    }

    @Test("a query ranks by the same subsequence score the slash menu uses, and reports the hits")
    func rankingAndHighlights() {
        let ranked = SearchPanelCommands.rank("archive")
        #expect(ranked.first?.item.action == .archive)
        #expect(ranked.first?.highlights == [0, 1, 2, 3, 4, 5, 6])
        #expect(!ranked.contains { $0.item.action == .about })
    }

    @Test("rows are grouped by the menu they live in, in the bar's own order")
    func groupedByMenu() {
        let sections = SearchPanelCommands.sections(SearchPanelCommands.rank(""))
        #expect(sections.map(\.title) == ["Unified Dev", "File", "Edit", "View", "Workspace", "Help"])
        #expect(sections.allSatisfy { $0.rows.allSatisfy { $0.drillable == nil } })
    }

    @Test("within a menu the rows keep the ranked order")
    func rankedInsideASection() {
        let sections = SearchPanelCommands.sections(SearchPanelCommands.rank("tab"))
        guard let view = sections.first(where: { $0.title == "View" }) else {
            Issue.record("expected a View section")
            return
        }
        let scores = view.rows.compactMap { row -> Int? in
            guard case .command(let hit) = row else { return nil }
            return hit.score
        }
        #expect(scores == scores.sorted(by: >))
    }

    @Test("a menu with nothing in it is not a heading over nothing")
    func emptyMenusAreDropped() {
        let sections = SearchPanelCommands.sections(SearchPanelCommands.rank("welcome"))
        #expect(sections.map(\.title) == ["Help"])
    }

    @Test("a row prints its key, or the words no key")
    func everyRowPrintsAKey() {
        #expect(MenuBarCatalogue[.archive].keyText == "\u{21E7}\u{2318}\u{232B}")
        #expect(MenuBarCatalogue[.pin].keyText == "no key")
        #expect(MenuBarCatalogue[.nextChangedFile].keyText == "\u{2325}\u{2318}J")
        #expect(MenuBarCatalogue[.projectSettings].keyText == "\u{21E7}\u{2318},")
        #expect(MenuBarCatalogue[.zoomPane].keyText == "\u{21E7}\u{2318}\u{21A9}")
        #expect(MenuBarCatalogue[.nextWorkspace].keyText == "\u{2325}\u{2318}\u{2193}")
        #expect(MenuBarCatalogue[.closePane].keyText == "\u{2303}\u{2318}W")
    }

    @Test("a row with a second key prints both, so the key the monitor reads is findable")
    func aRowPrintsItsAlternateKeyToo() {
        #expect(MenuBarCatalogue[.nextTab].keyText == "\u{21E7}\u{2318}] \u{2325}\u{21E5}")
        #expect(MenuBarCatalogue[.previousTab].keyText == "\u{21E7}\u{2318}[ \u{2325}\u{21E7}\u{21E5}")
    }

    @Test("the modifiers are drawn in the platform's order")
    func modifierOrder() {
        let all = MenuShortcut("x", .command, .shift, .option, .control)
        #expect(all.display == "\u{2303}\u{2325}\u{21E7}\u{2318}X")
    }

    @Test("the panel itself is a menu item, on a key nothing else claims")
    func thePanelIsInTheBar() {
        let item = MenuBarCatalogue[.quickSearch]
        #expect(item.menu == .edit)
        #expect(item.key == .command("k"))
        let others = MenuBarCatalogue.commands.filter { $0.action != .quickSearch }
        #expect(!others.contains { $0.key == .command("k") })
    }

    @Test("the catalogue offers the panel whatever is selected")
    func thePanelNeedsNoSelection() {
        #expect(MenuBarCatalogue[.quickSearch].availability == .always)
    }
}
