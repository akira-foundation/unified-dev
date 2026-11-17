import Foundation
import Testing
@testable import Core

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private let client = AgentAccountID("client")
private let ultra = AgentAccountID("ultra")
private let claudeClient = QuotaHolder(provider: .claudeCode, account: client)
private let claudeUltra = QuotaHolder(provider: .claudeCode, account: ultra)
private let codexClient = QuotaHolder(provider: .codex, account: client)

private func weekly(_ holder: QuotaHolder, _ fraction: Double, observed: Date = now) -> AgentQuota {
    AgentQuota(
        provider: holder.provider,
        window: .named("seven_day"),
        measure: .fraction(fraction),
        resetsAt: now.addingTimeInterval(115_200),
        observedAt: observed,
        account: holder.account
    )
}

private func scope(_ holders: QuotaHolder...) -> QuotaScope {
    QuotaScope(holders: Dictionary(uniqueKeysWithValues: holders.map { ($0.provider, $0) }))
}

@Suite("Which account a quota reading is drawn under")
struct QuotaShownTests {
    @Test("a reading for one account is never drawn under another account of the same agent")
    func anotherAccountsReadingIsNotDrawn() {
        let shown = QuotaShown.make(
            stored: [weekly(claudeClient, 1)], readings: QuotaReadings(), scope: scope(claudeUltra), reading: []
        )

        #expect(shown.quotas.isEmpty)
    }

    @Test("an account named the same under two agents keeps each agent's numbers apart")
    func sameNameUnderTwoAgentsStaysApart() {
        let shown = QuotaShown.make(
            stored: [weekly(claudeClient, 1), weekly(codexClient, 0.2)],
            readings: QuotaReadings(),
            scope: scope(codexClient),
            reading: []
        )

        #expect(shown.quotas.map(\.provider) == [.codex])
        #expect(shown.quotas.first?.fraction == 0.2)
    }

    @Test("both accounts' readings are kept, and the one in use is the one drawn")
    func theAccountInUseIsDrawn() {
        let stored = [weekly(claudeClient, 1), weekly(claudeUltra, 0.1)]

        let before = QuotaShown.make(stored: stored, readings: QuotaReadings(), scope: scope(claudeClient), reading: [])
        let after = QuotaShown.make(stored: stored, readings: QuotaReadings(), scope: scope(claudeUltra), reading: [])

        #expect(before.quotas.map(\.fraction) == [1])
        #expect(after.quotas.map(\.fraction) == [0.1])
    }

    @Test("a reading that names no account is drawn under none")
    func anUnownedReadingIsNotDrawn() {
        var unowned = weekly(claudeClient, 1)
        unowned.account = nil

        let shown = QuotaShown.make(stored: [unowned], readings: QuotaReadings(), scope: scope(claudeClient), reading: [])

        #expect(shown.quotas.isEmpty)
    }

    @Test("nothing is drawn before the accounts in use are known")
    func nothingBeforeTheScope() {
        let shown = QuotaShown.make(stored: [weekly(claudeClient, 1)], readings: QuotaReadings(), scope: nil, reading: [])

        #expect(shown == QuotaShown())
    }

    @Test("an account being read for the first time is pending rather than borrowing another's numbers")
    func aNewAccountIsPending() {
        let shown = QuotaShown.make(
            stored: [weekly(claudeClient, 1)], readings: QuotaReadings(), scope: scope(claudeUltra), reading: [claudeUltra]
        )

        #expect(shown.pending == [.claudeCode])
        #expect(shown.quotas.isEmpty)
    }

    @Test("an account being read again keeps its own earlier numbers and is not pending")
    func aKnownAccountIsNotPending() {
        let shown = QuotaShown.make(
            stored: [weekly(claudeUltra, 0.3)], readings: QuotaReadings(), scope: scope(claudeUltra), reading: [claudeUltra]
        )

        #expect(shown.pending.isEmpty)
        #expect(shown.quotas.map(\.fraction) == [0.3])
    }

    @Test("the plan, silence and last report of one account are not told of another")
    func readingsBelongToTheirAccount() {
        var readings = QuotaReadings()
        readings.adopt(QuotaReport(
            accounts: [AgentAccount(provider: .claudeCode, plan: "Max", observedAt: now)],
            unanswered: [.claudeCode],
            withoutLimits: [.claudeCode],
            lastReported: [.claudeCode: now],
            holders: [.claudeCode: claudeClient]
        ))

        let other = QuotaShown.make(stored: [], readings: readings, scope: scope(claudeUltra), reading: [])
        let own = QuotaShown.make(stored: [], readings: readings, scope: scope(claudeClient), reading: [])

        #expect(other == QuotaShown())
        #expect(own.accounts[.claudeCode]?.plan == "Max")
        #expect(own.unanswered == [.claudeCode])
        #expect(own.withoutLimits == [.claudeCode])
        #expect(own.lastReported == [.claudeCode: now])
    }
}

@Suite("Reading quotas when the accounts in use change")
struct QuotaAskLedgerTests {
    @Test("a slow reading for the previous account does not hold back the new account's")
    func aSwitchDoesNotWaitForASlowRead() {
        var ledger = QuotaAskLedger()
        ledger.begin([claudeClient], at: now)

        let due = ledger.due([claudeUltra], at: now.addingTimeInterval(1), after: QuotaPollSchedule.onDemandFloor)

        #expect(due == [claudeUltra])
    }

