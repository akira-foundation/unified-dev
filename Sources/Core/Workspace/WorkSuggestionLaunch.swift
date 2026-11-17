import Foundation

public struct WorkSuggestionRefusal: Error, Sendable, Equatable {
    public let sentence: String

    public init(_ sentence: String) {
        self.sentence = sentence
    }
}

public typealias ProjectAdmitting = @Sendable (String) async -> Result<Repo, WorkSuggestionRefusal>

public struct WorkSuggestionLaunch: Sendable {
    public enum Choice: Sendable, Equatable {
        case newWorkspace
        case here
    }

    public enum Outcome: Sendable, Equatable {
        case started(WorkSuggestion)
        case refused(String)
    }

    private let workspaces: AgentWorkspaceLaunch
    private let startCrew: CrewStarting
    private let admit: ProjectAdmitting
    private let orchestrate: OrchestratorRequestLaunch?

    public init(
        start: @escaping WorkspaceStarting,
        crew: @escaping CrewStarting,
        admit: @escaping ProjectAdmitting,
        orchestrate: OrchestratorRequestLaunch? = nil
    ) {
        workspaces = AgentWorkspaceLaunch(start: start)
        startCrew = crew
        self.admit = admit
        self.orchestrate = orchestrate
    }

    public func launch(
        _ id: WorkSuggestionID, as choice: Choice, store: Store, now: Date = Date()
    ) async -> Outcome {
        let suggestion: WorkSuggestion
        do {
            switch try await store.claimWorkSuggestion(id: id) {
            case .missing: return .refused(WorkSuggestionWording.gone)
            case .taken(let taken): return .refused(WorkSuggestionWording.taken(taken.state))
            case .claimed(let claimed): suggestion = claimed
            }
        } catch {
            return .refused("Unified Dev could not read this suggestion: \(error.readableMessage)")
        }

        let result: Result<WorkSuggestion.State, WorkSuggestionRefusal>
        switch (suggestion.target, choice) {
        case (.orchestrator(let repoID), _):
            result = await orchestrate?.launch(suggestion, for: repoID, store: store)
                ?? .failure(WorkSuggestionRefusal(WorkSuggestionWording.gone))
        case (_, .newWorkspace): result = await newWorkspace(for: suggestion, store: store, now: now)
        case (_, .here): result = await here(for: suggestion, store: store)
        }

        switch result {
        case .success(let state): return await settle(id, as: state, store: store, now: now)
        case .failure(let refusal): return await release(id, refusal: refusal, store: store)
        }
    }

    private func settle(
        _ id: WorkSuggestionID, as state: WorkSuggestion.State, store: Store, now: Date
    ) async -> Outcome {
        do {
            guard let settled = try await store.settleWorkSuggestion(id: id, as: state, at: now) else {
                return .refused(WorkSuggestionWording.gone)
            }
            return .started(settled)
        } catch {
            return .refused(Self.unrecorded(error))
        }
    }

    private func release(_ id: WorkSuggestionID, refusal: WorkSuggestionRefusal, store: Store) async -> Outcome {
        do {
            try await store.releaseWorkSuggestion(id: id, failure: refusal.sentence)
            return .refused(refusal.sentence)
        } catch {
            try? await store.releaseWorkSuggestion(id: id, failure: refusal.sentence)
            return .refused(Self.unrecorded(error))
        }
    }

    private static func unrecorded(_ error: any Error) -> String {
        "Unified Dev could not record what became of this suggestion: \(error.readableMessage)"
    }

    private func newWorkspace(
        for suggestion: WorkSuggestion, store: Store, now: Date
    ) async -> Result<WorkSuggestion.State, WorkSuggestionRefusal> {
        let project: Repo
        switch await repository(for: suggestion, store: store) {
        case .failure(let refusal): return .failure(refusal)
        case .success(let found): project = found
        }

        let order = AgentWorkspaceOrder(
            prompt: WorkSuggestionBrief.task(from: suggestion.prompt),
            name: WorkspaceName.given(suggestion.title)
        )
        let spawnID = order.spawnID(suggestion: suggestion.id)
        let origin: WorkspaceOrigin
        let identity: BridgeIdentity
        if let parent = suggestion.workspaceID {
            origin = .agent(parentWorkspaceID: parent, spawnToolUseID: spawnID)
            identity = BridgeIdentity(sessionID: suggestion.sessionID, workspaceID: parent, role: .workspace)
        } else {
            origin = .ownerClient(spawnToolUseID: spawnID)
            identity = BridgeIdentity(ownerSession: suggestion.sessionID)
        }

        switch await workspaces.launch(order, in: project, as: identity, origin: origin, store: store, now: now) {
        case .started(let summary):
            if suggestion.workspaceID != nil {
                try? await store.watchFirstTurn(of: summary, for: suggestion.sessionID)
            }
            return .success(.startedWorkspace(summary.workspaceID, name: summary.name))
        case .alreadyStarted(let existing): return .success(.startedWorkspace(existing.id, name: existing.name))
        case .refused(let refusal): return .failure(WorkSuggestionRefusal(WorkSuggestionWording.sentence(for: refusal)))
        }
    }

