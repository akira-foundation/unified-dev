import Testing
import Foundation
@testable import Core

@Suite("What holds a queued message")
struct DeliveryHoldTests {
    @Test("a running setup script holds everything behind it, on every backend")
    func setupWins() {
        let hold = DeliveryHold.of(
            isRunningSetup: true, isTurnRunning: true, isAwaitingQuestion: true
        )
        #expect(hold == .setup)
        for agent in AgentKind.allCases {
            #expect(!hold.allowsDelivery(on: agent))
        }
    }

    @Test("a question is named before the turn it is holding open")
    func questionBeatsTurn() {
        let hold = DeliveryHold.of(
            isRunningSetup: false, isTurnRunning: true, isAwaitingQuestion: true
        )
        #expect(hold == .question)
    }

    @Test("a running turn is still named as one, whatever the backend does about it")
    func turnIsStillNamed() {
        let hold = DeliveryHold.of(
            isRunningSetup: false, isTurnRunning: true, isAwaitingQuestion: false
        )
        #expect(hold == .turn)
    }

    @Test("a running turn holds the queue only where a line cannot be written into one")
    func turnHoldsPerBackend() {
        let hold = DeliveryHold.turn
        #expect(hold.allowsDelivery(on: .claudeCode))
        #expect(hold.allowsDelivery(on: .codex))
        #expect(!hold.allowsDelivery(on: .cursor))
        #expect(!hold.allowsDelivery(on: .openCode))
        for agent in AgentKind.allCases {
            #expect(hold.allowsDelivery(on: agent) == agent.acceptsMidTurnMessage)
        }
    }

    @Test("a question and a setup script hold on every backend, including the two that take a message mid turn")
    func questionAndSetupHoldEverywhere() {
        for agent in AgentKind.allCases {
            #expect(!DeliveryHold.question.allowsDelivery(on: agent))
            #expect(!DeliveryHold.setup.allowsDelivery(on: agent))
        }
    }

    @Test("only a runnable backend claims to take a message mid turn")
    func onlyRunnableBackendsAccept() {
        for agent in AgentKind.allCases where agent.acceptsMidTurnMessage {
            #expect(agent.canRunWorkspaces)
        }
    }

    @Test("a setup script that failed holds nothing, so the queue still moves")
    func failedSetupDoesNotHold() {
        let hold = DeliveryHold.of(
            isRunningSetup: false, isTurnRunning: false, isAwaitingQuestion: false
        )
        #expect(hold == .none)
        #expect(hold.allowsDelivery(on: .claudeCode))
    }

    @Test("an idle session lets the queue move, on every backend")
    func idleDelivers() {
        let hold = DeliveryHold.of(
            isRunningSetup: false, isTurnRunning: false, isAwaitingQuestion: false
        )
        #expect(hold == .none)
        for agent in AgentKind.allCases {
            #expect(hold.allowsDelivery(on: agent))
        }
    }

    @Test("everything that is holding something says what, and nothing else says anything")
    func everyHoldSpeaks() {
        for agent in AgentKind.allCases {
            for hold in DeliveryHold.allCases {
                if hold.allowsDelivery(on: agent) {
                    #expect(hold.sentence(on: agent) == nil)
                } else {
                    #expect(hold.sentence(on: agent)?.isEmpty == false)
                }
            }
        }
    }

    @Test("a running turn says nothing where the message goes into it")
    func aTurnThatHoldsNothingSaysNothing() {
        #expect(DeliveryHold.turn.sentence(on: .claudeCode) == nil)
        #expect(DeliveryHold.turn.sentence(on: .codex) == nil)
        #expect(DeliveryHold.turn.sentence(on: .cursor) == "Goes when this turn ends.")
    }

    @Test("the two that hold everywhere say the same thing everywhere")
    func heldSentencesDoNotVaryByBackend() {
        for agent in AgentKind.allCases {
            #expect(DeliveryHold.setup.sentence(on: agent) == "Goes as soon as setup finishes.")
            #expect(
                DeliveryHold.question.sentence(on: agent)
                    == "Goes once you have answered the question above."
            )
        }
        for agent in AgentKind.allCases {
            #expect(DeliveryHold.none.sentence(on: agent) == nil)
        }
    }
}

@Suite("How much of the queue may go at once")
struct DeliveryDeliverableTests {
    private func waiting(_ bodies: String...) -> [Delivery] {
        bodies.map { Delivery(targetSessionID: SessionID("s"), body: $0) }
    }

