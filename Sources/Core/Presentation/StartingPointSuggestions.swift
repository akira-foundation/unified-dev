import Foundation

public enum StartingPointSuggestions {
    public static let limit = 4
    static let branchWindow: TimeInterval = 14 * 24 * 3600

    public static func choose(
        _ reading: StartingPointReading,
        defaultBranch: String,
        holders: [String: BranchHolder],
        openPullRequests: [PullRequestListing] = [],
        now: Date,
        limit: Int = limit
    ) -> [StartingPointSuggestion] {
        let review = reading.pullRequests.reviewRequested
        let reviewNumbers = Set(review.map(\.number))
        let authored = reading.pullRequests.authored.filter { !reviewNumbers.contains($0.number) }
        let heads = WorkspaceCheckoutPlan.heads(of: review + authored + openPullRequests)
        let branches = reading.branches.filter { branch in
            branch.name != defaultBranch
                && holders[branch.name] == nil
                && !heads.contains(branch.name)
                && now.timeIntervalSince(branch.touched) <= branchWindow
        }
        let groups: [[StartingPointSuggestion]] = [
            review.map { .reviewRequested($0) },
            authored.map { .authored($0) },
            reading.issues.map { .issue($0) },
            branches.sorted { $0.touched > $1.touched }.map { .branch($0) },
        ]
        return interleaved(groups, limit: limit)
    }

    static func interleaved(_ groups: [[StartingPointSuggestion]], limit: Int) -> [StartingPointSuggestion] {
        var taken = Array(repeating: 0, count: groups.count)
        var total = 0
        var moved = true
        while total < limit && moved {
            moved = false
            for index in groups.indices where total < limit && taken[index] < groups[index].count {
                taken[index] += 1
                total += 1
                moved = true
            }
        }
        return groups.indices.flatMap { groups[$0].prefix(taken[$0]) }
    }
}
