import AppKit
import Core
import SwiftUI

struct ProfileMark: View {
    var symbol: String
    var colour: String

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(Color(hexString: colour))
            .accessibilityHidden(true)
    }
}

struct ProfileMenuLabel: View {
    var profile: Profile

    var body: some View {
        Label {
            Text(profile.name)
        } icon: {
            if let mark = ProfileMarkImage.of(symbol: profile.symbol, colour: profile.colour) {
                Image(nsImage: mark).renderingMode(.original)
            }
        }
    }
}

@MainActor
enum ProfileMarkImage {
    private struct Key: Hashable {
        var symbol: String
        var colour: String
    }

    private static var cache: [Key: NSImage] = [:]

    static func of(symbol: String, colour: String) -> NSImage? {
        guard let parsed = HexColor(hex: colour) else { return nil }
        let key = Key(symbol: symbol, colour: colour.lowercased())
        if let cached = cache[key] { return cached }
        let tint = NSColor(
            srgbRed: CGFloat(parsed.red) / 255,
            green: CGFloat(parsed.green) / 255,
            blue: CGFloat(parsed.blue) / 255,
            alpha: 1
        )
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [tint]))
        else { return nil }
        image.isTemplate = false
        cache[key] = image
        return image
    }
}
