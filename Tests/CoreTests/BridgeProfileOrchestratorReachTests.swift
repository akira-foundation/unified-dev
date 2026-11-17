import Foundation
import Testing
@testable import Core

@Suite("Any workspace reaches another profile through its orchestrator", .tags(.persistence), .scratchDirectory)
struct BridgeProfileOrchestratorReachTests {
    struct Far {
        let w: ProfileReachWorld
        let orchestrator: Workspace
        let window: WorkspaceSayWindow
    }

    static func world(_ label: String, withOrchestrator: Bool = true) async throws -> Far {
        let w = try await ProfileReachWorld.make(label)
        try await w.open(.initial, w.akira)
        let far = try await w.store.upsert(Workspace(
            repoID: w.world.farProject.id, name: "Far Lead", branch: "far-lead",
            path: TestScratch.unique("far-lead"), baseBranch: "main"
        ))
        if withOrchestrator { _ = try await w.store.setOrchestrator(true, workspaceID: far.id) }
        let chat = try await w.store.upsert(Session(workspaceID: far.id, title: "Far Lead Chat"))
        let orchestrator = try #require(try await w.store.workspace(id: far.id))
        return Far(w: w, orchestrator: orchestrator, window: WorkspaceSayWindow(store: w.store, chats: [far.id: chat]))
    }

    static func say(_ far: Far, as identity: BridgeIdentity, _ target: [String: JSONValue]) async -> BridgeToolResult {
        var arguments = target
        arguments["message"] = .string("The invoice export is broken.")
        arguments["profile"] = .string("Akira")
        return await far.window.tool().call(far.w.world.request("workspace_say", arguments), as: identity, store: far.w.store)
    }

    @Test("an ordinary workspace and a subagent talk to the orchestrator there")
    func ordinaryTalksToOrchestrator() async throws {
        let far = try await Self.world("orch-reach-talk")
        for identity in [far.w.world.homeAgent, far.w.subagent] {
            let told = await Self.say(far, as: identity, ["workspace": .string(far.orchestrator.id.rawValue)])
            #expect(!told.isError)
        }
        #expect(far.window.sent.count == 2)
        #expect(far.window.sent.allSatisfy { $0.target.workspaceID == far.orchestrator.id })
    }

    @Test("naming the project reaches its orchestrator")
    func projectNamesOrchestrator() async throws {
        let far = try await Self.world("orch-reach-project")
        let told = await Self.say(far, as: far.w.world.homeAgent, ["project": .string(ProfileScopeWorld.farProjectName)])
        #expect(!told.isError)
        #expect(far.window.sent.first?.target.workspaceID == far.orchestrator.id)
    }

    @Test("the receiver sees where it came from, fenced and without the owner's authority")
    func receiverSeesOrigin() async throws {
        let far = try await Self.world("orch-reach-envelope")
        let told = await Self.say(far, as: far.w.world.homeAgent, ["workspace": .string(far.orchestrator.id.rawValue)])
        #expect(!told.isError)
        let chat = try #require(try await far.w.store.sessions(workspaceID: far.orchestrator.id).first)
        let delivered = try #require(try await far.w.store.pendingDeliveries(sessionID: chat.id).first?.crewMessage)
        let envelope = delivered.sent
        let fenced = try #require(envelope.range(of: BridgeUntrustedText.opening))
        let closing = try #require(envelope.range(of: BridgeUntrustedText.closing, range: fenced.upperBound..<envelope.endIndex))
        let inside = String(envelope[fenced.upperBound..<closing.lowerBound])
        #expect(inside.contains("home-project"))
        #expect(inside.contains("Home Workspace"))
        #expect(envelope.contains(far.w.world.homeWorkspace.id.rawValue))
        #expect(envelope.contains("in the profile \"Unified\""))
        #expect(envelope.contains("does not carry the owner's authority"))
    }

