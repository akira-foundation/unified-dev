import Foundation

public struct SSHRemote: Sendable, Equatable {
    public var host: String
    public var port: Int?
    public var alias: String?

    public init(host: String, port: Int? = nil, alias: String? = nil) {
        self.host = SSHRemote.bare(host)
        self.port = port
        self.alias = alias
    }

    static func bare(_ host: String) -> String {
        host.lowercased().hasSuffix(".") ? String(host.lowercased().dropLast()) : host.lowercased()
    }

    public init?(remote: String) {
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") {
            guard let url = URL(string: trimmed), url.scheme?.lowercased() == "ssh",
                  let host = url.host, !host.isEmpty
            else { return nil }
            self.init(host: host.lowercased(), port: url.port)
            return
        }
        guard !trimmed.hasPrefix("/"), !trimmed.hasPrefix(".") else { return nil }
        var authority = Substring(trimmed)
        if let at = authority.firstIndex(of: "@"), !authority[..<at].contains(where: { $0 == ":" || $0 == "/" }) {
            authority = authority[authority.index(after: at)...]
        }
        let host: Substring
        if authority.hasPrefix("[") {
            guard let close = authority.firstIndex(of: "]") else { return nil }
            host = authority[authority.index(after: authority.startIndex)..<close]
        } else {
            guard let colon = authority.firstIndex(of: ":") else { return nil }
            host = authority[..<colon]
        }
        guard !host.isEmpty, !host.contains("/"), !host.hasPrefix("-") else { return nil }
        self.init(host: host.lowercased())
    }

    public var shown: String {
        if let alias { return alias }
        guard let port, port != 22 else { return host }
        return "[\(host)]:\(port)"
    }

    var isBitbucket: Bool {
        host == "bitbucket.org" || host.hasSuffix(".bitbucket.org")
    }

    func resolved(byConfig output: String) -> SSHRemote {
        var settings: [String: String] = [:]
        for line in GitFailureOutput.lines(of: output) {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            if parts.count == 2, settings[parts[0]] == nil { settings[parts[0]] = parts[1] }
        }
        let hostName = settings["hostname"].flatMap { $0.isEmpty ? nil : $0 } ?? host
        let resolvedPort = settings["port"].flatMap(Int.init) ?? port
        let resolvedAlias = settings["hostkeyalias"].flatMap { $0.isEmpty || $0 == "none" ? nil : $0 } ?? alias
        return SSHRemote(host: hostName, port: resolvedPort, alias: resolvedAlias)
    }
}

public struct KnownHostOffer: Sendable, Equatable {
    public var host: String
    public var lines: [String]
    public var fingerprints: [String]
    public var matchesPublished: Bool

    public init(host: String, lines: [String], fingerprints: [String], matchesPublished: Bool = false) {
        self.host = host
        self.lines = lines
        self.fingerprints = fingerprints
        self.matchesPublished = matchesPublished
    }
}

public enum KnownHosts {
    public static var file: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".ssh", directoryHint: .isDirectory)
            .appending(path: "known_hosts")
    }

    static let bitbucketFingerprints: Set<String> = [
        "ED25519 SHA256:ybgmFkzwOSotHTHLJgHO0QN8L0xErw6vd0VhFA9m3SM",
        "ECDSA SHA256:FC73VB6C4OQLSCrjEayhMp9UMxS97caD/Yyi2bhW/J0",
        "RSA SHA256:46OSHA1Rmj8E8ERTC6xkNcmGOw9oFxYr0WF6zWW8l1E",
    ]

    static let published: [String: Set<String>] = [
        "bitbucket.org": bitbucketFingerprints,
        "ssh.bitbucket.org": bitbucketFingerprints,
    ]

    public static func offer(for remote: SSHRemote, in file: URL = KnownHosts.file) async -> KnownHostOffer? {
        var configured = ["-G"]
        if let port = remote.port { configured += ["-p", String(port)] }
        configured += ["--", remote.host]
        let config = try? await Shell.run("ssh", configured, timeout: .seconds(10))
        let target = config.map { $0.ok ? remote.resolved(byConfig: $0.stdout) : remote } ?? remote
        return await offer(for: target, in: file, scan: scan)
    }

    static func offer(
        for remote: SSHRemote, in file: URL, scan: (SSHRemote) async -> (lines: [String], fingerprints: [String])?
    ) async -> KnownHostOffer? {
        let recorded = try? await Shell.run(
            "ssh-keygen", ["-F", remote.shown, "-f", file.path], timeout: .seconds(10)
        )
        guard recorded?.ok != true, let scanned = await scan(remote) else { return nil }
        return judged(remote: remote, lines: scanned.lines, fingerprints: scanned.fingerprints)
    }

    static func scan(_ remote: SSHRemote) async -> (lines: [String], fingerprints: [String])? {
        var arguments = ["-T", "5"]
        if let port = remote.port { arguments += ["-p", String(port)] }
        arguments += ["--", remote.host]
        guard let scanned = try? await Shell.run("ssh-keyscan", arguments, timeout: .seconds(15)) else {
            return nil
        }
        let lines = keyLines(in: scanned.stdout).map { line in
            ([remote.shown] + line.split(separator: " ").dropFirst().map(String.init)).joined(separator: " ")
        }
        guard !lines.isEmpty,
              let listed = try? await Shell.run(
                  "ssh-keygen", ["-l", "-f", "-"], stdin: lines.joined(separator: "\n") + "\n", timeout: .seconds(10)
              ),
              listed.ok
        else { return nil }
        return (lines, fingerprints(in: listed.stdout))
    }

    static func judged(remote: SSHRemote, lines: [String], fingerprints: [String]) -> KnownHostOffer? {
        guard !fingerprints.isEmpty, fingerprints.count == lines.count else { return nil }
        guard let expected = published[remote.host] else {
            guard !remote.isBitbucket else { return nil }
            return KnownHostOffer(host: remote.shown, lines: lines, fingerprints: fingerprints)
        }
        guard fingerprints.allSatisfy(expected.contains) else { return nil }
        return KnownHostOffer(host: remote.shown, lines: lines, fingerprints: fingerprints, matchesPublished: true)
    }

    public static func trust(_ offer: KnownHostOffer, in file: URL = KnownHosts.file) throws {
        let manager = FileManager.default
        let folder = file.deletingLastPathComponent()
        if !manager.fileExists(atPath: folder.path) {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let descriptor = open(file.path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        let existing = (try? Data(contentsOf: file)) ?? Data()
        let known = Set(GitFailureOutput.lines(of: String(decoding: existing, as: UTF8.self)))
        let added = offer.lines.filter { !known.contains($0) }
        guard !added.isEmpty else { return }
        let separator = existing.isEmpty || existing.last == UInt8(ascii: "\n") ? "" : "\n"
        try handle.write(contentsOf: Data((separator + added.joined(separator: "\n") + "\n").utf8))
    }

    static func keyLines(in output: String) -> [String] {
        GitFailureOutput.lines(of: output).filter { line in
            guard !line.hasPrefix("#"), !line.hasPrefix("@") else { return false }
            return line.split(separator: " ").count == 3
        }
    }

    static func fingerprints(in output: String) -> [String] {
        GitFailureOutput.lines(of: output).compactMap { line in
            let parts = line.split(separator: " ").map(String.init)
            guard parts.count >= 3, parts[1].hasPrefix("SHA256:"), let kind = parts.last,
                  kind.hasPrefix("("), kind.hasSuffix(")")
            else { return nil }
            return "\(kind.dropFirst().dropLast()) \(parts[1])"
        }
    }
}
