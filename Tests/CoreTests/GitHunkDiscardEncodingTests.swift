import Foundation
import Testing
@testable import Core

@Suite("Discarding a hunk from a file that is not UTF-8", .tags(.git, .destructive), .scratchDirectory)
struct GitHunkDiscardEncodingTests {
    private static let ascii = latin1((1...30).map { "line \($0)" }.joined(separator: "\n") + "\n")

    private static func latin1(_ text: String) -> Data {
        Data(text.unicodeScalars.map { UInt8($0.value) })
    }

    private static func replacing(_ old: String, with new: String, in data: Data) throws -> Data {
        var bytes = [UInt8](data)
        let needle = [UInt8](latin1(old))
        let start = try #require(
            (0...(bytes.count - needle.count)).first { Array(bytes[$0..<($0 + needle.count)]) == needle }
        )
        bytes.replaceSubrange(start..<(start + needle.count), with: [UInt8](latin1(new)))
        return Data(bytes)
    }

    private static func committed() throws -> Data {
        try replacing("line 25\n", with: "caf\u{e9} 25\n", in: ascii)
    }

    private let file = ChangedFile(path: "file.txt", change: .modified)

    private func repo(committed: Data, edited: Data) async throws -> TempRepo {
        let repo = try await TempRepo()
        try committed.write(to: url(repo))
        try await repo.commit("Before")
        try edited.write(to: url(repo))
        return repo
    }

    private func url(_ repo: TempRepo) -> URL {
        URL(fileURLWithPath: (repo.path as NSString).appendingPathComponent("file.txt"))
    }

    private func hunks(_ repo: TempRepo, scope: DiffScope = .all) async throws -> [DiffHunk] {
        let patch = try await Git.patch(worktree: repo.path, base: "main", file: file, scope: scope)
        return try #require(DiffParser.parse(patch).first).hunks
    }

    private func index(_ repo: TempRepo) async throws -> Data {
        try await Shell.runBytes("git", ["show", ":file.txt"], cwd: repo.path).stdout
    }

    @Test("a hunk that puts back a Latin-1 line restores it byte for byte")
    func putsBackLatin1Line() async throws {
        let committed = try Self.committed()
        let repo = try await repo(committed: committed, edited: Self.ascii)
        defer { repo.cleanUp() }
        let shown = try #require(try await hunks(repo).first)

        try await Git.discardHunk(shown, of: file, worktree: repo.path, base: "main", scope: .all)

        #expect(try Data(contentsOf: url(repo)) == committed)
    }

    @Test("a Latin-1 line the hunk does not touch is left byte for byte as it was")
    func latin1LineOutsideTheHunk() async throws {
        let committed = try Self.committed()
        let twentyEight = try Self.replacing("line 28\n", with: "line twenty-eight \u{ff}\n", in: committed)
        let repo = try await repo(
            committed: committed, edited: try Self.replacing("line 2\n", with: "line two\n", in: twentyEight)
        )
        defer { repo.cleanUp() }
        let shown = try await hunks(repo)
        try #require(shown.count == 2)

        try await Git.discardHunk(shown[0], of: file, worktree: repo.path, base: "main", scope: .all)

        #expect(try Data(contentsOf: url(repo)) == twentyEight)
    }

    @Test("a staged hunk that puts back a Latin-1 line leaves the index as well as the worktree")
    func stagedHunkPutsBackLatin1Line() async throws {
        let committed = try Self.committed()
        let repo = try await repo(committed: committed, edited: Self.ascii)
        defer { repo.cleanUp() }
        try await Shell.check("git", ["add", "file.txt"], cwd: repo.path)
        let shown = try #require(try await hunks(repo).first)

        let staged = await Git.stagedHunk(shown, of: file, worktree: repo.path, base: "main", scope: .all)
        try await Git.discardHunk(shown, of: file, worktree: repo.path, base: "main", scope: .all)

        #expect(staged == .holdsTheHunk)
        #expect(try Data(contentsOf: url(repo)) == committed)
        #expect(try await index(repo) == committed)
    }

    @Test("a staged hunk among Latin-1 lines that the worktree has moved on from is refused, not half discarded")
    func stagedHunkAmongLatin1LinesWithOtherEditsIsRefused() async throws {
        let committed = try Self.replacing("line 23\n", with: "caf\u{e9} 23\n", in: Self.ascii)
        let staged = try Self.replacing("line 25\n", with: "line twenty-five\n", in: committed)
        let repo = try await repo(committed: committed, edited: staged)
        defer { repo.cleanUp() }
        try await Shell.check("git", ["add", "file.txt"], cwd: repo.path)
        let alsoEdited = try Self.replacing("line 10\n", with: "line ten\n", in: staged)
        try alsoEdited.write(to: url(repo))
        let shown = try await hunks(repo, scope: .uncommitted)
        let restoring = try #require(shown.first { $0.lines.contains { $0.text == "line twenty-five" } })

        let asked = await Git.stagedHunk(
            restoring, of: file, worktree: repo.path, base: "main", scope: .uncommitted
        )
        await #expect(throws: HunkDiscardRefusal.indexDiffers) {
            try await Git.discardHunk(restoring, of: file, worktree: repo.path, base: "main", scope: .uncommitted)
        }

        #expect(asked == .divergesFromTheWorktree)
        #expect(try Data(contentsOf: url(repo)) == alsoEdited)
        #expect(try await index(repo) == staged)
    }

    @Test("a hunk that adds a line that is not UTF-8 is refused and nothing is written")
    func addedLatin1LineIsRefused() async throws {
        let edited = try Self.committed()
        let repo = try await repo(committed: Self.ascii, edited: edited)
        defer { repo.cleanUp() }
        let shown = try #require(try await hunks(repo).first)

        let asked = await Git.stagedHunk(shown, of: file, worktree: repo.path, base: "main", scope: .all)
        await #expect(throws: HunkDiscardRefusal.addsLinesThatAreNotUTF8) {
            try await Git.discardHunk(shown, of: file, worktree: repo.path, base: "main", scope: .all)
        }

        #expect(asked == .addsLinesThatAreNotUTF8)
        #expect(try Data(contentsOf: url(repo)) == edited)
    }

    @Test("a staged hunk that adds a line that is not UTF-8 is refused before it is confirmed")
    func stagedAddedLatin1LineIsRefused() async throws {
        let edited = try Self.committed()
        let repo = try await repo(committed: Self.ascii, edited: edited)
        defer { repo.cleanUp() }
        try await Shell.check("git", ["add", "file.txt"], cwd: repo.path)
        let shown = try #require(try await hunks(repo).first)

        let asked = await Git.stagedHunk(shown, of: file, worktree: repo.path, base: "main", scope: .all)
        await #expect(throws: HunkDiscardRefusal.addsLinesThatAreNotUTF8) {
            try await Git.discardHunk(shown, of: file, worktree: repo.path, base: "main", scope: .all)
        }

        #expect(asked == .addsLinesThatAreNotUTF8)
        #expect(try Data(contentsOf: url(repo)) == edited)
        #expect(try await index(repo) == edited)
    }

    @Test("a Latin-1 file changed under the diff is refused and nothing is written")
    func staleLatin1HunkRefuses() async throws {
        let repo = try await repo(committed: try Self.committed(), edited: Self.ascii)
        defer { repo.cleanUp() }
        let shown = try #require(try await hunks(repo).first)
        let moved = try Self.replacing("line 25\n", with: "line 26 again\n", in: Self.ascii)
        try moved.write(to: url(repo))

        await #expect(throws: HunkDiscardRefusal.changed) {
            try await Git.discardHunk(shown, of: file, worktree: repo.path, base: "main", scope: .all)
        }

        #expect(try Data(contentsOf: url(repo)) == moved)
    }
}
