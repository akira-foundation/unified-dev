import Foundation

public struct ProfileListTool: BridgeToolHandling {
    public init() {}

    public static let name = "profile_list"

    public let roles: Set<BridgeRole> = [.workspace, .owner]

    public let tool = BridgeTool(
        name: Self.name,
        description: """
            The profiles this connection can act in: its own, whether the owner has opened it so that \
            others can reach it, and every other open profile it can reach, by id and name. A profile \
            that is not open to others can still reach out to the open ones. Pass one of those as profile \
            to project_list, workspace_list or workspace_say, or 'all' to the two lists.

            When this chat can reach no other profile, the answer says which condition it does not meet: \
            it was not launched in Accept edits, or it runs on an agent that never crosses. A profile that \
            is not listed is either closed or does not exist, and Unified Dev does not say which.

            From a workspace chat, every call stops for the owner's approval, because it names other \
            profiles. Takes no arguments. Read only.
            """,
        inputSchema: BridgeTool.noArguments
    )

    public func call(
        _ request: MCPRequest,
        as identity: BridgeIdentity,
        store: Store
    ) async -> BridgeToolResult {
        do {
            guard let ownID = try await BridgeProfileScope.profile(of: identity, store: store),
                  let own = try await store.profile(id: ownID)
            else { return .failure("This connection belongs to no profile Unified Dev still has.") }

            let held = try await BridgeProfileReachRefusal.ownSide(identity, store: store)
            let others = held == nil ? try await BridgeProfileReach.reachable(from: identity, for: .talk, store: store) : []
            let answer: JSONValue = .object([
                "own": .object([
                    "id": .string(own.id.rawValue),
                    "name": .string(own.name),
                    "open_to_others": .bool(await ProfileBridgeSwitch.isOn(profile: own.id, in: store)),
                ]),
                "reachable": .array(others.map { .object(["id": .string($0.id.rawValue), "name": .string($0.name)]) }),
                "note": .string(held?.sentence ?? Self.note(reachesAny: !others.isEmpty)),
            ])
            guard identity.role == .workspace else { return .json(answer) }
            return BridgeWorkspaceQuote.answer(answer, preamble: BridgeWorkspaceQuote.lists("profiles"))
        } catch {
            return .failure("Unified Dev could not read its profiles: \(error.readableMessage)")
        }
    }

    static func note(reachesAny: Bool) -> String {
        guard reachesAny else {
            return "No other profile is open to this connection. The owner opens one in that profile's "
                + "settings; tell the owner which one you need."
        }
        return "Pass a profile's id, or a name no other listed profile shares, as profile to project_list, "
            + "workspace_list or workspace_say."
    }
}
