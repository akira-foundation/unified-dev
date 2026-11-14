import Foundation
import Testing
@testable import Core

@Suite("The models a shipped scenario pins")
struct PreviewScenarioModelTests {
    private func shipped() throws -> [(name: String, scenario: PreviewScenario)] {
        try FileManager.default
            .contentsOfDirectory(atPath: TestScenarios.repositoryRoot + "/Tools/scenarios")
            .filter { $0.hasSuffix(".json") }
            .sorted()
            .map { name in
                let name = String(name.dropLast(".json".count))
                return (name, try TestScenarios.shipped(name))
            }
    }

    @Test("a project's default model is read from the settings file the scenario seeds")
    func readsThePin() {
        let scenario = PreviewScenario(welcome: false, projects: [
            PreviewScenario.Project(
                name: "tidewater",
                files: [PreviewScenario.projectSettingsFile: "[models]\ndefault = \"codex:gpt-5.6-sol\"\n"]
            ),
            PreviewScenario.Project(name: "quay"),
        ])

        #expect(scenario.modelPins == [PreviewScenarioModelPin(project: "tidewater", model: "codex:gpt-5.6-sol")])
        #expect(scenario.modelPins.first?.kind == .codex)
    }

    @Test("every Codex model a shipped scenario pins is the one model the scenarios agree on")
    func everyCodexPinIsTheSame() throws {
        var codexPins = 0
        for (name, scenario) in try shipped() {
            for pin in scenario.modelPins where pin.kind == .codex {
                codexPins += 1
                #expect(
                    ModelIdentifier.resolve(pin.model).model == TestScenarios.codexModel,
                    "\(name): \(pin.project) pins \(pin.model)"
                )
            }
        }
        #expect(codexPins >= 2)
    }

    @Test("the composer defaults scenario puts tidewater on Codex")
    func composerDefaultsIsOnCodex() throws {
        let pins = try TestScenarios.shipped("composer-defaults").modelPins
        #expect(pins.first { $0.project == "tidewater" }?.kind == .codex)
    }
}

private let localAgentsEnabled = ProcessInfo.processInfo.environment["UD_LOCAL_AGENTS"] == "1"

@Suite("The scenarios' Codex model on this Mac", .enabled(if: localAgentsEnabled), .tags(.subprocess))
struct PreviewScenarioModelLocalTests {
    @Test("the Codex CLI here lists the model the scenarios pin")
    func theCLIListsIt() async throws {
        let client = CodexClient(configuration: .init(cwd: NSTemporaryDirectory()))
        try await client.start()
        let listed = try await client.listModels(includeHidden: true).map(\.id)
        await client.stop()

        #expect(listed.contains(TestScenarios.codexModel), "the Codex CLI lists \(listed)")
    }
}
