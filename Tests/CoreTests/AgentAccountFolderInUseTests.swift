import Testing
import Foundation
@testable import Core

@Suite("An account folder a process is still using", .tags(.persistence), .scratchDirectory)
struct AgentAccountFolderInUseTests {
    private func scratchSupport() -> URL {
        URL(filePath: TestScratch.unique("support"), directoryHint: .isDirectory)
    }

    private func account(in store: Store, support: URL) async throws -> AgentAccountHome {
        let made = AgentAccountCreation.plan(provider: .claudeCode, label: "Client", existing: [], support: support)
        try AgentAccountCreation.prepareDirectory(of: made.home)
        try await store.add(AgentAccountRow(id: made.id, provider: .claudeCode, directory: made.directory.path, label: "Client"))
        return made.home
    }

    private func whileACliHolds<T>(
        _ folder: URL,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ body: (ChildProcess) async throws -> T
    ) async throws -> T {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let held = folder.appending(path: "held.log")
        try Data().write(to: held)
        let cli = try ChildProcess("/usr/bin/tail", ["-f", held.path])
        do {
            let value = try await body(cli)
            await cli.stop(sourceLocation: sourceLocation)
            return value
        } catch {
            await cli.stop(sourceLocation: sourceLocation)
            throw error
        }
    }

