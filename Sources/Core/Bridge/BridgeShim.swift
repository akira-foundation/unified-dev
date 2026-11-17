import Foundation
import Synchronization

public enum BridgeShim {
    public enum Exit {
        public static let ok: Int32 = 0
        public static let notConfigured: Int32 = 64
        public static let cannotReachUnifiedDev: Int32 = 69
        public static let refused: Int32 = 70
    }

    public static func run(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        shim: String? = CommandLine.arguments.first,
        arguments: [String] = Array(CommandLine.arguments.dropFirst())
    ) async -> Int32 {
        if arguments.first == BitbucketCredentialHelper.command {
            return await BitbucketCredentialHelper.run(arguments: Array(arguments.dropFirst()), environment: environment)
        }
        if let complaint = missingEnvironment(environment) {
            complain(complaint)
            return Exit.notConfigured
        }
        let socketPath = environment[BridgeProtocol.socketVariable] ?? ""
        let token = environment[BridgeProtocol.tokenVariable] ?? ""
        let role = environment[BridgeProtocol.roleVariable] ?? BridgeRole.workspace.rawValue

        let connection: UnixSocketConnection
        do {
            connection = try UnixSocketConnection.connect(to: socketPath)
        } catch {
            complain("bridge could not reach Unified Dev on \(socketPath). Is Unified Dev running?")
            return Exit.cannotReachUnifiedDev
        }

        var iterator = connection.lines.makeAsyncIterator()
        let hello = BridgeHello(token: token, role: role, shim: shim)
        guard let data = try? JSONEncoder().encode(hello) else {
            complain("bridge could not build its hello frame.")
            return Exit.notConfigured
        }
        connection.writeLine(String(decoding: data, as: UTF8.self))

        guard let reply = await iterator.next() else {
            complain("Unified Dev closed the bridge without answering. Quit and reopen Unified Dev.")
            connection.close()
            return Exit.cannotReachUnifiedDev
        }
        let welcome = (reply.data(using: .utf8)).flatMap { try? JSONDecoder().decode(BridgeWelcome.self, from: $0) }
        guard let welcome, welcome.accepted else {
            complain(welcome?.problem ?? "Unified Dev refused the bridge connection.")
            connection.close()
            return Exit.refused
        }

        let shutdownAsked = ShutdownFlag()
        relayStandardInput(to: connection, shutdownAsked: shutdownAsked)
        while let line = await iterator.next() {
            write(line + "\n", to: STDOUT_FILENO)
        }
        connection.close()

        guard shutdownAsked.wasAsked else {
            complain("Unified Dev closed the bridge before answering. Quit and reopen Unified Dev, then try again.")
            return Exit.cannotReachUnifiedDev
        }
        return Exit.ok
    }

    private static func relayStandardInput(
        to connection: UnixSocketConnection,
        shutdownAsked: ShutdownFlag
    ) {
        let input = FileHandle.standardInput
        let buffer = LineBuffer()
        input.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                input.readabilityHandler = nil
                shutdownAsked.ask()
                connection.close()
                return
            }
            for line in buffer.take(data) { connection.writeLine(line) }
        }
    }

    static func missingEnvironment(_ environment: [String: String]) -> String? {
        let missing = [BridgeProtocol.socketVariable, BridgeProtocol.tokenVariable]
            .filter { (environment[$0] ?? "").isEmpty }
        guard !missing.isEmpty else { return nil }

        let absent = missing.count == 2
            ? "Neither was set"
            : "\(missing[0]) was not set"
        return """
            bridge is launched by Unified Dev and takes \(BridgeProtocol.socketVariable) and \
            \(BridgeProtocol.tokenVariable) from its environment. \(absent), so there is \
            nothing to connect to.
            """
    }

    private final class ShutdownFlag: Sendable {
        private let asked = Mutex(false)

        func ask() { asked.withLock { $0 = true } }

        var wasAsked: Bool { asked.withLock { $0 } }
    }

    private static func complain(_ sentence: String) {
        write(sentence + "\n", to: STDERR_FILENO)
    }

    private static func write(_ text: String, to descriptor: Int32) {
        var payload = Array(text.utf8)
        var offset = 0
        while offset < payload.count {
            let written = payload.withUnsafeMutableBufferPointer { bytes in
                Darwin.write(descriptor, bytes.baseAddress! + offset, bytes.count - offset)
            }
            if written < 0 {
                if errno == EINTR { continue }
                return
            }
            offset += written
        }
    }
}
