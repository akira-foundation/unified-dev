import Testing
import Foundation
import Synchronization
@testable import Core

@Suite("Every other way an agent is started carries the account that was chosen", .scratchDirectory)
struct AgentLaunchAccountCatalogueTests {
    private let workClaude = LaunchAccountFixture.workClaude
    private let workCodex = LaunchAccountFixture.workCodex
    private let workGrok = LaunchAccountFixture.workGrok

    @Test func aCodexRunnerBuildsItsClientForTheAccount() async throws {
        let (store, made) = try await LaunchAccountFixture.session(kind: .codex)
        let seen = Mutex<CodexClient.Configuration?>(nil)
        let runner = CodexRunner(
            workspacePath: "/tmp/w", session: made, store: store, segmentID: try await activeSegmentID(store, made), account: workCodex,
            makeClient: { configuration in
                seen.withLock { $0 = configuration }
                return CodexClient(configuration: configuration, makeProcess: { _ in SilentProcess() })
            }
        )
        try? await runner.send("hello")
        runner.terminateNow()
        let configuration = try #require(seen.withLock { $0 })
        #expect(configuration.account == workCodex)
        #expect(CodexClient.launch(configuration).environment["CODEX_HOME"] == workCodex.directory.path)
    }

    @Test func aGrokRunnerBuildsItsClientForTheAccount() async throws {
        let (store, made) = try await LaunchAccountFixture.session(kind: .grok)
        let seen = Mutex<ACPClient.Configuration?>(nil)
        let runner = ACPRunner(
            dialect: .grok,
            workspacePath: "/tmp/w", session: made, store: store, segmentID: try await activeSegmentID(store, made), account: workGrok,
            makeClient: { configuration in
                seen.withLock { $0 = configuration }
                return ACPClient(configuration: configuration, makeProcess: { _ in SilentProcess() })
            }
        )
        try? await runner.send("hello")
        runner.terminateNow()
        let configuration = try #require(seen.withLock { $0 })
        #expect(configuration.account == workGrok)
        #expect(ACPClient.launch(configuration).environment["GROK_HOME"] == workGrok.directory.path)
    }

    @Test func theCodexModelCatalogueListsUnderTheAccount() async {
        let log = LaunchLog()
        _ = try? await CodexModelCatalog.live(account: workCodex, makeProcess: log.factory).models()
        #expect(log.first?.environment["CODEX_HOME"] == workCodex.directory.path)
    }

    @Test func theCodexSkillCatalogueListsUnderTheAccount() async {
        let log = LaunchLog()
        _ = await CodexSkillCatalog.live(project: "/tmp/w", account: workCodex, makeProcess: log.factory).skills()
        #expect(log.first?.environment["CODEX_HOME"] == workCodex.directory.path)
    }

    @Test func theCodexSpeedIsReadUnderTheAccount() async {
        let log = LaunchLog()
        _ = try? await CodexSpeed.read(
            cwd: "/tmp/w", modelID: "gpt-5.6-sol", account: workCodex, makeProcess: log.factory
        )
        #expect(log.first?.environment["CODEX_HOME"] == workCodex.directory.path)
    }

    @Test func theGrokModelCatalogueListsUnderTheAccount() async {
        let seen = Mutex<ACPClient.Configuration?>(nil)
        let catalogue = GrokModelCatalog.live(account: workGrok, makeClient: { configuration in
            seen.withLock { $0 = configuration }
            return ACPClient(configuration: configuration, makeProcess: { _ in SilentProcess() })
        })
        _ = try? await catalogue.models()
        #expect(seen.withLock { $0 }?.account == workGrok)
    }

    @Test func theWorkspaceNamerLaunchCarriesTheAccountAndNoInheritedVariable() {
        let launch = WorkspaceNamer.launch(prompt: "name this", account: workClaude, environment: LaunchAccountFixture.inherited)
        #expect(launch.environment["CLAUDE_CONFIG_DIR"] == workClaude.directory.path)
        LaunchAccountFixture.expectClean(launch.environment)
    }

    @Test func theWorkspaceNamerAsksUnderTheAccountItWasGiven() async {
        let seen = Mutex<WorkspaceNamerLaunch?>(nil)
        let namer = WorkspaceNamer(run: { launch in
            seen.withLock { $0 = launch }
            return Data()
        })
        _ = await namer.suggest(
            task: "add a toggle", project: "p", template: "{task} {project}", account: workClaude
        )
        #expect(seen.withLock { $0 }?.environment["CLAUDE_CONFIG_DIR"] == workClaude.directory.path)
    }

    @Test func theWorkspaceNamerRunsWithTheEnvironmentItWasHandedAndNoOther() async throws {
        let launch = WorkspaceNamerLaunch(
            executable: "/usr/bin/env", arguments: [], stdin: "", cwd: "/tmp",
            environment: ["ONLY": "this"]
        )
        let output = try await WorkspaceNamer.shell(launch)
        let lines = String(decoding: output, as: UTF8.self).split(separator: "\n").map(String.init)
        #expect(lines == ["ONLY=this"])
    }

    @Test(
        "an interactive launch points the CLI at whichever account it runs and drops the inherited credentials",
        .tags(.subprocess),
        arguments: SignInShell.all, SignInShell.Account.allCases
    )
    func anInteractiveLaunchPointsTheCliAtTheAccountAndDropsInheritedVariables(
        shell: String, kind: SignInShell.Account
    ) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("unifieddev-account-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let account = kind.home(in: root)
        let fake = root.appendingPathComponent("claude")
        let probe = (LaunchAccountFixture.hostAuth + LaunchAccountFixture.credentials
            + LaunchAccountFixture.tokens + ["CLAUDE_CONFIG_DIR"])
            .map { "\($0)=${\($0)-unset}" }.joined(separator: " ")
        try Data("#!/bin/sh\necho \"\(probe)\"\n".utf8).write(to: fake)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fake.path)
        let command = try #require(AgentKind.claudeCode.interactiveCommand(
            directory: root.path, prompt: "", sessionID: .new(), model: "", effort: "", account: account
        ))
        var inherited = LaunchAccountFixture.inherited
        inherited["PATH"] = root.path + ":/usr/bin:/bin"
        inherited["CLAUDE_CONFIG_DIR"] = "/somewhere/else"
        let result = try await Shell.run(shell, ["-c", command], env: inherited)
        #expect(result.ok, "\(shell) exited \(result.status): \(result.stderr)")
        let reported = Dictionary(
            uniqueKeysWithValues: result.trimmed.split(separator: " ").compactMap { pair -> (String, String)? in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                return parts.count == 2 ? (parts[0], parts[1]) : nil
            }
        )
        for name in LaunchAccountFixture.hostAuth + LaunchAccountFixture.credentials
            + LaunchAccountFixture.tokens {
            #expect(reported[name] == "unset", "\(name) survived \(shell) under \(kind)")
        }
        #expect(reported["CLAUDE_CONFIG_DIR"] == (account?.directory.path ?? "unset"))
    }

    @Test func theSkillsDirectoryFollowsTheAccountTheProcessWillRunUnder() {
        let inherited = ["CODEX_HOME": "/inherited/codex"]
        #expect(AgentAccountEnvironment.codexHome(for: workCodex, inheriting: inherited) == workCodex.directory.path)
        #expect(AgentAccountEnvironment.codexHome(for: nil, inheriting: inherited) == "/inherited/codex")
        #expect(AgentAccountEnvironment.codexHome(for: nil, inheriting: [:]) == nil)
    }
}
