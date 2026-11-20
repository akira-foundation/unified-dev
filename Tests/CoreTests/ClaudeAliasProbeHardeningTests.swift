import Foundation
import Testing
@testable import Core

@Suite("What the alias probe refuses to run beside", .tags(.agentProtocol), .scratchDirectory)
struct ClaudeAliasProbeHardeningTests {
    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test("a managed MCP file beside the managed settings stops the probe before any launch")
    func managedMcpServersStopTheProbe() async throws {
        let servers = #"{"mcpServers":{"company":{"type":"stdio","command":"/usr/local/bin/company-mcp"}}}"#
        try write(servers, to: URL(filePath: TestScratch.path("managed/root/managed-mcp.json")))
        let launches = ProbeLaunches()

        let answers = await scriptedProbe(launches) { alias in [probeInitLine("claude-\(alias)-5-5")] }
            .resolve(["opus"], account: probeAccount())

        #expect(launches.launches.isEmpty)
        #expect(answers.all.isEmpty)
    }

    @Test("a managed MCP file counts in the settings fingerprint")
    func managedMcpServersChangeTheFingerprint() async throws {
        let probe = scriptedProbe(ProbeLaunches()) { _ in [] }
        let before = await probe.settingsFingerprint(["opus"], account: probeAccount())
        try write(#"{"mcpServers":{}}"#, to: URL(filePath: TestScratch.path("managed/root/managed-mcp.json")))

        let after = await probe.settingsFingerprint(["opus"], account: probeAccount())

        #expect(before.hasPrefix("managed=false;"))
        #expect(after.hasPrefix("managed=true;"))
    }

    @Test("a managed profile installed while the probe runs stops it before the next launch")
    func managedSettingsAppearingMidwayStopTheRest() async throws {
        let managedFile = URL(filePath: TestScratch.path("managed/root/managed-settings.json"))
        let launches = ProbeLaunches()
        let activity = ClaudeAccountActivity()
        let account = probeAccount()

        let answers = await scriptedProbe(launches, activity: activity) { alias in
            try? FileManager.default.createDirectory(at: managedFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? #"{"env":{"ANTHROPIC_BASE_URL":"https://gateway.example"}}"#.write(to: managedFile, atomically: true, encoding: .utf8)
            return [probeInitLine("claude-\(alias)-5-5")]
        }.resolve(["opus", "sonnet", "haiku"], account: account)
        let released = activity.beginProbe(ClaudeResolvedModel.accountID(account))

        #expect(launches.launches.map(probedAlias(of:)) == ["opus"])
        #expect(answers.probed == ["opus": "claude-opus-5-5"])
        #expect(released)
    }
}
