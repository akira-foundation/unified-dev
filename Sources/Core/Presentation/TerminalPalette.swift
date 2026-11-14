import Foundation

public enum TerminalPalette {
    public static let measuredBackground = PaletteInk.Pair(light: 0xFFFFFF, dark: 0x303135)

    public static let ansi: [PaletteInk.Pair] = [
        PaletteInk.Pair(light: 0x000000, dark: 0x1C1C1E),
        PaletteInk.Pair(light: 0xD70015, dark: 0xFF7B7B),
        PaletteInk.Pair(light: 0x2E7D32, dark: 0x6FCF7B),
        PaletteInk.Pair(light: 0xA15C00, dark: 0xFF9F0A),
        PaletteInk.Pair(light: 0x0B5CD5, dark: 0x7AB4FF),
        PaletteInk.Pair(light: 0xA21CAF, dark: 0xE38BFF),
        PaletteInk.Pair(light: 0x00727D, dark: 0x00D2E0),
        PaletteInk.Pair(light: 0x6E6E73, dark: 0xAEAEB2),
        PaletteInk.Pair(light: 0x59595E, dark: 0x98989D),
        PaletteInk.Pair(light: 0xA30010, dark: 0xFFA8A8),
        PaletteInk.Pair(light: 0x1B5E20, dark: 0xA6F0AE),
        PaletteInk.Pair(light: 0x7A4500, dark: 0xFFD15C),
        PaletteInk.Pair(light: 0x0040A8, dark: 0xA8CCFF),
        PaletteInk.Pair(light: 0x7B1488, dark: 0xF0BAFF),
        PaletteInk.Pair(light: 0x00545C, dark: 0x7DEAF2),
        PaletteInk.Pair(light: 0xEBEBF0, dark: 0xFFFFFF),
    ]

    public static let brightBlack = 8

    public static func colours(dark: Bool) -> [UInt32] {
        ansi.map { $0.member(dark: dark) }
    }

    public static func backgroundShade(dark: Bool) -> Int {
        dark ? 0 : 15
    }

    public static func floor(forIndex index: Int) -> Double {
        index == brightBlack ? 4.0 : Contrast.textFloor
    }
}
