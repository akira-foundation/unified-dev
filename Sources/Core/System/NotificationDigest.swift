import Foundation

public struct NotificationDraft: Sendable, Hashable {
    public var event: NotificationEvent
    public var workspaceID: WorkspaceID
    public var sessionID: SessionID?
    public var workspaceName: String
    public var detail: String

    public init(
        event: NotificationEvent,
        workspaceID: WorkspaceID,
        sessionID: SessionID? = nil,
        workspaceName: String,
        detail: String = ""
    ) {
        self.event = event
        self.workspaceID = workspaceID
        self.sessionID = sessionID
        self.workspaceName = workspaceName
        self.detail = detail
    }
}

public struct PreparedNotification: Sendable, Hashable {
    public var identifier: String
    public var threadIdentifier: String
    public var title: String
    public var body: String
    public var workspaceID: WorkspaceID
    public var workspaceIDs: [WorkspaceID]
    public var sessionID: SessionID?

    public init(
        identifier: String,
        threadIdentifier: String,
        title: String,
        body: String,
        workspaceID: WorkspaceID,
        workspaceIDs: [WorkspaceID]? = nil,
        sessionID: SessionID? = nil
    ) {
        self.identifier = identifier
        self.threadIdentifier = threadIdentifier
        self.title = title
        self.body = body
        self.workspaceID = workspaceID
        self.workspaceIDs = workspaceIDs ?? [workspaceID]
        self.sessionID = sessionID
    }
}

public struct NotificationDigest: Sendable {
    public static let window = Duration.milliseconds(2_500)

    public static let bodyLimit = 240

    private var pending: [NotificationEvent: [NotificationDraft]] = [:]

    public init() {}

    public var isEmpty: Bool { pending.isEmpty }

    @discardableResult
    public mutating func add(_ draft: NotificationDraft) -> Bool {
        var batch = pending[draft.event] ?? []
        let isNewBatch = batch.isEmpty
        batch.removeAll { $0.workspaceID == draft.workspaceID }
        batch.append(draft)
        pending[draft.event] = batch
        return isNewBatch
    }

    public mutating func drain(_ event: NotificationEvent) -> PreparedNotification? {
        guard let batch = pending.removeValue(forKey: event) else { return nil }
        return Self.prepare(batch)
    }

    public static func prepare(_ batch: [NotificationDraft]) -> PreparedNotification? {
        guard let first = batch.first else { return nil }
        guard batch.count > 1 else {
            let detail = first.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return PreparedNotification(
                identifier: "unifieddev.\(first.event.rawValue).\(first.workspaceID)",
                threadIdentifier: first.workspaceID.rawValue,
                title: first.workspaceName,
                body: cap(detail.isEmpty ? first.event.fallbackDetail : detail),
                workspaceID: first.workspaceID,
                sessionID: first.sessionID
            )
        }

        return PreparedNotification(
            identifier: "unifieddev.\(first.event.rawValue).digest",
            threadIdentifier: "unifieddev.\(first.event.rawValue)",
            title: first.event.summaryTitle(count: batch.count),
            body: cap(batch.map(\.workspaceName).joined(separator: ", ")),
            workspaceID: first.workspaceID,
            workspaceIDs: batch.map(\.workspaceID)
        )
    }

    static func cap(_ text: String) -> String {
        let firstLine = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        guard firstLine.count > bodyLimit else { return firstLine }
        return String(firstLine.prefix(bodyLimit)).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }
}
