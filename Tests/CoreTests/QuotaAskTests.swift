import Testing
import Foundation
@testable import Core

private let now = Date(timeIntervalSince1970: 1_787_500_000)

private func quota(
    _ provider: AgentKind = .codex,
    _ window: QuotaWindow,
    _ measure: QuotaMeasure,
    resetsAt: Date? = nil,
    observedAt: Date = now
) -> AgentQuota {
    AgentQuota(
        provider: provider,
        window: window,
        measure: measure,
        resetsAt: resetsAt,
        observedAt: observedAt
    )
}

@Suite("Quota merge")
struct QuotaMergeTests {
    private let week = QuotaWindow.lasting(604_800, key: "primary")
    private let reset = Date(timeIntervalSince1970: 1_787_986_128)

    @Test func keepsAResetTimeADeltaDidNotRestate() {
        let known = quota(.codex, week, .fraction(0.06), resetsAt: reset)
        let delta = quota(.codex, week, .fraction(0.11), resetsAt: nil, observedAt: now + 60)

        let merged = QuotaMerge.resolve(delta, against: known)

        #expect(merged.resetsAt == reset)
        #expect(merged.fraction == 0.11)
    }

    @Test func putsBackALengthADeltaDidNotRestate() {
        let known = quota(.codex, week, .fraction(0.06), resetsAt: reset)
        let bare = quota(
            .codex,
            QuotaWindow(key: "primary", label: "Primary"),
            .fraction(0.42),
            resetsAt: reset,
            observedAt: now + 60
        )

        let merged = QuotaMerge.resolve(bare, against: known)

        #expect(merged.window.duration == 604_800)
        #expect(merged.window.label == "Week")
        #expect(merged.fraction == 0.42)
    }

    @Test func keepsAFigureAReportDidNotRestate() {
        let known = quota(.claudeCode, .named("five_hour"), .fraction(0.77), resetsAt: reset)
        let silent = quota(
            .claudeCode,
            .named("five_hour"),
            .unknown,
            resetsAt: reset,
            observedAt: now + 60
        )

        #expect(QuotaMerge.resolve(silent, against: known).fraction == 0.77)
    }

    @Test func keepsAFigureWhenTheStreamRestatesTheResetInWholeSeconds() throws {
        let polled = """
        {"rate_limits_available":true,"rate_limits":{"seven_day":\
        {"utilization":37,"resets_at":"2026-08-28T03:00:00.415023+00:00"}}}
        """
        let streamed = """
        {"type":"rate_limit_event","rate_limit_info":{"status":"allowed",\
        "resetsAt":1787886000,"rateLimitType":"seven_day"}}
        """
        let known = AgentQuotaAdapters.quotas(fromRateLimitEvent: Data(polled.utf8), at: now)
        let reported = AgentQuotaAdapters.quotas(fromRateLimitEvent: Data(streamed.utf8), at: now + 60)

        let merged = try #require(QuotaMerge.resolved(reported, against: known).first)

        #expect(merged.fraction == 0.37)
    }

    @Test(arguments: [(0.415, true), (60, true), (61, false), (-61, false)])
    func treatsAResetWithinAMinuteAsTheSameWindow(shift: TimeInterval, keeps: Bool) {
        let known = quota(.claudeCode, .named("seven_day"), .fraction(0.37), resetsAt: reset)
        let silent = quota(.claudeCode, .named("seven_day"), .unknown, resetsAt: reset + shift, observedAt: now + 60)

        let merged = QuotaMerge.resolve(silent, against: known)

        #expect(merged.fraction == (keeps ? 0.37 : nil))
        #expect(merged.resetsAt == reset + shift)
    }

    @Test func putsBackALengthWhenTheResetMovedBySubseconds() {
        let known = quota(.codex, week, .fraction(0.06), resetsAt: reset + 0.415)
        let bare = quota(
            .codex,
            QuotaWindow(key: "primary", label: "Primary"),
            .fraction(0.42),
            resetsAt: reset,
            observedAt: now + 60
        )

        #expect(QuotaMerge.resolve(bare, against: known).window.duration == 604_800)
    }

