import Foundation
import Testing
@testable import Core

@Suite("Workspace status", .tags(.agentProtocol))
struct WorkspaceStatusTests {
    @Test("local state outranks GitHub, apart from unread output", arguments: [
        (
            name: "a running setup script wins over a merged pull request",
            setup: SetupState.running, running: true, unread: true, expected: WorkspaceStatus.settingUp
        ),
        (
            name: "an agent mid turn wins over a failed setup",
            setup: .failed, running: true, unread: true, expected: .running
        ),
        (
            name: "a failed setup wins over unread output",
            setup: .failed, running: false, unread: true, expected: .setupFailed
        ),
        (
            name: "the pull request wins over unread output",
            setup: .succeeded, running: false, unread: true, expected: .merged
        ),
    ])
    func localStateWins(
        name: String, setup: SetupState, running: Bool, unread: Bool, expected: WorkspaceStatus
    ) throws {
        let status = WorkspaceStatus.resolve(
            workspace: workspace(setup: setup, unread: unread, additions: 10),
            isRunning: running,
            pullRequest: try decode(json(state: "MERGED"))
        )
        #expect(status == expected, "\(name)")
    }

    @Test("a pull request decides the mark once the workspace is quiet", arguments: [
        (
            name: "merged",
            json: #"{"number":1,"title":"t","url":"u","state":"MERGED","statusCheckRollup":[]}"#,
            expected: WorkspaceStatus.merged
        ),
        (
            name: "closed without merging",
            json: #"{"number":1,"title":"t","url":"u","state":"CLOSED","statusCheckRollup":[]}"#,
            expected: .closed
        ),
        (
            name: "draft outranks its own green checks",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","isDraft":true,"statusCheckRollup":[{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"SUCCESS"}]}"#,
            expected: .draft
        ),
        (
            name: "a required failure",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","statusCheckRollup":[{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"FAILURE","isRequired":true}]}"#,
            expected: .checksFailing
        ),
        (
            name: "still running",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","statusCheckRollup":[{"__typename":"CheckRun","name":"a","status":"IN_PROGRESS"}]}"#,
            expected: .checksRunning
        ),
        (
            name: "green",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","statusCheckRollup":[{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"SUCCESS"}]}"#,
            expected: .checksPassed
        ),
        (
            name: "open with no checks configured",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","statusCheckRollup":[]}"#,
            expected: .pullRequestOpen
        ),
        (
            name: "a conflict outranks its own green checks",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","mergeable":"CONFLICTING","statusCheckRollup":[{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"SUCCESS"}]}"#,
            expected: .conflicted
        ),
    ])
    func pullRequestDecides(name: String, json: String, expected: WorkspaceStatus) throws {
        let status = WorkspaceStatus.resolve(
            workspace: workspace(additions: 3),
            isRunning: false,
            pullRequest: try decode(json)
        )
        #expect(status == expected, "\(name)")
    }

    @Test("without a pull request the worktree decides")
    func worktreeDecides() {
        let changed = WorkspaceStatus.resolve(
            workspace: workspace(additions: 12, deletions: 1), isRunning: false, pullRequest: nil
        )
        let clean = WorkspaceStatus.resolve(
            workspace: workspace(), isRunning: false, pullRequest: nil
        )
        #expect(changed == .changed)
        #expect(clean == .clean)
    }

    @Test("a missing pull request never turns into a bad one")
    func missingPullRequestIsNotAFailure() {
        for state in [SetupState.succeeded, .skipped, .ignored, .pending] {
            let status = WorkspaceStatus.resolve(
                workspace: workspace(setup: state, additions: 4), isRunning: false, pullRequest: nil
            )
            #expect(status == .changed)
        }
    }

    @Test("every state says what it is, and pull request states carry the number")
    func descriptions() throws {
        for status in WorkspaceStatus.allCases {
            #expect(!status.label.isEmpty)
            guard status != .awaitingPermission else {
                #expect(status.summary(pullRequest: nil) != status.label)
                #expect(status.summary(pullRequest: nil).contains("cannot go on until you answer"))
                continue
            }
            #expect(status.summary(pullRequest: nil) == status.label)
        }

        let pullRequest = try decode(json(
            state: "OPEN",
            checks: #"{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"FAILURE","isRequired":true}"#
        ))
        let summary = WorkspaceStatus.checksFailing.summary(pullRequest: pullRequest)
        #expect(summary.contains("#42"))
        #expect(summary.contains("1 required check failed"))
    }

