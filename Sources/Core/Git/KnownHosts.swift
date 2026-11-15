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
        guard !trimmed.hasPrefix("/"), !trimmed.hasPrefix("."), let colon = trimmed.firstIndex(of: ":") else {
            return nil
        }
        let host = trimmed[..<colon].split(separator: "@").last.map(String.init) ?? ""
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

    public init(host: String, lines: [String], fingerprints: [String]) {
        self.host = host
        self.lines = lines
        self.fingerprints = fingerprints
    }
}

public enum KnownHosts {
    public static var file: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".ssh", directoryHint: .isDirectory)
            .appending(path: "known_hosts")
    }

    public static func offer(for remote: SSHRemote) async -> KnownHostOffer? {
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
        let fingerprints = fingerprints(in: listed.stdout)
        guard !fingerprints.isEmpty else { return nil }
        return KnownHostOffer(host: remote.shown, lines: lines, fingerprints: fingerprints)
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
            guard !line.hasPrefix("#") else { return false }
            return line.split(separator: " ").count >= 3
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
