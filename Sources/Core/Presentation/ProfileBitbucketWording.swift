import Foundation

public enum ProfileBitbucketWording {
    public static let sectionTitle = "Bitbucket"
    public static let accountTitle = "Signed in as"
    public static let methodTitle = "Signed in with"
    public static let notSignedIn = "Not signed in"
    public static let notInstalled = "The Bitbucket CLI is not installed"
    public static let checking = "Checking"
    public static let signInMenuTitle = "Sign In to Bitbucket"

    public static func methodTitle(_ method: BitbucketLogin.Method) -> String {
        switch method {
        case .browser: "In the Browser (OAuth)"
        case .apiToken: "With an API Token"
        }
    }

    public static func methodSummary(_ method: BitbucketLogin.Method) -> String {
        switch method {
        case .browser:
            "Bitbucket opens in the browser, you approve bkt there, and it refreshes the sign-in by itself."
        case .apiToken:
            "Atlassian's API token page opens, and bkt asks in the terminal for the email and the token."
        }
    }

    public static func footnote(
        source: ProfileGitHubSource, isInitial: Bool, profileName: String, account: BitbucketAccount?, installed: Bool
    ) -> String {
        guard installed else {
            return "Install the Bitbucket CLI with brew install bitbucket-cli to read pull requests on Bitbucket."
        }
        let user = account?.user
        if isInitial || source == .inherits {
            let owner = isInitial ? "Unified" : "\(profileName) follows its GitHub choice above and"
            return "\(owner) uses this Mac's bkt sign-in, "
                + (user.map { "signed in as \($0)." } ?? "which is signed out.")
        }
        guard let user else {
            return "\(profileName) follows its GitHub choice above, so it keeps a Bitbucket sign-in of its own "
                + "and never uses this Mac's. Pull requests and agents in its Bitbucket projects stop until you "
                + "sign in here. App passwords are retired by Atlassian: use the browser or an API token."
        }
        return "Pull requests, builds and agents in \(profileName)'s Bitbucket projects run as \(user)."
    }
}
