import Foundation

public enum AgentQuotaSources {
    public static func all(accounts: [AgentKind: AgentAccountHome] = [:]) -> [any AgentQuotaSource] {
        [
            ClaudeCodeQuotaSource(account: accounts[.claudeCode]),
            CodexQuotaSource(account: accounts[.codex]),
            GrokQuotaSource(account: accounts[.grok]),
            AntigravityQuotaSource(account: accounts[.antigravity]),
        ]
    }

    public static func readAll(
        _ sources: [any AgentQuotaSource] = AgentQuotaSources.all(),
        at now: Date = Date()
    ) async -> [AgentQuota] {
        await report(sources, at: now).quotas
    }

    public static func report(
        _ sources: [any AgentQuotaSource] = AgentQuotaSources.all(),
        at now: Date = Date()
    ) async -> QuotaReport {
        await withTaskGroup(of: QuotaReport.self) { group in
            for source in sources {
                group.addTask {
                    let provider = type(of: source).provider
                    let holder = source.holder
                    let standing = await source.standing()
                    var report = QuotaReport(holders: [provider: holder])
                    guard standing.isInstalled else { return report }
                    if let reportedAt = standing.lastReportedAt { report.lastReported[provider] = reportedAt }

                    guard let payload = await source.read() else {
                        report.unanswered = [provider]
                        return report
                    }
                    report.quotas = AgentQuotaAdapters.quotas(fromRateLimitEvent: payload, at: now)
                        .map { $0.held(by: holder) }
                    report.accounts = source.account(from: payload, at: now).map { [$0] } ?? []
                    if ClaudeCodeUsageAdapter.declinesLimits(payload) { report.withoutLimits = [provider] }
                    return report
                }
            }
            return await group.reduce(into: QuotaReport()) { total, next in
                total.quotas += next.quotas
                total.accounts += next.accounts
                total.unanswered += next.unanswered
                total.withoutLimits += next.withoutLimits
                total.lastReported.merge(next.lastReported) { _, later in later }
                total.holders.merge(next.holders) { _, later in later }
            }
        }
    }
}

public struct QuotaReport: Sendable {
    public var quotas: [AgentQuota]
    public var accounts: [AgentAccount]
    public var unanswered: [AgentKind]
    public var withoutLimits: [AgentKind]
    public var lastReported: [AgentKind: Date]
    public var holders: [AgentKind: QuotaHolder]

    public init(
        quotas: [AgentQuota] = [],
        accounts: [AgentAccount] = [],
        unanswered: [AgentKind] = [],
        withoutLimits: [AgentKind] = [],
        lastReported: [AgentKind: Date] = [:],
        holders: [AgentKind: QuotaHolder] = [:]
    ) {
        self.quotas = quotas
        self.accounts = accounts
        self.unanswered = unanswered
        self.withoutLimits = withoutLimits
        self.lastReported = lastReported
        self.holders = holders
    }
}
