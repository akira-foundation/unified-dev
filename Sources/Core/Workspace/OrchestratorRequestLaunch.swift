import Foundation

public typealias OrchestratorStarting = @Sendable (Repo) async throws -> Workspace

public struct OrchestratorRequestLaunch: Sendable {
    private let start: OrchestratorStarting
    private let deliver: WorkspaceMessageDelivering

    public init(start: @escaping OrchestratorStarting, deliver: @escaping WorkspaceMessageDelivering) {
        self.start = start
        self.deliver = deliver
    }

    func launch(
        _ suggestion: WorkSuggestion, for repoID: RepoID, store: Store
    ) async -> Result<WorkSuggestion.State, WorkSuggestionRefusal> {
        let project: Repo
        let destination: Profile?
        do {
            guard let found = try await store.repo(id: repoID) else {
                return .failure(WorkSuggestionRefusal("That project is no longer in Unified Dev."))
            }
            project = found
            destination = try await Self.destination(of: suggestion, in: project, store: store)
            if let refusal = try await Self.refusal(of: suggestion, crossingTo: destination, store: store) {
                return .failure(refusal)
            }
        } catch {
            return .failure(WorkSuggestionRefusal("Unified Dev could not read that project: \(error.readableMessage)"))
        }

        let orchestrator: Workspace
        do {
            orchestrator = try await self.orchestrator(of: project, store: store)
        } catch {
            return .failure(WorkSuggestionRefusal("Unified Dev could not start that orchestrator: \(error.readableMessage)"))
        }
        guard orchestrator.id != suggestion.workspaceID else {
            return .failure(WorkSuggestionRefusal(WorkSuggestionWording.senderLeads(orchestrator.name)))
        }

        do {
            let message = try await WorkspaceMessageComposer.compose(
                suggestion.prompt, to: orchestrator, crossingTo: destination,
                originKnown: suggestion.workspaceID != nil, notify: false,
                as: Self.sender(of: suggestion), store: store
            )
            switch await deliver(message) {
            case .refused(let sentence): return .failure(Self.undelivered(to: orchestrator, sentence))
            case .sent: return .success(.startedWorkspace(orchestrator.id, name: orchestrator.name))
            }
        } catch {
            return .failure(Self.undelivered(to: orchestrator, error.readableMessage))
        }
    }

    private func orchestrator(of project: Repo, store: Store) async throws -> Workspace {
        if let existing = OrchestratorRole.orchestrator(of: project.id, among: try await store.workspaces()) {
            return existing
        }
        do {
            return try await start(try await WorkSuggestionLaunch.shown(project, store: store))
        } catch {
            guard let raced = OrchestratorRole.orchestrator(of: project.id, among: try await store.workspaces()) else {
                throw error
            }
            return raced
        }
    }

    static func sender(of suggestion: WorkSuggestion) -> BridgeIdentity {
        guard let workspaceID = suggestion.workspaceID else { return BridgeIdentity(ownerSession: suggestion.sessionID) }
        return BridgeIdentity(sessionID: suggestion.sessionID, workspaceID: workspaceID, role: .workspace, launchedAsking: true)
    }

    static func destination(of suggestion: WorkSuggestion, in project: Repo, store: Store) async throws -> Profile? {
        guard suggestion.workspaceID != nil else { return try await store.profile(id: project.profileID) }
        let source = try await BridgeProfileScope.profile(of: sender(of: suggestion), store: store)
        guard source != project.profileID else { return nil }
        return try await store.profile(id: project.profileID)
    }

    private static func refusal(
        of suggestion: WorkSuggestion, crossingTo destination: Profile?, store: Store
    ) async throws -> WorkSuggestionRefusal? {
        guard let destination, suggestion.workspaceID != nil else { return nil }
        let reachable = try await BridgeProfileReach.reachable(from: sender(of: suggestion), for: .talk, store: store)
        guard !reachable.contains(where: { $0.id == destination.id }) else { return nil }
        guard await ProfileBridgeSwitch.isOn(profile: destination.id, in: store) else {
            return WorkSuggestionRefusal(BridgeProfileTrouble.closedToOutside(given: destination.name).sentence)
        }
        return WorkSuggestionRefusal(WorkSuggestionWording.senderCannotCross)
    }

    private static func undelivered(to orchestrator: Workspace, _ reason: String) -> WorkSuggestionRefusal {
        WorkSuggestionRefusal(
            "\(WorkspaceMessage.oneLine(orchestrator.name)) is the project's orchestrator now, but the message did not "
                + "reach it: \(reason) Press again to send it."
        )
    }
}
