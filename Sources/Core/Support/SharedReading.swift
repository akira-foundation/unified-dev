import Foundation

public actor SharedReading<Value: Sendable> {
    private let read: @Sendable () async -> Value?
    private let now: @Sendable () -> ContinuousClock.Instant
    private var last: (value: Value, at: ContinuousClock.Instant)?
    private var inFlight: (reading: Task<Value?, Never>, startedAt: ContinuousClock.Instant)?
    private var generation = 0
    private(set) var waitingOnRead = 0

    public init(
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now },
        read: @escaping @Sendable () async -> Value?
    ) {
        self.now = now
        self.read = read
    }

    public func value(notOlderThan maxAge: Duration) async -> Value? {
        let asked = now()
        if let last, asked - last.at < maxAge { return last.value }
        if let inFlight, asked - inFlight.startedAt < maxAge {
            waitingOnRead += 1
            defer { waitingOnRead -= 1 }
            return await inFlight.reading.value
        }
        let reading = Task { await read() }
        let started = generation
        inFlight = (reading, asked)
        let value = await reading.value
        guard generation == started else { return value }
        if inFlight?.startedAt == asked { inFlight = nil }
        if let value, last.map({ $0.at < asked }) ?? true { last = (value, asked) }
        return value
    }

    public func invalidate() {
        generation += 1
        last = nil
        inFlight = nil
    }
}
