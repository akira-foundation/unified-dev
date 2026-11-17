import Foundation

public extension GitHub {
    static func signOutArguments(user: String?) -> [String] {
        let named = user.map { isPlausibleLogin($0) ? ["--user", $0] : [] } ?? []
        return ["auth", "logout", "--hostname", GitHubHostsFile.publicHost] + named
    }

    static func signOut(user: String?, login: GitHubLogin = .thisMac) async -> ShellResult? {
        let arguments = signOutArguments(user: user)
        if let commandOverride { return try? await $login.withValue(login) { try await commandOverride(arguments, nil) } }
        await LoginShellPath.ready()
        return try? await Shell.run("gh", arguments, env: login.variables, timeout: .seconds(20))
    }
}