    @Test("a hold that holds lets nothing go, whatever the backend")
    func heldLetsNothingGo() {
        let queue = waiting("first", "second")
        for agent in AgentKind.allCases {
            for hold in DeliveryHold.allCases where !hold.allowsDelivery(on: agent) {
                #expect(Delivery.deliverable(from: queue, hold: hold, on: agent).isEmpty)
                #expect(Delivery.next(from: queue, hold: hold, on: agent) == nil)
            }
        }
    }

    @Test("a backend that cannot take a message mid turn hands over one")
    func oneAtATimeWhereATurnHolds() {
        let queue = waiting("first", "second", "third")
        let going = Delivery.deliverable(from: queue, hold: .none, on: .cursor)
        #expect(going.map(\.body) == ["first"])
        #expect(Delivery.deliverable(from: queue, hold: .turn, on: .cursor).isEmpty)
    }

    @Test("a backend that takes a message mid turn empties the queue, in the order it was asked for")
    func theQueueEmptiesInOrder() {
        let queue = waiting("first", "second", "third")
        for agent in AgentKind.allCases where agent.acceptsMidTurnMessage {
            #expect(
                Delivery.deliverable(from: queue, hold: .none, on: agent).map(\.body)
                    == ["first", "second", "third"]
            )
            #expect(
                Delivery.deliverable(from: queue, hold: .turn, on: agent).map(\.body)
                    == ["first", "second", "third"]
            )
        }
    }

    @Test("what may go is always a prefix of the queue, in its own order")
    func alwaysAPrefixInOrder() {
        let queue = waiting("first", "second", "third")
        for agent in AgentKind.allCases {
            for hold in DeliveryHold.allCases {
                let going = Delivery.deliverable(from: queue, hold: hold, on: agent)
                #expect(going.map(\.id) == queue.prefix(going.count).map(\.id))
                #expect(Delivery.next(from: queue, hold: hold, on: agent)?.id == going.first?.id)
            }
        }
    }
}

