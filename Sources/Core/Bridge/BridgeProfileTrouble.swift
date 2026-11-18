import Foundation

public enum BridgeProfileTrouble: Error, Sendable, Equatable {
    case notText
    case unreachable(given: String)
    case launchedUnasked
    case agentConfined
    case ambiguous(given: String, ids: [String])
    case readsGoThroughOrchestrator(given: String)
    case closedToOutside(given: String)

    public var sentence: String {
        switch self {
        case .notText:
            return "'profile' takes a string: a profile's id, or a name no other profile shares."

        case .unreachable(let given):
            return """
                No open profile this connection can reach is called '\(WorkspaceMessage.oneLine(given))'. \
                A profile can be reached only once the owner opens it to the others, in that profile's own \
                settings, so ask the owner to open the one you need. profile_list names the ones open to you. \
                Unified Dev does not say whether a closed profile by that name exists, and retrying will not \
                change that.
                """

        case .launchedUnasked:
            return """
                This chat cannot reach any other profile, because it runs in a mode that does not ask the \
                owner before a tool call. A workspace reaches another profile only from a chat launched in \
                Accept edits, where the owner approves each call. Tell the owner what you wanted to do there, \
                or ask them to switch this chat's mode; the change applies from its next message.
                """

        case .agentConfined:
            return """
                This chat cannot reach any other profile: only a chat on Claude Code in an active workspace, \
                or a project's orchestrator on Grok, can, and never a chat on Codex. Tell the owner what you \
                wanted to do there. Retrying will not change that.
                """

        case let .ambiguous(given, ids):
            return """
                More than one profile is called '\(WorkspaceMessage.oneLine(given))', so Unified Dev \
                will not guess which you meant. Pass one of these ids instead: \
                \(BridgeWorkspaceLookup.list(ids)).
                """

        case .readsGoThroughOrchestrator(let given):
            return """
                Reading chats and diffs in the profile '\(WorkspaceMessage.oneLine(given))' is left to its \
                projects' orchestrators. Ask the orchestrator of the project you need with workspace_say, \
                naming that profile and the project, and it can read what you need and answer.
                """

        case .closedToOutside(let given):
            return """
                The profile '\(WorkspaceMessage.oneLine(given))' is not open to other profiles, so this \
                message cannot be delivered there. Turn on Reachable from other profiles in that profile's \
                settings and press again, or leave the message waiting.
                """
        }
    }
}
