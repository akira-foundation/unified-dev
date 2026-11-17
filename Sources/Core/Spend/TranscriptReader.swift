import Foundation

public struct TranscriptReadResult: Sendable {
    public var records: [SpendRecord]
    public var offset: Int
    public var carry: TranscriptCarry
    public var bytesRead: Int
    public var reachedEnd: Bool
    public var abandonedLines: Int

    public init(
        records: [SpendRecord] = [],
        offset: Int = 0,
        carry: TranscriptCarry = TranscriptCarry(),
        bytesRead: Int = 0,
        reachedEnd: Bool = true,
        abandonedLines: Int = 0
    ) {
        self.records = records
        self.offset = offset
        self.carry = carry
        self.bytesRead = bytesRead
        self.reachedEnd = reachedEnd
        self.abandonedLines = abandonedLines
    }
}

public enum TranscriptReader {
    public static let chunkSize = 1 << 20
    public static let defaultBudget = 16 << 20
    public static let lineCeiling = 64 << 20

    static let newline = UInt8(ascii: "\n")

    public static func read(
        _ file: TranscriptFile,
        from start: Int,
        carry: TranscriptCarry,
        budget: Int = defaultBudget,
        lineCeiling: Int = lineCeiling,
        chunkSize: Int = chunkSize
    ) throws -> TranscriptReadResult {
        let ceiling = min(lineCeiling, budget)
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(max(0, start)))

        var result = TranscriptReadResult(offset: max(0, start), carry: carry, reachedEnd: true)
        var pending = [UInt8]()
        var searched = 0
        var pendingStart = result.offset
        var consumed = 0
        var hitEnd = false
        var isDiscarding = carry.isDiscarding

        while consumed < budget {
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else {
                hitEnd = true
                break
            }
            consumed += chunk.count
            result.bytesRead += chunk.count

            if isDiscarding {
                guard let newline = chunk.firstIndex(of: newline) else {
                    pendingStart += chunk.count
                    continue
                }
                let dropped = chunk.distance(from: chunk.startIndex, to: newline) + 1
                pendingStart += dropped
                pending = Array(chunk[chunk.index(after: newline)...])
                searched = 0
                isDiscarding = false
            } else {
                pending.append(contentsOf: chunk)
            }

            drain(&pending, &searched, &pendingStart, file: file, into: &result)

            if pending.count > ceiling || (consumed >= budget && pending.count >= ceiling) {
                result.abandonedLines += 1
                pendingStart += pending.count
                pending.removeAll(keepingCapacity: false)
                searched = 0
                isDiscarding = true
            }
        }

        result.offset = pendingStart
        result.reachedEnd = hitEnd
        result.carry.isDiscarding = isDiscarding
        return result
    }

    private static func drain(
        _ pending: inout [UInt8],
        _ searched: inout Int,
        _ pendingStart: inout Int,
        file: TranscriptFile,
        into result: inout TranscriptReadResult
    ) {
        var carry = result.carry
        var records = result.records
        var cut = 0
        let from = searched
        let start = pendingStart
        pending.withUnsafeBufferPointer { buffer in
            var lineStart = 0
            var index = from
            while index < buffer.count {
                guard buffer[index] == newline else {
                    index += 1
                    continue
                }
                if index > lineStart,
                   var record = UsageLine.record(
                       in: buffer,
                       from: lineStart,
                       to: index,
                       provider: file.provider,
                       carry: &carry
                   ) {
                    if record.key.isEmpty {
                        record.key = SpendRecord.offsetKey(start + lineStart)
                    }
                    records.append(record)
                }
                lineStart = index + 1
                index += 1
            }
            cut = lineStart
        }
        result.records = records
        result.carry = carry
        guard cut > 0 else {
            searched = pending.count
            return
        }
        pending.removeFirst(cut)
        pendingStart += cut
        searched = pending.count
    }
}
