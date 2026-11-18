import Foundation

enum BridgeProfileReachRefusal {
    static func ownSide(_ identity: BridgeIdentity, store: Store) async throws -> BridgeProfileTrouble? {
        switch try await BridgeProfileReach.caller(of: identity, store: store) {
        case .owner, .orchestrator, .workspace: nil
        case .unasked: .launchedUnasked
        case .confined: .agentConfined
        }
    }

    static func plain(
        _ given: String,
        purpose: BridgeProfilePurpose,
        as identity: BridgeIdentity,
        store: Store
    ) async throws -> Result<BridgeProfileChoice, BridgeProfileTrouble>? {
        guard purpose == .read, try await BridgeProfileReach.caller(of: identity, store: store) == .workspace else { return nil }
        let talkable = try await BridgeProfileReach.reachable(from: identity, for: .talk, store: store)
        return names(given, among: talkable) ? .failure(.readsGoThroughOrchestrator(given: given)) : nil
    }

    static func names(_ given: String, among profiles: [Profile]) -> Bool {
        profiles.contains { profile in
            profile.id.rawValue.caseInsensitiveCompare(given) == .orderedSame
                || profile.name.caseInsensitiveCompare(given) == .orderedSame
        }
    }
}
