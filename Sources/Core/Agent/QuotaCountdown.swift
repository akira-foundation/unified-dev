import Foundation

public enum QuotaCountdown {
    public static func phrase(until reset: Date, from now: Date = Date()) -> String {
        phrase(after: reset.timeIntervalSince(now))
    }

    public static func rough(after seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "any moment now" }
        if seconds < 3600 { return "in under an hour" }
        if seconds < 86_400 { return "in about \(Int((seconds / 3600).rounded(.down)))h" }
        let days = Int((seconds / 86_400).rounded(.down))
        return days == 1 ? "in about a day" : "in about \(days)d"
    }

    public static func phrase(after seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "any moment now" }
        if seconds < 60 { return "in under a minute" }
        if seconds < 3600 {
            let minutes = Int((seconds / 60).rounded(.down))
            return "in \(minutes) min"
        }
        if seconds < 86_400 {
            let hours = Int((seconds / 3600).rounded(.down))
            let minutes = Int(((seconds - Double(hours) * 3600) / 60).rounded(.down))
            return minutes == 0 ? "in \(hours)h" : "in \(hours)h \(minutes)m"
        }
        let days = Int((seconds / 86_400).rounded(.down))
        let hours = Int(((seconds - Double(days) * 86_400) / 3600).rounded(.down))
        if days >= 3 || hours == 0 { return "in \(days)d" }
        return "in \(days)d \(hours)h"
    }
}
