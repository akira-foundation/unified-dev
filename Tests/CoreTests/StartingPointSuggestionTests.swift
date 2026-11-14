import Foundation
import Testing
@testable import Core

@Suite("Starting points suggested below the new workspace composer")
struct StartingPointSuggestionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func request(_ number: Int, head: String = "", draft: Bool = false, fork: Bool = false) -> PullRequestListing {
        PullRequestListing(
            number: number, title: "Request \(number)", author: "kid",
            headRefName: head.isEmpty ? "head-\(number)" : head, baseRefName: "main", isDraft: draft,
            isCrossRepository: fork, headRepositoryOwner: fork ? "someone" : nil
        )
    }

    private func branch(_ name: String, hoursAgo: Double) -> RecentBranch {
        RecentBranch(name: name, touched: now.addingTimeInterval(-hoursAgo * 3600))
    }

    private func suggestions(
        review: [PullRequestListing] = [],
        authored: [PullRequestListing] = [],
        issues: [AssignedIssue] = [],
        branches: [RecentBranch] = [],
        holders: [String: BranchHolder] = [:],
        open: [PullRequestListing] = []
    ) -> [StartingPointSuggestion] {
        let reading = StartingPointReading(
            pullRequests: PullRequestsAwaitingViewer(reviewRequested: review, authored: authored),
            issues: issues, branches: branches
        )
        return StartingPointSuggestions.choose(
            reading, defaultBranch: "main", holders: holders, openPullRequests: open, now: now
        )
    }

    @Test("every kind gets a row before any kind gets a second, in order of who is waiting")
    func interleavesKinds() {
        let chosen = suggestions(
            review: [request(1), request(2)],
            authored: [request(3), request(4)],
            issues: [AssignedIssue(number: 5, title: "Five"), AssignedIssue(number: 6, title: "Six")],
            branches: [branch("spike", hoursAgo: 2), branch("tidy", hoursAgo: 3)]
        )
        #expect(chosen == [
            .reviewRequested(request(1)), .authored(request(3)),
            .issue(AssignedIssue(number: 5, title: "Five")), .branch(branch("spike", hoursAgo: 2)),
        ])
    }

    @Test("a kind with nothing in it leaves its room to the others, still grouped by kind")
    func fillsFromTheRest() {
        let chosen = suggestions(
            review: [request(1), request(2), request(7)],
            branches: [branch("spike", hoursAgo: 2), branch("tidy", hoursAgo: 3), branch("old", hoursAgo: 4)]
        )
        #expect(chosen.map(\.id) == ["pr:1", "pr:2", "branch:spike", "branch:tidy"])
    }

    @Test("a project with no remote is offered its recent branches alone, newest first")
    func noRemote() {
        let chosen = suggestions(branches: [
            branch("b", hoursAgo: 30), branch("a", hoursAgo: 1), branch("c", hoursAgo: 50),
            branch("d", hoursAgo: 70), branch("e", hoursAgo: 90),
        ])
        #expect(chosen.map(\.id) == ["branch:a", "branch:b", "branch:c", "branch:d"])
    }

    @Test("a branch is left out when it is the default, held, stale, or any open pull request's head")
    func branchesLeftOut() {
        let chosen = suggestions(
            review: [request(8, head: "reviewing")],
            authored: [request(9, head: "paint")],
            branches: [
                branch("main", hoursAgo: 1),
                branch("held", hoursAgo: 1),
                branch("paint", hoursAgo: 1),
                branch("reviewing", hoursAgo: 1),
                branch("theirs", hoursAgo: 1),
                branch("ancient", hoursAgo: 24 * 14 + 0.01),
                branch("fortnight", hoursAgo: 24 * 14),
            ],
            holders: ["held": .workspace("lisbon")],
            open: [request(40, head: "theirs")]
        )
        #expect(chosen.map(\.id) == ["pr:8", "pr:9", "branch:fortnight"])
    }

    @Test("a fork's pull request does not hide a local branch that shares its name")
    func forkHeadsDoNotHide() {
        let chosen = suggestions(branches: [branch("fix", hoursAgo: 1)], open: [request(41, head: "fix", fork: true)])
        #expect(chosen.map(\.id) == ["branch:fix"])
    }

    @Test("a pull request both authored and awaiting review appears once, as a review")
    func noDuplicateRequests() {
        let chosen = suggestions(review: [request(4)], authored: [request(4), request(5)])
        #expect(chosen == [.reviewRequested(request(4)), .authored(request(5))])
        #expect(chosen.map { $0.reason(now: now) } == ["Review requested", "Your pull request"])
    }

    @Test("nothing to suggest is an empty list, so the column stays clean")
    func empty() {
        #expect(suggestions().isEmpty)
    }

    @Test("picking a pull request or a branch opens it, picking an issue cuts a branch from the default")
    func picks() {
        let listed = request(12)
        #expect(StartingPointSuggestion.reviewRequested(listed).pick(defaultBranch: "develop").startingPoint
            == .pullRequest(listed))
        #expect(StartingPointSuggestion.authored(listed).pick(defaultBranch: "develop").source
            == .pullRequest(.listed(listed)))
        #expect(StartingPointSuggestion.branch(branch("spike", hoursAgo: 1)).pick(defaultBranch: "develop").startingPoint
            == .existingBranch(ExistingBranch(name: "spike", isLocal: true)))

        let issue = StartingPointSuggestion.issue(AssignedIssue(number: 34, title: "Suggest starting points"))
            .pick(defaultBranch: "develop")
        #expect(issue.startingPoint == .newBranch(from: "develop"))
        #expect(issue.addsToPrompt)
        #expect(issue.prompt == "Work on issue #34, \"Suggest starting points\".")
        #expect(StartingPointSuggestion.issue(AssignedIssue(number: 8, title: "")).pick(defaultBranch: "main").prompt
            == "Work on issue #8.")
        #expect(!StartingPointSuggestion.authored(listed).pick(defaultBranch: "develop").addsToPrompt)
        #expect(StartingPointSuggestion.authored(listed).pick(defaultBranch: "develop").prompt == nil)
    }

    @Test("an issue's line joins what was typed, once, and a second issue replaces the first")
    func issuePrompt() {
        let pick = StartingPointSuggestion.issue(AssignedIssue(number: 34, title: "Suggest")).pick(defaultBranch: "main")
        let line = "Work on issue #34, \"Suggest\"."
        #expect(pick.prompt(into: "") == line)
        #expect(pick.prompt(into: "Keep it small") == "Keep it small\n\n" + line)
        #expect(pick.prompt(into: "Fix #34") == "Fix #34")
        #expect(pick.prompt(into: "See #345 and #34 first") == "See #345 and #34 first")
        #expect(pick.prompt(into: "See #345") == "See #345\n\n" + line)

        let other = StartingPointSuggestion.issue(AssignedIssue(number: 40, title: "Other")).pick(defaultBranch: "main")
        #expect(other.prompt(into: "Keep it small\n\n" + line) == "Keep it small\n\nWork on issue #40, \"Other\".")

        #expect(other.prompt(into: line + "\nKeep the public API stable")
            == "Keep the public API stable\n\nWork on issue #40, \"Other\".")
        #expect(other.prompt(into: "Work on issue #12 first, then rebase.\n\n" + line)
            == "Work on issue #12 first, then rebase.\n\nWork on issue #40, \"Other\".")
        #expect(other.prompt(into: line + "\n\nThen #40 too") == "Then #40 too")
        #expect(pick.prompt(into: line) == line)

        let open = StartingPointSuggestion.branch(branch("spike", hoursAgo: 1)).pick(defaultBranch: "main")
        #expect(open.prompt(into: "Typed\n\n" + line) == "Typed\n\n" + line)
    }

    @Test("replacing an issue's line takes that line and one blank beside it, and leaves the rest as typed")
    func issueLineReplacedInPlace() {
        let other = StartingPointSuggestion.issue(AssignedIssue(number: 40, title: "Other")).pick(defaultBranch: "main")
        let replacement = "Work on issue #40, \"Other\"."
        #expect(other.prompt(into: "A\n\nWork on issue #34, \"Old\".\n\nB") == "A\n\nB\n\n" + replacement)
        #expect(other.prompt(into: "Intro\n  Work on issue #34.\n    indented code")
            == "Intro\n    indented code\n\n" + replacement)
        #expect(other.prompt(into: "Typed\r\n\r\nWork on issue #34, \"Old\".\r") == "Typed\n\n" + replacement)
        #expect(other.prompt(into: "Please Work on issue #12.") == "Please Work on issue #12.\n\n" + replacement)
        #expect(StartingPointSuggestionPick.withoutIssueLines("  keep\n\n\n\nthis  ") == "  keep\n\n\n\nthis  ")
        #expect(StartingPointSuggestionPick.withoutIssueLines("A\n\nWork on issue #34.\nB") == "A\n\nB")
        #expect(StartingPointSuggestionPick.withoutIssueLines("A\n\nWork on issue #34.\n\nB") == "A\n\nB")
        #expect(StartingPointSuggestionPick.withoutIssueLines("A\n\nWork on issue #34.") == "A")
        #expect(StartingPointSuggestionPick.withoutIssueLines("A\n\nWork on issue #1.\nWork on issue #2.") == "A")
    }

    @Test("an issue's line is added only when the pick is used as the starting point")
    func issuePromptFollowsTheDecision() {
        let pick = StartingPointSuggestion.issue(AssignedIssue(number: 34, title: "")).pick(defaultBranch: "main")
        #expect(pick.prompt(into: "Typed", after: .use(.newBranch(from: "main"))) == "Typed\n\nWork on issue #34.")
        #expect(pick.prompt(into: "Typed", after: .use(.newBranch(from: "develop"))) == "Typed")
        #expect(pick.prompt(into: "Typed", after: .goTo(WorkspaceID("w1"))) == "Typed")
        #expect(pick.prompt(into: "Typed", after: .refuse("Taken")) == "Typed")
    }

    @Test("the line an issue adds is always a line that a later pick knows to replace")
    func issueLineIsRecognised() throws {
        for title in ["Suggest starting points", "", "Fix \"quoted\" titles", "A, B, and C."] {
            let pick = StartingPointSuggestion.issue(AssignedIssue(number: 7, title: title)).pick(defaultBranch: "main")
            #expect(StartingPointSuggestionPick.isIssueLine(try #require(pick.prompt)))
        }
    }

    @Test("the row that is already the starting point says so")
    func chosen() {
        let listed = request(3)
        let spike = branch("spike", hoursAgo: 1)
        #expect(StartingPointSuggestion.authored(listed).isChosen(by: .pullRequest(listed)))
        #expect(StartingPointSuggestion.reviewRequested(listed).isChosen(by: .pullRequest(listed)))
        #expect(!StartingPointSuggestion.authored(listed).isChosen(by: .pullRequest(request(4))))
        #expect(StartingPointSuggestion.branch(spike)
            .isChosen(by: .existingBranch(ExistingBranch(name: "spike", isLocal: false))))
        #expect(!StartingPointSuggestion.branch(spike).isChosen(by: .newBranch(from: "spike")))
        #expect(!StartingPointSuggestion.branch(spike)
            .isChosen(by: .existingBranch(ExistingBranch(name: "tidy", isLocal: true))))
        #expect(!StartingPointSuggestion.issue(AssignedIssue(number: 1, title: "")).isChosen(by: .newBranch(from: "main")))
    }

    @Test("a row wears the glyph of the starting point it sets, the same as the chip")
    func glyphs() {
        #expect(StartingPointSuggestion.reviewRequested(request(1)).glyph == "arrow.triangle.pull")
        #expect(StartingPointSuggestion.branch(branch("a", hoursAgo: 1)).glyph == "arrow.triangle.branch")
        #expect(StartingPointSuggestion.issue(AssignedIssue(number: 2, title: "")).glyph
            == StartingPointLabel.glyph(for: .newBranch(from: "main")))
    }

    @Test("each row says why it is there")
    func reasons() {
        #expect(StartingPointSuggestion.reviewRequested(request(1)).reason(now: now) == "Review requested")
        #expect(StartingPointSuggestion.authored(request(1)).reason(now: now) == "Your pull request")
        #expect(StartingPointSuggestion.authored(request(1, draft: true)).reason(now: now) == "Your draft")
        #expect(StartingPointSuggestion.issue(AssignedIssue(number: 1, title: "")).reason(now: now) == "Assigned to you")
        #expect(StartingPointSuggestion.branch(branch("a", hoursAgo: -3)).reason(now: now) == "Touched just now")
        #expect(StartingPointSuggestion.branch(branch("a", hoursAgo: 0.2)).reason(now: now) == "Touched 12m ago")
        #expect(StartingPointSuggestion.branch(branch("a", hoursAgo: 5)).reason(now: now) == "Touched 5h ago")
        #expect(StartingPointSuggestion.branch(branch("a", hoursAgo: 80)).reason(now: now) == "Touched 3d ago")
    }

    @Test("a row reads as what it is, and has something to show with no title")
    func titles() {
        let untitled = PullRequestListing(number: 9, title: "", headRefName: "spike", baseRefName: "main")
        #expect(StartingPointSuggestion.authored(untitled).title == "spike")
        #expect(StartingPointSuggestion.reviewRequested(request(10, head: "fix", fork: true).untitled).title
            == "someone:fix")
        #expect(StartingPointSuggestion.reviewRequested(request(10)).reference == "#10")
        #expect(StartingPointSuggestion.issue(AssignedIssue(number: 8, title: "")).id == "issue:8")
        #expect(StartingPointSuggestion.authored(request(9)).title == "Request 9")
        #expect(StartingPointSuggestion.issue(AssignedIssue(number: 8, title: "")).title == "Issue #8")
        #expect(StartingPointSuggestion.issue(AssignedIssue(number: 8, title: "Fix")).reference == "#8")
        #expect(StartingPointSuggestion.branch(branch("a", hoursAgo: 1)).reference == nil)
        #expect(StartingPointSuggestion.authored(request(9)).spoken == "pull request #9, Request 9")
        #expect(StartingPointSuggestion.reviewRequested(untitled).spoken == "pull request #9, spike")
        #expect(StartingPointSuggestion.issue(AssignedIssue(number: 8, title: "Fix")).spoken == "issue #8, Fix")
        #expect(StartingPointSuggestion.issue(AssignedIssue(number: 8, title: "")).spoken == "issue #8")
        #expect(StartingPointSuggestion.branch(branch("a", hoursAgo: 1)).spoken == "existing branch a")
    }

    @Test("GitHub is asked only once the pull requests answered, and nothing is read while they load")
    func readingRequest() {
        #expect(StartingPointReadingRequest(repoPath: "/p", offersPullRequests: nil, pullRequests: .listed([])) == nil)
        #expect(StartingPointReadingRequest(repoPath: "/p", offersPullRequests: true, pullRequests: .loading) == nil)
        #expect(StartingPointReadingRequest(repoPath: "/p", offersPullRequests: true, pullRequests: .listed([]))?.asksGitHub
            == true)
        #expect(StartingPointReadingRequest(
            repoPath: "/p", offersPullRequests: true, pullRequests: .unavailable("Sign in with gh")
        )?.asksGitHub == false)
        #expect(StartingPointReadingRequest(repoPath: "/p", offersPullRequests: false, pullRequests: .listed([]))?.asksGitHub
            == false)
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
        #expect(GitHub.decodeAssignedIssues(from: Data("not json".utf8)) == nil)
    }
}

private extension PullRequestListing {
    var untitled: PullRequestListing {
        PullRequestListing(
            number: number, title: "", author: author, headRefName: headRefName, baseRefName: baseRefName,
            isDraft: isDraft, state: state, isCrossRepository: isCrossRepository,
            headRepositoryOwner: headRepositoryOwner
        )
    }
}
