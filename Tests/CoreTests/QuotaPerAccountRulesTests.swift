import Foundation
import Testing
@testable import Core

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private let client = AgentAccountID("client")
private let ultra = AgentAccountID("ultra")
private let claudeClient = QuotaHolder(provider: .claudeCode, account: client)
private let claudeUltra = QuotaHolder(provider: .claudeCode, account: ultra)
private let codexClient = QuotaHolder(provider: .codex, account: client)

private func weekly(_ holder: QuotaHolder, _ measure: QuotaMeasure, observed: Date = now) -> AgentQuota {
    AgentQuota(
        provider: holder.provider,
        window: .named("seven_day"),
        measure: measure,
        resetsAt: now.addingTimeInterval(115_200),
        observedAt: observed,
        account: holder.account
    )
}

private func scope(_ holders: QuotaHolder...) -> QuotaScope {
    QuotaScope(holders: Dictionary(uniqueKeysWithValues: holders.map { ($0.provider, $0) }))
}

@Suite("What a report tells each account")
struct QuotaReadingsAdoptTests {
    @Test("one report for two agents gives each its own plan and its own silence")
    func eachAgentKeepsItsOwn() {
        var readings = QuotaReadings()
        readings.adopt(QuotaReport(
            accounts: [AgentAccount(provider: .claudeCode, plan: "Max", observedAt: now)],
            unanswered: [.codex],
            holders: [.claudeCode: claudeClient, .codex: codexClient]
        ))

        #expect(readings.identities[claudeClient]?.plan == "Max")
        #expect(readings.identities[codexClient] == nil)
        #expect(readings.unanswered == [codexClient])
    }

    @Test("reading a new account leaves what the previous account reported")
    func aNewAccountKeepsTheOldOnesReading() {
        var readings = QuotaReadings()
        readings.adopt(QuotaReport(
            accounts: [AgentAccount(provider: .claudeCode, plan: "Pro", observedAt: now)],
            holders: [.claudeCode: claudeClient]
        ))
        readings.adopt(QuotaReport(
            accounts: [AgentAccount(provider: .claudeCode, plan: "Ultra", observedAt: now)],
            holders: [.claudeCode: claudeUltra]
        ))

        #expect(readings.identities[claudeClient]?.plan == "Pro")
        #expect(readings.identities[claudeUltra]?.plan == "Ultra")
    }

    @Test("an account that answers again is no longer said to be silent")
    func silenceClears() {
        var readings = QuotaReadings()
        readings.adopt(QuotaReport(unanswered: [.codex], withoutLimits: [.codex], holders: [.codex: codexClient]))
        readings.adopt(QuotaReport(holders: [.codex: codexClient]))

        #expect(readings.unanswered.isEmpty)
        #expect(readings.withoutLimits.isEmpty)
    }
}

@Suite("Reports for agents that do not answer or are not installed")
struct QuotaReportSilentHolderTests {
    private struct Silent: AgentQuotaSource {
        static let provider = AgentKind.codex
        var holder: QuotaHolder { codexClient }
        func read() async -> Data? { nil }
    }

    private struct Absent: AgentQuotaSource {
        static let provider = AgentKind.codex
        var holder: QuotaHolder { codexClient }
        func read() async -> Data? { nil }
        func standing() async -> QuotaStanding { QuotaStanding(isInstalled: false) }
    }

    @Test("a silent agent is named against the account that was asked")
    func silenceNamesTheAccount() async {
        var readings = QuotaReadings()
        readings.adopt(await AgentQuotaSources.report([Silent()], at: now))

        #expect(readings.unanswered == [codexClient])
    }

    @Test("an agent that has gone stops being said to be silent")
    func anAbsentAgentClearsItsSilence() async {
        var readings = QuotaReadings()
        readings.adopt(await AgentQuotaSources.report([Silent()], at: now))
        readings.adopt(await AgentQuotaSources.report([Absent()], at: now))

        #expect(readings.unanswered.isEmpty)
    }

    @Test("an agent that has gone forgets when it last reported")
    func anAbsentAgentForgetsItsStamp() {
        var readings = QuotaReadings()
        readings.adopt(QuotaReport(lastReported: [.codex: now], holders: [.codex: codexClient]))
        readings.adopt(QuotaReport(holders: [.codex: codexClient]))

        #expect(readings.lastReported.isEmpty)
    }
}

@Suite("Rules that keep one account's numbers from another's")
struct QuotaAccountRulesTests {
    @Test("tagging a reading with another agent's account leaves it as it was")
    func anotherAgentsHolderIsRefused() {
        let reading = weekly(claudeClient, .fraction(1))

        #expect(reading.held(by: codexClient).holder == claudeClient)
    }

    @Test("a reading without a figure does not borrow another account's figure")
    func mergeDoesNotCrossAccounts() {
        let known = [weekly(claudeClient, .fraction(1), observed: now.addingTimeInterval(-60))]

        let merged = QuotaMerge.resolved([weekly(claudeUltra, .unknown)], against: known)

        #expect(merged.map(\.measure) == [.unknown])
        #expect(merged.map(\.holder) == [claudeUltra])
    }

