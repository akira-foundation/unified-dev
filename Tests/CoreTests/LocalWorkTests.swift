import Foundation
import Testing
@testable import Core

@Suite("Local work against a pull request")
struct LocalWorkTests {
    private func porcelain(_ records: [String]) -> Data {
        Data(records.map { $0 + "\0" }.joined().utf8)
    }

    @Test("a clean worktree on a pushed branch is holding nothing")
    func clean() {
        let work = Git.parseLocalWork(porcelain(["## work...origin/work"]))

        #expect(work.hasUpstream)
        #expect(work.modifiedFiles == 0)
        #expect(work.untrackedFiles == 0)
        #expect(work.unpushedCommits == 0)
        #expect(!work.isAhead)
    }

    @Test("the ahead count comes off the branch header")
    func ahead() {
        let work = Git.parseLocalWork(porcelain(["## work...origin/work [ahead 3]"]))

        #expect(work.unpushedCommits == 3)
        #expect(work.hasUnpushed)
        #expect(work.isAhead)
    }

    @Test("a branch that is ahead and behind still reports how far ahead")
    func aheadAndBehind() {
        let work = Git.parseLocalWork(porcelain(["## work...origin/work [ahead 2, behind 7]"]))

        #expect(work.unpushedCommits == 2)
    }

    @Test("behind alone is not work this machine is holding")
    func behindOnly() {
        let work = Git.parseLocalWork(porcelain(["## work...origin/work [behind 7]"]))

        #expect(work.unpushedCommits == 0)
        #expect(!work.isAhead)
    }

    @Test("a branch that was never pushed reports no upstream rather than a count")
    func noUpstream() {
        let work = Git.parseLocalWork(porcelain(["## work"]))

        #expect(!work.hasUpstream)
        #expect(work.unpushedCommits == 0)
        #expect(!work.hasUnpushed)
    }

    @Test("modified and untracked files are counted apart")
    func files() {
        let work = Git.parseLocalWork(porcelain([
            "## work...origin/work",
            " M Sources/App.swift",
            "M  Sources/Other.swift",
            "?? notes.md",
            "?? scratch/",
        ]))

        #expect(work.modifiedFiles == 2)
        #expect(work.untrackedFiles == 2)
        #expect(work.hasUncommitted)
        #expect(work.isAhead)
    }

    @Test("a rename is one file, not two")
    func rename() {
        let work = Git.parseLocalWork(porcelain([
            "## work...origin/work",
            "R  new/path.swift",
            "old/path.swift",
            " M other.swift",
        ]))

        #expect(work.modifiedFiles == 2)
    }

    @Test("output with no branch header answers nothing rather than clean")
    func noHeader() {
        let work = Git.parseLocalWork(porcelain([" M Sources/App.swift"]))

        #expect(!work.isAhead)
        #expect(work.modifiedFiles == 0)
    }

    private func pullRequest(
        state: String = "OPEN",
        isDraft: Bool = false,
        mergeable: String? = "MERGEABLE",
        checks: PullRequest.Checks = .passing,
        summary: String = "12 of 12 checks passed",
        review: String? = nil
    ) -> PullRequest {
        PullRequest(
            number: 128, title: "Ship it", url: "https://example/128", state: state,
            isDraft: isDraft, mergeable: mergeable, checks: checks, checksSummary: summary,
            reviewDecision: review, branch: "work"
        )
    }

    private let dirty = LocalWork(modifiedFiles: 3)
    private let unpushed = LocalWork(unpushedCommits: 2)

    @Test("local work outranks ready to merge")
    func outranksReady() {
        #expect(pullRequest().status.text == "Ready to merge")
        #expect(pullRequest().status(local: dirty).text == "Local changes")
        #expect(pullRequest().status(local: dirty).tone == .warning)
    }

