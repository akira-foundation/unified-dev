import Foundation

public enum MenuBarCatalogue {
    public static subscript(_ action: MenuBarAction) -> MenuBarItem {
        guard let item = byAction[action] else {
            preconditionFailure("no menu bar row for \(action)")
        }
        return item
    }

    public static func items(in menu: MenuBarMenu) -> [MenuBarItem] {
        commands.filter { $0.menu == menu }
    }

    private static let byAction: [MenuBarAction: MenuBarItem] = Dictionary(
        uniqueKeysWithValues: commands.map { ($0.action, $0) }
    )

    public static let commands: [MenuBarItem] = [

        MenuBarItem(.about, in: .unifieddev, "About Unified Dev"),
        MenuBarItem(.checkForUpdates, in: .unifieddev, "Check for Updates…", availability: .sometimes),

        MenuBarItem(.newWorkspace, in: .file, "New Workspace…", key: .command("n"), availability: .needsProject),
        MenuBarItem(.newWorkspaceFromPullRequest, in: .file, "New Workspace from Pull Request…", availability: .needsProject),
        MenuBarItem(.newAskConversation, in: .file, "New Ask Unified Dev Conversation", availability: .always),
        MenuBarItem(.newCanvas, in: .file, "New Canvas", availability: .needsWorkspace),
        MenuBarItem(.projectSettings, in: .file, "Project Settings…", key: .init("comma", .command, .shift), availability: .needsProject),
        MenuBarItem(.searchFiles, in: .file, "Search Files…", key: .command("p"), availability: .needsWorkspace),
        MenuBarItem(.newSession, in: .file, "New Session", key: .command("t"), availability: .needsConversationArea),
        MenuBarItem(.newTerminalTab, in: .file, "New Terminal Tab", key: .init("t", .command, .shift), availability: .needsWorkspace),
        MenuBarItem(.newBrowserTab, in: .file, "New Browser Tab", key: .init("b", .command, .shift), availability: .needsWorkspace),
        MenuBarItem(.showChanges, in: .file, "Show Changes", key: .init("d", .command, .shift), availability: .needsWorkspace),
        MenuBarItem(.reviewAllFiles, in: .file, "Review All Files", availability: .needsWorkspace),
        MenuBarItem(.showNotes, in: .file, "Show Notes", key: .init("n", .command, .shift), availability: .needsWorkspace),
        MenuBarItem(.renameTab, in: .file, "Rename Tab", availability: .needsTab),
        MenuBarItem(.closeTab, in: .file, "Close Tab", key: .command("w"), availability: .needsTab),
        MenuBarItem(.startProject, in: .file, "Start a Project…", key: .init("n", .command, .option)),
        MenuBarItem(.save, in: .file, "Save", key: .command("s"), availability: .sometimes),

        MenuBarItem(.find, in: .edit, "Find…", key: .command("f")),
        MenuBarItem(.findNext, in: .edit, "Find Next", key: .command("g")),
        MenuBarItem(.findPrevious, in: .edit, "Find Previous", key: .init("g", .command, .shift)),
        MenuBarItem(.quickSearch, in: .edit, "Quick Search…", key: .command("k")),
        MenuBarItem(.search, in: .edit, "Search", key: .init("f", .command, .shift), availability: .needsProject),

        MenuBarItem(.splitRight, in: .view, "Split Right", key: .command("\\"), keyOnSameAgainRow: true, availability: .needsSplittablePane),
        MenuBarItem(.splitDown, in: .view, "Split Down", key: .init("\\", .command, .shift), keyOnSameAgainRow: true, availability: .needsSplittablePane),
        MenuBarItem(.closePane, in: .view, "Close Pane", key: .init("w", .command, .control), availability: .needsWorkspace),
        MenuBarItem(.zoomPane, in: .view, "Zoom Pane", key: .init(.return, .command, .shift), availability: .needsTerminalPane),
        MenuBarItem(.focusPane, in: .view, "Focus Pane", availability: .needsTerminalPane),
        MenuBarItem(
            .previousTab, in: .view, "Previous Tab", key: .init("[", .command, .shift),
            alternateKey: .init(.tab, .option, .shift), availability: .needsSeveralTabs
        ),
        MenuBarItem(
            .nextTab, in: .view, "Next Tab", key: .init("]", .command, .shift),
            alternateKey: .init(.tab, .option), availability: .needsSeveralTabs
        ),
        MenuBarItem(.goToTab, in: .view, "Go to Tab", availability: .needsTab),
        MenuBarItem(.fileBack, in: .view, "Go Back in Files", alternateTitle: "Go Back", key: .init("[", .command), availability: .sometimes),
        MenuBarItem(.fileForward, in: .view, "Go Forward in Files", alternateTitle: "Go Forward", key: .init("]", .command), availability: .sometimes),
        MenuBarItem(.nextChangedFile, in: .view, "Next Changed File", key: .init("j", .command, .option), availability: .needsReview),
        MenuBarItem(.previousChangedFile, in: .view, "Previous Changed File", key: .init("k", .command, .option), availability: .needsReview),
        MenuBarItem(.browserReload, in: .view, "Reload Page", alternateTitle: "Stop Loading", key: .command("r"), availability: .needsBrowserPane),
        MenuBarItem(.browserResponsivePreview, in: .view, "Responsive Preview", key: .init("r", .command, .option), availability: .needsBrowserPane),
        MenuBarItem(.browserFullSize, in: .view, "Restore Full Browser Size", key: .init("0", .command, .option, .shift), availability: .needsBrowserPane),
        MenuBarItem(.browserScreenshot, in: .view, "Send a Screenshot to the Agent", key: .init("s", .command, .option), availability: .needsBrowserPane),
        MenuBarItem(.browserComment, in: .view, "Comment on an Area", alternateTitle: "Finish Reviewing Page", key: .init("c", .command, .option), availability: .needsBrowserPane),
        MenuBarItem(.browserOpenInDefaultBrowser, in: .view, "Open in Default Browser", key: .init("o", .command, .option), availability: .needsBrowserPane),
        MenuBarItem(.toggleSidebar, in: .view, "Toggle Sidebar", key: .init("s", .command, .control)),
        MenuBarItem(.toggleInspector, in: .view, "Hide Inspector", alternateTitle: "Show Inspector", key: .init("0", .command, .option)),
        MenuBarItem(.nextWorkspace, in: .view, "Next Workspace", key: .init(.downArrow, .command, .option), availability: .needsAnyWorkspace),
        MenuBarItem(.previousWorkspace, in: .view, "Previous Workspace", key: .init(.upArrow, .command, .option), availability: .needsAnyWorkspace),
        MenuBarItem(.nextUnread, in: .view, "Next Unread", key: .init("u", .command, .shift), availability: .sometimes),
        MenuBarItem(.goToHome, in: .view, "Go to Home", key: .init("h", .command, .shift), availability: .sometimes),
        MenuBarItem(.goToAsk, in: .view, "Go to Ask Unified Dev", availability: .sometimes),
        MenuBarItem(.zoomIn, in: .view, "Zoom In", key: .command("+"), availability: .sometimes),
        MenuBarItem(.zoomOut, in: .view, "Zoom Out", key: .command("-"), availability: .sometimes),
        MenuBarItem(.actualSize, in: .view, "Actual Size", key: .command("0"), availability: .sometimes),

        MenuBarItem(.renameWorkspace, in: .workspace, "Rename", availability: .needsWorkspaceSubject),
        MenuBarItem(.pin, in: .workspace, "Pin", alternateTitle: "Unpin", availability: .needsWorkspaceSubject),
        MenuBarItem(
            .unreadMark, in: .workspace, UnreadMarkAction.markUnread.title,
            alternateTitle: UnreadMarkAction.markRead.title, availability: .needsWorkspaceSubject
        ),
        MenuBarItem(.colour, in: .workspace, "Colour", availability: .needsWorkspaceSubject),
        MenuBarItem(.archive, in: .workspace, "Archive Workspace", key: .init(.delete, .command, .shift), availability: .needsWorkspaceSubject),
        MenuBarItem(.restore, in: .workspace, "Restore Workspace", availability: .needsWorkspaceSubject),
        MenuBarItem(.openInEditor, in: .workspace, "Open in Editor", key: .init("e", .command, .shift), availability: .needsWorkspaceSubject),
        MenuBarItem(.revealInFinder, in: .workspace, "Reveal in Finder", key: .init("r", .command, .shift), availability: .needsWorkspaceSubject),
        MenuBarItem(.copyName, in: .workspace, "Copy Name", availability: .needsWorkspaceSubject),
        MenuBarItem(.copyBranchName, in: .workspace, "Copy Branch Name", key: .init("c", .command, .shift), availability: .needsWorkspaceSubject),
        MenuBarItem(.runSetup, in: .workspace, "Run Setup", availability: .absentWhenUnavailable),
        MenuBarItem(.runScripts, in: .workspace, "Run", availability: .absentWhenUnavailable),
        MenuBarItem(.stopAgent, in: .workspace, "Stop Agent", key: .command("."), availability: .sometimes),

        MenuBarItem(.help, in: .help, "Unified Dev Help", key: .command("?")),
        MenuBarItem(.welcome, in: .help, "Welcome to Unified Dev…"),
        MenuBarItem(.sendFeedback, in: .help, "Send Feedback…", key: .init("f", .command, .option)),
        MenuBarItem(.submitPrompt, in: .help, "Submit a Prompt…"),
    ]
}

