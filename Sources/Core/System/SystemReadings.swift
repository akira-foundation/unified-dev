import Foundation

public enum SystemReadings {
    public enum Theme: String, Sendable, Equatable, CaseIterable, Codable {
        case system
        case light
        case dark

        public static let defaultsKey = "appearance"

        public init(defaultsValue: String?) {
            self = Theme(rawValue: defaultsValue ?? "") ?? .system
        }

        public init(in defaults: UserDefaults = .standard) {
            self.init(defaultsValue: defaults.string(forKey: Theme.defaultsKey))
        }
    }

    public static func wireName(_ kind: AgentKind) -> String {
        switch kind {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .grok: "grok"
        case .antigravity: "antigravity"
        case .cursor: "cursor"
        case .openCode: "opencode"
        }
    }

    public static let noAgent = "none"

    public static func agentName(installed: [AgentKind]) -> String {
        let runnable = AgentKind.allCases.filter { $0.canRunWorkspaces && installed.contains($0) }
        guard !runnable.isEmpty else { return noAgent }
        return runnable.map(wireName).joined(separator: "_")
    }

    public static func macOSVersion(major: Int, minor: Int, patch: Int) -> String {
        let clamped = [major, minor, patch].map { min(max($0, 0), 999) }
        return clamped.map(String.init).joined(separator: ".")
    }

    public static let appVersionPattern = #"^\d{1,4}(\.\d{1,4}){0,3}(-[A-Za-z0-9.]{1,16})?$"#

    public static let systemVersionPattern = #"^\d{1,3}(\.\d{1,3}){0,2}$"#

    public static let unknownVersion = "0.0.0"

    static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    static func checked(_ raw: String, _ pattern: String, or fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return matches(trimmed, pattern) ? trimmed : fallback
    }
}
