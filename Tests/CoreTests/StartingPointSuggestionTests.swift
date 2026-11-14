import Foundation
import Testing
@testable import Core

@Suite("Starting points suggested below the new workspace composer")
struct StartingPointSuggestionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func request(_ number: Int, head: String = "", draft: Bool = false) -> PullRequestListing {
        PullRequestListing(
            number: number, title: "Request \(number)", author: "kid",
            headRefName: head.isEmpty ? "head-\(number)" : head, baseRefName: "main", isDraft: draft
        )
    }

    private func branch(_ name: String, hoursAgo: Double) -> RecentBranch {
        RecentBranch(name: name, touched: now.addingTimeInterval(-hoursAgo * 3600))
    }

    private func choose(
        review: [PullRequestListing] = [],
        authored: [PullRequestListing] = [],
        issues: [AssignedIssue] = [],
        branches: [RecentBranch] = [],
        holders: [String: BranchHolder] = [:]
    ) -> [String] {
        let reading = StartingPointReading(
            pullRequests: PullRequestsAwaitingViewer(reviewRequested: review, authored: authored),
            issues: issues, branches: branches, readAt: now
        )
        return StartingPointSuggestions.choose(reading, defaultBranch: "main", holders: holders, now: now).map(\.id)
    }

    @Test("every kind gets a row before any kind gets a second, in order of who is waiting")
    func interleavesKinds() {
        let chosen = choose(
            review: [request(1), request(2)],
            authored: [request(3), request(4)],
            issues: [AssignedIssue(number: 5, title: "Five"), AssignedIssue(number: 6, title: "Six")],
            branches: [branch("spike", hoursAgo: 2), branch("tidy", hoursAgo: 3)]
        )
        #expect(chosen == ["pr:1", "pr:3", "issue:5", "branch:spike"])
    }

    @Test("a kind with nothing in it leaves its room to the others, still grouped by kind")
    func fillsFromTheRest() {
        let chosen = choose(
            review: [request(1), request(2), request(7)],
            branches: [branch("spike", hoursAgo: 2), branch("tidy", hoursAgo: 3), branch("old", hoursAgo: 4)]
        )
        #expect(chosen == ["pr:1", "pr:2", "branch:spike", "branch:tidy"])
    }

    @Test("a project with no remote is offered its recent branches alone, newest first")
    func noRemote() {
        let chosen = choose(branches: [
            branch("b", hoursAgo: 30), branch("a", hoursAgo: 1), branch("c", hoursAgo: 50),
            branch("d", hoursAgo: 70), branch("e", hoursAgo: 90),
        ])
        #expect(chosen == ["branch:a", "branch:b", "branch:c", "branch:d"])
    }

    @Test("a branch is left out when it is the default, held, a suggested pull request's head, or stale")
    func branchesLeftOut() {
        let chosen = choose(
            authored: [request(9, head: "paint")],
            branches: [
                branch("main", hoursAgo: 1),
                branch("held", hoursAgo: 1),
                branch("paint", hoursAgo: 1),
                branch("ancient", hoursAgo: 24 * 15),
                branch("fresh", hoursAgo: 24 * 13),
            ],
            holders: ["held": .workspace("lisbon")]
        )
        #expect(chosen == ["pr:9", "branch:fresh"])
    }

    @Test("a pull request both authored and awaiting review appears once, as a review")
    func noDuplicateRequests() {
        let chosen = choose(review: [request(4)], authored: [request(4), request(5)])
        #expect(chosen == ["pr:4", "pr:5"])
    }

    @Test("nothing to suggest is an empty list, so the column stays clean")
    func empty() {
        #expect(choose().isEmpty)
    }

    @Test("picking a pull request or a branch opens it, picking an issue cuts a branch from the default")
    func picks() {
        let listed = request(12)
        #expect(StartingPointSuggestion.reviewRequested(listed).pick(defaultBranch: "develop").source
            == .pullRequest(.listed(listed)))
        #expect(StartingPointSuggestion.branch(branch("spike", hoursAgo: 1)).pick(defaultBranch: "develop").source
            == .existingBranch(ExistingBranch(name: "spike", isLocal: true)))

        let issue = StartingPointSuggestion.issue(AssignedIssue(number: 34, title: "Suggest starting points"))
            .pick(defaultBranch: "develop")
        #expect(issue.source == .newBranch(from: "develop"))
        #expect(issue.prompt == "Work on issue #34: Suggest starting points")
        #expect(StartingPointSuggestion.authored(listed).pick(defaultBranch: "develop").prompt == nil)
    }

    @Test("an issue's line is added to what was typed, and not twice")
    func issuePrompt() {
        let pick = StartingPointSuggestion.issue(AssignedIssue(number: 34, title: "Suggest")).pick(defaultBranch: "main")
        #expect(pick.prompt(into: "") == "Work on issue #34: Suggest")
        #expect(pick.prompt(into: "Keep it small") == "Keep it small\n\nWork on issue #34: Suggest")
        #expect(pick.prompt(into: "See #34 first") == "See #34 first")
        #expect(pick.prompt(into: "See #345") == "See #345\n\nWork on issue #34: Suggest")

        let open = StartingPointSuggestion.branch(branch("spike", hoursAgo: 1)).pick(defaultBranch: "main")
        #expect(open.prompt(into: "Typed") == "Typed")
    }

    @Test("the row that is already the starting point says so")
    func chosen() {
        let listed = request(3)
        let spike = branch("spike", hoursAgo: 1)
        #expect(StartingPointSuggestion.authored(listed).isChosen(by: .pullRequest(listed)))
        #expect(!StartingPointSuggestion.authored(listed).isChosen(by: .pullRequest(request(4))))
        #expect(StartingPointSuggestion.branch(spike)
            .isChosen(by: .existingBranch(ExistingBranch(name: "spike", isLocal: false))))
        #expect(!StartingPointSuggestion.branch(spike).isChosen(by: .newBranch(from: "spike")))
        #expect(!StartingPointSuggestion.issue(AssignedIssue(number: 1, title: "")).isChosen(by: .newBranch(from: "main")))
    }

    @Test("each row says why it is there")
    func reasons() {
        #expect(StartingPointSuggestion.reviewRequested(request(1)).reason(now: now) == "Review requested")
        #expect(StartingPointSuggestion.authored(request(1)).reason(now: now) == "Your pull request")
        #expect(StartingPointSuggestion.authored(request(1, draft: true)).reason(now: now) == "Your draft")
        #expect(StartingPointSuggestion.issue(AssignedIssue(number: 1, title: "")).reason(now: now) == "Assigned to you")
        #expect(StartingPointSuggestion.branch(branch("a", hoursAgo: 0.2)).reason(now: now) == "Touched just now")
        #expect(StartingPointSuggestion.branch(branch("a", hoursAgo: 1)).reason(now: now) == "Touched an hour ago")
        #expect(StartingPointSuggestion.branch(branch("a", hoursAgo: 5)).reason(now: now) == "Touched 5 hours ago")
        #expect(StartingPointSuggestion.branch(branch("a", hoursAgo: 30)).reason(now: now) == "Touched yesterday")
        #expect(StartingPointSuggestion.branch(branch("a", hoursAgo: 80)).reason(now: now) == "Touched 3 days ago")
    }

    @Test("an issue with no title still has something to read")
    func untitled() {
        #expect(StartingPointSuggestion.issue(AssignedIssue(number: 8, title: "")).title == "Issue #8")
        #expect(StartingPointSuggestion.issue(AssignedIssue(number: 8, title: "Fix")).reference == "#8")
        #expect(StartingPointSuggestion.branch(branch("a", hoursAgo: 1)).reference == nil)
    }

    @Test("git's branch listing is read by recency, skipping lines it cannot parse")
    func parsesBranches() {
        let parsed = RecentBranch.parse("feat/a\t1800000000\nbroken\n\t17\nfeat/b\tlater\nfix/c\t1700000000\n")
        #expect(parsed == [
            RecentBranch(name: "feat/a", touched: Date(timeIntervalSince1970: 1_800_000_000)),
            RecentBranch(name: "fix/c", touched: Date(timeIntervalSince1970: 1_700_000_000)),
        ])
    }

    @Test("gh's issue listing keeps what has a number")
    func decodesIssues() {
        let json = #"[{"number":34,"title":"Suggest"},{"number":0,"title":"zero"},{"title":"none"},{"number":7}]"#
        #expect(GitHub.decodeAssignedIssues(from: Data(json.utf8))
            == [AssignedIssue(number: 34, title: "Suggest"), AssignedIssue(number: 7, title: "")])
        #expect(GitHub.decodeAssignedIssues(from: Data("not json".utf8)).isEmpty)
    }
}
