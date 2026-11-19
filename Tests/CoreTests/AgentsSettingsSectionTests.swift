import Testing
@testable import Core

@Suite("Agents settings sections")
struct AgentsSettingsSectionTests {
    @Test(arguments: AgentKind.allCases)
    func theAccountsComeRightAfterTheAgentsOwnCard(agent: AgentKind) {
        let order = AgentsSettingsSection.order(for: agent, connection: .connected)
        let accounts = order.firstIndex(of: .accounts)
        let beforeAccounts = order.prefix { $0 != .accounts }

        #expect(accounts != nil)
        #expect(beforeAccounts.allSatisfy { $0 == .status || $0 == .capability })
    }

    @Test func claudeCodesChromeSwitchComesAfterItsAccounts() throws {
        let order = AgentsSettingsSection.order(for: .claudeCode, connection: .connected)

        #expect(order == [.status, .accounts, .chrome, .gitHub, .advanced])
    }

    @Test func onlyClaudeCodeHasTheChromeSwitch() {
        let others = AgentKind.allCases.filter { $0 != .claudeCode }

        #expect(others.allSatisfy { !AgentsSettingsSection.order(for: $0, connection: .connected).contains(.chrome) })
    }

    @Test func anAgentThatCannotRunWorkspacesSaysSoBeforeItsAccounts() throws {
        let agent = try #require(AgentKind.allCases.first { !$0.canRunWorkspaces })

        #expect(AgentsSettingsSection.order(for: agent, connection: .connected).prefix(3) == [.status, .capability, .accounts])
    }

    @Test func anAgentThatIsNotInstalledSaysSoAfterItsAccounts() {
        let order = AgentsSettingsSection.order(for: .codex, connection: .notInstalled)

        #expect(order == [.status, .accounts, .notInstalled, .gitHub, .advanced])
    }
}
