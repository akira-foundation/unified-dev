import Foundation

extension Store {
    public nonisolated func gitHubLogins() -> ProfileGitHubLogins {
        gitHubLoginBook.withLock { $0 }
    }

    public nonisolated func gitHubLogin(for profile: ProfileID?) -> GitHubLogin {
        gitHubLogins().login(for: profile)
    }

    public func gitHubLogin(forDirectory directory: String) -> GitHubLogin {
        let book = gitHubLogins()
        guard let routes = try? gitHubLoginRoutes() else { return book.unresolved }
        return book.login(forDirectory: directory, routes: routes)
    }

    public func gitHubLogin(for scope: AccountScope) -> GitHubLogin {
        let book = gitHubLogins()
        if let profile = scope.profileID { return book.login(for: profile) }
        guard let repoID = scope.repoID else { return .thisMac }
        do {
            return book.login(for: try repo(id: repoID)?.profileID)
        } catch {
            return book.unresolved
        }
    }

    public func setGitHubSource(_ source: ProfileGitHubSource, for profile: ProfileID) throws {
        guard profile != .initial else { return }
        try writeGitHubSource(source, for: profile)
    }
}