    @Test func carriesNothingAcrossAWindowThatTurnedOver() {
        let known = quota(.codex, week, .fraction(0.94), resetsAt: reset)
        let after = quota(
            .codex,
            QuotaWindow(key: "primary", label: "Primary"),
            .unknown,
            resetsAt: reset + 604_800,
            observedAt: now + 60
        )

        let merged = QuotaMerge.resolve(after, against: known)

        #expect(merged.fraction == nil)
        #expect(merged.window.duration == nil)
        #expect(merged.resetsAt == reset + 604_800)
    }

    @Test func dropsAReportOlderThanWhatIsOnFile() {
        let known = quota(.codex, week, .fraction(0.5), resetsAt: reset)
        let stale = quota(.codex, week, .fraction(0.1), resetsAt: reset, observedAt: now - 300)

        #expect(QuotaMerge.resolve(stale, against: known).fraction == 0.5)
    }

    @Test func takesAWindowNobodyHasSeenAsItStands() {
        let fresh = quota(.codex, week, .fraction(0.2), resetsAt: reset)
        #expect(QuotaMerge.resolve(fresh, against: nil) == fresh)
    }

    @Test func keepsRowsNobodyMentionedOutOfTheWrite() {
        let claude = quota(.claudeCode, .named("five_hour"), .fraction(0.3), resetsAt: reset)
        let codex = quota(.codex, week, .fraction(0.06), resetsAt: reset)
        let report = [quota(.codex, week, .fraction(0.09), resetsAt: reset, observedAt: now + 60)]

        #expect(QuotaMerge.merged([claude, codex], with: report).count == 2)
        let written = QuotaMerge.resolved(report, against: [claude, codex])
        #expect(written.count == 1)
        #expect(written[0].provider == .codex)
    }
}

@Suite("Quota poll schedule")
struct QuotaPollScheduleTests {
    @Test func asksWhenItNeverHas() {
        #expect(QuotaPollSchedule.isDue(lastAskedAt: nil, at: now, after: QuotaPollSchedule.interval))
    }

    @Test func declinesUntilTheGapHasPassed() {
        let last = now - 10
        #expect(!QuotaPollSchedule.isDue(lastAskedAt: last, at: now, after: QuotaPollSchedule.onDemandFloor))
        #expect(QuotaPollSchedule.isDue(lastAskedAt: now - 300, at: now, after: QuotaPollSchedule.onDemandFloor))
        #expect(!QuotaPollSchedule.isDue(lastAskedAt: now - 30, at: now, after: QuotaPollSchedule.interval))
    }

    @Test func letsTheMenuAskSoonerThanTheBackgroundPoll() {
        #expect(QuotaPollSchedule.onDemandFloor < QuotaPollSchedule.interval)
        #expect(QuotaPollSchedule.onDemandFloor > 0)
    }

    @Test func asksEveryMinuteWhileTheAppIsInFront() {
        #expect(QuotaPollSchedule.gap(for: .foreground, isPanelOpen: false) == 60)
    }

    @Test func asksEveryMinuteWhileThePanelIsOpenWithTheAppBehind() {
        #expect(QuotaPollSchedule.gap(for: .background, isPanelOpen: true) == 60)
    }

    @Test func asksNoMoreThanEveryFiveMinutesInTheBackground() {
        #expect(QuotaPollSchedule.gap(for: .background, isPanelOpen: false) >= 300)
    }

    @Test("an hour of ticks asks as often as the attention allows", arguments: [
        (DiffRefreshSchedule.Activity.background, false, 12), (.foreground, false, 60), (.background, true, 60),
    ])
    func anHourOfTicks(activity: DiffRefreshSchedule.Activity, isPanelOpen: Bool, expected: Int) {
        let gap = QuotaPollSchedule.gap(for: activity, isPanelOpen: isPanelOpen)
        var lastAskedAt: Date?
        var asks = 0
        for second in stride(from: 0, to: 3_600, by: QuotaPollSchedule.tick) {
            let at = now + second
            guard QuotaPollSchedule.isDue(lastAskedAt: lastAskedAt, at: at, after: gap) else { continue }
            lastAskedAt = at
            asks += 1
        }
        #expect(asks == expected)
    }

