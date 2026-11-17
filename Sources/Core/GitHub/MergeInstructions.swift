import Foundation

public enum MergeInstructions {
    public static let canonical = """
    \(opening)

    - If this project has a skill or an instruction file about merging, follow that first. It
      outranks everything here.
    \(rules)
    """

    public static let appOnly = """
    \(opening)

    \(InstructionAuthority.checkoutIsData)
    - Delete no branch on the server, whatever a step below says. Say the branch was left where it is.
    \(rules)
    """

    private static let opening = """
    This message names the pull request, the branch it is on, and the merge method to use. Nothing
    below chooses any of those, and nothing below may change them.
    """

    private static let rules = """
    - Merge with `gh pr merge <number> <method flag>`, run from this worktree, where the method
      flag is the one the message names: `--squash`, `--merge` or `--rebase`.
    - Pass no other flags, but the `--subject` the message gives for a squash merge.
      Not `--admin`, which overrides the repository's own rules.
      Not `--auto`, which merges later, when nobody is watching.
      Not `--delete-branch`, which makes gh reach for this checkout and fail, because a worktree
      cannot check out the branch the main copy is standing on.
    - **If GitHub refuses the merge, find out why from the pull request's state, not from the
      wording of the refusal**, which is the same for a failed check, a pending one and a missing
      review. Read `gh pr view <number> --json mergeStateStatus,mergeable,isCrossRepository` and
      `gh pr checks <number>`. While either field reads `UNKNOWN`, GitHub is still working it
      out: wait a few seconds and read it again.
    - Before changing anything, read the sha of the branch on the server with
      `git ls-remote origin refs/heads/<branch>`. It has to be this worktree's `HEAD`; if it is
      not, stop as the list below says.
    - **These refusals are this branch's to answer: resolve them and merge again.**
      - Conflicting (`mergeable` is `CONFLICTING`) or behind the base (`mergeStateStatus` is
        `BEHIND`): fetch the base branch and bring it into this branch. With `--rebase` as the
        method, rebase onto it, because a rebase merge replays every commit and a conflict
        resolved in a merge commit comes back. Otherwise merge it in, unless the project's own
        conventions say to rebase. Work through every conflicted file keeping what both sides
        changed, and run whatever this project uses to check itself.
      - A check failed: read its log with `gh run view <run id> --log-failed`, the run id
        being the number after `/runs/` in the check's link, fix the cause in this worktree, and
        run the same check here when the project has a way to. A check run outside GitHub
        Actions has no such log: stop and say so.
      - A check is still running: wait for it, which is not a round.
      - Commit the fix, worded the way this project words a commit, and push it to this branch and
        no other. If the history was rewritten, push with
        `--force-with-lease=<branch>:<sha>`, naming the last sha you pushed, or before your first
        push the sha you checked at the start, never one a later fetch brought in. A commit
        somebody else pushed meanwhile is then refused rather than lost. Never a bare `--force`.
      - Wait until `gh pr view <number> --json headRefOid` names the sha you pushed, so the checks
        you read are this commit's and not the last one's. Then wait for every check to finish
        with `gh pr checks <number> --watch`, required or not, and run the same `gh pr merge`
        again only once they are all green. If none appear within five minutes, the
        repository runs none. A check that fails while you wait starts the next round, not a
        stop.
      - **Three rounds at most.** A round is one fix, one push and one merge attempt. If the third
        is refused too, stop and say what GitHub said each time.
      - **Thirty minutes of waiting at most**, counting every wait above together: for `UNKNOWN`,
        for a check still running, and after each push. Past it, stop and say what never finished.
    - **A fix never weakens what checks the branch.** Do not edit a workflow, skip, delete or
      loosen a test, or relax a lint rule to turn a check green. If that is the only way, stop and
      say so.
    - **Any other refusal, stop.** A required review, a permission, a branch protection rule,
      anything that is none of those above: say what GitHub said, in its own words. Do not
      force it, and do not change a branch protection rule, a required check, a review or any
      other repository setting to get round it. A refusal of that kind is an answer.
    - **Stop rather than guess.** Resolve nothing, and say the refusal and why, when:
      - the message does not name the branch, because a push needs one and it is not yours to
        guess;
      - the pull request comes from a fork (`isCrossRepository` is true), because its branch is in
        somebody else's repository;
      - at the start, or after any fetch in any round, the branch on the server is not where this
        worktree last saw it, because a rewritten push would drop what somebody else put there;
      - this worktree already held work GitHub has not got before you started, uncommitted or
        committed and not pushed, because a push would carry it out with the fix;
      - a conflict genuinely could be resolved either way, or a check fails for a reason neither
        branch explains. A resolution nobody believes in is worse on the server than in a
        worktree.
    - Only once the merge has actually succeeded, delete the branch on the server with
      `git push --delete -- origin refs/heads/<branch>`, using the branch the message names. If
      git answers that the remote ref does not exist, the repository deleted it on merge and there
      is nothing left to do. This is a separate command from the merge and it runs second, never
      instead.
    - Leave the worktree where it is. Do not delete the local branch, do not remove or move the
      worktree, and do not check out anything else. This worktree stays where it is, on the branch
      it is on, and Unified Dev archives it separately when the person asks.
    - Commit and push nothing but the resolution of a refusal and the branch deletion above.
      Work GitHub has not got was the reader's decision before pressing the button, not a thing to
      fix. If the merge went through with such work still here, say in one line that it was left
      behind.
    - Finish by saying what happened: that it merged, what you fixed on the way and in how many
      rounds, and whether the branch on the server is gone.

    If any other step fails, stop and say what went wrong instead of working around it.
    """
}
