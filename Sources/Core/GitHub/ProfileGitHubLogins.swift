import Foundation

public enum ProfileGitHubSource: String, Sendable, Hashable, CaseIterable, Codable {
    case inherits
    case own
}

public struct ProfileGitHubLogins: Sendable, Hashable {
    public let sources: [ProfileID: ProfileGitHubSource]
    public let root: URL

    public init(sources: [ProfileID: ProfileGitHubSource] = [:], root: URL) {
        self.sources = sources
        self.root = root
    }

    public static func root(support: URL) -> URL {
        support.appending(path: "GitHubLogins", directoryHint: .isDirectory)
    }

    public func source(of profile: ProfileID) -> ProfileGitHubSource {
        profile == .initial ? .inherits : sources[profile] ?? .inherits
    }

    public func login(for profile: ProfileID?) -> GitHubLogin {
        guard let profile, source(of: profile) == .own else { return .thisMac }
        return .profile(profile, directory: root.appending(path: profile.rawValue, directoryHint: .isDirectory))
    }

    public func login(forDirectory directory: String, routes: GitHubLoginRoutes) -> GitHubLogin {
        login(for: routes.profile(forDirectory: directory))
    }

    public var unresolved: GitHubLogin {
        guard sources.values.contains(.own) else { return .thisMac }
        return .unresolved(directory: root.appending(path: ".unresolved", directoryHint: .isDirectory))
    }
}
