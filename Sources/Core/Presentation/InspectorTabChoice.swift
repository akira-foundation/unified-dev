import Foundation

public struct InspectorTabChoice: Equatable, Sendable {
    public private(set) var chosen: InspectorTab
    private var beforeSide: InspectorTab?

    public init(_ chosen: InspectorTab = .changes) {
        self.chosen = chosen
    }

    public mutating func choose(_ tab: InspectorTab) {
        chosen = tab
        if tab != .side { beforeSide = nil }
    }

    public mutating func sideConversationStarted() {
        guard chosen != .side else { return }
        beforeSide = chosen
        chosen = .side
    }

    public mutating func sideConversationLeft() {
        guard chosen == .side else { return }
        chosen = beforeSide ?? InspectorTab.fallback
        beforeSide = nil
    }

    public func resolved(available: [InspectorTab]) -> InspectorTab {
        InspectorTab.resolve(chosen, available: available)
    }
}
