import AppKit
import Observation
import Core

struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

@MainActor
@Observable
final class AppModel {
    private(set) var store: Store?
    private(set) var manager: WorkspaceManager?
    @ObservationIgnored private(set) var bridge: BridgeServer?

    private(set) var profiles: [Profile] = []
    private(set) var activeProfileID: ProfileID = .initial
    @ObservationIgnored var profileMemory = ProfileMemoryDefaults.load()
    @ObservationIgnored var activeProfileWrite: Task<Void, Never>?
    var profileSheet: ProfileSheetRequest?

    private(set) var repos: [Repo] = []
    private(set) var workspaces: [Workspace] = []
    var projectActivity: [RepoID: Date] = [:]
    private(set) var isLoaded = false
    private(set) var storedQuotas: [AgentQuota] = []
    private(set) var quotaReadings = QuotaReadings()
    private(set) var quotaScope: QuotaScope?
    private(set) var quotaLedger = QuotaAskLedger()
    private(set) var seededQuotaSilence: (silent: Set<AgentKind>, declining: Set<AgentKind>) = ([], [])

    var selection: SidebarSelection {
        get { storedSelection }
        set {
            guard newValue != storedSelection else { return }
            if let id = newValue.workspaceID, id != storedSelection.workspaceID {
                SwitchTrace.begin(workspaceID: id)
            }
            activateProfile(showing: newValue)
            let previous = storedSelection
            let vacated = previous.workspaceID
            storedSelection = newValue
            seaDiscoveries.leave(vacated, for: newValue.workspaceID)
            leaveDraft(from: previous, to: newValue)
            rememberInActiveProfile(newValue)
            notificationInbox.noteOnScreen()
            Task { [weak self] in await self?.adoptSelectedAccounts() }
            for id in Set([vacated, newValue.workspaceID].compactMap { $0 }) {
                noteSubagentsChanged(workspaceID: id)
            }
            SwitchTrace.mark("selection.set")
            scheduleTranscriptRelease()
            if let id = newValue.workspaceID { workspaceModels[id]?.refreshSettings() }
            guard let id = newValue.workspaceID, workspaceModels[id] == nil,
                  let workspace = workspaces.first(where: { $0.id == id }) else {
                SwitchTrace.mark("model.reused")
                return
            }
            _ = model(for: workspace)
            SwitchTrace.mark("model.created")
        }
    }

    private var storedSelection: SidebarSelection = .home

    func adoptActiveProfile(_ id: ProfileID) {
        guard activeProfileID != id else { return }
        activeProfileID = id
        narrowHomeFilterToActiveProfile()
        saveActiveProfile(id)
        if let span = spendAccountsSpan { loadSpendAccounts(span: span) }
        Task { [weak self] in await self?.adoptSelectedAccounts() }
    }

    func reloadProfiles() async throws {
        guard let store else { return }
        let loaded = try await store.profiles()
        if profiles != loaded { profiles = loaded }
    }

    var inspectorVisibility = InspectorVisibility(
        isVisible: FrameProbe.wantsInspector && InspectorDefaults.stored.isVisible
    )

    var isInspectorVisible: Bool {
        get { inspectorVisibility.isVisible }
        set { inspectorVisibility.isVisible = newValue }
    }

    var isSidebarHidden = false

    var alert: AppAlert?
    var notice: Notice?
    var pendingArchive: ArchiveRequest?
    @ObservationIgnored var acknowledgedCanvasLosses: [RepoID: [String]] = [:]
    var foundTranscripts: [TranscriptWorkspaceMatches] = []
    var foundTranscriptOwners: [WorkspaceID: RepoID] = [:]
    var isTranscriptIndexIncomplete = false
    var pendingTranscriptTarget: TranscriptSearchTarget?

    @ObservationIgnored var transcriptSearchTask: Task<Void, Never>?
    @ObservationIgnored var transcriptBackfillTask: Task<Void, Never>?

    var spendDaysState = SpendDaysState()
    var spendCensus = SpendCensus()
    var spendAccounts = SpendAccountsState.notRead
    @ObservationIgnored var spendAccountsTask: Task<Void, Never>?
    @ObservationIgnored var spendAccountsSpan: SpendSpan?
    @ObservationIgnored var spendIndexTask: Task<Void, Never>?
    @ObservationIgnored var archiveRetentionTask: Task<Void, Never>?
    @ObservationIgnored var transcriptReleaseTask: Task<Void, Never>?
    @ObservationIgnored var spendIndexer: SpendIndexer?
    @ObservationIgnored var lastSpendReadAt: Date?
    var homeFilter = HomeFilter(scope: .archived)

    let drafts = WorkspaceDrafts()

    @ObservationIgnored var undoManager: UndoManager?

    @ObservationIgnored var workspaceModels: [WorkspaceID: WorkspaceModel] = [:]

