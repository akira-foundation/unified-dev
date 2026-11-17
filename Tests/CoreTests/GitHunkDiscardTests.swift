import Foundation
import Testing
@testable import Core

@Suite("Discarding a hunk", .tags(.git, .destructive), .scratchDirectory)
struct GitHunkDiscardTests {
    private static let before = (1...30).map { "line \($0)" }.joined(separator: "\n") + "\n"

    private static let after = before
        .replacingOccurrences(of: "line 2\n", with: "line two\n")
        .replacingOccurrences(of: "line 25\n", with: "line twenty-five\n")

    private static let firstDiscarded = after.replacingOccurrences(of: "line two\n", with: "line 2\n")

    private static let lastDiscarded =
        after.replacingOccurrences(of: "line twenty-five\n", with: "line 25\n")

    private func repo(named path: String = "file.txt") async throws -> TempRepo {
        let repo = try await TempRepo()
        try repo.write(path, Self.before)
        try await repo.commit("Before")
        try repo.write(path, Self.after)
        return repo
    }

    private func hunks(_ repo: TempRepo, _ file: ChangedFile, scope: DiffScope = .all) async throws -> [DiffHunk] {
        let patch = try await Git.patch(worktree: repo.path, base: "main", file: file, scope: scope)
        return try #require(DiffParser.parse(patch).first).hunks
    }

    private func staged(_ repo: TempRepo, _ path: String) async throws -> String {
        try await Shell.check("git", ["show", ":\(path)"], cwd: repo.path).stdout
    }

    @Test("one hunk goes and the other stays")
    func discardsOnlyThePressedHunk() async throws {
        let repo = try await repo()
        defer { repo.cleanUp() }
        let file = ChangedFile(path: "file.txt", change: .modified)
        let shown = try await hunks(repo, file)
        #expect(shown.count == 2)

        try await Git.discardHunk(shown[0], of: file, worktree: repo.path, base: "main", scope: .all)

        #expect(repo.read("file.txt") == Self.firstDiscarded)
    }

    @Test("a staged hunk leaves the index as well as the worktree")
    func stagedHunkLeavesBoth() async throws {
        let repo = try await repo()
        defer { repo.cleanUp() }
        try await Shell.check("git", ["add", "file.txt"], cwd: repo.path)
        let file = ChangedFile(path: "file.txt", change: .modified)
        let shown = try await hunks(repo, file, scope: .uncommitted)

        try await Git.discardHunk(shown[1], of: file, worktree: repo.path, base: "main", scope: .uncommitted)

        let index = try await staged(repo, "file.txt")
        #expect(index == Self.lastDiscarded)
        #expect(repo.read("file.txt") == Self.lastDiscarded)
    }

    @Test("an unstaged hunk leaves the index alone")
    func unstagedHunkLeavesTheIndex() async throws {
        let repo = try await repo()
        defer { repo.cleanUp() }
        let file = ChangedFile(path: "file.txt", change: .modified)
        let shown = try await hunks(repo, file, scope: .uncommitted)

        try await Git.discardHunk(shown[0], of: file, worktree: repo.path, base: "main", scope: .uncommitted)

        let index = try await staged(repo, "file.txt")
        #expect(repo.read("file.txt") == Self.firstDiscarded)
        #expect(index == Self.before)
    }

