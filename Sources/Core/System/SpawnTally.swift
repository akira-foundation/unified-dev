import Synchronization

public final class SpawnTally: Sendable {
    private let spawns = Atomic<Int>(0)

    public init() {}

    func add() {
        spawns.add(1, ordering: .relaxed)
    }

    public var count: Int {
        spawns.load(ordering: .relaxed)
    }
}
