import Foundation

public struct ChangesGeneration: Sendable, Equatable {
    public private(set) var value = 0
    private var last: ChangesSnapshot?

    public init() {}

    public mutating func record(_ snapshot: ChangesSnapshot) -> Bool {
        guard snapshot != last else { return false }
        last = snapshot
        value &+= 1
        return true
    }
}
