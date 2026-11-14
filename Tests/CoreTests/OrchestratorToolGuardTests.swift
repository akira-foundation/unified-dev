import Foundation
import Testing
@testable import Core

@Suite("Orchestrator tool guard")
struct OrchestratorToolGuardTests {
    private func command(_ text: String) -> JSONValue { .object(["command": .string(text)]) }

    @Test("file edits are refused whatever agent names them",
          arguments: ["Edit", "Write", "MultiEdit", "NotebookEdit", "ApplyPatch"])
    func editsAreRefused(_ tool: String) {
        #expect(OrchestratorToolGuard.refusal(toolName: tool, input: .object([:])) != nil)
    }

    @Test("a git command that changes the repository is refused, for either shell tool")
    func gitWritesAreRefused() {
        for tool in ["Bash", "Shell"] {
            #expect(OrchestratorToolGuard.refusal(toolName: tool, input: command("git commit -m x")) != nil)
            #expect(!OrchestratorToolGuard.answersItself(toolName: tool, input: command("git commit -m x"), worktree: "/tmp/w"))
        }
    }

    @Test("a command that is not on the read list is left for the owner to answer", arguments: [
        "rm -rf build", "echo hi > notes.txt", "find . -name x -delete", "git branch -D old",
    ])
    func otherCommandsAreAsked(_ text: String) {
        #expect(OrchestratorToolGuard.refusal(toolName: "Bash", input: command(text)) == nil)
        #expect(!OrchestratorToolGuard.answersItself(toolName: "Bash", input: command(text), worktree: "/tmp/w"))
    }

    @Test("a read on the list is answered by Unified Dev, for either shell tool")
    func readsAreAnswered() {
        for tool in ["Bash", "Shell"] {
            #expect(OrchestratorToolGuard.refusal(toolName: tool, input: command("git log -1")) == nil)
            #expect(OrchestratorToolGuard.answersItself(toolName: tool, input: command("git log -1"), worktree: "/tmp/w"))
        }
    }

    @Test("only a shell command is answered by the read list", arguments: [
        "Read", "Task", "AskUserQuestion", "ExitPlanMode", "WebFetch", "mcp__github__get_issue",
        "mcp__unifieddev-workspace-bridge__browser_click",
    ])
    func otherToolsAreNotAnswered(_ tool: String) {
        #expect(!OrchestratorToolGuard.answersItself(toolName: tool, input: command("git log -1"), worktree: "/tmp/w"))
    }

    @Test("a shell tool with no command string is not answered")
    func missingCommand() {
        #expect(!OrchestratorToolGuard.answersItself(toolName: "Bash", input: .object([:]), worktree: "/tmp/w"))
        #expect(!OrchestratorToolGuard.answersItself(toolName: "Bash", input: .object(["command": .array([.string("ls")])]), worktree: "/tmp/w"))
    }

    @Test("a read is answered only in the worktree it was judged for", arguments: [
        "cwd", "workdir", "working_directory", "directory",
    ])
    func directoriesAreJudged(_ key: String) {
        let elsewhere = JSONValue.object(["command": .string("git status"), key: .string("/tmp/evil")])
        let here = JSONValue.object(["command": .string("git status"), key: .string("/tmp/w/")])
        let unreadable = JSONValue.object(["command": .string("git status"), key: .integer(1)])
        #expect(!OrchestratorToolGuard.answersItself(toolName: "Shell", input: elsewhere, worktree: "/tmp/w"))
        #expect(OrchestratorToolGuard.answersItself(toolName: "Shell", input: here, worktree: "/tmp/w"))
        #expect(!OrchestratorToolGuard.answersItself(toolName: "Shell", input: unreadable, worktree: "/tmp/w"))
    }

