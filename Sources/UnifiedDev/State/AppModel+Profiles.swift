import Foundation
import Core

extension AppModel {
    var activeProfile: Profile? {
        profiles.first { $0.id == activeProfileID }
    }

    var profileRepos: [Repo] {
        ProfileScope.repos(repos, in: activeProfileID)
    }

    var profileWorkspaces: [Workspace] {
        ProfileScope.workspaces(workspaces, repos: repos, in: activeProfileID)
    }

    func inActiveProfile(_ rows: [Workspace]) -> [Workspace] {
        ProfileScope.workspaces(rows, repos: repos, in: activeProfileID)
    }

    func switchProfile(to id: ProfileID) async {
        guard ProfileNavigation.maySwitch(to: id, from: activeProfileID, among: profiles) else { return }
        adoptActiveProfile(id)
        selection = landing(in: id)
        await activeProfileWrite?.value
    }

    func askForProfileSheet(_ request: ProfileSheetRequest) {
        profileSheet = ProfileSheetRequest.presenting(request, over: profileSheet)
    }

    @discardableResult
    func createProfile(name: String, colour: String, symbol: String, accounts: ProfileAccountSource) async -> Profile? {
        guard let store else { return nil }
        do {
            let occupied = ProfileFolder.occupied(under: manager?.workspacesRoot ?? WorkspaceManager.workspacesRoot)
            let made = try await store.createProfile(
                name: name, colour: colour, symbol: symbol, accounts: accounts, occupiedFolders: occupied
            )
            try await reloadProfiles()
            await reload()
            await agentAccounts.reload(store: store)
            return made
        } catch {
            alert = AppAlert(title: "Could not create the profile", message: error.readableMessage)
            return nil
        }
    }

    func updateProfile(_ id: ProfileID, _ change: @Sendable (inout Profile) -> Void) async {
        guard let store else { return }
        do {
            try await store.update(profileID: id, change)
            try await reloadProfiles()
        } catch {
            alert = AppAlert(title: "Could not change the profile", message: error.readableMessage)
        }
    }

    var activeGitHubLogin: GitHubLogin {
        store?.gitHubLogin(for: activeProfileID) ?? .thisMac
    }

    func gitHubSource(of id: ProfileID) -> ProfileGitHubSource {
        store?.gitHubLogins().source(of: id) ?? .inherits
    }

    func setGitHubSource(_ source: ProfileGitHubSource, for id: ProfileID) async -> Bool {
        guard let store else { return false }
        do {
            try await store.setGitHubSource(source, for: id)
            return true
        } catch {
            return false
        }
    }

    func setAccountSource(_ source: ProfileAccountSource, for id: ProfileID) async {
        guard let store else { return }
        do {
            let cleared = try await store.setAccountSource(source, for: id)
            await reload()
            await agentAccounts.reload(store: store)
            await adoptSelectedAccounts()
            if let words = ProfileAccountNotice.cleared(cleared, repos: repos) { notice = Notice(message: words) }
        } catch {
            alert = AppAlert(title: "Could not change the profile's accounts", message: error.readableMessage)
        }
    }

    func deleteProfile(_ id: ProfileID) async {
        guard let store else { return }
        let title = "Could not delete the profile"
        do {
            try await store.deleteProfile(id: id)
            profileMemory.forget(id)
            ProfileMemoryDefaults.save(profileMemory)
            if activeProfileID == id {
                adoptActiveProfile(.initial)
                selection = landing(in: .initial)
                await activeProfileWrite?.value
            }
            try await reloadProfiles()
            await reload()
            await agentAccounts.reload(store: store)
        } catch let refusal as ProfileDeletionRefused {
            alert = AppAlert(title: title, message: refusal.sentence)
        } catch {
            alert = AppAlert(title: title, message: error.readableMessage)
        }
    }

    func moveProject(_ repoID: RepoID, to profile: ProfileID) async {
        guard let store else { return }
        let title = "Could not move the project"
        let words = repos.first { $0.id == repoID }.flatMap { repo in
            profiles.first { $0.id == profile }.flatMap { destination in
                ProfileAccountNotice.moved(
                    repo, to: destination,
                    holderName: profiles.first { $0.id == accountChoices.accounts.holder(for: profile) }?.name ?? "Unified",
                    book: accountChoices
                )
            }
        }
        do {
            try await store.move(repoID: repoID, to: profile)
            await reload()
            if let words { notice = Notice(message: words) }
        } catch let refusal as ProfileMoveRefused {
            alert = AppAlert(title: title, message: refusal.sentence)
        } catch {
            alert = AppAlert(title: title, message: error.readableMessage)
        }
    }

    func restoreLastSelection() {
        guard case .home = selection else { return }
        selection = landing(in: activeProfileID)
    }

    func activateProfile(showing selection: SidebarSelection) {
        guard let owner = ProfileNavigation.activation(
            for: selection, active: activeProfileID, workspaces: rows(naming: selection), repos: repos
        ) else { return }
        adoptActiveProfile(owner)
    }

    func rememberInActiveProfile(_ selection: SidebarSelection) {
        guard let id = selection.workspaceID else { return }
        profileMemory.remember(id, in: activeProfileID)
        ProfileMemoryDefaults.save(profileMemory)
    }

    func settleSelectionInActiveProfile() {
        narrowHomeFilterToActiveProfile()
        guard let landing = ProfileNavigation.settled(
            selection,
            active: activeProfileID,
            memory: profileMemory,
            workspaces: rows(naming: selection),
            repos: repos
        ) else { return }
        selection = landing
    }

    func narrowHomeFilterToActiveProfile() {
        let narrowed = ProfileNavigation.narrowed(homeFilter, to: activeProfileID, repos: repos)
        if homeFilter != narrowed { homeFilter = narrowed }
    }

    func saveActiveProfile(_ id: ProfileID) {
        guard let store else { return }
        let earlier = activeProfileWrite
        activeProfileWrite = Task { [weak self] in
            await earlier?.value
            do {
                try await store.setActiveProfile(id)
            } catch {
                self?.alert = AppAlert(title: "Could not remember the profile", message: error.readableMessage)
            }
        }
    }

    private func landing(in profile: ProfileID) -> SidebarSelection {
        ProfileNavigation.landing(in: profile, memory: profileMemory, workspaces: workspaces, repos: repos)
    }

    private func rows(naming selection: SidebarSelection) -> [Workspace] {
        guard let id = selection.archivedWorkspaceID, let row = workspaceModels[id]?.workspace else {
            return workspaces
        }
        return workspaces + [row]
    }
}
