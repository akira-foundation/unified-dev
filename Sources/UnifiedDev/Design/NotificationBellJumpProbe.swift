import Core
import Foundation

#if DEBUG
@MainActor
enum NotificationBellJumpProbe {
    private static let flag = "--bell-jump-probe"

    static func attach(_ app: AppModel) {
        guard let path = ProbeHarness.value(for: flag) else { return }
        Task { await run(app, reportingTo: path) }
    }

    private static func run(_ app: AppModel, reportingTo path: String) async {
        var lines: [String] = []
        let inbox = app.notificationInbox
        for _ in 0..<200 where inbox.rows.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
        func row(_ event: NotificationEvent) -> InboxNotification? { inbox.rows.first { $0.event == event } }
        func check(_ name: String, _ passed: Bool) { lines.append("\(passed ? "PASS" : "FAIL") \(name)") }

        if let target = row(.needsInput) {
            await inbox.open(target)
            await inbox.reload()
            check("switches profile", app.activeProfileID == target.profileID)
            check("selects the workspace", app.selection == .workspace(target.workspaceID))
            check("selects the chat", app.selectedModel?.activeSessionID == target.sessionID)
            check("marks the row read", row(.needsInput)?.isRead == true)
        } else {
            check("found the needs input row", false)
        }

        if let target = row(.turnFinished), let session = target.sessionID {
            try? await app.store?.deleteSession(id: session)
            await inbox.open(target)
            check("deleted chat opens its workspace", app.selection == .workspace(target.workspaceID))
            check("deleted chat switches profile", app.activeProfileID == target.profileID)
            check("deleted chat gives a notice", app.notice?.message == InboxRowReading.chatGoneNotice)
        } else {
            check("found the turn finished row", false)
        }

        if let target = row(.agentFailed) {
            await inbox.open(target)
            check("archived opens the archive view", app.selection == .archived(target.workspaceID))
        } else {
            check("found the agent failed row", false)
        }

        if let target = row(.setupFailed) {
            let before = app.selection
            await inbox.open(target)
            check("removed workspace goes nowhere", app.selection == before)
        } else {
            check("found the setup failed row", false)
        }

        lines.append("unseen \(inbox.unseen)")
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}
#endif