@Suite("The delivery queue", .tags(.persistence), .scratchDirectory)
struct DeliveryStoreTests {
    private func makeSession(in store: Store, label: String = "s") async throws -> Session {
        let repo = try await store.upsert(Repo(name: "r", path: "/tmp/r-\(label)"))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "w", branch: "b", path: "/tmp/r-\(label)-w", baseBranch: "main"
        ))
        return try await store.upsert(Session(workspaceID: workspace.id, title: "chat"))
    }

    @Test("a canvas comment keeps its kind and its document across a read")
    func aCommentKeepsItsKindAndDocument() async throws {
        let store = try makeTestStore("deliveries")
        let session = try await makeSession(in: store)
        let queued = try await store.enqueueDelivery(Delivery(
            targetSessionID: session.id, kind: .canvasComment, body: "look", canvasDocumentPath: "/w/deck.udcanvas"
        ))
        let read = try await store.pendingDeliveries(sessionID: session.id).first
        #expect(read?.kind == .canvasComment)
        #expect(read?.canvasDocumentPath == "/w/deck.udcanvas")
        #expect(read?.interactionMode == nil)
        #expect(queued.id == read?.id)
    }

    @Test("only a live chat holding a waiting comment is named for waking")
    func wakesOnlyChatsHoldingAComment() async throws {
        let store = try makeTestStore("deliveries")
        let holder = try await makeSession(in: store)
        let workspaceID = try #require(holder.workspaceID)
        let talker = try await store.upsert(Session(workspaceID: workspaceID, title: "talker"))
        let closed = try await store.upsert(Session(workspaceID: workspaceID, title: "closed"))
        let finished = try await store.upsert(Session(workspaceID: workspaceID, title: "finished"))
        let elsewhere = try await makeSession(in: store, label: "other")
        for chat in [holder, closed, elsewhere] {
            try await store.enqueueDelivery(Delivery(targetSessionID: chat.id, kind: .canvasComment, body: "look"))
        }
        try await store.enqueueDelivery(Delivery(targetSessionID: talker.id, body: "typed"))
        let left = try await store.enqueueDelivery(Delivery(targetSessionID: finished.id, kind: .canvasComment, body: "gone"))
        _ = try await store.markDelivered(id: left.id)
        try await store.update(sessionID: closed.id) { $0.archivedAt = Date() }

        #expect(try await store.sessionsHoldingCanvasComments(workspaceID: workspaceID) == [holder.id])
    }

    @Test("archiving cancels the comments a workspace still has waiting, and no message")
    func archivingCancelsOnlyComments() async throws {
        let store = try makeTestStore("deliveries")
        let chat = try await makeSession(in: store)
        let workspaceID = try #require(chat.workspaceID)
        let elsewhere = try await makeSession(in: store, label: "other")
        let comment = try await store.enqueueDelivery(Delivery(targetSessionID: chat.id, kind: .canvasComment, body: "look"))
        let message = try await store.enqueueDelivery(Delivery(targetSessionID: chat.id, body: "typed"))
        let other = try await store.enqueueDelivery(Delivery(targetSessionID: elsewhere.id, kind: .canvasComment, body: "look"))
        let left = try await store.enqueueDelivery(Delivery(targetSessionID: chat.id, kind: .canvasComment, body: "left"))
        _ = try await store.markDelivered(id: left.id)

        let cancelled = try await store.cancelQueuedCanvasComments(workspaceID: workspaceID)

        #expect(cancelled.map(\.id) == [comment.id])
        #expect(try await store.delivery(id: left.id)?.state == .accepted)
        #expect(try await store.pendingDeliveries(sessionID: chat.id).map(\.id) == [message.id])
        #expect(try await store.pendingDeliveries(sessionID: elsewhere.id).map(\.id) == [other.id])
    }

    @Test("a database with delivery rows keeps them through the canvas column")
    func upgradingKeepsExistingRows() async throws {
        let path = TestScratch.unique("canvas-column") + ".sqlite"
        let store = try Store(path: path)
        let chat = try await makeSession(in: store)
        let queued = try await store.enqueueDelivery(Delivery(targetSessionID: chat.id, body: "still waiting"))
        let left = try await store.enqueueDelivery(Delivery(targetSessionID: chat.id, body: "already gone"))
        _ = try await store.markDelivered(id: left.id)
        let current = try SQLiteDatabase(path: path).readUserVersion()
        let raw = try SQLiteDatabase(path: path)
        try raw.execute("ALTER TABLE deliveries DROP COLUMN canvas_document_path;")
        try raw.setUserVersion(current - 9)

        let upgraded = try Store(path: path)

        #expect(try SQLiteDatabase(path: path).readUserVersion() == current)
        let waiting = try await upgraded.pendingDeliveries(sessionID: chat.id)
        #expect(waiting.map(\.id) == [queued.id])
        #expect(waiting.first?.body == "still waiting")
        #expect(waiting.first?.canvasDocumentPath == nil)
        #expect(waiting.first?.kind == .owner)
        #expect(try await upgraded.delivery(id: left.id)?.state == .accepted)
        let comment = try await upgraded.enqueueDelivery(Delivery(
            targetSessionID: chat.id, kind: .canvasComment, body: "look", canvasDocumentPath: "/w/deck.udcanvas"
        ))
        #expect(try await upgraded.delivery(id: comment.id)?.canvasDocumentPath == "/w/deck.udcanvas")
    }

    @Test("rewriting a queued delivery changes what will be claimed, and nothing that has left")
    func rewritingTouchesOnlyAQueuedDelivery() async throws {
        let store = try makeTestStore("deliveries")
        let session = try await makeSession(in: store)
        let queued = try await store.enqueueDelivery(Delivery(targetSessionID: session.id, kind: .canvasComment, body: "old"))

        try await store.rewriteQueuedDelivery(id: queued.id, body: "new")
        #expect(try await store.delivery(id: queued.id)?.body == "new")

        _ = try await store.claimDelivery(id: queued.id)
        try await store.rewriteQueuedDelivery(id: queued.id, body: "late")
        #expect(try await store.delivery(id: queued.id)?.body == "new")
    }

    @Test("hands back what was asked for first, first")
    func keepsTheOrderItWasAsked() async throws {
        let store = try makeTestStore("deliveries")
        let session = try await makeSession(in: store)

        try await store.enqueueDelivery(
            Delivery(targetSessionID: session.id, body: "list the technologies used")
        )
        try await store.enqueueDelivery(Delivery(targetSessionID: session.id, body: "test"))

        let pending = try await store.pendingDeliveries(sessionID: session.id)
        #expect(pending.map(\.body) == ["list the technologies used", "test"])
    }

    @Test("keeps the order even when two land in the same instant")
    func breaksTiesByInsertionOrder() async throws {
        let store = try makeTestStore("deliveries-tie")
        let session = try await makeSession(in: store, label: "tie")
        let instant = Date()

        for body in ["first", "second", "third", "fourth"] {
            try await store.enqueueDelivery(
                Delivery(targetSessionID: session.id, body: body, createdAt: instant)
            )
        }

        let pending = try await store.pendingDeliveries(sessionID: session.id)
        #expect(pending.map(\.body) == ["first", "second", "third", "fourth"])
    }

    @Test("hands over the opening prompt before anything typed while setup was running")
    func openingPromptGoesBeforeWhatWasTypedDuringSetup() async throws {
        let store = try makeTestStore("deliveries-opening")
        let session = try await makeSession(in: store, label: "opening")

        try await store.enqueueDelivery(
            Delivery(targetSessionID: session.id, body: "list the technologies used")
        )
        try await store.enqueueDelivery(Delivery(targetSessionID: session.id, body: "test"))

        let duringSetup = try await store.pendingDeliveries(sessionID: session.id)
        for agent in AgentKind.allCases {
            #expect(Delivery.next(from: duringSetup, hold: .setup, on: agent) == nil)
        }

        let first = try #require(Delivery.next(from: duringSetup, hold: .none, on: .claudeCode))
        #expect(first.body == "list the technologies used")
        try await store.markDelivered(id: first.id)

        let duringTurn = try await store.pendingDeliveries(sessionID: session.id)
        #expect(Delivery.next(from: duringTurn, hold: .turn, on: .cursor) == nil)
        #expect(Delivery.next(from: duringTurn, hold: .turn, on: .claudeCode)?.body == "test")
        #expect(Delivery.next(from: duringTurn, hold: .none, on: .claudeCode)?.body == "test")
    }

    @Test("a delivered message leaves the queue and stays out of it")
    func deliveredLeavesTheQueue() async throws {
        let store = try makeTestStore("deliveries-drain")
        let session = try await makeSession(in: store, label: "drain")
        let first = try await store.enqueueDelivery(
            Delivery(targetSessionID: session.id, body: "one")
        )
        try await store.enqueueDelivery(Delivery(targetSessionID: session.id, body: "two"))

        try await store.markDelivered(id: first.id)

        let pending = try await store.pendingDeliveries(sessionID: session.id)
        #expect(pending.map(\.body) == ["two"])
    }

    @Test("survives the process that queued it")
    func survivesARelaunch() async throws {
        let path = TestScratch.unique("deliveries-relaunch") + ".sqlite"
        let store = try Store(path: path)
        let session = try await makeSession(in: store, label: "relaunch")
        try await store.enqueueDelivery(Delivery(targetSessionID: session.id, body: "still here"))

        let reopened = try Store(path: path)
        let pending = try await reopened.pendingDeliveries(sessionID: session.id)
        #expect(pending.map(\.body) == ["still here"])
    }

    @Test("changing your mind takes it back out")
    func cancelRemovesIt() async throws {
        let store = try makeTestStore("deliveries-cancel")
        let session = try await makeSession(in: store, label: "cancel")
        let one = try await store.enqueueDelivery(
            Delivery(targetSessionID: session.id, body: "one")
        )
        try await store.enqueueDelivery(Delivery(targetSessionID: session.id, body: "two"))

        #expect(try await store.cancelDelivery(id: one.id))
        #expect(try await store.pendingDeliveries(sessionID: session.id).map(\.body) == ["two"])
    }

    @Test("refuses to cancel a message that has already gone")
    func cancelWillNotUnsendIt() async throws {
        let store = try makeTestStore("deliveries-gone")
        let session = try await makeSession(in: store, label: "gone")
        let one = try await store.enqueueDelivery(
            Delivery(targetSessionID: session.id, body: "one")
        )
        try await store.markDelivered(id: one.id)

        #expect(try await store.cancelDelivery(id: one.id) == false)
        #expect(try await store.pendingDeliveries(sessionID: session.id).isEmpty)

        try await store.restoreDelivery(id: one.id)
        #expect(try await store.pendingDeliveries(sessionID: session.id).map(\.body) == ["one"])
    }

    @Test("comes back when the agent would not start")
    func restorePutsItBack() async throws {
        let store = try makeTestStore("deliveries-restore")
        let session = try await makeSession(in: store, label: "restore")
        let one = try await store.enqueueDelivery(
            Delivery(targetSessionID: session.id, body: "one")
        )
        try await store.enqueueDelivery(Delivery(targetSessionID: session.id, body: "two"))

        try await store.markDelivered(id: one.id)
        try await store.restoreDelivery(id: one.id)

        #expect(try await store.pendingDeliveries(sessionID: session.id).map(\.body) == ["one", "two"])
    }

    @Test("addresses a chat, not a workspace")
    func addressesOneChat() async throws {
        let store = try makeTestStore("deliveries-address")
        let repo = try await store.upsert(Repo(name: "r", path: "/tmp/r-address"))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "w", branch: "b", path: "/tmp/r-address-w", baseBranch: "main"
        ))
        let one = try await store.upsert(Session(workspaceID: workspace.id, title: "one"))
        let two = try await store.upsert(Session(workspaceID: workspace.id, title: "two"))

        try await store.enqueueDelivery(Delivery(targetSessionID: one.id, body: "for one"))

        #expect(try await store.pendingDeliveries(sessionID: one.id).count == 1)
        #expect(try await store.pendingDeliveries(sessionID: two.id).isEmpty)
    }

    @Test("carries a report from another workspace in the same order")
    func carriesAgentDeliveriesToo() async throws {
        let store = try makeTestStore("deliveries-kinds")
        let session = try await makeSession(in: store, label: "kinds")
        let child = WorkspaceID("ws-1f2a")

        try await store.enqueueDelivery(Delivery(targetSessionID: session.id, body: "mine"))
        try await store.enqueueDelivery(Delivery(
            targetSessionID: session.id,
            sourceWorkspaceID: child,
            kind: .report,
            verdict: "done",
            body: "Rebuilt the index migration."
        ))

        let pending = try await store.pendingDeliveries(sessionID: session.id)
        #expect(pending.map(\.kind) == [.owner, .report])
        #expect(pending[1].sourceWorkspaceID == child)
        #expect(pending[1].verdict == "done")
    }
}

