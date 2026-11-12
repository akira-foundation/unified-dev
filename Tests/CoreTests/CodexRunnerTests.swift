import Testing
import Foundation
@testable import Core

private func makeCodexSession(
    _ store: Store,
    permissionMode: PermissionMode = .acceptEdits,
    agentSessionID: String? = nil
) async throws -> (Session, RepoID) {
    let repo = try await store.upsert(Repo(name: "r", path: "/tmp/r-\(UUID().uuidString)"))
    let workspace = try await store.upsert(Workspace(
        repoID: repo.id, name: "w", branch: "b", path: "/tmp/w", baseBranch: "main"
    ))
    let session = try await store.upsert(Session(
        workspaceID: workspace.id,
        agentSessionID: agentSessionID,
        model: "gpt-5.6-sol",
        effort: "low",
        agentKind: .codex,
        permissionMode: permissionMode
    ))
    return (session, repo.id)
}

private func makeRunner(
    store: Store,
    session: Session,
    box: ProcessBox,
    gitHub: GitHubLogin = .thisMac,
    seen: SeenEnvironment? = nil
) async throws -> CodexRunner {
    CodexRunner(
        workspacePath: "/tmp/w",
        session: session,
        store: store, segmentID: try await activeSegmentID(store, session),
        gitHub: gitHub,
        makeClient: { configuration in
            seen?.value.withLock { $0 = configuration.environment }
            return CodexClient(configuration: configuration, makeProcess: box.factory)
        }
    )
}

private let threadStartReply = JSONValue.object([
    "thread": .object(["id": .string("01a02144-3b7e-7233-97f2-73ebd5105085")]),
    "model": .string("gpt-5.6-sol"),
])

private let turnStartReply = JSONValue.object([
    "turn": .object([
        "id": .string("01a02144-3bab-7fe3-a92c-6eec594d84fd"),
        "status": .string("inProgress"),
        "items": .array([]),
    ]),
])

private func scriptedBox(onWrite: @escaping @Sendable (String) -> Void = { _ in }) -> ProcessBox {
    let box = ProcessBox(onWrite: onWrite)
    box.reply(to: "thread/start", with: threadStartReply)
    box.reply(to: "thread/resume", with: threadStartReply)
    box.reply(to: "turn/start", with: turnStartReply)
    return box
}

private func eventually(
    _ description: String,
    within seconds: Double = 2,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @Sendable () async -> Bool
) async {
    await waitUntil(Comment(rawValue: description), within: .seconds(seconds), sourceLocation: sourceLocation, condition)
}

@Suite(.scratchDirectory) struct CodexRunnerTests {
    @Test func theServerStartsUnderTheProfilesGitHubLogin() async throws {
        let store = try makeTestStore("codex-github-login")
        let (session, _) = try await makeCodexSession(store)
        let seen = SeenEnvironment()
        let runner = try await makeRunner(
            store: store, session: session, box: scriptedBox(),
            gitHub: GitHubLogin.profile(ProfileID("debtges"), directory: URL(filePath: "/support/GitHubLogins/debtges")), seen: seen
        )
        defer { runner.terminateNow() }
        try await runner.send("first turn")
        let environment = seen.value.withLock { $0 }
        #expect(environment["GH_CONFIG_DIR"] == "/support/GitHubLogins/debtges")
        #expect(environment["GH_TOKEN"] == GitHubLogin.signedOutToken)
    }

    @Test(arguments: [false, true])
    func lateStoppedCompletionCannotEndTheNextIntentionalTurn(delayStart: Bool) async throws {
        let store = try makeTestStore("codex-late-stop")
        let (session, _) = try await makeCodexSession(store)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)
        try await runner.send("first turn")
        runner.cancelNow()
        box.reply(to: "turn/start", with: .object([
            "turn": .object(["id": .string("new-turn"), "status": .string("inProgress"), "items": .array([])]),
        ]))
        if delayStart { box.ignore("turn/start") }
        let nextSend = Task { try await runner.send("new intentional turn") }
        await eventually("second turn start", within: 20) {
            box.process.sentMethods.filter { $0 == "turn/start" }.count == 2
        }
        if !delayStart { try await nextSend.value }
        box.process.emit(#"{"method":"item/started","params":{"threadId":"01a02144-3b7e-7233-97f2-73ebd5105085","turnId":"new-turn","item":{"id":"new-command","type":"commandExecution","command":"echo new","status":"inProgress"}}}"#)
        box.process.emit(#"{"method":"turn/completed","params":{"threadId":"01a02144-3b7e-7233-97f2-73ebd5105085","turn":{"id":"01a02144-3bab-7fe3-a92c-6eec594d84fd","status":"interrupted","items":[]}}}"#)
        box.process.emit(#"{"method":"item/completed","params":{"threadId":"01a02144-3b7e-7233-97f2-73ebd5105085","turnId":"new-turn","item":{"id":"new-text","type":"agentMessage","text":"still working"}}}"#)
        await eventually("new output after stale completion", within: 20) {
            (try? await store.messages(sessionID: session.id).contains { $0.kind == .assistantText }) == true
        }
        #expect(try await store.messages(sessionID: session.id).filter { $0.kind == .result }.isEmpty)
        if delayStart {
            let starts = box.process.stdin.compactMap(JSONValue.parse).filter { $0["method"]?.stringValue == "turn/start" }
            let request = try #require(starts.last)
            let id = try #require(request["id"])
            box.process.emit("{\"id\":\(id.compactJSON),\"result\":{\"turn\":{\"id\":\"new-turn\",\"status\":\"inProgress\",\"items\":[]}}}")
            try await nextSend.value
        }
        #expect(try await store.session(id: session.id)?.state == .running)
        let interrupted = box.process.stdin.compactMap(JSONValue.parse).filter { $0["method"]?.stringValue == "turn/interrupt" }
        #expect(!interrupted.contains { $0["params"]?["turnId"]?.stringValue == "new-turn" })
        #expect(interrupted.contains { $0["params"]?["turnId"]?.stringValue == "01a02144-3bab-7fe3-a92c-6eec594d84fd" })
        box.process.emit(#"{"id":99,"method":"item/commandExecution/requestApproval","params":{"threadId":"01a02144-3b7e-7233-97f2-73ebd5105085","turnId":"new-turn","itemId":"new-command"}}"#)
        await eventually("new command approval after stale completion", within: 20) {
            ((try? await store.pendingPermissionAsks(sessionID: session.id)) ?? []).count == 1
        }
        let asks = try await store.pendingPermissionAsks(sessionID: session.id)
        #expect(asks.first?.ask.input["command"]?.stringValue == "echo new")
        runner.cancelNow()
        await eventually("new turn still interruptible", within: 20) {
            box.process.stdin.compactMap(JSONValue.parse).contains {
                $0["method"]?.stringValue == "turn/interrupt" && $0["params"]?["turnId"]?.stringValue == "new-turn"
            }
        }
        await runner.shutdown()
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["initialize", "thread/start", "turn/start"])
    func stopWhileStartingCannotBeLost(_ delayed: String) async throws {
        let store = try makeTestStore("codex-start-stop")
        let (session, _) = try await makeCodexSession(store)
        let (requests, requestSink) = AsyncStream<String>.makeStream()
        defer { requestSink.finish() }
        let box = scriptedBox { requestSink.yield($0) }
        box.ignore(delayed)
        let runner = try await makeRunner(store: store, session: session, box: box)
        let sending = Task {
            defer { requestSink.finish() }
            do {
                try await runner.send("do not run after Stop")
                Issue.record("a cancelled send returned success")
            } catch is CancellationError {
            } catch {
                Issue.record("unexpected send error: \(error)")
            }
        }
        let frame = await requests.first { JSONValue.parse($0)?["method"]?.stringValue == delayed }
        let request = try #require(frame.flatMap(JSONValue.parse))
        let id = try #require(request["id"])
        runner.cancelNow()
        let reply: JSONValue = switch delayed {
        case "thread/start": threadStartReply
        case "turn/start": turnStartReply
        default: .object([:])
        }
        box.process.reply(to: delayed, with: reply)
        box.process.emit("{\"id\":\(id.compactJSON),\"result\":\(reply.compactJSON)}")
        await sending.value

        if delayed == "turn/start" {
            #expect(box.process.sentMethods.contains("turn/interrupt"))
        } else {
            #expect(!box.process.sentMethods.contains("turn/start"))
        }
        #expect(try await store.session(id: session.id)?.state != .running)
        try await runner.send("this new turn is intentional")
        #expect(try await store.session(id: session.id)?.state == .running)
        await runner.shutdown()
    }

    @Test func startsAThreadOnTheFirstTurnAndStoresItsID() async throws {
        let store = try makeTestStore("codex-runner-start")
        let (session, _) = try await makeCodexSession(store)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)

        try await runner.send("hello")

        let methods = box.process.sentMethods
        #expect(methods == ["initialize", "initialized", "thread/start", "turn/start"])

        let stored = try await store.session(id: session.id)
        #expect(stored?.agentSessionID == "01a02144-3b7e-7233-97f2-73ebd5105085")
        #expect(stored?.state == .running)
    }

    @Test("Ask Unified Dev sends host instructions when starting and resuming Codex",
          arguments: [false, true], [false, true])
    func askAppInstructions(hasWorkspace: Bool, resumed: Bool) async throws {
        let store = try makeTestStore("codex-ask-instructions")
        var session: Session
        if hasWorkspace {
            (session, _) = try await makeCodexSession(store)
        } else {
            session = Session(workspaceID: nil, agentKind: .codex)
        }
        if resumed { session.agentSessionID = "existing-chat" }
        session = try await store.upsert(session)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)

        try await runner.send("create a workspace and explore the project")

        let method = resumed ? "thread/resume" : "thread/start"
        let frame = try #require(box.process.sentFrame { $0["method"]?.stringValue == method })
        #expect(frame["params"]?["developerInstructions"]?.stringValue ==
                (hasWorkspace ? nil : AskConversation.instructions))
        #expect(frame["params"]?["baseInstructions"] == nil)
        await runner.shutdown()
    }

