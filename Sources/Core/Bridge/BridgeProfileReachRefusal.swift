import Foundation

enum BridgeProfileReachRefusal {
    static func ownSide(_ identity: BridgeIdentity, own: Profile, store: Store) async throws -> BridgeProfileTrouble? {
        switch try await BridgeProfileReach.caller(of: identity, store: store) {
        case .owner:
            return nil
        case .unasked:
            return .launchedUnasked
        case .confined:
            return .agentConfined
        case .orchestrator, .workspace:
            return await ProfileBridgeSwitch.isOn(profile: own.id, in: store) ? nil : .ownProfileClosed(own: own.name)
        }
    }

    static func plain(
        _ given: String,
        own: Profile,
        purpose: BridgeProfilePurpose,
        allowsEvery: Bool,
        as identity: BridgeIdentity,
        store: Store
    ) async throws -> Result<BridgeProfileChoice, BridgeProfileTrouble>? {
        switch purpose {
        case .read:
            guard try await BridgeProfileReach.caller(of: identity, store: store) == .workspace else { return nil }
            let talkable = try await BridgeProfileReach.reachable(from: identity, for: .talk, store: store)
            return names(given, among: talkable) ? .failure(.readsGoThroughOrchestrator(given: given)) : nil
        case .talk:
            guard !allowsEvery, try await BridgeProfileReach.mayLeaveOwnProfile(identity, for: .talk, store: store)
            else { return nil }
            var closed: [Profile] = []
            for profile in try await store.profiles() where profile.id != own.id {
                if await !ProfileBridgeSwitch.isOn(profile: profile.id, in: store) { closed.append(profile) }
            }
            return names(given, among: closed) ? .failure(.closedToOutside(given: given)) : nil
        }
    }

    static func names(_ given: String, among profiles: [Profile]) -> Bool {
        profiles.contains { profile in
            profile.id.rawValue.caseInsensitiveCompare(given) == .orderedSame
                || profile.name.caseInsensitiveCompare(given) == .orderedSame
        }
    }
}
