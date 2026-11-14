import Foundation

public struct GrokQuotaSource: AgentQuotaSource {
    public static let provider = AgentKind.grok

    public static let method = "_x.ai/billing"

    public static let timeout = Duration.seconds(20)

    static let methodNotFound = -32601

    static let reportsNothing = Data("{}".utf8)

    private let executable: String
    private let cwd: String
    private let environment: [String: String]?
    let account: AgentAccountHome?
    private let timeout: Duration
    private let bundleIdentifier: String?
    private let makeProcess: @Sendable (AgentLaunch) -> any AgentProcessing
    private let watchdogSleep: @Sendable (Duration) async throws -> Void
    private let loginShellReady: @Sendable () async -> Void

    public init(
        executable: String = GrokClient.executable,
        cwd: String = AgentScratchDirectory.current(),
        environment: [String: String]? = nil,
        account: AgentAccountHome? = nil,
        timeout: Duration = GrokQuotaSource.timeout,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        makeProcess: @escaping @Sendable (AgentLaunch) -> any AgentProcessing = GrokClient.spawn,
        watchdogSleep: @escaping @Sendable (Duration) async throws -> Void = GrokClient.taskSleep,
        loginShellReady: @escaping @Sendable () async -> Void = LoginShellPath.readiness
    ) {
        self.executable = executable
        self.cwd = cwd
        self.environment = environment
        self.account = account
        self.timeout = timeout
        self.bundleIdentifier = bundleIdentifier
        self.makeProcess = makeProcess
        self.watchdogSleep = watchdogSleep
        self.loginShellReady = loginShellReady
    }

    public var holder: QuotaHolder { QuotaHolder(provider: Self.provider, home: account) }

    public func standing() async -> QuotaStanding {
        await loginShellReady()
        let wouldReadTheOwnersLogin = account == nil && PreviewIdentity.isPreview(bundleIdentifier: bundleIdentifier)
        return QuotaStanding(isInstalled: !wouldReadTheOwnersLogin && Shell.which(executable) != nil)
    }

    public func read() async -> Data? {
        await loginShellReady()
        let configuration = GrokClient.Configuration(
            executable: executable,
            cwd: cwd,
            account: account,
            environment: environment ?? Shell.environment()
        )
        let client = GrokClient(configuration: configuration, makeProcess: makeProcess, watchdogSleep: watchdogSleep)
        defer { Task { await client.stop() } }
        do {
            try await client.start(timeout: timeout)
        } catch {
            return nil
        }
        do {
            let result = try await client.send(Self.method, params: .object([:]), timeout: timeout)
            return try JSONEncoder().encode(result)
        } catch let refusal as GrokRPCError where refusal.code == Self.methodNotFound {
            return Self.reportsNothing
        } catch {
            return nil
        }
    }

    public func account(from payload: Data, at now: Date) -> AgentAccount? {
        guard let line = JSONValue.parse(payload), GrokQuotaAdapter.config(in: line) != nil else { return nil }
        let tier = line["subscription_tier"]?.stringValue?.trimmingCharacters(in: .whitespaces)
        return AgentAccount(provider: Self.provider, plan: tier?.isEmpty == false ? tier : nil, observedAt: now)
    }
}

public enum GrokQuotaAdapter: AgentQuotaAdapter {
    public static let provider = AgentKind.grok

    static let periodPrefix = "USAGE_PERIOD_TYPE_"

    static func config(in line: JSONValue) -> JSONValue? {
        guard let config = line["config"], config["creditUsagePercent"] != nil else { return nil }
        return config
    }

    public static func quotas(from line: JSONValue, at now: Date) -> [AgentQuota] {
        guard let config = config(in: line) else { return [] }
        let period = config["currentPeriod"]
        let start = (period?["start"] ?? config["billingPeriodStart"])?.stringValue
            .flatMap(ClaudeCodeUsageAdapter.date(fromISO:))
        let end = (period?["end"] ?? config["billingPeriodEnd"])?.stringValue
            .flatMap(ClaudeCodeUsageAdapter.date(fromISO:))
        let measure: QuotaMeasure = config["creditUsagePercent"]?.doubleValue
            .map { .fraction($0 / 100) } ?? .unknown
        return [AgentQuota(
            provider: provider,
            window: window(named: period?["type"]?.stringValue, from: start, to: end),
            measure: measure,
            resetsAt: end,
            observedAt: now
        )]
    }

    static func window(named type: String?, from start: Date?, to end: Date?) -> QuotaWindow {
        var duration: TimeInterval?
        if let start, let end, end > start { duration = end.timeIntervalSince(start).rounded() }
        let name = type.map { $0.hasPrefix(periodPrefix) ? String($0.dropFirst(periodPrefix.count)) : $0 }?
            .lowercased()
        guard let name, !name.isEmpty else {
            return duration.map { QuotaWindow.lasting($0, key: "credits") }
                ?? QuotaWindow(key: "credits", label: "Credits")
        }
        return QuotaWindow(key: name, label: QuotaWindow.humanised(name), duration: duration)
    }
}
