import Foundation
import Synchronization

final class SessionGrants: Sendable {
    private let store: Store
    private let workspaceID: WorkspaceID?
    private let cachedRepoID = Mutex<RepoID?>(nil)

    init(store: Store, workspaceID: WorkspaceID?) {
        self.store = store
        self.workspaceID = workspaceID
    }

    func repoID() async -> RepoID? {
        if let cached = cachedRepoID.withLock({ $0 }) { return cached }
        guard let workspaceID,
              let workspace = try? await store.workspace(id: workspaceID) else { return nil }
        cachedRepoID.withLock { $0 = workspace.repoID }
        return workspace.repoID
    }

    func isOrchestrator() async -> Bool {
        guard let workspaceID else { return false }
        return (try? await store.workspace(id: workspaceID))?.isOrchestrator ?? false
    }

    func refusal(toolName: String, input: JSONValue) async -> String? {
        guard let workspaceID, let workspace = try? await store.workspace(id: workspaceID),
              workspace.isOrchestrator else { return nil }
        let runsUnasked = await OrchestratorUnaskedCommands.isOn(repoID: workspace.repoID, in: store)
        return OrchestratorToolGuard.refusal(toolName: toolName, input: input, runsUnasked: runsUnasked)
    }

    func answersItself(toolName: String, input: JSONValue) async -> Bool {
        guard let workspaceID, let workspace = try? await store.workspace(id: workspaceID),
              workspace.isOrchestrator else { return false }
        let runsUnasked = await OrchestratorUnaskedCommands.isOn(repoID: workspace.repoID, in: store)
        return OrchestratorToolGuard.answersItself(
            toolName: toolName, input: input, worktree: workspace.path, runsUnasked: runsUnasked
        )
    }

    func matching(_ ask: PermissionAsk) async -> [PermissionGrant]? {
        guard ask.canWiden, let repoID = await repoID() else { return nil }
        let orchestrates = await isOrchestrator()
        guard OrchestratorToolGuard.appliesStoredApprovals(toolName: ask.toolName, orchestrates: orchestrates) else {
            return nil
        }
        guard let grants = try? await store.permissionGrants(repoID: repoID) else { return nil }
        return PermissionGrantIndex.match(ask: ask, grants: grants)
    }

    func recordUse(of grants: [PermissionGrant]) async {
        for grant in grants {
            try? await store.recordPermissionGrantUse(id: grant.id)
        }
    }

    func record(_ decision: PermissionDecision, from ask: PermissionAsk) async {
        guard ask.canWiden, let repoID = await repoID() else { return }
        for grant in PermissionGrant.all(granting: decision, from: ask, repoID: repoID) {
            _ = try? await store.upsert(grant)
        }
    }
}
