import Testing
import Foundation
@testable import Core

@Suite("Pull request auto fix decision")
struct PullRequestAutoFixTests {
    private static let head = "abc123"

    private func pullRequest(
        state: String = "OPEN",
        mergeable: String? = "MERGEABLE",
        checks: PullRequest.Checks = .failing,
        branch: String = "feat/work",
        headCommit: String? = Self.head,
        author: String? = "owner",
        isFromFork: Bool? = false,
        hasUnfinishedChecks: Bool? = false,
        hasFixableCheckFailure: Bool? = true
    ) -> PullRequest {
        PullRequest(
            number: 7, title: "t", url: "u", state: state, mergeable: mergeable, checks: checks,
            branch: branch, baseBranch: "develop", headCommit: headCommit, author: author,
            isFromFork: isFromFork, hasUnfinishedChecks: hasUnfinishedChecks,
            hasFixableCheckFailure: hasFixableCheckFailure
        )
    }

    private func situation(
        isEnabled: Bool = true,
        pullRequest: PullRequest? = nil,
        localWork: LocalWork? = LocalWork(),
        checkedOutBranch: String? = "feat/work",
        checkedOutHead: String? = Self.head,
        viewerLogin: String? = "owner",
        commitAuthors: PullRequestAutoFix.CommitAuthors? = PullRequestAutoFix.CommitAuthors(headCommit: Self.head, logins: ["owner"]),
        isArchived: Bool = false,
        chat: PullRequestAutoFix.Chat = .ready,
        account: PullRequestAutoFix.Account = .usable,
        ledger: PullRequestAutoFix.Ledger = PullRequestAutoFix.Ledger()
    ) -> PullRequestAutoFix.Situation {
        PullRequestAutoFix.Situation(
            isEnabled: isEnabled,
            pullRequest: pullRequest ?? self.pullRequest(),
            localWork: localWork,
            workspaceBranch: "feat/work",
            checkedOutBranch: checkedOutBranch,
            checkedOutHead: checkedOutHead,
            viewerLogin: viewerLogin,
            commitAuthors: commitAuthors,
            isArchived: isArchived,
            chat: chat,
            account: account,
            ledger: ledger
        )
    }

    private func attempt(_ reason: PullRequestAutoFix.Reason, head: String = Self.head) -> PullRequestAutoFix.Attempt {
        PullRequestAutoFix.Attempt(headCommit: head, reason: reason)
    }

    @Test("a failed check on the owner's own pull request goes")
    func failedCheckSends() {
        #expect(PullRequestAutoFix.decide(situation()) == .send(attempt(.checks)))
    }

