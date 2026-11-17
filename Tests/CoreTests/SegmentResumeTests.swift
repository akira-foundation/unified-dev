import Testing
import Foundation
@testable import Core

@Suite("A native session that was retired or cannot be resumed", .scratchDirectory)
struct SegmentResumeTests {
    private let codex = SessionSegmentTarget(agentKind: .codex, accountID: nil, model: "gpt-5.6", effort: "")
    private let claude = SessionSegmentTarget(agentKind: .claudeCode, accountID: nil, model: "opus", effort: "")

    private func makeSession(_ store: Store) async throws -> Session {
        let repo = try await store.upsert(Repo(name: "r", path: TestScratch.unique("repo")))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "w", branch: "b", path: TestScratch.unique("worktree"), baseBranch: "main"
        ))
        return try await store.upsert(Session(workspaceID: workspace.id, model: "opus", agentKind: .claudeCode))
    }

    private func say(_ store: Store, _ session: Session, _ text: String) async throws {
        let json = JSONValue.object(["type": .string("user"), "message": .object(["content": .string(text)])])
        try await store.appendNext(sessionID: session.id, kind: .user, payload: Data(json.compactJSON.utf8))
    }

    private func acknowledge(_ store: Store, _ session: Session) async throws {
        let active = try #require(try await store.activeSegment(sessionID: session.id))
        try await store.acknowledgeHandoff(sessionID: session.id, fromSegment: active.id, carriedDelta: false)
    }

    private func turn(_ store: Store, _ session: Session, deliveredSeq: Int? = nil) async throws -> String {
        try await store.handoffTurn(
            "PROMPT", sessionID: session.id, deliveredSeq: deliveredSeq, worktree: nil, contextWindow: nil
        )
    }

    @Test("a write from a retired segment changes nothing and says so")
    func aRetiredRunnerCannotWrite() async throws {
        let store = try makeTestStore("retired-write")
        let session = try await makeSession(store)
        let retired = try #require(try await store.activeSegment(sessionID: session.id)).id
        _ = try await store.switchSegment(sessionID: session.id, to: codex)
        let active = try #require(try await store.activeSegment(sessionID: session.id)).id
        _ = try await store.update(sessionID: session.id, fromSegment: active) {
            $0.agentSessionID = "codex-thread"
            $0.inputTokens = 11
            $0.outputTokens = 22
            $0.costUSD = 0.5
            $0.contextTokens = 33
        }

        let refused = try await store.update(sessionID: session.id, fromSegment: retired) {
            $0.agentSessionID = "claude-session"
            $0.inputTokens = 1000
            $0.outputTokens = 1000
            $0.costUSD = 99
            $0.contextTokens = 1000
        }

        #expect(refused == nil)
        let row = try #require(try await store.session(id: session.id))
        #expect(row.agentSessionID == "codex-thread")
        #expect(row.inputTokens == 11)
        #expect(row.outputTokens == 22)
        #expect(row.costUSD == 0.5)
        #expect(row.contextTokens == 33)
    }

    @Test("a write from the active segment is applied and returned")
    func theActiveSegmentWrites() async throws {
        let store = try makeTestStore("active-write")
        let session = try await makeSession(store)
        let active = try #require(try await store.activeSegment(sessionID: session.id)).id

        let written = try await store.update(sessionID: session.id, fromSegment: active) { $0.agentSessionID = "native" }

        #expect(written?.agentSessionID == "native")
        #expect(try await store.session(id: session.id)?.agentSessionID == "native")
    }

    @Test("a chat with no active segment has no seat, and nothing can write from any segment")
    func noActiveSegmentMeansNoSeat() async throws {
        let path = TestScratch.unique("no-active") + ".sqlite"
        let store = try Store(path: path)
        let session = try await makeSession(store)
        let segment = try #require(try await store.activeSegment(sessionID: session.id)).id
        try SQLiteDatabase(path: path).execute("UPDATE session_segments SET is_active = 0;")

        #expect(try await store.runnerSeat(sessionID: session.id) == nil)
        #expect(try await store.update(sessionID: session.id, fromSegment: segment) { $0.agentSessionID = "x" } == nil)
        #expect(try await store.session(id: session.id)?.agentSessionID == nil)
        #expect(try await store.runnerSeat(sessionID: SessionID("gone")) == nil)
    }

    @Test("a seat is the row and the segment of the same moment")
    func aSeatIsOneReading() async throws {
        let store = try makeTestStore("seat")
        let session = try await makeSession(store)
        let first = try #require(try await store.runnerSeat(sessionID: session.id))
        #expect(first.session.agentKind == .claudeCode)
        #expect(try await store.activeSegment(sessionID: session.id)?.id == first.segmentID)

        _ = try await store.switchSegment(sessionID: session.id, to: codex)

        let second = try #require(try await store.runnerSeat(sessionID: session.id))
        #expect(second.session.agentKind == .codex)
        #expect(second.segmentID != first.segmentID)
    }

    @Test("a retired segment's confirmation leaves the new agent's cursor alone")
    func aRetiredRunnerCannotMoveTheCursor() async throws {
        let store = try makeTestStore("retired-cursor")
        let session = try await makeSession(store)
        try await say(store, session, "said-to-claude")
        let retired = try #require(try await store.activeSegment(sessionID: session.id))
        _ = try await store.switchSegment(sessionID: session.id, to: codex)
        let before = try #require(try await store.activeSegment(sessionID: session.id)).cursorSeq

        try await store.acknowledgeHandoff(sessionID: session.id, fromSegment: retired.id, carriedDelta: false)

        #expect(try await store.activeSegment(sessionID: session.id)?.cursorSeq == before)
        let parked = try await store.segments(sessionID: session.id).first { $0.id == retired.id }
        #expect(parked?.cursorSeq == retired.cursorSeq)
        #expect(try await turn(store, session).contains("said-to-claude"))
    }

    @Test("a delivery released and sent after a switch carries what came after its own row")
    func aReleasedDeliveryAfterASwitchLosesNoRows() async throws {
        let store = try makeTestStore("released-delivery")
        let session = try await makeSession(store)
        let delivery = try await store.enqueueDelivery(Delivery(targetSessionID: session.id, body: "PROMPT"))
        #expect(try await store.claimDelivery(id: delivery.id))
        try await store.releaseDeliveryClaim(id: delivery.id)
        try await say(store, session, "said-after-the-release")
        _ = try await store.switchSegment(sessionID: session.id, to: codex)
        #expect(try await store.claimDelivery(id: delivery.id))
        let seq = try #require(try await store.delivery(id: delivery.id)?.deliveredSeq)

        let sent = try await turn(store, session, deliveredSeq: seq)

        #expect(sent.contains("said-after-the-release"))
        #expect(sent.components(separatedBy: "PROMPT").count == 2)
        try await acknowledge(store, session)
        #expect(try await store.handoffIsDue(sessionID: session.id, deliveredSeq: nil) == false)
    }

    @Test("the only readable row being the prompt itself owes nothing")
    func thePromptAloneIsNotADelta() async throws {
        let store = try makeTestStore("prompt-alone")
        let session = try await makeSession(store)
        let delivery = try await store.enqueueDelivery(Delivery(targetSessionID: session.id, body: "PROMPT"))
        #expect(try await store.claimDelivery(id: delivery.id))
        let seq = try #require(try await store.delivery(id: delivery.id)?.deliveredSeq)
        let active = try #require(try await store.activeSegment(sessionID: session.id))
        try await store.resetCursor(segmentID: active.id)

        #expect(try await store.handoffIsDue(sessionID: session.id, deliveredSeq: seq) == false)
    }

    @Test("an agent answering with another session has lost the history, and a first id has not")
    func lostHistoryWhenTheAgentAnswersWithAnotherSession() {
        #expect(SegmentResume.lostHistory(requested: "a", received: "b"))
        #expect(!SegmentResume.lostHistory(requested: "a", received: "a"))
        #expect(!SegmentResume.lostHistory(requested: nil, received: "b"))
        #expect(!SegmentResume.lostHistory(requested: "", received: "b"))
        #expect(!SegmentResume.lostHistory(requested: "a", received: ""))
        #expect(!SegmentResume.lostHistory(requested: "a", received: nil))
    }

    @Test("only a resume refused before the first init counts as refused")
    func aRefusedResumeIsRecognised() {
        let refusal = AgentResult(isError: true, subtype: "error_during_execution", sessionID: "a")
        #expect(SegmentResume.refused(requested: "a", result: refusal))
        #expect(!SegmentResume.refused(requested: "b", result: refusal))
        #expect(!SegmentResume.refused(requested: nil, result: refusal))
        #expect(!SegmentResume.refused(requested: "", result: refusal))
        #expect(!SegmentResume.refused(requested: "a", result: AgentResult(isError: false, subtype: "error_during_execution", sessionID: "a")))
        #expect(!SegmentResume.refused(requested: "a", result: AgentResult(isError: true, subtype: "error_max_turns", sessionID: "a")))
    }

    @Test("a reset cursor gives the next send the whole conversation")
    func lostHistoryResetsTheCursor() async throws {
        let store = try makeTestStore("lost-history")
        let session = try await makeSession(store)
        try await say(store, session, "the-oldest-words")
        try await acknowledge(store, session)
        #expect(try await turn(store, session) == "PROMPT")

        let active = try #require(try await store.activeSegment(sessionID: session.id))
        try await store.resetCursor(segmentID: active.id)

        #expect(try await turn(store, session).contains("the-oldest-words"))
    }

    @Test("the account recorded while a segment was active is parked with it, so a return finds that session")
    func aRecordedAccountIsParkedWithTheSegment() async throws {
        let store = try makeTestStore("record-parks")
        let session = try await makeSession(store)
        try await store.add(AgentAccountRow(id: AccountFixture.work.id, provider: .claudeCode, directory: "/accounts/work"))
        let first = try #require(try await store.activeSegment(sessionID: session.id))
        try await store.update(sessionID: session.id, accountID: AccountFixture.work.id)
        _ = try await store.update(sessionID: session.id, fromSegment: first.id) { $0.agentSessionID = "native" }

        _ = try await store.switchSegment(sessionID: session.id, to: codex)
        let parked = try await store.segments(sessionID: session.id).first { $0.id == first.id }
        #expect(parked?.accountID == AccountFixture.work.id)

        let back = try await store.switchSegment(sessionID: session.id, to: SessionSegmentTarget(
            agentKind: .claudeCode, accountID: AccountFixture.work.id, model: "opus", effort: ""
        ))

        #expect(back.agentSessionID == "native")
        #expect(try await store.activeSegment(sessionID: session.id)?.id == first.id)
    }

    @Test("an agent changed in place is parked under the agent that ran, so a switch back is a switch")
    func aChangedAgentIsParkedWithTheSegment() async throws {
        let store = try makeTestStore("kind-parks")
        let session = try await makeSession(store)
        let first = try #require(try await store.activeSegment(sessionID: session.id))
        _ = try await store.update(sessionID: session.id) {
            $0.agentKind = .codex
            $0.agentSessionID = "codex-thread"
        }

        let moved = try await store.switchSegment(sessionID: session.id, to: claude)

        #expect(moved.agentKind == .claudeCode)
        #expect(moved.agentSessionID == nil)
        let parked = try await store.segments(sessionID: session.id).first { $0.id == first.id }
        #expect(parked?.agentKind == .codex)
        #expect(parked?.agentSessionID == "codex-thread")
    }

    @Test("the chat's row decides a switch, so settling always ends with the account it asked for")
    func settlingAlwaysArrives() async throws {
        let store = try makeTestStore("settling-arrives")
        let session = try await makeSession(store)
        let work = AccountFixture.work
        let personal = AccountFixture.personal
        for home in [work, personal] {
            try await store.add(AgentAccountRow(id: home.id, provider: .claudeCode, directory: home.directory.path))
        }
        _ = try await store.switchSegment(sessionID: session.id, to: SessionSegmentTarget(
            agentKind: .claudeCode, accountID: work.id, model: "opus", effort: ""
        ))
        try await store.update(sessionID: session.id, accountID: personal.id)
        #expect(try await store.activeSegment(sessionID: session.id)?.accountID == work.id)
        let stored = try #require(try await store.session(id: session.id))

        let settlement = AgentSessionSettlement.decide(
            session: stored, account: work, purpose: .sending
        )
        try await AgentSessionRecord.write(settlement, session: session.id, account: work, standings: [], in: store)

        let settled = try #require(try await store.session(id: session.id))
        #expect(settled.accountID == work.id)
        #expect(AgentSessionSettlement.decide(
            session: settled, account: work, purpose: .sending
        ).changesNothing)
    }

    @Test("a switch leaves no turn marked as running, because the runner of that turn can no longer say it ended")
    func aSwitchLeavesNoTurnRunning() async throws {
        let store = try makeTestStore("switch-state")
        let session = try await makeSession(store)
        for (state, expected) in [
            (SessionState.running, SessionState.idle), (.waiting, .idle), (.failed, .failed), (.idle, .idle),
        ] {
            _ = try await store.update(sessionID: session.id) { $0.state = state }
            let target = try await store.session(id: session.id)?.agentKind == .codex ? claude : codex
            #expect(try await store.switchSegment(sessionID: session.id, to: target).state == expected)
        }
    }
}