    var setupScriptPresence = SetupScriptPresence()
    @ObservationIgnored var setupScriptPresenceTask: Task<Void, Never>?
    @ObservationIgnored var setupScriptPresenceGeneration = 0
    @ObservationIgnored var setupScriptPresenceActivationTask: Task<Void, Never>?

    @ObservationIgnored private var storedAsk: AskModel?

    var ask: AskModel {
        if let storedAsk { return storedAsk }
        let model = AskModel(app: self)
        storedAsk = model
        return model
    }

    private(set) var askStatus: WorkspaceStatus?

    private var archivingWorkspaceIDs: Set<WorkspaceID> = []
    @ObservationIgnored var missingWorktrees = MissingWorktreeWatch()

    func isArchiving(_ id: WorkspaceID) -> Bool { archivingWorkspaceIDs.contains(id) }

    private var archiveBookings: [WorkspaceID: SessionID] = [:]

    var mergeArchiveWaits = MergeArchiveWaits()
    var terminalRunningWorkspaceIDs: Set<WorkspaceID> = []
    @ObservationIgnored var mergeArchiveWatch: Task<Void, Never>?

    func bookArchive(of id: WorkspaceID, after sessionID: SessionID) {
        archiveBookings[id] = sessionID
    }

    func takeArchiveBooking(of id: WorkspaceID, endedIn sessionID: SessionID) -> Bool {
        guard archiveBookings[id] == sessionID else { return false }
        archiveBookings[id] = nil
        return true
    }

    private(set) var pendingWorkspaces: [PendingWorkspace] = []

    func showPending(_ pending: PendingWorkspace) {
        guard !pendingWorkspaces.contains(where: { $0.id == pending.id }) else { return }
        pendingWorkspaces.append(pending)
    }

    func forgetPending(_ id: WorkspaceID) {
        pendingWorkspaces.removeAll { $0.id == id }
    }

    private(set) var startHold = WorkspaceStartHold()

    func isStarting(_ workspace: Workspace) -> Bool {
        startHold.contains(workspace.id)
    }

    func beginStart(_ id: WorkspaceID) {
        startHold.begin(id)
    }

    func endStart(_ id: WorkspaceID) {
        guard startHold.contains(id) else { return }
        startHold.release(id)
    }

    private var refreshTask: Task<Void, Never>?
    @ObservationIgnored var pullRequestTrackTask: Task<Void, Never>?
    @ObservationIgnored private var lastDiffRefresh: [WorkspaceID: Date] = [:]
    @ObservationIgnored private var diffRefreshFailures: [WorkspaceID: DiffRefreshSchedule.Failure] = [:]

    @ObservationIgnored private var diffInvalidations = DiffRefreshInvalidations()

    @ObservationIgnored private lazy var worktreeWatcher = WorktreeWatcher { [weak self] paths in
        Task { @MainActor in self?.noteWorktreesChanged(paths) }
    }
    private var storeObservationTask: Task<Void, Never>?
    @ObservationIgnored private var diffStatReads = 0
    private var sessionObservationTask: Task<Void, Never>?
    private var quotaObservationTask: Task<Void, Never>?
    @ObservationIgnored var pullRequestAutoFixesUnderWay: Set<WorkspaceID> = []
    private var workspaceMessageObservationTask: Task<Void, Never>?

    private(set) var workspaceMessagesRevision = 0
    private(set) var workSuggestionsRevision = 0
    private(set) var undecidedSuggestionCounts: [WorkspaceID: Int] = [:]
    var seaDiscoveries = SeaDiscoveries()
    private var workSuggestionObservationTask: Task<Void, Never>?
    private var quotaPollTask: Task<Void, Never>?
    private var quotaActivationTask: Task<Void, Never>?
    @ObservationIgnored var isMenuBarPanelOpen: @MainActor () -> Bool = { false }
    @ObservationIgnored var accountSyncKey: AccountFingerprint?
    private(set) var accountChoices = AgentAccountChoiceBook()
    @ObservationIgnored var selectedAccountHomes: [AgentKind: AgentAccountHome] = [:]
    let agentAccounts = AgentAccountsModel()
    let notificationInbox = NotificationInboxModel()
    var accountMarks = AgentAccountMarks()
    private var identityTask: Task<Void, Never>?
    @ObservationIgnored var iconSearchTask: Task<Void, Never>?

    @ObservationIgnored static weak var probeInstance: AppModel?

    @MainActor
    static var probeSelectedModel: WorkspaceModel? { probeInstance?.selectedModel }

