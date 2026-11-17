import Testing
import Foundation
@testable import Core

@Suite("Chats from before accounts belong to their provider's default account", .tags(.persistence), .scratchDirectory)
struct PreAccountChatOwnersTests {
    private struct Seeded {
        let path: String
        let repo: Repo
        let claude: Session
        let codex: Session?
        let grok: Session
        let fresh: Session
        let blank: Session
        let owned: Session
        let client: AgentAccountRow
    }

    private let defaultClaude = AgentAccountHome.defaultID(for: .claudeCode)
    private let defaultCodex = AgentAccountHome.defaultID(for: .codex)
    private let accountsMigrationFromTheEnd: Int32 = 14

    private func seeded(_ name: String, withCodex: Bool = true) async throws -> Seeded {
        let path = TestScratch.unique(name) + ".sqlite"
        let store = try Store(path: path)
        let repo = try await store.upsert(Repo(name: "billing", path: TestScratch.unique("repo")))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "invoices", branch: "b", path: TestScratch.unique("worktree"), baseBranch: "main"
        ))
        let client = AgentAccountRow(
            id: AgentAccountID("client"), provider: .claudeCode, directory: "/accounts/claudeCode/client"
        )
        try await store.add(client)
        let claude = try await store.upsert(Session(workspaceID: workspace.id, agentSessionID: "claude-native"))
        let codex = withCodex ? try await store.upsert(Session(
            workspaceID: workspace.id, agentSessionID: "codex-native", model: "gpt-5", agentKind: .codex
        )) : nil
        let grok = try await store.upsert(Session(
            workspaceID: workspace.id, agentSessionID: "grok-native", model: "grok-4", agentKind: .grok
        ))
        let fresh = try await store.upsert(Session(workspaceID: workspace.id))
        let blank = try await store.upsert(Session(workspaceID: workspace.id, agentSessionID: ""))
        let owned = try await store.upsert(Session(workspaceID: workspace.id, agentSessionID: "client-native"))
        try await store.update(sessionID: owned.id, accountID: client.id)
        try await store.appendNext(sessionID: claude.id, kind: .assistantText, payload: Data())
        return Seeded(
            path: path, repo: repo, claude: claude, codex: codex, grok: grok, fresh: fresh, blank: blank,
            owned: owned, client: client
        )
    }

    private func fromBeforeAccounts(_ name: String, withCodex: Bool = true) async throws -> (Seeded, Store) {
        let seeded = try await seeded(name, withCodex: withCodex)
        let raw = try SQLiteDatabase(path: seeded.path)
        try raw.execute("DROP TABLE session_segments;")
        try raw.execute("DELETE FROM agent_accounts WHERE is_default = 1;")
        try raw.setUserVersion(0)
        return (seeded, try Store(path: seeded.path))
    }

    private func rewound(_ name: String, by steps: Int32) async throws -> (Seeded, Store) {
        let seeded = try await seeded(name)
        let raw = try SQLiteDatabase(path: seeded.path)
        try raw.setUserVersion(try raw.readUserVersion() - steps)
        return (seeded, try Store(path: seeded.path))
    }

    @Test("a chat with history from before accounts is recorded on its provider's default account, and so is its segment")
    func aChatFromBeforeAccountsIsRecordedOnTheDefault() async throws {
        let (seeded, store) = try await fromBeforeAccounts("pre-account-default")
        let codex = try #require(seeded.codex)

        #expect(try await store.session(id: seeded.claude.id)?.accountID == defaultClaude)
        #expect(try await store.activeSegment(sessionID: seeded.claude.id)?.accountID == defaultClaude)
        #expect(try await store.session(id: codex.id)?.accountID == defaultCodex)
        #expect(try await store.activeSegment(sessionID: codex.id)?.accountID == defaultCodex)
        let defaults = try await store.agentAccounts().filter(\.isDefault)
        #expect(Set(defaults.map(\.id)) == [defaultClaude, defaultCodex])
        #expect(defaults.first { $0.id == defaultCodex }?.provider == .codex)
    }

    @Test("a provider with no chat to record gains no default account row")
    func aProviderWithNothingToRecordGainsNoRow() async throws {
        let (_, store) = try await fromBeforeAccounts("pre-account-claude-only", withCodex: false)

        #expect(Set(try await store.agentAccounts().filter(\.isDefault).map(\.id)) == [defaultClaude])
    }

    @Test("a chat with no history, an empty one, or one of an agent with no default account, is left unrecorded")
    func chatsWithNoKnownOwnerAreLeftAlone() async throws {
        let (seeded, store) = try await fromBeforeAccounts("pre-account-unknown")

        for chat in [seeded.fresh, seeded.blank, seeded.grok] {
            #expect(try await store.session(id: chat.id)?.accountID == nil)
            #expect(try await store.activeSegment(sessionID: chat.id)?.accountID == nil)
        }
    }

    @Test("a chat that already names its account keeps it")
    func aRecordedChatKeepsItsAccount() async throws {
        let (seeded, store) = try await fromBeforeAccounts("pre-account-owned")

        #expect(try await store.session(id: seeded.owned.id)?.accountID == seeded.client.id)
        #expect(try await store.activeSegment(sessionID: seeded.owned.id)?.accountID == seeded.client.id)
    }

    @Test("a database stopped just before the accounts migration has its chats recorded")
    func theLastVersionBeforeAccountsIsRecorded() async throws {
        let (seeded, store) = try await rewound("pre-account-edge", by: accountsMigrationFromTheEnd)

        #expect(try await store.session(id: seeded.claude.id)?.accountID == defaultClaude)
        #expect(try await store.activeSegment(sessionID: seeded.claude.id)?.accountID == defaultClaude)
    }

    @Test("a chat with history and no owner in a database that already had accounts stays unknown")
    func aDatabaseWithAccountsKeepsItsUnknownChats() async throws {
        for steps in [1, accountsMigrationFromTheEnd - 1] {
            let (seeded, store) = try await rewound("pre-account-later", by: steps)

            #expect(try await store.session(id: seeded.claude.id)?.accountID == nil)
            #expect(try await store.activeSegment(sessionID: seeded.claude.id)?.accountID == nil)
        }
    }

    @Test("a project that chooses another account moves the old chat there instead of resuming it under that account")
    func choosingAnotherAccountMovesTheOldChat() async throws {
        let (seeded, store) = try await fromBeforeAccounts("pre-account-choice")
        let client = AgentAccountHome(
            provider: .claudeCode, id: AgentAccountID("client"),
            directory: URL(filePath: "/accounts/claudeCode/client", directoryHint: .isDirectory), isDefault: false
        )
        let session = try #require(try await store.session(id: seeded.claude.id))

        let settled = AgentSessionSettlement.decide(session: session, account: client, purpose: .sending)

        #expect(settled.switchTarget?.accountID == client.id)
        #expect(AgentSessionSettlement.resumable(session: session, account: client) == nil)
    }

    @Test("leaving for another agent and coming back resumes the old chat's own conversation")
    func comingBackResumesTheParkedConversation() async throws {
        let (seeded, store) = try await fromBeforeAccounts("pre-account-return")
        let original = try #require(try await store.activeSegment(sessionID: seeded.claude.id))
        for provider in [AgentKind.claudeCode, .codex] {
            try await store.addIfMissing(AgentAccountRow(
                id: AgentAccountHome.defaultID(for: provider), provider: provider,
                directory: "/home/\(provider.rawValue)", isDefault: true
            ))
        }

        _ = try await store.switchSegment(sessionID: seeded.claude.id, to: SessionSegmentTarget(
            agentKind: .codex, accountID: defaultCodex, model: "gpt-5", effort: ""
        ))
        let back = try await store.switchSegment(sessionID: seeded.claude.id, to: SessionSegmentTarget(
            agentKind: .claudeCode, accountID: defaultClaude, model: seeded.claude.model, effort: ""
        ))

        let active = try #require(try await store.activeSegment(sessionID: seeded.claude.id))
        #expect(active.id == original.id)
        #expect(active.cursorSeq == original.cursorSeq)
        #expect(back.agentSessionID == "claude-native")
        #expect(try await store.segments(sessionID: seeded.claude.id).count == 2)
    }
}
