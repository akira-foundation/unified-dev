import Foundation
import Testing
@testable import Core

@Suite("MenuBarCatalogue")
struct MenuBarCatalogueTests {
    private var keyed: [(MenuShortcut, MenuBarItem)] {
        MenuBarCatalogue.commands.compactMap { item in
            item.key.map { ($0, item) }
        }
    }

    private var alternates: [(MenuShortcut, MenuBarItem)] {
        MenuBarCatalogue.commands.compactMap { item in
            item.alternateKey.map { ($0, item) }
        }
    }

    @Test func fileHistoryShortcuts() {
        #expect(MenuBarCatalogue[.fileBack].key == MenuShortcut("[", .command))
        #expect(MenuBarCatalogue[.fileForward].key == MenuShortcut("]", .command))
    }

    @Test("Command-Backspace belongs to text editing, even without a published focus value")
    func commandBackspaceDoesNotArchive() {
        let editingKey = MenuShortcut(.delete, .command)
        #expect(!MenuBarCatalogue.commands.contains { $0.key == editingKey })
        #expect(MenuBarCatalogue[.archive].key == MenuShortcut(.delete, .command, .shift))
    }

    @Test("every action has exactly one row, so a lookup cannot trap")
    func everyActionHasARow() {
        for action in MenuBarAction.allCases {
            #expect(MenuBarCatalogue[action].action == action, "\(action)")
        }
        #expect(MenuBarCatalogue.commands.count == MenuBarAction.allCases.count)
    }

    @Test("no two items in the whole bar claim the same keystroke, alternates included")
    func noCollisions() {
        var seen: [MenuShortcut: MenuBarAction] = [:]
        for (key, item) in keyed + alternates {
            if let other = seen[key] {
                Issue.record("\(item.action) and \(other) both claim \(key)")
            }
            seen[key] = item.action
        }
    }

    @Test("only the two tab items carry a second key, and it is the one the monitor reads")
    func onlyTheTabsCarryAnAlternate() {
        #expect(Set(alternates.map(\.1.action)) == [.nextTab, .previousTab])
        for (key, item) in alternates {
            #expect(key.trigger == .tab, "\(item.action)")
            #expect(key.modifiers.contains(.option), "\(item.action)")
            #expect(!key.modifiers.contains(.command), "\(item.action)")
            #expect(item.key != nil, "\(item.action)")
        }
    }

    @Test("every key equivalent carries Command")
    func everyKeyIsACommandKey() {
        for (key, item) in keyed {
            #expect(key.modifiers.contains(.command), "\(item.action)")
        }
    }

    @Test("every item is in a menu that exists and says something")
    func everyItemIsNamed() {
        for item in MenuBarCatalogue.commands {
            #expect(!item.title.isEmpty, "\(item.action)")
            #expect(item.title.trimmingCharacters(in: .whitespaces) == item.title, "\(item.action)")
            #expect(MenuBarCatalogue.items(in: item.menu).contains(item), "\(item.action)")
        }
    }

    @Test("no menu is empty")
    func noEmptyMenu() {
        for menu in MenuBarMenu.allCases {
            #expect(!MenuBarCatalogue.items(in: menu).isEmpty, "\(menu)")
        }
    }

    @Test("there is one way to get a project, it is in File, and it carries a key")
    func oneProjectDoorInTheBar() {
        let start = MenuBarCatalogue[.startProject]
        #expect(start.menu == .file)
        #expect(start.key != nil)
        #expect(start.availability == .always)
        #expect(!MenuBarCatalogue.commands.contains(where: { $0.title.contains("Add Project") }))
    }

    @Test("only the two splits put their key on a submenu row")
    func onlyTheSplitsDeferTheirKey() {
        let deferred = MenuBarCatalogue.commands.filter(\.keyOnSameAgainRow).map(\.action)
        #expect(Set(deferred) == [.splitRight, .splitDown])
        for action in deferred {
            #expect(MenuBarCatalogue[action].key != nil, "\(action)")
        }
    }

