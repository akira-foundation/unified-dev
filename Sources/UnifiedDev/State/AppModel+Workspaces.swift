import Core

extension AppModel {
    @discardableResult
    func createWorkspace(in repo: Repo, prompt: String, opensWith: WorkspaceStartMode) async -> Workspace? {
        do {
            return try await startWorkspace(in: repo, prompt: prompt, opensWith: opensWith)
        } catch {
            let trouble = await WorkspaceTrouble.creating(
                error,
                project: repo.name,
                projectPath: repo.path,
                baseBranch: repo.defaultBranch
            )
            alert = AppAlert(title: "Could not create the workspace", message: trouble.sentence)
            return nil
        }
    }

    @discardableResult
    func startWorkspace(
        in repo: Repo,
        prompt: String,
        baseBranch: String? = nil,
        opensWith: WorkspaceStartMode = .chat,
        branch: String? = nil,
        controls: ComposerControls? = nil,
        staged: StagedAttachments? = nil,
        select: Bool = true,
        origin: WorkspaceOrigin = .user,
        name: String? = nil,
        checkout: WorkspaceCheckout? = nil,
        resuming: String? = nil,
        id: WorkspaceID = .new(),
        acceptsStaleBase: Bool = true,
        orchestrates: Bool = false
    ) async throws -> Workspace {
        guard let manager else { throw AppNotReady.stillStartingUp }

        let stagedPaths = staged?.attachments.map(\.path) ?? []
        let spoken = WorkspaceStartAttachments.spoken(prompt, staged: stagedPaths)

        var effectiveControls: ComposerControls
        if let controls {
            effectiveControls = controls
        } else {
            effectiveControls = try await resolvedControls(for: repo)
        }

        if let agentKind = opensWith.cliAgentKind {
            if controls == nil || effectiveControls.agentKind != agentKind {
                effectiveControls.model = ""
                effectiveControls.effort = ""
                effectiveControls.permissionMode = .auto
            }
            effectiveControls.agentKind = agentKind
        }

        let wantsAName = checkout == nil
            && shouldNameAutomatically(name: nil, prompt: spoken, opensWith: opensWith)

        let pick: OceanPick?
        if OceanCatalog.shouldClaim(
            userSuppliedName: name ?? checkout?.workspaceName,
            userSuppliedBranch: branch,
            isChatWorkspace: opensWith.runsAnAgent,
            wantsAutomaticName: wantsAName,
            hasTask: !spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ) {
            pick = try? await store?.claimOcean()
        } else {
            pick = nil
        }

        let seaBranch: String?
        if let pick {
            let path = repo.path
            let prefix = await Task.detached(priority: .userInitiated) {
                SettingsLoader.load(repo: path).branchPrefix
            }.value
            seaBranch = WorkspaceNaming.prefixedBranch(pick.ocean.slug, prefix: prefix)
        } else {
            seaBranch = nil
        }

        let suppliedName = name ?? WorkspaceStartPlan.unnamedName(
            isChatWorkspace: opensWith.runsAnAgent,
            hasTask: !spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            userSuppliedBranch: branch,
            claimedSea: pick?.ocean.name
        )
        let placeholder: String?
        if suppliedName == nil, checkout == nil, wantsAName {
            if let sea = pick?.ocean.name {
                placeholder = sea
            } else {
                placeholder = await placeholderName()
            }
        } else {
            placeholder = nil
        }

        showPending(PendingWorkspace(
            id: id,
            repoID: repo.id,
            name: WorkspaceStartPlan.name(
                supplied: suppliedName ?? placeholder, checkout: checkout, prompt: spoken
            )
        ))
        beginStart(id)

        let request = WorkspaceStartRequest(
            id: id,
            repo: repo,
            prompt: spoken,
            origin: origin,
            baseBranch: baseBranch,
            branch: branch ?? seaBranch,
            name: suppliedName,
            checkout: checkout,
            controls: effectiveControls,
            opensSession: opensWith.runsAnAgent,
            resuming: resuming,
            setupPolicy: .deferred,
            acceptsStaleBase: acceptsStaleBase,
            orchestrates: orchestrates
        )

        let started: StartedWorkspace
        do {
            started = try await manager.start(request) { placeholder }
        } catch {
            forgetPending(id)
            endStart(id)
            throw error
        }

        seaDiscoveries.record(pick, for: id)
        await adopt(started, repo: repo, prompt: spoken, opensWith: opensWith, select: select)
        await wake(started.announcedTo.map { [$0] } ?? [])

        if started.projectCameBack {
            self.notice = Notice(
                message: "\(repo.name) is back in Unified Dev's sidebar. It was hidden, and this "
                    + "workspace has just been added to it."
            )
        }

        let arrived: Set<String> = staged.map {
            WorkspaceStartAttachments
                .adopt(stagedPaths, from: $0.directory, into: started.workspace.path)
        } ?? []
        let opening = WorkspaceStartAttachments.opening(
            prompt, staged: stagedPaths, arrived: arrived, isChatWorkspace: opensWith.runsAnAgent
        )

        await model(for: started.workspace).startSetupThenSend(prompt: opening, repo: repo)
        return started.workspace
    }

