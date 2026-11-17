import Foundation

public enum AgentAccountOffer: Sendable, Equatable {
    case available
    case unavailable(reason: String)

    public var isAvailable: Bool { self == .available }

    public static func make(for provider: AgentKind, codexStorageMode: CodexAuthStorageMode) -> AgentAccountOffer {
        let doubt = AgentAccountRoster.isolationDoubt(for: provider, codexStorageMode: codexStorageMode)
        if let doubt { return refusal(provider, doubt) }
        guard AgentAccountLiveness.canAsk(about: provider) else {
            return refusal(
                provider,
                "Unified Dev cannot ask \(provider.label) whether a directory holds a login of its own."
            )
        }
        return .available
    }

    public static func canEverBeOffered(_ provider: AgentKind) -> Bool {
        make(for: provider, codexStorageMode: .file).isAvailable
    }

    private static func refusal(_ provider: AgentKind, _ because: String) -> AgentAccountOffer {
        .unavailable(reason: "Unified Dev cannot add another \(provider.label) account. \(because)")
    }
}
