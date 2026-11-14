import Foundation

public struct AgentDetail: Sendable, Hashable, Identifiable, Codable {
    public var label: String
    public var value: String

    public var id: String { label }

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct AgentStatus: Sendable, Hashable, Identifiable {
    public enum Connection: String, Sendable, Hashable, Codable {
        case notInstalled
        case installed
        case connected
    }

    public var kind: AgentKind
    public var connection: Connection
    public var executablePath: String?
    public var version: String?
    public var details: [AgentDetail]
    public var configPath: String?

    public var id: String { kind.rawValue }

    public init(
        kind: AgentKind,
        connection: Connection,
        executablePath: String? = nil,
        version: String? = nil,
        details: [AgentDetail] = [],
        configPath: String? = nil
    ) {
        self.kind = kind
        self.connection = connection
        self.executablePath = executablePath
        self.version = version
        self.details = details
        self.configPath = configPath
    }
}

public struct CodexAccount: Sendable, Hashable {
    public var email: String?
    public var name: String?
    public var planType: String?
    public var expiresAt: Date?

    public init(email: String? = nil, name: String? = nil, planType: String? = nil, expiresAt: Date? = nil) {
        self.email = email
        self.name = name
        self.planType = planType
        self.expiresAt = expiresAt
    }

    public var isEmpty: Bool {
        email == nil && name == nil && planType == nil && expiresAt == nil
    }
}

public actor AgentCatalog {
    private let overrides: [AgentKind: String]
    private var cache: [AgentKind: AgentStatus] = [:]
    private var inFlight: [AgentKind: Task<AgentStatus, Never>] = [:]

    public private(set) var detectionCount = 0

    public init(overrides: [AgentKind: String] = [:]) {
        self.overrides = overrides
    }

    public func statuses() async -> [AgentStatus] {
        let resolved = await withTaskGroup(of: (AgentKind, AgentStatus).self) { group in
            for kind in AgentKind.allCases {
                group.addTask { [self] in (kind, await resolvedStatus(for: kind)) }
            }
            var byKind: [AgentKind: AgentStatus] = [:]
            for await (kind, status) in group { byKind[kind] = status }
            return byKind
        }
        return AgentKind.allCases.compactMap { resolved[$0] }
    }

    public func status(for kind: AgentKind) async -> AgentStatus {
        await resolvedStatus(for: kind)
    }

    public func invalidate() {
        cache.removeAll()
        inFlight.removeAll()
    }

    private func resolvedStatus(for kind: AgentKind) async -> AgentStatus {
        if let cached = cache[kind] { return cached }

        let task: Task<AgentStatus, Never>
        if let running = inFlight[kind] {
            task = running
        } else {
            let override = overrides[kind]
            task = Task { await Self.detect(kind, override: override) }
            inFlight[kind] = task
            detectionCount += 1
        }

        let status = await task.value

        if inFlight[kind] == task {
            inFlight[kind] = nil
            cache[kind] = status
        }
        return status
    }

    static func detect(_ kind: AgentKind, override: String?) async -> AgentStatus {
        await LoginShellPath.ready()
        let configPath = resolvedPath(kind.configPath)

        if let override, !override.trimmingCharacters(in: .whitespaces).isEmpty {
            let wanted = expandingTilde(override.trimmingCharacters(in: .whitespaces))
            guard let path = Shell.which(wanted) else {
                return AgentStatus(
                    kind: kind,
                    connection: .notInstalled,
                    details: [
                        AgentDetail(label: "Custom path", value: wanted),
                        AgentDetail(label: "Problem", value: "No executable file at the configured path"),
                    ],
                    configPath: configPath
                )
            }
            return await describe(kind, executablePath: path, configPath: configPath)
        }

        guard let path = Shell.which(kind.executableName) else {
            return AgentStatus(kind: kind, connection: .notInstalled, configPath: configPath)
        }
        return await describe(kind, executablePath: path, configPath: configPath)
    }

    public static func executablePathSettingKey(_ kind: AgentKind) -> String {
        "agent.\(kind.rawValue).executablePath"
    }

    public static func executablePathOverrides(in store: Store?) async -> [AgentKind: String] {
        guard let store else { return [:] }

        var found: [AgentKind: String] = [:]
        for kind in AgentKind.allCases {
            guard let value = try? await store.setting(executablePathSettingKey(kind)) else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { found[kind] = trimmed }
        }
        return found
    }

    public static func executable(for kind: AgentKind, override: String?) -> String {
        let trimmed = override?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? kind.executableName : expandingTilde(trimmed)
    }

    public static func installedKinds(overrides: [AgentKind: String] = [:]) async -> [AgentKind] {
        await LoginShellPath.ready()
        return AgentKind.allCases.filter { kind in
            let override = overrides[kind]?.trimmingCharacters(in: .whitespaces)
            if let override, !override.isEmpty {
                return Shell.which(expandingTilde(override)) != nil
            }
            return Shell.which(kind.executableName) != nil
        }
    }

    private static func describe(
        _ kind: AgentKind,
        executablePath: String,
        configPath: String?
    ) async -> AgentStatus {
        let version = await readVersion(executablePath: executablePath)

        let details: [AgentDetail]
        switch kind {
        case .claudeCode:
            let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
            details = claudeDetails(
                accountJSON: readFile(claudeAccountPath),
                credentialJSON: readFile(claudeCredentialPath),
                version: version,
                apiKeyIsSet: !(key ?? "").isEmpty
            )
        case .codex:
            details = codexDetails(authJSON: readFile(codexAuthPath))
        case .grok:
            let key = ProcessInfo.processInfo.environment["XAI_API_KEY"]
            details = grokDetails(
                authJSON: readFile(grokAuthPath),
                version: version,
                apiKeyIsSet: !(key ?? "").isEmpty
            )
        case .antigravity:
            let result = try? await Shell.run(
                executablePath,
                AntigravityModelList.arguments,
                env: ACPDialect.antigravity.quietEnvironment,
                timeout: AntigravityModelList.timeout
            )
            details = antigravityDetails(reading: result.map(AntigravityModelList.read), version: version)
        case .cursor, .openCode:
            details = []
        }

        return AgentStatus(
            kind: kind,
            connection: details.isEmpty ? .installed : .connected,
            executablePath: executablePath,
            version: version,
            details: details,
            configPath: configPath
        )
    }

    public static var claudeAccountPath: String { "\(NSHomeDirectory())/.claude.json" }
    public static var claudeCredentialPath: String { "\(NSHomeDirectory())/.claude/.credentials.json" }
    static var codexAuthPath: String { "\(NSHomeDirectory())/.codex/auth.json" }
    static var grokAuthPath: String { "\(NSHomeDirectory())/.grok/auth.json" }

    private static func readFile(_ path: String) -> Data? {
        FileManager.default.contents(atPath: path)
    }

    static func readVersion(executablePath: String) async -> String? {
        guard let result = try? await Shell.run(executablePath, ["--version"], timeout: .seconds(5)) else {
            return nil
        }
        let stdout = result.trimmed
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = stdout.isEmpty ? stderr : stdout
        return parseVersion(raw)
    }

    public static func parseVersion(_ raw: String) -> String? {
        let firstLine = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let firstLine, !firstLine.isEmpty else { return nil }

        for token in firstLine.components(separatedBy: .whitespaces) {
            let candidate = token.hasPrefix("v") ? String(token.dropFirst()) : token
            guard let first = candidate.first, first.isNumber, candidate.contains(".") else { continue }
            let trimmed = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "(),;"))
            if !trimmed.isEmpty { return trimmed }
        }

