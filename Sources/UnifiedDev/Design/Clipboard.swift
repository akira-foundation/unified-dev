import AppKit
import Core

enum Clipboard {
    static func copy(_ text: String) {
        copy(.plain(text))
    }

    static func copy(_ content: ClipboardContent) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        for representation in content.representations {
            pasteboard.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.type))
        }
    }

    static let flashDuration: Duration = .seconds(1.5)
}