    @Test("an account already being read is not asked a second time")
    func anAccountInFlightIsNotAskedTwice() {
        var ledger = QuotaAskLedger()
        ledger.begin([claudeUltra], at: now)

        #expect(ledger.due([claudeUltra], at: now.addingTimeInterval(120), after: 0).isEmpty)
    }

    @Test("an account read moments ago waits for its gap, and one never read does not")
    func theGapIsKeptPerAccount() {
        var ledger = QuotaAskLedger()
        ledger.begin([claudeClient], at: now)
        ledger.end([claudeClient])

        let due = ledger.due([claudeClient, claudeUltra], at: now.addingTimeInterval(5), after: QuotaPollSchedule.interval)

        #expect(due == [claudeUltra])
    }
}

@Suite("A quota report names the account it was read for")
struct QuotaReportHolderTests {
    private struct Reading: AgentQuotaSource {
        static let provider = AgentKind.claudeCode
        let home: AgentAccountHome

        var holder: QuotaHolder { QuotaHolder(provider: Self.provider, home: home) }

        func read() async -> Data? {
            Data(#"{"session":{},"rate_limits_available":true,"rate_limits":{"seven_day":{"utilization":50}}}"#.utf8)
        }
    }

    @Test("every reading in a report carries the account its source read")
    func readingsCarryTheirAccount() async {
        let home = AgentAccountHome(
            provider: .claudeCode, id: ultra, directory: URL(filePath: "/tmp/ultra"), isDefault: false
        )

        let report = await AgentQuotaSources.report([Reading(home: home)], at: now)

        #expect(report.holders == [.claudeCode: claudeUltra])
        #expect(!report.quotas.isEmpty)
        #expect(report.quotas.allSatisfy { $0.holder == claudeUltra })
    }

    @Test("an account of another agent is not taken as this agent's")
    func anotherAgentsHomeFallsBackToTheDefault() {
        let home = AgentAccountHome(provider: .codex, id: client, directory: URL(filePath: "/tmp/c"), isDefault: false)

        #expect(QuotaHolder(provider: .claudeCode, home: home).account == AgentAccountHome.defaultID(for: .claudeCode))
    }
}

@Suite("Quota storage keeps one row per account", .scratchDirectory)
struct QuotaStorePerAccountTests {
    @Test("two accounts of one agent reporting the same window are two rows")
    func twoAccountsAreTwoRows() async throws {
        let store = try makeTestStore("quotas-accounts")
        try await store.recordQuotas([weekly(claudeClient, 1), weekly(claudeUltra, 0.1), weekly(codexClient, 0.2)])

        let stored = try await store.quotas(at: now)

        #expect(Set(stored.compactMap(\.holder)) == [claudeClient, claudeUltra, codexClient])
        #expect(stored.first { $0.holder == claudeUltra }?.fraction == 0.1)
    }

    @Test("a fresher reading for one account leaves another account's row alone")
    func oneAccountDoesNotOverwriteAnother() async throws {
        let store = try makeTestStore("quotas-accounts-fresh")
        try await store.recordQuotas([weekly(claudeClient, 1)])
        try await store.recordQuotas([weekly(claudeUltra, 0.1, observed: now.addingTimeInterval(60))])

        let stored = try await store.quotas(at: now)

        #expect(stored.first { $0.holder == claudeClient }?.fraction == 1)
    }

    @Test("a database from before readings named their account drops the readings it cannot place")
    func anOldTableIsReplaced() async throws {
        let path = TestScratch.unique("quotas-old") + ".sqlite"
        let db = try SQLiteDatabase(path: path)
        try db.execute("""
            CREATE TABLE agent_quotas (
                provider TEXT NOT NULL, window_key TEXT NOT NULL, window_label TEXT NOT NULL,
                window_seconds REAL, used REAL, limit_value REAL, unit TEXT, resets_at REAL,
                observed_at REAL NOT NULL, PRIMARY KEY (provider, window_key)
            );
            INSERT INTO agent_quotas VALUES ('claudeCode', 'seven_day', 'Week', 604800, 1, 1, 'fraction', NULL, 0);
            """)

        try QuotaAccountColumn.migrate(db)

        #expect(try db.query("SELECT * FROM agent_quotas").isEmpty)
        let columns = try db.query("PRAGMA table_info(agent_quotas);").compactMap { $0.string("name") }
        #expect(columns.contains(QuotaAccountColumn.column))
    }
}

@Suite("The menu bar panel while an account is being read")
struct MenuBarPanelPendingTests {
    @Test("an agent whose account is being read says so instead of showing nothing or old numbers")
    func pendingSaysReading() {
        let input = MenuBarPanelContent.Input(
            workspaces: [], running: [], waiting: [], agentsByWorkspace: [:],
            quotas: [], accounts: [:], unanswered: [], withoutLimits: [], lastReported: [:],
            pending: [.claudeCode],
            layout: UsageLayout(), hold: .none, now: now
        )

        let provider = MenuBarPanelContent.make(input).providers.first { $0.kind == .claudeCode }

        #expect(provider?.reading == .unavailable)
        #expect(provider?.note == MenuBarPanelContent.readingLine(for: .claudeCode))
    }
}
