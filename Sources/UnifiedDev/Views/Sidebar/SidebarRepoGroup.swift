import Core

struct SidebarRepoGroup: Identifiable, Equatable {
    var repo: Repo
    var workspaces: [Workspace]
    var hasUnreadWork: Bool

    var id: RepoID { repo.id }

    static func build(
        repos: [Repo],
        workspaces: [Workspace],
        filter: SidebarFilter,
        showingHidden: Bool
    ) -> [SidebarRepoGroup] {
        var byRepo: [RepoID: [Workspace]] = [:]
        for workspace in workspaces {
            byRepo[workspace.repoID, default: []].append(workspace)
        }

        return ProjectVisibility.listed(repos, showingHidden: showingHidden).map { repo in
            let all = byRepo[repo.id] ?? []
            let rows = SidebarReorder.drawn(all.filter(filter.accepts))
            return SidebarRepoGroup(
                repo: repo, workspaces: rows, hasUnreadWork: all.contains(where: \.unread)
            )
        }
    }
}
