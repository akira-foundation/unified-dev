import Foundation

public enum AgentAccountEnvironment {
    public static let strippedPrefixes = ["ANTHROPIC", "CLAUDE", "CODEX", "GROK", "OPENAI", "XAI"]

    public static let directoryVariables: Set<String> = Set(
        AgentKind.allCases.compactMap(directoryVariable(for:))
    )

    public static let exemptVariables: Set<String> = [
        "CLAUDE_CODE_USE_BEDROCK",
        "CLAUDE_CODE_USE_VERTEX",
        "ANTHROPIC_MODEL",
        "CLAUDE_CODE_MAX_OUTPUT_TOKENS",
        "CLAUDE_CODE_SUBAGENT_MODEL",
    ]

    public static func isStripped(_ name: String) -> Bool {
        guard !directoryVariables.contains(name), !exemptVariables.contains(name) else { return false }
        return strippedPrefixes.contains { name.hasPrefix($0) }
    }

    public static func apply(
        _ home: AgentAccountHome?,
        to environment: [String: String],
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String: String] {
        applied(home, to: environment, userHome: userHome).environment
    }

    public static func applied(
        _ home: AgentAccountHome?,
        to environment: [String: String],
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> (environment: [String: String], stripped: [String]) {
        var result: [String: String] = [:]
        var stripped: [String] = []
        for (name, value) in environment {
            if isStripped(name) {
                stripped.append(name)
                continue
            }
            result[name] = value
        }
        if let home, let variable = directoryVariable(for: home.provider) {
            result[variable] = home.isTheCliOwnDirectory(under: userHome) ? nil : home.directory.path
        }
        return (result, stripped.sorted())
    }

    public static func strippedNotice(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        return "Unified Dev cleared \(names.joined(separator: ", ")) from this chat's environment, "
            + "because those variables can send the agent to an account other than the one you chose."
    }

    public static func login(
        for home: AgentAccountHome?,
        inheriting inherited: [String: String],
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String: String] {
        apply(home, to: Shell.terminalEnvironment(inheriting: inherited), userHome: userHome)
    }

    public static func codexHome(for home: AgentAccountHome?, inheriting environment: [String: String]) -> String? {
        apply(home, to: environment)["CODEX_HOME"]
    }

    public static func subshell(around command: String) -> String {
        "(" + shellListing + " " + command + ")"
    }

    public static let listingFailure =
        "Unified Dev could not list the variables to clear, so it did not start the agent."

    public static let shellUnsets = "\"$@\""

    public static let listableNameCharacters = "A-Za-z0-9_.-"

    static let shellListing: String = {
        let kept = directoryVariables.union(exemptVariables).sorted().joined(separator: " ")
        let matched = strippedPrefixes.sorted().joined(separator: "|")
        let program = "BEGIN{n=split(\"\(kept)\",k,\" \");for(i=1;i<=n;i++)keep[k[i]]=1;"
            + "for(v in ENVIRON)if(!(v in keep)&&v ~ /^(\(matched))/"
            + "&&v ~ /^[\(listableNameCharacters)]+$/)"
            + "printf \"-u %s \", v}"
        return "ud_unsets=$(LC_ALL=C /usr/bin/awk '\(program)')"
            + " || { echo '\(listingFailure)' >&2; exit 1; };"
            + " eval \"set -- $ud_unsets\";"
    }()

    public static func filesDescribeTheSession(
        _ environment: [String: String],
        provider: AgentKind,
        hasChosenAccount: Bool
    ) -> Bool {
        guard (environment["ANTHROPIC_API_KEY"] ?? "").isEmpty else { return false }
        guard !hasChosenAccount else { return true }
        guard let variable = directoryVariable(for: provider) else { return true }
        return (environment[variable] ?? "").isEmpty
    }

    public static func shellArguments(
        for home: AgentAccountHome?,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        guard let home, let variable = directoryVariable(for: home.provider) else { return [] }
        guard !home.isTheCliOwnDirectory(under: userHome) else { return ["-u", variable] }
        return ["\(variable)=\(home.directory.path)"]
    }

    static func directoryVariable(for provider: AgentKind) -> String? {
        switch provider {
        case .claudeCode: "CLAUDE_CONFIG_DIR"
        case .codex: "CODEX_HOME"
        case .grok: "GROK_HOME"
        case .antigravity, .cursor, .openCode: nil
        }
    }
}
