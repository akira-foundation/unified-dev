import AppKit
import SwiftUI
import Core

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow

    @Bindable private var projectSetup = ProjectSetup.shared
    @Bindable private var closeSession = CloseSessionAlert.shared
    @Bindable private var setupRun = SetupRunAlert.shared
    @Bindable private var feedback = FeedbackPresenter.shared

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var centreWidth: CGFloat = 0
    @State private var sidebarWidth = Metrics.sidebarWidth
    @State private var sidebarFooterWidth: CGFloat = 0
    @State private var profileNameWidth: CGFloat?
    @State private var fullScreenBarIsHidden = false
    @State private var isStartingProject = false

    var body: some View {
        @Bindable var app = app

        return windowWiring(
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView()
                    .navigationSplitViewColumnWidth(
                        min: widths.sidebarMinimum,
                        ideal: max(Metrics.sidebarWidth, widths.sidebarMinimum),
                        max: columns.sidebarCeiling
                    )
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { sidebarWidth = $0 }
                    .onPreferenceChange(SidebarFooterWidth.self) { sidebarFooterWidth = $0 }
                    .toolbar {
                        if columns.drawsSidebar, fullScreenBarIsHidden {
                            ProfileSwitcherToolbar(
                                app: app,
                                placement: .automatic,
                                drawsSidebar: true,
                                barIsHidden: true,
                                sidebarWidth: sidebarWidth
                            )
                        }
                        if columns.drawsSidebar, !fullScreenBarIsHidden {
                            ProfileSwitcherToolbar(
                                app: app, placement: .secondaryAction, drawsSidebar: true, sidebarWidth: sidebarWidth
                            )
                        }
                    }
            } content: {
                DetailColumn()
                    .navigationSplitViewColumnWidth(
                        min: Metrics.centreColumnMinimum,
                        ideal: Metrics.centreColumnIdeal,
                        max: .infinity
                    )
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { centreWidth = $0 }
                    .noticeStage()
                    .toolbar {
                        WindowToolbar(
                            app: app,
                            centreWidth: centreWidth,
                            columns: columns,
                            startFreshAskConversation: { Task { await app.ask.newConversation() } }
                        )
                    }
            } detail: {
                InspectorColumn(isDrawn: columns.drawsInspector)
                    .navigationSplitViewColumnWidth(
                        min: Metrics.inspectorMinimum,
                        ideal: Metrics.inspectorWidth,
                        max: Metrics.inspectorMaximum
                    )
            }
            .draws(columns)
            .navigationTitle(WindowTitleMark.decorate(app.menuWorkspace?.name ?? WindowTitleMark.defaultTitle))
            .toolbar(removing: WindowToolbar.showsTabs(in: app) ? .title : nil)
            .keepsToolbarGroundAtToolbarHeight()

            .focusedSceneValue(\.isMainWindowFocused, true)

            .onChange(of: app.activeProfile?.name, initial: true) { _, name in
                profileNameWidth = name.map(ProfileSwitcherMenu.nameWidth)
            }

            .onChange(of: columns.reach, initial: true) { _, reach in
                columnVisibility = reach == .all ? .all : .doubleColumn
            }

            .onChange(of: columnVisibility) { _, visibility in
                guard columns.fitsSidebar else { return }
                app.isSidebarHidden = visibility != .all
            }

            .task { await app.bootstrap() }
            .task { FeedbackPresenter.shared.presentIfRequested() }
            .task { presentSearchPanelIfRequested() }
            .sheet(item: $feedback.sheet) { sheet in
                switch sheet {
                case .report: FeedbackSheet()
                case .prompt: PromptSubmissionSheet()
                case .reportSent:
                    FeedbackSentCard(
                        title: feedback.filedTitle(or: Feedback.Copy.reportSent),
                        detail: feedback.filedSentence(or: Feedback.Copy.reportSentDetail),
                        link: feedback.filedLink,
                        onDismiss: feedback.close
                    )
                case .promptSent:
                    FeedbackSentCard(
                        title: feedback.filedTitle(or: Feedback.Copy.promptSent),
                        detail: feedback.filedSentence(or: Feedback.Copy.promptSentDetail),
                        link: feedback.filedLink,
                        onDismiss: feedback.close
                    )
                }
            }
            .sheet(item: $projectSetup.request.on(.main)) { request in
                ProjectSetupSheet(request: request) { path in
                    Task { await app.finishProjectSetup(path) }
                }
            }
            .sheet(item: $app.profileSheet) { request in
                ProfileSheet(request: request, profiles: app.profiles, source: app.accountChoices.accounts.source(of:))
            }
            .confirmationDialog(
                "Archive this workspace?",
                isPresented: $app.pendingArchive.isPresent(),
                titleVisibility: .visible,
                presenting: app.pendingArchive
            ) { request in
                Button(
                    request.confirmLabel, role: request.isDestructive ? .destructive : nil
                ) { confirmArchive(request) }
                Button(request.cancelLabel, role: .cancel, action: app.cancelPendingArchive)
            } message: { request in
                Text(request.message)
            }
            .confirmationDialog(
                closeSession.request?.title ?? "",
                isPresented: $closeSession.request.isPresent(),
                titleVisibility: .visible,
                presenting: closeSession.request
            ) { request in
                Button(request.cost.confirmTitle, role: .destructive) { closeSession.confirm() }
                Button(request.cost.cancelTitle, role: .cancel) { closeSession.cancel() }
            } message: { request in
                Text(request.message)
            }
            .confirmation($setupRun.request) { request in
                Confirmation(
                    title: request.question.title,
                    message: request.question.message,
                    confirmLabel: request.question.confirmLabel,
                    cancelLabel: request.question.cancelLabel
                )
            } onConfirm: { request in
                request.model.runSetupAgain()
            }
            .modifier(CodeBlockRunConfirmation())
            .alert(
                app.alert?.title ?? "",
                isPresented: $app.alert.isPresent(),
                presenting: app.alert
            ) { _ in
            } message: { alert in
                Text(alert.message)
            }
            .onReceive(OpenWorkspaceNotification.publisher()) { id in
                Task { await app.open(workspaceID: id) }
            }
        )
    }

    private func presentSearchPanelIfRequested() {
        #if DEBUG
        SearchPanelModel.shared.presentIfRequested(app: app)
        #endif
    }

    private func windowWiring(_ content: some View) -> some View {
        content
        .searchPanel(app: app)
        .onReceive(NotificationCenter.default.publisher(for: .unifieddevFocusSearch)) { _ in
            SearchPanelModel.shared.open(scope: .transcripts, app: app)
        }
        .onChange(of: app.homeFilter.query) { old, new in
            let was = !WorkspaceSearch.needle(old).isEmpty
            let now = !WorkspaceSearch.needle(new).isEmpty
            guard was != now else { return }
            app.homeFilter.scope = HomeScope.settle(app.homeFilter.scope, searching: now)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.notificationInbox.noteOnScreen()
        }
        .background(FullScreenBarReader { fullScreenBarIsHidden = $0 })
        .onReceive(NotificationCenter.default.publisher(for: .unifieddevToggleSidebar)) { _ in
            toggleSidebar()
        }
        .onReceive(NotificationCenter.default.publisher(for: .unifieddevOfferProjectSetup)) { note in
            guard let path = note.object as? String else { return }
            Task { await app.addRepository(at: path) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .unifieddevOpenRepoSettings)) { note in
            let named = note.object as? String
            let repo = ProfileScope.repo(named: named, in: app.repos, preferring: app.activeProfileID) ?? app.profileRepos.first
            guard let repo else { return }
            openWindow(id: RepoSettingsWindow.id, value: repo.id)
        }
        .acceptsCaptureRunningState(app)
        .acceptsCaptureNotice(app)
        .onReceive(NotificationCenter.default.publisher(for: .udNewProject)) { _ in
            isStartingProject = true
        }
        .sheet(isPresented: $isStartingProject) { StartProjectSheet() }
        .onReceive(NotificationCenter.default.publisher(for: .udNewAskConversation)) { _ in
            app.selection = .ask
            Task { await app.ask.newConversation() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .udNewWorkspace)) { note in
            app.openDraft(
                in: note.object as? Repo,
                asksForStartingPoint: note.userInfo?[Notification.unifieddevPullRequestKey] as? Bool == true
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .unifieddevStartTerminalWorkspace)) { note in
            let named = note.object as? String
            let repo = ProfileScope.repo(named: named, in: app.repos, preferring: app.activeProfileID) ?? app.profileRepos.first
            guard let repo else { return }
            Task { await app.createWorkspace(in: repo, prompt: "", opensWith: .terminal) }
        }
    }

    private func toggleSidebar() {
        withAnimation(reduceMotion ? nil : Motion.pane) {
            app.isSidebarHidden = columns.drawsSidebar
        }
    }

    private var availableWidth: CGFloat {
        ProbeHarness.points(
            "--window-available-width",
            or: NSScreen.main?.visibleFrame.width ?? .greatestFiniteMagnitude
        )
    }

    private var columns: WindowColumns {
        WindowColumns.resolve(
            selection: app.selection,
            hasInspectorSubject: app.selectedModel != nil,
            reservesInspectorRoom: app.selectedWorkspace != nil,
            hidesSidebar: app.isSidebarHidden,
            hidesInspector: app.inspectorVisibility.hidesInspector,
            widths: widths,
            availableWidth: availableWidth
        )
    }

    private var widths: WindowWidths {
        let titleBar = profileNameWidth.map(ProfileToolbarLabel.titleBarWidth(forNameWidth:))
        return UnifiedDevApp.widths.holding(sidebarContent: [titleBar, sidebarFooterWidth].compactMap { $0 })
    }

    private func confirmArchive(_ request: ArchiveRequest) {
        Task { await app.confirmArchive(request) }
    }
}

extension Notification.Name {
    static let unifieddevToggleSidebar = Notification.Name("unifieddev.toggleSidebar")
    static let unifieddevFocusSearch = Notification.Name("unifieddev.focusSearch")
    static let udNewWorkspace = Notification.Name("unifieddev.newWorkspace")
    static let udNewAskConversation = Notification.Name("unifieddev.newAskConversation")
    static let udNewProject = Notification.Name("unifieddev.newProject")
    static let unifieddevStartTerminalWorkspace = Notification.Name("unifieddev.startTerminalWorkspace")
    static let unifieddevRenameWorkspace = Notification.Name("unifieddev.renameWorkspace")
    static let unifieddevRenameTab = Notification.Name("unifieddev.renameTab")
}

extension Notification {
    static let unifieddevPullRequestKey = "unifieddev.newWorkspace.pullRequest"
    static let unifieddevWorkspaceIDKey = "unifieddev.workspaceID"
}

private struct InspectorColumn: View {
    let isDrawn: Bool

    @Environment(AppModel.self) private var app

    var body: some View {
        if isDrawn, let model = app.selectedModel {
            InspectorView(model: model)
        } else {
            Color.clear
        }
    }
}
