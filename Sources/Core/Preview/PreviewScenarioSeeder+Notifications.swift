import Foundation

extension PreviewScenarioSeeder {
    func seedNotifications(_ scenario: PreviewScenario, at now: Date) async throws -> Int {
        let store = manager.store
        let repos = try await store.repos()
        var seeded = 0
        for notification in scenario.notifications {
            guard let repo = repos.first(where: { $0.path.hasSuffix("/projects/" + notification.project) }) else {
                continue
            }
            let moment = now.addingTimeInterval(-notification.minutesAgo * 60)
            if notification.removed {
                try await seedRemoved(notification, in: repo, at: moment, index: seeded)
            } else {
                try await seedLive(notification, in: repo, at: moment)
            }
            seeded += 1
        }
        return seeded
    }

    private func seedLive(_ notification: PreviewScenario.SeededNotification, in repo: Repo, at moment: Date) async throws {
        let store = manager.store
        let rows = try await store.workspaces(repoID: repo.id, includeArchived: true)
        guard let workspace = rows.first(where: { $0.name == notification.workspace }) else { return }
        let chats = try await store.sessions(workspaceID: workspace.id)
        let session = notification.chat.flatMap { title in chats.first { $0.title == title } }
        try await record(notification, workspace: workspace, sessionID: session?.id, at: moment)
    }

    private func seedRemoved(
        _ notification: PreviewScenario.SeededNotification, in repo: Repo, at moment: Date, index: Int
    ) async throws {
        let store = manager.store
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id,
            name: notification.workspace,
            branch: "removed-\(index)",
            path: scratchRoot + "/removed-\(index)",
            baseBranch: "main"
        ))
        try await record(notification, workspace: workspace, sessionID: nil, at: moment)
        try await store.deleteWorkspace(id: workspace.id)
    }

    private func record(
        _ notification: PreviewScenario.SeededNotification, workspace: Workspace, sessionID: SessionID?, at moment: Date
    ) async throws {
        let store = manager.store
        try await store.recordInboxNotification(
            NotificationDraft(
                event: notification.event,
                workspaceID: workspace.id,
                sessionID: sessionID,
                workspaceName: workspace.name,
                detail: notification.detail
            ),
            at: moment
        )
        guard notification.read else { return }
        let rows = try await store.inboxNotifications(at: moment)
        guard let row = rows.first(where: {
            $0.workspaceID == workspace.id && $0.sessionID == sessionID && $0.event == notification.event
        }) else { return }
        try await store.markInboxNotificationRead(id: row.id, at: moment)
    }
}
