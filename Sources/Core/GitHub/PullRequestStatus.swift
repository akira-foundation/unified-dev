import Foundation

public struct PullRequestStatus: Sendable, Hashable {
    public enum Tone: String, Sendable, Hashable, CaseIterable {
        case neutral
        case positive
        case negative
        case warning
        case merged
    }

    public var tone: Tone
    public var text: String
    public var detail: String?
    public var canMerge: Bool
    public var blockedReason: String?
    public var remedy: Remedy

    public enum Remedy: Sendable, Hashable {
        case merge
        case markReadyForReview
        case commitAndPush
        case push
        case fixConflicts
    }

    public init(
        tone: Tone,
        text: String,
        detail: String? = nil,
        canMerge: Bool,
        blockedReason: String? = nil,
        remedy: Remedy = .merge
    ) {
        self.tone = tone
        self.text = text
        self.detail = detail
        self.canMerge = canMerge
        self.blockedReason = blockedReason
        self.remedy = remedy
    }
}

public extension PullRequest {
    var isOpen: Bool { state.caseInsensitiveCompare("OPEN") == .orderedSame }
    var isMerged: Bool { state.caseInsensitiveCompare("MERGED") == .orderedSame }
    var isClosed: Bool { state.caseInsensitiveCompare("CLOSED") == .orderedSame }
    var mergedHead: String? { isMerged ? headCommit : nil }

    var hasConflicts: Bool {
        guard let mergeable = mergeable?.uppercased() else { return false }
        return mergeable == "CONFLICTING" || mergeable == "DIRTY"
    }

    var isMergeabilityUnknown: Bool {
        mergeable?.uppercased() == "UNKNOWN"
    }

    var reviewLabel: String? {
        guard let reviewDecision, !reviewDecision.isEmpty else { return nil }
        return reviewDecision.replacingOccurrences(of: "_", with: " ").capitalized
    }

    func status(local: LocalWork?) -> PullRequestStatus {
        let base = status
        guard let local, local.isAhead, isOpen, !hasConflicts else { return base }

        let remedy: PullRequestStatus.Remedy = local.hasUncommitted ? .commitAndPush : .push
        let localDetail = Self.localDetail(local)

        guard base.tone == .positive else {
            return PullRequestStatus(
                tone: base.tone,
                text: base.text,
                detail: [base.detail, localDetail]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: ", "),
                canMerge: base.canMerge,
                blockedReason: base.blockedReason,
                remedy: remedy
            )
        }

