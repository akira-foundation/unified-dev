import Foundation

public enum InboxDestination: Sendable, Hashable {
    case chat(WorkspaceID, SessionID?)
    case chatGone(WorkspaceID)
    case archived(WorkspaceID, SessionID?)
    case gone
}

public struct InboxNotification: Sendable, Hashable, Identifiable {
    public var id: InboxNotificationID
    public var event: NotificationEvent
    public var workspaceID: WorkspaceID
    public var sessionID: SessionID?
    public var workspaceName: String
    public var detail: String
    public var createdAt: Date
    public var readAt: Date?
    public var profileID: ProfileID?
    public var workspaceState: WorkspaceState?
    public var chatExists: Bool

    public init(
        id: InboxNotificationID = .new(),
        event: NotificationEvent,
        workspaceID: WorkspaceID,
        sessionID: SessionID? = nil,
        workspaceName: String,
        detail: String = "",
        createdAt: Date,
        readAt: Date? = nil,
        profileID: ProfileID? = nil,
        workspaceState: WorkspaceState? = .active,
        chatExists: Bool = true
    ) {
        self.id = id
        self.event = event
        self.workspaceID = workspaceID
        self.sessionID = sessionID
        self.workspaceName = workspaceName
        self.detail = detail
        self.createdAt = createdAt
        self.readAt = readAt
        self.profileID = profileID
        self.workspaceState = workspaceState
        self.chatExists = chatExists
    }

    public var isRead: Bool { readAt != nil }

    public var destination: InboxDestination {
        guard let workspaceState else { return .gone }
        if workspaceState == .archived { return .archived(workspaceID, chatExists ? sessionID : nil) }
        guard sessionID != nil, !chatExists else { return .chat(workspaceID, sessionID) }
        return .chatGone(workspaceID)
    }

    public var counts: Bool { !isRead && destination != .gone }
}
