import Foundation
import Testing
@testable import Core

@Suite struct AgentPresentationFeedTests {
    @Test func aStalledWindowRecoversEveryTextChunkWithoutKeepingEveryEvent() throws {
        let feed = AgentPresentationFeed(maxItems: 4, maxBytes: 1_024)
        for _ in 0..<2_000 { feed.yield(.streamDelta(.text("é🌱"))) }
        let batch = feed.read(after: 0)
        let recovery = try #require(batch.recovery)
        #expect(recovery.text == String(repeating: "é🌱", count: 2_000))
        #expect(feed.retainedUsage.items <= 4)
        #expect(feed.retainedUsage.bytes <= 1_024)
        #expect(batch.events.isEmpty)
    }

    @Test func overflowingACompletedBlockKeepsTheTerminalStateAndClearsLiveText() throws {
        let feed = AgentPresentationFeed(maxItems: 2)
        feed.yield(.streamDelta(.text("partial")))
        feed.yield(.result(AgentResult(summary: "Finished")))
        for _ in 0..<10 { feed.yield(.status("idle")) }
        let recovery = try #require(feed.read(after: 0).recovery)
        #expect(recovery.text.isEmpty)
        guard case .result(let result) = recovery.stateEvent else {
            Issue.record("The completion must survive overflow")
            return
        }
        #expect(result.summary == "Finished")
    }

    @Test func onlyTheProcessEndingCountsAsAnEnd() {
        let feed = AgentPresentationFeed()
        feed.yield(.result(AgentResult(summary: "Finished")))
        feed.yield(.error(AgentError(message: "Gone")))
        #expect(feed.processEnds == 0)
        feed.noteProcessEnded()
        feed.noteProcessEnded()
        #expect(feed.processEnds == 2)
        #expect(!feed.isTurnRunning)
    }

    @Test func independentSubscribersDoNotConsumeEachOthersWakeups() async throws {
        let feed = AgentPresentationFeed(maxItems: 2)
        var first = feed.notifications().makeAsyncIterator()
        var second = feed.notifications().makeAsyncIterator()
        _ = await first.next()
        _ = await second.next()
        for index in 0..<1_000 { feed.yield(.status(String(index))) }
        let firstRevision = await first.next()
        let secondRevision = await second.next()
        #expect(firstRevision == 1_000)
        #expect(secondRevision == 1_000)
        feed.finish()
        let firstEnd = await first.next()
        let secondEnd = await second.next()
        #expect(firstEnd == nil)
        #expect(secondEnd == nil)
    }

    @Test func aFastConsumerReceivesLifecycleBoundariesInOrder() {
        let feed = AgentPresentationFeed()
        feed.yield(.streamDelta(.text("answer")))
        feed.yield(.permissionDecided(PermissionResolution(requestID: "q", decision: "allow")))
        feed.yield(.result(AgentResult()))
        let batch = feed.read(after: 0)
        #expect(batch.recovery == nil)
        #expect(batch.events.count == 3)
        guard case .permissionDecided = batch.events[1], case .result = batch.events[2] else {
            Issue.record("Critical events must stay ordered")
            return
        }
        #expect(feed.read(after: batch.revision).events.isEmpty)
    }
}

extension AgentPresentationFeedTests {
    @Test func lifecycleOverflowKeepsCompletionBeforeAnAutonomousFollowup() throws {
        let feed = AgentPresentationFeed(maxItems: 2)
        feed.yield(.result(AgentResult(summary: "First finished")), messageSeq: 10)
        feed.yield(.initialized(AgentInit(sessionID: "session")), messageSeq: 11)
        for word in ["new", " autonomous", " answer"] { feed.yield(.streamDelta(.text(word))) }
        let batch = feed.read(after: 0)
        #expect(batch.recovery != nil)
        let firstPage = try feed.lifecycleEvents(after: 0, through: batch.revision, limit: 1)
        #expect(firstPage.count == 1)
        guard case .result(let result) = firstPage[0].event else {
            Issue.record("Completion must precede the autonomous start")
            return
        }
        #expect(result.summary == "First finished")
        #expect(firstPage[0].messageSeq == 10)
        #expect(feed.hasLaterTurn(than: firstPage[0].revision))
        let secondPage = try feed.lifecycleEvents(after: firstPage[0].revision, through: batch.revision, limit: 1)
        #expect(secondPage.count == 1)
        guard case .initialized = secondPage[0].event else {
            Issue.record("The autonomous start must also survive")
            return
        }
        #expect(secondPage[0].messageSeq == 11)
        #expect(!AgentPresentationReconciliation.permitsAutomaticDrain(isCatchingUp: true, isTurnRunning: false))
        #expect(!AgentPresentationReconciliation.permitsAutomaticDrain(isCatchingUp: false, isTurnRunning: feed.isTurnRunning))
        #expect(batch.recovery?.text == "new autonomous answer")
    }

