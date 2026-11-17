import Foundation
import Testing
@testable import Core

@Suite("A workspace crosses profiles only from a chat launched asking the owner", .tags(.persistence), .scratchDirectory)
struct BridgeProfileAskingModeTests {
    typealias Reach = BridgeProfileOrchestratorReachTests

    static func launched(_ far: Reach.Far, asking: Bool) throws -> BridgeIdentity {
        let home = far.w.world.homeAgent
        return BridgeIdentity(
            sessionID: try #require(home.sessionID), workspaceID: try #require(home.workspaceID), role: .workspace,
            launchedAsking: asking
        )
    }

    @Test("only Accept edits asks before every bridge call for the life of the process", arguments: PermissionMode.allCases)
    func askingModes(_ mode: PermissionMode) {
        #expect(BridgeProfileReach.asksTheOwner(mode) == (mode == .acceptEdits))
    }

    @Test("the bridge token records whether the chat launched in a mode that asks", arguments: PermissionMode.allCases)
    func tokenRecordsTheLaunch(_ mode: PermissionMode) async throws {
        let store = try makeTestStore("asking-token-\(mode.rawValue)")
        let repo = try await store.upsert(Repo(name: "r", path: TestScratch.unique("asking-token")))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "w", branch: "b", path: TestScratch.unique("asking-token-tree"), baseBranch: "main"
        ))
        let session = try await store.upsert(Session(workspaceID: workspace.id, title: "c", permissionMode: mode))
        let server = try BridgeServer(store: store)

        let token = server.attach(session: session, workspace: workspace, shimPath: "/tmp/bridge").token

        #expect(server.registry.identity(forToken: token)?.launchedAsking == BridgeProfileReach.asksTheOwner(session.permissionMode))
        let lead = server.attach(session: session, workspace: workspace, shimPath: "/tmp/bridge", orchestrates: true).token
        #expect(server.registry.identity(forToken: lead)?.launchedAsking == true)
    }

    @Test("a chat launched without asking is told why, and nothing is sent or left as a card, whatever its row says now")
    func unaskedIsRefused() async throws {
        let far = try await Reach.world("asking-unasked", withOrchestrator: false)
        let session = try #require(far.w.world.homeAgent.sessionID)
        try await far.w.store.updateSessionPreferences(id: session, permissionMode: .acceptEdits)
        let identity = try Self.launched(far, asking: false)

        #expect(try await BridgeProfileReach.caller(of: identity, store: far.w.store) == .unasked)
        let told = await Reach.say(far, as: identity, ["project": .string(ProfileScopeWorld.farProjectName)])
        let listed = await ProjectListTool().call(
            far.w.world.request("project_list", ["profile": .string("Akira")]), as: identity, store: far.w.store
        )

        #expect(told.isError)
        #expect(told.text.contains(BridgeProfileTrouble.asksNobody(given: "Akira").sentence))
        #expect(listed.text.contains(BridgeProfileTrouble.asksNobody(given: "Akira").sentence))
        #expect(!listed.text.contains(ProfileScopeWorld.farProjectName))
        #expect(far.window.sent.isEmpty)
        #expect(try await far.w.store.workSuggestions(sessionID: session).isEmpty)
    }

    @Test("a chat launched asking still crosses after its row moves to a mode that would not, until it starts again")
    func launchDecides() async throws {
        let far = try await Reach.world("asking-launch")
        let session = try #require(far.w.world.homeAgent.sessionID)
        try await far.w.store.updateSessionPreferences(id: session, permissionMode: .bypassPermissions)

        let told = await Reach.say(far, as: try Self.launched(far, asking: true), [
            "workspace": .string(far.orchestrator.id.rawValue),
        ])

        #expect(!told.isError)
        #expect(far.window.sent.map(\.target.workspaceID) == [far.orchestrator.id])
    }

    @Test("a profile that does not exist is answered as before, so the refusal reveals nothing new")
    func unaskedInventedProfile() async throws {
        let far = try await Reach.world("asking-invented")
        let listed = await ProjectListTool().call(
            far.w.world.request("project_list", ["profile": .string("Invented")]),
            as: try Self.launched(far, asking: false), store: far.w.store
        )
        #expect(listed.text.contains(BridgeProfileTrouble.unreachable(given: "Invented").sentence))
    }

    @Test("an ordinary workspace on Grok does not cross, because its approvals cover a whole tool")
    func grokOrdinaryConfined() async throws {
        let far = try await Reach.world("asking-grok")
        let workspace = try #require(far.w.world.homeAgent.workspaceID)
        let grok = try await far.w.store.upsert(Session(
            workspaceID: workspace, title: "Grok", agentKind: .grok, permissionMode: .acceptEdits
        ))
        let identity = BridgeIdentity(sessionID: grok.id, workspaceID: workspace, role: .workspace, launchedAsking: true)

        #expect(try await BridgeProfileReach.caller(of: identity, store: far.w.store) == .confined)
        let told = await Reach.say(far, as: identity, ["workspace": .string(far.orchestrator.id.rawValue)])
        #expect(told.text.contains(BridgeProfileTrouble.unreachable(given: "Akira").sentence))
        #expect(far.window.sent.isEmpty)
    }

    @Test("an orchestrator crosses whatever the chat's mode says, because it always launches asking")
    func orchestratorIgnoresMode() async throws {
        let far = try await Reach.world("asking-lead")
        let session = try #require(far.w.lead.sessionID)
        try await far.w.store.updateSessionPreferences(id: session, permissionMode: .bypassPermissions)
        #expect(try await BridgeProfileReach.caller(of: far.w.lead, store: far.w.store) == .orchestrator)
    }

    @Test("an ordinary chat that asks launches with the crossing tools set to ask, so a rule of the owner's cannot skip the card")
    func crossingToolsAsk() throws {
        let workspace = Session(workspaceID: WorkspaceID("w"), title: "c", permissionMode: .acceptEdits)
        let arguments = AgentRunner.argv(session: workspace, resume: nil)
        let settings = try #require(arguments.firstIndex(of: "--settings").map { arguments[$0 + 1] })
        let asked = JSONValue.parse(settings)?["permissions"]?["ask"]

        #expect(asked == .array(BridgeToolApproval.crossingTools.map { .string(BridgeToolApproval.toolPrefix + $0) }))
        #expect(!AgentRunner.argv(session: Session(workspaceID: nil, title: "Ask", permissionMode: .acceptEdits), resume: nil).contains("--settings"))
        for mode in [PermissionMode.bypassPermissions, .plan, .auto] {
            let unasked = Session(workspaceID: WorkspaceID("w"), title: "c", permissionMode: mode)
            #expect(!AgentRunner.argv(session: unasked, resume: nil).contains("--settings"))
        }
    }
}
