import Foundation

public struct QuotaExhaustionWatch: Sendable {
    private var told: [String: Date?] = [:]

    public init() {}

    public mutating func newlyExhausted(
        fromRateLimitEvent data: Data, in workspace: WorkspaceID, at now: Date = Date()
    ) -> [AgentQuota] {
        let refused = JSONValue.parse(data)?["rate_limit_info"]?["status"]?.stringValue == "rejected"
        return AgentQuotaAdapters.quotas(fromRateLimitEvent: data, at: now).filter { quota in
            let key = "\(workspace.rawValue)/\(quota.id)"
            guard refused || Self.isSpent(quota) else {
                if quota.resetsAt == nil { told[key] = nil }
                return false
            }
            if let earlier = told[key], earlier == quota.resetsAt { return false }
            told[key] = .some(quota.resetsAt)
            return true
        }
    }

    public static func sentence(for quota: AgentQuota) -> String {
        "All of the \(quota.window.label.lowercased()) allowance used"
    }

    private static func isSpent(_ quota: AgentQuota) -> Bool {
        guard let fraction = quota.fraction else { return false }
        return UsageMeterReading.isSpent(used: fraction, limit: 1, money: false)
    }
}
