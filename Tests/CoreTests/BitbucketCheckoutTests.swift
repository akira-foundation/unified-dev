import Foundation
import Testing
@testable import Core

@Suite("Starting a workspace from a Bitbucket pull request")
struct BitbucketCheckoutTests {
    private static let repository = ForgeRepository(kind: .bitbucket, host: "bitbucket.org", owner: "debtges", name: "ledger")

    @Test("a Bitbucket pull request becomes the same listing a GitHub one does")
    func listing() throws {
        let own = try Bitbucket.decodePullRequest(BitbucketPullRequestTests.pullRequestJSON(draft: true)).listing
        let fork = try Bitbucket.decodePullRequest(
            BitbucketPullRequestTests.pullRequestJSON(sourceRepository: "someone/aui")
        ).listing

        #expect(own.number == 5486)
        #expect(own.headRefName == "issue/10.2.x/upmerge")
        #expect(own.isDraft)
        #expect(own.state == "OPEN")
        #expect(!own.isCrossRepository)
        #expect(fork.isCrossRepository)
        #expect(fork.headRepositoryOwner == "someone")
        #expect(fork.qualifiedHead == "someone:issue/10.2.x/upmerge")
    }

    @Test("bkt checks out into the named local branch, in the repository from the remote")
    func checkoutArguments() {
        #expect(Bitbucket.checkoutArguments(number: 7, localBranch: "feat/7", in: Self.repository, context: "work") == [
            "pr", "checkout", "7", "--branch", "feat/7", "--workspace", "debtges", "--repo", "ledger", "--context", "work",
        ])
        #expect(Bitbucket.openPullRequestsArguments(in: Self.repository, context: "work").contains("state=OPEN"))
    }

    @Test("a branch from this repository tracks its source, a fork's branch tracks nothing")
    func tracking() {
        let own = PullRequestListing(number: 7, title: "", headRefName: "feat/7", baseRefName: "develop")
        let fork = PullRequestListing(
            number: 8, title: "", headRefName: "feat/8", baseRefName: "develop", isCrossRepository: true
        )

        #expect(Bitbucket.trackingConfiguration(for: own, localBranch: "pr-7") == [
            ["config", "branch.pr-7.remote", "origin"],
            ["config", "branch.pr-7.merge", "refs/heads/feat/7"],
        ])
        #expect(Bitbucket.trackingConfiguration(for: fork, localBranch: "pr-8").isEmpty)
    }

    @Test("the open pull requests are read through bkt, and the slug comes from the remote")
    func listsOpenPullRequests() async throws {
        let listed = try await Forge.$remoteOverride.withValue({ _ in "git@bitbucket.org:debtges/ledger.git" }) {
            try await Bitbucket.$commandOverride.withValue({ arguments, _ in
                if arguments.starts(with: ["auth", "status"]) {
                    return ShellResult(status: 0, stdout: BitbucketPipelineLogTests.signedIn, stderr: "")
                }
                let page = "{\"values\": [\(BitbucketPullRequestTests.pullRequestJSON(id: 7))]}"
                return ShellResult(status: 0, stdout: page, stderr: "")
            }) {
                try await ForgePullRequests.openPullRequests(repoPath: "/nowhere")
            }
        }
        let slug = await Forge.$remoteOverride.withValue({ _ in "git@bitbucket.org:debtges/ledger.git" }) {
            await ForgePullRequests.repositorySlug(repoPath: "/nowhere")
        }

        #expect(listed.map(\.number) == [7])
        #expect(slug == "debtges/ledger")
    }

    @Test("an empty list on Bitbucket names bkt, not gh")
    func loadWording() {
        #expect(PullRequestLoad.from(access: .signedOut, failure: nil, requests: [], forge: .bitbucket)
            == .unavailable("Sign in with bkt to list pull requests"))
        #expect(PullRequestLoad.from(access: .signedOut, failure: nil, requests: [])
            == .unavailable("Sign in with gh to list pull requests"))
    }
}
