import Foundation

public struct BitbucketAccount: Sendable, Hashable {
    public let user: String?
    public let method: String?

    public init(user: String?, method: String?) {
        self.user = user
        self.method = method
    }

    public var methodName: String? {
        switch method?.lowercased() {
        case "oauth": "Browser sign-in (OAuth)"
        case "basic": "API token"
        case "bearer": "Access token"
        case let other?: other
        case nil: nil
        }
    }
}

public extension Bitbucket {
    static func access(directory: String) async -> GitHubAccess {
        await access(login: GitHub.login(forDirectory: directory).bitbucket, directory: directory)
    }

    static func access(login: BitbucketLogin, directory: String) async -> GitHubAccess {
        guard await account(login: login, directory: directory) != nil else {
            return Shell.which(executable) == nil ? .notInstalled : .signedOut
        }
        return .ready
    }

    static func account(login: BitbucketLogin, directory: String) async -> BitbucketAccount? {
        if commandOverride == nil {
            await LoginShellPath.ready()
            guard Shell.which(executable) != nil else { return nil }
        }
        guard let result = try? await run(["auth", "status", "--json"], directory: directory, login: login), result.ok, let status = BitbucketAuthStatus.decode(result.stdout),
              let host = status.cloudHost
        else { return nil }
        return BitbucketAccount(user: host.username, method: host.authMethod)
    }
}
