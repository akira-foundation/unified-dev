import Foundation

public enum ComposerSettingsEvent: Equatable, Sendable {
    case pressedSend(canSend: Bool)
    case firedQuickPrompt(QuickPromptDelivery)
    case savedPreset
    case changedAccount
    case openedInNewChat

    public var closesSettings: Bool {
        switch self {
        case .pressedSend(let canSend):
            canSend
        case .firedQuickPrompt(let delivery):
            delivery.sends
        case .savedPreset, .changedAccount, .openedInNewChat:
            true
        }
    }
}

public struct ComposerSettingsCloseRequests: Equatable, Sendable {
    public private(set) var count = 0

    public init() {}

    public mutating func note(_ event: ComposerSettingsEvent) {
        if event.closesSettings { count += 1 }
    }
}
