import Foundation

public enum PullRequestLoad: Sendable, Equatable {
    case loading
    case listed([PullRequestListing])
    case unavailable(String)

    public var requests: [PullRequestListing] {
        guard case .listed(let requests) = self else { return [] }
        return requests
    }

    public var answered: Bool {
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

    public static func from(access: GitHubAccess, failure: String?, requests: [PullRequestListing]) -> Self {
        switch access {
        case .notInstalled: return .unavailable("Install the GitHub CLI to list pull requests")
        case .signedOut: return .unavailable("Sign in with gh to list pull requests")
        case .ready: return failure.map(PullRequestLoad.unavailable) ?? .listed(requests)
        }
    }

    public static func read(repoPath: String, offered: Bool) async -> Self {
        guard offered else { return .listed([]) }
        let access = await GitHub.access(directory: repoPath)
        guard access == .ready else { return from(access: access, failure: nil, requests: []) }
        do {
            return .listed(try await GitHub.openPullRequests(repoPath: repoPath))
        } catch {
            return from(access: access, failure: error.readableMessage, requests: [])
        }
    }
}
