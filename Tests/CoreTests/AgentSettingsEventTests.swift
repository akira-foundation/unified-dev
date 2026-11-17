import Testing
@testable import Core

@Suite("What closes the composer's agent settings")
struct AgentSettingsEventTests {
    @Test func sendingAMessageClosesThem() {
        #expect(AgentSettingsEvent.sentMessage.closesSettings)
    }

    @Test func leavingForAnotherPlaceClosesThem() {
        #expect(AgentSettingsEvent.savedPreset.closesSettings)
        #expect(AgentSettingsEvent.changedAccount.closesSettings)
        #expect(AgentSettingsEvent.openedInNewChat.closesSettings)
    }

    @Test func choosingASettingKeepsThemOpenForTheNextChoice() {
        #expect(!AgentSettingsEvent.changedSetting.closesSettings)
    }

    @Test func onlyChoosingASettingKeepsThemOpen() {
        let staying = AgentSettingsEvent.allCases.filter { !$0.closesSettings }
        #expect(staying == [.changedSetting])
    }
}