@Suite("What the transcript draws the instant Return is pressed")
struct DeliveryEchoTests {
    private func waiting(_ bodies: String...) -> [Delivery] {
        bodies.map { Delivery(targetSessionID: SessionID("s"), body: $0) }
    }

    @Test("a message typed into an idle chat has gone, so it is drawn as one that has")
    func idleGoesAtOnce() {
        for agent in AgentKind.allCases {
            #expect(Delivery.goesImmediately(behind: [], hold: .none, on: agent))
        }
    }

    @Test("a message typed while anything is holding the queue is drawn as waiting")
    func heldIsDrawnAsWaiting() {
        for agent in AgentKind.allCases {
            for hold in DeliveryHold.allCases where !hold.allowsDelivery(on: agent) {
                #expect(!Delivery.goesImmediately(behind: [], hold: hold, on: agent))
            }
        }
    }

    @Test("a message typed during a turn has gone, where the turn can take it")
    func typedDuringATurnGoesAtOnce() {
        #expect(Delivery.goesImmediately(behind: [], hold: .turn, on: .claudeCode))
        #expect(Delivery.goesImmediately(behind: [], hold: .turn, on: .codex))
        #expect(!Delivery.goesImmediately(behind: [], hold: .turn, on: .cursor))
    }

    @Test("a message typed behind one that is still waiting waits too")
    func queuedBehindWaits() {
        #expect(!Delivery.goesImmediately(behind: waiting("first"), hold: .none, on: .claudeCode))
    }

