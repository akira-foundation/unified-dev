import Testing
import Foundation
@testable import Core

@Suite("A merged pull request whose branch is gone", .tags(.persistence), .scratchDirectory)
struct MergedPullRequestTests {
    private func pullRequest(number: Int, state: String = "MERGED") -> PullRequest {
        PullRequest(
            number: number,
            title: "Read the Sentry worker from a blob",
            url: "https://github.com/akira-io/laravel-csp/pull/\(number)",
            state: state,
            branch: "sentry-worker-src-blob",
            closedAt: state == "OPEN" ? nil : Date()
        )
    }

    private func seed(_ store: Store, name: String = "review") async throws -> Workspace {
        let repo = try await store.upsert(Repo(name: name, path: TestScratch.unique("repo")))
        return try await store.upsert(Workspace(
            repoID: repo.id, name: name, branch: "sentry-worker-src-blob",
            path: TestScratch.unique("worktree"), baseBranch: "main"
        ))
    }

    @Test("the first answer about a workspace is written down")
    func recordsTheFirstAnswer() {
        #expect(PullRequestNumber.toRecord(found: pullRequest(number: 222), recorded: nil) == 222)
    }

    @Test("an answer the row already holds is not written again")
    func skipsAnUnchangedNumber() {
        #expect(PullRequestNumber.toRecord(found: pullRequest(number: 222), recorded: 222) == nil)
    }