public enum MenuBarMenu: String, CaseIterable, Sendable {
    case unifieddev
    case file
    case edit
    case view
    case workspace
    case help
}

public enum MenuBarAction: String, CaseIterable, Sendable {
    case about
    case checkForUpdates

    case newWorkspace
    case newWorkspaceFromPullRequest
    case newAskConversation
    case newCanvas
    case projectSettings
    case newSession
    case newTerminalTab
    case newBrowserTab
    case showChanges
    case reviewAllFiles
    case showNotes
    case renameTab
    case closeTab
    case startProject
    case save

    case find
    case findNext
    case findPrevious
    case searchFiles
    case quickSearch
    case search

    case splitRight
    case splitDown
    case closePane
    case zoomPane
    case focusPane
    case previousTab
    case nextTab
    case goToTab
    case fileBack
    case fileForward
    case nextChangedFile
    case previousChangedFile
    case browserReload
    case browserResponsivePreview
    case browserFullSize
    case browserScreenshot
    case browserComment
    case browserOpenInDefaultBrowser
    case toggleSidebar
    case toggleInspector
    case nextWorkspace
    case previousWorkspace
    case nextUnread
    case goToHome
    case goToAsk
    case zoomIn
    case zoomOut
    case actualSize

    case renameWorkspace
    case pin
    case unreadMark
    case colour
    case archive
    case restore
    case openInEditor
    case revealInFinder
    case copyName
    case copyBranchName
    case runSetup
    case runScripts
    case stopAgent

