import Foundation
import Synchronization
import Testing
@testable import Core

actor AskedCommands {
    private(set) var commands: [[String]] = []
    func record(_ arguments: [String]) { commands.append(arguments) }
}

final class ReadingClock: Sendable {
    private let instant = Mutex(ContinuousClock.now)
    var now: ContinuousClock.Instant { instant.withLock { $0 } }
    func advance(_ by: Duration) { instant.withLock { $0 += by } }
}

typealias GitHubCommand = @Sendable ([String], String?) async throws -> ShellResult

enum StartingPointGitHubDouble {
    static func listing(_ number: Int, state: String = "OPEN") -> String {
        #"{"number":\#(number),"title":"Request \#(number)","author":{"login":"kid"},"headRefName":"head-\#(number)","baseRefName":"main","isDraft":false,"state":"\#(state)"}"#
    }

    static let review = [
        "pr", "list", "--state", "open", "--search", "review-requested:@me", "--limit", "10",
        "--json", GitHub.summaryFields,
    ]
    static let authored = [
        "pr", "list", "--state", "open", "--author", "@me", "--limit", "10", "--json", GitHub.summaryFields,
    ]
    static let issues = [
        "issue", "list", "--state", "open", "--assignee", "@me", "--limit", "10", "--json", "number,title",
    ]

    static func answer(_ arguments: [String]) -> String {
        switch Array(arguments.prefix(6)) {
        case Array(review.prefix(6)): "[\(listing(21))]"
        case Array(authored.prefix(6)): "[\(listing(22)),\(listing(23, state: "CLOSED")),\(listing(22))]"
        default: #"[{"number":34,"title":"Suggest starting points"}]"#
        }
    }

    static func answering(
        _ asked: AskedCommands,
        refusing refused: @escaping @Sendable ([String]) -> Bool = { _ in false },
        stderr: String = ""
    ) -> GitHubCommand {
        { arguments, _ in
            await asked.record(arguments)
            let status: Int32 = refused(arguments) ? 1 : 0
            return ShellResult(status: status, stdout: answer(arguments), stderr: status == 0 ? "" : stderr)
        }
    }

    static func repository(
        _ name: String, remotes: [String: String] = [:], config: [String: String] = [:]
    ) async throws -> String {
        let repo = TestScratch.unique(name)
        try FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        let identity = ["-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false"]
        _ = try await Git.run(["init", "-q", "-b", "main"], in: repo)
        _ = try await Git.run(identity + ["commit", "-q", "--allow-empty", "-m", "one"], in: repo,
                              environment: ["GIT_COMMITTER_DATE": "1700000000 +0000"])
        _ = try await Git.run(["branch", "zebra-older"], in: repo)
        _ = try await Git.run(identity + ["commit", "-q", "--allow-empty", "-m", "two"], in: repo,
                              environment: ["GIT_COMMITTER_DATE": "1800000000 +0000"])
        _ = try await Git.run(["branch", "zz-newest"], in: repo)
        _ = try await Git.run(["checkout", "-q", "zz-newest"], in: repo)
        _ = try await Git.run(identity + ["commit", "-q", "--allow-empty", "-m", "three"], in: repo,
                              environment: ["GIT_COMMITTER_DATE": "1900000000 +0000"])
        _ = try await Git.run(["checkout", "-q", "main"], in: repo)
        for (name, url) in remotes.sorted(by: { $0.key < $1.key }) {
            _ = try await Git.run(["remote", "add", name, url], in: repo)
        }
        for (key, value) in config.sorted(by: { $0.key < $1.key }) {
            _ = try await Git.run(["config", key, value], in: repo)
        }
        let made = try await Git.run(["for-each-ref", "--format=%(refname:short)", "refs/heads"], in: repo)
        try #require(made.stdout.split(separator: "\n").count == 3)
        return repo
    }

    static func repoOption(_ arguments: [String]) -> String? {
        arguments.firstIndex(of: "--repo").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }
}
