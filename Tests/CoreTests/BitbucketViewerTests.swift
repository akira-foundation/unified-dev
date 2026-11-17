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
    func commitAuthors() throws {
        let page = """
        {"values": [{"hash": "ec3178d4d575a1b2", "author": {"raw": "Kid <k@x>", "user": {"nickname": "kid", "uuid": "{k1}"}}},
                    {"hash": "bbbb", "author": {"raw": "Bot <b@x>"}}]}
        """
        let authors = Bitbucket.commitAuthors(from: [try #require(Bitbucket.decodeCommitPage(page))])

        #expect(authors?.headCommit == "ec3178d4d575a1b2")
        #expect(authors?.logins == ["{k1}", ""])
        #expect(Bitbucket.commitAuthors(from: [try #require(Bitbucket.decodeCommitPage(#"{"values": []}"#))]) == nil)
        #expect(Bitbucket.commitAuthors(from: []) == nil)
    }

    @Test("pages are only vouched for once the last one has no next")
    func unfinishedPagesAreNotVouched() throws {
        let first = try #require(Bitbucket.decodeCommitPage("""
        {"values": [{"hash": "aaaa", "author": {"user": {"uuid": "{k1}"}}}],
         "next": "https://api.bitbucket.org/2.0/repositories/debtges/ledger/pullrequests/7/commits?pagelen=100&page=67Fg"}
        """))

        #expect(Bitbucket.commitAuthors(from: [first]) == nil)
    }

    static let ledger = ForgeRepository(kind: .bitbucket, host: "bitbucket.org", owner: "debtges", name: "ledger")

    @Test("the cursor of the next page is taken only from a link to the same pull request's commits", arguments: [
        ("https://api.bitbucket.org/2.0/repositories/debtges/ledger/pullrequests/7/commits?pagelen=100&page=67Fg", "67Fg" as String?),
        ("https://api.bitbucket.org/2.0/repositories/debtges/ledger/pullrequests/8/commits?page=67Fg", nil),
        ("https://api.bitbucket.org/2.0/repositories/elsewhere/ledger/pullrequests/7/commits?page=67Fg", nil),
        ("https://evil.example.com/2.0/repositories/debtges/ledger/pullrequests/7/commits?page=67Fg", nil),
        ("http://api.bitbucket.org/2.0/repositories/debtges/ledger/pullrequests/7/commits?page=67Fg", nil),
        ("https://api.bitbucket.org/2.0/repositories/debtges/ledger/pullrequests/7/commits?pagelen=100", nil),
        ("https://api.bitbucket.org/2.0/repositories/debtges/ledger/pullrequests/7/commits?page=--context", nil),
        ("not a link", nil),
        ("https://api.bitbucket.org/2.0/repositories/DebtGes/Ledger/pullrequests/7/commits?page=67Fg", "67Fg"),
    ])
    func nextCursor(next: String, cursor: String?) {
        #expect(Bitbucket.nextCommitPage(next, number: 7, in: Self.ledger) == cursor)
    }

    private actor Calls {
        var seen: [[String]] = []
        func record(_ arguments: [String]) { seen.append(arguments) }
    }

    @Test("a pull request of more than one page of commits is read to its last page and vouched for")
    func followsNext() async {
        let calls = Calls()
        let first = """
        {"values": [{"hash": "ec3178d4d575a1b2", "author": {"user": {"uuid": "{k1}"}}}],
         "next": "https://api.bitbucket.org/2.0/repositories/debtges/ledger/pullrequests/7/commits?pagelen=100&page=67Fg"}
        """
        let second = #"{"values": [{"hash": "e40154b81e5b", "author": {"user": {"uuid": "{k2}"}}}]}"#
        let pullRequest = PullRequest(
            number: 7, title: "", url: "https://bitbucket.org/debtges/ledger/pull-requests/7", state: "OPEN", branch: "feat/7"
        )
        let authors = await Forge.$remoteOverride.withValue({ _ in "git@bitbucket.org:debtges/ledger.git" }) {
            await Bitbucket.$commandOverride.withValue({ arguments, _ in
                if arguments.starts(with: ["auth", "status"]) {
                    return ShellResult(status: 0, stdout: BitbucketPipelineLogTests.signedIn, stderr: "")
                }
                await calls.record(arguments)
                return ShellResult(status: 0, stdout: arguments.contains("page=67Fg") ? second : first, stderr: "")
            }) {
                await Bitbucket.commitAuthors(of: pullRequest, in: "/nowhere")
            }
        }

        #expect(authors?.headCommit == "ec3178d4d575a1b2")
        #expect(authors?.logins == ["{k1}", "{k2}"])
        #expect(await calls.seen == [
            ["api", "/repositories/debtges/ledger/pullrequests/7/commits", "--param", "pagelen=100", "--context", "work"],
            [
                "api", "/repositories/debtges/ledger/pullrequests/7/commits", "--param", "pagelen=100",
                "--param", "page=67Fg", "--context", "work",
            ],
        ])
    }

    @Test("a pull request whose pages never end is not vouched for, and stops after ten pages")
    func endlessPagesStop() async {
        let calls = Calls()
        let endless = """
        {"values": [{"hash": "aaaa", "author": {"user": {"uuid": "{k1}"}}}],
         "next": "https://api.bitbucket.org/2.0/repositories/debtges/ledger/pullrequests/7/commits?page=again"}
        """
        let pullRequest = PullRequest(
            number: 7, title: "", url: "https://bitbucket.org/debtges/ledger/pull-requests/7", state: "OPEN", branch: "feat/7"
        )
        let authors = await Forge.$remoteOverride.withValue({ _ in "git@bitbucket.org:debtges/ledger.git" }) {
            await Bitbucket.$commandOverride.withValue({ arguments, _ in
                if arguments.starts(with: ["auth", "status"]) {
                    return ShellResult(status: 0, stdout: BitbucketPipelineLogTests.signedIn, stderr: "")
                }
                await calls.record(arguments)
                return ShellResult(status: 0, stdout: endless, stderr: "")
            }) {
                await Bitbucket.commitAuthors(of: pullRequest, in: "/nowhere")
            }
        }

        #expect(authors == nil)
        #expect(await calls.seen.count == Bitbucket.commitPagesRead)
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
