import SwiftUI
import Observation
import Synchronization
import Core

struct GitFailure: Error, Sendable {
    var message: String
}

@MainActor
@Observable
final class WorkspaceModel {
    var workspace: Workspace
    private unowned let app: AppModel

    var sessions: [Session] = [] {
        didSet { app.noteSubagentsChanged(workspaceID: workspace.id) }
    }
    var sideConversations: [SessionID: SideConversationState] = [:]

    private(set) var hasReadSessions = false

    var activeSessionID: SessionID? {
        get { storedActiveSessionID }
        set {
            if storedActiveSessionID != newValue {
                storedActiveSessionID = newValue
                tasksFocus.activeChatChanged()
                sideFocus.activeChatChanged()
            }
            prepareActiveTranscript()
            app.noteSubagentsChanged(workspaceID: workspace.id)
            app.notificationInbox.noteOnScreen()
        }
    }

    private var storedActiveSessionID: SessionID?

    private var transcripts: [SessionID: TranscriptModel] = [:]

    @ObservationIgnored var canvasDocuments: [String: CanvasDocumentModel] = [:]
    @ObservationIgnored var canvasCommentTurns = CanvasCommentTurns()
    @ObservationIgnored var canvasCommentsBeingSent: Set<DeliveryID> = []
    @ObservationIgnored var canvasShownBy: [String: SessionID] = [:]
    var canvasCommentTargets: [DeliveryID: SessionID] = [:]

    private var storedDiffScope: DiffScope = .all

    var diffScope: DiffScope {
        hasReadBranchCommits ? branchCommits.resolve(storedDiffScope) : storedDiffScope
    }

    private(set) var branchCommits = BranchCommitList()
    private(set) var hasReadBranchCommits = false

    private var inspectorChoice = InspectorTabChoice()

    private var sideFocus = SideConversationFocus()

    private var inspectorSideParentID: SessionID? {
        let present = Set(sideConversations.filter { $0.value.lifecycle.isPresent }.keys)
        return sideFocus.parent(active: activeSession?.id, present: present)
    }

    var inspectorSideParent: TranscriptModel? {
        inspectorSideParentID.flatMap { transcripts[$0] }
    }

    var inspectorSideConversation: SideConversationState? {
        inspectorSideParent.flatMap { sideConversations[$0.session.id] }
    }

    func isShowingSideConversation(of parent: TranscriptModel) -> Bool {
        inspectorTab == .side && inspectorSideParent === parent
    }

    var availableInspectorTabs: [InspectorTab] {
        InspectorTab.available(
            for: pullRequest, hasTasks: hasBackgroundTasks, hasSideConversation: inspectorSideConversation != nil
        )
    }

    func showSideConversation(of parent: TranscriptModel) {
        sideFocus.choose(parent.session.id, active: activeSession?.id)
        inspectorChoice.sideConversationStarted()
        app.setInspectorVisible(true)
    }

    func leaveSideConversation(of parent: TranscriptModel) {
        guard inspectorSideParentID == parent.session.id else { return }
        inspectorChoice.sideConversationLeft()
    }

    var hasBackgroundTasks: Bool {
        tasksTranscript?.hasBackgroundTasks ?? false
    }

    func clearFinishedTasks() {
        tasksTranscript?.clearFinishedTasks()
        guard !hasBackgroundTasks else { return }
        tasksFocus.activeChatChanged()
        inspectorChoice.choose(inspectorTab)
    }

    private var tasksFocus = BackgroundTasksFocus()

    func showTasks(of session: SessionID) {
        tasksFocus.choose(session, active: activeSession?.id)
    }

    var tasksTranscript: TranscriptModel? {
        tasksFocus.session(active: activeSession?.id).flatMap { transcripts[$0] } ?? activeTranscript
    }

    var inspectorTab: InspectorTab {
        get { inspectorChoice.resolved(available: availableInspectorTabs) }
        set { inspectorChoice.choose(newValue) }
    }
    var changedFiles: [ChangedFile] = [] {
        didSet { reviewFiles = ChangedFileTree.orderedFiles(from: changedFiles) }
    }
    private(set) var reviewFiles: [ChangedFile] = []
    var selectedFilePath: String?
    var isLoadingChanges = false
    private(set) var hasReadChanges = false
    private(set) var changesGeneration = 0
    @ObservationIgnored private var changesRecord = ChangesGeneration()
    @ObservationIgnored private var patches = PatchCache()
    @ObservationIgnored private var releasedHeldFiles = false
    @ObservationIgnored private var presentations = DiffPresentationCache()
    @ObservationIgnored private var panePositions: [TranscriptPaneState.Key: TranscriptPaneState] = [:]
    @ObservationIgnored private var transcriptPlaceWrite: Task<Void, Never>?
    var changesError: String?
    var pullRequest: PullRequest? {
        get { WorkspacePullRequests.shared.pullRequest(for: workspace.id) }
        set { WorkspacePullRequests.shared.set(newValue, for: workspace.id) }
    }

    var pullRequestRefreshFailure: GitHubReadFailure? {
        WorkspacePullRequests.shared.failure(for: workspace.id)
    }

    var isLoadingPullRequest = false
    private(set) var hasReadPullRequest = false
    private(set) var checkRuns: CheckRunsRead?

    private(set) var mergeMethod = MergeMethodChoice.fallback
    var pullRequestNotice: PullRequestNotice?
    var continued: ContinuedBranch?
    var isExpectingPullRequest = false
    var localWork: LocalWork?
    var hasRemote: Bool?

    private(set) var setupOutput: String = ""
    var isRunningSetup = false
    var events: [WorkspaceEvent] = []

    func record(_ event: WorkspaceEvent) {
        events.append(event)
    }

    func timeline(isRunningSetup running: Bool) -> [WorkspaceEvent] {
        let key = TimelineKey(
            isRunning: running,
            setupState: workspace.setupState,
            logBytes: setupOutput.utf8.count,
            logWrites: setupLogWrites,
            durationMS: setupDurationMS,
            exitStatus: setupExitStatus,
            recorded: events
        )
        if let timelineMemo, timelineMemo.key == key { return timelineMemo.events }

        let setup = WorkspaceEvent.setup(
            state: running ? .running : workspace.setupState,
            log: setupOutput,
            durationMS: setupDurationMS,
            status: setupExitStatus
        )
        let built = [setup].compactMap { $0 } + events
        timelineMemo = (key, built)
        return built
    }

    private struct TimelineKey: Equatable {
        var isRunning: Bool
        var setupState: SetupState
        var logBytes: Int
        var logWrites: Int
        var durationMS: Int?
        var exitStatus: Int?
        var recorded: [WorkspaceEvent]
    }

    @ObservationIgnored private var timelineMemo: (key: TimelineKey, events: [WorkspaceEvent])?

    @ObservationIgnored private var setupLogWrites = 0

    var setupStartedAt: Date?
    var setupDurationMS: Int?

    var setupExitStatus: Int?

    var port: Int { workspace.port }
    @ObservationIgnored private var portTask: Task<Int, Never>?

    private var arrivalTask: Task<Void, Never>?

