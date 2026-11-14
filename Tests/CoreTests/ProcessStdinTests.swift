import Foundation
import Testing
@testable import Core

@Suite("Writing to a process that is not there")
struct ProcessStdinTests {
    @Test("a line written before the child is launched is refused rather than queued", .timeLimit(.minutes(1)))
    func aWriteBeforeTheLaunchIsRefused() async throws {
        let process = StreamingProcess(executable: "/bin/cat", arguments: [])

        process.writeLine("before-the-launch")

        let lines = process.lines
        process.writeLine("after-the-launch")
        process.closeStdin()

        var seen: [String] = []
        for try await line in lines { seen.append(line) }

        #expect(seen == ["after-the-launch"])
        #expect(await process.exitStatus == 0)
    }

    @Test("a process that has already exited is not written to", .timeLimit(.minutes(1)))
    func aWriteAfterTheExitIsRefused() async throws {
        let process = StreamingProcess(executable: "/bin/echo", arguments: ["done"])

        var seen: [String] = []
        for try await line in process.lines { seen.append(line) }
        #expect(seen == ["done"])
        #expect(await process.exitStatus == 0)

        for _ in 0..<200 { process.writeLine("into the void") }
    }

    @Test("a write to a pipe nobody is reading fails the write rather than the process", .timeLimit(.minutes(1)))
    func aPipeWithNoReaderFailsTheWriteRatherThanTheProcess() throws {
        let pipe = Pipe()
        _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try pipe.fileHandleForReading.close()

        #expect(throws: (any Error).self) {
            try pipe.fileHandleForWriting.write(contentsOf: Data("nobody is reading".utf8))
        }
        try? pipe.fileHandleForWriting.close()
    }

    @Test("stdin closing under a write does not fault", .timeLimit(.minutes(2)))
    func aCloseDoesNotLandUnderAWrite() async throws {
        for _ in 0..<40 {
            let process = StreamingProcess(executable: "/bin/cat", arguments: [])
            _ = process.lines

            await withTaskGroup(of: Void.self) { group in
                for index in 0..<16 {
                    group.addTask { process.writeLine("line-\(index)") }
                }
                group.addTask { process.closeStdin() }
                group.addTask { process.terminate() }
            }

            _ = await process.exitStatus
        }
    }

    @Test("the Codex handshake goes to a process that has been launched", .timeLimit(.minutes(1)))
    func theHandshakeIsWrittenAfterTheLaunch() async throws {
        let process = LaunchOrderProcess()
        let client = CodexClient(
            configuration: CodexClient.Configuration(cwd: "/tmp"),
            makeProcess: { _ in process }
        )

        try await client.start()
        await client.stop()

        #expect(process.wroteBeforeTheLaunch == false)
        #expect(process.linesWereClaimed)
    }

    @Test("a Codex source whose process says nothing answers nothing", .timeLimit(.minutes(1)))
    func aSilentCodexProcessFailsAsASource() async {
        let source = CodexQuotaSource(makeProcess: { _ in DeadProcess() }, loginShellReady: {})

        let payload = await source.read()
        #expect(payload == nil)

        let quotas = await AgentQuotaSources.readAll([source] as [any AgentQuotaSource])
        #expect(quotas.isEmpty)
    }
}

private final class LaunchOrderProcess: AgentProcessing, @unchecked Sendable {
    private let lock = NSLock()
    private var launched = false
    private var firstWriteSawTheLaunch: Bool?

    private let stdout: AsyncThrowingStream<String, Error>
    private let stdoutContinuation: AsyncThrowingStream<String, Error>.Continuation
    private let stderr: AsyncStream<String>
    private let stderrContinuation: AsyncStream<String>.Continuation

    init() {
        (stdout, stdoutContinuation) = AsyncThrowingStream.makeStream(
            of: String.self, throwing: Error.self, bufferingPolicy: .unbounded
        )
        (stderr, stderrContinuation) = AsyncStream.makeStream(
            of: String.self, bufferingPolicy: .unbounded
        )
    }

    var wroteBeforeTheLaunch: Bool {
        lock.lock(); defer { lock.unlock() }
        return firstWriteSawTheLaunch == false
    }

    var linesWereClaimed: Bool {
        lock.lock(); defer { lock.unlock() }
        return launched
    }

    var lines: AsyncThrowingStream<String, Error> {
        lock.lock(); launched = true; lock.unlock()
        return stdout
    }

    var errorLines: AsyncStream<String> { stderr }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return launched
    }

    var exitStatus: Int32 { get async { 0 } }

    func writeLine(_ text: String) {
        lock.lock()
        if firstWriteSawTheLaunch == nil { firstWriteSawTheLaunch = launched }
        lock.unlock()

        guard let json = JSONValue.parse(text), let id = json["id"] else { return }
        stdoutContinuation.yield("{\"id\":\(id.compactJSON),\"result\":{}}")
    }

    func closeStdin() {}

    func terminate() {
        stdoutContinuation.finish()
        stderrContinuation.finish()
    }

    func kill() { terminate() }
}

private final class DeadProcess: AgentProcessing, @unchecked Sendable {
    let lines: AsyncThrowingStream<String, Error>
    let errorLines: AsyncStream<String>

    init() {
        let (stdout, out) = AsyncThrowingStream.makeStream(
            of: String.self, throwing: Error.self, bufferingPolicy: .unbounded
        )
        let (stderr, err) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .unbounded)
        lines = stdout
        errorLines = stderr
        out.finish()
        err.finish()
    }

    var isRunning: Bool { false }
    var exitStatus: Int32 { get async { 1 } }

    func writeLine(_ text: String) {}
    func closeStdin() {}
    func terminate() {}
    func kill() {}
}
