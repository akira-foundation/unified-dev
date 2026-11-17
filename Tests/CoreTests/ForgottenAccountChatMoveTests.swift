import Testing
import Foundation
@testable import Core

@Suite("Telling the owner where a forgotten account's chat goes", .tags(.persistence), .scratchDirectory)
struct ForgottenAccountChatMoveTests {
    private let client = AgentAccountRow(
        id: AgentAccountID("client"), provider: .claudeCode, directory: "/accounts/claudeCode/client", label: "Client"
    )

    private func chatOnTheClientAccount(_ store: Store) async throws -> Session {
        try await store.add(client)
        let session = try await store.upsert(Session(workspaceID: nil, agentSessionID: "native-1"))
        try await store.update(sessionID: session.id, accountID: client.id)
        return session
    }

    @Test func forgettingTheAccountMarksItsChats() async throws {
        let store = try makeTestStore("forgotten-marks")
        let session = try await chatOnTheClientAccount(store)
        let bystander = try await store.upsert(Session(workspaceID: nil, agentSessionID: "native-2"))

        try await store.forgetAgentAccount(client.id)

        #expect(try await store.runnerSeat(sessionID: session.id)?.lostItsAccount == true)
        #expect(try await store.runnerSeat(sessionID: bystander.id)?.lostItsAccount == false)
    }

    @Test func theNextSendMovesTheChatAndSaysWhere() async throws {
        let store = try makeTestStore("forgotten-moves")
        let session = try await chatOnTheClientAccount(store)
        try await store.forgetAgentAccount(client.id)
        let seat = try #require(try await store.runnerSeat(sessionID: session.id))
        let home = AccountFixture.defaultClaude
        let standings = [AccountFixture.standing(home, email: "ada@home.example")]

        let settlement = AgentSessionSettlement.decide(
            session: seat.session, account: home, purpose: .sending, lostItsAccount: seat.lostItsAccount
        )

        #expect(settlement.switchTarget?.accountID == home.id)
        #expect(settlement.notice(on: home, among: standings, besides: nil)
            == "The account this chat ran under was removed, so it moved to ada@home.example and its history went with it.")
    }

    @Test func aChatThatNeverHadAnAccountIsStillRecordedSilently() {
        let session = Session(workspaceID: nil, agentSessionID: nil)
        let home = AccountFixture.defaultClaude

        let settlement = AgentSessionSettlement.decide(session: session, account: home, purpose: .sending)

        #expect(settlement.switchTarget == nil)
        #expect(settlement.recordedAccount == home.id)
        #expect(settlement.notice(on: home, among: [], besides: nil) == nil)
    }

    @Test func answeringDoesNotMoveTheChat() {
        let settlement = AgentSessionSettlement.decide(
            session: Session(workspaceID: nil, agentSessionID: nil), account: AccountFixture.defaultClaude,
            purpose: .answering, lostItsAccount: true
        )

        #expect(settlement.changesNothing)
    }

    @Test func theMoveIsWrittenWithADividerAndTheMarkGoes() async throws {
        let store = try makeTestStore("forgotten-written")
        let session = try await chatOnTheClientAccount(store)
        try await store.forgetAgentAccount(client.id)
        let seat = try #require(try await store.runnerSeat(sessionID: session.id))
        let home = AccountFixture.defaultClaude
        let settlement = AgentSessionSettlement.decide(
            session: seat.session, account: home, purpose: .sending, lostItsAccount: seat.lostItsAccount
        )

        try await AgentSessionRecord.write(
            settlement, session: session.id, account: home,
            standings: [AccountFixture.standing(home)], in: store
        )

        let divider = try #require(try await store.messages(sessionID: session.id).last { $0.kind == .handoff })
        #expect(HandoffMark.decode(divider.payload)?.sentence == "Continued with Claude Code under the default account · \(seat.session.model)")
        #expect(try await store.session(id: session.id)?.accountID == home.id)
        #expect(try await store.runnerSeat(sessionID: session.id)?.lostItsAccount == false)
    }

    @Test func forgettingAnotherAccountSweepsTheMarksOfChatsThatAreGone() async throws {
        let store = try makeTestStore("forgotten-swept")
        let gone = SessionID("chat-whose-workspace-went")
        try await store.setSetting(AgentSessionSettlement.lostAccountKey(sessionID: gone), "1")
        let session = try await chatOnTheClientAccount(store)

        try await store.forgetAgentAccount(client.id)

        #expect(try await store.setting(AgentSessionSettlement.lostAccountKey(sessionID: gone)) == nil)
        #expect(try await store.setting(AgentSessionSettlement.lostAccountKey(sessionID: session.id)) == "1")
    }

    @Test func closingTheChatTakesTheMarkWithIt() async throws {
        let store = try makeTestStore("forgotten-closed")
        let session = try await chatOnTheClientAccount(store)
        try await store.forgetAgentAccount(client.id)

        try await store.deleteSession(id: session.id)

        #expect(try await store.setting(AgentSessionSettlement.lostAccountKey(sessionID: session.id)) == nil)
    }
}