    func bootstrap() async {
        Self.probeInstance = self
        guard store == nil else { return }
        Log.launchStep("bootstrap")
        let began = Date()
        do {
            let store = try await Task.detached(priority: .userInitiated) {
                try Store(path: try Store.defaultPath())
            }.value
            Log.launchStep("store open")
            self.store = store
            GitHub.adoptLoginResolver { [store] directory in await store.gitHubLogin(forDirectory: directory) }
            ComposerModelCatalog.shared.configure(store: store)
            let manager = WorkspaceManager(store: store)
            self.manager = manager
            try await store.resetRunningSessions()
            try await store.recoverDeliveryClaims()
            try await store.dropUnstartedResumes()
            try await store.releaseWorkSuggestionClaims()
            let abandoned = try await store.abandonPendingPermissionAsks()
            if abandoned > 0 {
                Log.permissions.info("closed \(abandoned, privacy: .public) questions left by the last launch")
            }
            try await store.recoverInterruptedSetups()
            switch await PreviewScenarioLaunch.seed(with: manager) {
            case .alert(let trouble): alert = trouble
            case .notice(let ignored): notice = ignored
            case nil: break
            }
            Log.launchStep("scenario seeded")
            await CenterTabStore.shared.adoptTerminalTabs(from: store)
            _ = WorkspaceTabsStore.shared
            TerminalSessionStore.shared.onAgentActivityChanged = { [weak self] in
                self?.noteAgentTurnsChanged()
                self?.settleMergeWaitsAfterTerminalActivity()
            }
            TerminalSessionStore.shared.onAgentTurnFinished = { [weak self] workspaceID in
                guard let self else { return }
                try? await store.touch(workspaceID: workspaceID, unread: self.selection.workspaceID != workspaceID)
                if let model = self.existingModel(for: workspaceID) {
                    Task { await model.onTurnFinished() }
                }
            }
            WorkspacePullRequests.shared.onCurrentRead = { [weak self] workspaceID, pullRequest in
                await self?.noteCurrentPullRequest(pullRequest, for: workspaceID)
                await self?.considerPullRequestAutoFix(pullRequest, for: workspaceID)
            }
            TerminalSessionStore.shared.useStore(store)
            BottomPanelDefaults.forget()
            Log.launchStep("recovery done")
            activeProfileID = try await store.activeProfileID()
            bridge = makeBridge(on: store)
            Log.launchStep("bridge bound")
            await reload()
            Log.launchStep("reloaded")
            await tellOfLostAgentAccountChoices()
            await loadDrafts()
            restoreLastSelection()
            isLoaded = true
            let blocking = Int(Date().timeIntervalSince(began) * 1000)
            Log.launch.info("window usable after \(blocking, privacy: .public)ms")
            Log.launchStep("loaded")
            DispatchQueue.main.async { Log.launchStep("loaded, next turn") }
        } catch {
            Log.launchStep("bootstrap failed")
            alert = AppAlert(
                title: "Could not open the Unified Dev database",
                message: TranscriptStanding.complaint(about: error)
            )
            isLoaded = true
        }

        identityTask = Task { await GitHubIdentity.resolve() }
        startBackgroundRefresh()
        startTrackingPullRequests()
        startObservingStore()
        startObservingSessions()
        startObservingWorkspaceMessages()
        startObservingWorkSuggestions()
        if let store { notificationInbox.start(app: self, store: store) }
        adoptSeededQuotaSilence()
        startObservingQuotas()
        startPollingQuotas()
        followSetupScriptPresenceOnActivation()
        startOwnerRegistrationRepair()
        startProjectIconSearch()
        startTranscriptIndexBackfill()
        startSpendIndexing()
        startArchiveRetention()
    }

    func makeBridge(on store: Store) -> BridgeServer? {
        do {
            let server = try BridgeServer(store: store, toolbox: bridgeToolbox()) { message in
                Log.bridge.info("\(message, privacy: .public)")
            }
            try server.start()
            return server
        } catch {
            Log.bridge.error("could not start the workspace bridge: \(error.readableMessage, privacy: .public)")
            return nil
        }
    }

    private func startOwnerRegistrationRepair() {
        guard let attachment = bridge?.ownerAttachment() else { return }
        let name = BridgeRegistration.ownerServerName
        Task.detached(priority: .utility) {
            switch BridgeUserRegistrationRepair.repairIfStale(serverNamed: name, matching: attachment) {
            case .repaired(let from, let to):
                Log.bridge.info("""
                    repointed \(name, privacy: .public) in ~/.claude.json \
                    from \(from, privacy: .public) to \(to, privacy: .public)
                    """)
            case .couldNotWrite(let message):
                Log.bridge.error("could not repair the \(name, privacy: .public) entry: \(message, privacy: .public)")
            case .unchanged:
                break
            }
        }
    }

