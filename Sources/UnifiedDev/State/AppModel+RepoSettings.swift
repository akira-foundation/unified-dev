import Core

extension AppModel {
    func refreshSettings(for repoID: RepoID, savedPaths: [String]) {
        let changedHome = !Set(savedPaths).isDisjoint(with: SettingsLoader.homePaths())
        for model in workspaceModels.values where changedHome || model.workspace.repoID == repoID {
            model.refreshSettings()
        }
        refreshSetupScriptPresence()
    }
}
