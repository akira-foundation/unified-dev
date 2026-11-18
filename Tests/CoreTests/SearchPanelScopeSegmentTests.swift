import Testing
@testable import Core

@Suite("Search panel scope segments")
struct SearchPanelScopeSegmentTests {
    private var counts: HomeScopeCounts {
        var counts = HomeScopeCounts()
        counts.workspaces = 3
        counts.transcripts = 1098
        counts.archived = 332
        counts.profiles = 1
        return counts
    }

    @Test("the four scopes are offered in order, each named with its count")
    func segmentsCarryTheirCounts() {
        let segments = SearchPanelScopeSegment.offered(counts: counts)
        #expect(segments.map(\.scope) == [.all, .workspaces, .transcripts, .archived])
        #expect(segments.map(\.title) == [
            "Everything (1102)", "Workspaces (3)", "Transcripts (1098)", "Archived (332)",
        ])
    }

    @Test("a scope with nothing in it still says so rather than vanishing")
    func emptyScopeKeepsItsSegment() {
        let segments = SearchPanelScopeSegment.offered(counts: HomeScopeCounts())
        #expect(segments.count == 4)
        #expect(segments.first { $0.scope == .workspaces }?.title == "Workspaces (0)")
    }

    @Test("a segment is identified by its scope, so the picker's tag and the panel's scope are one value")
    func segmentIdentity() {
        let segments = SearchPanelScopeSegment.offered(counts: counts)
        #expect(segments.map(\.id) == segments.map(\.scope))
        #expect(Set(segments.map(\.id)).count == segments.count)
    }
}
