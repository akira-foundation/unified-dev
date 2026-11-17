import Foundation

public enum WorkSuggestionCard {
    public static let heading = "Suggested work"

    public enum Action: String, Sendable, Hashable {
        case newWorkspace
        case here
        case addProjectAndStart
        case startOrchestrator
        case dismiss

        public var choice: WorkSuggestionLaunch.Choice? {
            switch self {
            case .newWorkspace, .addProjectAndStart, .startOrchestrator: .newWorkspace
            case .here: .here
            case .dismiss: nil
            }
        }
    }

    public struct Offer: Sendable, Hashable {
        public let action: Action
        public let title: String
        public let accessibilityLabel: String
        public let isProminent: Bool
    }

    public struct Context: Sendable, Hashable {
        public var projectName: String
        public var workspaceName: String?
        public var projectIsHidden: Bool
        public var chatIsSubagent: Bool
        public var workspaceWasStartedByAnAgent: Bool

        public init(
            projectName: String,
            workspaceName: String?,
            projectIsHidden: Bool = false,
            chatIsSubagent: Bool = false,
            workspaceWasStartedByAnAgent: Bool = false
        ) {
            self.projectName = projectName
            self.workspaceName = workspaceName
            self.projectIsHidden = projectIsHidden
            self.chatIsSubagent = chatIsSubagent
            self.workspaceWasStartedByAnAgent = workspaceWasStartedByAnAgent
        }
    }

    public enum OpenTarget: Sendable, Hashable {
        case workspace(WorkspaceID)
        case session(SessionID)
    }

    public static func offers(for suggestion: WorkSuggestion, in context: Context) -> [Offer] {
        guard suggestion.state == .pending else { return [] }
        let dismiss = Offer(
            action: .dismiss, title: "Dismiss",
            accessibilityLabel: "Dismiss the suggestion \(suggestion.title)", isProminent: false
        )
        switch suggestion.target {
        case .sameProject, .project:
            var offers: [Offer] = context.workspaceWasStartedByAnAgent ? [] : [Offer(
                action: .newWorkspace, title: "New Workspace",
                accessibilityLabel: "Start as a new workspace in \(context.projectName)", isProminent: true
            )]
            if suggestion.target == .sameProject, let workspace = context.workspaceName, !context.chatIsSubagent {
                offers.append(Offer(
                    action: .here, title: "Here",
                    accessibilityLabel: "Start here, as a subagent in \(workspace)",
                    isProminent: context.workspaceWasStartedByAnAgent
                ))
            }
            return offers + [dismiss]
        case .folder:
            guard !context.workspaceWasStartedByAnAgent else { return [dismiss] }
            return [
                Offer(
                    action: .addProjectAndStart, title: "Add Project and Start",
                    accessibilityLabel: "Add \(context.projectName) as a project and start a new workspace in it",
                    isProminent: true
                ),
                dismiss,
            ]
        case .remote:
            return [dismiss]
        case .orchestrator:
            return [
                Offer(
                    action: .startOrchestrator, title: "Start Orchestrator",
                    accessibilityLabel: "Start an orchestrator in \(context.projectName) and deliver the message to it",
                    isProminent: true
                ),
                dismiss,
            ]
        }
    }

    public static func opensAsDraft(_ suggestion: WorkSuggestion) -> Bool {
        guard suggestion.state == .pending else { return false }
        switch suggestion.target {
        case .sameProject, .project: return true
        case .folder, .remote, .orchestrator: return false
        }
    }

    public static func targetLine(for suggestion: WorkSuggestion, in context: Context) -> String? {
        switch suggestion.target {
        case .sameProject:
            context.projectIsHidden
                ? "In \(context.projectName), which is hidden from the sidebar. A new workspace brings the project back."
                : nil
        case .project:
            context.projectIsHidden
                ? "In \(context.projectName), which is hidden from the sidebar. Starting it brings the project back."
                : "In \(context.projectName)"
        case .folder(let path):
            "In \(path), which is not in Unified Dev yet. Starting it adds the folder as a project first."
        case .remote(let slug):
            WorkSuggestionWording.cloneFirst(slug)
        case .orchestrator:
            WorkSuggestionWording.awaitsOrchestrator(context.projectName)
        }
    }

    public static func statusLine(for suggestion: WorkSuggestion) -> String? {
        switch suggestion.state {
        case .pending: suggestion.failure
        case .starting: "Starting"
        case .startedWorkspace(_, let name), .startedHere(_, let name): "Started as \(name)"
        case .dismissed: "Dismissed"
        case .withdrawn: WorkSuggestionWording.withdrawn
        }
    }

    public static func openTarget(for suggestion: WorkSuggestion) -> OpenTarget? {
        switch suggestion.state {
        case .startedWorkspace(let workspaceID, _):
            .workspace(workspaceID)
        case .startedHere(let sessionID, _):
            sessionID.rawValue.isEmpty ? nil : .session(sessionID)
        case .pending, .starting, .dismissed, .withdrawn:
            nil
        }
    }

    public static func accessibilityLabel(for suggestion: WorkSuggestion) -> String {
        "\(heading(for: suggestion)): \(suggestion.title)"
    }

    public static func heading(for suggestion: WorkSuggestion) -> String {
        guard case .orchestrator = suggestion.target else { return heading }
        return "Message waiting for an orchestrator"
    }

    public static func promptLabel(for suggestion: WorkSuggestion) -> String {
        guard case .orchestrator = suggestion.target else { return "Prompt" }
        return "Message"
    }
}
