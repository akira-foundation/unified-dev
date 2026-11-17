import SwiftUI
import Core

struct ProfileBitbucketSection: View {
    let profile: Profile

    @Environment(AppModel.self) private var app

    @State private var account: BitbucketAccount?
    @State private var installed = true
    @State private var isChecking = true
    @State private var isSaving = false
    @State private var failure: String?
    @State private var source: ProfileGitHubSource = .inherits
    @State private var signIn: BitbucketSignInSheet.Request?
    @State private var refresh = 0

    private var login: BitbucketLogin {
        (app.store?.gitHubLogin(for: profile.id) ?? .thisMac).bitbucket
    }

    var body: some View {
        ProfileBitbucketRows(
            profile: profile, source: binding, account: account, installed: installed,
            isChecking: isChecking || isSaving, failure: failure, onSignIn: start
        )
        .task(id: "\(profile.id.rawValue).\(refresh)") {
            source = app.source(of: profile.id, on: .bitbucket)
            isChecking = true
            let login = login
            let directory = AgentScratchDirectory.current()
            account = await Bitbucket.account(login: login, directory: directory)
            installed = account != nil || Shell.which(Bitbucket.executable) != nil
            isChecking = false
        }
        .sheet(item: $signIn) { pending in
            BitbucketSignInSheet(request: pending) {
                signIn = nil
                refresh += 1
            }
        }
    }

    private var binding: Binding<ProfileGitHubSource> {
        Binding(
            get: { source },
            set: { chosen in
                guard chosen != source, !isSaving else { return }
                isSaving = true
                failure = nil
                Task {
                    if await !app.setSource(chosen, for: profile.id, on: .bitbucket) {
                        failure = ProfileGitHubWording.saveFailure
                    }
                    isSaving = false
                    refresh += 1
                }
            }
        )
    }

    private func start(_ method: BitbucketLogin.Method) {
        signIn = BitbucketSignInSheet.Request(login: login, method: method, profileName: profile.name)
    }
}

struct ProfileBitbucketRows: View {
    let profile: Profile
    @Binding var source: ProfileGitHubSource
    let account: BitbucketAccount?
    let installed: Bool
    let isChecking: Bool
    var failure: String?
    let onSignIn: (BitbucketLogin.Method) -> Void

    var body: some View {
        Section {
            if !profile.isInitial {
                Picker(ProfileBitbucketWording.pickerTitle, selection: $source) {
                    ForEach(ProfileGitHubSource.allCases, id: \.self) { source in
                        Text(ProfileGitHubWording.label(source)).tag(source)
                    }
                }
                .disabled(isChecking)
            }
            LabeledContent(ProfileBitbucketWording.accountTitle) {
                Text(accountText)
                    .foregroundStyle(account?.user == nil ? .secondary : .primary)
            }
            if let method = account?.methodName {
                LabeledContent(ProfileBitbucketWording.methodTitle, value: method)
            }
            if installed {
                Menu(ProfileBitbucketWording.signInMenuTitle) {
                    ForEach(BitbucketLogin.Method.allCases, id: \.self) { method in
                        Button(ProfileBitbucketWording.methodTitle(method)) { onSignIn(method) }
                            .help(ProfileBitbucketWording.methodSummary(method))
                    }
                }
                .fixedSize()
                .disabled(isChecking)
            }
        } header: {
            Text(ProfileBitbucketWording.sectionTitle)
        } footer: {
            VStack(alignment: .leading, spacing: Metrics.spacingSmall) {
                Text(
                    ProfileBitbucketWording.footnote(
                        source: source, isInitial: profile.isInitial, profileName: profile.name,
                        account: account, installed: installed
                    )
                )
                .settingsFootnote()
                if let failure {
                    Text(failure)
                        .font(Typo.caption)
                        .foregroundStyle(Palette.negative)
                }
            }
        }
    }

    private var accountText: String {
        if isChecking { return ProfileBitbucketWording.checking }
        if !installed { return ProfileBitbucketWording.notInstalled }
        return account?.user ?? ProfileBitbucketWording.notSignedIn
    }
}
