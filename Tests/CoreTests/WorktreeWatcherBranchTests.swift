import Foundation
import Synchronization
import Testing
@testable import Core

@Suite("Which worktrees a change in the shared repository marks", .tags(.git), .scratchDirectory)
struct WorktreeWatcherBranchTests {
    private struct Pair {
        let repo: TempRepo
        let one: String
        let two: String
        let common: String
        let metadata: [String: Set<String>]
        let branches: [String: Set<String>]
    }

    private func pair() async throws -> Pair {
        let repo = try await TempRepo()
        let one = TestScratch.unique("first-worktree")
        let two = TestScratch.unique("second-worktree")
        try await Git.addWorktree(repo: repo.path, path: one, branch: "one", base: "main")
        try await Git.addWorktree(repo: repo.path, path: two, branch: "two", base: "main")
        let paths = try #require(Git.repositoryPaths(in: one))
        return Pair(
            repo: repo, one: one, two: two,
            common: WorktreeWatcher.resolve(paths.commonDirectory),
            metadata: WorktreeWatcher.metadataRoots(for: [one, two]),
            branches: [one: ["one", "main"], two: ["two", "main"]]
        )
    }

    @Test("a branch that moves marks the worktree on it and not its sibling")
    func movedBranchMarksItsOwnWorktree() async throws {
        let pair = try await pair()
        defer { pair.repo.cleanUp() }

        let marked = WorktreeWatcher.metadataWorktrees(
            changed: [pair.common + "/refs/heads/one", pair.common + "/logs/refs/heads/one"],
            metadata: pair.metadata, branches: pair.branches
        )

        #expect(marked == [pair.one])
    }

    @Test("a ref being written under its lock marks the same worktree")
    func lockedRefMarksItsWorktree() async throws {
        let pair = try await pair()
        defer { pair.repo.cleanUp() }

        let marked = WorktreeWatcher.metadataWorktrees(
            changed: [pair.common + "/refs/heads/two.lock"], metadata: pair.metadata, branches: pair.branches
        )

        #expect(marked == [pair.two])
    }

    @Test("the base branch moving, locally or on the remote, marks every worktree built on it")
    func baseMovesMarksAll() async throws {
        let pair = try await pair()
        defer { pair.repo.cleanUp() }

        let local = WorktreeWatcher.metadataWorktrees(
            changed: [pair.common + "/refs/heads/main"], metadata: pair.metadata, branches: pair.branches
        )
        let remote = WorktreeWatcher.metadataWorktrees(
            changed: [pair.common + "/refs/remotes/origin/main"], metadata: pair.metadata, branches: pair.branches
        )

        #expect(local == [pair.one, pair.two])
        #expect(remote == [pair.one, pair.two])
    }

    @Test("a branch no worktree is on or built on marks nothing")
    func unrelatedBranchMarksNothing() async throws {
        let pair = try await pair()
        defer { pair.repo.cleanUp() }

        let marked = WorktreeWatcher.metadataWorktrees(
            changed: [pair.common + "/refs/heads/elsewhere"], metadata: pair.metadata, branches: pair.branches
        )

        #expect(marked.isEmpty)
    }

    @Test("a change no branch name can be read from still marks them all")
    func packedRefsMarksAll() async throws {
        let pair = try await pair()
        defer { pair.repo.cleanUp() }

        let marked = WorktreeWatcher.metadataWorktrees(
            changed: [pair.common + "/packed-refs"], metadata: pair.metadata, branches: pair.branches
        )

        #expect(marked == [pair.one, pair.two])
    }

    @Test("the lock git takes on packed refs during a commit marks nothing on its own")
    func packedRefsLockMarksNothing() async throws {
        let pair = try await pair()
        defer { pair.repo.cleanUp() }

        let marked = WorktreeWatcher.metadataWorktrees(
            changed: [pair.common + "/packed-refs.lock"], metadata: pair.metadata, branches: pair.branches
        )

        #expect(marked.isEmpty)
    }

