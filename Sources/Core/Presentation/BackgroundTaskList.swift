import Foundation

public struct BackgroundTaskList: Sendable, Hashable {
    public struct Row: Sendable, Hashable, Identifiable {
        public let id: SubagentID
        public let kind: SubagentKind
        public let title: String
        public let mark: SubagentRow.Mark
        public let detail: String
        public let canStop: Bool

        public var openHelp: String {
            kind == .command ? "Show what this command printed" : SubagentRunLink.openHelp
        }

        init(_ subagent: Subagent, stopsTasks: Bool, now: Date) {
            id = subagent.id
            kind = subagent.kind
            title = SubagentRow.title(of: subagent)
            mark = SubagentRow(subagent).mark
            canStop = stopsTasks && subagent.state == .running
            let state = SubagentPane.status(subagent, now: now)
            let elapsed = SubagentRow.duration(subagent.secondsElapsed(at: now))
            detail = ([kind.title, state] + (elapsed.isEmpty ? [] : [elapsed])).joined(separator: " · ")
        }
    }

    public let running: [Row]
    public let finished: [Row]
    public let rows: [Row]

    public init(
        _ roster: SubagentRoster,
        cleared: ClearedBackgroundTasks = ClearedBackgroundTasks(),
        stopsTasks: Bool = false,
        now: Date = Date()
    ) {
        let live = Set(roster.subagents.map(\.id))
        running = roster.subagents
            .filter { $0.state == .running }
            .sorted { $0.startedAt < $1.startedAt }
            .map { Row($0, stopsTasks: stopsTasks, now: now) }
        finished = (roster.subagents.filter(\.state.isFinished)
            + roster.history.filter { !live.contains($0.id) })
            .filter { !cleared.hides($0) }
            .sorted { ($0.finishedAt ?? $0.startedAt) > ($1.finishedAt ?? $1.startedAt) }
            .map { Row($0, stopsTasks: stopsTasks, now: now) }
        rows = running + finished
    }

    public var runningCount: Int { running.count }

    public var canClear: Bool { !finished.isEmpty }

    public var isEmpty: Bool { rows.isEmpty }

    public var label: String? {
        guard !rows.isEmpty else { return nil }
        if runningCount > 0 { return "\(runningCount) running" }
        return rows.count == 1 ? "1 task" : "\(rows.count) tasks"
    }

    public var spokenLabel: String? {
        guard !rows.isEmpty else { return nil }
        let total = rows.count == 1 ? "1 background task" : "\(rows.count) background tasks"
        return runningCount > 0 ? "\(total), \(runningCount) running" : total
    }
}
