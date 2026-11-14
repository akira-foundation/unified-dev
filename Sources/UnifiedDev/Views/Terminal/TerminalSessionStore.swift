import SwiftUI
import Observation
import Core

@MainActor
@Observable
final class TerminalSessionStore {
    static let shared = TerminalSessionStore()

    private var terminals: [String: AppTerminalView] = [:]

    private var pendingCommands: [String: String] = [:]

    private var paneOwner: [String: WorkspaceID] = [:]

    private var paneSession: [String: String] = [:]

    let recall = TerminalCommandRecall()

    let activity = RunScriptActivityMonitor()

    private init() {
        activity.probes = { [weak self] in self?.runScriptProbes() ?? [:] }
        activity.persistence = { [weak self] in self?.persistence }
        activity.onRunning = { [weak self] pane in self?.recall.withdraw(inPane: pane) }
    }

    func excerpt(inPaneID paneID: String, workspaceID: WorkspaceID, label: String) -> TerminalExcerpt? {
        guard paneOwner[paneID] == workspaceID,
              let selection = terminals[paneID]?.selection, selection.active else { return nil }
        return TerminalExcerpt(
            terminalID: TerminalTabID(paneID), workspaceID: workspaceID, label: label,
            firstLine: selection.start.row + 1, lastLine: selection.end.row + 1,
            text: selection.getSelectedText()
        )
    }

    func run(_ command: String, inPaneID paneID: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingCommands[paneID] = trimmed
        recall.remember(trimmed, sentTo: paneID)
    }

