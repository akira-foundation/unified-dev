import Foundation

public struct SetupProbe: Sendable {
    private let catalog: AgentCatalog

    public init(agentOverrides: [AgentKind: String] = [:]) {
        catalog = AgentCatalog(overrides: agentOverrides)
    }

    public func run() -> AsyncStream<SetupCheck> {
        AsyncStream { continuation in
            let work = Task {
                await withTaskGroup(of: SetupCheck.self) { group in
                    for tool in SetupTool.displayOrder {
                        group.addTask { await check(tool) }
                    }
                    for await result in group {
                        continuation.yield(result)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    public func report() async -> SetupReport {
        var byTool: [SetupTool: SetupCheck] = [:]
        for await check in run() { byTool[check.tool] = check }
        return SetupReport(checks: SetupTool.displayOrder.map {
            byTool[$0] ?? SetupCheck(tool: $0, outcome: .missing)
        })
    }

    public func check(_ tool: SetupTool) async -> SetupCheck {
        switch tool {
        case .git: await SetupCheck(tool: tool, outcome: gitOutcome())
        case .claudeCode, .codex, .grok, .antigravity: await SetupCheck(tool: tool, outcome: agentOutcome(tool))
        case .gitHub: await SetupCheck(tool: tool, outcome: gitHubOutcome())
        case .bitbucket: await SetupCheck(tool: tool, outcome: bitbucketOutcome())
        }
    }

    private func gitOutcome() async -> SetupOutcome {
        guard let path = Shell.which("git") else { return .missing }
        return Self.gitOutcome(version: try? await Shell.run(path, ["--version"], timeout: .seconds(5)))
    }

    static func gitOutcome(version: ShellResult?) -> SetupOutcome {
        guard let version else { return .ready(detail: nil) }
        guard version.ok else { return .missing }
        return .ready(detail: AgentCatalog.parseVersion(version.trimmed))
    }

    private func agentOutcome(_ tool: SetupTool) async -> SetupOutcome {
        guard let kind = tool.agentKind else { return .missing }
        let status = await catalog.status(for: kind)

        switch status.connection {
        case .notInstalled:
            return .missing
        case .installed:
            return .needsSignIn(detail: status.version)
        case .connected:
            return .ready(detail: Self.accountLine(status))
        }
    }

    static func accountLine(_ status: AgentStatus) -> String? {
        let wanted = ["Email", "Account", "Organization"]
        for label in wanted {
            if let value = status.details.first(where: { $0.label == label })?.value,
               value != AgentCatalog.unknown, !value.isEmpty {
                return value
            }
        }
        return status.version
    }

    private func gitHubOutcome() async -> SetupOutcome {
        switch await GitHub.access() {
        case .notInstalled: return .missing
        case .signedOut: return .needsSignIn(detail: nil)
        case .ready: return .ready(detail: "Signed in")
        }
    }

    private func bitbucketOutcome() async -> SetupOutcome {
        await LoginShellPath.ready()
        guard let path = Shell.which(Bitbucket.executable) else { return .missing }
        return Self.bitbucketOutcome(status: try? await Shell.run(path, ["auth", "status", "--json"], timeout: .seconds(5)))
    }

    static func bitbucketOutcome(status: ShellResult?) -> SetupOutcome {
        guard let status, status.ok, let decoded = BitbucketAuthStatus.decode(status.stdout),
              decoded.isSignedInToCloud else { return .needsSignIn(detail: nil) }
        return .ready(detail: "Signed in")
    }
}
