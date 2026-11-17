import SwiftUI
import Core

struct PullRequestBarGallery: View {
    let app: AppModel

    private static let branch = "feat/213-pull-request-bar-path"
    private static let base = "main"
    private static let widths: [CGFloat] = [Metrics.inspectorWidth, Metrics.inspectorMinimum]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(Self.cases.enumerated()), id: \.offset) { entry in
                    Case(title: entry.element.0, standing: entry.element.1)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(app)
    }

    private struct Case: View {
        let title: String
        let standing: PullRequestStanding

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Typo.label).foregroundStyle(Palette.textSecondary)
                HStack(alignment: .top, spacing: 12) {
                    ForEach(PullRequestBarGallery.widths, id: \.self) { width in
                        Measured(standing: standing, width: width)
                    }
                }
            }
        }
    }

    private struct Measured: View {
        let standing: PullRequestStanding
        let width: CGFloat

        @State private var height: CGFloat = 0

        private var measured: String { String(format: "%.1f", height) }

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                PullRequestBarContent(
                    standing: standing,
                    branchActions: .allowed,
                    isWorking: false,
                    mergeMethod: .squash,
                    canMerge: standing.reach(of: .merge) != nil,
                    worktree: "/tmp/unifieddev-snapshot/bar",
                    onChooseMergeMethod: { _ in },
                    onAct: { _ in },
                    onReach: { _ in }
                )
                .frame(width: width)
                .background(Palette.surface)
                .overlay(alignment: .top) { Hairline() }
                .overlay(alignment: .bottom) { Hairline() }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }

                Text(verbatim: "\(Int(width)) pt wide, \(measured) pt tall")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private static func pullRequest(
        state: String = "OPEN",
        isDraft: Bool = false,
        mergeable: String? = "MERGEABLE",
        checks: PullRequest.Checks = .none,
        checksSummary: String = ""
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
            branch: branch
        )
    }

    private static func standing(
        _ pullRequest: PullRequest?,
        ahead: Int = 3,
        localWork: LocalWork? = nil,
        hasRemote: Bool = true,
        branch: String = branch,
        checkRuns: [CheckRun] = []
    ) -> PullRequestStanding {
        PullRequestStanding.of(
            branch: branch,
            baseBranch: base,
            ahead: ahead,
            pullRequest: pullRequest,
            localWork: localWork,
            hasRemote: hasRemote,
            checkRuns: checkRuns
        )
    }

    private static var reviewed: PullRequest {
        var asked = pullRequest(checks: .passing, checksSummary: "12 checks passed")
        asked.reviewDecision = "CHANGES_REQUESTED"
        return asked
    }

    private static var cases: [(String, PullRequestStanding)] {
        [
            ("No pull request yet", standing(nil)),
            (
                "No pull request, and a branch name longer than the column",
                standing(nil, branch: "akira/feat/213-the-pull-request-bar-announces-where-the-work-stands")
            ),
            ("Nothing on the branch yet", standing(nil, ahead: 0)),
            ("No remote to push to", standing(nil, hasRemote: false)),
            ("Draft", standing(pullRequest(isDraft: true))),
            (
                "Work GitHub does not have",
                standing(
                    pullRequest(checks: .passing, checksSummary: "12 checks passed"),
                    localWork: LocalWork(modifiedFiles: 2, unpushedCommits: 1)
                )
            ),
            (
                "Checks running",
                standing(pullRequest(checks: .pending, checksSummary: "3 of 12 checks running"))
            ),
            (
                "One job running, one queued",
                standing(
                    pullRequest(checks: .pending, checksSummary: "1 check running"),
                    checkRuns: [CheckRun(name: "test", status: "IN_PROGRESS"), CheckRun(name: "lint", status: "QUEUED")]
                )
            ),
            (
                "Several jobs running",
                standing(
                    pullRequest(checks: .pending, checksSummary: "5 checks running"),
                    checkRuns: ["house rules", "build", "core suite", "browser scripts", "swiftlint"]
                        .map { CheckRun(name: $0, status: "IN_PROGRESS") }
                )
            ),
            (
                "Nothing started yet",
                standing(
                    pullRequest(checks: .pending, checksSummary: "2 checks queued"),
                    checkRuns: [CheckRun(name: "lint", status: "QUEUED"), CheckRun(name: "test", status: "QUEUED")]
                )
            ),
            (
                "A check failed",
                standing(pullRequest(checks: .failing, checksSummary: "1 of 12 checks failed"))
            ),
            ("Conflicting with the base branch", standing(pullRequest(mergeable: "CONFLICTING"))),
            (
                "Ready to merge",
                standing(pullRequest(checks: .passing, checksSummary: "12 checks passed"))
            ),
            ("Checks the token cannot read", standing(pullRequest(checks: .unavailable))),
            ("Changes requested", standing(reviewed)),
            ("Merged", standing(pullRequest(state: "MERGED"))),
            ("Closed without merging", standing(pullRequest(state: "CLOSED"))),
        ]
    }
}

extension Gallery {
    static let pullRequestBar = Gallery(
        name: "pull-request-bar",
        title: "Pull request bar",
        size: CGSize(width: 760, height: 1_600),
        needsFocus: false,
        view: { app in AnyView(PullRequestBarGallery(app: app)) }
    )
}