    @Test func acknowledgedLifecycleHistoryIsReclaimedOnlyAfterEverySubscriber() throws {
        let feed = AgentPresentationFeed(maxItems: 2)
        let first = UUID()
        let second = UUID()
        let firstStream = feed.notifications(id: first, after: 0)
        let secondStream = feed.notifications(id: second, after: 0)
        defer { withExtendedLifetime((firstStream, secondStream)) {} }
        feed.yield(.result(AgentResult(summary: "finished")))
        let revision = feed.snapshot().revision
        #expect(feed.retainedLifecycleBytes > 0)
        feed.acknowledge(subscriber: first, through: revision)
        #expect(feed.retainedLifecycleBytes > 0)
        #expect(try feed.lifecycleEvents(after: 0, through: revision).count == 1)
        feed.acknowledge(subscriber: second, through: revision)
        #expect(feed.retainedLifecycleBytes == 0)
        feed.unsubscribe(first)
        feed.unsubscribe(second)
        feed.finish()
    }

    @Test func lifecycleCapacityFailureIsExplicitRatherThanDroppingTheBoundary() {
        let feed = AgentPresentationFeed(lifecycleCapacity: 1)
        feed.yield(.result(AgentResult(summary: "will not fit")))
        #expect(feed.read(after: 0).failure != nil)
        #expect(feed.retainedLifecycleBytes == 0)
    }

    @Test func finishPreservesTheFinalUnacknowledgedBoundaryUntilConsumption() throws {
        let feed = AgentPresentationFeed(maxItems: 1)
        let reader = UUID()
        let stream = feed.notifications(id: reader, after: 0)
        defer { withExtendedLifetime(stream) {} }
        feed.yield(.result(AgentResult(summary: "last")), messageSeq: 7)
        let revision = feed.snapshot().revision
        feed.finish()
        #expect(try feed.lifecycleEvents(after: 0, through: revision).first?.messageSeq == 7)
        feed.acknowledge(subscriber: reader, through: revision)
        #expect(feed.retainedLifecycleBytes == 0)
        feed.unsubscribe(reader)
    }
}

extension AgentPresentationFeedTests {
    @Test func pagedLifecycleReplayCrossesSparseOffsetsWithoutDuplicates() throws {
        let feed = AgentPresentationFeed(maxItems: 1)
        let reader = UUID()
        let stream = feed.notifications(id: reader, after: 0)
        defer { withExtendedLifetime(stream) {}; feed.unsubscribe(reader) }
        for index in 0..<150 {
            feed.yield(.result(AgentResult(summary: String(index))), messageSeq: index)
        }
        let end = feed.snapshot().revision
        var cursor: UInt64 = 0
        var sequences: [Int] = []
        while true {
            let page = try feed.lifecycleEvents(after: cursor, through: end, limit: 7)
            guard let last = page.last else { break }
            #expect(page.count <= 7)
            sequences.append(contentsOf: page.compactMap(\.messageSeq))
            cursor = last.revision
            feed.acknowledge(subscriber: reader, through: cursor)
        }
        #expect(sequences == Array(0..<150))
        #expect(feed.retainedLifecycleBytes == 0)
    }
}

extension AgentPresentationFeedTests {
    @Test func acknowledgingAPageLetsGoOfTheEntriesItCovered() {
        let feed = AgentPresentationFeed()
        let reader = UUID()
        let stream = feed.notifications(id: reader, after: 0)
        defer { withExtendedLifetime(stream) {}; feed.unsubscribe(reader) }
        for index in 0..<100 { feed.yield(.status(String(repeating: "x", count: 1_000) + String(index))) }
        let before = feed.retainedUsage
        let revision = feed.snapshot().revision

        feed.acknowledge(subscriber: reader, through: revision - 10)
        let after = feed.retainedUsage

        #expect(before.items == 100)
        #expect(after.items == 10)
        #expect(after.bytes < before.bytes / 5)
        #expect(feed.read(after: revision - 10).events.count == 10)
    }

