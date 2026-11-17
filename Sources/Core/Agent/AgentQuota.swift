import Foundation

public struct QuotaWindow: Sendable, Hashable, Codable, Identifiable {
    public var key: String
    public var label: String
    public var duration: TimeInterval?

    public var id: String { key }

    public init(key: String, label: String, duration: TimeInterval? = nil) {
        self.key = key
        self.label = label
        self.duration = duration
    }

    public static func lasting(_ duration: TimeInterval, key: String) -> QuotaWindow {
        QuotaWindow(key: key, label: label(forSeconds: duration), duration: duration)
    }

    public static func named(_ key: String) -> QuotaWindow {
        guard let duration = seconds(fromName: key) else {
            return QuotaWindow(key: key, label: humanised(key), duration: nil)
        }
        let qualifier = words(after: 2, of: key)
        let base = label(forSeconds: duration)
        return QuotaWindow(
            key: key,
            label: qualifier.isEmpty ? base : "\(base) (\(qualifier))",
            duration: duration
        )
    }

    static func words(after count: Int, of key: String) -> String {
        key.lowercased()
            .split(whereSeparator: { $0 == "_" || $0 == "-" })
            .dropFirst(count)
            .joined(separator: " ")
    }

    private static let numerals: [String: Double] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "fourteen": 14, "twenty": 20, "thirty": 30, "sixty": 60,
    ]

    private static let units: [String: TimeInterval] = [
        "minute": 60, "min": 60, "hour": 3600, "day": 86_400, "week": 604_800, "month": 2_592_000,
    ]

    static func seconds(fromName key: String) -> TimeInterval? {
        let parts = key.lowercased().split(whereSeparator: { $0 == "_" || $0 == "-" }).map(String.init)
        guard parts.count >= 2 else { return nil }
        let count = numerals[parts[0]] ?? Double(parts[0])
        let unit = units[parts[1]] ?? units[String(parts[1].dropLast())]
        guard let count, let unit, count > 0 else { return nil }
        return count * unit
    }

    static func label(forSeconds seconds: TimeInterval) -> String {
        let rounded = seconds.rounded()
        switch rounded {
        case 604_800: return "Week"
        case 86_400: return "Day"
        case 2_592_000, 2_678_400: return "Month"
        default: break
        }
        if rounded >= 604_800, rounded.truncatingRemainder(dividingBy: 604_800) == 0 {
            return "\(Int(rounded / 604_800)) weeks"
        }
        if rounded >= 86_400, rounded.truncatingRemainder(dividingBy: 86_400) == 0 {
            let days = Int(rounded / 86_400)
            return days == 1 ? "Day" : "\(days) days"
        }
        if rounded >= 3600 {
            let hours = rounded / 3600
            let whole = Int(hours)
            let text = hours == Double(whole) ? "\(whole)" : String(format: "%.1f", hours)
            return whole == 1 && hours == 1 ? "Hour" : "\(text) hours"
        }
        return "\(Int((rounded / 60).rounded())) min"
    }

    static func humanised(_ key: String) -> String {
        let words = key.split(whereSeparator: { $0 == "_" || $0 == "-" }).map(String.init)
        guard let first = words.first, !first.isEmpty else { return key }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + words.dropFirst())
            .joined(separator: " ")
    }
}

public enum QuotaMeasure: Sendable, Hashable {
    case fraction(Double)
    case counted(used: Double, limit: Double?, unit: String)
    case unknown

    public var fraction: Double? {
        switch self {
        case .fraction(let value): return value
        case .counted(let used, let limit, _):
            guard let limit, limit > 0 else { return nil }
            return used / limit
        case .unknown: return nil
        }
    }

    public var isKnown: Bool {
        if case .unknown = self { return false }
        return true
    }
}

public struct AgentQuota: Sendable, Hashable, Identifiable {
    public var provider: AgentKind
    public var window: QuotaWindow
    public var measure: QuotaMeasure
    public var resetsAt: Date?
    public var observedAt: Date
    public var account: AgentAccountID?

    public var id: String {
        guard let account else { return "\(provider.rawValue)/\(window.key)" }
        return "\(provider.rawValue)/\(account.rawValue)/\(window.key)"
    }

    public var holder: QuotaHolder? {
        account.map { QuotaHolder(provider: provider, account: $0) }
    }

    public func held(by holder: QuotaHolder) -> AgentQuota {
        guard holder.provider == provider else { return self }
        var held = self
        held.account = holder.account
        return held
    }

