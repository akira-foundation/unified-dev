import Foundation
import Testing
@testable import Core

@Suite("Starting a workspace for an agent or a card", .tags(.persistence), .scratchDirectory)
struct AgentWorkspaceLaunchTests {
    private final class Starts: @unchecked Sendable {
        var orders: [AgentWorkspaceOrder] = []
        var origins: [WorkspaceOrigin] = []
        var failure: (any Error)?

        func launch() -> AgentWorkspaceLaunch {
            AgentWorkspaceLaunch { [self] order, _, _, origin in
                orders.append(order)
                origins.append(origin)
                if let failure { throw failure }
                return StartedWorkspaceSummary(
                    workspaceID: WorkspaceID("w-born"), name: order.name ?? "Born",
                    branch: "claude/born", path: "/tmp/born"
                )
            }
        }
    }

    private struct Fixture {
        let store: Store
        let repo: Repo
        let parent: Workspace
        let chat: Session

        var identity: BridgeIdentity {
            BridgeIdentity(sessionID: chat.id, workspaceID: parent.id, role: .workspace)
        }
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fixture(_ label: String) async throws -> Fixture {
        let store = try makeTestStore(label)
        let repo = try await store.upsert(Repo(name: "lantern", path: "/tmp/lantern", defaultBranch: "main"))
        let parent = try await store.upsert(Workspace(
            repoID: repo.id, name: "Importer", branch: "importer",
            path: "/tmp/lantern-importer", baseBranch: "main"
        ))
        let chat = try await store.upsert(Session(workspaceID: parent.id, title: "Import"))
        return Fixture(store: store, repo: repo, parent: parent, chat: chat)
    }

    @Test("a start that is not a repeat reaches the app once, with the order and origin it was given")
    func startsOnce() async throws {
        let f = try await fixture("launch-once")
        let starts = Starts()
        let order = AgentWorkspaceOrder(prompt: "Keep the last row", name: "Last row")
        let origin = WorkspaceOrigin.agent(parentWorkspaceID: f.parent.id, spawnToolUseID: "k1")

        let outcome = await starts.launch().launch(order, in: f.repo, as: f.identity, origin: origin, store: f.store)

        guard case .started(let summary) = outcome else { Issue.record("\(outcome)"); return }
        #expect(summary.name == "Last row")
        #expect(starts.orders == [order])
        #expect(starts.origins == [origin])
    }

    @Test("a repeat of the same key answers with the workspace that exists, and starts nothing")
    func repeatAnswersWithWhatExists() async throws {
        let f = try await fixture("launch-repeat")
        let existing = try await f.store.upsert(Workspace(
            repoID: f.repo.id, name: "Last row", branch: "claude/last-row", path: "/tmp/last-row",
            baseBranch: "main", origin: .agent(parentWorkspaceID: f.parent.id, spawnToolUseID: "k1")
        ))
        let starts = Starts()

        let outcome = await starts.launch().launch(
            AgentWorkspaceOrder(prompt: "Keep the last row"), in: f.repo, as: f.identity,
            origin: .agent(parentWorkspaceID: f.parent.id, spawnToolUseID: "k1"), store: f.store
        )

        guard case .alreadyStarted(let found) = outcome else { Issue.record("\(outcome)"); return }
        #expect(found.id == existing.id)
        #expect(starts.orders.isEmpty)
    }

    @Test("a parent at its ceiling is refused, and told a start frees up when one is archived")
    func parentCeiling() async throws {
        let f = try await fixture("launch-ceiling")
        for index in 0..<WorkspaceStartAllowance.maximumChildren {
            _ = try await f.store.upsert(Workspace(
                repoID: f.repo.id, name: "child \(index)", branch: "claude/child-\(index)",
                path: "/tmp/child-\(index)", baseBranch: "main",
                origin: .agent(parentWorkspaceID: f.parent.id, spawnToolUseID: "t\(index)")
            ))
        }
        let starts = Starts()

        let outcome = await starts.launch().launch(
            AgentWorkspaceOrder(prompt: "One more"), in: f.repo, as: f.identity,
            origin: .agent(parentWorkspaceID: f.parent.id, spawnToolUseID: "fresh"), store: f.store
        )

        guard case .refused(.overAllowance(_, let retry)) = outcome else { Issue.record("\(outcome)"); return }
        #expect(retry == .whenAWorkspaceIsArchived(limit: WorkspaceStartAllowance.maximumChildren))
        #expect(starts.orders.isEmpty)
    }

    private func children(_ count: Int, of parent: Workspace, in f: Fixture) async throws {
        for index in 0..<count {
            _ = try await f.store.upsert(Workspace(
                repoID: f.repo.id, name: "child \(index)", branch: "claude/child-\(index)",
                path: "/tmp/child-\(index)", baseBranch: "main",
                origin: .agent(parentWorkspaceID: parent.id, spawnToolUseID: "t\(index)")
            ))
        }
    }

