import Foundation

public enum WorkspaceStartMode: String, Sendable {
    case chat
    case claudeCLI
    case codexCLI
    case terminal

    public static func chat(usesCLI: Bool, agent: AgentKind) -> Self {
        guard usesCLI else { return .chat }
        switch agent {
        case .claudeCode: return .claudeCLI
        case .codex: return .codexCLI
        case .cursor, .openCode, .grok, .antigravity: return .chat
        }
    }

    public var runsAnAgent: Bool { self == .chat || cliAgentKind != nil }

    public var cliAgentKind: AgentKind? {
        switch self {
        case .claudeCLI: .claudeCode
        case .codexCLI: .codex
        case .chat, .terminal: nil
        }
    }

    public var pane: PaneKind {
        switch self {
        case .chat, .claudeCLI, .codexCLI: .chat
        case .terminal: .terminal
        }
    }

    public static func defaultsKey(workspaceID: WorkspaceID) -> String {
        "workspace.opensOn.\(workspaceID)"
    }

    static func legacyTerminalKey(workspaceID: WorkspaceID) -> String {
        "workspace.opensOnTerminal.\(workspaceID)"
    }

    public static func record(
        _ mode: WorkspaceStartMode, workspaceID: WorkspaceID, defaults: UserDefaults = .standard
    ) {
        guard mode != .chat else { return }
        defaults.set(mode.rawValue, forKey: defaultsKey(workspaceID: workspaceID))
    }

    public static func consumeOpeningTab(
        workspaceID: WorkspaceID, defaults: UserDefaults = .standard
    ) -> WorkspaceStartMode? {
        let key = defaultsKey(workspaceID: workspaceID)
        if let raw = defaults.string(forKey: key) {
            defaults.removeObject(forKey: key)
            let recorded = WorkspaceStartMode(rawValue: raw)
            return recorded == .chat ? nil : recorded
        }
        let legacy = legacyTerminalKey(workspaceID: workspaceID)
        guard defaults.bool(forKey: legacy) else { return nil }
        defaults.removeObject(forKey: legacy)
        return .terminal
    }
}
