import Foundation
import Testing
@testable import Core

@Suite("A caller that cannot leave its own profile is told why", .tags(.persistence), .scratchDirectory)
struct BridgeProfileOwnClosedTests {
    static func world(_ label: String) async throws -> ProfileReachWorld {
        let w = try await ProfileReachWorld.make(label)
        try await w.open(w.akira)
        return w
    }

    static func list(_ w: ProfileReachWorld, as identity: BridgeIdentity, profile: String) async -> BridgeToolResult {
        await ProjectListTool().call(w.world.request("project_list", ["profile": .string(profile)]), as: identity, store: w.store)
    }

    @Test("an orchestrator whose own profile is closed is told so, for all, a real profile and an invented one")
    func orchestratorOwnClosed() async throws {
        let w = try await Self.world("own-closed-lead")
        let ownClosed = BridgeProfileTrouble.ownProfileClosed(own: "Unified").sentence

        for answer in [
            await Self.list(w, as: w.lead, profile: "all"),
            await Self.list(w, as: w.lead, profile: "Akira"),
            await Self.list(w, as: w.lead, profile: "Invented"),
            await w.say(as: w.lead, profile: "Akira"),
            await w.say(as: w.lead, profile: "Invented"),
        ] {
            #expect(answer.isError)
            #expect(answer.text.contains(ownClosed), "\(answer.text)")
            #expect(!answer.text.contains("Akira"))
            #expect(!answer.text.contains(ProfileScopeWorld.farProjectName))
        }
        #expect(w.window.sent.isEmpty)
    }

    @Test("an ordinary workspace chat whose own profile is closed is told so too")
    func workspaceOwnClosed() async throws {
        let w = try await Self.world("own-closed-workspace")
        let answer = await Self.list(w, as: w.world.homeAgent, profile: "all")
        #expect(answer.text.contains(BridgeProfileTrouble.ownProfileClosed(own: "Unified").sentence))
    }

    @Test("a chat not launched asking is told about its mode when it asks for all")
    func unaskedAll() async throws {
        let w = try await Self.world("own-closed-unasked")
        try await w.open(.initial)
        let workspace = try #require(w.world.homeAgent.workspaceID)
        let chat = try await w.store.upsert(Session(workspaceID: workspace, title: "Bypass", permissionMode: .bypassPermissions))
        let identity = BridgeIdentity(sessionID: chat.id, workspaceID: workspace, role: .workspace)

        let answer = await Self.list(w, as: identity, profile: "all")
        #expect(answer.text.contains(BridgeProfileTrouble.launchedUnasked.sentence), "\(answer.text)")
    }

    @Test("a chat on an agent that never crosses is told so, whatever profile it names")
    func confined() async throws {
        let w = try await Self.world("own-closed-confined")
        try await w.open(.initial)
        let workspace = try #require(w.world.homeAgent.workspaceID)
        let codex = try await w.store.upsert(Session(workspaceID: workspace, title: "Codex", agentKind: .codex))
        let identity = BridgeIdentity(sessionID: codex.id, workspaceID: workspace, role: .workspace)

        let real = await Self.list(w, as: identity, profile: "Akira")
        let invented = await Self.list(w, as: identity, profile: "Invented")
        #expect(real.text.contains(BridgeProfileTrouble.agentConfined.sentence), "\(real.text)")
        #expect(real.text == invented.text)
    }

    @Test("naming the caller's own profile still answers its own projects")
    func ownByName() async throws {
        let w = try await Self.world("own-closed-own-name")
        let answer = await Self.list(w, as: w.lead, profile: "Unified")
        #expect(!answer.isError, "\(answer.text)")
        #expect(answer.text.contains("home-project"))
    }

    @Test("with its own profile open, the lead lists the other through all")
    func ownOpenReaches() async throws {
        let w = try await Self.world("own-closed-open")
        try await w.open(.initial)
        let answer = await Self.list(w, as: w.lead, profile: "all")
        #expect(!answer.isError, "\(answer.text)")
        #expect(answer.text.contains(ProfileScopeWorld.farProjectName))
    }
}
