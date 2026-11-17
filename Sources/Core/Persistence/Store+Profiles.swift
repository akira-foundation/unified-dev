import Foundation

public enum ProfileDeletionRefused: Error, Equatable {
    case initial
    case hasProjects(count: Int)

    public static func refusal(for id: ProfileID, projectCount: Int) -> ProfileDeletionRefused? {
        if id == .initial { return .initial }
        return projectCount > 0 ? .hasProjects(count: projectCount) : nil
    }

    public var sentence: String {
        switch self {
        case .initial:
            "The Unified profile cannot be deleted."
        case .hasProjects(let count):
            "This profile still has \(Counted.of(count, "project")). "
                + "Move \(count == 1 ? "it" : "them") to another profile first."
        }
    }
}

public enum ProfileMoveRefused: Error, Equatable {
    case unknownProfile

    public var sentence: String {
        switch self {
        case .unknownProfile: "That profile is no longer in Unified Dev."
        }
    }
}

extension Store {
    private static let activeProfileKey = "profile.active"

    public func createProfile(
        name: String,
        colour: String,
        symbol: String,
        accounts: ProfileAccountSource = .own,
        occupiedFolders: Set<String> = []
    ) throws -> Profile {
        let existing = try profiles()
        let taken = Set(existing.map(\.folder)).union([ProfileID.initial.rawValue]).union(occupiedFolders)
        let profile = Profile(
            id: .new(),
            name: name,
            folder: ProfileFolder.name(for: name, taken: taken),
            colour: colour,
            symbol: symbol,
            sortOrder: (existing.map(\.sortOrder).max() ?? 0) + 1
        )
        try inTransaction {
            try insertProfileRow(profile)
            _ = try writeAccountSource(accounts, for: profile.id)
        }
        return profile
    }

    @discardableResult
    public func update(
        profileID: ProfileID,
        _ change: @Sendable (inout Profile) -> Void
    ) throws -> Profile? {
        guard let stored = try profile(id: profileID) else { return nil }
        var changed = stored
        change(&changed)
        let row = Profile(
            id: stored.id,
            name: changed.name,
            folder: stored.folder,
            colour: changed.colour,
            symbol: changed.symbol,
            sortOrder: changed.sortOrder,
            createdAt: stored.createdAt
        )
        try writeProfileRow(row)
        return row
    }

    @discardableResult
    public func move(repoID: RepoID, to profile: ProfileID) throws -> Repo? {
        guard try self.profile(id: profile) != nil else { throw ProfileMoveRefused.unknownProfile }
        return try inTransaction {
            let moved = try update(repoID: repoID) { $0.profileID = profile }
            _ = try clearStrayChoices(in: profile, only: repoID)
            return moved
        }
    }

    public func deleteProfile(id: ProfileID) throws {
        let projects = try projectCount(profileID: id)
        if let refusal = ProfileDeletionRefused.refusal(for: id, projectCount: projects) { throw refusal }
        try inTransaction {
            try returnAccountsToInitial(from: id)
            try removeProfileRow(id: id)
        }
        try refreshGitHubLogins()
    }

    public func workSuggestionSource(_ suggestion: WorkSuggestion) throws -> WorkSuggestionProfile.Source {
        guard let workspaceID = suggestion.workspaceID else { return .noWorkspace }
        guard let source = try workspace(id: workspaceID) else { return .workspace(nil) }
        return .workspace(try repo(id: source.repoID)?.profileID)
    }

    public func activeProfileID() throws -> ProfileID {
        guard let value = try setting(Self.activeProfileKey), !value.isEmpty else { return .initial }
        return try profile(id: ProfileID(value))?.id ?? .initial
    }

    public func setActiveProfile(_ id: ProfileID) throws {
        try setSetting(Self.activeProfileKey, id.rawValue)
    }
}
