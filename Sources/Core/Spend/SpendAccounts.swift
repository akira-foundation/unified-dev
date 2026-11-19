import Foundation

public enum SpendAccounts {
    public static let unknown = "Unknown account"

    public static func defaultHomes(home: URL = TranscriptHome.resolve()) -> [AgentAccountHome] {
        TranscriptSources.sources(provider: home).map {
            AgentAccountHome(
                provider: $0.provider,
                id: AgentAccountHome.defaultID(for: $0.provider),
                directory: $0.home,
                isDefault: true
            )
        }
    }
}
