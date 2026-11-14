import Testing
import Foundation
import Synchronization
@testable import Core

@Suite("Every agent launch carries the account that was chosen", .scratchDirectory)
struct AgentLaunchAccountTests {
    private let workClaude = LaunchAccountFixture.workClaude
    private let workCodex = LaunchAccountFixture.workCodex
    private let workGrok = LaunchAccountFixture.workGrok

    @Test func theRunnerLaunchCarriesTheAccountDirectoryAndNoInheritedVariable() async throws {
        let (store, made) = try await LaunchAccountFixture.session(kind: .claudeCode)
        let runner = AgentRunner(
            workspacePath: "/tmp/w", session: made, store: store, segmentID: try await activeSegmentID(store, made),
            account: workClaude, inheritedEnvironment: LaunchAccountFixture.inherited
        )
        let launch = await runner.launch()
        #expect(launch.environment["CLAUDE_CONFIG_DIR"] == workClaude.directory.path)
        LaunchAccountFixture.expectClean(launch.environment)
    }

    @Test func theRunnerLaunchWithNoAccountStillStrips() async throws {
        let (store, made) = try await LaunchAccountFixture.session(kind: .claudeCode)
        let runner = AgentRunner(
            workspacePath: "/tmp/w", session: made, store: store, segmentID: try await activeSegmentID(store, made), inheritedEnvironment: LaunchAccountFixture.inherited
        )
        let launch = await runner.launch()
        #expect(launch.environment["CLAUDE_CONFIG_DIR"] == nil)
        LaunchAccountFixture.expectClean(launch.environment)
    }

    @Test func theQuotaAskLaunchCarriesTheSameAccountAsTheRunner() {
        let launch = ClaudeCodeQuotaSource.launch(account: workClaude, environment: LaunchAccountFixture.inherited)
        #expect(launch.environment["CLAUDE_CONFIG_DIR"] == workClaude.directory.path)
        LaunchAccountFixture.expectClean(launch.environment)
    }

    @Test func theClaudeQuotaSourceActuallyAsksUnderTheAccount() async {
        let log = LaunchLog()
        let source = ClaudeCodeQuotaSource(
            environment: LaunchAccountFixture.inherited,
            account: workClaude,
            makeProcess: log.factory,
            loginShellReady: {}
        )
        _ = await source.read()
        let launch = log.first
        #expect(launch?.environment["CLAUDE_CONFIG_DIR"] == workClaude.directory.path)
        LaunchAccountFixture.expectClean(launch?.environment ?? [:])
    }

    @Test func theClaudeQuotaCacheIsReadFromTheAccountThatWasAsked() async throws {
        let directory = URL(filePath: TestScratch.unique("quota-account"), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fetched = Date(timeIntervalSince1970: 1_790_859_223.675)
        let json = #"{"cachedUsageUtilization":{"fetchedAtMs":1790859223675,"utilization":{}}}"#
        try Data(json.utf8).write(to: directory.appending(path: ".claude.json"))
        let account = AgentAccountHome(
            provider: .claudeCode, id: AgentAccountID("work"), directory: directory, isDefault: false
        )
        let source = ClaudeCodeQuotaSource(
            account: account, clock: { fetched.addingTimeInterval(60) }, loginShellReady: {}
        )
        let standing = await source.standing()
        let reported = try #require(standing.lastReportedAt)
        #expect(abs(reported.timeIntervalSince(fetched)) < 0.01)
    }

    @Test func theCodexQuotaSourceActuallyAsksUnderTheAccount() async {
        let log = LaunchLog()
        let source = CodexQuotaSource(
            environment: LaunchAccountFixture.inherited, account: workCodex, makeProcess: log.factory, loginShellReady: {}
        )
        _ = await source.read()
        let launch = log.first
        #expect(launch?.environment["CODEX_HOME"] == workCodex.directory.path)
        LaunchAccountFixture.expectClean(launch?.environment ?? [:])
    }

    @Test func theCodexLaunchCarriesTheAccountHome() {
        let launch = CodexClient.launch(.init(cwd: "/w", account: workCodex, environment: LaunchAccountFixture.inherited))
        #expect(launch.environment["CODEX_HOME"] == workCodex.directory.path)
        LaunchAccountFixture.expectClean(launch.environment)
    }

    @Test func theGrokLaunchCarriesTheAccountHome() {
        let launch = GrokClient.launch(.init(cwd: "/w", account: workGrok, environment: LaunchAccountFixture.inherited))
        #expect(launch.environment["GROK_HOME"] == workGrok.directory.path)
        #expect(launch.environment["GROK_DISABLE_AUTOUPDATER"] == "1")
        LaunchAccountFixture.expectClean(launch.environment)
    }

    @Test func aCodexLaunchWithNoAccountStillStrips() {
        let launch = CodexClient.launch(.init(cwd: "/w", account: nil, environment: LaunchAccountFixture.inherited))
        #expect(launch.environment["CODEX_HOME"] == nil)
        LaunchAccountFixture.expectClean(launch.environment)
    }

    @Test func aGrokLaunchWithNoAccountStillStrips() {
        let launch = GrokClient.launch(.init(cwd: "/w", account: nil, environment: LaunchAccountFixture.inherited))
        #expect(launch.environment["GROK_HOME"] == nil)
        #expect(launch.environment["GROK_DISABLE_AUTOUPDATER"] == "1")
        LaunchAccountFixture.expectClean(launch.environment)
    }
}
