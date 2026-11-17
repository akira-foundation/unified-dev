import Testing
import Foundation
@testable import Core

@Suite("A profile with accounts of its own never runs on this Mac's login unasked", .tags(.persistence), .scratchDirectory)
struct OwnProfileAccountLaunchTests {
    private let user = URL(filePath: "/Users/someone")

    private var defaultClaude: AgentAccountHome { AgentAccountHome.defaultHome(for: .claudeCode, home: user)! }

    private func account(_ name: String, in profile: ProfileID) throws -> (row: AgentAccountRow, path: String) {
        let path = TestScratch.unique("accounts") + "/" + name
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return (AgentAccountRow(id: AgentAccountID(name), provider: .claudeCode, directory: path, profileID: profile), path)
    }

    private func repo(_ store: Store, in profile: ProfileID) async throws -> Repo {
        try await store.upsert(Repo(name: "site", path: TestScratch.unique("repo"), profileID: profile))
    }

    private func launch(_ store: Store, repo: Repo, profile: ProfileID) async throws -> AgentAccountLaunch {
        let resolution = try await AgentAccountResolver.resolve(
            workspaceID: nil, repoID: repo.id, profileID: profile, store: store, defaults: [defaultClaude]
        )
        return resolution.launch(for: .claudeCode)
    }

    @Test("a profile with accounts of its own and none chosen refuses to start the agent")
    func ownWithNoAccountRefuses() async throws {
        let store = try makeTestStore("own-profile-launch")
        let akira = try await store.createProfile(name: "Akira", colour: Accent.all[1], symbol: "star", accounts: .own)
        let site = try await repo(store, in: akira.id)

        let launch = try await launch(store, repo: site, profile: akira.id)

        #expect(launch == .refused(AgentAccountRefusal(provider: .claudeCode, isChoiceLost: false)))
        #expect(throws: AgentAccountRefusal.self) { try launch.home() }
    }

    @Test("a profile with accounts of its own whose chosen account is gone refuses rather than run the Mac's login")
    func ownWithRemovedAccountRefuses() async throws {
        let store = try makeTestStore("own-profile-launch")
        let akira = try await store.createProfile(name: "Akira", colour: Accent.all[1], symbol: "star", accounts: .own)
        let site = try await repo(store, in: akira.id)
        let client = try account("client", in: akira.id)
        try await store.add(client.row)
        try await store.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(client.row)), forRepo: site.id)
        try FileManager.default.removeItem(atPath: client.path)

        let launch = try await launch(store, repo: site, profile: akira.id)

        #expect(launch == .refused(AgentAccountRefusal(provider: .claudeCode, isChoiceLost: true)))
    }

    @Test("a profile that uses Unified's accounts still runs this Mac's login when nothing is chosen")
    func inheritingFallsBackToTheMac() async throws {
        let store = try makeTestStore("own-profile-launch")
        let heir = try await store.createProfile(name: "Heir", colour: Accent.all[1], symbol: "star", accounts: .inherits)
        let site = try await repo(store, in: heir.id)

        let launch = try await launch(store, repo: site, profile: heir.id)

        #expect(launch == .runs(defaultClaude))
    }

    @Test("Unified itself still runs this Mac's login when nothing is chosen")
    func unifiedFallsBackToTheMac() async throws {
        let store = try makeTestStore("own-profile-launch")
        let site = try await repo(store, in: .initial)

        let launch = try await launch(store, repo: site, profile: .initial)

        #expect(launch == .runs(defaultClaude))
    }

    @Test("a profile with accounts of its own runs the account its project chose")
    func ownWithValidAccountRuns() async throws {
        let store = try makeTestStore("own-profile-launch")
        let akira = try await store.createProfile(name: "Akira", colour: Accent.all[1], symbol: "star", accounts: .own)
        let site = try await repo(store, in: akira.id)
        let client = try account("client", in: akira.id)
        try await store.add(client.row)
        try await store.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(client.row)), forRepo: site.id)

        let launch = try await launch(store, repo: site, profile: akira.id)

        #expect(try launch.home()?.id == client.row.id)
    }

    @Test("a profile with accounts of its own runs its own default where the project chose nothing")
    func ownProfileDefaultRuns() async throws {
        let store = try makeTestStore("own-profile-launch")
        let akira = try await store.createProfile(name: "Akira", colour: Accent.all[1], symbol: "star", accounts: .own)
        let site = try await repo(store, in: akira.id)
        let client = try account("client", in: akira.id)
        try await store.add(client.row)
        try await store.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(client.row)), forProfile: akira.id)

        let launch = try await launch(store, repo: site, profile: akira.id)

        #expect(launch == .runs(AgentAccountHome(client.row)))
    }

    @Test("a valid project choice runs even when the profile's default has gone")
    func aValidProjectChoiceOutlivesALostDefault() async throws {
        let store = try makeTestStore("own-profile-launch")
        let akira = try await store.createProfile(name: "Akira", colour: Accent.all[1], symbol: "star", accounts: .own)
        let site = try await repo(store, in: akira.id)
        let client = try account("client", in: akira.id)
        let spare = try account("spare", in: akira.id)
        for row in [client.row, spare.row] { try await store.add(row) }
        try await store.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(spare.row)), forProfile: akira.id)
        try await store.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(client.row)), forRepo: site.id)
        try FileManager.default.removeItem(atPath: spare.path)

        let launch = try await launch(store, repo: site, profile: akira.id)

        #expect(launch == .runs(AgentAccountHome(client.row)))
    }

    @Test("the home a launch asks for is refused, not the Mac's login, in a profile with accounts of its own")
    func theLaunchHomeIsRefused() async throws {
        let store = try makeTestStore("own-profile-launch")
        let akira = try await store.createProfile(name: "Akira", colour: Accent.all[1], symbol: "star", accounts: .own)
        let site = try await repo(store, in: akira.id)
        let resolution = try await AgentAccountResolver.resolve(
            workspaceID: nil, repoID: site.id, profileID: akira.id, store: store, defaults: [defaultClaude]
        )

        #expect(resolution.home(for: .claudeCode) == defaultClaude)
        #expect(throws: AgentAccountRefusal(provider: .claudeCode, isChoiceLost: false)) {
            try resolution.launchHome(for: .claudeCode)
        }
    }

    @Test("a project of an own profile that chose this Mac's login on purpose runs it")
    func anExplicitMacChoiceRuns() async throws {
        let store = try makeTestStore("own-profile-launch")
        let akira = try await store.createProfile(name: "Akira", colour: Accent.all[1], symbol: "star", accounts: .own)
        let site = try await repo(store, in: akira.id)
        try await AgentAccountAssignment.choose(ChosenAgentAccount(defaultClaude), forRepo: site.id, in: store)

        let launch = try await launch(store, repo: site, profile: akira.id)

        #expect(launch == .runs(defaultClaude))
    }
}

