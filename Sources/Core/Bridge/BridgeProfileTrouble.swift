import Foundation

public enum BridgeProfileTrouble: Error, Sendable, Equatable {
    case notText
    case unreachable(given: String)
    case ownProfileClosed(own: String)
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
                This connection cannot reach a profile called '\(WorkspaceMessage.oneLine(given))'. \
                Unified Dev does not say whether one exists: either no profile has that name, or the owner \
                has not opened it to the others. Retrying will not change that.
                """

        case .ownProfileClosed(let own):
            return """
                This chat cannot reach any other profile, because its own profile, \
                '\(WorkspaceMessage.oneLine(own))', is not open to the others. The owner opens it in that \
                profile's settings, and both sides must be open. Tell the owner what you wanted to do there. \
                Retrying will not change that.
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
                This chat cannot reach any other profile: only a chat on Claude Code, or a project's \
                orchestrator on Grok, can, and never a chat on Codex. Tell the owner what you wanted to do \
                there. Retrying will not change that.
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
                The orchestrators in the profile '\(WorkspaceMessage.oneLine(given))' do not accept messages \
                from outside it: the owner has not opened it to other profiles. Tell the owner what you \
                wanted to send there. Retrying will not change that.
                """
        }
    }
}
