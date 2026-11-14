import Core

extension AppModel {
    func archiveCleanup() async -> ArchiveCleanup {
        let shownRepos = profileRepos
        guard let store, var footprints = try? await store.archivedFootprints() else {
            return ArchiveCleanup(footprints: [])
        }
        let shown = Set(shownRepos.map(\.id))
        footprints = footprints.filter { shown.contains($0.workspace.repoID) }

        var localBranches: [RepoID: Set<String>] = [:]
        for repo in shownRepos where footprints.contains(where: { $0.workspace.repoID == repo.id }) {
            guard let branches = try? await Git.branches(of: repo.path) else { continue }
            localBranches[repo.id] = Set(branches)
        }
        for index in footprints.indices {
            let workspace = footprints[index].workspace
            footprints[index].branchIsLocal = localBranches[workspace.repoID]?.contains(workspace.branch)
        }
        return ArchiveCleanup(footprints: footprints)
    }

    func databaseSize() async -> DatabaseSize? {
        guard let store else { return nil }
        return try? await store.databaseSize()
    }

    @discardableResult
    func deleteArchived(_ ids: [WorkspaceID]) async -> ArchiveDeletionOutcome {
        let outcome = await removeArchivedRecords(ids)
        if outcome.didDelete { invalidateArchived() }
        return outcome
    }

    func removeArchivedRecords(_ ids: [WorkspaceID]) async -> ArchiveDeletionOutcome {
        guard let store, !ids.isEmpty else { return .deleted(0) }
        let removed: [WorkspaceID]
        do {
            removed = try await store.deleteArchivedWorkspaces(ids: ids)
        } catch {
            return .refused(complaint: WorkspaceTrouble.complaint(about: error))
        }
        guard !removed.isEmpty else { return .deleted(0) }

        await flushCanvasDocuments(of: removed)
        if let open = selection.archivedWorkspaceID, removed.contains(open) {
            selection = .home
        }
        for id in removed {
            workspaceModels[id]?.teardown()
            workspaceModels[id] = nil
        }
        return .deleted(removed.count)
    }

    func compactDatabase() async {
        guard let store else { return }
        try? await store.compactDatabase()
    }

    @discardableResult
    func archive(
        _ workspace: Workspace,
        deleteBranch: Bool? = nil,
        alwaysConfirm: Bool = false,
        allowsConfirmation: Bool = true,
        presentConfirmation: ((ArchiveConfirmationFlow.Update) -> Void)? = nil
    ) async -> WorkspaceArchiveOutcome {
        guard let manager, let repo = repo(for: workspace) else {
            Log.archive.error(
                "asked to archive \(workspace.name, privacy: .public), but the app has no manager or no project for it"
            )
            return .refused("Unified Dev cannot archive this workspace because its project is unavailable.")
        }
        guard !isArchiving(workspace.id) else {
            return .refused("This workspace is already being archived. Check workspace_list shortly.")
        }
        let current = workspaces.first { $0.id == workspace.id } ?? workspace
        if let objection = OrchestratorRole.archiveObjection(to: current) {
            if allowsConfirmation { notice = Notice(message: objection, tone: .warning) }
            return .refused(objection)
        }

        let pullRequest = pullRequest(of: workspace)
        var hazards = ArchiveHazards(
            isAgentMidTurn: isAgentMidTurn(workspace),
            isPullRequestMerged: pullRequest?.isMerged ?? false,
            mergedPullRequestHead: pullRequest?.mergedHead,
            isDeletingBranch: ArchiveBranchDeletion.applies(
                requested: deleteBranch, settings: SettingsLoader.load(repo: repo.path),
                workspace: workspace, defaultBranch: repo.defaultBranch
            )
        )

        play(
            ArchiveSequence.opening(workspace, hazards: hazards, allowsConfirmation: allowsConfirmation),
            present: presentConfirmation
        )

        let check: ArchiveCheck
        var report = WorkspaceSafetyReport()
        do {
            report = try await manager.safetyReport(
                workspace: workspace, repo: repo, mergedPullRequestHead: hazards.mergedPullRequestHead
            )
            hazards.isAgentMidTurn = isAgentMidTurn(workspace)
            await flushCanvasDocuments(of: [workspace.id])
            hazards.canvasLosses = canvasArchiveQuestion(of: [workspace.id])?.losses ?? []
            check = .checked(report)
        } catch {
            let trouble = await WorkspaceTrouble.archiving(
                error,
                workspace: workspace.name,
                path: workspace.path,
                baseBranch: workspace.baseBranch
            )
            hazards.isAgentMidTurn = isAgentMidTurn(workspace)
            check = .couldNotCheck(
                problem: "Unified Dev could not check this workspace for unsaved work. \(trouble.sentence)"
            )
        }

        let step = ArchiveSequence.afterChecking(
            check, workspace: workspace, deleteBranch: deleteBranch, hazards: hazards,
            alwaysConfirm: alwaysConfirm, allowsConfirmation: allowsConfirmation
        )
        play(step.updates, present: presentConfirmation)
        if let refusal = step.refusal { return .refused(refusal) }

        return await performArchive(
            workspace,
            repo: repo,
            deleteBranch: deleteBranch,
            force: false,
            report: report,
            measuredTip: report.branchTip,
            hazards: hazards,
            allowsConfirmation: allowsConfirmation,
            presentConfirmation: presentConfirmation
        )
    }

