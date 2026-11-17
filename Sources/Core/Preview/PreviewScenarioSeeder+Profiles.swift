import Foundation

extension PreviewScenarioSeeder {
    static let initialKey = PreviewScenario.initialProfileName.lowercased()

    func seedProfiles(_ scenario: PreviewScenario) async throws -> [String: ProfileID] {
        var ids = [Self.initialKey: ProfileID.initial]
        for profile in scenario.profiles {
            let created = try await manager.store.createProfile(
                name: profile.name, colour: profile.colour, symbol: profile.symbol,
                accounts: profile.accounts,
                occupiedFolders: ProfileFolder.occupied(under: manager.workspacesRoot)
            )
            ids[profile.name.lowercased()] = created.id
            try await manager.store.setGitHubSource(profile.github, for: created.id)
        }
        for name in scenario.reachableProfiles {
            if let id = ids[name.lowercased()] {
                try await ProfileBridgeSwitch.save(true, profile: id, to: manager.store)
            }
        }
        return ids
    }
}
