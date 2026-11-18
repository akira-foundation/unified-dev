import Foundation
import Testing
@testable import Core

@Suite("Discarding a hunk from an awkward file", .tags(.git, .destructive), .scratchDirectory)
struct GitHunkDiscardFileTests {
    private static let before = (1...30).map { "line \($0)" }.joined(separator: "\n") + "\n"

    private static let after = before
        .replacingOccurrences(of: "line 2\n", with: "line two\n")
        .replacingOccurrences(of: "line 25\n", with: "line twenty-five\n")

    private func hunks(_ repo: TempRepo, _ file: ChangedFile) async throws -> [DiffHunk] {
        let patch = try await Git.patch(worktree: repo.path, base: "main", file: file, scope: .all)
        return try #require(DiffParser.parse(patch).first).hunks
    }

    @Test("a deletion with no context around it goes back where it was, not at the end of the file")
    func deletionWithoutContext() async throws {
        let repo = try await TempRepo()
        defer { repo.cleanUp() }
        try repo.write("file.txt", Self.before)
        try await repo.commit("Before")
        try await Shell.check("git", ["config", "diff.context", "0"], cwd: repo.path)
        try repo.write("file.txt", Self.before.replacingOccurrences(of: "line 25\n", with: ""))
        let file = ChangedFile(path: "file.txt", change: .modified)
        let hunk = try #require(try await hunks(repo, file).first)
        #expect(hunk.newCount == 0)

        try await Git.discardHunk(hunk, of: file, worktree: repo.path, base: "main", scope: .all)

        #expect(repo.read("file.txt") == Self.before)
    }

    @Test("a file with no newline at the end keeps it that way")
    func fileWithoutTrailingNewline() async throws {
        let repo = try await TempRepo()
        defer { repo.cleanUp() }
        let committed = (1...10).map { "line \($0)" }.joined(separator: "\n")
        try repo.write("file.txt", committed)
        try await repo.commit("Before")
        try repo.write("file.txt", committed.replacingOccurrences(of: "line 2", with: "line two"))
        let file = ChangedFile(path: "file.txt", change: .modified)
        let shown = try await hunks(repo, file)
        #expect(shown.count == 1)

        try await Git.discardHunk(shown[0], of: file, worktree: repo.path, base: "main", scope: .all)

        #expect(repo.read("file.txt") == committed)
    }

    @Test("a repository that keeps CRLF in the worktree discards the hunk all the same")
    func normalisedLineEndings() async throws {
        let repo = try await TempRepo()
        defer { repo.cleanUp() }
        try repo.write(".gitattributes", "*.txt text eol=crlf\n")
        try repo.write("file.txt", Self.before)
        try await repo.commit("Before")
        try FileManager.default.removeItem(
            atPath: (repo.path as NSString).appendingPathComponent("file.txt")
        )
        try await Shell.check("git", ["checkout", "-q", "--", "file.txt"], cwd: repo.path)
        let committed = try #require(repo.read("file.txt"))
        #expect(committed.contains("\r\n"))
        try repo.write("file.txt", committed.replacingOccurrences(of: "line 25\r\n", with: "line twenty-five\r\n"))
        let file = ChangedFile(path: "file.txt", change: .modified)
        let shown = try await hunks(repo, file)

        try await Git.discardHunk(shown[0], of: file, worktree: repo.path, base: "main", scope: .all)

        #expect(repo.read("file.txt") == committed)
    }

    @Test("a file emptied of every line is put back by discarding its one hunk")
    func emptiedFile() async throws {
        let repo = try await TempRepo()
        defer { repo.cleanUp() }
        try repo.write("file.txt", Self.before)
        try await repo.commit("Before")
        try repo.write("file.txt", "")
        let file = ChangedFile(path: "file.txt", change: .modified)
        let shown = try await hunks(repo, file)

        try await Git.discardHunk(shown[0], of: file, worktree: repo.path, base: "main", scope: .all)

        #expect(repo.read("file.txt") == Self.before)
    }
}
