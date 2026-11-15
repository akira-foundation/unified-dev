import Foundation

public enum PromptID: String, Sendable, Hashable, CaseIterable, Codable {
    case createPullRequest
    case pushLocalWork
    case mergePullRequest
    case markReadyForReview
    case fixConflicts
    case continueAfterMerge
    case carryOnArchived
    case review
    case nameWorkspace
}

public struct PromptVariable: Sendable, Hashable, Identifiable {
    public let name: String
    public let summary: String

    public var id: String { name }
    public var token: String { PromptTemplate.token(name) }

    public init(name: String, summary: String) {
        self.name = name
        self.summary = summary
    }
}

public struct PromptDefinition: Sendable, Hashable, Identifiable {
    public let id: PromptID
    public let title: String
    public let summary: String
    public let variables: [PromptVariable]
    public let defaultTemplate: String

    public init(
        id: PromptID,
        title: String,
        summary: String,
        variables: [PromptVariable],
        defaultTemplate: String
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.variables = variables
        self.defaultTemplate = defaultTemplate
    }
}

public enum PromptRegistry {
    public static let all: [PromptDefinition] = [
        createPullRequest, pushLocalWork, mergePullRequest, markReadyForReview, fixConflicts, continueAfterMerge,
        carryOnArchived, review, nameWorkspace,
    ]

    public static func definition(for id: PromptID) -> PromptDefinition {
        all.first { $0.id == id } ?? createPullRequest
    }

    public enum CreatePullRequest {
        public static let workspace = "workspace"
        public static let branch = "branch"
        public static let baseBranch = "base_branch"
        public static let task = "task"
        public static let changes = "changes"
    }

    public enum PushLocalWork {
        public static let workspace = "workspace"
        public static let branch = "branch"
        public static let baseBranch = "base_branch"
        public static let changes = "changes"
    }

    public enum MarkReadyForReview {
        public static let url = "url"
    }

    static let markReadyForReview = PromptDefinition(
        id: .markReadyForReview,
        title: "Mark ready for review",
        summary: "Sent when you press Mark ready for review on a draft pull request.",
        variables: [
            PromptVariable(name: MarkReadyForReview.url, summary: "The pull request's URL."),
        ],
        defaultTemplate: """
        Mark pull request {{url}} ready for review on GitHub using `gh pr ready`, then verify its \
        draft status is cleared. If GitHub refuses, explain why. Do not merge the pull request, \
        commit or push changes, or start any other work.
        """
    )

    public enum MergePullRequest {
        public static let workspace = "workspace"
        public static let number = "number"
        public static let title = "title"
        public static let branch = "branch"
        public static let baseBranch = "base_branch"
        public static let method = "method"
        public static let methodFlag = "method_flag"
    }

    public enum FixConflicts {
        public static let workspace = "workspace"
        public static let number = "number"
        public static let branch = "branch"
        public static let baseBranch = "base_branch"
    }

    public enum ContinueAfterMerge {
        public static let workspace = "workspace"
        public static let branch = "branch"
        public static let previousBranch = "previous_branch"
        public static let baseBranch = "base_branch"
        public static let pullRequest = "pull_request"
    }

    public enum CarryOnArchived {
        public static let workspace = "workspace"
        public static let project = "project"
        public static let previousBranch = "previous_branch"
        public static let previousPath = "previous_path"
        public static let branch = "branch"
        public static let baseBranch = "base_branch"
    }

    public enum NameWorkspace {
        public static let task = "task"
        public static let project = "project"
    }

    public enum Review {
        public static let message = "message"
        public static let comments = "comments"
        public static let count = "count"
    }

    static let createPullRequest = PromptDefinition(
        id: .createPullRequest,
        title: "Create pull request",
        summary: """
        Sent when you press Create pull request, with the project's `.unifieddev/pr-instructions.md` \
        attached when the branch is confirmed as the owner's.
        """,
        variables: [
            PromptVariable(name: CreatePullRequest.workspace, summary: "The workspace's name."),
            PromptVariable(name: CreatePullRequest.branch, summary: "The branch the work is on."),
            PromptVariable(
                name: CreatePullRequest.baseBranch,
                summary: "The branch the pull request targets."
            ),
            PromptVariable(
                name: CreatePullRequest.task,
                summary: "The first thing you asked this workspace for."
            ),
            PromptVariable(
                name: CreatePullRequest.changes,
                summary: "The changed files, with their added and removed line counts."
            ),
        ],
        defaultTemplate: """
        Create a pull request for this workspace against {{base_branch}}.
        """
    )

