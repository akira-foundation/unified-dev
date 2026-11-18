import Testing
import Foundation
@testable import Core

@Suite("Settings offer only the output styles every profile has", .tags(.persistence), .scratchDirectory)
struct AppWideOutputStyleTests {
    private func macLogin() throws -> SlashCommandTests.Tree {
        let tree = try SlashCommandTests.Tree()
        try tree.write(".claude/output-styles/mac.md", "---\nname: MacStyle\ndescription: Mac\n---\n")
        return tree
    }

    private func reading(_ store: Store) async throws -> AppWideOutputStyles {
        try await AppWideOutputStyles(accounts: store.agentAccountChoices().accounts, profiles: store.profiles())
    }

    private func settingsStyles(_ tree: SlashCommandTests.Tree, store: Store) async throws -> [String] {
        let defaults = AgentKind.allCases.compactMap { AgentAccountHome.defaultHome(for: $0, home: URL(filePath: tree.home)) }
        let account = try #require(AppWideOutputStyles.claudeAccount(in: defaults))
        return try await OutputStyleIndex.discover(
            home: tree.home, project: nil, claudeHome: account.directory.path, refusing: reading(store).refused
        ).map(\.name)
    }

    private func profile(_ store: Store, _ accounts: ProfileAccountSource) async throws -> Profile {
        try await store.createProfile(
            name: "P\(UUID().uuidString.prefix(6))", colour: Accent.all[1], symbol: "star", accounts: accounts
        )
    }

    @Test("with only the initial profile, Settings offer the default account's styles")
    func theInitialProfileReadsTheMacStyles() async throws {
        let tree = try macLogin()
        let store = try makeTestStore("app-wide-initial")

        let read = try await settingsStyles(tree, store: store)

        #expect(read.contains("MacStyle"))
        #expect(read.contains(OutputStyle.defaultName))
    }

    @Test("when every profile inherits, Settings offer the default account's styles")
    func everyHeirReadsTheMacStyles() async throws {
        let tree = try macLogin()
        let store = try makeTestStore("app-wide-heirs")
        _ = try await profile(store, .inherits)
        _ = try await profile(store, .inherits)

        let read = try await settingsStyles(tree, store: store)

        #expect(read.contains("MacStyle"))
    }

    @Test("a profile that keeps its own accounts leaves the Mac's styles out of Settings, wherever it sorts")
    func anOwnProfileRefusesTheMacStyles() async throws {
        let tree = try macLogin()
        let first = try makeTestStore("app-wide-own-first")
        _ = try await profile(first, .own)
        _ = try await profile(first, .inherits)
        let last = try makeTestStore("app-wide-own-last")
        _ = try await profile(last, .inherits)
        _ = try await profile(last, .own)

        let ownFirst = try await settingsStyles(tree, store: first)
        let ownLast = try await settingsStyles(tree, store: last)

        #expect(!ownFirst.contains("MacStyle"))
        #expect(!ownLast.contains("MacStyle"))
        #expect(ownLast.contains(OutputStyle.defaultName))
    }

    @Test("an own profile that is deleted no longer refuses, while another own profile still does")
    func aDeletedProfileIsNotCounted() async throws {
        let tree = try macLogin()
        let store = try makeTestStore("app-wide-deleted")
        let one = try await profile(store, .own)
        let other = try await profile(store, .own)

        try await store.deleteProfile(id: one.id)
        let oneGone = try await settingsStyles(tree, store: store)
        try await store.deleteProfile(id: other.id)
        let bothGone = try await settingsStyles(tree, store: store)

        #expect(!oneGone.contains("MacStyle"))
        #expect(bothGone.contains("MacStyle"))
    }

    @Test("an own profile that turns to inheriting stops refusing")
    func aProfileThatInheritsStopsRefusing() async throws {
        let tree = try macLogin()
        let store = try makeTestStore("app-wide-switch")
        let own = try await profile(store, .own)
        let before = try await settingsStyles(tree, store: store)

        try await store.setAccountSource(.inherits, for: own.id)
        let after = try await settingsStyles(tree, store: store)

        #expect(!before.contains("MacStyle"))
        #expect(after.contains("MacStyle"))
    }

    @Test("the Settings copy names the styles it offers")
    func theCopyFollowsTheReading() async throws {
        let shared = try makeTestStore("app-wide-copy-shared")
        let unshared = try makeTestStore("app-wide-copy-unshared")
        _ = try await profile(unshared, .own)

        let offering = try await reading(shared)
        let refusing = try await reading(unshared)

        #expect(offering.offersDefaultAccountStyles)
        #expect(offering.settingsFooter.hasPrefix("These are the output styles of the default Claude Code account"))
        #expect(offering.presetLabel == "From the default Claude Code account")
        #expect(!refusing.offersDefaultAccountStyles)
        #expect(refusing.settingsFooter.hasPrefix("Only the built-in output styles are offered"))
        #expect(refusing.presetLabel == "Built-in styles and the current choice")
    }

    @Test("Settings read the default account of Claude Code and no other agent's")
    func theClaudeAccountIsPicked() throws {
        let home = URL(filePath: "/tmp/home.example")
        let defaults = [AgentKind.codex, .claudeCode].compactMap { AgentAccountHome.defaultHome(for: $0, home: home) }

        let picked = AppWideOutputStyles.claudeAccount(in: defaults)

        #expect(picked?.provider == .claudeCode)
        #expect(AppWideOutputStyles.claudeAccount(in: defaults.filter { $0.provider != .claudeCode }) == nil)
    }
}
