import Foundation

public enum QuotaPollSchedule {
    public static let interval: TimeInterval = 60

    public static let backgroundInterval: TimeInterval = 300

    public static let onDemandFloor: TimeInterval = 30

    public static let tick: TimeInterval = 15

    public static func gap(for activity: DiffRefreshSchedule.Activity, isPanelOpen: Bool) -> TimeInterval {
        activity == .foreground || isPanelOpen ? interval : backgroundInterval
    }

    public static func isDue(lastAskedAt: Date?, at now: Date, after gap: TimeInterval) -> Bool {
        guard let lastAskedAt else { return true }
        return now.timeIntervalSince(lastAskedAt) >= gap
    }
}

public struct QuotaStanding: Sendable, Equatable {
    public var isInstalled: Bool
    public var lastReportedAt: Date?

    public init(isInstalled: Bool, lastReportedAt: Date? = nil) {
        self.isInstalled = isInstalled
        self.lastReportedAt = lastReportedAt
    }
}

public protocol AgentQuotaSource: Sendable {
    static var provider: AgentKind { get }

    var holder: QuotaHolder { get }

    func read() async -> Data?

    func standing() async -> QuotaStanding

    func account(from payload: Data, at now: Date) -> AgentAccount?
}

extension AgentQuotaSource {
    public var holder: QuotaHolder { QuotaHolder(provider: Self.provider, account: nil) }

    public func standing() async -> QuotaStanding { QuotaStanding(isInstalled: true) }

    public func account(from payload: Data, at now: Date) -> AgentAccount? {
        AgentAccountReader.account(from: payload, at: now)
    }
}

public struct ClaudeCodeQuotaSource: AgentQuotaSource {
    public static let provider = AgentKind.claudeCode

    public static let arguments = [
        "-p",
        "--output-format", "stream-json",
        "--input-format", "stream-json",
        "--verbose",
    ]

    public static func request(id: String) -> String {
        let json = JSONValue.object([
            "type": .string("control_request"),
            "request_id": .string(id),
            "request": .object(["subtype": .string("get_usage")]),
        ])
        return encode(json)
    }

