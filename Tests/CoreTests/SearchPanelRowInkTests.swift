import Testing
@testable import Core

@Suite("Search panel row ink")
struct SearchPanelRowInkTests {
    private static let accents: [UInt32] = [
        0x007AFF, 0x0A84FF, 0x953D96, 0xA550A7, 0xF74F9E, 0xE0383E, 0xFF5257,
        0xF7821B, 0xFFC726, 0xFFC600, 0x62BA46, 0x989898, 0x8C8C8C,
    ]

    @Test("a title that can be used is drawn in the primary ink")
    func enabledTitle() {
        #expect(SearchPanelRowInk.title(isEnabled: true) == .primary)
    }

    @Test("a disabled title and its detail are muted, apart from a usable row")
    func disabledRow() {
        #expect(SearchPanelRowInk.title(isEnabled: false) == .muted)
        #expect(SearchPanelRowInk.detail(isEnabled: false) == .muted)
        #expect(SearchPanelRowInk.title(isEnabled: false) != SearchPanelRowInk.title(isEnabled: true))
    }

    @Test("the second line and a heading sit one level below the title, off the selection")
    func levelsOffSelection() {
        #expect(SearchPanelRowInk.detail() == .secondary)
        #expect(SearchPanelRowInk.heading == .secondary)
        #expect(!SearchPanelRowInk.primary.isSecondaryOffSelection)
        #expect(SearchPanelRowInk.secondary.isSecondaryOffSelection)
        #expect(SearchPanelRowInk.muted.isSecondaryOffSelection)
    }

    @Test("on the accent selection a usable row's every line keeps the full on-accent ink")
    func usableLinesKeepFullInkOnSelection() {
        #expect(SearchPanelRowInk.primary.opacityOnSelection == 1)
        #expect(SearchPanelRowInk.secondary.opacityOnSelection == 1)
    }

    @Test("a muted line on the accent selection reads as dimmer than a usable one, and stays above 2:1",
          arguments: accents, [false, true])
    func mutedOnSelection(accent: UInt32, isDark: Bool) {
        let ink = AccentInk(accent: accent, isDark: isDark)
        let full = Contrast.ratio(ink.onFill, ink.fill)
        let muted = Contrast.ratio(
            Contrast.composited(ink.onFill, over: ink.fill, at: SearchPanelRowInk.muted.opacityOnSelection),
            ink.fill
        )
        #expect(muted <= full * 0.85)
        #expect(muted >= 2)
    }
}
