import Foundation
import Testing
@testable import Core

@Suite("git asks our helper for bitbucket.org and nobody else", .tags(.git, .subprocess))
struct BitbucketCredentialHelperGitTests {
    private func fixture() throws -> (shim: String, environment: [String: String]) {
        let folder = TestScratch.unique("unifieddev-credential-helper")
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let shim = (folder as NSString).appendingPathComponent("bridge")
        let script = """
            #!/bin/sh
            [ "$1" = "git-credential" ] && [ "$2" = "get" ] || exit 0
            path=$(grep '^path=' | cut -d= -f2)
            printf 'username=x-token-auth\\npassword=from-helper-%s\\n' "$path"
            """
        try script.write(toFile: shim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: shim)
        let global = (folder as NSString).appendingPathComponent("gitconfig")
        try "[credential]\n\thelper = \"!f() { printf 'username=mine\\\\npassword=keychain\\\\n'; }; f\"\n"
            .write(toFile: global, atomically: true, encoding: .utf8)
        let base = ["GIT_CONFIG_GLOBAL": global, "GIT_CONFIG_NOSYSTEM": "1", "GIT_TERMINAL_PROMPT": "0"]
        let helper = BitbucketCredentialHelper.gitEnvironment(shim: shim, over: base)
        return (shim, base.merging(helper) { _, ours in ours })
    }

    private func fill(_ request: String, environment: [String: String]) async throws -> String {
        let result = try await Shell.run("git", ["credential", "fill"], env: environment, stdin: request)
        try #require(result.ok)
        return result.stdout
    }

    @Test("bitbucket.org over https is answered by the shim alone, with the repository's path")
    func bitbucketIsOurs() async throws {
        let (_, environment) = try fixture()

        let filled = try await fill("protocol=https\nhost=bitbucket.org\npath=debtges/ledger.git\n\n", environment: environment)

        #expect(filled.contains("username=x-token-auth\n"))
        #expect(filled.contains("password=from-helper-debtges/ledger.git\n"))
    }

    @Test("every other host keeps the helpers this Mac already had")
    func otherHostsAreUntouched() async throws {
        let (_, environment) = try fixture()

        let filled = try await fill("protocol=https\nhost=github.com\n\n", environment: environment)

        #expect(filled.contains("username=mine\n"))
        #expect(filled.contains("password=keychain\n"))
    }

    @Test("entries already in GIT_CONFIG_COUNT are kept and ours follow them")
    func appendsAfterExistingEntries() {
        let inherited = ["GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "core.editor", "GIT_CONFIG_VALUE_0": "true"]

        let helper = BitbucketCredentialHelper.gitEnvironment(shim: "/Applications/Unified Dev.app/bridge", over: inherited)

        #expect(helper["GIT_CONFIG_COUNT"] == "4")
        #expect(helper["GIT_CONFIG_KEY_0"] == nil)
        #expect(helper["GIT_CONFIG_KEY_1"] == "credential.https://bitbucket.org.helper")
        #expect(helper["GIT_CONFIG_VALUE_1"] == "")
        #expect(helper["GIT_CONFIG_VALUE_2"] == "!'/Applications/Unified Dev.app/bridge' git-credential")
    }

    @Test("no token is ever placed in the environment or on a command line")
    func carriesNoSecret() {
        let helper = BitbucketCredentialHelper.gitEnvironment(shim: "/tmp/bridge", over: [:])

        #expect(helper.values.allSatisfy { !$0.contains("password") && !$0.contains("token") })
    }
}
