import Foundation
import Testing
@testable import Core

@Suite("profile_list names the profiles a caller can reach and nothing else", .tags(.persistence), .scratchDirectory)
struct ProfileListToolTests {
    static func list(_ w: ProfileReachWorld, as identity: BridgeIdentity) async -> BridgeToolResult {
        await ProfileListTool().call(w.world.request(ProfileListTool.name), as: identity, store: w.store)
    }

    static func answer(_ result: BridgeToolResult) throws -> JSONValue {
        try #require(JSONValue.parse(BridgeWorkspaceQuote.json(inside: result.text) ?? result.text))
    }

    static func names(_ answer: JSONValue) -> [String] {
        answer["reachable"]?.arrayValue?.compactMap { $0["name"]?.stringValue } ?? []
    }

    @Test("an orchestrator with both sides open lists its own and the other, fenced")
    func orchestratorReaches() async throws {
        let w = try await ProfileReachWorld.make("profile-list-lead")
        try await w.open(.initial, w.akira)
        let hidden = try await w.store.createProfile(name: "Closed One", colour: "red", symbol: "star")

        let result = await Self.list(w, as: w.lead)
        let answer = try Self.answer(result)

        #expect(result.text.contains(BridgeUntrustedText.opening))
        #expect(answer["own"]?["name"]?.stringValue == "Unified")
        #expect(answer["own"]?["open_to_others"] == .bool(true))
        #expect(Self.names(answer) == ["Akira"])
        #expect(answer["reachable"]?.arrayValue?.first?["id"]?.stringValue == w.akira.rawValue)
        #expect(answer["note"]?.stringValue == ProfileListTool.note(reachesAny: true))
        #expect(!result.text.contains(hidden.name))
        #expect(!result.text.contains(hidden.id.rawValue))
    }

    @Test("with its own profile closed to others it still lists the open one it can reach")
    func ownClosed() async throws {
        let w = try await ProfileReachWorld.make("profile-list-own-closed")
        try await w.open(w.akira)

        let answer = try Self.answer(await Self.list(w, as: w.lead))

        #expect(Self.names(answer) == ["Akira"])
        #expect(answer["own"]?["open_to_others"] == .bool(false))
    }

    @Test("a chat not launched asking lists no other and says why")
    func unasked() async throws {
        let w = try await ProfileReachWorld.make("profile-list-unasked")
        try await w.open(.initial, w.akira)
        let result = await Self.list(w, as: w.unasked)

        #expect(try Self.answer(result)["note"]?.stringValue == BridgeProfileTrouble.launchedUnasked.sentence)
        #expect(!result.text.contains("Akira"))
    }

    @Test("a chat on Codex lists only its own profile, because it never crosses")
    func confined() async throws {
        let w = try await ProfileReachWorld.make("profile-list-codex")
        try await w.open(.initial, w.akira)
        let workspace = try #require(w.world.homeAgent.workspaceID)
        let codex = try await w.store.upsert(Session(workspaceID: workspace, title: "Codex", agentKind: .codex))
        let identity = BridgeIdentity(sessionID: codex.id, workspaceID: workspace, role: .workspace)

        let result = await Self.list(w, as: identity)

        #expect(try Self.answer(result)["note"]?.stringValue == BridgeProfileTrouble.agentConfined.sentence)
        #expect(!result.text.contains("Akira"))
    }

    @Test("the owner's own client lists every open profile, unfenced, whatever its own switch says")
    func owner() async throws {
        let w = try await ProfileReachWorld.make("profile-list-owner")
        try await w.open(w.akira)

        let result = await Self.list(w, as: .owner)

        #expect(!result.text.contains(BridgeUntrustedText.opening))
        #expect(Self.names(try Self.answer(result)) == ["Akira"])
    }

    @Test("nothing open to reach says so")
    func nothingOpen() async throws {
        let w = try await ProfileReachWorld.make("profile-list-none")
        try await w.open(.initial)
        let answer = try Self.answer(await Self.list(w, as: w.lead))
        #expect(answer["note"]?.stringValue == ProfileListTool.note(reachesAny: false))
    }

    @Test("every call from any chat stops on the card and is never remembered")
    func approval() {
        let name = BridgeToolApproval.toolPrefix + ProfileListTool.name
        #expect(!BridgeToolApproval.isSelfApproved(toolName: name, input: .object([:]), inWorkspace: true))
        #expect(!BridgeToolApproval.isSelfApproved(toolName: name, input: .object([:]), inWorkspace: false))
        #expect(BridgeToolApproval.crossesProfile(toolName: name, input: .object([:])))
        #expect(BridgeToolApproval.crossingTools.contains(ProfileListTool.name))
        #expect(BridgeToolApproval.isSelfApproved(
            toolName: BridgeToolApproval.toolPrefix + "project_list", input: .object([:]), inWorkspace: true
        ))
    }

    @Test("it is served to every workspace chat and to the owner")
    func served() async throws {
        let w = try await ProfileReachWorld.make("profile-list-served")
        #expect(await w.listedTools(as: w.world.homeAgent).contains(ProfileListTool.name))
        #expect(await w.listedTools(as: w.unasked).contains(ProfileListTool.name))
        #expect(await w.listedTools(as: .owner).contains(ProfileListTool.name))
    }
}
