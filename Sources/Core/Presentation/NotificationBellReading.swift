import CoreGraphics
import Foundation

public enum NotificationBellReading {
    public static let maximumShown = 99

    public static let popoverWidth: CGFloat = 360

    public static let tallestList: CGFloat = 420

    public static func title(unseen: Int) -> String {
        guard let badge = badge(unseen: unseen) else { return "Notifications" }
        return "Notifications, \(badge) unseen"
    }

    public static func offersMarkAllRead(unseen: Int) -> Bool {
        unseen > 0
    }

    public static func listHeight(content: CGFloat) -> CGFloat {
        min(max(content, 0), tallestList).rounded(.up)
    }

    public static func badge(unseen: Int) -> String? {
        guard unseen > 0 else { return nil }
        return unseen > maximumShown ? "\(maximumShown)+" : "\(unseen)"
    }

    public static func accessibilityLabel(unseen: Int) -> String {
        switch unseen {
        case 0: "Notifications, none unseen"
        case 1: "Notifications, 1 unseen"
        default: "Notifications, \(unseen) unseen"
        }
    }
}