    func resolvedControls(for repo: Repo?) async throws -> ComposerControls {
        guard let store else { throw AppNotReady.stillStartingUp }

        let appDefaults = await AppDefaults.loadForNewSessions(from: store)
        let repoSettings = await Task.detached(priority: .userInitiated) {
            repo.map { SettingsLoader.load(repo: $0.path) } ?? RepoSettings()
        }.value

        return ComposerControls.resolved(
            repo: repoSettings,
            app: appDefaults,
            models: ComposerModelCatalog.shared.models
        )
    }

    func adopt(
        _ started: StartedWorkspace,
        repo: Repo,
        prompt: String,
        opensWith: WorkspaceStartMode,
        select: Bool
    ) async {
        if opensWith.cliAgentKind != nil, let session = started.session {
            let tabs = CenterTabStore.shared
            tabs.load(workspaceID: started.workspace.id)
            tabs.add(
                kind: .terminal, workspaceID: started.workspace.id,
                title: session.agentKind.label, agentSessionID: session.id
            )
            model(for: started.workspace).pendingCLILaunches.insert(session.id)
        }
        await reload()

        if let placeholder = started.placeholder {
            beginAutomaticNaming(
                workspace: started.workspace,
                repo: repo,
                prompt: prompt,
                placeholder: placeholder
            )
        }

        if select { selection = .workspace(started.workspace.id) }
        WorkspaceStartMode.record(opensWith, workspaceID: started.workspace.id)

        guard let session = started.session else { return }
        let model = model(for: started.workspace)
        await model.reloadSessions()
        model.activeSessionID = session.id
    }

    enum ContinuationOutcome {
        case continued(WorkspaceContinuation)
        case refused(ContinuationRefusal)
        case failed(String)
    }

    func continueAfterMerge(
        _ workspace: Workspace, pullRequest: PullRequest
    ) async -> ContinuationOutcome {
        guard let manager else { return .failed("Unified Dev is still starting up.") }

        let facts: ContinuationFacts
        do {
            facts = try await manager.continuationFacts(
                workspace: workspace,
                pullRequest: pullRequest,
                isAgentMidTurn: isAgentMidTurn(workspace)
            )
        } catch {
            return .failed(await trouble(continuing: error, in: workspace).sentence)
        }

        let branch: String
        switch ContinuationGate.decide(facts) {
        case .cut(let cut): branch = cut
        case .refuse(let refusal): return .refused(refusal)
        }

        let continuation: WorkspaceContinuation
        do {
            continuation = try await manager.continueOnNewBranch(
                workspace: workspace, branch: branch
            )
        } catch {
            return .failed(await trouble(continuing: error, in: workspace).sentence)
        }

        await adopt(continuation, pullRequest: pullRequest)
        return .continued(continuation)
    }