    private func here(
        for suggestion: WorkSuggestion, store: Store
    ) async -> Result<WorkSuggestion.State, WorkSuggestionRefusal> {
        guard suggestion.target == .sameProject, let workspaceID = suggestion.workspaceID else {
            return .failure(WorkSuggestionRefusal(WorkSuggestionWording.hereElsewhere))
        }
        do {
            guard let caller = try await store.session(id: suggestion.sessionID) else {
                return .failure(WorkSuggestionRefusal("The chat this suggestion came from is no longer in Unified Dev."))
            }
            let crew = try await store.crew(inWorkspace: workspaceID)
            let name = CrewNaming.free(for: suggestion.title, existing: Set(crew.map(\.title)))

            switch await CrewLaunch.launch(
                name: name, task: WorkSuggestionBrief.task(from: suggestion.prompt), model: nil, effort: nil,
                from: caller, in: workspaceID, store: store, start: startCrew
            ) {
            case .refused(let refusal):
                return .failure(WorkSuggestionRefusal(WorkSuggestionWording.sentence(for: refusal)))
            case .started(_, let named):
                let member = (try? await store.crew(of: caller.id))?.first { $0.title == named }
                return .success(.startedHere(member?.id ?? SessionID(""), name: named))
            }
        } catch {
            return .failure(WorkSuggestionRefusal("Unified Dev could not read this workspace's chats: \(error.readableMessage)"))
        }
    }

    private func repository(
        for suggestion: WorkSuggestion, store: Store
    ) async -> Result<Repo, WorkSuggestionRefusal> {
        do {
            let project: Repo
            switch try await target(of: suggestion, store: store) {
            case .failure(let refusal): return .failure(refusal)
            case .success(let found): project = found
            }
            guard WorkSuggestionProfile.admits(
                project: project.profileID, from: try await store.workSuggestionSource(suggestion)
            ) else {
                return .failure(WorkSuggestionRefusal(WorkSuggestionWording.anotherProfile))
            }
            return .success(try await Self.shown(project, store: store))
        } catch {
            return .failure(WorkSuggestionRefusal("Unified Dev could not read its projects: \(error.readableMessage)"))
        }
    }

    private func target(
        of suggestion: WorkSuggestion, store: Store
    ) async throws -> Result<Repo, WorkSuggestionRefusal> {
        switch suggestion.target {
        case .sameProject:
            guard let workspaceID = suggestion.workspaceID,
                  let workspace = try await store.workspace(id: workspaceID),
                  let repo = try await store.repo(id: workspace.repoID)
            else {
                return .failure(WorkSuggestionRefusal("The workspace this suggestion came from is no longer in Unified Dev."))
            }
            return .success(repo)

        case .project(let repoID):
            guard let repo = try await store.repo(id: repoID) else {
                return .failure(WorkSuggestionRefusal("That project is no longer in Unified Dev. Add it again, then start this from here."))
            }
            return .success(repo)

        case .folder(let path):
            return await admit(path)

        case .remote(let slug):
            return .failure(WorkSuggestionRefusal(WorkSuggestionWording.cloneFirst(slug)))

        case .orchestrator:
            return .failure(WorkSuggestionRefusal(WorkSuggestionWording.gone))
        }
    }

    public static func draftProject(
        _ project: Repo, for suggestion: WorkSuggestion, store: Store
    ) async throws -> Repo? {
        guard WorkSuggestionProfile.admits(
            project: project.profileID, from: try await store.workSuggestionSource(suggestion)
        ) else {
            try await store.noteWorkSuggestionFailure(id: suggestion.id, failure: WorkSuggestionWording.anotherProfile)
            return nil
        }
        return try await shown(project, store: store)
    }

    public static func shown(_ repo: Repo, store: Store) async throws -> Repo {
        guard repo.hidden else { return repo }
        return try await store.update(repoID: repo.id) { $0.hidden = false } ?? repo
    }
}
