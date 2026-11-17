import Foundation

enum BridgeProfileReachRefusal {
    static func plain(
        _ given: String,
        own: Profile,
        purpose: BridgeProfilePurpose,
        allowsEvery: Bool,
        as identity: BridgeIdentity,
        store: Store
    ) async throws -> Result<BridgeProfileChoice, BridgeProfileTrouble>? {
        if try await BridgeProfileReach.caller(of: identity, store: store) == .unasked {
            let others = try await store.profiles().filter { $0.id != own.id }
            return names(given, among: others) ? .failure(.asksNobody(given: given)) : nil
        }
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