    @Test("tools it does not know, and the bridge's terminal tools, are refused", arguments: [
        "delete_file", "edit_file", "Grok.edit", "Permissions",
        "mcp__unifieddev-workspace-bridge__terminal_start",
        "mcp__unifieddev-workspace-bridge__terminal_write",
        "mcp__unifieddev-workspace-bridge__terminal_send_key",
        "mcp__unifieddev-workspace-bridge__canvas_edit",
    ])
    func unknownToolsAreRefused(_ tool: String) {
        #expect(OrchestratorToolGuard.refusal(toolName: tool, input: .object([:])) != nil)
    }

    @Test("a canvas edit is refused for its own reason, not the terminal's, and canvas_read and canvas_render stay open")
    func canvasEditHasItsOwnReason() {
        let prefix = BridgeToolApproval.toolPrefix
        let edit = OrchestratorToolGuard.refusal(toolName: prefix + "canvas_edit", input: .object([:]))
        let terminal = OrchestratorToolGuard.refusal(toolName: prefix + "terminal_write", input: .object([:]))

        #expect(edit?.contains("changing a canvas file") == true)
        #expect(edit?.contains("terminal") == false)
        #expect(terminal?.contains("driving a terminal") == true)
        #expect(OrchestratorToolGuard.refusal(toolName: prefix + "canvas_read", input: .object([:])) == nil)
        #expect(OrchestratorToolGuard.refusal(toolName: prefix + "canvas_render", input: .object([:])) == nil)
    }

    @Test("a stored approval never answers a shell command in an orchestrator")
    func storedApprovals() {
        #expect(!OrchestratorToolGuard.appliesStoredApprovals(toolName: "Bash", orchestrates: true))
        #expect(!OrchestratorToolGuard.appliesStoredApprovals(toolName: "Shell", orchestrates: true))
        #expect(OrchestratorToolGuard.appliesStoredApprovals(toolName: "WebFetch", orchestrates: true))
        #expect(!OrchestratorToolGuard.appliesStoredApprovals(toolName: "mcp__github__merge_pull_request", orchestrates: true))
        #expect(OrchestratorToolGuard.appliesStoredApprovals(toolName: "Bash", orchestrates: false))
    }

    @Test("a Codex request is answered only when it names the command its item runs", arguments: [
        CodexApprovalRequest.Kind.permissions, .mcpElicitation, .commandExecution, .fileChange, .toolUserInput,
    ])
    func codexRequestWithoutCommand(_ kind: CodexApprovalRequest.Kind) {
        let request = codexRequest(kind, params: .object([:]))
        #expect(!CodexPermission.asksAboutItsItem(request, item: codexItem))
    }

    @Test("a Codex request that is not a command is not answered even when it names one", arguments: [
        CodexApprovalRequest.Kind.permissions, .mcpElicitation, .fileChange, .toolUserInput,
    ])
    func codexRequestOfAnotherKind(_ kind: CodexApprovalRequest.Kind) {
        let request = codexRequest(kind, params: .object(["command": .string("git log -1")]))
        #expect(!CodexPermission.asksAboutItsItem(request, item: codexItem))
    }

    @Test("a Codex command request naming its own item's command is answered")
    func codexRequestNamingItsCommand() {
        let request = codexRequest(.commandExecution, params: .object(["command": .string("git log -1")]))
        #expect(CodexPermission.asksAboutItsItem(request, item: codexItem))
    }

    @Test("a Codex request is not answered when no item confirms its command")
    func codexRequestWithoutAnItem() {
        let request = codexRequest(.commandExecution, params: .object(["command": .string("git log -1")]))
        #expect(!CodexPermission.asksAboutItsItem(request, item: nil))
    }

    @Test("a Codex request is not answered when it names another directory than its item")
    func codexRequestInAnotherDirectory() {
        let elsewhere = codexRequest(
            .commandExecution,
            params: .object(["command": .string("git log -1"), "cwd": .string("/tmp/evil")])
        )
        let here = codexRequest(
            .commandExecution,
            params: .object(["command": .string("git log -1"), "cwd": .string("/tmp/w")])
        )
        #expect(!CodexPermission.asksAboutItsItem(elsewhere, item: codexItem))
        #expect(CodexPermission.asksAboutItsItem(here, item: codexItem))
    }

