import Testing
@testable import Core

@Suite("Choosing the agent new sessions start on")
struct OnboardingAgentChoiceTests {
    private func report(
        claude: SetupOutcome = .ready(detail: nil),
        codex: SetupOutcome = .ready(detail: nil),
        grok: SetupOutcome = .missing,
        antigravity: SetupOutcome = .missing
    ) -> SetupReport {
        SetupReport(checks: [
            SetupCheck(tool: .git, outcome: .ready(detail: nil)),
            SetupCheck(tool: .claudeCode, outcome: claude),
            SetupCheck(tool: .codex, outcome: codex),
            SetupCheck(tool: .grok, outcome: grok),
            SetupCheck(tool: .antigravity, outcome: antigravity),
            SetupCheck(tool: .gitHub, outcome: .ready(detail: nil)),
        ])
    }

    private let codexModels: [AgentKind: [AgentModel]] = [
        .codex: [
            AgentModel(id: "gpt-5.5", displayName: "GPT-5.5", supportedEfforts: [
                AgentModelEffort(id: "medium", label: "Medium"),
            ], defaultEffort: "medium"),
            AgentModel(id: "gpt-5.6-sol", displayName: "GPT-5.6 Sol", isDefault: true, supportedEfforts: [
                AgentModelEffort(id: "low", label: "Low"), AgentModelEffort(id: "high", label: "High"),
            ], defaultEffort: "low"),
        ],
    ]

