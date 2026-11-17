import Foundation
import Testing
@testable import Core

struct ProfileScopeWorld {
    let store: Store
    let akira: ProfileID
    let homeProject: Repo
    let homeWorkspace: Workspace
    let homeAgent: BridgeIdentity
    let farProject: Repo
    let farWorkspace: Workspace
    let farAgent: BridgeIdentity

    static let farProjectName = "faraway-project"
    static let farWorkspaceName = "Faraway Workspace"
    static let farChat = "Faraway Chat"

    static func make(_ label: String) async throws -> ProfileScopeWorld {
        let store = try makeTestStore(label)
        let akira = try await store.createProfile(name: "Akira", colour: "blue", symbol: "star").id

        let homeProject = try await store.upsert(Repo(name: "home-project", path: TestScratch.unique("home")))
        let homeWorkspace = try await store.upsert(Workspace(
            repoID: homeProject.id, name: "Home Workspace", branch: "home",
            path: TestScratch.unique("home-tree"), baseBranch: "main"
        ))
        let homeChat = try await store.upsert(Session(workspaceID: homeWorkspace.id, title: "Home Chat", permissionMode: .acceptEdits))

        let farProject = try await store.upsert(Repo(
            name: farProjectName, path: TestScratch.unique("far"), profileID: akira
        ))
        let farWorkspace = try await store.upsert(Workspace(
            repoID: farProject.id, name: farWorkspaceName, branch: "far",
            path: TestScratch.unique("far-tree"), baseBranch: "main"
        ))
        let farSession = try await store.upsert(Session(workspaceID: farWorkspace.id, title: farChat))

        return ProfileScopeWorld(
            store: store,
            akira: akira,
            homeProject: homeProject,
            homeWorkspace: homeWorkspace,
            homeAgent: BridgeIdentity(
                sessionID: homeChat.id, workspaceID: homeWorkspace.id, role: .workspace, launchedAsking: true
            ),
            farProject: farProject,
            farWorkspace: farWorkspace,
            farAgent: BridgeIdentity(sessionID: farSession.id, workspaceID: farWorkspace.id, role: .workspace)
        )
    }

    func request(_ method: String, _ arguments: [String: JSONValue] = [:]) -> MCPRequest {
        MCPRequest(id: .number(1), method: method, params: .object(arguments))
    }

    func expectSameAsInvented(
        _ call: (String) async -> BridgeToolResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        for (real, invented) in [
            (farWorkspace.id.rawValue, "no-such-workspace-id"),
            (Self.farWorkspaceName, "No Such Workspace"),
        ] {
            let answer = await call(real)
            let baseline = await call(invented)
            #expect(answer.isError, "\(answer.text)", sourceLocation: sourceLocation)
            #expect(
                answer.text.replacingOccurrences(of: real, with: "<given>")
                    == baseline.text.replacingOccurrences(of: invented, with: "<given>"),
                sourceLocation: sourceLocation
            )
            if real != Self.farWorkspaceName {
                #expect(!answer.text.contains(Self.farWorkspaceName), sourceLocation: sourceLocation)
            }
            #expect(!answer.text.contains(Self.farProjectName), sourceLocation: sourceLocation)
        }
    }
}
