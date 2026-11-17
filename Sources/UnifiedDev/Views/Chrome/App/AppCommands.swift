import AppKit
import SwiftUI
import Core

@MainActor
struct AppCommands: Commands {
    private let model: AppModel

    private let zoom = TextZoomAvailability.shared

    private let updater = SoftwareUpdater.shared

    @FocusedValue(\.isMainWindowFocused) private var isMainWindowFocused: Bool?

    @FocusedValue(\.focusedWorkspaceRow) private var focusedRow: FocusedWorkspaceRow?

    @FocusedValue(\.sourceFind) private var sourceFind
    @FocusedValue(\.saveAction) private var saveAction: SaveAction?

    @FocusedValue(\.composerTranscript) private var composerTranscript: TranscriptModel?
    @FocusedValue(\.isTypingProse) private var isTypingProse: Bool?

    @Environment(\.openWindow) private var openWindow

    @AppStorage(SidebarGrouping.storageKey) private var storedGrouping = SidebarGrouping.standard.rawValue

    init(model: AppModel) {
        self.model = model
    }

    private var groupingChoice: Binding<SidebarGrouping> {
        let stored = $storedGrouping
        return Binding(
            get: { SidebarGrouping.resolve(stored.wrappedValue) },
            set: { stored.wrappedValue = $0.rawValue }
        )
    }

    private var projectSettingsRepo: Repo? {
        model.selectedWorkspace.flatMap(model.repo(for:)) ?? model.profileRepos.first
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            MenuCommand(.about) {
                AboutWindow.show()
            }
        }

