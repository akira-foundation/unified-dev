import Foundation

public extension GitHub {
    static func signOutArguments(user: String) -> [String]? {
        guard isPlausibleLogin(user) else { return nil }
        return ["auth", "logout", "--hostname", GitHubHostsFile.publicHost, "--user", user]
    }

    static func signOut(user: String, login: GitHubLogin = .thisMac) async -> ShellResult? {
        guard let arguments = signOutArguments(user: user) else { return nil }
        if let commandOverride { return try? await $login.withValue(login) { try await commandOverride(arguments, nil) } }
        await LoginShellPath.ready()
        return try? await Shell.run("gh", arguments, env: login.variables, timeout: .seconds(20))
    }
}
