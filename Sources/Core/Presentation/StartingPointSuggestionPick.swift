import Foundation

public struct StartingPointSuggestionPick: Sendable, Hashable {
    public let startingPoint: WorkspaceStartingPoint
    let issue: AssignedIssue?

    init(startingPoint: WorkspaceStartingPoint, issue: AssignedIssue? = nil) {
        self.startingPoint = startingPoint
        self.issue = issue
    }

    public var source: WorkspaceSource { startingPoint.source }

    public var addsToPrompt: Bool { issue != nil }

    public var prompt: String? {
        guard let issue else { return nil }
        return issue.title.isEmpty
            ? "\(Self.issueLead)\(issue.number)."
            : "\(Self.issueLead)\(issue.number), \"\(issue.title)\"."
    }

    public func prompt(into existing: String) -> String {
        guard let prompt, let issue else { return existing }
        if Self.mentions(issue.number, in: existing) { return existing }
        return WorkspaceDraft.receiving(prompt, into: Self.withoutIssueLines(existing))
    }

    static let issueLead = "Work on issue #"

    static func withoutIssueLines(_ text: String) -> String {
        text.components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(issueLead) }
            .joined(separator: "\n\n")
    }

    static func mentions(_ number: Int, in text: String) -> Bool {
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
