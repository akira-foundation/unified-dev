import Testing
import Foundation
@testable import Core

@MainActor
final class ScanFixture: AccountBound {
    static var built = 0

    let account: AgentAccountID?
    let refused: Set<AgentKind>

    init(account: AgentAccountHome?, refusing refused: Set<AgentKind>) {
        self.account = account?.id
        self.refused = refused
        Self.built += 1
    }
}

@Suite("Which selection an account reading belongs to", .tags(.persistence), .scratchDirectory)
struct AgentAccountReadingTests {
    private let work = AccountFixture.work
    private let personal = AccountFixture.personal
    private let repo: Repo
    private let space: Workspace

    init() {
        let repo = Repo(name: "r", path: "/tmp/r")
        self.repo = repo
        space = Workspace(repoID: repo.id, name: "w", branch: "b", path: "/tmp/w", baseBranch: "main")
    }

    private func made(project: AgentAccountID? = nil) -> AccountFingerprint {
        var book = AgentAccountChoiceBook()
        if let project { book.record(project, of: .claudeCode, forRepo: repo.id) }
        return AccountFingerprint.make(
            scope: AccountScope(workspaceID: space.id, repoID: repo.id), book: book, repoID: repo.id
        )
    }

    @Test func aFingerprintChangesWhenTheProjectPicksAnotherAccount() {
        #expect(made(project: work.id) != made(project: personal.id))
    }

    @Test func withNothingPickedTheFingerprintIsTheScopeAndChangesWithIt() {
        let elsewhere = Workspace(
            repoID: repo.id, name: "other", branch: "b", path: "/tmp/other", baseBranch: "main"
        )
        let other = AccountFingerprint.make(
            scope: AccountScope(workspaceID: elsewhere.id, repoID: repo.id),
            book: AgentAccountChoiceBook(),
            repoID: repo.id
        )
        #expect(made() == made())
        #expect(made() != other)
    }

    @Test func theSameSelectionReadTwiceIsTheSameFingerprint() {
        var book = AgentAccountChoiceBook()
        book.record(work.id, of: .claudeCode, forRepo: repo.id)
        book.record(personal.id, of: .codex, forRepo: repo.id)
        let scope = AccountScope(workspaceID: space.id, repoID: repo.id)

        #expect(AccountFingerprint.make(scope: scope, book: book, repoID: repo.id)
            == AccountFingerprint.make(scope: scope, book: book, repoID: repo.id))
    }

    @Test func aFingerprintChangesWhenOnlyTheOtherAgentsChoiceChanges() {
        let scope = AccountScope(workspaceID: nil, repoID: repo.id)
        var before = AgentAccountChoiceBook()
        before.record(work.id, of: .claudeCode, forRepo: repo.id)
        var after = before
        after.record(personal.id, of: .codex, forRepo: repo.id)

        #expect(AccountFingerprint.make(scope: scope, book: before, repoID: repo.id)
            != AccountFingerprint.make(scope: scope, book: after, repoID: repo.id))
    }

    @MainActor
    @Test func aStyleCatalogueIsBuiltOncePerProjectAndAccountAndNeverSharedBetweenAccounts() {
        let shelves = OutputStyleShelves<ScanFixture>()
        ScanFixture.built = 0

        let first = shelves.catalogue(project: "/tmp/p", account: work)
        let again = shelves.catalogue(project: "/tmp/p", account: work)
        let other = shelves.catalogue(project: "/tmp/p", account: personal)
        let elsewhere = shelves.catalogue(project: "/tmp/other", account: work)
        let none = shelves.catalogue(project: "/tmp/p", account: nil)

        #expect(first === again)
        #expect(first !== other)
        #expect(first !== elsewhere)
        #expect(first !== none)
        #expect(ScanFixture.built == 4)
        #expect(first.account == work.id)
        #expect(other.account == personal.id)
        #expect(none.account == nil)
    }

    @Test func twoAccountsDoNotShareAStyleShelf() {
        let home = AgentAccountHome.defaultHome(for: .claudeCode, home: AccountFixture.user)!

        #expect(OutputStyleShelf(project: "/tmp/p", account: work)
            != OutputStyleShelf(project: "/tmp/p", account: personal))
        #expect(OutputStyleShelf(project: "/tmp/p", account: nil)
            != OutputStyleShelf(project: "/tmp/p", account: home))
        #expect(OutputStyleShelf(project: "/tmp/p", account: work)
            == OutputStyleShelf(project: "/tmp/p", account: work))
        #expect(OutputStyleShelf(project: "/tmp/p", account: work)
            != OutputStyleShelf(project: "/tmp/other", account: work))
    }
}