    private var changesTask: Task<Result<ChangesAnswer, GitFailure>, Never>?
    private var pullRequestTask: Task<PullRequestReading, Never>?
    @ObservationIgnored private var settingsRefresh = RefreshDemand()
    @ObservationIgnored private var settingsTask: Task<Void, Never>?
    private var setupTask: Task<Void, Never>?
    var pendingCLILaunches: Set<SessionID> = []
    private(set) var pendingCLIPrompts: [SessionID: String] = [:]
    @ObservationIgnored private var setupRunTask: Task<Bool, Never>?
    @ObservationIgnored private var setupWasStopped = false

    init(workspace: Workspace, app: AppModel) {
        self.workspace = workspace
        self.app = app
        self.setupOutput = workspace.setupLog
        refreshSettings()
    }

    private(set) var settings = RepoSettings()

    func refreshSettings() {
        releasedHeldFiles = false
        guard settingsRefresh.request() else { return }
        settingsTask = Task { [weak self] in await self?.drainSettingsRefreshes() }
    }

    func reloadSettings() async {
        refreshSettings()
        await settingsTask?.value
    }

    private func drainSettingsRefreshes() async {
        repeat {
            if let path = repo?.path {
                let loaded = await Task.detached(priority: .utility) {
                    SettingsLoader.load(repo: path)
                }.value
                if settings != loaded { settings = loaded }
                app.recordSetupScript(loaded.setupScript != nil, forRepoID: workspace.repoID)
            }
        } while settingsRefresh.complete()
        settingsTask = nil
    }

    var store: Store? { app.store }
    var repo: Repo? { app.repo(for: workspace) }

    var activeSession: Session? {
        guard let activeSessionID else { return sessions.first { $0.sideConversationParentID == nil } }
        return sessions.first { $0.id == activeSessionID } ?? sessions.first { $0.sideConversationParentID == nil }
    }

    func reloadSessions() async {
        CenterTabStore.shared.load(workspaceID: workspace.id)
        guard let store else { return }
        SwitchTrace.mark("sessions.query.start", workspace: workspace.id)
        guard let fresh = try? await store.sessions(workspaceID: workspace.id) else { return }
        SwitchTrace.mark("sessions.query.done", workspace: workspace.id)
        if sessions != fresh { sessions = fresh }
        let isFirstRead = !hasReadSessions
        if isFirstRead { hasReadSessions = true }
        let tabs = CenterTabStore.shared
        WorkspaceTabsStore.shared.updateOrder(
            sessions: TabSet.tabbable(fresh),
            tools: tabs.hasReadTabs(for: workspace.id) ? tabs.stripToolIDs(for: workspace.id) : nil,
            workspaceID: workspace.id
        )
        SwitchTrace.mark("sessions.assigned", workspace: workspace.id)
        if activeSessionID == nil || !sessions.contains(where: { $0.id == activeSessionID }) {
            activeSessionID = sessions.first { $0.sideConversationParentID == nil }?.id
        } else {
            prepareActiveTranscript()
        }
        SwitchTrace.mark("sessions.prepared", workspace: workspace.id)
        if isFirstRead { Task { await wakeQueuedCanvasComments() } }
        Task { await sendOpenCanvasCommentsAwaitingChat() }
    }

    @discardableResult
    func createSession(
        title: String? = nil,
        controls: ComposerControls? = nil,
        draft: String = "",
        seededFrom source: SessionID? = nil,
        through seq: Int? = nil
    ) async -> Session? {
        guard !app.isArchiving(workspace.id), let store else { return nil }
        let openingControls: ComposerControls
        if let controls {
            openingControls = controls
        } else {
            guard let resolved = try? await app.resolvedControls(for: repo) else { return nil }
            openingControls = resolved
        }
        guard !app.isArchiving(workspace.id) else { return nil }
        var session = Session(
            workspaceID: workspace.id,
            title: title ?? PaneNaming.nextTitle(base: PaneNaming.chat, taken: sessions.map(\.title)),
            sortOrder: sessions.count
        )
        session.model = openingControls.model
        session.effort = openingControls.effort
        session.agentKind = openingControls.agentKind
        session.permissionMode = openingControls.permissionMode
        session.interactionMode = openingControls.interactionMode
        guard let stored = try? await store.upsert(session) else { return nil }
        await openingControls.store(sessionID: stored.id, in: store)
        if !draft.isEmpty { try? await store.saveDraft(sessionID: stored.id, body: draft) }
        if let source {
            do {
                try await store.seed(sessionID: stored.id, from: source, through: seq)
            } catch {
                try? await store.deleteSession(id: stored.id)
                return nil
            }
        }
        await reloadSessions()
        activeSessionID = stored.id
        return stored
    }

    func fork(_ transcript: TranscriptModel, through seq: Int) {
        let source = transcript.session
        Task { @MainActor in
            guard let store, let controls = try? await ComposerControls.carried(from: source, in: store),
                  let made = await createSession(
                      title: MessageMenu.forkTitle(of: source.title), controls: controls,
                      seededFrom: source.id, through: seq
                  ) else {
                app.notice = Notice(message: "Could not fork the conversation from that message.", tone: .error)
                return
            }
            WorkspaceTabsStore.shared.reveal(.chat(made.id), in: self)
        }
    }

    func createChat(title: String? = nil) async -> PaneContent? {
        guard let store, let repo = app.repo(for: workspace) else { return nil }
        let defaults = await AppDefaults.loadForNewSessions(from: store)
        let controls = ComposerControls.resolved(
            repo: SettingsLoader.load(repo: workspace.path),
            app: defaults,
            models: ComposerModelCatalog.shared.models
        )
        guard let session = await createSession(title: title, controls: controls) else { return nil }
        guard WorkspaceStartMode.chat(usesCLI: defaults.terminalChat, agent: controls.agentKind).cliAgentKind != nil
        else { return .chat(session.id) }
        CenterTabStore.shared.add(
            kind: .terminal, workspaceID: workspace.id,
            title: title ?? session.agentKind.label, agentSessionID: session.id
        )
        pendingCLILaunches.insert(session.id)
        await launchCLI(session, prompt: "", repo: repo)
        return .chat(session.id)
    }

    func clearConversation(_ previous: Session, controls: ComposerControls) async -> Session? {
        guard !app.isArchiving(workspace.id), let store else { return nil }
        do {
            let next = try await store.replaceWorkspaceConversation(id: previous.id, controls: controls)
            transcripts.removeValue(forKey: previous.id)?.teardown()
            forgetSideConversation(of: previous.id)
            app.bridge?.retire(sessionID: previous.id)
            WorkspaceTabsStore.shared.replaceConversation(previous.id, with: next.id, in: self)
            if let index = sessions.firstIndex(where: { $0.id == previous.id }) { sessions[index] = next }
            activeSessionID = next.id
            return next
        } catch {
            app.notice = Notice(message: "Could not clear the conversation: \(error.readableMessage)", tone: .error)
            return nil
        }
    }

    func reorderSessions(to ids: [SessionID]) {
        guard let store else { return }
        let byID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var ordered = ids.compactMap { byID[$0] }
        guard ordered.count == sessions.count else { return }

        for (order, item) in ordered.enumerated() { ordered[order] = item.with { $0.sortOrder = order } }
        sessions = ordered
        Task { try? await store.reorderSessions(ids: ordered.map(\.id)) }
    }

    var hasRunningBackgroundTasks: Bool {
        transcripts.values.contains { $0.subagents.isAnythingRunning }
    }

    func isRunning(_ session: Session) -> Bool {
        AgentTurns.session(.running, state: session.state, live: liveTurn(for: session.id))
            || transcripts[session.id]?.subagents.isWorking == true
    }

