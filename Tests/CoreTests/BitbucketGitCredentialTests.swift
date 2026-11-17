import Foundation
import Testing
@testable import Core

private actor RenewedWorkspace {
    var name: String?

    func record(_ workspace: String?) { name = workspace }
}

@Suite("The Bitbucket sign-in handed to git")
struct BitbucketGitCredentialTests {
    private let quiet: URL

    init() throws {
        quiet = URL(fileURLWithPath: TestScratch.unique("unifieddev-quiet"), isDirectory: true)
        try FileManager.default.createDirectory(at: quiet, withIntermediateDirectories: true)
    }

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

    private func config(_ text: String) throws -> URL {
        let file = quiet.appending(path: "config-\(UUID().uuidString).yml")
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private static let signedInConfig = """
        active_context: unifieddev
        contexts:
            unifieddev:
                host: api.bitbucket.org
                workspace: debtges
        hosts:
            api.bitbucket.org:
                kind: cloud
        """

    private static let contextOnlyConfig = """
        contexts:
            unifieddev:
                host: api.bitbucket.org
        hosts: {}
        """

    private let request = "protocol=https\nhost=bitbucket.org\npath=debtges/ledger.git\n"

    @Test("an OAuth sign-in written by bkt's own store opens to its access token")
    func opensTheOAuthStore() throws {
        let credential = try #require(
            BitbucketGitCredential.read(sealed: BitbucketTokenFixtures.oauth, passphrase: BitbucketTokenFixtures.passphrase)
        )

        #expect(credential.password == "fixture-access-token")
        let expected = Date(timeIntervalSince1970: 1_893_553_445.123)
        #expect(abs((credential.expiresAt ?? .distantPast).timeIntervalSince(expected)) < 0.001)
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
            markers: quiet, action: "get", request: request, environment: try profile(holding: BitbucketTokenFixtures.oauth),
            refresh: { _, _ in Issue.record("a fresh token was renewed") }
        )

