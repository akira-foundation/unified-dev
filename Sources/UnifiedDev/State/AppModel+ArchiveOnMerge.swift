import Core

extension AppModel {
    func noteCurrentPullRequest(_ pullRequest: PullRequest, for id: WorkspaceID) async {
        guard let store,
              let workspace = workspaces.first(where: { $0.id == id }),
              let repo = repo(for: workspace),
              !isArchiving(id) else { return }

        let isCommandRunning = pullRequest.isMerged ? await isRunningCommand(in: id) : false
        let decision = try? await MergeArchiveRead.note(
            pullRequest,
            workspaceID: id,
            isEnabled: SettingsLoader.load(repo: repo.path).archiveOnMerge,
            isAgentMidTurn: isAgentMidTurn(workspace),
            isCommandRunning: isCommandRunning,
            store: store
        )
        let isNewCommandWait = decision.map {
            mergeArchiveWaits.record(
                $0, for: id, pullRequest: pullRequest.number, mergedHead: pullRequest.headCommit
            )
        } ?? false
        switch decision {
        case .archiveNow:
            await archiveOnMerge(workspace, mergedHead: pullRequest.headCommit)
        case .archiveAfterTurn:
            Log.archive.info(
                "\(workspace.name, privacy: .public) merged mid turn and will be archived when the turn ends"
            )
        case .waitForCommand:
            watchMergeWaits()
            guard isNewCommandWait else { return }
            notice = Notice(
                message: "\(workspace.name) merged. It will be archived once the command still "
                    + "running in it ends.",
                tone: .information
            )
        case .leave, .forget, nil:
            break
        }
    }

    func archiveIfMergeWaiting(_ workspace: Workspace, wasStopped: Bool) async {
        let isCommandRunning = wasStopped ? false : await isRunningCommand(in: workspace.id)
        let mergedHead = mergeArchiveWaits.mergedHeads[workspace.id]
        let settlement = mergeArchiveWaits.settle(
            workspace.id,
            isAgentMidTurn: isAgentMidTurn(workspace),
            isCommandRunning: isCommandRunning,
            wasStopped: wasStopped
        )
        switch settlement {
        case .notWaiting:
            return
        case .keepWaiting:
            watchMergeWaits()
        case .dropStopped:
            try? await store?.recordPullRequestSeenOpen(nil, workspaceID: workspace.id)
            notice = Notice(
                message: "\(workspace.name) merged while work was still running in it. You stopped a "
                    + "turn there, so it was not archived.",
                tone: .warning
            )
        case .archive(let number):
            guard let store,
                  let repo = repo(for: workspace),
                  SettingsLoader.load(repo: repo.path).archiveOnMerge,
                  (try? await store.takePullRequestSeenOpen(number, workspaceID: workspace.id)) == true
            else { return }
            await archiveOnMerge(workspace, mergedHead: mergedHead)
        }
    }

    private func isRunningCommand(in id: WorkspaceID) async -> Bool {
        if existingModel(for: id)?.hasRunningBackgroundTasks == true { return true }
        return await TerminalSessionStore.shared.isRunningCommand(in: id)
    }

    func settleMergeWaitsAfterTerminalActivity() {
        let running = TerminalSessionStore.shared.runningWorkspaceIDs
        let ended = terminalRunningWorkspaceIDs.subtracting(running)
        terminalRunningWorkspaceIDs = running
        for id in ended.intersection(mergeArchiveWaits.ids) {
            guard let workspace = workspaces.first(where: { $0.id == id }) else { continue }
            Task { await archiveIfMergeWaiting(workspace, wasStopped: false) }
        }
    }

    private func watchMergeWaits() {
        guard mergeArchiveWatch == nil, !mergeArchiveWaits.recheckedIDs.isEmpty else { return }
        mergeArchiveWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: MergeArchiveWaits.recheckInterval)
                guard let self else { return }
                await self.settleMergeWaits()
                if self.mergeArchiveWaits.recheckedIDs.isEmpty {
                    self.mergeArchiveWatch = nil
                    return
                }
            }
        }
    }

    private func settleMergeWaits() async {
        for id in mergeArchiveWaits.recheckedIDs where !isArchiving(id) {
            guard let workspace = workspaces.first(where: { $0.id == id }) else {
                mergeArchiveWaits.forget(id)
                continue
            }
            await archiveIfMergeWaiting(workspace, wasStopped: false)
        }
    }

    private func archiveOnMerge(_ workspace: Workspace, mergedHead: String?) async {
        guard let store, !isArchiving(workspace.id) else { return }
        if let objection = await WorkspaceArchiveSafety.objection(to: workspace, excusing: nil, store: store) {
            refuseArchiveOnMerge(workspace, because: objection)
            return
        }
        let inFlight = await MergeArchiveInFlightRead.objection(worktree: workspace.path, mergedHead: mergedHead)
        guard !isArchiving(workspace.id) else { return }
        if let inFlight {
            Log.archive.info(
                "\(workspace.name, privacy: .public) merged and was held back: \(inFlight, privacy: .private)"
            )
            refuseArchiveOnMerge(workspace, because: inFlight)
            return
        }
        Log.archive.info("\(workspace.name, privacy: .public) merged and is being archived")
        guard case .refused(let reason) = await archive(
            workspace, deleteBranch: nil, allowsConfirmation: false
        ) else { return }
        refuseArchiveOnMerge(workspace, because: reason)
    }

    private func refuseArchiveOnMerge(_ workspace: Workspace, because reason: String) {
        notice = Notice(
            message: "\(workspace.name) merged and was not archived. \(reason)",
            tone: .warning
        )
    }
}
