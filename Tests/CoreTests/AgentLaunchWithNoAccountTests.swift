import Testing
import Foundation
@testable import Core

@Suite("A launch with no account runs under the CLI's own directory, not the one the app inherited", .scratchDirectory)
struct AgentLaunchWithNoAccountTests {
    private static let inherited = [
        "PATH": "/usr/bin:/bin",
        "CLAUDE_CONFIG_DIR": "/inherited/claude",
        "CODEX_HOME": "/inherited/codex",
        "GROK_HOME": "/inherited/grok",
    ]

    @Test func aHeadlessClaudeTurnUnsetsTheInheritedConfigDirectory() async throws {
        let (store, made) = try await LaunchAccountFixture.session(kind: .claudeCode)
        let runner = AgentRunner(
            workspacePath: "/tmp/w", session: made, store: store, segmentID: try await activeSegmentID(store, made),
            inheritedEnvironment: Self.inherited
        )
        let environment = await runner.launch().environment
        #expect(environment["CLAUDE_CONFIG_DIR"] == nil)
        #expect(environment["CODEX_HOME"] == "/inherited/codex")
    }

    @Test func aCodexTurnUnsetsTheInheritedHome() {
        let environment = CodexClient.launch(CodexClient.Configuration(cwd: "/tmp/w", environment: Self.inherited))
            .environment
        #expect(environment["CODEX_HOME"] == nil)
        #expect(environment["CLAUDE_CONFIG_DIR"] == "/inherited/claude")
    }

    @Test func anACPTurnUnsetsTheInheritedHomeOfItsOwnProviderOnly() {
        let grok = ACPClient.launch(ACPClient.Configuration(
            dialect: .grok, executable: "grok", cwd: "/tmp/w", environment: Self.inherited
        )).environment
        let antigravity = ACPClient.launch(ACPClient.Configuration(
            dialect: .antigravity, executable: "agy", cwd: "/tmp/w", environment: Self.inherited
        )).environment
        #expect(grok["GROK_HOME"] == nil)
        #expect(grok["CODEX_HOME"] == "/inherited/codex")
        #expect(antigravity["GROK_HOME"] == "/inherited/grok")
    }

    @Test func theNamerUnsetsTheInheritedConfigDirectory() {
        let environment = WorkspaceNamer.launch(prompt: "name this", environment: Self.inherited).environment
        #expect(environment["CLAUDE_CONFIG_DIR"] == nil)
    }

    @Test func theQuotaAskUnsetsTheInheritedConfigDirectory() {
        let environment = ClaudeCodeQuotaSource.launch(account: nil, environment: Self.inherited).environment
        #expect(environment["CLAUDE_CONFIG_DIR"] == nil)
    }

    @Test func theSlashCommandCatalogueReadsNoInheritedCodexHome() {
        #expect(AgentAccountEnvironment.codexHome(for: nil, inheriting: Self.inherited) == nil)
    }

    @Test func theAliasProbeReadsItsPinsFromAndProbesUnderTheCliOwnDirectory() async throws {
        let userHome = URL(filePath: TestScratch.path("user"), directoryHint: .isDirectory)
        let elsewhere = URL(filePath: TestScratch.path("elsewhere"), directoryHint: .isDirectory)
        try pin("opus", to: "claude-opus-own", in: userHome.appending(path: ".claude"))
        try pin("opus", to: "claude-opus-elsewhere", in: elsewhere)
        let launches = ProbeLaunches()
        let probe = ClaudeAliasProbe(
            executable: "claude", workRoot: probeWorkRoot(),
            environment: ["PATH": "/usr/bin:/bin", "CLAUDE_CONFIG_DIR": elsewhere.path],
            timeout: .seconds(5), exitGrace: .milliseconds(100), managed: unmanaged(),
            activity: ClaudeAccountActivity(),
            makeProcess: { launch in
                let process = ScriptedProbe(printing: [probeInitLine("claude-sonnet-5-5")], ignoresTerminate: false)
                launches.record(launch, process)
                return process
            },
            userHome: userHome
        )

        let answers = await probe.resolve(["opus", "sonnet"], account: nil)

        #expect(answers.pinned == ["opus": "claude-opus-own"])
        #expect(launches.launches.count == 1)
        #expect(launches.launches.allSatisfy { $0.environment["CLAUDE_CONFIG_DIR"] == nil })
    }

    @Test func theAliasFingerprintReadsTheCliOwnDirectory() async throws {
        let userHome = URL(filePath: TestScratch.path("user"), directoryHint: .isDirectory)
        let elsewhere = URL(filePath: TestScratch.path("elsewhere"), directoryHint: .isDirectory)
        try pin("opus", to: "claude-opus-own", in: userHome.appending(path: ".claude"))
        try pin("opus", to: "claude-opus-elsewhere", in: elsewhere)
        let probe = ClaudeAliasProbe(
            executable: "claude", workRoot: probeWorkRoot(),
            environment: ["PATH": "/usr/bin:/bin", "CLAUDE_CONFIG_DIR": elsewhere.path],
            managed: unmanaged(), activity: ClaudeAccountActivity(), userHome: userHome
        )

        let fingerprint = await probe.settingsFingerprint(["opus"], account: nil)

        #expect(fingerprint == "managed=false;opus=claude-opus-own")
    }

    private func pin(_ alias: String, to model: String, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settings = try JSONSerialization.data(withJSONObject: ["env": [ClaudeAliasPins.variable(for: alias): model]])
        try settings.write(to: directory.appending(path: "settings.json"))
    }
}
