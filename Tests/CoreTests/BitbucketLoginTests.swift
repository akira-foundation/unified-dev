import Foundation
import Testing
@testable import Core

@Suite("A profile's own Bitbucket sign-in")
struct BitbucketLoginTests {
    private static let profile = ProfileID("debtges")

    private func own(root: String = "/support") -> GitHubLogin {
        .profile(Self.profile, directory: URL(filePath: root).appending(path: "GitHubLogins/debtges"))
    }

    @Test("this Mac's sign-in adds nothing, so bkt reads its own config and the Keychain")
    func thisMacIsUntouched() {
        #expect(BitbucketLogin.thisMac.variables.isEmpty)
        #expect(GitHubLogin.thisMac.bitbucket == .thisMac)
        #expect(!BitbucketLogin.thisMac.signInArguments(.browser).contains("--allow-insecure-store"))
    }

    @Test("a profile with its own sign-ins gets its own bkt directory beside the GitHub one")
    func profileDirectory() {
        let login = own().bitbucket

        #expect(login.directory?.path == "/support/BitbucketLogins/debtges")
        #expect(login.variables["BKT_CONFIG_DIR"] == "/support/BitbucketLogins/debtges")
        #expect(login.variables["KEYRING_BACKEND"] == "file")
        #expect(login.variables["KEYRING_FILE_DIR"] == "/support/BitbucketLogins/debtges/secrets")
        #expect(login.variables["BKT_TOKEN"] == "")
        #expect(login.variables["BKT_HOST"] == "")
    }

    @Test("an unresolved login gives an empty bkt directory, so nothing reads this Mac's account")
    func unresolvedIsSignedOut() {
        let unresolved = GitHubLogin.unresolved(directory: URL(filePath: "/support/GitHubLogins/.unresolved"))

        #expect(unresolved.bitbucket.directory?.path == "/support/BitbucketLogins/.unresolved")
    }

    @Test("an agent's environment carries the profile's Bitbucket sign-in with its GitHub one")
    func agentsCarryBoth() {
        #expect(own().variables["BKT_CONFIG_DIR"] == nil)
        #expect(GitHubLogin.thisMac.everySignIn(appliedTo: ["BKT_TOKEN": "mine"]) == ["BKT_TOKEN": "mine"])
        let variables = own().everyVariable

        #expect(variables["GH_CONFIG_DIR"] == "/support/GitHubLogins/debtges")
        #expect(variables["BKT_CONFIG_DIR"] == "/support/BitbucketLogins/debtges")
    }

    @Test("a token inherited from the shell never reaches a profile with its own sign-in")
    func inheritedTokenIsDropped() {
        let applied = own().everySignIn(appliedTo: [
            "BKT_TOKEN": "leaked", "BKT_USERNAME": "someone", "PATH": "/bin",
            "KEYRING_FILE_PASSWORD": "shell", "KEYRING_PASSWORD": "shell",
        ])

        #expect(applied["BKT_TOKEN"] == nil)
        #expect(applied["KEYRING_FILE_PASSWORD"] == nil)
        #expect(applied["KEYRING_PASSWORD"] == nil)
        #expect(applied["BKT_USERNAME"] == nil)
        #expect(applied["PATH"] == "/bin")
        #expect(applied["BKT_CONFIG_DIR"] == "/support/BitbucketLogins/debtges")

        let terminal = BitbucketSignIn.environment(["BKT_TOKEN": "leaked"], login: own().bitbucket)
        #expect(terminal["BKT_TOKEN"] == nil)
        #expect(terminal["KEYRING_BACKEND"] == "file")
    }

    @Test("sign-in offers the browser and an API token, and stores them in the profile's file")
    func signInArguments() {
        let login = own().bitbucket

        #expect(login.signInArguments(.browser) == [
            "auth", "login", "https://bitbucket.org", "--kind", "cloud", "--web", "--allow-insecure-store",
        ])
        #expect(login.signInArguments(.apiToken).contains("--web-token"))
    }

    @Test("preparing writes a passphrase only the owner can read, once, and the variables carry it")
    func preparesPassphrase() throws {
        let root = TestScratch.unique("bitbucket-login")
        let login = own(root: root).bitbucket
        let directory = try #require(login.directory)

        #expect(login.variables["BKT_KEYRING_PASSPHRASE"] == nil)
        try login.prepare()
        let first = try #require(login.variables["BKT_KEYRING_PASSPHRASE"])
        let secrets = directory.appending(path: "secrets").path
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: secrets)
        try login.prepare()

        #expect(login.variables["BKT_KEYRING_PASSPHRASE"] == first)
        #expect(first.count >= 40)
        let file = directory.appending(path: "passphrase").path
        let permissions = try FileManager.default.attributesOfItem(atPath: file)[.posixPermissions] as? Int
        let folder = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        #expect(folder == 0o700)
        #expect(try FileManager.default.attributesOfItem(atPath: secrets)[.posixPermissions] as? Int == 0o700)
    }

    @Test("the account names the method bkt reports, and never a secret")
    func accountMethod() {
        let status = BitbucketAuthStatus.decode("""
        {"hosts": [{"key": "api.bitbucket.org", "kind": "cloud", "username": "kid",
          "auth_method": "basic", "token_source": "keyring"}], "contexts": []}
        """)

        #expect(status?.cloudHost?.username == "kid")
        #expect(BitbucketAccount(user: "kid", method: "basic").methodName == "API token")
        #expect(BitbucketAccount(user: "kid", method: "oauth").methodName == "Browser sign-in (OAuth)")
        #expect(BitbucketAccount(user: nil, method: nil).methodName == nil)
    }
}
