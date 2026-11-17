import Foundation

public enum ClaudeChrome {
    public static let settingKey = "agent.claudeCode.chrome"
    public static let serverName = "claude-in-chrome"
    public static let flag = "--chrome"

    public static func isEnabled(_ stored: String?) -> Bool {
        stored == "1"
    }

    public static func storedValue(_ enabled: Bool) -> String? {
        enabled ? "1" : nil
    }

    public static func isEnabled(in store: Store?) async -> Bool {
        guard let store else { return false }
        return isEnabled(try? await store.setting(settingKey))
    }

    public static func launches(in store: Store?, orchestrates: Bool) async -> Bool {
        guard !orchestrates else { return false }
        return await isEnabled(in: store)
    }
}

public struct ClaudeChromeNotice: Sendable, Hashable {
    static let type = "claude_in_chrome_missing"
    static let stillLoading: Set<String> = ["connected", "pending"]

    public let status: String?

    public static func missing(requested: Bool, initEvent: Data) -> ClaudeChromeNotice? {
        guard requested else { return nil }
        let servers = JSONValue.parse(initEvent)?["mcp_servers"]?.arrayValue ?? []
        guard let server = servers.first(where: { $0["name"]?.stringValue == ClaudeChrome.serverName }) else {
            return ClaudeChromeNotice(status: nil)
        }
        let status = server["status"]?.stringValue ?? ""
        guard !stillLoading.contains(status) else { return nil }
        return ClaudeChromeNotice(status: status.isEmpty ? "unknown" : status)
    }

    public var payload: Data {
        var object: [String: JSONValue] = ["type": .string(Self.type)]
        if let status { object["status"] = .string(status) }
        return (try? JSONEncoder().encode(JSONValue.object(object))) ?? Data()
    }

    public static func decode(_ payload: Data) -> ClaudeChromeNotice? {
        guard let json = JSONValue.parse(payload), json["type"]?.stringValue == type else { return nil }
        return ClaudeChromeNotice(status: json["status"]?.stringValue)
    }

    public var sentence: String {
        guard let status else {
            return "Claude Code started without Claude in Chrome. It needs the Claude extension in Chrome "
                + "and a claude.ai sign in rather than an API key."
        }
        return "Claude in Chrome did not connect (\(status)). Open Chrome and check the Claude extension is signed in."
    }
}
