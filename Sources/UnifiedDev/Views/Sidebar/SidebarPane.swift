import Foundation
import Observation
import Core

@MainActor
@Observable
final class SidebarPane {
    struct Shape: Equatable {
        var grouping: SidebarGrouping
        var filter: SidebarFilter
        var showsHiddenProjects: Bool
    }

    struct ReorderNote: Equatable {
        var id = UUID()
        var sentence: String
    }

    private(set) var groups: [SidebarRepoGroup] = []
    private(set) var reposByID: [RepoID: Repo] = [:]
    private(set) var rows: [SidebarPaneRow] = []
    private(set) var workspaceIdentities: Set<WorkspaceID> = []
    private(set) var statusArrangement: [String] = []
    private(set) var foldedStatusGroups: Set<SidebarStatusGroup> = []
    private(set) var readingHold: WorkspaceID?
    private(set) var hasSettled = false
    private(set) var reorderNote: ReorderNote?
    var arrival = RowArrival<WorkspaceID>()

    var foldedProjects: [RepoID] {
        groups.filter(\.repo.collapsed).map(\.id)
    }

    var projectIdentities: Set<RepoID> {
        Set(groups.map(\.id))
    }

    var hiddenProjects: [RepoID] {
        groups.filter(\.repo.hidden).map(\.id)
    }

    func regroup(_ app: AppModel, shape: Shape, rescoped: Bool = false) {
        reposByID = Dictionary(app.profileRepos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        groups = SidebarRepoGroup.build(
            repos: app.profileRepos,
            workspaces: app.profileWorkspaces,
            filter: shape.filter,
            showingHidden: shape.showsHiddenProjects
        )
        reflow(app, shape: shape)
        let ids = groups.flatMap { $0.workspaces.map(\.id) } + app.pendingWorkspaces.map(\.id)
        workspaceIdentities = Set(ids)
        if rescoped {
            arrival.adopt(ids)
        } else {
            arrival.absorb(ids)
        }
    }

    func reshape(_ app: AppModel, shape: Shape) {
        foldedStatusGroups = []
        regroup(app, shape: shape, rescoped: true)
    }

    func reflow(_ app: AppModel, shape: Shape) {
        #if DEBUG
        ActivityTally.sidebarReflows += 1
        #endif
        switch shape.grouping {
        case .projects:
            adopt(arrangement: [])
            adopt(rows: SidebarPaneRow.rows(
                groups,
                crew: app.crew(of:),
                subagents: app.subagents(of:),
                pending: app.drawnPending(in:),
                showsDraft: app.showsDraft(in:)
            ))
        case .status:
            let listing = statusListing(app)
            adopt(arrangement: listing.arrangement)
            let folded = listing.folding(foldedStatusGroups)
            if foldedStatusGroups != folded { foldedStatusGroups = folded }
            let names = Dictionary(groups.map { ($0.id, $0.repo.name) }, uniquingKeysWith: { first, _ in first })
            adopt(rows: SidebarStatusRows.rows(
                listing: listing,
                projectName: { names[$0] ?? "" },
                folded: foldedStatusGroups,
                crew: app.crew(of:),
                subagents: app.subagents(of:)
            ))
        }
    }

    private func adopt(rows next: [SidebarPaneRow]) {
        guard rows != next else { return }
        rows = next
        #if DEBUG
        ActivityTally.sidebarRowWrites += 1
        #endif
    }

    private func adopt(arrangement next: [String]) {
        guard statusArrangement != next else { return }
        statusArrangement = next
    }

    func reflowStatus(_ app: AppModel, shape: Shape) {
        guard shape.grouping == .status else { return }
        reflow(app, shape: shape)
    }

    func toggleFold(_ group: SidebarStatusGroup, _ app: AppModel, shape: Shape) {
        if foldedStatusGroups.remove(group) == nil { foldedStatusGroups.insert(group) }
        reflow(app, shape: shape)
    }

    func follow(_ selection: SidebarSelection, _ app: AppModel, shape: Shape) {
        let hold = SidebarReadingHold.next(selection: selection, current: readingHold, workspaces: app.workspaces)
        guard hold != readingHold else { return }
        readingHold = hold
        reflowStatus(app, shape: shape)
    }

    func draws(_ workspaceID: WorkspaceID) -> Bool {
        rows.contains { $0.drawnWorkspaceID == workspaceID }
    }

    func move(from: IndexSet, to: Int, in app: AppModel) {
        switch SidebarReorder.destination(rows: rows.map(\.identity), from: from, to: to) {
        case .nothing:
            break

        case .project(let id, let offset):
            let visible = groups.map(\.id)
            Task { await app.reorderProjects(id: id, visible: visible, to: offset) }

        case .workspace(let projectID, let offsets, let offset, let landedOutside):
            guard let group = groups.first(where: { $0.id == projectID }) else { return }
            if landedOutside { note("Kept in \(group.repo.name)") }
            Task {
                await app.reorderWorkspaces(
                    in: group.repo, visible: group.workspaces, from: offsets, to: offset
                )
            }
        }
    }

    func settle(isLoaded: Bool) async {
        hasSettled = false
        guard isLoaded else { return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        hasSettled = true
    }

    func note(_ sentence: String) {
        reorderNote = ReorderNote(sentence: sentence)
    }

    func expireReorderNote() async {
        guard reorderNote != nil else { return }
        try? await Task.sleep(for: .seconds(2.4))
        guard !Task.isCancelled else { return }
        reorderNote = nil
    }

    private func statusListing(_ app: AppModel) -> SidebarStatusListing {
        let listed = projectIdentities
        return SidebarStatusListing.build(
            workspaces: groups.flatMap(\.workspaces),
            holding: readingHold,
            pending: WorkspaceDraftRows.drawnPending(
                app.pendingWorkspaces.filter { listed.contains($0.repoID) },
                creating: app.drafts.creatingWorkspaceIDs
            ),
            drafts: app.shownDrafts.filter(listed.contains),
            status: { Self.status(of: $0, in: app) }
        )
    }

    static func status(of workspace: Workspace, in app: AppModel) -> WorkspaceStatus {
        WorkspaceStatus.resolve(
            workspace: workspace,
            isRunning: app.isRunning(workspace),
            pullRequest: WorkspacePullRequests.shared.pullRequest(for: workspace.id),
            isAwaitingPermission: app.isAwaitingPermission(workspace),
            isStarting: app.isStarting(workspace)
        )
    }
}
