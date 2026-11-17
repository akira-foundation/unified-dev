import Core

enum SidebarPaneRow: Identifiable, Equatable {
    case project(SidebarRepoGroup)
    case workspace(Workspace, projectName: String)
    case crew(CrewRow, workspaceID: WorkspaceID, repoID: RepoID)
    case subagent(SubagentRow, workspaceID: WorkspaceID, repoID: RepoID)
    case pending(PendingWorkspace)
    case statusHeading(SidebarStatusGroup, count: Int, isFolded: Bool)
    case notice(repoID: RepoID)
    case draft(RepoID)

    var id: String {
        switch self {
        case .project(let group): "project:" + group.id.rawValue
        case .workspace(let workspace, _): "workspace:" + workspace.id.rawValue
        case .crew(let row, _, _): "crew:" + row.id.rawValue
        case .subagent(let row, let workspaceID, _):
            "subagent:" + workspaceID.rawValue + ":" + row.id.rawValue
        case .pending(let pending): "workspace:" + pending.id.rawValue
        case .notice(let repoID): "notice:" + repoID.rawValue
        case .draft(let repoID): "draft:" + repoID.rawValue
        case .statusHeading(let group, _, _): "status:" + group.rawValue
        }
    }

    var identity: SidebarReorder.Row {
        switch self {
        case .project(let group): .project(group.id)
        case .workspace(let workspace, _): .workspace(id: workspace.id, projectID: workspace.repoID)
        case .crew(_, _, let repoID): .crew(projectID: repoID)
        case .subagent(_, _, let repoID): .subagent(projectID: repoID)
        case .pending(let pending): .pending(projectID: pending.repoID)
        case .notice(let repoID): .notice(projectID: repoID)
        case .draft(let repoID): .draft(projectID: repoID)
        case .statusHeading: .heading
        }
    }

    var drawnWorkspaceID: WorkspaceID? {
        if case .workspace(let workspace, _) = self { return workspace.id }
        return nil
    }

    static func rows(
        _ groups: [SidebarRepoGroup],
        crew: (WorkspaceID) -> [CrewRow] = { _ in [] },
        subagents: (WorkspaceID) -> [SubagentRow] = { _ in [] },
        pending: (RepoID) -> [PendingWorkspace] = { _ in [] },
        showsDraft: (RepoID) -> Bool = { _ in false }
    ) -> [SidebarPaneRow] {
        var rows: [SidebarPaneRow] = []
        for group in groups {
            rows.append(.project(group))
            let waiting = pending(group.id)
            for slot in WorkspaceDraftRows.slots(
                isCollapsed: group.repo.collapsed,
                workspaceCount: group.workspaces.count,
                pendingCount: waiting.count,
                showsDraft: showsDraft(group.id)
            ) {
                switch slot {
                case .workspaces:
                    for workspace in group.workspaces {
                        rows.append(.workspace(workspace, projectName: group.repo.name))
                        rows.append(contentsOf: crew(workspace.id).map {
                            .crew($0, workspaceID: workspace.id, repoID: group.id)
                        })
                        rows.append(contentsOf: subagents(workspace.id).map {
                            .subagent($0, workspaceID: workspace.id, repoID: group.id)
                        })
                    }
                case .pending:
                    rows.append(contentsOf: waiting.map { .pending($0) })
                case .draft:
                    rows.append(.draft(group.id))
                case .emptyNotice:
                    rows.append(.notice(repoID: group.id))
                }
            }
        }
        return rows
    }
}
