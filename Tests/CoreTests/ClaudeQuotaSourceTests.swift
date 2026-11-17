import Foundation
import Testing
@testable import Core

private final class ScriptedAsk: AgentProcessing, @unchecked Sendable {
    private let answer: String?
    private let continuation: AsyncThrowingStream<String, Error>.Continuation

    let lines: AsyncThrowingStream<String, Error>
    let errorLines = AsyncStream<String> { $0.finish() }

    init(answer: String?) {
        self.answer = answer
        var out: AsyncThrowingStream<String, Error>.Continuation!
        lines = AsyncThrowingStream(bufferingPolicy: .unbounded) { out = $0 }
        continuation = out
    }

    var isRunning: Bool { true }
    var exitStatus: Int32 { get async { 0 } }

    func writeLine(_ text: String) {
        guard let id = JSONValue.parse(text)?["request_id"]?.stringValue else { return }
        guard let answer else { return continuation.finish() }
        continuation.yield("""
            {"type":"control_response","response":{"request_id":"\(id)","subtype":"success","response":\(answer)}}
            """)
    }

    func closeStdin() {}
    func terminate() { continuation.finish() }
    func kill() { continuation.finish() }
}

@Suite("Asking Claude Code for its limits")
struct ClaudeQuotaSourceTests {
    private let fetchedAtMs = 1_790_859_223_675.0
    private var fetchedAt: Date { Date(timeIntervalSince1970: fetchedAtMs / 1000) }

    private let withoutLimits = """
        {"session":{"total_cost_usd":0.4},"subscription_type":null,"rate_limits_available":false,\
        "rate_limits":null,"behaviors":null}
        """

    private let withLimits = """
        {"session":{},"subscription_type":"max","rate_limits_available":true,\
        "rate_limits":{"five_hour":{"utilization":71,"resets_at":"2026-10-01T18:49:59Z"}}}
        """

    private func accountFile(fetchedAtMs: Double) -> String {
        let path = TestScratch.unique("claude-account") + ".json"
        let json = """
            {"cachedUsageUtilization":{"fetchedAtMs":\(fetchedAtMs),
              "utilization":{"five_hour":{"utilization":33,"resets_at":"2026-10-01T18:49:59Z"}}}}
            """
        FileManager.default.createFile(atPath: path, contents: Data(json.utf8))
        return path
    }

    private func source(answer: String?, accountPath: String, at now: Date) -> ClaudeCodeQuotaSource {
        ClaudeCodeQuotaSource(
            accountPath: accountPath,
            clock: { now },
            makeProcess: { _ in ScriptedAsk(answer: answer) },
            loginShellReady: {}
        )
    }