        return firstLine
    }

    public static func claudeDetails(
        accountJSON: Data?,
        credentialJSON: Data? = nil,
        version: String?,
        apiKeyIsSet: Bool
    ) -> [AgentDetail] {
        let root = accountJSON.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let account = root?["oauthAccount"] as? [String: Any]

        guard account != nil || apiKeyIsSet else { return [] }

        let plan = ClaudeAccountFiles(identity: accountJSON, credential: credentialJSON).plan
        let organization = (account?["organizationName"] as? String) ?? unknown
        let email = (account?["emailAddress"] as? String) ?? unknown

        return [
            AgentDetail(label: "Version", value: version ?? unknown),
            AgentDetail(label: "Provider", value: apiKeyIsSet ? "Anthropic API key" : "Anthropic"),
            AgentDetail(
                label: "Login method",
                value: apiKeyIsSet ? apiKeyLoginMethod : claudeLoginMethod(plan: plan)
            ),
            AgentDetail(label: "Organization", value: organization),
            AgentDetail(label: "Email", value: email),
        ]
    }

    static let apiKeyLoginMethod = "API key (ANTHROPIC_API_KEY set)"

    static func claudeLoginMethod(plan: String?) -> String {
        guard let plan else { return unknown }
        return "Claude \(plan) account"
    }

    public static func codexDetails(authJSON: Data?) -> [AgentDetail] {
        let root = authJSON.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        guard let root else { return [] }

        let authMode = root["auth_mode"] as? String
        let apiKeyIsSet = !((root["OPENAI_API_KEY"] as? String) ?? "").isEmpty
        let tokens = root["tokens"] as? [String: Any]
        let account = (tokens?["id_token"] as? String).flatMap(decodeCodexIDToken)

        if account == nil || account?.isEmpty == true {
            guard apiKeyIsSet else { return [] }
            return [
                AgentDetail(label: "Provider", value: "OpenAI"),
                AgentDetail(label: "Auth", value: codexAuthMethod(authMode, apiKeyIsSet: true)),
                AgentDetail(label: "API key", value: "Set"),
            ]
        }

        guard let account else { return [] }

        var details = [AgentDetail(label: "Provider", value: "OpenAI")]
        if let plan = account.planType, !plan.isEmpty {
            details.append(AgentDetail(label: "Plan", value: titleCased(plan)))
        }
        details.append(AgentDetail(
            label: "Auth",
            value: codexAuthMethod(authMode, apiKeyIsSet: apiKeyIsSet)
        ))
        details.append(AgentDetail(
            label: "Account",
            value: account.email ?? account.name ?? unknown
        ))
        if apiKeyIsSet {
            details.append(AgentDetail(label: "API key", value: "Set"))
        }
        return details
    }

    static func codexAuthMethod(_ authMode: String?, apiKeyIsSet: Bool) -> String {
        switch authMode {
        case "chatgpt": return "ChatGPT login"
        case "apikey": return "API key"
        case let mode? where !mode.isEmpty: return titleCased(mode)
        default: return apiKeyIsSet ? "API key" : unknown
        }
    }

    public static func decodeCodexIDToken(_ token: String) -> CodexAccount? {
        let segments = token.components(separatedBy: ".")
        guard segments.count >= 2 else { return nil }
        guard let payload = base64URLDecode(segments[1]) else { return nil }
        guard let claims = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else {
            return nil
        }

        let auth = claims["https://api.openai.com/auth"] as? [String: Any]
        let expiry = (claims["exp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }

        let account = CodexAccount(
            email: nonEmpty(claims["email"] as? String),
            name: nonEmpty(claims["name"] as? String),
            planType: nonEmpty(auth?["chatgpt_plan_type"] as? String),
            expiresAt: expiry
        )
        return account.isEmpty ? nil : account
    }

    public static func base64URLDecode(_ segment: String) -> Data? {
        guard !segment.isEmpty else { return nil }
        var normalized = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder == 1 { return nil }
        if remainder > 0 { normalized += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: normalized)
    }

    static let unknown = "unknown"

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    public static func grokDetails(
        authJSON: Data?,
        version: String?,
        apiKeyIsSet: Bool,
        now: Date = Date()
    ) -> [AgentDetail] {
        let account = authJSON.flatMap(decodeGrokAuth)
        guard account != nil || apiKeyIsSet else { return [] }

        var details = [
            AgentDetail(label: "Version", value: version ?? unknown),
            AgentDetail(label: "Provider", value: apiKeyIsSet && account == nil ? "xAI API key" : "xAI"),
            AgentDetail(
                label: "Login method",
                value: apiKeyIsSet && account == nil
                    ? "API key (XAI_API_KEY set)"
                    : grokLoginMethod(account?.authMode)
            ),
            AgentDetail(label: "Account", value: account?.email ?? account?.name ?? unknown),
        ]
        if let account, account.isExpired(at: now), !account.canRefresh {
            details.append(AgentDetail(
                label: "Session",
                value: "Expired, sign in again with `grok login`"
            ))
        }
        if apiKeyIsSet, account != nil {
            details.append(AgentDetail(label: "API key", value: "Set"))
        }
        return details
    }

    public static func antigravityDetails(reading: AntigravityModelList.Reading?, version: String?) -> [AgentDetail] {
        guard case .models = reading else { return [] }
        return [
            AgentDetail(label: "Version", value: version ?? unknown),
            AgentDetail(label: "Provider", value: "Google"),
            AgentDetail(label: "Login method", value: "Google sign in"),
        ]
    }

    static func grokLoginMethod(_ authMode: String?) -> String {
        switch authMode {
        case "oauth", "grok.com": return "Grok login"
        case "apikey", "api_key": return "API key"
        case let mode? where !mode.isEmpty: return titleCased(mode)
        default: return "Grok login"
        }
    }

    public struct GrokAccount: Sendable, Hashable {
        public var email: String?
        public var name: String?
        public var authMode: String?
        public var expiresAt: Date?
        public var canRefresh: Bool

        public init(
            email: String? = nil,
            name: String? = nil,
            authMode: String? = nil,
            expiresAt: Date? = nil,
            canRefresh: Bool = false
        ) {
            self.email = email
            self.name = name
            self.authMode = authMode
            self.expiresAt = expiresAt
            self.canRefresh = canRefresh
        }

        public func isExpired(at now: Date) -> Bool {
            guard let expiresAt else { return false }
            return expiresAt < now
        }
    }

    public static func decodeGrokAuth(_ data: Data) -> GrokAccount? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        for key in root.keys.sorted() {
            guard let object = root[key] as? [String: Any] else { continue }
            let email = nonEmpty(object["email"] as? String)
            let name = nonEmpty(object["first_name"] as? String)
                ?? nonEmpty(object["name"] as? String)
            let authMode = nonEmpty(object["auth_mode"] as? String)
            let expiry: Date? = switch object["expires_at"] {
            case let text as String: ISO8601DateFormatter().date(from: text)
            case let seconds as NSNumber: Date(timeIntervalSince1970: seconds.doubleValue)
            default: nil
            }
            let account = GrokAccount(
                email: email,
                name: name,
                authMode: authMode,
                expiresAt: expiry,
                canRefresh: nonEmpty(object["refresh_token"] as? String) != nil
            )
            if email != nil || name != nil { return account }
        }
        return nil
    }

    static func titleCased(_ value: String) -> String {
        value
            .components(separatedBy: CharacterSet(charactersIn: "_-"))
            .filter { !$0.isEmpty }
            .map(\.capitalizedFirst)
            .joined(separator: " ")
    }

    static func expandingTilde(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return NSHomeDirectory() + String(path.dropFirst(1))
    }

    static func resolvedPath(_ path: String) -> String? {
        let expanded = expandingTilde(path)
        guard FileManager.default.fileExists(atPath: expanded) else { return nil }
        return URL(fileURLWithPath: expanded).resolvingSymlinksInPath().path
    }
}
