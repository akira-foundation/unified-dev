import Foundation
import Testing
@testable import Core

@Suite("A profile chooses its Bitbucket login apart from its GitHub one", .tags(.persistence), .scratchDirectory)
struct ProfileBitbucketChoiceTests {
    private let root = URL(filePath: "/support/GitHubLogins", directoryHint: .isDirectory)
    private let debtges = ProfileID("debtges")

    @Test("own GitHub with this Mac's Bitbucket keeps gh apart and leaves bkt on this Mac's sign-in")
    func ownGitHubThisMacBitbucket() {
        let login = ProfileGitHubLogins(sources: [debtges: .own], root: root).login(for: debtges)

        #expect(login.directory?.path == "/support/GitHubLogins/debtges")
        #expect(login.bitbucket == .thisMac)
        #expect(login.everyVariable["BKT_CONFIG_DIR"] == nil)
        #expect(login.everyVariable["GH_CONFIG_DIR"] == "/support/GitHubLogins/debtges")
    }

    @Test("this Mac's GitHub with its own Bitbucket keeps gh on this Mac and gives bkt the profile's directory")
    func thisMacGitHubOwnBitbucket() {
        let login = ProfileGitHubLogins(bitbucketSources: [debtges: .own], root: root).login(for: debtges)

        #expect(login.directory == nil)
        #expect(!login.ownsGitHub)
        #expect(login.variables.isEmpty)
        #expect(login.bitbucket.directory?.path == "/support/BitbucketLogins/debtges")
        #expect(login.applied(to: ["GH_TOKEN": "mine"]) == ["GH_TOKEN": "mine"])
    }

    @Test("Unified always uses this Mac's account on both hosts")
    func initialInherits() {
        let logins = ProfileGitHubLogins(sources: [.initial: .own], bitbucketSources: [.initial: .own], root: root)

        #expect(logins.source(of: .initial, on: .bitbucket) == .inherits)
        #expect(logins.login(for: .initial) == .thisMac)
    }

    @Test("a directory nobody can place is signed out on Bitbucket too once any profile keeps its own")
    func unresolvedCountsBitbucket() {
        let logins = ProfileGitHubLogins(bitbucketSources: [debtges: .own], root: root)

        #expect(logins.unresolved.bitbucket.directory?.path == "/support/BitbucketLogins/.unresolved")
        #expect(ProfileGitHubLogins(root: root).unresolved == .thisMac)
    }

    @Test("the choice is stored per host and survives reopening")
    func storedApart() async throws {
        let store = try makeTestStore("bitbucket-choice")
        let profile = try await store.createProfile(name: "Debtges", colour: Accent.all[1], symbol: "star")
        try await store.setSource(.own, for: profile.id, on: .bitbucket)

        let reopened = try Store(path: store.path)
        #expect(reopened.gitHubLogins().source(of: profile.id, on: .bitbucket) == .own)
        #expect(reopened.gitHubLogins().source(of: profile.id, on: .gitHub) == .inherits)
        #expect(!reopened.gitHubLogin(for: profile.id).ownsGitHub)
        #expect(reopened.gitHubLogin(for: profile.id).bitbucket.isOwn)

        try await reopened.setSource(.own, for: .initial, on: .bitbucket)
        #expect(reopened.gitHubLogin(for: .initial) == .thisMac)
    }

    @Test("a database from before keeps every profile's Bitbucket where its GitHub choice put it")
    func migrationCopiesTheGitHubChoice() async throws {
        let first = try makeTestStore("bitbucket-choice-before")
        let own = try await first.createProfile(name: "Debtges", colour: Accent.all[1], symbol: "star")
        let shared = try await first.createProfile(name: "Akira", colour: Accent.all[2], symbol: "leaf")
        try await first.setGitHubSource(.own, for: own.id)
        let raw = try SQLiteDatabase(path: first.path)
        let version = try raw.readUserVersion()
        try raw.execute("ALTER TABLE profiles DROP COLUMN \(ProfileBitbucketColumn.column);")
        try raw.setUserVersion(version - 1)

        let reopened = try Store(path: first.path)
        #expect(reopened.gitHubLogins().source(of: own.id, on: .bitbucket) == .own)
        #expect(reopened.gitHubLogins().source(of: shared.id, on: .bitbucket) == .inherits)
        #expect(reopened.gitHubLogin(for: own.id).bitbucket.isOwn)
    }
}