    func carryOn(_ workspace: Workspace, plan: CarryOnPlan) async {
        guard let repo = repo(for: workspace) else {
            alert = AppAlert(
                title: "Could not carry \(workspace.name) on",
                message: "Its project is no longer in Unified Dev, so there is no repository to cut a "
                    + "worktree from. Add the project again and try once more."
            )
            return
        }
        guard !carryingOn.contains(workspace.id) else { return }

        carryingOn.insert(workspace.id)
        defer { carryingOn.remove(workspace.id) }

        let handover = ArchivedCarryOn(workspace: workspace, project: repo.name, plan: plan)
        let template = PromptOverrides().template(for: .carryOnArchived)

        do {
            let started = try await startWorkspace(
                in: repo,
                prompt: handover.render(template: template).text,
                baseBranch: plan.baseBranch,
                branch: plan.branch,
                controls: await carryOnControls(plan: plan, workspace: workspace),
                name: workspace.name,
                resuming: plan.agentSessionID
            )
            Log.archive.info(
                "carried \(workspace.name, privacy: .public) on as \(started.branch, privacy: .public)"
            )
        } catch {
            Log.archive.error(
                "could not carry \(workspace.name, privacy: .public) on: \(error.readableMessage, privacy: .public)"
            )
            let trouble = await WorkspaceTrouble.creating(
                error,
                project: repo.name,
                projectPath: repo.path,
                baseBranch: plan.baseBranch
            )
            alert = AppAlert(
                title: "Could not carry \(workspace.name) on", message: trouble.sentence
            )
        }
    }

    func carryOnDecision(
        for workspace: Workspace, session: Session?, source: RestoreSource?
    ) async -> CarryOnDecision {
        guard let manager else { return .refuse(.stillLooking) }
        guard let repo = repo(for: workspace) else { return .refuse(.projectGone) }
        return CarryOnGate.decide(
            await manager.carryOnFacts(
                workspace: workspace, repo: repo, session: session, source: source
            )
        )
    }

    private func carryOnControls(plan: CarryOnPlan, workspace: Workspace) async -> ComposerControls {
        guard let store, let session = await archivedSession(plan: plan, workspace: workspace) else {
            return ComposerControls(agentKind: plan.agentKind)
        }
        let isFastMode = (try? await store.setting(
            ComposerControls.fastModeKey(sessionID: session.id)
        )) == "1"
        let outputStyle = (try? await store.setting(
            ComposerControls.outputStyleKey(sessionID: session.id)
        )) ?? OutputStyle.defaultName
        let contextWindow = CodexContextWindow.normalised(try? await store.setting(
            ComposerControls.contextWindowKey(sessionID: session.id)
        ))
        let codexFastMode = CodexSpeed.override(stored: try? await store.setting(
            CodexSpeed.key(sessionID: session.id)
        ))
        return ComposerControls(
            session: session,
            isFastMode: isFastMode,
            outputStyle: outputStyle,
            codexContextWindow: contextWindow,
            codexFastMode: codexFastMode
        )
    }

    private func archivedSession(plan: CarryOnPlan, workspace: Workspace) async -> Session? {
        guard let store else { return nil }
        let sessions = (try? await store.sessions(workspaceID: workspace.id)) ?? []
        return sessions.first { $0.agentSessionID == plan.agentSessionID }
    }

    private func trouble(continuing error: any Error, in workspace: Workspace) async -> WorkspaceTrouble {
        await WorkspaceTrouble.continuing(
            error,
            workspace: workspace.name,
            path: workspace.path,
            baseBranch: workspace.baseBranch
        )
    }

    private func adopt(_ continuation: WorkspaceContinuation, pullRequest: PullRequest) async {
        let model = model(for: continuation.workspace)

        WorkspacePullRequests.shared.forget(continuation.workspace.id)

        model.continued = ContinuedBranch(continuation, pullRequest: pullRequest.number)

        await model.refreshChanges()

        await tellAgent(about: continuation, pullRequest: pullRequest, in: model)
    }

    private func tellAgent(
        about continuation: WorkspaceContinuation,
        pullRequest: PullRequest,
        in model: WorkspaceModel
    ) async {
        let template = PromptOverrides().template(for: .continueAfterMerge)
        let render = continuation.render(template: template, pullRequest: pullRequest.number)

        guard let session = await continuationSession(in: model) else { return }
        model.activeSessionID = session.id
        await model.transcript(for: session).submitAppRequest(render.text)
    }

    private func continuationSession(in model: WorkspaceModel) async -> Session? {
        if let session = model.activeSession { return session }
        await model.reloadSessions()
        if let session = model.activeSession { return session }
        return await model.createSession(title: "Continue")
    }
}
