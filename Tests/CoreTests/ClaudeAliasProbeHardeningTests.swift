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

    @Test("no inherited telemetry exporter or gRPC proxy reaches the CLI, and telemetry is switched off")
    func carriesNoTelemetry() async throws {
        let launches = ProbeLaunches()
        let inherited = [
            "OTEL_EXPORTER_OTLP_ENDPOINT": "https://collector.example:4317",
            "OTEL_METRICS_EXPORTER": "otlp",
            "OTEL_LOGS_EXPORTER": "otlp",
            "grpc_proxy": "http://proxy.example:8080",
            "GRPC_PROXY": "http://proxy.example:8080",
            "no_grpc_proxy": "collector.example",
            "NO_GRPC_PROXY": "collector.example",
            "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
            "DISABLE_TELEMETRY": "0",
            "DISABLE_ERROR_REPORTING": "0",
            "PATH": "/usr/bin",
        ]
        _ = await scriptedProbe(launches, inherited: inherited) { _ in [probeInitLine("claude-opus-5-5")] }
            .resolve(["opus"], account: probeAccount())
        let launch = try #require(launches.launches.first)
        let launched = launch.environment
        let index = try #require(launch.arguments.firstIndex(of: "--settings"))
        let env = try #require(JSONValue.parse(launch.arguments[index + 1])?["env"])

        #expect(launched.keys.filter { $0.hasPrefix("OTEL_") }.isEmpty)
        for variable in ["grpc_proxy", "GRPC_PROXY", "no_grpc_proxy", "NO_GRPC_PROXY"] {
            #expect(launched[variable] == nil)
        }
        for (variable, value) in ["CLAUDE_CODE_ENABLE_TELEMETRY": "0", "DISABLE_TELEMETRY": "1", "DISABLE_ERROR_REPORTING": "1"] {
            #expect(launched[variable] == value)
            #expect(env[variable]?.stringValue == value)
        }
        #expect(launched["PATH"] == "/usr/bin")
    }
}
