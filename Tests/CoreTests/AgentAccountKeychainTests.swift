import Testing
import Foundation
@testable import Core

private actor DeletedEntries {
    private(set) var entries: [AgentAccountKeychain.Entry] = []

    func note(_ entry: AgentAccountKeychain.Entry) {
        entries.append(entry)
    }
}

@Suite("Agent account keychain", .tags(.persistence), .scratchDirectory)
struct AgentAccountKeychainTests {
    private let deleted = DeletedEntries()
    private let measuredPath = "/tmp/ud-kc-vector/Application Support/Unified Dev/AgentAccounts/claudeCode/client"
    private let environment = ["USER": "fakeuser"]

    private var recording: AgentAccountKeychain {
        let deleted = deleted
        return AgentAccountKeychain { entry in
            await deleted.note(entry)
            return true
        }
    }

    private func scratchSupport() -> URL {
        URL(filePath: TestScratch.unique("support"), directoryHint: .isDirectory)
    }

    private func created(
        _ label: String, in store: Store, support: URL, provider: AgentKind = .claudeCode
    ) async throws -> AgentAccountHome {
        let made = AgentAccountCreation.plan(provider: provider, label: label, existing: [], support: support)
        try AgentAccountCreation.prepareDirectory(of: made.home)
        try await store.add(AgentAccountRow(id: made.id, provider: provider, directory: made.directory.path, label: label))
        return made.home
    }

    private func expected(for home: AgentAccountHome) -> [AgentAccountKeychain.Entry] {
        ClaudeKeychainEntries.of(
            configDirectory: home.directory.path, environment: Shell.environment(), username: NSUserName()
        )
    }

