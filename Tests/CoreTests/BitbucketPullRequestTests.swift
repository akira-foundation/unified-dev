import Foundation
import Testing
@testable import Core

@Suite("A Bitbucket pull request and its builds, as the bar reads them")
struct BitbucketPullRequestTests {
    static func pullRequestJSON(
        id: Int = 5486,
        state: String = "OPEN",
        draft: Bool = false,
        branch: String = "issue/10.2.x/upmerge",
        hash: String = "ec3178d4d575",
        sourceRepository: String = "atlassian/aui",
        participants: String = "[]",
        updatedOn: String = "2026-11-13T11:53:20.988070+00:00"
    ) -> String {
        """
        {"type": "pullrequest", "id": \(id), "title": "Upmerge release/9.12.x into release/10.2.x",
         "state": "\(state)", "draft": \(draft), "merge_commit": null,
         "author": {"display_name": "dc-core-bot", "type": "user", "nickname": "dc-core-bot",
                    "uuid": "{9196eaf9-6f9d-404f-a451-5bc9bb347ca9}"},
         "created_on": "2026-11-04T09:29:06.449178+00:00", "updated_on": "\(updatedOn)",
         "destination": {"branch": {"name": "release/10.2.x"}, "commit": {"hash": "280d938504e0", "type": "commit"},
                         "repository": {"type": "repository", "full_name": "atlassian/aui", "name": "aui"}},
         "source": {"branch": {"name": "\(branch)", "links": {}}, "commit": {"hash": "\(hash)", "type": "commit"},
                    "repository": {"type": "repository", "full_name": "\(sourceRepository)", "name": "aui"}},
         "links": {"html": {"href": "https://bitbucket.org/atlassian/aui/pull-requests/\(id)"}},
         "participants": \(participants)}
        """
    }

    static let statusesJSON = """
    {"values": [
      {"key": "3902112937", "type": "build", "state": "INPROGRESS",
       "name": "AUI - Atlassian AUI - 10.2.x (AUIB10D2X) - issue-10.2.x-upmerge", "refname": null,
       "url": "https://ecosystem-bamboo.internal.atlassian.com/browse/AUI-AUIB10D2X19",
       "created_on": "2026-11-13T11:40:00.000000+00:00", "updated_on": "2026-11-13T11:41:00.000000+00:00"},
      {"key": "-1211181337", "type": "build", "state": "FAILED", "name": "Pipeline #14542 for BESECART-3480_aui",
       "url": "https://bitbucket.org/atlassian/aui/addon/pipelines/home#!/results/14542",
       "created_on": "2026-11-13T10:00:00.123456+00:00", "updated_on": "2026-11-13T10:07:00.654321+00:00"},
      {"key": "renovate/stability-days", "type": "build", "state": "SUCCESSFUL", "name": "renovate/stability-days",
       "url": "https://docs.renovatebot.com/key-concepts/minimum-release-age/"},
      {"key": "stopped", "type": "build", "state": "STOPPED", "name": "Pipeline #14543 for main", "url": ""}
    ], "pagelen": 100, "page": 1, "size": 4}
    """

    @Test("the fields Bitbucket answers with land where the bar reads them")
    func mapsPullRequest() throws {
        let payload = try Bitbucket.decodePullRequest(Self.pullRequestJSON())
        let pullRequest = payload.pullRequest(runs: [])

        #expect(pullRequest.number == 5486)
        #expect(pullRequest.title == "Upmerge release/9.12.x into release/10.2.x")
        #expect(pullRequest.url == "https://bitbucket.org/atlassian/aui/pull-requests/5486")
        #expect(pullRequest.state == "OPEN")
        #expect(pullRequest.branch == "issue/10.2.x/upmerge")
        #expect(pullRequest.baseBranch == "release/10.2.x")
        #expect(pullRequest.headCommit == "ec3178d4d575")
        #expect(pullRequest.author == "{9196eaf9-6f9d-404f-a451-5bc9bb347ca9}")
        #expect(pullRequest.isFromFork == false)
        #expect(pullRequest.closedAt == nil)
        #expect(pullRequest.checks == PullRequest.Checks.none)
    }