    static func encode(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func answer(in line: String, to id: String) -> Data? {
        guard let json = JSONValue.parse(Data(line.utf8)),
              json["type"]?.stringValue == "control_response",
              let response = json["response"],
              response["request_id"]?.stringValue == id,
              response["subtype"]?.stringValue == "success",
              let payload = response["response"]
        else { return nil }
        return (try? JSONEncoder().encode(payload))
    }

    public static func launch(
        executable: String = AgentRunner.executable,
        cwd: String = AgentScratchDirectory.current(),
        account: AgentAccountHome?,
        environment: [String: String]
    ) -> AgentLaunch {
        AgentLaunch(
            executable: executable,
            arguments: arguments,
            cwd: cwd,
            environment: AgentAccountEnvironment.apply(account, to: environment)
        )
    }

    private let executable: String
    private let cwd: String
    private let environment: [String: String]?
    private let account: AgentAccountHome?
    private let accountPath: String
    private let credentialPath: String
    private let clock: @Sendable () -> Date
    private let activity: ClaudeAccountActivity
    private let makeProcess: @Sendable (AgentLaunch) -> any AgentProcessing
    private let loginShellReady: @Sendable () async -> Void

    public init(
        executable: String = AgentRunner.executable,
        cwd: String = AgentScratchDirectory.current(),
        environment: [String: String]? = nil,
        account: AgentAccountHome? = nil,
        accountPath: String? = nil,
        credentialPath: String? = nil,
        clock: @escaping @Sendable () -> Date = Date.init,
        activity: ClaudeAccountActivity = .shared,
        makeProcess: @escaping @Sendable (AgentLaunch) -> any AgentProcessing = AgentRunner.spawn,
        loginShellReady: @escaping @Sendable () async -> Void = LoginShellPath.readiness
    ) {
        self.activity = activity
        self.loginShellReady = loginShellReady
        self.executable = executable
        self.cwd = cwd
        self.environment = environment
        self.account = account
        self.accountPath = accountPath ?? account?.identityPath.path ?? AgentCatalog.claudeAccountPath
        self.credentialPath = credentialPath ?? account?.credentialPath.path
            ?? AgentCatalog.claudeCredentialPath
        self.clock = clock
        self.makeProcess = makeProcess
    }

    public var holder: QuotaHolder { QuotaHolder(provider: Self.provider, home: account) }

    public func standing() async -> QuotaStanding {
        await loginShellReady()
        return QuotaStanding(
            isInstalled: Shell.which(executable) != nil,
            lastReportedAt: ClaudeUsageCache.fetchedAt(in: accountFile(), at: clock())
        )
    }

    public func read() async -> Data? {
        let answer = await ask()
        guard !ClaudeCodeUsageAdapter.carriesLimits(answer) else { return answer }
        guard let cached = ClaudeUsageCache.reading(from: accountFile(), at: clock()) else { return answer }
        return Self.overlaid(answer, with: cached.payload) ?? cached.payload
    }

    static func overlaid(_ answer: Data?, with payload: Data) -> Data? {
        guard let answer,
              var fields = JSONValue.parse(answer)?.objectValue,
              let cached = JSONValue.parse(payload)?.objectValue
        else { return nil }
        for (key, value) in cached { fields[key] = value }
        return try? JSONEncoder().encode(JSONValue.object(fields))
    }

    public func account(from payload: Data, at now: Date) -> AgentAccount? {
        guard filesDescribeTheSession else { return AgentAccountReader.account(from: payload, at: now) }
        let files = ClaudeAccountFiles(
            identity: accountFile(),
            credential: FileManager.default.contents(atPath: credentialPath)
        )
        return AgentAccountReader.account(from: payload, claudeFiles: files, at: now)
    }

    private var filesDescribeTheSession: Bool {
        AgentAccountEnvironment.filesDescribeTheSession(
            environment ?? Shell.environment(), provider: .claudeCode, hasChosenAccount: account != nil
        )
    }

    private func accountFile() -> Data? {
        FileManager.default.contents(atPath: accountPath)
    }

    private func ask() async -> Data? {
        await loginShellReady()
        return await activity.holding(account) { await askHoldingTheAccount() }.flatMap(\.self)
    }

    private func askHoldingTheAccount() async -> Data? {
        let id = "unifieddev-usage-\(UUID().uuidString)"
        let process = makeProcess(Self.launch(
            executable: executable,
            cwd: cwd,
            account: account,
            environment: environment ?? Shell.environment()
        ))
        let lines = process.lines
        process.writeLine(Self.request(id: id))

        var answer: Data?
        do {
            for try await line in lines {
                if let payload = Self.answer(in: line, to: id) {
                    answer = payload
                    break
                }
            }
        } catch {
            answer = nil
        }
        await process.end(within: ClaudeAccountActivity.exitGrace)
        return answer
    }
}

public struct CodexQuotaSource: AgentQuotaSource {
    public static let provider = AgentKind.codex

    public static let method = "account/rateLimits/read"

    private let executable: String
    private let cwd: String
    private let environment: [String: String]?
    private let account: AgentAccountHome?
    private let makeProcess: @Sendable (AgentLaunch) -> any AgentProcessing
    private let loginShellReady: @Sendable () async -> Void

    public init(
        executable: String = CodexClient.executable,
        cwd: String = AgentScratchDirectory.current(),
        environment: [String: String]? = nil,
        account: AgentAccountHome? = nil,
        makeProcess: @escaping @Sendable (AgentLaunch) -> any AgentProcessing = CodexClient.spawn,
        loginShellReady: @escaping @Sendable () async -> Void = LoginShellPath.readiness
    ) {
        self.executable = executable
        self.cwd = cwd
        self.environment = environment
        self.account = account
        self.makeProcess = makeProcess
        self.loginShellReady = loginShellReady
    }

    public var holder: QuotaHolder { QuotaHolder(provider: Self.provider, home: account) }

    public func standing() async -> QuotaStanding {
        await loginShellReady()
        return QuotaStanding(isInstalled: Shell.which(executable) != nil)
    }

    public func read() async -> Data? {
        await loginShellReady()
        let configuration = CodexClient.Configuration(
            executable: executable,
            cwd: cwd,
            account: account,
            environment: environment ?? Shell.environment()
        )
        let client = CodexClient(configuration: configuration, makeProcess: makeProcess)
        defer { Task { await client.stop() } }
        do {
            try await client.start()
            let result = try await client.send(Self.method, params: nil)
            return try JSONEncoder().encode(result)
        } catch {
            return nil
        }
    }
}
