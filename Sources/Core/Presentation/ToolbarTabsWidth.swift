import CoreGraphics

public enum ToolbarTabsWidth {
    public static let minimum: CGFloat = 240

    public static let reservedForActions: CGFloat = 170

    public static let reservedForCollapsedSwitcher: CGFloat = 44

    public static func width(inColumn column: CGFloat, besideCollapsedSwitcher: Bool = false) -> CGFloat {
        max(minimum, column - reservedForActions - (besideCollapsedSwitcher ? reservedForCollapsedSwitcher : 0))
    }

    public static func showsStrip(tabCount: Int, paneCount: Int, isRenaming: Bool) -> Bool {
        guard tabCount > 0 else { return false }
        return tabCount > 1 || paneCount > 1 || isRenaming
    }
}
