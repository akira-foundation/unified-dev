import Foundation
import Testing
@testable import Core

@Suite("Menu bar panel content")
struct MenuBarPanelContentTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func workspace(_ name: String, unread: Bool = false) -> Workspace {
        Workspace(
            repoID: RepoID("repo"),
            name: name,
            branch: "feature/\(name)",
            path: "/tmp/\(name)",
            baseBranch: "main",
            setupState: .succeeded,
            unread: unread
        )
    }

    func quota(
        _ provider: AgentKind,
        _ window: QuotaWindow,
        _ fraction: Double?,
        resetsIn seconds: TimeInterval? = 86_400
    ) -> AgentQuota {
        AgentQuota(
            provider: provider,
            window: window,
            measure: fraction.map { .fraction($0) } ?? .unknown,
            resetsAt: seconds.map { now.addingTimeInterval($0) },
            observedAt: now
        )
    }

    private let codexWeek = QuotaWindow.lasting(604_800, key: "primary")
    private let fable = QuotaWindow(key: "seven_day_model_fable", label: "Week (Fable)", duration: 604_800)

    var calmCodex: AgentQuota { quota(.codex, codexWeek, 0.2) }

    func input(
        workspaces: [Workspace] = [],
        running: [Workspace] = [],
        waiting: [Workspace] = [],
        agents: [WorkspaceID: Int]? = nil,
        askIsWorking: Bool = false,
        quotas: [AgentQuota] = [],
        accounts: [AgentKind: AgentAccount] = [:],
        unanswered: Set<AgentKind> = [],
        withoutLimits: Set<AgentKind> = [],
        lastReported: [AgentKind: Date] = [:],
        layout: UsageLayout = UsageLayout(),
        hold: KeepAwake.Hold = .none,
        offers: [AgentKind: QuotaAccountOffer] = [:]
    ) -> MenuBarPanelContent.Input {
        MenuBarPanelContent.Input(
            workspaces: workspaces,
            running: Set(running.map(\.id)),
            waiting: Set(waiting.map(\.id)),
            agentsByWorkspace: agents ?? Dictionary(uniqueKeysWithValues: running.map { ($0.id, 1) }),
            quotas: quotas,
            accounts: accounts,
            unanswered: unanswered,
            withoutLimits: withoutLimits,
            lastReported: lastReported,
            layout: layout,
            hold: hold,
            now: now,
            offers: offers,
            askIsWorking: askIsWorking
        )
    }

    @Test("with nothing going on it says so, and shows no icons")
    func idle() {
        let content = MenuBarPanelContent.make(input(quotas: [calmCodex]))
        #expect(content.sentence == "No agents running.")
        #expect(content.badges.isEmpty)
        #expect(!content.needsSetup)
    }

    @Test("an offer of another account lands on its own provider and on no other")
    func offerLandsOnItsProvider() {
        let offer = QuotaAccountOffer(
            headline: "x", choices: [], notes: []
        )
        let content = MenuBarPanelContent.make(input(
            quotas: [calmCodex, quota(.claudeCode, .named("five_hour"), 0.2)],
            offers: [.codex: offer]
        ))
        #expect(content.providers.first { $0.kind == .codex }?.offer == offer)
        #expect(content.providers.first { $0.kind == .claudeCode }?.offer == nil)
    }

    @Test("an offer reaches a provider that did not answer, because a sign-out is why it may not")
    func offerReachesASilentProvider() {
        let offer = QuotaAccountOffer(
            headline: "x", choices: [], notes: []
        )
        let content = MenuBarPanelContent.make(input(
            quotas: [calmCodex], unanswered: [.claudeCode], offers: [.claudeCode: offer]
        ))
        let claude = content.providers.first { $0.kind == .claudeCode }
        #expect(claude?.reading == .unavailable)
        #expect(claude?.offer == offer)
    }

    @Test("counts agents and the workspaces they run in")
    func running() {
        let a = workspace("a"), b = workspace("b"), c = workspace("c")
        let content = MenuBarPanelContent.make(input(
            workspaces: [a, b, c], running: [a, b], agents: [a.id: 2, b.id: 1], quotas: [calmCodex]
        ))
        #expect(content.sentence == "3 agents running in 2 workspaces.")
        #expect(content.badges == [.running])
    }

    @Test("one agent in one workspace reads in the singular")
    func singular() {
        let a = workspace("a")
        let content = MenuBarPanelContent.make(input(workspaces: [a], running: [a], quotas: [calmCodex]))
        #expect(content.sentence == "1 agent running in 1 workspace.")
    }

    @Test("an agent running outside any workspace is counted without naming workspaces")
    func askConversation() {
        let content = MenuBarPanelContent.make(input(askIsWorking: true, quotas: [calmCodex]))
        #expect(content.sentence == "1 agent running.")
        #expect(content.badges == [.running])
    }

    @Test("an agent waiting on the owner is said after the running ones")
    func waiting() {
        let a = workspace("a"), b = workspace("b")
        let content = MenuBarPanelContent.make(input(
            workspaces: [b, a], running: [b], waiting: [a], quotas: [calmCodex]
        ))
        #expect(content.sentence == "1 agent running in 1 workspace. 1 agent waiting on you.")
        #expect(content.badges == [.running, .waiting])
    }

    @Test("the example the owner approved reads word for word")
    func approvedExample() {
        let a = workspace("a"), b = workspace("b")
        let content = MenuBarPanelContent.make(input(
            workspaces: [a, b],
            running: [a, b],
            agents: [a.id: 2, b.id: 1],
            quotas: [quota(.codex, codexWeek, 1, resetsIn: 140_400)],
            hold: .whileAgentsRun
        ))
        #expect(content.sentence == "3 agents running in 2 workspaces. Codex weekly limit reached, "
            + "resets in 1d 15h. The Mac stays awake until they finish.")
        #expect(content.badges == [.running, .limitReached, .awake])
    }

    @Test("a limit named after a model keeps the model's name in capitals")
    func modelLimit() {
        let content = MenuBarPanelContent.make(input(quotas: [quota(.claudeCode, fable, 1, resetsIn: 3600)]))
        #expect(content.sentence == "No agents running. Claude Code Fable limit reached, resets in 1h.")
        #expect(content.notices == [MenuBarPanelContent.LimitNotice(
            provider: .claudeCode, title: "Fable", resetsAt: now.addingTimeInterval(3600)
        )])
    }

    @Test("a spent limit with no reset time says only that it is spent")
    func limitWithoutReset() {
        let content = MenuBarPanelContent.make(input(quotas: [quota(.codex, codexWeek, 1, resetsIn: nil)]))
        #expect(content.sentence == "No agents running. Codex weekly limit reached.")
    }

    @Test("a limit that is nearly gone is not a limit reached")
    func nearlyGone() {
        let content = MenuBarPanelContent.make(input(quotas: [quota(.codex, codexWeek, 0.95)]))
        #expect(content.notices.isEmpty)
        #expect(!content.badges.contains(.limitReached))
    }

    @Test("says how long the Mac stays awake, whatever holds it", arguments: [
        (KeepAwake.Hold.indefinitely, "Keep Awake is on until you turn it off."),
        (KeepAwake.Hold.until(Date(timeIntervalSince1970: 1_800_003_600)), "Keep Awake is on for 1h more."),
    ])
    func awake(hold: KeepAwake.Hold, phrase: String) {
        let content = MenuBarPanelContent.make(input(quotas: [calmCodex], hold: hold))
        #expect(content.sentence == "No agents running. " + phrase)
        #expect(content.badges == [.awake])
    }

    @Test("with no provider signed in it says how to start")
    func setup() {
        let content = MenuBarPanelContent.make(input())
        #expect(content.needsSetup)
        #expect(content.providers.isEmpty)
        #expect(content.sentence == "No agents running. " + MenuBarPanelContent.setupSentence)
    }

    @Test("a provider shows once it has answered, in the order the owner chose")
    func providers() {
        let layout = UsageLayout(providerOrder: [.codex, .claudeCode])
        let content = MenuBarPanelContent.make(input(
            quotas: [calmCodex, quota(.claudeCode, .named("five_hour"), 0.1)], layout: layout
        ))
        #expect(content.providers.map(\.kind) == [.codex, .claudeCode])
        #expect(content.providers.allSatisfy { $0.reading == .measured })
    }

    @Test("a provider switched off in Menu Bar settings stays out of the panel")
    func disabledProvider() {
        let layout = UsageLayout(disabledProviders: [.codex])
        let content = MenuBarPanelContent.make(input(quotas: [calmCodex], layout: layout))
        #expect(content.providers.isEmpty)
        #expect(!content.needsSetup)
        #expect(content.sentence == "No agents running.")
    }

    @Test("a provider that did not answer the last ask is drawn saying so, never dropped")
    func unanswered() {
        let content = MenuBarPanelContent.make(input(quotas: [calmCodex], unanswered: [.codex, .claudeCode]))
        #expect(content.providers.map(\.kind) == [.claudeCode, .codex])
        #expect(content.providers.allSatisfy { $0.reading == .unavailable })
        #expect(content.providers.map(\.note) == [
            "Claude Code did not answer.",
            "Codex did not answer.",
        ])
    }

    @Test("a provider that did not answer says when it last reported, if that is known")
    func unansweredSaysItsLastReport() {
        let content = MenuBarPanelContent.make(input(
            unanswered: [.claudeCode],
            lastReported: [.claudeCode: now.addingTimeInterval(-165 * 3600)]
        ))
        #expect(content.providers.first?.note == "Claude Code did not answer. Last reported 6d 21h ago.")
    }

    @Test("an agent that answered to say its limits do not apply says that, not that it went quiet")
    func withoutLimits() {
        let account = AgentAccount(provider: .claudeCode, observedAt: now)
        let bare = MenuBarPanelContent.make(input(accounts: [.claudeCode: account], withoutLimits: [.claudeCode]))
        #expect(bare.providers.first?.reading == .unavailable)
        #expect(bare.providers.first?.note == "Claude Code reports that plan limits do not apply to it.")

        let dated = MenuBarPanelContent.make(input(
            accounts: [.claudeCode: account],
            withoutLimits: [.claudeCode],
            lastReported: [.claudeCode: now.addingTimeInterval(-165 * 3600)]
        ))
        #expect(dated.providers.first?.note
            == "Claude Code reports that plan limits do not apply to it. Last reported 6d 21h ago.")
    }

    @Test("a provider still drawing a stored reading is told it no longer has limits, beside its age")
    func withoutLimitsWhileStillDrawing() {
        var old = quota(.claudeCode, .named("seven_day"), 0.09)
        old.observedAt = now.addingTimeInterval(-3_600)

        let content = MenuBarPanelContent.make(input(quotas: [old], withoutLimits: [.claudeCode]))

        #expect(content.providers.first?.reading == .measured)
        #expect(content.providers.first?.note
            == "Claude Code reports that plan limits do not apply to it. Read 1h ago.")
    }

    @Test("a provider still drawing a fresh reading says only that it has no limits")
    func withoutLimitsOnAFreshReading() {
        let fresh = quota(.claudeCode, .named("seven_day"), 0.09)
        let content = MenuBarPanelContent.make(input(quotas: [fresh], withoutLimits: [.claudeCode]))

        #expect(content.providers.first?.note == "Claude Code reports that plan limits do not apply to it.")
    }

    @Test("an agent that said nothing at all is not reported as one that answered")
    func silenceOutranksDeclinedLimits() {
        let content = MenuBarPanelContent.make(input(
            unanswered: [.claudeCode], withoutLimits: [.claudeCode]
        ))
        #expect(content.providers.first?.note == "Claude Code did not answer.")
    }

    @Test("agents installed but signed into nothing still get told how to sign in")
    func signedIntoNothing() {
        let content = MenuBarPanelContent.make(input(unanswered: [.claudeCode, .codex]))
        #expect(content.needsSetup)
        #expect(content.sentence.hasSuffix(MenuBarPanelContent.setupSentence))
        #expect(content.providers.count == 2)
    }

    @Test("the age is that of the oldest window drawn, and a hidden old one does not speak for it")
    func ageIsOfWhatIsDrawn() {
        var old = quota(.claudeCode, .named("seven_day"), 0.09)
        old.observedAt = now.addingTimeInterval(-2_700)
        var fresh = quota(.claudeCode, .named("five_hour"), 0.1)
        fresh.observedAt = now

        let both = MenuBarPanelContent.make(input(quotas: [old, fresh]))
        #expect(both.providers.first?.note == "Read 45m ago")

        let hidden = UsageLayout(hidden: [UsageCatalogue.metric(for: old).id])
        let drawn = MenuBarPanelContent.make(input(quotas: [old, fresh], layout: hidden))
        #expect(drawn.providers.first?.reading == .measured)
        #expect(drawn.providers.first?.note == nil)
    }

    @Test("a provider that answered without limits says how long it has gone without reporting")
    func answeredWithoutLimits() {
        let account = AgentAccount(provider: .claudeCode, observedAt: now)
        let content = MenuBarPanelContent.make(input(
            accounts: [.claudeCode: account],
            lastReported: [.claudeCode: now.addingTimeInterval(-165 * 3600)]
        ))
        #expect(content.providers.map(\.kind) == [.claudeCode])
        #expect(content.providers.first?.reading == .unavailable)
        #expect(content.providers.first?.note == "Claude Code last reported its limits 6d 21h ago.")
    }

    @Test("a provider that has never reported says only that much")
    func neverReported() {
        let account = AgentAccount(provider: .claudeCode, observedAt: now)
        let content = MenuBarPanelContent.make(input(accounts: [.claudeCode: account]))
        #expect(content.providers.first?.note == "Claude Code did not report its limits.")
    }

    @Test("a reading older than a settled one says when it was taken")
    func readingCarriesItsAge() {
        var old = calmCodex
        old.observedAt = now.addingTimeInterval(-(MenuBarPanelContent.settledReading + 2_520))
        let content = MenuBarPanelContent.make(input(quotas: [old]))
        #expect(content.providers.first?.reading == .measured)
        #expect(content.providers.first?.note == "Read 45m ago")
        #expect(MenuBarPanelContent.settledReading == 180)
    }

    @Test("a reading taken moments ago says nothing about its age")
    func freshReadingIsSilentAboutItsAge() {
        let content = MenuBarPanelContent.make(input(quotas: [calmCodex]))
        #expect(content.providers.first?.reading == .measured)
        #expect(content.providers.first?.note == nil)
    }

    @Test("a reading whose window has already reset does not make a provider known")
    func expiredReading() {
        let content = MenuBarPanelContent.make(input(quotas: [quota(.codex, codexWeek, 0.3, resetsIn: -60)]))
        #expect(content.providers.isEmpty)
        #expect(content.needsSetup)
    }

    @Test("a limit reached on a provider the panel does not show is not said")
    func hiddenLimits() {
        let spent = quota(.codex, codexWeek, 1)
        let disabled = MenuBarPanelContent.make(input(quotas: [spent], layout: UsageLayout(disabledProviders: [.codex])))
        #expect(disabled.notices.isEmpty)
        #expect(!disabled.badges.contains(.limitReached))
        let silent = MenuBarPanelContent.make(input(quotas: [spent], unanswered: [.codex]))
        #expect(silent.notices.isEmpty)
        #expect(silent.sentence == "No agents running.")
    }

    @Test("a provider whose readings the owner hid stays out, one with no reading at all does not")
    func nothingToDraw() {
        let account = AgentAccount(provider: .claudeCode, plan: "Max", observedAt: now)
        let hidden = UsageLayout(hidden: [UsageCatalogue.metric(for: calmCodex).id])
        let content = MenuBarPanelContent.make(input(
            quotas: [calmCodex], accounts: [.claudeCode: account], layout: hidden
        ))
        #expect(content.providers.map(\.kind) == [.claudeCode])
        #expect(content.providers.first?.reading == .unavailable)
        #expect(!content.needsSetup)
    }

    @Test("a provider carries the limits it draws, and folds only when some wait on demand")
    func folding() {
        let extra = quota(.codex, .lasting(18_000, key: "secondary"), 0.1)
        let flat = MenuBarPanelContent.make(input(quotas: [calmCodex, extra]))
        #expect(flat.providers.first?.section?.alwaysVisible.count == 2)
        #expect(flat.providers.first?.isFoldable == false)
        let layout = UsageLayout(placements: [UsageCatalogue.metric(for: extra).id: .onDemand])
        let folded = MenuBarPanelContent.make(input(quotas: [calmCodex, extra], layout: layout))
        #expect(folded.providers.first?.section?.onDemand.count == 1)
        #expect(folded.providers.first?.isFoldable == true)
    }

    @Test("the count never falls below the workspaces seen working, and is never cut at five")
    func countFloor() {
        let names = ["a", "b", "c", "d", "e", "f"]
        let running = names.map { workspace($0) }
        let content = MenuBarPanelContent.make(input(
            workspaces: running, running: running, agents: [:], quotas: [calmCodex]
        ))
        #expect(content.sentence == "6 agents running in 6 workspaces.")
        #expect(content.agents.count == 5)
    }

    @Test("lists waiting agents first, leaves finished ones out, and stops at five")
    func agents() {
        let names = ["r1", "r2", "r3", "r4", "r5"]
        let running = names.map { workspace($0) }
        let asking = workspace("asking")
        let finished = workspace("finished", unread: true)
        let content = MenuBarPanelContent.make(input(
            workspaces: running + [finished, asking], running: running, waiting: [asking], quotas: [calmCodex]
        ))
        #expect(content.agents.map(\.workspace.name) == ["asking", "r1", "r2", "r3", "r4"])
        #expect(content.agents.first?.isWaiting == true)
        #expect(content.moreAgents == 1)
        #expect(MenuBarPanelContent.moreTitle(content.moreAgents) == "+1 more")
    }

    @Test("an agent row carries the glyph and the word the old menu used")
    func agentRow() {
        let row = MenuBarPanelContent.Agent(workspace: workspace("a"), isWaiting: true)
        #expect(row.symbolName == MenuBarSummary.waitingSymbol)
        #expect(row.label == MenuBarSummary.waitingHeading)
        #expect(MenuBarPanelContent.Agent(workspace: workspace("b"), isWaiting: false).label == MenuBarSummary.runningHeading)
    }

    @Test("a provider with no reading says so in a short line")
    func unavailableLine() {
        #expect(MenuBarPanelContent.unavailableLine(for: .codex) == "Codex did not report its limits.")
    }
}
