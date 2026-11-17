import Testing
import Foundation
@testable import Core

@Suite("Profile agent accounts in the store", .tags(.persistence), .scratchDirectory)
struct ProfileAgentAccountStoreTests {
    private let user = URL(filePath: "/Users/someone")

    private var defaultClaude: AgentAccountHome { AgentAccountHome.defaultHome(for: .claudeCode, home: user)! }

    private func account(
        _ name: String, _ provider: AgentKind = .claudeCode, in profile: ProfileID = .initial
    ) throws -> AgentAccountRow {
        let path = TestScratch.unique("accounts") + "/" + name
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return AgentAccountRow(id: AgentAccountID(name), provider: provider, directory: path, profileID: profile)
    }

    private func seed(_ store: Store, in profile: ProfileID) async throws -> (repo: Repo, workspace: Workspace) {
        let repo = try await store.upsert(Repo(name: "r", path: TestScratch.unique("repo"), profileID: profile))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "billing", branch: "feature/w",
            path: TestScratch.unique("worktree"), baseBranch: "main"
        ))
        return (repo, workspace)
    }

    @Test("a profile's choice is what a workspace with no choice of its own runs")
    func aWorkspaceFollowsItsProfile() async throws {
        let store = try makeTestStore("profile-accounts")
        let akira = try await store.createProfile(name: "Akira", colour: Accent.all[1], symbol: "star")
        let (repo, workspace) = try await seed(store, in: akira.id)
        let client = try account("client", in: akira.id)
        try await store.add(client)
        try await store.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(client)), forProfile: akira.id)

        let choice = try await AgentAccountResolver.resolve(
            workspaceID: workspace.id, repoID: repo.id, store: store, defaults: [defaultClaude]
        ).choice(for: .claudeCode)

        #expect(choice.home?.id == client.id)
        #expect(choice.reason == .profile)
    }

    @Test("another profile's choice never reaches a project outside it")
    func anotherProfilesChoiceStaysThere() async throws {
        let store = try makeTestStore("profile-accounts")
        let akira = try await store.createProfile(name: "Akira", colour: Accent.all[1], symbol: "star")
        let (repo, workspace) = try await seed(store, in: .initial)
        let client = try account("client", in: akira.id)
        try await store.add(client)
        try await store.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(client)), forProfile: akira.id)

        let choice = try await AgentAccountResolver.resolve(
            workspaceID: workspace.id, repoID: repo.id, profileID: akira.id, store: store, defaults: [defaultClaude]
        ).choice(for: .claudeCode)

        #expect(choice.home?.id == defaultClaude.id)
        #expect(choice.reason == .providerDefault)
    }

    @Test("with no project in view, the active profile's choice is the one resolved")
    func homeResolvesTheActiveProfile() async throws {
        let store = try makeTestStore("profile-accounts")
        let akira = try await store.createProfile(name: "Akira", colour: Accent.all[1], symbol: "star")
        let client = try account("client", in: akira.id)
        try await store.add(client)
        try await store.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(client)), forProfile: akira.id)

        let onAkira = try await AgentAccountResolver.resolve(
            workspaceID: nil, repoID: nil, profileID: akira.id, store: store, defaults: [defaultClaude]
        )
        let onUnified = try await AgentAccountResolver.resolve(
            workspaceID: nil, repoID: nil, profileID: .initial, store: store, defaults: [defaultClaude]
        )

        #expect(onAkira.home(for: .claudeCode)?.id == client.id)
        #expect(onUnified.home(for: .claudeCode)?.id == defaultClaude.id)
    }

    @Test("a moved project loses a choice its new profile does not hold and runs that profile's default")
    func movingClearsAChoiceFromTheOldProfile() async throws {
        let store = try makeTestStore("profile-accounts")
        let akira = try await store.createProfile(name: "Akira", colour: Accent.all[1], symbol: "star")
        let debtges = try await store.createProfile(name: "Debtges", colour: Accent.all[2], symbol: "leaf")
        let (repo, workspace) = try await seed(store, in: akira.id)
        let akiraClaude = try account("akira-claude", in: akira.id)
        let debtgesClaude = try account("debtges-claude", in: debtges.id)
        for row in [akiraClaude, debtgesClaude] { try await store.add(row) }
        try await store.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(akiraClaude)), forRepo: repo.id)
        try await store.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(debtgesClaude)), forProfile: debtges.id)

        _ = try await store.move(repoID: repo.id, to: debtges.id)
        let choice = try await AgentAccountResolver.resolve(
            workspaceID: workspace.id, repoID: repo.id, store: store, defaults: [defaultClaude]
        ).choice(for: .claudeCode)

        #expect(try await store.agentAccountChoices().repos[repo.id] == nil)
        #expect(choice.home?.id == debtgesClaude.id)
        #expect(choice.reason == .profile)
    }

    @Test("a project moved into a profile that inherits keeps a choice of Unified's accounts")
    func movingIntoAnInheritingProfileKeepsUnifiedChoices() async throws {
        let store = try makeTestStore("profile-accounts")
        let heir = try await store.createProfile(name: "Heir", colour: Accent.all[1], symbol: "star", accounts: .inherits)
        let (repo, _) = try await seed(store, in: .initial)
        let shared = try account("shared")
        try await store.add(shared)
        try await store.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(shared)), forRepo: repo.id)

        _ = try await store.move(repoID: repo.id, to: heir.id)

        #expect(try await store.agentAccountChoices().repos[repo.id] == [.claudeCode: shared.id])
    }

    @Test("a profile that starts using its own accounts clears its projects' choices of Unified's")
    func turningToOwnAccountsClearsUnifiedChoices() async throws {
        let store = try makeTestStore("profile-accounts")
        let heir = try await store.createProfile(name: "Heir", colour: Accent.all[1], symbol: "star", accounts: .inherits)
        let (repo, _) = try await seed(store, in: heir.id)
        let shared = try account("shared")
        let lab = try account("lab", .codex, in: heir.id)
        for row in [shared, lab] { try await store.add(row) }
        try await store.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(shared)), forRepo: repo.id)
        try await store.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(lab)), forRepo: repo.id)

        let cleared = try await store.setAccountSource(.own, for: heir.id)

        #expect(cleared == [repo.id])
        #expect(try await store.agentAccountChoices().repos[repo.id] == [.codex: lab.id])
        #expect(try await store.profileAccounts().source(of: heir.id) == .own)
    }

    @Test("Unified always has accounts of its own")
    func unifiedCannotInherit() async throws {
        let store = try makeTestStore("profile-accounts")
        try await store.setAccountSource(.inherits, for: .initial)
        #expect(try await store.profileAccounts().source(of: .initial) == .own)
    }

    @Test("a profile's choice goes with the account and with the profile")
    func choicesCascade() async throws {
        let store = try makeTestStore("profile-accounts")
        let akira = try await store.createProfile(name: "Akira", colour: Accent.all[1], symbol: "star")
        let debtges = try await store.createProfile(name: "Debtges", colour: Accent.all[2], symbol: "leaf")
        let client = try account("client", in: akira.id)
        let lab = try account("lab", .codex, in: debtges.id)
        try await store.add(client)
        try await store.add(lab)
        try await store.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(client)), forProfile: akira.id)
        try await store.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(lab)), forProfile: debtges.id)

        try await store.forgetAgentAccount(client.id)
        try await store.deleteProfile(id: debtges.id)

        #expect(try await store.agentAccountChoices().profiles.isEmpty)
        #expect(try await store.agentAccounts().map(\.id) == [lab.id])
        #expect(try await store.agentAccounts().first?.profileID == .initial)
    }

    @Test("choosing the profile's own default clears its row for that agent only")
    func inheritingClearsOneAgent() async throws {
        let store = try makeTestStore("profile-accounts")
        let akira = try await store.createProfile(name: "Akira", colour: Accent.all[1], symbol: "star")
        let client = try account("client", in: akira.id)
        let lab = try account("lab", .codex, in: akira.id)
        try await store.add(client)
        try await store.add(lab)
        try await store.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(client)), forProfile: akira.id)
        try await store.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(lab)), forProfile: akira.id)

        try await store.chooseAgentAccount(ChosenAgentAccount(inheritedBy: .claudeCode), forProfile: akira.id)

        #expect(try await store.agentAccountChoices().profiles[akira.id] == [.codex: lab.id])
    }

    @Test("an account the profile runs blocks its removal while an agent runs on it")
    func aProfileAccountInUseIsSeen() async throws {
        let store = try makeTestStore("profile-accounts")
        let akira = try await store.createProfile(name: "Akira", colour: Accent.all[1], symbol: "star")
        let (_, workspace) = try await seed(store, in: akira.id)
        let client = try account("client", in: akira.id)
        try await store.add(client)
        try await store.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(client)), forProfile: akira.id)
        var session = Session(workspaceID: workspace.id)
        session.apply(.turnStarted)
        try await store.upsert(session)

        let users = try await AgentAccountUsage.runningWorkspaces(
            under: AgentAccountHome(client), store: store, defaults: [defaultClaude]
        )

        #expect(users == ["billing"])
    }

    @Test("a database from before profile accounts gains them, each account in the profile that chose it")
    func theMigrationIsAdditiveAndPlacesAccounts() async throws {
        let path = TestScratch.unique("profile-accounts-migration") + ".sqlite"
        let first = try Store(path: path)
        let akira = try await first.createProfile(name: "Akira", colour: Accent.all[1], symbol: "star")
        let empty = try await first.createProfile(name: "Empty", colour: Accent.all[2], symbol: "leaf")
        let unified = try await first.upsert(Repo(name: "u", path: TestScratch.unique("repo")))
        let site = try await first.upsert(Repo(name: "site", path: TestScratch.unique("repo"), profileID: akira.id))
        let client = try account("client")
        let both = try account("both")
        let idle = try account("idle")
        for row in [client, both, idle] { try await first.add(row) }
        try await first.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(client)), forRepo: site.id)
        try await first.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(both)), forRepo: unified.id)
        let raw = try SQLiteDatabase(path: path)
        let version = try raw.readUserVersion()
        try raw.execute("DROP TABLE profile_agent_accounts;")
        try raw.execute("ALTER TABLE profiles DROP COLUMN account_source;")
        try raw.execute("ALTER TABLE agent_accounts DROP COLUMN profile_id;")
        try raw.setUserVersion(version - 7)

        let reopened = try Store(path: path)
        let owners = Dictionary(uniqueKeysWithValues: try await reopened.agentAccounts().map { ($0.id, $0.profileID) })
        let accounts = try await reopened.profileAccounts()

        #expect(owners == [client.id: akira.id, both.id: .initial, idle.id: .initial])
        #expect(accounts.source(of: akira.id) == .own)
        #expect(accounts.source(of: empty.id) == .inherits)
        #expect(try await reopened.agentAccountChoices().repos[site.id] == [.claudeCode: client.id])
        #expect(try SQLiteDatabase(path: path).readUserVersion() == version)
    }

    @Test("writing a profile's choice is heard by whoever watches projects and their accounts")
    func aProfileChoiceIsObserved() {
        #expect(StoreDomain.projectsWorkspacesAndTheirAccounts.contains(.profileAgentAccounts))
        #expect(StoreDomain(rawValue: AgentAccountChoiceColumns.profiles.name) == .profileAgentAccounts)
    }
}
