import Foundation

public enum AgentSettingsEvent: Sendable, CaseIterable {
    case sentMessage
    case savedPreset
    case changedAccount
    case openedInNewChat
    case changedSetting

    public var closesSettings: Bool {
        switch self {
        case .sentMessage, .savedPreset, .changedAccount, .openedInNewChat:
            true
        case .changedSetting:
            false
        }
    }
}
