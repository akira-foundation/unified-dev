import Foundation
import Testing
@testable import Core

@Suite("What a crossing answers, tool by tool", .tags(.persistence), .scratchDirectory)
struct BridgeProfileCrossingTests {
    private let unreachable = "does not say whether one exists"

    @Test("a workspace of the caller's own profile is not found by naming another")
    func ownWorkspaceThroughOtherProfile() async throws {
        let w = try await ProfileReachWorld.make("cross-own")
        try await w.open(.initial, w.akira)

        let answer = await ChatListTool().call(
            w.world.request("chat_list", ["workspace": .string(w.world.homeWorkspace.id.rawValue), "profile": .string("Akira")]),
            as: w.lead, store: w.store
        )

        #expect(answer.isError)
        #expect(!answer.text.contains("Home Workspace"))
    }

    @Test("a closed profile is refused in the words of an invented one when it is named")
    func closedLikeInvented() async throws {
        let w = try await ProfileReachWorld.make("cross-closed")
        try await w.open(.initial)

        let closed = await w.read(as: w.lead, profile: "Akira")
        let invented = await w.read(as: w.lead, profile: "Nowhere")

        #expect(closed.text.contains(unreachable))
        #expect(closed.text.replacingOccurrences(of: "Akira", with: "X") == invented.text.replacingOccurrences(of: "Nowhere", with: "X"))
    }

