import Foundation
import Testing
@testable import Core

@Suite("What a failed clone says, read from what git really printed")
struct CloneFailureWordingTests {
    static let https = """
        Cloning into '/Users/kid/unifieddev/workspaces.noindex/test'...
        fatal: could not read Username for 'https://bitbucket.org': terminal prompts disabled
        """

    static let sshRefused = """
        Cloning into 'd'...
        git@bitbucket.org: Permission denied (publickey).
        fatal: Could not read from remote repository.

        Please make sure you have the correct access rights
        and the repository exists.
        """

    static let unknownHost = """
        Cloning into 'x'...
        Host key verification failed.
        fatal: Could not read from remote repository.

        Please make sure you have the correct access rights
        and the repository exists.
        """

    static let refusedThroughTheHelper = """
        Cloning into 'x'...
        remote: You may not have access to this repository or it no longer exists in this workspace. \
        If you think this repository exists and you have access, make sure you are authenticated.
        fatal: Authentication failed for 'https://bitbucket.org/zz-nonexistent-ws-ud/test.git/'
        """

    static let progressThenFailure = "Cloning into 'a'...\nReceiving objects:   0% (1/2141)\rReceiving objects:  41% (878/2141)\n"
        + "remote: Enumerating objects: 4, done.\nerror: RPC failed; curl 56 Recv failure\nfatal: early EOF\n"

    @Test(
        "the line that names the cause is shown, never the line announcing the clone",
        arguments: [
            (https, "fatal: could not read Username for 'https://bitbucket.org': terminal prompts disabled"),
            (sshRefused, "git@bitbucket.org: Permission denied (publickey)."),
            (unknownHost, "Host key verification failed."),
            (progressThenFailure, "error: RPC failed; curl 56 Recv failure"),
            (
                refusedThroughTheHelper,
                "remote: You may not have access to this repository or it no longer exists in this workspace. "
                    + "If you think this repository exists and you have access, make sure you are authenticated."
            ),
        ]
    )
    func showsTheCause(output: String, cause: String) {
        let error = ShellError(command: "git clone", status: 128, stderr: output)

        #expect(RepositoryStarter.sentence(from: error) == cause)
    }

    @Test("only the generic line is left, so that is what is shown")
    func genericAlone() {
        let error = ShellError(command: "git fetch", status: 128, stderr: "fatal: Could not read from remote repository.\n")

        #expect(RepositoryStarter.sentence(from: error) == "fatal: Could not read from remote repository.")
    }

    @Test(
        "each failure git reports is recognised",
        arguments: [
            (https, RemoteFailure.httpsNeedsCredential),
            (sshRefused, .sshKeyRefused),
            (unknownHost, .unknownHostKey),
            ("fatal: Authentication failed for 'https://bitbucket.org/debtges/ledger.git/'", .httpsCredentialRefused),
            (refusedThroughTheHelper, .httpsCredentialRefused),
            ("You may not have access to this repository or it no longer exists in this workspace.", .noAccess),
            ("fatal: early EOF", .other),
        ]
    )
    func recognises(output: String, failure: RemoteFailure) {
        #expect(RemoteFailure.of(output) == failure)
    }

    @Test("Bitbucket's https failure says the sign-in is handed to git and names ssh as the other way")
    func bitbucketHTTPSAdvice() throws {
        let advice = try #require(RemoteFailure.httpsNeedsCredential.advice(host: "bitbucket.org", isBitbucket: true))

        #expect(advice.contains("Sign in to Bitbucket"))
        #expect(advice.contains("ssh"))
    }

    @Test("an unknown host is named, and an unrecognised failure adds nothing")
    func otherAdvice() {
        #expect(RemoteFailure.unknownHostKey.advice(host: "ssh.bitbucket.org", isBitbucket: true)?
            .hasPrefix("ssh.bitbucket.org is not among the ssh hosts") == true)
        #expect(RemoteFailure.other.advice(host: "bitbucket.org", isBitbucket: true) == nil)
    }

    @Test("a failed clone carries the advice and every line git printed")
    func failureCarriesTheDetail() async {
        let error = ShellError(command: "git clone", status: 128, stderr: Self.https)

        let failure = await RepositoryCloner.failure(cloning: "https://bitbucket.org/debtges/ledger.git", error)

        #expect(failure.message.hasPrefix("fatal: could not read Username"))
        #expect(failure.advice?.contains("bitbucket.org") == true)
        #expect(failure.detail == Self.https)
        #expect(failure.hostOffer == nil)
        #expect(!failure.folderWasCreated)
    }
}
