import Testing
@testable import Core

@Suite("Model section tags")
struct ModelSectionTagTests {
    private let models: [AgentKind: [AgentModel]] = [
        .antigravity: AntigravityModelList.parse(AntigravityWire.modelsStdout),
    ]

    @Test("a Claude model in the Antigravity section moves a Claude Code chat to Antigravity")
    func antigravitySectionWinsFromClaude() {
        let tag = ModelSectionTag.tag("claude-opus-4-6-thinking", in: .antigravity, running: .claudeCode, models: models)
        #expect(tag == "antigravity:claude-opus-4-6-thinking")
        let chosen = ModelSectionTag.choice(tag, running: .claudeCode, models: models)
        #expect(chosen.kind == .antigravity)
        #expect(chosen.model == "claude-opus-4-6-thinking")
    }

    @Test("a model in the Claude Code section moves an Antigravity chat to Claude Code")
    func claudeSectionWinsFromAntigravity() {
        let tag = ModelSectionTag.tag("claude-sonnet-4-6", in: .claudeCode, running: .antigravity, models: models)
        let chosen = ModelSectionTag.choice(tag, running: .antigravity, models: models)
        #expect(chosen.kind == .claudeCode)
        #expect(chosen.model == "claude-sonnet-4-6")
    }

    @Test("a model the running agent owns keeps its plain id, so the picker still shows it selected")
    func runningSectionStaysPlain() {
        #expect(ModelSectionTag.tag("claude-sonnet-4-6", in: .antigravity, running: .antigravity, models: models) == "claude-sonnet-4-6")
        #expect(ModelSectionTag.tag("gemini-3.8-flash-low", in: .antigravity, running: .claudeCode, models: models) == "gemini-3.8-flash-low")
        #expect(ModelSectionTag.tag("opus", in: .claudeCode, running: .claudeCode, models: models) == "opus")
    }
}
