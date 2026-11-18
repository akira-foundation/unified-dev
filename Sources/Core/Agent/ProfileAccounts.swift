import Foundation

public enum ProfileAccountSource: String, Sendable, Hashable, CaseIterable, Codable {
    case own
    case inherits
}

public struct ProfileAccounts: Sendable, Hashable {
    public let owners: [AgentAccountID: ProfileID]
    public let sources: [ProfileID: ProfileAccountSource]

    public init(owners: [AgentAccountID: ProfileID] = [:], sources: [ProfileID: ProfileAccountSource] = [:]) {
        self.owners = owners
        self.sources = sources
    }

    public func source(of profile: ProfileID) -> ProfileAccountSource {
        profile == .initial ? .own : sources[profile] ?? .own
    }

    public func holder(for profile: ProfileID) -> ProfileID {
        source(of: profile) == .inherits ? .initial : profile
    }

    public func keepsOwnAccounts(_ profile: ProfileID?) -> Bool {
        profile.map { holder(for: $0) != .initial } ?? false
    }

    public func defaultAccountIsShared(by profiles: [Profile]) -> Bool {
        !profiles.contains { keepsOwnAccounts($0.id) }
    }

    public func owner(of account: AgentAccountHome) -> ProfileID {
        account.isDefault ? .initial : owners[account.id] ?? .initial
    }

    public func belongs(_ account: AgentAccountHome, to profile: ProfileID) -> Bool {
        owner(of: account) == holder(for: profile)
    }

    public func listed(_ standings: [AgentAccountStanding], in profile: ProfileID) -> [AgentAccountStanding] {
        standings.filter { belongs($0.home, to: profile) }
    }

    public func reachable(_ standings: [AgentAccountStanding], from profile: ProfileID) -> [AgentAccountStanding] {
        standings.filter { belongs($0.home, to: profile) || $0.home.isDefault }
    }

    public func reaches(_ id: AgentAccountID, from profile: ProfileID) -> Bool {
        AgentAccountHome.isDefaultID(id) || (owners[id] ?? .initial) == holder(for: profile)
    }

    public func strayChoices(
        _ chosen: [AgentKind: AgentAccountID], in profile: ProfileID
    ) -> [AgentKind] {
        AgentKind.allCases.filter { provider in
            guard let id = chosen[provider] else { return false }
            return !reaches(id, from: profile)
        }
    }

    public func spendLines(_ lines: [SpendAccountLine], in profile: ProfileID) -> [SpendAccountLine] {
        lines.filter { line in
            guard line.spend == .none else { return true }
            guard let id = line.accountID else { return holder(for: profile) == .initial }
            return reaches(id, from: profile)
        }
    }

    public static func migratedOwner(
        of account: AgentAccountID,
        repoChoices: [RepoID: [AgentKind: AgentAccountID]],
        repoProfiles: [RepoID: ProfileID]
    ) -> ProfileID {
        let choosers = repoChoices.filter { $0.value.values.contains(account) }.keys
        let profiles = Set(choosers.map { repoProfiles[$0] ?? .initial })
        guard profiles.count == 1, let only = profiles.first else { return .initial }
        return only
    }

    public static func migratedSource(of profile: ProfileID, owners: [AgentAccountID: ProfileID]) -> ProfileAccountSource {
        profile == .initial || owners.values.contains(profile) ? .own : .inherits
    }
}
