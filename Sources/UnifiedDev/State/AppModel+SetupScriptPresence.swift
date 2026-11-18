import AppKit
import Core

extension AppModel {
    func refreshSetupScriptPresence() {
        setupScriptPresenceTask?.cancel()
        setupScriptPresenceGeneration += 1
        let generation = setupScriptPresenceGeneration
        let repos = repos
        let workspaces = workspaces
        setupScriptPresenceTask = Task { [weak self] in
            let read = await Task.detached(priority: .utility) {
                SetupScriptPresence.read(repos: repos, workspaces: workspaces)
            }.value
            guard !Task.isCancelled, let self else { return }
            guard generation == self.setupScriptPresenceGeneration else {
                self.refreshSetupScriptPresence()
                return
            }
            if self.setupScriptPresence != read { self.setupScriptPresence = read }
        }
    }

    func recordSetupScript(_ hasSetupScript: Bool, forRepoID repoID: RepoID) {
        setupScriptPresenceGeneration += 1
        var presence = setupScriptPresence
        presence.record(repoID: repoID, hasSetupScript: hasSetupScript)
        if presence != setupScriptPresence { setupScriptPresence = presence }
    }

    func followSetupScriptPresenceOnActivation() {
        setupScriptPresenceActivationTask?.cancel()
        setupScriptPresenceActivationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                self?.refreshSetupScriptPresence()
            }
        }
    }

    func askToRunSetup(_ workspace: Workspace) {
        let model = model(for: workspace)
        Task {
            await model.reloadSettings()
            SetupRunAlert.shared.ask(model)
        }
    }
}
