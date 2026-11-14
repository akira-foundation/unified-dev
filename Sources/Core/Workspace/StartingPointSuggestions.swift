import Foundation
import Synchronization

public enum StartingPointSuggestions {
    public static let limit = 4
    static let branchWindow: TimeInterval = 14 * 24 * 3600
    static let freshness: TimeInterval = 120

    private struct CacheKey: Hashable {
        let repoPath: String
        let asksGitHub: Bool
    }

    private static let readings = Mutex<[CacheKey: StartingPointReading]>([:])

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

    public static func fresh(repoPath: String, asksGitHub: Bool, now: Date = Date()) -> StartingPointReading? {
        guard let cached = cached(repoPath: repoPath, asksGitHub: asksGitHub), isFresh(cached, now: now) else {
            return nil
        }
        return cached
    }

    static func cached(repoPath: String, asksGitHub: Bool) -> StartingPointReading? {
        readings.withLock { $0[CacheKey(repoPath: repoPath, asksGitHub: asksGitHub)] }
    }

    static func isFresh(_ reading: StartingPointReading, now: Date) -> Bool {
        now.timeIntervalSince(reading.readAt) < freshness
    }

    public static func load(repoPath: String, asksGitHub: Bool, now: Date = Date()) async -> StartingPointReading? {
        if let reading = fresh(repoPath: repoPath, asksGitHub: asksGitHub, now: now) { return reading }
        let reading = await read(repoPath: repoPath, asksGitHub: asksGitHub, now: now)
        guard !Task.isCancelled else { return nil }
        readings.withLock { $0[CacheKey(repoPath: repoPath, asksGitHub: asksGitHub)] = reading }
        return reading
    }

    static func forget(repoPath: String) {
        readings.withLock { cache in
            for key in cache.keys where key.repoPath == repoPath { cache.removeValue(forKey: key) }
        }
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
