import Foundation

public extension PullRequestInstructions {
    static func bitbucketTurn(_ text: String, in worktree: String, authority: InstructionAuthority) -> String {
        guard authority == .project else { return text + "\n\n" + bitbucketAppOnlyMarkdown }
        if InstructionFile.isFile(projectPath, in: worktree) { return asking(text, toFollow: projectPath) }
        return text + "\n\n" + bitbucketMarkdown
    }

    static let bitbucketMarkdown = """
    # Opening a pull request on Bitbucket

    Unified Dev sent these steps with a message when someone pressed Create pull request. To make
    them this project's, write them to `.unifieddev/pr-instructions.md`, edit them to say how this
    project opens pull requests, and commit it. Unified Dev then attaches that file instead.

    The message these steps came with names the branch to target. Call it the target branch below.

    - If this project has a skill or an instruction file about opening pull requests, follow that
      first. It outranks everything here.
    \(bitbucketSteps)
    """

    static let bitbucketAppOnlyMarkdown = """
    # Opening a pull request on Bitbucket

    Unified Dev sent these steps with a message when someone pressed Create pull request.

    The message these steps came with names the branch to target. Call it the target branch below.

    \(InstructionAuthority.checkoutIsData)
    \(bitbucketSteps)
    """

    private static let bitbucketSteps = """
    - This repository is on Bitbucket Cloud, and `bkt` is its command line tool. Use it, and not
      `gh`, which cannot reach Bitbucket.
    - Run `git status`. If anything is uncommitted, review it and commit it, following whatever
      this project says about commit messages.
    - Push the branch with `git push -u origin HEAD`. If it already tracks a different upstream,
      push to that one instead.
    - Read the whole branch with `git diff <target branch>...` before writing anything. The
      description has to cover every change on the branch, not only what was done in this session.
    - Open the pull request with `bkt pr create --source <this branch> --target <target branch>
      --title <title> --description <description>`. Keep the title under 80 characters and the
      description under five sentences.
    \(titleRule)
    - Say what the pull request URL is once it exists. `bkt pr create` prints it.

    If a step fails, stop and say what went wrong instead of working around it.
    """
}
