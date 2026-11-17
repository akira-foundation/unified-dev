import Foundation

extension MenuBarPanelContent {
    public static let settledReading: TimeInterval = 180

    public static func silentLine(for provider: AgentKind) -> String {
        "\(provider.label) did not answer."
    }

    public static func lastReportedLine(for provider: AgentKind, since date: Date, from now: Date) -> String {
        "\(provider.label) last reported its limits \(age(since: date, from: now)) ago."
    }

    public static func readingLine(for provider: AgentKind) -> String {
        "Reading \(provider.label) limits\u{2026}"
    }

    public static func noLimitsLine(for provider: AgentKind) -> String {
        "\(provider.label) reports that plan limits do not apply to it."
    }

    public static func sinceLine(since date: Date, from now: Date) -> String {
        "Last reported \(age(since: date, from: now)) ago."
    }

    public static func readLine(age: TimeInterval) -> String {
        "Read \(UsageFormat.compactDuration(age)) ago"
    }

    static func age(since date: Date, from now: Date) -> String {
        UsageFormat.compactDuration(max(0, now.timeIntervalSince(date)))
    }

    static func reason(for provider: AgentKind, in input: Input) -> String {
        let reportedAt = input.lastReported[provider]
        guard !input.unanswered.contains(provider) else {
            return joined(silentLine(for: provider), since: reportedAt, at: input.now)
        }
        guard !input.withoutLimits.contains(provider) else {
            return joined(noLimitsLine(for: provider), since: reportedAt, at: input.now)
        }
        guard let reportedAt else { return unavailableLine(for: provider) }
        return lastReportedLine(for: provider, since: reportedAt, from: input.now)
    }

    static func joined(_ sentence: String, since date: Date?, at now: Date) -> String {
        guard let date else { return sentence }
        return "\(sentence) \(sinceLine(since: date, from: now))"
    }

    static func note(for provider: AgentKind, drawing section: UsageLayout.Section, in input: Input) -> String? {
        let age = ageNote(drawing: section, at: input.now)
        guard input.withoutLimits.contains(provider) else { return age }
        let sentence = noLimitsLine(for: provider)
        guard let age else { return sentence }
        return "\(sentence) \(age)."
    }

    static func ageNote(drawing section: UsageLayout.Section, at now: Date) -> String? {
        guard let readAt = section.visible.compactMap({ $0.quota?.observedAt }).min() else { return nil }
        let age = now.timeIntervalSince(readAt)
        guard age > settledReading else { return nil }
        return readLine(age: age)
    }
}
