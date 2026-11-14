import Testing
import Foundation
@testable import Core

private func configuration(alwaysApprove: Bool = false, asksEveryCall: Bool = false) -> ACPClient.Configuration {
    ACPClient.Configuration(
        dialect: .antigravity,
        executable: "agy",
        cwd: "/tmp/w",
        environment: [:],
        model: "gemini-3.8-flash-low",
        effort: "high",
        alwaysApprove: alwaysApprove,
        asksEveryCall: asksEveryCall
    )
}

private func sent(_ method: String, in box: ProcessBox) -> [JSONValue] {
    box.process.stdin.compactMap(JSONValue.parse).filter { $0["method"]?.stringValue == method }
}

@Suite("Antigravity dialect")
struct AntigravityDialectTests {
    @Test("Antigravity starts as agy acp, with no model flag and the updater quiet")
    func launchShape() {
        let launch = ACPClient.launch(configuration())
        #expect(launch.executable == "agy")
        #expect(launch.arguments == ["acp"])
        #expect(launch.environment["AGY_CLI_DISABLE_AUTO_UPDATE"] == "true")
    }

    @Test("bypass skips Antigravity's own permission prompts")
    func bypassArgument() {
        #expect(ACPClient.launch(configuration(alwaysApprove: true)).arguments == ["acp", "--dangerously-skip-permissions"])
    }

    @Test("Grok keeps its own launch")
    func grokUnchanged() {
        let arguments = ACPDialect.grok.arguments(model: "grok-4.6", effort: "high", alwaysApprove: true)
        #expect(arguments == ["agent", "--always-approve", "--model", "grok-4.6", "--reasoning-effort", "high", "--no-leader", "stdio"])
    }

    @Test("a config value is a plain string for Antigravity and wrapped for Grok")
    func configValueShapes() {
        #expect(ACPDialect.antigravity.configValue("auto") == .string("auto"))
        #expect(ACPDialect.grok.configValue("auto") == .object(["value": .string("auto")]))
    }

    @Test("permission modes map onto Antigravity's four modes, and an orchestrator is always asked")
    func modes() {
        let dialect = ACPDialect.antigravity
        #expect(dialect.mode(for: .acceptEdits, asksEveryCall: false) == "accept-edits")
        #expect(dialect.mode(for: .auto, asksEveryCall: false) == "auto")
        #expect(dialect.mode(for: .plan, asksEveryCall: false) == "plan")
        #expect(dialect.mode(for: .bypassPermissions, asksEveryCall: true) == "default")
        #expect(ACPDialect.grok.mode(for: .plan, asksEveryCall: false) == nil)
    }

    @Test("session/new carries no Grok _meta and set_config_option sends a plain string")
    func wireShapes() async throws {
        let box = ProcessBox()
        box.reply(to: "initialize", with: .object([:]))
        box.reply(to: "session/new", with: try #require(JSONValue.parse(Data(AntigravityWire.sessionNew.utf8)))["result"] ?? .null)
        box.reply(to: "session/set_config_option", with: .object([:]))
        let client = ACPClient(configuration: configuration(), makeProcess: box.factory)
        try await client.start()
        let session = try await client.newSession(cwd: "/tmp/w", permissionMode: .auto)
        try await client.setConfigOption(sessionID: session.id, configID: "model", value: "gemini-3.8-flash-low")
        #expect(session.id == "5361ec1e-4050-4bbc-91d8-f391b7a4c45b")
        #expect(session.currentModelID == "gemini-3.8-flash-high")
        #expect(sent("session/new", in: box).first?["params"]?["_meta"] == nil)
        #expect(sent("session/set_config_option", in: box).first?["params"]?["value"] == .string("gemini-3.8-flash-low"))
        await client.stop()
    }
}

@Suite("Antigravity model list")
struct AntigravityModelListTests {
    @Test("agy models is read as folded ids, the first being the session default")
    func parsesMeasuredOutput() {
        let models = AntigravityModelList.parse(AntigravityWire.modelsStdout)
        #expect(models.map(\.id) == [
            "gemini-3.8-flash-high", "gemini-3.8-flash-medium", "gemini-3.8-flash-low",
            "claude-sonnet-4-6", "claude-opus-4-6-thinking", "gpt-oss-120b-medium",
        ])
        #expect(models.first?.isDefault == true)
        #expect(models.dropFirst().allSatisfy { !$0.isDefault })
        #expect(models[3].displayName == "Claude Sonnet 4.6 (Thinking)")
        #expect(models.allSatisfy { $0.supportedEfforts.isEmpty })
    }

    @Test("a signed out agy reads as signed out, and shows no account")
    func signedOut() {
        let reading = AntigravityModelList.read(ShellResult(status: 1, stdout: "", stderr: AntigravityWire.modelsSignedOutStderr))
        #expect(reading == .signedOut)
        #expect(AgentCatalog.antigravityDetails(reading: reading, version: "1.5.9").isEmpty)
    }

    @Test("a model list proves a sign in")
    func signedIn() {
        let reading = AntigravityModelList.read(ShellResult(status: 0, stdout: AntigravityWire.modelsStdout, stderr: ""))
        let details = AgentCatalog.antigravityDetails(reading: reading, version: "1.5.9")
        #expect(details.first { $0.label == "Version" }?.value == "1.5.9")
        #expect(details.first { $0.label == "Provider" }?.value == "Google")
    }

    @Test("Antigravity's Claude models do not take a bare Claude id away from Claude Code")
    func claudeIDsStayWithClaude() {
        let models: [AgentKind: [AgentModel]] = [.antigravity: AntigravityModelList.parse(AntigravityWire.modelsStdout)]
        #expect(ModelIdentifier.resolve("claude-sonnet-4-6", models: models).kind == .claudeCode)
        #expect(ModelIdentifier.resolve("gemini-3.8-flash-high", models: models).kind == .antigravity)
        #expect(ModelIdentifier.resolve("antigravity:claude-sonnet-4-6", models: models).kind == .antigravity)
    }

    @Test("Antigravity is offered wherever an agent is chosen")
    func offered() {
        #expect(AgentKind.antigravity.canRunWorkspaces)
        #expect(AgentKind.runnable.contains(.antigravity))
        #expect(SetupTool.displayOrder.contains(.antigravity))
        #expect(SetupTool.antigravity.agentKind == .antigravity)
        #expect(AgentModelSource.followsExecutablePath(.antigravity))
        #expect(!AgentKind.antigravity.announcesModelEfforts)
    }
}
