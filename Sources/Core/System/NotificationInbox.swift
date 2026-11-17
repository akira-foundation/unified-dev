import Foundation

public enum InboxOpening: Sendable, Hashable {
    case chat(WorkspaceID, SessionID?)
    case archive(WorkspaceID)
    case replied(WorkspaceID, SessionID)

    public var workspaceID: WorkspaceID {
        switch self {
        case .chat(let id, _), .archive(let id), .replied(let id, _): id
        }
    }
}

public enum NotificationInbox {
    public static let retention: TimeInterval = 7 * 24 * 60 * 60
    public static let capacity = 200

    public static func ordered(_ rows: [InboxNotification]) -> [InboxNotification] {
        rows.sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
    }

    public static func unseenCount(_ rows: [InboxNotification]) -> Int {
        rows.count(where: \.counts)
    }

    public static func row(
        forBannerIn rows: [InboxNotification], workspaceID: WorkspaceID, sessionID: SessionID?
    ) -> InboxNotification? {
        ordered(rows).first { $0.workspaceID == workspaceID && $0.sessionID == sessionID }
    }

    public static func shouldRecord(
        workspaceID: WorkspaceID, sessionID: SessionID?, context: NotificationContext
    ) -> Bool {
        guard context.isAppActive, context.selectedWorkspaceID == workspaceID else { return true }
        guard let sessionID else { return false }
        return context.selectedSessionID != sessionID
    }

    public static func opening(
        selection: SidebarSelection, activeSession: SessionID?, isAppActive: Bool
    ) -> InboxOpening? {
        guard isAppActive else { return nil }
        switch selection {
        case .workspace(let id): return .chat(id, activeSession)
        case .archived(let id): return .archive(id)
        default: return nil
        }
    }

    public static func clears(_ row: InboxNotification, by opening: InboxOpening) -> Bool {
        guard !row.isRead, row.workspaceID == opening.workspaceID else { return false }
        switch opening {
        case .archive:
            return true
        case .replied(_, let session):
            return row.sessionID == session
        case .chat(_, let session):
            return row.sessionID == nil || row.sessionID == session || !row.chatExists
        }
    }
}
