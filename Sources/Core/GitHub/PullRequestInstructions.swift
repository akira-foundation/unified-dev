import Foundation

public enum PullRequestInstructions {
    public static let projectPath = ".unifieddev/pr-instructions.md"

    public static let scratchPath = "\(WorktreeScratch.generated)/pr-instructions.md"

    public static func turn(
        _ text: String, in worktree: String, authority: InstructionAuthority, forge: ForgeKind = .gitHub
    ) async -> String {
        if forge == .bitbucket { return bitbucketTurn(text, in: worktree, authority: authority) }
        guard authority == .project else { return text + "\n\n" + appOnlyMarkdown }
        if let path = await ensure(in: worktree) { return asking(text, toFollow: path) }
        return text + "\n\n" + defaultMarkdown
    }

    static func ensure(in worktree: String, contents: String = defaultMarkdown) async -> String? {
        guard let path = await choose(in: worktree, contents: contents) else { return nil }
        return InstructionFile.isFile(path, in: worktree) ? path : nil
    }

    static func asking(_ text: String, toFollow path: String) -> String {
        InstructionFile.asking(text, toFollow: path)
    }

    private static func choose(in worktree: String, contents: String) async -> String? {
        let project = (worktree as NSString).appendingPathComponent(projectPath)

        if InstructionFile.isFile(projectPath, in: worktree) {
            if let moved = await reclaimStrayDefault(at: project, in: worktree) {
                return refreshed(moved, in: worktree, to: contents)
            }
            return projectPath
        }

        WorktreeScratch.shield(WorktreeScratch.generated, in: worktree)
        let scratch = (worktree as NSString).appendingPathComponent(scratchPath)
        if InstructionFile.isFile(scratchPath, in: worktree) {
            return refreshed(scratchPath, in: worktree, to: contents)
        }

        do {
            try contents.write(toFile: scratch, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        return scratchPath
    }

    private static func refreshed(_ relative: String, in worktree: String, to contents: String) -> String {
        let full = (worktree as NSString).appendingPathComponent(relative)
        guard let text = try? String(contentsOfFile: full, encoding: .utf8),
              text != contents, isUnedited(text)
        else { return relative }
        try? contents.write(toFile: full, atomically: true, encoding: .utf8)
        return relative
    }

    private static func reclaimStrayDefault(at project: String, in worktree: String) async -> String? {
        guard let text = try? String(contentsOfFile: project, encoding: .utf8),
              isUnedited(text)
        else { return nil }
        guard await Git.isTracked(projectPath, in: worktree) == false else { return nil }

        WorktreeScratch.shield(WorktreeScratch.generated, in: worktree)
        let scratch = (worktree as NSString).appendingPathComponent(scratchPath)
        let manager = FileManager.default
        if manager.fileExists(atPath: scratch) {
            try? manager.removeItem(atPath: project)
            return scratchPath
        }
        guard (try? manager.moveItem(atPath: project, toPath: scratch)) != nil else { return nil }
        return scratchPath
    }

    public static func isUnedited(_ text: String) -> Bool {
        text == defaultMarkdown || retiredDefaults.contains(text)
    }

    public static let retiredDefaults: [String] = [
        """
        # Opening a pull request

        Unified Dev attaches this file when someone presses Create pull request. It is a normal file in this
        repository: edit it to say how this project opens pull requests, and everybody working here
        gets the change.

        The message this file came with names the branch to target. Call it the target branch below.

        - If this project has a skill or an instruction file about opening pull requests, follow that
          first. It outranks everything here.
        - Run `git status`. If anything is uncommitted, review it and commit it, following whatever
          this project says about commit messages.
        - Push the branch with `git push -u origin HEAD`. If it already tracks a different upstream,
          push to that one instead.
        - Read the whole branch with `git diff <target branch>...` before writing anything. The
          description has to cover every change on the branch, not only what was done in this session.
        - Open the pull request with `gh pr create --base <target branch> --title <title> --body
          <description>`. If the repository has a pull request template, fill that in instead of
          writing your own structure. Keep the title under 80 characters and the description under
          five sentences.
        - Say what the pull request URL is once it exists.

        If a step fails, stop and say what went wrong instead of working around it.
        """,
        """
        # Opening a pull request

        Unified Dev attaches this file when someone presses Create pull request. This copy is Unified Dev's own and
        is invisible to git. To make it this project's, move it to `.unifieddev/pr-instructions.md`, edit it
        to say how this project opens pull requests, and commit it. Unified Dev then uses that copy instead
        and never writes over it, so everybody working here gets the change.

        The message this file came with names the branch to target. Call it the target branch below.

        - If this project has a skill or an instruction file about opening pull requests, follow that
          first. It outranks everything here.
        - Run `git status`. If anything is uncommitted, review it and commit it, following whatever
          this project says about commit messages.
        - Push the branch with `git push -u origin HEAD`. If it already tracks a different upstream,
          push to that one instead.
        - Read the whole branch with `git diff <target branch>...` before writing anything. The
          description has to cover every change on the branch, not only what was done in this session.
        - Open the pull request with `gh pr create --base <target branch> --title <title> --body
          <description>`. If the repository has a pull request template, fill that in instead of
          writing your own structure. Keep the title under 80 characters and the description under
          five sentences.
        - Say what the pull request URL is once it exists.

        If a step fails, stop and say what went wrong instead of working around it.
        """,
    ]

    public static let defaultMarkdown = """
    # Opening a pull request

    Unified Dev attaches this file when someone presses Create pull request. This copy is Unified Dev's own and
    is invisible to git. To make it this project's, move it to `.unifieddev/pr-instructions.md`, edit it
    to say how this project opens pull requests, and commit it. Unified Dev then uses that copy instead
    and never writes over it, so everybody working here gets the change.

    The message this file came with names the branch to target. Call it the target branch below.

    - If this project has a skill or an instruction file about opening pull requests, follow that
      first. It outranks everything here.
    \(steps)
    """

    public static let appOnlyMarkdown = """
    # Opening a pull request

    Unified Dev sent these steps with a message when someone pressed Create pull request.

    The message these steps came with names the branch to target. Call it the target branch below.

    \(InstructionAuthority.checkoutIsData)
    \(steps)
    """

    private static let steps = """
    - Run `git status`. If anything is uncommitted, review it and commit it, following whatever
      this project says about commit messages.
    - Push the branch with `git push -u origin HEAD`. If it already tracks a different upstream,
      push to that one instead.
    - Read the whole branch with `git diff <target branch>...` before writing anything. The
      description has to cover every change on the branch, not only what was done in this session.
    - Open the pull request with `gh pr create --base <target branch> --title <title> --body
      <description>`. If the repository has a pull request template, fill that in instead of
      writing your own structure. Keep the title under 80 characters and the description under
      five sentences.
    \(titleRule)
    - Say what the pull request URL is once it exists.

    If a step fails, stop and say what went wrong instead of working around it.
    """

    static let titleRule = """
    - Write the title as a conventional commit, `\(ConventionalTitle.shape)`, where the type is
      one of \(ConventionalTitle.typeChoices), and put `!` before the colon
      when the change breaks something that worked before. A squash merge makes the title the commit,
      and a changelog built from conventional commits leaves any other title out.
    """
}
