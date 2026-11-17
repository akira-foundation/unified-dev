import Foundation

public struct QuotaHolder: Sendable, Hashable {
    public let provider: AgentKind
    public let account: AgentAccountID

    public init(provider: AgentKind, account: AgentAccountID?) {
        self.provider = provider
        self.account = account ?? AgentAccountHome.defaultID(for: provider)
    }

    public init(provider: AgentKind, home: AgentAccountHome?) {
        self.init(provider: provider, account: home?.provider == provider ? home?.id : nil)
    }
}
