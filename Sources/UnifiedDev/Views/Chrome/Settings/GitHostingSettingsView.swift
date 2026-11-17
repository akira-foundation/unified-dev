import SwiftUI
import Core

struct GitHostingSettingsView: View {
    @Environment(AppModel.self) private var app

    @State private var model = GitHostingModel()
    @State private var isSaving = false
    @State private var saveFailure: String?
    @State private var confirmingSignOut: ForgeKind?
    @State private var gitHubSignIn: GitHubSignIn.Request?
    @State private var bitbucketSignIn: BitbucketSignInSheet.Request?
    @State private var refresh = 0

    private var logins: ProfileGitHubLogins? { app.store?.gitHubLogins() }

    var body: some View {
        Form {
            if let failure = model.failure ?? saveFailure {
                Section {
                    ErrorBanner(title: GitHostingWording.paneTitle, message: failure) {
                        model.failure = nil
                        saveFailure = nil
                    }
                }
            }
            ForEach(GitHosting.hosts, id: \.self) { host in
                GitHostingSections(
                    host: host,
                    account: model.account(on: host),
                    rows: logins.map { model.rows(on: host, profiles: app.profiles, logins: $0) } ?? [],
                    isBusy: isSaving || model.signingOut != nil,
                    onSignIn: { signIn($0, on: host) },
                    onSignOut: { confirmingSignOut = host },
                    onChoose: { choose($1, for: $0, on: host) }
                )
            }
        }
        .settingsForm()
        .task(id: refresh) { await model.load(store: app.store, profiles: app.profiles) }
        .confirmationDialog(
            confirmingSignOut.map(GitHostingWording.signOutQuestion) ?? "",
            isPresented: Binding(get: { confirmingSignOut != nil }, set: { if !$0 { confirmingSignOut = nil } }),
            titleVisibility: .visible,
            presenting: confirmingSignOut
        ) { host in
            Button(GitHostingWording.signOutTitle, role: .destructive) {
                Task { await model.signOut(host) }
            }
        } message: { host in
            Text(GitHostingWording.signOutMessage(host, user: model.account(on: host).user ?? ""))
        }
        .sheet(item: $gitHubSignIn) { pending in
            GitHubSignInSheet(request: pending) { _ in
                gitHubSignIn = nil
                refresh += 1
            }
        }
        .sheet(item: $bitbucketSignIn) { pending in
            BitbucketSignInSheet(request: pending) {
                bitbucketSignIn = nil
                refresh += 1
            }
        }
    }

    private func signIn(_ target: GitHostingSignIn, on host: ForgeKind) {
        let login: GitHubLogin
        let profileName: String
        let method: BitbucketLogin.Method?
        switch target {
        case .thisMac(let chosen):
            if model.isSeeded { return model.restoreSeededSignIn(host) }
            login = .thisMac
            profileName = GitHostingWording.thisMacOwner
            method = chosen
        case .profile(let id, let chosen):
            guard !model.isSeeded, let store = app.store else { return }
            login = store.gitHubLogin(for: id)
            profileName = app.profiles.first { $0.id == id }?.name ?? id.rawValue
            method = chosen
        }
        switch host {
        case .gitHub:
            gitHubSignIn = GitHubSignIn.Request(
                access: model.account(on: host) == .notInstalled ? .notInstalled : .signedOut,
                directory: AgentScratchDirectory.current(),
                login: login
            )
        case .bitbucket:
            guard let method else { return }
            bitbucketSignIn = BitbucketSignInSheet.Request(login: login.bitbucket, method: method, profileName: profileName)
        }
    }

    private func choose(_ source: ProfileGitHubSource, for profile: ProfileID, on host: ForgeKind) {
        guard !isSaving else { return }
        isSaving = true
        saveFailure = nil
        Task {
            if await !app.setSource(source, for: profile, on: host) {
                saveFailure = ProfileGitHubWording.saveFailure
            }
            isSaving = false
            refresh += 1
        }
    }
}