    @Test("the strip's headline, tone and merge button follow the pull request", arguments: [
        (
            name: "green checks are ready to merge, with the count underneath",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","statusCheckRollup":[{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"SUCCESS"}]}"#,
            tone: PullRequestStatus.Tone.positive,
            text: "Ready to merge", detail: "1 check passed" as String?, canMerge: true
        ),
        (
            name: "an optional failure does not change the headline, only the detail",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","statusCheckRollup":[{"__typename":"StatusContext","context":"preview","state":"FAILURE","isRequired":false}]}"#,
            tone: .positive,
            text: "Ready to merge", detail: "1 optional check failed", canMerge: true
        ),
        (
            name: "a required failure is negative but still mergeable by hand",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","statusCheckRollup":[{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"FAILURE","isRequired":true}]}"#,
            tone: .negative,
            text: "Checks failing", detail: "1 required check failed", canMerge: true
        ),
        (
            name: "a check nobody has picked up is a warning, and says so in both lines",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","statusCheckRollup":[{"__typename":"CheckRun","name":"a","status":"QUEUED"}]}"#,
            tone: .warning,
            text: "Checks queued", detail: "1 check queued", canMerge: true
        ),
        (
            name: "a check a runner has is a warning too, in the other vocabulary",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","statusCheckRollup":[{"__typename":"CheckRun","name":"a","status":"IN_PROGRESS"}]}"#,
            tone: .warning,
            text: "Checks running", detail: "1 check running", canMerge: true
        ),
        (
            name: "changes requested is a warning even with green checks",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","reviewDecision":"CHANGES_REQUESTED","statusCheckRollup":[{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"SUCCESS"}]}"#,
            tone: .warning,
            text: "Changes requested", detail: "1 check passed", canMerge: true
        ),
        (
            name: "a review nobody has done yet is a warning, not a green light",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","reviewDecision":"REVIEW_REQUIRED","statusCheckRollup":[]}"#,
            tone: .warning,
            text: "Waiting for review", detail: nil, canMerge: true
        ),
        (
            name: "a pull request with no checks at all is still ready, and says nothing more",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","statusCheckRollup":[]}"#,
            tone: .positive,
            text: "Ready to merge", detail: nil, canMerge: true
        ),
        (
            name: "a draft cannot be merged",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","isDraft":true,"statusCheckRollup":[]}"#,
            tone: .neutral,
            text: "Draft", detail: nil, canMerge: false
        ),
        (
            name: "conflicts outrank green checks",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","mergeable":"CONFLICTING","statusCheckRollup":[{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"SUCCESS"}]}"#,
            tone: .negative,
            text: "Merge conflicts",
            detail: "This branch conflicts with the base branch", canMerge: false
        ),
        (
            name: "an older gh reports the same conflict as DIRTY",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","mergeStateStatus":"DIRTY","statusCheckRollup":[]}"#,
            tone: .negative,
            text: "Merge conflicts",
            detail: "This branch conflicts with the base branch", canMerge: false
        ),
        (
            name: "a merged pull request is done, not mergeable",
            json: #"{"number":1,"title":"t","url":"u","state":"MERGED","statusCheckRollup":[]}"#,
            tone: .merged, text: "Merged", detail: nil, canMerge: false
        ),
        (
            name: "a closed one is quiet",
            json: #"{"number":1,"title":"t","url":"u","state":"CLOSED","statusCheckRollup":[]}"#,
            tone: .neutral, text: "Closed", detail: nil, canMerge: false
        ),
    ])
    func stripPresentation(
        name: String,
        json: String,
        tone: PullRequestStatus.Tone,
        text: String,
        detail: String?,
        canMerge: Bool
    ) throws {
        let status = try decode(json).status
        #expect(status.tone == tone, "\(name)")
        #expect(status.text == text, "\(name)")
        #expect(status.detail == detail, "\(name)")
        #expect(status.canMerge == canMerge, "\(name)")
    }

