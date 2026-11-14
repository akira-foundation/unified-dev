import Foundation
import Synchronization
import Testing
@testable import Core

final class QuotaReadinessRecorder: Sendable {
    let installs = TestScratch.unique("agent-installed-by-the-login-shell")
    private let answered = Mutex(0)
    private let seenAtSpawn = Mutex<[Int]>([])

    var wait: @Sendable () async -> Void {
        { [self] in
            await Task.yield()
            FileManager.default.createFile(
                atPath: installs, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755]
            )
            answered.withLock { $0 += 1 }
        }
    }

    var factory: @Sendable (AgentLaunch) -> any AgentProcessing {
        { [self] _ in
            let count = answered.withLock { $0 }
            seenAtSpawn.withLock { $0.append(count) }
            return SilentProcess()
        }
    }

    var answers: Int { answered.withLock { $0 } }

    var spawns: [Int] { seenAtSpawn.withLock { $0 } }
}

@Suite("The quota sources wait for the login shell they are handed", .scratchDirectory)
struct QuotaSourceReadinessTests {
    enum Provider: String, CaseIterable, Sendable {
        case claudeCode, codex

        func source(_ readiness: QuotaReadinessRecorder) -> any AgentQuotaSource {
            switch self {
            case .claudeCode:
                ClaudeCodeQuotaSource(
                    executable: readiness.installs, environment: [:], accountPath: "/nonexistent/claude.json",
                    makeProcess: readiness.factory, loginShellReady: readiness.wait
                )
            case .codex:
                CodexQuotaSource(
                    executable: readiness.installs, environment: [:],
                    makeProcess: readiness.factory, loginShellReady: readiness.wait
                )
            }
        }
    }

    @Test("a read asks the agent only once the readiness it was handed has answered", arguments: Provider.allCases)
    func readWaits(provider: Provider) async {
        let readiness = QuotaReadinessRecorder()

        _ = await provider.source(readiness).read()

        #expect(readiness.spawns == [1])
    }

    @Test("the standing looks for the agent only once the readiness it was handed has answered", arguments: Provider.allCases)
    func standingWaits(provider: Provider) async {
        let readiness = QuotaReadinessRecorder()

        let standing = await provider.source(readiness).standing()

        #expect(readiness.answers == 1)
        #expect(standing.isInstalled)
        #expect(readiness.spawns.isEmpty)
    }
}
