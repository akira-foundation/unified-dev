import Foundation

public enum ProfileScope {
    public static func repos(_ repos: [Repo], in profile: ProfileID) -> [Repo] {
        repos.filter { $0.profileID == profile }
    }

    public static func repo(named name: String?, in repos: [Repo], preferring profile: ProfileID) -> Repo? {
        guard let name else { return nil }
        let named = repos.filter { $0.name == name }
        return named.first { $0.profileID == profile } ?? named.first
    }

    public static func workspaces(_ workspaces: [Workspace], repos: [Repo], in profile: ProfileID) -> [Workspace] {
        let owned = Set(Self.repos(repos, in: profile).map(\.id))
        return workspaces.filter { owned.contains($0.repoID) }
    }

    public static func transcripts(
        _ matches: [TranscriptWorkspaceMatches],
        owners: [WorkspaceID: RepoID],
        repos: [Repo],
        in profile: ProfileID
    ) -> [TranscriptWorkspaceMatches] {
        let owned = Set(Self.repos(repos, in: profile).map(\.id))
        return matches.filter { match in owners[match.workspaceID].map(owned.contains) ?? false }
    }

    public static func profile(of workspace: WorkspaceID, workspaces: [Workspace], repos: [Repo]) -> ProfileID? {
        guard let row = workspaces.first(where: { $0.id == workspace }) else { return nil }
        return repos.first(where: { $0.id == row.repoID })?.profileID
    }
}

public enum ProfileShortcut {
    public static let digits = 1...9

    public static func profile(at digit: Int, among profiles: [Profile]) -> ProfileID? {
        guard digits.contains(digit), digit <= profiles.count else { return nil }
        return profiles[digit - 1].id
    }

    public static func key(at digit: Int) -> MenuShortcut {
        MenuShortcut("\(digit)", .control, .command)
    }
}
