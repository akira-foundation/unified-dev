import Testing
import Foundation
@testable import Core

private func makeSession(_ store: Store, permissionMode: PermissionMode) async throws -> Session {
    let repo = try await store.upsert(Repo(name: "r", path: "/tmp/r-\(UUID().uuidString)"))
    let workspace = try await store.upsert(Workspace(
        repoID: repo.id, name: "w", branch: "b", path: "/tmp/w", baseBranch: "main"
    ))
    return try await store.upsert(Session(
        workspaceID: workspace.id,
        model: "gemini-3.8-flash-low",
        effort: "high",
        agentKind: .antigravity,
        permissionMode: permissionMode
    ))
}

private func scriptedBox() throws -> ProcessBox {
    let box = ProcessBox()
    box.reply(to: "initialize", with: .object([:]))
    let opened = try #require(JSONValue.parse(Data(AntigravityWire.sessionNew.utf8)))["result"] ?? .null
    box.reply(to: "session/new", with: opened)
    box.reply(to: "session/set_config_option", with: .object([:]))
    box.ignore("session/prompt")
    return box
}

private func configOptions(in box: ProcessBox) -> [String: JSONValue] {
    var options: [String: JSONValue] = [:]
    for line in box.process.stdin.compactMap(JSONValue.parse)
    where line["method"]?.stringValue == "session/set_config_option" {
        if let id = line["params"]?["configId"]?.stringValue { options[id] = line["params"]?["value"] }
    }
    return options
}

@Suite(.scratchDirectory)
struct AntigravityRunnerTests {
    @Test("a first send opens an Antigravity session and sets the model and the mode as plain strings")
    func firstSendSetsModelAndMode() async throws {
        let store = try makeTestStore("antigravity-first-send")
        let session = try await makeSession(store, permissionMode: .acceptEdits)
        let box = try scriptedBox()
        let runner = ACPRunner(
            dialect: .antigravity,
            workspacePath: "/tmp/w",
            session: session,
            store: store,
            segmentID: try await activeSegmentID(store, session),
            makeClient: { ACPClient(configuration: $0, makeProcess: box.factory) }
        )
        #expect(runner.agentKind == .antigravity)
        try await runner.send("hello")
        await waitUntil("the session id to be stored", within: .seconds(2)) {
            (try? await store.session(id: session.id)?.agentSessionID) == "5361ec1e-4050-4bbc-91d8-f391b7a4c45b"
        }
        let options = configOptions(in: box)
        #expect(options["model"] == .string("gemini-3.8-flash-low"))
        #expect(options["mode"] == .string("accept-edits"))
        #expect(options["reasoning_effort"] == nil)
        #expect(box.process.launch.arguments == ["acp"])
        let rows = try await store.messages(sessionID: session.id)
        let initRow = rows.first { JSONValue.parse($0.payload)?["subtype"]?.stringValue == "init" }
        #expect(initRow.flatMap { JSONValue.parse($0.payload)?["agent_kind"]?.stringValue } == "antigravity")
        runner.terminateNow()
    }
}

private func promptResultBox() throws -> ProcessBox {
    let box = ProcessBox()
    box.reply(to: "initialize", with: .object([:]))
    box.reply(to: "session/new", with: try #require(JSONValue.parse(Data(AntigravityWire.sessionNew.utf8)))["result"] ?? .null)
    box.reply(to: "session/set_config_option", with: .object([:]))
    box.reply(to: "session/prompt", with: try #require(JSONValue.parse(Data(AntigravityWire.promptResult.utf8)))["result"] ?? .null)
    return box
}

private func makeAntigravityRunner(_ store: Store, _ session: Session, _ box: ProcessBox) async throws -> ACPRunner {
    ACPRunner(
        dialect: .antigravity,
        workspacePath: "/tmp/w",
        session: session,
        store: store,
        segmentID: try await activeSegmentID(store, session),
        makeClient: { ACPClient(configuration: $0, makeProcess: box.factory) }
    )
}

@Suite(.scratchDirectory)
struct AntigravityRunnerSafetyTests {
    @Test("a chat that becomes an orchestrator is relaunched without skipping Antigravity's prompts")
    func orchestratorDropsTheBypassLaunch() async throws {
        let store = try makeTestStore("antigravity-bypass-relaunch")
        let session = try await makeSession(store, permissionMode: .bypassPermissions)
        let box = try promptResultBox()
        let runner = try await makeAntigravityRunner(store, session, box)
        defer { runner.terminateNow() }

        try await runner.send("first")
        await waitUntil("the first turn to finish", within: .seconds(2)) {
            box.process.sentMethods.contains("session/prompt")
        }
        try await store.setOrchestrator(true, workspaceID: try #require(session.workspaceID))
        try await runner.send("second")

        await waitUntil("a second launch", within: .seconds(2)) { box.processes.count == 2 }
        #expect(box.processes.first?.launch.arguments.contains("--dangerously-skip-permissions") == true)
        #expect(box.processes.last?.launch.arguments.contains("--dangerously-skip-permissions") == false)
    }

    @Test("an orchestrator whose mode cannot be set does not send its prompt")
    func orchestratorModeFailureStopsTheTurn() async throws {
        let store = try makeTestStore("antigravity-orchestrator-mode")
        let session = try await makeSession(store, permissionMode: .acceptEdits)
        try await store.setOrchestrator(true, workspaceID: try #require(session.workspaceID))
        let box = try promptResultBox()
        box.fail("session/set_config_option", code: -32602, message: "refused")
        let runner = try await makeAntigravityRunner(store, session, box)
        defer { runner.terminateNow() }

        await #expect(throws: (any Error).self) { try await runner.send("plan") }
        #expect(!box.process.sentMethods.contains("session/prompt"))
    }

    @Test("a mode that cannot be set outside an orchestrator does not stop the turn")
    func modeFailureIsToleratedOtherwise() async throws {
        let store = try makeTestStore("antigravity-mode-tolerated")
        let session = try await makeSession(store, permissionMode: .acceptEdits)
        let box = try promptResultBox()
        box.fail("session/set_config_option", code: -32602, message: "refused")
        let runner = try await makeAntigravityRunner(store, session, box)
        defer { runner.terminateNow() }

        try await runner.send("hello")
        await waitUntil("the prompt sent", within: .seconds(2)) { box.process.sentMethods.contains("session/prompt") }
        #expect(box.process.sentMethods.contains("session/prompt"))
    }
}