    @Test("a newer pull request replaces the one on the row")
    func newestAnswerWins() {
        #expect(
            PullRequestNumber.toRecord(found: pullRequest(number: 223, state: "OPEN"), recorded: 222)
                == 223
        )
    }

    @Test("nothing is written when the lookup answered nothing")
    func keepsTheNumberWhenGHCannotAnswer() {
        #expect(PullRequestNumber.toRecord(found: nil, recorded: 222) == nil)
    }

    @Test("a payload with no number in it is not written down as pull request zero")
    func refusesZero() throws {
        let decoded = try GitHub.decodePullRequest(from: Data("""
        {"state":"MERGED","headRefName":"sentry-worker-src-blob"}
        """.utf8))
        #expect(decoded.number == 0)
        #expect(PullRequestNumber.toRecord(found: decoded, recorded: nil) == nil)
    }

    private let started = Date(timeIntervalSince1970: 2_000_000)

    @Test("the newest pull request that could be this workspace's is chosen")
    func choosesTheNewestPlausibleMatch() {
        let matches = [
            PullRequestHeadMatch(number: 11, closedAt: started.addingTimeInterval(-604_800), isOpen: false),
            PullRequestHeadMatch(number: 175, closedAt: started.addingTimeInterval(3_600), isOpen: false),
            PullRequestHeadMatch(number: 207, closedAt: started.addingTimeInterval(-86_400), isOpen: false),
        ]
        #expect(
            PullRequestOwnership.choose(from: matches, startedAt: started, checkedOutAs: nil) == 175
        )
    }

    @Test("a pull request that ended before the workspace existed is not chosen")
    func refusesAnEarlierLifeOfTheName() {
        let matches = [
            PullRequestHeadMatch(number: 371, closedAt: started.addingTimeInterval(-86_400), isOpen: false)
        ]
        #expect(
            PullRequestOwnership.choose(from: matches, startedAt: started, checkedOutAs: nil) == nil
        )
    }

    @Test("an open one is chosen whenever the workspace was created")
    func acceptsAnOpenMatch() {
        let matches = [PullRequestHeadMatch(number: 412, closedAt: nil, isOpen: false)]
        #expect(
            PullRequestOwnership.choose(from: matches, startedAt: started, checkedOutAs: nil) == 412
        )
    }

    @Test("what the worktree was checked out from outranks the dates")
    func keepsTheCheckedOutNumber() {
        let matches = [
            PullRequestHeadMatch(number: 222, closedAt: started.addingTimeInterval(-604_800), isOpen: false)
        ]
        #expect(
            PullRequestOwnership.choose(from: matches, startedAt: started, checkedOutAs: 222) == 222
        )
        #expect(
            PullRequestOwnership.choose(from: matches, startedAt: started, checkedOutAs: 900) == nil
        )
    }

    @Test("nothing to choose from is nothing chosen")
    func choosesNothingFromAnEmptySearch() {
        #expect(PullRequestOwnership.choose(from: [], startedAt: started, checkedOutAs: nil) == nil)
    }

    @Test("a number that is not a number is never handed to gh")
    func refusesToAskAboutANonPositiveNumber() async throws {
        #expect(try await GitHub.snapshot(forNumber: 0, worktree: "/nowhere", maxAge: .zero) == nil)
        #expect(try await GitHub.snapshot(forNumber: -1, worktree: "/nowhere", maxAge: .zero) == nil)
    }

    @Test("the number is written, read back, and survives a relaunch")
    func theNumberSurvivesARelaunch() async throws {
        let path = TestScratch.unique("pr-number-restart") + ".sqlite"
        let store = try Store(path: path)
        let workspace = try await seed(store)
        #expect(workspace.pullRequestNumber == nil)

        await PullRequestNumber.record(pullRequest(number: 222), for: workspace, in: store)

        let relaunched = try Store(path: path)
        #expect(try await relaunched.workspace(id: workspace.id)?.pullRequestNumber == 222)
    }

    @Test("recording the number leaves alone every column it did not name")
    func recordingIsANarrowWrite() async throws {
        let store = try makeTestStore("pr-number-isolation")
        let workspace = try await seed(store)

        try await store.updateDiffStat(workspaceID: workspace.id, additions: 9, deletions: 2, files: 3)
        try await store.update(workspaceID: workspace.id) { $0.pinned = true }
        try await store.recordPullRequestNumber(222, workspaceID: workspace.id)

        let stored = try #require(try await store.workspace(id: workspace.id))
        #expect(stored.pullRequestNumber == 222)
        #expect(stored.additions == 9)
        #expect(stored.pinned)
    }

    @Test("the other writers of a workspace row leave the number alone")
    func writersKeepTheNumber() async throws {
        let store = try makeTestStore("pr-number-writers")
        let workspace = try await seed(store)
        try await store.recordPullRequestNumber(222, workspaceID: workspace.id)

        try await store.updateDiffStat(workspaceID: workspace.id, additions: 1, deletions: 0, files: 1)
        try await store.touch(workspaceID: workspace.id, unread: true)
        try await store.update(workspaceID: workspace.id) { $0.pinned = true }
        try await store.update(workspaceID: workspace.id) { $0.archive() }

        #expect(try await store.workspace(id: workspace.id)?.pullRequestNumber == 222)
    }

    @Test("a row written before the column existed reads as knowing no pull request")
    func anExistingDatabaseMigrates() async throws {
        let path = TestScratch.unique("pr-number-migration") + ".sqlite"
        let store = try Store(path: path)
        let workspace = try await seed(store)
        try await store.recordPullRequestNumber(222, workspaceID: workspace.id)

        let raw = try SQLiteDatabase(path: path)
        try raw.setUserVersion(0)

        let reopened = try Store(path: path)
        #expect(try await reopened.workspace(id: workspace.id)?.pullRequestNumber == 222)

        let fresh = try await seed(reopened, name: "fresh")
        #expect(fresh.pullRequestNumber == nil)
    }

    @Test("a workspace opened on a pull request knows its number before anything is looked up")
    func aReviewWorkspaceCarriesItsNumber() {
        let listing = PullRequestListing(
            number: 222,
            title: "Read the Sentry worker from a blob",
            headRefName: "sentry-worker-src-blob",
            baseRefName: "main"
        )
        #expect(WorkspaceCheckout.pullRequest(listing).pullRequestNumber == 222)

        let branch = ExistingBranch(name: "sentry-worker-src-blob", isLocal: true)
        #expect(WorkspaceCheckout.branch(branch).pullRequestNumber == nil)
    }
}
