import Foundation

public enum StartingPointSuggestion: Sendable, Hashable, Identifiable {
    case reviewRequested(PullRequestListing)
    case authored(PullRequestListing)
    case issue(AssignedIssue)
    case branch(RecentBranch)

    public var id: String {
        switch self {
        case .reviewRequested(let request), .authored(let request): "pr:\(request.number)"
        case .issue(let issue): "issue:\(issue.number)"
        case .branch(let branch): "branch:\(branch.name)"
        }
    }

    public var glyph: String {
        StartingPointLabel.glyph(for: pick(defaultBranch: "").startingPoint)
    }

    public var title: String {
        switch self {
        case .reviewRequested(let request), .authored(let request): request.title.isEmpty ? request.qualifiedHead : request.title
        case .issue(let issue): issue.title.isEmpty ? "Issue #\(issue.number)" : issue.title
        case .branch(let branch): branch.name
        }
    }

    public var reference: String? {
        switch self {
        case .reviewRequested(let request), .authored(let request): "#\(request.number)"
        case .issue(let issue): "#\(issue.number)"
        case .branch: nil
        }
    }

    public var spoken: String {
        guard case .issue(let issue) = self else {
            return StartingPointLabel.spoken(for: pick(defaultBranch: "").startingPoint, remote: nil)
        }
        return "issue #\(issue.number), \(title)"
    }

    public func reason(now: Date) -> String {
        switch self {
        case .reviewRequested: "Review requested"
        case .authored(let request): request.isDraft ? "Your draft" : "Your pull request"
        case .issue: "Assigned to you"
        case .branch(let branch): "Touched \(HomeAge.phrase(for: branch.touched, now: now))"
        }
    }

    public func pick(defaultBranch: String) -> StartingPointSuggestionPick {
        switch self {
        case .reviewRequested(let request), .authored(let request):
            StartingPointSuggestionPick(startingPoint: .pullRequest(request))
        case .branch(let branch):
            StartingPointSuggestionPick(startingPoint: .existingBranch(ExistingBranch(name: branch.name, isLocal: true)))
        case .issue(let issue):
            StartingPointSuggestionPick(startingPoint: .newBranch(from: defaultBranch), issue: issue)
        }
    }

    public func isChosen(by point: WorkspaceStartingPoint) -> Bool {
        switch (self, point) {
        case (.reviewRequested(let request), .pullRequest(let chosen)), (.authored(let request), .pullRequest(let chosen)):
            request.number == chosen.number
        case (.branch(let branch), .existingBranch(let chosen)):
            branch.name == chosen.name
        default:
            false
        }
    }
}
