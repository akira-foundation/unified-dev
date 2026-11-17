import Testing
import Foundation
@testable import Core

@Suite("Recording on a session which account it runs under", .tags(.persistence), .scratchDirectory)
struct AgentAccountSessionRecordTests {
    private var providerDefault: AgentAccountHome {
        AgentAccountHome.defaultHome(for: .claudeCode, home: AccountFixture.user)!
    }

    private func seed(_ store: Store, agentSessionID: String? = nil) async throws -> Session {
        let repo = try await store.upsert(Repo(name: "r", path: TestScratch.unique("repo")))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "w", branch: "feature/w",
            path: TestScratch.unique("worktree"), baseBranch: "main"
        ))
        return try await store.upsert(Session(workspaceID: workspace.id, agentSessionID: agentSessionID))
    }

    private func settle(
        _ session: Session,
        on account: AgentAccountHome,
        in store: Store
    ) async throws {
        let settlement = AgentSessionSettlement.decide(
            session: session, account: account, purpose: .sending
        )
        try await AgentSessionRecord.write(settlement, session: session.id, account: account, standings: [], in: store)
    }

    @Test("a first send on a database that has never chosen an account records the synthesised default")
    func theSynthesisedDefaultIsStoredBeforeItIsRecorded() async throws {
        let store = try makeTestStore("session-record")
        let session = try await seed(store)
        let home = providerDefault

        try await settle(session, on: home, in: store)

        #expect(try await store.session(id: session.id)?.accountID == home.id)
        let rows = try await store.agentAccounts()
        #expect(rows.map(\.id) == [home.id])
        #expect(rows.first?.isDefault == true)
        #expect(rows.first?.directory == home.directory.path)
    }

    @Test("a switch to the default account parks the conversation on its old segment")
    func aSwitchNeverClearsTheStoredID() async throws {
        let store = try makeTestStore("session-record")
        let session = try await seed(store, agentSessionID: "agent-session-1")
        let first = try #require(try await store.activeSegment(sessionID: session.id))
        let home = providerDefault
        try await store.add(AgentAccountRow(id: home.id, provider: .claudeCode, directory: home.directory.path))

        _ = try await store.switchSegment(sessionID: session.id, to: SessionSegmentTarget(
            agentKind: .claudeCode, accountID: home.id, model: session.model, effort: session.effort
        ))

        let read = try #require(try await store.session(id: session.id))
        #expect(read.agentSessionID == nil)
        #expect(read.accountID == home.id)
        let parked = try await store.segments(sessionID: session.id).first { $0.id == first.id }
        #expect(parked?.agentSessionID == "agent-session-1")
        #expect(parked?.isActive == false)
    }

    @Test("recording the default twice leaves one row and the same choice")
    func recordingTwiceIsHarmless() async throws {
        let store = try makeTestStore("session-record")
        let first = try await seed(store)
        let second = try await seed(store)
        let home = providerDefault

        try await settle(first, on: home, in: store)
        try await settle(second, on: home, in: store)

        #expect(try await store.agentAccounts().count == 1)
        #expect(try await store.session(id: second.id)?.accountID == home.id)
    }

    @Test("a settlement that cannot record its account leaves the conversation pointer alone")
    func aRecordThatFailsDestroysNothing() async throws {
        let store = try makeTestStore("session-record")
        let session = try await seed(store, agentSessionID: "agent-session-1")
        let forgotten = AgentAccountHome(
            provider: .claudeCode,
            id: AgentAccountID("forgotten"),
            directory: URL(filePath: "/accounts/forgotten", directoryHint: .isDirectory),
            isDefault: false
        )
        let settlement = AgentSessionSettlement(recordedAccount: nil, switchTarget: SessionSegmentTarget(
            agentKind: .claudeCode, accountID: forgotten.id, model: session.model, effort: session.effort
        ))

        await #expect(throws: (any Error).self) {
            try await AgentSessionRecord.write(
                settlement, session: session.id, account: forgotten, standings: [], in: store
            )
        }

        let read = try #require(try await store.session(id: session.id))
        #expect(read.agentSessionID == "agent-session-1")
        #expect(read.accountID == nil)
    }

    @Test("a chat whose resolved account changed moves to a new segment, and a return resumes it")
    func aChangedAccountIsASegmentAndComesBack() async throws {
        let store = try makeTestStore("session-record")
        let session = try await seed(store, agentSessionID: "agent-session-1")
        let work = AgentAccountHome(
            provider: .claudeCode,
            id: AgentAccountID("work"),
            directory: URL(filePath: "/accounts/work", directoryHint: .isDirectory),
            isDefault: false
        )
        try await store.add(AgentAccountRow(id: work.id, provider: .claudeCode, directory: work.directory.path))
        try await store.update(sessionID: session.id, accountID: work.id)
        let stored = try #require(try await store.session(id: session.id))

        try await settle(stored, on: providerDefault, in: store)

        let moved = try #require(try await store.session(id: session.id))
        #expect(moved.agentSessionID == nil)
        #expect(moved.accountID == providerDefault.id)
        #expect(try await store.segments(sessionID: session.id).count == 2)

        try await settle(moved, on: work, in: store)

        let back = try #require(try await store.session(id: session.id))
        #expect(back.agentSessionID == "agent-session-1")
        #expect(back.accountID == work.id)
        #expect(try await store.segments(sessionID: session.id).count == 2)
    }
}
