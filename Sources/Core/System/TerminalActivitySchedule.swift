import Foundation

public enum TerminalActivitySchedule {
    public static let tick: Duration = .seconds(1)

    public static let foregroundInterval: Duration = .seconds(2)

    public static let backgroundInterval: Duration = .seconds(10)

    public static let runScriptForegroundInterval: Duration = .seconds(1)

    public static let readingMaxAge: Duration = .seconds(2)

    public static let commandRecordInterval: Duration = .seconds(30)

    public static func interval(for activity: DiffRefreshSchedule.Activity) -> Duration {
        activity == .foreground ? foregroundInterval : backgroundInterval
    }

    public static func runScriptInterval(for activity: DiffRefreshSchedule.Activity) -> Duration {
        activity == .foreground ? runScriptForegroundInterval : backgroundInterval
    }

    public static func isDue(
        lastRun: ContinuousClock.Instant?, now: ContinuousClock.Instant, interval: Duration
    ) -> Bool {
        guard let lastRun else { return true }
        return now - lastRun >= interval
    }
}
