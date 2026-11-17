import Foundation
import Testing
@testable import Core

@Suite("A call that names another profile is approved once at a time", .tags(.persistence), .scratchDirectory)
struct BridgeProfileCrossingCardTests {
    static let tool = BridgeToolApproval.toolPrefix + "workspace_say"

    static func ask(_ input: JSONValue) -> PermissionAsk {
        PermissionAsk(
            requestID: "r", toolName: tool, input: input,
            suggestions: [PermissionSuggestion(
                type: "addRules", behavior: "allow", rules: [PermissionRule(toolName: tool)], raw: .object([:])
            )]
        )
    }

    static let crossing = ask(.object(["profile": .string("Akira"), "message": .string("m")]))

    @Test("it offers no always allow, while the same call in its own profile does")
    func crossingNeverWidens() {
        #expect(!Self.crossing.canWiden)
        #expect(Self.ask(.object(["message": .string("m")])).canWiden)
        #expect(Self.ask(.object(["profile": .string(" "), "message": .string("m")])).canWiden)
    }

    @Test("an answer for a wider scope still tells the CLI nothing to remember", arguments: [PermissionScope.session, .project])
    func answerDoesNotWiden(_ scope: PermissionScope) throws {
        let line = try PermissionAnswer.encode(ask: Self.crossing, decision: .allow(scope: scope))
        let wide = try PermissionAnswer.encode(ask: Self.ask(.object(["message": .string("m")])), decision: .allow(scope: scope))

        #expect(JSONValue.parse(line)?["response"]?["response"]?["updatedPermissions"] == nil)
        #expect(JSONValue.parse(wide)?["response"]?["response"]?["updatedPermissions"] != nil)
    }

    @Test("no grant is stored from it, so none can answer the next one")
    func noGrantStored() async throws {
        let store = try makeTestStore("crossing-grant")
        let repo = try await store.upsert(Repo(name: "r", path: TestScratch.unique("crossing-grant")))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "w", branch: "b", path: TestScratch.unique("crossing-grant-tree"), baseBranch: "main"
        ))
        let grants = SessionGrants(store: store, workspaceID: workspace.id)

        await grants.record(.allow(scope: .project), from: Self.crossing)

        #expect(try await store.permissionGrants(repoID: repo.id).isEmpty)
    }

    @Test("an orchestrator's card is judged as the orchestrator's on the click, whatever its chat's mode")
    func orchestratorCardDelivers() async throws {
        let far = try await BridgeProfileOrchestratorReachTests.world("crossing-lead-card", withOrchestrator: false)
        let lead = try #require(far.w.lead.sessionID)
        _ = await BridgeProfileOrchestratorReachTests.say(far, as: far.w.lead, ["project": .string(ProfileScopeWorld.farProjectName)])
        let card = try #require(try await far.w.store.workSuggestions(sessionID: lead).first)
        try await far.w.store.updateSessionPreferences(id: lead, permissionMode: .bypassPermissions)
        let started = OrchestratorRequestLaunchTests.Started()

        _ = await OrchestratorRequestLaunchTests.launch(far, started).launch(card.id, as: .newWorkspace, store: far.w.store)

        #expect(started.delivered.first?.source.workspaceID == far.w.lead.workspaceID)
    }

    @Test("a card whose sender became that project's orchestrator is not delivered to itself")
    func senderLeadsItself() async throws {
        let (far, card) = try await OrchestratorRequestLaunchTests.card("crossing-self")
        let home = try #require(try await far.w.store.workspace(id: far.w.world.homeWorkspace.id))
        let started = OrchestratorRequestLaunchTests.Started()
        let launch = WorkSuggestionLaunch(
            start: { _, _, _, _ in throw CancellationError() },
            crew: { _, _, _ in .refused("No crew.") },
            admit: { _ in .failure(WorkSuggestionRefusal("No folder.")) },
            orchestrate: OrchestratorRequestLaunch(
                start: { _ in home },
                deliver: { message in
                    started.delivered.append(message)
                    return .sent(message)
                }
            )
        )

        let outcome = await launch.launch(card.id, as: .newWorkspace, store: far.w.store)

        #expect(outcome == .refused(WorkSuggestionWording.senderLeads(home.name)))
        #expect(started.delivered.isEmpty)
    }

    @Test("an archived orchestrator is not listed to an ordinary workspace")
    func archivedOrchestratorUnlisted() {
        var archived = Workspace(
            repoID: RepoID("r"), name: "Old Lead", branch: "b", path: "/tmp/old-lead", baseBranch: "main"
        )
        archived.isOrchestrator = true
        archived.state = .archived
        var live = archived
        live.state = .active

        #expect(!BridgeProfileReach.lists(archived, to: .workspace))
        #expect(BridgeProfileReach.lists(live, to: .workspace))
        #expect(BridgeProfileReach.lists(archived, to: .orchestrator))
    }
}
