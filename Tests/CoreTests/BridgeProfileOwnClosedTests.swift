import Foundation
import Testing
@testable import Core

@Suite("A profile closed to others still reaches out to the open ones", .tags(.persistence), .scratchDirectory)
struct BridgeProfileOwnClosedTests {
    static func world(_ label: String) async throws -> ProfileReachWorld {
        let w = try await ProfileReachWorld.make(label)
        try await w.open(w.akira)
        return w
    }

    static func list(_ w: ProfileReachWorld, as identity: BridgeIdentity, profile: String) async -> BridgeToolResult {
        await ProjectListTool().call(w.world.request("project_list", ["profile": .string(profile)]), as: identity, store: w.store)
    }

    @Test("an orchestrator whose own profile is closed lists all, names the open one and sends to it")
    func orchestratorLeavesClosedOwn() async throws {
        let w = try await Self.world("own-closed-lead")

        let every = await Self.list(w, as: w.lead, profile: "all")
        let named = await Self.list(w, as: w.lead, profile: "Akira")
        let told = await w.say(as: w.lead, profile: "Akira")

        #expect(every.text.contains(ProfileScopeWorld.farProjectName), "\(every.text)")
        #expect(every.text.contains("home-project"))
        #expect(named.text.contains(ProfileScopeWorld.farProjectName), "\(named.text)")
        #expect(!told.isError, "\(told.text)")
        #expect(w.window.sent.map(\.target.workspaceID) == [w.world.farWorkspace.id])
    }

    @Test("an ordinary chat launched asking whose own profile is closed lists the open one")
    func workspaceLeavesClosedOwn() async throws {
        let w = try await Self.world("own-closed-workspace")
        let answer = await Self.list(w, as: w.world.homeAgent, profile: "all")
        #expect(answer.text.contains(ProfileScopeWorld.farProjectName), "\(answer.text)")
    }

    @Test("nobody reaches into a closed profile from it, and the refusal reads as an invented one does")
    func closedOwnStaysClosedToOthers() async throws {
        let w = try await Self.world("own-closed-inbound")
        let farLead = BridgeIdentity(
            sessionID: try #require(w.world.farAgent.sessionID), workspaceID: w.world.farWorkspace.id, role: .workspace,
            launchedAsking: true
        )

        let real = await Self.list(w, as: farLead, profile: "Unified")
        let invented = await Self.list(w, as: farLead, profile: "Invented")

        #expect(real.text.contains(BridgeProfileTrouble.unreachable(given: "Unified").sentence), "\(real.text)")
        #expect(invented.text.contains(BridgeProfileTrouble.unreachable(given: "Invented").sentence))
        #expect(real.isError && invented.isError)
        #expect(!real.text.contains("home-project"))
    }

    @Test("a chat not launched asking is told about its mode, for all and for any name alike")
    func unasked() async throws {
        let w = try await Self.world("own-closed-unasked")
        let workspace = try #require(w.world.homeAgent.workspaceID)
        let chat = try await w.store.upsert(Session(workspaceID: workspace, title: "Bypass", permissionMode: .bypassPermissions))
        let identity = BridgeIdentity(sessionID: chat.id, workspaceID: workspace, role: .workspace)

        for given in ["all", "Akira", "Invented"] {
            let answer = await Self.list(w, as: identity, profile: given)
            #expect(answer.text.contains(BridgeProfileTrouble.launchedUnasked.sentence), "\(answer.text)")
            #expect(!answer.text.contains(given == "all" ? "Akira" : given))
        }
    }

    @Test("a chat on an agent that never crosses is told so, whatever profile it names")
    func confined() async throws {
        let w = try await Self.world("own-closed-confined")
        let workspace = try #require(w.world.homeAgent.workspaceID)
        let codex = try await w.store.upsert(Session(workspaceID: workspace, title: "Codex", agentKind: .codex))
        let identity = BridgeIdentity(sessionID: codex.id, workspaceID: workspace, role: .workspace)

        let real = await Self.list(w, as: identity, profile: "Akira")
        let invented = await Self.list(w, as: identity, profile: "Invented")
        #expect(real.text.contains(BridgeProfileTrouble.agentConfined.sentence), "\(real.text)")
        #expect(real.text == invented.text)
    }

    @Test("naming the caller's own profile answers its own projects even from a confined chat")
    func ownByName() async throws {
        let w = try await Self.world("own-closed-own-name")
        let workspace = try #require(w.world.homeAgent.workspaceID)
        let codex = try await w.store.upsert(Session(workspaceID: workspace, title: "Codex", agentKind: .codex))
        let identity = BridgeIdentity(sessionID: codex.id, workspaceID: workspace, role: .workspace)

        let answer = await Self.list(w, as: identity, profile: "Unified")
        #expect(!answer.isError, "\(answer.text)")
        #expect(answer.text.contains("home-project"))
    }
}
