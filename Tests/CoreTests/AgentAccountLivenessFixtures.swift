import Foundation
import Synchronization
@testable import Core

final class ScriptedStatus: AgentProcessing, @unchecked Sendable {
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private let terminations = Mutex(0)
    private let status: Int32
    private let exitWaitsForTermination: Bool
    private let exit = Mutex<(isTerminated: Bool, waiters: [CheckedContinuation<Int32, Never>])>((false, []))

    let lines: AsyncThrowingStream<String, Error>
    let errorLines: AsyncStream<String>

    init(
        printing output: [String],
        failing errors: [String] = [],
        status: Int32 = 0,
        finishing: Bool = true,
        exitWaitsForTermination: Bool = false
    ) {
        var out: AsyncThrowingStream<String, Error>.Continuation!
        lines = AsyncThrowingStream(bufferingPolicy: .unbounded) { out = $0 }
        continuation = out
        self.status = status
        self.exitWaitsForTermination = exitWaitsForTermination
        errorLines = AsyncStream { stream in
            for line in errors { stream.yield(line) }
            stream.finish()
        }
        for line in output { continuation.yield(line) }
        if finishing { continuation.finish() }
    }

    var terminationCount: Int { terminations.withLock { $0 } }
    var isRunning: Bool { true }
    var exitStatus: Int32 {
        get async {
            guard exitWaitsForTermination else { return status }
            return await withCheckedContinuation { waiter in
                let alreadyTerminated = exit.withLock { state -> Bool in
                    if state.isTerminated { return true }
                    state.waiters.append(waiter)
                    return false
                }
                if alreadyTerminated { waiter.resume(returning: status) }
            }
        }
    }

    func writeLine(_ text: String) {}
    func closeStdin() {}
    func terminate() {
        terminations.withLock { $0 += 1 }
        continuation.finish()
        let waiting = exit.withLock { state -> [CheckedContinuation<Int32, Never>] in
            state.isTerminated = true
            defer { state.waiters = [] }
            return state.waiters
        }
        for waiter in waiting { waiter.resume(returning: status) }
    }
    func kill() { continuation.finish() }
}

final class Launches: @unchecked Sendable {
    private let seen = Mutex<[AgentLaunch]>([])

    var all: [AgentLaunch] { seen.withLock { $0 } }

    func record(_ launch: AgentLaunch) { seen.withLock { $0.append(launch) } }
}
