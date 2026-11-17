import CoreGraphics

public struct WindowColumns: Equatable, Sendable {
    public enum Reach: Equatable, Sendable, CaseIterable {
        case all
        case withoutSidebar

        public var showsCentre: Bool { self == .all || self == .withoutSidebar }
    }

    public enum ToolbarSection: Equatable, Sendable {
        case centre
        case inspector
    }

    public let fitsSidebar: Bool

    public let drawsSidebar: Bool

    public let offersInspector: Bool

    public let drawsInspector: Bool

    public let sidebarCeiling: CGFloat

    public var collapsesProfileSwitcher: Bool { !drawsSidebar }

    public var reach: Reach { drawsSidebar ? .all : .withoutSidebar }

    public var trailingSection: ToolbarSection { drawsInspector ? .inspector : .centre }

    public var inspectorToggleSection: ToolbarSection? { offersInspector ? trailingSection : nil }

    public static func resolve(
        selection: SidebarSelection,
        hasInspectorSubject: Bool,
        reservesInspectorRoom: Bool,
        hidesSidebar: Bool,
        hidesInspector: Bool,
        widths: WindowWidths,
        availableWidth: CGFloat
    ) -> WindowColumns {
        let room = widths.sidebarMaximum(
            sharing: availableWidth, withInspector: reservesInspectorRoom && !hidesInspector
        )
        let offers = hasInspectorSubject && selection.workspaceID != nil
        return WindowColumns(
            fitsSidebar: room != nil,
            drawsSidebar: room != nil && !hidesSidebar,
            offersInspector: offers,
            drawsInspector: offers && !hidesInspector,
            sidebarCeiling: room ?? widths.sidebarMinimum
        )
    }
}
