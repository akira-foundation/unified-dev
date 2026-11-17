import Testing
import Foundation
@testable import Core

@Suite struct BackendChangeTests {
    private func decide(
        from: AgentKind = .claudeCode, to: AgentKind = .codex, hasSpoken: Bool = false, terminal: Bool = false
    ) -> BackendChange {
        BackendChange.decide(from: from, to: to, hasSpoken: hasSpoken, isInteractiveTerminal: terminal)
    }

    @Test func spokenChatSwitchesInPlace() {
        #expect(decide(hasSpoken: true) == .switchInPlace(.codex))
        #expect(decide(from: .codex, to: .claudeCode, hasSpoken: true) == .switchInPlace(.claudeCode))
    }

    @Test func unspokenChatChangesInPlace() {
        #expect(decide() == .changeInPlace(.codex))
    }

    @Test func interactiveTerminalForks() {
        #expect(decide(hasSpoken: true, terminal: true) == .fork(.codex))
        #expect(decide(hasSpoken: false, terminal: true) == .fork(.codex))
    }

    @Test func choosingTheBackendItIsAlreadyOnDoesNothing() {
        #expect(decide(from: .codex, to: .codex, hasSpoken: true) == .unchanged)
        #expect(decide(from: .codex, to: .codex) == .unchanged)
        #expect(decide(from: .codex, to: .codex, hasSpoken: true, terminal: true) == .unchanged)
    }

    @Test func providerThatCannotRunWorkspacesIsUnchanged() {
        #expect(decide(to: .cursor) == .unchanged)
        #expect(decide(to: .openCode, hasSpoken: true) == .unchanged)
        #expect(decide(to: .openCode, hasSpoken: true, terminal: true) == .unchanged)
    }

    @Test func aChatWhoseHistoryHasNotBeenReadCountsAsHavingSpoken() {
        let hasSpoken = BackendChange.hasSpoken(rowCount: 0, agentSessionID: nil, isTranscriptLoaded: false)
        #expect(hasSpoken)
        #expect(decide(hasSpoken: hasSpoken) == .switchInPlace(.codex))
    }

