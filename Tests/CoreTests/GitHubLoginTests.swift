import Testing
import Foundation
@testable import Core

@Suite("A profile's GitHub login", .scratchDirectory)
struct GitHubLoginTests {
    private let root = URL(filePath: "/support/GitHubLogins", directoryHint: .isDirectory)
    private let debtges = ProfileID("debtges")

    @Test func unifiedAlwaysUsesThisMacsLogin() {
        let logins = ProfileGitHubLogins(sources: [.initial: .own], root: root)
        #expect(logins.source(of: .initial) == .inherits)
        #expect(logins.login(for: .initial) == .thisMac)
    }

    @Test func aProfileUsesUnifiedsLoginUntilToldOtherwise() {
        let logins = ProfileGitHubLogins(root: root)
        #expect(logins.source(of: debtges) == .inherits)
        #expect(logins.login(for: debtges) == .thisMac)
        #expect(logins.login(for: nil) == .thisMac)
    }

    @Test func aProfileWithItsOwnLoginHasADirectoryNamedAfterIt() {
        let logins = ProfileGitHubLogins(sources: [debtges: .own], root: root)
        let login = logins.login(for: debtges)
        #expect(login == .profile(debtges, directory: root.appending(path: "debtges", directoryHint: .isDirectory)))
        #expect(login.directory?.path == "/support/GitHubLogins/debtges")
    }

    @Test func thisMacsLoginLeavesTheEnvironmentAlone() {
        let inherited = ["GH_TOKEN": "inherited", "PATH": "/bin"]
        #expect(GitHubLogin.thisMac.variables.isEmpty)
        #expect(GitHubLogin.thisMac.applied(to: inherited) == inherited)
    }

