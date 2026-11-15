import Foundation
import Testing
@testable import Core

@Suite("Workspace checkout")
struct WorkspaceCheckoutTests {
    private func listing(
        number: Int = 12,
        title: String = "Fix the parser",
        head: String = "fix-parser",
        base: String = "main",
        state: String = "OPEN",
        isDraft: Bool = false,
        fork: Bool = false,
        owner: String? = nil
    ) -> PullRequestListing {
        PullRequestListing(
            number: number,
            title: title,
            author: "contributor",
            headRefName: head,
            baseRefName: base,
            isDraft: isDraft,
            state: state,
            isCrossRepository: fork,
            headRepositoryOwner: owner
        )
    }

    @Test("Open pull requests are offered newest first")
    func offersOpenNewestFirst() {
        let offered = WorkspaceCheckoutPlan.offered([
            listing(number: 3), listing(number: 9), listing(number: 5),
        ])
        #expect(offered.map(\.number) == [9, 5, 3])
    }

    @Test("Closed and merged pull requests are not offered")
    func skipsClosedAndMerged() {
        let offered = WorkspaceCheckoutPlan.offered([
            listing(number: 1, state: "MERGED"),
            listing(number: 2, state: "CLOSED"),
            listing(number: 3, state: "OPEN"),
        ])
        #expect(offered.map(\.number) == [3])
    }

    @Test("A draft is offered, because a draft is exactly what gets pulled down to look at")
    func offersDrafts() {
        #expect(WorkspaceCheckoutPlan.offered([listing(isDraft: true)]).count == 1)
    }

    @Test("The list is capped, so a busy repository does not fill the screen")
    func capsTheList() {
        let many = (1...80).map { listing(number: $0) }
        #expect(WorkspaceCheckoutPlan.offered(many, limit: 5).map(\.number) == [80, 79, 78, 77, 76])
    }

    @Test("A bare number, with or without its hash, is a pull request")
    func parsesNumbers() {
        #expect(WorkspaceCheckoutPlan.parseReference("42") == PullRequestReference(number: 42))
        #expect(WorkspaceCheckoutPlan.parseReference(" #42 ") == PullRequestReference(number: 42))
    }

