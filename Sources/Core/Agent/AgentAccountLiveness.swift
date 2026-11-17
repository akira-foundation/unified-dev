import Foundation

public struct AgentAccountLiveness: Sendable {
    public enum CliReport: Sendable, Hashable {
        case claimsSession
        case claimsNoSession
        case unanswered
    }

    public static let arguments = ["auth", "status"]

    public static let codexArguments = ["login", "status"]

    public static let codexNoSessionText = "Not logged in"

    public static let grokArguments = ["models"]

    public static let grokNoSessionText = "You are not authenticated."

    public static let grokSessionTexts = ["You are logged in with", "You are authenticated via"]

    public static let timeout: Duration = .seconds(10)

    private enum Command {
        case claudeAuthStatus
        case codexLoginStatus
        case grokModels

        init?(_ provider: AgentKind) {
            switch provider {
            case .claudeCode: self = .claudeAuthStatus
            case .codex: self = .codexLoginStatus
            case .grok: self = .grokModels
            case .antigravity, .cursor, .openCode: return nil
            }
        }

        var arguments: [String] {
            switch self {
            case .claudeAuthStatus: AgentAccountLiveness.arguments
            case .codexLoginStatus: AgentAccountLiveness.codexArguments
            case .grokModels: AgentAccountLiveness.grokArguments
            }
        }
    }

    private enum Outcome: Sendable {
        case answered(CliReport?)
        case timedOut
    }

    private let executable: String
    private let codexExecutable: String
    private let grokExecutable: String
    private let cwd: String
    private let environment: [String: String]?
    private let timeout: Duration
    private let activity: ClaudeAccountActivity
    private let makeProcess: @Sendable (AgentLaunch) -> any AgentProcessing

    init(
        executable: String = AgentRunner.executable,
        codexExecutable: String = CodexClient.executable,
        grokExecutable: String = AgentKind.grok.executableName,
        cwd: String = AgentScratchDirectory.current(),
        environment: [String: String]? = nil,
        timeout: Duration = AgentAccountLiveness.timeout,
        activity: ClaudeAccountActivity = .shared,
        makeProcess: @escaping @Sendable (AgentLaunch) -> any AgentProcessing = AgentRunner.spawn
    ) {
        self.activity = activity
        self.executable = executable
        self.codexExecutable = codexExecutable
        self.grokExecutable = grokExecutable
        self.cwd = cwd
        self.environment = environment
        self.timeout = timeout
        self.makeProcess = makeProcess
    }

    public static func using(
        executables: [AgentKind: String],
        makeProcess: @escaping @Sendable (AgentLaunch) -> any AgentProcessing = AgentRunner.spawn
    ) -> AgentAccountLiveness {
        AgentAccountLiveness(
            executable: executables[.claudeCode] ?? AgentRunner.executable,
            codexExecutable: executables[.codex] ?? CodexClient.executable,
            grokExecutable: executables[.grok] ?? AgentKind.grok.executableName,
            makeProcess: makeProcess
        )
    }

    public static func canAsk(about provider: AgentKind) -> Bool {
        Command(provider) != nil
    }

    public func report(for home: AgentAccountHome) async -> CliReport {
        guard let command = Command(home.provider) else { return .unanswered }
        await LoginShellPath.ready()
        guard command == .claudeAuthStatus else { return await ask(command, about: home) }
        return await activity.holding(home) { await ask(command, about: home) } ?? .unanswered
    }

    private func ask(_ command: Command, about home: AgentAccountHome) async -> CliReport {
        let process = makeProcess(AgentLaunch(
            executable: executable(for: command),
            arguments: command.arguments,
            cwd: cwd,
            environment: AgentAccountEnvironment.apply(home, to: environment ?? Shell.environment())
        ))
        let lines = process.lines
        let errorLines = process.errorLines
        process.closeStdin()

        let deadline = timeout
        let outcome = await withTaskGroup(of: Outcome.self) { group in
            group.addTask {
                switch command {
                case .claudeAuthStatus: .answered(await Self.firstReport(in: lines))
                case .codexLoginStatus: .answered(await Self.codexReport(of: process, lines: lines, errorLines: errorLines))
                case .grokModels: .answered(await Self.firstGrokReport(in: lines))
                }
            }
            group.addTask {
                do { try await Task.sleep(for: deadline) } catch { return .answered(nil) }
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            process.terminate()
            return first
        }
        if command == .claudeAuthStatus { await process.killUnlessExited(within: ClaudeAccountActivity.exitGrace) }
        guard case .answered(let answer) = outcome else { return .unanswered }
        return answer ?? .unanswered
    }

    private func executable(for command: Command) -> String {
        switch command {
        case .claudeAuthStatus: executable
        case .codexLoginStatus: codexExecutable
        case .grokModels: grokExecutable
        }
    }

    static func grokReport(in line: String) -> CliReport? {
        let text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix(grokNoSessionText) { return .claimsNoSession }
        return grokSessionTexts.contains { text.hasPrefix($0) } ? .claimsSession : nil
    }

    static func report(in output: String) -> CliReport? {
        guard let loggedIn = JSONValue.parse(Data(output.utf8))?["loggedIn"]?.boolValue else { return nil }
        return loggedIn ? .claimsSession : .claimsNoSession
    }

    static func codexReport(exitStatus: Int32, output: String) -> CliReport {
        if exitStatus == 0 { return .claimsSession }
        return output.contains(codexNoSessionText) ? .claimsNoSession : .unanswered
    }

    private static func firstReport(in lines: AsyncThrowingStream<String, Error>) async -> CliReport? {
        var output = ""
        do {
            for try await line in lines {
                output += line + "\n"
                if let report = report(in: output) { return report }
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func firstGrokReport(in lines: AsyncThrowingStream<String, Error>) async -> CliReport? {
        do {
            for try await line in lines {
                if let report = grokReport(in: line) { return report }
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func codexReport(
        of process: any AgentProcessing,
        lines: AsyncThrowingStream<String, Error>,
        errorLines: AsyncStream<String>
    ) async -> CliReport {
        async let standard = drain(lines)
        async let error = drain(errorLines)
        let output = await standard + error
        return codexReport(exitStatus: await process.exitStatus, output: output)
    }

    private static func drain(_ lines: AsyncThrowingStream<String, Error>) async -> String {
        var output = ""
        do {
            for try await line in lines { output += line + "\n" }
        } catch {
            return output
        }
        return output
    }

    private static func drain(_ lines: AsyncStream<String>) async -> String {
        var output = ""
        for await line in lines { output += line + "\n" }
        return output
    }
}
