import AppKit
import Core
import Observation

@MainActor
@Observable
final class NotificationInboxModel {
    private(set) var rows: [InboxNotification] = []

    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var jumpsUnderway = 0

    var unseen: Int { NotificationInbox.unseenCount(rows) }

    func start(app: AppModel, store: Store) {
        self.app = app
        observation?.cancel()
        observation = Task { [weak self] in
            try? await store.pruneInboxNotifications()
            await self?.reload()
            for await _ in store.changes(of: [.inboxNotifications, .workspaces, .repos, .sessions]) {
                guard let self else { return }
                await self.reload()
            }
        }
    }

    func stop() {
        observation?.cancel()
        observation = nil
    }

    func reload() async {
        guard let store = app?.store else { return }
        #if DEBUG
        ActivityTally.inboxReloads += 1
        #endif
        let loaded = NotificationInbox.ordered((try? await store.inboxNotifications()) ?? [])
        if rows != loaded { rows = loaded }
        noteOnScreen()
    }

    func record(_ draft: NotificationDraft, context: NotificationContext) {
        guard let store = app?.store,
              NotificationInbox.shouldRecord(
                workspaceID: draft.workspaceID, sessionID: draft.sessionID, context: context
              )
        else { return }
        Task { try? await store.recordInboxNotification(draft) }
    }

    func noteOnScreen() {
        guard jumpsUnderway == 0, let app, let store = app.store,
              let opening = NotificationInbox.opening(
                selection: app.selection,
                activeSession: app.selectedModel?.activeSessionID,
                isAppActive: NSApp?.isActive ?? false
              ),
              rows.contains(where: { NotificationInbox.clears($0, by: opening) })
        else { return }
        Task { try? await store.markInboxNotificationsRead(opening) }
    }

    func markAllRead() {
        guard let store = app?.store else { return }
        Task { try? await store.markAllInboxNotificationsRead() }
    }

    func open(_ row: InboxNotification) async {
        guard let app, let store = app.store else { return }
        jumpsUnderway += 1
        defer {
            jumpsUnderway -= 1
            noteOnScreen()
        }
        await reload()
        let current = rows.first { $0.id == row.id } ?? row
        guard current.destination != .gone else { return }

        try? await store.markInboxNotificationRead(id: current.id)
        if let profile = current.profileID { await app.switchProfile(to: profile) }
        await show(current.destination, in: app)
    }

    func openBanner(workspaceID: WorkspaceID, sessionID: SessionID?) async {
        jumpsUnderway += 1
        defer {
            jumpsUnderway -= 1
            noteOnScreen()
        }
        await reload()
        guard let row = NotificationInbox.row(forBannerIn: rows, workspaceID: workspaceID, sessionID: sessionID) else {
            OpenWorkspaceNotification.post(workspaceID)
            return
        }
        await open(row)
    }

    private func show(_ destination: InboxDestination, in app: AppModel) async {
        switch destination {
        case .chat(let workspaceID, let sessionID):
            if let sessionID, let workspace = app.workspaces.first(where: { $0.id == workspaceID }) {
                app.model(for: workspace).activeSessionID = sessionID
            }
            await app.open(workspaceID: workspaceID)
        case .chatGone(let workspaceID):
            await app.open(workspaceID: workspaceID)
            app.notice = Notice(message: InboxRowReading.chatGoneNotice)
        case .archived(let workspaceID, let sessionID):
            await app.open(workspaceID: workspaceID)
            if let sessionID { app.existingModel(for: workspaceID)?.activeSessionID = sessionID }
        case .gone:
            break
        }
    }
}