    func replaceSession(_ session: Session, controls: ComposerControls) async -> Session? {
        guard !app.isArchiving(workspace.id), let store else { return nil }
        guard !HistoryWorkspaceGate.shared.holds(workspace.id) else {
            app.notice = Notice(message: "Resolve the workspace's interrupted rewind before replacing a conversation.", tone: .warning)
            return nil
        }
        do {
            let next = try await store.replaceWorkspaceConversation(id: session.id, controls: controls)
            transcripts.removeValue(forKey: session.id)?.teardown()
            forgetSideConversation(of: session.id)
            app.bridge?.retire(sessionID: session.id)
            await reloadSessions()
            activeSessionID = next.id
            await settleOpenCanvasComments()
            return next
        } catch {
            app.alert = AppAlert(title: "Could not start a fresh chat", message: error.readableMessage)
            return nil
        }
    }

    func forgetSideConversation(of parentID: SessionID) {
        let wasShown = inspectorSideParentID == parentID || activeSessionID == parentID
        guard let state = sideConversations.removeValue(forKey: parentID) else { return }
        state.task?.cancel()
        if wasShown { inspectorChoice.sideConversationLeft() }
    }

    func endSideConversation(_ id: SessionID) -> Task<Void, Never>? {
        guard let store else { return nil }
        return Task {
            do {
                let closed = try await store.closeSideConversation(sessionID: id)
                let livesOnAsChat = try await store.session(id: id).map { $0.archivedAt == nil } ?? false
                if closed || !livesOnAsChat {
                    transcripts.removeValue(forKey: id)?.teardown()
                    app.bridge?.retire(sessionID: id)
                }
            } catch {
                app.notice = Notice(
                    message: "Could not close the side conversation: \(error.readableMessage)", tone: .error
                )
            }
            await reloadSessions()
        }
    }

    func closeSession(_ session: Session) async {
        guard let store else { return }
        guard !HistoryWorkspaceGate.shared.holds(workspace.id) else {
            app.notice = Notice(message: "Resolve the workspace's interrupted rewind before closing a conversation.", tone: .warning)
            return
        }
        do {
            _ = try await store.update(sessionID: session.id) { $0.archivedAt = Date() }
        } catch {
            app.notice = Notice(message: "Could not close the conversation: \(error.readableMessage)", tone: .error)
            return
        }
        WorkspaceTabsStore.shared.prepareToClose(.chat(session.id), in: self)
        sessions.removeAll { $0.id == session.id }
        if let terminal = CenterTabStore.shared.terminal(for: session.id, in: workspace.id) {
            await CenterTabStore.shared.close(terminal, in: self)
            pendingCLILaunches.remove(session.id)
            pendingCLIPrompts[session.id] = nil
        }
        transcripts[session.id]?.teardown()
        transcripts[session.id] = nil
        forgetSideConversation(of: session.id)
        app.bridge?.retire(sessionID: session.id)
        await reloadSessions()
        await settleOpenCanvasComments()
    }

    var chatBesideCanvas: SessionID? {
        guard let canvas = CenterTabStore.shared.canvas(for: workspace.id) else { return nil }
        let tabs = app.paneSplitSnapshots(of: WorkspaceTabsStore.shared.entries(in: self))
        return CanvasCommentRouting.chatBeside(.tool(canvas.id), in: tabs)
    }

    func noteCanvasComment(_ sentence: String) {
        app.notice = Notice(message: sentence)
    }

    func canvasCommentPlace(of canvas: CanvasDocumentModel) -> CanvasCommentPlace {
        CanvasCommentPlace(
            addedThisRun: canvas.commentsAddedThisRun,
            archiving: app.isArchiving(workspace.id),
            documentHeld: canvas.keeper.holdsCanvasComments
        )
    }

    @discardableResult
    func transcript(for session: Session) -> TranscriptModel {
        if let existing = transcripts[session.id] {
            if existing.session != session { existing.session = session }
            return existing
        }
        let model = TranscriptModel(session: session, workspace: workspace, app: app)
        transcripts[session.id] = model
        Task { await model.load() }
        return model
    }

    var activeTranscript: TranscriptModel? {
        activeSession.flatMap { transcripts[$0.id] }
    }

    func existingTranscript(for sessionID: SessionID) -> TranscriptModel? {
        transcripts[sessionID]
    }

    var openTranscripts: [TranscriptModel] {
        Array(transcripts.values)
    }

    func releaseHeldFiles() {
        guard !releasedHeldFiles else { return }
        releasedHeldFiles = true
        patches = PatchCache()
        presentations = DiffPresentationCache()
        let path = workspace.path
        Task { await FileIndex.shared.invalidate(workspacePath: path) }
    }

    func prepareTranscript(for sessionID: SessionID) {
        guard CenterTabStore.shared.terminal(for: sessionID, in: workspace.id) == nil,
              let session = sessions.first(where: { $0.id == sessionID }) else { return }
        transcript(for: session)
    }

    private func prepareActiveTranscript() {
        guard let session = activeSession else { return }
        prepareTranscript(for: session.id)
    }

    func startCrewMember(
        _ order: CrewOrder, reportingTo parentID: SessionID
    ) async -> CrewStartOutcome {
        guard let store else { return .refused(Self.crewWithoutStore) }
        guard let parent = try? await store.session(id: parentID) else {
            return .refused("The chat that asked for this subagent is not in Unified Dev any more.")
        }
        guard parent.parentSessionID == nil else {
            return .refused(Crew.sentence(for: .notAnOrchestrator))
        }
        guard let name = Crew.normalisedName(order.name) else {
            return .refused(Crew.sentence(for: .noName))
        }

        let member = Session(
            workspaceID: workspace.id,
            parentSessionID: parentID,
            title: name,
            model: order.model ?? parent.model,
            effort: order.effort ?? parent.effort,
            agentKind: parent.agentKind,
            permissionMode: parent.permissionMode,
            sortOrder: sessions.count
        )
        guard let stored = try? await store.upsert(member) else {
            return .refused("Unified Dev could not open a chat for that subagent.")
        }

        _ = try? await store.enqueueDelivery(
            Delivery(
                targetSessionID: stored.id,
                sourceWorkspaceID: workspace.id,
                kind: .message,
                crew: CrewMessage.brief(from: parent.title, task: order.task)
            )
        )

        await reloadSessions()

        let transcript = transcript(for: stored)
        await transcript.refreshQueue()
        await transcript.drain()

        return .started(
            "Started subagent \"\(name)\" in this workspace. Talk to it with agent_say, and Unified Dev "
                + "will tell you here when it stops, with the last thing it said."
        )
    }

