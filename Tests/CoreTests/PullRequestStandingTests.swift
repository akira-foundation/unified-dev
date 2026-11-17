import Foundation
import Testing
@testable import Core

@Suite("Pull request standing")
struct PullRequestStandingTests {
    private static let branch = "feat/213-pull-request-bar-path"

    private func pullRequest(
        state: String = "OPEN",
        isDraft: Bool = false,
        mergeable: String? = "MERGEABLE",
        checks: PullRequest.Checks = .none,
        checksSummary: String = "",
        reviewDecision: String? = nil,
        baseBranch: String = ""
    ) -> PullRequest {
        PullRequest(
            number: 213,
            title: "The pull request bar announces where the work stands",
            url: "https://github.com/akira-foundation/unified-dev-swift/pull/213",
            state: state,
            isDraft: isDraft,
            mergeable: mergeable,
            checks: checks,
            checksSummary: checksSummary,
            reviewDecision: reviewDecision,
            branch: Self.branch,
            baseBranch: baseBranch
        )
    }

    private func standing(
        pullRequest: PullRequest?,
        ahead: Int = 3,
        aheadIsCapped: Bool = false,
        hasUnreadCommitCount: Bool = false,
        localWork: LocalWork? = nil,
        hasRemote: Bool = true,
        continued: ContinuedBranch? = nil
    ) -> PullRequestStanding {
        PullRequestStanding.of(
            branch: Self.branch,
            baseBranch: "main",
            ahead: ahead,
            aheadIsCapped: aheadIsCapped,
            hasUnreadCommitCount: hasUnreadCommitCount,
            pullRequest: pullRequest,
            localWork: localWork,
            hasRemote: hasRemote,
            continued: continued
        )
    }

    @Test("A project with no remote shows what it has and nothing it cannot do")
    func withoutRemote() {
        let standing = standing(pullRequest: nil, hasRemote: false)

        #expect(standing.path.isEmpty)
        #expect(standing.links.isEmpty)
        #expect(standing.button == nil)
        #expect(standing.current == nil)
        #expect(standing.headline == Self.branch)
        #expect(standing.secondary == "3 commits ahead of main, no remote to push to")
    }

    @Test("A branch with commits and no pull request stands on commits, and opening one is next")
    func withoutPullRequest() {
        let standing = standing(pullRequest: nil)

        #expect(standing.current == .commits)
        #expect(standing.path == PullRequestStep.whole)
        #expect(standing.button?.act == .openPullRequest)
        #expect(standing.button?.label == "Open PR")
        #expect(standing.secondary == "3 commits ahead of main, no pull request yet")
        #expect(standing.reach(of: .commits) == .diff)
        #expect(standing.reach(of: .pullRequest) == nil)
        #expect(standing.reach(of: .merge) == nil)
    }

    @Test("A branch whose commits have not been counted yet is not called empty")
    func commitsNotCountedYet() {
        let unread = standing(pullRequest: nil, ahead: 0, hasUnreadCommitCount: true)
        let counted = standing(pullRequest: nil, ahead: 0)

        #expect(unread.button?.act == .openPullRequest)
        #expect(counted.button == nil)
    }

    @Test("A branch with nothing on it says where it was cut from rather than offering a pull request")
    func nothingToOpen() {
        let fresh = standing(pullRequest: nil, ahead: 0)
        let continued = standing(
            pullRequest: nil,
            ahead: 0,
            continued: ContinuedBranch(
                branch: Self.branch, previousBranch: "feat/204", baseBranch: "main", pullRequest: 204
            )
        )

        #expect(fresh.button == nil)
        #expect(fresh.secondary == "Nothing has changed on this branch yet.")
        #expect(continued.secondary == "Cut from main after #204 merged. Nothing on it yet.")
    }

    @Test("Uncommitted work alone is enough to offer a pull request")
    func uncommittedCounts() {
        let standing = standing(
            pullRequest: nil, ahead: 0, localWork: LocalWork(modifiedFiles: 2, hasUpstream: false)
        )

        #expect(standing.button?.act == .openPullRequest)
    }

    @Test("An open pull request with checks passing stands on merge, and merging is next")
    func readyToMerge() {
        let standing = standing(
            pullRequest: pullRequest(checks: .passing, checksSummary: "12 checks passed")
        )

        #expect(standing.current == .merge)
        #expect(standing.tone == .positive)
        #expect(standing.button?.act == .merge)
        #expect(standing.state == "Ready to merge")
        #expect(standing.secondary == "12 checks passed, ready to merge into main")
        #expect(standing.number == 213)
        #expect(standing.reach(of: .merge) == .merge)
        #expect(standing.reach(of: .checks) == .checks)
    }

