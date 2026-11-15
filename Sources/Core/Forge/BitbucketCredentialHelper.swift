import CryptoKit
import Foundation

public enum BitbucketCredentialHelper {
    public static let command = "git-credential"
    static let hosts = ["bitbucket.org", "www.bitbucket.org"]
    static let renewalPause: TimeInterval = 10 * 60
    static let mostInheritedEntries = 1_000

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

        var isBitbucket: Bool {
            protocolName == "https" && host.map(BitbucketCredentialHelper.hosts.contains) == true
        }

        var workspace: String? {
            guard let first = path?.split(separator: "/").first, !first.hasPrefix("-") else { return nil }
            return String(first)
        }
    }

    static func gitEnvironment(shim: String, over inherited: [String: String]) -> [String: String] {
        let start = inherited["GIT_CONFIG_COUNT"].flatMap(Int.init).map { min(max($0, 0), mostInheritedEntries) } ?? 0
        let entries = hosts.flatMap { host in
            let scope = "credential.https://\(host)"
            return [
                ("\(scope).helper", ""),
                ("\(scope).helper", "!\(BridgeRegistration.shellQuoted(shim)) \(command)"),
                ("\(scope).useHttpPath", "true"),
            ]
        }
        var result = ["GIT_CONFIG_COUNT": String(start + entries.count)]
        for (offset, entry) in entries.enumerated() {
            result["GIT_CONFIG_KEY_\(start + offset)"] = entry.0
            result["GIT_CONFIG_VALUE_\(start + offset)"] = entry.1
        }
        return result
    }

    static func environment(
        over inherited: [String: String],
        shim: String? = BridgeRegistration.shimPath(),
        declined: QuietMarker = BitbucketKeychainToken.declined(),
        keychainHoldsSignIn: () -> Bool = BitbucketKeychainToken.exists
    ) -> [String: String] {
        guard let shim, holdsSignIn(inherited, declined: declined, keychain: keychainHoldsSignIn) else { return inherited }
        return inherited.merging(gitEnvironment(shim: shim, over: inherited)) { _, helper in helper }
    }

    static func variables(signedInAs login: GitHubLogin) -> [String: String] {
        variables(adding: login.variables.merging(login.bitbucket.variables) { gitHub, _ in gitHub })
    }

    static func variables(adding signedIn: [String: String]) -> [String: String] {
        let inherited = Shell.environment().merging(signedIn) { _, login in login }
        let helper = environment(over: inherited).filter { $0.key.hasPrefix("GIT_CONFIG_") && inherited[$0.key] != $0.value }
        return signedIn.merging(helper) { _, helper in helper }
    }

    static func holdsSignIn(_ environment: [String: String], declined: QuietMarker, keychain: () -> Bool) -> Bool {
        if let folder = environment["KEYRING_FILE_DIR"], !folder.isEmpty {
            let file = URL(fileURLWithPath: folder).appending(path: BitbucketGitCredential.fileName(of: BitbucketGitCredential.tokenKey))
            return FileManager.default.fileExists(atPath: file.path)
        }
        guard environment[BitbucketLogin.configVariable]?.isEmpty ?? true,
              !declined.isQuiet(at: Date())
        else { return false }
        return keychain()
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
        markers: URL = FileManager.default.temporaryDirectory,
        action: String,
        request text: String,
        environment: [String: String],
        now: Date = Date(),
        keychain: @Sendable () -> BitbucketKeychainToken.Reading = { BitbucketKeychainToken.read() },
        refresh: (@Sendable (Request, [String: String]) async -> Void)? = nil
    ) async -> String {
        let request = Request(text)
        guard action == "get", request.isBitbucket else { return "" }
        let declined = BitbucketKeychainToken.declined(in: markers)
        guard let found = stored(environment: environment, now: now, declined: declined, keychain: keychain) else { return "" }
        guard found.isStale(at: now) else { return found.answer }
        let paused = renewalFailed(environment, in: markers)
        guard !paused.isQuiet(at: now) else { return found.answer }
        paused.remember()
        if let refresh {
            await refresh(request, environment)
        } else {
            await renew(for: request, environment: environment)
        }
        let renewed = stored(environment: environment, now: now, declined: declined, keychain: keychain) ?? found
        if !renewed.isStale(at: now) { paused.forget() }
        return renewed.answer
    }

    static func renewalFailed(_ environment: [String: String], in folder: URL) -> QuietMarker {
        let store = environment["KEYRING_FILE_DIR"].flatMap { $0.isEmpty ? nil : $0 } ?? "keychain"
        let digest = SHA256.hash(data: Data(store.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let name = "unified-dev-bitbucket-renewal-" + digest
        return QuietMarker(named: name, period: renewalPause, in: folder)
    }

    static func stored(
        environment: [String: String], now: Date, declined: QuietMarker, keychain: () -> BitbucketKeychainToken.Reading
    ) -> BitbucketGitCredential? {
        if let folder = environment["KEYRING_FILE_DIR"], !folder.isEmpty,
           let passphrase = environment["BKT_KEYRING_PASSPHRASE"], !passphrase.isEmpty {
            return BitbucketGitCredential.read(secrets: URL(fileURLWithPath: folder), passphrase: passphrase)
        }
        guard environment[BitbucketLogin.configVariable]?.isEmpty ?? true,
              !declined.isQuiet(at: now)
        else { return nil }
        switch keychain() {
        case .found(let value):
            declined.forget()
            return BitbucketGitCredential.credential(storedValue: value)
        case .declined:
            declined.remember()
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