    case help
    case welcome
    case sendFeedback
    case submitPrompt
}

public struct MenuBarItem: Equatable, Sendable, Identifiable {
    public var action: MenuBarAction
    public var menu: MenuBarMenu
    public var title: String
    public var alternateTitle: String?
    public var key: MenuShortcut?
    public var alternateKey: MenuShortcut?
    public var keyOnSameAgainRow: Bool
    public var availability: MenuBarAvailability

    public var id: MenuBarAction { action }

    init(
        _ action: MenuBarAction,
        in menu: MenuBarMenu,
        _ title: String,
        alternateTitle: String? = nil,
        key: MenuShortcut? = nil,
        alternateKey: MenuShortcut? = nil,
        keyOnSameAgainRow: Bool = false,
        availability: MenuBarAvailability = .always
    ) {
        self.action = action
        self.menu = menu
        self.title = title
        self.alternateTitle = alternateTitle
        self.key = key
        self.alternateKey = alternateKey
        self.keyOnSameAgainRow = keyOnSameAgainRow
        self.availability = availability
    }

    public func title(alternate isAlternate: Bool) -> String {
        isAlternate ? (alternateTitle ?? title) : title
    }
}

public enum MenuBarAvailability: String, Equatable, Sendable {
    case always
    case sometimes
    case needsProject
    case needsWorkspace
    case needsConversationArea
    case needsAnyWorkspace
    case needsWorkspaceSubject
    case needsTab
    case needsSeveralTabs
    case needsSplittablePane
    case needsTerminalPane
    case needsReview
    case needsBrowserPane
    case absentWhenUnavailable
}

public struct MenuShortcut: Equatable, Hashable, Sendable {
    public enum Trigger: Equatable, Hashable, Sendable {
        case character(Character)
        case upArrow
        case downArrow
        case leftArrow
        case rightArrow
        case delete
        case `return`
        case comma
        case tab
    }

    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }

    public var trigger: Trigger
    public var modifiers: Modifiers

    public init(_ trigger: Trigger, _ modifiers: Modifiers...) {
        self.trigger = trigger
        self.modifiers = modifiers.reduce(into: []) { $0.formUnion($1) }
    }

    public init(_ key: String, _ modifiers: Modifiers...) {
        if key == "comma" {
            self.trigger = .comma
        } else {
            precondition(key.count == 1, "a menu key is one character, or the word comma")
            self.trigger = .character(Character(key))
        }
        self.modifiers = modifiers.reduce(into: []) { $0.formUnion($1) }
    }

    public static func command(_ key: String) -> MenuShortcut {
        MenuShortcut(key, .command)
    }
}