    @Test("Checks running light the checks step in the accent, and merging is still the next step")
    func checksRunning() {
        let standing = standing(
            pullRequest: pullRequest(checks: .pending, checksSummary: "3 checks running")
        )

        #expect(standing.current == .checks)
        #expect(standing.tone == .accent)
        #expect(standing.button?.act == .merge)
        #expect(standing.secondary == "3 checks running")
    }

    @Test("A failed check lights the checks step in danger, offers the request, and withdraws merge")
    func checkFailed() {
        let standing = standing(
            pullRequest: pullRequest(checks: .failing, checksSummary: "1 of 12 checks failed")
        )

        #expect(standing.current == .checks)
        #expect(standing.tone == .danger)
        #expect(standing.button?.act == .askToFixChecks)
        #expect(standing.button?.label == "Ask to fix")
        #expect(standing.button?.sentence.contains("and push the fix to \(Self.branch).") == true)
        #expect(standing.button?.sentence.hasSuffix("is not merged.") == true)
        #expect(standing.secondary == "1 of 12 checks failed")
        #expect(standing.reach(of: .merge) == nil)
    }

    @Test("A failed check stays the danger even when there is local work to push first")
    func checkFailedWithLocalWork() {
        let standing = standing(
            pullRequest: pullRequest(checks: .failing, checksSummary: "1 of 12 checks failed"),
            localWork: LocalWork(unpushedCommits: 2)
        )

        #expect(standing.tone == .danger)
        #expect(standing.current == .commits)
        #expect(standing.button?.act == .push)
    }

    @Test("Checks the token cannot read are a warning, not a pass")
    func checksUnavailable() {
        let standing = standing(pullRequest: pullRequest(checks: .unavailable))

        #expect(standing.current == .checks)
        #expect(standing.tone == .warning)
        #expect(standing.state == GitHub.checksUnavailableSummary)
        #expect(standing.button?.act == .merge)
    }

    @Test("A reviewer asking for changes is a warning, not the colour of ready")
    func changesRequested() {
        let standing = standing(
            pullRequest: pullRequest(checks: .passing, reviewDecision: "CHANGES_REQUESTED")
        )

        #expect(standing.tone == .warning)
        #expect(standing.state == "Changes requested")
    }

    @Test("A conflict lights the merge step in warning, and nothing offers to merge")
    func conflicting() {
        let standing = standing(pullRequest: pullRequest(mergeable: "CONFLICTING"))

        #expect(standing.current == .merge)
        #expect(standing.tone == .warning)
        #expect(standing.button?.act == .askToFixConflicts)
        #expect(standing.secondary == "This branch conflicts with main")
        #expect(standing.reach(of: .merge) == nil)
    }

