import Foundation

public struct TranscriptSource: Sendable, Hashable {
    public var provider: AgentKind
    public var home: URL
    public var root: URL
    public var namePrefix: String

    public init(provider: AgentKind, home: URL, root: URL, namePrefix: String = "") {
        self.provider = provider
        self.home = home
        self.root = root
        self.namePrefix = namePrefix
    }
}

public struct TranscriptFile: Sendable, Hashable, Identifiable {
    public var provider: AgentKind
    public var url: URL
    public var size: Int
    public var modifiedAt: Date

    public var id: String { url.path }

    public init(provider: AgentKind, url: URL, size: Int, modifiedAt: Date) {
        self.provider = provider
        self.url = url
        self.size = size
        self.modifiedAt = modifiedAt
    }

    public var agentSessionID: String { TranscriptSources.agentSessionID(ofFile: url.path) }
}

public enum TranscriptSources {
    public static let extensionName = "jsonl"

    public static func agentSessionID(ofFile path: String) -> String {
        let stem = (path as NSString).lastPathComponent
        let name = stem.hasSuffix("." + extensionName)
            ? String(stem.dropLast(extensionName.count + 1))
            : stem
        guard name.hasPrefix("rollout-") else { return name }
        let parts = name.split(separator: "-")
        guard parts.count >= 5 else { return name }
        return parts.suffix(5).joined(separator: "-")
    }

    public static func sources(
        home: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [TranscriptSource] {
        let claude = claudeHome(home: home, environment: environment)
        let codex = codexHome(home: home, environment: environment)
        return [
            source(provider: .claudeCode, home: claude),
            source(provider: .codex, home: codex),
        ].compactMap { $0 }
    }

    public static func sources(accounts: [AgentAccountHome]) -> [TranscriptSource] {
        accounts.compactMap { source(provider: $0.provider, home: $0.directory) }
    }

    private static func source(provider: AgentKind, home: URL) -> TranscriptSource? {
        switch provider {
        case .claudeCode:
            TranscriptSource(provider: provider, home: home, root: home.appending(path: "projects"))
        case .codex:
            TranscriptSource(
                provider: provider, home: home, root: home.appending(path: "sessions"), namePrefix: "rollout-"
            )
        case .grok, .antigravity, .cursor, .openCode:
            nil
        }
    }

    public static func sources(provider home: URL) -> [TranscriptSource] {
        sources(home: home, environment: [:])
    }

    static func claudeHome(home: URL, environment: [String: String]) -> URL {
        directory(named: "CLAUDE_CONFIG_DIR", in: environment) ?? home.appending(path: ".claude")
    }

    static func codexHome(home: URL, environment: [String: String]) -> URL {
        directory(named: "CODEX_HOME", in: environment) ?? home.appending(path: ".codex")
    }

    private static func directory(named name: String, in environment: [String: String]) -> URL? {
        guard let value = environment[name], !value.isEmpty else { return nil }
        return URL(filePath: value)
    }

    public static func files(
        in source: TranscriptSource,
        manager: FileManager = .default
    ) -> [TranscriptFile] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let walker = manager.enumerator(
            at: source.root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [TranscriptFile] = []
        for case let url as URL in walker {
            guard url.pathExtension == extensionName,
                  source.namePrefix.isEmpty || url.lastPathComponent.hasPrefix(source.namePrefix),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let size = values.fileSize,
                  let modifiedAt = values.contentModificationDate
            else { continue }
            found.append(TranscriptFile(
                provider: source.provider, url: url, size: size, modifiedAt: modifiedAt
            ))
        }
        return found.sorted { $0.modifiedAt > $1.modifiedAt }
    }
}