    @Test func comingForwardAsksAtOnceWhenTheBackgroundAnswerIsOlderThanAMinute() {
        let backgroundAsk = now - 90
        #expect(!QuotaPollSchedule.isDue(
            lastAskedAt: backgroundAsk, at: now,
            after: QuotaPollSchedule.gap(for: .background, isPanelOpen: false)
        ))
        #expect(QuotaPollSchedule.isDue(
            lastAskedAt: backgroundAsk, at: now,
            after: QuotaPollSchedule.gap(for: .foreground, isPanelOpen: false)
        ))
    }

    @Test func theTickNeverOutrunsTheOnDemandFloor() {
        #expect(QuotaPollSchedule.tick <= QuotaPollSchedule.onDemandFloor)
    }

    @Test func staysWellInsideTheShortestWindowEitherProviderPublishes() {
        #expect(QuotaPollSchedule.interval / 18_000 < 0.05)
    }
}

@Suite("Quota sources")
struct QuotaSourceTests {
    @Test func writesTheControlRequestClaudeCodeAnswers() {
        let line = ClaudeCodeQuotaSource.request(id: "unifieddev-usage-1")
        let json = JSONValue.parse(line)

        #expect(json?["type"]?.stringValue == "control_request")
        #expect(json?["request_id"]?.stringValue == "unifieddev-usage-1")
        #expect(json?["request"]?["subtype"]?.stringValue == "get_usage")
        #expect(!line.contains("\n"))
    }

    private static let answer = """
    {"type":"control_response","response":{"subtype":"success","request_id":"u1","response":\
    {"session":{"total_cost_usd":0,"total_api_duration_ms":0,"total_duration_ms":326,\
    "total_lines_added":0,"total_lines_removed":0,"model_usage":{}},"subscription_type":null,\
    "rate_limits_available":false,"rate_limits":null,"behaviors":null}}}
    """

    @Test func readsTheAnswerToItsOwnRequestAndNobodyElses() {
        #expect(ClaudeCodeQuotaSource.answer(in: Self.answer, to: "u1") != nil)
        #expect(ClaudeCodeQuotaSource.answer(in: Self.answer, to: "u2") == nil)
        #expect(ClaudeCodeQuotaSource.answer(in: "not json at all", to: "u1") == nil)
    }

    @Test func asksSomethingThatCostsNothing() throws {
        let payload = try #require(ClaudeCodeQuotaSource.answer(in: Self.answer, to: "u1"))
        let json = try #require(JSONValue.parse(payload))

        #expect(json["session"]?["total_cost_usd"]?.doubleValue == 0)
        #expect(json["session"]?["total_api_duration_ms"]?.doubleValue == 0)
    }

    @Test func spawnsTheSmallestInvocationTheCLIAccepts() {
        #expect(ClaudeCodeQuotaSource.arguments.contains("--verbose"))
        #expect(ClaudeCodeQuotaSource.arguments.contains("--input-format"))
        #expect(!ClaudeCodeQuotaSource.arguments.contains("--model"))
        #expect(!ClaudeCodeQuotaSource.arguments.contains("--settings"))
        #expect(!ClaudeCodeQuotaSource.arguments.contains("--permission-prompt-tool"))
    }

    @Test func asksCodexOnItsStableSurface() {
        #expect(CodexQuotaSource.method == "account/rateLimits/read")
    }
}

@Suite("Requested quota payloads")
struct RequestedQuotaPayloadTests {
    private static let usage = """
    {"session":{"total_cost_usd":0,"total_api_duration_ms":0,"total_duration_ms":326,\
    "total_lines_added":0,"total_lines_removed":0,"model_usage":{}},"subscription_type":"max",\
    "rate_limits_available":true,"rate_limits":{\
    "five_hour":{"utilization":42,"resets_at":"2026-08-24T02:30:00Z"},\
    "seven_day":{"utilization":77.5,"resets_at":"2026-08-27T09:00:00Z"},\
    "seven_day_opus":{"utilization":null,"resets_at":"2026-08-27T09:00:00Z"},\
    "seven_day_sonnet":{"utilization":3,"resets_at":"2026-08-27T09:00:00Z"},\
    "extra_usage":{"is_enabled":false,"monthly_limit":null,"used_credits":null,"utilization":null}},\
    "behaviors":null}
    """

