import Testing
import Foundation
@testable import Core

@Suite("Pull request fix ledger", .tags(.persistence), .scratchDirectory)
struct PullRequestFixLedgerTests {
    private let number = 7

    private func seed(_ store: Store) async throws -> Workspace {
        let repo = try await store.upsert(Repo(name: "r", path: TestScratch.unique("repo")))
        return try await store.upsert(Workspace(
            repoID: repo.id, name: "w", branch: "feat/work",
            path: TestScratch.unique("worktree"), baseBranch: "develop"
        ))
    }

    private func attempt(_ head: String, _ reason: PullRequestAutoFix.Reason = .checks) -> PullRequestAutoFix.Attempt {
        PullRequestAutoFix.Attempt(headCommit: head, reason: reason)
    }

    @Test("an untouched pull request owes nothing")
    func empty() async throws {
        let store = try makeTestStore("ledger-empty")
        let workspace = try await seed(store)
        let ledger = try await store.pullRequestFixLedger(workspaceID: workspace.id, number: number)
        #expect(ledger == PullRequestAutoFix.Ledger())
    }

    @Test("a claim is recorded and counted")
    func claim() async throws {
        let store = try makeTestStore("ledger-claim")
        let workspace = try await seed(store)
        let won = try await store.claimPullRequestFix(attempt("a"), workspaceID: workspace.id, number: number)
        let ledger = try await store.pullRequestFixLedger(workspaceID: workspace.id, number: number)
        #expect(won)
        #expect(ledger.inARow == 1)
        #expect(ledger.tried == [attempt("a")])
    }

    @Test("the same head and reason is claimed once and counted once")
    func claimedOnce() async throws {
        let store = try makeTestStore("ledger-once")
        let workspace = try await seed(store)
        _ = try await store.claimPullRequestFix(attempt("a"), workspaceID: workspace.id, number: number)
        let again = try await store.claimPullRequestFix(attempt("a"), workspaceID: workspace.id, number: number)
        let ledger = try await store.pullRequestFixLedger(workspaceID: workspace.id, number: number)
        #expect(!again)
        #expect(ledger.inARow == 1)
    }

    @Test("the limit refuses the fourth claim")
    func limit() async throws {
        let store = try makeTestStore("ledger-limit")
        let workspace = try await seed(store)
        for head in ["a", "b", "c"] {
            let won = try await store.claimPullRequestFix(attempt(head), workspaceID: workspace.id, number: number)
            #expect(won)
        }
        let fourth = try await store.claimPullRequestFix(attempt("d"), workspaceID: workspace.id, number: number)
        let ledger = try await store.pullRequestFixLedger(workspaceID: workspace.id, number: number)
        #expect(!fourth)
        #expect(ledger.inARow == 3)
        #expect(!ledger.tried.contains(attempt("d")))
    }

    @Test("a restart keeps the count, the attempts and the told stop")
    func survivesRestart() async throws {
        let path = TestScratch.unique("ledger-restart") + ".sqlite"
        let before = try Store(path: path)
        let workspace = try await seed(before)
        _ = try await before.claimPullRequestFix(attempt("a"), workspaceID: workspace.id, number: number)
        _ = try await before.claimPullRequestFixStopNotice(workspaceID: workspace.id, number: number)

        let after = try Store(path: path)
        let ledger = try await after.pullRequestFixLedger(workspaceID: workspace.id, number: number)
        let again = try await after.claimPullRequestFix(attempt("a"), workspaceID: workspace.id, number: number)
        #expect(ledger.inARow == 1)
        #expect(ledger.tried == [attempt("a")])
        #expect(ledger.stopAnnounced)
        #expect(!again)
    }

