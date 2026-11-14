import Foundation

public protocol AgentQuotaAdapter: Sendable {
    static var provider: AgentKind { get }

    static func quotas(from line: JSONValue, at now: Date) -> [AgentQuota]
}

public enum AgentQuotaAdapters {
    public static let all: [any AgentQuotaAdapter.Type] = [
        ClaudeCodeQuotaAdapter.self,
        ClaudeCodeUsageAdapter.self,
        CodexQuotaAdapter.self,
        GrokQuotaAdapter.self,
        AntigravityQuotaAdapter.self,
    ]

    public static func quotas(fromRateLimitEvent data: Data, at now: Date = Date()) -> [AgentQuota] {
        guard let line = JSONValue.parse(data) else { return [] }
        return all.flatMap { $0.quotas(from: line, at: now) }
    }
}

public enum ClaudeCodeQuotaAdapter: AgentQuotaAdapter {
    public static let provider = AgentKind.claudeCode

    public static func quotas(from line: JSONValue, at now: Date) -> [AgentQuota] {
        guard let info = line["rate_limit_info"], let type = info["rateLimitType"]?.stringValue else {
            return []
        }
        let measure: QuotaMeasure = info["utilization"]?.doubleValue.map { .fraction($0) } ?? .unknown
        return [AgentQuota(
            provider: provider,
            window: .named(type),
            measure: measure,
            resetsAt: info["resetsAt"]?.doubleValue.map { Date(timeIntervalSince1970: $0) },
            observedAt: now
        )]
    }
}

public enum CodexQuotaAdapter: AgentQuotaAdapter {
    public static let provider = AgentKind.codex

    public static func quotas(from line: JSONValue, at now: Date) -> [AgentQuota] {
        let codex = line["codex"] ?? line
        let body = codex["params"] ?? codex["result"] ?? codex
        guard let limits = body["rateLimits"] else { return [] }
        return windows(in: limits, keyPrefix: "", nameSuffix: nil, at: now)
            + extraLimits(in: body, besides: limits["limitId"]?.stringValue ?? "codex", at: now)
    }

    static func extraLimits(in body: JSONValue, besides ownID: String, at now: Date) -> [AgentQuota] {
        let extras = body["rateLimitsByLimitId"]?.objectValue ?? [:]
        return extras.keys.sorted().filter { $0 != ownID }.flatMap { limitID -> [AgentQuota] in
            guard let snapshot = extras[limitID], !snapshot.isNull else { return [] }
            let name = snapshot["limitName"]?.stringValue
                .flatMap { $0.split(separator: "-").last.map(String.init) }
                ?? QuotaWindow.humanised(limitID)
            return windows(in: snapshot, keyPrefix: "\(limitID).", nameSuffix: name, at: now)
        }
    }

    static func windows(in limits: JSONValue, keyPrefix: String, nameSuffix: String?, at now: Date) -> [AgentQuota] {
        ["primary", "secondary"].compactMap { slot in
            guard let window = limits[slot] else { return nil }
            let minutes = window["windowDurationMins"]?.doubleValue.flatMap { $0 > 0 ? $0 : nil }
            let measure: QuotaMeasure = window["usedPercent"]?.doubleValue
                .map { .fraction($0 / 100) } ?? .unknown
            var shape = minutes.map { QuotaWindow.lasting($0 * 60, key: keyPrefix + slot) }
                ?? QuotaWindow(key: keyPrefix + slot, label: QuotaWindow.humanised(slot))
            if let nameSuffix { shape.label += " (\(nameSuffix))" }
            return AgentQuota(
                provider: provider,
                window: shape,
                measure: measure,
                resetsAt: window["resetsAt"]?.doubleValue.map { Date(timeIntervalSince1970: $0) },
                observedAt: now
            )
        }
    }
}

public enum ClaudeCodeUsageAdapter: AgentQuotaAdapter {
    public static let provider = AgentKind.claudeCode

    static let windowKeys = [
        "five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet", "seven_day_oauth_apps",
    ]