    func closePane(id: String) {
        pendingCommands[id] = nil
        if let workspaceID = paneOwner.removeValue(forKey: id) {
            let persistence = self.persistence
            Task { await persistence?.kill(workspaceID: workspaceID, paneIDs: [id]) }
        }
        paneSession[id] = nil
        paneAgents[id] = nil
        Task { await refreshAgentActivity() }
        recall.forget(panes: [id], store: repoStore)
        activity.forget(panes: [id])
        closedPanes.insert(id)
        guard let view = terminals[id] else { return }
        defer { terminals[id] = nil }

        guard view.process?.running == true else { return }
        let pid = view.process?.shellPid ?? 0

        view.willStop()
        hangUp(on: view)
        view.shutdown()

        guard pid > 0 else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            killpg(pid, SIGKILL)
        }
    }

    private func hangUp(on view: AppTerminalView) {
        signal(SIGHUP, toGroupOf: view)
        signal(SIGTERM, toGroupOf: view)
    }

    private var closedPanes: Set<String> = []

    func closePanes(of ownerID: String, workspaceID: WorkspaceID? = nil) {
        for pane in TerminalSplitStore.shared.panes(of: ownerID) {
            if let workspaceID { paneOwner[pane] = workspaceID }
            closePane(id: pane)
        }
        TerminalSplitStore.shared.discard(ownerID: ownerID)
    }

    func hasShell(paneID: String) -> Bool {
        terminals[paneID] != nil
    }

    func output(paneID: String, lines limit: Int) -> (text: String, live: Bool)? {
        guard let view = terminals[paneID] else { return nil }
        let terminal = view.getTerminal()
        var lines: [String] = []

        var row = terminal.buffer.totalLinesTrimmed
        while let line = terminal.getScrollInvariantLine(row: row) {
            let text = line.translateToString(trimRight: true, skipNullCellsFollowingWide: true)
            if line.isWrapped, !lines.isEmpty {
                lines[lines.count - 1] += text
            } else {
                lines.append(text)
            }
            row += 1
        }

        while lines.last?.isEmpty == true { lines.removeLast() }
        return (lines.suffix(limit).joined(separator: "\n"), view.process?.running == true)
    }

    func write(_ text: String, submit: Bool, paneID: String) -> Bool {
        guard let view = terminals[paneID], view.process?.running == true, !view.hasExited else {
            return false
        }
        view.send(txt: text + (submit ? "\r" : ""))
        if submit {
            recall.remember(text, sentTo: paneID)
            activity.typed(inPane: paneID)
        }
        return true
    }

    func retype(_ command: String, inPane pane: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let view = terminals[pane], view.process?.running == true,
              !view.hasExited else { return false }
        recall.remember(trimmed, sentTo: pane)
        type(trimmed, into: view, pane: pane)
        return true
    }

    private func runScriptProbes() -> [String: RunScriptActivityMonitor.Probe] {
        var probes: [String: RunScriptActivityMonitor.Probe] = [:]
        for tabs in CenterTabStore.shared.tabsByWorkspace.values {
            for tab in tabs where tab.kind == .terminal && tab.runScriptID != nil {
                guard let view = terminals[tab.id], let process = view.process, process.running,
                      !view.hasExited else { continue }
                if let session = paneSession[tab.id] {
                    probes[tab.id] = .tmux(session: session)
                } else {
                    probes[tab.id] = .direct(descriptor: process.childfd, shell: process.shellPid)
                }
            }
        }
        return probes
    }

    func send(_ key: TerminalKey, paneID: String) -> Bool {
        guard let view = terminals[paneID], view.process?.running == true, !view.hasExited else {
            return false
        }
        view.send(key.bytes)
        return true
    }

    func startRemembered(_ command: String, inPane pane: String) {
        guard write(command, submit: true, paneID: pane) else { return }
        recall.accepted(command, inPane: pane)
    }

    func dismissRemembered(inPane pane: String) {
        recall.dismiss(inPane: pane, store: repoStore)
    }

    func terminal(
        for tab: TerminalTab,
        workspace: Workspace,
        repo: Repo?,
        port: Int,
        directory: String = "",
        output: String? = nil
    ) -> AppTerminalView {
        if let existing = terminals[tab.id.rawValue], existing.hasStarted { return existing }

        let view = terminals[tab.id.rawValue]
            ?? AppTerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))

        guard !closedPanes.contains(tab.id.rawValue) else {
            view.willStop()
            return view
        }

        if let output {
            if terminals[tab.id.rawValue] == nil {
                terminals[tab.id.rawValue] = view
                paneOwner[tab.id.rawValue] = workspace.id
            }
            view.showOutput(output)
            return view
        }

        var extra: [String: String] = [:]
        if let repo, let store = repoStore {
            extra = WorkspaceManager(store: store).environment(
                for: workspace, repo: repo, port: port
            )
        }

        paneOwner[tab.id.rawValue] = workspace.id
        let start = FolderTerminal.launchDirectory(requested: directory, root: workspace.path)
        let decision = persistence?.decision(workspaceID: workspace.id, paneID: tab.id.rawValue)
            ?? .inProcess
        if let command = persistence?.command, let session = decision.session {
            paneSession[tab.id.rawValue] = session
            view.start(TerminalLaunch.tmux(
                command: command, session: session, directory: start, extra: extra
            ))
        } else {
            view.start(TerminalLaunch.loginShell(directory: start, extra: extra))
        }

        terminals[tab.id.rawValue] = view
        if let command = pendingCommands.removeValue(forKey: tab.id.rawValue) {
            type(command, into: view, pane: tab.id.rawValue)
        } else {
            offerLastCommand(inPane: tab.id.rawValue, decision: decision)
        }
        activity.ensurePolling()
        return view
    }

    private func offerLastCommand(inPane pane: String, decision: TerminalStartDecision) {
        guard let store = repoStore else { return }
        let persistence = self.persistence
        let session = decision.session
        Task { [recall] in
            await recall.considerOffer(
                inPane: pane, session: session, persistence: persistence, store: store
            )
        }
    }

    private func type(_ command: String, into view: AppTerminalView, pane: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard view.process?.running == true else { return }
            view.send(txt: command + "\n")
            activity.typed(inPane: pane)
        }
    }

    private var repoStore: Store?

    private(set) var persistence: TerminalPersistence?

    private var didSweepOrphans = false

    private var recordTask: Task<Void, Never>?
    private var paneAgents: [String: AgentKind] = [:]
    private var agentProcesses: [String: Int32] = [:]
    private var lastHookDates: [SessionID: Date] = [:]
    private let activityStartedAt = Date()
    private(set) var agentTurns: [SessionID: AgentTurns.Live] = [:]
    private(set) var runningWorkspaceIDs: Set<WorkspaceID> = []
    var onAgentActivityChanged: (() -> Void)?
    var onAgentTurnFinished: ((WorkspaceID) async -> Void)?

    func agentsInTerminals(of workspaceID: WorkspaceID) async -> [AgentKind]? {
        ensurePersistence()
        guard let table = await ProcessTable.recent(notOlderThan: TerminalActivitySchedule.readingMaxAge),
              !table.rows.isEmpty else { return nil }
        var shells = livePanes().filter { paneOwner[$0.pane] == workspaceID }.map(\.shell)
        if let persistence {
            guard let snapshot = await persistence.panePIDSnapshot(
                notOlderThan: TerminalActivitySchedule.readingMaxAge
            ) else { return nil }
            let names = TmuxSessions.sessions(ofWorkspace: workspaceID, in: Array(snapshot.keys))
            shells += names.compactMap { snapshot[$0] }
        }
        return shells.compactMap { table.interactiveAgentProcess(ofShell: $0) }
            .compactMap { ProcessTable.interactiveAgent(command: $0.command) }
    }

    func detectedAgent(inPane pane: String) -> AgentKind? {
        paneAgents[pane]
    }

    func detectedAgent(inTab tab: String) -> AgentKind? {
        TerminalSplitStore.shared.panes(of: tab).compactMap { paneAgents[$0] }.first
    }

    private func refreshAgentActivity() async {
        guard let store = repoStore else { return }
        let panes = livePanes()
        let linkedTabs = CenterTabStore.shared.tabsByWorkspace.values.flatMap { $0 }
            .filter { $0.kind == .terminal && $0.agentSessionID != nil }
        guard !panes.isEmpty || !linkedTabs.isEmpty else {
            paneAgents = [:]
            if !agentTurns.isEmpty || !runningWorkspaceIDs.isEmpty {
                agentTurns = [:]
                runningWorkspaceIDs = []
                onAgentActivityChanged?()
            }
            return
        }
        let observedAt = Date()
        guard let table = await ProcessTable.recent(notOlderThan: .zero) else { return }
        var pids: [String: Int32] = [:]
        if let persistence {
            guard let snapshot = await persistence.panePIDSnapshot(notOlderThan: .zero) else { return }
            pids = snapshot
        }
        var detected: [String: AgentKind] = [:]
        var processes: [String: Int32] = [:]
        for pane in panes {
            let shell = pane.session.flatMap { pids[$0] } ?? pane.shell
            if let process = table.interactiveAgentProcess(ofShell: shell) {
                detected[pane.pane] = ProcessTable.interactiveAgent(command: process.command)
                processes[pane.pane] = process.pid
            }
        }
        var runningPanes = Set(detected.compactMap { pane, kind in
            kind.interactiveScreenIsBusy(lines: currentScreen(inPane: pane)) ? pane : nil
        })
        var turns: [SessionID: AgentTurns.Live] = [:]
        let linkedSessions = (try? await store.sessions(ids: linkedTabs.compactMap(\.agentSessionID))) ?? [:]
        for tab in linkedTabs {
            guard let sessionID = tab.agentSessionID,
                  let session = linkedSessions[sessionID],
                  session.archivedAt == nil else { continue }
            let paneIDs = TerminalSplitStore.shared.panes(of: tab.id)
            for pane in paneIDs where detected[pane] == nil {
                let name = TmuxSessions.sessionName(workspaceID: tab.workspaceID, paneID: pane)
                if let shell = pids[name], let process = table.interactiveAgentProcess(ofShell: shell) {
                    detected[pane] = ProcessTable.interactiveAgent(command: process.command)
                    processes[pane] = process.pid
                }
            }
            let isPresent = detected[tab.id] == session.agentKind
            var state: SessionState = isPresent && runningPanes.contains(tab.id) ? .running
                : (session.state == .failed ? .failed : .idle)
            var externalSession: String?
            let statusURL = AgentKind.interactiveStatusURL(sessionID: sessionID)
            let replaced = agentProcesses[tab.id] != nil && agentProcesses[tab.id] != processes[tab.id]
            if let attributes = try? statusURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
               let size = attributes.fileSize, size <= 1_048_576,
               let data = try? Data(contentsOf: statusURL) {
                let oldHook = attributes.contentModificationDate == lastHookDates[sessionID]
                let disappeared = !isPresent && (agentProcesses[tab.id] != nil
                    || session.state == .running || session.state == .waiting)
                let stale = (disappeared || (replaced && oldHook))
                    && (attributes.contentModificationDate ?? .distantFuture) <= observedAt
                if stale {
                    try? FileManager.default.removeItem(at: statusURL)
                }
                if !stale, isPresent {
                    state = AgentKind.interactiveHookState(data: data) ?? .idle
                    externalSession = AgentKind.interactiveHookSessionID(data: data)
                    if let modified = attributes.contentModificationDate,
                       lastHookDates[sessionID] != modified {
                        lastHookDates[sessionID] = modified
                        if modified >= activityStartedAt,
                           let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           event["hook_event_name"] as? String == "Stop" {
                            await onAgentTurnFinished?(tab.workspaceID)
                        }
                    }
                }
            }
            if isPresent, let externalSession,
               let workspace = try? await store.workspace(id: tab.workspaceID),
               CenterTabStore.shared.terminal(for: sessionID, in: tab.workspaceID)?.id == tab.id,
               let resolution = try? await AgentAccountResolver.resolve(
                   workspaceID: workspace.id, repoID: workspace.repoID, store: store
               ),
               case .runs(let account) = resolution.launch(for: session.agentKind),
               let resume = try? session.agentKind.prepareInteractiveCommand(
                   directory: workspace.path, prompt: "", sessionID: sessionID,
                   model: session.model, effort: session.effort,
                   permissionMode: session.permissionMode, resuming: externalSession,
                   account: account,
                   orchestrates: workspace.isOrchestrator,
                   chrome: await ClaudeChrome.launches(in: store, orchestrates: workspace.isOrchestrator)
               ) {
                await recall.rememberResume(resume, inPane: tab.id, store: store)
            }
            if isPresent { runningPanes.remove(tab.id) }
            turns[sessionID] = AgentTurns.Live(
                sessionID: sessionID, workspaceID: tab.workspaceID,
                isRunning: state == .running, isAwaitingPermission: state == .waiting
            )
            if session.state != state || (externalSession != nil && session.agentSessionID != externalSession) {
                let nextState = state
                let nextID = externalSession
                _ = try? await store.update(sessionID: sessionID) { row in
                    row.applyInteractiveState(nextState)
                    if let nextID { row.agentSessionID = nextID }
                }
            }
        }
        agentProcesses = processes
        if paneAgents != detected { paneAgents = detected }
        let running = Set(runningPanes.compactMap { paneOwner[$0] })
        if agentTurns != turns || runningWorkspaceIDs != running {
            agentTurns = turns
            runningWorkspaceIDs = running
            onAgentActivityChanged?()
        }
    }

    private func currentScreen(inPane pane: String) -> [String] {
        guard let terminal = terminals[pane]?.getTerminal() else { return [] }
        let start = terminal.buffer.totalLinesTrimmed
        var lower = start
        var upper = start + terminal.rows
        while terminal.getScrollInvariantLine(row: upper) != nil {
            lower = upper
            upper = start + (upper - start) * 2
        }
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if terminal.getScrollInvariantLine(row: middle) == nil {
                upper = middle
            } else {
                lower = middle + 1
            }
        }
        return (max(start, upper - terminal.rows)..<upper).compactMap {
            terminal.getScrollInvariantLine(row: $0)?.translateToString(
                trimRight: true, skipNullCellsFollowingWide: true
            )
        }
    }

    func useStore(_ store: Store?) {
        if repoStore == nil { repoStore = store }
        ensurePersistence()
        sweepOrphanedSessions()
        startRecordingCommands()
    }

    private func startRecordingCommands() {
        guard recordTask == nil, repoStore != nil else { return }
        recordTask = Task { [weak self] in
            var lastRefresh: ContinuousClock.Instant?
            var lastRecorded = ContinuousClock.now
            while !Task.isCancelled {
                let now = ContinuousClock.now
                let activity: DiffRefreshSchedule.Activity = NSApp?.isActive ?? true ? .foreground : .background
                let interval = TerminalActivitySchedule.interval(for: activity)
                if TerminalActivitySchedule.isDue(lastRun: lastRefresh, now: now, interval: interval) {
                    lastRefresh = now
                    await self?.refreshAgentActivity()
                }
                let recordInterval = TerminalActivitySchedule.commandRecordInterval
                if TerminalActivitySchedule.isDue(lastRun: lastRecorded, now: now, interval: recordInterval) {
                    lastRecorded = now
                    await self?.recordCommands()
                }
                try? await Task.sleep(for: TerminalActivitySchedule.tick)
            }
        }
    }

    func recordCommands() async {
        guard let store = repoStore else { return }
        await recall.record(panes: livePanes(), persistence: persistence, store: store)
    }

    func isRunningCommand(in workspaceID: WorkspaceID) async -> Bool {
        await recordCommands()
        return recall.runningCommands.contains { paneOwner[$0] == workspaceID }
    }

    private func livePanes() -> [TerminalCommandRecall.Pane] {
        terminals.compactMap { pane, view in
            guard view.process?.running == true, !view.hasExited,
                  let pid = view.process?.shellPid, pid > 0 else { return nil }
            return TerminalCommandRecall.Pane(
                pane: pane, shell: pid, session: paneSession[pane]
            )
        }
    }

    func liveSessions(store: Store?) async -> [String]? {
        if repoStore == nil { repoStore = store }
        ensurePersistence()
        guard let persistence else { return [] }
        return await persistence.sessions()
    }

    private func ensurePersistence() {
        guard persistence == nil, let path = repoStore?.path ?? (try? Store.defaultPath()) else {
            return
        }
        persistence = TerminalPersistence(databasePath: path)
    }

    private func sweepOrphanedSessions() {
        guard !didSweepOrphans, repoStore != nil, let persistence, persistence.isAvailable else {
            return
        }
        didSweepOrphans = true

        Task { [weak self] in
            await persistence.refresh()
            guard let self, let store = self.repoStore,
                  let workspaces = try? await store.workspaces() else { return }

            let census = TerminalPaneCensus.census(
                of: workspaces.map(\.id), in: UserDefaults.standard
            )
            await persistence.sweepOrphans(livePaneIDs: census.panes, doubtful: census.doubtful)
        }
    }

    func discard(workspaceID: WorkspaceID) async {
        ensurePersistence()

        let tabs = CenterTabStore.shared.terminalTabIDs(for: workspaceID)

        for tab in tabs {
            for pane in TerminalSplitStore.shared.panes(of: tab) {
                terminals[pane]?.willStop()
            }
        }

        await persistence?.killEverything(workspaceID: workspaceID)

        var views: [AppTerminalView] = []
        for tab in tabs {
            let panes = TerminalSplitStore.shared.panes(of: tab)
            for pane in panes {
                if let view = terminals[pane] { views.append(view) }
                terminals[pane] = nil
                paneOwner[pane] = nil
                paneSession[pane] = nil
            }
            recall.forget(panes: panes, store: repoStore)
            activity.forget(panes: panes)
            TerminalSplitStore.shared.discard(ownerID: tab)
        }

        await stop(views)
    }

    func shutdownAll() async {
        recordTask?.cancel()
        recordTask = nil
        activity.stop()
        await recordCommands()

        let views = Array(terminals.values)
        terminals.removeAll()
        paneOwner.removeAll()
        paneSession.removeAll()
        pendingCommands.removeAll()
        await stop(views)
    }

    private func stop(_ views: [AppTerminalView]) async {
        let live = views.filter { $0.process?.running == true }
        guard !live.isEmpty else { return }

        for view in live {
            view.willStop()
            hangUp(on: view)
            view.shutdown()
        }

        try? await Task.sleep(for: .milliseconds(250))

        for view in live { signal(SIGKILL, toGroupOf: view) }
    }

    private func signal(_ number: Int32, toGroupOf view: AppTerminalView) {
        let pid = view.process?.shellPid ?? 0
        guard pid > 0 else { return }
        killpg(pid, number)
    }
}