    @Test func aThreadIdIsProofOnItsOwn() {
        #expect(BackendChange.hasSpoken(
            rowCount: 0, agentSessionID: "abc-123", isTranscriptLoaded: true
        ))
        #expect(!BackendChange.hasSpoken(rowCount: 0, agentSessionID: "", isTranscriptLoaded: true))
    }

    @Test func aRowOnScreenIsProofOnItsOwn() {
        #expect(BackendChange.hasSpoken(rowCount: 3, agentSessionID: nil, isTranscriptLoaded: true))
    }

    @Test func aReadAndEmptyChatHasNotSpoken() {
        let hasSpoken = BackendChange.hasSpoken(rowCount: 0, agentSessionID: nil, isTranscriptLoaded: true)
        #expect(!hasSpoken)
        #expect(decide(hasSpoken: hasSpoken) == .changeInPlace(.codex))
    }

    @Test func theInteractiveForkNoticeSaysWhyItIsANewChat() {
        let text = NoticeText(BackendChange.interactiveForkNotice(to: .codex))
        #expect(text.plain.contains("Codex"))
        #expect(text.plain.contains("terminal"))
        #expect(text.plain.contains("new chat"))
        #expect(!text.reason.isEmpty)
        #expect(!text.plain.contains("/"))
    }

    @Test func theNewChatActionNamesItsProvider() {
        #expect(BackendChange.newChatLabel(to: .codex) == "Open in a new chat with Codex")
    }

    @Test func aNewChatIsOfferedOnEveryOtherProviderThatCanRun() {
        let kinds = BackendChange.newChatProviders(from: .claudeCode, offered: [.claudeCode, .codex, .grok, .cursor])
        #expect(kinds == [.codex, .grok])
    }

    @Test func aNewChatOpensOnThatProvidersDefaultModel() throws {
        let models: [AgentKind: [AgentModel]] = [.codex: [
            AgentModel(id: "hidden", displayName: "Hidden", isDefault: true, hidden: true),
            AgentModel(id: "plain", displayName: "Plain"),
            AgentModel(id: "chosen", displayName: "Chosen", isDefault: true),
        ]]
        let controls = ComposerControls(model: "opus", effort: "high", agentKind: .claudeCode)

        let opening = try #require(BackendChange.newChatControls(from: controls, on: .codex, models: models))

        #expect(opening.agentKind == .codex)
        #expect(opening.model == "chosen")
        #expect(opening.effort == "")
    }

    @Test func aNewChatKeepsTheLevelWhenTheNewModelAnnouncesOne() throws {
        let models: [AgentKind: [AgentModel]] = [.codex: [
            AgentModel(
                id: "chosen", displayName: "Chosen", isDefault: true,
                supportedEfforts: [AgentModelEffort(id: "high", label: "High")], defaultEffort: "low"
            ),
        ]]
        let controls = ComposerControls(model: "opus", effort: "high", agentKind: .claudeCode)

        let opening = try #require(BackendChange.newChatControls(from: controls, on: .codex, models: models))

        #expect(opening.effort == "high")
    }

    @Test func aNewChatOnAProviderWithNoDefaultTakesItsFirstVisibleModel() throws {
        let models: [AgentKind: [AgentModel]] = [.codex: [
            AgentModel(id: "hidden", displayName: "Hidden", hidden: true),
            AgentModel(id: "plain", displayName: "Plain"),
        ]]
        let controls = ComposerControls(model: "opus", agentKind: .claudeCode)

        let opening = try #require(BackendChange.newChatControls(from: controls, on: .codex, models: models))

        #expect(opening.model == "plain")
    }

    @Test func aNewChatOnAProviderWithNothingReadTakesWhatThePickerOffers() throws {
        let controls = ComposerControls(model: "gpt-5", agentKind: .codex)

        let opening = try #require(BackendChange.newChatControls(
            from: controls, on: .claudeCode, models: [:], firstOffered: "opus"
        ))

        #expect(opening.agentKind == .claudeCode)
        #expect(opening.model == "opus")
    }

    @Test func aPickerOptionTaggedWithItsSectionIsStoredAsThePlainModel() throws {
        let controls = ComposerControls(model: "opus", agentKind: .claudeCode)

        let opening = try #require(BackendChange.newChatControls(
            from: controls, on: .antigravity, models: [:], firstOffered: "antigravity:claude-sonnet-4-6"
        ))

        #expect(opening.model == "claude-sonnet-4-6")
    }

    @Test func aNewChatOnAProviderWithNoModelsIsNotOffered() {
        let controls = ComposerControls(model: "opus", agentKind: .claudeCode)
        #expect(BackendChange.newChatControls(from: controls, on: .codex, models: [:]) == nil)
    }

    @Test func theForkNoticeNamesTheNewChatAndTheBackendThatStayed() {
        let message = BackendChange.forkNotice(title: "Fix the parser on Codex", from: .claudeCode)
        let text = NoticeText(message)
        #expect(text.plain.contains("Fix the parser on Codex"))
        #expect(text.plain.contains("Claude Code"))
        #expect(!text.reason.isEmpty)
        #expect(text.fact.contains { $0.isMachine && $0.text == "Fix the parser on Codex" })
    }

    @Test func aForkThatCouldNotBeMadeSaysSoRatherThanNothing() {
        let text = NoticeText(BackendChange.forkFailureNotice(to: .codex))
        #expect(text.plain.contains("Codex"))
        #expect(text.plain.contains("unchanged"))
    }

    @Test func aForkIsNamedSoTheStripCanTellThemApart() {
        #expect(BackendChange.forkedTitle("Fix the parser", to: .codex) == "Fix the parser on Codex")
        #expect(BackendChange.forkedTitle("", to: .codex) == "New session on Codex")
        #expect(BackendChange.forkedTitle("Fix the parser on Codex", to: .claudeCode)
            == "Fix the parser on Claude Code")
    }
}
