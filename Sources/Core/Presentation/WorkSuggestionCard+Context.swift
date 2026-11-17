import Foundation

extension WorkSuggestionCard.Context {
    public static func of(
        _ suggestion: WorkSuggestion,
        workspaces: [Workspace],
        repos: [Repo],
        chatIsSubagent: Bool
    ) -> Self {
        let workspace = suggestion.workspaceID.flatMap { id in workspaces.first { $0.id == id } }
        let project = WorkSuggestionCard.project(of: suggestion, workspaces: workspaces, repos: repos)
        let name = switch suggestion.target {
        case .sameProject: project?.name ?? "this project"
        case .project: project?.name ?? "a project no longer in Unified Dev"
        case .folder(let path): URL(fileURLWithPath: path).lastPathComponent
        case .remote(let slug): slug
        case .orchestrator: project?.name ?? "a project no longer in Unified Dev"
        }
        return Self(
            projectName: name,
            workspaceName: workspace?.name,
            projectIsHidden: project?.hidden ?? false,
            chatIsSubagent: chatIsSubagent,
            workspaceWasStartedByAnAgent: workspace?.origin.isAgentSpawned ?? false
        )
    }
}

extension WorkSuggestionCard {
    public static func project(of suggestion: WorkSuggestion, workspaces: [Workspace], repos: [Repo]) -> Repo? {
        let repoID: RepoID? = switch suggestion.target {
        case .sameProject: suggestion.workspaceID.flatMap { id in workspaces.first { $0.id == id }?.repoID }
        case .project(let id), .orchestrator(let id): id
        case .folder, .remote: nil
        }
        guard let repoID else { return nil }
        return repos.first { $0.id == repoID }
    }

    public static func draftProject(for suggestion: WorkSuggestion, workspaces: [Workspace], repos: [Repo]) -> Repo? {
        guard opensAsDraft(suggestion) else { return nil }
        return project(of: suggestion, workspaces: workspaces, repos: repos)
    }
}
