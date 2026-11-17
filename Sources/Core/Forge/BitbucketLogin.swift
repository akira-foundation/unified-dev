import Foundation

public struct BitbucketLogin: Sendable, Hashable {
    public enum Method: String, Sendable, Hashable, CaseIterable {
        case browser
        case apiToken

        public var arguments: [String] {
            switch self {
            case .browser: ["--web"]
            case .apiToken: ["--web-token"]
            }
        }
    }

    public static let configVariable = "BKT_CONFIG_DIR"
    public static let clearedVariables = [
        "BKT_TOKEN", "BKT_HOST", "BKT_USERNAME", "BKT_AUTH_METHOD", "BKT_WORKSPACE",
        "KEYRING_FILE_PASSWORD", "KEYRING_PASSWORD",
    ]
    static let passphraseFile = "passphrase"
    static let secretsFolder = "secrets"

    public let directory: URL?

    public init(directory: URL?) {
        self.directory = directory
    }

    public init(gitHub: GitHubLogin) {
        let anchor: URL
        switch gitHub {
        case .thisMac:
            self.init(directory: nil)
            return
        case .profile(_, let directory, let uses):
            guard uses.bitbucket == .own else {
                self.init(directory: nil)
                return
            }
            anchor = directory
        case .unresolved(let directory):
            anchor = directory
        }
        self.init(anchoredAt: anchor)
    }

    private init(anchoredAt directory: URL) {
        let root = directory.deletingLastPathComponent().deletingLastPathComponent()
        self.init(
            directory: root
                .appending(path: Self.rootName, directoryHint: .isDirectory)
                .appending(path: directory.lastPathComponent, directoryHint: .isDirectory)
        )
    }

    public static let rootName = "BitbucketLogins"
    public static let thisMac = BitbucketLogin(directory: nil)

    public var isOwn: Bool { directory != nil }

    public var variables: [String: String] {
        guard let directory else { return [:] }
        var result = Dictionary(uniqueKeysWithValues: Self.clearedVariables.map { ($0, "") })
        result[Self.configVariable] = directory.path
        result["KEYRING_BACKEND"] = "file"
        result["BKT_ALLOW_INSECURE_STORE"] = "1"
        result["KEYRING_FILE_DIR"] = directory.appending(path: Self.secretsFolder, directoryHint: .isDirectory).path
        if let passphrase = Self.readPassphrase(in: directory) { result["BKT_KEYRING_PASSPHRASE"] = passphrase }
        return result
    }

    public func signInArguments(_ method: Method) -> [String] {
        var arguments = ["auth", "login", "https://bitbucket.org", "--kind", "cloud"] + method.arguments
        if isOwn { arguments.append("--allow-insecure-store") }
        return arguments
    }

    public func prepare() throws {
        guard let directory else { return }
        let manager = FileManager.default
        let secrets = directory.appending(path: Self.secretsFolder, directoryHint: .isDirectory)
        try manager.createDirectory(at: secrets, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: secrets.path)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        guard Self.readPassphrase(in: directory) == nil else { return }
        let file = directory.appending(path: Self.passphraseFile)
        let written = manager.createFile(
            atPath: file.path, contents: Data(Self.freshPassphrase().utf8), attributes: [.posixPermissions: 0o600]
        )
        if !written { throw CocoaError(.fileWriteUnknown) }
    }

    static func readPassphrase(in directory: URL) -> String? {
        let file = directory.appending(path: passphraseFile)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func freshPassphrase() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
    }
}

public enum BitbucketSignIn {
    public static func environment(_ inherited: [String: String], login: BitbucketLogin) -> [String: String] {
        guard login.isOwn else { return inherited }
        var result = inherited
        for name in BitbucketLogin.clearedVariables { result.removeValue(forKey: name) }
        return result.merging(login.variables.filter { !$0.value.isEmpty }) { _, own in own }
    }
}
