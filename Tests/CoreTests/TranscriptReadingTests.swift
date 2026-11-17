import Testing
import Foundation
@testable import Core

private func line(_ output: Int, at stamp: String = "2026-10-09T12:00:00.000Z") -> String {
    """
    {"type":"assistant","timestamp":"\(stamp)","cwd":"/Users/ada/work",\
    "message":{"model":"claude-opus-5","usage":{"input_tokens":1,"output_tokens":\(output),\
    "cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
    """
}

private struct Scratch: ~Copyable {
    let directory: URL

    init() throws {
        directory = URL(filePath: NSTemporaryDirectory())
            .appending(path: "spend-reading-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func write(_ text: String, to name: String) throws -> TranscriptFile {
        let url = directory.appending(path: name)
        try Data(text.utf8).write(to: url)
        return try file(at: url)
    }

    func append(_ text: String, to name: String) throws -> TranscriptFile {
        let url = directory.appending(path: name)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
        return try file(at: url)
    }

    func file(at url: URL) throws -> TranscriptFile {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return TranscriptFile(
            provider: .claudeCode,
            url: url,
            size: values.fileSize ?? 0,
            modifiedAt: values.contentModificationDate ?? Date()
        )
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

@Suite("Transcript reading")
struct TranscriptReadingTests {
    @Test("a file read to the end reports every turn in it")
    func readsWholeFile() throws {
        let scratch = try Scratch()
        let file = try scratch.write([line(1), line(2), line(3)].joined(separator: "\n") + "\n", to: "a.jsonl")
        let result = try TranscriptReader.read(file, from: 0, carry: TranscriptCarry())
        #expect(result.records.map(\.usage.output) == [1, 2, 3])
        #expect(result.reachedEnd)
        #expect(result.offset == file.size)
    }

    @Test("a line still being written is left for the next read")
    func halfWrittenLastLine() throws {
        let scratch = try Scratch()
        let whole = line(7)
        let file = try scratch.write(line(1) + "\n" + String(whole.prefix(40)), to: "b.jsonl")
        let first = try TranscriptReader.read(file, from: 0, carry: TranscriptCarry())
        #expect(first.records.map(\.usage.output) == [1])
        #expect(first.offset < file.size)

        let grown = try scratch.append(String(whole.dropFirst(40)) + "\n", to: "b.jsonl")
        let second = try TranscriptReader.read(grown, from: first.offset, carry: first.carry)
        #expect(second.records.map(\.usage.output) == [7])
    }

    @Test("a refresh reads only what grew")
    func readsOnlyTheGrowth() throws {
        let scratch = try Scratch()
        let file = try scratch.write(line(1) + "\n", to: "c.jsonl")
        let first = try TranscriptReader.read(file, from: 0, carry: TranscriptCarry())
        let grown = try scratch.append(line(2) + "\n", to: "c.jsonl")
        let second = try TranscriptReader.read(grown, from: first.offset, carry: first.carry)
        #expect(second.records.map(\.usage.output) == [2])
        #expect(second.bytesRead < grown.size)
    }

    @Test("a budget stops the read and the next one carries on from there")
    func budgetStopsAndResumes() throws {
        let scratch = try Scratch()
        let body = (1...50).map { line($0) }.joined(separator: "\n") + "\n"
        let file = try scratch.write(body, to: "d.jsonl")

        var offset = 0
        var carry = TranscriptCarry()
        var outputs: [Int] = []
        var reads = 0
        while true {
            let result = try TranscriptReader.read(file, from: offset, carry: carry, budget: 1)
            outputs += result.records.map(\.usage.output)
            offset = result.offset
            carry = result.carry
            reads += 1
            if result.reachedEnd { break }
            #expect(reads < 100)
        }
        #expect(outputs == Array(1...50))
        #expect(reads > 1)
    }

    @Test("a file read before and unchanged since is not read again")
    func unchangedFileIsSkipped() throws {
        let scratch = try Scratch()
        let file = try scratch.write(line(1) + "\n", to: "e.jsonl")
        let cursor = TranscriptCursor(
            path: file.url.path,
            provider: .claudeCode,
            size: file.size,
            modifiedAt: file.modifiedAt,
            offset: file.size
        )
        #expect(TranscriptWork.decide(for: file, cursor: cursor) == .unchanged)
    }

    @Test("a file that grew is read from where the last read stopped")
    func growthIsWork() throws {
        let scratch = try Scratch()
        let file = try scratch.write(line(1) + "\n" + line(2) + "\n", to: "f.jsonl")
        let cursor = TranscriptCursor(
            path: file.url.path, provider: .claudeCode, size: 40, modifiedAt: file.modifiedAt, offset: 40
        )
        #expect(TranscriptWork.decide(for: file, cursor: cursor) == .grew(from: 40, carry: TranscriptCarry()))
    }

    @Test("a file that shrank is read over from the start")
    func shrinkStartsOver() throws {
        let scratch = try Scratch()
        let file = try scratch.write(line(1) + "\n", to: "g.jsonl")
        let cursor = TranscriptCursor(
            path: file.url.path,
            provider: .claudeCode,
            size: file.size + 5_000,
            modifiedAt: file.modifiedAt,
            offset: file.size + 5_000
        )
        #expect(TranscriptWork.decide(for: file, cursor: cursor) == .fresh)
    }

    @Test("a file rewritten to the same size is read over rather than trusted")
    func sameSizeRewriteStartsOver() throws {
        let scratch = try Scratch()
        let file = try scratch.write(line(1) + "\n", to: "i.jsonl")
        let cursor = TranscriptCursor(
            path: file.url.path,
            provider: .claudeCode,
            size: file.size,
            modifiedAt: file.modifiedAt.addingTimeInterval(-60),
            offset: file.size
        )
        #expect(TranscriptWork.decide(for: file, cursor: cursor) == .fresh)
    }

    @Test("a clock reading a hair apart is the same file, not a rewrite")
    func clockGrainIsNotARewrite() throws {
        let scratch = try Scratch()
        let file = try scratch.write(line(1) + "\n", to: "j.jsonl")
        let cursor = TranscriptCursor(
            path: file.url.path,
            provider: .claudeCode,
            size: file.size,
            modifiedAt: file.modifiedAt.addingTimeInterval(0.000_000_1),
            offset: file.size
        )
        #expect(TranscriptWork.decide(for: file, cursor: cursor) == .unchanged)
    }

    @Test("a line too long to hold is abandoned without losing the lines after it")
    func abandonedLineKeepsItsPlace() throws {
        let scratch = try Scratch()
        let filler = String(repeating: "x", count: 400_000)
        let fat = "{\"type\":\"assistant\",\"filler\":\"" + filler + "\"}"
        let file = try scratch.write(
            [line(1), fat, line(2), line(3)].joined(separator: "\n") + "\n", to: "k.jsonl"
        )
        let result = try TranscriptReader.read(
            file, from: 0, carry: TranscriptCarry(), lineCeiling: 1_000, chunkSize: 512
        )
        #expect(result.abandonedLines == 1)
        #expect(result.records.map(\.usage.output) == [1, 2, 3])
        #expect(result.offset == file.size)
    }

    @Test("a line as long as the whole budget is abandoned rather than read again for ever")
    func lineAsLongAsTheBudgetMovesOn() throws {
        let scratch = try Scratch()
        let fat = String(repeating: "x", count: 2_000)
        let file = try scratch.write([line(1), fat, line(2)].joined(separator: "\n") + "\n", to: "b.jsonl")

        var offset = 0
        var carry = TranscriptCarry()
        var outputs: [Int] = []
        var abandoned = 0
        var reads = 0
        while reads < 100 {
            let result = try TranscriptReader.read(file, from: offset, carry: carry, budget: 512, chunkSize: 64)
            outputs += result.records.map(\.usage.output)
            abandoned += result.abandonedLines
            offset = result.offset
            carry = result.carry
            reads += 1
            if result.reachedEnd { break }
        }
        #expect(outputs == [1, 2])
        #expect(abandoned == 1)
        #expect(offset == file.size)
    }

    @Test("a file never read before is read over from the start")
    func unknownFileStartsOver() throws {
        let scratch = try Scratch()
        let file = try scratch.write(line(1) + "\n", to: "h.jsonl")
        #expect(TranscriptWork.decide(for: file, cursor: nil) == .fresh)
    }
}
