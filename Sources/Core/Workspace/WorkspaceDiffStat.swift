import Foundation

public struct WorkspaceDiffStat: Sendable, Hashable {
    public var additions: Int
    public var deletions: Int
    public var files: Int

    public init(additions: Int, deletions: Int, files: Int) {
        self.additions = additions
        self.deletions = deletions
        self.files = files
    }

    public init(of workspace: Workspace) {
        self.init(
            additions: workspace.additions, deletions: workspace.deletions, files: workspace.changedFiles
        )
    }

    public func apply(to workspace: inout Workspace) {
        workspace.additions = additions
        workspace.deletions = deletions
        workspace.changedFiles = files
    }

    public static func changes(
        _ stats: [WorkspaceID: WorkspaceDiffStat], to workspaces: [Workspace]
    ) -> [WorkspaceID: WorkspaceDiffStat] {
        var moved: [WorkspaceID: WorkspaceDiffStat] = [:]
        for workspace in workspaces {
            guard let stat = stats[workspace.id], stat != WorkspaceDiffStat(of: workspace) else { continue }
            moved[workspace.id] = stat
        }
        return moved
    }
}
