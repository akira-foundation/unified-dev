import Foundation

public enum BridgeProfileTrouble: Error, Sendable, Equatable {
    case notText
    case unreachable(given: String)
    case ambiguous(given: String, ids: [String])
    case readsGoThroughOrchestrator(given: String)
    case closedToOutside(given: String)
    case asksNobody(given: String)

    public var sentence: String {
        switch self {
        case .notText:
            return "'profile' takes a string: a profile's id, or a name no other profile shares."

        case .unreachable(let given):
            return """
                This connection cannot reach a profile called '\(WorkspaceMessage.oneLine(given))'. \
                Unified Dev does not say whether one exists. Retrying will not change that.
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

        case .asksNobody(let given):
            return """
                This chat cannot reach the profile '\(WorkspaceMessage.oneLine(given))', because it runs in a \
                mode that does not ask the owner before a tool call. A workspace reaches another profile only \
                from a chat launched in Accept edits, where the owner approves each call. Tell the owner what \
                you wanted to send there, or ask them to switch this chat's mode.
                """
        }
    }
}
