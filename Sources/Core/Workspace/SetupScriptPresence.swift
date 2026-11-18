import Foundation

public struct SetupScriptPresence: Sendable, Hashable {
    private var repos: [RepoID: Bool] = [:]
    private var worktreesWithSubmodules: Set<WorkspaceID> = []

    public init() {}

    public static func read(
        repos: [Repo],
        workspaces: [Workspace],
        homePaths: [String] = SettingsLoader.homePaths()
    ) -> SetupScriptPresence {
        var presence = SetupScriptPresence()
        for repo in repos {
            let settings = SettingsLoader.load(repo: repo.path, homePaths: homePaths)
            presence.repos[repo.id] = settings.setupScript != nil
        }
        for workspace in workspaces where Git.hasSubmodules(in: workspace.path) {
            presence.worktreesWithSubmodules.insert(workspace.id)
        }
        return presence
    }

    public mutating func record(repoID: RepoID, hasSetupScript: Bool) {
        repos[repoID] = hasSetupScript
    }

    public func hasSetupScript(_ workspace: Workspace) -> Bool {
        guard let known = repos[workspace.repoID] else { return false }
        return Self.hasSetup(script: known, submodules: worktreesWithSubmodules.contains(workspace.id))
    }

    public static func hasSetup(script: Bool, submodules: Bool) -> Bool {
        script || submodules
    }
}
