import Foundation

enum WorkspaceSayDestination {
    enum Found: Sendable {
        case workspace(Workspace)
        case noOrchestrator(Repo)
    }

    static func orchestrators(among workspaces: [Workspace], repos: [Repo], in profile: Profile) -> [Workspace] {
        ProfileScope.workspaces(workspaces, repos: repos, in: profile.id).filter(OrchestratorRole.leads)
    }

    private static func orchestrator(
        named given: String, in profile: Profile, store: Store
    ) async throws -> Result<Found, WorkspaceSayTrouble> {
        let reachable = orchestrators(among: try await store.workspaces(), repos: try await store.repos(), in: profile)
        guard case .found(let target) = BridgeWorkspaceLookup.find(given, among: reachable) else {
            return .failure(.onlyOrchestrators(given: given))
        }
        return .success(.workspace(target))
    }

    static func resolve(
        workspace given: String?,
        project named: String?,
        in choice: BridgeProfileChoice,
        as identity: BridgeIdentity,
        store: Store
    ) async throws -> Result<Found, WorkspaceSayTrouble> {
        if given != nil, named != nil { return .failure(.workspaceAndProject) }
        if let given {
            if case .other(let profile) = choice,
               try await BridgeProfileReach.caller(of: identity, store: store) == .workspace {
                return try await orchestrator(named: given, in: profile, store: store)
            }
            switch try await WorkspaceSayTool.target(named: given, as: identity, store: store, in: choice) {
            case .failure(let trouble): return .failure(trouble)
            case .success(let found): return .success(.workspace(found))
            }
        }
        guard let named else { return .failure(.noWorkspace) }
        let projects = if case .other(let profile) = choice {
            ProfileScope.repos(try await store.repos(), in: profile.id)
        } else {
            try await BridgeProfileScope.repos(for: identity, store: store)
        }
        guard case .found(let project) = BridgeProjectLookup.find(named, in: projects) else {
            return .failure(.unknownProject(given: named))
        }
        guard let orchestrator = OrchestratorRole.orchestrator(of: project.id, among: try await store.workspaces()) else {
            return .success(.noOrchestrator(project))
        }
        return .success(.workspace(orchestrator))
    }

    static func awaitOrchestrator(
        _ project: Repo, saying text: String, as identity: BridgeIdentity, store: Store
    ) async throws -> BridgeToolResult {
        guard let sessionID = identity.sessionID else { return .failure(WorkspaceSayTrouble.noChatForCard.sentence) }
        let suggestion = WorkSuggestion(
            workspaceID: identity.workspaceID, sessionID: sessionID,
            title: WorkSuggestionWording.orchestratorTitle(project.name), why: WorkSuggestionWording.orchestratorWhy,
            prompt: text, target: .orchestrator(project.id)
        )
        switch try await store.addWorkSuggestion(suggestion) {
        case .full(let undecided): return .failure(WorkspaceSayTrouble.cardsFull(undecided: undecided).sentence)
        case .added(let added):
            return .json(.object([
                "state": .string("waiting_for_an_orchestrator"),
                "suggestion_id": .string(added.id.rawValue),
                "project": .string(project.name),
                "note": .string(
                    "That project has no orchestrator, so nothing has received the message yet. The owner sees "
                        + "a card below your message and decides whether to start one; when they do, the message "
                        + "is delivered to it. notify_when_done does not apply to a message waiting on a card. "
                        + "Carry on with your own work, and withdraw it with work_withdraw and this id if it stops "
                        + "making sense."
                ),
            ]))
        }
    }
}
