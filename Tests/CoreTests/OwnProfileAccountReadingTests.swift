import Testing
import Foundation
@testable import Core

@Suite("A profile with accounts of its own reads nothing under this Mac's login unasked", .tags(.persistence), .scratchDirectory)
struct OwnProfileAccountReadingTests {
    private let user = URL(filePath: "/Users/someone")

    private var defaultClaude: AgentAccountHome { AgentAccountHome.defaultHome(for: .claudeCode, home: user)! }

    private func resolution(
        _ accounts: ProfileAccountSource,
        choosing chosen: ((Store, Repo, ProfileID) async throws -> Void)? = nil
    ) async throws -> AgentAccountResolution {
        let store = try makeTestStore("own-profile-reading")
        let profile = try await store.createProfile(name: "Akira", colour: Accent.all[1], symbol: "star", accounts: accounts)
        let site = try await store.upsert(Repo(name: "site", path: TestScratch.unique("repo"), profileID: profile.id))
        try await chosen?(store, site, profile.id)
        return try await AgentAccountResolver.resolve(
            workspaceID: nil, repoID: site.id, profileID: profile.id, store: store, defaults: [defaultClaude]
        )
    }

    private func chooseClient(_ store: Store, _ site: Repo, _ profile: ProfileID) async throws -> String {
        let path = TestScratch.unique("accounts") + "/client"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        let row = AgentAccountRow(id: AgentAccountID("client"), provider: .claudeCode, directory: path, profileID: profile)
        try await store.add(row)
        try await store.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(row)), forRepo: site.id)
        return path
    }

    private func chooseClientThenLoseIt(_ store: Store, _ site: Repo, _ profile: ProfileID) async throws {
        try FileManager.default.removeItem(atPath: try await chooseClient(store, site, profile))
    }

    private func quotaHolders(_ resolution: AgentAccountResolution) -> [QuotaHolder] {
        AgentQuotaSources.all(accounts: resolution.homes, refusing: resolution.refusedProviders).map(\.holder)
    }

    @Test("only the agent this profile refuses to start is left unread")
    func onlyTheRefusedAgentIsLeftUnread() async throws {
        let own = try await resolution(.own)
        let sources = AgentModelSource.live(accounts: own.homes, refusing: own.refusedProviders)

        #expect(own.refusedProviders.contains(.claudeCode))
        #expect(!own.refusedProviders.contains(.antigravity))
        #expect(quotaHolders(own).contains { $0.provider == .antigravity })
        #expect(QuotaScope(homes: own.homes, refusing: own.refusedProviders).holders[.antigravity] != nil)
        #expect(sources[.antigravity] != nil)
    }

    @Test("an agent whose chosen account has gone is not read under the Mac's login either")
    func aLostChoiceIsNotReadUnderTheMac() async throws {
        let own = try await resolution(.own, choosing: chooseClientThenLoseIt)

        #expect(own.refusedProviders.contains(.claudeCode))
        #expect(!quotaHolders(own).contains { $0.provider == .claudeCode })
        #expect(AgentModelSource.live(accounts: own.homes, refusing: own.refusedProviders)[.claudeCode] == nil)
    }

    @Test("no quota is read for an agent this profile refuses, though the Mac's login is there to read")
    func noQuotaSourceForARefusedAgent() async throws {
        let own = try await resolution(.own)

        #expect(own.home(for: .claudeCode) == defaultClaude)
        #expect(!quotaHolders(own).contains { $0.provider == .claudeCode })
    }

    @Test("the quota scope holds no reading of the Mac's login for a refused agent")
    func scopeHoldsNoRefusedAgent() async throws {
        let own = try await resolution(.own)
        let scope = QuotaScope(homes: own.homes, refusing: own.refusedProviders)

        #expect(scope.holders[.claudeCode] == nil)
    }

    @Test("no model list is asked of an agent this profile refuses")
    func noModelSourceForARefusedAgent() async throws {
        let own = try await resolution(.own)
        let sources = AgentModelSource.live(accounts: own.homes, refusing: own.refusedProviders)

        #expect(sources[.claudeCode] == nil)
    }

    @Test("the account a project of an own profile chose is read for quota and models")
    func aChosenAccountIsRead() async throws {
        let own = try await resolution(.own, choosing: { _ = try await chooseClient($0, $1, $2) })
        let sources = AgentModelSource.live(accounts: own.homes, refusing: own.refusedProviders)

        #expect(!own.refusedProviders.contains(.claudeCode))
        #expect(quotaHolders(own).contains(QuotaHolder(provider: .claudeCode, account: AgentAccountID("client"))))
        #expect(sources[.claudeCode] != nil)
    }

    @Test("a profile that uses Unified's accounts still reads this Mac's login")
    func inheritingStillReadsTheMac() async throws {
        let heir = try await resolution(.inherits)

        #expect(!heir.refusedProviders.contains(.claudeCode))
        #expect(quotaHolders(heir).contains(QuotaHolder(provider: .claudeCode, home: defaultClaude)))
        #expect(QuotaScope(homes: heir.homes, refusing: heir.refusedProviders).holders[.claudeCode] != nil)
    }
}
