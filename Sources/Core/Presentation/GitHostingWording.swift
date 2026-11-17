import Foundation

public enum GitHostingWording {
    public static let paneTitle = "Git Hosting"
    public static let thisMacTitle = "This Mac"
    public static let thisMacOwner = "this Mac"
    public static let signOutTitle = "Sign Out"
    public static let signedInUnnamed = "Signed in"

    public static func cli(_ host: ForgeKind) -> String {
        switch host {
        case .gitHub: "gh"
        case .bitbucket: "bkt"
        }
    }

    public static func install(_ host: ForgeKind) -> String {
        switch host {
        case .gitHub: "brew install gh"
        case .bitbucket: "brew install bitbucket-cli"
        }
    }

    public static func status(_ account: GitHostingAccount, on host: ForgeKind) -> String {
        switch account {
        case .checking: ProfileGitHubWording.checking
        case .notInstalled: "The \(host.displayName) CLI is not installed"
        case .signedOut: ProfileGitHubWording.notSignedIn
        case .signedIn(let user): user
        }
    }

    public static func sourceLabel(_ source: ProfileGitHubSource) -> String {
        switch source {
        case .inherits: "This Mac's account"
        case .own: "Its own sign-in"
        }
    }

    public static func signInTitle(_ host: ForgeKind, account: GitHostingAccount) -> String {
        account.user == nil ? "Sign In to \(host.displayName)" : "Sign In to Another Account"
    }

    public static func thisMacFooter(_ host: ForgeKind, account: GitHostingAccount) -> String {
        if account == .notInstalled {
            return "Install the \(host.displayName) CLI with \(install(host)) to sign in."
        }
        let uses = switch host {
        case .gitHub: "pull requests, checks and agents"
        case .bitbucket: "cloning, pull requests, Pipelines and agents"
        }
        return "Read from \(cli(host))'s own sign-in. Unified, and every profile that uses this Mac's account, "
            + "use it for \(uses)."
    }

    public static func profilesFooter(_ host: ForgeKind) -> String {
        "A profile with its own sign-in never falls back to this Mac's account, even while it is signed out. "
            + "Sign in for it here or in the profile's settings."
    }

    public static func profilesHeader(_ host: ForgeKind) -> String {
        "\(host.displayName) Profiles"
    }

    public static func signInFor(_ host: ForgeKind, profileName: String) -> String {
        "Sign In for \(profileName)"
    }

    public static func signOutQuestion(_ host: ForgeKind) -> String {
        "Sign out of \(host.displayName) on this Mac?"
    }

    public static func signOutMessage(_ host: ForgeKind, user: String) -> String {
        "\(cli(host)) forgets \(user) on this Mac. Unified, and every profile that uses this Mac's account, "
            + "stop at \(host.displayName) until you sign in again. The token is not revoked."
    }

    public static func signOutFailure(_ host: ForgeKind, detail: String?) -> String {
        let reason = detail.flatMap { $0.isEmpty ? nil : $0 } ?? "\(cli(host)) did not say why."
        return "Could not sign out of \(host.displayName). \(reason)"
    }
}
