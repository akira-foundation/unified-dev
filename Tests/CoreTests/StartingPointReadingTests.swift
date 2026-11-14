import Foundation
import Testing
@testable import Core

@Suite("Reading the starting points to suggest", .scratchDirectory)
struct StartingPointReadingTests {
    private actor Asked {
        private(set) var commands: [[String]] = []
        func record(_ arguments: [String]) { commands.append(arguments) }
    }

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

    private func answering(_ asked: Asked) -> @Sendable ([String], String?) async throws -> ShellResult {
        { arguments, _ in
            await asked.record(arguments)
            let stdout = switch Array(arguments.prefix(6)) {
            case Array(Self.review.prefix(6)): Self.reviewAnswer
            case Array(Self.authored.prefix(6)): Self.authoredAnswer
            default: Self.issueAnswer
            }
            return ShellResult(status: 0, stdout: stdout, stderr: "")
        }
    }

    private func repository(_ name: String, origin: String? = nil) async throws -> String {
        let repo = TestScratch.unique(name)
        try FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        let identity = ["-c", "user.name=Test", "-c", "user.email=test@example.com"]
        _ = try await Git.run(["init", "-q", "-b", "main"], in: repo)
        _ = try await Git.run(identity + ["commit", "-q", "--allow-empty", "-m", "one"], in: repo,
                              environment: ["GIT_COMMITTER_DATE": "1700000000 +0000"])
        _ = try await Git.run(["branch", "older"], in: repo)
        _ = try await Git.run(identity + ["commit", "-q", "--allow-empty", "-m", "two"], in: repo,
                              environment: ["GIT_COMMITTER_DATE": "1800000000 +0000"])
        if let origin { _ = try await Git.run(["remote", "add", "origin", origin], in: repo) }
        return repo
    }

    @Test("review requests, the owner's own pull requests and their issues each come from their own list")
    func asksGitHub() async throws {
        let repo = try await repository("suggestions-ask")
        let asked = Asked()
        let reading = await GitHub.$commandOverride.withValue(answering(asked)) {
            await StartingPointSuggestions.read(repoPath: repo, asksGitHub: true, now: Date())
        }
        let commands = await asked.commands
        #expect(commands.contains(Self.review))
        #expect(commands.contains(Self.authored))
        #expect(commands.contains(Self.issues))
        #expect(reading.pullRequests.reviewRequested.map(\.number) == [21])
        #expect(reading.pullRequests.authored.map(\.number) == [22])
        #expect(reading.issues == [AssignedIssue(number: 34, title: "Suggest starting points")])
        #expect(reading.branches.map(\.name) == ["main", "older"])
    }

    @Test("issues are read from the repository the pull requests are read from")
    func issuesNameTheRepository() async throws {
        let repo = try await repository("suggestions-repo", origin: "https://github.com/akira/lantern.git")
        let asked = Asked()
        _ = await GitHub.$commandOverride.withValue(answering(asked)) {
            await GitHub.issuesAssignedToViewer(repoPath: repo)
        }
        #expect(await asked.commands == [Self.issues + ["--repo", "github.com/akira/lantern"]])
    }

    @Test("a project with no remote asks gh nothing and still has its branches")
    func noRemoteAsksNothing() async throws {
        let repo = try await repository("suggestions-local")
        let asked = Asked()
        let reading = await GitHub.$commandOverride.withValue(answering(asked)) {
            await StartingPointSuggestions.read(repoPath: repo, asksGitHub: false, now: Date())
        }
        #expect(await asked.commands.isEmpty)
        #expect(reading.pullRequests == PullRequestsAwaitingViewer())
        #expect(reading.issues.isEmpty)
        #expect(reading.branches.map(\.name) == ["main", "older"])
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

    @Test("pressing + again within two minutes reuses the last reading, and at two minutes asks again")
    func reusesAFreshReading() async {
        let path = TestScratch.unique("suggestions-cache")
        defer { StartingPointSuggestions.forget(repoPath: path) }
        let asked = Asked()
        let start = Date()
        await GitHub.$commandOverride.withValue(answering(asked)) {
            _ = await StartingPointSuggestions.load(repoPath: path, asksGitHub: true, now: start)
        }
        let first = await asked.commands.count
        #expect(first == 3)

        await GitHub.$commandOverride.withValue(answering(asked)) {
            _ = await StartingPointSuggestions.load(repoPath: path, asksGitHub: true, now: start.addingTimeInterval(119))
        }
        #expect(await asked.commands.count == first)
        #expect(StartingPointSuggestions.fresh(repoPath: path, asksGitHub: true, now: start.addingTimeInterval(119))?
            .readAt == start)
        #expect(StartingPointSuggestions.fresh(repoPath: path, asksGitHub: true, now: start.addingTimeInterval(120)) == nil)

        let later = start.addingTimeInterval(120)
        await GitHub.$commandOverride.withValue(answering(asked)) {
            _ = await StartingPointSuggestions.load(repoPath: path, asksGitHub: true, now: later)
        }
        #expect(StartingPointSuggestions.fresh(repoPath: path, asksGitHub: true, now: later)?.readAt == later)
    }

    @Test("a reading taken without GitHub is not reused once GitHub can be asked")
    func keyedByWhetherGitHubWasAsked() async {
        let path = TestScratch.unique("suggestions-key")
        defer { StartingPointSuggestions.forget(repoPath: path) }
        let asked = Asked()
        let start = Date()
        await GitHub.$commandOverride.withValue(answering(asked)) {
            _ = await StartingPointSuggestions.load(repoPath: path, asksGitHub: false, now: start)
            _ = await StartingPointSuggestions.load(repoPath: path, asksGitHub: true, now: start)
        }
        #expect(await asked.commands.count == 3)
    }

    @Test("a read cut short by leaving the pane is not kept as an empty reading")
    func cancelledReadIsNotKept() async {
        let path = TestScratch.unique("suggestions-cancelled")
        defer { StartingPointSuggestions.forget(repoPath: path) }
        let asked = Asked()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await GitHub.$commandOverride.withValue(answering(asked)) {
                await StartingPointSuggestions.load(repoPath: path, asksGitHub: true)
            }
        }
        #expect(await task.value == nil)
        #expect(StartingPointSuggestions.fresh(repoPath: path, asksGitHub: true) == nil)
    }

    @Test("a pull request listing that is answered lets the suggestions ask GitHub")
    func answered() {
        #expect(PullRequestLoad.listed([]).answered)
        #expect(!PullRequestLoad.loading.answered)
        #expect(!PullRequestLoad.unavailable("Sign in with gh to list pull requests").answered)
    }
}