    func sayToCrew(
        _ text: String, to name: String?, from callerID: SessionID
    ) async -> CrewSayOutcome {
        guard let store else { return .refused(Self.crewWithoutStore) }
        guard let caller = try? await store.session(id: callerID) else {
            return .refused("The chat that said that is not in Unified Dev any more.")
        }

        let target: Session
        let message: CrewMessage
        if let name {
            let crew = (try? await store.crew(of: callerID)) ?? []
            switch CrewLookup.find(name, among: crew) {
            case .found(let member): target = member
            case .unknown: return .refused(Self.noCrewMember(name, among: crew.map(\.title)))
            case .ambiguous: return .refused(Self.ambiguousCrewMember(name))
            }
            message = CrewMessage.said(from: caller.title, text: text, sender: .orchestrator)
        } else {
            guard let parentID = caller.parentSessionID,
                  let parent = try? await store.session(id: parentID) else {
                return .refused(
                    "No agent started this chat, so there is nobody above it to talk to. Name the "
                        + "subagent you meant to say that to."
                )
            }
            guard parent.archivedAt == nil else {
                return .refused(
                    "The chat that started you has been closed, so there is nobody above you to "
                        + "talk to any more. Finish what you can on your own and stop."
                )
            }
            target = parent
            message = CrewMessage.said(from: caller.title, text: text, sender: .subagent)
        }

        _ = try? await store.enqueueDelivery(
            Delivery(
                targetSessionID: target.id,
                sourceWorkspaceID: workspace.id,
                kind: .message,
                crew: message
            )
        )

        let transcript = transcript(for: target)
        await transcript.refreshQueue()
        await transcript.drain()

        let when = Crew.deliverySentence(to: target.agentKind)
        if name == nil {
            return .delivered("Passed that to the agent that started you. \(when)")
        }
        return .delivered(
            "Passed that to subagent \"\(target.title)\". \(when) Unified Dev will tell you here when "
                + "it stops."
        )
    }

    func chatForWorkspaceMessage(preferring preferred: SessionID?) async -> Session? {
        await reloadSessions()
        if let preferred, let chat = sessions.first(where: { $0.id == preferred }) {
            return chat
        }
        return await sessionToWriteInto(titledIfNew: "Messages")
    }

    func sessionToWriteInto(titledIfNew title: String = "Create pull request") async -> Session? {
        if let activeSession { return activeSession }
        await reloadSessions()
        if let activeSession { return activeSession }
        return await createSession(title: title)
    }

    func drainWorkspaceMessage(into chat: Session) async {
        let transcript = transcript(for: chat)
        await transcript.refreshQueue()
        await transcript.drain()
    }

    func tellWorkspaceMessageCancelled(_ message: WorkspaceMessage) async {
        guard let store, let sessionID = message.source.sessionID,
              let chat = try? await store.session(id: sessionID), chat.archivedAt == nil
        else { return }
        var acrossProfilesID: WorkspaceID?
        if let targetID = message.target.workspaceID,
           (try? await store.crossedProfileName(of: targetID, from: sessionID)) != nil {
            acrossProfilesID = targetID
        }
        _ = try? await store.enqueueDelivery(
            Delivery(
                targetSessionID: chat.id,
                sourceWorkspaceID: message.target.workspaceID,
                kind: .report,
                crew: CrewMessage.cancelled(
                    to: message.target.workspace, text: message.text, acrossProfilesID: acrossProfilesID
                )
            )
        )
        let transcript = transcript(for: chat)
        await transcript.refreshQueue()
        await transcript.drain()
    }

    func stopCrewMember(named name: String, startedBy callerID: SessionID) async -> CrewStopOutcome {
        guard let store else { return .refused(Self.crewWithoutStore) }
        let crew = (try? await store.crew(of: callerID)) ?? []
        let member: Session
        switch CrewLookup.find(name, among: crew) {
        case .found(let found): member = found
        case .unknown: return .refused(Self.noCrewMember(name, among: crew.map(\.title)))
        case .ambiguous: return .refused(Self.ambiguousCrewMember(name))
        }

        await closeSession(member)

        return .stopped(
            "Stopped subagent \"\(member.title)\" and closed its chat. Its conversation is still "
                + "here to read, and the name is free to use again."
        )
    }

    func closeCrewMember(_ member: Session) async {
        guard let store else { return }

        if let parentID = member.parentSessionID,
           let parent = try? await store.session(id: parentID), parent.archivedAt == nil {
            _ = try? await store.enqueueDelivery(
                Delivery(
                    targetSessionID: parent.id,
                    sourceWorkspaceID: workspace.id,
                    kind: .report,
                    crew: CrewMessage.stoppedByOwner(name: member.title)
                )
            )

            let transcript = transcript(for: parent)
            await transcript.refreshQueue()
            await transcript.drain()
        }

        await closeSession(member)
    }

    private static let crewWithoutStore =
        "Unified Dev's database is not open, so it cannot run a subagent right now."

    private static func ambiguousCrewMember(_ name: String) -> String {
        "Two of your subagents are called \"\(name)\", differing only in case, so Unified Dev will not "
            + "guess which you meant. Stop one of them, or say it again with the exact name "
            + "agent_list prints."
    }

    private static func noCrewMember(_ name: String, among known: [String]) -> String {
        guard !known.isEmpty else {
            return "You have no subagents, so there is no \"\(name)\" here. Start one with "
                + "agent_start."
        }
        let list = known.map { "\"\($0)\"" }.joined(separator: ", ")
        return "You have no subagent called \"\(name)\". Yours are: \(list)."
    }

    var isRunning: Bool {
        TerminalSessionStore.shared.runningWorkspaceIDs.contains(workspace.id)
            || AgentTurns.workspace(.running, sessions: sessions, live: liveTurns)
    }

    var liveTurns: [AgentTurns.Live] {
        let ids = Set(transcripts.keys).union(sessions.map(\.id))
        return ids.compactMap(liveTurn(for:))
    }

    private func liveTurn(for sessionID: SessionID) -> AgentTurns.Live? {
        if let terminal = TerminalSessionStore.shared.agentTurns[sessionID] { return terminal }
        guard let transcript = transcripts[sessionID] else { return nil }
        return AgentTurns.Live(
            sessionID: sessionID,
            workspaceID: workspace.id,
            isRunning: transcript.isRunning || transcript.subagents.isWorking,
            isAwaitingPermission: transcript.isAwaitingPermission
        )
    }

    var runningCommands: [Subagent] {
        transcripts.values
            .flatMap(\.subagents.runningCommands)
            .sorted { $0.startedAt < $1.startedAt }
    }

    var activeSubagentRoster: SubagentRoster? {
        activeTranscript?.subagents
    }

    func subagentStreamLines(forToolUseID toolUseID: String, in source: TranscriptModel? = nil) -> [Data] {
        guard !toolUseID.isEmpty, let transcript = source ?? activeTranscript else { return [] }
        return SubagentTranscript.streamLines(
            transcript.rows.filter { $0.parentToolUseID == toolUseID }.map { ($0.payload, $0.resultPayload) }
        )
    }

    func commandLine(forToolUseID toolUseID: String, in source: TranscriptModel? = nil) -> String? {
        guard !toolUseID.isEmpty, let transcript = source ?? activeTranscript else { return nil }
        guard let row = transcript.rows.last(where: { $0.refID == toolUseID }) else { return nil }
        return SubagentPane.commandLine(inPayload: row.payload)
    }

    func recordedSubagent(forToolUseID toolUseID: String, in source: TranscriptModel? = nil) -> Subagent? {
        guard !toolUseID.isEmpty, let transcript = source ?? activeTranscript,
              let row = transcript.rows.last(where: { $0.kind == .toolUse && $0.refID == toolUseID })
        else { return nil }
        var input: JSONValue?
        if case .toolUse(let use)? = TranscriptEventCache.event(rowID: row.id, payload: row.payload) {
            input = use.input
        }
        return SubagentRunLink.recordedSubagent(
            toolUseID: toolUseID,
            input: input,
            startedAt: row.createdAt,
            isSettled: row.resultPayload != nil,
            failed: row.isError || row.refusal != nil,
            durationMS: row.durationMS
        )
    }

