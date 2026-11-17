import Foundation

public enum WorkSuggestionWording {
    public static let gone = "This suggestion is no longer in Unified Dev."

    public static let withdrawn = "Withdrawn by the agent"

    public static let hereElsewhere = """
        Here starts a subagent in the workspace the suggestion came from, so it only works for work \
        in that workspace's own project. Start it as a new workspace instead.
        """

    public static let anotherProfile = """
        That project belongs to another profile than the workspace this suggestion came from, so it \
        cannot start there.
        """

    public static func taken(_ state: WorkSuggestion.State) -> String {
        switch state {
        case .pending: "It is waiting for you again."
        case .starting: "It is already starting."
        case .startedWorkspace(_, let name), .startedHere(_, let name): "It has already started, as \(name)."
        case .dismissed: "It was dismissed."
        case .withdrawn: withdrawn
        }
    }

    public static func awaitsOrchestrator(_ project: String) -> String {
        """
        \(project) has no orchestrator, so nothing has received this message. Starting one makes a new \
        workspace there as its orchestrator and delivers the message to it, marked as coming from \
        this workspace. If the project gains an orchestrator first, the message goes to that one.
        """
    }

    public static let senderCannotCross = """
        The chat that left this message cannot reach other profiles any more: its own profile was closed \
        to them, its workspace was archived, or it no longer runs in a mode that asks you first. Nothing \
        was started.
        """

    public static func senderLeads(_ name: String) -> String {
        "\(WorkspaceMessage.oneLine(name)) left this message and is now that project's orchestrator itself, "
            + "so there is nobody else to deliver it to. Dismiss the card."
    }

    public static func orchestratorTitle(_ project: String) -> String {
        "A message for the orchestrator of \(WorkspaceMessage.oneLine(project))"
    }

    public static let orchestratorWhy = """
        This chat sent a message to a project with no orchestrator. Unified Dev does not start one \
        without you, so the message waits here.
        """

    public static func cloneFirst(_ slug: String) -> String {
        "\(slug) is only on GitHub. Clone it and add it as a project, and then it can be started from here."
    }

    public static func notARepository(_ path: String) -> String {
        """
        \(path) is not a git repository, and Unified Dev does not make one from a suggestion. Add it \
        with Add Project, which offers to set it up, and start the work from there.
        """
    }

    public static func insideRepository(_ path: String, root: String) -> String {
        """
        \(path) is a folder inside the repository at \(root), not a repository of its own, and Unified \
        Dev does not add the repository around it from a suggestion. If that repository is what you \
        meant, add it with Add Project and start the work from there.
        """
    }

    public static func ownSetup(_ root: String, _ setup: RepositoryOwnSetup) -> String {
        let reason = switch setup {
        case .hook(let name): "it has an executable git hook, \(name)"
        case .setting(let key): "its own git configuration sets \(key), which is beyond the plain settings git writes itself"
        case .unreadable(let message): "Unified Dev could not read its git configuration or hooks (\(message))"
        }
        return """
            Unified Dev does not add \(root) as a project from a suggestion, because \(reason). An agent \
            can set that up, so the choice is yours: if you trust this repository, add it yourself with \
            Add Project and start the work from there.
            """
    }

    public static func sentence(for refusal: LaunchRefusal) -> String {
        switch refusal {
        case .overAllowance(_, retry: .whenAWorkspaceIsArchived(let limit)):
            """
            The workspace that suggested this has reached its limit of \(limit) workspaces it started \
            that are not archived. Try again once enough of them are archived to bring it below \(limit).
            """
        case .overAllowance(_, retry: .after(let date)):
            """
            Unified Dev has started as many workspaces from outside a workspace as it does in \
            \(Int(WorkspaceStartAllowance.ownerWindow / 60)) minutes. Try again after \
            \(date.formatted(date: .omitted, time: .shortened)).
            """
        case .unavailable(let sentence), .failed(let sentence):
            sentence
        }
    }

    public static func sentence(for refusal: CrewLaunchRefusal) -> String {
        switch refusal {
        case .rule(.tooMany(let running)):
            """
            \(running) subagents are already running in this workspace, which is as many as Unified \
            Dev runs at once. Try again when one of them stops.
            """
        case .rule(.notAnOrchestrator):
            "This chat is itself a subagent, and a subagent cannot start one. Start it as a new workspace instead."
        case .rule(.nameTaken(let name)):
            "This workspace already has a subagent called \"\(name)\"."
        case .rule(.noName):
            "The suggestion has no title to name a subagent after."
        case .noTask:
            "The suggestion has no prompt to give the agent."
        case .unavailable(let message):
            "Unified Dev could not read this workspace's subagents: \(message)"
        case .refused(let sentence):
            sentence
        }
    }
}