    func shutdownEverything() async {
        await flushDrafts()
        await activeProfileWrite?.value
        await flushCanvasDocuments()
        refreshTask?.cancel()
        refreshTask = nil
        pullRequestTrackTask?.cancel()
        pullRequestTrackTask = nil
        worktreeWatcher.stop()
        storeObservationTask?.cancel()
        storeObservationTask = nil
        sessionObservationTask?.cancel()
        sessionObservationTask = nil
        quotaObservationTask?.cancel()
        quotaObservationTask = nil
        workspaceMessageObservationTask?.cancel()
        workspaceMessageObservationTask = nil
        workSuggestionObservationTask?.cancel()
        workSuggestionObservationTask = nil
        notificationInbox.stop()
        quotaPollTask?.cancel()
        quotaPollTask = nil
        quotaActivationTask?.cancel()
        quotaActivationTask = nil
        identityTask?.cancel()
        identityTask = nil
        iconSearchTask?.cancel()
        iconSearchTask = nil
        setupScriptPresenceTask?.cancel()
        setupScriptPresenceTask = nil
        setupScriptPresenceActivationTask?.cancel()
        setupScriptPresenceActivationTask = nil
        archiveRetentionTask?.cancel()
        archiveRetentionTask = nil
        bridge?.stop()
        bridge = nil

        let models = Array(workspaceModels.values)
        for model in models { model.stopEverything() }
        storedAsk?.stopEverything()

        async let terminals: Void = TerminalSessionStore.shared.shutdownAll()
        for model in models { await model.shutdown() }
        await storedAsk?.shutdown()
        await terminals
    }

    func reload() async {
        guard let store else { return }
        #if DEBUG
        ActivityTally.reloads += 1
        #endif
        let known = Set(workspaces.map(\.id))
        do {
            try await reloadProfiles()
            let loadedRepos = try await store.repos()
            let loadedWorkspaces = try await store.workspaces()
            let loadedChoices = try await store.agentAccountChoices()
            let listed = WorkspaceListReconciliation.afterStoreReload(
                fresh: loadedWorkspaces, archiving: archivingWorkspaceIDs
            )
            let crew = Set(listed.map(\.id)) != known ? try await store.crewByWorkspace() : nil
            let reconciled = WorkspaceListReconciliation.afterStoreReload(
                fresh: loadedWorkspaces, archiving: archivingWorkspaceIDs
            )
            if accountChoices != loadedChoices { accountChoices = loadedChoices }
            let setupPresenceIsStale = repos != loadedRepos || Set(reconciled.map(\.id)) != known
            if repos != loadedRepos { repos = loadedRepos }
            if workspaces != reconciled { workspaces = reconciled }
            if setupPresenceIsStale { refreshSetupScriptPresence() }
            settleSelectionInActiveProfile()
            if !pendingWorkspaces.isEmpty {
                let landed = Set(reconciled.map(\.id))
                pendingWorkspaces.removeAll { landed.contains($0.id) }
            }
            worktreeWatcher.watch(
                roots: workspaces.map(\.path),
                branches: Dictionary(
                    workspaces.map {
                        ($0.path, WorktreeWatcher.concernedBranches(branch: $0.branch, base: $0.baseBranch))
                    }, uniquingKeysWith: { $0.union($1) }
                )
            )
            for workspace in workspaces {
                CenterTabStore.shared.load(workspaceID: workspace.id)
                if let existing = workspaceModels[workspace.id], existing.workspace != workspace {
                    existing.workspace = workspace
                }
            }
            if let crew { applyCrew(crew) }
            await refreshProjectActivity()
            await adoptSelectedAccounts()
            await adoptDiffStats()
        } catch {
            alert = AppAlert(
                title: "Could not read workspaces",
                message: TranscriptStanding.complaint(about: error)
            )
        }
    }

    func adoptProjectIcon(_ path: String?, source: RepoIconSource, forRepoID id: RepoID) {
        guard let index = repos.firstIndex(where: { $0.id == id }) else { return }
        repos[index].iconPath = path
        repos[index].iconSource = source
    }

    func recordQuotas(_ reported: [AgentQuota]) async {
        guard let store, !reported.isEmpty else { return }
        let quotas = QuotaMerge.resolved(reported, against: storedQuotas)
        try? await store.recordQuotas(quotas)
    }

    func reloadQuotas() async {
        guard let store else { return }
        let loaded = (try? await store.quotas()) ?? []
        if storedQuotas != loaded { storedQuotas = loaded }
    }

    func adoptQuotaScope(_ scope: QuotaScope) {
        guard quotaScope != scope else { return }
        quotaScope = scope
        Task { [weak self] in await self?.refreshQuotas(after: QuotaPollSchedule.onDemandFloor) }
    }

    func refreshQuotas(after gap: TimeInterval) async {
        guard store != nil, !UserDefaults.standard.bool(forKey: PreviewScenario.holdsQuotasKey) else { return }
        if let quotaScope, quotaLedger.due(quotaScope.holders.values, at: Date(), after: gap).isEmpty { return }
        guard let resolution = await accountResolution(for: selectedAccountScope) else { return }
        let sources = AgentQuotaSources.all(accounts: resolution.homes, refusing: resolution.refusedProviders)
        let due = quotaLedger.due(sources.map(\.holder), at: Date(), after: gap)
        guard !due.isEmpty else { return }
        quotaLedger.begin(due, at: Date())
        defer { quotaLedger.end(due) }
        let report = await AgentQuotaSources.report(sources.filter { due.contains($0.holder) })
        var readings = quotaReadings
        readings.adopt(report)
        if readings != quotaReadings { quotaReadings = readings }
        await recordQuotas(report.quotas)
    }