    var isAwaitingPermission: Bool {
        AgentTurns.workspace(.awaitingPermission, sessions: sessions, live: liveTurns)
    }

    var isAgentMidTurn: Bool {
        AgentTurns.isMidTurn { kind in
            switch kind {
            case .running: isRunning
            case .awaitingPermission: isAwaitingPermission
            }
        }
    }

    var revertBlocker: String? {
        FileBarControls.revertBlocker(isAgentMidTurn: isAgentMidTurn)
    }

    func stopEverything() {
        for state in sideConversations.values { state.task?.cancel() }
        for transcript in transcripts.values { transcript.terminateNow() }
        setupTask?.cancel()
        setupTask = nil
        arrivalTask?.cancel()
        arrivalTask = nil
        fileTreeTask?.cancel()
        fileTreeTask = nil
        changesTask?.cancel()
        changesTask = nil
        pullRequestTask?.cancel()
        pullRequestTask = nil
        isLoadingChanges = false
        isLoadingPullRequest = false
        isRunningSetup = false
    }

    func teardown() {
        stopEverything()
        for transcript in transcripts.values { transcript.teardown() }
        transcripts.removeAll()
        sideConversations.removeAll()
    }

    func shutdown() async {
        for state in sideConversations.values { state.task?.cancel() }
        setupTask?.cancel()
        setupTask = nil
        changesTask?.cancel()
        changesTask = nil
        pullRequestTask?.cancel()
        pullRequestTask = nil
        for transcript in transcripts.values {
            await transcript.shutdown()
        }
    }

    func startSetupThenSend(prompt: String?, repo: Repo) async {
        let cliSession = activeSession.flatMap { session in
            CenterTabStore.shared.terminal(for: session.id, in: workspace.id).map { _ in session }
        }
        if let cliSession { pendingCLIPrompts[cliSession.id] = prompt }
        let cliDelivery: Delivery?
        if let cliSession, let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cliDelivery = try? await store?.enqueueDelivery(Delivery(targetSessionID: cliSession.id, body: prompt))
            if let terminal = CenterTabStore.shared.terminal(for: cliSession.id, in: workspace.id),
               let command = await prepareCLICommand(for: cliSession, prompt: prompt) {
                try? await store?.setSetting(TerminalCommandMemory.key(paneID: terminal.id), command)
            }
        } else {
            cliDelivery = nil
        }
        if cliSession == nil { await enqueueOpening(prompt) }

