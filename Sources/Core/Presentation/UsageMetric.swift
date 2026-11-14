import Foundation

public struct UsageMetric: Sendable, Hashable, Identifiable {
    public enum Content: Sendable, Hashable {
        case meter(AgentQuota)
        case value(String, tray: String?, tooltip: String?)
    }

    public var id: UsageMetricID
    public var provider: AgentKind
    public var title: String
    public var content: Content
    public var isSession: Bool
    public var headerPhrase: String?

    public init(
        id: UsageMetricID,
        provider: AgentKind,
        title: String,
        content: Content,
        isSession: Bool = false,
        headerPhrase: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.title = title
        self.content = content
        self.isSession = isSession
        self.headerPhrase = headerPhrase
    }

    public var quota: AgentQuota? {
        if case .meter(let quota) = content { return quota }
        return nil
    }
}

public enum UsageCatalogue {
    public static func metrics(
        quotas: [AgentQuota],
        accounts: [AgentKind: AgentAccount],
        at now: Date = Date()
    ) -> [AgentKind: [UsageMetric]] {
        var grouped: [AgentKind: [UsageMetric]] = [:]
        for quota in quotas where !quota.hasExpired(at: now) {
            grouped[quota.provider, default: []].append(metric(for: quota))
        }
        for account in accounts.values {
            grouped[account.provider, default: []] += balances(for: account, at: now)
        }
        for (provider, metrics) in grouped {
            var seen: [UsageMetricID: UsageMetric] = [:]
            for metric in metrics {
                if let existing = seen[metric.id],
                   let old = existing.quota?.observedAt, let new = metric.quota?.observedAt, old >= new {
                    continue
                }
                seen[metric.id] = metric
            }
            grouped[provider] = seen.values.sorted { rank($0) < rank($1) }
        }
        return grouped.filter { !$0.value.isEmpty }
    }

    public static func metric(for quota: AgentQuota) -> UsageMetric {
        let key = key(for: quota)
        let content: UsageMetric.Content
        var headerPhrase: String?
        if case .counted(let used, nil, let unit) = quota.measure {
            let spent = "\(UsageFormat.money(used, code: unit)) spent"
            content = .value(spent, tray: UsageFormat.trayMoney(used, code: unit), tooltip: nil)
            headerPhrase = spent
        } else {
            content = .meter(quota)
        }
        return UsageMetric(
            id: UsageMetricID("\(quota.provider.rawValue)/\(key)"),
            provider: quota.provider,
            title: title(for: quota),
            content: content,
            isSession: kind(of: quota) == .session,
            headerPhrase: headerPhrase
        )
    }

    static func balances(for account: AgentAccount, at now: Date) -> [UsageMetric] {
        var metrics: [UsageMetric] = []
        if let credits = account.credits {
            let text = credits.isUnlimited ? "Unlimited" : "\(UsageFormat.count(credits.balance)) credits"
            metrics.append(UsageMetric(
                id: UsageMetricID("\(account.provider.rawValue)/credits"),
                provider: account.provider,
                title: "Credits",
                content: .value(text, tray: credits.isUnlimited ? nil : UsageFormat.count(credits.balance), tooltip: nil),
                headerPhrase: credits.isUnlimited ? "Unlimited credits" : text
            ))
        }
        if let resets = account.resetCredits {
            let tooltip = resets.expiries.first.map {
                UsageFormat.relative("Soonest expires", until: $0, from: now)
            }
            metrics.append(UsageMetric(
                id: UsageMetricID("\(account.provider.rawValue)/reset_credits"),
                provider: account.provider,
                title: "Rate Limit Resets",
                content: .value("\(resets.available) available", tray: "\(resets.available)", tooltip: tooltip),
                headerPhrase: Counted.of(resets.available, "reset")
            ))
        }
        return metrics
    }

    enum WindowKind: Equatable {
        case session
        case weekly
        case other
    }

