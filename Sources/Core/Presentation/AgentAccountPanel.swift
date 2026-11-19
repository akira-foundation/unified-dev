import Foundation

public struct AgentAccountPanel: Sendable, Equatable {
    public static let unknown = "unknown"
    public static let sessionLabel = "Session"

    public struct Field: Sendable, Equatable, Identifiable {
        public let label: String
        public let value: String

        public var id: String { label }
        public var isKnown: Bool { value != AgentAccountPanel.unknown }
    }

    public struct Row: Sendable, Equatable, Identifiable {
        public let id: AgentAccountID
        public let home: AgentAccountHome
        public let title: String
        public let fields: [Field]
        public let note: String?
        public let offersSignInAgain: Bool
        public let warns: Bool
        public let removal: AgentAccountRemoval.Warning?
        public let isUnfinished: Bool

        public var isDefault: Bool { home.isDefault }
        public var signInAgainHome: AgentAccountHome? { offersSignInAgain ? home : nil }
    }

    public struct Owner: Sendable, Equatable {
        public let name: String
        public let holderName: String
        public let inherits: Bool
        public let refusesWithoutAccount: Bool
        public let defaultAccount: AgentAccountID?
        public let choosers: [AgentAccountID: [String]]

        public init(
            name: String,
            holderName: String,
            inherits: Bool,
            refusesWithoutAccount: Bool,
            defaultAccount: AgentAccountID?,
            choosers: [AgentAccountID: [String]] = [:]
        ) {
            self.name = name
            self.holderName = holderName
            self.inherits = inherits
            self.refusesWithoutAccount = refusesWithoutAccount
            self.defaultAccount = defaultAccount
            self.choosers = choosers
        }

        public static func make(
            for provider: AgentKind,
            in profile: ProfileID,
            profiles: [Profile],
            repos: [Repo] = [],
            book: AgentAccountChoiceBook,
            standings: [AgentAccountStanding]
        ) -> Owner {
            let holder = book.accounts.holder(for: profile)
            let name = { (id: ProfileID) in profiles.first { $0.id == id }?.name ?? "Unified" }
            var choosers: [AgentAccountID: [String]] = [:]
            for repo in repos {
                guard let id = book.repos[repo.id]?[provider] else { continue }
                choosers[id, default: []].append(repo.name)
            }
            return Owner(
                name: name(profile),
                holderName: name(holder),
                inherits: holder != profile,
                refusesWithoutAccount: refusesLaunch(
                    of: provider, in: profile, book: book, standings: standings
                ),
                defaultAccount: book.profiles[holder]?[provider],
                choosers: choosers
            )
        }

        private static func refusesLaunch(
            of provider: AgentKind,
            in profile: ProfileID,
            book: AgentAccountChoiceBook,
            standings: [AgentAccountStanding]
        ) -> Bool {
            let stored = book.choices(repoID: nil, profileID: profile)
            let choice = AgentAccountChoice.resolve(
                provider: provider,
                project: stored.project[provider],
                profile: stored.profile[provider],
                standings: book.accounts.reachable(standings, from: profile)
            )
            let launch = AgentAccountLaunch.decide(
                choice: choice,
                provider: provider,
                outsideUnified: book.accounts.keepsOwnAccounts(profile)
            )
            guard case .refused = launch else { return false }
            return true
        }
    }

    public static func make(
        provider: AgentKind,
        in profile: ProfileID,
        profiles: [Profile],
        repos: [Repo] = [],
        book: AgentAccountChoiceBook,
        standings: [AgentAccountStanding],
        orphans: [AgentAccountHome] = [],
        codexStorageMode: CodexAuthStorageMode
    ) -> AgentAccountPanel {
        make(
            provider: provider,
            standings: book.accounts.listed(standings, in: profile),
            orphans: orphans,
            codexStorageMode: codexStorageMode,
            owner: Owner.make(
                for: provider, in: profile, profiles: profiles, repos: repos, book: book, standings: standings
            )
        )
    }

    public let provider: AgentKind
    public let rows: [Row]
    public let offer: AgentAccountOffer
    public let footer: String?

