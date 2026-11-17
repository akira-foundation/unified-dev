import SwiftUI
import Core

struct PullRequestBar: View {
    let model: WorkspaceModel

    @Environment(AppModel.self) private var app

    @State private var isWorking = false
    @State private var pendingArchive: ArchiveRequest?
    @State private var pendingMerge: GitHub.MergeMethod?
    @State private var isVisible = false

    private var report: PullRequestNotice? {
        get { model.pullRequestNotice }
        nonmutating set { model.pullRequestNotice = newValue }
    }

    private var standing: PullRequestStanding { model.pullRequestStanding }

    var body: some View {
        strip
            .task(id: model.workspace.id) { await poll() }
            .task(id: model.workspace.id) { await model.followMergeMethod() }
            .onChange(of: model.workspace.id) { _, _ in
                dismissConfirmations()
                isWorking = false
            }
            .onChange(of: model.pullRequest?.url) { _, _ in dismissConfirmations() }
            .onAppear { isVisible = true }
            .onDisappear {
                isVisible = false
                dismissConfirmations()
            }
    }

    private var strip: some View {
        PullRequestBarContent(
            standing: standing,
            branchActions: branchActions,
            isWorking: isWorking || model.isLoadingPullRequest,
            mergeMethod: model.mergeMethod,
            canMerge: canConfirmMerge,
            worktree: model.workspace.path,
            onChooseMergeMethod: chooseMergeMethod,
            onAct: act,
            onReach: reach
        )
        .contextMenu { menuItems }
        .archiveConfirmation(
            $pendingArchive,
            canConfirm: branchActions.isAllowed && !isWorking,
            tint: standing.tone.pathColour,
            onConfirm: confirmArchive
        )
        .mergeConfirmation(
            $pendingMerge, model: model, canConfirm: canConfirmMerge, arrowEdge: .top, onConfirm: merge
        )
    }

    @ViewBuilder
    private var menuItems: some View {
        if let pullRequest = model.pullRequest {
            Button("Open on \(pullRequest.hostName)") { GitHubBridge.open(pullRequest.url) }
            Button("Copy link") { Clipboard.copy(pullRequest.url) }
            if let url = URL(string: pullRequest.url) {
                ShareLink(item: url) { Text("Share") }
            }
            if pullRequest.isMerged {
                Divider()
                Button("Continue on a new branch") { carryOn(after: pullRequest) }
                    .disabled(!branchActions.isAllowed || isWorking)
            }
            Divider()
        }
        Button("Copy branch name") { Clipboard.copy(model.workspace.branch) }
    }

    private var branchActions: BranchActionAvailability {
        .mayActOnBranch(
            isAgentBusy: app.isRunning(model.workspace),
            pullRequest: model.pullRequest
        )
    }

    private var canConfirmMerge: Bool {
        model.canConfirmMerge(branchActions: branchActions, isWorking: isWorking)
    }

    private func reach(_ reach: PullRequestReach) {
        switch reach {
        case .diff: model.inspectorTab = .changes
        case .checks: model.inspectorTab = .checks
        case .pullRequestPage(let url): GitHubBridge.open(url)
        case .merge: propose(model.mergeMethod)
        }
    }

    private func act(_ act: PullRequestStanding.Act) {
        switch act {
        case .openPullRequest: ask { await model.requestPullRequest() }
        case .push, .commitAndPush: ask { await model.requestPush(from: .pullRequestBar) }
        case .markReadyForReview: markReadyForReview()
        case .merge: propose(model.mergeMethod)
        case .askToFixConflicts: ask { await model.sendFixConflictsRequest() }
        case .askToFixChecks: ask { await model.sendCheckFailureRequest() }
        case .archive: archive()
        }
    }

    private func ask(_ work: @escaping () async -> String?) {
        guard !isWorking else { return }
        isWorking = true
        report = nil

        Task {
            defer { isWorking = false }
            if let refusal = await work() {
                report = PullRequestNotice(
                    tone: .info, title: "Nothing was sent", message: refusal
                )
            }
        }
    }

    private func markReadyForReview() {
        guard let pullRequest = model.pullRequest, branchActions.isAllowed else { return }
        ask { await model.requestMarkReadyForReview(pullRequest) }
    }

    private func merge(_ method: GitHub.MergeMethod, confirmed: InstructionAuthority) {
        guard let pullRequest = model.pullRequest else { return }
        ask { await model.requestMerge(pullRequest, method: method, from: .pullRequestBar, confirmed: confirmed) }
    }

    private func propose(_ method: GitHub.MergeMethod) {
        guard canConfirmMerge else { return }
        GitHubSignIn.shared.run(directory: model.workspace.path) { pendingMerge = method }
    }

    private func chooseMergeMethod(_ method: GitHub.MergeMethod) {
        Task { await model.chooseMergeMethod(method) }
    }

    private func carryOn(after pullRequest: PullRequest) {
        isWorking = true
        report = nil

        Task {
            defer { isWorking = false }
            switch await app.continueAfterMerge(model.workspace, pullRequest: pullRequest) {
            case .continued:
                break
            case .refused(let refusal):
                report = PullRequestNotice(
                    tone: .info, title: "Nothing was changed", message: refusal.sentence
                )
            case .failed(let reason):
                report = PullRequestNotice(
                    tone: .failure, title: "Could not continue", message: reason, details: nil
                )
            }
        }
    }

    private func archive() {
        let workspace = model.workspace
        Task { await app.archive(workspace, presentConfirmation: presentArchive) }
    }

    private func confirmArchive(_ request: ArchiveRequest) {
        pendingArchive = nil
        Task { await app.confirmArchive(request, presentConfirmation: presentArchive) }
    }

    private func presentArchive(_ update: ArchiveConfirmationFlow.Update) {
        guard isVisible, app.selection.workspaceID == update.workspaceID else { return }
        pendingArchive = ArchiveConfirmationFlow.shows(update, while: pendingArchive, replacesInPlace: true)
    }

    private func dismissConfirmations() {
        pendingArchive = nil
        pendingMerge = nil
    }

    private func poll() async {
        await model.readRemote()

        let reader = PullRequestReader.pullRequestBar
        var maxAge = WorkspaceModel.pullRequestArrivalMaxAge
        while !Task.isCancelled {
            await model.refreshPullRequest(maxAge: maxAge)
            maxAge = reader.maxAge
            try? await Task.sleep(for: reader.interval)
        }
    }
}