    @Test func aSlowerSubscriberStillReadsWhatItHasNotAcknowledged() {
        let feed = AgentPresentationFeed()
        let fast = UUID()
        let slow = UUID()
        let fastStream = feed.notifications(id: fast, after: 0)
        let slowStream = feed.notifications(id: slow, after: 0)
        defer {
            withExtendedLifetime((fastStream, slowStream)) {}
            feed.unsubscribe(fast)
            feed.unsubscribe(slow)
        }
        for index in 0..<20 { feed.yield(.status(String(index))) }
        feed.acknowledge(subscriber: slow, through: 5)

        feed.acknowledge(subscriber: fast, through: 20)
        let slowBatch = feed.read(after: 5)

        #expect(slowBatch.recovery == nil)
        #expect(slowBatch.eventRevisions == Array(6...20))
        #expect(feed.retainedUsage.items == 15)
    }

    @Test func aSubscriberJoiningBehindTheDroppedEntriesRecoversInsteadOfReadingAHole() {
        let feed = AgentPresentationFeed()
        let first = UUID()
        let firstStream = feed.notifications(id: first, after: 0)
        defer { withExtendedLifetime(firstStream) {}; feed.unsubscribe(first) }
        feed.yield(.streamDelta(.text("hello ")))
        feed.yield(.streamDelta(.text("world")))
        feed.acknowledge(subscriber: first, through: feed.snapshot().revision)

        let late = UUID()
        let lateStream = feed.notifications(id: late, after: 0)
        defer { withExtendedLifetime(lateStream) {}; feed.unsubscribe(late) }
        let batch = feed.read(after: 0)

        #expect(batch.events.isEmpty)
        #expect(batch.recovery?.text == "hello world")
    }

    @Test func readingAfterACursorReturnsOnlyWhatFollowsIt() {
        let feed = AgentPresentationFeed()
        for index in 0..<10 { feed.yield(.status(String(index)), messageSeq: index) }
        let batch = feed.read(after: 7)
        #expect(batch.eventRevisions == [8, 9, 10])
        #expect(batch.messageSequences == [7, 8, 9])
        #expect(batch.events.count == 3)
    }
}

extension AgentPresentationFeedTests {
    @Test func theLastSubscriberLeavingLetsGoOfEveryEntry() {
        let feed = AgentPresentationFeed()
        let reader = UUID()
        let stream = feed.notifications(id: reader, after: 0)
        for index in 0..<20 { feed.yield(.status(String(index))) }

        feed.unsubscribe(reader)

        withExtendedLifetime(stream) {}
        #expect(feed.retainedUsage.items == 0)
        #expect(feed.retainedUsage.bytes == 0)
    }

    @Test func aSubscriberLeavingKeepsWhatTheOtherHasNotAcknowledged() {
        let feed = AgentPresentationFeed()
        let staying = UUID()
        let leaving = UUID()
        let stayingStream = feed.notifications(id: staying, after: 0)
        let leavingStream = feed.notifications(id: leaving, after: 0)
        defer { withExtendedLifetime((stayingStream, leavingStream)) {}; feed.unsubscribe(staying) }
        for index in 0..<20 { feed.yield(.status(String(index))) }
        feed.acknowledge(subscriber: staying, through: 12)

        feed.unsubscribe(leaving)

        #expect(feed.retainedUsage.items == 8)
        #expect(feed.read(after: 12).eventRevisions == Array(13...20))
    }

    @Test func aPumpJoiningAfterAnotherAcknowledgedRecoversFromItsBaseline() {
        let feed = AgentPresentationFeed()
        let first = UUID()
        let firstStream = feed.notifications(id: first, after: 0)
        defer { withExtendedLifetime(firstStream) {}; feed.unsubscribe(first) }
        feed.yield(.streamDelta(.text("early ")))
        let baseline = feed.snapshot()
        feed.yield(.streamDelta(.text("late")))
        feed.acknowledge(subscriber: first, through: feed.snapshot().revision)

        let joining = UUID()
        let joiningStream = feed.notifications(id: joining, after: baseline.revision)
        defer { withExtendedLifetime(joiningStream) {}; feed.unsubscribe(joining) }
        let batch = feed.read(after: baseline.revision)

        #expect(batch.events.isEmpty)
        #expect(batch.recovery?.text == "early late")
    }
}
