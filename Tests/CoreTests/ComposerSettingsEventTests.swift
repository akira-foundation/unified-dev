import Testing
@testable import Core

@Suite("What closes the composer's agent settings")
struct ComposerSettingsEventTests {
    @Test func sendingAMessageClosesThem() {
        #expect(ComposerSettingsEvent.pressedSend(canSend: true).closesSettings)
    }

    @Test func pressingSendWithNothingToSendLeavesThemOpen() {
        #expect(!ComposerSettingsEvent.pressedSend(canSend: false).closesSettings)
    }

    @Test func aQuickPromptClosesThemOnlyWhenItSends() {
        #expect(ComposerSettingsEvent.firedQuickPrompt(.send).closesSettings)
        #expect(ComposerSettingsEvent.firedQuickPrompt(.sendInNewChat).closesSettings)
        #expect(!ComposerSettingsEvent.firedQuickPrompt(.compose).closesSettings)
        #expect(!ComposerSettingsEvent.firedQuickPrompt(.composeInNewChat).closesSettings)
    }

    @Test func aSendCountsAsARequestToClose() {
        var requests = ComposerSettingsCloseRequests()
        requests.note(.pressedSend(canSend: true))
        requests.note(.firedQuickPrompt(.send))
        #expect(requests.count == 2)
    }

    @Test func aRefusedSendOrAComposedPromptIsNotARequest() {
        var requests = ComposerSettingsCloseRequests()
        requests.note(.pressedSend(canSend: false))
        requests.note(.firedQuickPrompt(.compose))
        #expect(requests == ComposerSettingsCloseRequests())
    }
}
