import Foundation

public enum OrchestratorRole {
    public enum Assignment: Equatable, Sendable {
        case allowed
        case refused(String)
    }

    public static func asksAtCreation(repoID: RepoID, workspaces: [Workspace]) -> Bool {
        !workspaces.contains { $0.repoID == repoID && ($0.state == .active || $0.isOrchestrator) }
    }

    public static func assignment(of workspace: Workspace, among workspaces: [Workspace]) -> Assignment {
        guard workspace.state == .active else {
            return .refused("\(workspace.name) is archived, so it cannot be the project's orchestrator.")
        }
        return assignment(in: workspace.repoID, replacing: workspace.id, among: workspaces)
    }

    public static func assignment(
        in repoID: RepoID, replacing candidate: WorkspaceID? = nil, among workspaces: [Workspace]
    ) -> Assignment {
        if let current = workspaces.first(where: {
            $0.repoID == repoID && $0.isOrchestrator && $0.id != candidate
        }) {
            return .refused(
                "\(current.name) is already this project's orchestrator. A project has one; "
                    + "stop \(current.name) being the orchestrator first."
            )
        }
        return .allowed
    }

    public static func pinned(_ requested: Bool, isOrchestrator: Bool) -> Bool {
        requested || isOrchestrator
    }

    public static func archiveObjection(to workspace: Workspace) -> String? {
        guard workspace.isOrchestrator else { return nil }
        return "\(workspace.name) is this project's orchestrator, so it is never archived. "
            + "Stop it being the orchestrator first if you want it gone."
    }

    public static func removalObjection(toWorktreeAt path: String, among workspaces: [Workspace]) -> String? {
        guard let orchestrator = workspaces.first(where: {
            $0.isOrchestrator && FolderPath.sameFolder($0.path, path)
        }) else { return nil }
        return "\(orchestrator.name) is this project's orchestrator, so its worktree is never removed. "
            + "Stop it being the orchestrator first if you want it gone."
    }

    public static func watchesStartedWorkspaces(requested: Bool, callerIsOrchestrator: Bool) -> Bool {
        requested || callerIsOrchestrator
    }

    public static let newWorkspaceName = "Orchestrator"

    public static func leads(_ workspace: Workspace) -> Bool {
        workspace.isOrchestrator && workspace.state == .active
    }

    public static func orchestrator(of repoID: RepoID, among workspaces: [Workspace]) -> Workspace? {
        workspaces.first { $0.repoID == repoID && leads($0) }
    }

    public static func announcedOrchestrator(for started: Workspace, among workspaces: [Workspace]) -> Workspace? {
        guard !started.isOrchestrator,
              let orchestrator = workspaces.first(where: {
                  $0.repoID == started.repoID && $0.isOrchestrator && $0.state == .active && $0.id != started.id
              }),
              started.origin.parentWorkspaceID != orchestrator.id
        else { return nil }
        return orchestrator
    }

    public static let instructions = """
        This chat runs in the orchestrator workspace of this project in Unified Dev. Nothing is \
        implemented here: no agent in this workspace edits, writes or deletes files in its worktree, \
        or commits, pushes, merges or rebases. Unified Dev refuses file edits, terminals, tools \
        it does not know, and the git verbs that change the worktree or the repository, such as \
        commit, push, merge and rebase. In a chat Unified Dev runs, it answers by itself a short \
        list of read-only commands written plainly: git log, diff, show and status, gh pr, issue \
        and run views and lists for this repository, ls, cat, grep, head, tail and wc, on paths \
        inside this worktree, with no cd, no git -C, no variables, no globs, no ~, and no --jq, \
        --template, --search or --watch on gh. Any other command or MCP tool may stop for the \
        owner, so write reads that way. The work here is to plan, \
        to start other workspaces with workspace_start for every piece of implementation, to follow \
        them with workspace_list, workspace_diff and chat_read, to answer them with workspace_say, \
        and to gather what they report into one account for the owner. Unified Dev tells the first \
        chat here about every workspace someone else starts in this project, and, when it opened \
        with a chat and a task, again when its first turn comes to rest. Reading files, searching and asking GitHub are fine.
        """
}
