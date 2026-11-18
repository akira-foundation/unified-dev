import Foundation

public struct MatchedRun: Equatable, Sendable {
    public var text: String
    public var isHit: Bool

    public init(text: String, isHit: Bool) {
        self.text = text
        self.isHit = isHit
    }

    public static func split(_ string: String, highlights: [Int]) -> [MatchedRun] {
        let characters = Array(string)
        let hits = Set(highlights)
        var runs: [MatchedRun] = []
        var start = 0
        while start < characters.count {
            let isHit = hits.contains(start)
            var end = start
            while end < characters.count, hits.contains(end) == isHit { end += 1 }
            runs.append(MatchedRun(text: String(characters[start..<end]), isHit: isHit))
            start = end
        }
        return runs
    }
}
