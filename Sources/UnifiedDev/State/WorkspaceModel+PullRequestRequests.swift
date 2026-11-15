import SwiftUI
import Core

extension WorkspaceModel {
    var pullRequestStanding: PullRequestStanding {
        PullRequestStanding.of(
            branch: workspace.branch,
            baseBranch: workspace.baseBranch,
            ahead: branchCommits.commits.count,
            aheadIsCapped: branchCommits.isTruncated,
            hasUnreadCommitCount: !hasReadBranchCommits,
            pullRequest: pullRequest,
            localWork: localWork,
            hasRemote: hasRemote ?? true,
            continued: continued,
            checkRuns: checkRuns?.runs ?? []
        )
    }

    func canConfirmMerge(branchActions: BranchActionAvailability, isWorking: Bool) -> Bool {
        MergeConfirmation.canConfirm(
            pullRequest: pullRequest, localWork: localWork, branchActions: branchActions, isWorking: isWorking
        )
    }

    func requestPullRequest(overrides: PromptOverrides = PromptOverrides()) async -> String? {
        let template = overrides.template(for: .createPullRequest)
        let wanted = Set(PromptTemplate.variableNames(in: template))

        if wanted.contains(PromptRegistry.CreatePullRequest.changes) {
            await refreshChanges()
        }

        guard let session = await sessionToWriteInto() else {
            return "Could not open a session in \(workspace.name) to send the request to."
        }

        let context = PullRequestPromptContext(
            workspaceName: workspace.name,
            branch: workspace.branch,
            baseBranch: workspace.baseBranch,
            task: wanted.contains(PromptRegistry.CreatePullRequest.task) ? await openingPrompt() : "",
            changes: wanted.contains(PromptRegistry.CreatePullRequest.changes)
                ? PullRequestPromptContext.changeSummary(changedFiles)
                : ""
        )
        let render = context.render(template: template)

        activeSessionID = session.id
        isExpectingPullRequest = true
        let authority = await instructionAuthority(for: pullRequest)
        let forge = await Forge.kind(forDirectory: workspace.path)
        let text = await PullRequestInstructions.turn(
            render.text, in: workspace.path, authority: authority, forge: forge
        )
        return await deliver(text, to: session)
    }

    func requestPush(
        overrides: PromptOverrides = PromptOverrides(),
        from source: AppRequest.Source
    ) async -> String? {
        let template = overrides.template(for: .pushLocalWork)
        let wanted = Set(PromptTemplate.variableNames(in: template))

        if wanted.contains(PromptRegistry.PushLocalWork.changes) {
            await refreshChanges()
        }

        guard let session = await sessionToWriteInto() else {
            return "Could not open a session in \(workspace.name) to send the request to."
        }

        let render = PromptTemplate.render(template, values: [
            PromptRegistry.PushLocalWork.workspace: workspace.name,
            PromptRegistry.PushLocalWork.branch: workspace.branch,
            PromptRegistry.PushLocalWork.baseBranch: workspace.baseBranch,
            PromptRegistry.PushLocalWork.changes:
                PullRequestPromptContext.changeSummary(changedFiles),
        ])

        activeSessionID = session.id
        return await send(render.text, to: session, from: source)
    }

    func requestMarkReadyForReview(
        _ pullRequest: PullRequest,
        overrides: PromptOverrides = PromptOverrides()
    ) async -> String? {
        guard pullRequest.isOpen, pullRequest.isDraft else {
            return "This pull request is no longer an open draft."
        }
        guard let session = await sessionToWriteInto(titledIfNew: "Mark ready for review") else {
            return "Could not open a session in \(workspace.name) to send the request to."
        }

        let render = PromptTemplate.render(
            overrides.template(for: .markReadyForReview, forge: pullRequest.forge),
            values: [PromptRegistry.MarkReadyForReview.url: pullRequest.url]
        )
        activeSessionID = session.id
        return await deliver(render.text, to: session)
    }

    func requestMerge(
        _ pullRequest: PullRequest,
        method: GitHub.MergeMethod,
        overrides: PromptOverrides = PromptOverrides(),
        from source: AppRequest.Source,
        confirmed: InstructionAuthority? = nil
    ) async -> String? {
        let authority = await instructionAuthority(for: pullRequest)
        if let refusal = InstructionAuthority.mergeRefusal(confirmed: confirmed, sending: authority) { return refusal }
        guard let session = await sessionToWriteInto(titledIfNew: "Merge") else {
            return "Could not open a session in \(workspace.name) to send the request to."
        }
        let chat = transcript(for: session)
        let isBusy = chat.isRunning || chat.queuesNextMessage || chat.sending != nil
        if let refusal = AppRequest.mergeRefusal(from: source, agentIsBusy: isBusy) { return refusal }

        let context = MergePromptContext(workspace: workspace, pullRequest: pullRequest, method: method)
        let render = context.render(template: overrides.template(for: .mergePullRequest))

        let text = await turn(render.text, for: .merge, authority: authority, forge: pullRequest.forge)
        activeSessionID = session.id
        return await send(text, to: session, from: source)
    }

    func instructionAuthority(for pullRequest: PullRequest?) async -> InstructionAuthority {
        await GitHub.instructionAuthority(
            for: workspace,
            pullRequest: pullRequest,
            hasReadPullRequest: hasReadPullRequest,
            readFailure: WorkspacePullRequests.shared.unresolvedFailure(for: workspace.id)
        )
    }

