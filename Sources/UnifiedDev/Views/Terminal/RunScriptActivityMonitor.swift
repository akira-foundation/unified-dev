import AppKit
import Darwin
import Observation
import Core

@MainActor
@Observable
final class RunScriptActivityMonitor {
    enum Probe {
        case direct(descriptor: Int32, shell: Int32)
        case tmux(session: String)
    }

    private var states: [String: RunScriptActivity.State] = [:]

    @ObservationIgnored private var activities: [String: RunScriptActivity] = [:]

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var tick = 0

    @ObservationIgnored var probes: @MainActor () -> [String: Probe] = { [:] }

    @ObservationIgnored var persistence: @MainActor () -> TerminalPersistence? = { nil }

    @ObservationIgnored var onRunning: @MainActor (String) -> Void = { _ in }

    private static let tmuxEvery = 2

    func state(inPane pane: String) -> RunScriptActivity.State {
        states[pane] ?? .idle
    }

    func typed(inPane pane: String) {
        guard probes()[pane] != nil else { return }
        update(pane) { $0.typed(at: .now) }
        ensurePolling()
    }

    func dismiss(inPane pane: String) {
        update(pane) { $0.dismiss() }
    }

    func forget(panes: [String]) {
        for pane in panes {
            activities[pane] = nil
            if states[pane] != nil { states[pane] = nil }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func ensurePolling() {
        guard pollTask == nil, !probes().isEmpty else { return }
        pollTask = Task { [weak self] in
            var lastPoll = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: TerminalActivitySchedule.tick)
                guard !Task.isCancelled, let self else { return }
                let now = ContinuousClock.now
                let activity: DiffRefreshSchedule.Activity = NSApp?.isActive ?? true ? .foreground : .background
                let interval = TerminalActivitySchedule.runScriptInterval(for: activity)
                guard TerminalActivitySchedule.isDue(lastRun: lastPoll, now: now, interval: interval) else { continue }
                lastPoll = now
                guard await self.poll() else {
                    self.pollTask = nil
                    return
                }
            }
        }
    }

    private func poll() async -> Bool {
        let probes = probes()
        guard !probes.isEmpty else { return false }
        tick += 1

        let readTmux = tick % Self.tmuxEvery == 0
        let readings = await read(probes, includingTmux: readTmux, notOlderThan: TerminalActivitySchedule.readingMaxAge)
        apply(readings) { activity, busy, moment in activity.observe(busy: busy, at: moment) }
        return true
    }

    func readNow(panes: [String]) async {
        let probes = probes().filter { panes.contains($0.key) }
        guard !probes.isEmpty else { return }
        let readings = await read(probes, includingTmux: true, notOlderThan: .zero)
        apply(readings) { activity, busy, moment in activity.adopt(busy: busy, at: moment) }
        ensurePolling()
    }

    private func read(
        _ probes: [String: Probe], includingTmux: Bool, notOlderThan maxAge: Duration
    ) async -> [String: Bool] {
        var readings: [String: Bool] = [:]
        var sessions: [String: String] = [:]

        for (pane, probe) in probes {
            switch probe {
            case .direct(let descriptor, let shell):
                readings[pane] = Self.isBusy(descriptor: descriptor, shell: shell)
            case .tmux(let session):
                if includingTmux { sessions[pane] = session }
            }
        }

        guard !sessions.isEmpty, let persistence = persistence() else { return readings }
        let pids = await persistence.panePIDs(notOlderThan: maxAge)
        guard let table = await ProcessTable.recent(notOlderThan: maxAge) else { return readings }
        for (pane, session) in sessions {
            readings[pane] = pids[session].flatMap { table.isBusy(shell: $0) } ?? false
        }
        return readings
    }

    private static func isBusy(descriptor: Int32, shell: Int32) -> Bool {
        guard descriptor >= 0, shell > 0 else { return false }
        let group = tcgetpgrp(descriptor)
        return group > 0 && group != shell
    }

    private func apply(
        _ readings: [String: Bool], _ change: (inout RunScriptActivity, Bool, Date) -> Void
    ) {
        guard !readings.isEmpty else { return }
        let live = probes()
        let moment = Date.now
        for (pane, busy) in readings where live[pane] != nil {
            update(pane) { change(&$0, busy, moment) }
        }
    }

    private func update(_ pane: String, _ change: (inout RunScriptActivity) -> Void) {
        var activity = activities[pane] ?? RunScriptActivity()
        change(&activity)
        activities[pane] = activity
        let state = activity.state
        guard (states[pane] ?? .idle) != state else { return }
        let wasRunning = states[pane]?.isRunning == true
        states[pane] = state
        if state.isRunning, !wasRunning { onRunning(pane) }
    }
}