    @Test func childOutputAndCompletionNeverEnterOrFinishTheParentChat() async throws {
        let store = try makeTestStore("codex-child-isolation")
        let (session, _) = try await makeCodexSession(store)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)
        try await runner.send("work with a child")
        box.process.emit(#"{"method":"item/completed","params":{"threadId":"01a02144-3b7e-7233-97f2-73ebd5105085","turnId":"parent-turn","item":{"id":"root-self","type":"subAgentActivity","agentThreadId":"01a02144-3b7e-7233-97f2-73ebd5105085","agentPath":"/root","kind":"interacted"}}}"#)
        box.process.emit(#"{"method":"item/completed","params":{"threadId":"child","turnId":"child-turn","item":{"id":"child-text","type":"agentMessage","text":"Child-only output"}}}"#)
        box.process.emit(#"{"method":"turn/completed","params":{"threadId":"child","turn":{"id":"child-turn","status":"completed","items":[]}}}"#)
        box.process.emit(#"{"method":"item/completed","params":{"threadId":"01a02144-3b7e-7233-97f2-73ebd5105085","turnId":"parent-turn","item":{"id":"parent-text","type":"agentMessage","text":"Parent still working"}}}"#)
        await eventually("parent output after child completion") {
            (try? await store.messages(sessionID: session.id).contains { $0.kind == .assistantText }) == true
        }
        let rows = try await store.messages(sessionID: session.id)
        #expect(rows.filter { $0.kind == .assistantText }.count == 1)
        #expect(!rows.contains { $0.kind == .result })
        #expect(!rows.contains { String(decoding: $0.payload, as: UTF8.self).contains("root-self") })
        #expect(!rows.contains { String(decoding: $0.payload, as: UTF8.self).contains("Child-only output") })
        let current = try await store.session(id: session.id)
        #expect(current?.state == .running)
        await runner.shutdown()
    }

    @Test func startsTheStoredCodexExecutable() async throws {
        let store = try makeTestStore("codex-runner-executable")
        let (session, _) = try await makeCodexSession(store)
        try await store.setSetting(
            AgentCatalog.executablePathSettingKey(.codex),
            "/tmp/tools/codex"
        )
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)

        try await runner.send("hello")

        #expect(box.process.launch.executable == "/tmp/tools/codex")
    }

    @Test func childApprovalsCannotBorrowParentMetadataOrSendReasonsToTheParent() async throws {
        let store = try makeTestStore("codex-child-approval")
        let (session, repoID) = try await makeCodexSession(store)
        try await store.upsert(PermissionGrant(repoID: repoID, toolName: "Bash", ruleContent: "echo parent"))
        let box = scriptedBox()
        box.reply(to: "turn/steer", with: .object([:]))
        let runner = try await makeRunner(store: store, session: session, box: box)
        try await runner.send("review")
        box.process.emit(#"{"method":"item/completed","params":{"threadId":"01a02144-3b7e-7233-97f2-73ebd5105085","turnId":"parent-turn","item":{"id":"spawn","type":"subAgentActivity","agentThreadId":"child","agentPath":"/root/review","kind":"started"}}}"#)
        box.process.emit(#"{"method":"item/started","params":{"threadId":"01a02144-3b7e-7233-97f2-73ebd5105085","turnId":"parent-turn","item":{"id":"shared","type":"commandExecution","command":"echo parent","status":"inProgress"}}}"#)
        box.process.emit(#"{"method":"item/started","params":{"threadId":"child","turnId":"child-turn","item":{"id":"shared","type":"commandExecution","command":"echo child","status":"inProgress"}}}"#)
        box.process.emit(#"{"id":55,"method":"item/commandExecution/requestApproval","params":{"threadId":"child","turnId":"child-turn","itemId":"shared"}}"#)
        await eventually("child permission to remain pending") {
            ((try? await store.pendingPermissionAsks(sessionID: session.id)) ?? []).count == 1
        }
        let asks = try await store.pendingPermissionAsks(sessionID: session.id)
        let ask = try #require(asks.first).ask
        #expect(ask.input["command"]?.stringValue == "echo child")
        await runner.answer(requestID: ask.requestID, decision: .deny(message: "Use a read-only check", endsTurn: false))
        let steer = try #require(box.process.sentFrame { $0["method"]?.stringValue == "turn/steer" })
        #expect(steer["params"]?["threadId"]?.stringValue == "child")
        #expect(steer["params"]?["expectedTurnId"]?.stringValue == "child-turn")
        await runner.shutdown()
    }

    @Test func aQuestionAnswerUsesTheCodexWireShapeAndResolvedQuestionsDisappear() async throws {
        let store = try makeTestStore("codex-question-answer")
        let (session, _) = try await makeCodexSession(store)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)
        try await runner.send("ask me")
        box.process.emit(#"{"id":71,"method":"item/tool/requestUserInput","params":{"threadId":"01a02144-3b7e-7233-97f2-73ebd5105085","turnId":"parent-turn","itemId":"question","isBlocking":false,"questions":[{"id":"scope","header":"Scope","question":"Which scope?","options":[{"label":"All","description":"Everything"}]}]}}"#)
        await eventually("question card") {
            ((try? await store.pendingPermissionAsks(sessionID: session.id)) ?? []).count == 1
        }
        let asks = try await store.pendingPermissionAsks(sessionID: session.id)
        let ask = try #require(asks.first).ask
        #expect(ask.toolName == AgentQuestionnaire.toolName)
        let answered = AgentQuestionnaire.answered(ask.input, answers: ["scope": "All"])
        await runner.answer(requestID: ask.requestID, decision: .answer(input: answered))
        let reply = try #require(box.process.sentFrame { $0["id"]?.intValue == 71 && $0["result"] != nil })
        #expect(reply["result"]?["answers"]?["scope"]?["answers"]?[0]?.stringValue == "All")
        await eventually("the answer kept with the question") {
            ((try? await store.permissionAskAnswers(sessionID: session.id)) ?? [:])[ask.requestID]
                == ["scope": "All"]
        }
        box.process.emit(#"{"id":72,"method":"item/tool/requestUserInput","params":{"threadId":"01a02144-3b7e-7233-97f2-73ebd5105085","turnId":"parent-turn","itemId":"question-2","questions":[{"id":"note","header":"Note","question":"Anything else?"}]}}"#)
        box.process.emit(#"{"method":"serverRequest/resolved","params":{"threadId":"01a02144-3b7e-7233-97f2-73ebd5105085","requestId":72}}"#)
        box.process.emit(#"{"method":"item/completed","params":{"threadId":"01a02144-3b7e-7233-97f2-73ebd5105085","turnId":"parent-turn","item":{"id":"sentinel","type":"agentMessage","text":"Question resolved"}}}"#)
        await eventually("resolution processed before following prose") {
            (try? await store.messages(sessionID: session.id).contains { $0.kind == .assistantText }) == true
        }
        let pending = try await store.pendingPermissionAsks(sessionID: session.id)
        #expect(pending.isEmpty)
        await runner.shutdown()
    }

    @Test func resumesAThreadItAlreadyHas() async throws {
        let store = try makeTestStore("codex-runner-resume")
        let (session, _) = try await makeCodexSession(store, agentSessionID: "01a02144-3b7e-7233-97f2-73ebd5105085")
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)

        try await runner.send("again")

        #expect(box.process.sentMethods.contains("thread/resume"))
        #expect(!box.process.sentMethods.contains("thread/start"))
    }

    @Test func writesTheUsersOwnWordsAsARowTheTranscriptAlreadyDraws() async throws {
        let store = try makeTestStore("codex-runner-user")
        let (session, _) = try await makeCodexSession(store)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)

        try await runner.send("write the tests first")

        let rows = try await store.messages(sessionID: session.id)
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.kind == .user)

        let json = try #require(JSONValue.parse(row.payload))
        #expect(json["type"]?.stringValue == "user")
        #expect(json["message"]?["content"]?[0]?["text"]?.stringValue == "write the tests first")
    }

    @Test(arguments: ["0", "1"], [InteractionMode.build, .plan])
    func sendsExplicitCodexSpeedChoice(value: String, mode: InteractionMode) async throws {
        let store = try Store(path: ":memory:")
        let (original, _) = try await makeCodexSession(store)
        var session = original
        session.interactionMode = mode
        try await store.setSetting("session.\(session.id).codexFastMode", value)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)
        try await runner.send("hello")
        let turn = try #require(box.process.sentFrame { $0["method"]?.stringValue == "turn/start" })
        #expect(turn["params"]?["serviceTier"]?.stringValue == (value == "1" ? "priority" : "default"))
        #expect(turn["params"]?["collaborationMode"]?["mode"]?.stringValue == (mode == .plan ? "plan" : "default"))
        runner.cancelNow()
        try await store.setSetting("session.\(session.id).codexFastMode", value == "1" ? "0" : "1")
        try await runner.send("next turn")
        let turns = box.process.stdin.compactMap(JSONValue.parse).filter { $0["method"]?.stringValue == "turn/start" }
        #expect(turns.count == 2)
        #expect(turns.last?["params"]?["serviceTier"]?.stringValue == (value == "1" ? "default" : "priority"))
        #expect(turns.last?["params"]?["collaborationMode"]?["mode"]?.stringValue == (mode == .plan ? "plan" : "default"))
        await runner.shutdown()
    }

    @Test func oldClaudeSpeedPreferenceDoesNotOverrideCodexConfiguration() async throws {
        let store = try Store(path: ":memory:")
        let (session, _) = try await makeCodexSession(store)
        try await store.setSetting(ComposerControls.fastModeKey(sessionID: session.id), "1")
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)
        try await runner.send("hello")
        let turn = try #require(box.process.sentFrame { $0["method"]?.stringValue == "turn/start" })
        #expect(turn["params"]?["serviceTier"] == nil)
        await runner.shutdown()
    }

    @Test func sendsTheChatsModelAndEffortWithEveryTurn() async throws {
        let store = try makeTestStore("codex-runner-turn")
        let (session, _) = try await makeCodexSession(store)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)

        try await runner.send("hello")

        let turn = try #require(box.process.sentFrame { $0["method"]?.stringValue == "turn/start" })
        let params = try #require(turn["params"])
        #expect(params["model"]?.stringValue == "gpt-5.6-sol")
        #expect(params["effort"]?.stringValue == "low")
        #expect(params["approvalPolicy"]?.stringValue == "on-request")
        #expect(params["sandboxPolicy"]?["type"]?.stringValue == "workspaceWrite")
        #expect(params["sandboxPolicy"]?["writableRoots"]?[0]?.stringValue == "/tmp/w")
        #expect(params["approvalsReviewer"]?.stringValue == "user")
    }

    @Test func mapsEveryPermissionModeOntoThePolicySandboxAndReviewerTriple() {
        #expect(CodexRunner.approvalPolicy(for: .bypassPermissions) == .never)
        #expect(CodexRunner.sandboxMode(for: .bypassPermissions) == .dangerFullAccess)
        #expect(CodexRunner.approvalPolicy(for: .acceptEdits) == .onRequest)
        #expect(CodexRunner.sandboxMode(for: .acceptEdits) == .workspaceWrite)
        #expect(CodexRunner.approvalPolicy(for: .auto) == .onRequest)
        #expect(CodexRunner.sandboxMode(for: .auto) == .readOnly)

        for mode in [PermissionMode.auto, .acceptEdits, .bypassPermissions, .plan] {
            #expect(CodexRunner.approvalsReviewer(for: mode) == .user)
        }
    }

    @Test func approveForMeIsAskForApprovalWithCodexsOwnReviewerAnswering() {
        #expect(CodexRunner.approvalsReviewer(for: .autoReview) == .autoReview)
        #expect(CodexRunner.approvalsReviewer(for: .acceptEdits) == .user)
        #expect(CodexRunner.approvalPolicy(for: .autoReview) == CodexRunner.approvalPolicy(for: .acceptEdits))
        #expect(CodexRunner.sandboxMode(for: .autoReview) == CodexRunner.sandboxMode(for: .acceptEdits))
        #expect(CodexApprovalsReviewer.autoReview.rawValue == "auto_review")
        #expect(CodexApprovalsReviewer.user.rawValue == "user")
    }

    @Test func sendsTheReviewerWithTheTurnWhenApproveForMeIsChosen() async throws {
        let store = try makeTestStore("codex-runner-approve-for-me")
        let (session, _) = try await makeCodexSession(store, permissionMode: .autoReview)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)

        try await runner.send("hello")

        let turn = try #require(box.process.sentFrame { $0["method"]?.stringValue == "turn/start" })
        let params = try #require(turn["params"])
        #expect(params["approvalsReviewer"]?.stringValue == "auto_review")
        #expect(params["sandboxPolicy"]?["type"]?.stringValue == "workspaceWrite")
    }

    @Test func replaysARecordedTurnIntoTheTranscript() async throws {
        let store = try makeTestStore("codex-runner-replay")
        let (session, _) = try await makeCodexSession(store)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)

        try await runner.send("Reply with exactly one word: unifieddev")
        for line in try fixtureLines("codex-turn.ndjson") {
            guard JSONValue.parse(line)?["method"] != nil else { continue }
            box.process.emit(line)
        }

        await eventually("the turn to finish") {
            (try? await store.session(id: session.id))??.state == .idle
        }

        let rows = try await store.messages(sessionID: session.id)
        #expect(rows.map(\.kind) == [.user, .system, .assistantText, .notice, .result])

        let stored = try #require(try await store.session(id: session.id))
        #expect(stored.outputTokens == 6)
        #expect(stored.inputTokens == 16159)
        #expect(stored.costUSD == 0)
    }

    @Test func aStoppedTurnIsCancelledRatherThanFailed() async throws {
        let store = try makeTestStore("codex-runner-stop")
        let (session, _) = try await makeCodexSession(store)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)

        try await runner.send("count to three hundred")
        runner.cancelNow()

        await eventually("the interrupt to reach the server") {
            box.process.sentMethods.contains("turn/interrupt")
        }
        let interrupt = try #require(box.process.sentFrame { $0["method"]?.stringValue == "turn/interrupt" })
        #expect(interrupt["params"]?["threadId"]?.stringValue == "01a02144-3b7e-7233-97f2-73ebd5105085")
        #expect(interrupt["params"]?["turnId"]?.stringValue == "01a02144-3bab-7fe3-a92c-6eec594d84fd")

        for line in try fixtureLines("codex-interrupt.ndjson") {
            guard let json = JSONValue.parse(line), json["method"]?.stringValue == "turn/completed" else {
                continue
            }
            box.process.emit(line)
        }
        await eventually("the session to settle") {
            (try? await store.session(id: session.id))??.state == .cancelled
        }
    }

