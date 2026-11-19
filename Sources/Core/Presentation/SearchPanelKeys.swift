import Foundation

public enum SearchPanelKey: Equatable, Sendable {
    case up
    case down
    case tab
    case backTab
    case returnKey
    case commandReturn
    case right
    case escape
    case backspaceOnEmpty
}

public enum SearchPanelOutcome: Equatable, Sendable {
    case move(Int)
    case open
    case drill
    case scope(HomeScope)
    case leaveMode
    case clearQuery
    case close
    case handled
    case ignored
}

public struct SearchPanelKeyContext: Equatable, Sendable {
    public var mode: SearchPanelMode
    public var rowCount: Int
    public var highlighted: Int?
    public var isQueryEmpty: Bool
    public var scope: HomeScope
    public var scopes: [HomeScope]
    public var canDrill: Bool
    public var caretAtEnd: Bool

    public init(
        mode: SearchPanelMode = .things,
        rowCount: Int = 0,
        highlighted: Int? = nil,
        isQueryEmpty: Bool = true,
        scope: HomeScope = .all,
        scopes: [HomeScope] = HomeScope.offered(searching: true),
        canDrill: Bool = false,
        caretAtEnd: Bool = true
    ) {
        self.mode = mode
        self.rowCount = rowCount
        self.highlighted = highlighted
        self.isQueryEmpty = isQueryEmpty
        self.scope = scope
        self.scopes = scopes
        self.canDrill = canDrill
        self.caretAtEnd = caretAtEnd
    }
}

public enum SearchPanelKeys {
    public static func outcome(
        for key: SearchPanelKey, in context: SearchPanelKeyContext
    ) -> SearchPanelOutcome {
        switch key {
        case .up, .down:
            guard let index = ListNavigation.destination(
                for: key == .down ? .down : .up,
                from: context.highlighted,
                count: context.rowCount
            ) else {
                return .handled
            }
            return index == context.highlighted ? .handled : .move(index)

        case .tab, .backTab:
            guard context.mode.showsScopes, !context.scopes.isEmpty else { return .ignored }
            let step = key == .tab ? 1 : -1
            let current = context.scopes.firstIndex(of: context.scope) ?? 0
            let next = (current + step + context.scopes.count) % context.scopes.count
            return .scope(context.scopes[next])

        case .returnKey:
            return context.highlighted == nil ? .handled : .open

        case .commandReturn:
            return context.canDrill ? .drill : .handled

        case .right:
            guard context.caretAtEnd else { return .ignored }
            return context.canDrill ? .drill : .ignored

        case .escape:
            return context.isQueryEmpty ? .close : .clearQuery

        case .backspaceOnEmpty:
            return context.mode == .things ? .ignored : .leaveMode
        }
    }

    public static func footer(
        for mode: SearchPanelMode, isSearching: Bool
    ) -> [SearchPanelFooterKey] {
        let open = MenuShortcut(.return)
        let close = MenuShortcut(.escape)
        switch mode {
        case .things:
            return [
                SearchPanelFooterKey(open, label: "Open"),
                SearchPanelFooterKey(MenuShortcut(.return, .command), label: "Actions"),
                isSearching
                    ? SearchPanelFooterKey(MenuShortcut(.tab), label: "Scope")
                    : SearchPanelFooterKey(MenuShortcut(">"), label: "Commands"),
                SearchPanelFooterKey(close, label: "Close"),
            ]
        case .commands:
            return [
                SearchPanelFooterKey(open, label: "Run"),
                SearchPanelFooterKey(MenuShortcut(.delete), label: "Leave commands"),
                SearchPanelFooterKey(close, label: "Close"),
            ]
        case .actions:
            return [
                SearchPanelFooterKey(open, label: "Run"),
                SearchPanelFooterKey(MenuShortcut(.delete), label: "Back"),
                SearchPanelFooterKey(close, label: "Close"),
            ]
        }
    }

    public static let fileSearchFooter = [
        SearchPanelFooterKey(MenuShortcut(.upArrow), MenuShortcut(.downArrow), label: "Navigate"),
        SearchPanelFooterKey(MenuShortcut(.return), label: "Open"),
        SearchPanelFooterKey(MenuShortcut(.escape), label: "Close"),
    ]
}

public struct SearchPanelFooterKey: Equatable, Sendable, Identifiable {
    public var shortcuts: [MenuShortcut]
    public var label: String

    public var key: String { shortcuts.map(\.display).joined() }

    public var text: String { "\(label) \(key)" }

    public var id: String { label }

    public init(_ shortcuts: MenuShortcut..., label: String) {
        self.shortcuts = shortcuts
        self.label = label
    }
}
