import Testing
import Foundation
@testable import Core

@Suite("Default Claude identity")
struct DefaultClaudeIdentityTests {
    private final class Home {
        let url: URL

        init() throws {
            url = FileManager.default.temporaryDirectory
                .appending(path: "default-claude-identity-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: url) }

        func directory(_ name: String) throws -> URL {
            let directory = url.appending(path: name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }

        func identity(_ email: String, at file: URL) throws {
            try Data(#"{"oauthAccount":{"emailAddress":"\#(email)"}}"#.utf8).write(to: file)
        }
    }

    private func defaultClaude(home: URL, environment: [String: String]) throws -> AgentAccountHome {
        try #require(SpendAccounts.defaultHomes(home: home, environment: environment)
            .first { $0.provider == .claudeCode })
    }

    private func email(of account: AgentAccountHome) -> String? {
        AgentAccountIdentities.read([account])[account.id]?.email
    }

    @Test func aConfigDirectoryFromTheEnvironmentKeepsItsIdentityInsideItself() throws {
        let home = try Home()
        let alternate = try home.directory(".claude-alt")
        try home.identity("home@identity.example", at: home.url.appending(path: ".claude.json"))
        try home.identity("alternate@identity.example", at: alternate.appending(path: ".claude.json"))

        let account = try defaultClaude(home: home.url, environment: ["CLAUDE_CONFIG_DIR": alternate.path])

        #expect(TranscriptHome.isSame(account.directory, as: alternate))
        #expect(account.identityPath == alternate.appending(path: ".claude.json"))
        #expect(email(of: account) == "alternate@identity.example")
    }

    @Test func aConfigDirectoryNamedClaudeOutsideTheHomeStillKeepsItsIdentityInsideItself() throws {
        let home = try Home()
        let elsewhere = try home.directory("elsewhere")
        let named = try home.directory("elsewhere/.claude")
        try home.identity("parent@identity.example", at: elsewhere.appending(path: ".claude.json"))
        try home.identity("named@identity.example", at: named.appending(path: ".claude.json"))
        let user = try home.directory("user")

        let account = try defaultClaude(home: user, environment: ["CLAUDE_CONFIG_DIR": named.path])

        #expect(email(of: account) == "named@identity.example")
    }

    @Test func theCliOwnDirectoryKeepsItsIdentityBesideItInTheHome() throws {
        let home = try Home()
        let own = try home.directory(".claude")
        try home.identity("home@identity.example", at: home.url.appending(path: ".claude.json"))
        try home.identity("stale@identity.example", at: own.appending(path: ".claude.json"))

        let account = try defaultClaude(home: home.url, environment: [:])

        #expect(account.identityPath == home.url.appending(path: ".claude.json"))
        #expect(email(of: account) == "home@identity.example")
    }

    @Test func theCliOwnDirectoryNamedThroughTheEnvironmentStillReadsTheHome() throws {
        let home = try Home()
        let own = try home.directory(".claude")
        try home.identity("home@identity.example", at: home.url.appending(path: ".claude.json"))

        let account = try defaultClaude(home: home.url, environment: ["CLAUDE_CONFIG_DIR": own.path + "/"])

        #expect(email(of: account) == "home@identity.example")
    }
}
