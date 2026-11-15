import Foundation

public struct SSHRemote: Sendable, Equatable {
    public var host: String
    public var port: Int?

    public init(host: String, port: Int? = nil) {
        self.host = host
        self.port = port
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
        guard let port, port != 22 else { return host }
        return "[\(host)]:\(port)"
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
        let recorded = try? await Shell.run(
            "ssh-keygen", ["-F", remote.shown, "-f", file.path], timeout: .seconds(10)
        )
        guard recorded?.ok != true else { return nil }
        var arguments = ["-T", "5"]
        if let port = remote.port { arguments += ["-p", String(port)] }
        arguments += ["--", remote.host]
        guard let scanned = try? await Shell.run("ssh-keyscan", arguments, timeout: .seconds(15)) else {
            return nil
        }
        let lines = keyLines(in: scanned.stdout)
        guard !lines.isEmpty,
              let listed = try? await Shell.run(
                  "ssh-keygen", ["-l", "-f", "-"], stdin: lines.joined(separator: "\n") + "\n", timeout: .seconds(10)
              ),
              listed.ok
        else { return nil }
        return judged(host: remote.shown, lines: lines, fingerprints: fingerprints(in: listed.stdout))
    }

    static func judged(host: String, lines: [String], fingerprints: [String]) -> KnownHostOffer? {
        guard !fingerprints.isEmpty, fingerprints.count == lines.count else { return nil }
        guard let expected = published[host] else {
            return KnownHostOffer(host: host, lines: lines, fingerprints: fingerprints)
        }
        guard fingerprints.allSatisfy(expected.contains) else { return nil }
        return KnownHostOffer(host: host, lines: lines, fingerprints: fingerprints, matchesPublished: true)
    }

    public static func trust(_ offer: KnownHostOffer, in file: URL = KnownHosts.file) throws {
        let manager = FileManager.default
        let folder = file.deletingLastPathComponent()
        if !manager.fileExists(atPath: folder.path) {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let known = Set(GitFailureOutput.lines(of: existing))
        let added = offer.lines.filter { !known.contains($0) }
        guard !added.isEmpty else { return }
        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        let addition = Data((separator + added.joined(separator: "\n") + "\n").utf8)
        guard manager.fileExists(atPath: file.path) else {
            let written = manager.createFile(atPath: file.path, contents: addition, attributes: [.posixPermissions: 0o600])
            if !written { throw CocoaError(.fileWriteUnknown) }
            return
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: addition)
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
