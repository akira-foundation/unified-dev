import Foundation

public extension PullRequestStanding {
    static func of(
        branch: String,
        baseBranch: String,
        ahead: Int = 0,
        aheadIsCapped: Bool = false,
        hasUnreadCommitCount: Bool = false,
        pullRequest: PullRequest?,
        localWork: LocalWork? = nil,
        hasRemote: Bool = true,
        continued: ContinuedBranch? = nil,
        checkRuns: [CheckRun] = []
    ) -> PullRequestStanding {
        let count = aheadSentence(ahead, base: baseBranch, isCapped: aheadIsCapped)

        guard hasRemote else {
            return PullRequestStanding(
                headline: branch,
                secondary: [count, "no remote to push to"].compactMap { $0 }.joined(separator: ", "),
                sentence: "This project has no remote, so there is nowhere to push \(branch) and no"
                    + " pull request to open."
            )
        }

        guard let pullRequest else {
            return withoutPullRequest(
                branch: branch,
                baseBranch: baseBranch,
                count: count,
                hasWork: ahead > 0 || hasUnreadCommitCount || localWork?.hasUncommitted == true,
                continued: continued
            )
        }

        let target = pullRequest.targetBranch(or: baseBranch)
        if pullRequest.isMerged { return merged(pullRequest, baseBranch: target) }
        if pullRequest.isClosed { return closed(pullRequest) }

        return open(pullRequest, baseBranch: target, localWork: localWork, checkRuns: checkRuns)
    }

    private static func withoutPullRequest(
        branch: String,
        baseBranch: String,
        count: String?,
        hasWork: Bool,
        continued: ContinuedBranch?
    ) -> PullRequestStanding {
        let quiet = ContinuedBranch.line(on: branch, continued: continued)
        return PullRequestStanding(
            headline: branch,
            secondary: hasWork
                ? [count, "no pull request yet"].compactMap { $0 }.joined(separator: ", ")
                : quiet,
            state: "No pull request yet",
            tone: hasWork ? .accent : .quiet,
            button: hasWork
                ? Button(
                    act: .openPullRequest,
                    sentence: "Ask this workspace's agent to push \(branch) and open a pull request"
                        + " against \(baseBranch), following this project's pull request instructions."
                        + " \(sentWithoutABubble)"
                )
                : nil,
            current: .commits,
            path: PullRequestStep.whole,
            links: [diffLink],
            sentence: hasWork
                ? "\(branch) has work \(baseBranch) does not, and no pull request yet."
                : quiet
        )
    }

    private static func merged(
        _ pullRequest: PullRequest, baseBranch: String
    ) -> PullRequestStanding {
        PullRequestStanding(
            headline: pullRequest.title,
            secondary: "Merged into \(baseBranch)",
            number: pullRequest.number,
            url: pullRequest.url,
            state: "Merged",
            tone: .merged,
            button: Button(
                act: .archive,
                sentence: "Remove this workspace's worktree. #\(pullRequest.number) is merged into"
                    + " \(baseBranch), so this asks first only when something here exists nowhere else."
            ),
            sentence: "#\(pullRequest.number) \(pullRequest.title) is merged into \(baseBranch)."
        )
    }

    private static func closed(_ pullRequest: PullRequest) -> PullRequestStanding {
        PullRequestStanding(
            headline: pullRequest.title,
            secondary: "Closed without merging",
            number: pullRequest.number,
            url: pullRequest.url,
            state: "Closed",
            current: .pullRequest,
            path: PullRequestStep.whole,
            links: [diffLink, page(pullRequest)],
            sentence: "#\(pullRequest.number) \(pullRequest.title) was closed without merging."
        )
    }

    private static func open(
        _ pullRequest: PullRequest,
        baseBranch: String,
        localWork: LocalWork?,
        checkRuns: [CheckRun]
    ) -> PullRequestStanding {
        let status = pullRequest.status(local: localWork)
        let act = act(for: status.remedy, checks: pullRequest.checks)

        var links = [diffLink, page(pullRequest)]
        if InspectorTab.hasChecks(pullRequest) { links.append(checksLink) }
        if status.canMerge, pullRequest.checks != .failing { links.append(mergeLink) }

        return PullRequestStanding(
            headline: pullRequest.title,
            secondary: secondary(status, pullRequest, baseBranch: baseBranch, checkRuns: checkRuns),
            number: pullRequest.number,
            url: pullRequest.url,
            state: status.text,
            tone: tone(status, checks: pullRequest.checks, isDraft: pullRequest.isDraft),
            button: act.map {
                Button(
                    act: $0,
                    sentence: $0 == .merge
                        ? status.blockedReason ?? sentence(for: $0, pullRequest, baseBranch: baseBranch)
                        : sentence(for: $0, pullRequest, baseBranch: baseBranch)
                )
            },
            current: step(for: status.remedy, checks: pullRequest.checks),
            path: PullRequestStep.whole,
            links: links,
            sentence: [
                "#\(pullRequest.number) \(pullRequest.title)",
                status.text,
                status.detail,
                status.blockedReason,
            ].compactMap { $0 }.joined(separator: "\n")
        )
    }

