import Foundation

public enum BitbucketCredentialHelper {
    public static let command = "git-credential"
    static let host = "bitbucket.org"

    struct Request: Equatable {
        var protocolName: String?
        var host: String?
        var path: String?

        init(_ text: String) {
            for line in text.components(separatedBy: "\n") {
                guard let equals = line.firstIndex(of: "=") else { continue }
                let key = line[..<equals]
                let value = String(line[line.index(after: equals)...])
                switch key {
                case "protocol": protocolName = value
                case "host": host = value.lowercased()
                case "path": path = value
                default: continue
                }
            }
        }

        var isBitbucket: Bool { protocolName == "https" && host == BitbucketCredentialHelper.host }

        var workspace: String? {
            guard let first = path?.split(separator: "/").first, !first.hasPrefix("-") else { return nil }
            return String(first)
        }
    }

    public static func gitEnvironment(shim: String, over inherited: [String: String]) -> [String: String] {
        let start = inherited["GIT_CONFIG_COUNT"].flatMap(Int.init).map { max($0, 0) } ?? 0
        let scope = "credential.https://\(host)"
        let entries = [
            ("\(scope).helper", ""),
            ("\(scope).helper", "!\(BridgeRegistration.shellQuoted(shim)) \(command)"),
            ("\(scope).useHttpPath", "true"),
        ]
        var result = ["GIT_CONFIG_COUNT": String(start + entries.count)]
        for (offset, entry) in entries.enumerated() {
            result["GIT_CONFIG_KEY_\(start + offset)"] = entry.0
            result["GIT_CONFIG_VALUE_\(start + offset)"] = entry.1
        }
        return result
    }

    public static func environment(over inherited: [String: String], shim: String? = BridgeRegistration.shimPath()) -> [String: String] {
        guard let shim else { return inherited }
        return inherited.merging(gitEnvironment(shim: shim, over: inherited)) { _, helper in helper }
    }

    public static func run(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> Int32 {
        var input = ""
        while let line = readLine(strippingNewline: true), !line.isEmpty {
            input += line + "\n"
        }
        let reply = await answer(action: arguments.first ?? "", request: input, environment: environment)
        FileHandle.standardOutput.write(Data(reply.utf8))
        return 0
    }

    static func answer(
        action: String,
        request text: String,
        environment: [String: String],
        now: Date = Date(),
        refresh: (@Sendable (Request, [String: String]) async -> Void)? = nil
    ) async -> String {
        let request = Request(text)
        guard action == "get", request.isBitbucket else { return "" }
        guard let found = stored(environment: environment, now: now) else { return "" }
        guard found.isStale(at: now) else { return found.answer }
        if let refresh {
            await refresh(request, environment)
        } else {
            await renew(for: request, environment: environment)
        }
        return (stored(environment: environment, now: now) ?? found).answer
    }

    static func stored(environment: [String: String], now: Date) -> BitbucketGitCredential? {
        if let folder = environment["KEYRING_FILE_DIR"], !folder.isEmpty,
           let passphrase = environment["BKT_KEYRING_PASSPHRASE"], !passphrase.isEmpty {
            return BitbucketGitCredential.read(secrets: URL(fileURLWithPath: folder), passphrase: passphrase)
        }
        guard environment[BitbucketLogin.configVariable]?.isEmpty ?? true,
              !BitbucketKeychainToken.recentlyDeclined(at: now)
        else { return nil }
        switch BitbucketKeychainToken.read() {
        case .found(let value):
            BitbucketKeychainToken.forgetDecline()
            return BitbucketGitCredential.credential(storedValue: value)
        case .declined:
            BitbucketKeychainToken.rememberDecline()
            return nil
        case .missing:
            return nil
        }
    }

    static func renew(for request: Request, environment: [String: String]) async {
        let executable = Bitbucket.executable
        guard let status = try? await Shell.run(executable, ["auth", "status", "--json"], env: environment, timeout: .seconds(20)),
              status.ok, let decoded = BitbucketAuthStatus.decode(status.stdout), decoded.isSignedInToCloud
        else { return }
        var context = decoded.cloudContext
        if context == nil, let workspace = request.workspace {
            let create = [
                "context", "create", Bitbucket.appContext,
                "--host", BitbucketAuthStatus.cloudHostKey, "--workspace", workspace,
            ]
            if (try? await Shell.run(executable, create, env: environment, timeout: .seconds(20)))?.ok == true {
                context = Bitbucket.appContext
            }
        }
        guard let context else { return }
        _ = try? await Shell.run(executable, ["api", "/user", "--context", context], env: environment, timeout: .seconds(30))
    }
}
