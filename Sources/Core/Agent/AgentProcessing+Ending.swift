import Foundation
import Synchronization

extension AgentProcessing {
    func end(within grace: Duration) async {
        terminate()
        await killUnlessExited(within: grace)
    }

    func killUnlessExited(within grace: Duration) async {
        guard await !exits(within: grace) else { return }
        kill()
        _ = await exits(within: grace)
    }

    func exits(within deadline: Duration) async -> Bool {
        let race = ExitRace()
        return await withCheckedContinuation { continuation in
            race.arm(continuation)
            Task { _ = await exitStatus; race.settle(true) }
            Task { try? await Task.sleep(for: deadline); race.settle(false) }
        }
    }
}

private final class ExitRace: Sendable {
    private let waiting = Mutex<CheckedContinuation<Bool, Never>?>(nil)

    func arm(_ continuation: CheckedContinuation<Bool, Never>) {
        waiting.withLock { $0 = continuation }
    }

    func settle(_ exited: Bool) {
        let continuation = waiting.withLock { held -> CheckedContinuation<Bool, Never>? in
            defer { held = nil }
            return held
        }
        continuation?.resume(returning: exited)
    }
}