    @Test func anOwnLoginWithNoSessionNamesItsDirectoryAndRefusesEveryOtherToken() {
        let login = GitHubLogin.profile(debtges, directory: root.appending(path: "debtges"))
        let variables = login.variables
        #expect(variables["GH_CONFIG_DIR"] == "/support/GitHubLogins/debtges")
        #expect(variables["GH_TOKEN"] == GitHubLogin.signedOutToken)
        #expect(variables["GH_ENTERPRISE_TOKEN"] == GitHubLogin.signedOutToken)
        for name in ["GITHUB_TOKEN", "GITHUB_ENTERPRISE_TOKEN"] {
            #expect(variables[name] == "")
        }

        let inherited = ["GH_TOKEN": "a", "GITHUB_TOKEN": "b", "GH_ENTERPRISE_TOKEN": "c", "PATH": "/bin"]
        #expect(login.applied(to: inherited) == [
            "GH_CONFIG_DIR": "/support/GitHubLogins/debtges", "GH_TOKEN": GitHubLogin.signedOutToken,
            "GH_ENTERPRISE_TOKEN": GitHubLogin.signedOutToken, "PATH": "/bin",
        ])
        #expect(login.signInEnvironment(from: inherited) == ["GH_CONFIG_DIR": "/support/GitHubLogins/debtges", "PATH": "/bin"])
    }

    @Test func anOwnLoginLetsGhReadItsOwnFileOnlyForTheHostItIsSignedInTo() throws {
        let directory = URL(filePath: TestScratch.unique("signed-in-profile"), directoryHint: .isDirectory)
        let login = GitHubLogin.profile(debtges, directory: directory)
        try login.prepare()
        let hosts = directory.appending(path: "hosts.yml")
        try "github.com:\n    oauth_token: \"\"\n    user: client-bot\n".write(to: hosts, atomically: true, encoding: .utf8)
        #expect(login.hostsHoldingTokens.isEmpty)

        try "github.com:\n    users:\n        client-bot:\n            oauth_token: not-a-real-token\n"
            .appending("    oauth_token: not-a-real-token\n    user: client-bot\n")
            .write(to: hosts, atomically: true, encoding: .utf8)
        #expect(login.hostsHoldingTokens == ["github.com"])
        #expect(login.variables["GH_TOKEN"] == "")
        #expect(login.variables["GH_ENTERPRISE_TOKEN"] == GitHubLogin.signedOutToken)
        #expect(login.applied(to: ["GH_TOKEN": "a", "PATH": "/bin"]) == [
            "GH_CONFIG_DIR": directory.path, "GH_ENTERPRISE_TOKEN": GitHubLogin.signedOutToken, "PATH": "/bin",
        ])

        try "git.example.com:\n    oauth_token: not-a-real-token\n    user: client-bot\n"
            .write(to: hosts, atomically: true, encoding: .utf8)
        #expect(login.hostsHoldingTokens == ["git.example.com"])
        #expect(login.variables["GH_TOKEN"] == GitHubLogin.signedOutToken)
        #expect(login.variables["GH_ENTERPRISE_TOKEN"] == "")
    }

    @Test func theSignInCommandToCopyNamesTheProfilesDirectory() {
        let login = GitHubLogin.profile(debtges, directory: URL(filePath: "/support/it's here", directoryHint: .isDirectory))
        #expect(login.signInCommand == #"GH_CONFIG_DIR='/support/it'\''s here' gh auth login --insecure-storage"#)
        #expect(login.signInArguments == ["auth", "login", "--insecure-storage"])
        #expect(GitHubLogin.thisMac.signInArguments == ["auth", "login"])
        #expect(GitHubLogin.thisMac.signInCommand == "gh auth login")
    }

    @Test func aDirectoryBelongsToTheProfileOfTheWorkspaceOrProjectHoldingIt() {
        let routes = GitHubLoginRoutes(routes: [
            .init(path: "/code/site", profile: debtges),
            .init(path: "/code/app", profile: .initial),
            .init(path: "/worktrees/debtges/site/w", profile: debtges),
        ])

        #expect(routes.profile(forDirectory: "/code/site") == debtges)
        #expect(routes.profile(forDirectory: "/code/site/Sources/") == debtges)
        #expect(routes.profile(forDirectory: "/worktrees/debtges/site/w") == debtges)
        #expect(routes.profile(forDirectory: "/code/app") == .initial)
        #expect(routes.profile(forDirectory: "/code/site-2") == nil)
        #expect(routes.profile(forDirectory: "/elsewhere") == nil)
        #expect(routes.profile(forDirectory: "") == nil)
    }

    @Test func anUnreadableRouteRefusesRatherThanUseThisMacsLoginOnceAProfileHasItsOwn() {
        #expect(ProfileGitHubLogins(sources: [debtges: .inherits], root: root).unresolved == .thisMac)

        let unresolved = ProfileGitHubLogins(sources: [debtges: .own], root: root).unresolved
        #expect(unresolved.directory?.path == "/support/GitHubLogins/.unresolved")
        #expect(unresolved.variables["GH_TOKEN"] == GitHubLogin.signedOutToken)
        #expect(!unresolved.acceptsSignIn)
        #expect(GitHubLogin.thisMac.acceptsSignIn)
    }

    @Test func preparingCreatesOnlyAProfilesOwnFolder() throws {
        let scratch = URL(filePath: TestScratch.unique("github-prepare"), directoryHint: .isDirectory)
        let unresolved = GitHubLogin.unresolved(directory: scratch.appending(path: ".unresolved"))
        try unresolved.prepare()
        #expect(!FileManager.default.fileExists(atPath: scratch.appending(path: ".unresolved").path))

        let own = GitHubLogin.profile(debtges, directory: scratch.appending(path: "debtges"))
        try own.prepare()
        let attributes = try FileManager.default.attributesOfItem(atPath: scratch.appending(path: "debtges").path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test func aPathSpelledInAnotherCaseFindsItsProjectOnADiskThatIgnoresCase() throws {
        let real = URL(filePath: TestScratch.unique("Cased-Site")).resolvingSymlinksInPath().path
        try FileManager.default.createDirectory(atPath: real + "/Sources", withIntermediateDirectories: true)
        let ignoresCase = (try URL(filePath: real).resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))
            .volumeSupportsCaseSensitiveNames == false
        let routes = GitHubLoginRoutes(routes: [.init(path: real, profile: debtges)])
        let respelled = real.lowercased() + "/sources"
        #expect(routes.profile(forDirectory: respelled) == (ignoresCase ? debtges : nil))
    }

    @Test func theDeepestPathDecidesWhenOneHoldsAnother() {
        let routes = GitHubLoginRoutes(routes: [
            .init(path: "/code", profile: .initial),
            .init(path: "/code/site/", profile: debtges),
        ])
        #expect(routes.profile(forDirectory: "/code/site/w") == debtges)
        #expect(routes.profile(forDirectory: "/code/other") == .initial)
    }

    @Test func theFootnoteSaysWhichLoginAProfileUses() {
        let unified = ProfileGitHubWording.footnote(source: .inherits, isInitial: true, profileName: "Unified", user: nil)
        #expect(unified.contains("this Mac's GitHub CLI login") && unified.contains("signed out"))

        let inherits = ProfileGitHubWording.footnote(source: .inherits, isInitial: false, profileName: "Debtges", user: "octo")
        #expect(inherits.contains("Unified's GitHub login") && inherits.contains("octo"))

        let signedOut = ProfileGitHubWording.footnote(source: .own, isInitial: false, profileName: "Debtges", user: nil)
        #expect(signedOut.contains("never use this Mac's login"))

        let own = ProfileGitHubWording.footnote(source: .own, isInitial: false, profileName: "Debtges", user: "client-bot")
        #expect(own.contains("run as client-bot"))
    }
}
