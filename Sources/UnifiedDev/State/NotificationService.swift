import AppKit
import Observation
import SwiftUI
import UserNotifications
import Core

@MainActor
@Observable
final class NotificationService {
    static let shared = NotificationService()

    nonisolated static let isAvailable = Bundle.main.bundleIdentifier != nil

    nonisolated private static let workspaceCategory = "unifieddev.workspace"
    nonisolated private static let summaryCategory = "unifieddev.summary"
    nonisolated private static let replyAction = "unifieddev.reply"
    nonisolated private static let openAction = "unifieddev.open"

    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private(set) var isRequestingPermission = false

    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private let preferences = NotificationPreferences()
    @ObservationIgnored private var digest = NotificationDigest()
    @ObservationIgnored private var flushTasks: [NotificationEvent: Task<Void, Never>] = [:]
    @ObservationIgnored private var checksTask: Task<Void, Never>?
    @ObservationIgnored private var lastSeenChecks: [WorkspaceID: PullRequest.Checks] = [:]
    @ObservationIgnored private var quotaWatch = QuotaExhaustionWatch()

    private init() {}

    func attach(_ app: AppModel) {
        guard self.app !== app else { return }
        self.app = app
        Task { await refreshAuthorization() }
        startWatchingChecks()
    }

    func registerCategories() {
        guard Self.isAvailable else { return }
        let reply = UNTextInputNotificationAction(
            identifier: Self.replyAction,
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Reply to the agent"
        )
        let open = UNNotificationAction(
            identifier: Self.openAction,
            title: "Open",
            options: [.foreground]
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.workspaceCategory,
                actions: [reply, open],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: Self.summaryCategory,
                actions: [open],
                intentIdentifiers: []
            ),
        ])
    }

    func refreshAuthorization() async {
        guard Self.isAvailable else { return }
        authorization = await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus
    }

    @discardableResult
    func requestPermission() async -> Bool {
        guard Self.isAvailable else { return false }
        guard !isRequestingPermission else { return authorization == .authorized }
        isRequestingPermission = true
        defer { isRequestingPermission = false }

        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
        await refreshAuthorization()
        return granted
    }

    var isBlockedBySystem: Bool {
        authorization == .denied
    }

    func openSystemSettings() {
        let identifier = Bundle.main.bundleIdentifier ?? ""
        let target = "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(identifier)"
        guard let url = URL(string: target) else { return }
        NSWorkspace.shared.open(url)
    }

    func turnFinished(
        workspace: Workspace,
        sessionID: SessionID?,
        result: AgentResult,
        wasCancelled: Bool,
        hookRefusedCalls: Set<String>
    ) {
        guard let outcome = result.outcome(
            wasCancelled: wasCancelled, hookRefusedCalls: hookRefusedCalls
        ) else { return }
        submit(NotificationDraft(
            event: outcome.event,
            workspaceID: workspace.id,
            sessionID: sessionID,
            workspaceName: workspace.name,
            detail: result.summary
        ))
    }

    func agentNeedsPermission(workspace: Workspace, sessionID: SessionID?, detail: String = "") {
        submit(NotificationDraft(
            event: .needsInput,
            workspaceID: workspace.id,
            sessionID: sessionID,
            workspaceName: workspace.name,
            detail: detail
        ))
    }

    func agentFailed(workspace: Workspace, sessionID: SessionID?, message: String) {
        submit(NotificationDraft(
            event: .agentFailed,
            workspaceID: workspace.id,
            sessionID: sessionID,
            workspaceName: workspace.name,
            detail: message
        ))
    }

    func rateLimitReported(_ event: Data, workspace: Workspace, sessionID: SessionID?) {
        for quota in quotaWatch.newlyExhausted(fromRateLimitEvent: event, in: workspace.id) {
            submit(NotificationDraft(
                event: .quotaExhausted,
                workspaceID: workspace.id,
                sessionID: sessionID,
                workspaceName: workspace.name,
                detail: QuotaExhaustionWatch.sentence(for: quota)
            ))
        }
    }

    func setupFailed(workspace: Workspace) {
        submit(NotificationDraft(
            event: .setupFailed,
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            detail: SetupFailure.instruction
        ))
    }

    func sendTestNotification() {
        deliver(PreparedNotification(
            identifier: "unifieddev.test",
            threadIdentifier: "unifieddev.test",
            title: "Unified Dev",
            body: "Notifications are working. This is what an agent finishing looks like.",
            workspaceID: app?.selection.workspaceID ?? WorkspaceID("")
        ))
    }

    private var context: NotificationContext {
        NotificationContext(
            isAppActive: NSApp?.isActive ?? false,
            selectedWorkspaceID: app?.selection.workspaceID,
            selectedSessionID: app?.selectedModel?.activeSessionID
        )
    }

    func pullRequestFixStopped(_ pullRequest: PullRequest, in workspace: Workspace) {
        submit(NotificationDraft(
            event: .pullRequestFixStopped,
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            detail: PullRequestAutoFix.stoppedSentence(number: pullRequest.number)
        ))
    }

    private func submit(_ draft: NotificationDraft) {
        app?.notificationInbox.record(draft, context: context)

        let verdict = NotificationPolicy.verdict(
            for: draft.event,
            workspaceID: draft.workspaceID,
            settings: preferences.settings,
            context: context
        )
        guard verdict.delivers else { return }

        guard digest.add(draft) else { return }

        flushTasks[draft.event] = Task { [weak self] in
            try? await Task.sleep(for: NotificationDigest.window)
            guard !Task.isCancelled else { return }
            self?.flush(draft.event)
        }
    }

    private func flush(_ event: NotificationEvent) {
        flushTasks[event] = nil
        guard let prepared = digest.drain(event) else { return }
        deliver(prepared)
    }

    private func deliver(_ prepared: PreparedNotification) {
        guard Self.isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title(of: prepared)
        content.body = prepared.body
        content.sound = .default
        content.threadIdentifier = prepared.threadIdentifier
        content.userInfo = BannerUserInfo.encode(workspaceID: prepared.workspaceID, sessionID: prepared.sessionID)
        content.categoryIdentifier = prepared.threadIdentifier == prepared.workspaceID.rawValue
            ? Self.workspaceCategory
            : Self.summaryCategory

        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: prepared.identifier, content: content, trigger: nil
        ))
    }

    private func title(of prepared: PreparedNotification) -> String {
        guard let app else { return prepared.title }
        let owner = ProfileNotice.profile(of: prepared.workspaceIDs, workspaces: app.workspaces, repos: app.repos)
        return ProfileNotice.title(
            prepared.title,
            profile: app.profiles.first { $0.id == owner },
            active: app.activeProfileID
        )
    }

    func reply(_ text: String, toWorkspace workspaceID: WorkspaceID, session sessionID: SessionID?) async {
        guard let app, let workspace = app.workspaces.first(where: { $0.id == workspaceID }) else { return }

        let model = app.model(for: workspace)
        if model.sessions.isEmpty { await model.reloadSessions() }
        guard let session = sessionID.map({ id in model.sessions.first { $0.id == id } }) ?? model.activeSession else {
            app.notice = Notice(message: InboxRowReading.replyNotSentNotice)
            return
        }

        await model.transcript(for: session).submit(text, dismissingAsks: true)
        try? await app.store?.markInboxNotificationsRead(.replied(workspaceID, session.id))
    }

    nonisolated static func workspaceID(from response: UNNotificationResponse) -> WorkspaceID? {
        BannerUserInfo.workspaceID(from: response.notification.request.content.userInfo)
    }

    nonisolated static func sessionID(from response: UNNotificationResponse) -> SessionID? {
        BannerUserInfo.sessionID(from: response.notification.request.content.userInfo)
    }

    private func startWatchingChecks() {
        checksTask?.cancel()
        checksTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: PullRequestReader.checksNotification.interval)
                guard let self else { return }
                await self.pollChecks()
            }
        }
    }

    private func pollChecks() async {
        guard let app else { return }

        let onScreen = context.isAppActive ? context.selectedWorkspaceID : nil

        for workspace in app.workspaces {
            guard !Task.isCancelled else { return }
            guard let pullRequest = WorkspacePullRequests.shared.pullRequest(for: workspace.id) else {
                lastSeenChecks[workspace.id] = nil
                continue
            }

            let previous = lastSeenChecks[workspace.id]
            lastSeenChecks[workspace.id] = pullRequest.checks
            guard workspace.id != onScreen else { continue }

            if previous == .pending, pullRequest.checks == .passing || pullRequest.checks == .failing {
                submit(NotificationDraft(
                    event: .checksFinished,
                    workspaceID: workspace.id,
                    workspaceName: workspace.name,
                    detail: pullRequest.checksSummary
                ))
            }

            if pullRequest.checks == .pending {
                await app.existingModel(for: workspace.id)?
                    .refreshPullRequest(maxAge: PullRequestReader.checksNotification.maxAge)
            }
        }
    }
}