    @Test(
        "Bitbucket's four states become the three the bar knows",
        arguments: [("OPEN", "OPEN"), ("MERGED", "MERGED"), ("DECLINED", "CLOSED"), ("SUPERSEDED", "CLOSED")]
    )
    func mapsState(bitbucket: String, unified: String) throws {
        let pullRequest = try Bitbucket.decodePullRequest(Self.pullRequestJSON(state: bitbucket)).pullRequest(runs: [])

        #expect(pullRequest.state == unified)
        #expect((pullRequest.closedAt != nil) == (unified != "OPEN"))
    }

    @Test("a source repository other than the destination is a fork")
    func fork() throws {
        let payload = try Bitbucket.decodePullRequest(Self.pullRequestJSON(sourceRepository: "someone/aui"))

        #expect(payload.pullRequest(runs: []).isFromFork == true)
    }

    @Test(
        "the reviewers' answers become a review decision",
        arguments: [
            (#"[{"state": "changes_requested", "approved": false}, {"state": "approved", "approved": true}]"#, "CHANGES_REQUESTED"),
            (#"[{"state": null, "approved": true}]"#, "APPROVED"),
            (#"[{"state": null, "approved": false}]"#, nil),
        ] as [(String, String?)]
    )
    func reviewDecision(participants: String, decision: String?) throws {
        let payload = try Bitbucket.decodePullRequest(Self.pullRequestJSON(participants: participants))

        #expect(payload.pullRequest(runs: []).reviewDecision == decision)
    }

    @Test("each build status becomes a check in the state the checks tab draws")
    func mapsStatuses() throws {
        let runs = try Bitbucket.decodeStatuses(Self.statusesJSON)

        #expect(runs.map(CheckState.init) == [.running, .failed, .passed, .failed])
        #expect(runs[1].name == "Pipeline #14542 for BESECART-3480_aui")
        #expect(runs[1].detailsURL == "https://bitbucket.org/atlassian/aui/addon/pipelines/home#!/results/14542")
        #expect(runs[1].startedAt != nil)
        #expect(runs[1].completedAt != nil)
        #expect(runs[0].completedAt == nil)
        #expect(runs[3].conclusion == "CANCELLED")
    }

    @Test("a failed build makes the pull request's checks fail and offers a fix")
    func rollsUpChecks() throws {
        let runs = try Bitbucket.decodeStatuses(Self.statusesJSON)
        let pullRequest = try Bitbucket.decodePullRequest(Self.pullRequestJSON()).pullRequest(runs: runs)

        #expect(pullRequest.checks == .failing)
        #expect(pullRequest.checksSummary == "2 required checks failed")
        #expect(pullRequest.hasFixableCheckFailure == true)
        #expect(pullRequest.hasUnfinishedChecks == true)
    }

    @Test("a running build alone keeps the checks pending")
    func pendingChecks() throws {
        let runs = try Bitbucket.decodeStatuses(Self.statusesJSON).filter { CheckState($0) != .failed }
        let pullRequest = try Bitbucket.decodePullRequest(Self.pullRequestJSON()).pullRequest(runs: runs)

        #expect(pullRequest.checks == .pending)
        #expect(pullRequest.hasFixableCheckFailure == false)
    }

    @Test("an open pull request on the branch wins over older merged ones")
    func choosesOpen() throws {
        let merged = try Bitbucket.decodePullRequest(Self.pullRequestJSON(id: 5485, state: "MERGED"))
        let open = try Bitbucket.decodePullRequest(Self.pullRequestJSON(id: 5486))

        #expect(Bitbucket.choose([merged, open], createdAt: .distantPast)?.id == 5486)
    }

    @Test("a fork's pull request from a branch of the same name is not this workspace's")
    func ignoresForks() throws {
        let fork = try Bitbucket.decodePullRequest(Self.pullRequestJSON(id: 5490, sourceRepository: "someone/aui"))
        let own = try Bitbucket.decodePullRequest(Self.pullRequestJSON(id: 5400, state: "MERGED"))

        #expect(Bitbucket.choose([fork], createdAt: .distantPast) == nil)
        #expect(Bitbucket.choose([fork, own], createdAt: .distantPast)?.id == 5400)
        #expect(Bitbucket.choose([fork], createdAt: .distantPast, ownRepositories: ["someone/aui"])?.id == 5490)
    }

    @Test("an empty page link is treated as no link")
    func emptyLink() throws {
        let json = Self.pullRequestJSON().replacingOccurrences(
            of: "https://bitbucket.org/atlassian/aui/pull-requests/5486", with: ""
        )

        #expect(try Bitbucket.decodePullRequest(json).pullRequest(runs: []).url.hasPrefix("https://bitbucket.org/"))
    }

    @Test("a pull request with no page link still names Bitbucket, so its merge goes through bkt")
    func missingLinkStaysBitbucket() throws {
        let json = Self.pullRequestJSON().replacingOccurrences(
            of: #""links": {"html": {"href": "https://bitbucket.org/atlassian/aui/pull-requests/5486"}},"#, with: ""
        )
        let pullRequest = try Bitbucket.decodePullRequest(json).pullRequest(runs: [])

        #expect(pullRequest.url == "https://bitbucket.org/atlassian/aui/pull-requests/5486")
        #expect(pullRequest.forge == .bitbucket)
    }

    @Test("a branch name reused after its pull request merged does not bring that pull request back")
    func ignoresStaleClosed() throws {
        let merged = try Bitbucket.decodePullRequest(
            Self.pullRequestJSON(id: 5400, state: "MERGED", updatedOn: "2026-10-01T09:00:00.000000+00:00")
        )
        let workspaceCreated = try Date("2026-11-01T00:00:00Z", strategy: .iso8601)

        #expect(Bitbucket.choose([merged], createdAt: workspaceCreated) == nil)
        #expect(Bitbucket.choose([merged], createdAt: .distantPast)?.id == 5400)
    }

    @Test("the branch is quoted inside the query, whatever it holds")
    func quotesBranch() {
        let repository = ForgeRepository(kind: .bitbucket, host: "bitbucket.org", owner: "debtges", name: "ledger")
        let arguments = Bitbucket.pullRequestQueryArguments(
            branch: #"fix/a"b\c"#, in: repository, context: "work"
        )

        #expect(arguments.prefix(2) == ["api", "/repositories/debtges/ledger/pullrequests"])
        #expect(arguments.contains(#"q=source.branch.name="fix/a\"b\\c""#))
        #expect(arguments.suffix(2) == ["--context", "work"])
    }

    @Test("an open Bitbucket pull request is offered to the merge, and a draft to Mark ready")
    func mergeOffered() throws {
        let pullRequest = try Bitbucket.decodePullRequest(Self.pullRequestJSON()).pullRequest(runs: [])
        let draft = try Bitbucket.decodePullRequest(Self.pullRequestJSON(draft: true)).pullRequest(runs: [])

        #expect(pullRequest.status.canMerge)
        #expect(pullRequest.status.blockedReason == nil)
        #expect(pullRequest.status.text == "Ready to merge")
        #expect(draft.status.remedy == .markReadyForReview)
        #expect(!draft.status.canMerge)
        #expect(pullRequest.hostName == "Bitbucket")
    }

    @Test("a state Bitbucket has not been seen to send still holds the merge")
    func unknownStateHeld() throws {
        let pullRequest = try Bitbucket.decodePullRequest(Self.pullRequestJSON(state: "QUEUED")).pullRequest(runs: [])

        #expect(pullRequest.state == "UNKNOWN")
        #expect(!pullRequest.status.canMerge)
        #expect(pullRequest.status.blockedReason == PullRequest.unknownStateHeld)
    }

    @Test("a GitHub pull request still merges as it did")
    func gitHubUnchanged() {
        let pullRequest = PullRequest(
            number: 42, title: "Add the glyph", url: "https://github.com/acme/widgets/pull/42", state: "OPEN",
            mergeable: "MERGEABLE"
        )

        #expect(pullRequest.status.canMerge)
        #expect(pullRequest.status.blockedReason == nil)
        #expect(pullRequest.hostName == "GitHub")
    }
}
