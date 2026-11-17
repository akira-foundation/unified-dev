import Foundation
import Testing
@testable import Core

@Suite("What the index holds for a hunk", .tags(.git, .destructive), .scratchDirectory)
struct GitStagedHunkTests {
    private static let before = (1...30).map { "line \($0)" }.joined(separator: "\n") + "\n"

    private static let after = before
        .replacingOccurrences(of: "line 2\n", with: "line two\n")
        .replacingOccurrences(of: "line 25\n", with: "line twenty-five\n")

    private func repo() async throws -> TempRepo {
        let repo = try await TempRepo()
        try repo.write("file.txt", Self.before)
        try await repo.commit("Before")
        try repo.write("file.txt", Self.after)
        return repo
    }

    private func hunks(_ repo: TempRepo, _ file: ChangedFile) async throws -> [DiffHunk] {
        let patch = try await Git.patch(
            worktree: repo.path, base: "main", file: file, scope: .uncommitted
        )
        return try #require(DiffParser.parse(patch).first).hunks
    }

    private func staged(
        _ repo: TempRepo, _ hunk: DiffHunk,
        _ file: ChangedFile = ChangedFile(path: "file.txt", change: .modified)
    ) async -> HunkDiscard.Staged {
        await Git.stagedHunk(
            hunk, of: file, worktree: repo.path, base: "main", scope: .uncommitted
        )
    }

    @Test("an index that matches the commit holds nothing of its own")
    func nothingStaged() async throws {
        let repo = try await repo()
        defer { repo.cleanUp() }
        let shown = try await hunks(repo, ChangedFile(path: "file.txt", change: .modified))

        #expect(await staged(repo, shown[0]) == .clean)
    }

    @Test("an index that holds the hunk itself says so")
    func indexHoldsTheHunk() async throws {
        let repo = try await repo()
        defer { repo.cleanUp() }
        try await Shell.check("git", ["add", "file.txt"], cwd: repo.path)
        let shown = try await hunks(repo, ChangedFile(path: "file.txt", change: .modified))

        #expect(await staged(repo, shown[0]) == .holdsTheHunk)
    }

    @Test("an index holding its own version of the region is told apart from the hunk")
    func indexHoldsAnotherVersion() async throws {
        let repo = try await repo()
        defer { repo.cleanUp() }
        try await Shell.check("git", ["add", "file.txt"], cwd: repo.path)
        try repo.write("file.txt", Self.after.replacingOccurrences(of: "line two\n", with: "line zwei\n"))
        let shown = try await hunks(repo, ChangedFile(path: "file.txt", change: .modified))
        let first = try #require(shown.first { $0.lines.contains { $0.text == "line zwei" } })

        #expect(await staged(repo, first) == .holdsAnotherVersion)
    }

    @Test("an index holding the hunk while the working file has moved on is told apart from one that agrees")
    func indexHoldsTheHunkApartFromTheWorktree() async throws {
        let repo = try await repo()
        defer { repo.cleanUp() }
        try await Shell.check("git", ["add", "file.txt"], cwd: repo.path)
        try repo.write("file.txt", Self.after.replacingOccurrences(of: "line 14\n", with: "line fourteen\n"))
        let shown = try await hunks(repo, ChangedFile(path: "file.txt", change: .modified))
        let first = try #require(shown.first { $0.lines.contains { $0.text == "line two" } })

        #expect(await staged(repo, first) == .divergesFromTheWorktree)
    }

    @Test("a staged rename on its own is no staged version of the region")
    func stagedRenameHoldsNothing() async throws {
        let repo = try await TempRepo()
        defer { repo.cleanUp() }
        try repo.write("old name.txt", Self.before)
        try await repo.commit("Before")
        try await Shell.check("git", ["mv", "old name.txt", "new name.txt"], cwd: repo.path)
        try repo.write("new name.txt", Self.after)
        let file = ChangedFile(path: "new name.txt", oldPath: "old name.txt", change: .renamed)
        let patch = try await Git.patch(
            worktree: repo.path, base: "main", file: file, scope: .uncommitted
        )
        let shown = try #require(DiffParser.parse(patch).first).hunks

        #expect(await staged(repo, shown[0], file) == .clean)
    }

    @Test("a version staged in another region of the file counts as one of its own")
    func stagedChangeElsewhereInTheFile() async throws {
        let repo = try await repo()
        defer { repo.cleanUp() }
        try repo.write("file.txt", Self.before.replacingOccurrences(of: "line 2\n", with: "line two\n"))
        try await Shell.check("git", ["add", "file.txt"], cwd: repo.path)
        try repo.write("file.txt", Self.after)
        let shown = try await hunks(repo, ChangedFile(path: "file.txt", change: .modified))
        let last = try #require(shown.last { $0.lines.contains { $0.text == "line twenty-five" } })

        #expect(await staged(repo, last) == .holdsAnotherVersion)
    }
}