    @Test("everything that blocks merging explains itself")
    func blockedReasons() throws {
        let blocked = [
            #"{"number":1,"title":"t","url":"u","state":"OPEN","isDraft":true,"statusCheckRollup":[]}"#,
            #"{"number":1,"title":"t","url":"u","state":"OPEN","mergeable":"CONFLICTING","statusCheckRollup":[]}"#,
            #"{"number":1,"title":"t","url":"u","state":"MERGED","statusCheckRollup":[]}"#,
            #"{"number":1,"title":"t","url":"u","state":"CLOSED","statusCheckRollup":[]}"#,
        ]
        for json in blocked {
            let status = try decode(json).status
            #expect(status.canMerge == false)
            #expect(status.blockedReason?.isEmpty == false)
        }

        let open = try decode(json(state: "OPEN")).status
        #expect(open.canMerge)
        #expect(open.blockedReason == nil)
    }

    @Test("gh reports the branch merging will delete")
    func decodesHeadBranch() throws {
        #expect(try decode(json(state: "OPEN")).branch == "feature/glyphs")
        #expect(try decode(
            #"{"number":1,"title":"t","url":"u","state":"OPEN","statusCheckRollup":[]}"#
        ).branch.isEmpty)
    }

    @Test("the merge confirmation says who is going to do it")
    func mergeConfirmationNamesEverything() throws {
        let pullRequest = try decode(json(
            state: "OPEN",
            checks: #"{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"FAILURE","isRequired":true}"#
        ))

        #expect(pullRequest.mergeConfirmationTitle(base: "main")
            == "Merge #42 into main?")

        let text = pullRequest.mergeConfirmation(base: "main", authority: .project)
        #expect(text.contains("feature/glyphs"))
        #expect(text.contains("1 required check failed"))
        #expect(text.contains("agent"))
        #expect(!text.contains("Unified Dev cannot undo this."))
        #expect(!text.contains("Better glyphs"))
        #expect(!text.contains("Squash and merge"))
    }

    @Test("a clean merge separates the explanation from the branch deletion note")
    func mergeConfirmationIsShort() throws {
        let pullRequest = try decode(json(state: "OPEN"))
        #expect(pullRequest.mergeWarnings(base: "main").isEmpty)
        #expect(pullRequest.mergeConfirmationMessage
            == "Your agent will merge this pull request in the chat, where you can follow its progress.")
        #expect(pullRequest.mergeBranchDeletionMessage(authority: .project)
            == "After merging, feature/glyphs will be deleted on GitHub. Your local branch stays.")
    }

    @Test("a confirmation whose instructions delete no branch says the branch is left as it is")
    func confirmationWithoutBranchDeletion() throws {
        let text = try decode(json(state: "OPEN")).mergeConfirmation(base: "main", authority: .appOnly)
        #expect(!text.contains("deleted on GitHub"))
        #expect(text.contains("agent will merge this pull request in the chat"))
        #expect(try decode(json(state: "OPEN")).mergeBranchDeletionMessage(authority: .appOnly)
            == "After merging, the agent leaves feature/glyphs on GitHub, unless the repository deletes merged"
                + " branches itself. Your local branch stays.")
    }

    @Test("a pull request with no branch is promised nothing about one", arguments: [InstructionAuthority.project, .appOnly])
    func noBranchNoPromise(authority: InstructionAuthority) throws {
        var pullRequest = try decode(json(state: "OPEN"))
        pullRequest.branch = ""
        #expect(pullRequest.mergeBranchDeletionMessage(authority: authority) == nil)
    }

    @Test("a merge whose instructions changed after the confirmation is not sent")
    func changedAuthorityRefusesTheMerge() {
        #expect(InstructionAuthority.mergeRefusal(confirmed: .appOnly, sending: .project)?
            .contains("Nothing was sent") == true)
        #expect(InstructionAuthority.mergeRefusal(confirmed: .project, sending: .appOnly) != nil)
        #expect(InstructionAuthority.mergeRefusal(confirmed: .project, sending: .project) == nil)
        #expect(InstructionAuthority.mergeRefusal(confirmed: .appOnly, sending: .appOnly) == nil)
        #expect(InstructionAuthority.mergeRefusal(confirmed: nil, sending: .project) == nil)
    }

    @Test(
        "a fork or another person's pull request is not promised a deletion",
        arguments: [(true, "ada"), (false, "grace"), (nil, "ada")] as [(Bool?, String)]
    )
    func foreignPullRequestKeepsItsBranch(isFromFork: Bool?, author: String) throws {
        var pullRequest = try decode(json(state: "OPEN"))
        pullRequest.isFromFork = isFromFork
        pullRequest.author = author
        pullRequest.headCommit = "abc123"
        let authority = InstructionAuthority.forPullRequest(
            pullRequest, checkedOutBranch: pullRequest.branch, checkedOutCommit: "abc123", viewer: "ada"
        )
        let text = pullRequest.mergeConfirmation(base: "main", authority: authority)
        #expect(!text.contains("will be deleted"))
        #expect(text.contains("the agent leaves feature/glyphs on GitHub"))
    }

    @Test("the person's own pull request on its checked out head is promised the deletion")
    func ownPullRequestDeletesItsBranch() throws {
        var pullRequest = try decode(json(state: "OPEN"))
        pullRequest.isFromFork = false
        pullRequest.author = "Ada"
        pullRequest.headCommit = "abc123"
        let authority = InstructionAuthority.forPullRequest(
            pullRequest, checkedOutBranch: pullRequest.branch, checkedOutCommit: "abc123", viewer: "ada"
        )
        #expect(pullRequest.mergeConfirmation(base: "main", authority: authority)
            .contains("feature/glyphs will be deleted on GitHub"))
    }

    @Test("every state is classified, and nothing a bare worktree produces reaches for GitHub")
    func pullRequestStatesArePartitioned() throws {
        let fromWorktree: Set<WorkspaceStatus> = [
            WorkspaceStatus.resolve(
                workspace: workspace(setup: .running), isRunning: false, pullRequest: nil
            ),
            WorkspaceStatus.resolve(
                workspace: workspace(), isRunning: false, pullRequest: nil,
                isAwaitingPermission: true
            ),
            WorkspaceStatus.resolve(workspace: workspace(), isRunning: true, pullRequest: nil),
            WorkspaceStatus.resolve(
                workspace: workspace(setup: .failed), isRunning: false, pullRequest: nil
            ),
            WorkspaceStatus.resolve(
                workspace: workspace(unread: true), isRunning: false, pullRequest: nil
            ),
            WorkspaceStatus.ofBranch(workspace: workspace(additions: 3), pullRequest: nil),
            WorkspaceStatus.ofBranch(workspace: workspace(), pullRequest: nil),
        ]
        #expect(fromWorktree.count == 7, "each of the seven is a different state")
        #expect(fromWorktree.allSatisfy { !$0.describesPullRequest })

        let fromGitHub = Set(WorkspaceStatus.allCases.filter(\.describesPullRequest))
        #expect(fromWorktree.union(fromGitHub) == Set(WorkspaceStatus.allCases))
        #expect(fromWorktree.isDisjoint(with: fromGitHub))
    }

    private func decode(_ json: String) throws -> PullRequest {
        try GitHub.decodePullRequest(from: Data(json.utf8))
    }

    private func json(state: String, checks: String = "") -> String {
        """
        {"number":42,"title":"Better glyphs","url":"https://github.com/acme/app/pull/42",
        "state":"\(state)","isDraft":false,"headRefName":"feature/glyphs",
        "statusCheckRollup":[\(checks)]}
        """
    }

    private func workspace(
        setup: SetupState = .succeeded,
        unread: Bool = false,
        additions: Int = 0,
        deletions: Int = 0
    ) -> Workspace {
        Workspace(
            repoID: RepoID("repo"),
            name: "Glyphs",
            branch: "feature/glyphs",
            path: "/tmp/glyphs",
            baseBranch: "main",
            setupState: setup,
            additions: additions,
            deletions: deletions,
            unread: unread
        )
    }
}