    @Test(
        "a state the reader has to act on keeps its headline and gains the local count",
        arguments: [
            (PullRequest.Checks.failing, nil, "Checks failing"),
            (PullRequest.Checks.pending, nil, "Checks running"),
            (PullRequest.Checks.passing, "CHANGES_REQUESTED", "Changes requested"),
            (PullRequest.Checks.passing, "REVIEW_REQUIRED", "Waiting for review"),
        ] as [(PullRequest.Checks, String?, String)]
    )
    func keepsHeadline(checks: PullRequest.Checks, review: String?, headline: String) {
        let status = pullRequest(checks: checks, review: review).status(local: dirty)

        #expect(status.text == headline)
        #expect(status.detail?.contains("3 files to commit") == true)
        #expect(status.remedy == .commitAndPush)
    }

    @Test("draft keeps its headline and gains the local count")
    func draftKeepsHeadline() {
        #expect(pullRequest(isDraft: true).status.text == "Draft")

        let status = pullRequest(isDraft: true).status(local: dirty)
        #expect(status.text == "Draft")
        #expect(status.detail?.contains("3 files to commit") == true)
    }

    @Test("merge conflicts still outrank local work, button included")
    func conflictsWin() {
        let conflicted = pullRequest(mergeable: "CONFLICTING")
        let status = conflicted.status(local: dirty)

        #expect(status.text == "Merge conflicts")
        #expect(status.remedy == .fixConflicts)
    }

    @Test("the button offers the remedy the state actually calls for")
    func remedies() {
        #expect(pullRequest().status(local: nil).remedy == .merge)
        #expect(pullRequest().status(local: dirty).remedy == .commitAndPush)
        #expect(pullRequest().status(local: unpushed).remedy == .push)
        #expect(
            pullRequest().status(local: LocalWork(modifiedFiles: 1, unpushedCommits: 2)).remedy
                == .commitAndPush
        )
    }

    @Test("a merged or closed pull request is unaffected by what is on disk")
    func finishedWins() {
        #expect(pullRequest(state: "MERGED").status(local: dirty).text == "Merged")
        #expect(pullRequest(state: "CLOSED").status(local: unpushed).text == "Closed")
    }

    @Test("a clean worktree leaves GitHub's answer exactly as it was")
    func cleanChangesNothing() {
        let clean = LocalWork(hasUpstream: true)

        #expect(pullRequest().status(local: clean) == pullRequest().status)
        #expect(pullRequest().status(local: nil) == pullRequest().status)
    }

    @Test("local work warns without disabling the merge button")
    func doesNotBlockMerging() {
        #expect(pullRequest().status(local: dirty).canMerge)
    }

    @Test("a draft with local work is still blocked, for the draft's own reason")
    func keepsAnExistingBlock() {
        let status = pullRequest(isDraft: true).status(local: dirty)

        #expect(!status.canMerge)
        #expect(status.blockedReason == "This pull request is still a draft.")
    }

    @Test("the detail names whichever halves are true, in the order they have to be dealt with")
    func detail() {
        #expect(
            pullRequest().status(local: LocalWork(modifiedFiles: 1)).detail
                == "1 file to commit"
        )
        #expect(
            pullRequest().status(local: LocalWork(modifiedFiles: 2, untrackedFiles: 1)).detail
                == "3 files to commit"
        )
        #expect(
            pullRequest().status(local: LocalWork(unpushedCommits: 1)).detail
                == "1 commit to push"
        )
        #expect(
            pullRequest().status(local: LocalWork(modifiedFiles: 1, unpushedCommits: 2)).detail
                == "1 file to commit, 2 commits to push"
        )
    }

    @Test("the merge confirmation says what GitHub has not got")
    func confirmationNamesLocalWork() {
        let text = pullRequest().mergeConfirmation(
            base: "main", authority: .project, local: dirty
        )

        #expect(text.contains("3 files to commit"))
        #expect(text.contains("None of that is part of what is merged"))
        #expect(text.contains("leave it alone rather than commit it first"))
    }

    @Test("a clean worktree adds nothing to the merge confirmation")
    func confirmationStaysQuiet() {
        let text = pullRequest().mergeConfirmation(
            base: "main", authority: .project, local: LocalWork()
        )

        #expect(!text.contains("does not have everything"))
    }
}