    @Test("a release gives back what the claim took")
    func release() async throws {
        let store = try makeTestStore("ledger-release")
        let workspace = try await seed(store)
        _ = try await store.claimPullRequestFix(attempt("a"), workspaceID: workspace.id, number: number)
        try await store.releasePullRequestFix(attempt("a"), workspaceID: workspace.id, number: number)
        let ledger = try await store.pullRequestFixLedger(workspaceID: workspace.id, number: number)
        let won = try await store.claimPullRequestFix(attempt("a"), workspaceID: workspace.id, number: number)
        #expect(ledger.inARow == 0)
        #expect(ledger.tried.isEmpty)
        #expect(won)
    }

    @Test("releasing what was never claimed changes nothing")
    func releaseUnclaimed() async throws {
        let store = try makeTestStore("ledger-release-none")
        let workspace = try await seed(store)
        _ = try await store.claimPullRequestFix(attempt("a"), workspaceID: workspace.id, number: number)
        try await store.releasePullRequestFix(attempt("b"), workspaceID: workspace.id, number: number)
        let ledger = try await store.pullRequestFixLedger(workspaceID: workspace.id, number: number)
        #expect(ledger.inARow == 1)
    }

    @Test("forgiving a run clears the count and the told stop and keeps the attempts")
    func forgive() async throws {
        let store = try makeTestStore("ledger-forgive")
        let workspace = try await seed(store)
        _ = try await store.claimPullRequestFix(attempt("a"), workspaceID: workspace.id, number: number)
        _ = try await store.claimPullRequestFixStopNotice(workspaceID: workspace.id, number: number)
        try await store.forgivePullRequestFixRun(workspaceID: workspace.id, number: number)
        let ledger = try await store.pullRequestFixLedger(workspaceID: workspace.id, number: number)
        let again = try await store.claimPullRequestFix(attempt("a"), workspaceID: workspace.id, number: number)
        #expect(ledger.inARow == 0)
        #expect(!ledger.stopAnnounced)
        #expect(ledger.tried == [attempt("a")])
        #expect(!again)
    }

    @Test("the stop notice is claimed once")
    func stopNoticeOnce() async throws {
        let store = try makeTestStore("ledger-stop")
        let workspace = try await seed(store)
        let first = try await store.claimPullRequestFixStopNotice(workspaceID: workspace.id, number: number)
        let second = try await store.claimPullRequestFixStopNotice(workspaceID: workspace.id, number: number)
        #expect(first)
        #expect(!second)
    }

    @Test("two pull requests keep separate counts")
    func separateCounts() async throws {
        let store = try makeTestStore("ledger-separate")
        let workspace = try await seed(store)
        _ = try await store.claimPullRequestFix(attempt("a"), workspaceID: workspace.id, number: 7)
        let other = try await store.pullRequestFixLedger(workspaceID: workspace.id, number: 8)
        #expect(other == PullRequestAutoFix.Ledger())
    }

    @Test("a write to the workspace row leaves the ledger alone")
    func workspaceWriteLeavesLedger() async throws {
        let store = try makeTestStore("ledger-upsert")
        let workspace = try await seed(store)
        _ = try await store.claimPullRequestFix(attempt("a"), workspaceID: workspace.id, number: number)
        try await store.update(workspaceID: workspace.id) { $0.name = "renamed" }
        let ledger = try await store.pullRequestFixLedger(workspaceID: workspace.id, number: number)
        #expect(ledger.inARow == 1)
    }

    @Test("a conflict and a failed check on one head are two attempts, and each reads back as itself")
    func perReasonInTheStore() async throws {
        let store = try makeTestStore("ledger-reason")
        let workspace = try await seed(store)
        let checks = try await store.claimPullRequestFix(attempt("a", .checks), workspaceID: workspace.id, number: number)
        let conflicts = try await store.claimPullRequestFix(attempt("a", .conflicts), workspaceID: workspace.id, number: number)
        let ledger = try await store.pullRequestFixLedger(workspaceID: workspace.id, number: number)
        #expect(checks)
        #expect(conflicts)
        #expect(ledger.inARow == 2)
        #expect(ledger.tried == [attempt("a", .checks), attempt("a", .conflicts)])
    }

