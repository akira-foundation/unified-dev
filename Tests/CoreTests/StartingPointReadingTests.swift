import Foundation
import Synchronization
import Testing
@testable import Core

@Suite("Reading the starting points to suggest", .scratchDirectory)
struct StartingPointReadingTests {
    private actor Asked {
        private(set) var commands: [[String]] = []
        func record(_ arguments: [String]) { commands.append(arguments) }
    }

    private final class StoppedClock: Sendable {
        private let instant = Mutex(ContinuousClock.now)
        var now: ContinuousClock.Instant { instant.withLock { $0 } }
        func advance(_ by: Duration) { instant.withLock { $0 += by } }
    }

    private typealias Command = @Sendable ([String], String?) async throws -> ShellResult

    private static func listing(_ number: Int, state: String = "OPEN") -> String {
        #"{"number":\#(number),"title":"Request \#(number)","author":{"login":"kid"},"headRefName":"head-\#(number)","baseRefName":"main","isDraft":false,"state":"\#(state)"}"#
    }

    private static let reviewAnswer = "[\(listing(21))]"
    private static let authoredAnswer = "[\(listing(22)),\(listing(23, state: "CLOSED")),\(listing(22))]"
    private static let issueAnswer = #"[{"number":34,"title":"Suggest starting points"}]"#

    private static let review = [
        "pr", "list", "--state", "open", "--search", "review-requested:@me", "--limit", "10",
        "--json", GitHub.summaryFields,
    ]
    private static let authored = [
        "pr", "list", "--state", "open", "--author", "@me", "--limit", "10", "--json", GitHub.summaryFields,
    ]
    private static let issues = [
        "issue", "list", "--state", "open", "--assignee", "@me", "--limit", "10", "--json", "number,title",
    ]

    private static func answer(_ arguments: [String]) -> String {
        switch Array(arguments.prefix(6)) {
        case Array(review.prefix(6)): reviewAnswer
        case Array(authored.prefix(6)): authoredAnswer
        default: issueAnswer
        }
    }

    private func answering(_ asked: Asked, status: Int32 = 0, refusing family: String? = nil) -> Command {
        { arguments, _ in
            await asked.record(arguments)
            let refused = family.map { arguments.first == $0 } ?? true
            return ShellResult(status: refused ? status : 0, stdout: Self.answer(arguments), stderr: "")
        }
    }

    private func repository(
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

    private static func repoOption(_ arguments: [String]) -> String? {
        arguments.firstIndex(of: "--repo").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }

    @Test("review requests, the owner's own pull requests and their issues each come from their own list")
    func asksGitHub() async throws {
        let repo = try await repository("suggestions-ask")
        let asked = Asked()
        let reading = try await GitHub.$commandOverride.withValue(answering(asked)) {
            try await StartingPointReader.read(repoPath: repo, asksGitHub: true)
        }
        let commands = await asked.commands
        #expect(commands.contains(Self.review))
        #expect(commands.contains(Self.authored))
        #expect(commands.contains(Self.issues))
        #expect(reading.pullRequests.reviewRequested.map(\.number) == [21])
        #expect(reading.pullRequests.authored.map(\.number) == [22])
        #expect(reading.issues == [AssignedIssue(number: 34, title: "Suggest starting points")])
    }

    @Test("recent branches come from git by the date of their last commit, not by name")
    func recentBranchesByDate() async throws {
        let repo = try await repository("suggestions-git")
        let reading = try await StartingPointReader.read(repoPath: repo, asksGitHub: false)
        #expect(reading.branches.map(\.name) == ["zz-newest", "main", "zebra-older"])
        #expect(reading.branches.first?.touched == Date(timeIntervalSince1970: 1_900_000_000))
        #expect(await Git.recentBranches(of: repo, count: 2).map(\.name) == ["zz-newest", "main"])
    }

    @Test("issues are read from the base repository the pull requests are read from, in a fork as well")
    func issuesNameTheRepository() async throws {
        let repo = try await repository("suggestions-repo", remotes: [
            "origin": "https://github.com/fork-owner/lantern.git",
            "upstream": "https://github.com/akira/lantern.git",
        ], config: ["branch.main.remote": "upstream", "remote.pushdefault": "origin"])
        let asked = Asked()
        _ = try await GitHub.$commandOverride.withValue(answering(asked)) {
            try await StartingPointReader.read(repoPath: repo, asksGitHub: true)
        }
        let commands = await asked.commands
        let pullRequestRepo = try #require(commands.first { $0.first == "pr" }.flatMap(Self.repoOption))
        let issueCommand = try #require(commands.first { $0.first == "issue" })
        #expect(Array(issueCommand.prefix(Self.issues.count)) == Self.issues)
        #expect(Self.repoOption(issueCommand) == "github.com/akira/lantern")
        #expect(pullRequestRepo == "github.com/akira/lantern")
    }

    @Test("a project with no remote asks gh nothing and still has its branches")
    func noRemoteAsksNothing() async throws {
        let repo = try await repository("suggestions-local")
        let asked = Asked()
        let reading = try await GitHub.$commandOverride.withValue(answering(asked)) {
            try await StartingPointReader.read(repoPath: repo, asksGitHub: false)
        }
        #expect(await asked.commands.isEmpty)
        #expect(reading.pullRequests == PullRequestsAwaitingViewer())
        #expect(reading.issues.isEmpty)
        #expect(reading.branches.count == 3)
    }

    @Test("a project on Bitbucket asks gh nothing")
    func bitbucketAsksNothing() async throws {
        let repo = try await repository("suggestions-bitbucket", remotes: [
            "origin": "https://bitbucket.org/akira/lantern.git",
        ])
        let asked = Asked()
        let reading = try await GitHub.$commandOverride.withValue(answering(asked)) {
            try await StartingPointReader.read(repoPath: repo, asksGitHub: true)
        }
        #expect(await asked.commands.isEmpty)
        #expect(reading.branches.count == 3)
    }

    @Test("gh refusing still shows the branches, and is asked again on the next visit")
    func refusalIsNotKept() async throws {
        let repo = try await repository("suggestions-refused")
        let readings = StartingPointReader.Readings()
        let request = StartingPointReadingRequest(repoPath: repo, asksGitHub: true)
        let asked = Asked()
        let reading = await GitHub.$commandOverride.withValue(answering(asked, status: 1)) {
            await StartingPointReader.load(request, from: readings)
        }
        #expect(await asked.commands.count == 3)
        #expect(reading?.pullRequests == PullRequestsAwaitingViewer())
        #expect(reading?.issues.isEmpty == true)
        #expect(reading?.branches.count == 3)

        let next = await GitHub.$commandOverride.withValue(answering(asked)) {
            await StartingPointReader.load(request, from: readings)
        }
        #expect(await asked.commands.count == 6)
        #expect(next?.issues.map(\.number) == [34])
    }

    @Test("one list refusing is a reading that is shown and not kept")
    func partialRefusal() async throws {
        let repo = try await repository("suggestions-partial")
        let asked = Asked()
        await #expect(throws: StartingPointReader.PartialReading.self) {
            try await GitHub.$commandOverride.withValue(answering(asked, status: 1, refusing: "issue")) {
                try await StartingPointReader.read(repoPath: repo, asksGitHub: true)
            }
        }
    }

