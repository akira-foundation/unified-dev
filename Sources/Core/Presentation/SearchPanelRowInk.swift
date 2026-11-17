import Foundation

public enum SearchPanelRowInk: Equatable, Sendable {
    case primary
    case secondary

    public static func title(isEnabled: Bool) -> SearchPanelRowInk {
        isEnabled ? .primary : .secondary
    }

    public static func detail(isSelected: Bool, isEnabled: Bool = true) -> SearchPanelRowInk {
        isSelected && isEnabled ? .primary : .secondary
    }
}
