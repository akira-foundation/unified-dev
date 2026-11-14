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

    public func prompt(into existing: String, after decision: StartingPointPick) -> String {
        guard decision == .use(startingPoint) else { return existing }
        return prompt(into: existing)
    }

    func prompt(into existing: String) -> String {
        guard let prompt, let issue else { return existing }
        let typed = Self.withoutIssueLines(existing)
        if Self.mentions(issue.number, in: typed) { return typed }
        return WorkspaceDraft.receiving(prompt, into: typed)
    }

    static let issueLead = "Work on issue #"

    static func withoutIssueLines(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            guard isIssueLine(lines[index]) else {
                index += 1
                continue
            }
            lines.remove(at: index)
            let following = index < lines.count && isBlank(lines[index]) ? index : nil
            let preceding = index == lines.count && index > 0 && isBlank(lines[index - 1]) ? index - 1 : nil
            guard let blank = following ?? preceding else { continue }
            lines.remove(at: blank)
            index = min(index, blank)
        }
        return lines.joined(separator: "\n")
    }

    static func isIssueLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).wholeMatch(of: /Work on issue #\d+(, ".*")?\./) != nil
    }

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
