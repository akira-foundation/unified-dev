import Foundation
import Testing
@testable import Core

@Suite("When a read of a workspace's changes moves the generation", .scratchDirectory)
struct ChangesSnapshotTests {
    private let file = ChangedFile(path: "a.txt", change: .modified, additions: 2, deletions: 1)

    private func snapshot(
        files: [ChangedFile]? = nil, revisions: [String: String] = ["a.txt": "r1"], scope: DiffScope = .all
    ) -> ChangesSnapshot {
        ChangesSnapshot(files: files ?? [file], revisions: revisions, scope: scope)
    }

    private func moves(from first: ChangesSnapshot, to second: ChangesSnapshot) -> Bool {
        var generation = ChangesGeneration()
        _ = generation.record(first)
        return generation.record(second)
    }

    @Test("the first read moves it to one")
    func firstReadMoves() {
        var generation = ChangesGeneration()
        let moved = generation.record(snapshot())

        #expect(moved)
        #expect(generation.value == 1)
    }

    @Test("reads that found the same files at the same revisions leave it where it was")
    func sameReadStays() {
        var generation = ChangesGeneration()
        _ = generation.record(snapshot())
        let second = generation.record(snapshot())
        let third = generation.record(snapshot())

        #expect(!second)
        #expect(!third)
        #expect(generation.value == 1)
    }

    @Test("a change after a quiet stretch moves it once, and going back moves it again")
    func changeAfterQuietMoves() {
        var generation = ChangesGeneration()
        _ = generation.record(snapshot())
        _ = generation.record(snapshot())
        let changed = generation.record(snapshot(revisions: ["a.txt": "r2"]))
        let back = generation.record(snapshot())

        #expect(changed)
        #expect(back)
        #expect(generation.value == 3)
    }

    @Test("a file whose revision moved, with the same counts, moves it")
    func revisionMoves() {
        #expect(moves(from: snapshot(), to: snapshot(revisions: ["a.txt": "r2"])))
    }

    @Test("a file added or with other counts moves it")
    func filesMove() {
        let other = ChangedFile(path: "a.txt", change: .modified, additions: 3, deletions: 1)
        let added = ChangedFile(path: "b.txt", change: .untracked, additions: 1, deletions: 0)

        #expect(moves(from: snapshot(), to: snapshot(files: [other])))
        #expect(moves(from: snapshot(), to: snapshot(files: [file, added])))
    }

    @Test("another scope moves it")
    func scopeMoves() {
        #expect(moves(from: snapshot(), to: snapshot(scope: .uncommitted)))
    }

    @Test("a file rewritten on disk reads as a new revision and moves it")
    func rewrittenFileMoves() async throws {
        let folder = TestScratch.unique("changes-snapshot")
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let path = folder + "/a.txt"
        try "one\n".write(toFile: path, atomically: false, encoding: .utf8)
        let before = ReviewedFileFingerprint.revisions(for: [file], worktree: folder, base: "main", scope: .all)
        let again = ReviewedFileFingerprint.revisions(for: [file], worktree: folder, base: "main", scope: .all)

        try await Task.sleep(for: .milliseconds(20))
        try "two\n".write(toFile: path, atomically: true, encoding: .utf8)
        let after = ReviewedFileFingerprint.revisions(for: [file], worktree: folder, base: "main", scope: .all)

        #expect(!moves(from: snapshot(revisions: before), to: snapshot(revisions: again)))
        #expect(moves(from: snapshot(revisions: before), to: snapshot(revisions: after)))
    }
}
