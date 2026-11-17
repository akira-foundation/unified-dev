import AppKit
import Core
import SwiftTerm

@MainActor
enum TerminalGhostty {
    static let defaultsKey = "useGhosttyTerminalTheme"

    private static var cache: [GhosttyAppearance: GhosttyTheme?] = [:]

    static func theme(for appearance: NSAppearance) -> GhosttyTheme? {
        let key: GhosttyAppearance =
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        if let cached = cache[key] { return cached }

        let loaded = GhosttyConfigLoader.load(appearance: key)
        cache[key] = loaded
        return loaded
    }

    static func splitAppearance() -> GhosttySplitAppearance {
        if let splitCache { return splitCache }
        let loaded = GhosttySplitAppearance.load()
        splitCache = loaded
        return loaded
    }

    private static var splitCache: GhosttySplitAppearance?

    static func font(family: String?, size: CGFloat) -> NSFont {
        guard let family, !family.isEmpty, let font = NSFont(name: family, size: size) else {
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
        return font
    }
}

extension NSColor {
    convenience init(_ color: GhosttyColor) {
        self.init(
            srgbRed: CGFloat(color.red) / 255,
            green: CGFloat(color.green) / 255,
            blue: CGFloat(color.blue) / 255,
            alpha: 1
        )
    }
}

extension SwiftTerm.Color {
    convenience init(_ color: GhosttyColor) {
        self.init(
            red8: UInt16(color.red),
            green8: UInt16(color.green),
            blue8: UInt16(color.blue)
        )
    }

    convenience init(rgb: UInt32) {
        self.init(
            red8: UInt16((rgb >> 16) & 0xFF),
            green8: UInt16((rgb >> 8) & 0xFF),
            blue8: UInt16(rgb & 0xFF)
        )
    }
}
