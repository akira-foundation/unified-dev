import Foundation
import Testing
@testable import Core

@Suite("The owner's click on a waiting message is judged again", .tags(.persistence), .scratchDirectory)
struct OrchestratorRequestClickTests {
    typealias Started = OrchestratorRequestLaunchTests.Started

    @Test("a profile closed since the card was made refuses the click, starts nothing and leaves it waiting")
    func closedSinceRefuses() async throws {
        let (far, card) = try await OrchestratorRequestLaunchTests.card("orch-click-closed")
        try await ProfileBridgeSwitch.save(false, profile: far.w.akira, to: far.w.store)
        let started = Started()

        let outcome = await OrchestratorRequestLaunchTests.launch(far, started).launch(card.id, as: .newWorkspace, store: far.w.store)

        #expect(outcome == .refused(BridgeProfileTrouble.closedToOutside(given: "Akira").sentence))
        #expect(started.projects.isEmpty)
        #expect(started.delivered.isEmpty)
        #expect(try await far.w.store.workSuggestion(id: card.id)?.state == .pending)
    }

    @Test("the sender's own profile closed since refuses the click too")
    func ownClosedSinceRefuses() async throws {
        let (far, card) = try await OrchestratorRequestLaunchTests.card("orch-click-own-closed")
        try await ProfileBridgeSwitch.save(false, profile: .initial, to: far.w.store)
        let started = Started()

        let outcome = await OrchestratorRequestLaunchTests.launch(far, started).launch(card.id, as: .newWorkspace, store: far.w.store)

        #expect(outcome == .refused(WorkSuggestionWording.senderCannotCross))
        #expect(started.projects.isEmpty)
        #expect(started.delivered.isEmpty)
        #expect(try await far.w.store.workSuggestion(id: card.id)?.state == .pending)
    }

    @Test("a card from the owner's Ask chat always arrives marked as coming from outside")
    func askChatIsFenced() async throws {
        let far = try await BridgeProfileOrchestratorReachTests.world("orch-click-ask", withOrchestrator: false)
        let ask = try await far.w.store.upsert(Session(workspaceID: nil, title: "Ask"))
        let owner = BridgeIdentity(ownerSession: ask.id, pinnedProfile: .initial)
        _ = await BridgeProfileOrchestratorReachTests.say(far, as: owner, ["project": .string(ProfileScopeWorld.farProjectName)])
        let card = try #require(try await far.w.store.workSuggestions(sessionID: ask.id).first)
        try await far.w.store.setActiveProfile(far.w.akira)
        let started = Started()

        _ = await OrchestratorRequestLaunchTests.launch(far, started).launch(card.id, as: .newWorkspace, store: far.w.store)

        let message = try #require(started.delivered.first)
        #expect(message.target.profile == "Akira")
        #expect(message.source.profile == WorkspaceMessageComposer.unknown)
        #expect(message.source.profileID == nil)
    }

    @Test("an orchestrator that another click started first receives the message")
    func racedStartDelivers() async throws {
        let (far, card) = try await OrchestratorRequestLaunchTests.card("orch-click-race")
        let store = far.w.store
        let orchestrator = far.orchestrator
        let started = Started()
        let launch = WorkSuggestionLaunch(
            start: { _, _, _, _ in throw CancellationError() },
            crew: { _, _, _ in .refused("No crew.") },
            admit: { _ in .failure(WorkSuggestionRefusal("No folder.")) },
            orchestrate: OrchestratorRequestLaunch(
                start: { _ in
                    _ = try await store.setOrchestrator(true, workspaceID: orchestrator.id)
                    throw CancellationError()
                },
                deliver: { message in
                    started.delivered.append(message)
                    return .sent(message)
                }
            )
        )

        _ = await launch.launch(card.id, as: .newWorkspace, store: store)

        #expect(started.delivered.first?.target.workspaceID == orchestrator.id)
    }
}