    @Test("an account read and finished is asked again once its gap has passed")
    func aFinishedReadIsAskedAgain() {
        var ledger = QuotaAskLedger()
        ledger.begin([claudeUltra], at: now)
        ledger.end([claudeUltra])

        let due = ledger.due([claudeUltra], at: now.addingTimeInterval(QuotaPollSchedule.interval), after: QuotaPollSchedule.interval)

        #expect(due == [claudeUltra])
    }

    @Test("the accounts in use name the chosen account, and the default where none is chosen")
    func scopeFromHomes() {
        let home = AgentAccountHome(provider: .claudeCode, id: ultra, directory: URL(filePath: "/tmp/u"), isDefault: false)

        let made = QuotaScope(homes: [.claudeCode: home])

        #expect(made.holders[.claudeCode] == claudeUltra)
        #expect(made.holders[.codex] == QuotaHolder(provider: .codex, account: AgentAccountHome.defaultID(for: .codex)))
        #expect(Set(made.holders.keys) == Set(AgentKind.allCases.filter(\.publishesUsage)))
    }

    @Test("the previous account's read in flight does not mark the new account as being read")
    func pendingIsOnlyTheScopesOwn() {
        let shown = QuotaShown.make(
            stored: [weekly(claudeClient, .fraction(1))], readings: QuotaReadings(), scope: scope(claudeUltra), reading: [claudeClient]
        )

        #expect(shown.pending.isEmpty)
    }

    @Test("an agent this Mac has never had an answer from is not shown as being read")
    func anUnheardAgentIsNotPending() {
        let shown = QuotaShown.make(stored: [], readings: QuotaReadings(), scope: scope(codexClient), reading: [codexClient])

        #expect(shown.pending.isEmpty)
    }

    @Test("an agent with an account's plan but no figures is not shown as being read")
    func anIdentityIsDrawn() {
        var readings = QuotaReadings()
        readings.adopt(QuotaReport(
            accounts: [AgentAccount(provider: .claudeCode, plan: "Ultra", observedAt: now)],
            holders: [.claudeCode: claudeUltra]
        ))

        let shown = QuotaShown.make(stored: [], readings: readings, scope: scope(claudeUltra), reading: [claudeUltra])

        #expect(shown.pending.isEmpty)
    }

    @Test("an agent known only by a plan or a last report is shown as being read for a new account", arguments: [
        QuotaReport(accounts: [AgentAccount(provider: .claudeCode, observedAt: now)], holders: [.claudeCode: claudeClient]),
        QuotaReport(lastReported: [.claudeCode: now], holders: [.claudeCode: claudeClient]),
    ])
    func anAgentHeardFromIsPending(report: QuotaReport) {
        var readings = QuotaReadings()
        readings.adopt(report)

        let shown = QuotaShown.make(stored: [], readings: readings, scope: scope(claudeUltra), reading: [claudeUltra])

        #expect(shown.pending == [.claudeCode])
    }

    @Test("a seeded reading for a named account has an id of its own")
    func seededIdNamesTheAccount() {
        let one = PreviewScenario.Quota(provider: .claudeCode, window: "seven_day", account: "client")
        let other = PreviewScenario.Quota(provider: .claudeCode, window: "seven_day", account: "ultra")

        #expect(one.id != other.id)
        #expect(one.quota(at: now).holder == claudeClient)
    }
}

@Suite("Quota storage and the accounts it belongs to", .scratchDirectory)
struct QuotaAccountStoreRulesTests {
    @Test("migrating a table that already names accounts keeps its readings")
    func aSecondMigrationKeepsRows() async throws {
        let store = try makeTestStore("quotas-remigrate")
        try await store.recordQuotas([weekly(claudeClient, .fraction(0.5))])

        try QuotaAccountColumn.migrate(try SQLiteDatabase(path: store.path))

        #expect(try await store.quotas(at: now).map(\.holder) == [claudeClient])
    }

    @Test("forgetting an account forgets its readings and no other agent's of the same name")
    func forgettingAnAccountForgetsItsReadings() async throws {
        let store = try makeTestStore("quotas-forget")
        try await store.add(AgentAccountRow(
            id: client, provider: .claudeCode, directory: "/accounts/claudeCode/client", label: "Client",
            createdAt: Date(timeIntervalSince1970: 1_000)
        ))
        try await store.recordQuotas([weekly(claudeClient, .fraction(1)), weekly(codexClient, .fraction(0.2))])

        try await store.forgetAgentAccount(client)

        #expect(try await store.quotas(at: now).map(\.holder) == [codexClient])
    }
}

@Suite("The menu bar panel when an account being read already has figures")
struct MenuBarPanelPendingWithFiguresTests {
    @Test("figures already read for the account are drawn while it is read again")
    func figuresWin() {
        let input = MenuBarPanelContent.Input(
            workspaces: [], running: [], waiting: [], agentsByWorkspace: [:],
            quotas: [weekly(claudeUltra, .fraction(0.3))], accounts: [:], unanswered: [], withoutLimits: [],
            lastReported: [:], pending: [.claudeCode], layout: UsageLayout(), hold: .none, now: now
        )

        let provider = MenuBarPanelContent.make(input).providers.first { $0.kind == .claudeCode }

        #expect(provider?.reading == .measured)
    }
}
