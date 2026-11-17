import Foundation
import Testing
@testable import Core

struct ProfileReachWorld {
    let world: ProfileScopeWorld
    let lead: BridgeIdentity
    let leadChat: Session
    let subagent: BridgeIdentity
    let window: WorkspaceSayWindow

    var store: Store { world.store }
    var akira: ProfileID { world.akira }

    static func make(_ label: String) async throws -> ProfileReachWorld {
        let world = try await ProfileScopeWorld.make(label)
        let store = world.store
        let leadWorkspace = try await store.upsert(Workspace(
            repoID: world.homeProject.id, name: "Lead", branch: "lead",
            path: TestScratch.unique("lead"), baseBranch: "main"
        ))
        _ = try await store.setOrchestrator(true, workspaceID: leadWorkspace.id)
        let leadChat = try await store.upsert(Session(workspaceID: leadWorkspace.id, title: "Lead Chat", permissionMode: .acceptEdits))
        let child = try await store.upsert(Session(
            workspaceID: leadWorkspace.id, parentSessionID: leadChat.id, title: "Helper", permissionMode: .acceptEdits
        ))
        let farChat = try #require(try await store.sessions(workspaceID: world.farWorkspace.id).first)
        return ProfileReachWorld(
            world: world,
            lead: BridgeIdentity(
                sessionID: leadChat.id, workspaceID: leadWorkspace.id, role: .workspace, launchedOrchestrating: true,
                launchedAsking: true
            ),
            leadChat: leadChat,
            subagent: BridgeIdentity(sessionID: child.id, workspaceID: leadWorkspace.id, role: .workspace, launchedAsking: true),
            window: WorkspaceSayWindow(
                store: store, chats: [world.farWorkspace.id: farChat]
            )
        )
    }

    func open(_ profiles: ProfileID...) async throws {
        for profile in profiles { try await ProfileBridgeSwitch.save(true, profile: profile, to: store) }
    }

    func say(as identity: BridgeIdentity, profile: String? = "Akira", notify: Bool = false) async -> BridgeToolResult {
        var arguments: [String: JSONValue] = [
            "workspace": .string(world.farWorkspace.id.rawValue), "message": .string("Check the invoices."),
            WorkspaceDoneWatch.argument: .bool(notify),
        ]
        if let profile { arguments["profile"] = .string(profile) }
        return await window.tool().call(world.request("workspace_say", arguments), as: identity, store: store)
    }

    func read(as identity: BridgeIdentity, profile: String) async -> BridgeToolResult {
        await ChatListTool().call(
            world.request("chat_list", [
                "workspace": .string(ProfileScopeWorld.farWorkspaceName), "profile": .string(profile),
            ]),
            as: identity, store: store
        )
    }

    func listedTools(as identity: BridgeIdentity) async -> [String] {
        await BridgeToolbox.standard.tools(for: identity, store: store).map(\.name)
    }
}
