import Foundation
import Testing
@testable import Core

@Suite("Which hunks of a file git will refuse to discard", .tags(.git, .destructive), .scratchDirectory)
struct GitHunkRefusalsTests {
    private static let before = (1...30).map { "line \($0)" }.joined(separator: "\n") + "\n"

    private static let after = before
        .replacingOccurrences(of: "line 2\n", with: "line two\n")
        .replacingOccurrences(of: "line 25\n", with: "line twenty-five\n")

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

    private func shown(_ repo: TempRepo, scope: DiffScope) async throws -> FileDiff {
        let patch = try await Git.patch(worktree: repo.path, base: "main", file: file, scope: scope)
        return try #require(DiffParser.parse(patch).first)
    }

    private func refusals(_ repo: TempRepo, _ diff: FileDiff, scope: DiffScope) async -> [DiffHunk: HunkDiscard.Staged] {
        await Git.hunkRefusals(in: diff, of: file, worktree: repo.path, base: "main", scope: scope)
    }

    private static func latin1(_ text: String) -> Data {
        Data(text.unicodeScalars.map { UInt8($0.value) })
    }

    @Test("nothing staged and every line UTF-8 refuses nothing")
    func cleanFileRefusesNothing() async throws {
        let repo = try await repo(committed: Data(Self.before.utf8), edited: Data(Self.after.utf8))
        defer { repo.cleanUp() }
        let diff = try await shown(repo, scope: .uncommitted)
        try #require(diff.hunks.count == 2)

        #expect(await refusals(repo, diff, scope: .uncommitted).isEmpty)
    }

    @Test("a staged hunk the working file has moved on from is refused, and agrees with the confirmation")
    func stagedHunkApartFromTheWorktree() async throws {
        let repo = try await repo(committed: Data(Self.before.utf8), edited: Data(Self.after.utf8))
        defer { repo.cleanUp() }
        try await Shell.check("git", ["add", "file.txt"], cwd: repo.path)
        try repo.write("file.txt", Self.after.replacingOccurrences(of: "line 14\n", with: "line fourteen\n"))
        let diff = try await shown(repo, scope: .uncommitted)
        try #require(diff.hunks.count == 3)

        let refused = await refusals(repo, diff, scope: .uncommitted)

        let fourteen = try #require(diff.hunks.first { $0.lines.contains { $0.text == "line fourteen" } })
        #expect(refused[fourteen] == nil)
        #expect(refused.count == 2)
        for hunk in diff.hunks {
            let asked = await Git.stagedHunk(hunk, of: file, worktree: repo.path, base: "main", scope: .uncommitted)
            #expect(refused[hunk] == (HunkDiscard.canConfirm(asked) ? nil : asked))
        }
    }

    @Test("a staged hunk the working file agrees with is not refused")
    func stagedHunkThatAgrees() async throws {
        let repo = try await repo(committed: Data(Self.before.utf8), edited: Data(Self.after.utf8))
        defer { repo.cleanUp() }
        try await Shell.check("git", ["add", "file.txt"], cwd: repo.path)
        let diff = try await shown(repo, scope: .all)

        #expect(await refusals(repo, diff, scope: .all).isEmpty)
    }

    @Test("a hunk that adds a Latin-1 line is refused, and the UTF-8 hunk beside it is not")
    func latin1AdditionIsRefused() async throws {
        let edited = Self.before
            .replacingOccurrences(of: "line 2\n", with: "line two\n")
            .replacingOccurrences(of: "line 25\n", with: "caf\u{e9} 25\n")
        let repo = try await repo(committed: Data(Self.before.utf8), edited: Self.latin1(edited))
        defer { repo.cleanUp() }
        let diff = try await shown(repo, scope: .all)
        try #require(diff.hunks.count == 2)

        let refused = await refusals(repo, diff, scope: .all)

        let latin = try #require(diff.hunks.first { $0.lines.contains { $0.text.hasPrefix("caf") } })
        #expect(refused == [latin: .addsLinesThatAreNotUTF8])
    }

    @Test("a real replacement character in a UTF-8 file is checked in bytes and not refused")
    func realReplacementCharacterIsNotRefused() async throws {
        let edited = Self.before.replacingOccurrences(of: "line 25\n", with: "broken \u{fffd} 25\n")
        let repo = try await repo(committed: Data(Self.before.utf8), edited: Data(edited.utf8))
        defer { repo.cleanUp() }
        let diff = try await shown(repo, scope: .all)

        #expect(await refusals(repo, diff, scope: .all).isEmpty)
    }

    @Test("a file a hunk cannot be discarded from refuses nothing, because it has no band")
    func notOfferedRefusesNothing() async throws {
        let repo = try await repo(committed: Data(Self.before.utf8), edited: Self.latin1("caf\u{e9}\n"))
        defer { repo.cleanUp() }
        let added = ChangedFile(path: "file.txt", change: .added)
        let diff = try await shown(repo, scope: .all)

        #expect(await Git.hunkRefusals(in: diff, of: added, worktree: repo.path, base: "main", scope: .all).isEmpty)
    }

    @Test("the index stands apart only when it differs from both the commit and the working file")
    func indexStandsApart() async throws {
        let repo = try await repo(committed: Data(Self.before.utf8), edited: Data(Self.after.utf8))
        defer { repo.cleanUp() }
        #expect(!(await Git.indexStandsApart(file, in: repo.path)))

        try await Shell.check("git", ["add", "file.txt"], cwd: repo.path)
        #expect(!(await Git.indexStandsApart(file, in: repo.path)))

        try repo.write("file.txt", Self.after.replacingOccurrences(of: "line 14\n", with: "line fourteen\n"))
        #expect(await Git.indexStandsApart(file, in: repo.path))
    }
}
