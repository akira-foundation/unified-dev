import Foundation

public actor GrokModelCatalog {
    public static let freshness = AgentModelCache<ACPModel>.freshness

    private let cache: AgentModelCache<ACPModel>

    public var fetchCount: Int { get async { await cache.fetchCount } }

    public init(
        fetch: @escaping @Sendable () async throws -> [ACPModel],
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        cache = AgentModelCache(fetch: { Self.sorted(try await fetch()) }, now: now)
    }

    public static func live(
        cwd: String = AgentScratchDirectory.current(),
        store: Store? = nil,
        account: AgentAccountHome? = nil,
        makeClient: @escaping @Sendable (ACPClient.Configuration) -> ACPClient = ACPRunner.spawn
    ) -> GrokModelCatalog {
        GrokModelCatalog(fetch: {
            await LoginShellPath.ready()
            let stored = try await store?.setting(AgentCatalog.executablePathSettingKey(.grok))
            let client = makeClient(ACPClient.Configuration(
                dialect: .grok,
                executable: AgentCatalog.executable(for: .grok, override: stored),
                cwd: cwd,
                account: account
            ))
            defer { Task { await client.stop() } }
            try await client.start()
            return await client.advertisedModels()
        })
    }

    public func models() async throws -> [ACPModel] {
        try await cache.models()
    }

    public func pickerModels() async throws -> [ACPModel] {
        try await models()
    }

    public func invalidate() async {
        await cache.invalidate()
    }

    public var lastKnown: [ACPModel] { get async { await cache.lastKnown } }

    static func sorted(_ models: [ACPModel]) -> [ACPModel] {
        GrokModelRank.ordered(models)
    }
}
