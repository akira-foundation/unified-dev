import Foundation
import Testing
@testable import Core

@Suite("Side conversation lifecycle")
struct SideConversationLifecycleTests {
    private typealias Arrival = SideConversationLifecycle.Arrival

    private func opening(_ start: SideConversationLifecycle.Start) -> SideConversationLifecycle.Opening? {
        guard case .open(let opening) = start else { return nil }
        return opening
    }

    private func arrive(
        _ life: inout SideConversationLifecycle, _ id: SessionID, _ opening: SideConversationLifecycle.Opening
    ) -> Arrival? {
        guard life.opened(id, generation: opening.generation) else { return nil }
        return life.ready(generation: opening.generation)
    }

    private func opened(_ id: SessionID, quoting: String = "") throws -> SideConversationLifecycle {
        var life = SideConversationLifecycle()
        let started = try #require(opening(life.start(quoting: quoting)))
        _ = arrive(&life, id, started)
        return life
    }

    @Test func aStartAfterACloseOpensAFreshConversationWithOnlyTheNewQuote() throws {
        let first = SessionID.new()
        var life = try opened(first, quoting: "old quote")
        let ending = life.close()
        let started = try #require(opening(life.start(quoting: "new quote")))
        let arrival = arrive(&life, SessionID.new(), started)
        #expect(ending == first)
        #expect(started.keeping == nil)
        #expect(arrival == Arrival(quotes: ["new quote"]))
        #expect(life.sessionID != first)
    }

    @Test func hidingKeepsTheConversationAndAReplyQuotesIntoIt() throws {
        let id = SessionID.new()
        var life = try opened(id)
        life.hide()
        let hidden = life.isShown
        let start = life.start(quoting: "more")
        #expect(!hidden)
        #expect(start == .resume(id, Arrival(quotes: ["more"])))
        #expect(life.isShown)
    }

    @Test func closingWhileOpeningDiscardsTheConversationThatArrivesLate() throws {
        var life = SideConversationLifecycle()
        let started = try #require(opening(life.start(question: "Why?", quoting: "q")))
        let ending = life.close()
        let accepted = life.opened(SessionID.new(), generation: started.generation)
        #expect(ending == nil)
        #expect(!accepted)
        #expect(life.phase == .idle)
        #expect(life.pending == Arrival())
    }

    @Test func closingBetweenArrivalAndReadyEndsTheArrivedSession() throws {
        var life = SideConversationLifecycle()
        let started = try #require(opening(life.start()))
        let id = SessionID.new()
        let accepted = life.opened(id, generation: started.generation)
        let ending = life.close()
        let arrival = life.ready(generation: started.generation)
        #expect(accepted)
        #expect(ending == id)
        #expect(arrival == nil)
    }

    @Test func aReplyBeforeTheConversationIsReadyWaitsForIt() throws {
        var life = SideConversationLifecycle()
        let started = try #require(opening(life.start(quoting: "a")))
        let accepted = life.opened(SessionID.new(), generation: started.generation)
        let reply = life.start(quoting: "b")
        let arrival = life.ready(generation: started.generation)
        #expect(accepted)
        #expect(reply == .wait)
        #expect(arrival == Arrival(quotes: ["a", "b"]))
    }

    @Test func aStaleOpeningCannotReplaceTheCurrentOne() throws {
        var life = SideConversationLifecycle()
        let stale = try #require(opening(life.start()))
        _ = life.close()
        let current = try #require(opening(life.start(quoting: "new")))
        let staleAccepted = life.opened(SessionID.new(), generation: stale.generation)
        let arrival = arrive(&life, SessionID.new(), current)
        #expect(!staleAccepted)
        #expect(arrival?.quotes == ["new"])
    }

    @Test func aStaleFailureLeavesTheCurrentOpeningAlone() throws {
        var life = SideConversationLifecycle()
        let stale = try #require(opening(life.start()))
        _ = life.close()
        let current = try #require(opening(life.start()))
        let failure = life.failed(generation: stale.generation)
        #expect(failure == .stale)
        #expect(life.phase == .opening(generation: current.generation, session: nil))
    }

    @Test func everyQuestionAskedWhileOpeningArrives() throws {
        var life = SideConversationLifecycle()
        let started = try #require(opening(life.start(question: "A?", quoting: "a")))
        let second = life.start(question: "B?", quoting: "b")
        let arrival = arrive(&life, SessionID.new(), started)
        #expect(second == .wait)
        #expect(arrival == Arrival(quotes: ["a", "b"], questions: ["A?", "B?"]))
    }

    @Test func keepEndsTheSideConversationSoTheNextStartIsFresh() throws {
        let kept = SessionID.new()
        var life = try opened(kept, quoting: "x")
        let ending = life.keep()
        let shown = life.isShown
        let next = try #require(opening(life.start()))
        #expect(ending == kept)
        #expect(!shown)
        #expect(next.keeping == nil)
    }

    @Test func keepIsRefusedUntilTheConversationIsOpen() {
        var life = SideConversationLifecycle()
        _ = life.start(quoting: "x")
        let ending = life.keep()
        #expect(ending == nil)
        #expect(life.isOpening)
        #expect(life.pending == Arrival(quotes: ["x"]))
    }

    @Test func startingNewKeepsTheOpenOneAndRestoresItWhenTheKeepFails() throws {
        let id = SessionID.new()
        var life = try opened(id)
        let started = try #require(opening(life.start(fresh: true)))
        let queued = life.start(quoting: "during the keep")
        let restored = life.keepFailed(generation: started.generation, restoring: id)
        #expect(started.keeping == id)
        #expect(queued == .wait)
        #expect(restored == Arrival(quotes: ["during the keep"]))
        #expect(life.sessionID == id)
        #expect(life.pending == Arrival())
    }

    @Test func aKeepFailureAfterACloseRestoresNothing() throws {
        let id = SessionID.new()
        var life = try opened(id)
        let started = try #require(opening(life.start(fresh: true)))
        _ = life.close()
        let restored = life.keepFailed(generation: started.generation, restoring: id)
        #expect(restored == nil)
        #expect(life.phase == .idle)
    }

    @Test func aFailedOpeningKeepsWhatWasAskedForTheRetry() throws {
        var life = SideConversationLifecycle()
        let started = try #require(opening(life.start(question: "Why?", quoting: "q")))
        let failure = life.failed(generation: started.generation)
        #expect(failure == .current(arrived: nil))
        let retry = try #require(opening(life.start()))
        let arrival = arrive(&life, SessionID.new(), retry)
        #expect(arrival == Arrival(quotes: ["q"], questions: ["Why?"]))
    }

    @Test func aFailureAfterArrivalNamesTheSessionToEnd() throws {
        var life = SideConversationLifecycle()
        let started = try #require(opening(life.start()))
        let id = SessionID.new()
        _ = life.opened(id, generation: started.generation)
        let failure = life.failed(generation: started.generation)
        #expect(failure == .current(arrived: id))
        #expect(life.phase == .idle)
    }

    @Test func aClosedConversationIsNoLongerPresent() throws {
        var life = try opened(SessionID.new())
        let before = life.isPresent
        _ = life.close()
        #expect(before)
        #expect(!life.isPresent)
    }
}
