import Foundation

public enum StartingPointReader {
    static let freshness = Duration.seconds(120)

    struct Key: Sendable, Hashable {
        let request: StartingPointReadingRequest
        let login: GitHubLogin
    }

    struct PartialReading: Error {
        let reading: StartingPointReading
    }

    typealias Readings = SharedReadings<Key, StartingPointReading>

    private static let shared = Readings()

    public static func load(_ request: StartingPointReadingRequest) async -> StartingPointReading? {
        await load(request, from: shared)
    }

    static func load(_ request: StartingPointReadingRequest, from readings: Readings) async -> StartingPointReading? {
        let key = Key(request: request, login: await GitHub.login(forDirectory: request.repoPath))
        do {
            return try await readings.value(for: key, notOlderThan: freshness) {
                try await read(repoPath: request.repoPath, asksGitHub: request.asksGitHub)
            }
        } catch let partial as PartialReading {
            return partial.reading
        } catch {
            return nil
        }
    }

    static func read(repoPath: String, asksGitHub: Bool) async throws -> StartingPointReading {
        async let branches = Git.recentBranches(of: repoPath)
        guard asksGitHub, await Forge.kind(forDirectory: repoPath) == .gitHub else {
            return StartingPointReading(branches: await branches)
        }
        async let requests = GitHub.pullRequestsAwaitingViewer(repoPath: repoPath)
        async let issues = GitHub.issuesAssignedToViewer(repoPath: repoPath)
        let (readRequests, readIssues, readBranches) = await (requests, issues, branches)
        let reading = StartingPointReading(
            pullRequests: readRequests.found, issues: readIssues ?? [], branches: readBranches
        )
        guard readRequests.isWhole, readIssues != nil else { throw PartialReading(reading: reading) }
        return reading
    }
}