    @Test("pressing + again within two minutes reuses the last reading, and at two minutes reads again")
    func reusesAFreshReading() async {
        let clock = StoppedClock()
        let readings = StartingPointReader.Readings(now: { clock.now })
        let request = StartingPointReadingRequest(repoPath: TestScratch.unique("suggestions-cache"), asksGitHub: true)
        let asked = Asked()
        await GitHub.$commandOverride.withValue(answering(asked)) {
            _ = await StartingPointReader.load(request, from: readings)
        }
        #expect(await asked.commands.count == 3)

        clock.advance(.seconds(119))
        let kept = await GitHub.$commandOverride.withValue(answering(asked)) {
            await StartingPointReader.load(request, from: readings)
        }
        #expect(await asked.commands.count == 3)
        #expect(kept?.issues.map(\.number) == [34])

        clock.advance(.seconds(1))
        await GitHub.$commandOverride.withValue(answering(asked)) {
            _ = await StartingPointReader.load(request, from: readings)
        }
        #expect(await asked.commands.count > 3)
    }

    @Test("a reading taken without GitHub is not reused once GitHub can be asked")
    func keyedByWhetherGitHubWasAsked() async {
        let readings = StartingPointReader.Readings()
        let path = TestScratch.unique("suggestions-key")
        let asked = Asked()
        await GitHub.$commandOverride.withValue(answering(asked)) {
            _ = await StartingPointReader.load(StartingPointReadingRequest(repoPath: path, asksGitHub: false), from: readings)
            _ = await StartingPointReader.load(StartingPointReadingRequest(repoPath: path, asksGitHub: true), from: readings)
        }
        #expect(await asked.commands.count == 3)
    }

    @Test("a reading is not shown to another GitHub login of the same project")
    func keyedByLogin() async {
        let readings = StartingPointReader.Readings()
        let request = StartingPointReadingRequest(repoPath: TestScratch.unique("suggestions-login"), asksGitHub: true)
        let other = GitHubLogin.unresolved(directory: URL(fileURLWithPath: request.repoPath))
        let asked = Asked()
        await GitHub.$commandOverride.withValue(answering(asked)) {
            _ = await GitHub.$login.withValue(.thisMac) {
                await StartingPointReader.load(request, from: readings)
            }
            _ = await GitHub.$login.withValue(other) {
                await StartingPointReader.load(request, from: readings)
            }
        }
        #expect(await asked.commands.count == 6)
    }

    @Test("leaving the pane in the middle of a read still keeps the whole reading for the next visit")
    func cancelledCallerKeepsTheReading() async {
        let readings = StartingPointReader.Readings()
        let request = StartingPointReadingRequest(repoPath: TestScratch.unique("suggestions-cancelled"), asksGitHub: true)
        let asked = Asked()
        let gate = ReadingGate()
        let held: Command = { arguments, _ in
            await asked.record(arguments)
            await gate.pass()
            return ShellResult(status: 0, stdout: Self.answer(arguments), stderr: "")
        }
        let task = Task {
            await GitHub.$commandOverride.withValue(held) {
                await StartingPointReader.load(request, from: readings)
            }
        }
        await gate.reached()
        task.cancel()
        await gate.open()
        _ = await task.value
        let next = await GitHub.$commandOverride.withValue(answering(asked)) {
            await StartingPointReader.load(request, from: readings)
        }
        #expect(next?.issues.map(\.number) == [34])
        #expect(next?.pullRequests.reviewRequested.map(\.number) == [21])
        #expect(await asked.commands.count == 3)
    }

    @Test("a pull request listing that answered lets the suggestions ask GitHub")
    func isListed() {
        #expect(PullRequestLoad.listed([]).isListed)
        #expect(!PullRequestLoad.loading.isListed)
        #expect(!PullRequestLoad.unavailable("Sign in with gh to list pull requests").isListed)
    }
}
