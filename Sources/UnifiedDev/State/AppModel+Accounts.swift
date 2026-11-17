import Foundation
import Core

struct ComposerAccountHomes: Hashable {
    var claude: AgentAccountHome?
    var codex: AgentAccountHome?
}

struct ComposerAccountKey: Hashable {
    var fingerprint: AccountFingerprint
    var provider: AgentKind
}

struct ComposerAccountReading: Equatable {
    var key: ComposerAccountKey
    var section: ComposerAccountSection?
    var homes: ComposerAccountHomes
}

extension AppModel {
    var selectedAccountScope: AccountScope {
        guard let workspace = selectedWorkspace else { return AccountScope(profileID: activeProfileID) }
        return AccountScope(workspaceID: workspace.id, repoID: workspace.repoID, profileID: activeProfileID)
    }

    func accountFingerprint(for scope: AccountScope) -> AccountFingerprint {
        AccountFingerprint.make(
            scope: scope,
            book: accountChoices,
            repoID: scope.workspaceID.flatMap { id in workspaces.first { $0.id == id } }?.repoID
        )
    }

    func accountResolution(for scope: AccountScope) async -> AgentAccountResolution? {
        guard let store else { return nil }
        return try? await AgentAccountResolver.resolve(
            workspaceID: scope.workspaceID, repoID: scope.repoID, profileID: scope.profileID, store: store
        )
    }

    func composerAccountKey(for scope: AccountScope, provider: AgentKind) -> ComposerAccountKey {
        ComposerAccountKey(fingerprint: accountFingerprint(for: scope), provider: provider)
    }

    func composerAccounts(for key: ComposerAccountKey) async -> ComposerAccountReading? {
        guard let resolution = await accountResolution(for: key.fingerprint.scope) else { return nil }
        return ComposerAccountReading(
            key: key,
            section: resolution.composerSection(repoID: key.fingerprint.scope.repoID, provider: key.provider),
            homes: ComposerAccountHomes(claude: resolution.home(for: .claudeCode), codex: resolution.home(for: .codex))
        )
    }

    func accounts(in scope: AccountScope) async throws -> AgentAccountResolution? {
        guard let store else { return nil }
        return try await AgentAccountResolver.resolve(
            workspaceID: scope.workspaceID, repoID: scope.repoID, profileID: scope.profileID, store: store
        )
    }

    func account(for provider: AgentKind, in scope: AccountScope) async throws -> AgentAccountHome? {
        try await accounts(in: scope)?.launchHome(for: provider)
    }

    func accountOptions(in scope: AccountScope) async -> AgentAccountOptions? {
        await accountResolution(for: scope)?.options
    }

    func profileAccountOptions(for profile: ProfileID) async -> AgentAccountOptions? {
        await accountResolution(for: AccountScope(profileID: profile))?.profileOptions
    }

    func chooseAccount(_ chosen: ChosenAgentAccount, forProfile profile: ProfileID) async -> String? {
        guard let store else { return AgentAccountAssignment.noDatabase }
        do {
            try await AgentAccountAssignment.choose(chosen, forProfile: profile, in: store)
            accountMarks.noteChosen()
            return nil
        } catch {
            return AgentAccountAssignment.saveFailure(error.readableMessage)
        }
    }

    func chooseAccount(_ chosen: ChosenAgentAccount, in scope: AccountScope) async -> String? {
        guard let store else { return AgentAccountAssignment.noDatabase }
        do {
            switch AgentAccountAssignment.target(repoID: scope.repoID) {
            case .failure(let unknown):
                return unknown.sentence
            case .success(let repoID):
                try await AgentAccountAssignment.choose(chosen, forRepo: repoID, in: store)
            }
            accountMarks.noteChosen()
            return nil
        } catch {
            return AgentAccountAssignment.saveFailure(error.readableMessage)
        }
    }

    func adoptSelectedAccounts() async {
        guard let store else { return }
        let fingerprint = accountFingerprint(for: selectedAccountScope)
        guard fingerprint != accountSyncKey else { return }
        accountSyncKey = fingerprint
        guard let resolution = await accountResolution(for: fingerprint.scope) else {
            if accountSyncKey == fingerprint { accountSyncKey = nil }
            return
        }
        guard accountFingerprint(for: selectedAccountScope) == fingerprint else { return }
        selectedAccountHomes = resolution.homes
        ComposerModelCatalog.shared.adopt(accounts: resolution.homes, store: store)
        adoptQuotaScope(QuotaScope(homes: resolution.homes))
    }
}

extension AppModel {
    func noteSwitched(to account: AgentAccountID) {
        accountMarks.noteSwitched(to: account, at: Date())
    }

    func observeAccount(_ observation: AgentAccountSignOut.Observation, on account: AgentAccountID) {
        var marks = accountMarks
        marks.apply(observation, on: account, at: Date())
        guard marks != accountMarks else { return }
        accountMarks = marks
    }

    func quotaAccountOffers(at now: Date) -> [AgentKind: QuotaAccountOffer] {
        guard let workspace = selectedWorkspace,
              let transcript = existingModel(for: workspace.id)?.activeTranscript,
              let current = selectedAccountHomes[transcript.session.agentKind]
        else { return [:] }
        let session = transcript.session
        let notices = MenuBarPanelContent.limitNotices(quotas, at: now)
        let signedOut = accountMarks.cause(for: current.id)
        let offer = QuotaAccountOffer.make(QuotaAccountOffer.Input(
            session: session,
            current: current,
            standings: agentAccounts.book.reachable(
                agentAccounts.standings, forRepo: workspace.repoID, otherwise: activeProfileID
            ),
            notices: notices,
            signedOut: signedOut,
            isTurnInFlight: transcript.isRunning,
            lastTurnEndedCleanly: QuotaAccountOffer.readsLastTurn(
                provider: session.agentKind, notices: notices, signedOut: signedOut, isTurnInFlight: transcript.isRunning
            ) && transcript.lastTurnEndedCleanly,
            projectName: repos.first { $0.id == workspace.repoID }?.name ?? workspace.name,
            now: now
        ))
        return offer.map { [session.agentKind: $0] } ?? [:]
    }

    func restartTurn(on account: AgentAccountHome) async {
        guard let workspace = selectedWorkspace,
              let transcript = existingModel(for: workspace.id)?.activeTranscript,
              transcript.session.agentKind == account.provider
        else { return }
        let asksForResume = quotaAccountOffers(at: Date())[account.provider]?.resumesTask == true
        if let complaint = await transcript.restartTurn(
            on: account, resume: asksForResume ? .quotaAccount : .accountOnly
        ) {
            notice = Notice(message: complaint, tone: .error)
        }
        await adoptSelectedAccounts()
    }
}
