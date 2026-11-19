import Foundation

public enum TranscriptHome {
    public static let override = "UD_TRANSCRIPT_HOME"

    public static let nowhere = URL(filePath: "/dev/null/no-transcripts", directoryHint: .isDirectory)

    public static func overrideValue(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        info: [String: Any]? = Bundle.main.infoDictionary
    ) -> String? {
        guard PreviewIdentity.isPreview(bundleIdentifier: bundleIdentifier) else { return nil }
        return LaunchOverride.value(override, environment: environment, info: info)
    }

    public static func resolve(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        overriddenBy value: String? = overrideValue()
    ) -> URL {
        guard PreviewIdentity.isPreview(bundleIdentifier: bundleIdentifier) else { return home }
        return seedable(overriddenBy: value, home: home, environment: environment) ?? nowhere
    }

    public static func seedable(
        overriddenBy value: String? = overrideValue(),
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        let seeded = URL(filePath: value, directoryHint: .isDirectory)
        guard !isSame(seeded, as: home) else { return nil }

        let theirs = [
            TranscriptSources.claudeHome(home: home, environment: environment),
            TranscriptSources.codexHome(home: home, environment: environment),
        ]
        let ours = TranscriptSources.sources(provider: seeded).map(\.home)
        for mine in ours where theirs.contains(where: { isInside(mine, of: $0) || isInside($0, of: mine) }) {
            return nil
        }
        return seeded
    }

    static func isSame(_ url: URL, as directory: URL) -> Bool {
        settled(url) == settled(directory)
    }

    static func isInside(_ url: URL, of directory: URL) -> Bool {
        isInside(settled: settled(url), of: settled(directory))
    }

    static func isInside(settled path: String, of top: String) -> Bool {
        path == top || path.hasPrefix(top.hasSuffix("/") ? top : top + "/")
    }

    static func settled(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
