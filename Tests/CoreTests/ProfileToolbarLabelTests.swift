import CoreGraphics
import Testing
@testable import Core

@Suite("ProfileToolbarLabel")
struct ProfileToolbarLabelTests {
    private func label(drawsSidebar: Bool = true, width: CGFloat) -> ProfileToolbarLabel {
        ProfileToolbarLabel.resolve(profileName: "Akira", drawsSidebar: drawsSidebar, sidebarWidth: width)
    }

    @Test("an open sidebar gives the name what the marks and the toggle leave")
    func openSidebarShowsTheName() {
        #expect(label(width: 260).menuWidth == 108)
        #expect(label(width: 340).menuWidth == 188)
    }

    @Test("a collapsed sidebar shows the mark alone at any width")
    func collapsedShowsTheMark() {
        #expect(label(drawsSidebar: false, width: 340).menuWidth == nil)
        #expect(label(drawsSidebar: false, width: 0).menuWidth == nil)
    }

    @Test("with the full screen bar hidden the switcher is the mark alone, however wide the sidebar is")
    func hiddenBarShowsTheMark() {
        let resolved = ProfileToolbarLabel.resolve(
            profileName: "Akira", drawsSidebar: true, barIsHidden: true, sidebarWidth: 340
        )
        #expect(resolved.menuWidth == nil)
        #expect(resolved.help == "Switch profile, Akira")
    }

    @Test("the name comes back when the full screen bar is revealed")
    func revealedBarShowsTheName() {
        let hidden = ProfileToolbarLabel.resolve(
            profileName: "Akira", drawsSidebar: true, barIsHidden: true, sidebarWidth: 260
        )
        let revealed = ProfileToolbarLabel.resolve(
            profileName: "Akira", drawsSidebar: true, barIsHidden: false, sidebarWidth: 260
        )
        #expect(revealed.menuWidth == 108)
        #expect(revealed.measureKey != hidden.measureKey)
    }

    @Test("the mark alone sits on glass, and the mark beside its name does not")
    func glassBelongsToTheMarkAlone() {
        let hiddenBar = ProfileToolbarLabel.resolve(
            profileName: "Akira", drawsSidebar: true, barIsHidden: true, sidebarWidth: 260
        )
        let collapsed = ProfileToolbarLabel.resolve(
            profileName: "Akira", drawsSidebar: false, sidebarWidth: 0
        )
        let tooNarrow = ProfileToolbarLabel.resolve(
            profileName: "Akira", drawsSidebar: true, sidebarWidth: 200
        )
        let named = ProfileToolbarLabel.resolve(
            profileName: "Akira", drawsSidebar: true, sidebarWidth: 260
        )
        #expect(hiddenBar.sitsOnGlass)
        #expect(collapsed.sitsOnGlass)
        #expect(tooNarrow.sitsOnGlass)
        #expect(!named.sitsOnGlass)
    }

    @Test(
        "only full screen with faded traffic lights counts as a hidden bar",
        arguments: [
            (false, CGFloat(0), false),
            (false, CGFloat(1), false),
            (true, CGFloat(1), false),
            (true, CGFloat(0.5), false),
            (true, CGFloat(0.49), true),
            (true, CGFloat(0), true),
        ]
    )
    func hiddenBarDecision(isFullScreen: Bool, opacity: CGFloat, expected: Bool) {
        #expect(
            ProfileToolbarLabel.barIsHidden(isFullScreen: isFullScreen, trafficLightsOpacity: opacity) == expected
        )
    }

    @Test("a name is dropped rather than squeezed below what reads as one")
    func tooNarrowDropsTheName() {
        #expect(label(width: 226).menuWidth == 74)
        #expect(label(width: 225).menuWidth == nil)
        #expect(label(width: 200).menuWidth == nil)
        #expect(label(width: 0).menuWidth == nil)
    }

    @Test("a fractional width never hands the name more than fits")
    func fractionalWidthRoundsDown() {
        #expect(label(width: 260.9).menuWidth == 108)
    }

    @Test("the toolbar is told to measure again when the menu's width or name changes, and only then")
    func measureKeyFollowsWhatChangesTheWidth() {
        let resolved = label(width: 260).measureKey
        #expect(label(width: 260).measureKey == resolved)
        #expect(label(width: 261).measureKey != resolved)
        #expect(label(drawsSidebar: false, width: 260).measureKey != resolved)
        #expect(
            ProfileToolbarLabel.resolve(profileName: "Unified", drawsSidebar: true, sidebarWidth: 260).measureKey != resolved
        )
        #expect(label(width: 0).measureKey == label(drawsSidebar: false, width: 260).measureKey)
    }

    @Test("help and accessibility carry the whole name, whatever is drawn")
    func fullNameIsAlwaysSaid() {
        let long = "A client whose name goes on far longer than any sidebar is wide"
        for drawsSidebar in [true, false] {
            let resolved = ProfileToolbarLabel.resolve(profileName: long, drawsSidebar: drawsSidebar, sidebarWidth: 260)
            #expect(resolved.help == "Switch profile, \(long)")
            #expect(resolved.accessibilityLabel == "Profile, \(long)")
        }
    }

    @Test("the title bar asks for the marks, the toggle and the whole of a short name")
    func titleBarFitsAShortName() {
        #expect(ProfileToolbarLabel.menuWidthAtMinimum(forNameWidth: 46.3) == 91)
        #expect(ProfileToolbarLabel.titleBarWidth(forNameWidth: 46.3) == 243)
    }

    @Test("a very short name still gets the smallest menu that reads as one")
    func shortNameGetsTheSmallestMenu() {
        #expect(ProfileToolbarLabel.menuWidthAtMinimum(forNameWidth: 8) == ProfileToolbarLabel.smallestMenuWithName)
    }

    @Test("a long name is truncated inside a capped menu rather than widening the sidebar without bound")
    func longNameIsCapped() {
        #expect(ProfileToolbarLabel.menuWidthAtMinimum(forNameWidth: 900) == ProfileToolbarLabel.widestMenuAtMinimum)
        #expect(ProfileToolbarLabel.titleBarWidth(forNameWidth: 900) == 312)
    }

    @Test(
        "a sidebar at the width its title bar asks for shows the name in the menu it asked for",
        arguments: [CGFloat(8), 46.3, 105, 900]
    )
    func minimumShowsTheName(nameWidth: CGFloat) {
        let resolved = ProfileToolbarLabel.resolve(
            profileName: "Akira",
            drawsSidebar: true,
            sidebarWidth: ProfileToolbarLabel.titleBarWidth(forNameWidth: nameWidth)
        )
        #expect(resolved.menuWidth == ProfileToolbarLabel.menuWidthAtMinimum(forNameWidth: nameWidth))
        #expect(!resolved.sitsOnGlass)
    }
}
