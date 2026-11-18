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

    private func settingsStyles(_ tree: SlashCommandTests.Tree, store: Store) async throws -> [String] {
        let refused = try await store.profileAccounts().appWideRefusals(across: store.profiles())
        return OutputStyleIndex.discover(
            home: tree.home, project: nil, claudeHome: "\(tree.home)/.claude", refusing: refused
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

    @Test("a profile that keeps its own accounts leaves the Mac's styles out of Settings")
    func anOwnProfileRefusesTheMacStyles() async throws {
        let tree = try macLogin()
        let store = try makeTestStore("app-wide-own")
        _ = try await profile(store, .inherits)
        _ = try await profile(store, .own)

        let read = try await settingsStyles(tree, store: store)

        #expect(!read.contains("MacStyle"))
        #expect(read.contains(OutputStyle.defaultName))
    }

    @Test("an own profile that is deleted no longer refuses anything")
    func aDeletedProfileIsNotCounted() async throws {
        let tree = try macLogin()
        let store = try makeTestStore("app-wide-deleted")
        let own = try await profile(store, .own)
        let before = try await settingsStyles(tree, store: store)

        try await store.deleteProfile(id: own.id)
        let after = try await settingsStyles(tree, store: store)

        #expect(!before.contains("MacStyle"))
        #expect(after.contains("MacStyle"))
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
}
