import Testing
import Foundation
@testable import Core

@Suite("Spend accounts")
struct SpendAccountsTests {
    private let defaultClaude = AgentAccountHome.defaultHome(
        for: .claudeCode, home: URL(filePath: "/Users/someone")
    )!
    private let defaultCodex = AgentAccountHome.defaultHome(
        for: .codex, home: URL(filePath: "/Users/someone")
    )!
    private let workClaude = claudeHome(id: "work", at: "/support/AgentAccounts/claudeCode/work")

    private func attribute(_ path: String, among accounts: [AgentAccountHome]) -> AgentAccountID? {
        SpendAccountAttribution(accounts: accounts).accountID(ofFile: path)
    }

    private static func claudeHome(id: String, at path: String) -> AgentAccountHome {
        AgentAccountHome(
            provider: .claudeCode,
            id: AgentAccountID(id),
            directory: URL(filePath: path, directoryHint: .isDirectory),
            isDefault: false
        )
    }

    @Test func aTranscriptIsAttributedToTheAccountDirectoryItSitsUnder() {
        let id = attribute("/Users/someone/.claude/projects/-a-b/x.jsonl", among: [defaultClaude, workClaude])
        #expect(id == defaultClaude.id)
    }

    @Test func theLongestMatchingDirectoryWinsWhenOneAccountSitsInsideAnother() {
        let outer = Self.claudeHome(id: "outer", at: "/support/AgentAccounts/claudeCode")
        let inner = Self.claudeHome(id: "inner", at: "/support/AgentAccounts/claudeCode/inner")
        let id = attribute("/support/AgentAccounts/claudeCode/inner/projects/-a/x.jsonl", among: [outer, inner])
        #expect(id == inner.id)
    }

    @Test func aTranscriptOutsideEveryKnownAccountIsNotAttributed() {
        #expect(attribute("/elsewhere/x.jsonl", among: [defaultClaude]) == nil)
    }

    @Test func aSiblingDirectorySharingAPrefixIsNotTheAccountDirectory() {
        let id = attribute("/Users/someone/.claude-work/projects/x.jsonl", among: [defaultClaude])
        #expect(id == nil)
    }

    @Test func aTranscriptReachedThroughASymlinkedAccountDirectoryStillMatches() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "spend-accounts-\(UUID().uuidString)", directoryHint: .isDirectory)
        let real = root.appending(path: "dotfiles", directoryHint: .isDirectory)
        let link = root.appending(path: "link", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: real.appending(path: "projects", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: root) }

        let account = Self.claudeHome(id: "linked", at: link.path)
        let id = attribute(real.appending(path: "projects/x.jsonl").path, among: [account])
        #expect(id == account.id)
    }

    @Test func theDirectoriesAreSettledWhenTheAttributionIsBuiltAndNotOnceForEveryFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "spend-settle-\(UUID().uuidString)", directoryHint: .isDirectory)
        let first = root.appending(path: "first", directoryHint: .isDirectory)
        let second = root.appending(path: "second", directoryHint: .isDirectory)
        let link = root.appending(path: "link", directoryHint: .isDirectory)
        for directory in [first, second] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: first)
        defer { try? FileManager.default.removeItem(at: root) }

        let account = Self.claudeHome(id: "linked", at: link.path)
        let attribution = SpendAccountAttribution(accounts: [account])
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: second)

        #expect(attribution.accountID(ofFile: first.appending(path: "projects/x.jsonl").path) == account.id)
        #expect(attribution.accountID(ofFile: second.appending(path: "projects/x.jsonl").path) == nil)
    }

    @Test func sourcesCarryOneRootPerAccount() {
        let sources = TranscriptSources.sources(accounts: [defaultClaude, workClaude, defaultCodex])
        #expect(sources.count == 3)
        #expect(Set(sources.filter { $0.provider == .claudeCode }.map(\.home))
            == [defaultClaude.directory, workClaude.directory])
        #expect(sources.first { $0.home == defaultCodex.directory }?.root.lastPathComponent == "sessions")
    }

    @Test func aProviderWithoutATranscriptLayoutContributesNoSource() {
        let grok = AgentAccountHome.defaultHome(for: .grok, home: URL(filePath: "/Users/someone"))!
        #expect(TranscriptSources.sources(accounts: [grok]).isEmpty)
    }

    @Test func theDefaultHomesAreTheDirectoriesTheIndexerReads() {
        let home = URL(filePath: "/Users/someone")
        let homes = SpendAccounts.defaultHomes(home: home)
        let sources = TranscriptSources.sources(provider: home)
        #expect(homes.map(\.directory) == sources.map(\.home))
        #expect(homes.map(\.id) == sources.map { AgentAccountHome.defaultID(for: $0.provider) })
        let allDefault = homes.allSatisfy { $0.isDefault }
        #expect(allDefault)
    }
}
