import Foundation

public struct StartingPointSection: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case newBranch
        case existingBranch
        case pullRequest
    }

    public let kind: Kind
    public let rows: [WorkspaceSource]

    public var id: Kind { kind }

    public var title: String {
        switch kind {
        case .newBranch: "New branch from"
        case .existingBranch: "Existing branch"
        case .pullRequest: "Pull request"
        }
    }
}

public enum StartingPointMenu {
    public static func sections(
        offering: WorkspaceSourceOffering,
        query: String,
        leadingBases: [String],
        offersPullRequests: Bool,
        limit: Int = 40
    ) -> [StartingPointSection] {
        let matches = offering.search(query: query, limit: limit)
        let newRows = leading(leadingBases, in: matches.new, when: matches.query.isEmpty)
        let branches = matches.open.filter { if case .existingBranch = $0 { true } else { false } }
        let requests = offersPullRequests
            ? matches.open.filter { if case .pullRequest = $0 { true } else { false } }
            : []
        return [
            StartingPointSection(kind: .newBranch, rows: newRows),
            StartingPointSection(kind: .existingBranch, rows: branches),
            StartingPointSection(kind: .pullRequest, rows: requests),
        ].filter { !$0.rows.isEmpty }
    }

    public static func leadingBases(point: WorkspaceStartingPoint, cameFrom: String?) -> [String] {
        var bases: [String] = []
        for base in [point.baseBranch, cameFrom].compactMap(\.self) where !bases.contains(base) {
            bases.append(base)
        }
        return bases
    }

    public static func rows(in sections: [StartingPointSection]) -> [WorkspaceSource] {
        sections.flatMap(\.rows)
    }

    public static func jump(query: String, in sections: [StartingPointSection]) -> WorkspaceSource? {
        guard let reference = WorkspaceCheckoutPlan.parseReference(query) else { return nil }
        let requests = sections.first { $0.kind == .pullRequest }?.rows ?? []
        return requests.first { row in
            switch row {
            case .pullRequest(.listed(let request)): request.number == reference.number
            case .pullRequest(.typed(let typed, _)): typed.number == reference.number
            case .newBranch, .existingBranch: false
            }
        }
    }

    public static func stepped(
        from current: WorkspaceSource?, by step: Int, in sections: [StartingPointSection]
    ) -> WorkspaceSource? {
        MenuRows.stepped(from: current, by: step, in: rows(in: sections))
    }

    private static func leading(
        _ bases: [String], in rows: [WorkspaceSource], when isResting: Bool
    ) -> [WorkspaceSource] {
        guard isResting else { return rows }
        let leads = bases.map { WorkspaceSource.newBranch(from: $0) }
        return leads + rows.filter { !leads.contains($0) }
    }
}
