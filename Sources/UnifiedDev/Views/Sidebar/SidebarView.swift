import SwiftUI
import Core

struct SidebarView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager

    @State private var renaming: WorkspaceID?
    @State private var filter: SidebarFilter = .all

    @AppStorage(ProjectVisibility.showsHiddenKey) private var showsHiddenProjects = false
    @AppStorage(SidebarGrouping.storageKey) private var storedGrouping = SidebarGrouping.standard.rawValue

    @State private var listSelection: SidebarSelection?
    @State private var archivePresentation = SidebarArchivePresentation()
    @State private var pane = SidebarPane()
    @State private var stoppingCrew: PendingCrewStop?

    var body: some View {
        answering(observing(animating(list)))
    }

    private var grouping: SidebarGrouping {
        SidebarGrouping.resolve(storedGrouping)
    }

    private var shape: SidebarPane.Shape {
        SidebarPane.Shape(grouping: grouping, filter: filter, showsHiddenProjects: showsHiddenProjects)
    }

    private var motion: SidebarMotion {
        SidebarMotion(
            hasSettled: pane.hasSettled,
            reduceMotion: reduceMotion,
            showsHiddenProjects: showsHiddenProjects
        )
    }

    private var list: some View {
        List(selection: $listSelection) {
            Section {
                SidebarNavRow(title: "Home", icon: "house")
                    .tag(SidebarSelection.home)
                SidebarAskRow()
                    .tag(SidebarSelection.ask)
            }

            if grouping.drawsProjectHeaders {
                SidebarProjectsHeader(onStartProject: startProject)
                    .selectionDisabled()
                    .listRowSeparator(.hidden)
            }

            paneRowsList
        }
        .listStyle(.sidebar)
        .environment(\.appearsActive, false)
        .scrollContentBackground(.hidden)
        .confirmation($stoppingCrew) { pending in
            Confirmation(
                title: "Stop \(pending.name)?",
                message: PendingCrewStop.message,
                confirmLabel: "Stop",
                cancelLabel: "Keep Working"
            )
        } onConfirm: { pending in
            Task { await pending.stop(in: app) }
        }
    }

    private var paneRowsList: some View {
        ForEach(pane.rows) { row in
            paneRow(row)
                .environment(\.sidebarRowIndent, grouping.drawsProjectHeaders ? SidebarMetrics.rowIndent : 0)
        }
        .onMove(perform: reorderAction)
    }

    private var reorderAction: ((IndexSet, Int) -> Void)? {
        guard grouping.allowsReordering else { return nil }
        return { from, to in pane.move(from: from, to: to, in: app) }
    }

    @ViewBuilder
    private func paneRow(_ row: SidebarPaneRow) -> some View {
        switch row {
        case .project(let group):
            RepoHeaderRow(
                repo: group.repo,
                hasUnreadWork: group.hasUnreadWork,
                workspaceCount: group.workspaces.count,
                onCreateWorkspace: presentCreate
            )
            .selectionDisabled()
        case .statusHeading(let group, let count, let isFolded):
            SidebarStatusHeadingRow(
                group: group,
                count: count,
                isFolded: isFolded,
                onToggleFold: group.canFold(count: count) ? { pane.toggleFold(group, app, shape: shape) } : nil
            )
            .selectionDisabled()
            .moveDisabled(true)
        case .workspace(let workspace, let projectName):
            workspaceRow(workspace, projectName: projectName)
        case .crew(let member, let workspaceID, _):
            CrewSidebarRow(row: member)
                .contextMenu {
                    Button("Stop Subagent") { askToStop(member, in: workspaceID) }
                }
                .moveDisabled(true)
                .tag(SidebarSelection.crew(workspaceID, member.id))
        case .subagent(let subagent, let workspaceID, _):
            SubagentSidebarRow(row: subagent)
                .selectionDisabled(!subagent.opensOutput)
                .moveDisabled(true)
                .tag(SidebarSelection.subagent(workspaceID, subagent.id))
        case .pending(let pending):
            PendingWorkspaceRow(
                pending: pending,
                projectName: projectName(for: pending.repoID),
                trailingRepo: trailingRepo(for: pending.repoID)
            )
                .arrivingRow(pane.arrival.isArriving(pending.id))
                .selectionDisabled()
                .moveDisabled(true)
        case .notice:
            SidebarEmptyNoticeRow(isFiltered: filter != .all)
                .selectionDisabled()
                .moveDisabled(true)
        case .draft(let repoID):
            draftRow(repoID)
        }
    }

    private func animating(_ content: some View) -> some View {
        content
            .animation(motion.fold, value: pane.foldedProjects)
            .animation(motion.visibility, value: pane.hiddenProjects)
            .animation(motion.visibility, value: pane.projectIdentities)
            .animation(motion.workspace, value: pane.workspaceIdentities)
            .animation(motion.workspace, value: pane.statusArrangement)
            .animation(motion.subagent, value: app.subagentRows.mapValues { $0.map(\.id) })
            .animation(motion.subagent, value: app.crewRows.mapValues { $0.map(\.id) })
            .settlesArrivals($pane.arrival)
            .task(id: pane.reorderNote) { await pane.expireReorderNote() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SidebarStatusBar(
                    filter: $filter,
                    note: pane.reorderNote?.sentence,
                    onNewWorkspace: { presentCreate(in: nil) },
                    onStartProject: startProject
                )
            }
    }

    private func observing(_ content: some View) -> some View {
        content
            .task(id: app.isLoaded) { await pane.settle(isLoaded: app.isLoaded) }
            .onChange(of: app.profileRepos, initial: true) { _, _ in pane.regroup(app, shape: shape) }
            .onChange(of: app.profileWorkspaces) { _, _ in pane.regroup(app, shape: shape) }
            .onChange(of: app.subagentRows) { _, _ in pane.reflow(app, shape: shape) }
            .onChange(of: app.crewRows) { _, _ in pane.reflow(app, shape: shape) }
            .onChange(of: app.pendingWorkspaces) { _, _ in pane.regroup(app, shape: shape) }
            .onChange(of: app.shownDrafts) { _, _ in pane.reflow(app, shape: shape) }
            .onChange(of: app.drafts.creatingWorkspaceIDs) { _, _ in pane.reflow(app, shape: shape) }
            .onChange(of: app.runningWorkspaceIDs) { _, _ in pane.reflowStatus(app, shape: shape) }
            .onChange(of: app.waitingWorkspaceIDs) { _, _ in pane.reflowStatus(app, shape: shape) }
            .onChange(of: app.startHold) { _, _ in pane.reflowStatus(app, shape: shape) }
            .onChange(of: storedGrouping) { _, _ in
                archivePresentation.cancel()
                pane.reshape(app, shape: shape)
            }
            .onChange(of: filter) { _, _ in
                archivePresentation.cancel()
                pane.regroup(app, shape: shape, rescoped: true)
            }
            .onChange(of: showsHiddenProjects) { _, _ in
                let fades = ProjectVisibilityMotion.filterToggle(reduceMotion: reduceMotion).fadesArrivals
                pane.regroup(app, shape: shape, rescoped: !fades)
            }
    }

    private func answering(_ content: some View) -> some View {
        content
            .onAppear { SwitchProbe.attachSidebarSelection($listSelection) }
            .onDisappear {
                archivePresentation.cancel()
                SwitchProbe.attachSidebarSelection(nil)
            }
            .onChange(of: listSelection) { _, selected in
                if selected == nil { listSelection = app.selection }
            }
            .task(id: listSelection) { await commitListSelection() }
            .onDeleteCommand { archiveSelectedRow() }
            .onReceive(NotificationCenter.default.publisher(for: .unifieddevRenameWorkspace)) { note in
                beginRename(note)
            }
            .onChange(of: app.selection, initial: true) { _, target in
                renaming = nil
                listSelection = target
                pane.follow(target, app, shape: shape)
            }
            .onChange(of: undoManager, initial: true) { _, manager in
                app.undoManager = manager
            }
    }

    private func commitListSelection() async {
        guard let target = listSelection, target != app.selection else { return }
        await Task.yield()
        guard !Task.isCancelled else { return }
        commitSelection(target, replacing: app.selection)
    }

    private func commitSelection(_ target: SidebarSelection, replacing previous: SidebarSelection) {
        guard listSelection == target, app.selection == previous else { return }
        if let id = target.workspaceID, !app.workspaces.contains(where: { $0.id == id }) {
            listSelection = app.selection
            return
        }
        app.selection = target
    }

    private func beginRename(_ note: Notification) {
        guard let raw = note.userInfo?[Notification.unifieddevWorkspaceIDKey] as? String else { return }
        let id = WorkspaceID(raw)
        guard app.workspaces.contains(where: { $0.id == id }) else { return }
        renaming = id
    }

    private func archiveSelectedRow() {
        guard let id = listSelection?.workspaceID,
              let workspace = app.workspaces.first(where: { $0.id == id }),
              pane.draws(workspace.id) else { return }
        WorkspaceHoverCardPresenter.shared.pointerExited(.workspaceRow(workspace.id))
        let generation = archivePresentation.begin(workspaceID: workspace.id, source: .row)
        Task {
            defer { archivePresentation.finish(generation: generation) }
            await app.archive(workspace) { update in
                archivePresentation.apply(update, generation: generation)
            }
        }
    }

    private func workspaceRow(_ workspace: Workspace, projectName: String) -> some View {
        let foldsMarkColumn = foldsMarkColumn(of: workspace)
        return SidebarWorkspaceRow(
            workspace: workspace,
            arrival: pane.arrival,
            projectName: projectName,
            foldsMarkColumn: foldsMarkColumn,
            trailingRepo: trailingRepo(for: workspace.repoID),
            renaming: $renaming,
            archivePresentation: $archivePresentation
        )
        .padding(
            .leading,
            indentsAsChild(workspace) ? SidebarMetrics.orchestratorChildIndent(foldsMarkColumn: foldsMarkColumn) : 0
        )
        .moveDisabled(SidebarReorder.isFixedInPlace(workspace, among: app.workspaces))
        .tag(SidebarSelection.workspace(workspace.id))
    }

    private func indentsAsChild(_ workspace: Workspace) -> Bool {
        grouping.drawsProjectHeaders && SidebarReorder.isOrchestratorChild(workspace, among: app.workspaces)
    }

    private func foldsMarkColumn(of workspace: Workspace) -> Bool {
        indentsAsChild(workspace) && SidebarMarkPolicy.foldsMarkColumn(
            of: workspace,
            among: app.workspaces,
            drawn: pane.workspaceIdentities
        ) { SidebarPane.status(of: $0, in: app) }
    }

    private func draftRow(_ repoID: RepoID) -> some View {
        WorkspaceDraftRow(
            isCreating: app.drafts.isCreating(repoID),
            projectName: projectName(for: repoID),
            trailingRepo: trailingRepo(for: repoID)
        )
            .moveDisabled(true)
            .contextMenu {
                Button("Discard Draft") { app.discardDraft(repoID) }
                    .disabled(app.drafts.isCreating(repoID))
            }
            .tag(SidebarSelection.draft(repoID))
    }

    private func projectName(for repoID: RepoID) -> String {
        pane.reposByID[repoID]?.name ?? ""
    }

    private func trailingRepo(for repoID: RepoID) -> Repo? {
        grouping.drawsProjectHeaders ? nil : pane.reposByID[repoID]
    }

    private func askToStop(_ member: CrewRow, in workspaceID: WorkspaceID) {
        let pending = PendingCrewStop(member: member, workspaceID: workspaceID)
        if member.state.isMidTurn {
            stoppingCrew = pending
        } else {
            Task { await pending.stop(in: app) }
        }
    }

    private func presentCreate(in repo: Repo?) {
        renaming = nil
        app.openDraft(in: repo)
    }

    private func startProject() {
        NotificationCenter.default.post(name: .udNewProject, object: nil)
    }
}
