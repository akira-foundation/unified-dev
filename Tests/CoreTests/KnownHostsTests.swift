import Foundation
import Testing
@testable import Core

@Suite("Trusting an ssh host the owner has confirmed")
struct KnownHostsTests {
    static let scanned = """
        # ssh.bitbucket.org:22 SSH-2.0-conker
        ssh.bitbucket.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIazEu89wgQZ4bqs3d63QSMzYVa0MuJ2e2gKTKqu+UUO
        ssh.bitbucket.org ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBPIQmuzMBuKdWeF4+a2sjSSpBK0iqitSQ+5BM9KhpexuGt20JpTVM7u5BDZngncgrqDMbWdxMWWOGtZ9UgbqgZE=
        """

    static let fingerprinted = """
        256 SHA256:ybgmFkzwOSotHTHLJgHO0QN8L0xErw6vd0VhFA9m3SM ssh.bitbucket.org (ED25519)
        256 SHA256:FC73VB6C4OQLSCrjEayhMp9UMxS97caD/Yyi2bhW/J0 ssh.bitbucket.org (ECDSA)
        """

    @Test(
        "every ssh address names its host, and https or a path names none",
        arguments: [
            ("git@ssh.bitbucket.org:debtges/ledger.git", SSHRemote(host: "ssh.bitbucket.org")),
            ("ssh://git@bitbucket.org/debtges/ledger.git", SSHRemote(host: "bitbucket.org")),
            ("ssh://git@git.example.com:7999/team/app.git", SSHRemote(host: "git.example.com", port: 7999)),
            ("git@[fe80::1]:team/app.git", SSHRemote(host: "fe80::1")),
            ("host.example.com:team/re@po.git", SSHRemote(host: "host.example.com")),
            ("https://bitbucket.org/debtges/ledger.git", nil),
            ("/srv/git/ledger.git", nil),
        ]
    )
    func readsTheHost(remote: String, expected: SSHRemote?) {
        #expect(SSHRemote(remote: remote) == expected)
    }

    @Test("a host on another port is written the way known_hosts names it")
    func shownWithPort() {
        #expect(SSHRemote(host: "git.example.com", port: 7999).shown == "[git.example.com]:7999")
        #expect(SSHRemote(host: "bitbucket.org", port: 22).shown == "bitbucket.org")
    }

