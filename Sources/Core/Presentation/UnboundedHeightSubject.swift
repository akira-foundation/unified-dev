public enum UnboundedHeightVerdict: String, Equatable, Sendable, CaseIterable, Codable {
    case emptiesTheWindow
    case drawsAnyway
    case neverWraps
    case unmeasured

    public var blocksRelease: Bool { self == .emptiesTheWindow }
}

public struct UnboundedHeightSubject: Equatable, Sendable, Identifiable, Codable {
    public enum Host: String, Equatable, Sendable, CaseIterable, Codable {
        case mainWindow
        case sheet
        case settingsWindow
        case menuBarPanel
        case welcomeWindow
        case hoverPanel
        case composerPopover
    }

    public let key: String

    public let file: String

    public let line: Int

    public let host: Host

    public let path: String

    public init(key: String, file: String, line: Int, host: Host, path: String) {
        self.key = key
        self.file = file
        self.line = line
        self.host = host
        self.path = path
    }

    public var id: String { key }

    public static func verdict(
        comparison: HeightComparison, read: Bool, escaped: Bool
    ) -> UnboundedHeightVerdict {
        guard comparison.wasStaged, read else { return .unmeasured }
        if escaped { return .emptiesTheWindow }
        return comparison.wraps ? .drawsAnyway : .neverWraps
    }

    public var json: JSONValue {
        .object([
            "key": .string(key),
            "file": .string(file),
            "line": .integer(line),
            "host": .string(host.rawValue),
            "path": .string(path),
        ])
    }
}

public extension UnboundedHeightSubject {
    static let all: [UnboundedHeightSubject] = [
        UnboundedHeightSubject(
            key: "inspector-notice",
            file: "Sources/UnifiedDev/Views/Inspector/InspectorNotice.swift",
            line: 54,
            host: .mainWindow,
            path: "Open a workspace and let a pull request action fail: the inspector draws the "
                + "notice above the tabs, carrying whatever gh said."
        ),
        UnboundedHeightSubject(
            key: "agent-question-option",
            file: "Sources/UnifiedDev/Views/Transcript/AgentQuestionCard.swift",
            line: 220,
            host: .mainWindow,
            path: "Any question an agent asks whose option title is longer than the centre column."
        ),
        UnboundedHeightSubject(
            key: "attachment-comment",
            file: "Sources/UnifiedDev/Views/Center/Attachments/AttachmentCard.swift",
            line: 44,
            host: .mainWindow,
            path: "Capture a region of a page, comment on it, and hover the attachment in the "
                + "transcript: the card prints the comment."
        ),
        UnboundedHeightSubject(
            key: "browser-capture-comment",
            file: "Sources/UnifiedDev/Views/Center/Browser/BrowserRegionCaptureView.swift",
            line: 66,
            host: .mainWindow,
            path: "Capture a region of a page and select the comment left on it: the bar under the "
                + "page prints it."
        ),
        UnboundedHeightSubject(
            key: "start-project-consequence",
            file: "Sources/UnifiedDev/Views/Sidebar/StartProjectConsequenceBlock.swift",
            line: 24,
            host: .sheet,
            path: "Start a project and point it at a folder the app has something to say about: "
                + "the block under the field says what will happen."
        ),
        UnboundedHeightSubject(
            key: "quick-prompt-toggle",
            file: "Sources/UnifiedDev/Views/Center/Composer/QuickPromptForm.swift",
            line: 184,
            host: .composerPopover,
            path: "Open the composer's prompt list and edit a prompt: the two switches carry the "
                + "app's own labels."
        ),
        UnboundedHeightSubject(
            key: "prompt-settings-title",
            file: "Sources/UnifiedDev/Views/Chrome/Settings/PromptSettingsView.swift",
            line: 27,
            host: .settingsWindow,
            path: "Settings, Prompts: the list on the left carries the registry's own titles in a "
                + "column of fixed width."
        ),
        UnboundedHeightSubject(
            key: "notifications-blocked",
            file: "Sources/UnifiedDev/Views/Chrome/Settings/NotificationSettingsView.swift",
            line: 78,
            host: .settingsWindow,
            path: "Deny Unified Dev notifications in System Settings, then open Settings, "
                + "Notifications: the pane says macOS is blocking them."
        ),
        UnboundedHeightSubject(
            key: "approval-provenance",
            file: "Sources/UnifiedDev/Views/Chrome/Settings/ApprovalSettingsView.swift",
            line: 94,
            host: .settingsWindow,
            path: "Approve a command once, then open Settings, Permissions: each row says where "
                + "the grant came from."
        ),
        UnboundedHeightSubject(
            key: "menu-bar-provider-note",
            file: "Sources/UnifiedDev/Views/Chrome/MenuBar/Panel/MenuBarProviderModule.swift",
            line: 115,
            host: .menuBarPanel,
            path: "Sign out of an agent that reports usage, then open the menu bar panel: the reason "
                + "it gives for drawing no limits wraps beside Try again."
        ),
        UnboundedHeightSubject(
            key: "welcome-command",
            file: "Sources/UnifiedDev/Views/Chrome/Window/WelcomeCheckDetailStep.swift",
            line: 57,
            host: .welcomeWindow,
            path: "First launch with an agent CLI missing: the welcome step prints the command to "
                + "run and a button to copy it."
        ),
        UnboundedHeightSubject(
            key: "workspace-hover-title",
            file: "Sources/UnifiedDev/Views/Sidebar/WorkspaceHoverCardView.swift",
            line: 46,
            host: .hoverPanel,
            path: "Hover a workspace row whose name is longer than the card is wide."
        ),
    ]

    static let longSentence = "The worktree was removed when this was archived, and the branch it "
        + "stood on is still on the remote, so restoring it cuts a fresh worktree from that branch "
        + "and leaves the archive exactly as it is, with every chat it held still readable here and "
        + "nothing at all written back into the project it came from, which is the whole reason "
        + "this sentence has to be long enough to wrap in any column the window can offer it."
}
