import Foundation

public enum BridgeProfileCaller: Sendable, Equatable {
    case owner
    case orchestrator
    case workspace
    case unasked
    case confined
}

public enum BridgeProfilePurpose: Sendable, Equatable {
    case talk
    case read
}

public enum BridgeProfileChoice: Sendable, Equatable {
    case own
    case other(Profile)
    case every(own: Profile, others: [Profile])

    public var profiles: [Profile] {
        switch self {
        case .own: []
        case .other(let profile): [profile]
        case let .every(own, others): [own] + others
        }
    }
}

public enum BridgeProfileReach {
    static let argument = "profile"
    static let everyProfile = "all"

    static let schemaProperty: JSONValue = .object([
        "type": .string("string"),
        "description": .string(
            "Another profile to act in, by its id or by a name no other reachable profile shares. "
                + "Leave it out to stay in your own. Any workspace on Claude Code can send a message to a "
                + "project's orchestrator there; reading its chats and diffs is left to a project's "
                + "orchestrator and the owner's own clients. Only a profile the owner has opened can be "
                + "reached, a workspace's own profile must be open too, and a workspace reaches one only from a "
                + "chat launched in Accept edits, where the owner approves every call that names one."
        ),
    ])

    static let listSchemaProperty: JSONValue = .object([
        "type": .string("string"),
        "description": .string(
            "Another profile to list, by its id or by a name no other reachable profile shares, or "
                + "'all' for your own and every other you can reach. Leave it out to stay in your own. "
                + "Any workspace on Claude Code can list another profile the owner has opened, when its own "
                + "is open too, from a chat launched in Accept edits, where the owner approves every call that names one. Each "
                + "row then says which profile it belongs to."
        ),
    ])

    public static func mayCross(
        _ caller: BridgeProfileCaller, for purpose: BridgeProfilePurpose, ownOpen: Bool, targetOpen: Bool
    ) -> Bool {
        switch caller {
        case .owner: targetOpen
        case .orchestrator: ownOpen && targetOpen
        case .workspace: purpose == .talk && ownOpen && targetOpen
        case .unasked, .confined: false
        }
    }

    public static func caller(of identity: BridgeIdentity, store: Store) async throws -> BridgeProfileCaller {
        switch identity.role {
        case .owner:
            return .owner
        case .workspace:
            guard let workspaceID = identity.workspaceID, let sessionID = identity.sessionID,
                  let workspace = try await store.workspace(id: workspaceID), workspace.state == .active,
                  let session = try await store.session(id: sessionID),
                  session.workspaceID == workspaceID, session.agentKind != .codex
            else { return .confined }
            let leads = identity.launchedOrchestrating && workspace.isOrchestrator && session.parentSessionID == nil
            guard !leads else { return .orchestrator }
            guard session.agentKind == .claudeCode else { return .confined }
            return identity.launchedAsking ? .workspace : .unasked
        }
    }

    public static func asksTheOwner(_ mode: PermissionMode) -> Bool {
        mode == .acceptEdits
    }

    public static func lists(_ workspace: Workspace, to caller: BridgeProfileCaller) -> Bool {
        switch caller {
        case .owner, .orchestrator: true
        case .workspace, .unasked, .confined: OrchestratorRole.leads(workspace)
        }
    }

    public static func mayLeaveOwnProfile(
        _ identity: BridgeIdentity, for purpose: BridgeProfilePurpose, store: Store
    ) async throws -> Bool {
        let caller = try await caller(of: identity, store: store)
        guard let own = try await BridgeProfileScope.profile(of: identity, store: store) else { return false }
        return mayCross(
            caller, for: purpose, ownOpen: await ProfileBridgeSwitch.isOn(profile: own, in: store), targetOpen: true
        )
    }

    public static func reachable(
        from identity: BridgeIdentity, for purpose: BridgeProfilePurpose, store: Store
    ) async throws -> [Profile] {
        let caller = try await caller(of: identity, store: store)
        guard let own = try await BridgeProfileScope.profile(of: identity, store: store) else { return [] }
        let ownOpen = await ProfileBridgeSwitch.isOn(profile: own, in: store)
        var open: [Profile] = []
        for profile in try await store.profiles() where profile.id != own {
            let targetOpen = await ProfileBridgeSwitch.isOn(profile: profile.id, in: store)
            if mayCross(caller, for: purpose, ownOpen: ownOpen, targetOpen: targetOpen) { open.append(profile) }
        }
        return open
    }

    static func choice(
        _ request: MCPRequest,
        allowsEvery: Bool,
        for purpose: BridgeProfilePurpose,
        as identity: BridgeIdentity,
        store: Store
    ) async throws -> Result<BridgeProfileChoice, BridgeProfileTrouble> {
        guard let raw = request.param(argument), raw != .null else { return .success(.own) }
        guard let text = raw.stringValue else { return .failure(.notText) }
        guard let given = AgentStartTool.text(text) else { return .success(.own) }

        guard let ownID = try await BridgeProfileScope.profile(of: identity, store: store),
              let own = try await store.profile(id: ownID)
        else { return .failure(.unreachable(given: given)) }

        let others = try await reachable(from: identity, for: purpose, store: store)
        if allowsEvery, given.caseInsensitiveCompare(everyProfile) == .orderedSame {
            guard try await mayLeaveOwnProfile(identity, for: purpose, store: store) else {
                return .failure(.unreachable(given: given))
            }
            return .success(.every(own: own, others: others))
        }
        let found = find(given, own: own, others: others)
        guard case .failure(.unreachable) = found else { return found }
        return try await BridgeProfileReachRefusal.plain(
            given, own: own, purpose: purpose, allowsEvery: allowsEvery, as: identity, store: store
        ) ?? found
    }

    private static func find(
        _ given: String, own: Profile, others: [Profile]
    ) -> Result<BridgeProfileChoice, BridgeProfileTrouble> {
        let candidates = [own] + others
        let byID = candidates.first { $0.id.rawValue.caseInsensitiveCompare(given) == .orderedSame }
        let byName = candidates.filter { $0.name.caseInsensitiveCompare(given) == .orderedSame }
        if byID == nil, byName.count > 1 {
            return .failure(.ambiguous(given: given, ids: byName.map(\.id.rawValue)))
        }
        guard let found = byID ?? byName.first else { return .failure(.unreachable(given: given)) }
        return .success(found.id == own.id ? .own : .other(found))
    }

    static func tagged(_ row: JSONValue, profile: Profile) -> JSONValue {
        guard case .object(var fields) = row else { return row }
        fields["profile"] = .string(profile.name)
        return .object(fields)
    }
}