        CommandGroup(after: .appInfo) {
            Button("Settings\u{2026}") { openWindow(id: SettingsWindow.id) }
                .keyboardShortcut(",", modifiers: .command)

            Button(SpendLines.title) { openWindow(id: SpendScreenWindow.id) }

            if updater.availability != .localBuild {
                MenuCommand(.checkForUpdates) {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
        }

        CommandGroup(replacing: .newItem) {
            MenuCommand(.newWorkspace) {
                NotificationCenter.default.post(name: .udNewWorkspace, object: nil)
            }
            .disabled(model.profileRepos.isEmpty)

            MenuCommand(.newWorkspaceFromPullRequest) {
                NotificationCenter.default.post(
                    name: .udNewWorkspace, object: nil,
                    userInfo: [Notification.unifieddevPullRequestKey: true]
                )
            }
            .disabled(model.profileRepos.isEmpty)

            MenuCommand(.projectSettings) {
                guard let repo = projectSettingsRepo else { return }
                openWindow(id: RepoSettingsWindow.id, value: repo.id)
            }
            .disabled(projectSettingsRepo == nil)

            MenuCommand(.newAskConversation) {
                NotificationCenter.default.post(name: .udNewAskConversation, object: nil)
            }

            MenuCommand(.newCanvas) {
                model.newCanvas()
            }
            .disabled(model.selectedWorkspace == nil)

            MenuCommand(.searchFiles) {
                SearchPanelModel.shared.openFiles(app: model)
            }
            .disabled(model.selectedWorkspace == nil)

            MenuCommand(.newSession) {
                if model.selection == .ask {
                    Task { await model.ask.newConversation() }
                    return
                }
                guard let workspace = model.selectedModel else { return }
                Task { await workspace.createSession() }
            }
            .disabled(model.selectedModel == nil && model.selection != .ask)

            Divider()

            MenuCommand(.newTerminalTab) { openPane(.terminal) }
                .disabled(model.selectedModel == nil)

            MenuCommand(.newBrowserTab) { openBrowserPane() }
                .disabled(model.selectedModel == nil)

            MenuCommand(.showChanges) {
                guard let workspace = model.selectedModel else { return }
                FileReview.toggle(in: workspace)
            }
            .disabled(model.selectedModel == nil)

            MenuCommand(.reviewAllFiles) {
                guard let workspace = model.selectedModel else { return }
                FileReview.openAll(in: workspace)
            }
            .disabled(model.selectedModel == nil)

            MenuCommand(.showNotes) {
                guard let workspace = model.selectedModel else { return }
                WorkspaceNotes.open(in: workspace)
            }
            .disabled(model.selectedModel == nil)

            Divider()

            MenuCommand(.renameTab) { renameSelectedTab() }
                .disabled(isMainWindowFocused != true || renamableTab == nil)

            MenuCommand(.closeTab) {
                closeSelectedTab()
            }
            .disabled(isMainWindowFocused != true || (closableTab == nil && !canCloseAskTab))

            Divider()

            MenuCommand(.startProject) {
                NotificationCenter.default.post(name: .udNewProject, object: nil)
            }
        }

        CommandGroup(replacing: .saveItem) {
            MenuCommand(.save) { saveAction?.perform() }
                .disabled(saveAction?.isEnabled != true)
        }

        CommandGroup(after: .pasteboard) {
            Divider()

            Menu("Find") {
                MenuCommand(.find, perform: find)
                    .disabled(model.profileRepos.isEmpty && !FindInPlace.isAvailable)

                MenuCommand(.findNext) { step(.nextMatch) }

                MenuCommand(.findPrevious) { step(.previousMatch) }
            }

            MenuCommand(.quickSearch) {
                SearchPanelModel.shared.open(app: model)
            }

            MenuCommand(.search) {
                NotificationCenter.default.post(name: .unifieddevFocusSearch, object: nil)
            }
            .disabled(model.profileRepos.isEmpty)
        }

        CommandGroup(after: .sidebar) {
            splitMenu(.splitRight, axis: .horizontal, symbol: PaneSymbol.splitRight)
            splitMenu(.splitDown, axis: .vertical, symbol: PaneSymbol.splitDown)

            MenuCommand(.closePane, symbol: PaneSymbol.closePane) { closeCentrePane() }
                .disabled(model.selectedModel == nil)

            MenuCommand(.zoomPane, symbol: PaneSymbol.zoomIn) { terminalPane(.toggleZoom) }
                .disabled(!canCommandTerminalPane)

            MenuCommandGroup(.focusPane) {
                ForEach(SplitDirection.allCases, id: \.self) { direction in
                    Button(direction.title) { terminalPane(.focus(direction)) }
                }
            }
            .disabled(!canCommandTerminalPane)

            Divider()

            MenuCommand(.previousTab) { cycleCentreTab(by: -1) }
                .disabled(!canCycleCentreTabs)

            MenuCommand(.nextTab) { cycleCentreTab(by: 1) }
                .disabled(!canCycleCentreTabs)

            goToTabMenu

            Divider()

            MenuCommand(.fileBack, alternate: focusedBrowser?.paneState.usesAlternateTitle(.back) == true) {
                if let focusedBrowser {
                    focusedBrowser.run(.back)
                    return
                }
                guard let workspace = model.selectedModel else { return }
                SourceNavigation.shared.move(-1, in: workspace)
            }
            .disabled(focusedBrowser.map { !$0.paneState.isEnabled(.back) } ?? (fileHistory?.canGoBack != true))

            MenuCommand(.fileForward, alternate: focusedBrowser?.paneState.usesAlternateTitle(.forward) == true) {
                if let focusedBrowser {
                    focusedBrowser.run(.forward)
                    return
                }
                guard let workspace = model.selectedModel else { return }
                SourceNavigation.shared.move(1, in: workspace)
            }
            .disabled(focusedBrowser.map { !$0.paneState.isEnabled(.forward) } ?? (fileHistory?.canGoForward != true))

            MenuCommand(.nextChangedFile) { stepChangedFile(1) }
                .disabled(!canStepChangedFiles)

            MenuCommand(.previousChangedFile) { stepChangedFile(-1) }
                .disabled(!canStepChangedFiles)

            Divider()

            BrowserMenuCommands(session: focusedBrowser)

            Divider()
        }

        CommandGroup(after: .sidebar) {
            MenuCommand(.toggleSidebar) {
                NotificationCenter.default.post(name: .unifieddevToggleSidebar, object: nil)
            }

            MenuCommand(.toggleInspector, alternate: model.inspectorVisibility.menuTitleIsAlternate) {
                model.toggleInspector()
            }

            Picker("Group Sidebar By", selection: groupingChoice) {
                ForEach(SidebarGrouping.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }

            Divider()

            MenuCommand(.nextWorkspace) {
                model.selectNextWorkspace(offset: 1)
            }
            .disabled(model.profileWorkspaces.isEmpty)

            MenuCommand(.previousWorkspace) {
                model.selectNextWorkspace(offset: -1)
            }
            .disabled(model.profileWorkspaces.isEmpty)

            MenuCommand(.nextUnread) {
                model.selectNextUnread()
            }
            .disabled(!model.profileWorkspaces.contains(where: \.unread))

            MenuCommand(.goToHome) {
                model.selection = .home
            }
            .disabled(model.selection == .home)

            MenuCommand(.goToAsk) {
                model.selection = .ask
            }
            .disabled(model.selection == .ask)
        }

        CommandGroup(after: .sidebar) {
            Divider()

            MenuCommand(.zoomIn) { TextZoom.zoomIn() }
                .disabled(!zoom.canZoomIn)

            MenuCommand(.zoomOut) { TextZoom.zoomOut() }
                .disabled(!zoom.canZoomOut)

            MenuCommand(.actualSize) { TextZoom.actualSize() }
                .disabled(!zoom.canResetSize)
        }

        CommandMenu("Workspace") {
            MenuCommand(.renameWorkspace) {
                guard let workspace = workspace(for: .rename) else { return }
                NotificationCenter.default.post(
                    name: .unifieddevRenameWorkspace, object: nil,
                    userInfo: [Notification.unifieddevWorkspaceIDKey: workspace.id.rawValue]
                )
            }
            .disabled(workspace(for: .rename) == nil)

            if let workspace = workspace(for: .pin) {
                WorkspacePinItem(workspace: workspace, app: model)
            } else {
                MenuCommand(.pin) {}.disabled(true)
            }

            if let workspace = workspace(for: .unreadMark) {
                WorkspaceUnreadItem(workspace: workspace, app: model)
            } else {
                MenuCommand(.unreadMark) {}.disabled(true)
            }

            if let workspace = workspace(for: .colour) {
                WorkspaceColourItem(workspace: workspace, app: model)
            } else {
                MenuCommand(.colour) {}.disabled(true)
            }

            Divider()

            MenuCommand(.archive) {
                guard let workspace = workspace(for: .archive) else { return }
                archive(workspace)
            }
            .disabled(workspace(for: .archive) == nil || isTypingProse == true)

            MenuCommand(.restore) {
                guard let workspace = restorableWorkspace else { return }
                Task { await model.restore(workspace) }
            }
            .disabled(restorableWorkspace == nil)

            Divider()

            MenuCommand(.openInEditor) {
                guard let workspace = workspace(for: .openInEditor) else { return }
                Reveal.inEditor(workspace.path, repo: workspace.repoID)
            }
            .disabled(workspace(for: .openInEditor) == nil)

            MenuCommand(.revealInFinder) {
                guard let workspace = workspace(for: .revealInFinder) else { return }
                Reveal.inFinder(workspace.path)
            }
            .disabled(workspace(for: .revealInFinder) == nil)

            MenuCommand(.copyName) {
                guard let workspace = workspace(for: .copyName) else { return }
                Clipboard.copy(workspace.name)
            }
            .disabled(workspace(for: .copyName) == nil)

            MenuCommand(.copyBranchName) {
                guard let workspace = workspace(for: .copyBranchName) else { return }
                Clipboard.copy(workspace.branch)
            }
            .disabled(workspace(for: .copyBranchName) == nil)

            Divider()

            setupItem

            runScriptsMenu

            MenuCommand(.stopAgent) {
                (composerTranscript ?? subjectModel?.activeTranscript)?.stop()
            }
            .disabled((composerTranscript ?? subjectModel?.activeTranscript)?.isRunning != true)
        }

        Group {
            ProfileCommands(model: model)

            CommandGroup(replacing: .help) {
                MenuCommand(.help) {
                    NSWorkspace.shared.open(AppRepository.readmeURL)
                }

                MenuCommand(.welcome) {
                    WelcomeWindow.show(trigger: .firstRun, restarting: true)
                }

                Divider()

                MenuCommand(.sendFeedback) {
                    FeedbackPresenter.shared.open(.report)
                }

                MenuCommand(.submitPrompt) {
                    FeedbackPresenter.shared.open(.prompt)
                }
            }
        }
    }

    @ViewBuilder
    private var setupItem: some View {
        if let workspace = model.selectedModel, let offer = workspace.setupRunOffer {
            Button(offer.title) { SetupRunAlert.shared.ask(workspace) }
                .disabled(!offer.isEnabled)
        }
    }

    @ViewBuilder
    private var runScriptsMenu: some View {
        if let workspace = model.selectedModel, !workspace.settings.runScripts.isEmpty {
            MenuCommandGroup(.runScripts) {
                ForEach(workspace.settings.runScripts) { script in
                    Button(script.name) { RunScriptLauncher.shared.pick(script, in: workspace) }
                        .disabled(!RunScriptLauncher.shared.menuItem(for: script, in: workspace).isEnabled)
                }
            }

            Divider()
        }
    }

    private func splitMenu(_ action: MenuBarAction, axis: SplitAxis, symbol: String) -> some View {
        MenuCommandGroup(action, symbol: symbol) {
            ForEach(PaneKind.allCases) { kind in
                splitRow(action, axis: axis, kind: kind)
            }
        }
        .disabled(model.selectedModel == nil)
    }

    @ViewBuilder
    private func splitRow(_ action: MenuBarAction, axis: SplitAxis, kind: PaneKind) -> some View {
        let row = Button(kind.title, systemImage: kind.symbol) {
            splitCentre(axis, opening: kind)
        }
        if kind == sameAgainKind, let key = MenuBarCatalogue[action].key {
            row.keyboardShortcut(key.equivalent, modifiers: key.eventModifiers)
        } else {
            row
        }
    }

    private var sameAgainKind: PaneKind? {
        guard let workspace = model.selectedModel else { return nil }
        let tabs = WorkspaceTabsStore.shared
        guard let tab = tabs.selectedTab(in: workspace) else { return nil }
        return PaneDuplicate.sameAgainKind(
            tabs.content(of: tabs.focusedPane(of: tab), in: tab), in: workspace
        )
    }

    private func splitCentre(_ axis: SplitAxis, opening kind: PaneKind) {
        guard let workspace = model.selectedModel else { return }
        let tabs = WorkspaceTabsStore.shared
        guard let tab = tabs.selectedTab(in: workspace) else { return }
        let pane = tabs.focusedPane(of: tab)

        NewPane.open(kind, in: workspace) { content in
            tabs.split(tab: tab, pane: pane, axis: axis, showing: content)
        }
    }

    private var terminalOwnerID: String? {
        guard let workspace = model.selectedModel else { return nil }
        let tabs = WorkspaceTabsStore.shared
        guard let tab = tabs.selectedTab(in: workspace),
              case .tool(let id) = tabs.content(of: tabs.focusedPane(of: tab), in: tab),
              CenterTabStore.shared.tabs(for: workspace.workspace.id)
                  .first(where: { $0.id == id })?.kind == .terminal else { return nil }
        return id
    }

    private var focusedBrowser: BrowserSession? {
        guard isMainWindowFocused == true, let workspace = model.selectedModel else { return nil }
        let tabs = WorkspaceTabsStore.shared
        guard let tab = tabs.selectedTab(in: workspace),
              case .tool(let id) = tabs.content(of: tabs.focusedPane(of: tab), in: tab),
              let browser = CenterTabStore.shared.tabs(for: workspace.workspace.id)
                  .first(where: { $0.id == id && $0.kind == .browser }) else { return nil }
        return CenterTabStore.shared.browser(for: browser, root: workspace.workspace.path)
    }

    private var canCommandTerminalPane: Bool {
        guard let ownerID = terminalOwnerID else { return false }
        return TerminalSplitStore.shared.panes(of: ownerID).count > 1
    }

    private func terminalPane(_ command: TerminalPaneCommand) {
        guard let ownerID = terminalOwnerID else { return }
        let splits = TerminalSplitStore.shared
        switch command {
        case .toggleZoom:
            _ = splits.toggleZoom(in: ownerID)
        case .focus(let direction):
            _ = splits.moveFocus(direction, in: ownerID)
        case .split, .close:
            return
        }
    }

    private var canCycleCentreTabs: Bool {
        if model.selection == .ask { return model.ask.sessions.count > 1 }
        guard let workspace = model.selectedModel else { return false }
        return WorkspaceTabsStore.shared.entries(in: workspace).count > 1
    }

    private func cycleCentreTab(by offset: Int) {
        _ = CentreTabCycleShortcut.cycle(by: offset, in: model)
    }

    @ViewBuilder
    private var goToTabMenu: some View {
        if model.selection == .ask {
            MenuCommandGroup(.goToTab) {
                ForEach(TabCycle.numbered(model.ask.sessions.map(\.id))) { entry in
                    if let chat = model.ask.sessions.first(where: { $0.id == entry.tab }) {
                        let button = Button(model.ask.title(for: chat)) {
                            Task { await model.ask.select(chat.id) }
                        }
                        if let ordinal = entry.ordinal {
                            button.keyboardShortcut(KeyEquivalent(Character("\(ordinal)")), modifiers: .command)
                        } else { button }
                    }
                }
            }
        }
        if model.selection != .ask, let workspace = model.selectedModel {
            let entries = WorkspaceTabsStore.shared.entries(in: workspace)
            MenuCommandGroup(.goToTab) {
                ForEach(TabCycle.numbered(entries), id: \.tab) { entry in
                    tabItem(entry.tab, ordinal: entry.ordinal, in: workspace)
                }
            }
            .disabled(entries.isEmpty)
        }
    }

    @ViewBuilder
    private func tabItem(_ tab: PaneContent, ordinal: Int?, in workspace: WorkspaceModel) -> some View {
        let button = Button(CenterTabStore.shared.title(of: tab, in: workspace)) {
            WorkspaceTabsStore.shared.select(tab, in: workspace)
        }
        if let ordinal {
            button.keyboardShortcut(KeyEquivalent(Character("\(ordinal)")), modifiers: .command)
        } else {
            button
        }
    }

    private var closableTab: PaneContent? {
        guard let workspace = model.selectedModel else { return nil }
        let tabs = WorkspaceTabsStore.shared
        guard let tab = tabs.selectedTab(in: workspace) else { return nil }
        return TabClosure.target(
            selectedTab: tab,
            focusedPaneContent: tabs.content(of: tabs.focusedPane(of: tab), in: tab)
        )
    }

    private var renamableTab: PaneContent? {
        guard let workspace = model.selectedModel else { return nil }
        let tabs = WorkspaceTabsStore.shared
        guard let selected = tabs.selectedTab(in: workspace) else { return nil }
        let kind = CenterTabStore.shared.tabs(for: workspace.workspace.id)
            .first { $0.id == selected.id }?.kind
        return TabRenaming.canRename(selected, tabKind: kind) ? selected : nil
    }

    private func renameSelectedTab() {
        guard renamableTab != nil else { return }
        NotificationCenter.default.post(name: .unifieddevRenameTab, object: nil)
    }

    private var canCloseAskTab: Bool { model.selection == .ask && model.ask.sessions.count > 1 }

    private func closeSelectedTab() {
        if canCloseAskTab, let id = model.ask.selectedID {
            model.ask.requestClose(id)
            return
        }
        guard let workspace = model.selectedModel, let target = closableTab else { return }
        switch target {
        case .chat(let id):
            guard let session = workspace.sessions.first(where: { $0.id == id }) else { return }
            CloseSessionAlert.shared.close(session, in: workspace)
        case .tool(let id):
            guard let tab = CenterTabStore.shared.tabs(for: workspace.workspace.id)
                .first(where: { $0.id == id }) else { return }
            Task { await CenterTabStore.shared.close(tab, in: workspace) }
        }
    }

    private var fileHistory: SourceHistory? {
        guard let workspace = model.selectedModel,
              let tab = WorkspaceTabsStore.shared.selectedTab(in: workspace),
              case let .tool(id) = WorkspaceTabsStore.shared.content(
                of: WorkspaceTabsStore.shared.focusedPane(of: tab), in: tab),
              CenterTabStore.shared.tabs(for: workspace.workspace.id).contains(where: { $0.id == id && $0.kind == .review })
        else { return nil }
        return SourceNavigation.shared.histories[workspace.workspace.id]
    }

    private var canStepChangedFiles: Bool {
        guard let workspace = model.selectedModel, !workspace.changedFiles.isEmpty else {
            return false
        }
        return CenterTabStore.shared.review(for: workspace.workspace.id) != nil
    }

    private func stepChangedFile(_ delta: Int) {
        guard let workspace = model.selectedModel else { return }
        FileReview.step(delta, in: workspace)
    }

    private func closeCentrePane() {
        guard let workspace = model.selectedModel else { return }
        let tabs = WorkspaceTabsStore.shared
        guard let tab = tabs.selectedTab(in: workspace) else { return }
        tabs.close(
            pane: tabs.focusedPane(of: tab), in: tab, of: workspace.workspace.id
        )
    }

    private func openPane(_ kind: PaneKind) {
        guard let workspace = model.selectedModel else { return }
        NewPane.open(kind, in: workspace) {
            WorkspaceTabsStore.shared.select($0, in: workspace)
        }
    }

    private func openBrowserPane() {
        guard let workspace = model.selectedModel else { return }
        Task {
            let address = await workspace.browserAddress()
            NewPane.open(.browser, in: workspace, url: address) {
                WorkspaceTabsStore.shared.select($0, in: workspace)
            }
        }
    }

    private func find() {
        if !FindInPlace.isAvailable, let sourceFind {
            sourceFind.perform(.showFindInterface)
            return
        }
        switch FindCommand.find(
            canFindInPlace: FindInPlace.isAvailable, hasProjects: !model.profileRepos.isEmpty
        ) {
        case .findInPlace:
            FindInPlace.perform(.showFindInterface)
        case .workspaceSearch:
            NotificationCenter.default.post(name: .unifieddevFocusSearch, object: nil)
        case nil:
            break
        }
    }

    private func step(_ action: NSTextFinder.Action) {
        if !FindInPlace.isAvailable, let sourceFind {
            sourceFind.perform(action)
            return
        }
        guard FindCommand.step(canFindInPlace: FindInPlace.isAvailable) == .findInPlace else {
            return
        }
        FindInPlace.perform(action)
    }

    private var subject: WorkspaceMenuSubject? {
        WorkspaceMenuSubject.resolve(selection: model.selection, focusedRow: focusedRow?.row)
    }

    private func workspace(for action: WorkspaceMenuAction) -> Workspace? {
        guard let subject, subject.allows(action) else { return nil }
        if let focusedRow, focusedRow.workspace.id == subject.id { return focusedRow.workspace }
        return [model.selectedWorkspace, model.selectedArchivedWorkspace]
            .compactMap { $0 }
            .first { $0.id == subject.id }
    }

    private var restorableWorkspace: Workspace? {
        guard let workspace = workspace(for: .restore),
              !model.restoring.contains(workspace.id) else { return nil }
        return workspace
    }

    private var subjectModel: WorkspaceModel? {
        guard let id = subject?.liveID else { return nil }
        return model.existingModel(for: id)
    }

    private func archive(_ workspace: Workspace) {
        Task { await model.archive(workspace) }
    }
}
