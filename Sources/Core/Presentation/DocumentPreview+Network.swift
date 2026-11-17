import Foundation

extension DocumentPreview {
    public static let networkRuleListIdentifier = "unified-dev-preview-network"

    static let blockedAddressPatterns = ["^https?:", "^wss?:"]

    public static var networkRules: String {
        let rules = blockedAddressPatterns.map { pattern in
            ["trigger": ["url-filter": pattern], "action": ["type": "block"]]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys]) else {
            return "[]"
        }
        return String(decoding: data, as: UTF8.self)
    }
}
