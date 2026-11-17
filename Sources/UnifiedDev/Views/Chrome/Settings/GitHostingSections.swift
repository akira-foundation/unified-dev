import SwiftUI
import Core

enum GitHostingSignIn: Hashable {
    case thisMac(BitbucketLogin.Method?)
    case profile(ProfileID, BitbucketLogin.Method?)
}

struct GitHostingSections: View {
    let host: ForgeKind
    let account: GitHostingAccount
    let rows: [GitHostingProfileRow]
    var isBusy = false
    var onSignIn: (GitHostingSignIn) -> Void = { _ in }
    var onSignOut: () -> Void = {}
    var onChoose: (ProfileID, ProfileGitHubSource) -> Void = { _, _ in }

    var body: some View {
        Section {
            LabeledContent(GitHostingWording.thisMacTitle) {
                Text(GitHostingWording.status(account, on: host))
                    .foregroundStyle(account.user == nil ? .secondary : .primary)
                    .textSelection(.enabled)
            }
            if account.isSettled, account != .notInstalled {
                signIn(GitHostingWording.signInTitle(host, account: account)) { .thisMac($0) }
                if GitHosting.canSignOut(host, account: account) {
                    Button(GitHostingWording.signOutTitle, role: .destructive, action: onSignOut)
                        .disabled(isBusy)
                }
            }
        } header: {
            Text(host.displayName)
        } footer: {
            Text(GitHostingWording.thisMacFooter(host, account: account))
                .settingsFootnote()
        }

        Section {
            ForEach(rows) { row in
                profileRow(row)
            }
        } header: {
            Text(GitHostingWording.profilesHeader(host))
        } footer: {
            Text(GitHostingWording.profilesFooter(host))
                .settingsFootnote()
        }
    }

    @ViewBuilder
    private func profileRow(_ row: GitHostingProfileRow) -> some View {
        if row.choosesSource {
            Picker(selection: choice(row)) {
                ForEach(ProfileGitHubSource.allCases, id: \.self) { source in
                    Text(GitHostingWording.sourceLabel(source)).tag(source)
                }
            } label: {
                Text(row.name)
                Text(GitHostingWording.status(row.account, on: host))
            }
            .disabled(isBusy)
            if row.canSignIn {
                signIn(GitHostingWording.signInFor(host, profileName: row.name)) { .profile(row.profileID, $0) }
            }
        } else {
            LabeledContent {
                Text(GitHostingWording.sourceLabel(row.source))
                    .foregroundStyle(.secondary)
            } label: {
                Text(row.name)
                Text(GitHostingWording.status(row.account, on: host))
            }
        }
    }

    @ViewBuilder
    private func signIn(_ title: String, target: @escaping (BitbucketLogin.Method?) -> GitHostingSignIn) -> some View {
        switch host {
        case .gitHub:
            Button(title) { onSignIn(target(nil)) }
                .disabled(isBusy)
        case .bitbucket:
            Menu(title) {
                ForEach(BitbucketLogin.Method.allCases, id: \.self) { method in
                    Button(ProfileBitbucketWording.methodTitle(method)) { onSignIn(target(method)) }
                        .help(ProfileBitbucketWording.methodSummary(method))
                }
            }
            .fixedSize()
            .disabled(isBusy)
        }
    }

    private func choice(_ row: GitHostingProfileRow) -> Binding<ProfileGitHubSource> {
        Binding(get: { row.source }, set: { onChoose(row.profileID, $0) })
    }
}
