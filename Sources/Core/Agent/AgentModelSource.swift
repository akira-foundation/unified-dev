import Foundation

public struct AgentModelSource: Sendable {
    public let models: @Sendable () async throws -> [AgentModel]
    public let invalidate: @Sendable () async -> Void
    public let isInstalled: @Sendable () async -> Bool

    public static let alwaysInstalled: @Sendable () async -> Bool = { true }

    public init(
        models: @escaping @Sendable () async throws -> [AgentModel],
        invalidate: @escaping @Sendable () async -> Void,
        isInstalled: @escaping @Sendable () async -> Bool = AgentModelSource.alwaysInstalled
    ) {
        self.models = models
        self.invalidate = invalidate
        self.isInstalled = isInstalled
    }

    public func failure(of kind: AgentKind, because error: any Error) async -> ModelListFailure {
        ModelListFailure(kind: kind, error: error, agentIsInstalled: await isInstalled())
    }

    public static func kindsAwaitingModels(
        sources: [AgentKind: AgentModelSource],
        loaded: [AgentKind: [AgentModel]]
    ) -> [AgentKind] {
        AgentKind.runnable.filter { sources[$0] != nil && (loaded[$0] ?? []).isEmpty }
    }

    public static func live(
        store: Store? = nil,
        accounts: [AgentKind: AgentAccountHome] = [:]
    ) -> [AgentKind: AgentModelSource] {
        let claude = ClaudeModelSource.live(path: accounts[.claudeCode]?.identityPath.path)
        let codex = CodexModelCatalog.live(account: accounts[.codex])
        let grok = GrokModelCatalog.live(store: store, account: accounts[.grok])
        return [
            .claudeCode: AgentModelSource(
                models: { try await claude.models() },
                invalidate: { await claude.invalidate() }
            ),
            .codex: AgentModelSource(
                models: { try await codex.models().map(\.agentModel) },
                invalidate: { await codex.invalidate() },
                isInstalled: { await isInstalled(.codex, store: store) }
            ),
            .grok: AgentModelSource(
                models: { try await grok.models().map(\.agentModel) },
                invalidate: { await grok.invalidate() },
                isInstalled: { await isInstalled(.grok, store: store) }
            ),
        ]
    }

    private static func isInstalled(_ kind: AgentKind, store: Store?) async -> Bool {
        let overrides = await AgentCatalog.executablePathOverrides(in: store)
        return await AgentCatalog.installedKinds(overrides: overrides).contains(kind)
    }
}
