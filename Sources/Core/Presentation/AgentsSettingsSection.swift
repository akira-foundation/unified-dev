import Foundation

public enum AgentsSettingsSection: Sendable, Hashable {
    case status
    case capability
    case accounts
    case chrome
    case notInstalled
    case gitHub
    case advanced

    public static func order(for agent: AgentKind, connection: AgentStatus.Connection) -> [AgentsSettingsSection] {
        var sections: [AgentsSettingsSection] = [.status]
        if !agent.canRunWorkspaces { sections.append(.capability) }
        if connection == .notInstalled { sections.append(.notInstalled) }
        sections.append(.accounts)
        if agent == .claudeCode { sections.append(.chrome) }
        return sections + [.gitHub, .advanced]
    }
}
