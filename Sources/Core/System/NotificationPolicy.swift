import Foundation

public struct NotificationContext: Sendable, Hashable {
    public var isAppActive: Bool
    public var selectedWorkspaceID: WorkspaceID?
    public var selectedSessionID: SessionID?

    public init(isAppActive: Bool, selectedWorkspaceID: WorkspaceID?, selectedSessionID: SessionID? = nil) {
        self.isAppActive = isAppActive
        self.selectedWorkspaceID = selectedWorkspaceID
        self.selectedSessionID = selectedSessionID
    }
}

public enum NotificationVerdict: Sendable, Hashable {
    case deliver
    case notificationsAreOff
    case eventIsOff
    case alreadyOnScreen

    public var delivers: Bool { self == .deliver }
}

public enum NotificationPolicy {
    public static func verdict(
        for event: NotificationEvent,
        workspaceID: WorkspaceID,
        settings: NotificationSettings,
        context: NotificationContext
    ) -> NotificationVerdict {
        guard settings.isEnabled else { return .notificationsAreOff }
        guard settings.enabledEvents.contains(event) else { return .eventIsOff }

        if context.isAppActive, context.selectedWorkspaceID == workspaceID {
            return .alreadyOnScreen
        }

        return .deliver
    }
}
