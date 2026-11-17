import SwiftUI
import Core

struct RepoPullRequestAutoFixSection: View {
    let repo: Repo

    var body: some View {
        RepoSettingSwitch(
            repo: repo,
            copy: RepoSettingSwitchCopy(
                title: PullRequestAutoFixSetting.settingTitle,
                header: PullRequestAutoFixSetting.settingHeader,
                caveat: PullRequestAutoFixSetting.caveat,
                saveFailure: PullRequestAutoFixSetting.saveFailure
            ),
            read: { await PullRequestAutoFixSetting.isOn(repoID: $0, in: $1) },
            write: { try await PullRequestAutoFixSetting.save($0, repoID: $1, to: $2) }
        )
    }
}