        setupTask?.cancel()
        setupGeneration += 1
        let generation = setupGeneration
        let workspaceID = workspace.id
        setupTask = Task { [weak self, weak app = self.app] in
            await self?.runSetupThenSend(repo: repo, cliSession: cliSession, cliPrompt: prompt)
            if let self {
                self.releaseStartHold(afterCLILaunch: cliSession != nil)
            } else {
                app?.endStart(workspaceID)
            }
            if let cliDelivery, let self, !Task.isCancelled,
               !self.pendingCLILaunches.contains(cliDelivery.targetSessionID),
               CenterTabStore.shared.terminal(for: cliDelivery.targetSessionID, in: self.workspace.id) != nil {
                _ = try? await self.store?.markDelivered(id: cliDelivery.id)
            }
            guard let self, self.setupGeneration == generation else { return }
            self.setupTask = nil
        }
    }

    private func releaseStartHold(afterCLILaunch: Bool) {
        let id = workspace.id
        guard let delay = WorkspaceStartHold.releaseDelay(afterCLILaunch: afterCLILaunch) else {
            app.endStart(id)
            return
        }
        Task { [weak app = self.app] in
            try? await Task.sleep(for: delay)
            app?.endStart(id)
        }
    }

    private var setupGeneration = 0

    private func enqueueOpening(_ prompt: String?) async {
        guard let prompt, let store, let session = activeSession else { return }
        let body = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        _ = try? await store.enqueueDelivery(Delivery(targetSessionID: session.id, body: body))
        await transcript(for: session).refreshQueue()
    }

    func runSetupThenSend(repo: Repo, cliSession: Session? = nil, cliPrompt: String? = nil) async {
        guard let manager = app.manager else { return }

        let repoPath = repo.path
        let settings = await Task.detached(priority: .userInitiated) {
            SettingsLoader.load(repo: repoPath)
        }.value

        if workspace.setupState == .pending, settings.setupScript != nil || Git.hasSubmodules(in: workspace.path) {
            let succeeded = await stream(setupIn: repo, through: manager)

            guard !Task.isCancelled else { return }

            if succeeded {
                Task { [weak self] in
                    guard let self else { return }
                    await RunScriptLauncher.shared.considerAutostart(in: self)
                }
            }

            if !succeeded, !setupWasStopped {
                app.alert = AppAlert(
                    title: "Setup failed for \(workspace.name)",
                    message: SetupFailure.instruction
                )
                NotificationService.shared.setupFailed(workspace: workspace)
            }
        }

        await reloadSessions()
        guard !Task.isCancelled else { return }
        if let cliSession {
            await launchCLI(cliSession, prompt: cliPrompt ?? "", repo: repo)
            await wakeQueuedCanvasComments()
            return
        }
        if let session = activeSession, CenterTabStore.shared.terminal(for: session.id, in: workspace.id) == nil {
            await transcript(for: session).drain()
        }
        await wakeQueuedCanvasComments()
    }

    private func launchCLI(_ cliSession: Session, prompt: String, repo: Repo) async {
        let port = await ensurePort()
        guard !Task.isCancelled,
              let terminal = CenterTabStore.shared.terminal(for: cliSession.id, in: workspace.id),
              sessions.contains(where: { $0.id == cliSession.id }),
              let command = await prepareCLICommand(for: cliSession, prompt: prompt) else { return }
        try? FileManager.default.removeItem(at: AgentKind.interactiveStatusURL(sessionID: cliSession.id))
        let terminals = TerminalSessionStore.shared
        terminals.useStore(store)
        terminals.run(command, inPaneID: terminal.id)
        _ = terminals.terminal(
            for: TerminalTab(id: TerminalTabID(terminal.id), workspaceID: workspace.id, title: terminal.title),
            workspace: workspace, repo: repo, port: port, directory: terminal.directory
        )
        pendingCLILaunches.remove(cliSession.id)
        pendingCLIPrompts[cliSession.id] = nil
    }

    private func prepareCLICommand(for session: Session, prompt: String) async -> String? {
        do {
            let account = try await app.account(
                for: session.agentKind, in: AccountScope(workspaceID: workspace.id, repoID: workspace.repoID)
            )
            let orchestrates = await app.store?.orchestratesAtLaunch(workspaceID: workspace.id) ?? workspace.isOrchestrator
            let chrome = await ClaudeChrome.launches(in: app.store, orchestrates: orchestrates)
            return try session.agentKind.prepareInteractiveCommand(
                directory: workspace.path, prompt: prompt, sessionID: session.id,
                model: session.model, effort: session.effort, permissionMode: session.permissionMode,
                account: account,
                orchestrates: orchestrates,
                chrome: chrome
            )
        } catch {
            if let refusal = error as? AgentAccountRefusal, let store = app.store,
               let pane = CenterTabStore.shared.terminal(for: session.id, in: workspace.id)?.id {
                await TerminalSessionStore.shared.recall.forgetRefusedResume(
                    .refused(refusal), inPane: pane, of: session.id, store: store
                )
            }
            app.alert = AppAlert(title: "Could not launch the agent", message: error.readableMessage)
            return nil
        }
    }

    func browserAddress(readingWhatTheScriptsWrote: Bool = true) async -> String {
        let port = await ensurePort()
        guard let repo, let store = app.store else {
            return WorkspaceBrowserURL.resolve(
                written: nil, stated: nil, environment: [:], port: port
            )
        }

        let environment = WorkspaceManager(store: store).environment(
            for: workspace, repo: repo, port: port
        )
        let worktree = workspace.path
        let repoPath = repo.path
        return await Task.detached(priority: .userInitiated) {
            let settings = SettingsLoader.load(repo: repoPath)
            guard readingWhatTheScriptsWrote else {
                return WorkspaceBrowserURL.declared(
                    settings: settings, environment: environment, port: port
                )
            }
            return WorkspaceBrowserURL.read(
                worktree: worktree,
                settings: settings,
                environment: environment,
                port: port
            )
        }.value
    }

    @discardableResult
    func ensurePort() async -> Int {
        if port != 0 { return port }
        if let inFlight = portTask { return await inFlight.value }
        guard let manager = app.manager else { return 0 }
        let workspace = workspace
        let task = Task { await manager.ensurePort(for: workspace) }
        portTask = task
        let allocated = await task.value
        portTask = nil
        if self.workspace.port == 0 { self.workspace.port = allocated }
        return self.workspace.port
    }

    @discardableResult
    private func stream(
        setupIn repo: Repo, through manager: WorkspaceManager, operationLease: WorkspaceOperationLease? = nil
    ) async -> Bool {
        guard !HistoryWorkspaceGate.shared.holds(workspace.id),
              let lease = operationLease ?? WorkspaceOperationLease.acquire(in: workspace.path, operation: .setup),
              lease.isValid(in: workspace.path, operation: .setup) else {
            operationLease?.release()
            if operationLease != nil { isRunningSetup = false }
            app.notice = Notice(message: "Resolve the workspace's rewind before running setup.", tone: .warning)
            return false
        }
        isRunningSetup = true
        defer { isRunningSetup = false; lease.release() }
        do {
            guard let store = app.store,
                  try await store.pendingCheckpointRewind(workspaceID: workspace.id) == nil else {
                app.notice = Notice(message: "Resolve the interrupted rewind before running setup.", tone: .warning)
                return false
            }
        } catch {
            if !Task.isCancelled {
                app.notice = Notice(
                    message: "Unified Dev could not check this workspace's rewind state. Setup did not start.",
                    tone: .error
                )
            }
            return false
        }
        setupWasStopped = false
        setupStartedAt = .now
        setupDurationMS = nil
        setupExitStatus = nil
        setupOutput = ""
        setupLogWrites += 1
        await ensurePort()

        let buffer = LineBuffer()
        let flusher = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                guard let self else { return }
                self.appendSetupOutput(buffer.drain())
            }
        }

        let workspace = workspace
        let port = port
        let run = Task { [weak self] in
            await manager.runSetup(
                workspace: workspace, repo: repo, port: port, operationLease: lease,
                onExit: { [weak self] status in
                    Task { @MainActor in self?.setupExitStatus = status }
                }
            ) { line in
                buffer.append(line)
            }
        }
        setupRunTask = run
        let succeeded = await withTaskCancellationHandler {
            await run.value
        } onCancel: {
            run.cancel()
        }
        if setupRunTask == run { setupRunTask = nil }

        flusher.cancel()
        appendSetupOutput(buffer.drain())
        isRunningSetup = false
        setupDurationMS = setupStartedAt.map { Int(Date.now.timeIntervalSince($0) * 1000) }
        await refreshSetupState()
        return succeeded
    }

    var setupRunLive: SetupRunOffer.Live {
        SetupRunOffer.Live(
            hasSetupScript: repo != nil && SetupScriptPresence.hasSetup(
                script: settings.setupScript != nil, submodules: Git.hasSubmodules(in: workspace.path)
            ),
            hasRunSetup: hasRunSetup,
            isRunning: isRunningSetup
        )
    }

    var setupRunOffer: SetupRunOffer? {
        SetupRunOffer.offer(setupRunLive)
    }

    var canRunSetup: Bool {
        setupRunOffer?.isEnabled == true
    }

    var hasRunSetup: Bool {
        SetupRunOffer.hasRunSetup(setupState: workspace.setupState, log: setupOutput)
    }

    func runSetupAgain() {
        guard !app.isArchiving(workspace.id), !HistoryWorkspaceGate.shared.holds(workspace.id),
              canRunSetup, let repo, let manager = app.manager,
              let lease = WorkspaceOperationLease.acquire(in: workspace.path, operation: .setup) else { return }
        isRunningSetup = true
        setupTask?.cancel()
        setupGeneration += 1
        let generation = setupGeneration
        setupTask = Task { [weak self] in
            guard let self else { lease.release(); return }
            await self.stream(setupIn: repo, through: manager, operationLease: lease)
            guard self.setupGeneration == generation else { return }
            self.setupTask = nil
            await self.wakeQueuedCanvasComments()
        }
    }

    func stopSetup() {
        guard isRunningSetup, let run = setupRunTask else { return }
        setupWasStopped = true
        run.cancel()
    }

    func refreshSetupState() async {
        guard let store, let fresh = try? await store.workspace(id: workspace.id) else { return }
        workspace = fresh
    }

    func appendSetupOutput(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        setupOutput += lines.joined(separator: "\n") + "\n"
        setupLogWrites += 1
        if setupOutput.count > Workspace.setupLogLimit {
            setupOutput = String(setupOutput.suffix(Workspace.setupLogLimit))
        }
    }

    enum ChangesRefresh {
        case requested
        case quiet
    }

    func refreshChanges(
        _ reason: ChangesRefresh = .requested,
        activity: DiffRefreshSchedule.Activity = .foreground
    ) async {
        if reason == .quiet, changesTask != nil { return }

        changesTask?.cancel()
        let path = workspace.path
        let base = workspace.baseBranch
        let name = workspace.name
        let scope = diffScope
        let wantsCommits = reason == .requested
        let manager = app.manager
        let observedWorkspace = workspace

        let task = Task.detached(
            priority: DiffRefreshSchedule.priority(for: activity)
        ) { () -> Result<ChangesAnswer, GitFailure> in
            if wantsCommits { await manager?.refreshBranch(workspace: observedWorkspace) }
            do {
                async let filesRead = Git.changedFiles(worktree: path, base: base, scope: scope)
                async let localRead = try? Git.localWork(worktree: path)
                async let commitsRead: BranchCommitList? = wantsCommits
                    ? try? Git.branchCommits(worktree: path, base: base)
                    : nil

                let files = try await filesRead
                let local = await localRead
                let commits = await commitsRead
                let revisions = ReviewedFileFingerprint.revisions(for: files, worktree: path, base: base, scope: scope)
                return .success(ChangesAnswer(files: files, local: local, commits: commits, revisions: revisions))
            } catch {
                let trouble = await WorkspaceTrouble.readingChanges(
                    error, workspace: name, path: path, baseBranch: base
                )
                return .failure(GitFailure(message: trouble.sentence))
            }
        }
        changesTask = task
        if reason == .requested, changedFiles.isEmpty { isLoadingChanges = true }
        if reason == .requested { SwitchTrace.mark("changes.git.start", workspace: workspace.id) }

        let outcome = await task.value
        if reason == .requested { SwitchTrace.mark("changes.git.done", workspace: workspace.id) }

        guard changesTask == task, !task.isCancelled else { return }
        changesTask = nil
        if isLoadingChanges { isLoadingChanges = false }
        if !hasReadChanges { hasReadChanges = true }

        switch outcome {
        case .failure(let failure):
            if changesError != failure.message { changesError = failure.message }

        case .success(let answer):
            #if DEBUG
            ActivityTally.changeReads += 1
            #endif
            let snapshot = ChangesSnapshot(files: answer.files, revisions: answer.revisions, scope: scope)
            if changesRecord.record(snapshot) {
                changesGeneration = changesRecord.value
                #if DEBUG
                ActivityTally.changeGenerations += 1
                #endif
                reconcileCanvasDocuments()
            }
            if changesError != nil { changesError = nil }
            if changedFiles != answer.files { changedFiles = answer.files }
            if viewedRevisions != answer.revisions { viewedRevisions = answer.revisions }
            if let local = answer.local, localWork != local { localWork = local }
            if let commits = answer.commits {
                if branchCommits != commits { branchCommits = commits }
                hasReadBranchCommits = true
            }
            adoptSelection(among: answer.files, reason: reason)
        }
    }

    struct ChangesAnswer: Sendable {
        var files: [ChangedFile]
        var local: LocalWork?
        var commits: BranchCommitList?
        var revisions: [String: String] = [:]
    }

    func setDiffScope(_ scope: DiffScope) {
        guard scope != storedDiffScope else { return }
        storedDiffScope = scope
        Task { await refreshChanges(.requested) }
    }

    var scopeNote: String? {
        diffScope.strandedNote(reviewComments, among: changedFiles)
    }

    private func adoptSelection(among files: [ChangedFile], reason: ChangesRefresh) {
        if let selectedFilePath, !files.contains(where: { $0.path == selectedFilePath }) {
            self.selectedFilePath = reason == .requested ? files.first?.path : nil
            return
        }
        guard selectedFilePath == nil, reason == .requested else { return }
        selectedFilePath = files.first?.path
    }

    private(set) var reviewComments: [ReviewComment] = []
    private(set) var hasReadReviewComments = false

    var reviewDrafts: [String: ReviewDraft] = [:]

    var browserReviews: [String: BrowserRegionCapture] = [:]

    var reviewEdits: Set<ReviewCommentID> = []

    let reviewText = ReviewTextHost()

    func reloadReviewComments() async {
        guard let store else { return }
        let fresh = (try? await store.reviewComments(workspaceID: workspace.id)) ?? []
        hasReadReviewComments = true
        if reviewComments != fresh { reviewComments = fresh }
    }

    func addReviewComment(
        filePath: String,
        selection: ReviewSelection,
        anchor: ReviewCommentAnchor,
        body: String
    ) async {
        guard let store else { return }
        let comment = ReviewComment(
            workspaceID: workspace.id,
            filePath: filePath,
            side: selection.side,
            anchor: anchor,
            body: body
        )
        guard let stored = try? await store.upsert(comment) else { return }
        reviewComments = (reviewComments + [stored]).sortedForReview()
    }

    func editReviewComment(id: ReviewCommentID, body: String) async {
        guard let store else { return }
        do {
            try await store.updateReviewCommentBody(id: id, body: body)
        } catch {
            report(refused: error)
            return
        }
        guard let index = reviewComments.firstIndex(where: { $0.id == id }) else { return }
        reviewComments[index].body = body
    }

    func removeReviewComment(id: ReviewCommentID) async {
        guard let store else { return }
        do {
            try await store.deleteReviewComment(id: id)
        } catch {
            report(refused: error)
            return
        }
        reviewComments.removeAll { $0.id == id }
        reviewEdits.remove(id)
        reviewText.edits[id] = nil
    }

    private func report(refused error: any Error) {
        app.alert = AppAlert(
            title: "That comment was not saved",
            message: WorkspaceTrouble.reviewCommentUnwritable(
                complaint: WorkspaceTrouble.complaint(about: error)
            ).sentence
        )
    }

    func removeReviewComments(ids: [ReviewCommentID]) async {
        guard let store, !ids.isEmpty else { return }
        var removed: [ReviewCommentID] = []
        var refusal: (any Error)?
        for id in ids {
            do {
                try await store.deleteReviewComment(id: id)
                removed.append(id)
            } catch {
                refusal = refusal ?? error
            }
        }
        let sent = Set(removed)
        reviewComments.removeAll { sent.contains($0.id) }
        for id in removed {
            reviewEdits.remove(id)
            reviewText.edits[id] = nil
        }
        if let refusal { report(refused: refusal) }
    }

    private(set) var viewedFiles: [String: String] = [:]
    private(set) var viewedRevisions: [String: String] = [:]
    private(set) var hasReadViewedFiles = false

    var viewedSummary: String? {
        ReviewedFiles.summary(among: changedFiles, marks: viewedFiles, revisions: viewedRevisions)
    }

    func isViewed(_ file: ChangedFile) -> Bool {
        ReviewedFiles.isViewed(file, marks: viewedFiles, revisions: viewedRevisions)
    }

    func reloadViewedFiles() async {
        guard let store else { return }
        let fresh = (try? await store.reviewedFiles(workspaceID: workspace.id)) ?? []
        hasReadViewedFiles = true
        let marks = Dictionary(
            fresh.map { ($0.path, $0.fingerprint) }, uniquingKeysWith: { _, latest in latest }
        )
        if viewedFiles != marks { viewedFiles = marks }
    }

    func setViewed(_ isViewed: Bool, file: ChangedFile) async {
        guard let store else { return }
        let fingerprint = ReviewedFileFingerprint.of(file, revision: viewedRevisions[file.path] ?? "")
        do {
            if isViewed {
                try await store.markReviewed(ReviewedFile(
                    workspaceID: workspace.id, path: file.path, fingerprint: fingerprint
                ))
            } else {
                try await store.clearReviewed(workspaceID: workspace.id, path: file.path)
            }
        } catch {
            app.alert = AppAlert(
                title: "That file was not marked",
                message: WorkspaceTrouble.complaint(about: error)
            )
            return
        }
        if isViewed {
            viewedFiles[file.path] = fingerprint
        } else {
            viewedFiles[file.path] = nil
        }
    }

    func clearViewedFiles() async {
        guard let store, !viewedFiles.isEmpty else { return }
        do {
            try await store.clearReviewed(workspaceID: workspace.id)
        } catch {
            app.alert = AppAlert(
                title: "Those marks were not cleared",
                message: WorkspaceTrouble.complaint(about: error)
            )
            return
        }
        viewedFiles = [:]
    }

    var reviewDestinationID: SessionID?

    var reviewDestination: Session? {
        let id = ReviewDestination.resolved(
            chosen: reviewDestinationID,
            active: activeSession?.id,
            sessions: sessions.map(\.id)
        )
        return sessions.first { $0.id == id }
    }

    private(set) var fileTree: [String: [FileTreeNode]] = [:]
    private(set) var hasReadFileTree = false
    private var fileTreeTask: Task<Void, Never>?

    func refreshFileTree(force: Bool = false) async {
        if hasReadFileTree, !force { return }
        if let fileTreeTask, !force { return await fileTreeTask.value }

        fileTreeTask?.cancel()
        let worktree = workspace.path
        let task = Task { [weak self] in
            let index = await Task.detached(priority: .userInitiated) {
                () -> [String: [FileTreeNode]] in
                let result = try? await Shell.run(
                    "git",
                    ["ls-files", "--cached", "--others", "--exclude-standard"],
                    cwd: worktree,
                    timeout: .seconds(30)
                )
                return FileTreeNode.index(result?.lines ?? [])
            }.value
            guard let self, !Task.isCancelled else { return }
            if fileTree != index { fileTree = index }
            hasReadFileTree = true
            fileTreeTask = nil
        }
        fileTreeTask = task
        await task.value
    }

    func panePosition(pane: String, session: SessionID) -> TranscriptPaneState? {
        panePositions[TranscriptPaneState.Key(pane: pane, session: session)]
    }

    func rememberPanePosition(_ state: TranscriptPaneState, pane: String, session: SessionID) {
        panePositions[TranscriptPaneState.Key(pane: pane, session: session)] = state
    }

    func writeTranscriptPlace(_ place: TranscriptPlace, session: SessionID) {
        guard let store else { return }
        let earlier = transcriptPlaceWrite
        transcriptPlaceWrite = Task {
            await earlier?.value
            try? await store.setTranscriptPlace(place, sessionID: session)
        }
    }

    func patch(for file: ChangedFile) async -> String {
        let path = workspace.path
        let base = workspace.baseBranch
        let scope = diffScope
        let key = PatchCache.Key(
            worktree: path, base: base, file: file, scope: scope, generation: changesGeneration
        )
        if let held = patches.patch(for: key) { return held }

        let patch = await Task.detached(priority: .userInitiated) {
            (try? await Git.patch(worktree: path, base: base, file: file, scope: scope)) ?? ""
        }.value

        guard !patch.isEmpty else { return patch }
        guard changesGeneration == key.generation else { return patch }
        patches.store(patch, for: key)
        return patch
    }

    func imageSides(for file: ChangedFile) async -> ImageDiffSides {
        await Git.imageSides(worktree: workspace.path, base: workspace.baseBranch, file: file, scope: diffScope)
    }

    func heldDiff(for file: ChangedFile, ignoringWhitespace: Bool) -> DiffPresentation? {
        presentations.presentation(for: presentationKey(file, ignoringWhitespace: ignoringWhitespace))
    }

    func holdDiff(
        _ presentation: DiffPresentation, for file: ChangedFile, ignoringWhitespace: Bool
    ) {
        presentations.store(
            presentation, for: presentationKey(file, ignoringWhitespace: ignoringWhitespace)
        )
    }

    func forgetHeldDiff(for path: String) {
        presentations.forget(file: path)
    }

    private func presentationKey(
        _ file: ChangedFile, ignoringWhitespace: Bool
    ) -> DiffPresentationCache.Key {
        DiffPresentationCache.Key(
            worktree: workspace.path,
            base: workspace.baseBranch,
            file: file,
            scope: diffScope,
            ignoresWhitespace: ignoringWhitespace
        )
    }

    func contents(of relativePath: String) -> String? {
        Self.contents(of: relativePath, in: workspace.path)
    }

    nonisolated static func contents(of relativePath: String, in worktree: String) -> String? {
        let full = (worktree as NSString).appendingPathComponent(relativePath)
        return try? String(contentsOfFile: full, encoding: .utf8)
    }

    static let pullRequestArrivalMaxAge = Duration.seconds(30)

    func followMergeMethod() async {
        guard let store else { return }
        let changes = store.changes(of: [.settings])
        mergeMethod = await MergeMethodChoice.load(repoID: workspace.repoID, from: store)
        for await _ in changes {
            mergeMethod = await MergeMethodChoice.load(repoID: workspace.repoID, from: store)
        }
    }

    func chooseMergeMethod(_ method: GitHub.MergeMethod) async {
        mergeMethod = method
        guard let store else { return }
        await MergeMethodChoice.save(method, repoID: workspace.repoID, to: store)
    }

    func refreshPullRequest(maxAge: Duration = .zero) async {
        pullRequestTask?.cancel()
        let asked = workspace

        let task = Task.detached(priority: .utility) {
            await GitHubBridge.readPullRequestAndChecks(for: asked, maxAge: maxAge)
        }
        pullRequestTask = task
        if PullRequestProgress.announces(
            hasAnswered: hasReadPullRequest, hasPullRequest: pullRequest != nil
        ) {
            isLoadingPullRequest = true
        }

        let reading = await task.value

        guard pullRequestTask == task, !task.isCancelled else { return }
        pullRequestTask = nil
        hasReadPullRequest = true
        if let checks = reading.checks, checks != checkRuns { checkRuns = checks }
        WorkspacePullRequests.shared.record(reading.pullRequest, for: workspace.id)
        guard case .current(let current) = reading.pullRequest else {
            isLoadingPullRequest = false
            return
        }
        let fresh = current
        await PullRequestNumber.record(fresh, for: asked, in: store)
        isLoadingPullRequest = false
        SwitchTrace.mark("pullRequest.loaded", workspace: workspace.id)
    }

    func onAppear() async {
        SwitchTrace.mark("onAppear.start", workspace: workspace.id)
        let isFirstVisit = !hasReadSessions
        if isFirstVisit { await reloadSessions() }
        SwitchTrace.mark("sessions.loaded", workspace: workspace.id)

        arrivalTask?.cancel()
        arrivalTask = Task { [weak self] in
            guard let self else { return }
            if !isFirstVisit { await reloadSessions() }
            guard !Task.isCancelled else { return }
            if !hasReadReviewComments { await reloadReviewComments() }
            guard !Task.isCancelled else { return }
            if !hasReadViewedFiles { await reloadViewedFiles() }
            guard !Task.isCancelled else { return }
            async let changes: Void = refreshChanges()
            async let read: Void = app.markRead(workspace)
            _ = await (changes, read)
            SwitchTrace.mark("changes.loaded", workspace: self.workspace.id)
            SwitchTrace.markOnScreen("changes.loaded", workspace: self.workspace.id)
            guard !Task.isCancelled else { return }
            await refreshPullRequest(maxAge: Self.pullRequestArrivalMaxAge)
        }
    }

    func onTurnFinished() async {
        await refreshChanges()
        if let manager = app.manager {
            await manager.refreshDiffStat(workspace: workspace)
        }

        guard isExpectingPullRequest else {
            Task { await refreshPullRequest() }
            return
        }
        isExpectingPullRequest = false
        await refreshPullRequest()
    }
}

final class LineBuffer: Sendable {
    private let pending = Mutex<[String]>([])

    func append(_ line: String) {
        pending.withLock { $0.append(line) }
    }

    func drain() -> [String] {
        pending.withLock { lines in
            defer { lines.removeAll(keepingCapacity: true) }
            return lines
        }
    }
}

struct ReviewDraft: Hashable {
    var selection: ReviewSelection
    var anchor: ReviewCommentAnchor

    var spot: ReviewSpot { selection.anchor }
}
