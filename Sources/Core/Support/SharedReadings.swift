import Foundation

public actor SharedReadings<Key: Hashable & Sendable, Value: Sendable> {
    private struct Kept {
        let value: Value
        let at: ContinuousClock.Instant
    }

    private struct InFlight {
        let reading: Task<Value, any Error>
        let startedAt: ContinuousClock.Instant
        let number: UInt64
    }

    private let now: @Sendable () -> ContinuousClock.Instant
    private let retention: Duration
    private var kept: [Key: Kept] = [:]
    private var inFlight: [Key: InFlight] = [:]
    private var started: UInt64 = 0

    public init(
        retention: Duration = .seconds(600),
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.retention = retention
        self.now = now
    }

    public func value(
        for key: Key,
        notOlderThan maxAge: Duration,
        read: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let asked = now()
        if let last = kept[key], asked - last.at < maxAge { return last.value }
        if let flight = inFlight[key], asked - flight.startedAt < maxAge { return try await flight.reading.value }

        started &+= 1
        let number = started
        let reading = Task { try await read() }
        inFlight[key] = InFlight(reading: reading, startedAt: asked, number: number)
        let result = await reading.result

        if inFlight[key]?.number == number { inFlight[key] = nil }
        if case .success(let value) = result, kept[key].map({ $0.at < asked }) ?? true {
            kept = kept.filter { asked - $0.value.at < retention }
            kept[key] = Kept(value: value, at: asked)
        }
        return try result.get()
    }

    var keptCount: Int { kept.count }
}
