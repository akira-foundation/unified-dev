import Testing
import CoreGraphics
@testable import Core

@Suite("ToolbarTabsWidth")
struct ToolbarTabsWidthTests {
    @Test("the collapsed profile switcher takes its room out of the strip, down to the minimum")
    func profileMarkRoom() {
        #expect(ToolbarTabsWidth.width(inColumn: 900, besideCollapsedSwitcher: true) == 686)
        #expect(ToolbarTabsWidth.width(inColumn: 900, besideCollapsedSwitcher: false) == 730)
        #expect(ToolbarTabsWidth.width(inColumn: 300, besideCollapsedSwitcher: true) == 240)
    }

    @Test("the tabs take the centre column less the room the toolbar actions need")
    func fillsTheColumn() {
        #expect(ToolbarTabsWidth.width(inColumn: 900) == 730)
    }

    @Test("the minimum takes over exactly where the column leaves no more room than it")
    func boundary() {
        #expect(ToolbarTabsWidth.width(inColumn: 410) == 240)
        #expect(ToolbarTabsWidth.width(inColumn: 411) == 241)
        #expect(ToolbarTabsWidth.width(inColumn: 409) == 240)
    }

    @Test("a narrow column keeps the tabs at their minimum rather than shrinking them away")
    func neverBelowMinimum() {
        #expect(ToolbarTabsWidth.width(inColumn: 300) == 240)
        #expect(ToolbarTabsWidth.width(inColumn: 0) == 240)
    }

    @Test("the strip shows only when there is more than one tab")
    func stripNeedsTwoTabs() {
        #expect(!ToolbarTabsWidth.showsStrip(tabCount: 0, paneCount: 1, isRenaming: false))
        #expect(!ToolbarTabsWidth.showsStrip(tabCount: 1, paneCount: 1, isRenaming: false))
        #expect(ToolbarTabsWidth.showsStrip(tabCount: 2, paneCount: 1, isRenaming: false))
    }

    @Test("a single tab split into panes keeps the strip")
    func splitTabKeepsTheStrip() {
        #expect(ToolbarTabsWidth.showsStrip(tabCount: 1, paneCount: 2, isRenaming: false))
        #expect(ToolbarTabsWidth.showsStrip(tabCount: 2, paneCount: 3, isRenaming: false))
        #expect(!ToolbarTabsWidth.showsStrip(tabCount: 1, paneCount: 1, isRenaming: false))
        #expect(!ToolbarTabsWidth.showsStrip(tabCount: 0, paneCount: 2, isRenaming: false))
    }

    @Test("renaming a lone tab shows the strip for as long as the field is open")
    func renamingShowsTheStrip() {
        #expect(ToolbarTabsWidth.showsStrip(tabCount: 1, paneCount: 1, isRenaming: true))
        #expect(!ToolbarTabsWidth.showsStrip(tabCount: 0, paneCount: 1, isRenaming: true))
    }
}
