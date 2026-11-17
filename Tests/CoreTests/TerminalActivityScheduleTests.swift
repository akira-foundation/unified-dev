import Testing
@testable import Core

@Suite struct TerminalActivityScheduleTests {
    @Test func theForegroundIntervalStaysAtTwoSeconds() {
        #expect(TerminalActivitySchedule.interval(for: .foreground) == .seconds(2))
    }

    @Test func theBackgroundIntervalIsNoShorterThanTenSeconds() {
        #expect(TerminalActivitySchedule.interval(for: .background) >= .seconds(10))
        #expect(TerminalActivitySchedule.runScriptInterval(for: .background) >= .seconds(10))
    }

    @Test func aRunScriptIsWatchedEverySecondInFront() {
        #expect(TerminalActivitySchedule.runScriptInterval(for: .foreground) == .seconds(1))
    }

    @Test func theTickIsShortEnoughToNoticeComingForward() {
        #expect(TerminalActivitySchedule.tick <= TerminalActivitySchedule.runScriptForegroundInterval)
    }

    @Test func aSharedReadingLivesNoLongerThanTheForegroundInterval() {
        #expect(TerminalActivitySchedule.readingMaxAge <= TerminalActivitySchedule.foregroundInterval)
    }

    @Test func workIsDueOnceItsIntervalHasPassed() {
        let start = ContinuousClock.now
        let interval = TerminalActivitySchedule.commandRecordInterval
        #expect(TerminalActivitySchedule.isDue(lastRun: nil, now: start, interval: interval))
        #expect(!TerminalActivitySchedule.isDue(lastRun: start, now: start + .seconds(29), interval: interval))
        #expect(TerminalActivitySchedule.isDue(lastRun: start, now: start + .seconds(30), interval: interval))
    }

    @Test("a minute of one-second ticks runs the loop as often as the attention allows", arguments: [
        (DiffRefreshSchedule.Activity.foreground, 30), (.background, 6),
    ])
    func aMinuteOfTicks(activity: DiffRefreshSchedule.Activity, expected: Int) {
        let start = ContinuousClock.now
        var lastRun: ContinuousClock.Instant?
        var runs = 0
        for second in 0..<60 {
            let now = start + .seconds(second)
            guard TerminalActivitySchedule.isDue(
                lastRun: lastRun, now: now, interval: TerminalActivitySchedule.interval(for: activity)
            ) else { continue }
            lastRun = now
            runs += 1
        }
        #expect(runs == expected)
    }
}
