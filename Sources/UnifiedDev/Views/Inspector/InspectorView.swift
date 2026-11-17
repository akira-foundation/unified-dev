import SwiftUI
import Core

struct InspectorView: View {
    let model: WorkspaceModel

    @Environment(AppModel.self) private var app

    @Bindable private var signIn = GitHubSignIn.shared

    @State private var fileQuery = ""

    var body: some View {
        VStack(spacing: 0) {
            if let notice = model.pullRequestNotice {
                InspectorNotice(notice: notice) { model.pullRequestNotice = nil }
                Hairline()
            }

            if model.inspectorTab.readsTheDiff, model.diffScope.isNarrowed {
                DiffScopeBand(
                    scope: model.diffScope,
                    fileCount: model.changedFiles.count,
                    note: model.scopeNote
                ) {
                    model.setDiffScope(.all)
                }
                Hairline()
            }

            content
                .frame(maxHeight: .infinity)

            if let failure = model.pullRequestRefreshFailure {
                RefreshFailureRow(
                    failure: failure,
                    hasPullRequest: model.pullRequest != nil,
                    onDismiss: { WorkspacePullRequests.shared.dismissFailure(for: model.workspace.id) }
                )
            }

            PullRequestBar(model: model)
        }
        .sheet(item: $signIn.request) { request in
            GitHubSignInSheet(request: request) { connected in
                signIn.finish(connected: connected)
            }
        }
        .alert(
            signIn.bitbucketRefusal.map { ProfileBitbucketWording.cannotReachTitle($0.access) } ?? "",
            isPresented: $signIn.bitbucketRefusal.isPresent(),
            presenting: signIn.bitbucketRefusal
        ) { _ in
        } message: { refusal in
            Text(ProfileBitbucketWording.cannotReachMessage(refusal.access))
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width.rounded() } action: { width in
            guard width >= Metrics.inspectorMinimum else { return }
            InspectorGeometry.shared.setInspectorWidth(width)
        }
        .onDisappear { InspectorGeometry.shared.setInspectorWidth(0) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NotificationBellButton(inbox: app.notificationInbox, profiles: app.profiles)
            }
        }
        .searchable(text: $fileQuery, placement: .automatic, prompt: "Filter files")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                InspectorViewPicker(model: model)
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItemGroup(placement: .primaryAction) {
                InspectorToolbar.GroupingButton(model: model)
                InspectorToolbar.ScopeMenu(model: model)
                InspectorToolbar.MoreMenu(model: model)
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)

            if let work = model.localWork, work.unpushedCommits > 0 || work.modifiedFiles > 0 {
                ToolbarItem(placement: .primaryAction) {
                    InspectorToolbar.PushButton(model: model)
                }
            }

            if let pullRequest = model.pullRequest,
               pullRequest.status(local: model.localWork).canMerge {
                ToolbarItem(placement: .primaryAction) {
                    InspectorToolbar.MergeButton(model: model)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                InspectorToggle(visibility: app.inspectorVisibility) { app.toggleInspector() }
            }
        }
        .environment(\.openInRepoID, model.repo?.id)
    }

    @ViewBuilder
    private var content: some View {
        switch model.inspectorTab {
        case .allFiles:
            FileTreeView(model: model, query: $fileQuery)
        case .changes:
            ChangedFileList(model: model, query: $fileQuery)
        case .side:
            if let parent = model.inspectorSideParent, let state = model.inspectorSideConversation {
                SideConversationView(parent: parent, state: state, model: model)
            }
        case .tasks:
            BackgroundTasksView(model: model)
        case .checks:
            ChecksView(model: model)
        }
    }
}

private struct RefreshFailureRow: View {
    var failure: GitHubReadFailure
    var hasPullRequest: Bool
    var onDismiss: @MainActor () -> Void

    @State private var isExpanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: InspectorLayout.tight) {
            header
            if isExpanded {
                details
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, InspectorLayout.inset)
        .padding(.vertical, Metrics.spacing)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: InspectorLayout.gap) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: InspectorLayout.tight) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(Palette.textTertiary)
                        .accessibilityHidden(true)
                    Label(failure.headline(hasPullRequest: hasPullRequest), systemImage: "exclamationmark.triangle")
                    .lineLimit(1)
                }
                .font(Typo.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(Palette.textTertiary)
                .help("Dismiss")
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: InspectorLayout.gap) {
            Text(failure.summary)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            if let transcript = failure.transcript {
                ScrollView(.horizontal) {
                    Text(transcript)
                        .font(Typo.codeSmall)
                        .foregroundStyle(Palette.textSecondary)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 140)
                .padding(InspectorLayout.tight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surfaceRaised, in: .rect(cornerRadius: Metrics.cornerSmall))
            }

            if let retryAt = failure.retryAt {
                Text("Next refresh after \(retryAt.formatted(date: .omitted, time: .shortened))")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
