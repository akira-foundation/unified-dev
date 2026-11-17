import Foundation

public struct Subagent: Sendable, Hashable, Identifiable {
    public let id: SubagentID
    public let toolUseID: String
    public let description: String
    public let type: String
    public let spawnDepth: Int
    public let isBackgrounded: Bool
    public let prompt: String
    public let taskType: String
    public private(set) var state: SubagentState = .running
    public private(set) var summary: String = ""
    public private(set) var outputFile: String?
    public private(set) var elapsedSeconds: Int = 0
    public let startedAt: Date
    public private(set) var workingSince: Date
    public private(set) var retry: AgentRetry?
    public private(set) var finishedAt: Date?

    init(_ start: SubagentStart, at now: Date) {
        startedAt = now
        workingSince = now
        id = start.id
        toolUseID = start.toolUseID
        description = start.description
        type = start.type
        spawnDepth = start.spawnDepth
        isBackgrounded = start.isBackgrounded
        prompt = start.prompt
        taskType = start.taskType
    }

    public init(
        id: SubagentID,
        toolUseID: String = "",
        description: String = "",
        type: String = "",
        spawnDepth: Int = 1,
        isBackgrounded: Bool = false,
        prompt: String = "",
        taskType: String = "",
        state: SubagentState = .running,
        summary: String = "",
        outputFile: String? = nil,
        elapsedSeconds: Int = 0,
        retry: AgentRetry? = nil,
        finishedAt: Date? = nil,
        startedAt: Date = Date()
    ) {
        self.startedAt = startedAt
        self.workingSince = min(startedAt, (finishedAt ?? startedAt).addingTimeInterval(-Double(elapsedSeconds)))
        self.id = id
        self.toolUseID = toolUseID
        self.description = description
        self.type = type
        self.spawnDepth = spawnDepth
        self.isBackgrounded = isBackgrounded
        self.prompt = prompt
        self.taskType = taskType
        self.state = state
        self.summary = summary
        self.outputFile = outputFile
        self.elapsedSeconds = elapsedSeconds
        self.retry = retry
        self.finishedAt = finishedAt
    }

    public var kind: SubagentKind { SubagentKind(taskType: taskType) }

    public var hasOutput: Bool { !(outputFile ?? "").isEmpty }

    public func secondsElapsed(at now: Date) -> Int {
        max(0, Int((finishedAt ?? now).timeIntervalSince(workingSince)))
    }

    fileprivate mutating func move(to state: SubagentState, at now: Date) {
        self.state = state
        if state == .running {
            if finishedAt != nil { workingSince = now }
            finishedAt = nil
            return
        }
        if finishedAt == nil { finishedAt = now }
        retry = nil
    }

    fileprivate mutating func note(summary: String) {
        guard !summary.isEmpty else { return }
        self.summary = summary
    }

    fileprivate mutating func note(outputFile: String?) {
        guard let outputFile, !outputFile.isEmpty else { return }
        self.outputFile = outputFile
    }

    fileprivate mutating func tick(_ progress: SubagentProgress, at now: Date) {
        elapsedSeconds = max(elapsedSeconds, progress.elapsedSeconds)
        retry = progress.retry
        let reported = now.addingTimeInterval(-Double(progress.elapsedSeconds))
        if reported.timeIntervalSince(workingSince) <= -1 { workingSince = reported }
    }
}

public struct SubagentRoster: Sendable, Hashable {
    public private(set) var subagents: [Subagent] = []
    public private(set) var history: [Subagent] = []
    public private(set) var refusals = 0

    public static let historyLimit = 30

    private var byToolUse: [String: SubagentID] = [:]

    public init() {}

    public init(_ subagents: [Subagent]) {
        self.subagents = subagents
        for subagent in subagents where !subagent.toolUseID.isEmpty {
            byToolUse[subagent.toolUseID] = subagent.id
        }
    }

    public var isEmpty: Bool { subagents.isEmpty }

    public subscript(id: SubagentID) -> Subagent? {
        subagents.first { $0.id == id }
    }

    public func task(_ id: SubagentID) -> Subagent? {
        self[id] ?? history.first { $0.id == id }
    }

    public func subagent(forToolUseID toolUseID: String) -> Subagent? {
        guard !toolUseID.isEmpty, let id = byToolUse[toolUseID] else { return nil }
        return subagents.first { $0.id == id }
    }

    public var isWorking: Bool { subagents.contains { $0.kind == .agent && $0.state == .running } }

    public var isAnythingRunning: Bool { subagents.contains { $0.state == .running } }

    public var runningCommands: [Subagent] {
        subagents.filter { $0.kind == .command && $0.state == .running }
    }

    public mutating func turnStarted() {
        let finished = subagents.filter(\.state.isFinished)
        let finishedIDs = Set(finished.map(\.id))
        history.removeAll { finishedIDs.contains($0.id) }
        history.append(contentsOf: finished)
        history.removeFirst(max(0, history.count - Self.historyLimit))
        subagents.removeAll { $0.state.isFinished }
        let living = Set(subagents.map(\.id))
        byToolUse = byToolUse.filter { living.contains($0.value) }
        refusals = 0
    }

    public mutating func agentExited(now: Date = Date()) {
        for index in subagents.indices {
            apply(.agentExited, at: index, now: now)
        }
    }

    public mutating func apply(_ signal: SubagentSignal, now: Date = Date()) {
        switch signal {
        case .started(let start):
            guard let index = subagents.firstIndex(where: { $0.id == start.id }) else {
                subagents.append(Subagent(start, at: now))
                if !start.toolUseID.isEmpty { byToolUse[start.toolUseID] = start.id }
                return
            }
            apply(start.resumesExisting ? .resumed : .spawned, at: index, now: now)

        case .progressed(let progress):
            guard let id = byToolUse[progress.parentToolUseID],
                  let index = subagents.firstIndex(where: { $0.id == id }),
                  subagents[index].state == .running
            else { return }
            subagents[index].tick(progress, at: now)

        case .patched(let patch):
            guard let index = subagents.firstIndex(where: { $0.id == patch.id }) else { return }
            subagents[index].note(summary: patch.error ?? "")
            guard let status = patch.status else { return }
            apply(.reported(status: status), at: index, now: now)

        case .reported(let report):
            guard let index = subagents.firstIndex(where: { $0.id == report.id }) else { return }
            subagents[index].note(summary: report.summary)
            subagents[index].note(outputFile: report.outputFile)
            apply(.reported(status: report.status), at: index, now: now)
        }
    }

    private mutating func apply(_ event: SubagentLifecycleEvent, at index: Int, now: Date) {
        let transition = subagents[index].state.transition(on: event)
        if let destination = transition.destination {
            subagents[index].move(to: destination, at: now)
        } else if transition.isRefused {
            refusals += 1
        }
    }
}
