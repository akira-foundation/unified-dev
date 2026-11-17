import Foundation

public struct WorkspaceDoneWatch: Identifiable, Sendable, Hashable {
    public enum Cause: Sendable, Hashable {
        case message(WorkspaceMessageID, state: WorkspaceMessage.State)
        case start
    }

    public let id: WorkspaceDoneWatchID
    public let cause: Cause
    public let watcherSessionID: SessionID
    public internal(set) var target: WorkspaceMessageEnd
    public let createdAt: Date
    public let notifiedAt: Date?

    public init(
        id: WorkspaceDoneWatchID = .new(),
        cause: Cause,
        watcherSessionID: SessionID,
        target: WorkspaceMessageEnd,
        createdAt: Date = Date(),
        notifiedAt: Date? = nil
    ) {
        self.id = id
        self.cause = cause
        self.watcherSessionID = watcherSessionID
        self.target = target
        self.createdAt = createdAt
        self.notifiedAt = notifiedAt
    }

    public func verdict(
        on ending: WorkspaceTurnEnding, in sessionID: SessionID?, isSubagentChat: Bool
    ) -> WorkspaceDoneVerdict {
        guard notifiedAt == nil else { return .ignore }
        if case .message(_, .cancelled) = cause { return .discard }
        guard ending == .archived || isWatching(sessionID, isSubagentChat: isSubagentChat) else {
            return .ignore
        }
        return .notify(WorkspaceDoneNotice.message(for: ending, watch: self))
    }

    private func isWatching(_ sessionID: SessionID?, isSubagentChat: Bool) -> Bool {
        if wasNeverRead { return false }
        guard let watched = target.sessionID else { return !isSubagentChat }
        return watched == sessionID
    }

    public static let argument = "notify_when_done"

    public static func isRequested(_ value: JSONValue?) -> Bool {
        switch value {
        case .bool(let flag)?: flag
        case .string(let text)?: text.trimmingCharacters(in: .whitespaces).lowercased() == "true"
        default: false
        }
    }

    var wasNeverRead: Bool {
        if case .message(_, .queued) = cause { return true }
        return false
    }
}
