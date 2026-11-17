import Foundation

public enum MessageMenuAction: Equatable, Hashable, Sendable {
    case copy
    case copyMessage
    case copyMessageAsMarkdown
    case attachSelection
    case pinChapter
    case unpinChapter
    case forkFromHere

    public var title: String {
        switch self {
        case .copy: "Copy"
        case .copyMessage: "Copy message"
        case .copyMessageAsMarkdown: "Copy message as Markdown"
        case .attachSelection: "Attach selection as context"
        case .pinChapter: "Pin as chapter"
        case .unpinChapter: "Unpin chapter"
        case .forkFromHere: "Fork from here"
        }
    }

    public var keyEquivalent: String {
        switch self {
        case .copy: "c"
        case .attachSelection: "l"
        case .copyMessage, .copyMessageAsMarkdown, .pinChapter, .unpinChapter, .forkFromHere: ""
        }
    }

    public var needsShift: Bool { self == .attachSelection }
}

public struct MessageMenuItem: Equatable, Sendable {
    public var action: MessageMenuAction
    public var isEnabled: Bool

    public init(_ action: MessageMenuAction, isEnabled: Bool) {
        self.action = action
        self.isEnabled = isEnabled
    }
}

public struct MessageMenuContext: Equatable, Sendable {
    public var hasSelection: Bool
    public var hasText: Bool
    public var isChapter: Bool
    public var canFork: Bool

    public init(hasSelection: Bool, hasText: Bool, isChapter: Bool, canFork: Bool) {
        self.hasSelection = hasSelection
        self.hasText = hasText
        self.isChapter = isChapter
        self.canFork = canFork
    }
}

public enum MessageMenu {
    public static func sections(for context: MessageMenuContext) -> [[MessageMenuItem]] {
        var chapterAndFork = [
            MessageMenuItem(context.isChapter ? .unpinChapter : .pinChapter, isEnabled: context.isChapter || context.hasText),
        ]
        if context.canFork { chapterAndFork.append(MessageMenuItem(.forkFromHere, isEnabled: true)) }
        return [
            [MessageMenuItem(.copy, isEnabled: context.hasSelection)],
            [
                MessageMenuItem(.copyMessage, isEnabled: context.hasText),
                MessageMenuItem(.copyMessageAsMarkdown, isEnabled: context.hasText),
            ],
            [MessageMenuItem(.attachSelection, isEnabled: context.hasSelection)],
            chapterAndFork,
        ]
    }

    public static func forkTitle(of title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Fork" : "\(trimmed) (fork)"
    }
}
