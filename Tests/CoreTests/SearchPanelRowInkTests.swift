import Testing
@testable import Core

@Suite("Search panel row ink")
struct SearchPanelRowInkTests {
    @Test("a title that can be used is drawn in the primary ink")
    func enabledTitle() {
        #expect(SearchPanelRowInk.title(isEnabled: true) == .primary)
    }

    @Test("a disabled title stays different from a usable one, in an ink that can be read")
    func disabledTitle() {
        #expect(SearchPanelRowInk.title(isEnabled: false) == .secondary)
        #expect(SearchPanelRowInk.title(isEnabled: false) != SearchPanelRowInk.title(isEnabled: true))
    }

    @Test("the second line is secondary until its row is selected, because secondary falls short on the plate")
    func detail() {
        #expect(SearchPanelRowInk.detail(isSelected: false) == .secondary)
        #expect(SearchPanelRowInk.detail(isSelected: true) == .primary)
    }

    @Test("selecting a disabled command does not make its detail read as usable")
    func detailOfADisabledCommand() {
        #expect(SearchPanelRowInk.detail(isSelected: true, isEnabled: false) == .secondary)
    }
}
