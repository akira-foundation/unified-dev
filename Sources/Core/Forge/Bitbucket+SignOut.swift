import Foundation

public extension Bitbucket {
    static let signOutArguments = ["auth", "logout", BitbucketAuthStatus.cloudHostKey]

    static func signOut(login: BitbucketLogin = .thisMac, directory: String) async -> ShellResult? {
        if commandOverride == nil {
            await LoginShellPath.ready()
            guard Shell.which(executable) != nil else { return nil }
        }
        return try? await run(signOutArguments, directory: directory, login: login)
    }
}
