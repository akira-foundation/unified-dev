import Foundation
import Testing
@testable import Core

@Suite("The updates an archive plays, in order")
struct ArchiveSequenceTests {
    private let workspace = Workspace(
        repoID: RepoID.new(), name: "Lighthouse", branch: "lighthouse",
        path: "/tmp/Lighthouse", baseBranch: "main"
    )

    private let dirty = WorkspaceSafetyReport(hasUncommittedChanges: true)

    private func played(
        _ check: ArchiveCheck,
        hazards: ArchiveHazards = ArchiveHazards(),
        alwaysConfirm: Bool = false,
        allowsConfirmation: Bool = true
    ) -> (updates: [ArchiveConfirmationFlow.Update], refusal: String?) {
        let step = ArchiveSequence.afterChecking(
            check, workspace: workspace, deleteBranch: nil, hazards: hazards,
            alwaysConfirm: alwaysConfirm, allowsConfirmation: allowsConfirmation
        )
        let opening = ArchiveSequence.opening(
            workspace, hazards: hazards, allowsConfirmation: allowsConfirmation
        )
        return (opening + step.updates, step.refusal)
    }

    @Test("a clean workspace offers the check, then withdraws it before anyone answers, and archives")
    func archived() {
        let (updates, refusal) = played(.checked(WorkspaceSafetyReport()))

        #expect(updates == [
            .offer(.checking(workspace: workspace, hazards: ArchiveHazards())),
            .withdraw(workspace.id),
        ])
        #expect(refusal == nil)

        let before = ArchiveSequence.beforeArchiving(
            workspace, report: WorkspaceSafetyReport(), deleteBranch: nil, hazards: ArchiveHazards(),
            canvasLosses: [], alreadyStopped: [], allowsConfirmation: true
        )
        #expect(before == ArchiveStep(updates: []))
    }

    @Test("work that would be lost replaces the check with the report, and refuses")
    func refused() {
        let (updates, refusal) = played(.checked(dirty))
        let request = ArchiveRequest(workspace: workspace, report: dirty)

        #expect(updates == [
            .offer(.checking(workspace: workspace, hazards: ArchiveHazards())),
            .replace(request),
        ])
        #expect(refusal == request.refusal)
    }

    @Test("a check that could not run replaces the question with the problem, and refuses")
    func couldNotCheck() {
        let (updates, refusal) = played(.couldNotCheck(problem: "git is not answering."))

        #expect(updates.count == 2)
        #expect(updates.last?.request?.problem == "git is not answering.")
        #expect(updates.last.map { if case .replace = $0 { true } else { false } } == true)
        #expect(refusal?.contains("git is not answering.") == true)
    }

    @Test("an agent mid turn, or a click that always asks, keeps the question up over a clean report")
    func stillAsks() {
        let midTurn = played(.checked(WorkspaceSafetyReport()), hazards: ArchiveHazards(isAgentMidTurn: true))
        let asked = played(.checked(WorkspaceSafetyReport()), alwaysConfirm: true)

        #expect(!midTurn.updates.contains(.withdraw(workspace.id)))
        #expect(midTurn.refusal != nil)
        #expect(!asked.updates.contains(.withdraw(workspace.id)))
        #expect(asked.refusal != nil)
    }

    @Test("a workspace that changed while it was being archived is offered again, and refused")
    func failedHalfway() {
        let stopped = [Subagent(id: SubagentID("build"), description: "swift build", taskType: "local_bash")]
        let question = ArchiveSequence.changedWhileArchiving(
            workspace, fresh: dirty, deleteBranch: false, hazards: ArchiveHazards(),
            stoppedCommands: stopped, allowsConfirmation: true
        )
        let request = ArchiveRequest(
            workspace: workspace, report: dirty, deleteBranch: false, stoppedCommands: stopped
        )

        #expect(question.updates == [.offer(request)])
        #expect(question.refusal == request.refusal)
    }

    @Test("a canvas loss that appeared after the answer is offered before anything is removed")
    func canvasLossAfterTheAnswer() {
        let before = ArchiveSequence.beforeArchiving(
            workspace, report: nil, deleteBranch: nil, hazards: ArchiveHazards(),
            canvasLosses: ["the unsaved canvas Plan"], alreadyStopped: [], allowsConfirmation: true
        )

        #expect(before.updates.count == 1)
        #expect(before.updates.first?.request?.hazards.canvasLosses == ["the unsaved canvas Plan"])
        #expect(before.refusal != nil)

        let acknowledged = ArchiveSequence.beforeArchiving(
            workspace, report: nil, deleteBranch: nil,
            hazards: ArchiveHazards(canvasLosses: ["the unsaved canvas Plan"]),
            canvasLosses: ["the unsaved canvas Plan"], alreadyStopped: [], allowsConfirmation: true
        )
        #expect(acknowledged == ArchiveStep(updates: []))
    }

    @Test("a caller that cannot show a question gets the same verdicts and no updates")
    func withoutConfirmation() {
        let clean = played(.checked(WorkspaceSafetyReport()), allowsConfirmation: false)
        let lost = played(.checked(dirty), allowsConfirmation: false)

        #expect(clean.updates.isEmpty)
        #expect(clean.refusal == nil)
        #expect(lost.updates.isEmpty)
        #expect(lost.refusal == ArchiveRequest(workspace: workspace, report: dirty).refusal)
    }
}