    @Test("a two-state item carries both of its titles")
    func twoStateItems() {
        let twoState = MenuBarCatalogue.commands.filter { $0.alternateTitle != nil }
        #expect(Set(twoState.map(\.action)) == [.pin, .unreadMark, .fileBack, .fileForward, .browserReload, .browserComment, .toggleInspector])
        for item in twoState {
            #expect(item.title(alternate: false) == item.title, "\(item.action)")
            #expect(item.title(alternate: true) == item.alternateTitle, "\(item.action)")
        }
        #expect(MenuBarCatalogue[.archive].title(alternate: true) == "Archive Workspace")
    }

    @Test("the inspector is hidden and shown with Option-Command-0, workspace or not")
    func inspectorItem() {
        let item = MenuBarCatalogue[.toggleInspector]
        #expect(item.menu == .view)
        #expect(item.key == MenuShortcut("0", .command, .option))
        #expect(item.availability == .always)
        #expect(item.title(alternate: false) == "Hide Inspector")
        #expect(item.title(alternate: true) == "Show Inspector")
    }

    @Test("the bar words a workspace's actions the way its own row menu does")
    func workspaceWording() {
        #expect(MenuBarCatalogue[.openInEditor].title == "Open in Editor")
        #expect(MenuBarCatalogue[.revealInFinder].title == "Reveal in Finder")
        #expect(MenuBarCatalogue[.copyBranchName].title == "Copy Branch Name")
        #expect(MenuBarCatalogue[.copyName].title == "Copy Name")
        #expect(MenuBarCatalogue[.renameWorkspace].title == "Rename")
        #expect(MenuBarCatalogue[.colour].title == "Colour")
        #expect(MenuBarCatalogue[.pin].title == "Pin")
        #expect(MenuBarCatalogue[.pin].alternateTitle == "Unpin")
    }

    @Test("the unread item is worded by the rule the rows already read")
    func unreadWording() {
        let item = MenuBarCatalogue[.unreadMark]
        #expect(item.title == UnreadMarkAction.markUnread.title)
        #expect(item.alternateTitle == UnreadMarkAction.markRead.title)
    }

    @Test("the splits are worded as the pane menus word them")
    func splitWording() {
        #expect(MenuBarCatalogue[.splitRight].title == "Split Right")
        #expect(MenuBarCatalogue[.splitDown].title == "Split Down")
        #expect(MenuBarCatalogue[.closePane].title == "Close Pane")
        #expect(MenuBarCatalogue[.zoomPane].title == "Zoom Pane")
    }

    @Test("every key a focused view takes is either unspent in the bar or a known overlap")
    func theKeysTheViewsOwn() {
        let claimedByViews: [MenuShortcut: MenuBarAction?] = [
            MenuShortcut("d", .command): nil,
            MenuShortcut("d", .command, .shift): .showChanges,
            MenuShortcut("k", .command): .quickSearch,
            MenuShortcut("w", .command): .closeTab,
            MenuShortcut(.return, .command, .shift): .zoomPane,
            MenuShortcut(.leftArrow, .command, .option): nil,
            MenuShortcut(.rightArrow, .command, .option): nil,
            MenuShortcut(.upArrow, .command, .option): .previousWorkspace,
            MenuShortcut(.downArrow, .command, .option): .nextWorkspace,
            MenuShortcut("+", .command): .zoomIn,
            MenuShortcut("-", .command): .zoomOut,
            MenuShortcut("0", .command): .actualSize,
            MenuShortcut("f", .command): .find,
            MenuShortcut("g", .command): .findNext,
            MenuShortcut("g", .command, .shift): .findPrevious
        ]

        let inTheBar = Dictionary(uniqueKeysWithValues: keyed.map { ($0.0, $0.1.action) })
        for (key, expected) in claimedByViews {
            #expect(inTheBar[key] == expected, "\(key) is drawn as \(String(describing: inTheBar[key]))")
        }
    }

    @Test("the splits keep the editor's key rather than the shell's")
    func theSplitsKeepTheirKey() {
        #expect(MenuBarCatalogue[.splitRight].key == MenuShortcut("\\", .command))
        #expect(MenuBarCatalogue[.splitDown].key == MenuShortcut("\\", .command, .shift))
    }

    @Test("the once-in-a-workspace items take no key")
    func theItemsWithNoKey() {
        for action in [MenuBarAction.pin, .unreadMark, .colour, .copyName, .renameTab, .focusPane] {
            #expect(MenuBarCatalogue[action].key == nil, "\(action)")
        }
    }
}
