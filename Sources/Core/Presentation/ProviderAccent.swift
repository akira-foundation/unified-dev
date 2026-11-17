import Foundation

public enum ProviderAccent {
    public static func hex(for provider: AgentKind) -> String {
        switch provider {
        case .claudeCode: Accent.all[2]
        case .codex: Accent.all[1]
        case .grok: Accent.all[7]
        case .antigravity: Accent.all[0]
        case .cursor: Accent.all[3]
        case .openCode: Accent.all[8]
        }
    }
}