    @Test("an index that does not hold the hunk is left as it is")
    func differentIndexIsLeftAlone() async throws {
        let repo = try await repo()
        defer { repo.cleanUp() }
        try await Shell.check("git", ["add", "file.txt"], cwd: repo.path)
        let edited = Self.after.replacingOccurrences(of: "line two\n", with: "line zwei\n")
        try repo.write("file.txt", edited)
        let file = ChangedFile(path: "file.txt", change: .modified)
        let shown = try await hunks(repo, file, scope: .uncommitted)

        try await Git.discardHunk(shown[0], of: file, worktree: repo.path, base: "main", scope: .uncommitted)

        let index = try await staged(repo, "file.txt")
        #expect(repo.read("file.txt")
            == edited.replacingOccurrences(of: "line zwei\n", with: "line 2\n"))
        #expect(index == Self.after)
    }

    @Test("a hunk the index holds but the worktree has moved on from is refused, not half discarded")
    func stagedHunkWithOtherEditsIsRefused() async throws {
        let repo = try await repo()
        defer { repo.cleanUp() }
        try await Shell.check("git", ["add", "file.txt"], cwd: repo.path)
        let alsoEdited = Self.after.replacingOccurrences(of: "line 14\n", with: "line fourteen\n")
        try repo.write("file.txt", alsoEdited)
        let file = ChangedFile(path: "file.txt", change: .modified)
        let shown = try await hunks(repo, file, scope: .uncommitted)
        let first = try #require(shown.first { $0.lines.contains { $0.text == "line two" } })

        let asked = await Git.stagedHunk(first, of: file, worktree: repo.path, base: "main", scope: .uncommitted)
        #expect(asked == .divergesFromTheWorktree)

        await #expect(throws: HunkDiscardRefusal.indexDiffers) {
            try await Git.discardHunk(first, of: file, worktree: repo.path, base: "main", scope: .uncommitted)
        }

        #expect(repo.read("file.txt") == alsoEdited)
        #expect(try await staged(repo, "file.txt") == Self.after)
    }

    @Test("a hunk committed on the branch is discarded from the worktree and the index")
    func committedHunk() async throws {
        let repo = try await TempRepo()
        defer { repo.cleanUp() }
        try repo.write("file.txt", Self.before)
        try await repo.commit("Before")
        try await Shell.check("git", ["checkout", "-q", "-b", "feature"], cwd: repo.path)
        try repo.write("file.txt", Self.after)
        try await repo.commit("After")
        let file = ChangedFile(path: "file.txt", change: .modified)
        let shown = try await hunks(repo, file)

        try await Git.discardHunk(shown[0], of: file, worktree: repo.path, base: "main", scope: .all)

        let index = try await staged(repo, "file.txt")
        #expect(repo.read("file.txt") == Self.firstDiscarded)
        #expect(index == Self.firstDiscarded)
        let committed = try await Shell.check("git", ["show", "HEAD:file.txt"], cwd: repo.path).stdout
        #expect(committed == Self.after)
    }

    @Test("a file changed under the diff refuses and writes nothing")
    func staleHunkRefuses() async throws {
        let repo = try await repo()
        defer { repo.cleanUp() }
        let file = ChangedFile(path: "file.txt", change: .modified)
        let shown = try await hunks(repo, file)
        let moved = Self.after.replacingOccurrences(of: "line two\n", with: "line deux\n")
        try repo.write("file.txt", moved)

        await #expect(throws: HunkDiscardRefusal.changed) {
            try await Git.discardHunk(shown[0], of: file, worktree: repo.path, base: "main", scope: .all)
        }
        #expect(repo.read("file.txt") == moved)
    }

    @Test("a file that moves between the check and the write is refused, not written at an offset")
    func fileThatMovesUnderThePlanIsRefused() async throws {
        let repo = try await repo()
        defer { repo.cleanUp() }
        let file = ChangedFile(path: "file.txt", change: .modified)
        let shown = try await hunks(repo, file)
        let plan = try await Git.hunkDiscardPlan(
            shown[1], of: file, worktree: repo.path, base: "main", scope: .all
        )
        let pushedDown = "new a\nnew b\nnew c\nnew d\nnew e\n" + Self.after
        try repo.write("file.txt", pushedDown)

        await #expect(performing: { try await Git.apply(plan, in: repo.path) }, throws: { error in
            guard case .doesNotApply = error as? HunkDiscardRefusal else { return false }
            return true
        })

        #expect(repo.read("file.txt") == pushedDown)
        #expect(try await staged(repo, "file.txt") == Self.before)
    }

    @Test("a file that is all one change is refused before git is asked")
    func addedFileIsNotOffered() async throws {
        let repo = try await repo()
        defer { repo.cleanUp() }
        let modified = ChangedFile(path: "file.txt", change: .modified)
        let shown = try await hunks(repo, modified)
        let added = ChangedFile(path: "file.txt", change: .added)

        await #expect(throws: HunkDiscardRefusal.notOffered) {
            try await Git.discardHunk(shown[0], of: added, worktree: repo.path, base: "main", scope: .all)
        }
        #expect(repo.read("file.txt") == Self.after)
    }

    @Test("the middle hunk of three is the only one that goes")
    func middleHunk() async throws {
        let repo = try await TempRepo()
        defer { repo.cleanUp() }
        try repo.write("file.txt", Self.before)
        try await repo.commit("Before")
        let three = Self.after.replacingOccurrences(of: "line 14\n", with: "line fourteen\n")
        try repo.write("file.txt", three)
        let file = ChangedFile(path: "file.txt", change: .modified)
        let shown = try await hunks(repo, file)
        #expect(shown.count == 3)

        try await Git.discardHunk(shown[1], of: file, worktree: repo.path, base: "main", scope: .all)

        #expect(repo.read("file.txt")
            == three.replacingOccurrences(of: "line fourteen\n", with: "line 14\n"))
    }

    @Test("a submodule bump has no hunk to discard, so it is refused before git is asked")
    func submoduleBumpIsNotOffered() async throws {
        let repo = try await TempRepo()
        defer { repo.cleanUp() }
        let bump = """
            diff --git a/sub b/sub
            index 1111111..2222222 160000
            --- a/sub
            +++ b/sub
            @@ -1 +1 @@
            -Subproject commit 1111111111111111111111111111111111111111
            +Subproject commit 2222222222222222222222222222222222222222

            """
        let gitlink = try #require(DiffParser.parse(bump).first)
        #expect(gitlink.newMode == HunkDiscard.gitlinkMode)
        #expect(!HunkDiscard.offers(ChangedFile(path: "sub", change: .modified), in: gitlink))
    }

    @Test("a file that became a symlink is refused before git is asked")
    func typechangeIsNotOffered() async throws {
        let repo = try await repo()
        defer { repo.cleanUp() }
        let modified = ChangedFile(path: "file.txt", change: .modified)
        let shown = try await hunks(repo, modified)
        let swapped = ChangedFile(path: "file.txt", change: .typechange)

        await #expect(throws: HunkDiscardRefusal.notOffered) {
            try await Git.discardHunk(shown[0], of: swapped, worktree: repo.path, base: "main", scope: .all)
        }
        #expect(repo.read("file.txt") == Self.after)
    }
}
