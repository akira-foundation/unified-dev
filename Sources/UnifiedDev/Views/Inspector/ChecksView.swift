import SwiftUI
import Core

struct ChecksView: View {
    let model: WorkspaceModel

    @State private var runs: [CheckRun] = []
    @State private var groups: [CheckRunGroup] = []
    @State private var hasLoaded = false
    @State private var checksUnavailable = false
    @State private var hovered: String?
    @State private var github: GitHubAvailability.State = .unknown
    @State private var forge: ForgeKind = .gitHub
    @State private var reload = 0
    @State private var sender = CheckFailureSender()

    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            if !runs.isEmpty {
                summary
                Hairline()
            }
            if runs.isEmpty {
                empty
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: "\(model.workspace.id)|\(reload)") { await poll() }
        .onChange(of: model.checkRuns, initial: true) { _, read in show(read) }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.runs) { run in
                            row(run)
                        }
                    } header: {
                        header(group)
                    }
                }
            }
            .padding(.bottom, Metrics.spacingSmall)
        }
    }

    private func row(_ run: CheckRun) -> some View {
        var onSend: (@MainActor () -> Void)?
        if CheckFailureSender.canSend(run), model.activeSession != nil {
            onSend = { send(run) }
        }

        return CheckRunRow(
            run: run,
            isHovered: hovered == run.id,
            isSending: sender.isSending(run),
            onSend: onSend
        )
            .rowBackground(isSelected: false, isHovered: hovered == run.id)
            .padding(.horizontal, Metrics.spacingSmall)
            .onHoverChange { hovering in
                hovered = hovering ? run.id : (hovered == run.id ? nil : hovered)
            }
    }

    private var summary: some View {
        let rollup = GitHub.rollup(runs)
        return HStack(spacing: InspectorLayout.gap) {
            Circle()
                .fill(color(for: rollup.0))
                .frame(width: Metrics.dot, height: Metrics.dot)
                .accessibilityHidden(true)
            Text(summaryText(rollup.1))
                .font(Typo.body)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Text("\(runs.count)")
                .font(Typo.micro)
                .monospacedDigit()
                .foregroundStyle(Palette.textTertiary)
                .accessibilityLabel("\(runs.count) checks")
        }
        .padding(.horizontal, InspectorLayout.inset)
        .frame(height: InspectorLayout.barHeight)
    }

    private var empty: some View {
        emptyContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private enum EmptyReason {
        case cannotAsk
        case unreadable
        case none
        case loading
    }

    private var emptyReason: EmptyReason {
        if !github.isUsable { return .cannotAsk }
        if checksUnavailable { return .unreadable }
        if hasLoaded { return .none }
        return .loading
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch emptyReason {
        case .cannotAsk:
            if let actionTitle = wording.cannotAskAction(access: access) {
                EmptyStateView(
                    glyph: "questionmark.circle",
                    title: wording.cannotAskTitle(access: access),
                    message: wording.cannotAskMessage(access: access),
                    actionTitle: actionTitle,
                    action: { GitHubSignIn.shared.run(directory: model.workspace.path) { reload += 1 } }
                )
            } else {
                EmptyStateView(
                    glyph: "questionmark.circle",
                    title: wording.cannotAskTitle(access: access),
                    message: wording.cannotAskMessage(access: access)
                )
            }
        case .unreadable:
            EmptyStateView(glyph: "lock", title: "Checks unavailable", message: wording.unreadable)
        case .none:
            EmptyStateView(glyph: "checkmark.seal", title: "No checks", message: wording.none)
        case .loading:
            LoadingView(wording.loading)
        }
    }

    private func header(_ group: CheckRunGroup) -> some View {
        HStack(spacing: Metrics.spacingSmall) {
            Text(group.workflow)
                .font(Typo.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text("\(group.runs.count)")
                .font(Typo.micro)
                .monospacedDigit()
        }
        .foregroundStyle(Palette.textTertiary)
        .padding(.horizontal, InspectorLayout.inset)
        .padding(.vertical, Metrics.spacingSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceSunken)
    }

    private func summaryText(_ rollup: String) -> String {
        if !github.isUsable { return wording.summary(access: access) }
        return runs.isEmpty && !hasLoaded ? "Loading checks" : rollup
    }

    private func color(for checks: PullRequest.Checks) -> Color {
        switch checks {
        case .passing: Palette.positive
        case .failing: Palette.negative
        case .pending: Palette.warning
        case .none, .unavailable: Palette.textTertiary
        }
    }

    private var wording: ChecksWording { ChecksWording(forge: forge) }

    private var access: GitHubAccess { github == .notInstalled ? .notInstalled : .signedOut }

    private func send(_ run: CheckRun) {
        Task {
            guard let failure = await sender.send(run, in: model) else { return }
            app.alert = AppAlert(
                title: "That check was not sent to the agent", message: failure
            )
        }
    }

    private func show(_ read: CheckRunsRead?) {
        checksUnavailable = read == .unreadable
        runs = read?.runs ?? []
        groups = CheckRunGroup.build(from: runs)
    }

    private func poll() async {
        let reader = PullRequestReader.checksTab
        forge = await Forge.kind(forDirectory: model.workspace.path)
        while !Task.isCancelled {
            let state: GitHubAvailability.State = forge == .bitbucket
                ? GitHubAvailability.State(await Bitbucket.access(directory: model.workspace.path))
                : await GitHubAvailability.shared.check(directory: model.workspace.path)
            github = state

            if state == .ready {
                await model.refreshPullRequest(maxAge: reader.maxAge)
            }
            hasLoaded = true
            try? await Task.sleep(for: reader.interval)
        }
    }
}