    public static func carriesLimits(_ data: Data?) -> Bool {
        guard let data, let line = JSONValue.parse(data) else { return false }
        return reported(in: line) != nil
    }

    public static func declinesLimits(_ data: Data?) -> Bool {
        guard let data, let line = JSONValue.parse(data) else { return false }
        return payload(in: line)["rate_limits_available"]?.boolValue == false
    }

    static func payload(in line: JSONValue) -> JSONValue {
        line["response"]?["response"] ?? line
    }

    static func reported(in line: JSONValue) -> (payload: JSONValue, limits: JSONValue)? {
        let payload = payload(in: line)
        guard payload["rate_limits_available"]?.boolValue == true,
              let limits = payload["rate_limits"],
              limits.objectValue?.isEmpty == false
        else { return nil }
        return (payload, limits)
    }

    public static func quotas(from line: JSONValue, at now: Date) -> [AgentQuota] {
        guard let (payload, limits) = reported(in: line) else { return [] }

        let observedAt = payload[ClaudeUsageCache.observedKey]?.doubleValue
            .map { Date(timeIntervalSince1970: $0 / 1000) } ?? now

        let named: [AgentQuota] = windowKeys.compactMap { key in
            guard let window = limits[key] else { return nil }
            let measure: QuotaMeasure = window["utilization"]?.doubleValue
                .map { .fraction($0 / 100) } ?? .unknown
            return AgentQuota(
                provider: provider,
                window: .named(key),
                measure: measure,
                resetsAt: window["resets_at"]?.stringValue.flatMap(Self.date(fromISO:)),
                observedAt: observedAt
            )
        }

        return named + modelScoped(in: limits, at: observedAt) + extraUsage(in: limits, at: observedAt)
    }

    static func modelScoped(in limits: JSONValue, at now: Date) -> [AgentQuota] {
        (limits["model_scoped"]?.arrayValue ?? []).compactMap { entry in
            guard let name = entry["display_name"]?.stringValue, !name.isEmpty else { return nil }
            let measure: QuotaMeasure = entry["utilization"]?.doubleValue
                .map { .fraction($0 / 100) } ?? .unknown
            return AgentQuota(
                provider: provider,
                window: QuotaWindow(
                    key: "seven_day_model_\(slug(name))",
                    label: "Week (\(name))",
                    duration: 604_800
                ),
                measure: measure,
                resetsAt: entry["resets_at"]?.stringValue.flatMap(Self.date(fromISO:)),
                observedAt: now
            )
        }
    }

    static func slug(_ name: String) -> String {
        String(name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }

    static func extraUsage(in limits: JSONValue, at now: Date) -> [AgentQuota] {
        guard let extra = limits["extra_usage"], extra["is_enabled"]?.boolValue == true else {
            return []
        }
        let currency = (extra["currency"]?.stringValue ?? "USD").uppercased()
        let used = extra["used_credits"]?.doubleValue.map { majorUnits($0, currency: currency) }
        let limit = extra["monthly_limit"]?.doubleValue.map { majorUnits($0, currency: currency) }
        return [AgentQuota(
            provider: provider,
            window: QuotaWindow(key: "extra_usage", label: "Extra usage"),
            measure: spend(in: extra, used: used, limit: limit, currency: currency),
            resetsAt: nil,
            observedAt: now
        )]
    }

    static func spend(in extra: JSONValue, used: Double?, limit: Double?, currency: String) -> QuotaMeasure {
        if let used { return .counted(used: used, limit: limit, unit: currency) }
        if let utilization = extra["utilization"]?.doubleValue { return .fraction(utilization / 100) }
        return .unknown
    }

    static let zeroDecimalCurrencies: Set<String> = ["JPY", "KRW", "VND"]

    static func majorUnits(_ minor: Double, currency: String) -> Double {
        zeroDecimalCurrencies.contains(currency) ? minor : minor / 100
    }

    static func date(fromISO text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }
}