    func bookArchiveForBridge(of workspace: Workspace, after sessionID: SessionID) -> WorkspaceArchiveOutcome {
        bookArchive(of: workspace.id, after: sessionID)
        Log.archive.info(
            "\(workspace.name, privacy: .public) is booked to be archived when its agent's turn ends"
        )
        return .requested
    }

    func archiveIfRequested(
        _ workspace: Workspace, endedIn sessionID: SessionID, wasStopped: Bool = false
    ) async {
        guard takeArchiveBooking(of: workspace.id, endedIn: sessionID) else { return }
        guard let store else { return }

        if wasStopped {
            Log.archive.notice(
                "the booked archive of \(workspace.name, privacy: .public) was dropped: its turn was stopped by hand"
            )
            notice = Notice(
                message: "\(workspace.name) had asked to be archived when its agent finished. You "
                    + "stopped that turn, so nothing was archived and the request is dropped.",
                tone: .warning
            )
            return
        }

        if let objection = await WorkspaceArchiveSafety.objection(
            to: workspace, excusing: nil, store: store
        ) {
            Log.archive.notice(
                "the booked archive of \(workspace.name, privacy: .public) was refused: \(objection, privacy: .public)"
            )
            notice = Notice(
                message: "\(workspace.name) asked to be archived when its agent finished, and it "
                    + "was not. \(objection)",
                tone: .warning
            )
            return
        }

        switch await archive(workspace, deleteBranch: false, allowsConfirmation: false) {
        case .archived, .requested:
            break
        case .refused(let reason):
            notice = Notice(
                message: "\(workspace.name) asked to be archived when its agent finished, and it "
                    + "was not. \(reason)",
                tone: .warning
            )
        }
    }

    private func pullRequest(of workspace: Workspace) -> PullRequest? {
        workspaceModels[workspace.id]?.pullRequest
            ?? WorkspacePullRequests.shared.pullRequest(for: workspace.id)
    }

    func confirmArchive(
        _ request: ArchiveRequest,
        presentConfirmation: ((ArchiveConfirmationFlow.Update) -> Void)? = nil
    ) async {
        if pendingArchive?.id == request.id { pendingArchive = nil }
        guard let repo = repo(for: request.workspace) else {
            Log.archive.error(
                "confirmed the archive of \(request.workspace.name, privacy: .public), but its project is gone"
            )
            return
        }
        let fresh = try? await manager?.safetyReport(
            workspace: request.workspace, repo: repo,
            mergedPullRequestHead: request.hazards.mergedPullRequestHead
        )
        switch ArchiveDecisionGate.resolve(
            pressedWhileChecking: request.isChecking,
            request: request,
            report: fresh,
            isAgentMidTurn: isAgentMidTurn(request.workspace)
        ) {
        case .refuse(let sentence):
            Log.archive.notice(
                "\(request.workspace.name, privacy: .public) was not archived: an agent started a turn while the question was open"
            )
            notice = Notice(
                message: ArchiveNotice.afterFailing(
                    "\(request.workspace.name) was not archived. \(sentence)", stopping: request.stoppedCommands
                ),
                tone: .warning
            )
            return
        case .ask(let again):
            Log.archive.notice(
                "\(request.workspace.name, privacy: .public) changed while its archive was being confirmed, so it is being asked about again"
            )
            updateArchiveConfirmation(.offer(again), present: presentConfirmation)
            return
        case .archive:
            break
        }
        await performArchive(
            request.workspace,
            repo: repo,
            deleteBranch: request.deletesBranch(archivingWith: fresh),
            force: true,
            report: request.reportForArchiving(fresh: fresh),
            measuredTip: request.tipForArchiving(fresh: fresh),
            hazards: request.hazards,
            alreadyStopped: request.stoppedCommands,
            presentConfirmation: presentConfirmation
        )
    }

