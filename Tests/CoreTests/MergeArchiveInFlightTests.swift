import Testing
import Foundation
@testable import Core

@Suite("When a merged pull request would archive a worktree that still has work in flight")
struct MergeArchiveInFlightTests {
    private let nextStep = "Archive it by hand once that work is done."

    @Test("a merge with nothing else in flight raises no objection")
    func nothingInFlight() {
        let branches = [
            MergeArchiveInFlight.standing(
                branch: "fix/579-a", pullRequests: [PullRequestHeadMatch(number: 579, closedAt: Date(), isOpen: false)],
                unpushedCommits: 0
            ),
            MergeArchiveInFlight.standing(branch: "develop", pullRequests: [], unpushedCommits: 0),
        ]
        #expect(MergeArchiveInFlight.objection(branches) == nil)
        #expect(MergeArchiveInFlight.objection([]) == nil)
    }

    @Test("other open pull requests from the same worktree are named to the owner")
    func openPullRequestsObject() {
        let branches = [
            MergeArchiveInFlight.standing(
                branch: "fix/580-b", pullRequests: [PullRequestHeadMatch(number: 580, closedAt: nil, isOpen: true)],
                unpushedCommits: 0
            ),
            MergeArchiveInFlight.standing(
                branch: "fix/579-a", pullRequests: [PullRequestHeadMatch(number: 579, closedAt: nil, isOpen: true)],
                unpushedCommits: 3
            ),
        ]
        #expect(MergeArchiveInFlight.objection(branches) == """
            #579 and #580 are still open. fix/579-a has 3 commits that are not pushed. \(nextStep)
            """)
        #expect(MergeArchiveInFlight.objection(Array(branches.prefix(1))) == "#580 is still open. \(nextStep)")
    }

    @Test("three open pull requests are listed with commas and a final and")
    func listsThree() {
        let branches = [583, 579, 580].map {
            MergeArchiveInFlight.standing(
                branch: "fix/\($0)", pullRequests: [PullRequestHeadMatch(number: $0, closedAt: nil, isOpen: true)],
                unpushedCommits: 0
            )
        }
        #expect(MergeArchiveInFlight.objection(branches) == "#579, #580 and #583 are still open. \(nextStep)")
    }

    @Test("a local branch with commits not on its remote is named to the owner")
    func unpushedBranchObjects() {
        let one = MergeArchiveInFlight.standing(branch: "fix/453-local", pullRequests: [], unpushedCommits: 1)
        let two = MergeArchiveInFlight.standing(branch: "fix/454-local", pullRequests: [], unpushedCommits: 2)
        #expect(MergeArchiveInFlight.objection([one, two]) == """
            fix/453-local has 1 commit that is not pushed. \
            fix/454-local has 2 commits that are not pushed. \(nextStep)
            """)
    }

    @Test("the branches of a worktree are its checkouts and its current branch, if they still exist")
    func candidatesFromReflog() {
        let reflog = """
            checkout: moving from fix/580-b to fix/586-d
            commit: something
            checkout: moving from 1234abcd to fix/580-b
            checkout: moving from nowhere
            checkout: moving from  to fix/580-b
            """
        let checkedOut = MergeArchiveInFlight.checkedOutBranches(reflogSubjects: reflog)
        #expect(checkedOut == ["fix/586-d", "fix/580-b", "1234abcd"])
        #expect(MergeArchiveInFlight.candidates(
            checkedOut: checkedOut,
            current: "renamed",
            localBranches: ["fix/586-d", "renamed", "someone-elses"]
        ) == ["renamed", "fix/586-d"])
        #expect(MergeArchiveInFlight.candidates(
            checkedOut: checkedOut, current: "fix/586-d", localBranches: ["fix/586-d", "fix/580-b"]
        ) == ["fix/586-d", "fix/580-b"])
    }

    @Test("the merged commit counts as published for every branch, beside each branch's own pull request heads")
    func publishedHeads() {
        let pullRequests = [PullRequestHeadMatch(number: 1, closedAt: nil, isOpen: false, headCommit: "aaa")]
        #expect(MergeArchiveInFlight.publishedHeads(pullRequests, mergedHead: "bbb") == ["aaa", "bbb"])
        #expect(MergeArchiveInFlight.publishedHeads([], mergedHead: nil).isEmpty)
    }

    @Test("a wait for a turn or a command keeps the merged commit until it is settled")
    func waitsKeepTheMergedHead() {
        let id = WorkspaceID("w588")
        var waits = MergeArchiveWaits()
        waits.record(.waitForCommand, for: id, pullRequest: 586, mergedHead: "abc")
        #expect(waits.mergedHeads[id] == "abc")
        _ = waits.settle(id, isAgentMidTurn: false, isCommandRunning: false, wasStopped: false)
        #expect(waits.mergedHeads[id] == nil)
        waits.record(.archiveAfterTurn, for: id, pullRequest: 586, mergedHead: "def")
        #expect(waits.mergedHeads[id] == "def")
        _ = waits.settle(id, isAgentMidTurn: false, isCommandRunning: false, wasStopped: true)
        #expect(waits.mergedHeads[id] == nil)
        waits.record(.leave, for: id, pullRequest: 586, mergedHead: "ghi")
        #expect(waits.mergedHeads[id] == nil)
    }

    @Test("a real worktree with another open pull request and an unpushed branch is not archived")
    func objectsInARealWorktree() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        try await fixture.branch("fix/579-open", push: true)
        try await fixture.branch("fix/453-local", push: false)
        try await fixture.branch("fix/586-merged", push: true)
        try await fixture.git(["tag", "fix/586-merged"])

        let objection = try await fixture.objection(mergedHead: nil, answers: [
            "fix/579-open": #"[{"number":579,"state":"OPEN"}]"#,
            "fix/586-merged": #"[{"number":586,"state":"MERGED"}]"#,
        ])
        #expect(objection == "#579 is still open. fix/453-local has 1 commit that is not pushed. \(nextStep)")
    }

    @Test("a real worktree whose other branches all landed is archived, squashed heads included")
    func archivesWhenEverythingLanded() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        try await fixture.branch("fix/560-squashed", push: false)
        let squashed = try await fixture.tip()
        try await fixture.branch("fix/586-merged", push: false)
        let merged = try await fixture.tip()

        let missing = String(repeating: "f", count: 40)
        let answers = [
            "fix/560-squashed": #"[{"number":560,"state":"MERGED","headRefOid":"\#(squashed)"},"#
                + #"{"number":561,"state":"CLOSED","headRefOid":"\#(missing)"}]"#,
        ]
        #expect(try await fixture.objection(mergedHead: merged, answers: answers) == nil)
        #expect(try await fixture.objection(mergedHead: nil, answers: answers)
            == "fix/586-merged has 1 commit that is not pushed. \(nextStep)")
    }

    @Test("a branch whose remote was deleted after its last fetch counts as not pushed")
    func staleRemoteBranchIsNotPublished() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        try await fixture.branch("fix/453-gone", push: true)
        try await Shell.check("git", ["branch", "-D", "fix/453-gone"], cwd: fixture.remote)
        try await fixture.branch("fix/586-merged", push: true)
        #expect(try await fixture.objection(mergedHead: nil, answers: [:])
            == "fix/453-gone has 1 commit that is not pushed. \(nextStep)")
    }

    @Test("more branches than can be checked holds the archive back")
    func tooManyBranches() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        for index in 0...MergeArchiveInFlight.branchLimit {
            try await fixture.git(["checkout", "-q", "-b", "fix/\(index)", "main"])
        }
        #expect(try await fixture.objection(mergedHead: nil, answers: [:]) == MergeArchiveInFlight.tooManyBranches)
    }

    @Test("exactly as many branches as can be checked are all checked")
    func checksUpToTheLimit() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        for index in 1..<MergeArchiveInFlight.branchLimit {
            try await fixture.git(["checkout", "-q", "-b", "fix/\(index)", "main"])
        }
        #expect(try await fixture.objection(mergedHead: nil, answers: [:]) == nil)
    }

    @Test("a detached head still checks the branches the worktree had checked out")
    func detachedHead() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        try await fixture.branch("fix/453-local", push: false)
        try await fixture.git(["checkout", "-q", "--detach", "main"])
        #expect(try await fixture.objection(mergedHead: nil, answers: [:])
            == "fix/453-local has 1 commit that is not pushed. \(nextStep)")
    }

    @Test("a directory git cannot read holds the archive back")
    func unreadableWorktree() async throws {
        let directory = TestScratch.unique("unifieddev-not-git")
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        #expect(await MergeArchiveInFlightRead.objection(worktree: directory, mergedHead: nil)
            == MergeArchiveInFlight.unreadable)
    }

    @Test("a pull request read that fails holds the archive back and says so")
    func failedReadObjects() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        try await fixture.branch("fix/586-merged", push: true)
        let objection = await GitHub.$commandOverride.withValue({ _, _ in
            ShellResult(status: 1, stdout: "", stderr: "offline")
        }) {
            await MergeArchiveInFlightRead.objection(worktree: fixture.repo.path, mergedHead: nil)
        }
        #expect(objection == MergeArchiveInFlight.unreadable)
    }

    private struct Fixture {
        let repo: TempRepo
        let remote: String

        init() async throws {
            repo = try await TempRepo()
            remote = TestScratch.unique("unifieddev-remote")
            try FileManager.default.createDirectory(atPath: remote, withIntermediateDirectories: true)
            try await Shell.check("git", ["init", "-q", "--bare"], cwd: remote)
            try await git(["remote", "add", "origin", remote])
            try await git(["push", "-q", "origin", "main"])
        }

        func branch(_ name: String, push: Bool) async throws {
            try await git(["checkout", "-q", "-b", name, "main"])
            try repo.write("\(name).txt", name)
            try await repo.commit(name)
            if push { try await git(["push", "-q", "origin", name]) }
        }

        func tip() async throws -> String {
            try await Shell.check("git", ["rev-parse", "HEAD"], cwd: repo.path).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func git(_ arguments: [String]) async throws {
            try await Shell.check("git", arguments, cwd: repo.path)
        }

        func objection(mergedHead: String?, answers: [String: String]) async throws -> String? {
            await GitHub.$commandOverride.withValue({ arguments, _ in
                guard arguments.contains(where: { $0.split(separator: ",").contains("state") }),
                      let index = arguments.firstIndex(of: "--head"), arguments.indices.contains(index + 1)
                else { return ShellResult(status: 1, stdout: "", stderr: "unexpected gh call") }
                return ShellResult(status: 0, stdout: answers[arguments[index + 1]] ?? "[]", stderr: "")
            }) {
                await MergeArchiveInFlightRead.objection(worktree: repo.path, mergedHead: mergedHead)
            }
        }

        func cleanUp() {
            repo.cleanUp()
            try? FileManager.default.removeItem(atPath: remote)
        }
    }
}