    static let pushLocalWork = PromptDefinition(
        id: .pushLocalWork,
        title: "Commit and push",
        summary: """
        Sent when you press Commit and push in the pull request strip. The agent writes the \
        commit message, not Unified Dev.
        """,
        variables: [
            PromptVariable(name: PushLocalWork.workspace, summary: "The workspace's name."),
            PromptVariable(name: PushLocalWork.branch, summary: "The branch the work is on."),
            PromptVariable(
                name: PushLocalWork.baseBranch,
                summary: "The branch the pull request targets."
            ),
            PromptVariable(
                name: PushLocalWork.changes,
                summary: "The changed files, with their added and removed line counts."
            ),
        ],
        defaultTemplate: """
        Commit everything outstanding in this worktree, with a message that describes the change \
        the way this project words one, then push {{branch}} so its pull request reflects what is \
        here. If there is nothing to commit, just push.
        """
    )

    static let continueAfterMerge = PromptDefinition(
        id: .continueAfterMerge,
        title: "Continue after a merge",
        summary: """
        Sent when you press Continue on a merged pull request, after the worktree has already \
        moved to a new branch. It only says what moved.
        """,
        variables: [
            PromptVariable(name: ContinueAfterMerge.workspace, summary: "The workspace's name."),
            PromptVariable(
                name: ContinueAfterMerge.branch,
                summary: "The new branch this worktree is on now."
            ),
            PromptVariable(
                name: ContinueAfterMerge.previousBranch,
                summary: "The branch that was merged."
            ),
            PromptVariable(
                name: ContinueAfterMerge.baseBranch,
                summary: "The branch the new one was cut from."
            ),
            PromptVariable(
                name: ContinueAfterMerge.pullRequest,
                summary: "The number of the pull request that landed."
            ),
        ],
        defaultTemplate: """
        Pull request #{{pull_request}} is merged, so {{previous_branch}} is finished with.

        This worktree is now on a new branch, {{branch}}, cut from an up to date \
        {{base_branch}}, so everything that just landed is already underneath you. Nothing else \
        moved: same directory, same session, and anything that was uncommitted is still here.

        Do not redo what the pull request landed, and do not start anything new yet. Say in one \
        line that you are ready, then wait for what I ask next.
        """
    )

    static let mergePullRequest = PromptDefinition(
        id: .mergePullRequest,
        title: "Merge a pull request",
        summary: """
        Sent when you confirm Merge, with Unified Dev's own merge steps under it and the project's own \
        instructions attached when it has any and the branch is confirmed as the owner's. The agent runs `gh pr merge`, or \
        `bkt pr merge` on Bitbucket, in front of you, not Unified Dev. When the host refuses for a conflict or a failed \
        check, it fixes that, pushes to the pull request's branch and merges again, three times at most.
        """,
        variables: [
            PromptVariable(name: MergePullRequest.workspace, summary: "The workspace's name."),
            PromptVariable(name: MergePullRequest.number, summary: "The pull request's number."),
            PromptVariable(name: MergePullRequest.title, summary: "The pull request's title."),
            PromptVariable(name: MergePullRequest.branch, summary: "The branch it is on."),
            PromptVariable(
                name: MergePullRequest.baseBranch,
                summary: "The branch it is merged into."
            ),
            PromptVariable(
                name: MergePullRequest.method,
                summary: "The method you chose, in words: squash merge, merge commit, rebase merge."
            ),
            PromptVariable(
                name: MergePullRequest.methodFlag,
                summary: "The same method as the flag that performs it: --squash for gh, --strategy squash for bkt."
            ),
        ],
        defaultTemplate: """
        Merge pull request #{{number}} into {{base_branch}} as a {{method}}, which is \
        `{{method_flag}}`. It is on the branch {{branch}}.
        """
    )

