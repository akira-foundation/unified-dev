import Foundation

public enum PullRequestLoad: Sendable, Equatable {
    case loading
    case listed([PullRequestListing])
    case unavailable(String)

    public var requests: [PullRequestListing] {
        guard case .listed(let requests) = self else { return [] }
        return requests
    }

    public var isListed: Bool {
        guard case .listed = self else { return false }
        return true
    }

    public var note: String? {
        switch self {
        case .loading: "Loading pull requests"
        case .listed(let requests): requests.isEmpty ? "No open pull requests" : nil
        case .unavailable(let sentence): sentence
        }
    }

    public static func from(
        access: GitHubAccess, failure: String?, requests: [PullRequestListing], forge: ForgeKind = .gitHub
    ) -> Self {
        switch (access, forge) {
        case (.notInstalled, .gitHub): return .unavailable("Install the GitHub CLI to list pull requests")
        case (.signedOut, .gitHub): return .unavailable("Sign in with gh to list pull requests")
        case (.notInstalled, .bitbucket): return .unavailable("Install the Bitbucket CLI to list pull requests")
        case (.signedOut, .bitbucket): return .unavailable("Sign in with bkt to list pull requests")
        case (.ready, _): return failure.map(PullRequestLoad.unavailable) ?? .listed(requests)
        }
    }

    public static func read(repoPath: String, offered: Bool) async -> Self {
        guard offered else { return .listed([]) }
        let forge = await Forge.kind(forDirectory: repoPath)
        let access = await ForgePullRequests.access(directory: repoPath)
        guard access == .ready else { return from(access: access, failure: nil, requests: [], forge: forge) }
        do {
            return .listed(try await ForgePullRequests.openPullRequests(repoPath: repoPath))
        } catch {
            return from(access: access, failure: error.readableMessage, requests: [], forge: forge)
        }
    }
}
