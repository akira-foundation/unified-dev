import Foundation

public struct SideConversationFocus: Sendable, Hashable {
    private var chosen: SessionID?
    private var chosenWhileActive: SessionID?

    public init() {}

    public mutating func choose(_ parent: SessionID, active: SessionID?) {
        chosen = parent
        chosenWhileActive = active
    }

    public mutating func activeChatChanged() {
        chosen = nil
        chosenWhileActive = nil
    }

    public func parent(active: SessionID?, present: Set<SessionID>) -> SessionID? {
        if let chosen, chosenWhileActive == active, present.contains(chosen) { return chosen }
        guard let active, present.contains(active) else { return nil }
        return active
    }
}
