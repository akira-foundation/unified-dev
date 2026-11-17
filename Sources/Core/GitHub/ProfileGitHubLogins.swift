import Foundation

public enum ProfileGitHubSource: String, Sendable, Hashable, CaseIterable, Codable {
    case inherits
    case own
}

public struct ProfileGitHubLogins: Sendable, Hashable {
    public let sources: [ProfileID: ProfileGitHubSource]
    public let bitbucketSources: [ProfileID: ProfileGitHubSource]
    public let root: URL

    public init(
        sources: [ProfileID: ProfileGitHubSource] = [:],
        bitbucketSources: [ProfileID: ProfileGitHubSource] = [:],
        root: URL
    ) {
        self.sources = sources
        self.bitbucketSources = bitbucketSources
        self.root = root
    }

    public static func root(support: URL) -> URL {
        support.appending(path: "GitHubLogins", directoryHint: .isDirectory)
    }

    public func source(of profile: ProfileID) -> ProfileGitHubSource {
        profile == .initial ? .inherits : sources[profile] ?? .inherits
    }

    public func bitbucketSource(of profile: ProfileID) -> ProfileGitHubSource {
        profile == .initial ? .inherits : bitbucketSources[profile] ?? .inherits
    }

    public func source(of profile: ProfileID, on host: ForgeKind) -> ProfileGitHubSource {
        choice(of: profile).source(for: host)
    }

    public func choice(of profile: ProfileID) -> ProfileForgeChoice {
        ProfileForgeChoice(gitHub: source(of: profile), bitbucket: bitbucketSource(of: profile))
    }

    public func login(for profile: ProfileID?) -> GitHubLogin {
        guard let profile else { return .thisMac }
        let choice = choice(of: profile)
        guard choice != .thisMac else { return .thisMac }
        return .profile(
            profile, directory: root.appending(path: profile.rawValue, directoryHint: .isDirectory), uses: choice
        )
    }

    public func login(forDirectory directory: String, routes: GitHubLoginRoutes) -> GitHubLogin {
        login(for: routes.profile(forDirectory: directory))
    }

    public var unresolved: GitHubLogin {
        let uses = ProfileForgeChoice(
            gitHub: sources.values.contains(.own) ? .own : .inherits,
            bitbucket: bitbucketSources.values.contains(.own) ? .own : .inherits
        )
        guard uses != .thisMac else { return .thisMac }
        return .unresolved(directory: root.appending(path: ".unresolved", directoryHint: .isDirectory), uses: uses)
    }
}
