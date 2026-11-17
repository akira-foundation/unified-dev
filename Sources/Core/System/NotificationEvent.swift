import Foundation

public enum NotificationEvent: String, CaseIterable, Sendable, Hashable, Codable {
    case turnFinished
    case needsInput
    case agentFailed
    case setupFailed
    case checksFinished
    case quotaExhausted
    case pullRequestFixStopped

    public var title: String {
        switch self {
        case .turnFinished: "An agent finishes its turn"
        case .needsInput: "An agent needs something from me"
        case .agentFailed: "An agent stops without finishing"
        case .setupFailed: "A setup script fails"
        case .checksFinished: "Checks finish on a pull request"
        case .quotaExhausted: "An agent reaches its usage limit"
        case .pullRequestFixStopped: "Automatic fixes stop on a pull request"
        }
    }

    public var detail: String {
        switch self {
        case .turnFinished:
            "The agent has answered and is waiting for you."
        case .needsInput:
            "The turn ended without doing the work: a permission was denied, or it ran out of turns."
        case .agentFailed:
            "The agent exited without finishing. A model it does not know, expired credentials, a crash."
        case .setupFailed:
            "The workspace was created but its setup script exited non-zero, so no agent was started."
        case .checksFinished:
            "CI on the workspace's pull request went from pending to a result."
        case .quotaExhausted:
            "The account the agent runs under has used all of a usage window."
        case .pullRequestFixStopped:
            "A pull request's conflicts or failed checks were sent to its agent three times in a row without the checks passing."
        }
    }

    public var inboxLabel: String {
        switch self {
        case .turnFinished: "Turn finished"
        case .needsInput: "Needs you"
        case .agentFailed: "Agent stopped"
        case .setupFailed: "Setup failed"
        case .checksFinished: "Checks finished"
        case .quotaExhausted: "Limit reached"
        case .pullRequestFixStopped: "Automatic fixes stopped"
        }
    }

    public var fallbackDetail: String {
        switch self {
        case .turnFinished: "The agent finished its turn."
        case .needsInput: "The agent needs something from you before it can carry on."
        case .agentFailed: "The agent stopped without finishing the turn."
        case .setupFailed: "The setup script failed. The agent was started anyway."
        case .checksFinished: "The checks finished."
        case .quotaExhausted: "The agent reached a usage limit."
        case .pullRequestFixStopped: "Stopped asking the agent to fix a pull request."
        }
    }

    public func summaryTitle(count: Int) -> String {
        switch self {
        case .turnFinished: "\(count) agents finished"
        case .needsInput: "\(count) agents need you"
        case .agentFailed: "\(count) agents stopped"
        case .setupFailed: "Setup failed in \(count) workspaces"
        case .checksFinished: "Checks finished in \(count) workspaces"
        case .quotaExhausted: "\(count) agents reached a limit"
        case .pullRequestFixStopped: "Automatic fixes stopped in \(count) workspaces"
        }
    }
}

public struct NotificationSettings: Sendable, Hashable {
    public var isEnabled: Bool
    public var enabledEvents: Set<NotificationEvent>

    public init(
        isEnabled: Bool = false,
        enabledEvents: Set<NotificationEvent> = Set(NotificationEvent.allCases)
    ) {
        self.isEnabled = isEnabled
        self.enabledEvents = enabledEvents
    }

    public func allows(_ event: NotificationEvent) -> Bool {
        isEnabled && enabledEvents.contains(event)
    }
}

public struct NotificationPreferences: @unchecked Sendable {
    public static let enabledKey = "notifications.enabled"
    public static let eventKeyPrefix = "notifications.event."

    public static func key(for event: NotificationEvent) -> String {
        eventKeyPrefix + event.rawValue
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    public func isEnabled(_ event: NotificationEvent) -> Bool {
        defaults.object(forKey: Self.key(for: event)) as? Bool ?? true
    }

    public func setEnabled(_ value: Bool, for event: NotificationEvent) {
        defaults.set(value, forKey: Self.key(for: event))
    }

    public var settings: NotificationSettings {
        NotificationSettings(
            isEnabled: isEnabled,
            enabledEvents: Set(NotificationEvent.allCases.filter(isEnabled))
        )
    }
}
