import Foundation

public enum SearchPanelRowInk: Equatable, Sendable {
    case primary
    case secondary
    case tertiary

    public static func title(isEnabled: Bool) -> SearchPanelRowInk {
        isEnabled ? .primary : .secondary
    }

    public static func detail(isEnabled: Bool = true) -> SearchPanelRowInk {
        isEnabled ? .secondary : .tertiary
    }

    public static let heading = SearchPanelRowInk.secondary
}
