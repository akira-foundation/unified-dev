import SwiftUI
import Core

struct RepoOrchestratorSection: View {
    let repo: Repo

    static let copy = RepoSettingSwitchCopy(
        title: OrchestratorUnaskedCommands.settingTitle,
        header: OrchestratorUnaskedCommands.settingHeader,
        caveat: OrchestratorUnaskedCommands.caveat,
        saveFailure: OrchestratorUnaskedCommands.saveFailure
    )

    var body: some View {
        RepoSettingSwitch(
            repo: repo,
            copy: Self.copy,
            read: { await OrchestratorUnaskedCommands.isOn(repoID: $0, in: $1) },
            write: { try await OrchestratorUnaskedCommands.save($0, repoID: $1, to: $2) }
        )
    }
}
