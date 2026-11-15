import Foundation
import Testing
@testable import Core

@Suite("Who is signed in to Bitbucket, and whose commits a pull request holds")
struct BitbucketViewerTests {
    @Test("the viewer is the account uuid bkt's /user answers with, never a name anybody can choose")
    func viewer() async {
        let viewer = await Forge.$remoteOverride.withValue({ _ in "git@bitbucket.org:debtges/ledger.git" }) {
            await Bitbucket.$commandOverride.withValue({ arguments, _ in
                if arguments.starts(with: ["auth", "status"]) {
                    return ShellResult(status: 0, stdout: BitbucketPipelineLogTests.signedIn, stderr: "")
                }
                #expect(arguments == ["api", "/user", "--context", "work"])
                return ShellResult(
                    status: 0, stdout: #"{"nickname": "kid", "display_name": "Kid", "uuid": "{k1}", "account_id": "557"}"#,
                    stderr: ""
                )
            }) {
                await Bitbucket.viewer(in: "/nowhere")
            }
        }

        #expect(viewer == "{k1}")
    }

    @Test("an account is identified by its uuid, then its account id, and a nickname alone identifies nobody")
    func identity() throws {
        func user(_ json: String) throws -> BitbucketPullRequestPayload.User {
            try Bitbucket.decode(BitbucketPullRequestPayload.User.self, from: json)
        }

        #expect(try user(#"{"nickname": "kid", "uuid": "{k1}", "account_id": "557"}"#).identity == "{k1}")
        #expect(try user(#"{"nickname": "kid", "uuid": "", "account_id": "557"}"#).identity == "557")
        #expect(try user(#"{"nickname": "kid", "display_name": "Kid"}"#).identity == nil)
        #expect(try user(#"{"nickname": "", "username": "kid"}"#).name == "kid")
    }

    @Test("commit authors come from each commit's linked account, and an unlinked one counts as nobody")
    func commitAuthors() {
        let page = """
        {"values": [{"hash": "ec3178d4d575a1b2", "author": {"raw": "Kid <k@x>", "user": {"nickname": "kid", "uuid": "{k1}"}}},
                    {"hash": "bbbb", "author": {"raw": "Bot <b@x>"}}]}
        """
        let authors = Bitbucket.decodeCommitAuthors(page)

        #expect(authors?.headCommit == "ec3178d4d575a1b2")
        #expect(authors?.logins == ["{k1}", ""])
        #expect(Bitbucket.decodeCommitAuthors(#"{"values": []}"#) == nil)
    }

    @Test("a pull request with more commits than one page is not vouched for")
    func secondPageIsNotRead() {
        let page = """
        {"values": [{"hash": "aaaa", "author": {"user": {"uuid": "{k1}"}}}],
         "next": "https://api.bitbucket.org/2.0/repositories/debtges/ledger/pullrequests/7/commits?page=2"}
        """

        #expect(Bitbucket.decodeCommitAuthors(page) == nil)
    }

    @Test("an abbreviated head matches the full commit it begins, and nothing shorter does", arguments: [
        ("ec3178d4d575", "ec3178d4d575a1b2c3d4e5f60718293a4b5c6d7e", true),
        ("EC3178D4D575", "ec3178d4d575a1b2c3d4e5f60718293a4b5c6d7e", true),
        ("ec3178d", "ec3178d4d575a1b2c3d4e5f60718293a4b5c6d7e", false),
        ("ec3178d4d576", "ec3178d4d575a1b2c3d4e5f60718293a4b5c6d7e", false),
        ("head", "head", true),
        ("", "", false),
    ])
    func commitHash(short: String, long: String, same: Bool) {
        #expect(CommitHash.same(short, long) == same)
        #expect(CommitHash.same(long, short) == same)
    }

    @Test("the owner's own Bitbucket branch, checked out at its head, may follow the project's instructions")
    func authority() {
        let pullRequest = PullRequest(
            number: 7, title: "", url: "https://bitbucket.org/debtges/ledger/pull-requests/7", state: "OPEN",
            branch: "feat/7", headCommit: "ec3178d4d575", author: "{k1}", isFromFork: false
        )
        let full = "ec3178d4d575a1b2c3d4e5f60718293a4b5c6d7e"

        #expect(InstructionAuthority.forPullRequest(
            pullRequest, checkedOutBranch: "feat/7", checkedOutCommit: full, viewer: "{k1}"
        ) == .project)
        #expect(InstructionAuthority.forPullRequest(
            pullRequest, checkedOutBranch: "feat/7", checkedOutCommit: full, viewer: "{k2}"
        ) == .appOnly)
    }
}