    @Test("a restart at the limit cannot spend a fourth attempt")
    func limitSurvivesRestart() async throws {
        let path = TestScratch.unique("ledger-limit-restart") + ".sqlite"
        let before = try Store(path: path)
        let workspace = try await seed(before)
        for head in ["a", "b", "c"] {
            _ = try await before.claimPullRequestFix(attempt(head), workspaceID: workspace.id, number: number)
        }
        let after = try Store(path: path)
        let fourth = try await after.claimPullRequestFix(attempt("d"), workspaceID: workspace.id, number: number)
        #expect(!fourth)
    }

    @Test("a database from before this feature gains the tables and keeps its version")
    func migrationAddsTables() async throws {
        let path = TestScratch.unique("ledger-old") + ".sqlite"
        let original = try Store(path: path)
        let workspace = try await seed(original)
        let raw = try SQLiteDatabase(path: path)
        let version = try raw.readUserVersion()
        try raw.execute("DROP TABLE pull_request_fix_attempts; DROP TABLE pull_request_fix_runs;")

        let reopened = try Store(path: path)
        let won = try await reopened.claimPullRequestFix(attempt("a"), workspaceID: workspace.id, number: number)
        let kept = try await reopened.workspace(id: workspace.id)
        #expect(won)
        #expect(kept?.name == "w")
        #expect(try raw.readUserVersion() == version)
    }

    @Test("deleting a workspace takes its ledger with it")
    func cascade() async throws {
        let path = TestScratch.unique("ledger-cascade") + ".sqlite"
        let store = try Store(path: path)
        let workspace = try await seed(store)
        _ = try await store.claimPullRequestFix(attempt("a"), workspaceID: workspace.id, number: number)
        try await store.deleteWorkspace(id: workspace.id)

        let raw = try SQLiteDatabase(path: path)
        #expect(try raw.query("SELECT 1 FROM pull_request_fix_runs").isEmpty)
        #expect(try raw.query("SELECT 1 FROM pull_request_fix_attempts").isEmpty)
    }

    @Test("a release after the run was forgiven cannot take the count below zero")
    func releaseAfterForgive() async throws {
        let store = try makeTestStore("ledger-floor")
        let workspace = try await seed(store)
        _ = try await store.claimPullRequestFix(attempt("a"), workspaceID: workspace.id, number: number)
        try await store.forgivePullRequestFixRun(workspaceID: workspace.id, number: number)
        try await store.releasePullRequestFix(attempt("a"), workspaceID: workspace.id, number: number)
        let ledger = try await store.pullRequestFixLedger(workspaceID: workspace.id, number: number)
        #expect(ledger.inARow == 0)
    }

    @Test("each write reaches one pull request of one workspace")
    func writesStayOnTheirRow() async throws {
        let store = try makeTestStore("ledger-rows")
        let workspace = try await seed(store)
        let other = try await seed(store)
        for (id, pull) in [(workspace.id, 7), (workspace.id, 8), (other.id, 7)] {
            _ = try await store.claimPullRequestFix(attempt("a"), workspaceID: id, number: pull)
        }
        try await store.releasePullRequestFix(attempt("a"), workspaceID: workspace.id, number: 7)
        _ = try await store.claimPullRequestFixStopNotice(workspaceID: workspace.id, number: 8)
        try await store.forgivePullRequestFixRun(workspaceID: other.id, number: 7)

        let released = try await store.pullRequestFixLedger(workspaceID: workspace.id, number: 7)
        let told = try await store.pullRequestFixLedger(workspaceID: workspace.id, number: 8)
        let forgiven = try await store.pullRequestFixLedger(workspaceID: other.id, number: 7)
        #expect(released == PullRequestAutoFix.Ledger(stopAnnounced: false))
        #expect(told == PullRequestAutoFix.Ledger(inARow: 1, tried: [attempt("a")], stopAnnounced: true))
        #expect(forgiven == PullRequestAutoFix.Ledger(inARow: 0, tried: [attempt("a")]))
    }
}
