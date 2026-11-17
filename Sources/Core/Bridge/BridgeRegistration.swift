import Foundation

public struct BridgeAttachment: Sendable, Hashable {
    public let shimPath: String
    public let socketPath: String
    public let token: String
    public let role: BridgeRole

    public init(shimPath: String, socketPath: String, token: String, role: BridgeRole) {
        self.shimPath = shimPath
        self.socketPath = socketPath
        self.token = token
        self.role = role
    }

    public var environment: [String: String] {
        [
            BridgeProtocol.socketVariable: socketPath,
            BridgeProtocol.tokenVariable: token,
            BridgeProtocol.roleVariable: role.rawValue,
        ]
    }
}

public enum BridgeRegistration {
    public static let serverName = "unifieddev-workspace-bridge"

    public static var ownerServerName: String {
        ownerServerName(forBundleIdentifier: Bundle.main.bundleIdentifier)
    }

    public static func ownerServerName(forBundleIdentifier identifier: String?) -> String {
        let slug = slugified(Store.databaseDirectoryName(forBundleIdentifier: identifier))
        return slug.isEmpty ? "unifieddev" : slug
    }

    static func slugified(_ value: String) -> String {
        var slug = ""
        var pendingHyphen = false
        for scalar in value.lowercased().unicodeScalars {
            switch scalar {
            case "a"..."z", "0"..."9":
                if pendingHyphen, !slug.isEmpty { slug.unicodeScalars.append("-") }
                pendingHyphen = false
                slug.unicodeScalars.append(scalar)
            default:
                pendingHyphen = true
            }
        }
        return slug
    }

    public static func ownerAddCommand(_ attachment: BridgeAttachment) -> String {
        let environment = attachment.environment
            .sorted { $0.key < $1.key }
            .map { "-e \(shellQuoted("\($0.key)=\($0.value)"))" }
            .joined(separator: " ")
        return "claude mcp add --scope user \(ownerServerName) \(environment) -- "
            + shellQuoted(attachment.shimPath)
    }

    public static func ownerCodexAddCommand(_ attachment: BridgeAttachment) -> String {
        let environment = attachment.environment
            .sorted { $0.key < $1.key }
            .map { "--env \(shellQuoted("\($0.key)=\($0.value)"))" }
            .joined(separator: " ")
        return "codex mcp add \(ownerServerName) \(environment) -- "
            + shellQuoted(attachment.shimPath)
    }

    public static func ownerGrokAddCommand(_ attachment: BridgeAttachment) -> String {
        let environment = attachment.environment
            .sorted { $0.key < $1.key }
            .map { "-e \(shellQuoted("\($0.key)=\($0.value)"))" }
            .joined(separator: " ")
        return "grok mcp add --scope user \(ownerServerName) \(environment) -- "
            + shellQuoted(attachment.shimPath)
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    public static func claudeConfig(_ attachment: BridgeAttachment) throws -> Data {
        let server: [String: Any] = [
            "command": attachment.shimPath,
            "args": [String](),
            "env": attachment.environment,
        ]
        let document: [String: Any] = ["mcpServers": [serverName: server]]
        return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    }

    public static func writeClaudeConfig(
        _ attachment: BridgeAttachment,
        sessionID: SessionID,
        directory: String
    ) throws -> String {
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let path = (directory as NSString).appendingPathComponent("\(sessionID).mcp.json")
        let data = try claudeConfig(attachment)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        return path
    }

    public static func claudeArguments(configPath: String) -> [String] {
        ["--mcp-config", configPath]
    }

    public static func codexArguments(_ attachment: BridgeAttachment) -> [String] {
        let environment = attachment.environment
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(tomlString($0.value))" }
            .joined(separator: ",")
        return [
            "-c", "mcp_servers.\(serverName).command=\(tomlString(attachment.shimPath))",
            "-c", "mcp_servers.\(serverName).args=[]",
            "-c", "mcp_servers.\(serverName).env={\(environment)}",
        ]
    }

    public static func acpServers(_ attachment: BridgeAttachment?) -> [JSONValue] {
        guard let attachment else { return [] }
        let environment = attachment.environment
            .sorted { $0.key < $1.key }
            .map { JSONValue.object(["name": .string($0.key), "value": .string($0.value)]) }
        return [.object([
            "name": .string(serverName),
            "command": .string(attachment.shimPath),
            "args": .array([]),
            "env": .array(environment),
        ])]
    }

    static func tomlString(_ value: String) -> String {
        var escaped = ""
        for character in value.unicodeScalars {
            switch character {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default: escaped.unicodeScalars.append(character)
            }
        }
        return "\"\(escaped)\""
    }

    public static func shimPath(
        beside executable: String? = Bundle.main.executableURL?.path,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let override = environment["UD_BRIDGE_SHIM"], !override.isEmpty {
            return FileManager.default.isExecutableFile(atPath: override) ? override : nil
        }
        guard let executable else { return nil }
        let candidate = (executable as NSString).deletingLastPathComponent + "/bridge"
        return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
    }
}
