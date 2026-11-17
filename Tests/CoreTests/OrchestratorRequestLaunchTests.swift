import Foundation
import Testing
@testable import Core

@Suite("A message waiting for an orchestrator starts one only on the owner's click", .tags(.persistence), .scratchDirectory)
struct OrchestratorRequestLaunchTests {
    final class Started: @unchecked Sendable {
        var projects: [RepoID] = []
        var delivered: [WorkspaceMessage] = []
    }

    static func card(_ label: String) async throws -> (BridgeProfileOrchestratorReachTests.Far, WorkSuggestion) {
        let far = try await BridgeProfileOrchestratorReachTests.world(label, withOrchestrator: false)
        _ = await BridgeProfileOrchestratorReachTests.say(
            far, as: far.w.world.homeAgent, ["project": .string(ProfileScopeWorld.farProjectName)]
        )
        let session = try #require(far.w.world.homeAgent.sessionID)
        return (far, try #require(try await far.w.store.workSuggestions(sessionID: session).first))
    }

    static func launch(_ far: BridgeProfileOrchestratorReachTests.Far, _ started: Started) -> WorkSuggestionLaunch {
        let store = far.w.store
        return WorkSuggestionLaunch(
            start: { _, _, _, _ in throw CancellationError() },
            crew: { _, _, _ in .refused("No crew.") },
            admit: { _ in .failure(WorkSuggestionRefusal("No folder.")) },
            orchestrate: OrchestratorRequestLaunch(
                start: { project in
                    started.projects.append(project.id)
                    let born = try await store.upsert(Workspace(
                        repoID: project.id, name: OrchestratorRole.newWorkspaceName, branch: "orchestrator",
                        path: TestScratch.unique("born"), baseBranch: "main"
                    ))
                    _ = try await store.setOrchestrator(true, workspaceID: born.id)
                    return try #require(try await store.workspace(id: born.id))
                },
                deliver: { message in
                    started.delivered.append(message)
                    return .sent(message)
                }
            )
        )
    }

    @Test("the click starts an orchestrator in that project and delivers the message to it, marked as crossing")
    func clickStartsAndDelivers() async throws {
        let (far, card) = try await Self.card("orch-request-start")
        let started = Started()

        let outcome = await Self.launch(far, started).launch(card.id, as: .newWorkspace, store: far.w.store)

        #expect(started.projects == [far.w.world.farProject.id])
        let message = try #require(started.delivered.first)
        #expect(message.text == card.prompt)
        #expect(message.source.workspaceID == far.w.world.homeWorkspace.id)
        #expect(message.source.profile == "Unified")
        #expect(message.target.profile == "Akira")
        guard case .started(let settled) = outcome, case .startedWorkspace(let id, _) = settled.state else {
            Issue.record("The card did not settle as started: \(outcome)")
            return
        }
        #expect(message.target.workspaceID == id)
        #expect(try await far.w.store.workspace(id: id)?.isOrchestrator == true)
        guard case .startedWorkspace = try await far.w.store.workSuggestion(id: card.id)?.state else {
            Issue.record("The stored card is not settled as started")
            return
        }
    }

    @Test("an orchestrator that appeared before the click receives it, and nothing new is started")
    func existingOrchestratorReceives() async throws {
        let (far, card) = try await Self.card("orch-request-existing")
        _ = try await far.w.store.setOrchestrator(true, workspaceID: far.orchestrator.id)
        let started = Started()

        _ = await Self.launch(far, started).launch(card.id, as: .newWorkspace, store: far.w.store)

        #expect(started.projects.isEmpty)
        #expect(started.delivered.first?.target.workspaceID == far.orchestrator.id)
    }

    @Test("without the app's seam nothing is started and the card waits again")
    func noSeamStartsNothing() async throws {
        let (far, card) = try await Self.card("orch-request-seamless")
        let before = try await far.w.store.workspaces().count
        let plain = WorkSuggestionLaunch(
            start: { _, _, _, _ in throw CancellationError() },
            crew: { _, _, _ in .refused("No crew.") },
            admit: { _ in .failure(WorkSuggestionRefusal("No folder.")) }
        )

        let outcome = await plain.launch(card.id, as: .newWorkspace, store: far.w.store)

        #expect(outcome == .refused(WorkSuggestionWording.gone))
        #expect(try await far.w.store.workspaces().count == before)
        #expect(try await far.w.store.workSuggestion(id: card.id)?.state == .pending)
    }

    @Test("a refused delivery leaves the card waiting for another click")
    func refusedDeliveryWaits() async throws {
        let (far, card) = try await Self.card("orch-request-refused")
        let launch = WorkSuggestionLaunch(
            start: { _, _, _, _ in throw CancellationError() },
            crew: { _, _, _ in .refused("No crew.") },
            admit: { _ in .failure(WorkSuggestionRefusal("No folder.")) },
            orchestrate: OrchestratorRequestLaunch(
                start: { _ in far.orchestrator },
                deliver: { _ in .refused("No chat.") }
            )
        )

        guard case .refused(let sentence) = await launch.launch(card.id, as: .newWorkspace, store: far.w.store) else {
            Issue.record("A refused delivery settled the card")
            return
        }
        #expect(sentence.contains("No chat."))
        #expect(sentence.contains(far.orchestrator.name))
        #expect(try await far.w.store.workSuggestion(id: card.id)?.state == .pending)
    }

    @Test("the card offers to start the orchestrator or to dismiss, and no draft")
    func cardOffers() async throws {
        let (_, card) = try await Self.card("orch-request-offers")
        let context = WorkSuggestionCard.Context(projectName: ProfileScopeWorld.farProjectName, workspaceName: "Home Workspace")

        #expect(WorkSuggestionCard.offers(for: card, in: context).map(\.action) == [.startOrchestrator, .dismiss])
        #expect(WorkSuggestionCard.Action.startOrchestrator.choice == .newWorkspace)
        #expect(!WorkSuggestionCard.opensAsDraft(card))
        #expect(WorkSuggestionCard.promptLabel(for: card) == "Message")
        #expect(WorkSuggestionCard.heading(for: card) == "Message waiting for an orchestrator")
        #expect(WorkSuggestionCard.targetLine(for: card, in: context)?.contains("has no orchestrator") == true)
    }
}