    private func turn(
        _ text: String, for subject: ProjectInstructions.Subject, authority: InstructionAuthority,
        forge: ForgeKind = .gitHub
    ) async -> String {
        await reloadSettings()
        let stated = ProjectInstructions.stated(subject, in: settings)
        let path = workspace.path
        let extra = await Task.detached(priority: .userInitiated) {
            ProjectInstructions.resolve(subject, in: path, stated: stated, authority: authority)
        }.value
        return ProjectInstructions.turn(text, for: subject, adding: extra, authority: authority, forge: forge)
    }

    func sendFixConflictsRequest(
        overrides: PromptOverrides = PromptOverrides()
    ) async -> String? {
        guard let pullRequest else { return "This branch has no pull request to resolve." }
        guard let session = await sessionToWriteInto(titledIfNew: "Fix merge conflicts") else {
            return "Could not open a session in \(workspace.name) to send the request to."
        }
        let chat = transcript(for: session)
        guard chat.acceptsMessages else { return Self.cannotTakeRequest }
        activeSessionID = session.id

        let context = FixConflictsPromptContext(workspace: workspace, pullRequest: pullRequest)
        let request = context.request(template: overrides.template(for: .fixConflicts))

        let authority = await instructionAuthority(for: pullRequest)
        let path = workspace.path
        let asked = await Task.detached(priority: .userInitiated) {
            ConflictInstructions.asking(request, in: path, authority: authority)
        }.value
        return await deliver(await turn(asked, for: .fixConflicts, authority: authority), to: session)
    }

    func sendCheckFailureRequest() async -> String? {
        guard let pullRequest else { return "This branch has no pull request to read checks from." }

        let asked = workspace
        let runs = await Task.detached(priority: .userInitiated) {
            try? await ForgePullRequests.checks(for: asked)
        }.value
        guard let runs else {
            return "Unified Dev could not ask \(pullRequest.hostName) for the checks on #\(pullRequest.number)."
        }

        let failed = runs.filter { CheckState($0) == .failed }
        guard !failed.isEmpty else {
            return "\(pullRequest.hostName) no longer reports a failed check on #\(pullRequest.number)."
        }
        return await sendCheckFailureRequest(for: failed)
    }

    func sendCheckFailureRequest(for failed: [CheckRun]) async -> String? {
        guard let pullRequest else { return "This branch has no pull request to read checks from." }
        guard let session = await sessionToWriteInto(titledIfNew: "Fix the failing checks") else {
            return "Could not open a session in \(workspace.name) to send the request to."
        }
        let chat = transcript(for: session)
        guard chat.acceptsMessages else { return Self.cannotTakeRequest }
        activeSessionID = session.id
        return await deliver(await checkFailureRequest(for: failed, number: pullRequest.number), to: session)
    }

    func checkFailureRequest(for failed: [CheckRun], number: Int) async -> String {
        let carried = Array(failed.prefix(CheckFailureHandoff.mentionsCarried))
        var gathered: [CheckFailureHandoff.Mention] = []
        var logs: [AttachmentSource] = []

        for run in carried {
            var excerpt: CheckFailureHandoff.Excerpt?
            if let log = await ForgePullRequests.failedLog(of: run, worktree: workspace.path) {
                excerpt = CheckFailureHandoff.excerpt(log)
            }
            if let excerpt {
                logs.append(
                    .text(excerpt.text, named: CheckFailureHandoff.logFilename(for: run.name))
                )
            }
            gathered.append(
                CheckFailureHandoff.Mention(
                    name: run.name,
                    workflow: run.workflowName,
                    detailsURL: run.detailsURL,
                    excerpt: excerpt
                )
            )
        }

        let mentions = gathered
        let more = failed.count - carried.count

        let sources = logs
        let folder = workspace.path
        let paths = await Task.detached(priority: .userInitiated) {
            AttachmentFiles.save(sources, workspace: folder)
        }.value

        return CheckFailureHandoff.request(
            CheckFailureHandoff.carrying(mentions, logPaths: paths),
            moreFailed: more,
            number: number,
            host: pullRequest?.forge ?? .gitHub
        )
    }

    private static let cannotTakeRequest =
        "This agent runs in a terminal or its workspace is being archived, so it cannot take that request."

    private func send(
        _ text: String, to session: Session, from source: AppRequest.Source
    ) async -> String? {
        guard source.hidesTurn else {
            await transcript(for: session).submit(text)
            return nil
        }
        return await deliver(text, to: session)
    }

    private func deliver(_ text: String, to session: Session) async -> String? {
        let chat = transcript(for: session)
        guard chat.acceptsMessages else { return Self.cannotTakeRequest }
        guard await chat.submitAppRequest(text) else {
            return "Unified Dev could not send that request to the agent."
        }
        WorkspaceTabsStore.shared.reveal(.chat(session.id), in: self)
        return nil
    }

    func readRemote() async {
        let repo = repo?.path ?? workspace.path
        let names = await Task.detached(priority: .utility) {
            try? await Git.remoteNames(of: repo)
        }.value
        guard let names else { return }
        let found = !names.isEmpty
        if hasRemote != found { hasRemote = found }
    }

    private func openingPrompt() async -> String {
        guard let store else { return "" }
        for session in sessions {
            let messages = (try? await store.messages(sessionID: session.id, limit: 200)) ?? []
            guard let first = messages.first(where: { $0.kind == .user }),
                  let text = UserTurnPayload.text(from: first.payload) else { continue }
            return AttachmentDraft.withoutAttachments(AttachmentTrailer.split(text).body)
        }
        return ""
    }
}