    func cancelPendingArchive() {
        pendingArchive = nil
    }

    private func play(
        _ updates: [ArchiveConfirmationFlow.Update],
        present: ((ArchiveConfirmationFlow.Update) -> Void)?
    ) {
        for update in updates {
            updateArchiveConfirmation(update, present: present)
        }
    }

    private func updateArchiveConfirmation(
        _ update: ArchiveConfirmationFlow.Update,
        present: ((ArchiveConfirmationFlow.Update) -> Void)?
    ) {
        guard let present else {
            pendingArchive = ArchiveConfirmationFlow.shows(
                update, while: pendingArchive, replacesInPlace: false
            )
            return
        }
        present(update)
    }

    @discardableResult
    private func performArchive(
        _ workspace: Workspace,
        repo: Repo,
        deleteBranch: Bool?,
        force: Bool,
        report: WorkspaceSafetyReport?,
        measuredTip: String?,
        hazards: ArchiveHazards,
        alreadyStopped: [Subagent] = [],
        allowsConfirmation: Bool = true,
        presentConfirmation: ((ArchiveConfirmationFlow.Update) -> Void)?
    ) async -> WorkspaceArchiveOutcome {
        guard let manager else {
            Log.archive.error(
                "archiving \(workspace.name, privacy: .public) stopped before it began: no workspace manager"
            )
            return .refused("Unified Dev is still starting up. Try again in a moment.")
        }

        await flushCanvasDocuments(of: [workspace.id])
        let before = ArchiveSequence.beforeArchiving(
            workspace, report: report, deleteBranch: deleteBranch, hazards: hazards,
            canvasLosses: canvasArchiveQuestion(of: [workspace.id])?.losses ?? [],
            alreadyStopped: alreadyStopped, allowsConfirmation: allowsConfirmation
        )
        play(before.updates, present: presentConfirmation)
        if let refusal = before.refusal { return .refused(refusal) }

        guard hideFromSidebar(workspace.id) else {
            return .refused("This workspace is already being archived. Check workspace_list shortly.")
        }
        let stoppedCommands = ArchiveNotice.everyCommandStopped(
            earlier: alreadyStopped, now: workspaceModels[workspace.id]?.runningCommands ?? []
        )
        workspaceModels[workspace.id]?.stopEverything()

        let departure = ArchiveNavigation.destination(leaving: selection, archiving: workspace.id)
        if let departure { selection = departure }

        do {
            let keptBranch = try await manager.archive(
                workspace: workspace,
                repo: repo,
                deleteBranch: deleteBranch,
                force: force,
                mergedPullRequestHead: hazards.mergedPullRequestHead,
                measuredTip: measuredTip
            )
            _ = try? await store?.cancelQueuedCanvasComments(workspaceID: workspace.id)
            if let home = ArchiveNavigation.destination(leaving: selection, archiving: workspace.id) {
                selection = home
            }
            await TerminalSessionStore.shared.discard(workspaceID: workspace.id)
            workspaceModels[workspace.id]?.teardown()
            forgetWorkspace(workspace.id)
            invalidateArchived()
            await noteWorkspaceArchivedForWatchers(workspace.id)
            await offerUndo(of: workspace, repo: repo, report: report)
            if let archived = ArchiveNotice.after(
                archiving: workspace.name,
                preservedFolderPath: report?.preservedFolderPath,
                keptBranch: keptBranch,
                stopping: stoppedCommands
            ) {
                notice = archived
            }
            Log.archive.info("archived \(workspace.name, privacy: .public)")
            return .archived
        } catch let error as WorkspaceError {
            await undoOptimisticArchive(workspace)
            switch error {
            case .archiveScriptFailed(let status, let output):
                Log.archive.error(
                    "the archive script for \(workspace.name, privacy: .public) exited \(status), so nothing was removed"
                )
                alert = AppAlert(
                    title: "The archive script failed",
                    message: ArchiveNotice.scriptFailure(
                        workspaceName: workspace.name, status: status, output: output, stopping: stoppedCommands
                    )
                )
            case .unsafeToArchive(let fresh):
                Log.archive.notice(
                    "\(workspace.name, privacy: .public) changed between the check and the archive, so it is being asked about again"
                )
                let changed = ArchiveSequence.changedWhileArchiving(
                    workspace, fresh: fresh, deleteBranch: deleteBranch, hazards: hazards,
                    stoppedCommands: stoppedCommands, allowsConfirmation: allowsConfirmation
                )
                play(changed.updates, present: departure == nil ? presentConfirmation : nil)
                return .refused(changed.refusal)
            default:
                Log.archive.error(
                    "could not archive \(workspace.name, privacy: .public): \(error.readableMessage, privacy: .public)"
                )
                return .refused(await reportArchiveFailure(error, workspace: workspace, stopping: stoppedCommands))
            }
            return .refused(ArchiveNotice.afterFailing(
                "The archive script failed. Its worktree and branch were kept. Check Unified Dev's alert for the script output.",
                stopping: stoppedCommands
            ))
        } catch {
            await undoOptimisticArchive(workspace)
            Log.archive.error(
                "could not archive \(workspace.name, privacy: .public): \(error.readableMessage, privacy: .public)"
            )
            return .refused(await reportArchiveFailure(error, workspace: workspace, stopping: stoppedCommands))
        }
    }

