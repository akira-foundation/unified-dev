import Foundation
import Testing
@testable import Core

private actor RenewedWorkspace {
    var name: String?

    func record(_ workspace: String?) { name = workspace }
}

@Suite("The Bitbucket sign-in handed to git")
struct BitbucketGitCredentialTests {
    private func secrets(holding sealed: String) throws -> URL {
        let folder = URL(fileURLWithPath: TestScratch.unique("unifieddev-bkt-secrets"), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try sealed.write(
            to: folder.appending(path: "host%2Fapi.bitbucket.org%2Ftoken"), atomically: true, encoding: .utf8
        )
        return folder
    }

    private func profile(holding sealed: String) throws -> [String: String] {
        [
            "BKT_CONFIG_DIR": TestScratch.unique("unifieddev-bkt-config"),
            "KEYRING_FILE_DIR": try secrets(holding: sealed).path,
            "BKT_KEYRING_PASSPHRASE": BitbucketTokenFixtures.passphrase,
        ]
    }

    private let request = "protocol=https\nhost=bitbucket.org\npath=debtges/ledger.git\n"

    @Test("an OAuth sign-in written by bkt's own store opens to its access token")
    func opensTheOAuthStore() throws {
        let credential = try #require(
            BitbucketGitCredential.read(sealed: BitbucketTokenFixtures.oauth, passphrase: BitbucketTokenFixtures.passphrase)
        )

        #expect(credential.password == "fixture-access-token")
        #expect(credential.expiresAt == BitbucketDates.parse("2030-01-02T03:04:05.123Z"))
    }

    @Test("an API token is handed over as it was stored, with no expiry")
    func opensTheAPIToken() throws {
        let credential = try #require(
            BitbucketGitCredential.read(sealed: BitbucketTokenFixtures.apiToken, passphrase: BitbucketTokenFixtures.passphrase)
        )

        #expect(credential.password == "fixture-api-token")
        #expect(credential.expiresAt == nil)
    }

    @Test("the wrong passphrase opens nothing")
    func refusesAWrongPassphrase() {
        #expect(BitbucketGitCredential.read(sealed: BitbucketTokenFixtures.oauth, passphrase: "not-it") == nil)
    }

    @Test("git is answered with x-token-auth and the profile's token")
    func answersGit() async throws {
        let answer = await BitbucketCredentialHelper.answer(
            action: "get", request: request, environment: try profile(holding: BitbucketTokenFixtures.oauth)
        ) { _, _ in Issue.record("a fresh token was renewed") }

        #expect(answer == "username=x-token-auth\npassword=fixture-access-token\n")
    }

    @Test("store and erase are ignored, so git never writes the token anywhere through us")
    func ignoresStoreAndErase() async throws {
        let environment = try profile(holding: BitbucketTokenFixtures.oauth)

        let stored = await BitbucketCredentialHelper.answer(action: "store", request: request, environment: environment)
        let erased = await BitbucketCredentialHelper.answer(action: "erase", request: request, environment: environment)

        #expect(stored.isEmpty)
        #expect(erased.isEmpty)
    }

    @Test(
        "another host, or plain http, is not answered",
        arguments: ["protocol=https\nhost=github.com\n", "protocol=http\nhost=bitbucket.org\n"]
    )
    func answersOnlyBitbucketOverHTTPS(request: String) async throws {
        let answer = await BitbucketCredentialHelper.answer(
            action: "get", request: request, environment: try profile(holding: BitbucketTokenFixtures.oauth)
        )

        #expect(answer.isEmpty)
    }

    @Test("an expired token is renewed through bkt before git is answered, for the workspace git asked about")
    func renewsAnExpiredToken() async throws {
        let environment = try profile(holding: BitbucketTokenFixtures.expiredOAuth)
        let folder = try #require(environment["KEYRING_FILE_DIR"])
        let renewed = RenewedWorkspace()

        let answer = await BitbucketCredentialHelper.answer(action: "get", request: request, environment: environment) { asked, _ in
            await renewed.record(asked.workspace)
            try? BitbucketTokenFixtures.oauth.write(
                to: URL(fileURLWithPath: folder).appending(path: "host%2Fapi.bitbucket.org%2Ftoken"),
                atomically: true, encoding: .utf8
            )
        }

        #expect(await renewed.name == "debtges")
        #expect(answer == "username=x-token-auth\npassword=fixture-access-token\n")
    }

    @Test("a profile of its own that is signed out answers nothing and never reaches for this Mac's Keychain")
    func ownProfileSignedOut() async {
        let environment = ["BKT_CONFIG_DIR": TestScratch.unique("unifieddev-bkt-config")]

        let answer = await BitbucketCredentialHelper.answer(action: "get", request: request, environment: environment)

        #expect(answer.isEmpty)
    }

    @Test("a decline of the Keychain prompt keeps it quiet for an hour, then asks again")
    func declineIsRemembered() throws {
        let marker = URL(fileURLWithPath: TestScratch.unique("unifieddev-keychain-declined"))
        #expect(!BitbucketKeychainToken.recentlyDeclined(at: Date(), marker: marker))

        BitbucketKeychainToken.rememberDecline(marker: marker)

        #expect(BitbucketKeychainToken.recentlyDeclined(at: Date(), marker: marker))
        #expect(!BitbucketKeychainToken.recentlyDeclined(at: Date().addingTimeInterval(2 * 60 * 60), marker: marker))
    }
}