    @Test func asksTheQuestionTheServerAskedAndAnswersIt() async throws {
        let store = try makeTestStore("codex-runner-ask")
        let (session, _) = try await makeCodexSession(store)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)

        try await runner.send("create note.txt")
        for line in try fixtureLines("codex-approval.ndjson") {
            guard let json = JSONValue.parse(line), let method = json["method"]?.stringValue else {
                continue
            }
            guard method == "item/started" || method.hasSuffix("requestApproval") else { continue }
            box.process.emit(line)
        }

        await eventually("the question to be stored") {
            ((try? await store.pendingPermissionAsks(sessionID: session.id)) ?? []).isEmpty == false
        }

        let asks = try await store.pendingPermissionAsks(sessionID: session.id)
        let ask = try #require(asks.first).ask
        #expect(ask.toolName == "ApplyPatch")
        #expect(ask.subject.hasSuffix("note.txt"))

        await eventually("the session to say it is waiting") {
            (try? await store.session(id: session.id))??.state == .waiting
        }

        await runner.answer(requestID: ask.requestID, decision: .deny(message: "no", endsTurn: false))

        await eventually("the refusal to reach the server") {
            box.process.stdin.contains { $0.contains("\"decline\"") }
        }
        let answered = try await store.pendingPermissionAsks(sessionID: session.id)
        #expect(answered.isEmpty)
    }

    private func commandStarted(_ id: String, _ command: String) -> String {
        #"{"method":"item/started","params":{"threadId":"01a02144-3b7e-7233-97f2-73ebd5105085","turnId":"new-turn","item":{"type":"commandExecution","id":"\#(id)","command":"\#(command)","cwd":"/tmp/w","status":"inProgress"}}}"#
    }

    private func commandApproval(_ request: Int, _ id: String, command: String? = nil) -> String {
        let asked = command.map { #","command":"\#($0)""# } ?? ""
        return #"{"id":\#(request),"method":"item/commandExecution/requestApproval","params":{"threadId":"01a02144-3b7e-7233-97f2-73ebd5105085","turnId":"new-turn","itemId":"\#(id)"\#(asked)}}"#
    }

    @Test func anOrchestratorAcceptsAListedReadWithoutAQuestionAndLeavesAnythingElseForTheOwner() async throws {
        let store = try makeTestStore("codex-runner-orchestrator-read")
        let (session, _) = try await makeCodexSession(store, permissionMode: .bypassPermissions)
        try await store.setOrchestrator(true, workspaceID: try #require(session.workspaceID))
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)
        defer { runner.terminateNow() }
        try await runner.send("look")

        box.process.emit(commandStarted("read", "git log -1"))
        box.process.emit(commandApproval(61, "read", command: "git log -1"))
        await eventually("the read accepted") {
            box.process.sentFrame { $0["id"]?.intValue == 61 && $0["result"] != nil } != nil
        }
        let reply = try #require(box.process.sentFrame { $0["id"]?.intValue == 61 && $0["result"] != nil })
        #expect(reply["result"]?["decision"]?.stringValue == CodexApprovalDecision.accept.rawValue)
        #expect(try await store.pendingPermissionAsks(sessionID: session.id).isEmpty)
        #expect(try await !store.messages(sessionID: session.id).contains { $0.kind == .permissionAsk })

        box.process.emit(commandStarted("write", "rm -rf Sources"))
        box.process.emit(commandApproval(62, "write", command: "rm -rf Sources"))
        box.process.emit(commandStarted("later", "git status"))
        box.process.emit(commandApproval(63, "later", command: "git status"))
        await eventually("the later read accepted") {
            box.process.sentFrame { $0["id"]?.intValue == 63 && $0["result"] != nil } != nil
        }
        #expect(box.process.sentFrame { $0["id"]?.intValue == 62 && $0["result"] != nil } == nil)
        #expect(try await store.pendingPermissionAsks(sessionID: session.id).count == 1)
    }

    @Test func theRunWithoutAskingSwitchIsReadOnEachAskOfARunningThread() async throws {
        let store = try makeTestStore("codex-runner-orchestrator-unasked")
        let (session, _) = try await makeCodexSession(store, permissionMode: .bypassPermissions)
        try await store.setOrchestrator(true, workspaceID: try #require(session.workspaceID))
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)
        defer { runner.terminateNow() }
        try await runner.send("look")
        @Sendable func decided(_ id: Int) -> String? {
            box.process.sentFrame { $0["id"]?.intValue == id && $0["result"] != nil }?["result"]?["decision"]?.stringValue
        }
        let compound = "rg x && echo a"
        let wrapped = "/bin/zsh -lc 'rg x && echo a'"

        box.process.emit(commandStarted("off", compound))
        box.process.emit(commandApproval(71, "off", command: compound))
        await eventually("the question to wait") {
            ((try? await store.pendingPermissionAsks(sessionID: session.id)) ?? []).count == 1
        }
        #expect(decided(71) == nil)

        try await OrchestratorUnaskedCommands.turn(true, for: session, in: store)
        box.process.emit(commandStarted("on", compound))
        box.process.emit(commandApproval(72, "on", command: compound))
        await eventually("the command accepted") { decided(72) != nil }
        #expect(decided(72) == CodexApprovalDecision.accept.rawValue)

        box.process.emit(commandStarted("wrapped", wrapped))
        box.process.emit(commandApproval(73, "wrapped", command: wrapped))
        await eventually("the wrapped command accepted") { decided(73) != nil }
        #expect(decided(73) == CodexApprovalDecision.accept.rawValue)

        box.process.emit(commandStarted("refused", "eval git push"))
        box.process.emit(commandApproval(74, "refused", command: "eval git push"))
        await eventually("the command declined") { decided(74) != nil }
        #expect(decided(74) == CodexApprovalDecision.decline.rawValue)

        box.process.emit(commandStarted("other", compound))
        box.process.emit(commandApproval(75, "other", command: "rg x && echo b"))
        await eventually("the mismatched request to wait") {
            ((try? await store.pendingPermissionAsks(sessionID: session.id)) ?? []).count == 2
        }
        #expect(decided(75) == nil)

        try await OrchestratorUnaskedCommands.turn(false, for: session, in: store)
        box.process.emit(commandStarted("off-again", compound))
        box.process.emit(commandApproval(76, "off-again", command: compound))
        await eventually("the last question to wait") {
            ((try? await store.pendingPermissionAsks(sessionID: session.id)) ?? []).count == 3
        }
        #expect(decided(76) == nil)
    }

    @Test func aRequestNamingAnotherCommandThanItsItemIsNotAccepted() async throws {
        let store = try makeTestStore("codex-runner-orchestrator-mismatch")
        let (session, _) = try await makeCodexSession(store, permissionMode: .bypassPermissions)
        try await store.setOrchestrator(true, workspaceID: try #require(session.workspaceID))
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)
        defer { runner.terminateNow() }
        try await runner.send("look")

        box.process.emit(commandStarted("swap", "ls"))
        box.process.emit(commandApproval(71, "swap", command: "rm -rf Sources"))
        box.process.emit(commandStarted("later", "git status"))
        box.process.emit(commandApproval(72, "later", command: "git status"))
        await eventually("the later read accepted") {
            box.process.sentFrame { $0["id"]?.intValue == 72 && $0["result"] != nil } != nil
        }
        #expect(box.process.sentFrame { $0["id"]?.intValue == 71 && $0["result"] != nil } == nil)
    }

    @Test func aRequestNamingNoCommandIsNotAccepted() async throws {
        let store = try makeTestStore("codex-runner-orchestrator-unnamed")
        let (session, _) = try await makeCodexSession(store, permissionMode: .bypassPermissions)
        try await store.setOrchestrator(true, workspaceID: try #require(session.workspaceID))
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)
        defer { runner.terminateNow() }
        try await runner.send("look")

        box.process.emit(commandStarted("unnamed", "git log -1"))
        box.process.emit(commandApproval(81, "unnamed"))
        box.process.emit(commandStarted("later", "git status"))
        box.process.emit(commandApproval(82, "later", command: "git status"))
        await eventually("the later read accepted") {
            box.process.sentFrame { $0["id"]?.intValue == 82 && $0["result"] != nil } != nil
        }
        #expect(box.process.sentFrame { $0["id"]?.intValue == 81 && $0["result"] != nil } == nil)
        #expect(try await store.pendingPermissionAsks(sessionID: session.id).count == 1)
    }

    @Test func anOrchestratorDeclinesAFileChangeAStoredGrantWouldAllow() async throws {
        let store = try makeTestStore("codex-runner-orchestrator")
        let (session, repoID) = try await makeCodexSession(store, permissionMode: .bypassPermissions)
        try await store.setOrchestrator(true, workspaceID: try #require(session.workspaceID))
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)
        let path = try #require(try fixtureLines("codex-approval.ndjson").compactMap { line -> String? in
            guard let json = JSONValue.parse(line), json["params"]?["item"]?["type"]?.stringValue == "fileChange"
            else { return nil }
            return json["params"]?["item"]?["changes"]?[0]?["path"]?.stringValue
        }.first)
        try await store.upsert(PermissionGrant(repoID: repoID, toolName: "ApplyPatch", ruleContent: path))

        try await runner.send("create note.txt")
        for line in try fixtureLines("codex-approval.ndjson") {
            guard let json = JSONValue.parse(line), let method = json["method"]?.stringValue else {
                continue
            }
            guard method == "item/started" || method.hasSuffix("requestApproval") else { continue }
            box.process.emit(line)
        }

        await eventually("the refusal to reach the server") {
            box.process.stdin.contains { $0.contains("\"decline\"") }
        }
        let start = try #require(box.process.sentFrame { $0["method"]?.stringValue == "thread/start" })
        #expect(start["params"]?["sandbox"]?.stringValue == CodexSandboxMode.readOnly.rawValue)
        #expect(start["params"]?["developerInstructions"]?.stringValue?.contains(OrchestratorRole.instructions) == true)
        await eventually("the refused question to be settled in the database", within: 20) {
            ((try? await store.pendingPermissionAsks(sessionID: session.id)) ?? []).isEmpty
        }
        let decisions = try await store.permissionAskDecisions(sessionID: session.id)
        #expect(!decisions.isEmpty)
        #expect(decisions.values.allSatisfy { $0 == PermissionDecision.deny(message: "", endsTurn: false).storedName })
        await runner.shutdown()
    }

    @Test func aStoredGrantAnswersTheQuestionWithoutAsking() async throws {
        let store = try makeTestStore("codex-runner-grant")
        let (session, repoID) = try await makeCodexSession(store)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)

        let paths = try fixtureLines("codex-approval.ndjson")
            .compactMap { line -> String? in
                guard let json = JSONValue.parse(line),
                      json["method"]?.stringValue == "item/started",
                      json["params"]?["item"]?["type"]?.stringValue == "fileChange"
                else { return nil }
                return json["params"]?["item"]?["changes"]?[0]?["path"]?.stringValue
            }
        let path = try #require(paths.first)
        try await store.upsert(PermissionGrant(
            repoID: repoID,
            toolName: "ApplyPatch",
            ruleContent: path
        ))

        let events = runner.events
        let watching = Task { () -> PermissionResolution? in
            for await event in events {
                if case .permissionDecided(let resolution) = event { return resolution }
            }
            return nil
        }

        try await runner.send("create note.txt")
        for line in try fixtureLines("codex-approval.ndjson") {
            guard let json = JSONValue.parse(line), let method = json["method"]?.stringValue else {
                continue
            }
            guard method == "item/started" || method.hasSuffix("requestApproval") else { continue }
            box.process.emit(line)
        }

        let resolution = try #require(await watching.value)
        #expect(resolution.decision == PermissionAskOutcome.auto)
        #expect(resolution.note.contains("ApplyPatch"))
        await eventually("the automatic answer to reach the server") {
            box.process.stdin.contains { $0.contains("acceptForSession") }
        }
    }

    @Test func stopInterruptsTheTurnAndLeavesTheServerRunning() async throws {
        let store = try makeTestStore("codex-runner-stop-keeps-server")
        let (session, _) = try await makeCodexSession(store)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)

        try await runner.send("count to three hundred")
        runner.cancelNow()
        await eventually("the interrupt to reach the server") {
            box.process.sentMethods.contains("turn/interrupt")
        }
        for line in try fixtureLines("codex-interrupt.ndjson") {
            guard let json = JSONValue.parse(line), json["method"]?.stringValue == "turn/completed" else {
                continue
            }
            box.process.emit(line)
        }
        await eventually("the session to settle") {
            (try? await store.session(id: session.id))??.state == .cancelled
        }

        #expect(box.process.isRunning)
        #expect(await runner.isProcessAlive)

        try await runner.send("carry on")
        #expect(box.process.sentMethods.filter { $0 == "initialize" }.count == 1)
        #expect(box.process.sentMethods.filter { $0 == "turn/start" }.count == 2)
    }

    @Test func tearingDownKillsTheServer() async throws {
        let store = try makeTestStore("codex-runner-terminate")
        let (session, _) = try await makeCodexSession(store)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)

        try await runner.send("count to three hundred")
        #expect(box.process.isRunning)

        runner.terminateNow()

        #expect(box.process.isRunning == false)
        #expect(await runner.isProcessAlive == false)
    }

    @Test func tearingDownFilesTheQuestionNobodyAnswered() async throws {
        let store = try makeTestStore("codex-runner-terminate-ask")
        let (session, _) = try await makeCodexSession(store)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)

        let events = runner.events
        let watching = Task { () -> PermissionResolution? in
            for await event in events {
                if case .permissionDecided(let resolution) = event { return resolution }
            }
            return nil
        }

        try await runner.send("create note.txt")
        for line in try fixtureLines("codex-approval.ndjson") {
            guard let json = JSONValue.parse(line), let method = json["method"]?.stringValue else {
                continue
            }
            guard method == "item/started" || method.hasSuffix("requestApproval") else { continue }
            box.process.emit(line)
        }
        await eventually("the question to be stored") {
            ((try? await store.pendingPermissionAsks(sessionID: session.id)) ?? []).isEmpty == false
        }
        let ask = try #require(try await store.pendingPermissionAsks(sessionID: session.id).first).ask

        runner.terminateNow()

        let resolution = try #require(await watching.value)
        #expect(resolution.requestID == ask.requestID)
        #expect(resolution.decision == PermissionAskOutcome.stopped)

        await eventually("the question to be settled in the database") {
            ((try? await store.pendingPermissionAsks(sessionID: session.id)) ?? []).isEmpty
        }
        let decisions = try await store.permissionAskDecisions(sessionID: session.id)
        #expect(decisions[ask.requestID] == PermissionAskOutcome.stopped)
        #expect(decisions[ask.requestID] != PermissionAskOutcome.abandoned)
    }

    @Test func aChatWhoseServerWasKilledResumesOnTheNextMessage() async throws {
        let store = try makeTestStore("codex-runner-terminate-resume")
        let (session, _) = try await makeCodexSession(store)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)

        try await runner.send("hello")
        runner.terminateNow()
        await eventually("the teardown to finish") {
            (try? await store.session(id: session.id))??.state == .cancelled
        }

        try await runner.send("again")

        #expect(box.process.sentMethods == ["initialize", "initialized", "thread/resume", "turn/start"])
        #expect(box.process.isRunning)
    }

    @Test func handsEveryConsumerItsOwnStream() async throws {
        let store = try makeTestStore("codex-runner-streams")
        let (session, _) = try await makeCodexSession(store)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)

        let firstEvents = runner.events
        let secondEvents = runner.events
        let first = Task {
            for await event in firstEvents {
                if case .initialized = event { return true }
            }
            return false
        }
        let second = Task {
            for await event in secondEvents {
                if case .initialized = event { return true }
            }
            return false
        }

        try await runner.send("hello")
        box.process.emit(#"{"method":"thread/started","params":{"thread":{"id":"01a02144-3b7e-7233-97f2-73ebd5105085"}}}"#)

        #expect(await first.value)
        #expect(await second.value)
    }
}

