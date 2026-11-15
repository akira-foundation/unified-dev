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
        256 SHA256:exampleEd25519FingerprintNotARealHostKey000 ssh.bitbucket.org (ED25519)
        256 SHA256:exampleEcdsaFingerprintNotARealHostKey00000 ssh.bitbucket.org (ECDSA)
        """

    @Test(
        "every ssh address names its host, and https or a path names none",
        arguments: [
            ("git@ssh.bitbucket.org:debtges/ledger.git", SSHRemote(host: "ssh.bitbucket.org")),
            ("ssh://git@bitbucket.org/debtges/ledger.git", SSHRemote(host: "bitbucket.org")),
            ("ssh://git@git.example.com:7999/team/app.git", SSHRemote(host: "git.example.com", port: 7999)),
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
            "ED25519 SHA256:exampleEd25519FingerprintNotARealHostKey000",
            "ECDSA SHA256:exampleEcdsaFingerprintNotARealHostKey00000",
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
}