    @Test("Asking to fix a conflict goes on the click and says so, and no longer speaks of the composer")
    func conflictRequestLeavesOnTheClick() throws {
        let standing = standing(pullRequest: pullRequest(mergeable: "CONFLICTING"))
        let sentence = try #require(standing.button?.sentence)

        #expect(sentence == "Ask this workspace's agent to bring main into this worktree, resolve the"
            + " conflicts here and push \(Self.branch). The request goes as soon as you click and"
            + " does not appear in the conversation. #\(standing.number ?? 0) is not merged.")
    }

    @Test("Every request the bar sends says it leaves without a bubble")
    func everyRequestOfTheBarIsSilent() throws {
        let openPullRequest = standing(pullRequest: nil).button
        let failedCheck = standing(
            pullRequest: pullRequest(checks: .failing, checksSummary: "1 of 12 checks failed")
        ).button
        let draft = standing(
            pullRequest: pullRequest(isDraft: true, checks: .passing, checksSummary: "12 checks passed")
        ).button
        let push = standing(
            pullRequest: pullRequest(checks: .passing), localWork: LocalWork(unpushedCommits: 2)
        ).button

        #expect(draft?.act == .markReadyForReview)
        #expect(draft?.sentence.contains(PullRequestStanding.sentWithoutABubble) == true)
        #expect(push?.act == .push)
        #expect(push?.sentence.contains(PullRequestStanding.sentWithoutABubble) == true)
        #expect(openPullRequest?.act == .openPullRequest)
        #expect(openPullRequest?.sentence.contains(PullRequestStanding.sentWithoutABubble) == true)
        #expect(failedCheck?.act == .askToFixChecks)
        #expect(failedCheck?.sentence.contains(PullRequestStanding.sentWithoutABubble) == true)
        #expect(PullRequestStanding.sentWithoutABubble
            == "The request goes as soon as you click and does not appear in the conversation.")
    }

    @Test("Merging says it waits for the confirmation, and then leaves without a bubble")
    func mergeWaitsForTheConfirmation() throws {
        let merge = standing(pullRequest: pullRequest(checks: .passing)).button

        #expect(merge?.act == .merge)
        #expect(merge?.sentence.hasSuffix("Once you confirm, the request goes without appearing in the conversation.") == true)
        #expect(merge?.sentence.contains(PullRequestStanding.sentWithoutABubble) == false)
    }

    @Test("A draft stands on the pull request, and marking it ready is next")
    func draft() {
        let standing = standing(
            pullRequest: pullRequest(isDraft: true, checks: .passing, checksSummary: "12 checks passed")
        )

        #expect(standing.current == .pullRequest)
        #expect(standing.tone == .quiet)
        #expect(standing.button?.act == .markReadyForReview)
        #expect(standing.button?.label == "Mark ready")
        #expect(standing.secondary == "Draft, 12 checks passed")
    }

    @Test("Work GitHub does not have stands on commits, and pushing is next")
    func localWorkAhead() {
        let committed = standing(
            pullRequest: pullRequest(checks: .passing),
            localWork: LocalWork(unpushedCommits: 2)
        )
        let uncommitted = standing(
            pullRequest: pullRequest(checks: .passing),
            localWork: LocalWork(modifiedFiles: 1, unpushedCommits: 2)
        )

        #expect(committed.current == .commits)
        #expect(committed.tone == .accent)
        #expect(committed.button?.act == .push)
        #expect(committed.secondary == "2 commits to push")
        #expect(uncommitted.button?.act == .commitAndPush)
        #expect(uncommitted.button?.label == "Push")
        #expect(uncommitted.secondary == "1 file to commit, 2 commits to push")
    }

    @Test("Merged is one line with archiving as the action, and no path at all")
    func merged() {
        let standing = standing(pullRequest: pullRequest(state: "MERGED"))

        #expect(standing.path.isEmpty)
        #expect(standing.links.isEmpty)
        #expect(standing.current == nil)
        #expect(standing.state == "Merged")
        #expect(standing.tone == .merged)
        #expect(standing.button?.act == .archive)
        #expect(standing.secondary == "Merged into main")
    }

    @Test("A pull request merged into another base names that base, not the workspace's")
    func mergedIntoItsOwnBase() {
        let standing = standing(pullRequest: pullRequest(state: "MERGED", baseBranch: "develop"))

        #expect(standing.secondary == "Merged into develop")
        #expect(standing.sentence.contains("is merged into develop."))
    }

    @Test("A conflict is named against the pull request's base")
    func conflictAgainstItsOwnBase() {
        let standing = standing(pullRequest: pullRequest(mergeable: "CONFLICTING", baseBranch: "develop"))

        #expect(standing.secondary.contains("develop"))
        #expect(!standing.secondary.contains("main"))
    }

    @Test("A closed pull request keeps the path and offers nothing the app cannot do")
    func closed() {
        let standing = standing(pullRequest: pullRequest(state: "CLOSED"))

        #expect(standing.path == PullRequestStep.whole)
        #expect(standing.current == .pullRequest)
        #expect(standing.state == "Closed")
        #expect(standing.tone == .quiet)
        #expect(standing.button == nil)
        #expect(standing.reach(of: .merge) == nil)
    }

    @Test("Checks the app has not been told about are not a step to reach")
    func noChecksToOpen() {
        let standing = standing(pullRequest: pullRequest(checks: .none))

        #expect(standing.reach(of: .checks) == nil)
        #expect(standing.current == .merge)
    }

    @Test("A count past the limit says it is a floor rather than the number")
    func cappedCount() {
        let standing = standing(pullRequest: nil, ahead: 50, aheadIsCapped: true)

        #expect(standing.secondary == "more than 50 commits ahead of main, no pull request yet")
    }

    @Test("One commit is a commit")
    func oneCommit() {
        let standing = standing(pullRequest: nil, ahead: 1)

        #expect(standing.secondary == "1 commit ahead of main, no pull request yet")
    }
}
