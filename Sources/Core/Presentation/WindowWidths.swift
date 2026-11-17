import CoreGraphics

public struct WindowWidths: Equatable, Sendable {
    public let sidebar: CGFloat

    public let sidebarMinimum: CGFloat

    public let detail: CGFloat

    public let inspector: CGFloat

    public let divider: CGFloat

    public init(
        sidebar: CGFloat,
        sidebarMinimum: CGFloat,
        detail: CGFloat,
        inspector: CGFloat,
        divider: CGFloat
    ) {
        self.sidebar = sidebar
        self.sidebarMinimum = sidebarMinimum
        self.detail = detail
        self.inspector = inspector
        self.divider = divider
    }

    public func holding(sidebarContent widths: [CGFloat]) -> WindowWidths {
        let widest = (widths.max() ?? 0).rounded(.up)
        return WindowWidths(
            sidebar: sidebar,
            sidebarMinimum: min(max(sidebarMinimum, widest), sidebar),
            detail: detail,
            inspector: inspector,
            divider: divider
        )
    }

    public func minimum(withInspector: Bool) -> CGFloat {
        sidebar + divider + detailHalf(withInspector: withInspector)
    }

    public func detailHalf(withInspector: Bool) -> CGFloat {
        withInspector ? detail + divider + inspector : detail
    }

    public func sidebarMaximum(sharing total: CGFloat, withInspector: Bool) -> CGFloat? {
        let room = total - divider - detailHalf(withInspector: withInspector)
        if room >= sidebar { return sidebar }
        if room >= sidebarMinimum { return room }
        return nil
    }

    public func presenting(windowWidth: CGFloat, screenWidth: CGFloat) -> InspectorFit {
        let needed = minimum(withInspector: true)
        guard windowWidth < needed else { return .settled }

        let grown = max(windowWidth, min(needed, screenWidth))
        let widened = grown > windowWidth ? grown : nil
        guard grown < needed else {
            return InspectorFit(windowWidth: widened, sidebarWidth: nil, foldsSidebar: false)
        }

        guard let room = sidebarMaximum(sharing: grown, withInspector: true) else {
            return InspectorFit(windowWidth: widened, sidebarWidth: nil, foldsSidebar: true)
        }
        return InspectorFit(windowWidth: widened, sidebarWidth: room, foldsSidebar: false)
    }
}

public struct InspectorFit: Equatable, Sendable {
    public let windowWidth: CGFloat?

    public let sidebarWidth: CGFloat?

    public let foldsSidebar: Bool

    public static let settled = InspectorFit(
        windowWidth: nil, sidebarWidth: nil, foldsSidebar: false
    )

    public init(windowWidth: CGFloat?, sidebarWidth: CGFloat?, foldsSidebar: Bool) {
        self.windowWidth = windowWidth
        self.sidebarWidth = sidebarWidth
        self.foldsSidebar = foldsSidebar
    }

    public var isSettled: Bool { self == .settled }
}
