import Foundation

public enum CodeBlockLaunch: Sendable, Equatable {
    case runs
    case asks(CodeBlockConfirmation)

    public static func of(_ command: String, in folder: String, orchestrates: Bool) -> CodeBlockLaunch {
        guard orchestrates, !OrchestratorShellJudge.reads(command) else { return .runs }
        return .asks(CodeBlockConfirmation(command: command, folder: folder))
    }
}

public enum CodeBlockAnswer: Sendable, Equatable {
    case run(command: String, folder: String)
    case nothing
    case refused(String)
}

public struct CodeBlockConfirmation: Sendable, Equatable {
    public let command: String
    public let folder: String

    public static let title = "Run this command?"
    public static let confirmLabel = "Run"
    public static let cancelLabel = "Cancel"
    static let closedChat = "the chat closed or stopped accepting messages while it waited"

    public var message: String {
        let hidden = CodeBlockVisibleText.hiddenCount(in: command) + CodeBlockVisibleText.hiddenCount(in: folder)
        let warning = "It is not on the list of commands that only read, so it may change files."
        let lines = [
            CodeBlockVisibleText.shown(command),
            "",
            "It runs in \(CodeBlockVisibleText.shown(folder)). \(warning)",
        ]
        guard hidden > 0 else { return lines.joined(separator: "\n") }
        let noun = hidden == 1 ? "character" : "characters"
        return (lines + ["", "It holds \(hidden) invisible \(noun), shown above as [U+code]."]).joined(separator: "\n")
    }

    public func answer(confirmed: Bool, chatAccepts: Bool) -> CodeBlockAnswer {
        guard confirmed else { return .nothing }
        guard chatAccepts else { return .refused(Self.closedChat) }
        return .run(command: command, folder: folder)
    }
}
