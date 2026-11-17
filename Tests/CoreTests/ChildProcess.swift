import Foundation
import Testing

final class ChildProcess: @unchecked Sendable {
    static let exitLimit = Duration.seconds(20)

    let process: Process
    private let exited = DispatchSemaphore(value: 0)
    private let exits: AsyncStream<Void>

    init(_ process: Process) throws {
        self.process = process
        let (exits, finished) = AsyncStream<Void>.makeStream()
        self.exits = exits
        process.terminationHandler = { [exited] _ in
            exited.signal()
            finished.finish()
        }
        try process.run()
    }

    convenience init(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        try self.init(process)
    }

    @discardableResult
    func waitForExit(within limit: Duration = exitLimit, sourceLocation: SourceLocation = #_sourceLocation) -> Bool {
        let seconds = Double(limit.components.seconds) + Double(limit.components.attoseconds) / 1e18
        guard exited.wait(timeout: .now() + seconds) == .success else {
            give(up: limit, sourceLocation)
            return false
        }
        exited.signal()
        return true
    }

    func stop(within limit: Duration = exitLimit, sourceLocation: SourceLocation = #_sourceLocation) async {
        process.terminate()
        await awaitExit(within: limit, sourceLocation: sourceLocation)
    }

    func awaitExit(within limit: Duration = exitLimit, sourceLocation: SourceLocation = #_sourceLocation) async {
        let hasExited = await withTaskGroup(of: Bool.self) { group in
            group.addTask { [exits] in
                for await _ in exits {}
                return !Task.isCancelled
            }
            group.addTask {
                try? await Task.sleep(for: limit)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        if !hasExited { give(up: limit, sourceLocation) }
    }

    private func give(up limit: Duration, _ sourceLocation: SourceLocation) {
        Issue.record("process \(process.processIdentifier) had not exited after \(limit)", sourceLocation: sourceLocation)
        kill(process.processIdentifier, SIGKILL)
    }
}
