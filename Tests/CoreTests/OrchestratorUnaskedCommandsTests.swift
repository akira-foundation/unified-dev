import Foundation
import Testing
@testable import Core

extension OrchestratorUnaskedCommands {
    static func turn(_ isOn: Bool, for session: Session, in store: Store) async throws {
        let workspaceID = try #require(session.workspaceID)
        let workspace = try #require(try await store.workspace(id: workspaceID))
        try await save(isOn, repoID: workspace.repoID, to: store)
    }
}

@Suite("The orchestrator's run without asking switch", .tags(.persistence), .scratchDirectory)
struct OrchestratorUnaskedCommandsTests {
    private static let repositoryRefusal = "This workspace is the project's orchestrator, and Unified Dev refuses "
        + "running a command that changes files or the repository here. "
        + "Start a workspace with workspace_start for the change and follow it from here."

    private func shell(_ command: String) -> JSONValue {
        .object(["command": .string(command)])
    }

    private func seedOrchestrator(_ store: Store, named name: String = "r") async throws -> (Repo, SessionGrants) {
        let repo = try await store.upsert(Repo(name: name, path: TestScratch.unique(name)))
        let lead = try await store.upsert(Workspace(
            repoID: repo.id, name: "lead-\(name)", branch: "b/\(name)",
            path: TestScratch.unique("lead-\(name)"), baseBranch: "main"
        ))
        try await store.setOrchestrator(true, workspaceID: lead.id)
        return (repo, SessionGrants(store: store, workspaceID: lead.id))
    }

    @Test("on when nothing is stored")
    func onWhenAbsent() {
        #expect(OrchestratorUnaskedCommands.parse(nil))
    }

    @Test("on when on is stored")
    func onWhenStoredOn() {
        #expect(OrchestratorUnaskedCommands.parse("on"))
    }

    @Test("off when off or anything else is stored", arguments: ["off", "", "true", "1", "ON", "yes"])
    func offWhenStoredOtherwise(_ stored: String) {
        #expect(!OrchestratorUnaskedCommands.parse(stored))
    }

    @Test("a project with nothing stored is on, and each saved value is kept as saved")
    func savedValuesAreKept() async throws {
        let store = try makeTestStore("unasked-row")
        let repoID = RepoID.new()
        #expect(await OrchestratorUnaskedCommands.isOn(repoID: repoID, in: store))
        try await OrchestratorUnaskedCommands.save(false, repoID: repoID, to: store)
        #expect(await !OrchestratorUnaskedCommands.isOn(repoID: repoID, in: store))
        #expect(try await store.setting(OrchestratorUnaskedCommands.key(repoID: repoID)) == "off")
        try await OrchestratorUnaskedCommands.save(true, repoID: repoID, to: store)
        #expect(await OrchestratorUnaskedCommands.isOn(repoID: repoID, in: store))
        #expect(try await store.setting(OrchestratorUnaskedCommands.key(repoID: repoID)) == "on")
    }

    @Test("off, the guard answers only what it answers today", arguments: [
        "make build && echo \"a b\"", "echo \"$(git log -1)\"", "rm -rf Sources", "echo x > file",
        "eval git push", "echo \"$(git push)\"",
    ])
    func offChangesNothing(_ command: String) {
        #expect(!OrchestratorToolGuard.answersItself(toolName: "Bash", input: shell(command), worktree: "/w"))
        #expect(OrchestratorToolGuard.refusal(toolName: "Bash", input: shell(command)) == nil)
    }

    @Test("on, a command that used to reach the card is answered")
    func onAnswers() {
        let command = "git log -1 && echo \"$(git status)\""
        #expect(!OrchestratorToolGuard.answersItself(toolName: "Bash", input: shell(command), worktree: "/w"))
        #expect(OrchestratorToolGuard.answersItself(toolName: "Bash", input: shell(command), worktree: "/w", runsUnasked: true))
        #expect(OrchestratorToolGuard.refusal(toolName: "Bash", input: shell(command), runsUnasked: true) == nil)
    }

