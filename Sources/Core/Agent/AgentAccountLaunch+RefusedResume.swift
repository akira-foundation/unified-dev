import Foundation

public extension AgentAccountLaunch {
    static func terminal(
        of sessionID: SessionID,
        store: Store,
        defaults: [AgentAccountHome] = SpendAccounts.defaultHomes()
    ) async throws -> AgentAccountLaunch? {
        guard let session = try await store.session(id: sessionID), let workspaceID = session.workspaceID,
              let workspace = try await store.workspace(id: workspaceID) else { return nil }
        return try await AgentAccountResolver.resolve(
            workspaceID: workspace.id, repoID: workspace.repoID, store: store, defaults: defaults
        ).launch(for: session.agentKind)
    }

    func forgetsResume(inPane pane: String, of sessionID: SessionID, store: Store, base: URL? = nil) async -> Bool {
        guard isRefused else { return false }
        try? await store.setSetting(TerminalCommandMemory.key(paneID: pane), nil)
        if let folder = try? AgentKind.interactiveLaunchDirectory(sessionID: sessionID, base: base) {
            try? FileManager.default.removeItem(at: folder.appending(path: AgentKind.resumeFileName))
        }
        return true
    }
}
