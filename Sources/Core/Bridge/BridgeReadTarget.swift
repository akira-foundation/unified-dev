import Foundation

public enum BridgeReadTarget: Sendable, Equatable {
    case own(Workspace)
    case named(Workspace)
    case crossed(Workspace, Profile)

    public var workspace: Workspace {
        switch self {
        case .own(let workspace), .named(let workspace), .crossed(let workspace, _): workspace
        }
    }

    var other: Workspace? {
        switch self {
        case .own: nil
        case .named(let workspace), .crossed(let workspace, _): workspace
        }
    }

    var profile: Profile? {
        guard case .crossed(_, let profile) = self else { return nil }
        return profile
    }

    public var workspaceID: WorkspaceID { workspace.id }

    static let argument = "workspace"

    static let schemaProperty: JSONValue = .object([
        "type": .string("string"),
        "description": .string(
            "Another workspace to read, by the id workspace_list or workspace_start reports, or by "
                + "its name when no other active workspace shares it. Leave it out to read your own. "
                + "Required from a client that is not working in a workspace."
        ),
    ])

    static func resolve(
        _ request: MCPRequest, as identity: BridgeIdentity, store: Store
    ) async throws -> Result<BridgeReadTarget, BridgeReadTrouble> {
        var given: String?
        if let raw = request.param(argument), raw != .null {
            guard let text = raw.stringValue else { return .failure(.notText) }
            given = AgentStartTool.text(text)
        }
        let choice: BridgeProfileChoice
        switch try await BridgeProfileReach.choice(request, allowsEvery: false, for: .read, as: identity, store: store) {
        case .failure(let trouble): return .failure(.profile(trouble))
        case .success(let resolved): choice = resolved
        }
        if case .other(let profile) = choice {
            guard let given else { return .failure(.profileNeedsWorkspace) }
            return crossed(try await BridgeWorkspaceLookup.activeTarget(given, in: profile, store: store), given, profile)
        }
        guard let given else {
            guard let own = identity.workspaceID else { return .failure(.noWorkspaceNamed) }
            return try await ownWorkspace(own, store: store)
        }
        switch try await BridgeWorkspaceLookup.activeTarget(given, as: identity, store: store) {
        case .found(let workspace) where workspace.id == identity.workspaceID:
            return .success(.own(workspace))
        case .found(let workspace):
            return .success(.named(workspace))
        case .ambiguous(let ids):
            return .failure(.ambiguous(given: given, ids: ids))
        case .archived:
            return .failure(.archived(given: given))
        case .unknown(let known):
            return .failure(.unknown(given: given, known: known))
        }
    }

    private static func crossed(
        _ outcome: BridgeWorkspaceLookup.ActiveTarget, _ given: String, _ profile: Profile
    ) -> Result<BridgeReadTarget, BridgeReadTrouble> {
        switch outcome {
        case .found(let workspace): .success(.crossed(workspace, profile))
        case .ambiguous(let ids): .failure(.ambiguous(given: given, ids: ids))
        case .archived: .failure(.archived(given: given))
        case .unknown(let known): .failure(.unknown(given: given, known: known))
        }
    }

    private static func ownWorkspace(
        _ id: WorkspaceID, store: Store
    ) async throws -> Result<BridgeReadTarget, BridgeReadTrouble> {
        guard let workspace = try await store.workspace(id: id) else { return .failure(.callerHasGone) }
        guard workspace.state != .archived else { return .failure(.callerArchived) }
        return .success(.own(workspace))
    }
}