    @Test("nothing typed during a turn overtakes what was queued before it")
    func nothingOvertakes() {
        let queued = waiting("asked for first")
        for agent in AgentKind.allCases where agent.acceptsMidTurnMessage {
            #expect(!Delivery.goesImmediately(behind: queued, hold: .turn, on: agent))
            #expect(Delivery.next(from: queued, hold: .turn, on: agent)?.body == "asked for first")
        }
    }

    @Test("the bubble and the drain never disagree about what goes next")
    func echoAgreesWithTheDrain() {
        let queues = [waiting(), waiting("first"), waiting("first", "second")]
        for agent in AgentKind.allCases {
            for hold in DeliveryHold.allCases {
                for queue in queues {
                    let typed = Delivery(targetSessionID: SessionID("s"), body: "just typed")
                    let goesNext = Delivery.next(
                        from: queue + [typed], hold: hold, on: agent
                    )?.id == typed.id
                    #expect(
                        Delivery.goesImmediately(behind: queue, hold: hold, on: agent) == goesNext
                    )
                }
            }
        }
    }
}

@Suite("What a Stop leaves behind")
struct PendingMessageReturnTests {
    private func typed(_ body: String, delivered: Bool = false) -> Delivery {
        Delivery(
            targetSessionID: SessionID("s"),
            body: body,
            deliveredAt: delivered ? Date() : nil
        )
    }

