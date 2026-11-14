import Foundation
import Synchronization

public struct StartingPointReading: Sendable, Hashable {
    public let pullRequests: PullRequestsAwaitingViewer
    public let issues: [AssignedIssue]
    public let branches: [RecentBranch]
    public let readAt: Date

    public init(
        pullRequests: PullRequestsAwaitingViewer = PullRequestsAwaitingViewer(),
        issues: [AssignedIssue] = [],
        branches: [RecentBranch] = [],
        readAt: Date
    ) {
        self.pullRequests = pullRequests
        self.issues = issues
        self.branches = branches
        self.readAt = readAt
    }
}

public enum StartingPointSuggestions {
    public static let limit = 4
    static let branchWindow: TimeInterval = 14 * 24 * 3600
    static let freshness: TimeInterval = 120

    private static let readings = Mutex<[String: StartingPointReading]>([:])

    public static func choose(
        _ reading: StartingPointReading,
        defaultBranch: String,
        holders: [String: BranchHolder],
        now: Date,
        limit: Int = limit
    ) -> [StartingPointSuggestion] {
        let review = reading.pullRequests.reviewRequested
        let reviewNumbers = Set(review.map(\.number))
        let authored = reading.pullRequests.authored.filter { !reviewNumbers.contains($0.number) }
        let heads = Set((review + authored).filter { !$0.isCrossRepository }.map(\.headRefName))
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

    public static func cached(repoPath: String) -> StartingPointReading? {
        readings.withLock { $0[repoPath] }
    }

    public static func isFresh(_ reading: StartingPointReading, now: Date) -> Bool {
        now.timeIntervalSince(reading.readAt) < freshness
    }

    public static func load(repoPath: String, asksGitHub: Bool, now: Date = Date()) async -> StartingPointReading {
        if let cached = cached(repoPath: repoPath), isFresh(cached, now: now) { return cached }
        let reading = await read(repoPath: repoPath, asksGitHub: asksGitHub, now: now)
        remember(reading, for: repoPath)
        return reading
    }

    static func remember(_ reading: StartingPointReading, for repoPath: String) {
        readings.withLock { $0[repoPath] = reading }
    }

    static func forget(repoPath: String) {
        _ = readings.withLock { $0.removeValue(forKey: repoPath) }
    }

    static func read(repoPath: String, asksGitHub: Bool, now: Date) async -> StartingPointReading {
        async let branches = Git.recentBranches(of: repoPath)
        guard asksGitHub else { return StartingPointReading(branches: await branches, readAt: now) }
        async let requests = GitHub.pullRequestsAwaitingViewer(repoPath: repoPath)
        async let issues = GitHub.issuesAssignedToViewer(repoPath: repoPath)
        return StartingPointReading(
            pullRequests: await requests, issues: await issues, branches: await branches, readAt: now
        )
    }
}
