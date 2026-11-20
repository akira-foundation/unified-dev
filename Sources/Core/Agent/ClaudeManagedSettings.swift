import Foundation

public struct ClaudeManagedSettings: Sendable {
    public static let system = ClaudeManagedSettings(
        root: URL(filePath: "/Library/Application Support/ClaudeCode", directoryHint: .isDirectory),
        preferences: URL(filePath: "/Library/Managed Preferences", directoryHint: .isDirectory),
        user: NSUserName()
    )

    static let preferencesDomain = "com.anthropic.claudecode"
    static let remoteFileName = "remote-settings.json"
    static let mcpFileName = "managed-mcp.json"

    let root: URL
    let preferences: URL
    let user: String

    func documents(accountDirectory: URL) -> [URL] {
        let dropIns = root.appending(path: "managed-settings.d", directoryHint: .isDirectory)
        return [root.appending(path: "managed-settings.json"), root.appending(path: Self.mcpFileName)]
            + Self.dropIns(in: dropIns)
            + [
                preferences.appending(path: user).appending(path: "\(Self.preferencesDomain).plist"),
                preferences.appending(path: "\(Self.preferencesDomain).plist"),
                accountDirectory.appending(path: Self.remoteFileName),
            ]
    }

    static func dropIns(in directory: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        guard let listed = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return [directory]
        }
        return listed.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
    }

    public func governs(accountDirectory: URL) -> Bool {
        documents(accountDirectory: accountDirectory).contains { Self.setsAnything(at: $0) }
    }

    static func setsAnything(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard let data = FileManager.default.contents(atPath: url.path) else { return true }
        let parsed = url.pathExtension == "plist"
            ? try? PropertyListSerialization.propertyList(from: data, format: nil)
            : try? JSONSerialization.jsonObject(with: data)
        guard let settings = parsed as? [String: Any] else { return true }
        return !settings.isEmpty
    }
}
