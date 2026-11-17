import Foundation

public struct AgentAccountOptions: Sendable, Equatable {
    public enum Scope: Sendable, Hashable {
        case profile
        case project
    }

    public enum Pick: Sendable, Hashable {
        case inherit
        case unavailable
        case account(AgentAccountID)
    }

    public struct Entry: Sendable, Equatable, Identifiable {
        public let pick: Pick
        public let title: String
        public let home: AgentAccountHome?

        public var id: Pick { pick }
    }

    public struct Group: Sendable, Equatable, Identifiable {
        public let provider: AgentKind
        public let inherit: Entry
        public let entries: [Entry]
        public let unavailable: Entry?
        public let selected: Pick
        public let note: String
        public let warns: Bool

        public var id: AgentKind { provider }
        public var title: String { provider.label }

        public var selectedTitle: String {
            ([inherit] + entries + [unavailable].compactMap(\.self))
                .first { $0.pick == selected }?.title ?? inherit.title
        }

        public func chosen(for pick: Pick) -> ChosenAgentAccount? {
            switch pick {
            case .inherit:
                return ChosenAgentAccount(inheritedBy: provider)
            case .unavailable:
                return nil
            case .account:
                guard let home = entries.first(where: { $0.pick == pick })?.home else { return nil }
                return ChosenAgentAccount(home)
            }
        }
    }

    public let groups: [Group]
    public let footer: String?

    public var offersToAddAnAccount: Bool { groups.isEmpty }

    public static let addAnAccount =
        "To run another account, add one in Settings, under Agents, with Add account\u{2026}"

    public static func make(
        scope: Scope = .project,
        choices: AgentAccountChoices,
        standings: [AgentAccountStanding],
        outsideProfile: Bool = false
    ) -> AgentAccountOptions {
        let present = standings.filter { $0.directoryExists || $0.home.isDefault }
        let groups = AgentKind.allCases.compactMap { provider in
            group(
                scope: scope,
                provider: provider,
                stored: scope == .profile ? choices.profile[provider] : choices.project[provider],
                inherited: scope == .profile ? nil : choices.profile[provider],
                present: present,
                standings: standings,
                outsideProfile: outsideProfile
            )
        }
        return AgentAccountOptions(
            groups: groups,
            footer: groups.isEmpty ? AgentAccountOptionsNote.nothingToOffer(scope, outsideProfile: outsideProfile) : nil
        )
    }

    private static func group(
        scope: Scope,
        provider: AgentKind,
        stored: AgentAccountID?,
        inherited: AgentAccountID?,
        present: [AgentAccountStanding],
        standings: [AgentAccountStanding],
        outsideProfile: Bool
    ) -> Group? {
        let mine = present.filter { $0.home.provider == provider }
        let offersDefaults = scope == .project && inherited != nil
        let offered = mine.filter { offersDefaults || !$0.home.isDefault || $0.home.id == stored }
        guard !offered.isEmpty || stored != nil || inherited != nil else { return nil }

        let own = AgentAccountOptionsNote.Reach(stored, in: mine)
        let selected: Pick = switch own {
        case .present(let found): .account(found.home.id)
        case .gone: .unavailable
        case .none: .inherit
        }
        let words = AgentAccountOptionsNote.make(
            scope: scope,
            agent: provider.label,
            own: own,
            profile: AgentAccountOptionsNote.Reach(inherited, in: mine),
            standings: standings,
            outsideProfile: outsideProfile
        )

        return Group(
            provider: provider,
            inherit: Entry(
                pick: .inherit,
                title: inheritTitle(scope, followsProfile: inherited != nil, outsideProfile: outsideProfile),
                home: nil
            ),
            entries: offered.map {
                Entry(
                    pick: .account($0.home.id),
                    title: AgentAccountNames.title(of: $0, among: standings),
                    home: $0.home
                )
            },
            unavailable: own.isGone ? Entry(pick: .unavailable, title: "Unavailable account", home: nil) : nil,
            selected: selected,
            note: words.text,
            warns: words.warns
        )
    }

    private static func inheritTitle(_ scope: Scope, followsProfile: Bool, outsideProfile: Bool) -> String {
        switch scope {
        case .profile: outsideProfile ? "No account" : "Default account"
        case .project where followsProfile: "Same as profile"
        case .project: outsideProfile ? "No account" : "Default account"
        }
    }
}
