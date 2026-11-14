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
        switch self {
        case .reviewRequested, .authored: "arrow.triangle.pull"
        case .issue: "smallcircle.filled.circle"
        case .branch: "arrow.triangle.branch"
        }
    }

    public var title: String {
        switch self {
        case .reviewRequested(let request), .authored(let request): request.title.isEmpty ? request.headRefName : request.title
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

    public func reason(now: Date) -> String {
        switch self {
        case .reviewRequested: "Review requested"
        case .authored(let request): request.isDraft ? "Your draft" : "Your pull request"
        case .issue: "Assigned to you"
        case .branch(let branch): Self.touched(branch.touched, now: now)
        }
    }

    public var spokenVerb: String {
        switch self {
        case .reviewRequested: "Review"
        case .authored, .branch: "Open"
        case .issue: "Start on"
        }
    }

    public func pick(defaultBranch: String) -> StartingPointSuggestionPick {
        switch self {
        case .reviewRequested(let request), .authored(let request):
            StartingPointSuggestionPick(source: .pullRequest(.listed(request)), prompt: nil)
        case .branch(let branch):
            StartingPointSuggestionPick(source: .existingBranch(ExistingBranch(name: branch.name, isLocal: true)), prompt: nil)
        case .issue(let issue):
            StartingPointSuggestionPick(
                source: .newBranch(from: defaultBranch),
                prompt: "Work on issue #\(issue.number): \(issue.title)",
                issueNumber: issue.number
            )
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

    static func touched(_ date: Date, now: Date) -> String {
        let hours = Int(max(0, now.timeIntervalSince(date)) / 3600)
        switch hours {
        case ..<1: return "Touched just now"
        case ..<24: return hours == 1 ? "Touched an hour ago" : "Touched \(hours) hours ago"
        case ..<48: return "Touched yesterday"
        default: return "Touched \(hours / 24) days ago"
        }
    }
}

public struct StartingPointSuggestionPick: Sendable, Hashable {
    public let source: WorkspaceSource
    public let prompt: String?
    let issueNumber: Int?

    init(source: WorkspaceSource, prompt: String?, issueNumber: Int? = nil) {
        self.source = source
        self.prompt = prompt
        self.issueNumber = issueNumber
    }

    public func prompt(into existing: String) -> String {
        guard let prompt else { return existing }
        if let issueNumber, Self.mentions(issueNumber, in: existing) { return existing }
        return WorkspaceDraft.receiving(prompt, into: existing)
    }

    private static func mentions(_ number: Int, in text: String) -> Bool {
        let mark = "#\(number)"
        var remainder = text[...]
        while let found = remainder.range(of: mark) {
            let next = remainder[found.upperBound...].first
            if next.map({ !$0.isNumber }) ?? true { return true }
            remainder = remainder[found.upperBound...]
        }
        return false
    }
}
