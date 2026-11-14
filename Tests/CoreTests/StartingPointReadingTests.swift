import Foundation
import Testing
@testable import Core

@Suite("Reading the starting points to suggest", .scratchDirectory)
struct StartingPointReadingTests {
    private actor Asked {
        private(set) var commands: [String] = []
        func record(_ arguments: [String]) { commands.append(arguments.joined(separator: " ")) }
    }

    private static let requests = #"[{"number":21,"title":"Paint","author":{"login":"kid"},"headRefName":"paint","baseRefName":"main","isDraft":false,"state":"OPEN"}]"#
    private static let issues = #"[{"number":34,"title":"Suggest starting points"}]"#

    private func answering(_ asked: Asked) -> @Sendable ([String], String?) async throws -> ShellResult {
        { arguments, _ in
            await asked.record(arguments)
            let stdout = arguments.first == "issue" ? Self.issues : Self.requests
            return ShellResult(status: 0, stdout: stdout, stderr: "")
        }
    }

    @Test("it asks gh for review requests, the owner's own pull requests and their assigned issues")
    func asksGitHub() async {
        let path = TestScratch.unique("suggestions-ask")
        let asked = Asked()
        let reading = await GitHub.$commandOverride.withValue(answering(asked)) {
            await StartingPointSuggestions.read(repoPath: path, asksGitHub: true, now: Date())
        }
        let commands = await asked.commands
        #expect(commands.contains { $0.hasPrefix("pr list --state open --search review-requested:@me") })
        #expect(commands.contains { $0.hasPrefix("pr list --state open --author @me") })
        #expect(commands.contains { $0.hasPrefix("issue list --state open --assignee @me") })
        #expect(reading.pullRequests.reviewRequested.map(\.number) == [21])
        #expect(reading.pullRequests.authored.map(\.number) == [21])
        #expect(reading.issues == [AssignedIssue(number: 34, title: "Suggest starting points")])
    }

    @Test("a project with no remote asks gh nothing")
    func noRemoteAsksNothing() async {
        let path = TestScratch.unique("suggestions-local")
        let asked = Asked()
        let reading = await GitHub.$commandOverride.withValue(answering(asked)) {
            await StartingPointSuggestions.read(repoPath: path, asksGitHub: false, now: Date())
        }
        #expect(await asked.commands.isEmpty)
        #expect(reading.pullRequests == PullRequestsAwaitingViewer())
        #expect(reading.issues.isEmpty)
    }

    @Test("gh refusing leaves nothing to suggest from it, rather than an error under the composer")
    func refusalIsQuiet() async {
        let path = TestScratch.unique("suggestions-refused")
        let reading = await GitHub.$commandOverride.withValue({ _, _ in
            ShellResult(status: 1, stdout: "", stderr: "HTTP 401: Bad credentials")
        }) {
            await StartingPointSuggestions.read(repoPath: path, asksGitHub: true, now: Date())
        }
        #expect(reading.pullRequests == PullRequestsAwaitingViewer())
        #expect(reading.issues.isEmpty)
    }

    @Test("pressing + again within two minutes reuses the last reading, and after that asks again")
    func reusesAFreshReading() async {
        let path = TestScratch.unique("suggestions-cache")
        defer { StartingPointSuggestions.forget(repoPath: path) }
        let asked = Asked()
        let start = Date()
        await GitHub.$commandOverride.withValue(answering(asked)) {
            _ = await StartingPointSuggestions.load(repoPath: path, asksGitHub: true, now: start)
        }
        let first = await asked.commands.count
        await GitHub.$commandOverride.withValue(answering(asked)) {
            _ = await StartingPointSuggestions.load(repoPath: path, asksGitHub: true, now: start.addingTimeInterval(60))
        }
        #expect(await asked.commands.count == first)
        #expect(StartingPointSuggestions.cached(repoPath: path)?.readAt == start)

        let later = start.addingTimeInterval(StartingPointSuggestions.freshness + 1)
        await GitHub.$commandOverride.withValue(answering(asked)) {
            _ = await StartingPointSuggestions.load(repoPath: path, asksGitHub: true, now: later)
        }
        #expect(await asked.commands.count == first * 2)
        #expect(StartingPointSuggestions.cached(repoPath: path)?.readAt == later)
    }

    @Test("recent branches come from git, newest commit first")
    func readsRecentBranches() async throws {
        let repo = TestScratch.unique("suggestions-git")
        try FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        let identity = ["-c", "user.name=Test", "-c", "user.email=test@example.com"]
        _ = try await Git.run(["init", "-q", "-b", "main"], in: repo)
        _ = try await Git.run(identity + ["commit", "-q", "--allow-empty", "-m", "one"], in: repo,
                              environment: ["GIT_COMMITTER_DATE": "1700000000 +0000"])
        _ = try await Git.run(["branch", "older"], in: repo)
        _ = try await Git.run(identity + ["commit", "-q", "--allow-empty", "-m", "two"], in: repo,
                              environment: ["GIT_COMMITTER_DATE": "1800000000 +0000"])

        let branches = await Git.recentBranches(of: repo)
        #expect(branches.map(\.name) == ["main", "older"])
        #expect(branches.first?.touched == Date(timeIntervalSince1970: 1_800_000_000))
    }
}
