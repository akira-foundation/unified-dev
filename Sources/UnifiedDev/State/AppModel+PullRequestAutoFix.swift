import Foundation
import Core

extension AppModel {
    func considerPullRequestAutoFix(_ seen: PullRequest, for id: WorkspaceID) async {
        guard let store, let workspace = workspaces.first(where: { $0.id == id }),
              !pullRequestAutoFixesUnderWay.contains(id) else { return }
        pullRequestAutoFixesUnderWay.insert(id)
        defer { pullRequestAutoFixesUnderWay.remove(id) }

        guard await PullRequestAutoFixSetting.isOn(repoID: workspace.repoID, in: store),
              let known = try? await store.pullRequestFixLedger(workspaceID: id, number: seen.number),
              PullRequestAutoFix.isWorthReading(seen, ledger: known),
              let facts = await ForgePullRequests.autoFixFacts(for: workspace),
              let ledger = try? await store.pullRequestFixLedger(workspaceID: id, number: facts.pullRequest.number),
              let current = workspaces.first(where: { $0.id == id })
        else { return }

        func verdict(_ chat: PullRequestAutoFix.Chat, _ account: PullRequestAutoFix.Account) -> PullRequestAutoFix.Verdict {
            PullRequestAutoFix.decide(PullRequestAutoFix.Situation(
                isEnabled: true,
                pullRequest: facts.pullRequest,
                localWork: facts.localWork,
                workspaceBranch: current.branch,
                checkedOutBranch: facts.checkedOutBranch,
                checkedOutHead: facts.checkedOutHead,
                viewerLogin: facts.viewerLogin,
                commitAuthors: facts.commitAuthors,
                isArchived: current.state == .archived || isArchiving(id),
                chat: chat,
                account: account,
                ledger: ledger
            ))
        }

        if case .leave = verdict(.ready, .usable) { return }

        let model = model(for: current)
        await model.reloadSessions()
        let session = model.activeSession
        let chat = await chatForAutoFix(session, in: model)
        let account = await accountForAutoFix(session, in: model)
        await carryOut(verdict(chat, account), facts: facts, workspace: current, session: session, model: model)
    }

    private func chatForAutoFix(_ session: Session?, in model: WorkspaceModel) async -> PullRequestAutoFix.Chat {
        guard let session else { return PullRequestAutoFix.chat(nil) }
        let transcript = model.transcript(for: session)
        await transcript.load()
        await transcript.refreshQueue()
        return PullRequestAutoFix.chat(transcript.pullRequestAutoFixReading)
    }

    private func accountForAutoFix(_ session: Session?, in model: WorkspaceModel) async -> PullRequestAutoFix.Account {
        guard let session, let scope = model.existingTranscript(for: session.id)?.accountScope else { return .missing }
        let chosen: AgentAccountHome?
        do {
            chosen = try await account(for: session.agentKind, in: scope)
        } catch {
            return .missing
        }
        let own = QuotaScope(holders: [session.agentKind: QuotaHolder(provider: session.agentKind, home: chosen)])
        return PullRequestAutoFix.account(
            isResolved: true, provider: session.agentKind, quotas: storedQuotas.filter(own.shows), at: Date()
        )
    }

    private func carryOut(
        _ verdict: PullRequestAutoFix.Verdict,
        facts: PullRequestAutoFixFacts,
        workspace: Workspace,
        session: Session?,
        model: WorkspaceModel
    ) async {
        guard let store else { return }
        let id = workspace.id
        let number = facts.pullRequest.number
        switch verdict {
        case .leave:
            return
        case .forgiveRun:
            try? await store.forgivePullRequestFixRun(workspaceID: id, number: number)
        case .announceStop:
            guard (try? await store.claimPullRequestFixStopNotice(workspaceID: id, number: number)) == true else { return }
            NotificationService.shared.pullRequestFixStopped(facts.pullRequest, in: workspace)
        case .send(let attempt):
            guard let session,
                  (try? await store.claimPullRequestFix(attempt, workspaceID: id, number: number)) == true
            else { return }
            let sent = await model.sendAutoFixRequest(attempt, pullRequest: facts.pullRequest, into: session)
            if !sent { try? await store.releasePullRequestFix(attempt, workspaceID: id, number: number) }
        }
    }
}
