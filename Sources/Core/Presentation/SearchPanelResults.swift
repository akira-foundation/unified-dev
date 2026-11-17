import Foundation

public enum SearchPanelResults {
    public static func build(
        query: String,
        repos: [Repo],
        workspaces: [Workspace],
        archived: [Workspace],
        transcripts: [TranscriptWorkspaceMatches],
        scope: HomeScope,
        commands: [MenuBarItem] = MenuBarCatalogue.commands,
        profiles: [Profile] = [],
        activeProfile: ProfileID = .initial,
        reach: SearchPanelReach = .live
    ) -> SearchPanelListing {
        let needle = WorkspaceSearch.needle(query)
        guard !needle.isEmpty else { return .empty }

        var byID: [RepoID: Repo] = [:]
        byID.reserveCapacity(repos.count)
        for repo in repos { byID[repo.id] = repo }

        let reachable = Set(reach.projects(repos).map(\.id))

        var counts = HomeScopeCounts()
        var live: [SearchPanelWorkspaceHit] = []
        live.reserveCapacity(workspaces.count)
        var finished: [SearchPanelWorkspaceHit] = []

        func consider(_ workspace: Workspace, isArchived: Bool) {
            let repo = byID[workspace.repoID]
            guard reachable.contains(workspace.repoID) else { return }
            let hit = FuzzyMatch.hit(workspace.name, query: needle)
            let field = WorkspaceSearch.match(workspace: workspace, repo: repo, needle: needle)
            guard hit != nil || field != nil else { return }
            let found = SearchPanelWorkspaceHit(
                workspace: workspace,
                repo: repo,
                highlights: hit?.positions ?? [],
                match: hit == nil && field != workspace.name ? field : nil,
                isArchived: isArchived,
                score: hit?.score ?? 0
            )
            if isArchived {
                finished.append(found)
                counts.archived += 1
            } else {
                live.append(found)
                counts.live += 1
            }
        }

        for workspace in workspaces { consider(workspace, isArchived: false) }
        for workspace in archived { consider(workspace, isArchived: true) }
        counts.workspaces = live.count

        let archivedIDs = Set(archived.map(\.id))
        let known = Set(workspaces.map(\.id)).union(archivedIDs)
        let repoOf: (WorkspaceID) -> RepoID? = { id in
            (workspaces.first { $0.id == id } ?? archived.first { $0.id == id })?.repoID
        }
        let hits = transcripts.filter { result in
            guard known.contains(result.workspaceID) else { return false }
            guard let repoID = repoOf(result.workspaceID) else { return false }
            return reachable.contains(repoID)
        }
        var archivedWorkspaces = Set(finished.map(\.id))
        for hit in hits {
            if archivedIDs.contains(hit.workspaceID) {
                counts.archived += hit.total
                archivedWorkspaces.insert(hit.workspaceID)
            } else {
                counts.transcripts += hit.total
                counts.transcriptWorkspaces += 1
            }
        }

        let matched = reach.archived ? live + finished : live
        let shownWorkspaces = matched
            .filter { hit in
                scope.showsWorkspaces && scope.includes(
                    HomeRow(workspace: hit.workspace, repo: hit.repo), activity: HomeActivity()
                )
            }
            .sorted { left, right in
                if left.score != right.score { return left.score > right.score }
                return left.workspace.lastActivityAt > right.workspace.lastActivityAt
            }

        let shownTranscripts = hits
            .filter { result in
                let isArchived = archivedIDs.contains(result.workspaceID)
                guard reach.archived || !isArchived else { return false }
                return scope.includesTranscript(isArchived: isArchived)
            }
            .map { result in
                let workspace = workspaces.first { $0.id == result.workspaceID }
                    ?? archived.first { $0.id == result.workspaceID }
                return SearchPanelTranscriptHit(
                    result: result,
                    workspace: workspace,
                    repo: workspace.flatMap { byID[$0.repoID] },
                    isArchived: archivedIDs.contains(result.workspaceID)
                )
            }

        let shownCommands = inlineCommands(needle, scope: scope, commands: commands)
        let matchedProfiles = SearchPanelProfiles.hits(needle, in: profiles, active: activeProfile)
        counts.profiles = matchedProfiles.count
        let shownProfiles = scope == .all ? matchedProfiles : []

        var sections: [SearchPanelSection] = []
        if !shownWorkspaces.isEmpty {
            sections.append(
                SearchPanelSection(
                    id: "workspaces", title: "Workspaces",
                    rows: shownWorkspaces.map { .workspace($0) }
                )
            )
        }
        if !shownProfiles.isEmpty {
            let section = SearchPanelSection(
                id: "profiles", title: "Profiles",
                rows: shownProfiles.map { .profile($0) }
            )
            let leads = SearchPanelProfiles.lead(shownProfiles, over: shownWorkspaces)
            sections.insert(section, at: leads ? 0 : sections.count)
        }
        if !shownCommands.isEmpty {
            sections.append(
                SearchPanelSection(
                    id: "commands", title: "Commands",
                    rows: shownCommands.map { .command($0) }
                )
            )
        }
        if !shownTranscripts.isEmpty {
            sections.append(
                SearchPanelSection(
                    id: "transcripts", title: "Transcripts",
                    rows: shownTranscripts.map { .transcript($0) }
                )
            )
        }

        return SearchPanelListing(
            sections: sections,
            counts: counts,
            isSearching: true,
            summary: SearchPanelSummary.searching(scope: scope, counts: counts),
            nothing: sections.isEmpty
                ? nothing(
                    query,
                    archived: archivedWorkspaces.count,
                    hidden: ProjectVisibility.hiddenCount(repos),
                    reach: reach
                )
                : nil
        )
    }

    private static func nothing(
        _ query: String, archived: Int, hidden: Int, reach: SearchPanelReach
    ) -> SearchPanelNothing {
        if !reach.archived, archived > 0 { return .noLiveMatch(query, archived: archived) }
        if !reach.hidden, hidden > 0 { return .noHiddenMatch(query, hidden: hidden) }
        return .noMatch(query)
    }

    private static func inlineCommands(
        _ needle: String, scope: HomeScope, commands: [MenuBarItem]
    ) -> [SearchPanelCommandHit] {
        guard scope == .all, needle.count >= SearchPanelCommands.inlineMinimumQueryLength else {
            return []
        }
        return Array(SearchPanelCommands.rank(needle, in: commands).prefix(SearchPanelCommands.inlineLimit))
    }
}
