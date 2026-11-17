import Foundation

public extension MergeInstructions {
    static func canonical(for forge: ForgeKind) -> String {
        switch forge {
        case .gitHub: canonical
        case .bitbucket: bitbucketCanonical
        }
    }

    static func appOnly(for forge: ForgeKind) -> String {
        switch forge {
        case .gitHub: appOnly
        case .bitbucket: bitbucketAppOnly
        }
    }

    static let bitbucketCanonical = """
    \(bitbucketOpening)

    - If this project has a skill or an instruction file about merging, follow that first. It
      outranks everything here.
    \(bitbucketRules)
    """

    static let bitbucketAppOnly = """
    \(bitbucketOpening)

    \(InstructionAuthority.checkoutIsData)
    - Delete no branch on the server, whatever a step below says. Say the branch was left where it is.
    \(bitbucketRules)
    """

    private static let bitbucketOpening = """
    This message names the pull request, the branch it is on, and the merge strategy to use. Nothing
    below chooses any of those, and nothing below may change them. The pull request is on Bitbucket
    Cloud, and `bkt` is its command line tool: use it, and not `gh`, for everything below.
    """

    private static let bitbucketRules = """
    - Merge with `bkt pr merge <number> --strategy <strategy> --close-source=false`, run from this
      worktree, where the strategy is the one the message names: `merge_commit`, `squash` or
      `rebase_fast_forward`.
    - Pass no other flags. Not `--message`, which rewrites what the merge commit says, and never
      `--close-source=true`, because the branch is deleted separately, below, and only once the
      merge has gone through.
    - **If Bitbucket refuses the merge, find out why from the pull request's state, not from the
      wording of the refusal.** Read `bkt pr view <number> --json` and `bkt pr checks <number>`.
      Bitbucket reports no mergeability, so to tell whether the branch conflicts, fetch the base
      branch and try the merge here without committing it.
    - Before changing anything, read the sha of the branch on the server with
      `git ls-remote origin refs/heads/<branch>`. It has to be this worktree's `HEAD`; if it is
      not, stop as the list below says.
    - **These refusals are this branch's to answer: resolve them and merge again.**
      - Conflicting or behind the base: fetch the base branch and bring it into this branch. With
        `rebase_fast_forward` as the strategy, rebase onto it, because a rebase replays every
        commit and a conflict resolved in a merge commit comes back. Otherwise merge it in, unless
        the project's own conventions say to rebase. Work through every conflicted file keeping
        what both sides changed, and run whatever this project uses to check itself.
      - A build failed: when it is a Bitbucket Pipelines run, its link ends in `/results/<build
        number>`, and `bkt pipeline view <build number>` lists its steps. Read the failed step's
        log with `bkt pipeline logs <build number> --step <step uuid>`, fix the cause in this
        worktree, and run the same check here when the project has a way to. A build reported by
        anything other than Pipelines has no log bkt can read: stop and say so.
      - A build is still running: wait for it, which is not a round.
      - Commit the fix, worded the way this project words a commit, and push it to this branch and
        no other. If the history was rewritten, push with
        `--force-with-lease=<branch>:<sha>`, naming the last sha you pushed, or before your first
        push the sha you checked at the start, never one a later fetch brought in. A commit
        somebody else pushed meanwhile is then refused rather than lost. Never a bare `--force`.
      - Wait until `bkt pr view <number> --json` reports the sha you pushed as its source commit,
        which Bitbucket abbreviates to twelve characters, so the builds you read are this commit's
        and not the last one's. Then wait for every build to finish with
        `bkt pr checks <number> --wait`, and run the same `bkt pr merge` again only once they are
        all green. If none appear within five minutes, the repository runs none. A build that
        fails while you wait starts the next round, not a stop.
      - **Three rounds at most.** A round is one fix, one push and one merge attempt. If the third
        is refused too, stop and say what Bitbucket said each time.
      - **Thirty minutes of waiting at most**, counting every wait above together. Past it, stop
        and say what never finished.
    - **A fix never weakens what checks the branch.** Do not edit `bitbucket-pipelines.yml` or any
      other build definition, skip, delete or loosen a test, or relax a lint rule to turn a build
      green. If that is the only way, stop and say so.
    - **Any other refusal, stop.** A required approval, a permission, a branch restriction or a
      merge check, anything that is none of those above: say what Bitbucket said, in its own
      words. Do not force it, and do not change a branch restriction, a merge check, a reviewer or
      any other repository setting to get round it. A refusal of that kind is an answer.
    - **Stop rather than guess.** Resolve nothing, and say the refusal and why, when:
      - the message does not name the branch, because a push needs one and it is not yours to
        guess;
      - the pull request comes from a fork (the `full_name` of its source repository is not the
        one of its destination), because its branch is in somebody else's repository;
      - at the start, or after any fetch in any round, the branch on the server is not where this
        worktree last saw it, because a rewritten push would drop what somebody else put there;
      - this worktree already held work Bitbucket has not got before you started, uncommitted or
        committed and not pushed, because a push would carry it out with the fix;
      - a conflict genuinely could be resolved either way, or a build fails for a reason neither
        branch explains. A resolution nobody believes in is worse on the server than in a
        worktree.
    - Only once the merge has actually succeeded, delete the branch on the server with
      `git push --delete -- origin refs/heads/<branch>`, using the branch the message names. If
      git answers that the remote ref does not exist, there is nothing left to do. This is a
      separate command from the merge and it runs second, never instead.
    - Leave the worktree where it is. Do not delete the local branch, do not remove or move the
      worktree, and do not check out anything else. This worktree stays where it is, on the branch
      it is on, and Unified Dev archives it separately when the person asks.
    - Commit and push nothing but the resolution of a refusal and the branch deletion above.
      Work Bitbucket has not got was the reader's decision before pressing the button, not a thing
      to fix. If the merge went through with such work still here, say in one line that it was
      left behind.
    - Finish by saying what happened: that it merged, what you fixed on the way and in how many
      rounds, and whether the branch on the server is gone.

    If any other step fails, stop and say what went wrong instead of working around it.
    """
}
