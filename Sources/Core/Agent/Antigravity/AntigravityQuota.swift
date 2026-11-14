import Foundation

public struct AntigravityQuotaSource: AgentQuotaSource {
    public typealias Run = @Sendable (_ executable: String, _ arguments: [String], _ cwd: String) async -> ShellResult?

    public static let provider = AgentKind.antigravity

    public static let arguments = ["-p", "/usage", "--output-format", "json", "--print-timeout", "20s"]

    public static let timeout = Duration.seconds(30)

    static let reportsNothing = Data("{}".utf8)

    private static let refusal = AntigravityUsageRefusal()

    private let executable: String
    private let cwd: String
    let account: AgentAccountHome?
    private let bundleIdentifier: String?
    private let refusal: AntigravityUsageRefusal
    private let run: Run
    private let loginShellReady: @Sendable () async -> Void

    public init(
        executable: String = AgentKind.antigravity.executableName,
        cwd: String = AgentScratchDirectory.current(),
        account: AgentAccountHome? = nil,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        refusal: AntigravityUsageRefusal? = nil,
        run: @escaping Run = AntigravityQuotaSource.shell,
        loginShellReady: @escaping @Sendable () async -> Void = LoginShellPath.readiness
    ) {
        self.executable = executable
        self.cwd = cwd
        self.account = account
        self.bundleIdentifier = bundleIdentifier
        self.refusal = refusal ?? Self.refusal
        self.run = run
        self.loginShellReady = loginShellReady
    }

    public static let shell: Run = { executable, arguments, cwd in
        try? await Shell.run(
            executable, arguments, cwd: cwd, env: ACPDialect.antigravity.quietEnvironment, timeout: timeout
        )
    }

    public var holder: QuotaHolder { QuotaHolder(provider: Self.provider, home: account) }

    public func standing() async -> QuotaStanding {
        await loginShellReady()
        let wouldReadTheOwnersLogin = account == nil && PreviewIdentity.isPreview(bundleIdentifier: bundleIdentifier)
        return QuotaStanding(isInstalled: !wouldReadTheOwnersLogin && Shell.which(executable) != nil)
    }

    public func read() async -> Data? {
        guard !refusal.hasRefused else { return Self.reportsNothing }
        await loginShellReady()
        guard let result = await run(executable, Self.arguments, cwd), result.ok else { return nil }
        guard let reply = JSONValue.parse(Data(result.stdout.utf8)) else { return nil }
        guard AntigravityQuotaAdapter.isUsageCommand(reply) else {
            refusal.refuse()
            return Self.reportsNothing
        }
        return Data(result.stdout.utf8)
    }

    public func account(from payload: Data, at now: Date) -> AgentAccount? { nil }
}

public final class AntigravityUsageRefusal: @unchecked Sendable {
    private let lock = NSLock()
    private var refused = false

    public init() {}

    public var hasRefused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return refused
    }

    func refuse() {
        lock.lock()
        refused = true
        lock.unlock()
    }
}

public enum AntigravityQuotaAdapter: AgentQuotaAdapter {
    public static let provider = AgentKind.antigravity

    static let week: TimeInterval = 604_800

    static func isUsageCommand(_ reply: JSONValue) -> Bool {
        reply["command"]?["name"]?.stringValue == "usage" && (reply["num_turns"]?.intValue ?? 0) == 0
    }

    public static func quotas(from line: JSONValue, at now: Date) -> [AgentQuota] {
        guard isUsageCommand(line) else { return [] }
        let groups = line["command"]?["data"]?["groups"]?.arrayValue ?? []
        return groups.flatMap { group -> [AgentQuota] in
            let name = label(of: group["name"]?.stringValue ?? "")
            return (group["buckets"]?.arrayValue ?? []).compactMap { bucket in
                guard let id = bucket["id"]?.stringValue, !id.isEmpty else { return nil }
                let measure: QuotaMeasure = bucket["remaining_fraction"]?.doubleValue
                    .map { .fraction(max(0, min(1, 1 - $0))) } ?? .unknown
                return AgentQuota(
                    provider: provider,
                    window: QuotaWindow(
                        key: id,
                        label: name.isEmpty ? QuotaWindow.humanised(id) : name,
                        duration: bucket["window"]?.stringValue == "weekly" ? week : nil
                    ),
                    measure: measure,
                    resetsAt: bucket["reset_time"]?.stringValue.flatMap(ClaudeCodeUsageAdapter.date(fromISO:)),
                    observedAt: now
                )
            }
        }
    }

    static func label(of group: String) -> String {
        var name = group.trimmingCharacters(in: .whitespaces)
        for suffix in [" Models", " models"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        return name.components(separatedBy: " and ").first ?? name
    }
}