    public init(
        provider: AgentKind,
        window: QuotaWindow,
        measure: QuotaMeasure,
        resetsAt: Date?,
        observedAt: Date,
        account: AgentAccountID? = nil
    ) {
        self.provider = provider
        self.window = window
        self.measure = measure
        self.resetsAt = resetsAt
        self.observedAt = observedAt
        self.account = account
    }

    public var fraction: Double? { measure.fraction }

    public func hasExpired(at now: Date) -> Bool {
        guard let resetsAt else { return false }
        return resetsAt <= now
    }
}

public enum QuotaSeverity: Int, Sendable, Hashable, Comparable, CaseIterable {
    case calm
    case warning
    case critical
    case spent

    public static func < (lhs: QuotaSeverity, rhs: QuotaSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var word: String? {
        switch self {
        case .calm: nil
        case .warning: "Running low"
        case .critical: "Nearly gone"
        case .spent: "Spent"
        }
    }

    public var symbol: String? {
        switch self {
        case .calm: nil
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        case .spent: "circle.slash.fill"
        }
    }

    public static let warningAt = 0.8
    public static let criticalAt = 0.9

    public static func of(_ fraction: Double?) -> QuotaSeverity {
        guard let fraction else { return .calm }
        if fraction >= 1 { return .spent }
        if fraction >= criticalAt { return .critical }
        if fraction >= warningAt { return .warning }
        return .calm
    }
}

public struct QuotaBoard: Sendable, Hashable {
    public struct Provider: Sendable, Hashable, Identifiable {
        public var kind: AgentKind
        public var quotas: [AgentQuota]
        public var id: String { kind.rawValue }
    }

    public var providers: [Provider]

    public var headline: AgentQuota?

    public init(providers: [Provider], headline: AgentQuota? = nil) {
        self.providers = providers
        self.headline = headline
    }

    public var isEmpty: Bool { providers.isEmpty }

    public var all: [AgentQuota] { providers.flatMap(\.quotas) }

    public var severity: QuotaSeverity { QuotaSeverity.of(headline?.fraction) }

    public static func make(from quotas: [AgentQuota], at now: Date = Date()) -> QuotaBoard {
        let live = quotas.filter { !$0.hasExpired(at: now) }
        let grouped = Dictionary(grouping: live, by: \.provider)
        let providers = AgentKind.allCases.compactMap { kind -> Provider? in
            guard let found = grouped[kind], !found.isEmpty else { return nil }
            return Provider(kind: kind, quotas: found.sorted(by: isShorter))
        }
        let nearest = providers.flatMap(\.quotas)
            .filter { $0.fraction != nil }
            .max { rank($0, at: now) < rank($1, at: now) }
        return QuotaBoard(providers: providers, headline: nearest)
    }

    static func rank(_ quota: AgentQuota, at now: Date) -> (QuotaSeverity, Double, Double) {
        (
            QuotaSeverity.of(quota.fraction),
            QuotaPace.of(quota, at: now)?.overspend ?? 0,
            quota.fraction ?? 0
        )
    }

    public func lines(at now: Date = Date(), locale: Locale = .current) -> [QuotaLine] {
        let forecast = forecastable(at: now)
        return all.map {
            QuotaLine.of($0, at: now, forecasting: $0.id == forecast?.id, locale: locale)
        }
    }

    public func spokenSummary(at now: Date = Date(), locale: Locale = .current) -> String {
        let rows = lines(at: now, locale: locale)
        guard !rows.isEmpty else { return "Agent limits. Nothing has reported one yet." }

        guard let headline, let leader = rows.first(where: { $0.id == headline.id }) else {
            return "Agent limits. \(rows.count) windows, none of them measured."
        }
        if severity == .calm {
            return "Agent limits. Nothing is close to a limit. Nearest is \(leader.spoken)."
        }
        return "Agent limits. \(leader.spoken)."
    }

    func forecastable(at now: Date) -> AgentQuota? {
        all.filter { QuotaPace.of($0, at: now)?.runsOutIn != nil }
            .max { lhs, rhs in
                (QuotaPace.of(lhs, at: now)?.overspend ?? 0)
                    < (QuotaPace.of(rhs, at: now)?.overspend ?? 0)
            }
    }

    private static func isShorter(_ lhs: AgentQuota, _ rhs: AgentQuota) -> Bool {
        switch (lhs.window.duration, rhs.window.duration) {
        case (let left?, let right?): return left == right ? lhs.window.key < rhs.window.key : left < right
        case (nil, _?): return false
        case (_?, nil): return true
        default: return lhs.window.key < rhs.window.key
        }
    }
}
