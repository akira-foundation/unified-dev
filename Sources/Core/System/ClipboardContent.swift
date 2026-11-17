import Foundation

public struct ClipboardContent: Sendable, Equatable {
    public struct Representation: Sendable, Equatable {
        public let type: String
        public let data: Data
    }

    public static let plainTextType = "public.utf8-plain-text"
    public static let concealedType = "org.nspasteboard.ConcealedType"

    public let text: String
    public let isConcealed: Bool

    public static func plain(_ text: String) -> ClipboardContent {
        ClipboardContent(text: text, isConcealed: false)
    }

    public static func command(_ text: String) -> ClipboardContent {
        ClipboardContent(text: text, isConcealed: text.contains(BridgeProtocol.tokenVariable))
    }

    public var representations: [Representation] {
        let text = Representation(type: Self.plainTextType, data: Data(text.utf8))
        guard isConcealed else { return [text] }
        return [text, Representation(type: Self.concealedType, data: Data())]
    }
}
