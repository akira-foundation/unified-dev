import Foundation

enum WorkspaceMessageComposer {
    static func compose(
        _ text: String,
        to target: Workspace,
        crossingTo destination: Profile?,
        originKnown: Bool = true,
        notify: Bool,
        as identity: BridgeIdentity,
        store: Store
    ) async throws -> WorkspaceMessage {
        let sender = try await WorkspaceSayTool.Sender.resolve(identity, store: store)
        var heard: WorkspaceMessage?
        if let source = sender.workspace {
            heard = try await store.latestWorkspaceMessage(from: target.id, to: source.id)
        }
        var sendEnd = sender.end
        if destination != nil {
            sendEnd.profile = originKnown ? try await originName(of: identity, store: store) : Self.unknown
            sendEnd.profileID = originKnown ? try await BridgeProfileScope.profile(of: identity, store: store) : nil
        }
        let projectName = try await store.repo(id: target.repoID)?.name ?? ""
        return WorkspaceMessage(
            source: sendEnd,
            target: WorkspaceMessageEnd(
                workspaceID: target.id, workspace: target.name, project: projectName, profile: destination?.name
            ),
            replySessionID: heard?.source.sessionID,
            text: text,
            notifyWhenDone: notify && sendEnd.sessionID != nil
        )
    }

    static let unknown = "unknown"

    private static func originName(of identity: BridgeIdentity, store: Store) async throws -> String {
        guard let id = try await BridgeProfileScope.profile(of: identity, store: store),
              let profile = try await store.profile(id: id)
        else { return unknown }
        return profile.name
    }
}
