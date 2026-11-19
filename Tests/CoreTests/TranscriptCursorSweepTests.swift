import Foundation
import Testing
@testable import Core

@Suite("Transcript cursor sweep", .tags(.persistence))
struct TranscriptCursorSweepTests {
    private func cursor(_ path: String) -> TranscriptCursor {
        TranscriptCursor(
            path: path, provider: .claudeCode, size: 10,
            modifiedAt: Date(timeIntervalSince1970: 1_000), offset: 10
        )
    }

    private func turn(_ key: String, file: String) -> SpendTurn {
        SpendTurn(
            file: file, key: key, provider: .claudeCode, day: Date(),
            model: "claude-haiku-5-5", directory: "/d", tier: .base, usage: TokenUsage(output: 7)
        )
    }

    private func missing(_ index: Int) -> String {
        "/nowhere/ud-sweep/" + String(format: "%06d", index) + ".jsonl"
    }

    @Test("files are read a page at a time, and every file is on one page")
    func pagesCoverEveryFile() {
        let files = (0..<(TranscriptCursorSweep.readBatch * 2 + 1)).map { index in
            TranscriptFile(
                provider: .claudeCode, url: URL(filePath: "/t/\(index).jsonl"), size: 1, modifiedAt: .distantPast
            )
        }
        let pages = TranscriptCursorSweep.pages(of: files)
        #expect(pages.map(\.count) == [TranscriptCursorSweep.readBatch, TranscriptCursorSweep.readBatch, 1])
        #expect(pages.flatMap { Array($0) } == files)
    }

    @Test("the position wraps once a page comes back short")
    func positionWrapsAtTheEnd() {
        let full = Array(repeating: "/a", count: TranscriptCursorSweep.sweepBatch - 1) + ["/z"]
        #expect(TranscriptCursorSweep.nextPosition(after: full) == "/z")
        #expect(TranscriptCursorSweep.nextPosition(after: ["/a"]) == nil)
    }

    @Test("a pass forgets the cursor of a file that went and keeps what it counted")
    func forgetsVanishedCursorsAndKeepsTheSpend() async throws {
        let home = try SpendHome()
        try home.write(claudeLine(10) + "\n", to: home.claude)
        let store = try makeTestStore("sweep")
        let gone = "/nowhere/ud-sweep/gone.jsonl"
        try await store.record([turn("t", file: gone)], reaching: cursor(gone))

        _ = try await SpendIndexer(store: store, home: home.root).refresh()

        let left = try await store.transcriptCursorPaths(after: "", limit: 10)
        #expect(left.count == 1)
        #expect(left.first?.hasSuffix("session.jsonl") == true)
        let days = try await store.spendDays(since: Date(timeIntervalSince1970: 0))
        #expect(days.contains { $0.file == gone })
    }

    @Test("one pass looks at no more cursors than its batch, and the next carries on")
    func oneBatchPerPass() async throws {
        let home = try SpendHome()
        let store = try makeTestStore("sweep")
        let overflow = 5
        for index in 0..<(TranscriptCursorSweep.sweepBatch + overflow) {
            try await store.record([], reaching: cursor(missing(index)))
        }
        let indexer = SpendIndexer(store: store, home: home.root)

        _ = try await indexer.refresh()
        let afterFirst = try await store.transcriptCursorPaths(after: "", limit: overflow * 2)
        #expect(afterFirst == (TranscriptCursorSweep.sweepBatch..<(TranscriptCursorSweep.sweepBatch + overflow)).map(missing))
        #expect(try await store.setting(TranscriptCursorSweep.positionKey) == missing(TranscriptCursorSweep.sweepBatch - 1))

        _ = try await indexer.refresh()
        #expect(try await store.transcriptCursorPaths(after: "", limit: overflow * 2).isEmpty)
        #expect(try await store.setting(TranscriptCursorSweep.positionKey) == nil)
    }

    @Test("a file gone from a volume that is not mounted is not called vanished")
    func unmountedVolumeIsNotVanished() {
        let paths = ["/Volumes/Away/.claude/a.jsonl", "/Volumes/Here/.claude/b.jsonl", "/Users/ada/c.jsonl"]

        let vanished = TranscriptCursorSweep.vanished(in: paths) { $0 == "/Volumes/Here" }

        #expect(vanished == ["/Volumes/Here/.claude/b.jsonl", "/Users/ada/c.jsonl"])
    }

    @Test("the sweep resumes past the cursors it already looked at", .scratchDirectory)
    func resumesFromThePosition() async throws {
        let home = try SpendHome()
        let store = try makeTestStore("sweep")
        let base = URL(filePath: TestScratch.unique("sweep-kept"), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        for index in 0..<TranscriptCursorSweep.sweepBatch {
            let file = base.appending(path: "s-" + String(format: "%06d", index))
            try Data().write(to: file)
            try await store.record([], reaching: cursor(file.path))
        }
        let late = base.appending(path: "z-gone").path
        try await store.record([], reaching: cursor(late))
        let indexer = SpendIndexer(store: store, home: home.root)

        _ = try await indexer.refresh()
        #expect(!(try await store.transcriptCursorPaths(after: "", limit: 2_000).filter { $0 == late }.isEmpty))

        _ = try await indexer.refresh()
        #expect(try await store.transcriptCursorPaths(after: "", limit: 2_000).filter { $0 == late }.isEmpty)
    }

    @Test("a cursor nobody asked about stays out of the read")
    func readsOnlyWhatIsAsked() async throws {
        let store = try makeTestStore("sweep")
        try await store.record([], reaching: cursor("/t/a.jsonl"))
        try await store.record([], reaching: cursor("/t/b.jsonl"))

        let read = try await store.transcriptCursors(forPaths: ["/t/a.jsonl"])

        #expect(read.count == 1)
        #expect(read["/t/b.jsonl"] == nil)
    }

    @Test("files past the first page are still recognised as unchanged")
    func unchangedAcrossPages() async throws {
        let home = try SpendHome()
        let directory = home.claude.deletingLastPathComponent()
        for index in 0..<(TranscriptCursorSweep.readBatch + 10) {
            try home.write(claudeLine(10) + "\n", to: directory.appending(path: "s\(index).jsonl"))
        }
        let store = try makeTestStore("sweep")
        let indexer = SpendIndexer(store: store, home: home.root)

        let first = try await indexer.refresh()
        let second = try await indexer.refresh()

        #expect(first.filesRead == TranscriptCursorSweep.readBatch + 10)
        #expect(second.filesRead == 0)
    }
}