    @Test func readsEveryWindowClaudeCodeAnswersWith() throws {
        let quotas = AgentQuotaAdapters.quotas(fromRateLimitEvent: Data(Self.usage.utf8), at: now)
        let byKey = Dictionary(quotas.map { ($0.window.key, $0) }, uniquingKeysWith: { first, _ in first })

        #expect(quotas.count == 4)
        #expect(quotas.allSatisfy { $0.provider == .claudeCode })
        #expect(byKey["five_hour"]?.fraction == 0.42)
        #expect(byKey["seven_day"]?.fraction == 0.775)
        #expect(byKey["five_hour"]?.resetsAt == ISO8601DateFormatter().date(from: "2026-08-24T02:30:00Z"))
    }

    @Test func keepsAWindowNobodyMeasuredAsUnmeasured() throws {
        let quotas = AgentQuotaAdapters.quotas(fromRateLimitEvent: Data(Self.usage.utf8), at: now)
        let opus = try #require(quotas.first { $0.window.key == "seven_day_opus" })

        #expect(opus.measure == .unknown)
        #expect(opus.fraction == nil)
        #expect(opus.window.duration == 604_800)
        #expect(opus.window.label == "Week (opus)")
    }

    private static let maxAccount = """
    {"session":{"total_cost_usd":0},"subscription_type":"max","rate_limits_available":true,    "rate_limits":{    "five_hour":{"utilization":4,"resets_at":"2026-08-24T10:20:00.415000+00:00"},    "seven_day":{"utilization":60,"resets_at":"2026-08-28T03:00:00.415023+00:00"},    "seven_day_oauth_apps":null,"seven_day_opus":null,"seven_day_sonnet":null,    "extra_usage":{"is_enabled":false,"monthly_limit":null,"used_credits":null,    "utilization":null,"currency":null},    "model_scoped":[{"display_name":"Fable","utilization":71,    "resets_at":"2026-08-28T03:00:00.415206+00:00"}]}}
    """

    @Test func readsTheModelScopedWeeklyThatWasBeingThrownAway() throws {
        let quotas = AgentQuotaAdapters.quotas(fromRateLimitEvent: Data(Self.maxAccount.utf8), at: now)
        let byKey = Dictionary(quotas.map { ($0.window.key, $0) }, uniquingKeysWith: { first, _ in first })

        #expect(quotas.count == 3)
        #expect(byKey["seven_day"]?.fraction == 0.6)
        #expect(byKey["seven_day_model_fable"]?.fraction == 0.71)
        #expect(byKey["seven_day_model_fable"]?.window.duration == 604_800)
        #expect(byKey["seven_day_model_fable"]?.window.label == "Week (Fable)")
    }

    @Test func producesNoRowForAWindowThePlanDoesNotHave() {
        let quotas = AgentQuotaAdapters.quotas(fromRateLimitEvent: Data(Self.maxAccount.utf8), at: now)
        #expect(!quotas.contains { $0.window.key.contains("opus") })
        #expect(!quotas.contains { $0.window.key.contains("oauth") })
    }

    @Test func showsNoExtraUsageRowUntilTheAccountHasItSwitchedOn() {
        let quotas = AgentQuotaAdapters.quotas(fromRateLimitEvent: Data(Self.maxAccount.utf8), at: now)
        #expect(!quotas.contains { $0.window.key == "extra_usage" })
    }

    @Test func readsExtraUsageAsMoneyOnceItIsSwitchedOn() throws {
        let enabled = """
        {"rate_limits_available":true,"rate_limits":{\
        "extra_usage":{"is_enabled":true,"monthly_limit":5000,"used_credits":1720,\
        "utilization":34.4,"currency":"USD"}}}
        """
        let quotas = AgentQuotaAdapters.quotas(fromRateLimitEvent: Data(enabled.utf8), at: now)
        let extra = try #require(quotas.first { $0.window.key == "extra_usage" })

        #expect(extra.measure == .counted(used: 17.2, limit: 50, unit: "USD"))
        #expect(extra.fraction == 0.344)
        #expect(extra.resetsAt == nil)
        #expect(extra.window.duration == nil)
    }

