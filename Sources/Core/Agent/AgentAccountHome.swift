import Foundation

public struct AgentAccountHome: Sendable, Hashable {
    public let provider: AgentKind
    public let id: AgentAccountID
    public let directory: URL
    public let isDefault: Bool
    public let label: String
    let identityBesideDirectory: Bool

    public init(
        provider: AgentKind,
        id: AgentAccountID,
        directory: URL,
        isDefault: Bool,
        label: String = "",
        identityBesideDirectory: Bool? = nil
    ) {
        self.provider = provider
        self.id = id
        self.directory = directory
        self.isDefault = isDefault
        self.label = label
        self.identityBesideDirectory = identityBesideDirectory ?? isDefault
    }

    public init(_ row: AgentAccountRow) {
        self.init(
            provider: row.provider,
            id: row.id,
            directory: URL(filePath: row.directory, directoryHint: .isDirectory),
            isDefault: row.isDefault,
            label: row.label
        )
    }

    public static func defaultID(for provider: AgentKind) -> AgentAccountID {
        AgentAccountID("default." + provider.rawValue)
    }

    public static func provider(ofDefaultID id: AgentAccountID) -> AgentKind? {
        AgentKind.allCases.first { defaultID(for: $0) == id }
    }

    public static func isDefaultID(_ id: AgentAccountID) -> Bool {
        provider(ofDefaultID: id) != nil
    }

    public static func defaultHome(for provider: AgentKind, home: URL) -> AgentAccountHome? {
        guard let name = defaultDirectoryName(for: provider) else { return nil }
        return AgentAccountHome(
            provider: provider,
            id: defaultID(for: provider),
            directory: home.appending(path: name, directoryHint: .isDirectory),
            isDefault: true
        )
    }

    public func isTheCliOwnDirectory(under userHome: URL) -> Bool {
        Self.isTheCliOwnDirectory(directory, of: provider, under: userHome)
    }

    static func isTheCliOwnDirectory(_ directory: URL, of provider: AgentKind, under userHome: URL) -> Bool {
        guard let name = defaultDirectoryName(for: provider) else { return false }
        return TranscriptHome.isSame(directory, as: userHome.appending(path: name, directoryHint: .isDirectory))
    }

    public var identityPath: URL {
        switch provider {
        case .claudeCode:
            claudeIdentityDirectory.appending(path: ".claude.json")
        case .codex, .grok, .antigravity, .cursor, .openCode:
            directory.appending(path: "auth.json")
        }
    }

    private var claudeIdentityDirectory: URL {
        if identityBesideDirectory { return directory.deletingLastPathComponent() }
        return directory
    }

    public var credentialPath: URL {
        switch provider {
        case .claudeCode: directory.appending(path: ".credentials.json")
        case .codex, .grok, .antigravity, .cursor, .openCode: directory.appending(path: "auth.json")
        }
    }

    private static func defaultDirectoryName(for provider: AgentKind) -> String? {
        switch provider {
        case .claudeCode: ".claude"
        case .codex: ".codex"
        case .grok: ".grok"
        case .antigravity, .cursor, .openCode: nil
        }
    }
}

public enum AgentAccountHomes {
    public static func root(support: URL) -> URL {
        support.appending(path: "AgentAccounts", directoryHint: .isDirectory)
    }

    public static func directory(for id: AgentAccountID, provider: AgentKind, support: URL) -> URL {
        root(support: support)
            .appending(path: provider.rawValue, directoryHint: .isDirectory)
            .appending(path: id.rawValue, directoryHint: .isDirectory)
    }
}
