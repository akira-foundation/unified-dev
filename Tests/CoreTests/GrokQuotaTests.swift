import Testing
import Foundation
@testable import Core

@Suite("Grok quota")
struct GrokQuotaTests {
    private static let now = Date(timeIntervalSince1970: 1_793_790_000)

    private static let billing = """
    {"config":{"creditUsagePercent":100.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY",\
    "start":"2026-11-01T13:01:35.239+00:00","end":"2026-11-08T13:01:35.239+00:00"},\
    "prepaidBalance":{"val":0},"isUnifiedBillingUser":true,\
    "billingPeriodStart":"2026-11-01T13:01:35.239+00:00","billingPeriodEnd":"2026-11-08T13:01:35.239+00:00"},\
    "subscription_tier":"SuperGrok Lite"}
    """

    private static func reading(_ text: String = billing) -> [AgentQuota] {
        AgentQuotaAdapters.quotas(fromRateLimitEvent: Data(text.utf8), at: now)
    }

    @Test("the billing answer reads as one weekly window, spent, resetting when the period ends")
    func readsTheWeeklyPeriod() throws {
        let quota = try #require(Self.reading().first)
        let end = try #require(ClaudeCodeUsageAdapter.date(fromISO: "2026-11-08T13:01:35.239+00:00"))

        #expect(Self.reading().count == 1)
        #expect(quota.provider == .grok)
        #expect(quota.window.key == "weekly")
        #expect(quota.window.label == "Weekly")
        #expect(quota.window.duration == 604_800)
        #expect(quota.fraction == 1)
        #expect(quota.resetsAt == end)
        #expect(UsageCatalogue.kind(of: quota) == .weekly)
    }

    @Test("a part spent is a fraction of the whole")
    func readsAPartialSpend() throws {
        let partial = Self.billing.replacingOccurrences(of: "100.0", with: "37.5")
        #expect(try #require(Self.reading(partial).first).fraction == 0.375)
    }