    @Test func readsExtraUsageInPenceAsPounds() throws {
        let enabled = """
        {"rate_limits_available":true,"rate_limits":{\
        "extra_usage":{"is_enabled":true,"monthly_limit":2000,"used_credits":1856,\
        "utilization":92.8,"currency":"gbp"}}}
        """
        let quotas = AgentQuotaAdapters.quotas(fromRateLimitEvent: Data(enabled.utf8), at: now)
        let extra = try #require(quotas.first { $0.window.key == "extra_usage" })

        #expect(extra.measure == .counted(used: 18.56, limit: 20, unit: "GBP"))
    }

    @Test func leavesAZeroDecimalCurrencyUndivided() throws {
        let enabled = """
        {"rate_limits_available":true,"rate_limits":{\
        "extra_usage":{"is_enabled":true,"monthly_limit":3000,"used_credits":1200,\
        "utilization":40,"currency":"JPY"}}}
        """
        let quotas = AgentQuotaAdapters.quotas(fromRateLimitEvent: Data(enabled.utf8), at: now)
        let extra = try #require(quotas.first { $0.window.key == "extra_usage" })

        #expect(extra.measure == .counted(used: 1200, limit: 3000, unit: "JPY"))
    }

    @Test func makesOneStableKeyOutOfAModelsDisplayName() {
        #expect(ClaudeCodeUsageAdapter.slug("Claude Opus 4.5") == "claude_opus_4_5")
        #expect(ClaudeCodeUsageAdapter.slug("Fable") == "fable")
    }

    @Test func writesNothingForAnAccountWithNoPlanLimits() {
        let none = """
        {"session":{"total_cost_usd":0},"subscription_type":null,\
        "rate_limits_available":false,"rate_limits":null,"behaviors":null}
        """
        #expect(AgentQuotaAdapters.quotas(fromRateLimitEvent: Data(none.utf8), at: now).isEmpty)
    }

    @Test func readsCodexsFullSnapshot() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/codex-rate-limits-read.json")
        let data = try Data(contentsOf: url)
        let result = try #require(JSONValue.parse(data)?["result"])
        let payload = try JSONEncoder().encode(result)

        let quotas = AgentQuotaAdapters.quotas(fromRateLimitEvent: payload, at: now)

        #expect(quotas.count == 3)
        let own = try #require(quotas.first { $0.window.key == "primary" })
        #expect(own.provider == .codex)
        #expect(own.window.duration == 604_800)
        #expect(own.fraction == 0)
        #expect(own.resetsAt == Date(timeIntervalSince1970: 1_787_986_128))

        let spark = try #require(quotas.first { $0.window.key == "codex_bengalfox.primary" })
        #expect(spark.window.duration == 18_000)
        #expect(spark.window.label == "5 hours (Spark)")
        #expect(quotas.contains { $0.window.key == "codex_bengalfox.secondary" })
    }

    @Test func readsARollingUpdateCarryingNothingButAPercentage() throws {
        let delta = """
        {"rateLimits":{"limitId":"codex","primary":{"usedPercent":37},"secondary":null}}
        """
        let quotas = AgentQuotaAdapters.quotas(fromRateLimitEvent: Data(delta.utf8), at: now)

        #expect(quotas.count == 1)
        #expect(quotas[0].fraction == 0.37)
        #expect(quotas[0].window.duration == nil)
        #expect(quotas[0].resetsAt == nil)
    }

    @Test func mergesARollingUpdateOntoTheSnapshotBeforeIt() throws {
        let snapshot = """
        {"rateLimits":{"primary":{"usedPercent":6,"windowDurationMins":10080,"resetsAt":1787986128}}}
        """
        let delta = """
        {"rateLimits":{"primary":{"usedPercent":37}}}
        """
        let known = AgentQuotaAdapters.quotas(fromRateLimitEvent: Data(snapshot.utf8), at: now)
        let reported = AgentQuotaAdapters.quotas(fromRateLimitEvent: Data(delta.utf8), at: now + 300)

        let merged = try #require(QuotaMerge.resolved(reported, against: known).first)

        #expect(merged.fraction == 0.37)
        #expect(merged.window.duration == 604_800)
        #expect(merged.window.label == "Week")
        #expect(merged.resetsAt == Date(timeIntervalSince1970: 1_787_986_128))
    }
}
