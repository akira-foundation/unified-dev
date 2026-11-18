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

    @Test("the second line is one level below its title, and a disabled one a level further")
    func detail() {
        #expect(SearchPanelRowInk.detail() == .secondary)
        #expect(SearchPanelRowInk.detail(isEnabled: false) == .tertiary)
    }

    @Test("a section heading sits below the rows it heads")
    func heading() {
        #expect(SearchPanelRowInk.heading == .secondary)
        #expect(SearchPanelRowInk.heading != SearchPanelRowInk.title(isEnabled: true))
    }
}
