import Foundation
import Testing
@testable import Core

@Suite("The starting point chip")
struct StartingPointLabelTests {
    private let branch = ExistingBranch(name: "feat/x", isLocal: true)
    private let request = PullRequestListing(
        number: 13, title: "Paint the boats", author: "kid", headRefName: "paint", baseRefName: "main"
    )

    @Test("it reads as a sentence for each kind of start")
    func readsAsASentence() {
        #expect(StartingPointLabel.text(for: .newBranch(from: "main"), remote: "origin") == "from origin/main")
        #expect(StartingPointLabel.text(for: .newBranch(from: "spike"), remote: nil) == "from spike")
        #expect(StartingPointLabel.text(for: .existingBranch(branch), remote: "origin") == "on feat/x")
        #expect(StartingPointLabel.text(for: .pullRequest(request), remote: "origin") == "PR #13")
    }

    @Test("VoiceOver hears what kind of start it is")
    func spoken() {
        #expect(StartingPointLabel.accessibilityLabel == "Starting point")
        #expect(StartingPointLabel.spoken(for: .newBranch(from: "main"), remote: "origin")
            == "new branch from origin/main")
        #expect(StartingPointLabel.spoken(for: .existingBranch(branch), remote: nil) == "existing branch feat/x")
        #expect(StartingPointLabel.spoken(for: .pullRequest(request), remote: nil)
            == "pull request #13, Paint the boats")
    }

    @Test("a new branch is created, a branch or a pull request that exists is opened")
    func createOrOpen() {
        #expect(StartingPointLabel.action(for: .newBranch(from: "main")) == .create)
        #expect(StartingPointLabel.action(for: .existingBranch(branch)) == .open)
        #expect(StartingPointLabel.action(for: .pullRequest(request)) == .open)
        #expect(WorkspaceDraftAction.create.title == "Create")
        #expect(WorkspaceDraftAction.open.title == "Open")
    }

    @Test("the line under the heading says what the button will do, and nothing happens before it")
    func explains() {
        #expect(StartingPointLabel.explanation(for: .newBranch(from: "main"), remote: "origin")
            .contains("new branch from origin/main"))
        #expect(StartingPointLabel.explanation(for: .newBranch(from: "main"), remote: nil)
            .contains("Nothing is written to disk"))
        #expect(StartingPointLabel.explanation(for: .existingBranch(branch), remote: nil).hasPrefix("Open checks out feat/x"))
        #expect(StartingPointLabel.explanation(for: .pullRequest(request), remote: nil)
            .hasPrefix("Open checks out pull request #13"))
    }

    @Test("each kind has its own glyph")
    func glyphs() {
        #expect(StartingPointLabel.glyph(for: .newBranch(from: "main")) == "plus.circle")
        #expect(StartingPointLabel.glyph(for: .existingBranch(branch)) == "arrow.triangle.branch")
        #expect(StartingPointLabel.glyph(for: .pullRequest(request)) == "arrow.triangle.pull")
    }
}

@Suite("The starting point popover")
struct StartingPointMenuTests {
    private let request = PullRequestListing(
        number: 13, title: "Paint the boats", author: "kid", headRefName: "paint", baseRefName: "main"
    )
    private var offering: WorkspaceSourceOffering {
        WorkspaceSourceOffering(
            pullRequests: [request],
            branches: [ExistingBranch(name: "bell", isLocal: true), ExistingBranch(name: "lamp", isLocal: false)],
            baseBranches: ["bell", "lamp", "main"]
        )
    }

    @Test("three sections, in order, each with its own title")
    func threeSections() {
        let sections = StartingPointMenu.sections(
            offering: offering, query: "", leadingBases: [], offersPullRequests: true
        )
        #expect(sections.map(\.kind) == [.newBranch, .existingBranch, .pullRequest])
        #expect(sections.map(\.title) == ["New branch from", "Existing branch", "Pull request"])
        #expect(sections[1].rows.allSatisfy { if case .existingBranch = $0 { true } else { false } })
        #expect(sections[2].rows == [.pullRequest(.listed(request))])
    }

    @Test("the branch you came from leads the new branch section while nothing is typed")
    func leadingBase() {
        let sections = StartingPointMenu.sections(
            offering: offering, query: "", leadingBases: ["lamp"], offersPullRequests: true
        )
        #expect(sections[0].rows.first == .newBranch(from: "lamp"))
        #expect(sections[0].rows.count == 3)
    }

    @Test("a project without a remote has no pull request section")
    func noRemoteNoRequests() {
        let sections = StartingPointMenu.sections(
            offering: offering, query: "", leadingBases: [], offersPullRequests: false
        )
        #expect(!sections.map(\.kind).contains(.pullRequest))
    }

    @Test("an empty section is left out")
    func emptySectionsGo() {
        let sections = StartingPointMenu.sections(
            offering: offering, query: "bell", leadingBases: [], offersPullRequests: true
        )
        #expect(!sections.map(\.kind).contains(.pullRequest))
        #expect(sections.map(\.kind).contains(.existingBranch))
    }