        return PullRequestStatus(
            tone: .warning,
            text: "Local changes",
            detail: localDetail,
            canMerge: base.canMerge,
            blockedReason: base.blockedReason,
            remedy: remedy
        )
    }

    static func localDetail(_ local: LocalWork) -> String {
        var parts: [String] = []
        let files = local.modifiedFiles + local.untrackedFiles
        if files > 0 {
            parts.append("\(files) file\(files == 1 ? "" : "s") to commit")
        }
        if local.hasUnpushed {
            let count = local.unpushedCommits
            parts.append("\(count) commit\(count == 1 ? "" : "s") to push")
        }
        return parts.joined(separator: ", ")
    }

    static let unknownStateHeld = "Bitbucket reports a state Unified Dev does not know for this pull request."

    var forge: ForgeKind { ForgeRepository.kind(ofRemote: url) }

    var hostName: String { forge.displayName }

    var status: PullRequestStatus {
        let decided = hostNeutralStatus
        guard forge == .bitbucket, !isOpen, !isMerged, !isClosed else { return decided }
        var held = decided
        held.canMerge = false
        held.blockedReason = Self.unknownStateHeld
        return held
    }

    private var hostNeutralStatus: PullRequestStatus {
        if isMerged {
            return PullRequestStatus(
                tone: .merged,
                text: "Merged",
                canMerge: false,
                blockedReason: "This pull request is already merged."
            )
        }
        if isClosed {
            return PullRequestStatus(
                tone: .neutral,
                text: "Closed",
                canMerge: false,
                blockedReason: "This pull request was closed without merging."
            )
        }
        if hasConflicts {
            return PullRequestStatus(
                tone: .negative,
                text: "Merge conflicts",
                detail: "This branch conflicts with the base branch",
                canMerge: false,
                blockedReason: "Resolve the conflicts with the base branch first.",
                remedy: .fixConflicts
            )
        }
        if isDraft {
            return PullRequestStatus(
                tone: .neutral,
                text: "Draft",
                detail: checksDetail,
                canMerge: false,
                blockedReason: "This pull request is still a draft.",
                remedy: .markReadyForReview
            )
        }

        return PullRequestStatus(
            tone: openTone,
            text: openHeadline,
            detail: checksDetail,
            canMerge: !isMergeabilityUnknown,
            blockedReason: isMergeabilityUnknown
                ? "\(hostName) is still checking this branch against the base branch."
                : nil
        )
    }

    func mergeConfirmationTitle(base: String) -> String {
        "Merge #\(number) into \(base)?"
    }

    var mergeConfirmationMessage: String {
        "Your agent will merge this pull request in the chat, where you can follow its progress."
    }

    func mergeBranchDeletionMessage(authority: InstructionAuthority) -> String? {
        guard !branch.isEmpty else { return nil }
        switch authority {
        case .project:
            return "After merging, \(branch) will be deleted on \(hostName). Your local branch stays."
        case .appOnly:
            return "After merging, the agent leaves \(branch) on \(hostName), unless the repository deletes merged branches"
                + " itself. Your local branch stays."
        }
    }

    func mergeWarnings(base: String, local: LocalWork? = nil) -> [String] {
        var warnings: [String] = []
        if let local, local.isAhead {
            warnings.append(
                "\(hostName) does not have everything in this worktree: "
                    + Self.localDetail(local)
                    + ". None of that is part of what is merged, and the agent is told to leave it"
                    + " alone rather than commit it first."
            )
        }
        if checks == .failing { warnings.append(checksSummary) }
        if checks == .unavailable {
            warnings.append("Unified Dev could not read this pull request's checks, so it cannot say whether they passed.")
        }
        if hasConflicts { warnings.append("This branch conflicts with \(base).") }
        return warnings
    }

    func mergeConfirmation(
        base: String,
        authority: InstructionAuthority,
        local: LocalWork? = nil
    ) -> String {
        (mergeWarnings(base: base, local: local)
            + [mergeConfirmationMessage]
            + [mergeBranchDeletionMessage(authority: authority)].compactMap { $0 })
            .joined(separator: "\n\n")
    }

    private var openHeadline: String {
        switch checks {
        case .failing: return "Checks failing"
        case .pending: return checksSummary.hasSuffix("queued") ? "Checks queued" : "Checks running"
        case .unavailable: return GitHub.checksUnavailableSummary
        case .passing, .none: break
        }
        if isMergeabilityUnknown { return "Checking for conflicts" }
        switch reviewDecision?.uppercased() {
        case "CHANGES_REQUESTED": return "Changes requested"
        case "REVIEW_REQUIRED": return "Waiting for review"
        default: return "Ready to merge"
        }
    }

    private var checksDetail: String? {
        if checks == .unavailable { return "\(hostName) did not let this token read check runs" }
        guard checks != .none, !checksSummary.isEmpty else { return nil }
        return checksSummary
    }

    private var openTone: PullRequestStatus.Tone {
        switch checks {
        case .failing: return .negative
        case .pending, .unavailable: return .warning
        case .passing, .none: break
        }
        if isMergeabilityUnknown { return .neutral }
        switch reviewDecision?.uppercased() {
        case "CHANGES_REQUESTED", "REVIEW_REQUIRED": return .warning
        default: return .positive
        }
    }
}

public extension GitHub.MergeMethod {
    var label: String {
        switch self {
        case .merge: "Merge commit"
        case .squash: "Squash and merge"
        case .rebase: "Rebase and merge"
        }
    }
}