    private func adoptSeededQuotaSilence() {
        let silent = UserDefaults.standard.stringArray(forKey: PreviewScenario.silentAgentsKey) ?? []
        let quotaless = UserDefaults.standard.stringArray(forKey: PreviewScenario.agentsWithoutLimitsKey) ?? []
        seededQuotaSilence = (PreviewScenario.agents(storedAs: silent), PreviewScenario.agents(storedAs: quotaless))
    }

    private func refreshQuotasIfDue() async {
        let activity: DiffRefreshSchedule.Activity = NSApp?.isActive ?? true ? .foreground : .background
        await refreshQuotas(after: QuotaPollSchedule.gap(for: activity, isPanelOpen: isMenuBarPanelOpen()))
    }

    private func startPollingQuotas() {
        quotaPollTask?.cancel()
        quotaPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshQuotasIfDue()
                try? await Task.sleep(for: .seconds(QuotaPollSchedule.tick))
            }
        }
        quotaActivationTask?.cancel()
        quotaActivationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                guard let self else { return }
                await self.refreshQuotas(after: QuotaPollSchedule.gap(for: .foreground, isPanelOpen: false))
            }
        }
    }

    private func startObservingStore() {
        guard let store else { return }
        storeObservationTask?.cancel()
        storeObservationTask = Task { [weak self] in
            for await batch in store.changes(of: StoreDomain.projectListFeed) {
                guard let self else { return }
                switch ProjectListRefresh(answering: batch) {
                case .reload: await self.reload()
                case .diffStatsOnly: await self.adoptDiffStats()
                }
            }
        }
    }

    private func adoptDiffStats() async {
        diffStatReads &+= 1
        let read = diffStatReads
        guard let store, let stats = try? await store.diffStats(), read == diffStatReads else { return }
        let moved = WorkspaceDiffStat.changes(stats, to: workspaces)
        guard !moved.isEmpty else { return }
        var updated = workspaces
        for index in updated.indices {
            moved[updated[index].id]?.apply(to: &updated[index])
        }
        workspaces = updated
        for (id, stat) in moved {
            guard let model = workspaceModels[id], stat != WorkspaceDiffStat(of: model.workspace) else { continue }
            stat.apply(to: &model.workspace)
        }
    }

    private func startObservingSessions() {
        guard let store else { return }
        sessionObservationTask?.cancel()
        sessionObservationTask = Task { [weak self] in
            await self?.refreshAgentTurns()
            await self?.refreshCrew()
            for await _ in store.changes(of: [.sessions]) {
                guard let self else { return }
                await self.refreshAgentTurns()
                await self.refreshCrew()
            }
        }
    }

    private func startObservingWorkspaceMessages() {
        guard let store else { return }
        workspaceMessageObservationTask?.cancel()
        workspaceMessageObservationTask = Task { [weak self] in
            for await _ in store.changes(of: [.workspaceMessages]) {
                guard let self else { return }
                self.workspaceMessagesRevision += 1
            }
        }
    }

    private func startObservingWorkSuggestions() {
        guard let store else { return }
        workSuggestionObservationTask?.cancel()
        workSuggestionObservationTask = Task { [weak self] in
            await self?.reloadUndecidedSuggestions()
            for await batch in store.changes(of: [.workSuggestions, .sessions]) {
                guard let self else { return }
                if batch.contains(.workSuggestions) { self.workSuggestionsRevision += 1 }
                await self.reloadUndecidedSuggestions()
            }
        }
    }

    private func reloadUndecidedSuggestions() async {
        guard let store else { return }
        let counts = (try? await store.undecidedWorkSuggestionCounts()) ?? [:]
        if counts != undecidedSuggestionCounts { undecidedSuggestionCounts = counts }
    }

    private func startObservingQuotas() {
        guard let store else { return }
        quotaObservationTask?.cancel()
        quotaObservationTask = Task { [weak self] in
            await self?.reloadQuotas()
            for await _ in store.changes(of: [.agentQuotas]) {
                guard let self else { return }
                await self.reloadQuotas()
            }
        }
    }

    private func startBackgroundRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            var lastRun: ContinuousClock.Instant?
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(DiffRefreshSchedule.tick))
                guard let self else { return }
                let activity: DiffRefreshSchedule.Activity =
                    NSApp?.isActive ?? true ? .foreground : .background
                let now = ContinuousClock.now
                guard DiffRefreshSchedule.isDue(activity: activity, lastRun: lastRun, now: now)
                else { continue }
                lastRun = now
                await self.runDiffRefreshTick(activity: activity)
            }
        }
    }

    func runDiffRefreshTick(activity: DiffRefreshSchedule.Activity) async {
        await noteMissingWorktrees(exempt: archivingWorkspaceIDs.union(restoring))
        let refreshed = await refreshDiffStats(activity: activity)
        if let selected = selection.workspaceID, refreshed.contains(selected) {
            await refreshSelectedChangedFiles(activity: activity)
        }
    }

    private func refreshSelectedChangedFiles(
        activity: DiffRefreshSchedule.Activity = .foreground
    ) async {
        guard let id = selection.workspaceID, let model = workspaceModels[id] else { return }
        guard FileManager.default.fileExists(atPath: model.workspace.path) else { return }

        await model.refreshChanges(.quiet, activity: activity)
    }

    private func noteWorktreesChanged(_ paths: Set<String>) {
        let changed = workspaces.filter { paths.contains($0.path) }.map(\.id)
        guard !changed.isEmpty else { return }
        diffInvalidations.record(Set(changed))
    }

    @discardableResult
    func refreshDiffStats(activity: DiffRefreshSchedule.Activity) async -> Set<WorkspaceID> {
        guard let manager else { return [] }

        var busy = runningWorkspaceIDs
        busy.formUnion(diffInvalidations.pending)
        let due = Set(DiffRefreshSchedule.due(
            workspaces: workspaces.map(\.id),
            busy: busy,
            selected: selection.workspaceID,
            activity: activity,
            shown: Set(profileWorkspaces.map(\.id)),
            failures: diffRefreshFailures,
            lastRefreshed: lastDiffRefresh,
            now: Date()
        ))

        let present = Set(workspaces.map(\.id))
        lastDiffRefresh = lastDiffRefresh.filter { present.contains($0.key) }
        diffRefreshFailures = diffRefreshFailures.filter { present.contains($0.key) }
        diffInvalidations.retain(present)

        let pending = workspaces.filter {
            due.contains($0.id) && FileManager.default.fileExists(atPath: $0.path)
        }

        var refreshed: Set<WorkspaceID> = []
        await withTaskGroup(of: (WorkspaceID, UInt64, Bool).self) { group in
            var next = pending.startIndex
            var running = 0
            while next < pending.endIndex || running > 0 {
                while running < DiffRefreshSchedule.width, next < pending.endIndex {
                    let workspace = pending[next]
                    let generation = diffInvalidations.generation(for: workspace.id)
                    next = pending.index(after: next)
                    running += 1
                    group.addTask(priority: DiffRefreshSchedule.priority(for: activity)) {
                        let succeeded = await Self.withTimeLimit(.seconds(5)) {
                            await manager.refreshDiffStat(workspace: workspace)
                        }
                        return (workspace.id, generation, succeeded)
                    }
                }
                guard let (id, generation, succeeded) = await group.next() else { break }
                running -= 1
                diffInvalidations.finish(id, generation: generation, succeeded: succeeded)
                if succeeded {
                    lastDiffRefresh[id] = Date()
                    diffRefreshFailures[id] = nil
                    refreshed.insert(id)
                }
                if !succeeded, !Task.isCancelled {
                    let previous = diffRefreshFailures[id] ?? DiffRefreshSchedule.Failure(count: 0, at: Date())
                    diffRefreshFailures[id] = previous.after(another: Date())
                }
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
            }
        }
        return refreshed
    }

    private nonisolated static func withTimeLimit(
        _ limit: Duration,
        _ work: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await work() }
            group.addTask { try? await Task.sleep(for: limit); return false }
            let succeeded = await group.next() ?? false
            group.cancelAll()
            return succeeded
        }
    }

    func repo(for workspace: Workspace) -> Repo? {
        repos.first { $0.id == workspace.repoID }
    }

    func archivedWorkspaces() async -> [Workspace] {
        if let cachedArchived { return cachedArchived }
        guard let store, let all = try? await store.workspaces(includeArchived: true) else {
            return []
        }
        let archived = all.filter { $0.state != .active }
        cachedArchived = archived
        return archived
    }

    func invalidateArchived() {
        cachedArchived = nil
        archivedRevision &+= 1
    }

    private(set) var archivedRevision = 0

    @ObservationIgnored private var cachedArchived: [Workspace]?

    func workspaces(in repo: Repo) -> [Workspace] {
        SidebarReorder.drawn(workspaces.filter { $0.repoID == repo.id })
    }

    var selectedWorkspace: Workspace? {
        guard let id = selection.workspaceID else { return nil }
        return workspaces.first { $0.id == id }
            ?? (archivingWorkspaceIDs.contains(id) ? workspaceModels[id]?.workspace : nil)
    }

    var isInspectorPresented: Bool {
        inspectorVisibility.isPresented(hasWorkspace: selectedWorkspace != nil)
    }

    func setInspectorVisible(_ isVisible: Bool) {
        remember(InspectorVisibility(isVisible: isVisible))
    }

    func toggleInspector() {
        remember(inspectorVisibility.toggled())
    }

    private func remember(_ visibility: InspectorVisibility) {
        inspectorVisibility = visibility
        InspectorDefaults.remember(visibility)
    }

    var selectedArchivedWorkspace: Workspace? {
        guard let id = storedSelection.archivedWorkspaceID else { return nil }
        return workspaceModels[id]?.workspace
    }

    var menuWorkspace: Workspace? {
        if let id = selection.workspaceID, isArchiving(id) { return nil }
        return selectedWorkspace ?? selectedArchivedWorkspace
    }

    @discardableResult
    func model(for workspace: Workspace) -> WorkspaceModel {
        if let existing = workspaceModels[workspace.id] {
            if existing.workspace != workspace { existing.workspace = workspace }
            return existing
        }
        let model = WorkspaceModel(workspace: workspace, app: self)
        workspaceModels[workspace.id] = model
        return model
    }

    func existingModel(for id: WorkspaceID) -> WorkspaceModel? {
        workspaceModels[id]
    }

    var selectedModel: WorkspaceModel? {
        guard let id = storedSelection.workspaceID else { return nil }
        return workspaceModels[id]
    }

    private(set) var runningWorkspaceIDs: Set<WorkspaceID> = []
    private(set) var workingAgentsByWorkspace: [WorkspaceID: Int] = [:]

    @ObservationIgnored private var storedActivity: [SessionActivity] = []

    func refreshAgentTurns() async {
        guard let store, let rows = try? await store.sessionActivity() else { return }
        storedActivity = rows
        recomputeAgentTurns()
    }

    func noteAgentTurnsChanged() {
        recomputeAgentTurns()
    }

    private func recomputeAgentTurns() {
        let terminalTurns = TerminalSessionStore.shared.agentTurns
        let live = workspaceModels.values.flatMap { $0.liveTurns }
            .filter { terminalTurns[$0.sessionID] == nil } + Array(terminalTurns.values)
        let running = AgentTurns.workspaces(.running, stored: storedActivity, live: live)
            .union(TerminalSessionStore.shared.runningWorkspaceIDs)
        let waiting = AgentTurns.workspaces(.awaitingPermission, stored: storedActivity, live: live)
        if runningWorkspaceIDs != running { runningWorkspaceIDs = running }
        if !startHold.ids.isDisjoint(with: running) { startHold.settle(running: running) }
        if waitingWorkspaceIDs != waiting { waitingWorkspaceIDs = waiting }

        let ask: WorkspaceStatus? = if let storedAsk {
            storedAsk.isAwaitingPermission ? .awaitingPermission
                : (storedAsk.isRunning ? .running : nil)
        } else {
            nil
        }
        if askStatus != ask { askStatus = ask }
        let byWorkspace = AgentTurns.agentsByWorkspace(
            stored: storedActivity, live: live, runningWorkspaces: running, waitingWorkspaces: waiting
        )
        if workingAgentsByWorkspace != byWorkspace { workingAgentsByWorkspace = byWorkspace }
    }

    private(set) var waitingWorkspaceIDs: Set<WorkspaceID> = []

    @discardableResult
    func hideFromSidebar(_ id: WorkspaceID) -> Bool {
        guard archivingWorkspaceIDs.insert(id).inserted else { return false }
        workspaces.removeAll { $0.id == id }
        return true
    }

    func restoreToSidebar(_ workspace: Workspace) {
        if !workspaces.contains(where: { $0.id == workspace.id }) { workspaces.append(workspace) }
        stopHidingFromSidebar(workspace.id)
    }

    func stopHidingFromSidebar(_ id: WorkspaceID) {
        archivingWorkspaceIDs.remove(id)
    }

    func forgetWorkspace(_ id: WorkspaceID) {
        stopHidingFromSidebar(id)
        workspaceModels[id] = nil
        archiveBookings[id] = nil
        mergeArchiveWaits.forget(id)
        storedActivity.removeAll { $0.workspaceID == id }
        crewRows[id] = nil
        BranchKeptNotices.shared.dismiss(id)
        endStart(id)
        recomputeAgentTurns()
    }

    func isAwaitingPermission(_ workspace: Workspace) -> Bool {
        waitingWorkspaceIDs.contains(workspace.id)
    }

    private(set) var subagentRows: [WorkspaceID: [SubagentRow]] = [:]

    private(set) var subagentFailures: [WorkspaceID: Int] = [:]

    @ObservationIgnored private var subagentSweeps: [WorkspaceID: Task<Void, Never>] = [:]

    func noteSubagentsChanged(workspaceID: WorkspaceID) {
        subagentSweeps.removeValue(forKey: workspaceID)?.cancel()
        guard let roster = workspaceModels[workspaceID]?.activeSubagentRoster else {
            if subagentRows[workspaceID] != nil { subagentRows[workspaceID] = nil }
            if subagentFailures[workspaceID] != nil { subagentFailures[workspaceID] = nil }
            return
        }

        if case .subagent(workspaceID, let id) = selection, roster[id] == nil {
            selection = .workspace(workspaceID)
            return
        }

        let now = Date()
        let rows = SubagentRetention.rows(roster, now: now, opened: selection.subagentID)
        let shownRows = rows.isEmpty ? nil : rows
        if subagentRows[workspaceID] != shownRows {
            subagentRows[workspaceID] = shownRows
            #if DEBUG
            ActivityTally.subagentRowWrites += 1
            #endif
        }

        let failures = SubagentRetention.failureCount(roster)
        let shownFailures = failures == 0 ? nil : failures
        if subagentFailures[workspaceID] != shownFailures { subagentFailures[workspaceID] = shownFailures }

        guard let next = SubagentRetention.nextChange(roster, now: now, opened: selection.subagentID)
        else { return }
        subagentSweeps[workspaceID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.noteSubagentsChanged(workspaceID: workspaceID)
        }
    }

    func subagents(of workspaceID: WorkspaceID) -> [SubagentRow] {
        subagentRows[workspaceID] ?? []
    }

    func subagentFailures(of workspaceID: WorkspaceID) -> Int {
        subagentFailures[workspaceID] ?? 0
    }

    private(set) var crewRows: [WorkspaceID: [CrewRow]] = [:]

    func crew(of workspaceID: WorkspaceID) -> [CrewRow] {
        crewRows[workspaceID] ?? []
    }

    func refreshCrew() async {
        guard let store else { return }
        applyCrew((try? await store.crewByWorkspace()) ?? [:])
    }

    private func applyCrew(_ grouped: [WorkspaceID: [Session]]) {
        var fresh: [WorkspaceID: [CrewRow]] = [:]
        for workspace in workspaces {
            guard let members = grouped[workspace.id], !members.isEmpty else { continue }
            fresh[workspace.id] = members.map(CrewRow.init)
        }
        if crewRows != fresh { crewRows = fresh }

        if let sessionID = selection.crewSessionID, let workspaceID = selection.workspaceID,
           !crew(of: workspaceID).contains(where: { $0.id == sessionID }) {
            selection = .workspace(workspaceID)
        }
    }

    var waitingCount: Int {
        DockBadge.waitingCount(in: workspaces) { waitingWorkspaceIDs.contains($0.id) }
    }

    var profileWaitingCount: Int {
        DockBadge.waitingCount(in: profileWorkspaces) { waitingWorkspaceIDs.contains($0.id) }
    }

    #if DEBUG
    func setRunningWorkspaceIDsForCapture(_ ids: Set<WorkspaceID>) {
        runningWorkspaceIDs = ids
    }
    #endif

    var runningCount: Int {
        runningWorkspaceIDs.count
    }

    func isRunning(_ workspace: Workspace) -> Bool {
        runningWorkspaceIDs.contains(workspace.id)
    }

    func isAgentMidTurn(_ workspace: Workspace) -> Bool {
        AgentTurns.isMidTurn { kind in
            switch kind {
            case .running: isRunning(workspace)
            case .awaitingPermission: isAwaitingPermission(workspace)
            }
        }
    }

    var runningAgentCount: Int {
        runningWorkspaceIDs.count + ((storedAsk?.isRunning ?? false) ? 1 : 0)
    }

    var runningAgentWorkspaceNames: [String] {
        let workspaceNames = runningWorkspaceIDs
            .compactMap { id in
                workspaceModels[id]?.workspace.name ?? workspaces.first { $0.id == id }?.name
            }
            .sorted()
        guard storedAsk?.isRunning == true else { return workspaceNames }
        return workspaceNames + [AskConversation.title]
    }

    var restoring: Set<WorkspaceID> = []

    var carryingOn: Set<WorkspaceID> = []

    func reorderWorkspaces(in repo: Repo, visible: [Workspace], from: IndexSet, to: Int) async {
        guard let store else { return }
        let changes = SidebarReorder.move(
            visible: visible, all: workspaces(in: repo), from: from, to: to
        )
        guard !changes.isEmpty else { return }

        let byID = Dictionary(changes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        workspaces = workspaces.map { workspace in
            guard let change = byID[workspace.id] else { return workspace }
            var moved = workspace
            moved.sortOrder = change.sortOrder
            moved.pinned = change.pinned
            return moved
        }

        try? await store.reorderWorkspaces(changes)
    }

    func reorderProjects(id: RepoID, visible: [RepoID], to: Int) async {
        guard let store else { return }
        let changes = SidebarReorder.move(projects: repos, visible: visible, id: id, to: to)
        guard !changes.isEmpty else { return }

        let byID = Dictionary(changes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        repos = repos
            .map { repo in
                guard let change = byID[repo.id] else { return repo }
                var moved = repo
                moved.sortOrder = change.sortOrder
                return moved
            }
            .sorted { $0.sortOrder < $1.sortOrder }

        try? await store.reorderProjects(changes)
    }
}
