import Foundation

public struct AgentAccountResolution: Sendable {
    public let standings: [AgentAccountStanding]
    public let choices: [AgentKind: AgentAccountChoice]
    public let runsOutsideProfile: Bool
    let stored: AgentAccountChoices

    public init(
        standings: [AgentAccountStanding],
        choices: [AgentKind: AgentAccountChoice],
        stored: AgentAccountChoices = .none,
        runsOutsideProfile: Bool = false
    ) {
        self.standings = standings
        self.choices = choices
        self.stored = stored
        self.runsOutsideProfile = runsOutsideProfile
    }

    public func choice(for provider: AgentKind) -> AgentAccountChoice {
        choices[provider] ?? AgentAccountChoice(home: nil, reason: .noAccount)
    }

    public func home(for provider: AgentKind) -> AgentAccountHome? {
        choice(for: provider).home
    }

    public func launch(for provider: AgentKind) -> AgentAccountLaunch {
        AgentAccountLaunch.decide(choice: choice(for: provider), provider: provider, outsideUnified: runsOutsideProfile)
    }

    public func launchHome(for provider: AgentKind) throws -> AgentAccountHome? {
        try launch(for: provider).home()
    }

    public var refusedProviders: Set<AgentKind> {
        Set(AgentKind.allCases.filter { launch(for: $0).isRefused })
    }

    public func isPresent(_ account: AgentAccountID) -> Bool {
        AgentAccountChoice.present(in: standings).contains { $0.id == account }
    }

    public var homes: [AgentKind: AgentAccountHome] {
        choices.compactMapValues(\.home)
    }

    public func line(for provider: AgentKind) -> AgentAccountLine {
        AgentAccountLine.make(
            choice: choice(for: provider), provider: provider, standings: standings,
            outsideProfile: runsOutsideProfile
        )
    }

    public func composerSection(repoID: RepoID?, provider: AgentKind) -> ComposerAccountSection? {
        ComposerAccountSection.make(
            repoID: repoID, provider: provider, choice: choice(for: provider), standings: standings,
            outsideProfile: runsOutsideProfile
        )
    }

    public var options: AgentAccountOptions {
        AgentAccountOptions.make(choices: stored, standings: standings, outsideProfile: runsOutsideProfile)
    }

    public var profileOptions: AgentAccountOptions {
        AgentAccountOptions.make(
            scope: .profile, choices: stored, standings: standings, outsideProfile: runsOutsideProfile
        )
    }
}

public enum AgentAccountResolver {
    public static func resolve(
        workspaceID: WorkspaceID?,
        repoID: RepoID?,
        profileID: ProfileID? = nil,
        store: Store,
        defaults: [AgentAccountHome] = SpendAccounts.defaultHomes()
    ) async throws -> AgentAccountResolution {
        var workspace: Workspace?
        if let workspaceID { workspace = try await store.workspace(id: workspaceID) }
        let project = repoID ?? workspace?.repoID
        let every = await AgentAccountInventory.standingsWithoutAsking(
            rows: try await store.agentAccounts(),
            defaults: defaults
        )
        let book = try await store.agentAccountChoices()
        let stored = book.choices(repoID: project, profileID: profileID)
        let profile = book.profile(of: project, otherwise: profileID)
        let standings = book.reachable(every, forRepo: project, otherwise: profileID)
        return AgentAccountResolution(
            standings: standings,
            choices: resolve(stored: stored, standings: standings),
            stored: stored,
            runsOutsideProfile: book.accounts.keepsOwnAccounts(profile)
        )
    }

    public static func resolve(
        stored: AgentAccountChoices,
        standings: [AgentAccountStanding]
    ) -> [AgentKind: AgentAccountChoice] {
        Dictionary(uniqueKeysWithValues: AgentKind.allCases.map { provider in
            (provider, AgentAccountChoice.resolve(
                provider: provider,
                project: stored.project[provider],
                profile: stored.profile[provider],
                standings: standings
            ))
        })
    }
}