    private func readings(_ payload: Data?, at now: Date) throws -> [String: AgentQuota] {
        let read = AgentQuotaAdapters.quotas(fromRateLimitEvent: try #require(payload), at: now)
        return Dictionary(read.map { ($0.window.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func reportedPlan(
        answer: String?,
        identity: String,
        credential: String = "{}",
        environment: [String: String] = [:]
    ) async throws -> String? {
        let path = TestScratch.unique("claude-identity") + ".json"
        FileManager.default.createFile(atPath: path, contents: Data(identity.utf8))
        let credentialPath = TestScratch.unique("claude-credential") + ".json"
        FileManager.default.createFile(atPath: credentialPath, contents: Data(credential.utf8))
        let now = fetchedAt.addingTimeInterval(60)
        let asked = ClaudeCodeQuotaSource(
            executable: "/bin/sh",
            environment: environment,
            accountPath: path,
            credentialPath: credentialPath,
            clock: { now },
            makeProcess: { _ in ScriptedAsk(answer: answer) },
            loginShellReady: {}
        )
        let report = await AgentQuotaSources.report([asked], at: now)
        return try #require(report.accounts.first).plan
    }

    private let ultraIdentity = """
        {"oauthAccount":{"organizationType":"claude_max","organizationRateLimitTier":"default_claude_max_20x"}}
        """

    @Test("the panel names a 20x account Ultra though get_usage only says max")
    func panelFollowsTheIdentity() async throws {
        #expect(try await reportedPlan(answer: withLimits, identity: ultraIdentity) == "Ultra")
    }

    @Test("the panel agrees with the other screens when the identity and the credential disagree")
    func panelPrefersTheIdentityToTheCredential() async throws {
        let stale = """
            {"claudeAiOauth":{"subscriptionType":"max","rateLimitTier":"default_claude_max_5x"}}
            """
        #expect(try await reportedPlan(answer: withLimits, identity: ultraIdentity, credential: stale) == "Ultra")
    }

    @Test("the panel reads the credential when the identity names no tier")
    func panelFallsBackToTheCredential() async throws {
        let twentyTimes = """
            {"claudeAiOauth":{"subscriptionType":"max","rateLimitTier":"default_claude_max_20x"}}
            """
        #expect(try await reportedPlan(answer: withLimits, identity: "{}", credential: twentyTimes) == "Ultra")
    }

    @Test("a Team account stays Team in the panel, whatever tier it carries")
    func panelKeepsTeam() async throws {
        let team = """
            {"oauthAccount":{"organizationType":"claude_team","organizationRateLimitTier":"default_claude_max_20x"}}
            """
        #expect(try await reportedPlan(answer: withLimits, identity: team) == "Team")
    }

    @Test("a session on another config directory is named by its own answer, not by the default files")
    func anotherConfigDirectoryIgnoresTheFiles() async throws {
        let team = #"{"session":{},"subscription_type":"team","rate_limits_available":true,"rate_limits":{}}"#
        let plan = try await reportedPlan(
            answer: team, identity: ultraIdentity, environment: ["CLAUDE_CONFIG_DIR": "/elsewhere"]
        )
        #expect(plan == "Team")
    }

    @Test("an API key in the session's environment names no plan even when the cache answers")
    func apiKeyIgnoresTheFiles() async throws {
        let cached = """
            {"oauthAccount":{"organizationType":"claude_max","organizationRateLimitTier":"default_claude_max_20x"},\
            "cachedUsageUtilization":{"fetchedAtMs":\(fetchedAtMs),\
            "utilization":{"five_hour":{"utilization":33,"resets_at":"2026-10-01T18:49:59Z"}}}}
            """
        let plan = try await reportedPlan(
            answer: nil, identity: cached, environment: ["ANTHROPIC_API_KEY": "fixture"]
        )
        #expect(plan == nil)
    }

    @Test("an empty value in the environment leaves the files in charge")
    func emptyEnvironmentKeepsTheFiles() async throws {
        let plan = try await reportedPlan(
            answer: withLimits,
            identity: ultraIdentity,
            environment: ["ANTHROPIC_API_KEY": "", "CLAUDE_CONFIG_DIR": ""]
        )
        #expect(plan == "Ultra")
    }

    @Test("the panel keeps a plan when the answer comes from the cache, which names none")
    func panelNamesAPlanFromTheCache() async throws {
        let cached = """
            {"oauthAccount":{"organizationType":"claude_max","organizationRateLimitTier":"default_claude_max_20x"},\
            "cachedUsageUtilization":{"fetchedAtMs":\(fetchedAtMs),\
            "utilization":{"five_hour":{"utilization":33,"resets_at":"2026-10-01T18:49:59Z"}}}}
            """
        #expect(try await reportedPlan(answer: nil, identity: cached) == "Ultra")
    }

    @Test("a session with no subscription names no plan, whatever account is on disk")
    func noSubscriptionNamesNoPlan() async throws {
        #expect(try await reportedPlan(answer: withoutLimits, identity: ultraIdentity) == nil)
    }

    @Test("the panel falls back to what get_usage says when no file names a plan")
    func panelFallsBackToTheAnswer() async throws {
        #expect(try await reportedPlan(answer: withLimits, identity: "{}") == "Max")
    }

    @Test("an answer that carries limits is kept, and the cache is left alone")
    func keepsAnAnswerWithLimits() async throws {
        let now = fetchedAt.addingTimeInterval(60)
        let asked = source(answer: withLimits, accountPath: accountFile(fetchedAtMs: fetchedAtMs), at: now)

        let found = try readings(await asked.read(), at: now)

        #expect(found["five_hour"]?.measure == .fraction(0.71))
        #expect(found["five_hour"]?.observedAt == now)
    }

    @Test("an answer with no limits is filled from the cache, keeping what the answer did carry")
    func fallsBackToTheCache() async throws {
        let now = fetchedAt.addingTimeInterval(60)
        let asked = source(answer: withoutLimits, accountPath: accountFile(fetchedAtMs: fetchedAtMs), at: now)
        let payload = try #require(await asked.read())

        let found = try readings(payload, at: now)
        #expect(found["five_hour"]?.measure == .fraction(0.33))
        #expect(found["five_hour"]?.observedAt == fetchedAt)
        #expect(JSONValue.parse(payload)?["session"]?["total_cost_usd"]?.doubleValue == 0.4)
    }

    @Test("with no answer at all the cache stands on its own")
    func answersFromTheCacheAlone() async throws {
        let now = fetchedAt.addingTimeInterval(60)
        let asked = source(answer: nil, accountPath: accountFile(fetchedAtMs: fetchedAtMs), at: now)

        let found = try readings(await asked.read(), at: now)

        #expect(found["five_hour"]?.measure == .fraction(0.33))
        #expect(found["five_hour"]?.observedAt == fetchedAt)
    }

    @Test("a cache out of its hour leaves the empty answer as it was")
    func leavesAStaleCacheAlone() async throws {
        let now = fetchedAt.addingTimeInterval(7200)
        let asked = source(answer: withoutLimits, accountPath: accountFile(fetchedAtMs: fetchedAtMs), at: now)
        let payload = try #require(await asked.read())

        #expect(!ClaudeCodeUsageAdapter.carriesLimits(payload))
        #expect(AgentQuotaAdapters.quotas(fromRateLimitEvent: payload, at: now).isEmpty)
    }

    @Test("with neither an answer nor a cache there is nothing to report")
    func nothingAtAll() async {
        let asked = source(answer: nil, accountPath: "/nonexistent/claude.json", at: fetchedAt)
        #expect(await asked.read() == nil)
    }

    @Test("an executable that is not on PATH is reported as not installed, with its last report")
    func standingNamesWhatIsThere() async {
        let path = accountFile(fetchedAtMs: fetchedAtMs)
        let absent = ClaudeCodeQuotaSource(executable: "unifieddev-no-such-agent", accountPath: path, loginShellReady: {})
        let standing = await absent.standing()

        #expect(!standing.isInstalled)
        #expect(standing.lastReportedAt == fetchedAt)
    }

    @Test("an executable that is on PATH is reported as installed")
    func standingFindsAnInstalledAgent() async {
        let installed = ClaudeCodeQuotaSource(executable: "/bin/sh", accountPath: "/nonexistent/claude.json", loginShellReady: {})
        let standing = await installed.standing()

        #expect(standing.isInstalled)
        #expect(standing.lastReportedAt == nil)
    }

    @Test("Codex is asked only when its own executable is there, and carries no last report")
    func codexStanding() async {
        let absent = await CodexQuotaSource(executable: "unifieddev-no-such-agent", loginShellReady: {}).standing()
        let installed = await CodexQuotaSource(executable: "/bin/sh", loginShellReady: {}).standing()

        #expect(!absent.isInstalled)
        #expect(installed.isInstalled)
        #expect(absent.lastReportedAt == nil)
        #expect(installed.lastReportedAt == nil)
    }
}