    public static func make(
        provider: AgentKind,
        standings: [AgentAccountStanding],
        orphans: [AgentAccountHome] = [],
        codexStorageMode: CodexAuthStorageMode,
        owner: Owner? = nil,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> AgentAccountPanel {
        let mine = standings.filter { $0.home.provider == provider }
        return AgentAccountPanel(
            provider: provider,
            rows: mine.map {
                row(for: $0, among: standings, owner: owner, locale: locale, timeZone: timeZone)
            } + orphans.filter { $0.provider == provider }.map(unfinishedRow),
            offer: AgentAccountOffer.make(for: provider, codexStorageMode: codexStorageMode),
            footer: footer(provider: provider, owner: owner, isEmpty: mine.isEmpty)
        )
    }

    private static func footer(provider: AgentKind, owner: Owner?, isEmpty: Bool) -> String? {
        guard let owner else { return nil }
        if owner.inherits {
            return "\(owner.name) uses the accounts of \(owner.holderName). Choose its own in Profile Settings."
        }
        guard isEmpty, provider.canRunWorkspaces else { return nil }
        guard owner.refusesWithoutAccount else {
            return "\(owner.name) has no \(provider.label) account of its own, "
                + "so its projects run \(provider.label) under this Mac's own login."
        }
        return "\(owner.name) has no \(provider.label) account of its own, so its projects do not start \(provider.label) until one is added."
    }

    static func unfinishedRow(for home: AgentAccountHome) -> Row {
        let title = home.directory.lastPathComponent
        return Row(
            id: home.id,
            home: home,
            title: title,
            fields: [Field(label: sessionLabel, value: "Sign-in did not finish")],
            note: "Unified Dev never added this account, because its sign-in did not finish. The folder is still on this Mac.",
            offersSignInAgain: false,
            warns: true,
            removal: AgentAccountRemoval.warningForUnfinishedSignIn(named: title, provider: home.provider),
            isUnfinished: true
        )
    }

    static func row(
        for standing: AgentAccountStanding,
        among standings: [AgentAccountStanding],
        owner: Owner? = nil,
        locale: Locale,
        timeZone: TimeZone
    ) -> Row {
        let home = standing.home
        let title = AgentAccountNames.title(of: standing, among: standings)
        let note = note(for: standing, owner: owner)
        return Row(
            id: home.id,
            home: home,
            title: title,
            fields: [
                Field(label: "Email", value: standing.identity.email ?? unknown),
                Field(label: "Plan", value: standing.identity.plan ?? unknown),
                Field(
                    label: "Expires",
                    value: standing.identity.expiresAt.map { expiry($0, locale: locale, timeZone: timeZone) } ?? unknown
                ),
                Field(label: sessionLabel, value: session(of: standing)),
            ],
            note: note.text,
            offersSignInAgain: AgentAccountSignInAgain.isOffered(for: standing),
            warns: note.warns,
            removal: home.isDefault
                ? nil
                : AgentAccountRemoval.warning(
                    forAccountNamed: title,
                    provider: home.provider,
                    folderExists: standing.directoryExists,
                    chosenBy: owner?.choosers[home.id] ?? []
                ),
            isUnfinished: false
        )
    }

    static func session(of standing: AgentAccountStanding) -> String {
        guard standing.directoryExists else { return standing.home.isDefault ? "Not set up" : "Folder missing" }
        return switch standing.cliReport {
        case .claimsSession: "Signed in"
        case .claimsNoSession: "Not signed in"
        case .unanswered: "Not confirmed"
        }
    }

    private static func note(for standing: AgentAccountStanding, owner: Owner?) -> (text: String?, warns: Bool) {
        let home = standing.home
        var sentences: [String] = []
        if let role = role(of: home, owner: owner) { sentences.append(role) }
        if home.isDefault { return (sentences.first, false) }
        if !standing.directoryExists {
            sentences.append("This account's folder is no longer on this Mac.")
        }
        if let doubt = standing.isolationDoubt {
            sentences.append("Unified Dev does not guarantee this account stays separate for \(home.provider.label). \(doubt)")
        }
        let warns = !standing.directoryExists || standing.isolationDoubt != nil
        return (sentences.isEmpty ? nil : sentences.joined(separator: " "), warns)
    }

    private static func role(of home: AgentAccountHome, owner: Owner?) -> String? {
        guard let owner else {
            return home.isDefault ? "Used wherever a project has not chosen another account." : nil
        }
        if owner.defaultAccount == home.id || (owner.defaultAccount == nil && home.isDefault) {
            return "The default account of \(owner.holderName), used wherever a project has not chosen another."
        }
        guard home.isDefault else { return nil }
        return "This Mac's own login, used when the default account of \(owner.holderName) is not available."
    }

    private static func expiry(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone))
    }
}
