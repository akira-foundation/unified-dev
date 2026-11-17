import Foundation

@MainActor
public final class CanvasCoalescedCommit {
    private let delay: Duration
    private let sleep: @Sendable (Duration) async -> Void
    private var pending: (() -> Void)?
    private var timer: Task<Void, Never>?

    public static let taskSleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }

    public init(
        delay: Duration = .milliseconds(300),
        sleep: @escaping @Sendable (Duration) async -> Void = CanvasCoalescedCommit.taskSleep
    ) {
        self.delay = delay
        self.sleep = sleep
    }

    public func schedule(_ action: @escaping () -> Void) {
        pending = action
        timer?.cancel()
        timer = Task { [weak self, delay, sleep] in
            await sleep(delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    public func flush() {
        timer?.cancel()
        timer = nil
        let action = pending
        pending = nil
        action?()
    }
}
