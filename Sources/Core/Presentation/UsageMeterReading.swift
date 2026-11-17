import Foundation

public enum UsagePace {
    public enum Status: Sendable, Hashable {
        case ahead
        case onTrack
        case behind
    }

    public struct Result: Sendable, Hashable {
        public var status: Status
        public var projectedUsage: Double
    }

    public static func minimumElapsed(period: TimeInterval) -> TimeInterval {
        max(60, period * 0.01)
    }

    public static func evaluate(
        used: Double,
        limit: Double,
        resetsAt: Date,
        period: TimeInterval,
        now: Date
    ) -> Result? {
        guard limit > 0, period > 0, used > 0 else { return nil }
        let elapsed = now.timeIntervalSince(resetsAt.addingTimeInterval(-period))
        guard elapsed >= minimumElapsed(period: period), now < resetsAt else { return nil }

        let projected = used / elapsed * period
        if used >= limit { return Result(status: .behind, projectedUsage: projected) }
        if projected <= limit * 0.9 { return Result(status: .ahead, projectedUsage: projected) }
        if projected <= limit { return Result(status: .onTrack, projectedUsage: projected) }
        return Result(status: .behind, projectedUsage: projected)
    }

    public static func secondsToRunOut(
        used: Double,
        limit: Double,
        resetsAt: Date,
        period: TimeInterval,
        now: Date
    ) -> TimeInterval? {
        guard let result = evaluate(used: used, limit: limit, resetsAt: resetsAt, period: period, now: now),
              result.status == .behind
        else { return nil }
        let rate = result.projectedUsage / period
        guard rate > 0 else { return nil }
        let eta = (limit - used) / rate
        guard eta > 0, eta < resetsAt.timeIntervalSince(now) else { return nil }
        return eta
    }
}

public struct UsageMeterReading: Sendable, Hashable {
    public enum Tone: Sendable, Hashable {
        case normal
        case warning
        case critical
        case empty
    }

    public struct Status: Sendable, Hashable {
        public var text: String?
        public var showsFlame: Bool
        public var tooltip: String?
        public var isDeadline: Bool
        public var deadline: Date?
    }

    public var fill: Double
    public var tone: Tone
    public var headline: String
    public var headlineAlternate: String?
    public var trailing: String
    public var trailingAlternate: String?
    public var trailingTooltip: String?
    public var status: Status?
    public var paceTick: Double?
    public var paceTooltip: String?
    public var menuBarValue: String?

    public static let emptyHeadline = "\u{2014}"
    public static let noData = "No data"
    public static let notStarted = "Not started"
    public static let notStartedTooltip = "Sessions start after you send your first message."
    public static let limitReached = "Limit reached"

    public static func of(
        _ quota: AgentQuota,
        isSession: Bool,
        at now: Date,
        options: UsageDisplayOptions = UsageDisplayOptions()
    ) -> UsageMeterReading {
        let money = moneyUnit(quota)
        let figures = figures(quota)

        if isSession, quota.resetsAt == nil, quota.measure.isKnown, (figures?.used ?? 0) == 0 {
            let limit = figures?.limit ?? 100
            return UsageMeterReading(
                fill: options.meterStyle == .left ? 1 : 0,
                tone: .normal,
                headline: headline(used: 0, limit: limit, money: money, style: options.meterStyle),
                headlineAlternate: headline(used: 0, limit: limit, money: money, style: options.meterStyle.toggled),
                trailing: notStarted,
                trailingTooltip: notStartedTooltip,
                menuBarValue: trayValue(used: 0, limit: limit, money: money, style: options.meterStyle)
            )
        }

        guard let (used, limit) = figures, limit > 0 else {
            return UsageMeterReading(
                fill: 0,
                tone: .empty,
                headline: emptyHeadline,
                trailing: noData
            )
        }

        let shareUsed = min(max(used / limit, 0), 1)
        var reading = UsageMeterReading(
            fill: options.meterStyle == .left ? 1 - shareUsed : shareUsed,
            tone: .normal,
            headline: headline(used: used, limit: limit, money: money, style: options.meterStyle),
            headlineAlternate: headline(used: used, limit: limit, money: money, style: options.meterStyle.toggled),
            trailing: "",
            menuBarValue: trayValue(used: used, limit: limit, money: money, style: options.meterStyle)
        )

        let trailing = trailing(quota, limit: limit, money: money, at: now, options: options)
        reading.trailing = trailing.text
        reading.trailingAlternate = trailing.alternate

        if isSpent(used: used, limit: limit, money: money != nil) {
            reading.tone = .critical
            reading.status = Status(text: limitReached, showsFlame: true, tooltip: nil, isDeadline: false)
            reading.paceTooltip = limitReached
            return reading
        }

        guard let resetsAt = quota.resetsAt, let period = quota.window.duration,
              let pace = UsagePace.evaluate(used: used, limit: limit, resetsAt: resetsAt, period: period, now: now)
        else {
            reading.tone = bandTone(shareUsed: shareUsed)
            return reading
        }

        let projectedShare = pace.projectedUsage / limit
        let elapsed = min(max(1 - resetsAt.timeIntervalSince(now) / period, 0), 1)
        let tick = options.meterStyle == .left ? 1 - elapsed : elapsed
        let trustsProjection = shareUsed >= 0.05

        switch pace.status {
        case .ahead:
            let left = Int(((1 - projectedShare) * 100).rounded())
            reading.tone = .normal
            reading.paceTooltip = "~\(left)% left at reset"
            if options.alwaysShowsPacing {
                reading.status = Status(text: "~\(left)% left at reset", showsFlame: false, tooltip: nil, isDeadline: false)
                reading.paceTick = tick
            }
        case .onTrack where trustsProjection:
            let spare = Int(((1 - projectedShare) * 100).rounded())
            let usedAtReset = Int((projectedShare * 100).rounded())
            reading.paceTick = tick
            reading.paceTooltip = "~\(usedAtReset)% used at reset"
            if spare < 1 {
                reading.tone = .critical
                reading.status = Status(text: nil, showsFlame: true, tooltip: reading.paceTooltip, isDeadline: false)
            } else {
                reading.tone = .warning
                reading.status = Status(
                    text: "~\(spare)% spare", showsFlame: false, tooltip: reading.paceTooltip, isDeadline: false
                )
            }
        case .behind where trustsProjection:
            reading.tone = .critical
            reading.paceTick = tick
            let over = Int(((projectedShare - 1) * 100).rounded())
            reading.paceTooltip = over >= 1 ? "~\(over)% over limit at reset" : "~100% used at reset"
            if let eta = UsagePace.secondsToRunOut(used: used, limit: limit, resetsAt: resetsAt, period: period, now: now) {
                let deadline = now.addingTimeInterval(eta)
                reading.status = Status(
                    text: UsageFormat.deadline(
                        "Limit", at: deadline, from: now, display: options.resetDisplay,
                        clock: options.timeFormat, calendar: options.calendar, locale: options.locale
                    ),
                    showsFlame: true,
                    tooltip: reading.paceTooltip,
                    isDeadline: true,
                    deadline: deadline
                )
            } else {
                reading.status = Status(text: nil, showsFlame: true, tooltip: reading.paceTooltip, isDeadline: false)
            }
        case .onTrack, .behind:
            reading.tone = bandTone(shareUsed: shareUsed)
        }
        return reading
    }