    @Test("a Codex command request about something other than running it is not answered", arguments: [
        ("kind", JSONValue.string("writeStdin")),
        ("approvalId", JSONValue.string("callback")),
        ("networkApprovalContext", JSONValue.object(["host": .string("example.com")])),
        ("additionalPermissions", JSONValue.object(["network": .bool(true)])),
        ("environmentId", JSONValue.string("remote")),
        ("availableDecisions", JSONValue.array([.string("decline")])),
        ("aFieldNobodyHasReadYet", JSONValue.bool(true)),
    ])
    func codexRequestAboutSomethingElse(_ key: String, _ value: JSONValue) {
        let request = codexRequest(
            .commandExecution, params: .object(["command": .string("git log -1"), key: value])
        )
        #expect(!CodexPermission.asksAboutItsItem(request, item: codexItem))
    }

    @Test("a Codex command request with those fields empty, or kind command, is answered", arguments: [
        ("kind", JSONValue.string("command")),
        ("kind", JSONValue.null),
        ("approvalId", JSONValue.null),
        ("networkApprovalContext", JSONValue.null),
        ("cwd", JSONValue.null),
        ("reason", JSONValue.string("needs a look")),
        ("startedAtMs", JSONValue.integer(1)),
        ("commandActions", JSONValue.array([])),
    ])
    func codexRequestWithEmptyFields(_ key: String, _ value: JSONValue) {
        let request = codexRequest(
            .commandExecution, params: .object(["command": .string("git log -1"), key: value])
        )
        #expect(CodexPermission.asksAboutItsItem(request, item: codexItem))
    }

    private var codexItem: CodexItem {
        .commandExecution(CodexCommandExecution(id: "exec-1", command: "git log -1", cwd: "/tmp/w"))
    }

    private func codexRequest(_ kind: CodexApprovalRequest.Kind, params: JSONValue) -> CodexApprovalRequest {
        CodexApprovalRequest(id: .number(3), kind: kind, threadID: "t", turnID: "u", itemID: "exec-1", params: params)
    }

    @Test("tools that only read, and the bridge's own tools, pass",
          arguments: ["Read", "Grep", "Glob", "WebSearch", "TodoWrite", "ExitPlanMode", "AskUserQuestion",
                      "mcp__unifieddev-workspace-bridge__workspace_start", "mcp__github__get_issue"])
    func otherToolsPass(_ tool: String) {
        #expect(OrchestratorToolGuard.refusal(toolName: tool, input: .object([:])) == nil)
    }

    @Test("a mode that would approve writes by itself is brought down to asking")
    func modeIsClamped() {
        #expect(OrchestratorToolGuard.permissionMode(.bypassPermissions) == .auto)
        #expect(OrchestratorToolGuard.permissionMode(.acceptEdits) == .auto)
        #expect(OrchestratorToolGuard.permissionMode(.autoReview) == .auto)
        #expect(OrchestratorToolGuard.permissionMode(.plan) == .plan)
        #expect(OrchestratorToolGuard.permissionMode(.auto) == .auto)
    }

    @Test("Claude is launched with the edits denied, the commits denied and the role explained")
    func claudeArguments() throws {
        let session = Session(workspaceID: WorkspaceID("w"), permissionMode: .bypassPermissions)
        let arguments = AgentRunner.argv(session: session, resume: nil, orchestrates: true)

        let flag = try #require(arguments.firstIndex(of: "--disallowedTools"))
        let list = arguments[flag + 1]
        let names = list.components(separatedBy: " ")
        #expect(names.contains("Edit"))
        #expect(names.contains("Write"))
        #expect(names.contains("MultiEdit"))
        #expect(names.contains("NotebookEdit"))
        #expect(list.contains("Bash(git commit:*)"))
        #expect(!list.contains("mcp__"))
        #expect(arguments.contains(OrchestratorRole.instructions))
        let mode = arguments.firstIndex(of: "--permission-mode").map { arguments[$0 + 1] }
        #expect(mode == OrchestratorToolGuard.claudeAskingMode)
        #expect(!arguments.contains("--allow-dangerously-skip-permissions"))
        let settings = try #require(arguments.firstIndex(of: "--settings").map { arguments[$0 + 1] })
        let asked = JSONValue.parse(settings)?["permissions"]?["ask"]
        #expect(asked == .array([.string("Bash"), .string("mcp__*")]))
    }

