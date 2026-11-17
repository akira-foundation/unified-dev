import Foundation

public enum BridgeReadTrouble: Error, Sendable, Equatable {
    case notText
    case noWorkspaceNamed
    case unknown(given: String, known: [String])
    case ambiguous(given: String, ids: [String])
    case archived(given: String)
    case callerHasGone
    case callerArchived
    case profile(BridgeProfileTrouble)
    case profileNeedsWorkspace

    public func sentence(tool: String) -> String {
        switch self {
        case .notText:
            return "\(tool) takes 'workspace' as a string: a workspace id or name. Leave it out to read your own."

        case .noWorkspaceNamed:
            return """
                \(tool) needs to be told which workspace to read, because this connection is not \
                working in one. Pass 'workspace' with the id workspace_list reports, or a name no \
                other workspace shares.
                """

        case let .unknown(given, known):
            return BridgeWorkspaceLookup.unknown(given, known: known)

        case let .ambiguous(given, ids):
            return BridgeWorkspaceLookup.ambiguous(given, ids: ids)

        case .archived(let given):
            return """
                The workspace '\(given)' has been archived, so \(tool) has nothing there to read. \
                Retrying will not change that.
                """

        case .profile(let trouble):
            return trouble.sentence

        case .profileNeedsWorkspace:
            return "\(tool) needs 'workspace' as well when it is given 'profile': the id workspace_list reports for that profile."

        case .callerHasGone:
            return """
                Unified Dev no longer has the workspace this connection speaks for, so \(tool) has \
                nothing of its own to read. Its row has gone, which retrying will not undo.
                """

        case .callerArchived:
            return """
                The workspace this connection speaks for has been archived, so \(tool) has nothing \
                of its own to read. Pass 'workspace' to read another one.
                """
        }
    }
}