    private static func secondary(
        _ status: PullRequestStatus, _ pullRequest: PullRequest, baseBranch: String, checkRuns: [CheckRun]
    ) -> String {
        if pullRequest.hasConflicts { return "This branch conflicts with \(baseBranch)" }

        let detail = status.detail.flatMap { $0.isEmpty ? nil : $0 }
        let inFlight = pullRequest.checks == .pending ? ChecksInFlight.line(checkRuns) : nil
        switch status.remedy {
        case .push, .commitAndPush:
            return detail ?? status.text
        case .markReadyForReview:
            return ["Draft", inFlight ?? detail].compactMap { $0 }.joined(separator: ", ")
        case .fixConflicts, .merge:
            break
        }

        switch pullRequest.checks {
        case .pending:
            return inFlight ?? detail ?? status.text
        case .failing, .unavailable:
            return detail ?? status.text
        case .passing, .none:
            return [detail, status.text == "Ready to merge"
                ? "ready to merge into \(baseBranch)"
                : status.text.lowercased()]
                .compactMap { $0 }
                .joined(separator: ", ")
        }
    }

    private static func step(
        for remedy: PullRequestStatus.Remedy, checks: PullRequest.Checks
    ) -> PullRequestStep {
        switch remedy {
        case .fixConflicts: .merge
        case .push, .commitAndPush: .commits
        case .markReadyForReview: .pullRequest
        case .merge: checks == .passing || checks == .none ? .merge : .checks
        }
    }

    private static func tone(
        _ status: PullRequestStatus, checks: PullRequest.Checks, isDraft: Bool
    ) -> Tone {
        if checks == .failing { return .danger }
        if status.remedy == .fixConflicts { return .warning }
        if checks == .unavailable { return .warning }
        if isDraft { return .quiet }
        if checks == .pending { return .accent }

        switch status.tone {
        case .negative: return .danger
        case .warning: return status.remedy == .merge ? .warning : .accent
        case .positive: return status.canMerge ? .positive : .accent
        case .neutral, .merged: return .accent
        }
    }

    internal static func act(
        for remedy: PullRequestStatus.Remedy, checks: PullRequest.Checks
    ) -> Act? {
        switch remedy {
        case .fixConflicts: .askToFixConflicts
        case .push: .push
        case .commitAndPush: .commitAndPush
        case .markReadyForReview: .markReadyForReview
        case .merge: checks == .failing ? .askToFixChecks : .merge
        }
    }

    static let sentWithoutABubble =
        "The request goes as soon as you click and does not appear in the conversation."

    private static func sentence(
        for act: Act, _ pullRequest: PullRequest, baseBranch: String
    ) -> String {
        let number = pullRequest.number
        let branch = pullRequest.branch.isEmpty ? "this branch" : pullRequest.branch
        switch act {
        case .askToFixConflicts:
            return "Ask this workspace's agent to bring \(baseBranch) into this worktree, resolve the"
                + " conflicts here and push \(branch). \(sentWithoutABubble) #\(number) is not merged."
        case .askToFixChecks:
            return "Ask this workspace's agent, with the failing check's log, to fix what #\(number)"
                + " broke and push the fix to \(branch). \(sentWithoutABubble) #\(number) is not merged."
        case .push, .commitAndPush:
            let what = act == .push ? "push" : "commit what is here and push"
            return "Ask this workspace's agent to \(what) on \(branch), so #\(number) is what is on"
                + " this disk. \(sentWithoutABubble)"
        case .markReadyForReview:
            return "Ask this workspace's agent to mark #\(number) ready for review on \(pullRequest.hostName)."
                + " \(sentWithoutABubble)"
        case .merge:
            return "Merge #\(number) into \(baseBranch), or choose another method from the chevron."
                + " Once you confirm, the request goes without appearing in the conversation."
        case .openPullRequest:
            return "Ask this workspace's agent to open a pull request for #\(number). \(sentWithoutABubble)"
        case .archive:
            return "Remove this workspace's worktree."
        }
    }

    private static var diffLink: PullRequestStepLink {
        PullRequestStepLink(
            step: .commits, reach: .diff, announcement: "Opens the diff for this branch"
        )
    }

    private static func page(_ pullRequest: PullRequest) -> PullRequestStepLink {
        PullRequestStepLink(
            step: .pullRequest,
            reach: .pullRequestPage(pullRequest.url),
            announcement: "Opens #\(pullRequest.number) on \(pullRequest.hostName)"
        )
    }

    private static var checksLink: PullRequestStepLink {
        PullRequestStepLink(
            step: .checks, reach: .checks, announcement: "Opens this pull request's checks"
        )
    }

    private static var mergeLink: PullRequestStepLink {
        PullRequestStepLink(
            step: .merge, reach: .merge, announcement: "Opens the merge, where you choose how it lands"
        )
    }
}
