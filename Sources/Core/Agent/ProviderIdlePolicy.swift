import Foundation

public enum ProviderIdlePolicy {
    public static let settingKey = "agents.idleProcessMinutes"
    public static let choices = [0, 15, 30, 60, 120]
    public static let defaultMinutes = 30

    public static func minutes(stored: String?) -> Int {
        guard let stored else { return defaultMinutes }
        guard let value = Int(stored), choices.contains(value) else { return 0 }
        return value
    }

    public static func duration(stored: String?) -> Duration? {
        let value = minutes(stored: stored)
        guard value > 0 else { return nil }
        return .seconds(value * 60)
    }

    public static func duration(in store: Store) async -> Duration? {
        do {
            return duration(stored: try await store.setting(settingKey))
        } catch {
            return nil
        }
    }
}

public enum ProviderIdleError: Error, Sendable {
    case retired
}
