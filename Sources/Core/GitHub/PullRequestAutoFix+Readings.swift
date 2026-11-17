import Foundation

public extension PullRequestAutoFix {
    struct ChatReading: Sendable, Hashable {
        public var runsInTerminal: Bool
        public var isBusy: Bool
        public var isAwaitingAnswer: Bool
        public var wasStoppedByOwner: Bool
        public var permissionMode: PermissionMode
        public var interactionMode: InteractionMode

        public init(
            runsInTerminal: Bool,
            isBusy: Bool,
            isAwaitingAnswer: Bool,
            wasStoppedByOwner: Bool,
            permissionMode: PermissionMode,
            interactionMode: InteractionMode
        ) {
            self.runsInTerminal = runsInTerminal
            self.isBusy = isBusy
            self.isAwaitingAnswer = isAwaitingAnswer
            self.wasStoppedByOwner = wasStoppedByOwner
            self.permissionMode = permissionMode
            self.interactionMode = interactionMode
        }
    }

    static func chat(_ reading: ChatReading?) -> Chat {
        guard let reading else { return .absent }
        if reading.runsInTerminal { return .terminal }
        if reading.isAwaitingAnswer { return .awaitingAnswer }
        let isPlanning = reading.permissionMode == .plan || reading.interactionMode == .plan
        if reading.isBusy || reading.wasStoppedByOwner || isPlanning { return .busy }
        return reading.permissionMode == .bypassPermissions ? .unattended : .ready
    }

    static func account(
        isResolved: Bool, provider: AgentKind, quotas: [AgentQuota], at now: Date
    ) -> Account {
        guard isResolved else { return .missing }
        let isSpent = quotas.contains { quota in
            guard quota.provider == provider, let used = quota.fraction else { return false }
            return UsageMeterReading.isSpent(used: used, limit: 1, money: false)
                && (quota.resetsAt.map { $0 > now } ?? true)
        }
        return isSpent ? .quotaExhausted : .usable
    }

    static func isWorthReading(_ pullRequest: PullRequest, ledger: Ledger) -> Bool {
        guard pullRequest.isOpen else { return false }
        if pullRequest.checks == .passing, !pullRequest.hasConflicts { return ledger.inARow > 0 }
        guard pullRequest.hasConflicts || pullRequest.checks == .failing else { return false }
        guard ledger.inARow < attemptsInARow else { return !ledger.stopAnnounced }
        guard let head = pullRequest.headCommit else { return true }
        let reason: Reason = pullRequest.hasConflicts ? .conflicts : .checks
        return !ledger.tried.contains(Attempt(headCommit: head, reason: reason))
    }

    static func stoppedSentence(number: Int) -> String {
        "Stopped asking the agent to fix #\(number) after \(attemptsInARow) attempts in a row."
    }
}