    @Test("a worktree whose branches were never given is marked as before")
    func unknownBranchesMarkAsBefore() async throws {
        let pair = try await pair()
        defer { pair.repo.cleanUp() }

        let marked = WorktreeWatcher.metadataWorktrees(
            changed: [pair.common + "/refs/heads/one"], metadata: pair.metadata, branches: [pair.one: ["one"]]
        )

        #expect(marked == [pair.one, pair.two])
    }

    @Test("a base picked from the remote also answers to the local branch of the same name")
    func remoteBaseAnswersToLocal() async throws {
        let pair = try await pair()
        defer { pair.repo.cleanUp() }
        let branches = [
            pair.one: WorktreeWatcher.concernedBranches(branch: "one", base: "origin/main"),
            pair.two: WorktreeWatcher.concernedBranches(branch: "two", base: "elsewhere"),
        ]

        let marked = WorktreeWatcher.metadataWorktrees(
            changed: [pair.common + "/refs/heads/main"], metadata: pair.metadata, branches: branches
        )

        #expect(marked == [pair.one])
        #expect(WorktreeWatcher.concernedBranches(branch: "b", base: "origin/feature/x") == ["b", "origin/feature/x", "feature/x"])
    }

    @Test("the branch named by a ref path", arguments: [
        ("refs/heads/feature/x", Set(["feature/x"])),
        ("logs/refs/heads/one", Set(["one"])),
        ("refs/heads/one.lock", Set(["one"])),
        ("refs/remotes/origin/main", Set(["main", "origin/main"])),
    ] as [(String, Set<String>)])
    func branchNames(relative: String, names: Set<String>) {
        #expect(WorktreeWatcher.movedBranchNames(relative) == names)
    }

    @Test("a path that names no branch", arguments: ["refs", "refs/heads", "refs/tags/v1", "refs/remotes/origin", "HEAD"])
    func noBranchName(relative: String) {
        #expect(WorktreeWatcher.movedBranchNames(relative) == nil)
    }

    private func untilEarlierEventsAreDelivered() async throws {
        let folder = TestScratch.unique("fsevents-marker")
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let marker = folder + "/marker"
        let seen = Mutex(false)
        let watcher = WorktreeWatcher(onFilesChanged: { changes in
            if changes.contains(where: { $0.path == marker }) { seen.withLock { $0 = true } }
        }, onChange: { _ in })
        defer { watcher.stop() }
        watcher.watch(roots: [folder])

        try Data("marker".utf8).write(to: URL(filePath: marker))
        await waitUntil("the marker written after the worktrees is delivered", within: .seconds(20)) {
            seen.withLock { $0 }
        }
    }

    private func wokenByACommit(in pair: Pair, branches: [String: Set<String>]) async throws -> Set<String> {
        try await untilEarlierEventsAreDelivered()
        let reported = Mutex<Set<String>>([])
        let watcher = WorktreeWatcher { changed in reported.withLock { $0.formUnion(changed) } }
        defer { watcher.stop() }
        watcher.watch(roots: [pair.one, pair.two], branches: branches)

        try await Shell.check("git", ["commit", "-q", "--allow-empty", "-m", "Move one"], cwd: pair.one)

        var waited = Duration.zero
        while reported.withLock({ $0.isEmpty }), waited < .seconds(20) {
            try await Task.sleep(for: .milliseconds(100))
            waited += .milliseconds(100)
        }
        try await Task.sleep(for: .seconds(2))
        return reported.withLock { $0 }
    }

    @Test("a commit in one worktree wakes that worktree and not its sibling", .timeLimit(.minutes(1)))
    func realCommitWakesOneWorktree() async throws {
        let pair = try await pair()
        defer { pair.repo.cleanUp() }

        let woken = try await wokenByACommit(in: pair, branches: pair.branches)

        #expect(woken == [pair.one])
    }

    @Test("without the branches, a commit in one worktree still wakes both", .timeLimit(.minutes(1)))
    func realCommitWithoutBranchesWakesBoth() async throws {
        let pair = try await pair()
        defer { pair.repo.cleanUp() }

        let woken = try await wokenByACommit(in: pair, branches: [:])

        #expect(woken == [pair.one, pair.two])
    }
}
