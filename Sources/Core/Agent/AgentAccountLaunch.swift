import Foundation

public struct AgentAccountRefusal: Error, Sendable, Equatable, CustomStringConvertible {
    public let provider: AgentKind
    public let isChoiceLost: Bool

    public init(provider: AgentKind, isChoiceLost: Bool) {
        self.provider = provider
        self.isChoiceLost = isChoiceLost
    }

    public var description: String {
        "\(provider.label) did not start, \(because)"
    }

    public var beforeStarting: String {
        "\(provider.label) does not start here, \(because)"
    }

    private var because: String {
        let agent = provider.label
        let why = isChoiceLost
            ? "the \(agent) account chosen for it is not available"
            : "it has no \(agent) account chosen"
        return "because this profile has accounts of its own and \(why). "
            + "Choose one for the project, or a default for the profile in Profile Settings."
    }
}

public enum AgentAccountLaunch: Sendable, Equatable {
    case runs(AgentAccountHome?)
    case refused(AgentAccountRefusal)

    public static func decide(
        choice: AgentAccountChoice,
        provider: AgentKind,
        profile: ProfileID?,
        accounts: ProfileAccounts
    ) -> AgentAccountLaunch {
        decide(choice: choice, provider: provider, outsideUnified: accounts.keepsOwnAccounts(profile))
    }

    public static func decide(
        choice: AgentAccountChoice,
        provider: AgentKind,
        outsideUnified: Bool
    ) -> AgentAccountLaunch {
        let isLost = choice.isProjectChoiceLost || choice.isProfileChoiceLost
        let fallsToTheMac = switch choice.reason {
        case .project, .profile: false
        case .providerDefault: true
        case .noAccount: isLost
        }
        guard outsideUnified, fallsToTheMac else { return .runs(choice.home) }
        return .refused(AgentAccountRefusal(provider: provider, isChoiceLost: isLost))
    }

    public func home() throws -> AgentAccountHome? {
        switch self {
        case .runs(let home): home
        case .refused(let refusal): throw refusal
        }
    }

    public var isRefused: Bool {
        if case .refused = self { true } else { false }
    }
}