    private func reportArchiveFailure(
        _ error: any Error, workspace: Workspace, stopping commands: [Subagent]
    ) async -> String {
        let trouble = await WorkspaceTrouble.archiving(
            error,
            workspace: workspace.name,
            path: workspace.path,
            baseBranch: workspace.baseBranch
        )
        let sentence = ArchiveNotice.afterFailing(trouble.sentence, stopping: commands)
        alert = AppAlert(title: "Could not archive the workspace", message: sentence)
        return sentence
    }

    private func undoOptimisticArchive(_ workspace: Workspace) async {
        restoreToSidebar(workspace)
        await reload()
    }

    private func offerUndo(
        of workspace: Workspace, repo: Repo, report: WorkspaceSafetyReport?
    ) async {
        guard let manager, undoManager != nil else { return }
        guard let report, report.isRestorableFromBranch else { return }
        guard SettingsLoader.load(repo: repo.path).archiveScript == nil else { return }
        guard await manager.canRestore(workspace: workspace, repo: repo) else { return }
        registerArchiveUndo(workspace, repo: repo)
    }

    private func registerArchiveUndo(_ workspace: Workspace, repo: Repo) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.beginRestore(of: workspace, repo: repo) }
        }
        undoManager.setActionName("Archive Workspace")
    }

    private func beginRestore(of workspace: Workspace, repo: Repo) {
        Task { await restore(workspace) }
    }

    func openArchived(_ workspace: Workspace) {
        model(for: workspace)
        selection = .archived(workspace.id)
    }

    func open(workspaceID id: WorkspaceID) async {
        if workspaces.contains(where: { $0.id == id }) {
            selection = .workspace(id)
            return
        }
        guard let archived = await archivedWorkspaces().first(where: { $0.id == id }) else { return }
        openArchived(archived)
    }

    func restoreSource(for workspace: Workspace) async -> RestoreSource? {
        guard let manager, let repo = repo(for: workspace) else { return nil }
        return await manager.restoreSource(workspace: workspace, repo: repo)
    }

    func restore(_ workspace: Workspace) async {
        guard let manager else { return }
        guard let repo = repo(for: workspace) else {
            alert = AppAlert(
                title: "Could not bring \(workspace.name) back",
                message: "Its project is no longer in Unified Dev, so there is no repository to cut a "
                    + "worktree from. Add the project again and try once more."
            )
            return
        }
        guard !restoring.contains(workspace.id) else { return }

        restoring.insert(workspace.id)
        defer { restoring.remove(workspace.id) }

        do {
            guard try await manager.store.workspace(id: workspace.id) != nil else {
                invalidateArchived()
                alert = AppAlert(
                    title: "Could not bring \(workspace.name) back",
                    message: "Its archived record has been deleted, so there is nothing left to restore."
                )
                return
            }
            let outcome = try await manager.restore(workspace: workspace, repo: repo)
            invalidateArchived()
            await reload()
            selection = .workspace(outcome.workspace.id)
            Log.archive.info("restored \(workspace.name, privacy: .public)")

            if let from = outcome.relocatedFrom {
                notice = Notice(
                    message: "\(outcome.workspace.name) came back to a different place. "
                        + "Something else is at `\(from)`, so the worktree was rebuilt at "
                        + "`\(outcome.workspace.path)`.",
                    dismissal: .untilDismissed
                )
            }
        } catch {
            Log.archive.error(
                "could not restore \(workspace.name, privacy: .public): \(error.readableMessage, privacy: .public)"
            )
            let trouble = await WorkspaceTrouble.restoring(
                error,
                workspace: workspace.name,
                branch: workspace.branch,
                project: repo.name,
                projectPath: repo.path
            )
            alert = AppAlert(
                title: "Could not bring \(workspace.name) back",
                message: trouble.sentence
            )
        }
    }
}
