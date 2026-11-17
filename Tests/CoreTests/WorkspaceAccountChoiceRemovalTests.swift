import Testing
import Foundation
@testable import Core

@Suite("Accounts are chosen per project only", .tags(.persistence), .scratchDirectory)
struct WorkspaceAccountChoiceRemovalTests {
    private struct Seeded {
        let path: String
        let repo: Repo
        let workspace: Workspace
        let session: Session
        let elsewhere: Session
        let codex: Session
        let project: AgentAccountRow
        let own: AgentAccountRow
        let version: Int32
    }

    private func directory(_ name: String) throws -> String {
        let path = TestScratch.unique("accounts") + "/" + name
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func seededWithAWorkspaceChoice(recordingTheChat: Bool = true) async throws -> Seeded {
        let path = TestScratch.unique("per-workspace") + ".sqlite"
        let store = try Store(path: path)
        let repo = try await store.upsert(Repo(name: "billing", path: TestScratch.unique("repo")))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "invoices", branch: "b", path: TestScratch.unique("worktree"), baseBranch: "main"
        ))
        let project = AgentAccountRow(id: AgentAccountID("client"), provider: .claudeCode, directory: try directory("client"))
        let own = AgentAccountRow(id: AgentAccountID("lab"), provider: .claudeCode, directory: try directory("lab"))
        try await store.add(project)
        try await store.add(own)
        try await store.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(project)), forRepo: repo.id)
        var session = try await store.upsert(Session(workspaceID: workspace.id, agentSessionID: "native-1"))
        if recordingTheChat { try await store.update(sessionID: session.id, accountID: own.id) }
        session = try #require(try await store.session(id: session.id))
        var elsewhere = try await store.upsert(Session(workspaceID: workspace.id, agentSessionID: "native-2"))
        try await store.update(sessionID: elsewhere.id, accountID: project.id)
        elsewhere = try #require(try await store.session(id: elsewhere.id))
        let codex = try await store.upsert(Session(
            workspaceID: workspace.id, agentSessionID: "native-3", model: "gpt-5", agentKind: .codex
        ))

        let raw = try SQLiteDatabase(path: path)
        let version = try raw.readUserVersion()
        try raw.run(
            "UPDATE session_segments SET account_id = ? WHERE session_id = ?",
            [.text(project.id.rawValue), .text(elsewhere.id.rawValue)]
        )
        try raw.execute("""
            CREATE TABLE workspace_agent_accounts (
                workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                provider TEXT NOT NULL,
                account_id TEXT NOT NULL REFERENCES agent_accounts(id) ON DELETE CASCADE,
                PRIMARY KEY (workspace_id, provider)
            );
            """)
        try raw.run(
            "INSERT INTO workspace_agent_accounts (workspace_id, provider, account_id) VALUES (?, ?, ?)",
            [.text(workspace.id.rawValue), .text(AgentKind.claudeCode.rawValue), .text(own.id.rawValue)]
        )
        try raw.setUserVersion(version - 8)
        return Seeded(
            path: path, repo: repo, workspace: workspace, session: session, elsewhere: elsewhere, codex: codex,
            project: project, own: own, version: version
        )
    }

    private func tables(at path: String) throws -> Set<String> {
        Set(try SQLiteDatabase(path: path).query("SELECT name FROM sqlite_master WHERE type = 'table'")
            .compactMap { $0.string("name") })
    }

    @Test("a database with workspace choices loses them and lands on the current version")
    func theWorkspaceChoicesAreDropped() async throws {
        let seeded = try await seededWithAWorkspaceChoice()
        #expect(try tables(at: seeded.path).contains("workspace_agent_accounts"))

        let store = try Store(path: seeded.path)

        #expect(!(try tables(at: seeded.path).contains("workspace_agent_accounts")))
        #expect(try SQLiteDatabase(path: seeded.path).readUserVersion() == seeded.version)
        #expect(try await store.agentAccountChoices().repos[seeded.repo.id] == [.claudeCode: seeded.project.id])
        #expect(try await store.agentAccounts().map(\.id).sorted() == [seeded.own.id, seeded.project.id].sorted())
    }

    @Test("a chat that ran a workspace's own account moves to the project's on its next send, and says so once")
    func aChatOnTheWorkspaceAccountMovesToTheProjectAccount() async throws {
        let seeded = try await seededWithAWorkspaceChoice()
        let store = try Store(path: seeded.path)

        let resolution = try await AgentAccountResolver.resolve(
            workspaceID: seeded.workspace.id, repoID: seeded.repo.id, store: store, defaults: []
        )
        let account = try #require(resolution.home(for: .claudeCode))
        let session = try #require(try await store.session(id: seeded.session.id))
        let settlement = AgentSessionSettlement.decide(session: session, account: account, purpose: .sending)

        #expect(account.id == seeded.project.id)
        #expect(settlement.switchTarget?.accountID == seeded.project.id)
        #expect(settlement.notice(on: account, among: resolution.standings, besides: nil)?
            .hasPrefix("This chat moved to client") == true)
    }

    @Test("a chat with a history and no recorded account keeps the workspace's account, so its history moves with it")
    func anUnrecordedChatIsRecordedOnTheWorkspaceAccount() async throws {
        let seeded = try await seededWithAWorkspaceChoice(recordingTheChat: false)
        let store = try Store(path: seeded.path)

        let session = try #require(try await store.session(id: seeded.session.id))
        let segment = try #require(try await store.activeSegment(sessionID: seeded.session.id))
        let resolution = try await AgentAccountResolver.resolve(
            workspaceID: seeded.workspace.id, repoID: seeded.repo.id, store: store, defaults: []
        )
        let account = try #require(resolution.home(for: .claudeCode))
        let settlement = AgentSessionSettlement.decide(session: session, account: account, purpose: .sending)

        #expect(session.accountID == seeded.own.id)
        #expect(segment.accountID == seeded.own.id)
        #expect(settlement.switchTarget?.accountID == seeded.project.id)
    }

    @Test("a chat already recorded on another account keeps it when the workspace's choice is recorded")
    func aRecordedChatKeepsItsOwnAccount() async throws {
        let seeded = try await seededWithAWorkspaceChoice(recordingTheChat: false)
        let store = try Store(path: seeded.path)

        #expect(try await store.session(id: seeded.elsewhere.id)?.accountID == seeded.project.id)
        #expect(try await store.activeSegment(sessionID: seeded.elsewhere.id)?.accountID == seeded.project.id)
        #expect(try await store.session(id: seeded.session.id)?.accountID == seeded.own.id)
    }

    @Test("a Codex chat in a workspace that chose a Claude account is not given that account")
    func aChatOfAnotherProviderIsNotGivenTheChoice() async throws {
        let seeded = try await seededWithAWorkspaceChoice(recordingTheChat: false)
        let store = try Store(path: seeded.path)

        #expect(try await store.session(id: seeded.codex.id)?.accountID == nil)
        #expect(try await store.activeSegment(sessionID: seeded.codex.id)?.accountID == nil)
        #expect(try await store.session(id: seeded.session.id)?.accountID == seeded.own.id)
    }

    @Test("a chat with no history is left unrecorded and simply runs the project's account")
    func aChatWithNoHistoryIsLeftAlone() async throws {
        let seeded = try await seededWithAWorkspaceChoice(recordingTheChat: false)
        let raw = try SQLiteDatabase(path: seeded.path)
        try raw.run("UPDATE sessions SET agent_session_id = NULL WHERE id = ?", [.text(seeded.session.id.rawValue)])
        try raw.run(
            "UPDATE session_segments SET agent_session_id = NULL WHERE session_id = ?",
            [.text(seeded.session.id.rawValue)]
        )
        let store = try Store(path: seeded.path)

        #expect(try await store.session(id: seeded.session.id)?.accountID == nil)
    }

    @Test("a database from before the choice tables records the workspace column on its chats before dropping it")
    func theOldWorkspaceColumnIsRecordedOnItsChats() async throws {
        let seeded = try await seededWithAWorkspaceChoice(recordingTheChat: false)
        let raw = try SQLiteDatabase(path: seeded.path)
        try raw.execute("DELETE FROM workspace_agent_accounts;")
        try raw.execute("ALTER TABLE workspaces ADD COLUMN account_id TEXT;")
        try raw.run(
            "UPDATE workspaces SET account_id = ? WHERE id = ?",
            [.text(seeded.own.id.rawValue), .text(seeded.workspace.id.rawValue)]
        )
        let store = try Store(path: seeded.path)

        let columns = try SQLiteDatabase(path: seeded.path).query("PRAGMA table_info(workspaces);")
            .compactMap { $0.string("name") }
        #expect(!columns.contains("account_id"))
        #expect(try await store.session(id: seeded.session.id)?.accountID == seeded.own.id)
        #expect(try await store.activeSegment(sessionID: seeded.session.id)?.accountID == seeded.own.id)
    }

    @Test("a build that knows fewer migrations than the database refuses it rather than reading it")
    func anOlderBuildRefusesTheMigratedDatabase() async throws {
        let seeded = try await seededWithAWorkspaceChoice()
        _ = try Store(path: seeded.path)

        let raw = try SQLiteDatabase(path: seeded.path)
        try raw.setUserVersion(seeded.version + 1)

        #expect(throws: SQLiteError.self) { _ = try Store(path: seeded.path) }
    }
}
