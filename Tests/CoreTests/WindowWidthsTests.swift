import Testing
@testable import Core

@Suite struct WindowWidthsTests {
    private let widths = WindowWidths(
        sidebar: 420, sidebarMinimum: 200, detail: 420, inspector: 280, divider: 1
    )

    @Test func theWindowGivesBackTheInspectorsRoomWhenItIsNotShowing() {
        #expect(widths.minimum(withInspector: true) == 1122)
        #expect(widths.minimum(withInspector: false) == 841)
    }

    @Test func openingTheInspectorCannotClip() {
        let step = widths.inspector + widths.divider
        let windowLandsExactly = widths.minimum(withInspector: false) + step == widths.minimum(withInspector: true)
        let halfLandsExactly = widths.detailHalf(withInspector: false) + step == widths.detailHalf(withInspector: true)
        #expect(windowLandsExactly)
        #expect(halfLandsExactly)
    }

    @Test func theDetailHalfIsTheWindowMinimumLessTheSidebarAndItsDivider() {
        for showing in [true, false] {
            let half = widths.minimum(withInspector: showing) - widths.sidebar - widths.divider
            let agrees = half == widths.detailHalf(withInspector: showing)
            #expect(agrees)
        }
    }

    @Test func aWindowAlreadyWideEnoughIsLeftAlone() {
        #expect(widths.presenting(windowWidth: 1122, screenWidth: 1800).isSettled)
        #expect(widths.presenting(windowWidth: 1500, screenWidth: 1800).isSettled)
    }

    @Test func aNarrowWindowOnARoomyScreenIsWidenedAndNothingElseMoves() {
        let fit = widths.presenting(windowWidth: 841, screenWidth: 1800)
        #expect(fit.windowWidth == 1122)
        #expect(fit.sidebarWidth == nil)
        #expect(!fit.foldsSidebar)
    }

    @Test func aScreenThatCannotAffordItGrowsTheWindowAsFarAsItGoesAndTheSidebarGivesTheRest() {
        let fit = widths.presenting(windowWidth: 900, screenWidth: 1024)
        #expect(fit.windowWidth == 1024)
        #expect(fit.sidebarWidth == 322)
        #expect(!fit.foldsSidebar)
    }

    @Test func aWindowAtTheScreensWidthAlreadyOnlyMovesTheSidebar() {
        let fit = widths.presenting(windowWidth: 1024, screenWidth: 1024)
        #expect(fit.windowWidth == nil)
        #expect(fit.sidebarWidth == 322)
        #expect(!fit.foldsSidebar)
    }

    @Test func aScreenTooNarrowEvenForTheSidebarsMinimumFoldsItAway() {
        let fit = widths.presenting(windowWidth: 768, screenWidth: 768)
        #expect(fit.foldsSidebar)
        #expect(fit.sidebarWidth == nil)
    }

    @Test func aWindowWiderThanItsScreenIsNeverShrunk() {
        let fit = widths.presenting(windowWidth: 1100, screenWidth: 1000)
        #expect(fit.windowWidth == nil)
        #expect(fit.sidebarWidth == 398)
    }

    @Test func whatIsAskedForIsAlwaysSomethingTheWindowCanBeGiven() {
        for window in stride(from: 600.0, through: 2000, by: 37) {
            for screen in [768.0, 1024, 1280, 1440, 1800, 3008] {
                let fit = widths.presenting(windowWidth: window, screenWidth: screen)
                let settled = fit.windowWidth ?? window
                let neverShrinks = settled >= window
                #expect(neverShrinks)
                let sidebar = fit.foldsSidebar ? 0 : (fit.sidebarWidth ?? widths.sidebar)
                let panesFit = sidebar + widths.divider + widths.detailHalf(withInspector: true) <= settled
                #expect(panesFit)
            }
        }
    }

    @Test func theSidebarKeepsItsReserveOnAnyScreenThatCanAffordIt() {
        #expect(widths.sidebarMaximum(sharing: 1122, withInspector: true) == 420)
        #expect(widths.sidebarMaximum(sharing: 3008, withInspector: true) == 420)
        #expect(widths.sidebarMaximum(sharing: 841, withInspector: false) == 420)
    }

    @Test func theSidebarsCeilingComesDownBeforeItFolds() {
        #expect(widths.sidebarMaximum(sharing: 1024, withInspector: true) == 322)
        #expect(widths.sidebarMaximum(sharing: 902, withInspector: true) == 200)
        #expect(widths.sidebarMaximum(sharing: 901, withInspector: true) == nil)
    }

    @Test func theSidebarMinimumGrowsToHoldWhatItsTitleBarAndFooterNeed() {
        let held = widths.holding(sidebarContent: [243, 228.4])
        #expect(held.sidebarMinimum == 243)
        #expect(widths.holding(sidebarContent: [180]).sidebarMinimum == 200)
        #expect(widths.holding(sidebarContent: []).sidebarMinimum == 200)
    }

    @Test func theSidebarMinimumNeverPassesTheWidthItIsAllowed() {
        #expect(widths.holding(sidebarContent: [900]).sidebarMinimum == widths.sidebar)
    }

    @Test func aWindowAtItsMinimumStillDrawsTheSidebarAtItsNewMinimum() {
        let held = widths.holding(sidebarContent: [312])
        for showing in [true, false] {
            let window = held.minimum(withInspector: showing)
            let room = held.sidebarMaximum(sharing: window, withInspector: showing)
            #expect(room != nil)
            #expect((room ?? 0) >= held.sidebarMinimum)
        }
    }

    @Test func aSidebarHeldWiderFoldsSoonerRatherThanDrawingNarrowerThanItsContent() {
        let held = widths.holding(sidebarContent: [300])
        let room = held.detailHalf(withInspector: false) + held.divider + 250
        #expect(widths.sidebarMaximum(sharing: room, withInspector: false) == 250)
        #expect(held.sidebarMaximum(sharing: room, withInspector: false) == nil)
    }
}