    @Test("A pull request URL carries its repository with it")
    func parsesURLs() {
        #expect(
            WorkspaceCheckoutPlan.parseReference("https://github.com/akira-io/laravel-backup/pull/1234")
                == PullRequestReference(number: 1234, repository: "akira-io/laravel-backup", forge: .gitHub)
        )
        #expect(
            WorkspaceCheckoutPlan.parseReference("https://github.com/akira-io/ray/pull/7/files#r12345")
                == PullRequestReference(number: 7, repository: "akira-io/ray", forge: .gitHub)
        )
        #expect(
            WorkspaceCheckoutPlan.parseReference("https://github.com/acme/pull-requests/pull/4")
                == PullRequestReference(number: 4, repository: "acme/pull-requests", forge: .gitHub)
        )
    }

    @Test("Nothing that is not a pull request parses as one")
    func rejectsNonsense() {
        #expect(WorkspaceCheckoutPlan.parseReference("") == nil)
        #expect(WorkspaceCheckoutPlan.parseReference("main") == nil)
        #expect(WorkspaceCheckoutPlan.parseReference("0") == nil)
        #expect(WorkspaceCheckoutPlan.parseReference("-3") == nil)
        #expect(WorkspaceCheckoutPlan.parseReference("https://github.com/akira-io/ray/issues/7") == nil)
    }

    @Test("A pull request pasted from another repository is refused rather than resolved")
    func refusesAnotherRepository() {
        let problem = WorkspaceCheckoutResolver.problem(
            with: "https://github.com/akira-io/ray/pull/7", in: "akira-io/laravel-backup"
        )
        #expect(problem?.contains("akira-io/ray") == true)
        #expect(
            WorkspaceCheckoutResolver.problem(
                with: "https://github.com/Akira-Io/Ray/pull/7", in: "akira-io/ray"
            ) == nil
        )
        #expect(WorkspaceCheckoutResolver.problem(with: "7", in: "akira-io/ray") == nil)
        #expect(WorkspaceCheckoutResolver.problem(with: "  ", in: nil) != nil)
    }

    @Test("A pull request from this repository keeps its own branch name")
    func keepsHeadBranchName() {
        let checkout = WorkspaceCheckout.pullRequest(listing(head: "fix-parser"))
        #expect(checkout.preferredLocalBranch == "fix-parser")
        #expect(WorkspaceCheckoutPlan.localBranch(for: checkout, taken: []) == "fix-parser")
    }

    @Test("A fork's pull request keeps its head name, which is what gh looks it up by")
    func keepsForkHeadName() {
        let checkout = WorkspaceCheckout.pullRequest(
            listing(head: "patch-1", fork: true, owner: "someone")
        )
        #expect(checkout.preferredLocalBranch == "patch-1")
        #expect(WorkspaceCheckoutPlan.localBranch(for: checkout, taken: []) == "patch-1")
    }

    @Test("A fork's head name that is taken falls back to the owner's prefix")
    func prefixesForkBranchesOnCollision() {
        let checkout = WorkspaceCheckout.pullRequest(
            listing(head: "patch-1", fork: true, owner: "someone")
        )
        #expect(
            WorkspaceCheckoutPlan.localBranch(for: checkout, taken: ["patch-1"]) == "someone-patch-1"
        )
        let twice = WorkspaceCheckoutPlan.localBranch(
            for: checkout, taken: ["patch-1", "someone-patch-1"]
        )
        #expect(twice.hasPrefix("someone-patch-1"))
        #expect(twice != "someone-patch-1")
    }

    @Test("Your own pull request opens the branch it is about, even when it is already local")
    func opensItsOwnHeadBranch() {
        let checkout = WorkspaceCheckout.pullRequest(listing(head: "fix-parser"))
        #expect(
            WorkspaceCheckoutPlan.localBranch(for: checkout, taken: ["main", "fix-parser"])
                == "fix-parser"
        )
        #expect(
            WorkspaceCheckoutPlan.localBranch(for: checkout, taken: ["main"]) == "fix-parser"
        )
    }

    @Test("An existing local branch is opened as it is, not copied under a new name")
    func opensExistingBranchInPlace() {
        let checkout = WorkspaceCheckout.branch(ExistingBranch(name: "wip", isLocal: true))
        #expect(WorkspaceCheckoutPlan.localBranch(for: checkout, taken: ["main", "wip"]) == "wip")
    }

    @Test("A branch checked out from the remote keeps its own name on the row")
    func keepsRemoteBranchNameOnTheRow() {
        let checkout = WorkspaceCheckout.branch(ExistingBranch(name: "wip", isLocal: false))
        #expect(WorkspaceCheckoutPlan.localBranch(for: checkout, taken: ["main", "wip"]) == "wip")
    }

    @Test("The workspace is named after the pull request, number first")
    func namesAfterThePullRequest() {
        #expect(
            WorkspaceCheckout.pullRequest(listing(number: 12, title: "Fix the parser")).workspaceName
                == "#12 Fix the parser"
        )
        #expect(
            WorkspaceCheckout.branch(ExistingBranch(name: "wip", isLocal: true)).workspaceName == "wip"
        )
    }

    @Test("A pull request is diffed against its own base, not the project's default branch")
    func diffsAgainstThePullRequestsBase() {
        let checkout = WorkspaceCheckout.pullRequest(listing(base: "v3"))
        #expect(checkout.baseBranch(default: "main") == "v3")
    }

    @Test("A branch has nobody to ask, so it falls back to the default branch")
    func branchFallsBackToTheDefault() {
        let checkout = WorkspaceCheckout.branch(ExistingBranch(name: "wip", isLocal: true))
        #expect(checkout.baseBranch(default: "main") == "main")
    }

    @Test("A live workspace on that branch is found; an archived one is not")
    func findsTheWorkspaceHoldingABranch() {
        let repoID = RepoID("r")
        var archived = Workspace(
            repoID: repoID, name: "old", branch: "fix-parser", path: "/tmp/a", baseBranch: "main"
        )
        archived.state = .archived
        let live = Workspace(
            repoID: repoID, name: "review", branch: "fix-parser", path: "/tmp/b", baseBranch: "main"
        )
        #expect(
            WorkspaceCheckoutPlan.workspaceHolding(
                branch: "fix-parser", in: repoID, among: [archived, live]
            )?.name == "review"
        )
        #expect(
            WorkspaceCheckoutPlan.workspaceHolding(
                branch: "fix-parser", in: repoID, among: [archived]
            ) == nil
        )
    }

    @Test("a branch of the same name in another project is not this project's branch")
    func doesNotReachIntoAnotherProject() {
        let mine = RepoID("unifieddev")
        let theirs = RepoID("beacon")
        let elsewhere = Workspace(
            repoID: theirs, name: "Beacon develop", branch: "develop",
            path: "/tmp/beacon", baseBranch: "main"
        )
        let here = Workspace(
            repoID: mine, name: "Unified Dev develop", branch: "develop",
            path: "/tmp/unifieddev", baseBranch: "main"
        )

        #expect(
            WorkspaceCheckoutPlan.workspaceHolding(
                branch: "develop", in: mine, among: [elsewhere]
            ) == nil
        )
        #expect(
            WorkspaceCheckoutPlan.workspaceHolding(
                branch: "develop", in: mine, among: [elsewhere, here]
            )?.name == "Unified Dev develop"
        )
        #expect(
            WorkspaceCheckoutPlan.workspaceHolding(
                branch: "develop", in: theirs, among: [elsewhere, here]
            )?.name == "Beacon develop"
        )
    }

    @Test("A merged or closed pull request opens, and says so first")
    func warnsAboutDeadPullRequests() {
        #expect(
            WorkspaceCheckoutPlan.warning(for: .pullRequest(listing(state: "MERGED")))?
                .contains("merged") == true
        )
        #expect(
            WorkspaceCheckoutPlan.warning(for: .pullRequest(listing(state: "CLOSED")))?
                .contains("closed") == true
        )
        #expect(WorkspaceCheckoutPlan.warning(for: .pullRequest(listing())) == nil)
        #expect(
            WorkspaceCheckoutPlan.warning(for: .branch(ExistingBranch(name: "wip", isLocal: true)))
                == nil
        )
    }

    @Test("gh's list JSON decodes, logins and all")
    func decodesGHOutput() throws {
        let json = """
        [
          {
            "number": 41,
            "title": "Add a thing",
            "author": {"login": "contributor"},
            "headRefName": "add-a-thing",
            "baseRefName": "main",
            "isDraft": false,
            "state": "OPEN",
            "isCrossRepository": true,
            "headRepositoryOwner": {"login": "contributor"}
          }
        ]
        """
        let decoded = try GitHub.decodePullRequestListings(from: Data(json.utf8))
        #expect(decoded.count == 1)
        #expect(decoded[0].number == 41)
        #expect(decoded[0].author == "contributor")
        #expect(decoded[0].headRepositoryOwner == "contributor")
        #expect(decoded[0].isCrossRepository)
        #expect(WorkspaceCheckout.pullRequest(decoded[0]).preferredLocalBranch == "add-a-thing")
        #expect(
            WorkspaceCheckout.pullRequest(decoded[0]).alternateLocalBranch == "contributor-add-a-thing"
        )
    }

    @Test("A gh version that omits a field decodes rather than throwing")
    func decodesSparseOutput() throws {
        let decoded = try GitHub.decodePullRequestListings(
            from: Data("""
            [{"number": 3, "title": "t", "headRefName": "h", "baseRefName": "b"}]
            """.utf8)
        )
        #expect(decoded[0].state == "OPEN")
        #expect(decoded[0].author.isEmpty)
        #expect(!decoded[0].isCrossRepository)
    }

    @Test("A repository that is not on GitHub is recognised from gh's own words")
    func recognisesNoGitHubRemote() {
        #expect(
            GitHub.indicatesNotAGitHubRepository(
                stderr: "none of the git remotes configured for this repository point to a known GitHub host"
            )
        )
        #expect(!GitHub.indicatesNotAGitHubRepository(stderr: "could not connect to github.com"))
    }
}