    @Test("typing #13 jumps to that pull request")
    func jumpsToAPullRequest() {
        let sections = StartingPointMenu.sections(
            offering: offering, query: "#13", leadingBases: [], offersPullRequests: true
        )
        #expect(StartingPointMenu.jump(query: "#13", in: sections) == .pullRequest(.listed(request)))
    }

    @Test("typing a number nobody listed offers to look it up")
    func typedNumberIsOffered() {
        let sections = StartingPointMenu.sections(
            offering: offering, query: "#99", leadingBases: [], offersPullRequests: true
        )
        let jumped = StartingPointMenu.jump(query: "#99", in: sections)
        guard case .pullRequest(.typed(let reference, _)) = jumped else {
            Issue.record("expected a typed pull request")
            return
        }
        #expect(reference.number == 99)
    }

    @Test("the arrow keys walk every row across the sections")
    func stepsAcrossSections() {
        let sections = StartingPointMenu.sections(
            offering: offering, query: "", leadingBases: [], offersPullRequests: true
        )
        let rows = StartingPointMenu.rows(in: sections)
        let last = StartingPointMenu.stepped(from: rows[2], by: 1, in: sections)
        #expect(last == rows[3])
        #expect(rows.count == 6)
    }

    @Test("the branch you came from stops leading once something is typed")
    func leadingBaseRestsOnlyWhenNothingIsTyped() {
        let sections = StartingPointMenu.sections(
            offering: offering, query: "bell", leadingBases: ["lamp"], offersPullRequests: true
        )
        #expect(sections.first?.rows.first != .newBranch(from: "lamp"))
    }

    @Test("a project without pull requests never jumps to one")
    func noJumpWithoutRequests() {
        let sections = StartingPointMenu.sections(
            offering: offering, query: "#13", leadingBases: [], offersPullRequests: false
        )
        #expect(StartingPointMenu.jump(query: "#13", in: sections) == nil)
    }
}

@Suite("What a chosen starting point does")
struct StartingPointPickTests {
    private let repoID = RepoID("harbour")

    @Test("a base is used as it is")
    func baseIsUsed() {
        #expect(StartingPointPick.decide(
            .newBranch(from: "main"), holders: [:], taken: [], repoID: repoID, workspaces: []
        ) == .use(.newBranch(from: "main")))
    }

    @Test("a free branch is used")
    func freeBranchIsUsed() {
        let bell = ExistingBranch(name: "bell", isLocal: true)
        #expect(StartingPointPick.decide(
            .existingBranch(bell), holders: [:], taken: ["bell"], repoID: repoID, workspaces: []
        ) == .use(.existingBranch(bell)))
    }

    @Test("a branch one of our workspaces holds takes you to that workspace")
    func heldByOursGoesThere() {
        let held = Workspace(repoID: repoID, name: "Bell", branch: "bell", path: "/ws/bell", baseBranch: "main")
        let bell = ExistingBranch(name: "bell", isLocal: true, inUseBy: .workspace("Bell"))
        #expect(StartingPointPick.decide(
            .existingBranch(bell), holders: ["bell": .workspace("Bell")], taken: ["bell"],
            repoID: repoID, workspaces: [held]
        ) == .goTo(held.id))
    }

    @Test("a branch held elsewhere is refused with who holds it and the way out")
    func heldElsewhereIsRefused() {
        let bell = ExistingBranch(name: "bell", isLocal: true)
        let holder = BranchHolder.otherWorktree(path: "/elsewhere/bell")
        #expect(StartingPointPick.decide(
            .existingBranch(bell), holders: ["bell": holder], taken: ["bell"], repoID: repoID, workspaces: []
        ) == .refuse(holder.refusal(branch: "bell")))
    }

    @Test("a typed pull request is looked up first")
    func typedIsLookedUp() {
        let typed = WorkspaceSource.pullRequest(.typed(PullRequestReference(number: 13), text: "#13"))
        #expect(StartingPointPick.decide(typed, holders: [:], taken: [], repoID: repoID, workspaces: [])
            == .lookUp("#13"))
    }

    @Test("the refusal points at New branch from, not at a tab that is gone")
    func refusalNamesTheSection() {
        let sentence = BranchHolder.otherWorktree(path: "/elsewhere").refusal(branch: "bell")
        #expect(sentence.contains("New branch from"))
        #expect(!sentence.contains("tab"))
    }

    @Test("a listed pull request whose head a workspace of ours holds, but which we cannot find, is refused")
    func heldRequestWithoutItsWorkspaceIsRefused() {
        let request = PullRequestListing(number: 13, title: "t", headRefName: "paint", baseRefName: "main")
        let pick = StartingPointPick.decide(
            .pullRequest(.listed(request)), holders: ["paint": .workspace("Paint")], taken: ["paint"],
            repoID: repoID, workspaces: []
        )
        guard case .refuse = pick else {
            Issue.record("expected a refusal, got \(pick)")
            return
        }
    }
}
