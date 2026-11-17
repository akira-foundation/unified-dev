import Testing
import Foundation
@testable import Core

@Suite("Workspace start allowance")
struct WorkspaceStartAllowanceTests {
    private func parent(isOrchestrator: Bool) -> Workspace {
        Workspace(
            repoID: RepoID("r1"), name: "Parent", branch: "parent", path: "/tmp/parent",
            baseBranch: "main", isOrchestrator: isOrchestrator
        )
    }

    @Test("who asked decides which brake applies")
    func brakePerOrigin() {
        #expect(WorkspaceStartAllowance.of(.user, parent: nil) == .unlimited)
        #expect(
            WorkspaceStartAllowance
                .of(.agent(parentWorkspaceID: WorkspaceID("w1"), spawnToolUseID: "t1"), parent: nil)
                == .running(limit: WorkspaceStartAllowance.maximumChildren)
        )
        #expect(
            WorkspaceStartAllowance.of(.ownerClient(spawnToolUseID: "t1"), parent: nil)
                == .rate(
                    limit: WorkspaceStartAllowance.maximumOwnerStarts,
                    window: WorkspaceStartAllowance.ownerWindow
                )
        )
    }

    @Test("an agent's ceiling follows the role on its parent's row")
    func ceilingFollowsTheParentsRole() {
        let origin = WorkspaceOrigin.agent(parentWorkspaceID: WorkspaceID("w1"), spawnToolUseID: "t1")

        #expect(WorkspaceStartAllowance.of(origin, parent: parent(isOrchestrator: true)) == .running(limit: 16))
        #expect(WorkspaceStartAllowance.of(origin, parent: parent(isOrchestrator: false)) == .running(limit: 8))
        #expect(WorkspaceStartAllowance.of(origin, parent: nil) == .running(limit: 8))
    }

    @Test("being the orchestrator changes only an agent's ceiling")
    func theRoleLeavesTheOtherBrakesAlone() {
        let orchestrator = parent(isOrchestrator: true)

        #expect(WorkspaceStartAllowance.of(.user, parent: orchestrator) == .unlimited)
        #expect(
            WorkspaceStartAllowance.of(.ownerClient(spawnToolUseID: "t1"), parent: orchestrator)
                == .rate(limit: 6, window: 15 * 60)
        )
    }

    @Test("the owner's own hand is never refused, however many they have")
    func theSheetIsUncapped() {
        #expect(WorkspaceStartAllowance.unlimited.refusal(count: 400) == nil)
        #expect(!WorkspaceStartAllowance.unlimited.isExceeded(by: 400))
    }

    @Test("a ceiling refuses at the limit and not below it")
    func ceiling() {
        let allowance = WorkspaceStartAllowance.running(limit: 8)

        #expect(allowance.refusal(count: 7) == nil)
        #expect(allowance.refusal(count: 8) != nil)
        #expect(allowance.refusal(count: 9)?.contains("started 9 workspaces") == true)
    }

    @Test("the ceiling's refusal says what counts and what frees a place, and does not say running")
    func theCeilingRefusalNamesWhatItCounts() throws {
        let sentence = try #require(WorkspaceStartAllowance.running(limit: 16).refusal(count: 16))

        #expect(sentence.contains("not archived"))
        #expect(sentence.contains("counts until it is archived"))
        #expect(sentence.contains("below 16"))
        #expect(sentence.contains("workspace_archive"))
        #expect(!sentence.localizedCaseInsensitiveContains("running"))
    }

    @Test("a refusal above the ceiling names the ceiling rather than the count")
    func aRefusalAboveTheCeiling() throws {
        let sentence = try #require(WorkspaceStartAllowance.running(limit: 8).refusal(count: 12))

        #expect(sentence.contains("started 12 workspaces"))
        #expect(sentence.contains("limit is 8 at once"))
        #expect(sentence.contains("below 8"))
    }

    @Test("a rate refuses at the limit and not below it")
    func rate() {
        let allowance = WorkspaceStartAllowance.rate(limit: 6, window: 15 * 60)

        #expect(allowance.refusal(count: 5) == nil)
        #expect(allowance.refusal(count: 6)?.contains("in the last 15 minutes") == true)
    }

    @Test("the rate refusal says that waiting and retrying are both pointless")
    func theRateRefusalHeadsOffARetryLoop() throws {
        let sentence = try #require(
            WorkspaceStartAllowance.rate(limit: 6, window: 15 * 60).refusal(count: 6)
        )

        #expect(sentence.contains("do not retry and do not wait for it"))
        #expect(sentence.contains("nothing you can do here shortens"))
        #expect(!sentence.contains("/"))
    }
}
