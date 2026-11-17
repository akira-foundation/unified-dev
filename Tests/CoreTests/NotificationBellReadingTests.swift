import CoreGraphics
import Testing
@testable import Core

@Suite("Notification bell reading")
struct NotificationBellReadingTests {
    @Test("the toolbar item is named, so the overflow menu and Customise Toolbar can say what it is")
    func titleNamesTheBell() {
        #expect(NotificationBellReading.title(unseen: 0) == "Notifications")
        #expect(NotificationBellReading.title(unseen: 3) == "Notifications, 3 unseen")
        #expect(NotificationBellReading.title(unseen: 250) == "Notifications, 99+ unseen")
    }

    @Test("Mark All as Read is offered only when something is unread")
    func markAllNeedsSomethingUnread() {
        #expect(!NotificationBellReading.offersMarkAllRead(unseen: 0))
        #expect(NotificationBellReading.offersMarkAllRead(unseen: 1))
    }

    @Test("a short list is as tall as its rows, and a long one stops at the ceiling and scrolls")
    func listSizesToItsRows() {
        #expect(NotificationBellReading.listHeight(content: 120.2) == 121)
        #expect(NotificationBellReading.listHeight(content: 2_000) == NotificationBellReading.tallestList)
        #expect(NotificationBellReading.listHeight(content: -4) == 0)
    }
}