    private func fromAnAgent(_ text: String) -> Delivery {
        Delivery(
            targetSessionID: SessionID("s"),
            sourceWorkspaceID: WorkspaceID("ws-1f2a"),
            kind: .message,
            crew: CrewMessage.said(from: "indexer", text: text, sender: .subagent)
        )
    }

    @Test("the whole queue comes back, in the order it was asked for")
    func everythingReturnsInOrder() {
        let queue = [typed("first"), typed("second"), typed("third")]
        #expect(PendingMessageReturn.returning(from: queue).map(\.body) == ["first", "second", "third"])
        #expect(PendingMessageReturn.draft(taking: queue, into: "") == "first\n\nsecond\n\nthird")
    }

    @Test("a draft already in the composer is kept, and goes last")
    func theDraftIsNotDestroyed() {
        let joined = PendingMessageReturn.draft(
            taking: [typed("first"), typed("second")], into: "half a thought"
        )
        #expect(joined == "first\n\nsecond\n\nhalf a thought")
    }

    @Test("a blank composer counts as empty and its whitespace does not survive")
    func blankDraftCountsAsEmpty() {
        #expect(PendingMessageReturn.draft(taking: [typed("one")], into: " \n\n ") == "one")
    }

    @Test("an empty queue leaves the composer exactly as it was")
    func nothingToReturnChangesNothing() {
        #expect(PendingMessageReturn.draft(taking: [], into: "half a thought") == "half a thought")
    }

    @Test("returning one message is the same move as editing it")
    func oneMessageMatchesTheEditButton() {
        for draft in ["", "  ", "half a thought"] {
            let one = typed("one")
            #expect(
                PendingMessageReturn.draft(taking: [one], into: draft)
                    == PendingMessageEdit.draft(taking: one, into: draft)
            )
        }
    }

    @Test("something an agent said stays in the queue")
    func crewMessagesStayQueued() {
        let queue = [typed("mine"), fromAnAgent("the index is rebuilt")]
        #expect(PendingMessageReturn.returning(from: queue).map(\.body) == ["mine"])
        #expect(PendingMessageReturn.keeping(from: queue).map(\.kind) == [.message])
    }

    @Test("a message carrying attachments stays in the queue")
    func attachmentsStayQueued() {
        let attached = typed(AttachmentTrailer.compose(text: "look at this", paths: ["a.png"]))
        let queue = [typed("mine"), attached]
        #expect(PendingMessageReturn.returning(from: queue).map(\.body) == ["mine"])
        #expect(PendingMessageReturn.keeping(from: queue).count == 1)
    }

    @Test("a message that has already gone is not offered back")
    func deliveredIsNotReturned() {
        #expect(!PendingMessageReturn.canReturn(typed("gone", delivered: true)))
    }

    @Test("what comes back and what stays partition the queue")
    func thePartitionIsComplete() {
        let queue = [
            typed("first"),
            fromAnAgent("from the indexer"),
            typed(AttachmentTrailer.compose(text: "look", paths: ["a.png"])),
            typed("last"),
        ]
        let returning = PendingMessageReturn.returning(from: queue)
        let keeping = PendingMessageReturn.keeping(from: queue)
        #expect(returning.count + keeping.count == queue.count)
        #expect(returning.map(\.body) == ["first", "last"])
        #expect(keeping.map(\.id) == [queue[1].id, queue[2].id])
    }
}

@Suite("Steering one message past the rest")
struct DeliverySteerTests {
    private func typed(_ body: String, delivered: Bool = false) -> Delivery {
        Delivery(
            targetSessionID: SessionID("s"),
            body: body,
            deliveredAt: delivered ? Date() : nil
        )
    }