    @Test("Offered only between two or more ready agents")
    func offered() {
        #expect(OnboardingAgentChoice.candidates(in: report()) == [.claudeCode, .codex])
        #expect(OnboardingAgentChoice.isOffered(in: report(), hasCompletedOnboarding: false))
        #expect(!OnboardingAgentChoice.isOffered(in: report(codex: .missing), hasCompletedOnboarding: false))
        #expect(!OnboardingAgentChoice.isOffered(
            in: report(codex: .needsSignIn(detail: nil)), hasCompletedOnboarding: false
        ))
        #expect(OnboardingAgentChoice.candidates(in: report(grok: .ready(detail: nil))) == [.claudeCode, .codex, .grok])
        #expect(OnboardingAgentChoice.candidates(in: report(antigravity: .ready(detail: nil))) == [.claudeCode, .codex, .antigravity])
    }

    @Test("Somebody who has been through this already is not asked again")
    func onlyOnTheFirstRun() {
        #expect(!OnboardingAgentChoice.isOffered(in: report(), hasCompletedOnboarding: true))
    }

    @Test("A default preset already decides the agent, so the row stays away")
    func defaultPresetAnswersIt() {
        #expect(!OnboardingAgentChoice.isOffered(
            in: report(), hasCompletedOnboarding: false, hasDefaultPreset: true
        ))
    }

    @Test("Not offered while an agent row is still being looked at")
    func settling() {
        #expect(OnboardingAgentChoice.candidates(in: report(grok: .pending)).isEmpty)
    }

    @Test("A report with no row for an agent at all offers nothing rather than guessing")
    func incompleteReport() {
        let missingGrok = SetupReport(checks: [
            SetupCheck(tool: .git, outcome: .ready(detail: nil)),
            SetupCheck(tool: .claudeCode, outcome: .ready(detail: nil)),
            SetupCheck(tool: .codex, outcome: .ready(detail: nil)),
            SetupCheck(tool: .gitHub, outcome: .ready(detail: nil)),
        ])
        #expect(OnboardingAgentChoice.candidates(in: missingGrok).isEmpty)
    }

    @Test("An agent's card names the account it is signed in to, never a version standing in for one")
    func signedInLine() {
        let signed = report(claude: .ready(detail: "ada@example.com"), codex: .ready(detail: "0.130.0"))
        #expect(OnboardingAgentChoice.signedInLine(for: .claudeCode, in: signed) == "ada@example.com")
        #expect(OnboardingAgentChoice.signedInLine(for: .codex, in: signed) == "Signed in")
        #expect(OnboardingAgentChoice.signedInLine(for: .codex, in: report(codex: .ready(detail: "v2.1.4"))) == "Signed in")
        #expect(OnboardingAgentChoice.signedInLine(for: .codex, in: report(codex: .ready(detail: ""))) == "Signed in")
        #expect(OnboardingAgentChoice.signedInLine(for: .codex, in: report(codex: .ready(detail: "42team"))) == "42team")
        #expect(OnboardingAgentChoice.signedInLine(for: .codex, in: report(codex: .ready(detail: "team 2.0"))) == "team 2.0")
    }

    @Test("Only an agent that is ready is said to be signed in")
    func signedInOnlyWhenReady() {
        let unsure = report(claude: .needsSignIn(detail: "2.1.234"), codex: .pending, grok: .missing)
        #expect(OnboardingAgentChoice.signedInLine(for: .claudeCode, in: unsure) == nil)
        #expect(OnboardingAgentChoice.signedInLine(for: .codex, in: unsure) == nil)
        #expect(OnboardingAgentChoice.signedInLine(for: .grok, in: unsure) == nil)
        #expect(OnboardingAgentChoice.signedInLine(for: .claudeCode, in: report()) == "Signed in")
    }

    @Test("The picker lands on a candidate rather than on an agent that is not there")
    func selection() {
        #expect(OnboardingAgentChoice.selection(among: [.claudeCode, .codex], current: .codex) == .codex)
        #expect(OnboardingAgentChoice.selection(among: [.codex, .grok], current: .claudeCode) == .codex)
        #expect(OnboardingAgentChoice.selection(among: [], current: .claudeCode) == nil)
    }

    @Test("Only the agents whose models come from a server need their list fetched")
    func modelLists() {
        #expect(!OnboardingAgentChoice.needsModelList(for: .claudeCode))
        #expect(OnboardingAgentChoice.needsModelList(for: .codex))
        #expect(OnboardingAgentChoice.needsModelList(for: .grok))
    }

    @Test("Choosing Codex takes its server's default model and a level that model accepts")
    func choosingCodex() throws {
        let chosen = try #require(
            OnboardingAgentChoice.defaults(choosing: .codex, from: AppDefaults(), models: codexModels)
        )
        #expect(chosen.backend == .codex)
        #expect(chosen.model == "gpt-5.6-sol")
        #expect(chosen.effort == "high")
        #expect(chosen.reviewBackend == .codex)
        #expect(chosen.reviewModel == "gpt-5.6-sol")
        #expect(chosen.reviewEffort == "high")
    }

    @Test("A fetched agent with no list yet cannot be answered")
    func notYetFetched() {
        #expect(OnboardingAgentChoice.defaults(choosing: .codex, from: AppDefaults()) == nil)
    }

    @Test("Confirming the agent already in force keeps the model somebody picked")
    func sameAgent() {
        let current = AppDefaults(model: "sonnet", effort: "medium")
        #expect(OnboardingAgentChoice.defaults(choosing: .claudeCode, from: current) == current)
    }

    @Test("A model that already belongs to the chosen agent survives the trip out and back")
    func handPickedModelSurvives() throws {
        let current = AppDefaults(model: "sonnet", effort: "medium", backend: .codex)
        let chosen = try #require(
            OnboardingAgentChoice.defaults(choosing: .claudeCode, from: current)
        )
        #expect(chosen.backend == .claudeCode)
        #expect(chosen.model == "sonnet")
        #expect(chosen.effort == "medium")
    }

    @Test("A review deliberately on another model stays there")
    func separateReview() throws {
        let current = AppDefaults(reviewModel: "sonnet")
        let chosen = try #require(
            OnboardingAgentChoice.defaults(choosing: .codex, from: current, models: codexModels)
        )
        #expect(chosen.reviewBackend == .claudeCode)
        #expect(chosen.reviewModel == "sonnet")
    }

    @Test("A review deliberately deeper on the same model stays there too")
    func separateReviewEffort() throws {
        let current = AppDefaults(model: "gpt-5.6-sol", effort: "low", backend: .codex,
                                  reviewModel: "gpt-5.6-sol", reviewEffort: "high", reviewBackend: .codex)
        let chosen = try #require(
            OnboardingAgentChoice.defaults(choosing: .claudeCode, from: current)
        )
        #expect(chosen.reviewEffort == "high")
        #expect(chosen.reviewBackend == .codex)
    }

    @Test("Going back to Claude Code from a model of its own uses the fallbacks")
    func backToClaude() throws {
        let current = AppDefaults(model: "gpt-5.6-sol", effort: "ultra", backend: .codex,
                                  reviewModel: "gpt-5.6-sol", reviewEffort: "ultra", reviewBackend: .codex)
        let chosen = try #require(
            OnboardingAgentChoice.defaults(choosing: .claudeCode, from: current)
        )
        #expect(chosen.backend == .claudeCode)
        #expect(chosen.model == AppDefaults.fallbackModel)
        #expect(chosen.effort == AppDefaults.fallbackEffort)
        #expect(chosen.reviewBackend == .claudeCode)
    }

    @Test("A model whose server lists no levels never stores an empty one")
    func modelWithoutLevels() throws {
        let bare: [AgentKind: [AgentModel]] = [.grok: [AgentModel(id: "grok-5", displayName: "Grok 5")]]
        let chosen = try #require(
            OnboardingAgentChoice.defaults(choosing: .grok, from: AppDefaults(), models: bare)
        )
        #expect(chosen.model == "grok-5")
        #expect(!chosen.effort.isEmpty)
        #expect(chosen.effort == AppDefaults.fallbackEffort)
    }
}
