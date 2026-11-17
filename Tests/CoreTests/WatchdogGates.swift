import Foundation

final class WatchdogGates: @unchecked Sendable {
    private let lock = NSLock()
    private var requested: [Duration] = []
    private var waiting: [UUID: UnsafeContinuation<Void, Error>] = [:]
    private var watcher: (count: Int, continuation: CheckedContinuation<Void, Never>)?
    private var closed = false

    var asked: [Duration] {
        lock.withLock { requested }
    }

    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, Error>) in
                park(id, asking: duration, continuation)
            }
        } onCancel: {
            wake(id)
        }
    }

    func expireTheOneLeft(afterAsking count: Int) async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                watch(count, continuation)
            }
        } onCancel: {
            expireAll()
        }
    }

    private func park(_ id: UUID, asking duration: Duration, _ continuation: UnsafeContinuation<Void, Error>) {
        lock.lock()
        requested.append(duration)
        let cancelled = Task.isCancelled
        let expired = closed
        if !cancelled, !expired { waiting[id] = continuation }
        lock.unlock()
        if cancelled {
            continuation.resume(throwing: CancellationError())
            return
        }
        if expired {
            continuation.resume()
            return
        }
        settle()
    }

    private func wake(_ id: UUID) {
        lock.lock()
        let parked = waiting.removeValue(forKey: id)
        lock.unlock()
        parked?.resume(throwing: CancellationError())
        settle()
    }

    private func watch(_ count: Int, _ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        let cancelled = Task.isCancelled
        if !cancelled { watcher = (count, continuation) }
        lock.unlock()
        if cancelled {
            continuation.resume()
            expireAll()
        }
        settle()
    }

    private func settle() {
        lock.lock()
        guard let watcher, requested.count >= watcher.count, waiting.count == 1, let id = waiting.keys.first,
              let expired = waiting.removeValue(forKey: id)
        else {
            lock.unlock()
            return
        }
        self.watcher = nil
        lock.unlock()
        expired.resume()
        watcher.continuation.resume()
    }

    private func expireAll() {
        lock.lock()
        let parked = Array(waiting.values)
        let watching = watcher?.continuation
        closed = true
        waiting.removeAll()
        watcher = nil
        lock.unlock()
        for continuation in parked { continuation.resume() }
        watching?.resume()
    }
}
