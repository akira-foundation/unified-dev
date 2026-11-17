import Foundation
import Testing
@testable import Core

@Suite("Terminal palette")
struct TerminalPaletteTests {
    private static let modes: [(name: String, isDark: Bool)] = [("light", false), ("dark", true)]

    @Test("there are sixteen colours, one pair for each ANSI index")
    func sixteenPairs() {
        #expect(TerminalPalette.ansi.count == 16)
        #expect(TerminalPalette.colours(dark: true).count == 16)
        #expect(TerminalPalette.colours(dark: false).count == 16)
    }

    @Test("the palette asked for in dark is the dark member of every pair, and the light one in light")
    func followsTheAppearanceAskedFor() {
        let dark = TerminalPalette.colours(dark: true)
        let light = TerminalPalette.colours(dark: false)
        #expect(dark[4] == 0x7AB4FF)
        #expect(light[4] == 0x0B5CD5)
        for index in 0..<16 {
            #expect(dark[index] == TerminalPalette.ansi[index].dark)
            #expect(light[index] == TerminalPalette.ansi[index].light)
        }
    }

    @Test("only the dark aqua appearance name picks the dark palette")
    func appearanceNamePicksTheMode() {
        #expect(TerminalPalette.isDark(appearanceNamed: "NSAppearanceNameDarkAqua"))
        #expect(!TerminalPalette.isDark(appearanceNamed: "NSAppearanceNameAqua"))
        #expect(!TerminalPalette.isDark(appearanceNamed: nil))
    }

    @Test("a terminal in a dark appearance gets colours readable on the dark pane, and none of the light ones")
    func darkAppearanceGetsTheDarkPalette() {
        let choice = TerminalColourChoice(appearance: "NSAppearanceNameDarkAqua", matchedAppearance: "NSAppearanceNameDarkAqua", ghostty: nil)
        let colours = TerminalPalette.colours(dark: choice.isDark)
        let pane = TerminalPalette.measuredPaneBackground.dark
        #expect(colours[4] == 0x7AB4FF)
        #expect(Contrast.ratio(colours[15], pane) >= Contrast.textFloor)
        #expect(!colours.contains(TerminalPalette.ansi[4].light))
    }

    @Test("the colours are installed again only when the appearance or the Ghostty theme changes")
    func reinstallsOnlyOnChange() {
        var theme = GhosttyTheme()
        theme.background = GhosttyColor(red: 1, green: 2, blue: 3)
        let dark = TerminalColourChoice(appearance: "NSAppearanceNameDarkAqua", matchedAppearance: "NSAppearanceNameDarkAqua", ghostty: nil)
        let darkAgain = TerminalColourChoice(appearance: "NSAppearanceNameDarkAqua", matchedAppearance: "NSAppearanceNameDarkAqua", ghostty: nil)
        let light = TerminalColourChoice(appearance: "NSAppearanceNameAqua", matchedAppearance: "NSAppearanceNameAqua", ghostty: nil)
        let themed = TerminalColourChoice(appearance: "NSAppearanceNameDarkAqua", matchedAppearance: "NSAppearanceNameDarkAqua", ghostty: theme)
        #expect(dark.replaces(nil))
        #expect(!darkAgain.replaces(dark))
        #expect(light.replaces(dark))
        #expect(themed.replaces(dark))
        #expect(dark.replaces(themed))
    }

    @Test("a change inside dark, such as Increase Contrast, installs again even though the mode stays dark")
    func reinstallsWhenTheAppearanceChangesWithinAMode() {
        let dark = TerminalColourChoice(
            appearance: "NSAppearanceNameDarkAqua", matchedAppearance: "NSAppearanceNameDarkAqua", ghostty: nil
        )
        let highContrast = TerminalColourChoice(
            appearance: "NSAppearanceNameAccessibilityHighContrastDarkAqua",
            matchedAppearance: "NSAppearanceNameDarkAqua",
            ghostty: nil
        )
        #expect(highContrast.isDark)
        #expect(highContrast.replaces(dark))
    }

    @Test("every colour but the exempt shade clears its floor on the measured pane background")
    func everyColourIsReadable() {
        for (mode, isDark) in Self.modes {
            let background = TerminalPalette.measuredPaneBackground.member(dark: isDark)
            let colours = TerminalPalette.colours(dark: isDark)
            for index in 0..<16 where index != TerminalPalette.exemptShade(dark: isDark) {
                let ratio = Contrast.ratio(colours[index], background)
                #expect(
                    ratio >= TerminalPalette.contrastFloor(forIndex: index),
                    "index \(index) in \(mode) is \(ratio):1 on \(String(background, radix: 16))"
                )
            }
        }
    }

    @Test("bright black is held to four to one, and every other index to the text floor")
    func floors() {
        #expect(TerminalPalette.contrastFloor(forIndex: 8) == 4.0)
        for index in 0..<16 where index != 8 {
            #expect(TerminalPalette.contrastFloor(forIndex: index) == Contrast.textFloor)
        }
    }

    @Test("the exempt shade is black in dark and bright white in light")
    func exemptShades() {
        #expect(TerminalPalette.exemptShade(dark: true) == 0)
        #expect(TerminalPalette.exemptShade(dark: false) == 15)
    }

    @Test("blue is told apart from magenta in both modes")
    func blueIsNotMagenta() {
        for (mode, isDark) in Self.modes {
            let colours = TerminalPalette.colours(dark: isDark)
            for (blue, magenta) in [(4, 5), (12, 13)] {
                let distance = Contrast.deltaE(colours[blue], colours[magenta])
                #expect(distance >= 20, "\(blue) and \(magenta) in \(mode) are only \(distance) apart")
            }
        }
    }

    @Test("blue has a blue hue, not a violet one")
    func blueIsBlue() {
        for isDark in [false, true] {
            for index in [4, 12] {
                let lab = Contrast.lab(of: TerminalPalette.colours(dark: isDark)[index])
                var hue = atan2(lab.b, lab.a) * 180 / .pi
                if hue < 0 { hue += 360 }
                #expect((240...308).contains(hue), "index \(index) has hue \(hue)")
            }
        }
    }

    @Test("each bright colour differs from its normal one, lighter in dark and darker in light")
    func brightColoursAreDistinct() {
        for (mode, isDark) in Self.modes {
            let colours = TerminalPalette.colours(dark: isDark)
            for normal in 1...6 {
                let bright = normal + 8
                let normalLuminance = Contrast.relativeLuminance(of: colours[normal])
                let brightLuminance = Contrast.relativeLuminance(of: colours[bright])
                #expect(colours[normal] != colours[bright], "\(normal) and \(bright) match in \(mode)")
                #expect(
                    isDark ? brightLuminance > normalLuminance : brightLuminance < normalLuminance,
                    "\(bright) does not move away from \(normal) in \(mode)"
                )
            }
        }
    }

    @Test("the grey pairs differ too: black from bright black, white from bright white")
    func greyPairsAreDistinct() {
        for isDark in [false, true] {
            let colours = TerminalPalette.colours(dark: isDark)
            #expect(colours[0] != colours[8])
            #expect(colours[7] != colours[15])
        }
    }
}
