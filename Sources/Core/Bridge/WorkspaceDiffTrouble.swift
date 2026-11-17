import Foundation

public enum WorkspaceDiffTrouble: Error, Sendable, Equatable {
    case target(BridgeReadTrouble)
    case worktreeGone(workspaceID: WorkspaceID)
    case pathNotText
    case noSuchPath(String, workspaceID: WorkspaceID)
    case fileTooLarge(String, lines: Int)
    case badCursor
    case staleCursor
    case gitFailed(workspaceID: WorkspaceID, String)
    case unexplained(String)

    public var sentence: String {
        switch self {
        case .target(let trouble):
            return trouble.sentence(tool: WorkspaceDiffTool.name)

        case .worktreeGone(let workspaceID):
            return """
                The worktree of the workspace with the id '\(workspaceID.rawValue)' is no longer on \
                disk, so there are no changes to read. Retrying will not help; the owner can restore \
                or archive it in Unified Dev.
                """

        case .pathNotText:
            return "workspace_diff takes 'path' as a string naming one changed file. Leave it out for every file."

        case let .noSuchPath(path, workspaceID):
            return """
                '\(path)' is not among the files changed in the workspace with the id \
                '\(workspaceID.rawValue)'. Call workspace_diff without 'path' and pass a path from \
                its file list.
                """

        case let .fileTooLarge(path, lines):
            return """
                '\(path)' changes \(lines) lines, more than the \(WorkspaceDiffBudget.lineLimit) \
                workspace_diff reads in one file, so its diff is left out. Its counts are in the \
                file list workspace_diff gives without 'path'.
                """

        case .badCursor:
            return "'cursor' must be a next_cursor returned for this workspace. Omit it to start again."

        case .staleCursor:
            return """
                That cursor does not match these changes: it was returned for another path, or the \
                workspace's changes have moved since. Omit 'cursor' to read them from the start.
                """

        case let .gitFailed(workspaceID, message):
            return """
                Unified Dev could not read the changes in the workspace with the id \
                '\(workspaceID.rawValue)' from git: \(message)
                """

        case .unexplained(let message):
            return "Unified Dev could not complete workspace_diff: \(message)"
        }
    }

    var sentenceAcrossProfiles: String {
        guard case .gitFailed(let workspaceID, _) = self else { return sentence }
        return "Unified Dev could not read the changes in the workspace with the id '\(workspaceID.rawValue)' from git."
    }
}
