import Foundation

public enum SearchPanelRowInk: Equatable, Sendable {
    case primary
    case secondary
    case muted

    public static let mutedOpacityOnSelection = 0.76

    public static func title(isEnabled: Bool) -> SearchPanelRowInk {
        isEnabled ? .primary : .muted
    }

    public static func detail(isEnabled: Bool = true) -> SearchPanelRowInk {
        isEnabled ? .secondary : .muted
    }

    public static let heading = SearchPanelRowInk.secondary

    public var isSecondaryOffSelection: Bool { self != .primary }

    public var opacityOnSelection: Double {
        self == .muted ? Self.mutedOpacityOnSelection : 1
    }
}
