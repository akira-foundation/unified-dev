import Foundation

extension Store {
    func changeSettings(
        _ keys: [String],
        _ change: @Sendable (_ current: [String: String]) -> [String: String?]
    ) throws {
        try inTransaction {
            var current: [String: String] = [:]
            for key in keys { current[key] = try setting(key) }
            for (key, value) in change(current) where keys.contains(key) && current[key] != value {
                try setSetting(key, value)
            }
        }
    }
}