    @Test("an orchestrator that asked to plan stays in plan mode")
    func planStays() {
        #expect(OrchestratorToolGuard.claudeMode(.plan, orchestrates: true) == "plan")
        #expect(OrchestratorToolGuard.claudeMode(.bypassPermissions, orchestrates: true) == "default")
        #expect(OrchestratorToolGuard.claudeMode(.bypassPermissions, orchestrates: false) == "bypassPermissions")
    }

    @Test("Grok in an orchestrator neither approves by itself nor runs everything")
    func grokAsks() {
        let meta = ACPClient.sessionMeta(.auto, asksEveryCall: true)
        #expect(meta["yoloMode"]?.boolValue == false)
        #expect(meta["autoMode"]?.boolValue == false)
        #expect(ACPClient.sessionMeta(.auto, asksEveryCall: false)["autoMode"]?.boolValue == true)
    }

    @Test("an ordinary workspace is launched exactly as before")
    func ordinaryClaude() {
        let session = Session(workspaceID: WorkspaceID("w"), permissionMode: .bypassPermissions)
        let arguments = AgentRunner.argv(session: session, resume: nil)
        #expect(!arguments.contains("--disallowedTools"))
        #expect(!arguments.contains("--append-system-prompt"))
        let mode = arguments.firstIndex(of: "--permission-mode").map { arguments[$0 + 1] }
        #expect(mode == "bypassPermissions")
    }

    @Test("Codex is held to a read only sandbox whatever mode was picked")
    func codexSandbox() {
        let mode = OrchestratorToolGuard.permissionMode(.bypassPermissions)
        #expect(CodexRunner.sandboxMode(for: mode) == .readOnly)
        #expect(CodexRunner.approvalPolicy(for: mode) == .onRequest)
    }

    @Test("the terminal chat carries the same limits for Claude and Codex")
    func interactive() {
        let claude = AgentKind.claudeCode.interactiveArguments(
            prompt: "", sessionID: SessionID("s"), model: "", effort: "",
            permissionMode: .bypassPermissions, orchestrates: true
        ) ?? []
        #expect(claude.contains("--disallowedTools"))
        #expect(claude.contains(OrchestratorRole.instructions))
        let mode = claude.firstIndex(of: "--permission-mode").map { claude[$0 + 1] }
        #expect(mode == OrchestratorToolGuard.claudeAskingMode)
        let settings = claude.firstIndex(of: "--settings").map { claude[$0 + 1] } ?? ""
        #expect(JSONValue.parse(settings)?["permissions"]?["ask"] == .array([.string("Bash"), .string("mcp__*")]))

        let codex = AgentKind.codex.interactiveArguments(
            prompt: "", sessionID: SessionID("s"), model: "", effort: "",
            permissionMode: .bypassPermissions, orchestrates: true
        ) ?? []
        let sandbox = codex.firstIndex(of: "--sandbox").map { codex[$0 + 1] }
        #expect(sandbox == CodexSandboxMode.readOnly.rawValue)
    }

    @Test("Grok hears the role at the head of a new session's first prompt, and nowhere else")
    func grokPrompt() {
        let first = OrchestratorToolGuard.prompt("Plan the release", orchestrates: true, opensSession: true)
        #expect(first.hasPrefix(OrchestratorRole.instructions))
        #expect(first.hasSuffix("Plan the release"))
        #expect(OrchestratorToolGuard.prompt("Next", orchestrates: true, opensSession: false) == "Next")
        #expect(OrchestratorToolGuard.prompt("Next", orchestrates: false, opensSession: true) == "Next")
    }
}
