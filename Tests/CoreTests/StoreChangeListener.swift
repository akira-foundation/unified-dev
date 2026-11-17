import Testing
import Foundation
import Synchronization
@testable import Core

final class StoreChangeListener: Sendable {
    private struct State {
        var batches: [Set<StoreDomain>] = []
        var taken = 0
        var task: Task<Void, Never>?
    }

    private let state = Mutex(State())

    init(
        _ store: Store,
        interest: Set<StoreDomain> = Set(StoreDomain.allCases),
        handlerDelay: Duration? = nil
    ) async throws {
        let hub = store.changeHub
        let before = hub.subscriberCount
        let feed = store.changes(of: interest)
        let task = Task { [self] in
            for await batch in feed {
                state.withLock { $0.batches.append(batch) }
                if let handlerDelay { try? await Task.sleep(for: handlerDelay) }
            }
        }
        state.withLock { $0.task = task }
        await waitUntil("the listener has subscribed") { hub.subscriberCount > before }
    }

    var batches: [Set<StoreDomain>] {
        state.withLock { $0.batches }
    }

    func nextBatch(within timeout: Duration = .seconds(3)) async -> Set<StoreDomain>? {
        let seen = state.withLock { $0.taken }
        await waitUntil("a batch arrives", within: timeout) { self.batches.count > seen }
        return state.withLock { state in
            guard state.batches.count > seen else { return nil }
            state.taken = seen + 1
            return state.batches[seen]
        }
    }

    func nothingFurther(within window: Duration = .milliseconds(250)) async -> Bool {
        let before = batches.count
        try? await Task.sleep(for: window)
        return batches.count == before
    }

    func hasSettled(for window: Duration) async -> Bool {
        await nothingFurther(within: window)
    }

    func stop() {
        state.withLock { $0.task }?.cancel()
    }

    deinit {
        state.withLock { $0.task }?.cancel()
    }
}