    @Test("offered only while there is a turn to interrupt, and only where interrupting is the way in")
    func onlyDuringATurn() {
        let one = typed("one")
        for hold in DeliveryHold.allCases {
            #expect(!DeliverySteer.canSteer(one, hold: hold, on: .claudeCode))
            #expect(!DeliverySteer.canSteer(one, hold: hold, on: .codex))
            #expect(DeliverySteer.canSteer(one, hold: hold, on: .cursor) == (hold == .turn))
        }
    }

    @Test("a backend that takes a message mid turn never offers it")
    func midTurnBackendsNeverSteer() {
        let one = typed("one")
        for agent in AgentKind.allCases where agent.acceptsMidTurnMessage {
            #expect(!DeliverySteer.canSteer(one, hold: .turn, on: agent))
        }
    }

    @Test("a message that has already gone cannot be steered")
    func deliveredCannotSteer() {
        #expect(!DeliverySteer.canSteer(typed("gone", delivered: true), hold: .turn, on: .cursor))
    }

    @Test("a message from another agent carries no Steer")
    func crewCannotSteer() {
        let fromAnAgent = Delivery(
            targetSessionID: SessionID("s"),
            sourceWorkspaceID: WorkspaceID("ws-1f2a"),
            kind: .message,
            crew: CrewMessage.said(from: "indexer", text: "done", sender: .subagent)
        )
        #expect(!DeliverySteer.canSteer(fromAnAgent, hold: .turn, on: .cursor))
    }

    @Test("a message carrying attachments can be steered, unlike edited")
    func attachmentsCanStillSteer() {
        let attached = typed(AttachmentTrailer.compose(text: "look at this", paths: ["a.png"]))
        #expect(!PendingMessageEdit.canEdit(attached))
        #expect(DeliverySteer.canSteer(attached, hold: .turn, on: .cursor))
    }

    @Test("everything else keeps its place and its order, whichever one is steered")
    func theRestIsUntouched() {
        let queue = [typed("first"), typed("second"), typed("third")]
        let expected = [["second", "third"], ["first", "third"], ["first", "second"]]
        for (index, chosen) in queue.enumerated() {
            let rest = DeliverySteer.queue(after: chosen, from: queue)
            #expect(rest.map(\.body) == expected[index])
        }
    }

    @Test("steering the front leaves what the drain would have left")
    func steeringTheFrontMatchesTheDrain() throws {
        let queue = [typed("first"), typed("second"), typed("third")]
        let front = try #require(Delivery.next(from: queue, hold: .none, on: .cursor))
        #expect(DeliverySteer.queue(after: front, from: queue).map(\.body) == ["second", "third"])
    }
}

@Suite("A canvas comment waits for an idle agent")
struct CanvasCommentQueueDeliveryTests {
    private let session = SessionID("s")

    private func comment(_ body: String) -> Delivery {
        Delivery(targetSessionID: session, kind: .canvasComment, body: body)
    }

    private func message(_ body: String) -> Delivery {
        Delivery(targetSessionID: session, body: body)
    }

    @Test(arguments: AgentKind.allCases)
    func commentWaitsForTheTurnOnEveryAgent(agent: AgentKind) {
        #expect(Delivery.deliverable(from: [comment("c")], hold: .turn, on: agent).isEmpty)
        #expect(Delivery.next(from: [comment("c")], hold: .turn, on: agent) == nil)
    }

    @Test(arguments: AgentKind.allCases)
    func commentWaitsForAQuestionAndForSetupOnEveryAgent(agent: AgentKind) {
        #expect(Delivery.deliverable(from: [comment("c")], hold: .question, on: agent).isEmpty)
        #expect(Delivery.deliverable(from: [comment("c")], hold: .setup, on: agent).isEmpty)
    }

    @Test(arguments: AgentKind.allCases)
    func oneCommentAtATime(agent: AgentKind) {
        let first = comment("first")
        let queue = [first, comment("second"), comment("third")]
        #expect(Delivery.deliverable(from: queue, hold: .none, on: agent).map(\.id) == [first.id])
    }

    @Test(arguments: AgentKind.allCases)
    func messageOvertakesAQueuedComment(agent: AgentKind) {
        let queued = comment("c")
        let typed = message("m")
        let queue = [queued, typed]
        let midTurn = Delivery.deliverable(from: queue, hold: .turn, on: agent).map(\.id)
        #expect(midTurn == (agent.acceptsMidTurnMessage ? [typed.id] : []))
        #expect(Delivery.goesImmediately(behind: [queued], hold: .turn, on: agent) == agent.acceptsMidTurnMessage)
        #expect(Delivery.goesImmediately(behind: [queued], hold: .none, on: agent))
        #expect(!Delivery.goesImmediately(behind: [queued, typed], hold: .none, on: agent))
    }

