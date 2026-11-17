import Testing
import Foundation
@testable import Core

@Suite("Naming the account in the divider of an account switch", .tags(.persistence), .scratchDirectory)
struct AccountSwitchDividerTests {
    private let work = AgentAccountRow(
        id: AgentAccountID("work"), provider: .claudeCode, directory: "/accounts/claudeCode/work", label: "Work"
    )

    @Test func aSwitchBetweenAccountsOfOneProviderNamesTheAccount() {
        let mark = HandoffMark.continued(agent: .claudeCode, model: "opus", from: .claudeCode, account: "ada@client.example")

        #expect(mark.sentence == "Continued with Claude Code under ada@client.example · opus")
    }

    @Test func aSwitchOfProviderDoesNotNameTheAccount() {
        let mark = HandoffMark.continued(agent: .codex, model: "gpt-5", from: .claudeCode, account: "ada@client.example")

        #expect(mark.sentence == "Continued with Codex · gpt-5")
    }

    @Test func aSwitchWithNoAccountNameReadsAsBefore() {
        #expect(HandoffMark.continued(agent: .claudeCode, model: "opus", from: .claudeCode).sentence
            == "Continued with Claude Code · opus")
        #expect(HandoffMark.continued(agent: .claudeCode, model: "opus", from: .claudeCode, account: "").sentence
            == "Continued with Claude Code · opus")
    }

    @Test func aDividerStoredBeforeAccountsWereNamedStillRendersAsItDid() throws {
        let stored = Data(#"{"continued":{"agent":"claudeCode","model":"opus","from":"claudeCode"}}"#.utf8)
        let mark = try #require(HandoffMark.decode(stored))

        #expect(mark == .continued(agent: .claudeCode, model: "opus", from: .claudeCode))
        #expect(mark.sentence == "Continued with Claude Code · opus")
    }

    @Test func theNameSurvivesEncoding() throws {
        let mark = HandoffMark.continued(agent: .claudeCode, model: "opus", from: .claudeCode, account: "Work")

        #expect(HandoffMark.decode(mark.payload) == mark)
    }

    @Test func theAccountIsSpokenAsTheOwnerKnowsIt() {
        let work = AccountFixture.work
        let standings = [
            AccountFixture.standing(AccountFixture.defaultClaude),
            AccountFixture.standing(work, email: "ada@client.example"),
        ]

        #expect(AgentAccountNames.spoken(of: work, among: standings) == "ada@client.example")
        #expect(AgentAccountNames.spoken(of: AccountFixture.defaultClaude, among: standings) == "the default account")
        #expect(AgentAccountNames.spoken(of: AccountFixture.personal, among: standings) == "personal")
    }

    @Test func theStoreWritesTheNameIntoTheDivider() async throws {
        let store = try makeTestStore("divider-account")
        try await store.add(work)
        let session = try await store.upsert(Session(workspaceID: nil, agentSessionID: "c1"))
        let target = SessionSegmentTarget(agentKind: .claudeCode, accountID: work.id, model: "opus", effort: "")

        _ = try await store.switchSegment(sessionID: session.id, to: target.named("Work"))

        let divider = try #require(try await store.messages(sessionID: session.id).last { $0.kind == .handoff })
        #expect(HandoffMark.decode(divider.payload)?.sentence == "Continued with Claude Code under Work · opus")
    }
}

@Suite("What another agent reads of an account switch")
struct AccountSwitchDividerReadingTests {
    @Test func chatReadGivesTheDividerWithoutTheAccount() throws {
        let mark = HandoffMark.continued(agent: .claudeCode, model: "opus", from: .claudeCode, account: "ada@client.example")
        let divider = Message(sessionID: SessionID("s"), seq: 1, kind: .handoff, payload: mark.payload)

        let page = try ChatTranscriptPage.make(messages: [divider], cursor: .init(sessionID: SessionID("s")), limit: 50)

        #expect(page.messages[0]["content"]?.stringValue == "Continued with Claude Code · opus")
    }

    @Test func aMarkWithoutTheAccountKeepsEverythingElse() {
        let mark = HandoffMark.continued(agent: .codex, model: "gpt-5", from: .claudeCode, account: "ada@client.example")

        #expect(mark.withoutAccount == .continued(agent: .codex, model: "gpt-5", from: .claudeCode))
        #expect(HandoffMark.resuming.withoutAccount == .resuming)
    }
}

@Suite("The account a switch names", .tags(.persistence), .scratchDirectory)
struct AccountSwitchNamingTests {
    private let work = AgentAccountRow(
        id: AgentAccountID("work"), provider: .claudeCode, directory: "/accounts/claudeCode/work", label: "Work"
    )

    private func divider(_ store: Store, _ session: Session) async throws -> HandoffMark? {
        let row = try #require(try await store.messages(sessionID: session.id).last { $0.kind == .handoff })
        return HandoffMark.decode(row.payload)
    }

    @Test func theProviderPickerNamesTheAccountAsTheOwnerKnowsIt() async throws {
        let store = try makeTestStore("switch-names-account")
        try await store.add(work)
        let session = try await store.upsert(Session(workspaceID: nil, agentSessionID: "c1", model: "opus"))
        let home = AgentAccountHome(work)

        _ = try await AgentSwitch.retireAndSwitch(
            runner: nil, store: store, sessionID: session.id,
            controls: ComposerControls(model: "opus", effort: "", agentKind: .claudeCode), account: home,
            standings: [AccountFixture.standing(home, email: "ada@client.example")]
        )

        #expect(try await divider(store, session)?.sentence == "Continued with Claude Code under ada@client.example · opus")
    }

    @Test func aMoveAtSendTimeNamesTheAccountAsTheOwnerKnowsIt() async throws {
        let store = try makeTestStore("record-names-account")
        let lab = AgentAccountRow(id: AgentAccountID("lab"), provider: .claudeCode, directory: "/accounts/claudeCode/lab")
        try await store.add(work)
        try await store.add(lab)
        var session = try await store.upsert(Session(workspaceID: nil, agentSessionID: "c1", model: "opus"))
        try await store.update(sessionID: session.id, accountID: lab.id)
        session = try #require(try await store.session(id: session.id))
        let home = AgentAccountHome(work)
        let settlement = AgentSessionSettlement.decide(session: session, account: home, purpose: .sending)

        try await AgentSessionRecord.write(
            settlement, session: session.id, account: home,
            standings: [AccountFixture.standing(home, email: "ada@client.example")], in: store
        )

        #expect(try await divider(store, session)?.sentence == "Continued with Claude Code under ada@client.example · opus")
    }
}
