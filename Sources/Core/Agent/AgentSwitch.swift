import Foundation

public enum AgentSwitch {
    public enum Step: Sendable, Equatable {
        case stopTurn
        case denyOpenAsks
        case endSubagents
        case retireRunnerAndSwitch
        case waitForRetiredRunner
        case closeTurn
        case drainQueue
    }

    public struct Turn: Sendable, Equatable {
        public var isRunning: Bool
        public var hasActiveTurn: Bool
        public var hasOpenAsks: Bool

        public init(isRunning: Bool, hasActiveTurn: Bool, hasOpenAsks: Bool) {
            self.isRunning = isRunning
            self.hasActiveTurn = hasActiveTurn
            self.hasOpenAsks = hasOpenAsks
        }
    }

    public struct Outcome: Sendable, Equatable {
        public var written: Bool
        public var queueSettled: Bool

        public init(written: Bool, queueSettled: Bool) {
            self.written = written
            self.queueSettled = queueSettled
        }
    }

    public struct Facts: Sendable, Equatable {
        public var isArchiving: Bool
        public var isRewindHeld: Bool
        public var isSavingTurn: Bool
        public var isCatchingUp: Bool
        public var isAlreadySwitching: Bool

        public init(
            isArchiving: Bool, isRewindHeld: Bool, isSavingTurn: Bool, isCatchingUp: Bool, isAlreadySwitching: Bool
        ) {
            self.isArchiving = isArchiving
            self.isRewindHeld = isRewindHeld
            self.isSavingTurn = isSavingTurn
            self.isCatchingUp = isCatchingUp
            self.isAlreadySwitching = isAlreadySwitching
        }
    }

    public static let rewindHeld = "Resolve the interrupted rewind before changing the agent."
    public static let savingTurn = "Still saving this turn's file changes. Try again in a moment."
    public static let catchingUp = "This chat is still catching up with its agent. Try again in a moment."
    public static let alreadySwitching = "The previous agent is still shutting down. Try again in a moment."

    public static func failure(to wanted: AgentKind, detail: String) -> String {
        "Could not move this chat to \(wanted.label). \(detail)"
    }

    public static func queueFailure(to wanted: AgentKind, detail: String) -> String {
        "This chat moved to \(wanted.label), but its queued messages could not be updated, so they are waiting. \(detail)"
    }

    public static func refusal(_ facts: Facts) -> String? {
        if facts.isArchiving { return AgentTurnRestart.workspaceArchiving }
        if facts.isRewindHeld { return rewindHeld }
        if facts.isAlreadySwitching { return alreadySwitching }
        if facts.isSavingTurn { return savingTurn }
        if facts.isCatchingUp { return catchingUp }
        return nil
    }

    public static func steps(for turn: Turn) -> [Step] {
        let hasTurn = turn.isRunning || turn.hasActiveTurn
        var steps: [Step] = []
        if hasTurn { steps.append(.stopTurn) }
        if turn.hasOpenAsks { steps.append(.denyOpenAsks) }
        steps += [.retireRunnerAndSwitch, .endSubagents, .waitForRetiredRunner]
        if hasTurn { steps.append(.closeTurn) }
        steps.append(.drainQueue)
        return steps
    }

    @discardableResult
    public static func retireAndSwitch(
        runner: (any SessionRunner)?, store: Store, sessionID: SessionID,
        controls: ComposerControls, account: AgentAccountHome?, standings: [AgentAccountStanding]
    ) async throws -> Session {
        runner?.terminateNow()
        try await AgentAccountAssignment.remember(account, in: store)
        let switched = try await store.switchSegment(sessionID: sessionID, to: SessionSegmentTarget(
            agentKind: controls.agentKind, accountID: account?.id, model: controls.model, effort: controls.effort,
            accountName: account.map { AgentAccountNames.spoken(of: $0, among: standings) }
        ))
        runner?.terminateNow()
        try await store.updateSessionPreferences(
            id: sessionID, permissionMode: controls.permissionMode, interactionMode: controls.interactionMode
        )
        return try await store.session(id: sessionID) ?? switched
    }

    public static func denyAsks(_ ids: [String], in store: Store) async {
        for id in ids {
            try? await store.resolvePermissionAsk(id: id, decision: PermissionAskOutcome.stopped)
        }
    }

    public static let exitPollPause: @Sendable () async -> Void = { try? await Task.sleep(for: .milliseconds(25)) }

    public static func waitForExit(
        of runner: any SessionRunner,
        budget: Duration = AgentRunner.defaultShutdownBudget,
        pause: @Sendable () async -> Void = AgentSwitch.exitPollPause
    ) async -> Bool {
        let deadline = ContinuousClock.now + budget
        while await !runner.hasStoppedWriting {
            guard ContinuousClock.now < deadline else { return false }
            await pause()
        }
        return true
    }
}
