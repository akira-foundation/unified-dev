import Testing
import Foundation
@testable import Core

private let now = Date(timeIntervalSince1970: 1_794_700_000)

private func source(
    replying stdout: String,
    status: Int32 = 0,
    refusal: AntigravityUsageRefusal = AntigravityUsageRefusal(),
    calls: CallCount = CallCount()
) -> AntigravityQuotaSource {
    AntigravityQuotaSource(
        executable: "/bin/agy",
        cwd: "/tmp/scratch",
        bundleIdentifier: "io.akira.unifieddev",
        refusal: refusal,
        run: { _, arguments, _ in
            calls.record(arguments)
            return ShellResult(status: status, stdout: stdout, stderr: "")
        },
        loginShellReady: {}
    )
}

private final class CallCount: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [[String]] = []

    func record(_ arguments: [String]) {
        lock.lock()
        seen.append(arguments)
        lock.unlock()
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return seen
    }
}

@Suite("Antigravity quota")
struct AntigravityQuotaTests {
    @Test("the measured /usage reply reads as two weekly windows, counted as used")
    func measuredReply() throws {
        let line = try #require(JSONValue.parse(Data(AntigravityWire.usageReply.utf8)))
        let quotas = AntigravityQuotaAdapter.quotas(from: line, at: now)
        #expect(quotas.map(\.window.key) == ["gemini-weekly", "3p-weekly"])
        #expect(quotas.map(\.window.label) == ["Gemini", "Claude"])
        #expect(quotas.allSatisfy { $0.window.duration == 604_800 && $0.provider == .antigravity })
        guard case .fraction(let used) = quotas[0].measure else {
            Issue.record("expected a fraction")
            return
        }
        #expect(abs(used - 0.037667989730835) < 0.000_001)
        #expect(quotas[1].measure == .fraction(0))
        #expect(quotas[0].resetsAt == ClaudeCodeUsageAdapter.date(fromISO: "2026-11-21T18:38:24Z"))
        #expect(quotas.map(UsageCatalogue.title(for:)) == ["Gemini", "Claude"])
    }

    @Test("the quota is asked of the /usage command in print mode, which runs no turn")
    func asksTheUsageCommand() async throws {
        let calls = CallCount()
        let payload = try #require(await source(replying: AntigravityWire.usageReply, calls: calls).read())
        #expect(calls.calls == [["-p", "/usage", "--output-format", "json", "--print-timeout", "10s"]])
        #expect(AgentQuotaAdapters.quotas(fromRateLimitEvent: payload, at: now).count == 2)
    }

    @Test("a reply that ran a turn instead of the command is never asked for again")
    func aTurnStopsTheAsking() async {
        let refusal = AntigravityUsageRefusal()
        let calls = CallCount()
        let turn = #"{"status":"SUCCESS","response":"Sure","num_turns":1,"usage":{"total_tokens":120}}"#
        let reading = source(replying: turn, refusal: refusal, calls: calls)

        #expect(await reading.read() == AntigravityQuotaSource.reportsNothing)
        #expect(await reading.read() == AntigravityQuotaSource.reportsNothing)
        #expect(refusal.hasRefused)
        #expect(calls.calls.count == 1)
    }

    @Test("a failed or signed out agy is unanswered rather than read as an empty quota")
    func failureIsUnanswered() async {
        let refusal = AntigravityUsageRefusal()
        #expect(await source(replying: "", status: 1, refusal: refusal).read() == nil)
        #expect(await source(replying: "not json", refusal: refusal).read() == nil)
        let error = #"{"status":"ERROR","num_turns":0,"usage":{"total_tokens":0}}"#
        #expect(await source(replying: error, refusal: refusal).read() == nil)
        #expect(!refusal.hasRefused)
    }

    @Test("a turn is refused whether it ended well, failed, or carried the usage command's name")
    func everyTurnIsRefused() {
        let turns = [
            (#"{"status":"ERROR","num_turns":1}"#, Int32(1)),
            (#"{"status":"SUCCESS","num_turns":0,"usage":{"total_tokens":42}}"#, Int32(0)),
            (#"{"command":{"name":"usage"},"num_turns":1}"#, Int32(0)),
        ]
        for (stdout, status) in turns {
            let reading = AntigravityQuotaSource.reading(ShellResult(status: status, stdout: stdout, stderr: ""))
            #expect(reading == .ranATurn, "\(stdout)")
        }
    }

    @Test("a run that never finished is taken for a turn and not asked again")
    func timeoutIsRefused() async {
        let refusal = AntigravityUsageRefusal()
        let hung = AntigravityQuotaSource(
            executable: "/bin/agy", refusal: refusal, run: { _, _, _ in nil }, loginShellReady: {}
        )
        #expect(await hung.read() == AntigravityQuotaSource.reportsNothing)
        #expect(refusal.hasRefused)
    }

    @Test("a read that overlaps one in flight does not start a second agy")
    func overlappingReadsAreSerialised() {
        let refusal = AntigravityUsageRefusal()
        #expect(refusal.admit())
        #expect(!refusal.admit())
        refusal.finish(refusing: false)
        #expect(refusal.admit())
    }

    @Test("Antigravity's limits show in the panel and its mark is the official one")
    func publishedWithItsMark() throws {
        #expect(AgentKind.antigravity.publishesUsage)
        #expect(UsageLayout.defaultProviderOrder.contains(.antigravity))
        #expect(AgentQuotaSources.all().contains { type(of: $0).provider == .antigravity })
        let mark = try #require(ProviderMark.path(for: .antigravity))
        #expect(mark.commands.count == 8)
        #expect(mark.bounds.minX >= 0 && mark.bounds.maxX <= 136)
        #expect(mark.bounds.width > 70 && mark.bounds.height > 70)
    }

    @Test("a preview with no account of its own does not read the owner's Antigravity login")
    func previewDoesNotReadTheOwnersLogin() async {
        let preview = AntigravityQuotaSource(
            executable: "/bin/sh", bundleIdentifier: PreviewIdentity.bundlePrefix + "ud552", loginShellReady: {}
        )
        #expect(await preview.standing().isInstalled == false)
    }
}
