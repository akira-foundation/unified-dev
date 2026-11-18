import SwiftUI
import Core

struct MenuCommand: View {
    var action: MenuBarAction
    var alternate = false
    var symbol: String?
    var perform: @MainActor () -> Void

    init(
        _ action: MenuBarAction,
        alternate: Bool = false,
        symbol: String? = nil,
        perform: @escaping @MainActor () -> Void
    ) {
        self.action = action
        self.alternate = alternate
        self.symbol = symbol
        self.perform = perform
    }

    private var item: MenuBarItem { MenuBarCatalogue[action] }

    var body: some View {
        button
            .modifier(MenuKeyEquivalent(key: item.keyOnSameAgainRow ? nil : item.key))
    }

    @ViewBuilder
    private var button: some View {
        if let symbol {
            Button(item.title(alternate: alternate), systemImage: symbol, action: perform)
        } else {
            Button(item.title(alternate: alternate), action: perform)
        }
    }
}

struct MenuCommandGroup<Content: View>: View {
    var action: MenuBarAction
    var symbol: String?
    @ViewBuilder var content: Content

    init(_ action: MenuBarAction, symbol: String? = nil, @ViewBuilder content: () -> Content) {
        self.action = action
        self.symbol = symbol
        self.content = content()
    }

    private var title: String { MenuBarCatalogue[action].title }

    var body: some View {
        if let symbol {
            Menu(title, systemImage: symbol) { content }
        } else {
            Menu(title) { content }
        }
    }
}

private struct MenuKeyEquivalent: ViewModifier {
    var key: MenuShortcut?

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key.equivalent, modifiers: key.eventModifiers)
        } else {
            content
        }
    }
}

extension MenuShortcut {
    var equivalent: KeyEquivalent {
        switch trigger {
        case .character(let character): KeyEquivalent(character)
        case .upArrow: .upArrow
        case .downArrow: .downArrow
        case .leftArrow: .leftArrow
        case .rightArrow: .rightArrow
        case .delete: .delete
        case .return: .return
        case .comma: KeyEquivalent(",")
        case .tab: .tab
        case .escape: .escape
        }
    }

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        return result
    }
}