@Suite("Merge conflicts", .tags(.agentProtocol))
struct ConflictedStatusTests {
    @Test("where a conflict sits against everything else GitHub reports", arguments: [
        (
            name: "outranks a green rollup",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","mergeable":"CONFLICTING","statusCheckRollup":[{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"SUCCESS"}]}"#,
            expected: WorkspaceStatus.conflicted
        ),
        (
            name: "outranks a failing rollup, which a push could clear and this cannot",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","mergeable":"CONFLICTING","statusCheckRollup":[{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"FAILURE","isRequired":true}]}"#,
            expected: .conflicted
        ),
        (
            name: "outranks checks that have not finished",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","mergeable":"CONFLICTING","statusCheckRollup":[{"__typename":"CheckRun","name":"a","status":"IN_PROGRESS"}]}"#,
            expected: .conflicted
        ),
        (
            name: "outranks the draft flag, because a draft that conflicts still conflicts",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","isDraft":true,"mergeable":"CONFLICTING","statusCheckRollup":[]}"#,
            expected: .conflicted
        ),
        (
            name: "an older gh calls the same thing DIRTY",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","mergeStateStatus":"DIRTY","statusCheckRollup":[]}"#,
            expected: .conflicted
        ),
        (
            name: "merged wins, because the branch it conflicted with is landed",
            json: #"{"number":1,"title":"t","url":"u","state":"MERGED","mergeable":"CONFLICTING","statusCheckRollup":[]}"#,
            expected: .merged
        ),
        (
            name: "closed wins, for the same reason",
            json: #"{"number":1,"title":"t","url":"u","state":"CLOSED","mergeable":"CONFLICTING","statusCheckRollup":[]}"#,
            expected: .closed
        ),
        (
            name: "a pull request gh could not compute a merge for is not a conflicted one",
            json: #"{"number":1,"title":"t","url":"u","state":"OPEN","mergeable":"UNKNOWN","statusCheckRollup":[{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"SUCCESS"}]}"#,
            expected: .checksPassed
        ),
    ])
    func precedence(name: String, json: String, expected: WorkspaceStatus) throws {
        #expect(try mark(json) == expected, "\(name)")
    }