    static func trailing(
        _ quota: AgentQuota,
        limit: Double,
        money: String?,
        at now: Date,
        options: UsageDisplayOptions
    ) -> (text: String, alternate: String?) {
        guard let resetsAt = quota.resetsAt else {
            guard let money else { return ("", nil) }
            return ("\(UsageFormat.trayMoney(limit, code: money)) limit", nil)
        }
        return (
            UsageFormat.deadline(
                "Resets", at: resetsAt, from: now, display: options.resetDisplay,
                clock: options.timeFormat, calendar: options.calendar, locale: options.locale
            ),
            UsageFormat.deadline(
                "Resets", at: resetsAt, from: now, display: options.resetDisplay.toggled,
                clock: options.timeFormat, calendar: options.calendar, locale: options.locale
            )
        )
    }

    static func bandTone(shareUsed: Double) -> Tone {
        let percent = (shareUsed * 100).rounded()
        if percent >= 90 { return .critical }
        if percent >= 80 { return .warning }
        return .normal
    }

    static func figures(_ quota: AgentQuota) -> (used: Double, limit: Double)? {
        switch quota.measure {
        case .fraction(let fraction): return (fraction * 100, 100)
        case .counted(let used, let limit?, _): return (used, limit)
        case .counted, .unknown: return nil
        }
    }

    static func moneyUnit(_ quota: AgentQuota) -> String? {
        if case .counted(_, _, let unit) = quota.measure { return unit }
        return nil
    }

    static func isSpent(used: Double, limit: Double, money: Bool) -> Bool {
        let remaining = max(0, limit - used)
        if money { return (remaining * 100).rounded() == 0 }
        return (remaining / limit * 100).rounded() == 0
    }

    static func headline(used: Double, limit: Double, money: String?, style: UsageMeterStyle) -> String {
        let value = style == .left ? max(0, limit - used) : min(max(used, 0), limit)
        let figure = money.map { UsageFormat.money(value, code: $0) } ?? UsageFormat.percent(value / limit * 100)
        return "\(figure) \(style == .left ? "left" : "used")"
    }

    static func trayValue(used: Double, limit: Double, money: String?, style: UsageMeterStyle) -> String {
        let value = style == .left ? max(0, limit - used) : min(max(used, 0), limit)
        return money.map { UsageFormat.trayMoney(value, code: $0) } ?? UsageFormat.percent(value / limit * 100)
    }

    static func spokenStatus(_ status: Status?) -> String? {
        guard let status else { return nil }
        if let text = status.text { return text }
        return status.showsFlame ? "Running out" : nil
    }

    public func spoken(title: String) -> String {
        var parts = [title, headline == Self.emptyHeadline ? Self.noData : headline]
        if !trailing.isEmpty, trailing != Self.noData { parts.append(trailing) }
        if let word = Self.spokenStatus(status) { parts.append(word) }
        return parts.joined(separator: ", ")
    }
}
