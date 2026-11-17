import Foundation

public struct InboxRowReading: Sendable, Hashable {
    public static let goneSentence = "This workspace no longer exists."
    public static let chatGoneNotice = "That chat no longer exists, so its workspace was opened instead."

    public static let replyNotSentNotice = "That chat no longer exists, so your reply was not sent."

    public var title: String
    public var origin: String
    public var detail: String
    public var age: String
    public var isDimmed: Bool
    public var opens: Bool
    public var accessibilityLabel: String

    public init(_ row: InboxNotification, profileName: String?, now: Date) {
        let isGone = row.destination == .gone
        let spoken = row.detail.isEmpty ? row.event.fallbackDetail : row.detail
        title = row.workspaceName
        origin = [profileName, row.event.inboxLabel].compactMap { $0 }.joined(separator: " \u{00B7} ")
        detail = isGone ? Self.goneSentence : spoken
        age = UsageFormat.compactDuration(max(0, now.timeIntervalSince(row.createdAt)))
        isDimmed = row.isRead || isGone
        opens = !isGone
        accessibilityLabel = [row.counts ? "Unseen" : nil, title, origin, detail, age]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
