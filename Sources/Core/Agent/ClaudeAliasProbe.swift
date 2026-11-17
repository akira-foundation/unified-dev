import Foundation

public struct ClaudeAliasProbe: Sendable {
    public static let timeout: Duration = .seconds(20)
    static let exitGrace = ClaudeAccountActivity.exitGrace

    private let executable: String
    private let workRoot: String
    private let environment: [String: String]?
    private let timeout: Duration
    private let exitGrace: Duration
    private let managed: ClaudeManagedSettings
    private let activity: ClaudeAccountActivity
    private let makeProcess: @Sendable (AgentLaunch) -> any AgentProcessing

    init(
        executable: String = AgentRunner.executable,
        workRoot: String = NSTemporaryDirectory(),
        environment: [String: String]? = nil,
        timeout: Duration = ClaudeAliasProbe.timeout,
        exitGrace: Duration = ClaudeAliasProbe.exitGrace,
        managed: ClaudeManagedSettings = .system,
        activity: ClaudeAccountActivity = .shared,
        makeProcess: @escaping @Sendable (AgentLaunch) -> any AgentProcessing = AgentRunner.spawn
    ) {
        self.executable = executable
        self.workRoot = workRoot
        self.environment = environment
        self.timeout = timeout
        self.exitGrace = exitGrace
        self.managed = managed
        self.activity = activity
        self.makeProcess = makeProcess
    }

    public static func using(executableOverride override: String?) -> ClaudeAliasProbe {
        ClaudeAliasProbe(executable: AgentCatalog.executable(for: .claudeCode, override: override))
    }

    public func resolve(_ aliases: [String], account: AgentAccountHome?) async -> ClaudeAliasAnswers {
        let inherited = await inheritedEnvironment()
        let configuration = Self.configurationDirectory(in: AgentAccountEnvironment.apply(account, to: inherited))
        guard !managed.governs(accountDirectory: configuration) else { return ClaudeAliasAnswers() }
        let pins = ClaudeAliasPins.pinned(aliases, inSettingsAt: configuration.appending(path: "settings.json"))
        var found = ClaudeAliasAnswers(pinned: pins)
        let unpinned = aliases.filter { pins[$0] == nil }
        guard !unpinned.isEmpty else { return found }
        guard let endpoint = UnansweredEndpoint(), let proxy = RefusingEndpoint(),
              let directory = Self.freshDirectory(in: workRoot) else { return found }
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let id = ClaudeResolvedModel.accountID(account)
        for alias in unpinned {
            guard activity.beginProbe(id) else { break }
            let launch = AgentLaunch(
                executable: executable,
                arguments: Self.arguments(alias: alias, baseURL: endpoint.url, proxy: proxy.url),
                cwd: directory,
                environment: AgentAccountEnvironment.apply(account, to: inherited)
                    .merging(Self.overrides(baseURL: endpoint.url, proxy: proxy.url)) { _, override in override }
            )
            found.probed[alias] = await reportedModel(launching: launch)
            activity.endProbe(id)
        }
        withExtendedLifetime((endpoint, proxy)) {}
        return found
    }

    public func settingsFingerprint(_ aliases: [String], account: AgentAccountHome?) async -> String {
        let configuration = Self.configurationDirectory(in: AgentAccountEnvironment.apply(account, to: await inheritedEnvironment()))
        let governed = managed.governs(accountDirectory: configuration)
        let pins = ClaudeAliasPins.pinned(aliases, inSettingsAt: configuration.appending(path: "settings.json"))
        return "managed=\(governed);" + pins.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ";")
    }

    private func inheritedEnvironment() async -> [String: String] {
        await LoginShellPath.ready()
        return (environment ?? Shell.environment()).filter { !Self.proxyVariables.contains($0.key) }
    }

    static func configurationDirectory(in environment: [String: String]) -> URL {
        if let variable = AgentAccountEnvironment.directoryVariable(for: .claudeCode),
           let path = environment[variable], !path.isEmpty {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude", directoryHint: .isDirectory)
    }

    static func freshDirectory(in root: String) -> String? {
        var template = Array((root as NSString).appendingPathComponent("unifieddev-alias-probe.XXXXXX").utf8CString)
        guard let made = template.withUnsafeMutableBufferPointer({ mkdtemp($0.baseAddress) }) else { return nil }
        return String(cString: made)
    }

    static let proxyVariables: Set<String> = [
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy",
    ]

    static func arguments(alias: String, baseURL: String, proxy: String) -> [String] {
        [
            "-p", ".",
            "--model", alias,
            "--output-format", "stream-json",
            "--verbose",
            "--setting-sources", "local",
            "--settings", settings(baseURL: baseURL, proxy: proxy),
            "--strict-mcp-config",
            "--no-session-persistence",
            "--disable-slash-commands",
        ]
    }

    static func overrides(baseURL: String, proxy: String) -> [String: String] {
        var values = [
            "ANTHROPIC_BASE_URL": baseURL,
            "CLAUDE_CODE_USE_BEDROCK": "0",
            "CLAUDE_CODE_USE_VERTEX": "0",
            "CLAUDE_CODE_USE_FOUNDRY": "0",
            "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
            "DISABLE_AUTOUPDATER": "1",
            "NO_PROXY": "127.0.0.1,localhost",
            "no_proxy": "127.0.0.1,localhost",
        ]
        for variable in proxyVariables { values[variable] = proxy }
        return values
    }

    static func settings(baseURL: String, proxy: String) -> String {
        let value: [String: Any] = [
            "disableAllHooks": true,
            "autoMemoryEnabled": false,
            "env": overrides(baseURL: baseURL, proxy: proxy),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func initModel(in line: String) -> String? {
        guard let event = JSONValue.parse(line),
              event["type"]?.stringValue == "system",
              event["subtype"]?.stringValue == "init",
              let model = event["model"]?.stringValue, !model.isEmpty else { return nil }
        return model
    }

    private func reportedModel(launching launch: AgentLaunch) async -> String? {
        let process = makeProcess(launch)
        let lines = process.lines
        process.closeStdin()
        let model = await Self.first(within: timeout) { await Self.firstInitModel(in: lines) }
        await process.end(within: exitGrace)
        return model
    }

    private static func first<Answer: Sendable>(
        within deadline: Duration,
        _ work: @escaping @Sendable () async -> Answer?
    ) async -> Answer? {
        await withTaskGroup(of: Answer?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: deadline)
                return nil
            }
            let first = await group.next()
            group.cancelAll()
            return first.flatMap(\.self)
        }
    }

    private static func firstInitModel(in lines: AsyncThrowingStream<String, Error>) async -> String? {
        do {
            for try await line in lines {
                if let model = initModel(in: line) { return model }
            }
        } catch {
            return nil
        }
        return nil
    }
}
