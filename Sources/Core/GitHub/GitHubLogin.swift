import Foundation

public enum GitHubLogin: Sendable, Hashable {
    case thisMac
    case profile(ProfileID, directory: URL, uses: ProfileForgeChoice = .own)
    case unresolved(directory: URL)

    public static let directoryVariable = "GH_CONFIG_DIR"
    public static let tokenVariables = ["GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN"]
    public static let signedOutToken = "unified-dev-profile-signed-out"

    public var directory: URL? {
        switch self {
        case .thisMac: nil
        case .profile(_, let directory, let uses): uses.gitHub == .own ? directory : nil
        case .unresolved(let directory): directory
        }
    }

    public var ownsGitHub: Bool {
        guard case .profile(_, _, let uses) = self else { return false }
        return uses.gitHub == .own
    }

    public var hostsHoldingTokens: Set<String> {
        guard ownsGitHub, let directory else { return [] }
        return GitHubHostsFile.hostsHoldingTokens(in: directory)
    }

    public var variables: [String: String] {
        guard let directory else { return [:] }
        var result = Dictionary(uniqueKeysWithValues: Self.tokenVariables.map { ($0, "") })
        result[Self.directoryVariable] = directory.path
        let holding = hostsHoldingTokens
        if !holding.contains(GitHubHostsFile.publicHost) { result["GH_TOKEN"] = Self.signedOutToken }
        if holding.subtracting([GitHubHostsFile.publicHost]).isEmpty {
            result["GH_ENTERPRISE_TOKEN"] = Self.signedOutToken
        }
        return result
    }

    public var bitbucket: BitbucketLogin { BitbucketLogin(gitHub: self) }

    public var everyVariable: [String: String] {
        variables.merging(bitbucket.variables) { gitHub, _ in gitHub }
    }

    public func applied(to environment: [String: String]) -> [String: String] {
        guard directory != nil else { return environment }
        return signInEnvironment(from: environment).merging(variables.filter { !$0.value.isEmpty }) { _, login in login }
    }

    public func everySignIn(appliedTo environment: [String: String]) -> [String: String] {
        BitbucketSignIn.environment(applied(to: environment), login: bitbucket)
    }

    public func signInEnvironment(from environment: [String: String]) -> [String: String] {
        guard let directory else { return environment }
        var result = environment
        for name in Self.tokenVariables { result.removeValue(forKey: name) }
        result[Self.directoryVariable] = directory.path
        return result
    }

    public var signInArguments: [String] {
        directory == nil ? ["auth", "login"] : ["auth", "login", "--insecure-storage"]
    }

    public var acceptsSignIn: Bool {
        switch self {
        case .thisMac, .profile: true
        case .unresolved: false
        }
    }

    public var signInCommand: String {
        let command = (["gh"] + signInArguments).joined(separator: " ")
        guard let directory else { return command }
        return "\(Self.directoryVariable)=\(BridgeRegistration.shellQuoted(directory.path)) \(command)"
    }

    public func prepare() throws {
        guard ownsGitHub, let directory else { return }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
    }
}
