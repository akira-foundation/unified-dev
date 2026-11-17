import Foundation

extension PreviewScenarioSeeder {
    public func seedAgentAccounts(
        _ scenario: PreviewScenario,
        home: URL?,
        at now: Date
    ) throws -> Int {
        guard !scenario.accounts.isEmpty else { return 0 }
        guard let home else { throw PreviewScenarioError.noTranscriptHome }

        var written = 0
        for account in scenario.accounts {
            guard let place = Self.place(of: account, home: home) else { continue }
            written += 1
            guard !account.missing else { continue }
            try FileManager.default.createDirectory(
                at: place.directory, withIntermediateDirectories: true
            )
            for (url, body) in files(of: account, at: place, expiring: now) {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try Data(body.utf8).write(to: url)
            }
        }
        return written
    }

    static func target(
        of handoff: PreviewScenario.Handoff, among accounts: [PreviewScenario.Account]
    ) -> SessionSegmentTarget {
        let account = handoff.account.flatMap { label in
            accounts.first { $0.provider == handoff.agent && $0.label == label }
        }
        return SessionSegmentTarget(
            agentKind: handoff.agent, accountID: account?.id, model: handoff.model, effort: "",
            accountName: account?.email
        )
    }

    static func place(of account: PreviewScenario.Account, home: URL) -> AgentAccountHome? {
        guard let label = account.label else { return AgentAccountHome.defaultHome(for: account.provider, home: home) }
        return AgentAccountHome(
            provider: account.provider,
            id: account.id,
            directory: home
                .appending(path: "accounts", directoryHint: .isDirectory)
                .appending(path: account.provider.rawValue, directoryHint: .isDirectory)
                .appending(path: label, directoryHint: .isDirectory),
            isDefault: false,
            label: label
        )
    }

    func seedAccountRows(
        _ scenario: PreviewScenario,
        profiles: [String: ProfileID] = [:],
        home: URL?
    ) async throws {
        guard !scenario.accounts.isEmpty else { return }
        guard let home else { throw PreviewScenarioError.noTranscriptHome }
        for account in scenario.accounts where account.label != nil {
            guard let place = Self.place(of: account, home: home) else { continue }
            let owner = account.profile.flatMap { profiles[$0.lowercased()] } ?? .initial
            try await manager.store.addIfMissing(AgentAccountRow(
                id: place.id, provider: place.provider, directory: place.directory.path, label: place.label,
                profileID: owner
            ))
        }
    }

    func seedAccountChoices(
        _ scenario: PreviewScenario,
        repos: [String: RepoID],
        profiles: [String: ProfileID] = [:],
        home: URL?
    ) async throws {
        guard let home else { return }
        try await seedAccountRows(scenario, profiles: profiles, home: home)
        for account in scenario.accounts where account.label != nil && account.isProfileDefault {
            guard let place = Self.place(of: account, home: home) else { continue }
            let owner = account.profile.flatMap { profiles[$0.lowercased()] } ?? .initial
            try await manager.store.chooseAgentAccount(ChosenAgentAccount(place), forProfile: owner)
        }
        for project in scenario.projects {
            guard let repoID = repos[project.name] else { continue }
            for (key, label) in project.accounts {
                guard let provider = AgentKind(rawValue: key),
                      let account = scenario.accounts.first(where: { $0.provider == provider && $0.label == label }),
                      let place = Self.place(of: account, home: home)
                else { continue }
                try await AgentAccountAssignment.choose(ChosenAgentAccount(place), forRepo: repoID, in: manager.store)
            }
        }
    }

    private func files(
        of account: PreviewScenario.Account,
        at place: AgentAccountHome,
        expiring now: Date
    ) -> [(URL, String)] {
        let expiry = now.addingTimeInterval(60 * 60 * 24 * 30)
        switch account.provider {
        case .codex:
            return [(place.credentialPath, codexAuth(account, expiring: expiry))]
        default:
            return [
                (place.identityPath, claudeIdentity(account)),
                (place.credentialPath, claudeCredential(account, expiring: expiry)),
            ]
        }
    }

    private func claudeIdentity(_ account: PreviewScenario.Account) -> String {
        let members = [
            "\"emailAddress\":\"\(escaped(account.email))\"",
            "\"displayName\":\"\(escaped(account.displayName ?? account.email))\"",
            "\"organizationName\":\"\(escaped(account.organisation ?? "Preview"))\"",
        ]
        return "{\"oauthAccount\":{" + members.joined(separator: ",") + "}}"
    }

    private func claudeCredential(_ account: PreviewScenario.Account, expiring: Date) -> String {
        let subscription = (account.plan ?? "max").lowercased().replacingOccurrences(of: " ", with: "_")
        let tier = account.rateLimitTier.map { "\"rateLimitTier\":\"\(escaped($0))\"," } ?? ""
        return "{\"claudeAiOauth\":{\"subscriptionType\":\"\(escaped(subscription))\"," + tier
            + "\"expiresAt\":\(Int(expiring.timeIntervalSince1970 * 1000))}}"
    }

    private func codexAuth(_ account: PreviewScenario.Account, expiring: Date) -> String {
        let claims = "{\"email\":\"\(escaped(account.email))\","
            + "\"name\":\"\(escaped(account.displayName ?? account.email))\","
            + "\"exp\":\(Int(expiring.timeIntervalSince1970)),"
            + "\"https://api.openai.com/auth\":{\"chatgpt_plan_type\":\"\(escaped(account.plan ?? "pro"))\"}}"
        let token = [base64URL("{\"alg\":\"none\"}"), base64URL(claims), "not-a-signature"]
            .joined(separator: ".")
        return "{\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"\(token)\"}}"
    }

    private func base64URL(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
