import Testing
import Foundation
@testable import Core

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func makeIDToken(claims: [String: Any], signature: String = "not-a-real-signature") -> String {
    let header = base64URL(Data(#"{"alg":"RS256","typ":"JWT"}"#.utf8))
    let payload = base64URL(try! JSONSerialization.data(withJSONObject: claims))
    return "\(header).\(payload).\(base64URL(Data(signature.utf8)))"
}

private func json(_ object: [String: Any]) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
}

private func claudeAccount() -> [String: Any] { [
    "oauthAccount": [
        "emailAddress": "ada@example.com",
        "displayName": "Ada Lovelace",
        "organizationName": "Example Labs",
        "organizationType": "claude_max",
        "organizationRateLimitTier": "default_claude_max_20x",
        "organizationRole": "admin",
    ],
] }

private func codexClaims() -> [String: Any] { [
    "email": "ada@example.com",
    "name": "Ada Lovelace",
    "exp": 4_102_444_800,
    "https://api.openai.com/auth": [
        "chatgpt_plan_type": "prolite",
        "chatgpt_account_id": "acct-fixture",
    ],
] }

private func codexAuthFile(
    claims: [String: Any]? = nil,
    authMode: String = "chatgpt",
    apiKey: Any = NSNull(),
    accessToken: String = "access-token-fixture",
    refreshToken: String = "refresh-token-fixture"
) -> Data {
    let claims = claims ?? codexClaims()
    return json([
        "auth_mode": authMode,
        "OPENAI_API_KEY": apiKey,
        "last_refresh": "2026-08-18T09:00:00Z",
        "tokens": [
            "access_token": accessToken,
            "refresh_token": refreshToken,
            "id_token": makeIDToken(claims: claims),
            "account_id": "acct-fixture",
        ],
    ])
}

@Suite("AgentCatalog", .tags(.agentProtocol), .scratchDirectory)
struct AgentCatalogTests {
    @Test("describes every agent kind")
    func describesKinds() {
        #expect(AgentKind.allCases.map(\.label) == ["Claude Code", "Codex", "Grok", "Antigravity", "Cursor", "OpenCode"])
        #expect(AgentKind.allCases.map(\.executableName) == ["claude", "codex", "grok", "agy", "cursor-agent", "opencode"])
        #expect(AgentKind.allCases.filter(\.canRunWorkspaces) == [.claudeCode, .codex, .grok, .antigravity])
        #expect(AgentKind.runnableSentence == "Claude Code, Codex, Grok and Antigravity")
        #expect(AgentKind.claudeCode.loginCommand == "claude auth login")
        #expect(AgentKind.codex.loginCommand == "codex login")
        #expect(AgentKind.grok.loginCommand == "grok login")
        #expect(AgentKind.antigravity.loginCommand == "agy acp --login")
        #expect(AgentKind.codex.configPath.hasSuffix("/.codex/config.toml"))
        #expect(AgentKind.claudeCode.configPath.hasSuffix("/.claude/settings.json"))
        #expect(AgentKind.grok.configPath.hasSuffix("/.grok/config.toml"))
    }

    @Test("reads a Claude account into five ordered details")
    func readsClaudeAccount() {
        let details = AgentCatalog.claudeDetails(
            accountJSON: json(claudeAccount()),
            version: "2.1.234",
            apiKeyIsSet: false
        )

        #expect(details.map(\.label) == ["Version", "Provider", "Login method", "Organization", "Email"])
        #expect(details.map(\.value) == [
            "2.1.234", "Anthropic", "Claude Ultra account", "Example Labs", "ada@example.com",
        ])
    }

    @Test("reports unknown rather than dropping fields the Claude account lacks")
    func fillsMissingClaudeFields() {
        let details = AgentCatalog.claudeDetails(
            accountJSON: json(["oauthAccount": ["emailAddress": "ada@example.com"]]),
            version: nil,
            apiKeyIsSet: false
        )

        #expect(details.count == 5)
        #expect(details[0].value == "unknown")
        #expect(details[2].value == "unknown")
        #expect(details[3].value == "unknown")
        #expect(details[4].value == "ada@example.com")
    }

    @Test("returns no Claude details when oauthAccount is missing")
    func handlesMissingClaudeAccount() {
        let withoutAccount = json(["numStartups": 42, "theme": "dark"])
        #expect(AgentCatalog.claudeDetails(accountJSON: withoutAccount, version: "2.1.234", apiKeyIsSet: false).isEmpty)
        #expect(AgentCatalog.claudeDetails(accountJSON: nil, version: "2.1.234", apiKeyIsSet: false).isEmpty)
        #expect(AgentCatalog.claudeDetails(accountJSON: Data("not json".utf8), version: nil, apiKeyIsSet: false).isEmpty)
    }

    @Test("lets an API key in the environment win over the stored Claude account")
    func apiKeyBeatsOAuthAccount() {
        let details = AgentCatalog.claudeDetails(
            accountJSON: json(claudeAccount()),
            version: "2.1.234",
            apiKeyIsSet: true
        )

        #expect(details.map(\.label) == ["Version", "Provider", "Login method", "Organization", "Email"])
        #expect(details[1].value == "Anthropic API key")
        #expect(details[2].value == "API key (ANTHROPIC_API_KEY set)")
    }

    @Test("reads Codex claims into ordered details")
    func readsCodexAccount() {
        let details = AgentCatalog.codexDetails(authJSON: codexAuthFile())

        #expect(details.map(\.label) == ["Provider", "Plan", "Auth", "Account"])
        #expect(details.map(\.value) == ["OpenAI", "Prolite", "ChatGPT login", "ada@example.com"])
    }

    @Test("the Codex file never judges the session, whatever its token says")
    func theCodexFileNeverJudgesTheSession() {
        var expired = codexClaims()
        expired["exp"] = 1_600_000_000

        let stale = AgentCatalog.codexDetails(authJSON: codexAuthFile(claims: expired))
        let staleWithoutRefresh = AgentCatalog.codexDetails(
            authJSON: codexAuthFile(claims: expired, refreshToken: "")
        )
        let fresh = AgentCatalog.codexDetails(authJSON: codexAuthFile())

        for details in [stale, staleWithoutRefresh, fresh] {
            #expect(details.map(\.label) == ["Provider", "Plan", "Auth", "Account"])
            #expect(details[3].value == "ada@example.com")
        }
    }

    @Test("keeps a token without an expiry claim usable")
    func toleratesMissingExpiry() {
        var claims = codexClaims()
        claims.removeValue(forKey: "exp")

        let details = AgentCatalog.codexDetails(authJSON: codexAuthFile(claims: claims))

        #expect(details.map(\.label) == ["Provider", "Plan", "Auth", "Account"])
    }

    @Test("returns nothing for a malformed Codex token instead of throwing")
    func survivesMalformedTokens() {
        #expect(AgentCatalog.decodeCodexIDToken("only-one-segment") == nil)
        #expect(AgentCatalog.decodeCodexIDToken("header.!!!not base64!!!.signature") == nil)
        #expect(AgentCatalog.decodeCodexIDToken("header.\(base64URL(Data("plain text".utf8))).sig") == nil)
        #expect(AgentCatalog.decodeCodexIDToken("header.\(base64URL(json(["sub": "x"]))).sig") == nil)
        #expect(AgentCatalog.decodeCodexIDToken("") == nil)

        for token in ["only-one-segment", "a.###.c", ""] {
            let file = json(["auth_mode": "chatgpt", "tokens": ["id_token": token]])
            #expect(AgentCatalog.codexDetails(authJSON: file).isEmpty)
        }
        #expect(AgentCatalog.codexDetails(authJSON: nil).isEmpty)
        #expect(AgentCatalog.codexDetails(authJSON: Data("{ broken".utf8)).isEmpty)
    }

    @Test("describes Codex in API key mode without a token")
    func readsCodexApiKeyMode() {
        let file = json([
            "auth_mode": "apikey",
            "OPENAI_API_KEY": "sk-proj-FAKEKEYVALUE0123456789",
            "tokens": NSNull(),
        ])

        let details = AgentCatalog.codexDetails(authJSON: file)

        #expect(details.map(\.label) == ["Provider", "Auth", "API key"])
        #expect(details.map(\.value) == ["OpenAI", "API key", "Set"])
    }

    @Test("reads a Grok account into ordered details and never the key")
    func readsGrokAccount() {
        let details = AgentCatalog.grokDetails(
            authJSON: json([
                "https://auth.x.ai::client": [
                    "auth_mode": "oauth",
                    "email": "ada@example.com",
                    "first_name": "Ada",
                    "key": "xai-secret-must-never-appear",
                    "refresh_token": "refresh-secret-must-never-appear",
                ],
            ]),
            version: "1.0.24",
            apiKeyIsSet: false
        )

        #expect(details.map(\.label) == ["Version", "Provider", "Login method", "Account"])
        #expect(details.map(\.value) == ["1.0.24", "xAI", "Grok login", "ada@example.com"])
        #expect(!details.contains { $0.value.contains("xai-secret") })
        #expect(!details.contains { $0.value.contains("refresh-secret") })
    }

    @Test("a Grok login past its expiry is not called expired while a refresh token is there")
    func anOldGrokLoginWithARefreshIsNotCalledExpired() {
        let details = AgentCatalog.grokDetails(
            authJSON: json([
                "https://auth.x.ai::client": [
                    "auth_mode": "oauth",
                    "email": "ada@example.com",
                    "expires_at": "2020-01-01T00:00:00Z",
                    "refresh_token": "refresh-secret-must-never-appear",
                ],
            ]),
            version: "1.0.24",
            apiKeyIsSet: false
        )

        #expect(details.map(\.label) == ["Version", "Provider", "Login method", "Account"])
        #expect(!details.contains { $0.value.contains("refresh-secret") })
    }

    @Test("a Grok login with nothing left to refresh with asks for a new sign-in")
    func anExpiredGrokLoginWithNoRefreshAsksForOne() {
        let details = AgentCatalog.grokDetails(
            authJSON: json([
                "https://auth.x.ai::client": [
                    "auth_mode": "oauth",
                    "email": "ada@example.com",
                    "expires_at": "2020-01-01T00:00:00Z",
                ],
            ]),
            version: "1.0.24",
            apiKeyIsSet: false
        )

        #expect(details.map(\.label) == ["Version", "Provider", "Login method", "Account", "Session"])
        #expect(details.last?.value.contains("Expired") == true)
    }

    @Test("a Grok file with two sign-ins is read by sorted issuer, not by whatever came first")
    func twoGrokSignInsAreReadBySortedIssuer() {
        let file = json([
            "https://auth.x.ai::zulu": [
                "auth_mode": "oauth",
                "email": "zoe@example.com",
                "expires_at": "2020-01-01T00:00:00Z",
            ],
            "https://auth.x.ai::alpha": [
                "auth_mode": "oauth",
                "email": "ada@example.com",
                "expires_at": "2020-01-01T00:00:00Z",
                "refresh_token": "refresh-secret-must-never-appear",
            ],
        ])

        for _ in 0..<8 {
            let details = AgentCatalog.grokDetails(authJSON: file, version: "1.0.24", apiKeyIsSet: false)
            #expect(details.map(\.label) == ["Version", "Provider", "Login method", "Account"])
            #expect(details.last?.value == "ada@example.com")
        }
    }

    @Test("an XAI_API_KEY with no auth file still shows as connected")
    func grokAPIKeyWithoutFile() {
        let details = AgentCatalog.grokDetails(authJSON: nil, version: "1.0.24", apiKeyIsSet: true)
        #expect(details.map(\.label) == ["Version", "Provider", "Login method", "Account"])
        #expect(details.map(\.value) == ["1.0.24", "xAI API key", "API key (XAI_API_KEY set)", "unknown"])
    }

    @Test("parses both observed version formats and falls back on anything else")
    func parsesVersions() {
        #expect(AgentCatalog.parseVersion("2.1.234 (Claude Code)") == "2.1.234")
        #expect(AgentCatalog.parseVersion("codex-cli 0.147.0") == "0.147.0")
        #expect(AgentCatalog.parseVersion("grok 1.0.24 (68e414c661e3) [alpha]") == "1.0.24")
        #expect(AgentCatalog.parseVersion("v1.2.3") == "1.2.3")
        #expect(AgentCatalog.parseVersion("  0.9.0\nextra noise\n") == "0.9.0")
        #expect(AgentCatalog.parseVersion("built from source") == "built from source")
        #expect(AgentCatalog.parseVersion("   ") == nil)
        #expect(AgentCatalog.parseVersion("") == nil)
    }

    @Test("never puts a credential into a detail")
    func neverLeaksSecrets() {
        let accessToken = "sk-codex-access-QWERTYUIOPASDFGHJKLZXCVBNM1234567890"
        let refreshToken = "sk-codex-refresh-MNBVCXZLKJHGFDSAPOIUYTREWQ0987654321"
        let openAIKey = "sk-proj-OPENAIKEY-abcdefghijklmnopqrstuvwxyz123456"
        let anthropicToken = "sk-ant-oat01-ZYXWVUTSRQPONMLKJIHGFEDCBA9876543210abcdef"

        var claudeFile = claudeAccount()
        claudeFile["oauthToken"] = anthropicToken
        claudeFile["primaryApiKey"] = anthropicToken

        let idToken = makeIDToken(claims: codexClaims(), signature: "signature-\(refreshToken)")
        let codexFile = json([
            "auth_mode": "chatgpt",
            "OPENAI_API_KEY": openAIKey,
            "tokens": [
                "access_token": accessToken,
                "refresh_token": refreshToken,
                "id_token": idToken,
                "account_id": "acct-fixture",
            ],
        ])

        let grokKey = "xai-secret-GROKKEY-abcdefghijklmnopqrstuvwxyz123456"
        let grokRefresh = "grok-refresh-MNBVCXZLKJHGFDSAPOIUYTREWQ0987654321"
        let grokFile = json([
            "https://auth.x.ai::client": [
                "auth_mode": "oauth",
                "email": "ada@example.com",
                "key": grokKey,
                "refresh_token": grokRefresh,
            ],
        ])

        let details = AgentCatalog.claudeDetails(
            accountJSON: json(claudeFile), version: "2.1.234", apiKeyIsSet: true
        ) + AgentCatalog.codexDetails(authJSON: codexFile)
            + AgentCatalog.grokDetails(authJSON: grokFile, version: "1.0.24", apiKeyIsSet: true)

        #expect(details.isEmpty == false)

        let secrets = [accessToken, refreshToken, openAIKey, anthropicToken, idToken, grokKey, grokRefresh]
        for secret in secrets {
            let characters = Array(secret)
            for start in 0...(characters.count - 12) {
                let window = String(characters[start..<(start + 12)])
                for detail in details {
                    #expect(detail.value.contains(window) == false, "leaked \(window) in \(detail.label)")
                    #expect(detail.label.contains(window) == false)
                }
            }
        }
    }

    @Test("reports a missing override without falling back to PATH")
    func rejectsBrokenOverride() async {
        let missing = TestScratch.unique("unifieddev-no-such-agent")
        let catalog = AgentCatalog(overrides: [.claudeCode: missing])

        let status = await catalog.status(for: .claudeCode)

        #expect(status.connection == .notInstalled)
        #expect(status.executablePath == nil)
        #expect(status.version == nil)
        #expect(status.details.contains { $0.value == missing })
        #expect(status.details.contains { $0.label == "Problem" })
    }

    @Test("reads trimmed executable overrides from the shared settings table")
    func readsStoredOverrides() async throws {
        let store = try makeTestStore("agent-executable-overrides")
        try await store.setSetting(
            AgentCatalog.executablePathSettingKey(.codex),
            "  /tmp/tools/codex  "
        )
        try await store.setSetting(
            AgentCatalog.executablePathSettingKey(.claudeCode),
            "   "
        )

        let overrides = await AgentCatalog.executablePathOverrides(in: store)

        #expect(overrides == [.codex: "/tmp/tools/codex"])
        #expect(await AgentCatalog.executablePathOverrides(in: nil).isEmpty)
    }

    @Test("an override is the runner command and an empty value keeps the ordinary name")
    func resolvesRunnerExecutable() {
        #expect(AgentCatalog.executable(for: .codex, override: " /tmp/tools/codex ") == "/tmp/tools/codex")
        #expect(AgentCatalog.executable(for: .codex, override: nil) == "codex")
        #expect(AgentCatalog.executable(for: .claudeCode, override: "   ") == "claude")
    }

    @Test("returns one status per kind, in order, and caches until invalidated")
    func cachesStatuses() async {
        let missing = TestScratch.unique("unifieddev-no-such-agent")
        let catalog = AgentCatalog(overrides: Dictionary(
            uniqueKeysWithValues: AgentKind.allCases.map { ($0, missing) }
        ))

        let first = await catalog.statuses()
        #expect(first.map(\.kind) == AgentKind.allCases)
        #expect(first.allSatisfy { $0.connection == .notInstalled })
        #expect(first.map(\.id) == AgentKind.allCases.map(\.rawValue))

        let cached = await catalog.statuses()
        #expect(cached == first)

        await catalog.invalidate()
        let refreshed = await catalog.statuses()
        #expect(refreshed == first)
    }

    @Test("resolves a config path through its symlinks and reports absence as nil")
    func resolvesConfigPaths() throws {
        let base = TestScratch.unique("unifieddev-agentcat")
        let real = base + "/real.json"
        let link = base + "/link.json"
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: URL(fileURLWithPath: real))
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
        defer { try? FileManager.default.removeItem(atPath: base) }

        let resolved = AgentCatalog.resolvedPath(link)
        #expect(resolved?.hasSuffix("/real.json") == true)
        #expect(AgentCatalog.resolvedPath(base + "/absent.json") == nil)
    }
}

private let localAgentsEnabled = ProcessInfo.processInfo.environment["UD_LOCAL_AGENTS"] == "1"

@Suite("AgentCatalogLocal", .enabled(if: localAgentsEnabled), .tags(.subprocess))
struct AgentCatalogLocalTests {
    @Test("finds the CLIs this machine has and none that it does not")
    func detectsLocalAgents() async {
        let statuses = await AgentCatalog().statuses()
        let byKind = Dictionary(uniqueKeysWithValues: statuses.map { ($0.kind, $0) })

        for kind in [AgentKind.claudeCode, .codex] {
            let status = byKind[kind]
            #expect(status?.connection != .notInstalled)
            #expect(status?.executablePath?.isEmpty == false)
            #expect(status?.version?.isEmpty == false)
        }

        #expect(byKind[.cursor]?.connection == .notInstalled)
        #expect(byKind[.openCode]?.connection == .notInstalled)
        #expect(byKind[.cursor]?.version == nil)
        #expect(byKind[.openCode]?.version == nil)
    }
}