@Suite(.scratchDirectory) struct SessionAgentKindTests {
    @Test func aChatDefaultsToClaudeCode() async throws {
        let store = try makeTestStore("agent-kind-default")
        let repo = try await store.upsert(Repo(name: "r", path: "/tmp/r-\(UUID().uuidString)"))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "w", branch: "b", path: "/tmp/w", baseBranch: "main"
        ))
        let session = try await store.upsert(Session(workspaceID: workspace.id))
        #expect(session.agentKind == .claudeCode)

        let stored = try await store.session(id: session.id)
        #expect(stored?.agentKind == .claudeCode)
    }

    @Test func theColumnSurvivesARoundTrip() async throws {
        let store = try makeTestStore("agent-kind-roundtrip")
        let repo = try await store.upsert(Repo(name: "r", path: "/tmp/r-\(UUID().uuidString)"))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "w", branch: "b", path: "/tmp/w", baseBranch: "main"
        ))
        let session = try await store.upsert(Session(workspaceID: workspace.id, agentKind: .codex))

        #expect(try await store.session(id: session.id)?.agentKind == .codex)
        let listed = try await store.sessions(workspaceID: workspace.id)
        #expect(listed.first?.agentKind == .codex)
    }

    @Test func changingTheBackendLeavesTheRunnersColumnsAlone() async throws {
        let store = try makeTestStore("agent-kind-narrow")
        let (session, _) = try await makeCodexSession(store)

        try await store.update(sessionID: session.id) {
            $0.agentSessionID = "thread-1"
            $0.inputTokens = 42
        }
        try await store.updateSessionPreferences(id: session.id, agentKind: .codex)

        let stored = try #require(try await store.session(id: session.id))
        #expect(stored.agentKind == .codex)
        #expect(stored.agentSessionID == "thread-1")
        #expect(stored.inputTokens == 42)
    }

    @Test func launchesTheServerWithTheWindowTheChatIsSetTo() async throws {
        let store = try makeTestStore("codex-runner-window")
        let (session, _) = try await makeCodexSession(store)
        try await store.setSetting(
            ComposerControls.contextWindowKey(sessionID: session.id), "1000000"
        )
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)

        try await runner.send("hello")

        let arguments = box.process.launch.arguments
        #expect(arguments.contains("model_context_window=1000000"))
        #expect(arguments.contains("model_auto_compact_token_limit=900000"))
    }

    @Test func startsAnotherServerWhenTheWindowChangesMidChat() async throws {
        let store = try makeTestStore("codex-runner-window-change")
        let (session, _) = try await makeCodexSession(store)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)

        try await runner.send("first")
        #expect(box.processes.count == 1)
        #expect(!box.process.launch.arguments.contains("model_context_window=500000"))

        try await store.setSetting(
            ComposerControls.contextWindowKey(sessionID: session.id), "500000"
        )
        try await runner.send("second")

        #expect(box.processes.count == 2)
        #expect(box.process.launch.arguments.contains("model_context_window=500000"))
        #expect(box.process.sentMethods.contains("thread/resume"))
    }

    @Test func leavesTheServerAloneWhenTheWindowHasNotChanged() async throws {
        let store = try makeTestStore("codex-runner-window-same")
        let (session, _) = try await makeCodexSession(store)
        try await store.setSetting(
            ComposerControls.contextWindowKey(sessionID: session.id), "500000"
        )
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)

        try await runner.send("first")
        try await runner.send("second")

        #expect(box.processes.count == 1)
    }

    @Test func theMigrationSurvivesBeingReplayed() async throws {
        let path = TestScratch.unique("agent-kind-replay") + ".sqlite"
        let store = try Store(path: path)
        let repo = try await store.upsert(Repo(name: "r", path: "/tmp/r-\(UUID().uuidString)"))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "w", branch: "b", path: "/tmp/w", baseBranch: "main"
        ))
        let session = try await store.upsert(Session(workspaceID: workspace.id, agentKind: .codex))

        let raw = try SQLiteDatabase(path: path)
        try raw.setUserVersion(0)

        let reopened = try Store(path: path)
        let sessions = try await reopened.sessions(workspaceID: workspace.id)
        #expect(sessions.count == 1)
        #expect(sessions.first?.id == session.id)
        #expect(sessions.first?.agentKind == .codex)
    }
}