    static let fixConflicts = PromptDefinition(
        id: .fixConflicts,
        title: "Fix merge conflicts",
        summary: """
        Sent when you press Fix merge conflicts, with Unified Dev's own steps attached. It \
        resolves against the base branch here and pushes the result; it never merges the pull \
        request.
        """,
        variables: [
            PromptVariable(name: FixConflicts.workspace, summary: "The workspace's name."),
            PromptVariable(name: FixConflicts.number, summary: "The pull request's number."),
            PromptVariable(
                name: FixConflicts.branch,
                summary: "The branch the conflicts are resolved on, which is this worktree's."
            ),
            PromptVariable(
                name: FixConflicts.baseBranch,
                summary: "The branch that conflicts with it, and that is brought in."
            ),
        ],
        defaultTemplate: """
        Pull request #{{number}} conflicts with {{base_branch}}, so GitHub will not merge it as it \
        stands. Resolve that here, in this worktree, on {{branch}}: bring {{base_branch}} into this \
        branch, work through the conflicts, commit, and push {{branch}}, so the conflict is gone \
        for everybody rather than only here.

        Do not merge the pull request.
        """
    )

    static let carryOnArchived = PromptDefinition(
        id: .carryOnArchived,
        title: "Carry on from an archive",
        summary: """
        Sent when you press Carry On in an archived workspace, into a new worktree, resuming that \
        workspace's conversation. It only says what moved.
        """,
        variables: [
            PromptVariable(
                name: CarryOnArchived.workspace,
                summary: "The archived workspace's name, which the new one keeps."
            ),
            PromptVariable(name: CarryOnArchived.project, summary: "The project it belongs to."),
            PromptVariable(
                name: CarryOnArchived.previousBranch,
                summary: "The branch the archived workspace was on, which no longer exists."
            ),
            PromptVariable(
                name: CarryOnArchived.previousPath,
                summary: "The worktree the archive removed."
            ),
            PromptVariable(
                name: CarryOnArchived.branch,
                summary: "The branch the new worktree is on."
            ),
            PromptVariable(
                name: CarryOnArchived.baseBranch,
                summary: "The branch the new one was cut from."
            ),
        ],
        defaultTemplate: """
        We are carrying on somewhere else. The workspace this conversation was in, \
        {{workspace}}, has been archived: its worktree at {{previous_path}} was deleted, and \
        {{previous_branch}} is gone from this Mac and from the remote, so there was nothing left \
        to rebuild it from.

        You are in a new worktree now, on a fresh branch {{branch}} cut from an up \
        to date {{base_branch}} in {{project}}. Everything we said to each other is still yours, \
        and none of the files are: every path you remember is stale, so read anything here before \
        you rely on it, and expect work that landed on {{base_branch}} to already be underneath \
        you.

        Do not redo what the old branch held, and do not start anything new yet. Say in one or \
        two lines where we had got to and what was left, which is the only record of it this \
        chat has, then wait for what I ask next.
        """
    )

    static let review = PromptDefinition(
        id: .review,
        title: "Send review comments",
        summary: """
        Sent when you send the inline comments you left on the diff.
        """,
        variables: [
            PromptVariable(
                name: Review.message,
                summary: "What you typed in the composer alongside the comments."
            ),
            PromptVariable(
                name: Review.comments,
                summary: "Every attached comment, with its file, line and surrounding code."
            ),
            PromptVariable(name: Review.count, summary: "How many comments are attached."),
        ],
        defaultTemplate: """
        {{message}}

        I reviewed the diff and left {{count}} inline comment(s). Each one below names the file it \
        is about, the line it points at, and the code around that line, with the commented line \
        marked `>`.

        Work through them in order. Read the surrounding code before you change anything, because \
        a comment is about the line it points at and not about the whole file. Where a comment \
        says the line has moved or is gone, find what it is actually about before acting on it, \
        and tell me if you cannot. If you disagree with one, say so instead of changing the code.

        {{comments}}
        """
    )

    static let nameWorkspace = PromptDefinition(
        id: .nameWorkspace,
        title: "Name a new workspace",
        summary: """
        Sent a moment after a workspace is created, to turn what you asked for into a name and a \
        branch.
        """,
        variables: [
            PromptVariable(
                name: NameWorkspace.task,
                summary: "The first thing you asked this workspace for."
            ),
            PromptVariable(name: NameWorkspace.project, summary: "The project it was created in."),
        ],
        defaultTemplate: """
        Name this coding task, for a workspace sitting in a list beside twenty others.

        Project: {{project}}

        Answer at once, without deliberating.

        - name: at most five words, sentence case, no full stop, no quotes. Say what the work is, \
        in the words someone would use out loud. Never start it with "Task" or "Workspace".
        - branch: lowercase, words joined by hyphens, at most four words, letters, digits and \
        hyphens only, no slashes and no prefix.

        ## Task

        {{task}}
        """
    )
}
