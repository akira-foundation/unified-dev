public struct InspectorVisibility: Equatable, Sendable {
    public var isVisible: Bool

    public init(isVisible: Bool = true) {
        self.isVisible = isVisible
    }

    public init(storedHidden: Bool) {
        self.isVisible = !storedHidden
    }

    public var storedHidden: Bool { !isVisible }

    public var hidesInspector: Bool { !isVisible }

    public var menuTitleIsAlternate: Bool { !isVisible }

    public var toggleHelp: String {
        BrowserToolbar.help(isVisible ? "Hide the inspector" : "Show the inspector", key: .toggleInspector)
    }

    public func toggled() -> InspectorVisibility {
        InspectorVisibility(isVisible: !isVisible)
    }

    public func isPresented(hasWorkspace: Bool) -> Bool {
        isVisible && hasWorkspace
    }
}
