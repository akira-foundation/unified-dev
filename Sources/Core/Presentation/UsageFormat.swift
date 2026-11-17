import Foundation

public enum UsageFormat {
    public static let longestDuration: TimeInterval = 100 * 365 * 86_400

    public static func compactDuration(_ seconds: TimeInterval) -> String {
        let bounded = seconds.isFinite ? min(seconds, longestDuration) : longestDuration
        let totalMinutes = max(1, Int((bounded / 60).rounded(.up)))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }

    public static let soonThreshold: TimeInterval = 5 * 60

    public static let soonWord = "soon"

    public static func relative(_ prefix: String, until date: Date, from now: Date) -> String {
        let left = countdown(until: date, from: now)
        return left == soonWord ? "\(prefix) \(soonWord)" : "\(prefix) in \(left)"
    }

    public static func countdown(until date: Date, from now: Date) -> String {
        let remaining = date.timeIntervalSince(now)
        return remaining > soonThreshold ? compactDuration(remaining) : soonWord
    }

    public static func absolute(
        _ prefix: String,
        at date: Date,
        from now: Date,
        clock: UsageTimeFormat = .automatic,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        guard date.timeIntervalSince(now) > 0 else { return "\(prefix) soon" }
        let time = timeOfDay(date, clock: clock, calendar: calendar, locale: locale)
        if calendar.isDate(date, inSameDayAs: now) { return "\(prefix) today at \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "\(prefix) tomorrow at \(time)"
        }
        let formatter = formatter(calendar: calendar, locale: locale)
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return "\(prefix) \(formatter.string(from: date)) at \(time)"
    }

    public static func deadline(
        _ prefix: String,
        at date: Date,
        from now: Date,
        display: UsageResetDisplay,
        clock: UsageTimeFormat = .automatic,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        switch display {
        case .countdown: relative(prefix, until: date, from: now)
        case .exactTime: absolute(prefix, at: date, from: now, clock: clock, calendar: calendar, locale: locale)
        }
    }

    static func timeOfDay(
        _ date: Date,
        clock: UsageTimeFormat,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let formatter = formatter(calendar: calendar, locale: locale)
        switch clock {
        case .automatic:
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        case .twelveHour:
            formatter.dateFormat = "h:mm a"
        case .twentyFourHour:
            formatter.dateFormat = "HH:mm"
        }
        return formatter.string(from: date)
    }

    private static func formatter(calendar: Calendar, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        return formatter
    }

    public static func percent(_ value: Double) -> String {
        "\(Int(min(max(value, 0), 100).rounded()))%"
    }

    public static func money(_ amount: Double, code: String = "USD", locale: Locale = Locale(identifier: "en_US")) -> String {
        if abs(amount) >= 1000 { return compactMoney(amount, code: code, locale: locale) }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = code.uppercased()
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }

    public static func trayMoney(_ amount: Double, code: String = "USD", locale: Locale = Locale(identifier: "en_US")) -> String {
        if abs(amount) >= 1000 { return compactMoney(amount, code: code, locale: locale) }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = code.uppercased()
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount.rounded())) ?? "\(Int(amount.rounded()))"
    }

    static func compactMoney(_ amount: Double, code: String, locale: Locale) -> String {
        let symbol = currencySymbol(code: code, locale: locale)
        let compact = amount.formatted(
            .number.notation(.compactName).precision(.fractionLength(0...1)).locale(locale)
        )
        return symbol + compact
    }

    static func currencySymbol(code: String, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = code.uppercased()
        return formatter.currencySymbol ?? code.uppercased()
    }

    public static func count(_ value: Double, locale: Locale = Locale(identifier: "en_US")) -> String {
        if abs(value) >= 1000 {
            return value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(locale))
        }
        return value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    }
}
