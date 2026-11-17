import AppKit
import SwiftUI
import Core

struct StartProjectSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @AppStorage(ProjectVisibility.showsHiddenKey) private var showsHiddenProjects = false

    @State private var model = StartProjectModel()

    private static let width: CGFloat = 560
    private static let markSize: CGFloat = 96
    private static let closeSize: CGFloat = 28

    var body: some View {
        VStack(spacing: 0) {
            plinth
            body(for: model.stage)
            if !model.stage.takesTheWholeCard { footer }
        }
        .frame(width: Self.width)
        .presentationBackground(Palette.surface)
        .overlay(alignment: .topLeading) { closeButton }
        .task {
            model.gitHubLogin = app.activeGitHubLogin
            await model.load(projectPaths: app.repos.map(\.path), store: app.store)
        }
        .task(id: Draft(typed: model.typed, location: model.defaultLocation)) {
            try? await Task.sleep(for: StartProjectModel.inspectionDelay)
            guard !Task.isCancelled else { return }
            await model.inspect()
        }
        .task(id: model.typed + model.searchLocations.joined(separator: "\n")) {
            await model.complete()
        }
        .task(id: model.repositoryToCheck) { await model.checkRepository() }
        .task(id: Draft(typed: model.remote, location: model.defaultLocation)) {
            try? await Task.sleep(for: StartProjectModel.inspectionDelay)
            guard !Task.isCancelled else { return }
            await model.readAddress()
        }
        .task(id: model.pathToScan) { await model.scan() }
        .onChange(of: model.outcome) { _, outcome in
            guard let outcome else { return }
            settle(outcome)
        }
        .onDisappear { model.discardIfLeavingMidWork() }
    }

    private struct Draft: Equatable {
        var typed: String
        var location: String
    }

    private var plinth: some View {
        VStack(spacing: Metrics.spacing) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: Self.markSize, height: Self.markSize)
                .accessibilityHidden(true)

            Text(WindowTitleMark.decorate(WindowTitleMark.defaultTitle))
                .font(Typo.display)
                .tracking(Typo.displayTracking)
                .foregroundStyle(Palette.textPrimary)

            Text(versionLine)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.top, Metrics.gutter * 2)
        .padding(.bottom, Metrics.gutter)
    }

    @ViewBuilder
    private func body(for stage: StartProjectStage) -> some View {
        switch stage {
        case .landing:
            StartProjectLanding(
                recent: model.recent,
                repos: offeredProjects,
                home: model.home,
                onNewProject: { model.show(.naming) },
                onClone: { model.show(.cloning) },
                onOpen: openFolder,
                onPick: pick(_:)
            )

        case .naming:
            inset {
                StartProjectForm(model: model, onChoose: chooseFolder, onSubmit: model.start)
            }

        case .cloning:
            inset { StartProjectCloneForm(model: model, onSubmit: model.clone) }

        case .creating(let step):
            inset { StartProjectProgress(step: step, isSlow: model.isStepSlow) }
                .task(id: step) { await model.watchForSlowness(step.patience) }

        case .fetching:
            inset { StartProjectFetching(isSlow: model.isStepSlow) }
                .task { await model.watchForSlowness(RepositoryCloner.patience) }

        case .failed(let fault):
            inset { StartProjectFailure(fault: fault) }
        }
    }

    private func inset<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Metrics.gutter) { content() }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, Metrics.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Hairline()
            StartProjectActions(
                model: model,
                onStart: model.start,
                onClone: model.clone,
                onStop: model.stop,
                onClose: model.discardAndLeave
            )
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(Typo.label)
                .foregroundStyle(Palette.textPrimary)
                .frame(width: Self.closeSize, height: Self.closeSize)
                .background(Palette.hover, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(Metrics.spacing)
        .help("Close")
        .accessibilityLabel("Close")
    }

    private var versionLine: String {
        BuildIdentity.read(from: .main).line(built: BuildTimestamp.read(from: .main))
    }

    private var offeredProjects: [Repo] {
        StartProjectPick.offered(app.profileRepos, showingHidden: showsHiddenProjects)
    }

    private func openFolder() {
        Task {
            let chosen = await ProjectFolderPicker.chooseTarget(startingAt: model.home)
            guard let chosen else { return }
            dismiss()
            await add(chosen)
        }
    }

    private func chooseFolder() {
        Task {
            let chosen = await ProjectFolderPicker.chooseTarget(
                startingAt: model.folderToOpenFrom()
            )
            guard let chosen else { return }
            model.choose(chosen)
        }
    }

    private func pick(_ path: String) {
        guard let project = StartProjectPick.project(at: path, repos: offeredProjects) else {
            return openFolder(at: path)
        }
        dismiss()
        Task { await remember(project.path) }
        let opened = StartProjectPick.opens(repo: project, workspaces: app.workspaces) { _ in true }
        guard let opened else { return app.openDraft(in: project) }
        app.selection = .workspace(opened)
    }

    private func openFolder(at path: String) {
        Task {
            dismiss()
            await add(path)
        }
    }

    private func add(_ path: String) async {
        await app.addRepository(at: path)
        guard StartProjectPick.project(at: path, repos: app.repos) != nil else { return }
        await remember(path)
    }

    private func settle(_ outcome: StartProjectOutcome) {
        guard case .started(let started) = outcome else { return dismiss() }
        Task {
            let repo = await app.addStartedProject(at: started.path)
            if repo != nil { await remember(started.path) }
            dismiss()
            guard started.opensWorkspace, let repo else { return }
            app.openDraft(in: repo)
        }
    }

    private func remember(_ path: String) async {
        guard let store = app.store else { return }
        try? await DirectoryPreferences.remember(path, in: store)
    }
}
