import Testing
import Foundation
@testable import Core

@Suite("Notification inbox rules")
struct NotificationInboxRulesTests {
    private let moment = Date(timeIntervalSince1970: 1_800_000_000)

    private func row(
        _ event: NotificationEvent = .turnFinished,
        workspace: String = "w1",
        session: String? = "s1",
        at offset: TimeInterval = 0,
        read: Bool = false,
        state: WorkspaceState? = .active,
        chatExists: Bool = true
    ) -> InboxNotification {
        InboxNotification(
            event: event,
            workspaceID: WorkspaceID(workspace),
            sessionID: session.map(SessionID.init),
            workspaceName: "Tide tables",
            createdAt: moment.addingTimeInterval(offset),
            readAt: read ? moment : nil,
            workspaceState: state,
            chatExists: chatExists
        )
    }

    @Test("the newest notification comes first")
    func newestFirst() {
        let older = row(at: -60)
        let newer = row(at: 0)

        #expect(NotificationInbox.ordered([older, newer]).map(\.id) == [newer.id, older.id])
    }

    @Test("only what is unseen and still reachable counts")
    func countsUnseenAndReachable() {
        let rows = [
            row(),
            row(read: true),
            row(state: .archived),
            row(state: nil),
            row(chatExists: false),
        ]

        #expect(NotificationInbox.unseenCount(rows) == 3)
    }

    @Test("a live workspace goes to the chat the notification was about")
    func liveChat() {
        #expect(row().destination == .chat(WorkspaceID("w1"), SessionID("s1")))
    }

    @Test("a notification with no chat goes to the workspace")
    func noChat() {
        #expect(row(session: nil).destination == .chat(WorkspaceID("w1"), nil))
    }

    @Test("a chat that no longer exists goes to the workspace and says so")
    func deletedChat() {
        #expect(row(chatExists: false).destination == .chatGone(WorkspaceID("w1")))
    }

    @Test("an archived workspace goes to the archive view")
    func archived() {
        #expect(row(state: .archived).destination == .archived(WorkspaceID("w1"), SessionID("s1")))
        #expect(row(state: .archived, chatExists: false).destination == .archived(WorkspaceID("w1"), nil))
    }

    @Test("a removed workspace has nowhere to go")
    func removed() {
        #expect(row(state: nil).destination == .gone)
    }

