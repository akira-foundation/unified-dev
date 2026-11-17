import Foundation

public struct QuotaScope: Sendable, Hashable {
    public var holders: [AgentKind: QuotaHolder]

    public init(holders: [AgentKind: QuotaHolder]) {
        self.holders = holders
    }

    public init(homes: [AgentKind: AgentAccountHome]) {
        self.init(holders: Dictionary(uniqueKeysWithValues: AgentKind.allCases.filter(\.publishesUsage).map {
            ($0, QuotaHolder(provider: $0, home: homes[$0]))
        }))
    }

    public func shows(_ quota: AgentQuota) -> Bool {
        quota.holder.map(holds) ?? false
    }

    public func holds(_ holder: QuotaHolder) -> Bool {
        holders[holder.provider] == holder
    }
}

public struct QuotaReadings: Sendable, Equatable {
    public private(set) var identities: [QuotaHolder: AgentAccount] = [:]
    public private(set) var unanswered: Set<QuotaHolder> = []
    public private(set) var withoutLimits: Set<QuotaHolder> = []
    public private(set) var lastReported: [QuotaHolder: Date] = [:]

    public init() {}

    public mutating func adopt(_ report: QuotaReport) {
        for (provider, holder) in report.holders {
            if let identity = report.accounts.first(where: { $0.provider == provider }) {
                identities[holder] = identity
            }
            mark(&unanswered, holder, report.unanswered.contains(provider))
            mark(&withoutLimits, holder, report.withoutLimits.contains(provider))
            lastReported[holder] = report.lastReported[provider]
        }
    }

    private func mark(_ set: inout Set<QuotaHolder>, _ holder: QuotaHolder, _ isIn: Bool) {
        if isIn { set.insert(holder) } else { set.remove(holder) }
    }
}

public struct QuotaShown: Sendable, Equatable {
    public var quotas: [AgentQuota]
    public var accounts: [AgentKind: AgentAccount]
    public var unanswered: Set<AgentKind>
    public var withoutLimits: Set<AgentKind>
    public var lastReported: [AgentKind: Date]
    public var pending: Set<AgentKind>

    public init(
        quotas: [AgentQuota] = [],
        accounts: [AgentKind: AgentAccount] = [:],
        unanswered: Set<AgentKind> = [],
        withoutLimits: Set<AgentKind> = [],
        lastReported: [AgentKind: Date] = [:],
        pending: Set<AgentKind> = []
    ) {
        self.quotas = quotas
        self.accounts = accounts
        self.unanswered = unanswered
        self.withoutLimits = withoutLimits
        self.lastReported = lastReported
        self.pending = pending
    }

    public static func make(
        stored: [AgentQuota],
        readings: QuotaReadings,
        scope: QuotaScope?,
        reading: Set<QuotaHolder>
    ) -> QuotaShown {
        guard let scope else { return QuotaShown() }
        let quotas = stored.filter(scope.shows)
        let inScope = { (holder: QuotaHolder) in scope.holds(holder) }
        let accounts = Dictionary(
            readings.identities.filter { inScope($0.key) }.map { ($0.key.provider, $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        let drawn = Set(quotas.map(\.provider)).union(accounts.keys)
        let answered = Set(stored.map(\.provider))
            .union(readings.identities.keys.map(\.provider))
            .union(readings.lastReported.keys.map(\.provider))
        return QuotaShown(
            quotas: quotas,
            accounts: accounts,
            unanswered: Set(readings.unanswered.filter(inScope).map(\.provider)),
            withoutLimits: Set(readings.withoutLimits.filter(inScope).map(\.provider)),
            lastReported: Dictionary(
                readings.lastReported.filter { inScope($0.key) }.map { ($0.key.provider, $0.value) },
                uniquingKeysWith: { first, _ in first }
            ),
            pending: Set(reading.filter(inScope).map(\.provider)).intersection(answered).subtracting(drawn)
        )
    }
}
