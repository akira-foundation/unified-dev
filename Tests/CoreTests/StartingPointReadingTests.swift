import Foundation
import Testing
@testable import Core

@Suite("Reading the starting points to suggest", .scratchDirectory)
struct StartingPointReadingTests {
    private typealias Double = StartingPointGitHubDouble

    @Test("review requests, the owner's own pull requests and their issues each come from their own list")
    func asksGitHub() async throws {
        let repo = try await Double.repository("suggestions-ask")
        let asked = AskedCommands()
        let reading = try await GitHub.$commandOverride.withValue(Double.answering(asked)) {
            try await StartingPointReader.read(repoPath: repo, asksGitHub: true)
        }
        let commands = await asked.commands
        #expect(commands.contains(Double.review))
        #expect(commands.contains(Double.authored))
        #expect(commands.contains(Double.issues))
        #expect(reading.pullRequests.reviewRequested.map(\.number) == [21])
        #expect(reading.pullRequests.authored.map(\.number) == [22])
        #expect(reading.issues == [AssignedIssue(number: 34, title: "Suggest starting points")])
    }

    @Test("recent branches come from git by the date of their last commit, not by name")
    func recentBranchesByDate() async throws {
        let repo = try await Double.repository("suggestions-git")
        let reading = try await StartingPointReader.read(repoPath: repo, asksGitHub: false)
        #expect(reading.branches.map(\.name) == ["zz-newest", "main", "zebra-older"])
        #expect(reading.branches.first?.touched == Date(timeIntervalSince1970: 1_900_000_000))
        #expect(await Git.recentBranches(of: repo, count: 2).map(\.name) == ["zz-newest", "main"])
    }

    @Test("issues are read from the base repository the pull requests are read from, in a fork as well")
    func issuesNameTheRepository() async throws {
        let repo = try await Double.repository("suggestions-repo", remotes: [
            "origin": "https://github.com/fork-owner/lantern.git",
            "upstream": "https://github.com/akira/lantern.git",
        ], config: ["branch.main.remote": "upstream", "remote.pushdefault": "origin"])
        let asked = AskedCommands()
        _ = try await GitHub.$commandOverride.withValue(Double.answering(asked)) {
            try await StartingPointReader.read(repoPath: repo, asksGitHub: true)
        }
        let commands = await asked.commands
        let pullRequestRepo = try #require(commands.first { $0.first == "pr" }.flatMap(Double.repoOption))
        let issueCommand = try #require(commands.first { $0.first == "issue" })
        #expect(Array(issueCommand.prefix(Double.issues.count)) == Double.issues)
        #expect(Double.repoOption(issueCommand) == "github.com/akira/lantern")
        #expect(pullRequestRepo == "github.com/akira/lantern")
    }

    @Test("a project with no remote asks gh nothing and still has its branches")
    func noRemoteAsksNothing() async throws {
        let repo = try await Double.repository("suggestions-local")
        let asked = AskedCommands()
        let reading = try await GitHub.$commandOverride.withValue(Double.answering(asked)) {
            try await StartingPointReader.read(repoPath: repo, asksGitHub: false)
        }
        #expect(await asked.commands.isEmpty)
        #expect(reading.pullRequests == PullRequestsAwaitingViewer())
        #expect(reading.issues.isEmpty)
        #expect(reading.branches.count == 3)
    }

    @Test("a project on Bitbucket asks gh nothing")
    func bitbucketAsksNothing() async throws {
        let repo = try await Double.repository("suggestions-bitbucket", remotes: [
            "origin": "https://bitbucket.org/akira/lantern.git",
        ])
        let asked = AskedCommands()
        let reading = try await GitHub.$commandOverride.withValue(Double.answering(asked)) {
            try await StartingPointReader.read(repoPath: repo, asksGitHub: true)
        }
        #expect(await asked.commands.isEmpty)
        #expect(reading.branches.count == 3)
    }

    @Test("gh refusing still shows the branches, and is asked again on the next visit")
    func refusalIsNotKept() async throws {
        let repo = try await Double.repository("suggestions-refused")
        let readings = StartingPointReader.Readings()
        let request = StartingPointReadingRequest(repoPath: repo, asksGitHub: true)
        let asked = AskedCommands()
        let reading = await GitHub.$commandOverride.withValue(Double.answering(asked, refusing: { _ in true })) {
            await StartingPointReader.load(request, from: readings)
        }
        #expect(await asked.commands.count == 3)
        #expect(reading?.pullRequests == PullRequestsAwaitingViewer())
        #expect(reading?.issues.isEmpty == true)
        #expect(reading?.branches.count == 3)

        let next = await GitHub.$commandOverride.withValue(Double.answering(asked)) {
            await StartingPointReader.load(request, from: readings)
        }
        #expect(await asked.commands.count == 6)
        #expect(next?.issues.map(\.number) == [34])
    }

    @Test("one list refusing shows what the others answered, and is not kept",
          arguments: ["issue", "pr", "--author", "review-requested:@me"])
    func partialRefusal(refusedWord: String) async throws {
        let repo = try await Double.repository("suggestions-partial")
        let readings = StartingPointReader.Readings()
        let request = StartingPointReadingRequest(repoPath: repo, asksGitHub: true)
        let asked = AskedCommands()
        let refusing = Double.answering(asked, refusing: { $0.contains(refusedWord) })
        let reading = await GitHub.$commandOverride.withValue(refusing) {
            await StartingPointReader.load(request, from: readings)
        }
        #expect(reading?.branches.count == 3)
        #expect(reading?.issues.isEmpty == Double.issues.contains(refusedWord))
        #expect(reading?.pullRequests.reviewRequested.isEmpty == Double.review.contains(refusedWord))
        #expect(reading?.pullRequests.authored.isEmpty == Double.authored.contains(refusedWord))

        _ = await GitHub.$commandOverride.withValue(Double.answering(asked)) {
            await StartingPointReader.load(request, from: readings)
        }
        #expect(await asked.commands.count == 6)
    }

    @Test("a repository with issues turned off is a whole reading with no issues, kept like any other")
    func issuesTurnedOff() async throws {
        let repo = try await Double.repository("suggestions-no-issues")
        let readings = StartingPointReader.Readings()
        let request = StartingPointReadingRequest(repoPath: repo, asksGitHub: true)
        let asked = AskedCommands()
        let turnedOff = Double.answering(
            asked, refusing: { $0.first == "issue" }, stderr: "the 'akira/lantern' repository has disabled issues"
        )
        for _ in 0..<2 {
            let reading = await GitHub.$commandOverride.withValue(turnedOff) {
                await StartingPointReader.load(request, from: readings)
            }
            #expect(reading?.issues.isEmpty == true)
            #expect(reading?.pullRequests.reviewRequested.map(\.number) == [21])
        }
        #expect(await asked.commands.count == 3)
    }

    @Test("a pull request listing that answered lets the suggestions ask GitHub")
    func isListed() {
        #expect(PullRequestLoad.listed([]).isListed)
        #expect(!PullRequestLoad.loading.isListed)
        #expect(!PullRequestLoad.unavailable("Sign in with gh to list pull requests").isListed)
    }
}
