import Foundation

public enum HunkPatch {
    typealias Line = [UInt8]

    public static func isolate(_ hunk: DiffHunk, from patch: Data) -> Data? {
        let files = DiffParser.parse(String(decoding: patch, as: UTF8.self))
        guard files.count == 1, let file = files.first else { return nil }
        guard let position = file.hunks.firstIndex(where: { matches($0, hunk) }) else { return nil }

        let lines = split(patch)
        guard let newPath = lines.first(where: { $0.starts(with: newMarker) }),
              let oldPath = oldSide(of: newPath) else { return nil }

        let starts = lines.indices.filter { lines[$0].starts(with: hunkMarker) }
        guard starts.count == file.hunks.count else { return nil }

        let start = starts[position]
        var end = position + 1 < starts.count ? starts[position + 1] : lines.count
        if end == lines.count, lines.last?.isEmpty == true { end -= 1 }
        let body = lines[start..<end]

        return join([header(old: oldPath, new: newPath), oldPath, newPath] + body)
    }

    public static let wholeFileContext = 1_000_000

    public static func addsLinesThatAreNotUTF8(_ patch: Data) -> Bool {
        split(patch)
            .drop { !$0.starts(with: hunkMarker) }
            .contains { $0.first == UInt8(ascii: "+") && String(validating: $0, as: UTF8.self) == nil }
    }

    public static func anchor(_ hunk: DiffHunk, in whole: Data) -> Data? {
        let files = DiffParser.parse(String(decoding: whole, as: UTF8.self))
        guard files.count == 1, let file = files.first, file.hunks.count == 1,
              let merged = file.hunks.first, merged.oldStart <= 1, merged.newStart <= 1
        else { return nil }

        let lines = split(whole)
        guard let newPath = lines.first(where: { $0.starts(with: newMarker) }),
              let oldPath = oldSide(of: newPath),
              let heading = lines.firstIndex(where: { $0.starts(with: hunkMarker) })
        else { return nil }

        var body = Array(lines[(heading + 1)...])
        if body.last?.isEmpty == true { body.removeLast() }
        guard let region = region(of: hunk, in: body.map { String(decoding: $0, as: UTF8.self) })
        else { return nil }

        let rewritten = reduce(body, keeping: region)
        let counts = "@@ -\(rewritten.oldStart),\(rewritten.oldCount)"
            + " +\(rewritten.newStart),\(rewritten.newCount) @@"
        return join([header(old: oldPath, new: newPath), oldPath, newPath, Line(counts.utf8)] + rewritten.body)
    }

    struct Reduced {
        var body: [Line] = []
        var oldCount = 0
        var newCount = 0

        var oldStart: Int { oldCount == 0 ? 0 : 1 }
        var newStart: Int { newCount == 0 ? 0 : 1 }
    }

    static func reduce(_ body: [Line], keeping region: Range<Int>) -> Reduced {
        var reduced = Reduced()
        var dropped = false
        for (index, line) in body.enumerated() {
            let kept = region.contains(index)
            switch line.first {
            case UInt8(ascii: "\\"):
                if !dropped { reduced.body.append(line) }
            case UInt8(ascii: "-"):
                dropped = !kept
                if kept {
                    reduced.body.append(line)
                    reduced.oldCount += 1
                }
            case UInt8(ascii: "+"):
                dropped = false
                reduced.body.append(kept ? line : [UInt8(ascii: " ")] + line.dropFirst())
                reduced.newCount += 1
                if !kept { reduced.oldCount += 1 }
            default:
                dropped = false
                reduced.body.append(line)
                reduced.oldCount += 1
                reduced.newCount += 1
            }
        }
        return reduced
    }

    static func region(of hunk: DiffHunk, in body: [String]) -> Range<Int>? {
        let wanted = hunk.lines
            .filter { $0.kind != .noNewline }
            .map { mark(of: $0.kind) + $0.text }
        guard !wanted.isEmpty else { return nil }
        let linesAbove = hunk.newCount == 0 ? hunk.newStart : hunk.newStart - 1

        var newSideBefore: [Int] = []
        var seen = 0
        for line in body {
            newSideBefore.append(seen)
            if line.hasPrefix(" ") || line.hasPrefix("+") { seen += 1 }
        }

        var found: Range<Int>?
        for start in body.indices where newSideBefore[start] == linesAbove {
            var index = start
            var position = 0
            while index < body.count, position < wanted.count {
                if body[index].hasPrefix("\\") {
                    index += 1
                    continue
                }
                guard body[index] == wanted[position] else { break }
                index += 1
                position += 1
            }
            guard position == wanted.count else { continue }
            if index < body.count, body[index].hasPrefix("\\") { index += 1 }
            guard found == nil else { return nil }
            found = start..<index
        }
        return found
    }

    static func mark(of kind: DiffLine.Kind) -> String {
        switch kind {
        case .context: " "
        case .addition: "+"
        case .deletion: "-"
        case .noNewline: "\\ "
        }
    }

    static func split(_ patch: Data) -> [Line] {
        patch.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false).map { Line($0) }
    }

    static func join(_ lines: [Line]) -> Data {
        Data(lines.joined(separator: [UInt8(ascii: "\n")]) + [UInt8(ascii: "\n")])
    }

    static func header(old: Line, new: Line) -> Line {
        Line("diff --git ".utf8) + name(of: old, after: oldMarker) + [UInt8(ascii: " ")]
            + name(of: new, after: newMarker)
    }

    static func name(of line: Line, after marker: Line) -> Line {
        var name = line.dropFirst(marker.count)
        while name.last == UInt8(ascii: "\t") { name = name.dropLast() }
        return Line(name)
    }

    static func oldSide(of newPath: Line) -> Line? {
        let name = newPath.dropFirst(newMarker.count)
        if name.starts(with: "\"b/".utf8) { return oldMarker + "\"a/".utf8 + name.dropFirst(3) }
        if name.starts(with: "b/".utf8) { return oldMarker + "a/".utf8 + name.dropFirst(2) }
        return nil
    }

    private static let oldMarker = Line("--- ".utf8)
    private static let newMarker = Line("+++ ".utf8)
    private static let hunkMarker = Line("@@".utf8)

    private static func matches(_ lhs: DiffHunk, _ rhs: DiffHunk) -> Bool {
        lhs.oldStart == rhs.oldStart && lhs.oldCount == rhs.oldCount
            && lhs.newStart == rhs.newStart && lhs.newCount == rhs.newCount
            && lhs.lines.map(\.kind) == rhs.lines.map(\.kind)
            && lhs.lines.map(\.text) == rhs.lines.map(\.text)
    }
}
