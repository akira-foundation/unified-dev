import Foundation

public enum WorkspaceSayTrouble: Error, Sendable, Equatable {
    case noMessage
    case tooLong(count: Int)
    case noWorkspace
    case unknown(given: String, known: [String])
    case ambiguous(given: String, ids: [String])
    case archived(name: String)
    case toItself
    case callerHasGone
    case repeated(workspace: String)
    case tooMany(workspace: String, count: Int)
    case appRefused(String)
    case onlyOrchestrators(given: String)
    case workspaceAndProject
    case unknownProject(given: String)
    case noChatForCard
    case cardsFull(undecided: Int)
    case unexplained(String)

    public var sentence: String {
        switch self {
        case .noMessage:
            return "workspace_say needs a 'message' to send and it cannot be blank."

        case .tooLong(let count):
            return """
                That message is \(count) characters and workspace_say takes up to \
                \(WorkspaceSayTool.maximumLength). Send the other agent what it needs to act on, \
                and point it at files in its own worktree for the rest.
                """

        case .noWorkspace:
            return """
                workspace_say needs the 'workspace' to send it to. Call workspace_list and pass the \
                id it reports, or pass the id named in the message you are answering.
                """

        case let .unknown(given, known):
            return BridgeWorkspaceLookup.unknown(given, known: known)

        case let .ambiguous(given, ids):
            return BridgeWorkspaceLookup.ambiguous(given, ids: ids)

        case .archived(let name):
            return """
                The workspace "\(WorkspaceMessage.oneLine(name))" has been archived, so there is no agent there to send it \
                to. Retrying will not change that.
                """

        case .toItself:
            return """
                That is the workspace you are in. workspace_say is for another workspace; to talk \
                to a subagent in this one, use agent_say.
                """

        case .callerHasGone:
            return """
                Unified Dev no longer has the workspace this connection speaks for, so it cannot say \
                where a message from it came from. Its row has gone, which retrying will not undo.
                """

        case .repeated(let workspace):
            return """
                You already sent exactly that message to "\(WorkspaceMessage.oneLine(workspace))" in the last \
                \(WorkspaceSayThrottle.windowMinutes) minutes, so Unified Dev did not send it again. \
                Do not retry. Wait for the answer, which lands in this chat, or tell the owner if \
                you are stuck.
                """

        case let .tooMany(workspace, count):
            return """
                You have sent \(count) messages to "\(WorkspaceMessage.oneLine(workspace))" in the last \
                \(WorkspaceSayThrottle.windowMinutes) minutes, which is as many as Unified Dev lets \
                one workspace send another, so this one was not sent. Two agents answering each \
                other is a loop that spends a turn on both sides every round. Do not retry and do \
                not acknowledge: wait for the answer you are owed, or tell the owner what you need.
                """

        case .appRefused(let sentence):
            return "Unified Dev did not deliver it: \(sentence)"

        case .onlyOrchestrators(let given):
            return """
                From this workspace, another profile is reached through its projects' orchestrators, and \
                none of them there is called '\(WorkspaceMessage.oneLine(given))'. Call workspace_list with the \
                same profile for their ids, or pass project instead of workspace to reach that project's \
                orchestrator, and the owner is asked to start one if it has none.
                """

        case .workspaceAndProject:
            return """
                Pass workspace or project, not both: workspace names the agent to send it to, and project \
                sends it to that project's orchestrator.
                """

        case .unknownProject(let given):
            return """
                No project called '\(WorkspaceMessage.oneLine(given))' can be reached there, or the name is \
                shared. Call project_list with the same profile for its ids.
                """

        case .noChatForCard:
            return """
                That project has no orchestrator, and this connection is not a chat, so there is nowhere \
                to show the owner a card asking to start one. Ask the owner to start it.
                """

        case .cardsFull(let undecided):
            return """
                That project has no orchestrator, and the owner already has \(undecided) cards from here \
                waiting for a decision, so Unified Dev did not add another. Wait for the owner, or \
                withdraw one with work_withdraw.
                """

        case .unexplained(let message):
            return "Unified Dev could not complete workspace_say: \(message)"
        }
    }
}
