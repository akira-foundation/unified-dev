import Foundation

public enum ProfileGitHubWording {
    public static let sectionTitle = "GitHub"
    public static let pickerTitle = "GitHub login"
    public static let accountTitle = "Signed in as"
    public static let notSignedIn = "Not signed in"
    public static let checking = "Checking"
    public static let saveFailure = "This could not be saved, so it is as it was."

    public static func label(_ source: ProfileGitHubSource) -> String {
        switch source {
        case .inherits: "Unified's"
        case .own: "Its own"
        }
    }

    public static func signInTitle(isSignedIn: Bool) -> String {
        isSignedIn ? "Sign In to Another Account" : "Sign In to GitHub"
    }

    public static func footnote(
        source: ProfileGitHubSource, isInitial: Bool, profileName: String, user: String?
    ) -> String {
        if isInitial {
            return "Unified uses this Mac's GitHub CLI login, "
                + (user.map { "signed in as \($0)." } ?? "which is signed out.")
        }
        switch source {
        case .inherits:
            return "\(profileName) uses Unified's GitHub login, which is this Mac's, "
                + (user.map { "signed in as \($0)." } ?? "and it is signed out.")
        case .own:
            guard let user else {
                return "\(profileName) has no GitHub login yet. Pull requests, checks and agents in its "
                    + "projects stop at GitHub until you sign in here, and never use this Mac's login."
            }
            return "Pull requests, checks and agents in \(profileName)'s projects run as \(user)."
        }
    }
}