    @Test("the workspace's own state still comes first")
    func localStateStillWins() throws {
        let conflicting = try decode(
            #"{"number":1,"title":"t","url":"u","state":"OPEN","mergeable":"CONFLICTING","statusCheckRollup":[]}"#
        )
        #expect(
            WorkspaceStatus.resolve(
                workspace: workspace(), isRunning: true, pullRequest: conflicting
            ) == .running
        )
        #expect(
            WorkspaceStatus.resolve(
                workspace: workspace(unread: true), isRunning: false, pullRequest: conflicting
            ) == .conflicted
        )
    }

    @Test("unread only decides the mark when there is no pull request")
    func unreadYieldsToThePullRequest() throws {
        let merged = try decode(
            #"{"number":1,"title":"t","url":"u","state":"MERGED","statusCheckRollup":[]}"#
        )
        #expect(
            WorkspaceStatus.resolve(
                workspace: workspace(unread: true), isRunning: false, pullRequest: merged
            ) == .merged
        )
        #expect(
            WorkspaceStatus.resolve(
                workspace: workspace(unread: true), isRunning: false, pullRequest: nil
            ) == .unread
        )
        #expect(
            WorkspaceStatus.resolve(
                workspace: workspace(unread: true), isRunning: false, pullRequest: nil
            ) == .unread
        )
    }

    @Test("the row's mark and the band's headline say the same thing")
    func theTwoPanesAgree() throws {
        let conflicting = try decode(
            #"{"number":1,"title":"t","url":"u","state":"OPEN","mergeable":"CONFLICTING","statusCheckRollup":[{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"SUCCESS"}]}"#
        )
        let mark = WorkspaceStatus.ofBranch(workspace: workspace(), pullRequest: conflicting)

        #expect(mark == .conflicted)
        #expect(mark.label == conflicting.status.text)
        #expect(conflicting.status.remedy == .fixConflicts)
    }

    @Test("it reads as a GitHub state, and its detail is about the conflict")
    func legendAndTooltip() throws {
        #expect(WorkspaceStatus.conflicted.describesPullRequest)
        #expect(WorkspaceStatus.conflicted.label == "Merge conflicts")

        let conflicting = try decode(
            #"{"number":7,"title":"t","url":"u","state":"OPEN","mergeable":"CONFLICTING","statusCheckRollup":[{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"SUCCESS"}]}"#
        )
        let detail = WorkspaceStatus.conflicted.detail(pullRequest: conflicting)
        #expect(detail == "This branch conflicts with the base branch")

        let summary = WorkspaceStatus.conflicted.summary(pullRequest: conflicting)
        #expect(summary == "Merge conflicts, pull request #7: This branch conflicts with the base branch")
    }

    private func mark(_ json: String) throws -> WorkspaceStatus {
        WorkspaceStatus.resolve(
            workspace: workspace(), isRunning: false, pullRequest: try decode(json)
        )
    }

    private func decode(_ json: String) throws -> PullRequest {
        try GitHub.decodePullRequest(from: Data(json.utf8))
    }

    private func workspace(unread: Bool = false) -> Workspace {
        Workspace(
            repoID: RepoID("repo"),
            name: "Glyphs",
            branch: "feature/glyphs",
            path: "/tmp/glyphs",
            baseBranch: "main",
            setupState: .succeeded,
            additions: 3,
            unread: unread
        )
    }
}

