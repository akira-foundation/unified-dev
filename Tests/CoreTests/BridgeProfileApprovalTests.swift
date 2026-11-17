import Foundation
import Testing
@testable import Core

@Suite("What stops for the owner when an orchestrator names another profile", .tags(.persistence), .scratchDirectory)
struct BridgeProfileApprovalTests {
    private static let prefix = BridgeToolApproval.toolPrefix
    private static let naming: JSONValue = .object(["profile": .string("Akira")])
    private static let reads = ["project_list", "chat_list", "chat_read", "workspace_diff", "workspace_say"]

    @Test("a workspace chat naming a profile stops, read or message", arguments: reads + ["workspace_list"])
    func namingStops(tool: String) {
        #expect(!BridgeToolApproval.isSelfApproved(toolName: Self.prefix + tool, input: Self.naming, inWorkspace: true))
    }

    @Test("a workspace chat that names none is answered as before", arguments: reads + ["workspace_list"])
    func notNamingPasses(tool: String) {
        #expect(BridgeToolApproval.isSelfApproved(toolName: Self.prefix + tool, input: .object([:]), inWorkspace: true))
    }

    @Test(
        "an empty profile is no crossing, and a value that is not text still stops",
        arguments: [
            (JSONValue.null, true), (.string("   "), true), (.number(3), false), (.bool(true), false),
        ] as [(JSONValue, Bool)]
    )
    func oddValues(value: JSONValue, approved: Bool) {
        let input: JSONValue = .object(["profile": value])
        #expect(
            BridgeToolApproval.isSelfApproved(toolName: Self.prefix + "chat_list", input: input, inWorkspace: true)
                == approved
        )
    }

    @Test("an Ask chat does not stop, and gains no self-approval it did not have")
    func askChatUnchanged() {
        #expect(BridgeToolApproval.isSelfApproved(
            toolName: Self.prefix + "chat_list", input: Self.naming, inWorkspace: false
        ))
        #expect(
            BridgeToolApproval.isSelfApproved(
                toolName: Self.prefix + "workspace_list", input: .object([:]), inWorkspace: false
            ) == BridgeToolApproval.isSelfApproved(toolName: Self.prefix + "workspace_list")
        )
    }

    @Test("a tool that always asks keeps asking without a profile")
    func alwaysAsks() {
        #expect(!BridgeToolApproval.isSelfApproved(
            toolName: Self.prefix + "workspace_archive", input: .object([:]), inWorkspace: true
        ))
    }

    private func crossingAsk() -> PermissionAsk {
        PermissionAsk(requestID: "req-1", toolName: Self.prefix + "chat_list", input: Self.naming)
    }

    @Test("a waiting crossing card is not shown as answered, and an Ask chat's is")
    func standingCard() {
        #expect(crossingAsk().standing(in: [:], inWorkspace: true) == nil)
        #expect(crossingAsk().standing(in: ["req-1": "allow"], inWorkspace: true) == "allow")
        #expect(crossingAsk().standing(in: [:], inWorkspace: false) == PermissionAskOutcome.selfApproved)
    }

    @Test("a Codex orchestrator, which no card can stop, does not cross")
    func codexConfined() async throws {
        let w = try await ProfileReachWorld.make("reach-codex")
        try await w.open(.initial, w.akira)
        let workspace = try #require(w.lead.workspaceID)
        let codex = try await w.store.upsert(Session(workspaceID: workspace, title: "Codex", agentKind: .codex))
        let identity = BridgeIdentity(
            sessionID: codex.id, workspaceID: workspace, role: .workspace, launchedOrchestrating: true
        )

        #expect(try await BridgeProfileReach.caller(of: identity, store: w.store) == .confined)
        #expect(await w.say(as: identity).isError)
        #expect(await w.listedTools(as: identity).contains("workspace_list") == false)
    }

    @Test("a chat already running when its workspace becomes the orchestrator does not cross as one")
    func promotedWhileRunning() async throws {
        let w = try await ProfileReachWorld.make("reach-promoted")
        try await w.open(.initial, w.akira)
        let identity = BridgeIdentity(
            sessionID: w.leadChat.id, workspaceID: try #require(w.lead.workspaceID), role: .workspace
        )

        #expect(try await BridgeProfileReach.caller(of: identity, store: w.store) == .unasked)
        #expect(await w.say(as: identity).isError)
        #expect(await w.read(as: identity, profile: "Akira").isError)
    }

    @Test("the launch flag reaches the identity its token resolves to")
    func tokenCarriesLaunch() throws {
        let registry = BridgeRegistry()
        let token = registry.mint(
            sessionID: SessionID("s"), workspaceID: WorkspaceID("w"), role: .workspace, launchedOrchestrating: true
        )
        #expect(try #require(registry.identity(forToken: token)).launchedOrchestrating)
    }

    @Test("an archived orchestrator and a session from another workspace are confined")
    func staleIdentities() async throws {
        let w = try await ProfileReachWorld.make("reach-stale")
        try await w.open(.initial, w.akira)
        let foreign = BridgeIdentity(
            sessionID: try #require(w.world.homeAgent.sessionID), workspaceID: try #require(w.lead.workspaceID),
            role: .workspace, launchedOrchestrating: true
        )
        #expect(try await BridgeProfileReach.caller(of: foreign, store: w.store) == .confined)

        try await w.store.update(workspaceID: try #require(w.lead.workspaceID)) { $0.state = .archived }

        #expect(try await BridgeProfileReach.caller(of: w.lead, store: w.store) == .confined)
    }
}
