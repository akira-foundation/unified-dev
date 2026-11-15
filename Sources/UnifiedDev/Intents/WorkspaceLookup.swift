import Foundation
import Core

enum WorkspaceLookup {
    static func isAgentRunning(workspaceID: WorkspaceID, store: Store) async -> Bool {
        let sessions = (try? await store.sessions(workspaceID: workspaceID)) ?? []
        return sessions.contains { $0.state == .running }
    }

    static func isAwaitingPermission(workspaceID: WorkspaceID, store: Store) async -> Bool {
        let sessions = (try? await store.sessions(workspaceID: workspaceID)) ?? []
        return sessions.contains { $0.state == .waiting }
    }

    static func entities(
        for workspaces: [Workspace],
        store: Store,
        includePullRequests: Bool
    ) async throws -> [WorkspaceEntity] {
        let repos = try await store.repos()
        let names = Dictionary(uniqueKeysWithValues: repos.map { ($0.id, $0.name) })

        var entities: [WorkspaceEntity] = []
        for workspace in workspaces {
            entities.append(
                WorkspaceEntity(
                    workspace: workspace,
                    project: names[workspace.repoID] ?? "Unknown project",
                    isAgentRunning: await isAgentRunning(workspaceID: workspace.id, store: store),
                    isAwaitingPermission: await isAwaitingPermission(workspaceID: workspace.id, store: store),
                    pullRequest: includePullRequests ? await pullRequest(for: workspace) : nil
                )
            )
        }
        return entities
    }

    static func pullRequest(for workspace: Workspace) async -> PullRequest? {
        guard FileManager.default.fileExists(atPath: workspace.path) else { return nil }
        return try? await ForgePullRequests.pullRequest(for: workspace, maxAge: .seconds(60))
    }
}