    @Test("calling workspace_list when it is not served answers as an unknown tool does")
    func listThroughDispatch() async throws {
        let w = try await ProfileReachWorld.make("cross-dispatch")
        let dispatch = BridgeDispatch(store: w.store, identity: w.lead)

        func call(_ name: String) async throws -> String {
            let request = MCPRequest(id: .number(1), method: "tools/call", params: .object(["name": .string(name), "arguments": .object([:])]))
            return try #require(await dispatch.respond(to: request)).line()
        }

        let served = try await call("workspace_list")
        let unknown = try await call("no_such_tool")
        #expect(
            JSONValue.parse(served.replacingOccurrences(of: "workspace_list", with: "X"))
                == JSONValue.parse(unknown.replacingOccurrences(of: "no_such_tool", with: "X"))
        )
    }

    @Test("chat_read across profiles is fenced, says where it came from, and needs a workspace")
    func chatRead() async throws {
        let w = try await ProfileReachWorld.make("cross-chat-read")
        try await w.open(.initial, w.akira)
        let args: [String: JSONValue] = [
            "workspace": .string(w.world.farWorkspace.id.rawValue), "chat": .string(ProfileScopeWorld.farChat), "profile": .string("Akira"),
        ]

        let answer = await ChatReadTool().call(w.world.request("chat_read", args), as: w.lead, store: w.store)
        let missing = await ChatReadTool().call(
            w.world.request("chat_read", ["chat": .string("x"), "profile": .string("Akira")]), as: w.lead, store: w.store
        )

        #expect(answer.text.hasPrefix(BridgeWorkspaceQuote.fromAnotherProfile), "\(answer.text)")
        #expect(answer.text.contains(BridgeUntrustedText.opening))
        #expect(missing.isError)
        #expect(missing.text.contains("'workspace' as well"))
    }

    @Test("a chat that is not found there points back to the same profile")
    func chatReadHint() async throws {
        let w = try await ProfileReachWorld.make("cross-chat-hint")
        try await w.open(.initial, w.akira)

        let answer = await ChatReadTool().call(
            w.world.request("chat_read", [
                "workspace": .string(w.world.farWorkspace.id.rawValue), "chat": .string("nope"), "profile": .string("Akira"),
            ]),
            as: w.lead, store: w.store
        )

        #expect(answer.isError)
        #expect(answer.text.contains("and profile"))
    }

    @Test("workspace_diff across profiles is fenced", .tags(.git, .subprocess))
    func diff() async throws {
        let w = try await ProfileReachWorld.make("cross-diff")
        let repo = try await TempRepo()
        try repo.write("a.txt", "one\n")
        try await repo.commit("first")
        try repo.write("a.txt", "two\n")
        let tree = try await w.store.upsert(Workspace(
            repoID: w.world.farProject.id, name: "Diffed", branch: "main", path: repo.path, baseBranch: "main"
        ))
        try await w.open(.initial, w.akira)

        let answer = await WorkspaceDiffTool().call(
            w.world.request("workspace_diff", ["workspace": .string(tree.id.rawValue), "profile": .string("Akira")]),
            as: w.lead, store: w.store
        )

        #expect(!answer.isError, "\(answer.text)")
        #expect(answer.text.hasPrefix(BridgeWorkspaceQuote.fromAnotherProfile))
        #expect(answer.text.contains(BridgeUntrustedText.opening))
    }

    @Test("turning a switch off stops the next call, and a watch already made still reports")
    func switchOffAgain() async throws {
        let w = try await ProfileReachWorld.make("cross-off")
        try await w.open(.initial, w.akira)
        #expect(await w.say(as: w.lead, notify: true).isError == false)

        try await ProfileBridgeSwitch.save(false, profile: w.akira, to: w.store)

        #expect(await w.read(as: w.lead, profile: "Akira").text.contains(unreachable))
        let row = try #require(w.window.sent.first)
        _ = try await w.store.markDelivered(id: try #require(row.deliveryID))
        let farChat = try #require(try await w.store.sessions(workspaceID: w.world.farWorkspace.id).first)
        let told = try await w.store.settleWorkspaceDoneWatches(
            on: w.world.farWorkspace.id, ending: .finished(lastMessage: "Done."), in: farChat.id, isSubagentChat: false
        )
        #expect(told.map(\.id) == [w.leadChat.id])
    }

    @Test("the notice names the other profile and how to answer there")
    func noticeNamesProfile() async throws {
        let w = try await ProfileReachWorld.make("cross-notice")
        try await w.open(.initial, w.akira)
        _ = await w.say(as: w.lead, notify: true)
        let row = try #require(w.window.sent.first)
        _ = try await w.store.markDelivered(id: try #require(row.deliveryID))
        let farChat = try #require(try await w.store.sessions(workspaceID: w.world.farWorkspace.id).first)

        _ = try await w.store.settleWorkspaceDoneWatches(
            on: w.world.farWorkspace.id, ending: .finished(lastMessage: "Done."), in: farChat.id, isSubagentChat: false
        )

        let report = try #require(try await w.store.pendingDeliveries(sessionID: w.leadChat.id).first?.crewMessage)
        #expect(report.sent.contains("in the profile \"Akira\""))
        #expect(report.sent.contains("use workspace_say with its profile."))
    }

    @Test("a profile is found by id and any case, and a shared name is not guessed")
    func naming() async throws {
        let w = try await ProfileReachWorld.make("cross-naming")
        try await w.open(.initial, w.akira)

        #expect(await w.read(as: w.lead, profile: "aKiRa").isError == false)
        #expect(await w.read(as: w.lead, profile: w.akira.rawValue).isError == false)

        let twin = try await w.store.createProfile(name: "AKIRA", colour: "red", symbol: "star").id
        try await w.open(twin)
        let answer = await w.read(as: w.lead, profile: "Akira")

        #expect(answer.isError)
        #expect(answer.text.contains(w.akira.rawValue))
        #expect(answer.text.contains(twin.rawValue))
    }

    @Test("all is for the two lists alone")
    func allElsewhere() async throws {
        let w = try await ProfileReachWorld.make("cross-all")
        try await w.open(.initial, w.akira)

        #expect(await w.read(as: w.lead, profile: "all").isError)
        #expect(await w.say(as: w.lead, profile: "all").isError)
    }

    @Test("workspace_list with all tags every row, and refuses to ask GitHub about all of them")
    func listAll() async throws {
        let w = try await ProfileReachWorld.make("cross-list-all")
        try await w.open(.initial, w.akira)

        let answer = await WorkspaceListTool().call(
            w.world.request("workspace_list", ["profile": .string("all")]), as: w.lead, store: w.store
        )
        let github = await WorkspaceListTool().call(
            w.world.request("workspace_list", ["profile": .string("all"), "include_github": .bool(true)]),
            as: w.lead, store: w.store
        )

        #expect(answer.text.contains("\"profile\" : \"Akira\""))
        #expect(answer.text.contains("\"profile\" : \"Unified\""))
        #expect(github.isError)
        #expect(github.text.contains("include_github"))
    }

    @Test("an orchestrator's own list is fenced, and the owner's own is not")
    func ownListFence() async throws {
        let w = try await ProfileReachWorld.make("cross-own-fence")
        try await w.open(.initial)

        let lead = await WorkspaceListTool().call(w.world.request("workspace_list"), as: w.lead, store: w.store)
        let owner = await WorkspaceListTool().call(w.world.request("workspace_list"), as: .owner, store: w.store)

        #expect(lead.text.contains(BridgeUntrustedText.opening))
        #expect(!owner.text.contains(BridgeUntrustedText.opening))
    }

    @Test("a project lookup across profiles refuses without naming what is there")
    func projectRefusal() async throws {
        let w = try await ProfileReachWorld.make("cross-project")
        try await w.open(.initial, w.akira)

        let answer = await WorkspaceListTool().call(
            w.world.request("workspace_list", ["profile": .string("Akira"), "project": .string("nope")]),
            as: w.lead, store: w.store
        )

        #expect(answer.isError)
        #expect(!answer.text.contains(ProfileScopeWorld.farProjectName))
    }

    @Test("the reply line names the sender's profile by id")
    func replyLine() async throws {
        let w = try await ProfileReachWorld.make("cross-reply")
        try await w.open(.initial, w.akira)

        _ = await w.say(as: w.lead)

        let chat = try #require(try await w.store.sessions(workspaceID: w.world.farWorkspace.id).first)
        let delivered = try #require(try await w.store.pendingDeliveries(sessionID: chat.id).first?.crewMessage)
        #expect(delivered.sent.contains("profile \"\(ProfileID.initial.rawValue)\""))
    }

    @Test("an archived workspace in another profile is refused like one that never existed")
    func archivedThere() async throws {
        let w = try await ProfileReachWorld.make("cross-archived")
        try await w.open(.initial, w.akira)
        try await w.store.update(workspaceID: w.world.farWorkspace.id) { $0.state = .archived }

        let answer = await w.say(as: w.lead)

        #expect(answer.isError)
        #expect(!answer.text.contains(ProfileScopeWorld.farWorkspaceName))
    }

    @Test("the answer to a crossing message is fenced, and the record still reads it")
    func sayAnswer() async throws {
        let w = try await ProfileReachWorld.make("cross-say")
        try await w.open(.initial, w.akira)

        let answer = await w.say(as: w.lead)

        #expect(answer.text.contains(BridgeUntrustedText.opening))
        #expect(answer.text.contains("without the owner's authority"))
        #expect(answer.text.contains("Use notify_when_done"))
        let record = try #require(WorkspaceSayRecord(
            toolName: BridgeToolApproval.toolPrefix + "workspace_say",
            input: .object(["message": .string("Check the invoices.")]),
            resultText: answer.text
        ))
        #expect(record.target.workspaceID == w.world.farWorkspace.id)
        #expect(record.target.profile == "Akira")
    }

    @Test("a refusal from the app across profiles says nothing of what it found")
    func appRefusal() async throws {
        let w = try await ProfileReachWorld.make("cross-app-refusal")
        try await w.open(.initial, w.akira)
        let secret = "The workspace 'Secret Name' is gone."
        let tool = WorkspaceSayTool { _ in .refused(secret) }

        let answer = await tool.call(
            w.world.request("workspace_say", [
                "workspace": .string(w.world.farWorkspace.id.rawValue), "message": .string("Hello."), "profile": .string("Akira"),
            ]),
            as: w.lead, store: w.store
        )

        #expect(answer.isError)
        #expect(!answer.text.contains("Secret Name"))
    }

    @Test("a repeat across profiles is refused by id, without the workspace's name")
    func throttle() async throws {
        let w = try await ProfileReachWorld.make("cross-throttle")
        try await w.open(.initial, w.akira)
        _ = await w.say(as: w.lead)

        let again = await w.say(as: w.lead)

        #expect(again.isError)
        #expect(!again.text.contains(ProfileScopeWorld.farWorkspaceName))
        #expect(again.text.contains(w.world.farWorkspace.id.rawValue))
    }

    @Test("the owner's client is not told to wait for a notice it cannot get")
    func ownerNote() async throws {
        let w = try await ProfileReachWorld.make("cross-owner-note")
        try await w.open(w.akira)

        let answer = await w.say(as: .owner)

        #expect(answer.text.contains("This connection is not a workspace"))
        #expect(!answer.text.contains("Use notify_when_done"))
    }

    @Test("a notice inside one profile does not call the other side another organisation")
    func sameProfileNotice() async throws {
        let w = try await ProfileReachWorld.make("cross-same-notice")
        let home = try #require(try await w.store.sessions(workspaceID: w.world.homeWorkspace.id).first)
        let watcher = try #require(w.lead.sessionID)

        #expect(try await w.store.crossedProfileName(of: w.world.homeWorkspace.id, from: watcher) == nil)
        #expect(try await w.store.crossedProfileName(of: w.world.farWorkspace.id, from: home.id) == "Akira")
    }

    @Test("a notice about another profile names it by id, not by a name its agents can set")
    func noticeUsesID() async throws {
        let w = try await ProfileReachWorld.make("cross-notice-id")
        try await w.open(.initial, w.akira)
        _ = await w.say(as: w.lead, notify: true)
        let row = try #require(w.window.sent.first)
        _ = try await w.store.markDelivered(id: try #require(row.deliveryID))
        let farChat = try #require(try await w.store.sessions(workspaceID: w.world.farWorkspace.id).first)

        _ = try await w.store.settleWorkspaceDoneWatches(
            on: w.world.farWorkspace.id, ending: .finished(lastMessage: nil), in: farChat.id, isSubagentChat: false
        )

        let report = try #require(try await w.store.pendingDeliveries(sessionID: w.leadChat.id).first?.crewMessage)
        #expect(!report.sent.contains(ProfileScopeWorld.farWorkspaceName))
        #expect(report.sent.contains(w.world.farWorkspace.id.rawValue))
    }

    @Test("a notice of a blocked agent in another profile does not name the tool it asked for")
    func noticeHidesTool() async throws {
        let w = try await ProfileReachWorld.make("cross-notice-tool")
        try await w.open(.initial, w.akira)
        _ = await w.say(as: w.lead, notify: true)
        let row = try #require(w.window.sent.first)
        _ = try await w.store.markDelivered(id: try #require(row.deliveryID))
        let farChat = try #require(try await w.store.sessions(workspaceID: w.world.farWorkspace.id).first)

        _ = try await w.store.settleWorkspaceDoneWatches(
            on: w.world.farWorkspace.id, ending: .waitingOnPermission(tool: "planted_tool_name"), in: farChat.id,
            isSubagentChat: false
        )

        let report = try #require(try await w.store.pendingDeliveries(sessionID: w.leadChat.id).first?.crewMessage)
        #expect(!report.sent.contains("planted_tool_name"))
        #expect(report.sent.contains("permission to use a tool"))
    }

    @Test("a message from another profile puts the sender's names inside the markers")
    func originInsideMarkers() async throws {
        let w = try await ProfileReachWorld.make("cross-origin")
        try await w.open(.initial, w.akira)

        _ = await w.say(as: w.lead)

        let chat = try #require(try await w.store.sessions(workspaceID: w.world.farWorkspace.id).first)
        let sent = try #require(try await w.store.pendingDeliveries(sessionID: chat.id).first?.crewMessage).sent
        let opening = try #require(sent.range(of: BridgeUntrustedText.opening))
        #expect(!sent[..<opening.lowerBound].contains("Lead"))
        #expect(sent[opening.upperBound...].contains("\"Lead\""))
    }

    @Test("a git failure in another profile does not repeat what git wrote")
    func gitFailureQuiet() {
        let trouble = WorkspaceDiffTrouble.gitFailed(workspaceID: WorkspaceID("w"), "planted words")
        #expect(!trouble.sentenceAcrossProfiles.contains("planted words"))
        #expect(trouble.sentence.contains("planted words"))
    }

    @Test("a cancelled notice across profiles names the workspace by id")
    func cancelledByID() {
        let crew = CrewMessage.cancelled(to: "Planted", text: "x", acrossProfilesID: WorkspaceID("the-id"))
        #expect(!crew.sent.contains("Planted"))
        #expect(crew.sent.contains("the-id"))
    }

    @Test("only the stored word for on opens a profile", arguments: ["off", "", "ON", "true"])
    func onlyOnOpens(stored: String) {
        #expect(!ProfileBridgeSwitch.parse(stored))
    }

    @Test("a message stored before profiles were named still decodes")
    func oldPayload() throws {
        let old = Data(#"{"workspaceID":"w","workspace":"W","project":"P","chat":"C"}"#.utf8)
        let end = try JSONDecoder().decode(WorkspaceMessageEnd.self, from: old)
        #expect(end.profile == nil)
        #expect(end.profileID == nil)
    }

    @Test("a workspace name cannot break the line of a cancelled notice")
    func cancelledName() {
        let crew = CrewMessage.cancelled(to: "A\nB", text: "x")
        #expect(!crew.sent.contains("A\nB"))
        #expect(!crew.text.contains("A\nB"))
    }
}
