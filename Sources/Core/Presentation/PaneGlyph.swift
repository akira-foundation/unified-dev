public enum PaneGlyph {
    public static let chat = "text.bubble"
    public static let terminal = "apple.terminal"
    public static let browser = "globe"
    public static let review = "doc.text"
    public static let notes = "note.text"
    public static let canvas = "doc.richtext"

    public static func chatTab(agentMark: String?) -> String {
        agentMark ?? chat
    }

    public static func marksAgents(_ kinds: some Sequence<AgentKind>) -> Bool {
        Set(kinds).count > 1
    }

    public static func agentMark(for kind: AgentKind, among kinds: some Sequence<AgentKind>) -> String? {
        guard marksAgents(kinds) else { return nil }
        return agentMark(for: kind)
    }

    public static func agentMark(for kind: AgentKind) -> String {
        switch kind {
        case .claudeCode: "asterisk"
        case .codex: "circle.hexagongrid"
        case .grok: "sparkles"
        case .antigravity: "atom"
        case .cursor: "cursorarrow"
        case .openCode: "chevron.left.forwardslash.chevron.right"
        }
    }
}