    @Test func aCliInATerminalPaneKeepsTheFolderEvenThoughNoTurnIsRecorded() async throws {
        let store = try makeTestStore("in-use")
        let support = scratchSupport()
        let home = try await account(in: store, support: support)
        try await whileACliHolds(home.directory) { _ in
            await #expect(throws: AgentAccountError.folderInUse(home.directory.path)) {
                try await AgentAccountRemoval.remove(home, support: support, store: store, keychain: .untouched)
            }

            let accounts = try await store.agentAccounts().map(\.id)
            #expect(FileManager.default.fileExists(atPath: home.directory.path))
            #expect(accounts == [home.id])
        }
    }

    @Test func aTurnStillRecordedInAnArchivedWorkspaceKeepsTheFolder() async throws {
        let store = try makeTestStore("in-use")
        let support = scratchSupport()
        let home = try await account(in: store, support: support)
        let repo = try await store.upsert(Repo(name: "r", path: TestScratch.unique("repo")))
        var workspace = Workspace(
            repoID: repo.id, name: "billing", branch: "feature/x", path: TestScratch.unique("worktree"), baseBranch: "main"
        )
        workspace.archive()
        try await store.upsert(workspace)
        try await store.chooseAgentAccount(ChosenAgentAccount(home), forRepo: repo.id)
        var session = Session(workspaceID: workspace.id)
        session.apply(.turnStarted)
        try await store.upsert(session)

        await #expect(throws: AgentAccountError.inUse(workspaces: ["billing"])) {
            try await AgentAccountRemoval.remove(home, support: support, store: store, keychain: .untouched)
        }

        #expect(FileManager.default.fileExists(atPath: home.directory.path))
    }

    @Test func aLoginStillRunningKeepsTheFolderOfAnUnfinishedSignIn() async throws {
        let support = scratchSupport()
        let made = AgentAccountCreation.plan(provider: .claudeCode, label: "Client", existing: [], support: support)
        try AgentAccountCreation.prepareDirectory(of: made.home)
        try await whileACliHolds(made.directory) { _ in
            await #expect(throws: AgentAccountError.folderInUse(made.directory.path)) {
                try await AgentAccountRemoval.removeUnfinished(made.home, support: support, keychain: .untouched)
            }

            #expect(FileManager.default.fileExists(atPath: made.directory.path))
        }
    }

    @Test func aReservationAProcessStillHoldsIsNotDiscarded() async throws {
        let support = scratchSupport()
        let reservation = try AgentAccountCreation.reserve(
            provider: .claudeCode, label: "Client", existing: [], support: support
        )
        try await whileACliHolds(reservation.plan.directory) { _ in
            #expect(!reservation.discard())
            #expect(FileManager.default.fileExists(atPath: reservation.plan.directory.path))
        }
    }

    @Test func aFolderAlreadyGoneIsForgottenEvenWhenTheProcessesCannotBeRead() async throws {
        let store = try makeTestStore("in-use")
        let support = scratchSupport()
        let home = try await account(in: store, support: support)
        try FileManager.default.removeItem(at: home.directory)

        try await AgentAccountRemoval.remove(home, support: support, store: store, keychain: .untouched, processes: { nil })

        #expect(try await store.agentAccounts().isEmpty)
    }

    @Test func aRowOutsideTheAccountsRootIsForgottenEvenWhileAProcessNamesIt() async throws {
        let store = try makeTestStore("in-use")
        let support = scratchSupport()
        let elsewhere = URL(filePath: TestScratch.unique("not-ours"), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let home = AgentAccountHome(
            provider: .claudeCode, id: AgentAccountID("odd"), directory: elsewhere, isDefault: false
        )
        try await store.add(AgentAccountRow(id: home.id, provider: .claudeCode, directory: elsewhere.path))
        let holder = ProcessVector(pid: 7, strings: ["X=\(elsewhere.path)"])

        await #expect(throws: AgentAccountError.folderLeftAlone(elsewhere.path)) {
            try await AgentAccountRemoval.remove(home, support: support, store: store, keychain: .untouched, processes: { [holder] })
        }

        #expect(FileManager.default.fileExists(atPath: elsewhere.path))
        #expect(try await store.agentAccounts().isEmpty)
    }

    @Test func aTurnRecordedOnTheAccountKeepsItAfterTheProjectChoseAnother() async throws {
        let store = try makeTestStore("in-use")
        let support = scratchSupport()
        let home = try await account(in: store, support: support)
        let repo = try await store.upsert(Repo(name: "r", path: TestScratch.unique("repo")))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "billing", branch: "feature/x", path: TestScratch.unique("worktree"), baseBranch: "main"
        ))
        var session = Session(workspaceID: workspace.id)
        session.accountID = home.id
        session.apply(.turnStarted)
        try await store.upsert(session)

        await #expect(throws: AgentAccountError.inUse(workspaces: ["billing"])) {
            try await AgentAccountRemoval.remove(home, support: support, store: store, keychain: .untouched, processes: { [] })
        }

        #expect(FileManager.default.fileExists(atPath: home.directory.path))
    }

    @Test func anAccountIsLeftAloneAndKeptWhenTheProcessesCannotBeRead() async throws {
        let store = try makeTestStore("in-use")
        let support = scratchSupport()
        let home = try await account(in: store, support: support)

        await #expect(throws: AgentAccountError.folderUseUnknown(home.directory.path)) {
            try await AgentAccountRemoval.remove(home, support: support, store: store, keychain: .untouched, processes: { nil })
        }

        #expect(FileManager.default.fileExists(atPath: home.directory.path))
        #expect(try await store.agentAccounts().map(\.id) == [home.id])
    }

    @Test func aProcessThatStartsDuringTheRemovalStillKeepsTheFolder() async throws {
        let store = try makeTestStore("in-use")
        let support = scratchSupport()
        let home = try await account(in: store, support: support)
        let held = ProcessVector(pid: 7, strings: ["CLAUDE_CONFIG_DIR=\(home.directory.path)"])
        let reads = Reads()

        await #expect(throws: AgentAccountError.forgottenWithFolderKept(home.directory.path)) {
            try await AgentAccountRemoval.remove(home, support: support, store: store, keychain: .untouched, processes: {
                reads.next() == 0 ? [] : [held]
            })
        }

        #expect(FileManager.default.fileExists(atPath: home.directory.path))
        #expect(try await store.agentAccounts().isEmpty)
    }

    @Test func anUnreadableProcessAfterTheForgetIsReportedAsAKeptFolder() async throws {
        let store = try makeTestStore("in-use")
        let support = scratchSupport()
        let home = try await account(in: store, support: support)
        let reads = Reads()

        await #expect(throws: AgentAccountError.forgottenWithFolderKept(home.directory.path)) {
            try await AgentAccountRemoval.remove(home, support: support, store: store, keychain: .untouched, processes: {
                reads.next() == 0 ? [] : nil
            })
        }

        #expect(FileManager.default.fileExists(atPath: home.directory.path))
        #expect(try await store.agentAccounts().isEmpty)
    }

    @Test func aRecordedTurnNamesItsWorkspaceEvenWhenAProcessAlsoHoldsTheFolder() async throws {
        let store = try makeTestStore("in-use")
        let support = scratchSupport()
        let home = try await account(in: store, support: support)
        let repo = try await store.upsert(Repo(name: "r", path: TestScratch.unique("repo")))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "billing", branch: "feature/x", path: TestScratch.unique("worktree"), baseBranch: "main"
        ))
        var session = Session(workspaceID: workspace.id)
        session.accountID = home.id
        session.apply(.turnStarted)
        try await store.upsert(session)
        let holder = ProcessVector(pid: 7, strings: ["X=\(home.directory.path)"])

        await #expect(throws: AgentAccountError.inUse(workspaces: ["billing"])) {
            try await AgentAccountRemoval.remove(home, support: support, store: store, keychain: .untouched, processes: { [holder] })
        }
    }

    @Test func nothingHoldingTheFolderLetsItGo() async throws {
        let store = try makeTestStore("in-use")
        let support = scratchSupport()
        let home = try await account(in: store, support: support)
        let other = ProcessVector(pid: 7, strings: ["sleep", "HOME=/Users/someone"])

        try await AgentAccountRemoval.remove(home, support: support, store: store, keychain: .untouched, processes: { [other] })

        #expect(!FileManager.default.fileExists(atPath: home.directory.path))
    }

    @Test(arguments: [
        ("CLAUDE_CONFIG_DIR=/s/AgentAccounts/claudeCode/client", true),
        ("--config=/s/AgentAccounts/claudeCode/client/settings.json", true),
        ("/s/AgentAccounts/claudeCode/client", true),
        ("CLAUDE_CONFIG_DIR=/s/AgentAccounts/claudeCode/client-2", false),
        ("CLAUDE_CONFIG_DIR=/s/AgentAccounts/claudeCode/client.old", false),
        ("CLAUDE_CONFIG_DIR=/s/AgentAccounts/claudeCode/client2", false),
        ("CLAUDE_CONFIG_DIR=/s/AgentAccounts/claudeCode/clientx", false),
        ("CLAUDE_CONFIG_DIR=/s/AgentAccounts/claudeCode/client_2", false),
        ("CLAUDE_CONFIG_DIR=/s/AgentAccounts/claudeCode/client2 x /s/AgentAccounts/claudeCode/client", true),
    ])
    func aFolderIsHeldOnlyByAProcessThatNamesIt(entry: String, held: Bool) {
        let folder = URL(filePath: "/s/AgentAccounts/claudeCode/client", directoryHint: .isDirectory)
        let use = AgentAccountFolderUse.of(folder, among: [ProcessVector(pid: 7, strings: [entry])])

        #expect(use == (held ? .held(pids: [7]) : .free))
    }

    @Test func aProcessWhoseVectorCannotBeReadMakesTheAnswerUnknown() {
        let folder = URL(filePath: "/s/client", directoryHint: .isDirectory)
        let use = AgentAccountFolderUse.of(folder, among: [
            ProcessVector(pid: 7, strings: ["sleep"]), ProcessVector(pid: 8, strings: nil),
        ])

        #expect(use == .unknown)
    }

    @Test func aRealProcessIsFoundByTheFolderItNames() async throws {
        let folder = URL(filePath: TestScratch.unique("account"), directoryHint: .isDirectory)

        try await whileACliHolds(folder) { cli in
            let use = AgentAccountFolderUse.of(folder, among: ProcessVectors.ofThisUser())
            #expect(use == .held(pids: [cli.process.processIdentifier]))
        }
    }

    @Test func aFolderIsAlsoHeldThroughItsResolvedPath() throws {
        let real = URL(filePath: TestScratch.unique("real"), directoryHint: .isDirectory)
        let link = URL(filePath: TestScratch.unique("link"), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let holder = ProcessVector(pid: 7, strings: ["X=\(real.resolvingSymlinksInPath().path)"])

        #expect(AgentAccountFolderUse.of(link, among: [holder]) == .held(pids: [7]))
    }

    @Test func eachRefusalSaysWhatHappenedToTheAccount() {
        let held = AgentAccountError.folderInUse("/f").errorDescription ?? ""
        let unknown = AgentAccountError.folderUseUnknown("/f").errorDescription ?? ""
        let forgotten = AgentAccountError.forgottenWithFolderKept("/f").errorDescription ?? ""

        #expect(held.contains("still using"))
        #expect(unknown.contains("could not tell"))
        #expect(forgotten.contains("forgotten"))
    }

    @Test func aProcessThatHoldsTheFolderOutweighsOneThatCannotBeRead() {
        let folder = URL(filePath: "/s/client", directoryHint: .isDirectory)
        let use = AgentAccountFolderUse.of(folder, among: [
            ProcessVector(pid: 8, strings: nil), ProcessVector(pid: 9, strings: ["X=/s/client"]),
        ])

        #expect(use == .held(pids: [9]))
    }
}

final class Reads: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        defer { count += 1 }
        return count
    }
}
