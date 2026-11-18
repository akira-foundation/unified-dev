import Testing
@testable import Core

@Suite("Matched runs")
struct MatchedRunTests {
    @Test("a name with no highlights is one plain run")
    func noHighlights() {
        #expect(MatchedRun.split("Pin", highlights: []) == [MatchedRun(text: "Pin", isHit: false)])
    }

    @Test("neighbouring hits join into one run, and the gaps between them stay plain")
    func runsJoinAndAlternate() {
        #expect(MatchedRun.split("Previous Workspace", highlights: [0, 1, 9]) == [
            MatchedRun(text: "Pr", isHit: true),
            MatchedRun(text: "evious ", isHit: false),
            MatchedRun(text: "W", isHit: true),
            MatchedRun(text: "orkspace", isHit: false),
        ])
    }

    @Test("highlights count characters, so a composed character is one position")
    func charactersNotScalars() {
        #expect(MatchedRun.split("Caf\u{E9} Pr\u{E9}", highlights: [3, 7]) == [
            MatchedRun(text: "Caf", isHit: false),
            MatchedRun(text: "\u{E9}", isHit: true),
            MatchedRun(text: " Pr", isHit: false),
            MatchedRun(text: "\u{E9}", isHit: true),
        ])
    }

    @Test("a highlight past the end is ignored rather than drawn")
    func outOfRange() {
        #expect(MatchedRun.split("ab", highlights: [1, 5]) == [
            MatchedRun(text: "a", isHit: false),
            MatchedRun(text: "b", isHit: true),
        ])
    }

    @Test("an empty name has no runs")
    func empty() {
        #expect(MatchedRun.split("", highlights: [0]).isEmpty)
    }
}