    private func oneMore(_ f: Fixture, _ starts: Starts = Starts()) async -> AgentWorkspaceLaunch.Outcome {
        await starts.launch().launch(
            AgentWorkspaceOrder(prompt: "One more"), in: f.repo, as: f.identity,
            origin: .agent(parentWorkspaceID: f.parent.id, spawnToolUseID: "fresh"), store: f.store
        )
    }

    private func isStarted(_ outcome: AgentWorkspaceLaunch.Outcome) -> Bool {
        if case .started = outcome { return true }
        return false
    }

    private func refusedLimit(_ outcome: AgentWorkspaceLaunch.Outcome) -> Int? {
        if case .refused(.overAllowance(_, retry: .whenAWorkspaceIsArchived(let limit))) = outcome { return limit }
        return nil
    }

    @Test("an orchestrator holding fifteen workspaces it started may start another")
    func orchestratorBelowItsCeiling() async throws {
        let f = try await fixture("launch-orchestrator-15")
        _ = try await f.store.setOrchestrator(true, workspaceID: f.parent.id)
        try await children(15, of: f.parent, in: f)

        #expect(isStarted(await oneMore(f)))
    }

    @Test("an orchestrator holding sixteen workspaces it started is refused at sixteen")
    func orchestratorAtItsCeiling() async throws {
        let f = try await fixture("launch-orchestrator-16")
        _ = try await f.store.setOrchestrator(true, workspaceID: f.parent.id)
        try await children(16, of: f.parent, in: f)
        let starts = Starts()

        let outcome = await oneMore(f, starts)

        #expect(refusedLimit(outcome) == 16)
        #expect(starts.orders.isEmpty)
        guard case .refused(let refusal) = outcome else { return }
        #expect(refusal.sentence == WorkspaceStartAllowance.running(limit: 16).refusal(count: 16))
    }

    @Test("an ordinary workspace may start its eighth and is refused at eight")
    func ordinaryWorkspaceKeepsEight() async throws {
        let below = try await fixture("launch-ordinary-7")
        try await children(7, of: below.parent, in: below)
        let at = try await fixture("launch-ordinary-8")
        try await children(8, of: at.parent, in: at)

        #expect(isStarted(await oneMore(below)))
        #expect(refusedLimit(await oneMore(at)) == 8)
    }

    @Test("another workspace being the project's orchestrator lends an ordinary one nothing")
    func theRoleIsTheCallersOwn() async throws {
        let f = try await fixture("launch-neighbour-orchestrator")
        let orchestrator = try await f.store.upsert(Workspace(
            repoID: f.repo.id, name: "Bridge", branch: "bridge", path: "/tmp/bridge", baseBranch: "main"
        ))
        _ = try await f.store.setOrchestrator(true, workspaceID: orchestrator.id)
        try await children(8, of: f.parent, in: f)

        #expect(refusedLimit(await oneMore(f)) == 8)
    }

    @Test("a workspace that stops being the orchestrator is held to eight at its next call")
    func losingTheRoleLowersTheCeiling() async throws {
        let f = try await fixture("launch-orchestrator-lost")
        _ = try await f.store.setOrchestrator(true, workspaceID: f.parent.id)
        try await children(8, of: f.parent, in: f)

        #expect(isStarted(await oneMore(f)))

        _ = try await f.store.setOrchestrator(false, workspaceID: f.parent.id)

        #expect(refusedLimit(await oneMore(f)) == 8)
    }

    @Test("the owner's rate says when the next start is free")
    func ownerRate() async throws {
        let f = try await fixture("launch-rate")
        for index in 0..<WorkspaceStartAllowance.maximumOwnerStarts {
            _ = try await f.store.upsert(Workspace(
                repoID: f.repo.id, name: "owner \(index)", branch: "claude/owner-\(index)",
                path: "/tmp/owner-\(index)", baseBranch: "main",
                createdAt: now.addingTimeInterval(-600 + Double(index)),
                origin: .ownerClient(spawnToolUseID: "o\(index)")
            ))
        }

        let outcome = await Starts().launch().launch(
            AgentWorkspaceOrder(prompt: "One more"), in: f.repo, as: .owner,
            origin: .ownerClient(spawnToolUseID: "fresh"), store: f.store, now: now
        )

        guard case .refused(.overAllowance(_, let retry)) = outcome else { Issue.record("\(outcome)"); return }
        #expect(retry == .after(now.addingTimeInterval(-600 + WorkspaceStartAllowance.ownerWindow)))
    }

    @Test("a start that fails is refused with the sentence the tool has always given")
    func failureIsDiagnosed() async throws {
        let f = try await fixture("launch-failure")
        let starts = Starts()
        starts.failure = AgentRunnerError.previousRunStillExiting

        let outcome = await starts.launch().launch(
            AgentWorkspaceOrder(prompt: "Keep the last row"), in: f.repo, as: f.identity,
            origin: .agent(parentWorkspaceID: f.parent.id, spawnToolUseID: "k1"), store: f.store
        )

        guard case .refused(.failed(let sentence)) = outcome else { Issue.record("\(outcome)"); return }
        #expect(sentence.contains("could not start"))
    }
}
