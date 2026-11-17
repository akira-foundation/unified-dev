import Testing
import Foundation
import Synchronization
@testable import Core

final class LaunchLog: Sendable {
    private let launches = Mutex<[AgentLaunch]>([])

    func record(_ launch: AgentLaunch) { launches.withLock { $0.append(launch) } }

    var all: [AgentLaunch] { launches.withLock { $0 } }

    var first: AgentLaunch? { all.first }

    var factory: @Sendable (AgentLaunch) -> any AgentProcessing {
        { launch in
            self.record(launch)
            return SilentProcess()
        }
    }
}

final class SilentProcess: AgentProcessing, @unchecked Sendable {
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

enum LaunchAccountFixture {
    static let hostAuth = [
        "CLAUDECODE",
        "CLAUDE_CODE_ENTRYPOINT",
        "CLAUDE_CODE_SDK_HAS_HOST_AUTH_REFRESH",
        "CLAUDE_CODE_SDK_HAS_OAUTH_REFRESH",
        "CLAUDE_CODE_SESSION_ACCESS_TOKEN",
        "CLAUDE_CODE_HOST_AUTH_ENV_VAR",
        "CLAUDE_CODE_HOST_CREDS_FILE",
        "CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST",
        "CLAUDE_CODE_MESSAGING_SOCKET",
        "CLAUDE_CODE_MESSAGING_TOKEN",
        "CLAUDE_CODE_EXECPATH",
    ]

    static let credentials = [
        "ANTHROPIC_API_KEY",
        "OPENAI_API_KEY",
        "ANTHROPIC_BASE_URL",
        "CLAUDE_CODE_USER_EMAIL",
        "CLAUDE_CODE_ACCOUNT_UUID",
        "CLAUDE_CODE_ORGANIZATION_UUID",
    ]

    static let tokens = [
        "CLAUDE_CODE_OAUTH_TOKEN",
        "CLAUDE_CODE_OAUTH_REFRESH_TOKEN",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_IDENTITY_TOKEN",
        "CLAUDE_TRUSTED_DEVICE_TOKEN",
        "CLAUDE_SECURESTORAGE_CONFIG_DIR",
        "ANTHROPIC_CONFIG_DIR",
        "XAI_API_KEY",
        "GROK_API_KEY",
        "CODEX_API_KEY",
        "CODEX_ACCESS_TOKEN",
        "CODEX_AUTH",
    ]

    static var inherited: [String: String] {
        var variables = Dictionary(uniqueKeysWithValues: (hostAuth + credentials + tokens).map { ($0, "inherited") })
        variables["PATH"] = "/usr/bin"
        return variables
    }

    static let workClaude = AgentAccountHome(
        provider: .claudeCode,
        id: AgentAccountID("work"),
        directory: URL(filePath: "/support/AgentAccounts/claudeCode/work", directoryHint: .isDirectory),
        isDefault: false
    )
    static let workCodex = AgentAccountHome(
        provider: .codex,
        id: AgentAccountID("work"),
        directory: URL(filePath: "/support/AgentAccounts/codex/work", directoryHint: .isDirectory),
        isDefault: false
    )
    static let workGrok = AgentAccountHome(
        provider: .grok,
        id: AgentAccountID("work"),
        directory: URL(filePath: "/support/AgentAccounts/grok/work", directoryHint: .isDirectory),
        isDefault: false
    )

    static func expectClean(
        _ environment: [String: String], sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for name in hostAuth + credentials + tokens {
            #expect(environment[name] == nil, "\(name) survived", sourceLocation: sourceLocation)
        }
        #expect(environment["PATH"] == "/usr/bin", sourceLocation: sourceLocation)
    }

    static func session(kind: AgentKind) async throws -> (Store, Session) {
        let store = try makeTestStore("launch-account-\(kind.rawValue)")
        let repo = try await store.upsert(Repo(name: "r", path: "/tmp/r-\(UUID().uuidString)"))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "w", branch: "b", path: "/tmp/w", baseBranch: "main"
        ))
        let made = try await store.upsert(Session(workspaceID: workspace.id, model: "opus", agentKind: kind))
        return (store, made)
    }
}

final class SeenEnvironment: Sendable {
    let value = Mutex<[String: String]>([:])
}