    @Test("a period with no type is named after its length")
    func namesAnUntypedPeriodByItsLength() throws {
        let untyped = Self.billing.replacingOccurrences(of: #""type":"USAGE_PERIOD_TYPE_WEEKLY","#, with: "")
        let quota = try #require(Self.reading(untyped).first)

        #expect(quota.window.key == "credits")
        #expect(quota.window.label == "Week")
    }

    @Test("an answer with no usage figure is not a Grok reading")
    func ignoresAnAnswerWithoutAFigure() {
        #expect(Self.reading(#"{"config":{"prepaidBalance":{"val":0}}}"#).isEmpty)
        #expect(Self.reading(#"{"rateLimits":{"primary":{"usedPercent":4}}}"#).allSatisfy { $0.provider != .grok })
    }

    @Test("the subscription tier is the plan")
    func readsThePlan() {
        let account = GrokQuotaSource().account(from: Data(Self.billing.utf8), at: Self.now)

        #expect(account?.provider == .grok)
        #expect(account?.plan == "SuperGrok Lite")
    }

    @Test("Grok now counts as an agent that reports usage")
    func publishesUsage() {
        #expect(AgentKind.grok.publishesUsage)
        #expect(UsageLayout.defaultProviderOrder.contains(.grok))
    }

    @Test("the source asks Grok's billing extension and hands back what it answers", .timeLimit(.minutes(1)))
    func asksTheBillingExtension() async throws {
        let box = ProcessBox()
        let answer = try #require(JSONValue.parse(Data(Self.billing.utf8)))
        box.reply(to: GrokQuotaSource.method, with: answer)
        let source = GrokQuotaSource(environment: [:], makeProcess: box.factory, loginShellReady: {})

        let payload = try #require(await source.read())

        #expect(GrokQuotaSource.method == "_x.ai/billing")
        #expect(box.process.sentMethods.contains("_x.ai/billing"))
        #expect(box.process.launch.arguments.suffix(2) == ["--no-leader", "stdio"])
        #expect(AgentQuotaAdapters.quotas(fromRateLimitEvent: payload, at: Self.now).first?.fraction == 1)
    }

    @Test("the source asks under the account it was handed", .timeLimit(.minutes(1)))
    func asksUnderTheChosenAccount() async throws {
        let box = ProcessBox()
        let account = LaunchAccountFixture.workGrok
        let source = GrokQuotaSource(
            environment: LaunchAccountFixture.inherited, account: account, makeProcess: box.factory, loginShellReady: {}
        )

        _ = await source.read()

        #expect(box.process.launch.environment["GROK_HOME"] == account.directory.path)
    }

    @Test("the quota sources ask Grok under its own account")
    func registersGrokUnderItsAccount() throws {
        let sources = AgentQuotaSources.all(accounts: [
            .grok: LaunchAccountFixture.workGrok, .codex: LaunchAccountFixture.workCodex,
        ])
        let grok = try #require(sources.compactMap { $0 as? GrokQuotaSource }.first)
        #expect(grok.account == LaunchAccountFixture.workGrok)
    }

    @Test("a Grok that does not know the billing request reports nothing rather than failing", .timeLimit(.minutes(1)))
    func aCLIWithoutBillingReportsNothing() async throws {
        let box = ProcessBox()
        box.fail(GrokQuotaSource.method, code: -32601, message: "Method not found")
        let source = GrokQuotaSource(environment: [:], makeProcess: box.factory, loginShellReady: {})

        let payload = try #require(await source.read())

        #expect(AgentQuotaAdapters.quotas(fromRateLimitEvent: payload, at: Self.now).isEmpty)
        #expect(source.account(from: payload, at: Self.now) == nil)
    }

    @Test("any other refusal leaves Grok unanswered", .timeLimit(.minutes(1)))
    func anotherRefusalIsUnanswered() async {
        let box = ProcessBox()
        box.fail(GrokQuotaSource.method, code: -32000, message: "Not signed in")
        let source = GrokQuotaSource(environment: [:], makeProcess: box.factory, loginShellReady: {})

        #expect(await source.read() == nil)
    }

    @Test("a Grok that never answers is given up on within the quota timeout", .timeLimit(.minutes(1)))
    func aSilentGrokIsGivenUpOn() async {
        let box = ProcessBox()
        box.ignore(GrokQuotaSource.method)
        let watchdogs = WatchdogGates()
        let source = GrokQuotaSource(
            environment: [:], timeout: .milliseconds(200), makeProcess: box.factory,
            watchdogSleep: watchdogs.sleep, loginShellReady: {}
        )

        let reading = Task { await source.read() }
        await watchdogs.expireTheOneLeft(afterAsking: 2)

        #expect(await reading.value == nil)
        #expect(watchdogs.asked == [.milliseconds(200), .milliseconds(200)])
        #expect(GrokQuotaSource.timeout < ACPClient.requestTimeout)
    }

    @Test("a Grok that never finishes the handshake is given up on too", .timeLimit(.minutes(1)))
    func aSilentHandshakeIsGivenUpOn() async {
        let box = ProcessBox()
        box.ignore("initialize")
        let watchdogs = WatchdogGates()
        let source = GrokQuotaSource(
            environment: [:], timeout: .milliseconds(200), makeProcess: box.factory,
            watchdogSleep: watchdogs.sleep, loginShellReady: {}
        )

        let reading = Task { await source.read() }
        await watchdogs.expireTheOneLeft(afterAsking: 1)

        #expect(await reading.value == nil)
        #expect(watchdogs.asked == [.milliseconds(200)])
    }

    @Test("a handshake refused as unknown is a failure, not a CLI without billing", .timeLimit(.minutes(1)))
    func aRefusedHandshakeIsUnanswered() async {
        let box = ProcessBox()
        box.fail("initialize", code: -32601, message: "Method not found")
        let source = GrokQuotaSource(environment: [:], makeProcess: box.factory, loginShellReady: {})

        #expect(await source.read() == nil)
    }

    @Test("the process is stopped once the source has its answer", .timeLimit(.minutes(1)))
    func stopsTheProcessAfterReading() async throws {
        let box = ProcessBox()
        let source = GrokQuotaSource(environment: [:], makeProcess: box.factory, loginShellReady: {})

        _ = await source.read()

        for _ in 0..<100 where box.process.isRunning {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!box.process.isRunning)
    }

    @Test("a preview with no Grok account of its own never asks under the owner's login")
    func aPreviewDoesNotReadTheOwnersLogin() async {
        let preview = "io.akira.unifieddev.dev.gulf-of-gonave"
        let own = await GrokQuotaSource(executable: "sh", bundleIdentifier: preview).standing()
        let chosen = await GrokQuotaSource(
            executable: "sh", account: LaunchAccountFixture.workGrok, bundleIdentifier: preview
        ).standing()
        let installed = await GrokQuotaSource(executable: "sh", bundleIdentifier: "io.akira.unifieddev").standing()

        #expect(!own.isInstalled)
        #expect(chosen.isInstalled)
        #expect(installed.isInstalled)
    }

    @Test("the period falls back to the billing period when no current period is named")
    func fallsBackToTheBillingPeriod() throws {
        let text = """
        {"config":{"creditUsagePercent":12,\
        "billingPeriodStart":"2026-11-01T13:01:35.239+00:00","billingPeriodEnd":"2026-11-08T13:01:35.239+00:00"}}
        """
        let quota = try #require(Self.reading(text).first)
        let end = try #require(ClaudeCodeUsageAdapter.date(fromISO: "2026-11-08T13:01:35.239+00:00"))

        #expect(quota.resetsAt == end)
        #expect(quota.window.duration == 604_800)
        #expect(quota.window.label == "Week")
    }

    @Test("a period with no type and no usable length is plain credits")
    func namesAPeriodWithNoLength() throws {
        let backwards = """
        {"config":{"creditUsagePercent":12,"currentPeriod":\
        {"start":"2026-11-08T13:01:35Z","end":"2026-11-08T13:01:35Z"}}}
        """
        let quota = try #require(Self.reading(backwards).first)

        #expect(quota.window.key == "credits")
        #expect(quota.window.label == "Credits")
        #expect(quota.window.duration == nil)
    }

    @Test("a period that ends before it starts has no length")
    func refusesAReversedPeriod() throws {
        let reversed = """
        {"config":{"creditUsagePercent":12,"currentPeriod":\
        {"start":"2026-11-08T13:01:35Z","end":"2026-11-01T13:01:35Z"}}}
        """
        let quota = try #require(Self.reading(reversed).first)

        #expect(quota.window.duration == nil)
    }

    @Test("a period type without the usual prefix is still its own name")
    func namesAnUnprefixedType() throws {
        let text = #"{"config":{"creditUsagePercent":12,"currentPeriod":{"type":"MONTHLY"}}}"#
        let quota = try #require(Self.reading(text).first)

        #expect(quota.window.key == "monthly")
        #expect(quota.window.label == "Monthly")
    }

    @Test("a usage figure that is not a number is drawn without one")
    func readsAnUnreadableFigureAsUnknown() throws {
        let quota = try #require(Self.reading(#"{"config":{"creditUsagePercent":"lots"}}"#).first)
        #expect(quota.measure == .unknown)
    }

    @Test("the plan is read only from a Grok answer, trimmed, and dropped when blank", arguments: [
        (#"{"config":{"creditUsagePercent":1},"subscription_tier":"  SuperGrok  "}"#, "SuperGrok"),
        (#"{"config":{"creditUsagePercent":1},"subscription_tier":"   "}"#, nil),
    ])
    func readsThePlanCarefully(text: String, plan: String?) {
        let account = GrokQuotaSource().account(from: Data(text.utf8), at: Self.now)
        #expect(account?.provider == .grok)
        #expect(account?.plan == plan)
    }

    @Test("an answer that is not Grok's carries no Grok account")
    func ignoresAnotherAgentsAnswer() {
        let codex = #"{"rateLimits":{"planType":"pro"},"subscription_tier":"SuperGrok"}"#
        #expect(GrokQuotaSource().account(from: Data(codex.utf8), at: Self.now) == nil)
    }

    @Test("the setup sentence names every agent whose limits the panel shows")
    func setupSentenceNamesGrok() {
        #expect(MenuBarPanelContent.setupSentence == "Sign in to Claude Code, Codex, Grok or Antigravity and their limits show here.")
    }
}