@Suite("Waiting on you")
struct AwaitingPermissionStatusTests {
    private func workspace(unread: Bool = false, additions: Int = 0) -> Workspace {
        Workspace(
            repoID: RepoID("r"), name: "w", branch: "b", path: "/tmp/w", baseBranch: "main",
            setupState: .succeeded, additions: additions, unread: unread
        )
    }

    @Test("waiting outranks running")
    func outranksRunning() {
        let status = WorkspaceStatus.resolve(
            workspace: workspace(unread: true, additions: 9),
            isRunning: true,
            pullRequest: nil,
            isAwaitingPermission: true
        )

        #expect(status == .awaitingPermission)
        #expect(status.needsAnswer)
    }

    @Test("a workspace still setting up says so first")
    func setupWinsOverWaiting() {
        var setting = workspace()
        setting.apply(.runStarted)
        let status = WorkspaceStatus.resolve(
            workspace: setting, isRunning: true, pullRequest: nil, isAwaitingPermission: true
        )

        #expect(status == .settingUp)
    }

    @Test("nothing changes for a workspace nobody is waiting on")
    func defaultsToFalse() {
        let workspace = workspace(additions: 3)

        #expect(WorkspaceStatus.resolve(workspace: workspace, isRunning: false, pullRequest: nil) == .changed)
        #expect(WorkspaceStatus.resolve(workspace: workspace, isRunning: true, pullRequest: nil) == .running)
    }

    @Test("only the waiting state asks for an answer")
    func onlyOneStateNeedsAnswering() {
        #expect(WorkspaceStatus.allCases.filter(\.needsAnswer) == [.awaitingPermission])
    }

    @Test("the dock badge counts waiting ahead of unread, and never sums them")
    func dockBadge() {
        #expect(DockBadge.label(unread: 4, waiting: 2, isEnabled: true) == "2")
        #expect(DockBadge.label(unread: 4, waiting: 0, isEnabled: true) == "4")
        #expect(DockBadge.label(unread: 0, waiting: 3, isEnabled: true) == "3")
        #expect(DockBadge.label(unread: 4, waiting: 2, isEnabled: true) != "6")
        #expect(DockBadge.label(unread: 0, waiting: 0, isEnabled: true) == nil)
        #expect(DockBadge.label(unread: 4, waiting: 2, isEnabled: false) == nil)
    }

    @Test("the badge counts workspaces, not questions")
    func waitingCount() {
        let blocked = workspace()
        let working = workspace()
        let count = DockBadge.waitingCount(in: [blocked, working, working]) { $0.id == blocked.id }

        #expect(count == 1)
    }

    @Test("the menu bar puts waiting ahead of unread")
    func menuBar() {
        let segments = MenuBarSummary.segments(waiting: 2, unread: 1)

        #expect(segments.map(\.count) == [2, 1])
        #expect(segments.first?.symbolName == MenuBarSummary.waitingSymbol)
        #expect(segments.first?.label == "Agents waiting on you")
    }

    @Test("nothing waiting leaves the unread count on its own")
    func menuBarUnchanged() {
        #expect(MenuBarSummary.segments(waiting: 0, unread: 1)
            == [MenuBarSummary.Segment(
                symbolName: MenuBarSummary.unreadSymbol, count: 1, label: "Unread results"
            )])
        #expect(MenuBarSummary.tooltip(waiting: 0, unread: 1) == "1 unread result")
    }

    @Test("the tooltip says it in words, singular and plural")
    func tooltip() {
        #expect(MenuBarSummary.tooltip(waiting: 1, unread: 0) == "1 agent waiting on you")
        #expect(MenuBarSummary.tooltip(waiting: 2, unread: 0) == "2 agents waiting on you")
        #expect(MenuBarSummary.tooltip(waiting: 2, unread: 1)
            == "2 agents waiting on you, 1 unread result")
    }
}
