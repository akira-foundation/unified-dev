import Foundation

extension PreviewScenario {
    public static let holdsQuotasKey = "preview.holdsSeededQuotas"

    public static let silentAgentsKey = "preview.silentAgents"

    public static let agentsWithoutLimitsKey = "preview.agentsWithoutLimits"

    public struct Quota: Sendable, Equatable, Codable {
        public var provider: AgentKind
        public var window: String
        public var label: String?
        public var hours: Double?
        public var used: Double?
        public var resetsInMinutes: Double?
        public var readMinutesAgo: Double?
        public var account: String?

        public init(
            provider: AgentKind,
            window: String,
            label: String? = nil,
            hours: Double? = nil,
            used: Double? = nil,
            resetsInMinutes: Double? = nil,
            readMinutesAgo: Double? = nil,
            account: String? = nil
        ) {
            self.provider = provider
            self.window = window
            self.label = label
            self.hours = hours
            self.used = used
            self.resetsInMinutes = resetsInMinutes
            self.readMinutesAgo = readMinutesAgo
            self.account = account
        }

        public var id: String {
            guard let account else { return "\(provider.rawValue)/\(window)" }
            return "\(provider.rawValue)/\(account)/\(window)"
        }

        public func quota(at now: Date) -> AgentQuota {
            let named = QuotaWindow.named(window)
            let duration = hours.map { $0 * 3600 } ?? named.duration
            let fallback = hours.map { QuotaWindow.label(forSeconds: $0 * 3600) } ?? named.label
            return AgentQuota(
                provider: provider,
                window: QuotaWindow(key: window, label: label ?? fallback, duration: duration),
                measure: used.map { .fraction($0) } ?? .unknown,
                resetsAt: resetsInMinutes.map { now.addingTimeInterval($0 * 60) },
                observedAt: readMinutesAgo.map { now.addingTimeInterval(-$0 * 60) } ?? now,
                account: QuotaHolder(provider: provider, account: account.map(AgentAccountID.init)).account
            )
        }
    }

    public var holdsSeededQuotas: Bool {
        !quotas.isEmpty || !silentAgents.isEmpty || !agentsWithoutLimits.isEmpty
    }

    public static func agents(storedAs raw: [String]) -> Set<AgentKind> {
        Set(raw.compactMap(AgentKind.init(rawValue:)).filter(\.publishesUsage))
    }

    var quotaProblems: [String] {
        var problems: [String] = []
        var seen = Set<String>()
        for quota in quotas {
            let name = quota.id
            if !quota.provider.publishesUsage {
                problems.append("quota \(name) names an agent that reports no usage")
            }
            if quota.window.trimmingCharacters(in: .whitespaces).isEmpty {
                problems.append("a quota for \(quota.provider.rawValue) names no window")
            }
            if let used = quota.used, used < 0 {
                problems.append("quota \(name) uses a negative amount")
            }
            if let used = quota.used, used > 1 {
                problems.append("quota \(name) uses more than the whole limit; used is a fraction, 1 is a limit reached")
            }
            if let hours = quota.hours, hours <= 0 {
                problems.append("quota \(name) lasts no time at all")
            }
            if let minutes = quota.resetsInMinutes, minutes <= 0 {
                problems.append("quota \(name) resets in the past")
            }
            if let minutes = quota.readMinutesAgo, minutes < 0 {
                problems.append("quota \(name) was read in the future")
            }
            if !seen.insert(name).inserted {
                problems.append("quota \(name) is named twice")
            }
        }
        for agent in silentAgents where !agent.publishesUsage {
            problems.append("silent agent \(agent.rawValue) reports no usage")
        }
        for agent in agentsWithoutLimits where !agent.publishesUsage {
            problems.append("agent \(agent.rawValue) without limits reports no usage")
        }
        return problems
    }
}