    @Test("on, a listed read still answers")
    func onKeepsTheList() {
        #expect(OrchestratorToolGuard.answersItself(toolName: "Bash", input: shell("git log -1"), worktree: "/w", runsUnasked: true))
    }

    @Test("on, what the judge refuses is refused in our words and never answered", arguments: [
        "eval git push", "echo \"$(git push)\"", "bash -c 'rm file'", "git log && echo x > file", "gh pr merge 1",
    ])
    func onStillRefuses(_ command: String) {
        #expect(!OrchestratorToolGuard.answersItself(toolName: "Bash", input: shell(command), worktree: "/w", runsUnasked: true))
        #expect(OrchestratorToolGuard.refusal(toolName: "Bash", input: shell(command), runsUnasked: true) == Self.repositoryRefusal)
    }

    @Test("on, what the guard already refused is refused in the same words", arguments: ["git push", "git log && git commit -m x"])
    func onKeepsTheOldRefusal(_ command: String) {
        #expect(!OrchestratorToolGuard.answersItself(toolName: "Bash", input: shell(command), worktree: "/w", runsUnasked: true))
        #expect(
            OrchestratorToolGuard.refusal(toolName: "Bash", input: shell(command), runsUnasked: true)
                == OrchestratorToolGuard.refusal(toolName: "Bash", input: shell(command))
        )
    }

    @Test("on, a command it cannot read is neither answered nor refused", arguments: ["eval \"$X\"", "git $V", "python3 -c x"])
    func onUnreadableAsks(_ command: String) {
        #expect(!OrchestratorToolGuard.answersItself(toolName: "Bash", input: shell(command), worktree: "/w", runsUnasked: true))
        #expect(OrchestratorToolGuard.refusal(toolName: "Bash", input: shell(command), runsUnasked: true) == nil)
    }

    @Test("on, an ask carrying a field it does not know stays with the owner", arguments: [
        "args", "argv", "arguments", "script", "stdin", "shell", "code", "somethingNew",
    ])
    func unknownFieldAsks(_ key: String) {
        let input = JSONValue.object(["command": .string("rg x"), key: .array([.string("x")])])
        #expect(!OrchestratorToolGuard.answersItself(toolName: "Bash", input: input, worktree: "/w", runsUnasked: true))
    }

    @Test("a listed read is not answered when the ask carries a different cmd", arguments: [false, true])
    func listedReadWithADifferentCmd(_ runsUnasked: Bool) {
        let differs = JSONValue.object(["command": .string("ls"), "cmd": .string("rm x")])
        let same = JSONValue.object(["command": .string("ls"), "cmd": .string("ls")])
        let listed = JSONValue.object(["command": .string("ls"), "cmd": .array([.string("rm"), .string("x")])])
        #expect(!OrchestratorToolGuard.answersItself(toolName: "Bash", input: listed, worktree: "/w", runsUnasked: runsUnasked))
        #expect(!OrchestratorToolGuard.answersItself(toolName: "Bash", input: differs, worktree: "/w", runsUnasked: runsUnasked))
        #expect(OrchestratorToolGuard.answersItself(toolName: "Bash", input: same, worktree: "/w", runsUnasked: runsUnasked))
    }

    @Test("on, the fields the agents really send do not stop an answer")
    func knownFieldsAnswer() {
        let claude = JSONValue.object([
            "command": .string("rg x"), "description": .string("d"), "timeout": .integer(1),
            "run_in_background": .bool(false),
        ])
        let codex = JSONValue.object([
            "command": .string("rg x"), "cwd": .string("/other"), CodexTranslation.itemKey: .object([:]),
        ])
        let grok = JSONValue.object([
            "command": .string("rg x"), "cmd": .string("rg x"), GrokTranslation.itemKey: .object([:]),
        ])
        for input in [claude, codex, grok] {
            #expect(OrchestratorToolGuard.answersItself(toolName: "Bash", input: input, worktree: "/w", runsUnasked: true))
        }
        let differs = JSONValue.object(["command": .string("rg x"), "cmd": .string("rm x")])
        #expect(!OrchestratorToolGuard.answersItself(toolName: "Bash", input: differs, worktree: "/w", runsUnasked: true))
    }

    @Test("on, the switch reaches shell tools alone")
    func onlyShellTools() {
        let command = shell("git log && git status")
        for tool in ["Edit", "Write", "Read", "mcp__other__tool", "mcp__unifieddev-workspace-bridge__terminal_start"] {
            #expect(!OrchestratorToolGuard.answersItself(toolName: tool, input: command, worktree: "/w", runsUnasked: true))
        }
        #expect(OrchestratorToolGuard.refusal(toolName: "Edit", input: command, runsUnasked: true) != nil)
        #expect(OrchestratorToolGuard.refusal(
            toolName: "mcp__unifieddev-workspace-bridge__terminal_start", input: command, runsUnasked: true
        ) != nil)
        let unnamed = JSONValue.object(["cmd": .string("ls && ls")])
        #expect(!OrchestratorToolGuard.answersItself(toolName: "Bash", input: unnamed, worktree: "/w", runsUnasked: true))
    }

    @Test("grants read the switch on every ask, for the orchestrator of that project alone")
    func grantsReadLive() async throws {
        let store = try makeTestStore("unasked-grants")
        let (repo, lead) = try await seedOrchestrator(store)
        let (otherRepo, otherLead) = try await seedOrchestrator(store, named: "s")
        let crew = try await store.upsert(Workspace(
            repoID: repo.id, name: "crew", branch: "b/crew", path: TestScratch.unique("crew"), baseBranch: "main"
        ))
        let crewGrants = SessionGrants(store: store, workspaceID: crew.id)
        let compound = shell("rg x && echo \"a b\"")
        let refused = shell("eval git push")

        #expect(await lead.answersItself(toolName: "Bash", input: compound))
        #expect(await lead.refusal(toolName: "Bash", input: refused) == Self.repositoryRefusal)

        try await OrchestratorUnaskedCommands.save(false, repoID: otherRepo.id, to: store)
        try await OrchestratorUnaskedCommands.save(false, repoID: repo.id, to: store)
        #expect(await !lead.answersItself(toolName: "Bash", input: compound))
        #expect(await lead.refusal(toolName: "Bash", input: refused) == nil)

        try await OrchestratorUnaskedCommands.save(true, repoID: repo.id, to: store)
        #expect(await lead.answersItself(toolName: "Bash", input: compound))
        #expect(await lead.refusal(toolName: "Bash", input: refused) == Self.repositoryRefusal)
        #expect(await !otherLead.answersItself(toolName: "Bash", input: compound))
        #expect(await otherLead.refusal(toolName: "Bash", input: refused) == nil)
        #expect(await !crewGrants.answersItself(toolName: "Bash", input: compound))
        #expect(await crewGrants.refusal(toolName: "Bash", input: refused) == nil)

        try await OrchestratorUnaskedCommands.save(false, repoID: repo.id, to: store)
        #expect(await !lead.answersItself(toolName: "Bash", input: compound))
        #expect(await lead.refusal(toolName: "Bash", input: refused) == nil)
    }

    @Test("the footer states the cost and what stays refused")
    func copy() {
        #expect(OrchestratorUnaskedCommands.caveat.contains("you would not see them first"))
        #expect(OrchestratorUnaskedCommands.caveat.contains("stay refused"))
        #expect(OrchestratorUnaskedCommands.caveat.contains("Builds, scripts and network tools ask you first"))
        #expect(OrchestratorUnaskedCommands.caveat.hasPrefix("On by default."))
    }
}
