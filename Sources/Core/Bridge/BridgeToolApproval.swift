import Foundation

public enum BridgeToolApproval {
    public static var toolPrefix: String { "mcp__\(BridgeRegistration.serverName)__" }

    public static let selfApproved: Set<String> = [
        "whoami",
        "workspace_start",
        "pane_open",
        "pane_split",
        "pane_close",
        "pane_rename",
        "workspace_rename",
        "project_list",
        "quick_prompt_list",
        "pane_list",
        "browser_read",
        "agent_start",
        "agent_say",
        "agent_list",
        "agent_stop",
        "media_show",
        "canvas_show",
        "canvas_read",
        "canvas_edit",
        "canvas_render",
        "canvas_comment_resolve",
        "workspace_tabs",
        "chat_list",
        "chat_read",
        "workspace_diff",
        "workspace_tab_select",
        "reveal",
        "workspace_say",
        "work_suggest",
        "work_withdraw",
    ]

    public static func isSelfApproved(toolName: String) -> Bool {
        guard toolName.hasPrefix(toolPrefix) else { return false }
        return selfApproved.contains(String(toolName.dropFirst(toolPrefix.count)))
    }

    public static func isSelfApproved(toolName: String, input: JSONValue, inWorkspace: Bool) -> Bool {
        guard inWorkspace else { return isSelfApproved(toolName: toolName) }
        guard !namesProfile(input) else { return false }
        return isSelfApproved(toolName: toolName) || toolName == toolPrefix + "workspace_list"
    }

    public static let crossingTools = [
        "project_list", "workspace_list", "workspace_say", "chat_list", "chat_read", "workspace_diff",
    ]

    public static var claudeCrossingPermissions: [String: [String]] {
        ["ask": crossingTools.map { toolPrefix + $0 }]
    }

    public static func crossesProfile(toolName: String, input: JSONValue) -> Bool {
        toolName.hasPrefix(toolPrefix) && namesProfile(input)
    }

    private static func namesProfile(_ input: JSONValue) -> Bool {
        guard let given = input[BridgeProfileReach.argument], given != .null else { return false }
        guard let text = given.stringValue else { return true }
        return AgentStartTool.text(text) != nil
    }
}
