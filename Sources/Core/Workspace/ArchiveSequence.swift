import Foundation

public enum ArchiveCheck: Sendable, Equatable {
    case couldNotCheck(problem: String)
    case checked(WorkspaceSafetyReport)
}

public struct ArchiveQuestion: Sendable, Equatable {
    public var updates: [ArchiveConfirmationFlow.Update]
    public var refusal: String

    public init(updates: [ArchiveConfirmationFlow.Update], refusal: String) {
        self.updates = updates
        self.refusal = refusal
    }
}

public struct ArchiveStep: Sendable, Equatable {
    public var updates: [ArchiveConfirmationFlow.Update]
    public var refusal: String?

    public init(updates: [ArchiveConfirmationFlow.Update], refusal: String? = nil) {
        self.updates = updates
        self.refusal = refusal
    }

    init(_ question: ArchiveQuestion) {
        self.init(updates: question.updates, refusal: question.refusal)
    }
}

public enum ArchiveSequence {
    public static func opening(
        _ workspace: Workspace, hazards: ArchiveHazards, allowsConfirmation: Bool
    ) -> [ArchiveConfirmationFlow.Update] {
        guard allowsConfirmation else { return [] }
        return [.offer(.checking(workspace: workspace, hazards: hazards))]
    }

    public static func afterChecking(
        _ check: ArchiveCheck,
        workspace: Workspace,
        deleteBranch: Bool?,
        hazards: ArchiveHazards,
        alwaysConfirm: Bool,
        allowsConfirmation: Bool
    ) -> ArchiveStep {
        let request: ArchiveRequest
        switch check {
        case .couldNotCheck(let problem):
            request = ArchiveRequest(
                workspace: workspace, report: WorkspaceSafetyReport(), deleteBranch: deleteBranch,
                problem: problem, hazards: hazards
            )
        case .checked(let report):
            let isSafe = report.isSafeToDiscard(
                deletingBranch: hazards.isDeletingBranch,
                isPullRequestMerged: hazards.isPullRequestMerged
            )
            guard !isSafe || hazards.isAgentMidTurn || !hazards.canvasLosses.isEmpty || alwaysConfirm else {
                return ArchiveStep(updates: allowsConfirmation ? [.withdraw(workspace.id)] : [])
            }
            request = ArchiveRequest(
                workspace: workspace, report: report, deleteBranch: deleteBranch, hazards: hazards
            )
        }
        return ArchiveStep(asking(request, as: .replace(request), allowsConfirmation: allowsConfirmation))
    }

    public static func beforeArchiving(
        _ workspace: Workspace,
        report: WorkspaceSafetyReport?,
        deleteBranch: Bool?,
        hazards: ArchiveHazards,
        canvasLosses: [String],
        alreadyStopped: [Subagent],
        allowsConfirmation: Bool
    ) -> ArchiveStep {
        guard CanvasArchiveQuestion.asks(canvasLosses, acknowledged: hazards.canvasLosses) else {
            return ArchiveStep(updates: [])
        }
        var unacknowledged = hazards
        unacknowledged.canvasLosses = canvasLosses
        let request = ArchiveRequest(
            workspace: workspace, report: report ?? WorkspaceSafetyReport(), deleteBranch: deleteBranch,
            hazards: unacknowledged, stoppedCommands: alreadyStopped
        )
        return ArchiveStep(asking(request, as: .offer(request), allowsConfirmation: allowsConfirmation))
    }

    public static func changedWhileArchiving(
        _ workspace: Workspace,
        fresh: WorkspaceSafetyReport,
        deleteBranch: Bool?,
        hazards: ArchiveHazards,
        stoppedCommands: [Subagent],
        allowsConfirmation: Bool
    ) -> ArchiveQuestion {
        let request = ArchiveRequest(
            workspace: workspace, report: fresh, deleteBranch: deleteBranch, hazards: hazards,
            stoppedCommands: stoppedCommands
        )
        return asking(request, as: .offer(request), allowsConfirmation: allowsConfirmation)
    }

    private static func asking(
        _ request: ArchiveRequest, as update: ArchiveConfirmationFlow.Update, allowsConfirmation: Bool
    ) -> ArchiveQuestion {
        ArchiveQuestion(updates: allowsConfirmation ? [update] : [], refusal: request.refusal)
    }
}
