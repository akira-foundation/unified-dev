import Foundation

public enum ForgeKind: String, Sendable, Hashable, CaseIterable {
    case gitHub
    case bitbucket

    public var displayName: String {
        switch self {
        case .gitHub: "GitHub"
        case .bitbucket: "Bitbucket"
        }
    }

    public var cli: String {
        switch self {
        case .gitHub: "gh"
        case .bitbucket: Bitbucket.executable
        }
    }

    public var checkNoun: String {
        switch self {
        case .gitHub: "check"
        case .bitbucket: "build"
        }
    }

    public var buildDefinition: String {
        switch self {
        case .gitHub: "workflow"
        case .bitbucket: "pipeline"
        }
    }

    public var buildDefinitionNotToEdit: String {
        switch self {
        case .gitHub: "a workflow"
        case .bitbucket: "bitbucket-pipelines.yml"
        }
    }
}

public struct ForgeRepository: Sendable, Hashable {
    public let kind: ForgeKind
    public let host: String
    public let owner: String
    public let name: String

    public init(kind: ForgeKind, host: String, owner: String, name: String) {
        self.kind = kind
        self.host = host
        self.owner = owner
        self.name = name
    }

    public var fullName: String { "\(owner)/\(name)".lowercased() }

    public static func kind(ofHost host: String) -> ForgeKind {
        let host = host.lowercased()
        return bitbucketCloudHosts.contains(host) ? .bitbucket : .gitHub
    }

    public static func kind(ofRemote remoteURL: String?) -> ForgeKind {
        guard let remoteURL, let host = parts(of: remoteURL)?.host else { return .gitHub }
        return kind(ofHost: host)
    }

    public static func parse(remoteURL: String) -> ForgeRepository? {
        guard let parts = parts(of: remoteURL) else { return nil }
        var segments = parts.path.split(separator: "/").map(String.init)
        guard segments.count == 2 else { return nil }
        if segments[1].hasSuffix(".git") { segments[1].removeLast(4) }
        guard segments.allSatisfy({ !$0.isEmpty && !$0.hasPrefix("-") && $0 != "." && $0 != ".." }) else { return nil }
        return ForgeRepository(
            kind: kind(ofHost: parts.host), host: parts.host, owner: segments[0], name: segments[1]
        )
    }

    private static let bitbucketCloudHosts: Set<String> = ["bitbucket.org", "www.bitbucket.org"]

    private static func parts(of remoteURL: String) -> (host: String, path: String)? {
        let remote = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if remote.contains("://") {
            guard let url = URL(string: remote), let host = url.host, !host.isEmpty else { return nil }
            return (host.lowercased(), url.path)
        }
        guard let colon = remote.firstIndex(of: ":") else { return nil }
        let authority = remote[..<colon]
        let host = authority.split(separator: "@").last.map(String.init) ?? ""
        guard !host.isEmpty, !host.contains("/") else { return nil }
        return (host.lowercased(), String(remote[remote.index(after: colon)...]))
    }
}
