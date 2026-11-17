import Foundation
import Testing
@testable import Core

@Suite("The Git Hosting pane: which account each profile uses, and what each row says")
struct GitHostingTests {
    private let root = URL(filePath: "/support/GitHubLogins", directoryHint: .isDirectory)
    private let unified = Profile(id: .initial, name: "Unified", folder: "unified", colour: Accent.all[0], symbol: "star")
    private let akira = Profile(id: ProfileID("akira"), name: "Akira", folder: "akira", colour: Accent.all[1], symbol: "leaf")
    private let debtges = Profile(
        id: ProfileID("debtges"), name: "Debtges", folder: "debtges", colour: Accent.all[2], symbol: "briefcase"
    )

    @Test("a profile on this Mac's account shows this Mac's, and one with its own shows its own, never this Mac's")
    func whichAccount() {
        let mac = GitHostingAccount.signedIn("kid")

        #expect(GitHosting.account(source: .inherits, thisMac: mac, own: .signedIn("bot")) == mac)
        #expect(GitHosting.account(source: .own, thisMac: mac, own: .signedOut) == .signedOut)
        #expect(GitHosting.account(source: .own, thisMac: mac, own: nil) == .checking)
        #expect(GitHosting.account(source: .own, thisMac: .notInstalled, own: nil) == .notInstalled)
    }

    @Test("rows put Unified first, fixed on this Mac's account, and read each host's choice on its own")
    func rows() {
        let logins = ProfileGitHubLogins(sources: [debtges.id: .own], bitbucketSources: [akira.id: .own], root: root)
        let own: [ProfileID: GitHostingAccount] = [akira.id: .signedIn("akira-bot")]

        let bitbucket = GitHosting.rows(
            on: .bitbucket, profiles: [akira, debtges, unified], logins: logins, thisMac: .signedIn("kid"), own: own
        )
        #expect(bitbucket.map(\.name) == ["Unified", "Akira", "Debtges"])
        #expect(bitbucket[0].choosesSource == false)
        #expect(bitbucket[1].account == .signedIn("akira-bot"))
        #expect(bitbucket[2].account == .signedIn("kid"))
        #expect(bitbucket[2].usesThisMac)

        let gitHub = GitHosting.rows(
            on: .gitHub, profiles: [akira, debtges, unified], logins: logins, thisMac: .signedIn("kid"), own: [:]
        )
        #expect(gitHub[1].source == .inherits)
        #expect(gitHub[2].source == .own)
        #expect(gitHub[2].account == .checking)
        #expect(GitHosting.profilesWithOwnLogin(on: .gitHub, profiles: [unified, akira, debtges], logins: logins) == [debtges.id])
    }

    @Test("sign-in is offered on a profile row only once its own sign-in is known and the CLI is there")
    func canSignIn() {
        func row(_ source: ProfileGitHubSource, _ account: GitHostingAccount, choosing: Bool = true) -> GitHostingProfileRow {
            GitHostingProfileRow(profileID: akira.id, name: "Akira", source: source, choosesSource: choosing, account: account)
        }

        #expect(row(.own, .signedOut).canSignIn)
        #expect(row(.own, .signedIn("bot")).canSignIn)
        #expect(!row(.own, .checking).canSignIn)
        #expect(!row(.own, .notInstalled).canSignIn)
        #expect(!row(.inherits, .signedOut).canSignIn)
        #expect(!row(.own, .signedOut, choosing: false).canSignIn)
    }

    @Test("each row says whose account it is, beside the choice that says where it comes from", arguments: [
        (ProfileGitHubSource.inherits, GitHostingAccount.signedIn("kid"), "kid"),
        (.inherits, .signedOut, "Not signed in"),
        (.own, .signedIn("bot"), "bot"),
        (.own, .signedOut, "Not signed in"),
        (.own, .checking, "Checking"),
        (.own, .notInstalled, "The Bitbucket CLI is not installed"),
    ])
    func profileStatus(source: ProfileGitHubSource, account: GitHostingAccount, expected: String) {
        let row = GitHostingProfileRow(profileID: akira.id, name: "Akira", source: source, choosesSource: true, account: account)
        #expect(GitHostingWording.status(row.account, on: .bitbucket) == expected)
    }

    @Test("this Mac's row says who, or why not, and the footer says what to install")
    func thisMacWording() {
        #expect(GitHostingWording.status(.signedIn("kid"), on: .gitHub) == "kid")
        #expect(GitHostingWording.status(.notInstalled, on: .gitHub) == "The GitHub CLI is not installed")
        #expect(GitHostingWording.signInTitle(.bitbucket, account: .signedOut) == "Sign In to Bitbucket")
        #expect(GitHostingWording.signInTitle(.gitHub, account: .signedIn("kid")) == "Sign In to Another Account")
        #expect(GitHostingWording.thisMacFooter(.bitbucket, account: .notInstalled).contains("brew install bitbucket-cli"))
        #expect(GitHostingWording.thisMacFooter(.bitbucket, account: .signedOut).contains("Pipelines"))
        #expect(GitHostingWording.signOutMessage(.gitHub, user: "kid").hasPrefix("gh forgets kid on this Mac."))
        #expect(GitHostingWording.signOutFailure(.bitbucket, detail: "") == "Could not sign out of Bitbucket. bkt did not say why.")
    }

    @Test("sign out names the account to gh only when it is a real login, and asks bkt for the Cloud host")
    func signOutArguments() {
        #expect(GitHub.signOutArguments(user: "kid") == ["auth", "logout", "--hostname", "github.com", "--user", "kid"])
        #expect(GitHub.signOutArguments(user: nil) == ["auth", "logout", "--hostname", "github.com"])
        #expect(GitHub.signOutArguments(user: "--all") == ["auth", "logout", "--hostname", "github.com"])
        #expect(Bitbucket.signOutArguments == ["auth", "logout", "api.bitbucket.org"])
    }

    @Test("an account the tool reads is signed in, a missing one is signed out, or not installed")
    func accountFromReading() {
        #expect(GitHostingAccount(user: "kid", installed: true) == .signedIn("kid"))
        #expect(GitHostingAccount(user: nil, installed: true) == .signedOut)
        #expect(GitHostingAccount(user: nil, installed: false) == .notInstalled)
    }
}