    static func kind(of quota: AgentQuota) -> WindowKind {
        switch quota.window.duration?.rounded() {
        case 18_000: return .session
        case 604_800: return .weekly
        case nil:
            let slot = codexSlot(quota)?.slot
            if slot == "primary" { return .session }
            if slot == "secondary" { return .weekly }
            return quota.window.key == "five_hour" ? .session : .other
        default:
            return .other
        }
    }

    public static func key(for quota: AgentQuota) -> String {
        guard quota.provider == .codex else { return quota.window.key }
        let slot = codexSlot(quota)
        let base: String
        switch kind(of: quota) {
        case .session: base = "session"
        case .weekly: base = "weekly"
        case .other: base = slot?.slot ?? quota.window.key
        }
        guard let limit = slot?.limit else { return base }
        return "\(limit).\(base)"
    }

    public static func title(for quota: AgentQuota) -> String {
        let window = quota.window
        switch quota.provider {
        case .claudeCode:
            switch window.key {
            case "five_hour": return "Session"
            case "seven_day": return "Weekly"
            case "seven_day_opus": return "Opus"
            case "seven_day_sonnet": return "Sonnet"
            case "seven_day_oauth_apps": return "OAuth Apps"
            case "extra_usage": return "Extra Usage"
            default:
                if window.key.hasPrefix("seven_day_model_"), let name = parenthesised(window.label) {
                    return name
                }
                return window.label
            }
        case .codex:
            let name = codexSlot(quota)?.limit != nil ? parenthesised(window.label) : nil
            switch kind(of: quota) {
            case .session: return name ?? "Session"
            case .weekly: return name.map { "\($0) Weekly" } ?? "Weekly"
            case .other: return name.map { "\($0) \(window.label)" } ?? window.label
            }
        case .grok, .antigravity, .cursor, .openCode:
            return window.label
        }
    }

    static func codexSlot(_ quota: AgentQuota) -> (limit: String?, slot: String)? {
        guard quota.provider == .codex else { return nil }
        let parts = quota.window.key.split(separator: ".", maxSplits: 1).map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : (nil, parts[0])
    }

    static func parenthesised(_ label: String) -> String? {
        guard let open = label.firstIndex(of: "("), let close = label.lastIndex(of: ")"), open < close else {
            return nil
        }
        let inner = label[label.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
        return inner.isEmpty ? nil : inner
    }

    public static func isOnDemandByDefault(_ id: UsageMetricID) -> Bool {
        let key = keyPart(of: id)
        switch providerPart(of: id) {
        case AgentKind.claudeCode.rawValue:
            return ["seven_day_opus", "seven_day_sonnet", "seven_day_oauth_apps"].contains(key)
        case AgentKind.codex.rawValue:
            return !["session", "weekly"].contains(key)
        default:
            return false
        }
    }

    public static func isPinnedByDefault(_ id: UsageMetricID) -> Bool {
        let key = keyPart(of: id)
        return ["five_hour", "seven_day", "session", "weekly"].contains(key)
    }

    static func rank(_ metric: UsageMetric) -> (Int, String) {
        let key = keyPart(of: metric.id)
        let order: [String]
        switch metric.provider {
        case .claudeCode:
            order = ["five_hour", "seven_day", "seven_day_model_", "extra_usage",
                     "seven_day_sonnet", "seven_day_opus", "seven_day_oauth_apps"]
        default:
            order = ["session", "weekly", ".session", ".weekly", "credits", "reset_credits"]
        }
        let index = order.firstIndex { key == $0 || (($0.hasSuffix("_") || $0.hasPrefix(".")) && matches(key, $0)) }
        return (index ?? order.count, key)
    }

    private static func matches(_ key: String, _ pattern: String) -> Bool {
        pattern.hasPrefix(".") ? key.hasSuffix(pattern) : key.hasPrefix(pattern)
    }

    public static func providerPart(of id: UsageMetricID) -> String {
        String(id.rawValue.split(separator: "/", maxSplits: 1).first ?? "")
    }

    static func keyPart(of id: UsageMetricID) -> String {
        let parts = id.rawValue.split(separator: "/", maxSplits: 1)
        return parts.count == 2 ? String(parts[1]) : id.rawValue
    }
}
