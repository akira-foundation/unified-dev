import Foundation

extension MenuShortcut {
    public var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "\u{2303}" }
        if modifiers.contains(.option) { text += "\u{2325}" }
        if modifiers.contains(.shift) { text += "\u{21E7}" }
        if modifiers.contains(.command) { text += "\u{2318}" }
        return text + Self.glyph(for: trigger)
    }

    static func glyph(for trigger: Trigger) -> String {
        switch trigger {
        case .character(let character): String(character).uppercased()
        case .upArrow: "\u{2191}"
        case .downArrow: "\u{2193}"
        case .leftArrow: "\u{2190}"
        case .rightArrow: "\u{2192}"
        case .delete: "\u{232B}"
        case .return: "\u{21A9}"
        case .comma: ","
        case .tab: "\u{21E5}"
        case .escape: "\u{238B}"
        }
    }
}

extension MenuBarItem {
    public var keyText: String? {
        let shown = [key, alternateKey].compactMap { $0?.display }
        return shown.isEmpty ? nil : shown.joined(separator: " ")
    }

    public func help(_ phrase: String) -> String {
        guard let key else { return phrase }
        return "\(phrase) (\(key.display))"
    }
}
