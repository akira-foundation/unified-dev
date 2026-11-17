import Foundation

public struct ProcessTable: Sendable, Equatable {
    public struct Row: Sendable, Equatable {
        public let pid: Int32
        public let parent: Int32
        public let group: Int32
        public let terminalGroup: Int32
        public let command: String

        public init(pid: Int32, parent: Int32, group: Int32, terminalGroup: Int32 = 0, command: String) {
            self.pid = pid
            self.parent = parent
            self.group = group
            self.terminalGroup = terminalGroup
            self.command = command
        }
    }

    public let rows: [Row]

    public init(rows: [Row] = []) {
        self.rows = rows
    }

    public static let arguments = ["-Ao", "pid=,ppid=,pgid=,tpgid=,args="]

    public init(psOutput: String) {
        rows = psOutput.split(separator: "\n").compactMap { line in
            var rest = Substring(line)
            guard let pid = Self.takeNumber(&rest),
                  let parent = Self.takeNumber(&rest),
                  let group = Self.takeNumber(&rest),
                  let terminalGroup = Self.takeNumber(&rest) else { return nil }
            let command = rest.trimmingCharacters(in: .whitespaces)
            guard !command.isEmpty else { return nil }
            return Row(
                pid: pid, parent: parent, group: group, terminalGroup: terminalGroup, command: command
            )
        }
    }

    private static func takeNumber(_ rest: inout Substring) -> Int32? {
        rest = rest.drop { $0 == " " || $0 == "\t" }
        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty, let value = Int32(digits) else { return nil }
        rest = rest.dropFirst(digits.count)
        guard rest.first == nil || rest.first == " " || rest.first == "\t" else { return nil }
        return value
    }

    public static let shared = SharedReading<ProcessTable> { await current() }

    public static func recent(notOlderThan maxAge: Duration) async -> ProcessTable? {
        await shared.value(notOlderThan: maxAge)
    }

    public static func current() async -> ProcessTable? {
        guard let result = try? await Shell.run("ps", arguments, timeout: .seconds(5)) else {
            return nil
        }
        return ProcessTable(psOutput: result.stdout)
    }

    public func foregroundCommand(ofShell shell: Int32) -> String? {
        guard shell > 0 else { return nil }
        let children = rows.filter { $0.parent == shell && $0.pid != shell }
        let leaders = children.filter { $0.pid == $0.group }
        return (leaders.isEmpty ? children : leaders).last?.command
    }
    public func interactiveAgent(ofShell shell: Int32) -> AgentKind? {
        interactiveAgentProcess(ofShell: shell).flatMap { Self.interactiveAgent(command: $0.command) }
    }

    public func interactiveAgentProcess(ofShell shell: Int32) -> Row? {
        guard shell > 0 else { return nil }
        let children = rows.filter { $0.parent == shell && $0.pid != shell }
        let leaders = children.filter { $0.pid == $0.group }
        guard let job = (leaders.isEmpty ? children : leaders).last else { return nil }
        var pending = [job]
        var visited: Set<Int32> = []
        while let process = pending.popLast() {
            guard visited.insert(process.pid).inserted else { continue }
            if Self.interactiveAgent(command: process.command) != nil { return process }
            pending.append(contentsOf: rows.filter { $0.parent == process.pid })
        }
        return nil
    }

    private static func interpretedScript(_ script: String) -> String? {
        if script.hasSuffix("/@anthropic-ai/claude-code/cli.js") { return "claude" }
        if script.hasSuffix("/@openai/codex/bin/codex.js") { return "codex" }
        return nil
    }

    private static func stride(over argument: String, valueOptions: Set<String>) -> Int? {
        if valueOptions.contains(argument) { return 2 }
        if argument.hasPrefix("-") { return 1 }
        return nil
    }

    public static func interactiveAgent(command: String) -> AgentKind? {
        var arguments = commandWords(command)
        guard let executable = arguments.first else { return nil }
        let name = URL(fileURLWithPath: executable).lastPathComponent
        if name == "node" || name == "nodejs" || name == "bun" {
            arguments.removeFirst()
            guard let script = arguments.first else { return nil }
            guard let named = interpretedScript(script) else { return nil }
            arguments[0] = named
        }
        guard let commandName = arguments.first else { return nil }
        let binary = URL(fileURLWithPath: commandName).lastPathComponent
        switch binary {
        case "claude":
            let commands: Set<String> = ["auth", "mcp", "plugin", "install", "update", "doctor", "setup-token", "help"]
            let valueOptions: Set<String> = [
                "--settings", "--session-id", "--resume", "-r", "--model", "--effort", "--permission-mode",
                "--system-prompt", "--append-system-prompt", "--mcp-config", "--agent", "--agents",
                "--add-dir", "--allowedTools", "--disallowedTools", "--tools", "--setting-sources"
            ]
            var index = 1
            while index < arguments.count {
                let argument = arguments[index]
                if argument == "--" { break }
                if ["--help", "-h", "--version", "-V", "--print", "-p"].contains(argument)
                    || argument.hasPrefix("--print=") || argument.hasPrefix("--output-format") { return nil }
                guard let step = stride(over: argument, valueOptions: valueOptions) else {
                    guard !commands.contains(argument) else { return nil }
                    break
                }
                index += step
            }
            return .claudeCode
        case "codex":
            let commands: Set<String> = ["exec", "e", "review", "app-server", "mcp-server", "mcp", "login", "logout", "completion", "sandbox", "debug", "apply", "cloud", "features", "help"]
            let valueOptions: Set<String> = ["-c", "--config", "-m", "--model", "-C", "--cd", "-s", "--sandbox", "-a", "--ask-for-approval", "-i", "--image", "-p", "--profile", "--add-dir", "--enable", "--disable"]
            var index = 1
            while index < arguments.count {
                let argument = arguments[index]
                if argument == "--" { break }
                if ["--help", "-h", "--version", "-V"].contains(argument) { return nil }
                guard let step = stride(over: argument, valueOptions: valueOptions) else {
                    guard !commands.contains(argument) else { return nil }
                    break
                }
                index += step
            }
            return .codex
        default:
            return nil
        }
    }

    private static func commandWords(_ command: String) -> [String] {
        var words: [String] = []
        var word = ""
        var quote: Character?
        var escaped = false
        var brackets: [Character] = []
        for character in command {
            if let delimiter = quote {
                word.append(character)
                if escaped {
                    escaped = false
                    continue
                }
                if character == "\\", delimiter == "\"" {
                    escaped = true
                    continue
                }
                if character == delimiter { quote = nil }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                word.append(character)
                continue
            }
            if character == "{" || character == "[" {
                brackets.append(character == "{" ? "}" : "]")
                word.append(character)
                continue
            }
            if character == brackets.last {
                brackets.removeLast()
                word.append(character)
                continue
            }
            if character.isWhitespace, brackets.isEmpty {
                if !word.isEmpty {
                    words.append(word)
                    word = ""
                }
                continue
            }
            word.append(character)
        }
        if !word.isEmpty { words.append(word) }
        return words
    }

    public func isBusy(shell: Int32) -> Bool? {
        guard shell > 0, let row = rows.first(where: { $0.pid == shell }) else { return nil }
        return row.terminalGroup > 0 && row.terminalGroup != shell
    }
}