    @Test("a banner finds the row of its own chat and no other")
    func bannerFindsItsRow() {
        let wanted = row(session: "s1")
        let sibling = row(session: "s2", at: 60)
        let sessionless = row(session: nil, at: 120)

        #expect(NotificationInbox.row(
            forBannerIn: [sibling, wanted, sessionless], workspaceID: WorkspaceID("w1"), sessionID: SessionID("s1")
        )?.id == wanted.id)
        #expect(NotificationInbox.row(
            forBannerIn: [sibling, wanted], workspaceID: WorkspaceID("w1"), sessionID: nil
        ) == nil)
        #expect(NotificationInbox.row(
            forBannerIn: [wanted], workspaceID: WorkspaceID("w2"), sessionID: SessionID("s1")
        ) == nil)
    }

    @Test("the chat on screen in the frontmost app is not recorded")
    func onScreenIsNotRecorded() {
        let context = NotificationContext(
            isAppActive: true, selectedWorkspaceID: WorkspaceID("w1"), selectedSessionID: SessionID("s1")
        )

        #expect(!NotificationInbox.shouldRecord(
            workspaceID: WorkspaceID("w1"), sessionID: SessionID("s1"), context: context
        ))
        #expect(!NotificationInbox.shouldRecord(workspaceID: WorkspaceID("w1"), sessionID: nil, context: context))
    }

    @Test("another chat of the workspace on screen, another workspace or the background are recorded")
    func offScreenIsRecorded() {
        let onW1 = NotificationContext(
            isAppActive: true, selectedWorkspaceID: WorkspaceID("w1"), selectedSessionID: SessionID("s1")
        )
        let inBackground = NotificationContext(
            isAppActive: false, selectedWorkspaceID: WorkspaceID("w1"), selectedSessionID: SessionID("s1")
        )

        #expect(NotificationInbox.shouldRecord(
            workspaceID: WorkspaceID("w1"), sessionID: SessionID("s2"), context: onW1
        ))
        #expect(NotificationInbox.shouldRecord(
            workspaceID: WorkspaceID("w2"), sessionID: SessionID("s9"), context: onW1
        ))
        #expect(NotificationInbox.shouldRecord(
            workspaceID: WorkspaceID("w1"), sessionID: SessionID("s1"), context: inBackground
        ))
    }

    @Test("what is selected only counts as opened while the app is frontmost")
    func openingNeedsTheAppInFront() {
        let selected = SidebarSelection.workspace(WorkspaceID("w1"))

        #expect(NotificationInbox.opening(
            selection: selected, activeSession: SessionID("s1"), isAppActive: false
        ) == nil)
        #expect(NotificationInbox.opening(
            selection: selected, activeSession: SessionID("s1"), isAppActive: true
        ) == .chat(WorkspaceID("w1"), SessionID("s1")))
        #expect(NotificationInbox.opening(
            selection: .archived(WorkspaceID("w1")), activeSession: nil, isAppActive: true
        ) == .archive(WorkspaceID("w1")))
        #expect(NotificationInbox.opening(selection: .home, activeSession: nil, isAppActive: true) == nil)
    }

    @Test("opening a chat clears that chat and leaves the others")
    func openingClearsItsOwnChat() {
        let opening = InboxOpening.chat(WorkspaceID("w1"), SessionID("s1"))

        #expect(NotificationInbox.clears(row(), by: opening))
        #expect(NotificationInbox.clears(row(session: nil), by: opening))
        #expect(NotificationInbox.clears(row(session: "s2", chatExists: false), by: opening))
        #expect(!NotificationInbox.clears(row(session: "s2"), by: opening))
        #expect(!NotificationInbox.clears(row(workspace: "w2"), by: opening))
        #expect(!NotificationInbox.clears(row(read: true), by: opening))
    }

    @Test("replying from a banner clears that chat alone")
    func replyClearsOnlyItsChat() {
        let replied = InboxOpening.replied(WorkspaceID("w1"), SessionID("s1"))

        #expect(NotificationInbox.clears(row(), by: replied))
        #expect(!NotificationInbox.clears(row(session: nil), by: replied))
        #expect(!NotificationInbox.clears(row(session: "s2", chatExists: false), by: replied))
    }

    @Test("opening the archive view clears every chat of that workspace")
    func openingTheArchiveClearsAll() {
        #expect(NotificationInbox.clears(row(session: "s2", state: .archived), by: .archive(WorkspaceID("w1"))))
    }

    @Test("a row reads with its profile, its event and how long ago it was")
    func rowReading() {
        let reading = InboxRowReading(row(.needsInput, at: -120), profileName: "Akira", now: moment)

        #expect(reading.title == "Tide tables")
        #expect(reading.origin == "Akira \u{00B7} Needs you")
        #expect(reading.detail == NotificationEvent.needsInput.fallbackDetail)
        #expect(reading.age == "2m")
        #expect(!reading.isDimmed)
        #expect(reading.opens)
        #expect(reading.accessibilityLabel.hasPrefix("Unseen, Tide tables"))
    }

    @Test("a read row is dimmed and still opens")
    func readRowReading() {
        let reading = InboxRowReading(row(read: true), profileName: "Akira", now: moment)

        #expect(reading.isDimmed)
        #expect(reading.opens)
        #expect(!reading.accessibilityLabel.hasPrefix("Unseen"))
    }

    @Test("a removed workspace's row says so and does not open")
    func goneRowReading() {
        let reading = InboxRowReading(row(state: nil), profileName: nil, now: moment)

        #expect(reading.detail == InboxRowReading.goneSentence)
        #expect(reading.isDimmed)
        #expect(!reading.opens)
        #expect(reading.origin == "Turn finished")
    }

    @Test("the bell says its count aloud", arguments: [
        (0, "Notifications, none unseen"),
        (1, "Notifications, 1 unseen"),
        (7, "Notifications, 7 unseen"),
    ])
    func bellLabel(unseen: Int, label: String) {
        #expect(NotificationBellReading.accessibilityLabel(unseen: unseen) == label)
    }

    @Test("the badge is absent at zero and stops at 99")
    func bellBadge() {
        #expect(NotificationBellReading.badge(unseen: 0) == nil)
        #expect(NotificationBellReading.badge(unseen: 12) == "12")
        #expect(NotificationBellReading.badge(unseen: 99) == "99")
        #expect(NotificationBellReading.badge(unseen: 100) == "99+")
    }

    @Test("a banner carries its chat")
    func bannerCarriesItsChat() {
        let info = BannerUserInfo.encode(workspaceID: WorkspaceID("w1"), sessionID: SessionID("s1"))

        #expect(BannerUserInfo.workspaceID(from: info) == WorkspaceID("w1"))
        #expect(BannerUserInfo.sessionID(from: info) == SessionID("s1"))
        #expect(BannerUserInfo.sessionID(from: BannerUserInfo.encode(workspaceID: WorkspaceID("w1"))) == nil)
    }

    @Test("a digest of one keeps its chat and a digest of several has none")
    func digestChat() {
        let first = NotificationDraft(
            event: .turnFinished, workspaceID: WorkspaceID("w1"), sessionID: SessionID("s1"), workspaceName: "One"
        )
        let second = NotificationDraft(
            event: .turnFinished, workspaceID: WorkspaceID("w2"), sessionID: SessionID("s2"), workspaceName: "Two"
        )

        #expect(NotificationDigest.prepare([first])?.sessionID == SessionID("s1"))
        #expect(NotificationDigest.prepare([first, second])?.sessionID == nil)
    }
}
