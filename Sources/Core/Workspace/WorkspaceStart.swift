import Foundation

public struct WorkspaceStartRequest: Sendable {
    public var id: WorkspaceID
    public var repo: Repo
    public var prompt: String
    public var baseBranch: String?
    public var branch: String?
    public var name: String?
    public var checkout: WorkspaceCheckout?
    public var controls: ComposerControls?
    public var origin: WorkspaceOrigin
    public var opensSession: Bool
    public var resuming: String?
    public var setupPolicy: WorkspaceSetupPolicy
    public var acceptsStaleBase: Bool
    public var orchestrates: Bool
    public var announcesToOrchestrator: Bool

    public init(
        id: WorkspaceID = .new(),
        repo: Repo,
        prompt: String,
        origin: WorkspaceOrigin,
        baseBranch: String? = nil,
        branch: String? = nil,
        name: String? = nil,
        checkout: WorkspaceCheckout? = nil,
        controls: ComposerControls? = nil,
        opensSession: Bool = true,
        resuming: String? = nil,
        setupPolicy: WorkspaceSetupPolicy = .deferred,
        acceptsStaleBase: Bool = true,
        orchestrates: Bool = false,
        announcesToOrchestrator: Bool = true
    ) {
        self.id = id
        self.repo = repo
        self.prompt = prompt
        self.origin = origin
        self.baseBranch = baseBranch
        self.branch = branch
        self.name = name
        self.checkout = checkout
        self.controls = controls
        self.opensSession = opensSession
        self.resuming = resuming
        self.setupPolicy = setupPolicy
        self.acceptsStaleBase = acceptsStaleBase
        self.orchestrates = orchestrates
        self.announcesToOrchestrator = announcesToOrchestrator
    }

    public var cutsItsOwnBranch: Bool { checkout == nil }
}

public struct StartedWorkspace: Sendable {
    public var workspace: Workspace
    public var session: Session?
    public var placeholder: String?
    public var setupSucceeded: Bool?
    public var projectCameBack: Bool
    public var announcedTo: Session?

    public init(
        workspace: Workspace,
        session: Session? = nil,
        placeholder: String? = nil,
        setupSucceeded: Bool? = nil,
        projectCameBack: Bool = false,
        announcedTo: Session? = nil
    ) {
        self.workspace = workspace
        self.session = session
        self.placeholder = placeholder
        self.setupSucceeded = setupSucceeded
        self.projectCameBack = projectCameBack
        self.announcedTo = announcedTo
    }
}

extension WorkspaceManager {
    public static let unnamed: @Sendable () async -> String? = { nil }

    public func start(
        _ request: WorkspaceStartRequest,
        namer: @Sendable () async -> String? = WorkspaceManager.unnamed,
        setupOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> StartedWorkspace {
        if request.orchestrates {
            let neighbours = try await store.workspaces(repoID: request.repo.id, includeArchived: true)
            if case .refused(let sentence) = OrchestratorRole.assignment(in: request.repo.id, among: neighbours) {
                throw WorkspaceError.orchestratorRefused(sentence)
            }
        }

        let placeholder = request.name == nil && request.checkout == nil ? await namer() : nil

        var workspace = try await createWorkspace(
            id: request.id,
            repo: request.repo,
            prompt: request.prompt,
            name: request.name ?? placeholder,
            branch: request.branch,
            baseBranch: request.baseBranch,
            origin: request.origin,
            checkout: request.checkout,
            setupPolicy: request.setupPolicy,
            acceptsStaleBase: request.acceptsStaleBase
        )

        if request.orchestrates {
            do {
                if let marked = try await store.setOrchestrator(true, workspaceID: workspace.id) {
                    workspace = marked
                }
            } catch {
                await discardRefusedStart(workspace, repo: request.repo, deletingBranch: request.cutsItsOwnBranch)
                throw error
            }
        }

        let projectCameBack = await bringProjectBack(request.repo.id)

        var session: Session?
        if request.opensSession {
            let controls = request.controls
            let backend = controls?.agentKind ?? .claudeCode
            let mode = (controls?.permissionMode ?? AppDefaults.fallbackPermissionMode)
                .nearest(on: backend)
            let opened = try await store.upsert(Session(
                workspaceID: workspace.id,
                title: PaneNaming.chat,
                agentSessionID: request.resuming,
                model: controls?.model ?? AppDefaults.fallbackModel,
                effort: controls?.effort ?? AppDefaults.fallbackEffort,
                agentKind: backend,
                permissionMode: mode,
                interactionMode: controls?.interactionMode ?? .build
            ))
            await controls?.store(sessionID: opened.id, in: store)
            session = opened
        }

        let announcedTo: Session? = if request.announcesToOrchestrator {
            try? await store.announceToOrchestrator(workspace, prompt: request.prompt, firstChat: session)
        } else {
            nil
        }

        var setupSucceeded: Bool?
        if request.setupPolicy == .run {
            let port = await ensurePort(for: workspace)
            setupSucceeded = await runSetup(
                workspace: workspace, repo: request.repo, port: port
            ) { line in
                setupOutput?(line)
            }
        }

        return StartedWorkspace(
            workspace: workspace,
            session: session,
            placeholder: placeholder,
            setupSucceeded: setupSucceeded,
            projectCameBack: projectCameBack,
            announcedTo: announcedTo
        )
    }

    private func discardRefusedStart(_ workspace: Workspace, repo: Repo, deletingBranch: Bool) async {
        await discardFreshWorktree(of: repo, at: workspace.path)
        if deletingBranch {
            try? await Git.deleteBranch(workspace.branch, in: repo.path, force: true)
        }
        try? await store.deleteWorkspace(id: workspace.id)
    }
}