    @Test func theServicesAreTheOnesTheCliAskedForWithAFakeKeychain() {
        let entries = ClaudeKeychainEntries.of(configDirectory: measuredPath, environment: environment, username: "other")

        #expect(entries == [
            AgentAccountKeychain.Entry(service: "Claude Code-credentials-0cb3a733", account: "fakeuser"),
            AgentAccountKeychain.Entry(service: "Claude Code-0cb3a733", account: "fakeuser"),
        ])
    }

    @Test func aDecomposedPathHashesAsItsComposedFormLikeTheCli() {
        let decomposed = "/tmp/ud-kc-vector/Cafe\u{301}"

        let services = ClaudeKeychainEntries.of(configDirectory: decomposed, environment: environment, username: "x")
            .map(\.service)

        #expect(services == ["Claude Code-credentials-b25849f4", "Claude Code-b25849f4"])
    }

    @Test(arguments: [
        (["USER": "ada"], "ada"),
        ([:], "fallback.name"),
        (["USER": ""], "fallback.name"),
        (["USER": "a b"], "claude-code-user"),
        (["USER": "José"], "claude-code-user"),
        (["USER": "a_b-c.d"], "a_b-c.d"),
    ])
    func theAccountFollowsTheCli(environment: [String: String], account: String) {
        let entries = ClaudeKeychainEntries.of(
            configDirectory: measuredPath, environment: environment, username: "fallback.name"
        )

        #expect(entries.map(\.account) == [account, account])
    }

    @Test func theServiceIsCalculatedFromTheDirectoryTheCliIsTold() throws {
        let support = scratchSupport()
        let made = AgentAccountCreation.plan(provider: .claudeCode, label: "Client", existing: [], support: support)
        let told = try #require(AgentAccountEnvironment.apply(launching: .claudeCode, as: made.home, to: [:])["CLAUDE_CONFIG_DIR"])

        let entries = AgentAccountRemoval.keychainEntries(
            of: made.home, support: support, environment: environment, username: "x"
        )

        #expect(entries == ClaudeKeychainEntries.of(configDirectory: told, environment: environment, username: "x"))
        #expect(entries.count == 2)
    }

    @Test func theDeletionNeverAsksForTheSecret() {
        let entry = AgentAccountKeychain.Entry(service: "s", account: "a")

        #expect(AgentAccountKeychain.deletionArguments(for: entry) == ["delete-generic-password", "-a", "a", "-s", "s"])
    }

    @Test(arguments: [(Int32(0), true), (Int32(44), true), (Int32(1), false), (Int32(51), false)])
    func anEntryIsGoneWhenDeletedOrAlreadyAbsent(status: Int32, gone: Bool) {
        #expect(AgentAccountKeychain.isGone(exitStatus: status) == gone)
    }

    @Test func theLoginKeychainAsksTheToolAndReadsItsExit() async {
        let entry = AgentAccountKeychain.Entry(service: "s", account: "a")
        let seen = DeletedEntries()
        let deleted = await AgentAccountKeychain.running { tool, arguments in
            await seen.note(AgentAccountKeychain.Entry(service: tool, account: arguments.joined(separator: " ")))
            return 0
        }.delete(entry)
        let refused = await AgentAccountKeychain.running { _, _ in 51 }.delete(entry)
        let absent = await AgentAccountKeychain.running { _, _ in 44 }.delete(entry)
        let unrunnable = await AgentAccountKeychain.running { _, _ in throw CocoaError(.fileNoSuchFile) }.delete(entry)

        #expect(await seen.entries == [AgentAccountKeychain.Entry(
            service: "/usr/bin/security", account: "delete-generic-password -a a -s s"
        )])
        #expect(deleted)
        #expect(!refused)
        #expect(absent)
        #expect(!unrunnable)
    }

    @Test func removingAnAccountRowDeletesItsEntries() async throws {
        let store = try makeTestStore("keychain")
        let support = scratchSupport()
        let home = try await created("Client", in: store, support: support)
        let standings = await AgentAccountInventory.standingsWithoutAsking(rows: try await store.agentAccounts(), defaults: [])
        let row = try #require(
            AgentAccountPanel.make(provider: .claudeCode, standings: standings, codexStorageMode: .file).rows.first
        )

        try await AgentAccountRemoval.remove(row, support: support, store: store, keychain: recording, processes: { [] })

        #expect(await deleted.entries == expected(for: home))
    }

    @Test func removingAnUnfinishedRowDeletesItsEntries() async throws {
        let store = try makeTestStore("keychain")
        let support = scratchSupport()
        let orphan = AgentAccountCreation.plan(provider: .claudeCode, label: "Client", existing: [], support: support)
        try AgentAccountCreation.prepareDirectory(of: orphan.home)
        let row = try #require(
            AgentAccountPanel.make(provider: .claudeCode, standings: [], orphans: [orphan.home], codexStorageMode: .file).rows.first
        )

        try await AgentAccountRemoval.remove(row, support: support, store: store, keychain: recording, processes: { [] })

        #expect(await deleted.entries == expected(for: orphan.home))
    }

    @Test func anUnfinishedFolderThatCouldNotBeDeletedKeepsItsEntries() async throws {
        let support = scratchSupport()
        let orphan = AgentAccountCreation.plan(provider: .claudeCode, label: "Client", existing: [], support: support)
        try AgentAccountCreation.prepareDirectory(of: orphan.home)
        let parent = orphan.directory.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: parent.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path) }

        await #expect(throws: (any Error).self) {
            try await AgentAccountRemoval.removeUnfinished(orphan.home, support: support, keychain: recording, processes: { [] })
        }

        #expect(await deleted.entries.isEmpty)
    }

    @Test func anUnfinishedFolderWhoseUseCannotBeReadKeepsItsEntries() async throws {
        let support = scratchSupport()
        let orphan = AgentAccountCreation.plan(provider: .claudeCode, label: "Client", existing: [], support: support)
        try AgentAccountCreation.prepareDirectory(of: orphan.home)

        await #expect(throws: AgentAccountError.folderUseUnknown(orphan.directory.path)) {
            try await AgentAccountRemoval.removeUnfinished(orphan.home, support: support, keychain: recording, processes: { nil })
        }

        #expect(await deleted.entries.isEmpty)
        #expect(FileManager.default.fileExists(atPath: orphan.directory.path))
    }

    @Test func theFailureNamesTheEntryAndClaimsNothingAboutTheAccount() throws {
        let message = try #require(AgentAccountError.keychainEntriesLeft(["Claude Code-abc"]).errorDescription)

        #expect(message.contains("Claude Code-abc"))
        #expect(message.contains("Keychain Access"))
        #expect(!message.contains("was removed"))
    }

    @Test func thePanelWarnsOfTheKeychainOnlyOnAClaudeCodeRow() throws {
        func message(_ provider: AgentKind, folderExists: Bool = true) throws -> String {
            let home = AgentAccountHome(
                provider: provider, id: AgentAccountID("client"),
                directory: URL(filePath: "/tmp/\(provider.rawValue)/client", directoryHint: .isDirectory), isDefault: false
            )
            let standing = AgentAccountStanding(
                home: home, identity: AgentAccountIdentity(), cliReport: .claimsSession, isolationDoubt: nil, directoryExists: folderExists
            )
            let panel = AgentAccountPanel.make(provider: provider, standings: [standing], codexStorageMode: .file)
            return try #require(panel.rows.first?.removal?.message)
        }

        #expect(try message(.claudeCode).contains("keychain"))
        #expect(try !message(.codex).contains("keychain"))
    }

    @Test func removingAnAccountDeletesItsTwoEntriesAndNoOthers() async throws {
        let store = try makeTestStore("keychain")
        let support = scratchSupport()
        let gone = try await created("Gone", in: store, support: support)
        let kept = try await created("Kept", in: store, support: support)

        try await AgentAccountRemoval.remove(gone, support: support, store: store, keychain: recording, processes: { [] })

        let entries = await deleted.entries
        #expect(entries == expected(for: gone))
        #expect(Set(entries).isDisjoint(with: expected(for: kept)))
        #expect(entries.count == 2)
    }

    @Test func anAccountWhoseFolderIsAlreadyGoneStillLosesItsEntries() async throws {
        let store = try makeTestStore("keychain")
        let support = scratchSupport()
        let home = try await created("Client", in: store, support: support)
        try FileManager.default.removeItem(at: home.directory)

        try await AgentAccountRemoval.remove(home, support: support, store: store, keychain: recording, processes: { [] })

        #expect(await deleted.entries == expected(for: home))
    }

    @Test func anUnfinishedSignInLosesWhatItSaved() async throws {
        let support = scratchSupport()
        let orphan = AgentAccountCreation.plan(provider: .claudeCode, label: "Client", existing: [], support: support)
        try AgentAccountCreation.prepareDirectory(of: orphan.home)

        try await AgentAccountRemoval.removeUnfinished(orphan.home, support: support, keychain: recording, processes: { [] })

        #expect(await deleted.entries == expected(for: orphan.home))
    }

    @Test(arguments: [AgentKind.codex, AgentKind.grok])
    func anotherAgentHasNoEntryToDelete(provider: AgentKind) async throws {
        let store = try makeTestStore("keychain")
        let support = scratchSupport()
        let home = try await created("Client", in: store, support: support, provider: provider)

        try await AgentAccountRemoval.remove(home, support: support, store: store, keychain: recording, processes: { [] })

        #expect(await deleted.entries.isEmpty)
    }

    @Test func theDefaultLoginIsNeverAFolderEntry() {
        let support = scratchSupport()
        let byFlag = AgentAccountHome(
            provider: .claudeCode, id: AgentAccountID("odd"),
            directory: AgentAccountHomes.directory(for: AgentAccountID("odd"), provider: .claudeCode, support: support),
            isDefault: true
        )
        let id = AgentAccountHome.defaultID(for: .claudeCode)
        let byID = AgentAccountHome(
            provider: .claudeCode, id: id,
            directory: AgentAccountHomes.directory(for: id, provider: .claudeCode, support: support),
            isDefault: false
        )

        #expect(AgentAccountRemoval.keychainEntries(of: byFlag, support: support, environment: environment, username: "x").isEmpty)
        #expect(AgentAccountRemoval.keychainEntries(of: byID, support: support, environment: environment, username: "x").isEmpty)
    }

    @Test func aFolderOutsideTheAccountsRootNamesNoEntry() {
        let support = scratchSupport()
        let elsewhere = URL(filePath: TestScratch.unique("not-ours"), directoryHint: .isDirectory)
        let home = AgentAccountHome(provider: .claudeCode, id: AgentAccountID("odd"), directory: elsewhere, isDefault: false)

        #expect(AgentAccountRemoval.keychainEntries(of: home, support: support, environment: environment, username: "x").isEmpty)
    }

    @Test func aFolderLeftAloneKeepsItsEntries() async throws {
        let store = try makeTestStore("keychain")
        let support = scratchSupport()
        let elsewhere = URL(filePath: TestScratch.unique("not-ours"), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let home = AgentAccountHome(provider: .claudeCode, id: AgentAccountID("odd"), directory: elsewhere, isDefault: false)
        try await store.add(AgentAccountRow(id: home.id, provider: .claudeCode, directory: elsewhere.path))

        await #expect(throws: AgentAccountError.folderLeftAlone(elsewhere.path)) {
            try await AgentAccountRemoval.remove(home, support: support, store: store, keychain: recording, processes: { [] })
        }

        #expect(await deleted.entries.isEmpty)
    }

    @Test func aFolderThatCouldNotBeDeletedKeepsItsEntriesForTheRetry() async throws {
        let store = try makeTestStore("keychain")
        let support = scratchSupport()
        let home = try await created("Client", in: store, support: support)
        let parent = home.directory.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: parent.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path) }

        await #expect(throws: (any Error).self) {
            try await AgentAccountRemoval.remove(home, support: support, store: store, keychain: recording, processes: { [] })
        }

        #expect(await deleted.entries.isEmpty)
    }

    @Test func anAccountWithARunningAgentKeepsItsEntries() async throws {
        let store = try makeTestStore("keychain")
        let support = scratchSupport()
        let home = try await created("Client", in: store, support: support)
        let repo = try await store.upsert(Repo(name: "r", path: TestScratch.unique("repo")))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "billing", branch: "feature/x", path: TestScratch.unique("worktree"), baseBranch: "main"
        ))
        try await store.chooseAgentAccount(ChosenAgentAccount(home), forRepo: repo.id)
        var session = Session(workspaceID: workspace.id)
        session.apply(.turnStarted)
        try await store.upsert(session)

        await #expect(throws: AgentAccountError.inUse(workspaces: ["billing"])) {
            try await AgentAccountRemoval.remove(home, support: support, store: store, keychain: recording, processes: { [] })
        }

        #expect(await deleted.entries.isEmpty)
    }

    @Test func anEntryThatCouldNotBeDeletedIsNamedAndTheOtherIsStillTried() async throws {
        let store = try makeTestStore("keychain")
        let support = scratchSupport()
        let home = try await created("Client", in: store, support: support)
        let deleted = deleted
        let failing = AgentAccountKeychain { entry in
            await deleted.note(entry)
            return entry.service.contains("-credentials-") == false
        }
        let service = try #require(expected(for: home).first?.service)

        await #expect(throws: AgentAccountError.keychainEntriesLeft([service])) {
            try await AgentAccountRemoval.remove(home, support: support, store: store, keychain: failing, processes: { [] })
        }

        #expect(await deleted.entries == expected(for: home))
        #expect(try await store.agentAccounts().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: home.directory.path))
    }

    @Test(arguments: [AgentKind.codex, AgentKind.grok])
    func theWarningOfAnotherAgentSaysNothingAboutTheKeychain(provider: AgentKind) {
        let account = AgentAccountRemoval.warning(forAccountNamed: "x", provider: provider, folderExists: true)
        let gone = AgentAccountRemoval.warning(forAccountNamed: "x", provider: provider, folderExists: false)
        let unfinished = AgentAccountRemoval.warningForUnfinishedSignIn(named: "x", provider: provider)

        #expect(!account.message.lowercased().contains("keychain"))
        #expect(!gone.message.lowercased().contains("keychain"))
        #expect(!unfinished.message.lowercased().contains("keychain"))
    }
}