    @Test(arguments: AgentKind.allCases)
    func messagesGoBeforeComments(agent: AgentKind) {
        let queued = comment("c")
        let typed = message("m")
        let second = message("n")
        let expected = agent.acceptsMidTurnMessage ? [typed.id, second.id] : [typed.id]
        #expect(Delivery.deliverable(from: [queued, typed, second], hold: .none, on: agent).map(\.id) == expected)
    }

    @Test(arguments: AgentKind.allCases)
    func aMessageWhoseDeliveryIsUnconfirmedStillHoldsTheComment(agent: AgentKind) {
        var unconfirmed = message("m")
        unconfirmed.state = .uncertain
        #expect(Delivery.deliverable(from: [comment("c"), unconfirmed], hold: .none, on: agent).isEmpty)
        #expect(!Delivery.goesImmediately(behind: [comment("c"), unconfirmed], hold: .none, on: agent))
    }

    @Test(arguments: AgentKind.allCases)
    func aCommentWhoseDeliveryIsUnconfirmedHoldsNoMessage(agent: AgentKind) {
        var unconfirmed = comment("c")
        unconfirmed.state = .uncertain
        let typed = message("m")
        #expect(Delivery.deliverable(from: [unconfirmed, typed], hold: .none, on: agent).map(\.id) == [typed.id])
        #expect(Delivery.goesImmediately(behind: [unconfirmed], hold: .none, on: agent))
    }

    @Test func aCommentBehindAnUnconfirmedCommentWaits() {
        var unconfirmed = comment("c")
        unconfirmed.state = .uncertain
        #expect(Delivery.deliverable(from: [unconfirmed, comment("d")], hold: .none, on: .claudeCode).isEmpty)
    }

    @Test(arguments: AgentKind.allCases, DeliveryHold.allCases)
    func commentIsNotSteerable(agent: AgentKind, hold: DeliveryHold) {
        #expect(!DeliverySteer.canSteer(comment("c"), hold: hold, on: agent))
    }

    @Test func commentIsNotReturnedToTheComposer() {
        let queued = comment("c")
        let typed = message("m")
        #expect(!PendingMessageReturn.canReturn(queued))
        #expect(PendingMessageReturn.returning(from: [queued, typed]).map(\.id) == [typed.id])
        #expect(PendingMessageReturn.keeping(from: [queued, typed]).map(\.id) == [queued.id])
        #expect(!PendingMessageEdit.canEdit(queued))
        #expect(PendingMessageDiscard.recovery(of: queued, composerDraft: "") == .discarded(.notTheOwners))
    }

    @Test func afterAFailureOnlyAQueueOfCommentsAloneMoves() {
        var unconfirmedMessage = message("m")
        unconfirmedMessage.state = .uncertain
        var unconfirmedComment = comment("c")
        unconfirmedComment.state = .uncertain
        #expect(Delivery.holdsOnlyCanvasComments([comment("c")]))
        #expect(Delivery.holdsOnlyCanvasComments([comment("c"), comment("d")]))
        #expect(Delivery.holdsOnlyCanvasComments([unconfirmedComment]))
        #expect(!Delivery.holdsOnlyCanvasComments([]))
        #expect(!Delivery.holdsOnlyCanvasComments([message("m")]))
        #expect(!Delivery.holdsOnlyCanvasComments([comment("c"), message("m")]))
        #expect(!Delivery.holdsOnlyCanvasComments([message("m"), comment("c")]))
        #expect(!Delivery.holdsOnlyCanvasComments([unconfirmedMessage, comment("c")]))
    }

    @Test func anEditedDraftHoldsTheCommentUntilItIsClearedOut() {
        #expect(!PendingMessageEdit.draftIsAbandoned("still typing"))
        #expect(!PendingMessageEdit.draftIsAbandoned(" x\n"))
        #expect(PendingMessageEdit.draftIsAbandoned(""))
        #expect(PendingMessageEdit.draftIsAbandoned(" \n\t"))
    }

    @Test func theChatQueueLeavesCommentsToTheirMarks() {
        let queued = comment("c")
        let typed = message("m")
        #expect(Delivery.messages(in: [queued, typed]).map(\.id) == [typed.id])
    }
}
