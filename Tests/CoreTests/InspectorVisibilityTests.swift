import Testing
@testable import Core

@Suite("Inspector visibility")
struct InspectorVisibilityTests {
    @Test("a first launch, with nothing stored, shows the inspector")
    func shownByDefault() {
        #expect(InspectorVisibility().isVisible)
        #expect(InspectorVisibility(storedHidden: false).isVisible)
    }

    @Test("what is stored comes back as it was left")
    func storedRoundTrip() {
        for visible in [true, false] {
            let stored = InspectorVisibility(isVisible: visible).storedHidden
            #expect(InspectorVisibility(storedHidden: stored).isVisible == visible)
        }
        #expect(InspectorVisibility(isVisible: false).storedHidden)
        #expect(!InspectorVisibility(isVisible: true).storedHidden)
    }

    @Test("the menu offers to hide a visible inspector and to show a hidden one")
    func menuTitle() {
        let item = MenuBarCatalogue[.toggleInspector]
        let shown = InspectorVisibility(isVisible: true)
        let hidden = InspectorVisibility(isVisible: false)
        #expect(item.title(alternate: shown.menuTitleIsAlternate) == "Hide Inspector")
        #expect(item.title(alternate: hidden.menuTitleIsAlternate) == "Show Inspector")
    }

    @Test("the button names what it will do and the key that does the same")
    func toggleHelp() {
        #expect(InspectorVisibility(isVisible: true).toggleHelp == "Hide the inspector (\u{2325}\u{2318}0)")
        #expect(InspectorVisibility(isVisible: false).toggleHelp == "Show the inspector (\u{2325}\u{2318}0)")
    }

    @Test("toggling flips the choice, with or without a workspace")
    func toggling() {
        #expect(!InspectorVisibility(isVisible: true).toggled().isVisible)
        #expect(InspectorVisibility(isVisible: false).toggled().isVisible)
        #expect(InspectorVisibility(isVisible: false).toggled().toggled() == InspectorVisibility(isVisible: false))
    }

    @Test("it is presented only when it is visible and a workspace is there to show")
    func presented() {
        #expect(InspectorVisibility(isVisible: true).isPresented(hasWorkspace: true))
        #expect(!InspectorVisibility(isVisible: true).isPresented(hasWorkspace: false))
        #expect(!InspectorVisibility(isVisible: false).isPresented(hasWorkspace: true))
        #expect(!InspectorVisibility(isVisible: false).isPresented(hasWorkspace: false))
        #expect(InspectorVisibility(isVisible: false).hidesInspector)
        #expect(!InspectorVisibility(isVisible: true).hidesInspector)
    }
}