@Suite("Whether an account choice may start an agent")
struct AgentAccountLaunchDecisionTests {
    private let defaultClaude = AgentAccountHome.defaultHome(for: .claudeCode, home: URL(filePath: "/Users/someone"))!

    @Test(
        "an agent that cannot hold accounts starts in an own profile with nothing to choose",
        arguments: [AgentKind.antigravity, .cursor, .openCode]
    )
    func anAgentWithoutAccountsRuns(provider: AgentKind) {
        let choice = AgentAccountChoice(home: nil, reason: .noAccount)

        #expect(AgentAccountLaunch.decide(choice: choice, provider: provider, outsideUnified: true) == .runs(nil))
    }

    @Test("Grok with no account chosen is refused in an own profile rather than run this Mac's login")
    func grokWithNothingChosenIsRefused() {
        let choice = AgentAccountChoice(home: nil, reason: .noAccount)

        #expect(AgentAccountLaunch.decide(choice: choice, provider: .grok, outsideUnified: true)
            == .refused(AgentAccountRefusal(provider: .grok, isChoiceLost: false)))
        #expect(AgentAccountLaunch.decide(choice: choice, provider: .grok, outsideUnified: false) == .runs(nil))
    }

    @Test("a lost choice with nothing left to fall to is refused in an own profile")
    func aLostChoiceWithNothingLeftIsRefused() {
        let choice = AgentAccountChoice(home: nil, reason: .noAccount, isProfileChoiceLost: true)

        #expect(AgentAccountLaunch.decide(choice: choice, provider: .codex, outsideUnified: true)
            == .refused(AgentAccountRefusal(provider: .codex, isChoiceLost: true)))
    }

    @Test("the profile's own source decides, through ProfileAccounts")
    func theSourceDecides() {
        let akira = ProfileID("akira")
        let heir = ProfileID("heir")
        let accounts = ProfileAccounts(sources: [akira: .own, heir: .inherits])
        let choice = AgentAccountChoice(home: defaultClaude, reason: .providerDefault)

        let own = AgentAccountLaunch.decide(choice: choice, provider: .claudeCode, profile: akira, accounts: accounts)
        let inherits = AgentAccountLaunch.decide(choice: choice, provider: .claudeCode, profile: heir, accounts: accounts)
        let unified = AgentAccountLaunch.decide(choice: choice, provider: .claudeCode, profile: .initial, accounts: accounts)
        let none = AgentAccountLaunch.decide(choice: choice, provider: .claudeCode, profile: nil, accounts: accounts)

        #expect(own == .refused(AgentAccountRefusal(provider: .claudeCode, isChoiceLost: false)))
        #expect(inherits == .runs(defaultClaude))
        #expect(unified == .runs(defaultClaude))
        #expect(none == .runs(defaultClaude))
    }

    @Test("the chat is told the refusal itself, not a failure to work out the account")
    func theChatReadsTheRefusal() {
        let refusal = AgentAccountRefusal(provider: .claudeCode, isChoiceLost: false)

        #expect(AgentSessionSettlement.resolutionFailure(refusal) == refusal.description)
        #expect(refusal.description.hasPrefix("Claude Code did not start, because this profile has accounts of its own"))
    }

    @Test("a refusal after a lost choice says the chosen account is not available")
    func aLostRefusalNamesTheLoss() {
        let refusal = AgentAccountRefusal(provider: .codex, isChoiceLost: true)

        #expect(refusal.description == "Codex did not start, because this profile has accounts of its own and "
            + "the Codex account chosen for it is not available. "
            + "Choose one for the project, or a default for the profile in Profile Settings.")
        #expect(refusal.beforeStarting.hasPrefix("Codex does not start here, because"))
    }

    @Test("any other failure to resolve still reads as one")
    func anotherFailureIsWrapped() {
        let failure = CocoaError(.fileReadNoSuchFile)

        #expect(AgentSessionSettlement.resolutionFailure(failure)
            == AgentSessionSettlement.resolutionFailure(failure.readableMessage))
    }
}