    @Test("a Bitbucket head abbreviated to twelve characters matches the full commit checked out and in the commits")
    func abbreviatedHeadSends() {
        let full = "ec3178d4d575a1b2c3d4e5f60718293a4b5c6d7e"
        let decision = PullRequestAutoFix.decide(situation(
            pullRequest: pullRequest(headCommit: "ec3178d4d575"),
            checkedOutHead: full,
            commitAuthors: PullRequestAutoFix.CommitAuthors(headCommit: full, logins: ["owner"])
        ))

        #expect(decision == .send(attempt(.checks, head: "ec3178d4d575")))
        #expect(PullRequestAutoFix.decide(situation(
            pullRequest: pullRequest(headCommit: "ec3178d4d576"),
            checkedOutHead: full,
            commitAuthors: PullRequestAutoFix.CommitAuthors(headCommit: full, logins: ["owner"])
        )) != .send(attempt(.checks, head: "ec3178d4d576")))
    }

    @Test("a conflict goes under its own reason")
    func conflictSends() {
        let conflicted = pullRequest(mergeable: "CONFLICTING", checks: .passing)
        #expect(PullRequestAutoFix.decide(situation(pullRequest: conflicted)) == .send(attempt(.conflicts)))
    }

    @Test("off by the switch, nothing goes")
    func switchedOff() {
        #expect(PullRequestAutoFix.decide(situation(isEnabled: false)) == .leave(.switchedOff))
    }

    @Test("a closed or merged pull request is left alone", arguments: ["CLOSED", "MERGED"])
    func notOpen(state: String) {
        #expect(PullRequestAutoFix.decide(situation(pullRequest: pullRequest(state: state))) == .leave(.notOpen))
    }

    @Test("a fork never fires, and not knowing counts as a fork", arguments: [Bool?.some(true), nil])
    func fork(isFromFork: Bool?) {
        let forked = pullRequest(isFromFork: isFromFork)
        #expect(PullRequestAutoFix.decide(situation(pullRequest: forked)) == .leave(.notTheOwners))
    }

    @Test("someone else's pull request never fires")
    func otherAuthor() {
        let theirs = pullRequest(author: "someone-else")
        #expect(PullRequestAutoFix.decide(situation(pullRequest: theirs)) == .leave(.notTheOwners))
    }

    @Test("an unknown author or viewer never fires")
    func unknownIdentity() {
        #expect(PullRequestAutoFix.decide(situation(pullRequest: pullRequest(author: nil))) == .leave(.notTheOwners))
        #expect(PullRequestAutoFix.decide(situation(viewerLogin: nil)) == .leave(.notTheOwners))
    }

    @Test("an empty login is not a match even against an empty author")
    func emptyLogins() {
        #expect(PullRequestAutoFix.decide(situation(pullRequest: pullRequest(author: ""), viewerLogin: "")) == .leave(.notTheOwners))
    }

    @Test("logins compare without regard to case")
    func loginCase() {
        let cased = pullRequest(author: "Owner")
        #expect(PullRequestAutoFix.decide(situation(pullRequest: cased)) == .send(attempt(.checks)))
    }

    @Test("a pull request on another branch than the workspace's does not fire")
    func otherBranch() {
        let elsewhere = pullRequest(branch: "feat/other")
        #expect(PullRequestAutoFix.decide(situation(pullRequest: elsewhere)) == .leave(.notThisBranch))
    }

    @Test("a checkout that moved off the workspace's branch does not fire", arguments: [String?.some("main"), nil])
    func movedCheckout(checkedOut: String?) {
        #expect(PullRequestAutoFix.decide(situation(checkedOutBranch: checkedOut)) == .leave(.notThisBranch))
    }

    @Test("an archived workspace does not fire")
    func archived() {
        #expect(PullRequestAutoFix.decide(situation(isArchived: true)) == .leave(.archived))
    }

    @Test("unfinished checks hold back a failure and a conflict, and not knowing holds too", arguments: [Bool?.some(true), nil])
    func unfinished(hasUnfinishedChecks: Bool?) {
        let failing = pullRequest(hasUnfinishedChecks: hasUnfinishedChecks)
        let conflicted = pullRequest(mergeable: "CONFLICTING", hasUnfinishedChecks: hasUnfinishedChecks)
        #expect(PullRequestAutoFix.decide(situation(pullRequest: failing)) == .leave(.checksUnfinished))
        #expect(PullRequestAutoFix.decide(situation(pullRequest: conflicted)) == .leave(.checksUnfinished))
    }

    @Test("pending and passing checks ask for nothing")
    func nothingToFix() {
        let pending = pullRequest(checks: .pending, hasUnfinishedChecks: true)
        let passing = pullRequest(checks: .passing)
        #expect(PullRequestAutoFix.decide(situation(pullRequest: pending)) == .leave(.nothingToFix))
        #expect(PullRequestAutoFix.decide(situation(pullRequest: passing)) == .leave(.nothingToFix))
    }

    @Test("a draft with failing checks offers mark ready, as the bar does, so nothing goes")
    func draftFailing() {
        var draft = pullRequest()
        draft.isDraft = true
        #expect(PullRequestAutoFix.decide(situation(pullRequest: draft)) == .leave(.nothingToFix))
    }

    @Test("a head the app could not read does not fire")
    func noHead() {
        let unknown = pullRequest(headCommit: nil)
        #expect(PullRequestAutoFix.decide(situation(pullRequest: unknown)) == .leave(.unknownHead))
    }

    @Test("an empty head does not match the commits that were read")
    func emptyHead() {
        let unknown = pullRequest(headCommit: "")
        #expect(PullRequestAutoFix.decide(situation(pullRequest: unknown)) == .leave(.notTheOwners))
    }

    @Test("a chat that skips permissions is left alone and spends nothing")
    func unattended() {
        #expect(PullRequestAutoFix.decide(situation(chat: .unattended)) == .leave(.unattended))
    }

    @Test("authors read at another head prove nothing about this one")
    func authorsOfAnotherHead() {
        let older = PullRequestAutoFix.CommitAuthors(headCommit: "older", logins: ["owner"])
        #expect(PullRequestAutoFix.decide(situation(commitAuthors: older)) == .leave(.notTheOwners))
    }

    @Test("work on disk that GitHub does not have holds a conflict back")
    func aheadHoldsConflict() {
        let conflicted = pullRequest(mergeable: "CONFLICTING", checks: .passing)
        let dirty = LocalWork(modifiedFiles: 1)
        #expect(PullRequestAutoFix.decide(situation(pullRequest: conflicted, localWork: dirty)) == .leave(.localWork))
    }

    @Test("local work the app has not read holds it back")
    func unknownLocalWork() {
        #expect(PullRequestAutoFix.decide(situation(localWork: nil)) == .leave(.localWork))
    }

    @Test("each state of the chat holds the request", arguments: [
        (PullRequestAutoFix.Chat.absent, PullRequestAutoFix.Leave.noChat),
        (.terminal, .terminal),
        (.busy, .busy),
        (.awaitingAnswer, .awaitingAnswer),
        (.unattended, .unattended),
    ])
    func chatHolds(chat: PullRequestAutoFix.Chat, expected: PullRequestAutoFix.Leave) {
        #expect(PullRequestAutoFix.decide(situation(chat: chat)) == .leave(expected))
    }

    @Test("no account or an exhausted quota holds it back and spends nothing", arguments: [
        (PullRequestAutoFix.Account.missing, PullRequestAutoFix.Leave.noAccount),
        (.quotaExhausted, .quotaExhausted),
    ])
    func accountHolds(account: PullRequestAutoFix.Account, expected: PullRequestAutoFix.Leave) {
        #expect(PullRequestAutoFix.decide(situation(account: account)) == .leave(expected))
    }

    @Test("the same head and reason goes once")
    func alreadyTried() {
        let ledger = PullRequestAutoFix.Ledger(inARow: 1, tried: [attempt(.checks)])
        #expect(PullRequestAutoFix.decide(situation(ledger: ledger)) == .leave(.alreadyTried))
    }

    @Test("the other reason on the same head still goes")
    func otherReasonOnSameHead() {
        let ledger = PullRequestAutoFix.Ledger(inARow: 1, tried: [attempt(.conflicts)])
        #expect(PullRequestAutoFix.decide(situation(ledger: ledger)) == .send(attempt(.checks)))
    }

    @Test("a new head goes again")
    func newHead() {
        let ledger = PullRequestAutoFix.Ledger(inARow: 2, tried: [attempt(.checks, head: "old")])
        #expect(PullRequestAutoFix.decide(situation(ledger: ledger)) == .send(attempt(.checks)))
    }

    @Test("the limit is three")
    func limit() {
        #expect(PullRequestAutoFix.attemptsInARow == 3)
    }

    @Test("the third attempt in a row is the last one")
    func thirdIsLast() {
        let below = PullRequestAutoFix.Ledger(inARow: 2)
        let at = PullRequestAutoFix.Ledger(inARow: 3)
        #expect(PullRequestAutoFix.decide(situation(ledger: below)) == .send(attempt(.checks)))
        #expect(PullRequestAutoFix.decide(situation(ledger: at)) == .announceStop)
    }

    @Test("the stop is told once")
    func stopToldOnce() {
        let ledger = PullRequestAutoFix.Ledger(inARow: 3, stopAnnounced: true)
        #expect(PullRequestAutoFix.decide(situation(ledger: ledger)) == .leave(.stopped))
    }

    @Test("the stop waits for the chat, so the last attempt's turn gets to finish")
    func stopWaitsForTurn() {
        let ledger = PullRequestAutoFix.Ledger(inARow: 3)
        #expect(PullRequestAutoFix.decide(situation(chat: .busy, ledger: ledger)) == .leave(.busy))
    }

    @Test("an exhausted quota does not keep the stop from being told")
    func stopDespiteQuota() {
        let ledger = PullRequestAutoFix.Ledger(inARow: 3)
        #expect(PullRequestAutoFix.decide(situation(account: .quotaExhausted, ledger: ledger)) == .announceStop)
    }

    @Test("green with no conflict forgives the run")
    func greenForgives() {
        let passing = pullRequest(checks: .passing)
        let ledger = PullRequestAutoFix.Ledger(inARow: 2)
        #expect(PullRequestAutoFix.decide(situation(pullRequest: passing, ledger: ledger)) == .forgiveRun)
    }

    @Test("green with nothing owed has nothing to forgive")
    func greenWithNothingOwed() {
        let passing = pullRequest(checks: .passing)
        #expect(PullRequestAutoFix.decide(situation(pullRequest: passing)) == .leave(.nothingToFix))
    }

    @Test("no checks reported does not forgive, since a fresh push looks the same")
    func noChecksDoesNotForgive() {
        let none = pullRequest(checks: PullRequest.Checks.none)
        let ledger = PullRequestAutoFix.Ledger(inARow: 2)
        #expect(PullRequestAutoFix.decide(situation(pullRequest: none, ledger: ledger)) == .leave(.nothingToFix))
    }

    @Test("green that GitHub has not finished comparing does not forgive")
    func unknownMergeabilityDoesNotForgive() {
        let unknown = pullRequest(mergeable: "UNKNOWN", checks: .passing)
        let ledger = PullRequestAutoFix.Ledger(inARow: 2)
        #expect(PullRequestAutoFix.decide(situation(pullRequest: unknown, ledger: ledger)) == .leave(.nothingToFix))
    }

    @Test("a conflict on green checks does not forgive")
    func conflictDoesNotForgive() {
        let conflicted = pullRequest(mergeable: "CONFLICTING", checks: .passing)
        let ledger = PullRequestAutoFix.Ledger(inARow: 2)
        #expect(PullRequestAutoFix.decide(situation(pullRequest: conflicted, ledger: ledger)) == .send(attempt(.conflicts)))
    }

    @Test("another author's green does not touch the run")
    func strangerDoesNotForgive() {
        let theirs = pullRequest(checks: .passing, author: "someone-else")
        let ledger = PullRequestAutoFix.Ledger(inARow: 2)
        #expect(PullRequestAutoFix.decide(situation(pullRequest: theirs, ledger: ledger)) == .leave(.notTheOwners))
    }

    @Test("a failure that only cancelled runs produced asks for nothing, and not knowing asks for nothing", arguments: [Bool?.some(false), nil])
    func cancelledOnly(hasFixable: Bool?) {
        let cancelled = pullRequest(hasFixableCheckFailure: hasFixable)
        #expect(PullRequestAutoFix.decide(situation(pullRequest: cancelled)) == .leave(.nothingToFix))
    }

    @Test("a checkout that moved past the pull request's head holds it back", arguments: [String?.some("later"), nil])
    func checkoutMoved(checkedOutHead: String?) {
        #expect(PullRequestAutoFix.decide(situation(checkedOutHead: checkedOutHead)) == .leave(.localWork))
    }

    @Test("unpushed commits hold a conflict back")
    func unpushedHoldsConflict() {
        let conflicted = pullRequest(mergeable: "CONFLICTING", checks: .passing)
        let unpushed = LocalWork(unpushedCommits: 1)
        #expect(PullRequestAutoFix.decide(situation(pullRequest: conflicted, localWork: unpushed)) == .leave(.localWork))
    }

    @Test("a third attempt whose turn pushed nothing still tells the owner")
    func stopOnTheSameHead() {
        let ledger = PullRequestAutoFix.Ledger(inARow: 3, tried: [attempt(.checks)])
        #expect(PullRequestAutoFix.decide(situation(ledger: ledger)) == .announceStop)
    }

    @Test("a missing account does not keep the stop from being told")
    func stopDespiteNoAccount() {
        let ledger = PullRequestAutoFix.Ledger(inARow: 3)
        #expect(PullRequestAutoFix.decide(situation(account: .missing, ledger: ledger)) == .announceStop)
    }

    @Test("green forgives from one attempt up to a run that was already told", arguments: [
        PullRequestAutoFix.Ledger(inARow: 1),
        PullRequestAutoFix.Ledger(inARow: 3),
        PullRequestAutoFix.Ledger(inARow: 3, stopAnnounced: true),
    ])
    func greenForgivesAnyRun(ledger: PullRequestAutoFix.Ledger) {
        let passing = pullRequest(checks: .passing)
        #expect(PullRequestAutoFix.decide(situation(pullRequest: passing, ledger: ledger)) == .forgiveRun)
    }

    @Test("green does not forgive with the switch off, on a closed pull request, in an archived workspace or on another branch")
    func greenForgivesOnlyWhereItApplies() {
        let passing = pullRequest(checks: .passing)
        let ledger = PullRequestAutoFix.Ledger(inARow: 2)
        let closed = pullRequest(state: "CLOSED", checks: .passing)
        let elsewhere = pullRequest(checks: .passing, branch: "feat/other")
        #expect(PullRequestAutoFix.decide(situation(isEnabled: false, pullRequest: passing, ledger: ledger)) == .leave(.switchedOff))
        #expect(PullRequestAutoFix.decide(situation(pullRequest: closed, ledger: ledger)) == .leave(.notOpen))
        #expect(PullRequestAutoFix.decide(situation(pullRequest: passing, isArchived: true, ledger: ledger)) == .leave(.archived))
        #expect(PullRequestAutoFix.decide(situation(pullRequest: elsewhere, ledger: ledger)) == .leave(.notThisBranch))
    }

    @Test("a commit by anyone else on the owner's own pull request stops it, and not knowing stops it", arguments: [
        Set<String>?.some(["owner", "collaborator"]),
        .some(["collaborator"]),
        .some([""]),
        .some([]),
        nil,
    ])
    func otherCommitAuthors(logins: Set<String>?) {
        let authors = logins.map { PullRequestAutoFix.CommitAuthors(headCommit: Self.head, logins: $0) }
        #expect(PullRequestAutoFix.decide(situation(commitAuthors: authors)) == .leave(.notTheOwners))
    }

    @Test("commit authors compare without regard to case")
    func commitAuthorCase() {
        #expect(PullRequestAutoFix.decide(situation(commitAuthors: PullRequestAutoFix.CommitAuthors(headCommit: Self.head, logins: ["OWNER"]))) == .send(attempt(.checks)))
    }

    @Test("an empty branch on both sides is not a match")
    func emptyBranch() {
        var blank = situation(pullRequest: pullRequest(branch: ""), checkedOutBranch: "")
        blank.workspaceBranch = ""
        #expect(PullRequestAutoFix.decide(blank) == .leave(.notThisBranch))
    }

    @Test("green on a head the app could not read does not forgive")
    func greenWithoutHead() {
        let passing = pullRequest(checks: .passing, headCommit: nil)
        let ledger = PullRequestAutoFix.Ledger(inARow: 2)
        #expect(PullRequestAutoFix.decide(situation(pullRequest: passing, ledger: ledger)) == .leave(.unknownHead))
    }
}