@Suite("Side conversation Codex transport", .scratchDirectory)
struct SideConversationCodexRunnerTests {
    @Test func failedStartRetriesWithContextWithoutChangingTheEditableQuestion() async throws {
        let store = try makeTestStore("side-codex-wire")
        let (createdParent, _) = try await makeCodexSession(store, agentSessionID: "parent-thread")
        let parent = try #require(try await store.session(id: createdParent.id))
        let child = try await store.openSideConversation(parentID: parent.id, streamingText: "Original context")
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: child, box: box)
        box.fail("turn/start", code: -32000, message: "Try again")
        do {
            try await runner.send("Why?")
            Issue.record("Expected the scripted first start to fail")
        } catch {
            #expect((error as? CodexRPCError)?.message == "Try again")
        }
        #expect(try await store.setting(SideConversation.contextDeliveredKey(child.id)) == nil)
        await runner.shutdown()
        let resumed = try #require(try await store.session(id: child.id))
        let retryBox = scriptedBox()
        let retryRunner = try await makeRunner(store: store, session: resumed, box: retryBox)
        try await retryRunner.send("Why?")
        let frames = box.process.stdin + retryBox.process.stdin
        let starts = frames.compactMap(JSONValue.parse).filter { $0["method"]?.stringValue == "turn/start" }
        #expect(starts.count == 2)
        for start in starts {
            #expect(start["params"]?["input"]?[0]?["text"]?.stringValue?.contains("Original context") == true)
        }
        #expect(!box.process.sentMethods.contains("thread/resume"))
        #expect(try await store.setting(SideConversation.contextDeliveredKey(child.id)) == "1")
        let messages = try await store.messages(sessionID: child.id).filter { $0.kind == .user }
        #expect(messages.allSatisfy { UserTurnPrompt.text(in: $0.payload) == "Why?" })
        #expect(try await store.session(id: parent.id) == parent)
        await retryRunner.shutdown()
    }
}