    @Test("an ordinary workspace sees only orchestrators in workspace_list")
    func listShowsOrchestrators() async throws {
        let far = try await Self.world("orch-reach-list")
        let listed = await WorkspaceListTool().call(
            far.w.world.request("workspace_list", ["profile": .string("Akira")]), as: far.w.world.homeAgent, store: far.w.store
        )
        #expect(!listed.isError)
        #expect(listed.text.contains(far.orchestrator.id.rawValue))
        #expect(!listed.text.contains(far.w.world.farWorkspace.id.rawValue))
        let projects = await ProjectListTool().call(
            far.w.world.request("project_list", ["profile": .string("Akira")]), as: far.w.world.homeAgent, store: far.w.store
        )
        #expect(projects.text.contains(ProfileScopeWorld.farProjectName))
    }

    @Test("a message to another workspace there is refused like one that does not exist, and points at the orchestrators")
    func otherWorkspaceLooksAbsent() async throws {
        let far = try await Self.world("orch-reach-pointer")
        let other = await Self.say(far, as: far.w.world.homeAgent, ["workspace": .string(far.w.world.farWorkspace.id.rawValue)])
        let invented = await Self.say(far, as: far.w.world.homeAgent, ["workspace": .string("invented")])
        #expect(other.isError)
        #expect(other.text.contains("workspace_list"))
        #expect(!other.text.contains(ProfileScopeWorld.farProjectName))
        #expect(!invented.text.contains(far.orchestrator.id.rawValue))
        #expect(
            other.text.replacingOccurrences(of: far.w.world.farWorkspace.id.rawValue, with: "X")
                == invented.text.replacingOccurrences(of: "invented", with: "X")
        )
        #expect(far.window.sent.isEmpty)
        let lead = await Self.say(far, as: far.w.lead, ["workspace": .string(far.w.world.farWorkspace.id.rawValue)])
        #expect(!lead.text.contains("reached through its projects' orchestrators"))
        #expect(lead.text.contains("could not put it in that workspace's chat"))
    }

    @Test("naming both a workspace and a project is refused, and so is a project that is not there")
    func workspaceAndProject() async throws {
        let far = try await Self.world("orch-reach-both")
        let both = await Self.say(far, as: far.w.world.homeAgent, [
            "workspace": .string(far.orchestrator.id.rawValue), "project": .string(ProfileScopeWorld.farProjectName),
        ])
        #expect(both.text.contains(WorkspaceSayTrouble.workspaceAndProject.sentence))
        let missing = await Self.say(far, as: far.w.world.homeAgent, ["project": .string("home-project")])
        #expect(missing.text.contains(WorkspaceSayTrouble.unknownProject(given: "home-project").sentence))
        #expect(far.window.sent.isEmpty)
    }

    @Test("an ordinary workspace's own list holds only orchestrators, by id, name and project")
    func ownListIsBrief() async throws {
        let far = try await Self.world("orch-reach-own-list")
        let listed = await WorkspaceListTool().call(
            far.w.world.request("workspace_list"), as: far.w.world.homeAgent, store: far.w.store
        )
        #expect(listed.text.contains(try #require(far.w.lead.workspaceID).rawValue))
        #expect(!listed.text.contains(far.w.world.homeWorkspace.id.rawValue))
        #expect(!listed.text.contains("\"path\""))
        #expect(!listed.text.contains("\"sessions\""))
        let owners = await WorkspaceListTool().call(far.w.world.request("workspace_list"), as: .owner, store: far.w.store)
        #expect(owners.text.contains(far.w.world.homeWorkspace.id.rawValue))
    }

    @Test("an owner connection with no chat cannot leave a card")
    func ownerWithoutChat() async throws {
        let far = try await Self.world("orch-reach-no-chat", withOrchestrator: false)
        let told = await Self.say(far, as: .owner, ["project": .string(ProfileScopeWorld.farProjectName)])
        #expect(told.text.contains(WorkspaceSayTrouble.noChatForCard.sentence))
    }

    @Test("reads there are refused and pointed at the orchestrator", arguments: ["chat_list", "chat_read", "workspace_diff"])
    func readsPointAtOrchestrator(_ tool: String) async throws {
        let far = try await Self.world("orch-reach-reads-\(tool)")
        let arguments: [String: JSONValue] = [
            "workspace": .string(far.orchestrator.id.rawValue), "profile": .string("Akira"), "chat": .string("x"),
        ]
        let toolbox = BridgeToolbox.standard
        let handler = try #require(await toolbox.handler(named: tool, for: far.w.world.homeAgent, store: far.w.store))
        let answer = await handler.call(far.w.world.request(tool, arguments), as: far.w.world.homeAgent, store: far.w.store)
        #expect(answer.isError)
        #expect(answer.text.contains(BridgeProfileTrouble.readsGoThroughOrchestrator(given: "Akira").sentence))
    }

    @Test("a closed destination says so plainly, and a closed own profile says nothing about others")
    func closedDestination() async throws {
        let far = try await Self.world("orch-reach-closed")
        try await ProfileBridgeSwitch.save(false, profile: far.w.akira, to: far.w.store)
        for identity in [far.w.world.homeAgent, BridgeIdentity.owner] {
            let told = await Self.say(far, as: identity, ["workspace": .string(far.orchestrator.id.rawValue)])
            #expect(told.text.contains(BridgeProfileTrouble.closedToOutside(given: "Akira").sentence))
            let listed = await ProjectListTool().call(
                far.w.world.request("project_list", ["profile": .string("Akira")]), as: identity, store: far.w.store
            )
            #expect(listed.text.contains(BridgeProfileTrouble.unreachable(given: "Akira").sentence))
        }
        try await ProfileBridgeSwitch.save(true, profile: far.w.akira, to: far.w.store)
        try await ProfileBridgeSwitch.save(false, profile: .initial, to: far.w.store)
        let told = await Self.say(far, as: far.w.world.homeAgent, ["workspace": .string(far.orchestrator.id.rawValue)])
        #expect(told.text.contains(BridgeProfileTrouble.unreachable(given: "Akira").sentence))
        #expect(far.window.sent.isEmpty)
    }

    @Test("an ordinary workspace on Codex does not cross")
    func codexOrdinaryConfined() async throws {
        let far = try await Self.world("orch-reach-codex")
        let workspace = try #require(far.w.world.homeAgent.workspaceID)
        let codex = try await far.w.store.upsert(Session(workspaceID: workspace, title: "Codex", agentKind: .codex))
        let identity = BridgeIdentity(sessionID: codex.id, workspaceID: workspace, role: .workspace)
        #expect(try await BridgeProfileReach.caller(of: identity, store: far.w.store) == .confined)
        let told = await Self.say(far, as: identity, ["workspace": .string(far.orchestrator.id.rawValue)])
        #expect(told.text.contains(BridgeProfileTrouble.unreachable(given: "Akira").sentence))
        #expect(far.window.sent.isEmpty)
    }

    @Test("a project with no orchestrator gets a card for the owner, and nothing is created")
    func noOrchestratorCard() async throws {
        let far = try await Self.world("orch-reach-card", withOrchestrator: false)
        let before = try await far.w.store.workspaces().count
        let told = await Self.say(far, as: far.w.world.homeAgent, ["project": .string(ProfileScopeWorld.farProjectName)])
        #expect(!told.isError)
        #expect(told.text.contains("waiting_for_an_orchestrator"))
        #expect(far.window.sent.isEmpty)
        #expect(try await far.w.store.workspaces().count == before)
        let session = try #require(far.w.world.homeAgent.sessionID)
        let cards = try await far.w.store.workSuggestions(sessionID: session)
        let card = try #require(cards.first)
        #expect(card.target == .orchestrator(far.w.world.farProject.id))
        #expect(card.prompt == "The invoice export is broken.")
        #expect(card.state == .pending)
    }
}
