import SwiftUI
import Core

struct ProfileBitbucketSection: View {
    let profile: Profile

    @Environment(AppModel.self) private var app

    @State private var account: BitbucketAccount?
    @State private var installed = true
    @State private var isChecking = true
    @State private var signIn: BitbucketSignInSheet.Request?
    @State private var refresh = 0

    private var login: BitbucketLogin {
        (app.store?.gitHubLogin(for: profile.id) ?? .thisMac).bitbucket
    }

    private var source: ProfileGitHubSource {
        app.gitHubSource(of: profile.id)
    }

    var body: some View {
        Section {
            LabeledContent(ProfileBitbucketWording.accountTitle) {
                Text(accountText)
                    .foregroundStyle(account?.user == nil ? .secondary : .primary)
            }
            if let method = account?.methodName {
                LabeledContent(ProfileBitbucketWording.methodTitle, value: method)
            }
            if login.isOwn, installed {
                Menu(ProfileBitbucketWording.signInMenuTitle) {
                    ForEach(BitbucketLogin.Method.allCases, id: \.self) { method in
                        Button(ProfileBitbucketWording.methodTitle(method)) { start(method) }
                            .help(ProfileBitbucketWording.methodSummary(method))
                    }
                }
                .fixedSize()
                .disabled(isChecking)
            }
        } header: {
            Text(ProfileBitbucketWording.sectionTitle)
        } footer: {
            Text(
                ProfileBitbucketWording.footnote(
                    source: source, isInitial: profile.isInitial, profileName: profile.name,
                    account: account, installed: installed
                )
            )
            .settingsFootnote()
        }
        .task(id: "\(profile.id.rawValue).\(source.rawValue).\(refresh)") {
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

    private var accountText: String {
        if isChecking { return ProfileBitbucketWording.checking }
        if !installed { return ProfileBitbucketWording.notInstalled }
        return account?.user ?? ProfileBitbucketWording.notSignedIn
    }

    private func start(_ method: BitbucketLogin.Method) {
        signIn = BitbucketSignInSheet.Request(login: login, method: method, profileName: profile.name)
    }
}