extension CodexRunnerTests {
    @Test func deliveryAcceptanceLinksTheExistingPromptToTheProviderTurn() async throws {
        let store = try makeTestStore("codex-delivery-acceptance")
        let (session, _) = try await makeCodexSession(store)
        let delivery = try await store.enqueueDelivery(Delivery(targetSessionID: session.id, body: "Only once"))
        let claimed = try await store.claimDelivery(id: delivery.id)
        #expect(claimed)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)
        try await runner.sendDelivery(delivery)
        #expect(try await store.delivery(id: delivery.id)?.state == .accepted)
        #expect(try await store.delivery(id: delivery.id)?.providerTurnID == "01a02144-3bab-7fe3-a92c-6eec594d84fd")
        #expect(try await store.messages(sessionID: session.id).filter { $0.kind == .user }.count == 1)
        await runner.shutdown()
    }

    @Test func stopInterruptsOwnedChildrenAsWellAsTheParent() async throws {
        let store = try makeTestStore("codex-family-stop")
        let (session, _) = try await makeCodexSession(store)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)
        try await runner.send("Start a child")
        box.process.emit(#"{"method":"turn/started","params":{"threadId":"child","turn":{"id":"child-turn","status":"inProgress","items":[]}}}"#)
        box.process.emit(#"{"method":"item/completed","params":{"threadId":"01a02144-3b7e-7233-97f2-73ebd5105085","turnId":"01a02144-3bab-7fe3-a92c-6eec594d84fd","item":{"id":"spawn-child","type":"subAgentActivity","agentPath":"/root/child","agentThreadId":"child","kind":"started"}}}"#)
        await eventually("registered child") { runner.presentationFeed?.hasBackgroundWork == true }
        runner.cancelNow()
        await eventually("family interrupts") {
            let frames = box.process.stdin.compactMap(JSONValue.parse).filter { $0["method"]?.stringValue == "turn/interrupt" }
            return frames.contains { $0["params"]?["threadId"]?.stringValue == "child" }
                && frames.contains { $0["params"]?["threadId"]?.stringValue == "01a02144-3b7e-7233-97f2-73ebd5105085" }
        }
        await runner.shutdown()
    }

    @Test func idleEvictionPreservesRunningTurnsAndPendingDeliveries() async throws {
        let store = try makeTestStore("codex-idle-guard")
        let (session, _) = try await makeCodexSession(store, agentSessionID: "resumable")
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)
        let delivery = try await store.enqueueDelivery(Delivery(targetSessionID: session.id, body: "waiting"))
        let queuedEviction = await runner.evictIfIdle(for: .zero)
        #expect(!queuedEviction)
        _ = try await store.cancelDelivery(id: delivery.id)
        try await runner.send("working")
        let activeEviction = await runner.evictIfIdle(for: .zero)
        #expect(!activeEviction)
        box.process.emit(#"{"method":"turn/completed","params":{"threadId":"01a02144-3b7e-7233-97f2-73ebd5105085","turn":{"id":"01a02144-3bab-7fe3-a92c-6eec594d84fd","status":"completed","items":[]}}}"#)
        await eventually("idle turn") { await runner.currentSession.state == .idle }
        let idleEviction = await runner.evictIfIdle(for: .zero)
        #expect(idleEviction)
        await #expect(throws: ProviderIdleError.self) { try await runner.send("must use a new runner") }
        await runner.shutdown()
    }

    @Test func theNextSendAfterAnIdleEvictionResumesTheSameThread() async throws {
        let store = try makeTestStore("codex-idle-resume")
        let (session, _) = try await makeCodexSession(store)
        let first = scriptedBox()
        let evicted = try await makeRunner(store: store, session: session, box: first)
        try await evicted.send("first")
        first.process.emit(#"{"method":"turn/completed","params":{"threadId":"01a02144-3b7e-7233-97f2-73ebd5105085","turn":{"id":"01a02144-3bab-7fe3-a92c-6eec594d84fd","status":"completed","items":[]}}}"#)
        await eventually("idle turn") { await evicted.currentSession.state == .idle }
        let wasEvicted = await evicted.evictIfIdle(for: .zero)
        #expect(wasEvicted)

        let reopened = try #require(try await store.session(id: session.id))
        let second = scriptedBox()
        let resumed = try await makeRunner(store: store, session: reopened, box: second)
        try await resumed.send("second")

        let resume = second.process.sentFrame { $0["method"]?.stringValue == "thread/resume" }
        #expect(first.process.sentMethods.contains("thread/start"))
        #expect(!second.process.sentMethods.contains("thread/start"))
        #expect(resume?["params"]?["threadId"]?.stringValue == "01a02144-3b7e-7233-97f2-73ebd5105085")
        await resumed.shutdown()
    }
}

extension CodexRunnerTests {
    @Test func anAmbiguousSteerFailureDoesNotStartTheSameMessageAgain() async throws {
        let store = try makeTestStore("codex-ambiguous-steer")
        let (session, _) = try await makeCodexSession(store)
        let box = scriptedBox()
        let runner = try await makeRunner(store: store, session: session, box: box)
        try await runner.send("first")
        box.fail("turn/steer", code: -32603, message: "internal failure after dispatch")
        let delivery = try await store.enqueueDelivery(Delivery(targetSessionID: session.id, body: "follow up"))
        _ = try await store.claimDelivery(id: delivery.id)
        await #expect(throws: CodexRPCError.self) { try await runner.sendDelivery(delivery) }
        #expect(box.process.sentMethods.filter { $0 == "turn/start" }.count == 1)
        #expect(try await store.delivery(id: delivery.id)?.state == .uncertain)
        await runner.shutdown()
    }

    @Test func anExplicitTurnRejectionReturnsThePromptToPending() async throws {
        let store = try makeTestStore("codex-definitive-rejection")
        let (session, _) = try await makeCodexSession(store)
        let box = scriptedBox()
        box.fail("turn/start", code: -32602, message: "invalid model parameter")
        let runner = try await makeRunner(store: store, session: session, box: box)
        let delivery = try await store.enqueueDelivery(Delivery(targetSessionID: session.id, body: "safe to retry"))
        _ = try await store.claimDelivery(id: delivery.id)
        await #expect(throws: CodexRPCError.self) { try await runner.sendDelivery(delivery) }
        #expect(try await store.delivery(id: delivery.id)?.state == .pending)
        #expect(try await store.messages(sessionID: session.id).filter { $0.kind == .user }.count == 1)
        await runner.shutdown()
    }
}

extension CodexRunnerTests {
    private static let parentThread = "01a02144-3b7e-7233-97f2-73ebd5105085"
    private static let parentTurn = "01a02144-3bab-7fe3-a92c-6eec594d84fd"

    private func rewindableBox() -> ProcessBox {
        let box = scriptedBox()
        box.reply(to: "thread/read", with: .object([
            "thread": .object(["id": .string(Self.parentThread), "historyMode": .string("paginated")]),
        ]))
        box.reply(to: "thread/revert", with: .object([:]))
        return box
    }

    @Test func aCommandLeftRunningAfterItsTurnBlocksRewindUntilItEnds() async throws {
        let store = try makeTestStore("codex-rewind-background-command")
        let (session, _) = try await makeCodexSession(store)
        let box = rewindableBox()
        let runner = try await makeRunner(store: store, session: session, box: box)
        try await runner.send("Start the dev server")
        box.process.emit(#"{"method":"item/started","params":{"threadId":"\#(Self.parentThread)","turnId":"\#(Self.parentTurn)","item":{"type":"commandExecution","id":"exec-dev","command":"/bin/zsh -lc 'npm run dev'","status":"inProgress"}}}"#)
        box.process.emit(#"{"method":"turn/completed","params":{"threadId":"\#(Self.parentThread)","turn":{"id":"\#(Self.parentTurn)","status":"completed","items":[]}}}"#)
        await eventually("background command") { runner.presentationFeed?.hasBackgroundWork == true }
        await eventually("idle turn") { await runner.currentSession.state == .idle }
        await #expect(throws: ConversationRewindError.busy) { try await runner.rewind(beforeTurnID: Self.parentTurn) }
        #expect(!box.process.sentMethods.contains("thread/revert"))

        box.process.emit(#"{"method":"item/completed","params":{"threadId":"\#(Self.parentThread)","turnId":"\#(Self.parentTurn)","item":{"type":"commandExecution","id":"exec-dev","command":"/bin/zsh -lc 'npm run dev'","status":"completed","exitCode":0,"durationMs":10,"aggregatedOutput":""}}}"#)
        await eventually("command ended") { runner.presentationFeed?.hasBackgroundWork == false }
        try await runner.rewind(beforeTurnID: Self.parentTurn)
        #expect(box.process.sentMethods.contains("thread/revert"))
        await runner.shutdown()
    }

    @Test func aRewindForgetsTheRowsItWasHoldingForTheScreen() async throws {
        let store = try makeTestStore("codex-rewind-forgets-held-rows")
        let (session, _) = try await makeCodexSession(store)
        let box = rewindableBox()
        let runner = try await makeRunner(store: store, session: session, box: box)
        let relay = try #require(runner.storedMessages)
        relay.deposit(Message(sessionID: session.id, seq: 9, kind: .notice, payload: Data("{}".utf8)))
        try await runner.send("Start")
        box.process.emit(#"{"method":"turn/completed","params":{"threadId":"\#(Self.parentThread)","turn":{"id":"\#(Self.parentTurn)","status":"completed","items":[]}}}"#)
        await eventually("idle turn") { await runner.currentSession.state == .idle }
        #expect(relay.heldCount > 0)

        try await runner.rewind(beforeTurnID: Self.parentTurn)

        #expect(relay.heldCount == 0)
        await runner.shutdown()
    }
}
