import Foundation

public struct AppWideOutputStyles: Sendable, Hashable {
    public let refused: Set<AgentKind>

    public init(accounts: ProfileAccounts, profiles: [Profile]) {
        refused = accounts.defaultAccountIsShared(by: profiles) ? [] : [.claudeCode]
    }

    public var offersDefaultAccountStyles: Bool {
        !refused.contains(.claudeCode)
    }

    public var settingsFooter: String {
        offersDefaultAccountStyles
            ? "These are the output styles of the default Claude Code account. A project that runs another account may not have the style you choose."
            : "Only the built-in output styles are offered, beside the style already chosen. These settings apply to every profile, and a profile with its own accounts does not have the default account's styles."
    }

    public var presetLabel: String {
        offersDefaultAccountStyles ? "From the default Claude Code account" : "Built-in styles and the current choice"
    }

    public static func claudeAccount(in defaults: [AgentAccountHome]) -> AgentAccountHome? {
        defaults.first { $0.provider == .claudeCode }
    }
}

extension OutputStyleShelves {
    public func appWide(_ reading: AppWideOutputStyles, defaults: [AgentAccountHome]) -> Catalogue {
        catalogue(project: nil, account: AppWideOutputStyles.claudeAccount(in: defaults), refusing: reading.refused)
    }
}
