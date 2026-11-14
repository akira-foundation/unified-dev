import SwiftUI
import Core

struct NewWorkspacePane: View {
    var repoID: RepoID

    @Environment(AppModel.self) private var app

    @State private var catalogue: WorkspaceSourceCatalogue?
    @State private var pullRequests = PullRequestLoad.loading
    @State private var reading: StartingPointReading?
    @State private var loadedRepoID: RepoID?
    @State private var pickProblem: String?
    @State private var isLookingUp = false
    @State private var isChoosingStart = false

    private var repo: Repo? { app.repos.first { $0.id == repoID } }

    var body: some View {
        if let repo, let draft = app.drafts.draft(for: repoID) {
            column(repo: repo, draft: draft)
                .task(id: repoID) { await load(repo) }
                .task(id: readingRequest(repo)) { await loadSuggestions(readingRequest(repo)) }
                .task(id: prefetch(repo: repo, draft: draft)) {
                    await WorkspaceStartContext.prefetch(prefetch(repo: repo, draft: draft))
                }
                .task(id: isOriginAskReady) {
                    guard isOriginAskReady, app.drafts.consumeOriginAsk(repoID) else { return }
                    isChoosingStart = true
                }
        } else {
            HomeView()
        }
    }

    private func column(repo: Repo, draft: WorkspaceDraft) -> some View {
        VStack(spacing: Metrics.spacingWide) {
            Spacer(minLength: 0)

            NewWorkspaceHeader(
                point: draft.startingPoint,
                remote: remote(of: draft.startingPoint),
                isBusy: app.drafts.isCreating(repoID) || isLookingUp,
                busyLabel: isLookingUp ? "Looking up the pull request" : "Creating the workspace",
                roleNote: draft.isOrchestrator && app.asksForOrchestrator(in: repoID)
                    ? "It plans and starts other workspaces, and never edits its own worktree." : nil
            ) {
                NewWorkspaceProjectChip(repo: repo) { app.moveDraft(repoID, to: $0) }
                StartingPointChip(
                    point: draft.startingPoint,
                    remote: remote(of: draft.startingPoint),
                    catalogue: catalogue,
                    pullRequests: pullRequests,
                    leadingBase: leadingBase(in: repo),
                    isPresented: $isChoosingStart,
                    onPick: { pick($0) }
                )
                if app.asksForOrchestrator(in: repoID) {
                    NewWorkspaceOrchestratorChip(isOn: Binding(
                        get: { draft.isOrchestrator },
                        set: { isOn in app.editDraft(repoID) { $0.isOrchestrator = isOn } }
                    ))
                }
            }
            .disabled(app.drafts.isCreating(repoID))

            Spacer(minLength: 0)

            if let problem = app.drafts.failure(for: repoID) ?? pickProblem
                ?? draft.startingPoint.checkout.flatMap(WorkspaceCheckoutPlan.warning(for:)) {
                NewWorkspaceProblem(sentence: problem)
            }

            NewWorkspaceComposer(repo: repo, draft: draft)

            if let catalogue, let reading, readingRequest(repo) != nil, !app.drafts.isCreating(repoID) {
                let suggestions = StartingPointSuggestions.choose(
                    reading, defaultBranch: repo.defaultBranch, holders: catalogue.holders,
                    openPullRequests: pullRequests.requests, now: Date()
                )
                if !suggestions.isEmpty {
                    StartingPointSuggestionList(
                        suggestions: suggestions,
                        point: draft.startingPoint,
                        onPick: { pickSuggestion($0, in: repo) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, ComposerLayout.bottomInset)
    }

    private var isOriginAskReady: Bool {
        catalogue != nil && app.drafts.originAsks.contains(repoID)
    }

    private func remote(of point: WorkspaceStartingPoint) -> String? {
        point.baseBranch.flatMap { catalogue?.remote(of: $0) }
    }

    private func leadingBase(in repo: Repo) -> String? {
        guard case .workspace(let id)? = app.drafts.returnTarget(for: repoID),
              let workspace = app.workspaces.first(where: { $0.id == id }),
              workspace.repoID == repo.id else { return nil }
        return workspace.branch
    }

    private func prefetch(repo: Repo, draft: WorkspaceDraft) -> BaseBranchPrefetch? {
        BaseBranchPrefetch.target(
            repoPath: repo.path,
            baseBranch: draft.startingPoint.baseBranch ?? "",
            opensCheckout: draft.startingPoint.checkout != nil
        )
    }

    private func readingRequest(_ repo: Repo) -> StartingPointReadingRequest? {
        guard loadedRepoID == repo.id else { return nil }
        return StartingPointReadingRequest(
            repoPath: repo.path, offersPullRequests: catalogue?.offersPullRequests, pullRequests: pullRequests
        )
    }

    private func loadSuggestions(_ request: StartingPointReadingRequest?) async {
        guard let request else {
            reading = nil
            return
        }
        let loaded = await StartingPointReader.load(request)
        guard !Task.isCancelled else { return }
        reading = loaded
    }

    private func load(_ repo: Repo) async {
        loadedRepoID = nil
        catalogue = nil
        pullRequests = .loading
        pickProblem = nil
        await app.prepareDraftControls(for: repo)
        let listed = await WorkspaceSourceCatalogue.load(repo: repo, workspaces: app.workspaces)
        guard !Task.isCancelled else { return }
        catalogue = listed
        let requests = await PullRequestLoad.read(repoPath: repo.path, offered: listed.offersPullRequests)
        guard !Task.isCancelled else { return }
        pullRequests = requests
        loadedRepoID = repo.id
        catalogue = listed.with(pullRequests: requests.requests)
        guard await WorkspaceStartContext.fetchBranchList(repoPath: repo.path) else { return }
        let current = await app.refreshDefaultBranch(of: repo)
        guard !Task.isCancelled else { return }
        let fetched = await WorkspaceSourceCatalogue.load(repo: current, workspaces: app.workspaces)
        guard !Task.isCancelled else { return }
        catalogue = fetched.with(pullRequests: requests.requests)
    }

    @discardableResult
    private func pick(_ source: WorkspaceSource) -> StartingPointPick? {
        guard let catalogue else { return nil }
        pickProblem = nil
        let decision = StartingPointPick.decide(
            source, holders: catalogue.holders, taken: catalogue.localBranches,
            repoID: repoID, workspaces: app.workspaces
        )
        apply(decision)
        return decision
    }

    private func pickSuggestion(_ suggestion: StartingPointSuggestion, in repo: Repo) {
        let chosen = suggestion.pick(defaultBranch: repo.defaultBranch)
        guard let decision = pick(chosen.source), chosen.addsToPrompt else { return }
        app.editDraft(repoID) { $0.prompt = chosen.prompt(into: $0.prompt, after: decision) }
    }

    private func apply(_ pick: StartingPointPick) {
        switch pick {
        case .use(let point): app.editDraft(repoID) { $0.startingPoint = point }
        case .goTo(let id): app.selection = .workspace(id)
        case .refuse(let sentence): pickProblem = sentence
        case .lookUp(let text): lookUp(text)
        }
    }

    private func lookUp(_ text: String) {
        guard let repo, let catalogue, !isLookingUp else { return }
        isLookingUp = true
        Task {
            let resolution = await WorkspaceCheckoutResolver.resolve(text, repoPath: repo.path)
            isLookingUp = false
            switch resolution {
            case .checkout(let resolved):
                apply(StartingPointPick.decide(
                    checkout: resolved, holders: catalogue.holders, taken: catalogue.localBranches,
                    repoID: repoID, workspaces: app.workspaces
                ))
            case .failure(let sentence):
                pickProblem = sentence
            }
        }
    }
}
