import Foundation

public struct ChecksWording: Sendable, Hashable {
    public let forge: ForgeKind

    public init(forge: ForgeKind) {
        self.forge = forge
    }

    public func cannotAskTitle(access: GitHubAccess) -> String {
        switch (forge, access) {
        case (.gitHub, .notInstalled): "The GitHub CLI is not installed"
        case (.gitHub, _): "GitHub is not connected"
        case (.bitbucket, .notInstalled): "The Bitbucket CLI is not installed"
        case (.bitbucket, _): "Bitbucket is not connected"
        }
    }

    public func cannotAskMessage(access: GitHubAccess) -> String {
        switch (forge, access) {
        case (.gitHub, .notInstalled): "Checks come from GitHub through the gh command, and it is not on this Mac."
        case (.gitHub, _): "Checks come from GitHub through the gh command, and it is signed out."
        case (.bitbucket, .notInstalled):
            "Builds come from Bitbucket through the bkt command, and it is not on this Mac. "
                + "Install it with brew install bitbucket-cli."
        case (.bitbucket, _):
            "Builds come from Bitbucket through the bkt command, and it is signed out. "
                + "Sign in to Bitbucket from the profile's settings."
        }
    }

    public func cannotAskAction(access: GitHubAccess) -> String? {
        guard forge == .gitHub else { return nil }
        return access == .notInstalled ? "Install the GitHub CLI" : "Connect GitHub"
    }

    public func summary(access: GitHubAccess) -> String {
        switch (forge, access) {
        case (.gitHub, .notInstalled): "No GitHub CLI"
        case (.gitHub, _): "GitHub not connected"
        case (.bitbucket, .notInstalled): "No Bitbucket CLI"
        case (.bitbucket, _): "Bitbucket not connected"
        }
    }

    public var unreadable: String {
        switch forge {
        case .gitHub:
            "GitHub did not let this token read check runs. A fine-grained personal "
                + "access token cannot be given that permission, so their results are unknown."
        case .bitbucket:
            "Bitbucket did not let this sign-in read the builds of this commit, so their results are unknown."
        }
    }

    public var none: String {
        switch forge {
        case .gitHub: "GitHub has not reported a check run for this branch."
        case .bitbucket: "Bitbucket has not reported a build for this branch."
        }
    }

    public var loading: String { "Asking \(forge.displayName)" }
}