    @Test("the scan keeps the key lines and drops ssh-keyscan's comments")
    func keepsKeyLines() {
        let lines = KnownHosts.keyLines(in: Self.scanned)

        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0.hasPrefix("ssh.bitbucket.org ") })
    }

    @Test("fingerprints are shown as the key type and its SHA256")
    func fingerprints() {
        #expect(KnownHosts.fingerprints(in: Self.fingerprinted) == [
            "ED25519 SHA256:ybgmFkzwOSotHTHLJgHO0QN8L0xErw6vd0VhFA9m3SM",
            "ECDSA SHA256:FC73VB6C4OQLSCrjEayhMp9UMxS97caD/Yyi2bhW/J0",
        ])
    }

    @Test("trusting appends the confirmed lines once, creating a private file when there was none")
    func trustAppendsOnce() throws {
        let file = URL(fileURLWithPath: TestScratch.unique("unifieddev-ssh")).appending(path: "known_hosts")
        let offer = KnownHostOffer(host: "ssh.bitbucket.org", lines: KnownHosts.keyLines(in: Self.scanned), fingerprints: [])

        try KnownHosts.trust(offer, in: file)
        try KnownHosts.trust(offer, in: file)

        let written = try String(contentsOf: file, encoding: .utf8)
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(written == offer.lines.joined(separator: "\n") + "\n")
        #expect(permissions == 0o600)
    }

    @Test("an existing file keeps what it had, even with no newline at its end")
    func trustKeepsExisting() throws {
        let folder = URL(fileURLWithPath: TestScratch.unique("unifieddev-ssh"), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "known_hosts")
        try "github.com ssh-ed25519 AAAA".write(to: file, atomically: true, encoding: .utf8)
        let offer = KnownHostOffer(host: "ssh.bitbucket.org", lines: ["ssh.bitbucket.org ssh-ed25519 BBBB"], fingerprints: [])

        try KnownHosts.trust(offer, in: file)

        #expect(try String(contentsOf: file, encoding: .utf8) == "github.com ssh-ed25519 AAAA\nssh.bitbucket.org ssh-ed25519 BBBB\n")
    }

    @Test("Bitbucket's keys are offered only when they are the ones Bitbucket publishes")
    func bitbucketIsPinned() {
        let lines = ["ssh.bitbucket.org ssh-ed25519 AAAA", "ssh.bitbucket.org ecdsa-sha2-nistp256 BBBB"]
        let genuine = ["ED25519 SHA256:ybgmFkzwOSotHTHLJgHO0QN8L0xErw6vd0VhFA9m3SM", "ECDSA SHA256:FC73VB6C4OQLSCrjEayhMp9UMxS97caD/Yyi2bhW/J0"]
        let forged = ["ED25519 SHA256:ybgmFkzwOSotHTHLJgHO0QN8L0xErw6vd0VhFA9m3SM", "ECDSA SHA256:someoneElsesKeyEntirely000000000000000000"]

        #expect(KnownHosts.judged(remote: SSHRemote(host: "ssh.bitbucket.org"), lines: lines, fingerprints: genuine)?.matchesPublished == true)
        #expect(KnownHosts.judged(remote: SSHRemote(host: "ssh.bitbucket.org"), lines: lines, fingerprints: forged) == nil)
        #expect(KnownHosts.judged(remote: SSHRemote(host: "git.example.com"), lines: lines, fingerprints: forged)?.matchesPublished == false)
    }

    @Test("a host this Mac already records is never offered, because a mismatch there is a changed key")
    func recordedHostIsNotOffered() async throws {
        let folder = URL(fileURLWithPath: TestScratch.unique("unifieddev-ssh"), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "known_hosts")
        try "git.example.invalid \(Self.scanned.split(separator: "\n")[1].split(separator: " ", maxSplits: 1)[1])\n"
            .write(to: file, atomically: true, encoding: .utf8)

        let offer = await KnownHosts.offer(for: SSHRemote(host: "git.example.invalid"), in: file) { _ in
            Issue.record("a recorded host was scanned")
            return (["git.example.invalid ssh-ed25519 AAAA"], ["ED25519 SHA256:x"])
        }

        #expect(offer == nil)
    }

    @Test("a Bitbucket name on another port or with a trailing dot is still held to the published fingerprints")
    func bitbucketPinnedWhateverTheName() {
        let lines = ["[bitbucket.org]:2222 ssh-ed25519 AAAA"]
        let forged = ["ED25519 SHA256:someoneElsesKeyEntirely000000000000000000"]
        let genuine = ["ED25519 SHA256:ybgmFkzwOSotHTHLJgHO0QN8L0xErw6vd0VhFA9m3SM"]

        #expect(KnownHosts.judged(remote: SSHRemote(host: "bitbucket.org", port: 2222), lines: lines, fingerprints: forged) == nil)
        #expect(KnownHosts.judged(remote: SSHRemote(host: "bitbucket.org."), lines: lines, fingerprints: forged) == nil)
        #expect(KnownHosts.judged(remote: SSHRemote(host: "altssh.bitbucket.org", port: 443), lines: lines, fingerprints: genuine) == nil)
        #expect(
            KnownHosts.judged(remote: SSHRemote(host: "bitbucket.org", port: 2222), lines: lines, fingerprints: genuine)?
                .host == "[bitbucket.org]:2222"
        )
    }

    @Test("ssh's own configuration decides the host, port and name that known_hosts is checked against")
    func resolvedByConfig() {
        let remote = SSHRemote(host: "bitbucket.org")
        let moved = "user git\nhostname altssh.bitbucket.org\nport 443\n"
        let aliased = "hostname git.internal\nport 22\nhostkeyalias gitbox\n"

        #expect(remote.resolved(byConfig: moved) == SSHRemote(host: "altssh.bitbucket.org", port: 443))
        #expect(remote.resolved(byConfig: moved).shown == "[altssh.bitbucket.org]:443")
        #expect(remote.resolved(byConfig: aliased).shown == "gitbox")
        #expect(remote.resolved(byConfig: "") == remote)
    }

    @Test("a known_hosts that is not utf-8 and lacks a final newline keeps its last line whole")
    func appendsAfterAnUnterminatedLine() throws {
        let folder = URL(fileURLWithPath: TestScratch.unique("unifieddev-ssh"), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "known_hosts")
        try (Data("old.example ssh-ed25519 AAAA ".utf8) + Data([0xFF, 0xFE])).write(to: file)

        try KnownHosts.trust(KnownHostOffer(host: "new.example", lines: ["new.example ssh-ed25519 BBBB"], fingerprints: []), in: file)

        let written = try Data(contentsOf: file)
        #expect(written.suffix(30) == Data("\nnew.example ssh-ed25519 BBBB\n".utf8))
        #expect(written.prefix(29) == Data("old.example ssh-ed25519 AAAA ".utf8))
    }

    @Test("lines that would mark a certificate authority or a revoked key are never written")
    func dropsMarkers() {
        let scan = "@cert-authority *.example.com ssh-ed25519 AAAA\nexample.com ssh-ed25519 AAAA\nexample.com ssh-ed25519 AAAA extra"
        #expect(KnownHosts.keyLines(in: scan) == ["example.com ssh-ed25519 AAAA"])
    }
}