        #expect(answer == "username=x-token-auth\npassword=fixture-access-token\n")
    }

    @Test("store and erase are ignored, so git never writes the token anywhere through us")
    func ignoresStoreAndErase() async throws {
        let environment = try profile(holding: BitbucketTokenFixtures.oauth)

        let stored = await BitbucketCredentialHelper.answer(markers: quiet, action: "store", request: request, environment: environment)
        let erased = await BitbucketCredentialHelper.answer(markers: quiet, action: "erase", request: request, environment: environment)

        #expect(stored.isEmpty)
        #expect(erased.isEmpty)
    }

    @Test(
        "another host, or plain http, is not answered",
        arguments: ["protocol=https\nhost=github.com\n", "protocol=http\nhost=bitbucket.org\n"]
    )
    func answersOnlyBitbucketOverHTTPS(request: String) async throws {
        let answer = await BitbucketCredentialHelper.answer(
            markers: quiet, action: "get", request: request, environment: try profile(holding: BitbucketTokenFixtures.oauth)
        )

        #expect(answer.isEmpty)
    }

    @Test("an expired token is renewed through bkt before git is answered, for the workspace git asked about")
    func renewsAnExpiredToken() async throws {
        let environment = try profile(holding: BitbucketTokenFixtures.expiredOAuth)
        let folder = try #require(environment["KEYRING_FILE_DIR"])
        let renewed = RenewedWorkspace()

        let answer = await BitbucketCredentialHelper.answer(
            markers: quiet, action: "get", request: request, environment: environment,
            refresh: { asked, _ in
                await renewed.record(asked.workspace)
                try? BitbucketTokenFixtures.oauth.write(
                    to: URL(fileURLWithPath: folder).appending(path: "host%2Fapi.bitbucket.org%2Ftoken"),
                    atomically: true, encoding: .utf8
                )
            }
        )

        #expect(await renewed.name == "debtges")
        #expect(answer == "username=x-token-auth\npassword=fixture-access-token\n")
    }

    @Test("a profile of its own that is signed out answers nothing and never reaches for this Mac's Keychain")
    func ownProfileSignedOut() async {
        let environment = ["BKT_CONFIG_DIR": TestScratch.unique("unifieddev-bkt-config")]

        let answer = await BitbucketCredentialHelper.answer(
            markers: quiet, action: "get", request: request, environment: environment,
            keychain: {
                Issue.record("a profile of its own read this Mac's Keychain")
                return .found("this-macs-token")
            }
        )

        #expect(answer.isEmpty)
    }

    @Test("a profile that uses this Mac's sign-in is answered from the Keychain")
    func thisMacReadsTheKeychain() async {
        let answer = await BitbucketCredentialHelper.answer(
            markers: quiet, action: "get", request: request, environment: [:], keychain: { .found("plain-api-token") }
        )

        #expect(answer == "username=x-token-auth\npassword=plain-api-token\n")
    }

    @Test("a declined Keychain prompt is not asked again for an hour, and the helper stands aside")
    func declineIsRemembered() async throws {
        let first = await BitbucketCredentialHelper.answer(
            markers: quiet, action: "get", request: request, environment: [:], keychain: { .declined }
        )
        let second = await BitbucketCredentialHelper.answer(
            markers: quiet, action: "get", request: request, environment: [:],
            keychain: {
                Issue.record("the Keychain was asked again after a decline")
                return .found("this-macs-token")
            }
        )
        let declined = BitbucketKeychainToken.declined(in: quiet)
        let helper = BitbucketCredentialHelper.environment(
            over: [:], shim: "/tmp/bridge", declined: declined, thisMacConfig: try config(Self.signedInConfig)
        )

        #expect(first.isEmpty)
        #expect(second.isEmpty)
        #expect(helper["GIT_CONFIG_COUNT"] == nil)
        #expect(!declined.isQuiet(at: Date().addingTimeInterval(2 * 60 * 60)))
    }

    @Test("the pause is written before bkt is asked, so a helper killed mid-renewal still pauses the next one")
    func pauseBeforeRenewal() async throws {
        let environment = try profile(holding: BitbucketTokenFixtures.expiredOAuth)
        let paused = BitbucketCredentialHelper.renewalFailed(environment, in: quiet)
        let seen = RenewedWorkspace()

        _ = await BitbucketCredentialHelper.answer(
            markers: quiet, action: "get", request: request, environment: environment,
            refresh: { _, _ in await seen.record(paused.isQuiet(at: Date()) ? "paused" : "open") }
        )

        #expect(await seen.name == "paused")
    }

    @Test("a fetch that arrives while another renewal is under way renews too, behind bkt's own lock")
    func concurrentFetchRenewsToo() async throws {
        let environment = try profile(holding: BitbucketTokenFixtures.expiredOAuth)
        BitbucketCredentialHelper.renewalFailed(environment, in: quiet).remember()
        let seen = RenewedWorkspace()

        _ = await BitbucketCredentialHelper.answer(
            markers: quiet, action: "get", request: request, environment: environment,
            refresh: { asked, _ in await seen.record(asked.workspace) }
        )

        #expect(await seen.name == "debtges")
    }

    @Test("a renewal that has been under way longer than a renewal can take pauses the rest of the ten minutes")
    func staleRenewalPauses() async throws {
        let environment = try profile(holding: BitbucketTokenFixtures.expiredOAuth)
        let now = Date()
        BitbucketCredentialHelper.renewalFailed(environment, in: quiet).remember(at: now.addingTimeInterval(-120))

        let answer = await BitbucketCredentialHelper.answer(
            markers: quiet, action: "get", request: request, environment: environment, now: now,
            refresh: { _, _ in Issue.record("a paused renewal was tried again") }
        )

        #expect(answer == "username=x-token-auth\npassword=fixture-expired-token\n")
    }

    @Test("bkt's config counts a sign-in only for a host listed under hosts", arguments: [
        (signedInConfig, true),
        (contextOnlyConfig, false),
        ("contexts:\n    api.bitbucket.org:\n        host: api.bitbucket.org\nhosts: {}\n", false),
        ("hosts:\r\n    \"API.bitbucket.org\": # signed in\r\n        kind: cloud\r\n", true),
        ("hosts:\n    bitbucket.example.com:\n        kind: dc\n", false),
    ])
    func readsTheHosts(config: String, signedIn: Bool) {
        #expect(BitbucketCredentialHelper.namesCloudHost(config) == signedIn)
    }

    @Test("with no bkt token to give, git is answered by the Keychain helper the reset set aside")
    func fallsBackToTheKeychainHelper() async {
        let asked = RenewedWorkspace()
        let empty = await BitbucketCredentialHelper.respond(
            action: "get", request: request, environment: [:], answer: { _, _, _ in "" },
            fallback: { _, _ in
                await asked.record("osxkeychain")
                return "username=me\npassword=app-password\n"
            }
        )
        let ours = await BitbucketCredentialHelper.respond(
            action: "get", request: request, environment: [:], answer: { _, _, _ in "username=x-token-auth\npassword=t\n" },
            fallback: { _, _ in
                Issue.record("the Keychain helper was asked although bkt answered")
                return ""
            }
        )
        let stored = await BitbucketCredentialHelper.respond(
            action: "store", request: request, environment: [:], answer: { _, _, _ in "" },
            fallback: { _, _ in
                Issue.record("a store was forwarded")
                return ""
            }
        )

        #expect(empty == "username=me\npassword=app-password\n")
        #expect(await asked.name == "osxkeychain")
        #expect(ours == "username=x-token-auth\npassword=t\n")
        #expect(stored.isEmpty)
    }

    @Test("an absurd inherited GIT_CONFIG_COUNT cannot overflow the count")
    func inheritedCountIsBounded() {
        let inherited = ["GIT_CONFIG_COUNT": String(Int.max)]

        let helper = BitbucketCredentialHelper.gitEnvironment(shim: "/tmp/bridge", over: inherited)

        #expect(helper["GIT_CONFIG_COUNT"] == String(BitbucketCredentialHelper.mostInheritedEntries + 6))
    }

    @Test("a renewal that fails is not tried again on every fetch for ten minutes")
    func failedRenewalPauses() async throws {
        let environment = try profile(holding: BitbucketTokenFixtures.expiredOAuth)
        let attempts = RenewedWorkspace()
        let renew: @Sendable (BitbucketCredentialHelper.Request, [String: String]) async -> Void = { _, _ in
            await attempts.record((await attempts.name ?? "") + "x")
        }

        _ = await BitbucketCredentialHelper.answer(markers: quiet, action: "get", request: request, environment: environment, refresh: renew)
        let second = await BitbucketCredentialHelper.answer(markers: quiet, action: "get", request: request, environment: environment, refresh: renew)

        #expect(await attempts.name == "x")
        #expect(second == "username=x-token-auth\npassword=fixture-expired-token\n")
    }

    @Test("www.bitbucket.org is answered as bitbucket.org is")
    func answersWWW() async throws {
        let answer = await BitbucketCredentialHelper.answer(
            markers: quiet, action: "get", request: "protocol=https\nhost=www.bitbucket.org\npath=debtges/ledger.git\n",
            environment: try profile(holding: BitbucketTokenFixtures.oauth)
        )

        #expect(answer == "username=x-token-auth\npassword=fixture-access-token\n")
    }

    @Test("git keeps the helpers it already had unless there is a bkt sign-in to hand over")
    func helperOnlyWithASignIn() throws {
        let signedOut = ["BKT_CONFIG_DIR": "/tmp/profile", "KEYRING_FILE_DIR": TestScratch.unique("unifieddev-empty")]
        let signedIn = try profile(holding: BitbucketTokenFixtures.oauth)

        let declined = BitbucketKeychainToken.declined(in: quiet)
        let signedInHere = try config(Self.signedInConfig)
        let missing = quiet.appending(path: "absent.yml")
        func helper(_ over: [String: String], _ thisMac: URL) -> [String: String] {
            BitbucketCredentialHelper.environment(over: over, shim: "/tmp/bridge", declined: declined, thisMacConfig: thisMac)
        }

        let without = helper(signedOut, signedInHere)
        let with = helper(signedIn, missing)
        let thisMacWithout = helper([:], missing)
        let thisMacContextOnly = helper([:], try config(Self.contextOnlyConfig))
        let thisMacWith = helper([:], signedInHere)

        #expect(without["GIT_CONFIG_COUNT"] == nil)
        #expect(with["GIT_CONFIG_COUNT"] == "6")
        #expect(thisMacWithout["GIT_CONFIG_COUNT"] == nil)
        #expect(thisMacContextOnly["GIT_CONFIG_COUNT"] == nil)
        #expect(thisMacWith["GIT_CONFIG_COUNT"] == "6")
    }
}
