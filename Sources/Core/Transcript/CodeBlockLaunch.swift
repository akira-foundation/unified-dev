import Foundation

public enum CodeBlockLaunch: Sendable, Equatable {
    case runs
    case asks(CodeBlockConfirmation)

    public static func of(_ command: String, in folder: String, orchestrates: Bool) -> CodeBlockLaunch {
        guard orchestrates, !OrchestratorShellJudge.reads(command) else { return .runs }
        return .asks(CodeBlockConfirmation(command: command, folder: folder))
    }
}

public struct CodeBlockConfirmation: Sendable, Equatable {
    public let command: String
    public let folder: String

    public static let title = "Run this command?"
    public static let confirmLabel = "Run"
    public static let cancelLabel = "Cancel"

    public var message: String {
        command + "\n\nIt runs in \(folder). It is not on the list of commands that only read, so it may change files."
    }

    public func answer(confirmed: Bool) -> String? {
        confirmed ? command : nil
    }
}
