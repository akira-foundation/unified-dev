import Foundation

public enum OrchestratorToolGuard {
    static let readingTools: Set<String> = [
        "Read", "Grep", "Glob", "LS", "WebSearch", "WebFetch", "TodoWrite", "Task", "Agent", "SubAgent",
        "ExitPlanMode", "EnterPlanMode", "Plan", "BashOutput", "KillShell", "ToolSearch", "Skill",
        AgentQuestionnaire.toolName, "UserInput", "McpElicitation",
    ]

    static let shellTools: Set<String> = ["Bash", "Shell"]

    private static let directoryKeys = ["cwd", "workdir", "working_directory", "directory"]

    static let refusedBridgeTools: [String: String] = [
        "terminal_start": "driving a terminal",
        "terminal_write": "driving a terminal",
        "terminal_send_key": "driving a terminal",
        "canvas_edit": "changing a canvas file",
    ]

    public static let claudeAskingMode = "default"

    public static let claudeAskingLabel = "Default"

    public static let claudeAskingSummary =
        "Claude asks before anything Unified Dev cannot check for itself. This chat is the project's "
        + "orchestrator, so file edits and git changes are refused in every mode."

    public static let claudePermissions: [String: [String]] = ["ask": ["Bash", "mcp__*"]]

    public static let claudeDisallowedTools: [String] =
        ["Edit", "Write", "MultiEdit", "NotebookEdit"] + OrchestratorShellJudge.gitVerbs.map { "Bash(git \($0):*)" }

    private static let keysBesideACommand: Set<String> = [
        "command", "description", "explanation", "timeout", "run_in_background", "is_background",
        "dangerouslyDisableSandbox", "cwd", "workdir", "working_directory", "directory", "file_path", "path",
        CodexTranslation.itemKey, GrokTranslation.itemKey,
    ]

    public static func refusal(toolName: String, input: JSONValue, runsUnasked: Bool = false) -> String? {
        if shellTools.contains(toolName) {
            let command = input["command"]?.stringValue ?? ""
            if OrchestratorShellJudge.refuses(command) { return refused("running a git command that changes the repository") }
            guard runsUnasked, OrchestratorUnaskedJudge.verdict(command) == .refused else { return nil }
            return refused("running a command that changes files or the repository")
        }
        if toolName.hasPrefix(BridgeToolApproval.toolPrefix) {
            let tool = String(toolName.dropFirst(BridgeToolApproval.toolPrefix.count))
            return refusedBridgeTools[tool].map(refused)
        }
        if toolName.hasPrefix("mcp__") || readingTools.contains(toolName) { return nil }
        return refused("using \(toolName), which can change files")
    }

    static func answersItself(toolName: String, input: JSONValue, worktree: String, runsUnasked: Bool = false) -> Bool {
        guard shellTools.contains(toolName), let command = input["command"]?.stringValue else { return false }
        if input["cmd"].map({ names($0, command) }) ?? true, directoryKeys.allSatisfy({ runs(in: input[$0], worktree: worktree) }),
           OrchestratorShellJudge.reads(command) {
            return true
        }
        guard runsUnasked, holdsOnlyTheCommand(input, command: command),
              directoryKeys.allSatisfy({ runs(in: input[$0], worktree: worktree) }) else { return false }
        return OrchestratorUnaskedJudge.verdict(command) == .passes
    }

    private static func holdsOnlyTheCommand(_ input: JSONValue, command: String) -> Bool {
        guard let members = input.objectValue else { return false }
        return members.allSatisfy { key, value in
            keysBesideACommand.contains(key) || (key == "cmd" && names(value, command))
        }
    }

    private static func names(_ cmd: JSONValue, _ command: String) -> Bool {
        cmd.stringValue == command
    }

    private static func runs(in directory: JSONValue?, worktree: String) -> Bool {
        guard let directory else { return true }
        guard let path = directory.stringValue else { return false }
        return URL(fileURLWithPath: path).standardized.path == URL(fileURLWithPath: worktree).standardized.path
    }

    public static func terminalRefusal(workspaceID: WorkspaceID, store: Store) async -> String? {
        await orchestratorRefusal(workspaceID: workspaceID, store: store, doing: "driving a terminal")
    }

    public static func canvasEditRefusal(workspaceID: WorkspaceID, store: Store) async -> String? {
        await orchestratorRefusal(workspaceID: workspaceID, store: store, doing: "changing a canvas file")
    }

    private static func orchestratorRefusal(workspaceID: WorkspaceID, store: Store, doing what: String) async -> String? {
        do {
            guard try await store.workspace(id: workspaceID)?.isOrchestrator == true else { return nil }
        } catch {
            return refused(what)
        }
        return refused(what)
    }

    public static func appliesStoredApprovals(toolName: String, orchestrates: Bool) -> Bool {
        !orchestrates || readingTools.contains(toolName)
    }

    public static let claudeArguments = [
        "--disallowedTools", claudeDisallowedTools.joined(separator: " "),
        "--append-system-prompt", OrchestratorRole.instructions,
    ]

    public static func claudeMode(_ requested: PermissionMode, orchestrates: Bool) -> String {
        guard orchestrates, requested != .plan else { return requested.cliValue }
        return claudeAskingMode
    }

    public static func permissionMode(_ requested: PermissionMode, orchestrates: Bool) -> PermissionMode {
        orchestrates ? permissionMode(requested) : requested
    }

    public static func permissionMode(_ requested: PermissionMode) -> PermissionMode {
        switch requested {
        case .bypassPermissions, .acceptEdits, .autoReview: .auto
        case .auto, .plan: requested
        }
    }

    public static func prompt(_ text: String, orchestrates: Bool, opensSession: Bool) -> String {
        guard orchestrates, opensSession else { return text }
        return OrchestratorRole.instructions + "\n\n" + text
    }

    private static func refused(_ what: String) -> String {
        "This workspace is the project's orchestrator, and Unified Dev refuses \(what) here. "
            + "Start a workspace with workspace_start for the change and follow it from here."
    }
}
