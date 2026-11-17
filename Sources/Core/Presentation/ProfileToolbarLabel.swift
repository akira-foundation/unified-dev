import CoreGraphics

public struct ProfileToolbarLabel: Equatable, Sendable {
    public static let occupiedBesideMenu: CGFloat = 152

    public static let smallestMenuWithName: CGFloat = 74

    public static let menuBesideName: CGFloat = 44

    public static let widestMenuAtMinimum: CGFloat = 160

    public let menuWidth: CGFloat?

    public let sitsOnGlass: Bool

    public let help: String

    public let accessibilityLabel: String

    public let measureKey: String

    public static func barIsHidden(isFullScreen: Bool, trafficLightsOpacity: CGFloat) -> Bool {
        isFullScreen && trafficLightsOpacity < 0.5
    }

    public static func menuWidthAtMinimum(forNameWidth nameWidth: CGFloat) -> CGFloat {
        min(max((nameWidth + menuBesideName).rounded(.up), smallestMenuWithName), widestMenuAtMinimum)
    }

    public static func titleBarWidth(forNameWidth nameWidth: CGFloat) -> CGFloat {
        occupiedBesideMenu + menuWidthAtMinimum(forNameWidth: nameWidth)
    }

    public static func resolve(profileName: String, drawsSidebar: Bool, barIsHidden: Bool = false, sidebarWidth: CGFloat) -> ProfileToolbarLabel {
        let room = (sidebarWidth - occupiedBesideMenu).rounded(.down)
        let showsName = drawsSidebar && !barIsHidden && room >= smallestMenuWithName
        return ProfileToolbarLabel(
            menuWidth: showsName ? room : nil,
            sitsOnGlass: !showsName,
            help: "Switch profile, \(profileName)",
            accessibilityLabel: "Profile, \(profileName)",
            measureKey: "\(profileName)|\(showsName ? room : 0)|\(barIsHidden)"
        )
    }
}
