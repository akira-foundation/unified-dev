import Testing
@testable import Core

struct AgentModelSourceTests {
    private let source = AgentModelSource(models: { [] }, invalidate: {})
    private let model = AgentModel(id: "grok-test", displayName: "Test")

    @Test("an agent whose models never arrived is asked again")
    func askAgainWhenNeverLoaded() {
        let awaiting = AgentModelSource.kindsAwaitingModels(
            sources: [.claudeCode: source, .grok: source],
            loaded: [.claudeCode: [model]]
        )
        #expect(awaiting == [.grok])
    }

    @Test("an agent that answered with an empty list is asked again")
    func askAgainWhenEmpty() {
        let awaiting = AgentModelSource.kindsAwaitingModels(
            sources: [.grok: source],
            loaded: [.grok: []]
        )
        #expect(awaiting == [.grok])
    }

    @Test("an agent that already has models is not asked again")
    func leaveLoadedAlone() {
        let awaiting = AgentModelSource.kindsAwaitingModels(
            sources: [.claudeCode: source, .codex: source, .grok: source],
            loaded: [.claudeCode: [model], .codex: [model], .grok: [model]]
        )
        #expect(awaiting.isEmpty)
    }

    @Test("an agent with no source, or one that cannot run a workspace, is not asked")
    func skipWhatCannotAnswer() {
        let awaiting = AgentModelSource.kindsAwaitingModels(
            sources: [.cursor: source, .openCode: source],
            loaded: [:]
        )
        #expect(awaiting.isEmpty)
    }

    @Test("agents are asked in the order the runnable list gives them")
    func keepRunnableOrder() {
        let awaiting = AgentModelSource.kindsAwaitingModels(
            sources: [.antigravity: source, .grok: source, .codex: source, .claudeCode: source],
            loaded: [:]
        )
        #expect(awaiting == AgentKind.runnable)
    }
}
