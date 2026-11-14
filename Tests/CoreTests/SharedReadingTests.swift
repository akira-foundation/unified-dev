import Testing
import Foundation
import Synchronization
@testable import Core

private final class ReadCounter: Sendable {
    private let count = Mutex(0)
    var reads: Int { count.withLock { $0 } }
    func read() -> Int { count.withLock { $0 += 1; return $0 } }
}

private final class FakeClock: Sendable {
    private let instant = Mutex(ContinuousClock.now)
    var now: ContinuousClock.Instant { instant.withLock { $0 } }
    func advance(_ by: Duration) { instant.withLock { $0 += by } }
}

private final class ReadGate: Sendable {
    private let state = Mutex<(isOpen: Bool, waiting: [CheckedContinuation<Void, Never>])>((false, []))

    func open() {
        let waiting = state.withLock { state in
            state.isOpen = true
            defer { state.waiting = [] }
            return state.waiting
        }
        for continuation in waiting { continuation.resume() }
    }

    func passed() async {
        await withCheckedContinuation { continuation in
            let isOpen = state.withLock { state in
                if !state.isOpen { state.waiting.append(continuation) }
                return state.isOpen
            }
            if isOpen { continuation.resume() }
        }
    }
}

@Suite struct SharedReadingTests {
    @Test func callersWithinTheAgeShareOneReading() async {
        let counter = ReadCounter()
        let clock = FakeClock()
        let reading = SharedReading<Int>(now: { clock.now }) { counter.read() }

        let first = await reading.value(notOlderThan: .seconds(2))
        clock.advance(.seconds(1))
        let second = await reading.value(notOlderThan: .seconds(2))

        #expect(first == 1)
        #expect(second == 1)
        #expect(counter.reads == 1)
    }

    @Test func aReadingOlderThanTheAgeIsTakenAgain() async {
        let counter = ReadCounter()
        let clock = FakeClock()
        let reading = SharedReading<Int>(now: { clock.now }) { counter.read() }

        _ = await reading.value(notOlderThan: .seconds(2))
        clock.advance(.seconds(2))
        let again = await reading.value(notOlderThan: .seconds(2))

        #expect(again == 2)
        #expect(counter.reads == 2)
    }

    @Test func aZeroAgeAlwaysReadsAfresh() async {
        let counter = ReadCounter()
        let reading = SharedReading<Int> { counter.read() }

        _ = await reading.value(notOlderThan: .seconds(60))
        let fresh = await reading.value(notOlderThan: .zero)

        #expect(fresh == 2)
    }

    @Test func callersArrivingDuringAReadWaitForIt() async {
        let counter = ReadCounter()
        let clock = FakeClock()
        let gate = ReadGate()
        let reading = SharedReading<Int>(now: { clock.now }) {
            await gate.passed()
            return counter.read()
        }

        async let first = reading.value(notOlderThan: .seconds(2))
        async let second = reading.value(notOlderThan: .seconds(2))
        async let third = reading.value(notOlderThan: .seconds(2))
        await waitUntil("two callers wait on the read the first one started") { await reading.waitingOnRead == 2 }
        gate.open()
        let values = await [first, second, third]

        #expect(counter.reads == 1)
        #expect(values == [1, 1, 1])
    }

    @Test func aFailedReadingIsNotKept() async {
        let counter = ReadCounter()
        let reading = SharedReading<Int> { counter.read() == 1 ? nil : 7 }

        let failed = await reading.value(notOlderThan: .seconds(60))
        let next = await reading.value(notOlderThan: .seconds(60))

        #expect(failed == nil)
        #expect(next == 7)
        #expect(counter.reads == 2)
    }

    @Test func aFreshCallerDoesNotJoinAReadThatStartedBeforeIt() async {
        let counter = ReadCounter()
        let reading = SharedReading<Int> {
            try? await Task.sleep(for: .milliseconds(200))
            return counter.read()
        }

        async let older = reading.value(notOlderThan: .seconds(2))
        try? await Task.sleep(for: .milliseconds(50))
        let fresh = await reading.value(notOlderThan: .zero)
        _ = await older

        #expect(counter.reads == 2)
        #expect(fresh == 2)
    }

    @Test func aReadingCountsFromWhenItWasAskedFor() async {
        let counter = ReadCounter()
        let clock = FakeClock()
        let reading = SharedReading<Int>(now: { clock.now }) {
            clock.advance(.seconds(1))
            return counter.read()
        }

        _ = await reading.value(notOlderThan: .seconds(2))
        clock.advance(.milliseconds(500))
        let stillShared = await reading.value(notOlderThan: .seconds(2))
        clock.advance(.milliseconds(600))
        let taken = await reading.value(notOlderThan: .seconds(2))

        #expect(stillShared == 1)
        #expect(taken == 2)
    }

    @Test func invalidatingForgetsTheKeptReading() async {
        let counter = ReadCounter()
        let reading = SharedReading<Int> { counter.read() }

        _ = await reading.value(notOlderThan: .seconds(60))
        await reading.invalidate()
        let next = await reading.value(notOlderThan: .seconds(60))

        #expect(next == 2)
    }
}
