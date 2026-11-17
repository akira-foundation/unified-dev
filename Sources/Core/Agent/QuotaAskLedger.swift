import Foundation

public struct QuotaAskLedger: Sendable, Equatable {
    public private(set) var inFlight: Set<QuotaHolder> = []
    public private(set) var askedAt: [QuotaHolder: Date] = [:]

    public init() {}

    public func due(_ wanted: some Sequence<QuotaHolder>, at now: Date, after gap: TimeInterval) -> Set<QuotaHolder> {
        Set(wanted.filter {
            !inFlight.contains($0) && QuotaPollSchedule.isDue(lastAskedAt: askedAt[$0], at: now, after: gap)
        })
    }

    public mutating func begin(_ holders: Set<QuotaHolder>, at now: Date) {
        inFlight.formUnion(holders)
        for holder in holders { askedAt[holder] = now }
    }

    public mutating func end(_ holders: Set<QuotaHolder>) {
        inFlight.subtract(holders)
    }
}
