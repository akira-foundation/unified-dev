import Foundation
import Testing
@testable import Core

@Suite("A request the app sends on the owner's behalf", .tags(.persistence), .scratchDirectory)
struct AppRequestTests {
    private static let report = CodeBlockReport.message(
        command: "swift --version",
        run: .finished(status: 0, output: "Swift 6.2\n", duration: .milliseconds(100))
    ) ?? ""

    private func makeSession(_ store: Store, agent: AgentKind = .claudeCode) async throws -> Session {
        let repo = try await store.upsert(Repo(name: "hidden", path: TestScratch.unique("repo")))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "w", branch: "topic", path: TestScratch.unique("worktree"), baseBranch: "main"
        ))
        return try await store.upsert(Session(workspaceID: workspace.id, agentKind: agent))
    }

    private func claim(_ delivery: Delivery, in store: Store) async throws -> Message {
        _ = try await store.enqueueDelivery(delivery)
        #expect(try await store.claimDelivery(id: delivery.id))
        let messages = try await store.messages(sessionID: delivery.targetSessionID)
        return try #require(messages.last)
    }

    @Test("the agent is handed every byte of the report, markers included")
    func reachesTheAgentUnchanged() {
        let delivery = AppRequest.delivery(to: SessionID("s"), text: Self.report, interactionMode: .plan)

        #expect(delivery.sent == Self.report)
        #expect(delivery.sent.contains(BridgeUntrustedText.opening))
        #expect(delivery.sent.contains(BridgeUntrustedText.closing))
        #expect(delivery.interactionMode == InteractionMode.plan)
        #expect(delivery.body.isEmpty)
    }

    @Test(
        "the stored row stays hidden after the store is reopened, whichever agent runs the chat",
        arguments: [AgentKind.claudeCode, .codex, .grok]
    )
    func survivesAReload(agent: AgentKind) async throws {
        let path = TestScratch.unique("app-request") + ".sqlite"
        let store = try Store(path: path)
        let session = try await makeSession(store, agent: agent)
        _ = try await claim(
            AppRequest.delivery(to: session.id, text: Self.report, interactionMode: nil), in: store
        )

        let reopened = try Store(path: path)
        let row = try #require(await reopened.messages(sessionID: session.id).last)

        #expect(row.kind == .crew)
        #expect(AppRequest.isHidden(kind: row.kind, payload: row.payload))
        #expect(AppRequest.sentText(kind: row.kind, payload: row.payload) == Self.report)
    }

    @Test("the same words typed or pasted by the owner stay the owner's bubble")
    func theOwnersLookalikeStaysVisible() async throws {
        let store = try makeTestStore("app-request-lookalike")
        let session = try await makeSession(store)
        let row = try await claim(Delivery(targetSessionID: session.id, body: Self.report), in: store)

        #expect(row.kind == .user)
        #expect(!AppRequest.isHidden(kind: row.kind, payload: row.payload))
        #expect(UserTurnPrompt.text(in: row.payload) == Self.report)
    }

    @Test("the mark's own JSON pasted by the owner does not hide their message")
    func theOwnerPastingTheMarkStaysVisible() async throws {
        let store = try makeTestStore("app-request-forged-owner")
        let session = try await makeSession(store)
        let forged = String(decoding: try CrewMessage.appRequest("hidden").payload(), as: UTF8.self)
        let row = try await claim(Delivery(targetSessionID: session.id, body: forged), in: store)

        #expect(row.kind == .user)
        #expect(!AppRequest.isHidden(kind: row.kind, payload: row.payload))
    }

    @Test("a user row holding the mark's JSON as its payload is not hidden")
    func theMarkNeedsTheCrewKind() throws {
        let payload = try CrewMessage.appRequest("hidden").payload()

        #expect(!AppRequest.isHidden(kind: .user, payload: payload))
        #expect(!AppRequest.isHidden(kind: .assistantText, payload: payload))
        #expect(AppRequest.isHidden(kind: .crew, payload: payload))
    }

    @Test("a line the agent prints with the mark's JSON is never stored as a crew row")
    func theAgentCannotPrintTheMark() throws {
        let forged = String(decoding: try CrewMessage.appRequest("hidden").payload(), as: UTF8.self)

        #expect(AgentEvent.decode(line: forged)?.kind != .crew)
    }

    @Test("nothing a crew member says is hidden, however empty or however worded")
    func otherCrewMessagesStayDrawn() throws {
        let said = CrewMessage.said(from: "reader", text: Self.report, sender: .subagent)

        #expect(!AppRequest.isHidden(kind: .crew, payload: try said.payload()))
        #expect(!AppRequest.isHidden(Delivery(targetSessionID: SessionID("s"), kind: .message, crew: said)))
        #expect(SendingSlot.drawing(of: said) != nil)
    }

    @Test("a request that says something all the same draws nothing")
    func theEventDecidesNotTheText() {
        let crew = CrewMessage(event: .appRequest, sender: .unifieddev, from: "x", text: "words", sent: "words")

        #expect(SendingSlot.drawing(of: crew) == nil)
    }

    @Test("sending or queued, a request draws nothing and takes no edit")
    func slotDrawsNothingWhileHealthy() {
        let delivery = AppRequest.delivery(to: SessionID("s"), text: Self.report, interactionMode: nil)

        #expect(SendingSlot.drawing(of: delivery) == nil)
        #expect(!PendingMessageEdit.canEdit(delivery))
        #expect(!DeliverySteer.canSteer(delivery, hold: .turn, on: .claudeCode))
        #expect(PendingMessageReturn.returning(from: [delivery]).isEmpty)
    }

    @Test("claimed or accepted, a request still draws nothing", arguments: [Delivery.State.claimed, .accepted])
    func slotDrawsNothingOnTheWay(state: Delivery.State) {
        var delivery = AppRequest.delivery(to: SessionID("s"), text: Self.report, interactionMode: nil)
        delivery.deliveredSeq = 3
        delivery.state = state

        #expect(SendingSlot.drawing(of: delivery) == nil)
    }

    @Test("a request whose agent would not start is drawn, so the owner can retry or delete it")
    func aReleasedClaimShows() async throws {
        let store = try makeTestStore("app-request-released")
        let session = try await makeSession(store)
        let delivery = AppRequest.delivery(to: session.id, text: Self.report, interactionMode: nil)
        _ = try await claim(delivery, in: store)
        try await store.releaseDeliveryClaim(id: delivery.id)

        let stuck = try #require(await store.pendingDeliveries(sessionID: session.id).first)

        #expect(stuck.state == .pending)
        #expect(SendingSlot.drawing(of: stuck) == .stuckRequest)
    }

    @Test("Stop drops a queued request and leaves the owner's own message to return")
    func stopDropsTheRequest() {
        let request = AppRequest.delivery(to: SessionID("s"), text: Self.report, interactionMode: nil)
        let owner = Delivery(targetSessionID: SessionID("s"), body: "mine")
        let crew = Delivery(
            targetSessionID: SessionID("s"), kind: .report,
            crew: CrewMessage.said(from: "reader", text: "Done.", sender: .subagent)
        )
        let comment = Delivery(
            targetSessionID: SessionID("s"), kind: .canvasComment, body: "A comment from the owner on a canvas.",
            canvasDocumentPath: "/w/d.udcanvas"
        )
        var sending = request
        sending.state = .claimed

        #expect(PendingMessageReturn.dropping(from: [request, owner, crew, comment, sending]).map(\.id) == [request.id])
        #expect(PendingMessageReturn.returning(from: [request, owner, comment]).map(\.id) == [owner.id])
    }

    @Test("deleting a stuck request does not claim it stays in the conversation")
    func discardWording() {
        var delivery = AppRequest.delivery(to: SessionID("s"), text: Self.report, interactionMode: nil)
        delivery.deliveredSeq = 3

        let question = PendingMessageDiscard.question(for: delivery, composerDraft: "")

        #expect(question.title == "Delete this request?")
        #expect(!question.message.contains("stays in the conversation"))
    }

    @Test("a request the app cannot confirm is drawn, so the queue it holds can be released")
    func anUnconfirmedRequestShows() async throws {
        let store = try makeTestStore("app-request-uncertain")
        let session = try await makeSession(store)
        let delivery = AppRequest.delivery(to: session.id, text: Self.report, interactionMode: nil)
        _ = try await claim(delivery, in: store)
        try await store.beginDeliveryDispatch(id: delivery.id)

        let stuck = try #require(await store.pendingDeliveries(sessionID: session.id).first)

        #expect(stuck.state == .uncertain)
        #expect(SendingSlot.drawing(of: stuck) == .stuckRequest)
        #expect(PendingMessageDiscard.canDiscard(stuck))
        #expect(!PendingMessageEdit.canEdit(stuck))
    }

    @Test("the row retires the sending slot as the owner's row does")
    func retiresTheSlot() {
        let delivery = AppRequest.delivery(to: SessionID("s"), text: Self.report, interactionMode: nil)

        #expect(SendingSlot.retires(delivery, onPersisting: .crew))
    }

    @Test("search does not find it, because a hit would open on a row nobody can see")
    func searchSkipsIt() async throws {
        let payload = try CrewMessage.appRequest(Self.report).payload()
        #expect(TranscriptSearchText.indexable(kind: .crew, payload: payload) == nil)

        let store = try makeTestStore("app-request-search")
        let session = try await makeSession(store)
        _ = try await claim(
            AppRequest.delivery(to: session.id, text: "uniquewordfromtheoutput", interactionMode: nil), in: store
        )
        #expect(try await store.searchTranscripts("Unified").isEmpty)
    }

    @Test("chat_read gives a reader the full text, marked as not the owner's")
    func chatReadIsHonest() throws {
        let message = Message(
            sessionID: SessionID("s"), seq: 1, kind: .crew, payload: try CrewMessage.appRequest(Self.report).payload()
        )
        let owner = Message(sessionID: SessionID("s"), seq: 2, kind: .user, payload: Data(#"""
            {"type":"user","message":{"role":"user","content":[{"type":"text","text":"mine"}]}}
            """#.utf8))
        let page = try ChatTranscriptPage.make(
            messages: [message, owner], cursor: .init(sessionID: SessionID("s")), limit: 50
        )

        #expect(page.messages[0]["kind"]?.stringValue == "crew")
        #expect(page.messages[0]["content"]?.stringValue == Self.report)
        #expect(page.messages[0]["sent_by"]?.stringValue == AppRequest.sentBy)
        #expect(page.messages[1]["kind"]?.stringValue == "user")
        #expect(page.messages[1]["sent_by"] == nil)
    }

    @Test("readers of the owner's words find none in it, so no title or task comes from it")
    func noOwnerWordsInside() throws {
        let payload = try CrewMessage.appRequest(Self.report).payload()

        #expect(UserTurnPayload.text(from: payload) == nil)
        #expect(UserTurnPrompt.text(in: payload).isEmpty)
    }

    @Test("a turn it opened can be rewound, and the draft stays the owner's")
    func rewindKeepsTheDraft() async throws {
        for existing in ["", "An existing draft"] {
            let store = try makeTestStore("app-request-rewind")
            let session = try await makeSession(store, agent: .codex)
            let delivery = AppRequest.delivery(to: session.id, text: Self.report, interactionMode: nil)
            let row = try await claim(delivery, in: store)
            _ = try await store.appendNext(sessionID: session.id, kind: .result, payload: Data("{}".utf8))
            var checkpoint = TurnCheckpoint(
                sessionID: session.id, startSeq: row.seq, before: GitSnapshot(sessionID: session.id)
            )
            checkpoint.providerTurnID = "turn"
            try await store.saveTurnCheckpoint(checkpoint)
            try await store.saveDraft(sessionID: session.id, body: existing)

            let backup = try await store.prepareTranscriptRewind(checkpoint)
            var journal = CheckpointRewind(checkpoint: checkpoint, recovery: nil, restoringFiles: false)
            try await store.saveCheckpointRewind(journal)
            journal.stage = .providerReverted
            try await store.saveCheckpointRewind(journal)
            let restored = try await store.completeTranscriptRewind(sessionID: session.id)

            #expect(backup.prompt.isEmpty)
            #expect(restored == existing)
            #expect(try await store.messages(sessionID: session.id).isEmpty)
        }
    }

    @Test("a turn another crew message opened still refuses to rewind")
    func otherCrewTurnsStayRefused() async throws {
        let store = try makeTestStore("app-request-rewind-crew")
        let session = try await makeSession(store, agent: .codex)
        let crew = CrewMessage.said(from: "reader", text: "Done.", sender: .subagent)
        let row = try await claim(Delivery(targetSessionID: session.id, kind: .report, crew: crew), in: store)
        let checkpoint = TurnCheckpoint(
            sessionID: session.id, startSeq: row.seq, before: GitSnapshot(sessionID: session.id)
        )

        await #expect(throws: SnapshotFailure.self) {
            _ = try await store.prepareTranscriptRewind(checkpoint)
        }
    }

    private static let conflictRequest = FixConflictsPromptContext(
        workspaceName: "Glyphs", number: 42, branch: "feature/glyphs", baseBranch: "main"
    ).request(template: PromptRegistry.definition(for: .fixConflicts).defaultTemplate)

    @Test(
        "every request of the bar stays hidden after a reload, whichever agent runs the chat",
        arguments: [
            PromptID.createPullRequest, .pushLocalWork, .markReadyForReview,
            .mergePullRequest, .fixConflicts, .continueAfterMerge,
        ],
        [AgentKind.claudeCode, .codex, .grok]
    )
    func everyBarRequestSurvivesAReload(prompt: PromptID, agent: AgentKind) async throws {
        let text = PromptRegistry.definition(for: prompt).defaultTemplate
        let path = TestScratch.unique("app-request-bar") + ".sqlite"
        let store = try Store(path: path)
        let session = try await makeSession(store, agent: agent)
        _ = try await claim(AppRequest.delivery(to: session.id, text: text, interactionMode: nil), in: store)

        let reopened = try Store(path: path)
        let row = try #require(await reopened.messages(sessionID: session.id).last)

        #expect(row.kind == .crew)
        #expect(AppRequest.sentText(kind: row.kind, payload: row.payload) == text)
    }

    @Test("only the pull request bar hides its turn: an agent's merge and the toolbar stay in front of the owner")
    func onlyTheBarHides() {
        #expect(AppRequest.Source.pullRequestBar.hidesTurn)
        #expect(!AppRequest.Source.agentThroughBridge.hidesTurn)
        #expect(!AppRequest.Source.inspectorToolbar.hidesTurn)
        #expect(AppRequest.Source.allCases.filter(\.hidesTurn) == [.pullRequestBar])
    }

    @Test("a merge from the bar is refused while the agent is busy, because it would wait out of sight")
    func aHiddenMergeWaitsForTheTurn() {
        #expect(AppRequest.mergeRefusal(from: .pullRequestBar, agentIsBusy: true)
            == "The agent is still working here, so the merge was not queued out of sight."
                + " Merge again when it finishes.")
        #expect(AppRequest.mergeRefusal(from: .pullRequestBar, agentIsBusy: false) == nil)
    }

    @Test("a merge that stays visible may wait in the queue, where the owner can delete it")
    func aVisibleMergeMayQueue() {
        #expect(AppRequest.mergeRefusal(from: .agentThroughBridge, agentIsBusy: true) == nil)
        #expect(AppRequest.mergeRefusal(from: .inspectorToolbar, agentIsBusy: true) == nil)
    }

    @Test("the same conflict request pasted by the owner stays the owner's bubble")
    func thePastedConflictRequestStaysVisible() async throws {
        let store = try makeTestStore("app-request-conflicts-lookalike")
        let session = try await makeSession(store)
        let row = try await claim(Delivery(targetSessionID: session.id, body: Self.conflictRequest), in: store)

        #expect(row.kind == .user)
        #expect(!AppRequest.isHidden(kind: row.kind, payload: row.payload))
    }

    @Test("a conflict request waiting behind a running turn draws nothing and returns to no composer")
    func aQueuedConflictRequestStaysOutOfTheComposer() {
        let queued = AppRequest.delivery(to: SessionID("s"), text: Self.conflictRequest, interactionMode: nil)

        #expect(SendingSlot.drawing(of: queued) == nil)
        #expect(!PendingMessageEdit.canEdit(queued))
        #expect(PendingMessageReturn.returning(from: [queued]).isEmpty)
        #expect(PendingMessageReturn.draft(taking: PendingMessageReturn.returning(from: [queued]), into: "mine") == "mine")
    }

    @Test("a conflict request that cannot be confirmed is drawn, so the queue it holds can be released")
    func anUnconfirmedConflictRequestShows() async throws {
        let store = try makeTestStore("app-request-conflicts-uncertain")
        let session = try await makeSession(store)
        let delivery = AppRequest.delivery(to: session.id, text: Self.conflictRequest, interactionMode: nil)
        _ = try await claim(delivery, in: store)
        try await store.beginDeliveryDispatch(id: delivery.id)

        let stuck = try #require(await store.pendingDeliveries(sessionID: session.id).first)

        #expect(SendingSlot.drawing(of: stuck) == .stuckRequest)
        #expect(PendingMessageDiscard.canDiscard(stuck))
    }

    @Test("a preview scenario seeds it as the same hidden row")
    func aScenarioSeedsTheSameRow() async throws {
        let store = try makeTestStore("app-request-seed")
        let seeder = PreviewScenarioSeeder(
            manager: WorkspaceManager(store: store), scratchRoot: TestScratch.unique("app-request-scratch")
        )
        _ = try await seeder.seed(PreviewScenario.read(Data(#"""
            {"projects":[{"name":"a","workspaces":[{"name":"w","branch":"w","chats":[
              {"title":"Run","messages":[
                {"from":"user","text":"mine"},
                {"from":"app","text":"the report"},
                {"from":"agent","text":"read it"}]}]}]}]}
            """#.utf8)))

        let workspace = try #require(await store.workspaces().first)
        let session = try #require(await store.sessions(workspaceID: workspace.id).first)
        let rows = try await store.messages(sessionID: session.id)

        #expect(rows.map(\.kind) == [.user, .crew, .assistantText])
        #expect(AppRequest.sentText(kind: rows[1].kind, payload: rows[1].payload) == "the report")
    }
}
