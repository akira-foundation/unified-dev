import Foundation

public enum GitHostingAccount: Sendable, Hashable {
    case checking
    case notInstalled
    case signedOut
    case signedIn(String)

    public var user: String? {
        guard case .signedIn(let user) = self else { return nil }
        return user
    }

    public var isSettled: Bool { self != .checking }

    public init(user: String?, installed: Bool) {
        if let user {
            self = .signedIn(user)
        } else {
            self = installed ? .signedOut : .notInstalled
        }
    }
}

public struct GitHostingProfileRow: Sendable, Hashable, Identifiable {
    public let profileID: ProfileID
    public let name: String
    public let source: ProfileGitHubSource
    public let choosesSource: Bool
    public let account: GitHostingAccount

    public var id: ProfileID { profileID }
    public var usesThisMac: Bool { source == .inherits }
    public var canSignIn: Bool { choosesSource && source == .own && account != .notInstalled && account.isSettled }

    public init(
        profileID: ProfileID, name: String, source: ProfileGitHubSource, choosesSource: Bool, account: GitHostingAccount
    ) {
        self.profileID = profileID
        self.name = name
        self.source = source
        self.choosesSource = choosesSource
        self.account = account
    }
}

public enum GitHosting {
    public static let hosts: [ForgeKind] = [.gitHub, .bitbucket]

    public static func account(
        source: ProfileGitHubSource, thisMac: GitHostingAccount, own: GitHostingAccount?
    ) -> GitHostingAccount {
        switch source {
        case .inherits: thisMac
        case .own:
            if thisMac == .notInstalled { .notInstalled } else { own ?? .checking }
        }
    }

    public static func rows(
        on host: ForgeKind,
        profiles: [Profile],
        logins: ProfileGitHubLogins,
        thisMac: GitHostingAccount,
        own: [ProfileID: GitHostingAccount]
    ) -> [GitHostingProfileRow] {
        let ordered = profiles.filter(\.isInitial) + profiles.filter { !$0.isInitial }
        return ordered.map { profile in
            let source = logins.source(of: profile.id, on: host)
            return GitHostingProfileRow(
                profileID: profile.id,
                name: profile.name,
                source: source,
                choosesSource: !profile.isInitial,
                account: account(source: source, thisMac: thisMac, own: own[profile.id])
            )
        }
    }

    public static func profilesWithOwnLogin(
        on host: ForgeKind, profiles: [Profile], logins: ProfileGitHubLogins
    ) -> [ProfileID] {
        profiles.filter { !$0.isInitial && logins.source(of: $0.id, on: host) == .own }.map(\.id)
    }
}
