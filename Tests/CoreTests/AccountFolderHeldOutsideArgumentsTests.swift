import Testing
import Foundation
@testable import Core

@Suite("An account folder a process holds without naming it in its arguments", .tags(.persistence), .scratchDirectory)
struct AccountFolderHeldOutsideArgumentsTests {
    private func scratchSupport() -> URL {
        URL(filePath: TestScratch.unique("support"), directoryHint: .isDirectory)
    }

    private func account(in store: Store, support: URL) async throws -> AgentAccountHome {
        let made = AgentAccountCreation.plan(provider: .claudeCode, label: "Client", existing: [], support: support)
        try AgentAccountCreation.prepareDirectory(of: made.home)
        try await store.add(AgentAccountRow(id: made.id, provider: .claudeCode, directory: made.directory.path, label: "Client"))
        return made.home
    }

    private func cliStartedByHand(
        workingIn directory: URL,
        reading input: URL? = nil
    ) throws -> ChildProcess {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sleep")
        process.arguments = ["120"]
        process.environment = [:]
        process.currentDirectoryURL = directory
        let handle = try input.map { try FileHandle(forReadingFrom: $0) }
        process.standardInput = handle
        let child = try ChildProcess(process)
        try handle?.close()
        return child
    }

    private func elsewhere() throws -> URL {
        let directory = URL(filePath: TestScratch.unique("elsewhere"), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test(arguments: [
        ("/s/AgentAccounts/claudeCode/client", true),
        ("/s/AgentAccounts/claudeCode/client/projects/a.jsonl", true),
        ("/s/AgentAccounts/claudeCode/client-2", false),
        ("/s/AgentAccounts/claudeCode/client2/projects/a.jsonl", false),
        ("/s/AgentAccounts/claudeCode", false),
    ])
    func aFolderIsHeldByAProcessWorkingInItOrHoldingAFileInsideIt(path: String, held: Bool) {
        let folder = URL(filePath: "/s/AgentAccounts/claudeCode/client", directoryHint: .isDirectory)
        let process = ProcessVector(pid: 7, strings: ["sleep", "120"], paths: [path])

        #expect(AgentAccountFolderUse.of(folder, among: [process]) == (held ? .held(pids: [7]) : .free))
    }

    @Test func aCliWorkingInsideTheFolderIsFoundThoughNothingItWasGivenNamesIt() async throws {
        let folder = URL(filePath: TestScratch.unique("account"), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let cli = try cliStartedByHand(workingIn: folder)

        let use = AgentAccountFolderUse.of(folder, among: ProcessVectors.ofThisUser())
        await cli.stop()

        guard case .held(let pids) = use else { Issue.record("expected the folder to be held, got \(use)"); return }
        #expect(pids.contains(cli.process.processIdentifier))
    }

    @Test func aCliHoldingAFileInsideTheFolderOpenIsFoundThoughItWorksElsewhere() async throws {
        let folder = URL(filePath: TestScratch.unique("account"), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let history = folder.appending(path: "history.jsonl")
        try Data().write(to: history)
        let cli = try cliStartedByHand(workingIn: try elsewhere(), reading: history)

        let use = AgentAccountFolderUse.of(folder, among: ProcessVectors.ofThisUser())
        await cli.stop()

        guard case .held(let pids) = use else { Issue.record("expected the folder to be held, got \(use)"); return }
        #expect(pids.contains(cli.process.processIdentifier))
    }

    @Test func removingTheAccountRefusesWhileACliStartedByHandWorksInItsFolder() async throws {
        let store = try makeTestStore("held-outside-arguments")
        let support = scratchSupport()
        let home = try await account(in: store, support: support)
        let cli = try cliStartedByHand(workingIn: home.directory)

        await #expect(throws: AgentAccountError.folderInUse(home.directory.path)) {
            try await AgentAccountRemoval.remove(home, support: support, store: store, keychain: .untouched)
        }
        await cli.stop()

        #expect(FileManager.default.fileExists(atPath: home.directory.path))
        #expect(try await store.agentAccounts().map(\.id) == [home.id])
    }

    @Test func aDescriptionNeverCarriesThePathsAProcessHolds() {
        let vector = ProcessVector(pid: 7, strings: [], paths: ["/s/private-folder"])

        #expect(!String(describing: vector).contains("private-folder"))
        #expect(!String(reflecting: vector).contains("private-folder"))
        #expect(Mirror(reflecting: vector).children.map(\.label) == ["pid"])
    }
}
