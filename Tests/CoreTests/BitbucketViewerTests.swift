import Foundation
import Testing
@testable import Core

@Suite("Who is signed in to Bitbucket, and whose commits a pull request holds")
struct BitbucketViewerTests {
    @Test("the viewer is the nickname bkt's /user answers with")
    func viewer() async {
        let viewer = await Forge.$remoteOverride.withValue({ _ in "git@bitbucket.org:debtges/ledger.git" }) {
            await Bitbucket.$commandOverride.withValue({ arguments, _ in
                if arguments.starts(with: ["auth", "status"]) {
                    return ShellResult(status: 0, stdout: BitbucketPipelineLogTests.signedIn, stderr: "")
                }
                #expect(arguments == ["api", "/user", "--context", "work"])
                return ShellResult(status: 0, stdout: #"{"nickname": "kid", "display_name": "Kid"}"#, stderr: "")
            }) {
                await Bitbucket.viewer(in: "/nowhere")
            }
        }

        #expect(viewer == "kid")
    }

    @Test("commit authors come from each commit's linked user, and an unlinked one counts as nobody")
    func commitAuthors() {
        let page = """
        {"values": [{"hash": "aaaa", "author": {"raw": "Kid <k@x>", "user": {"nickname": "kid"}}},
                    {"hash": "bbbb", "author": {"raw": "Bot <b@x>"}}]}
        """
        let authors = Bitbucket.decodeCommitAuthors(page, head: "ec3178d4d575")

        #expect(authors?.headCommit == "ec3178d4d575")
        #expect(authors?.logins == ["kid", ""])
        #expect(Bitbucket.decodeCommitAuthors(#"{"values": []}"#, head: "ec3178d4d575") == nil)
        #expect(Bitbucket.decodeCommitAuthors(page, head: nil) == nil)
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
            branch: "feat/7", headCommit: "ec3178d4d575", author: "kid", isFromFork: false
        )
        let full = "ec3178d4d575a1b2c3d4e5f60718293a4b5c6d7e"

        #expect(InstructionAuthority.forPullRequest(
            pullRequest, checkedOutBranch: "feat/7", checkedOutCommit: full, viewer: "kid"
        ) == .project)
        #expect(InstructionAuthority.forPullRequest(
            pullRequest, checkedOutBranch: "feat/7", checkedOutCommit: full, viewer: "someone"
        ) == .appOnly)
    }
}
