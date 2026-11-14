import Foundation
import Synchronization

public enum LoginShellPath {
    public static let timeout: Duration = .seconds(5)

    public static let switchVariable = "UD_LOGIN_SHELL_PATH"

    public static let readiness: @Sendable () async -> Void = { await ready() }

    static let sentinel = "/usr/bin/printf '\\0'; /usr/bin/env -0"

    private static let probe = Mutex<Task<Void, Never>?>(nil)

    private static let source = Mutex<(@Sendable () async -> [String])?>(nil)

    public static func begin() {
        probe.withLock { existing in
            guard existing == nil else { return }
            let installed = source.withLock { $0 }
            existing = Task { await adopt(installed) }
        }
    }

    private static func adopt(_ installed: (@Sendable () async -> [String])?) async {
        guard let installed else {
            Shell.adoptLoginShellPath(await discover())
            return
        }
        Shell.adoptLoginShellPath(await installed())
    }

    public static func ready() async {
        await probe.withLock { $0 }?.value
    }

    static func install(_ discovery: @escaping @Sendable () async -> [String]) {
        source.withLock { $0 = discovery }
        probe.withLock { $0 = nil }
    }

    static func forget() {
        source.withLock { $0 = nil }
        probe.withLock { $0 = nil }
    }

    static func discover(
        shell: String = LoginShell.path(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        overlay: [String: String] = [:],
        timeout: Duration = LoginShellPath.timeout
    ) async -> [String] {
        guard environment[switchVariable] != "0" else { return [] }
        let result = try? await Shell.runBytes(
            shell, ["-i", "-l", "-c", sentinel], env: overlay, timeout: timeout
        )
        guard let result, result.status == 0 else { return [] }
        return directories(inEnvironmentDump: result.stdout)
    }

    static func directories(inEnvironmentDump data: Data) -> [String] {
        for record in data.split(separator: 0, omittingEmptySubsequences: false).dropFirst() {
            let text = String(decoding: record, as: UTF8.self)
            guard text.hasPrefix("PATH=") else { continue }
            return String(text.dropFirst("PATH=".count)).components(separatedBy: ":")
        }
        return []
    }

    static func merge(discovered: [String], inherited: [String], guessed: [String]) -> [String] {
        var seen = Set<String>()
        return (discovered + inherited + guessed)
            .filter { $0.hasPrefix("/") }
            .filter { seen.insert($0).inserted }
    }
}
