import Foundation
import Testing
@testable import Core

@Suite("workspace_merge", .tags(.persistence), .scratchDirectory)
struct WorkspaceMergeToolTests {
    private final class Sent: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [(Workspace, PullRequest, GitHub.MergeMethod)] = []

        func record(_ workspace: Workspace, _ pullRequest: PullRequest, _ method: GitHub.MergeMethod) {
            lock.lock()
            defer { lock.unlock() }
            calls.append((workspace, pullRequest, method))
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return calls.count
        }

        var last: (workspace: Workspace, pullRequest: PullRequest, method: GitHub.MergeMethod)? {
            lock.lock()
            defer { lock.unlock() }
            return calls.last
        }
    }

    @Test("the description says a refused merge may be fixed and pushed before it lands")
    func describesTheRounds() {
        let description = tool().tool.description

        #expect(description.contains("If the host refuses for a conflict or a failed check, the agent fixes it, pushes to the pull request's branch and merges again, three times at most; any other refusal it reports."))
    }

    private func tool(
        reading: WorkspacePullRequestReading? = nil,
        handoff: WorkspaceMergeHandoff = .turnBegun(chat: "Merge"),
        sent: Sent = Sent(),
        forge: ForgeKind = .gitHub
    ) -> WorkspaceMergeTool {
        let reading = reading ?? .found(Self.open(), local: nil)
        return WorkspaceMergeTool(read: { _ in reading }, host: { _ in forge }) { workspace, pullRequest, method in
            sent.record(workspace, pullRequest, method)
            return handoff
        }
    }

    private func request(_ arguments: [String: JSONValue]) -> MCPRequest {
        MCPRequest(id: .number(1), method: "workspace_merge", params: .object(arguments))
    }

    private static func open(
        number: Int = 42,
        state: String = "OPEN",
        isDraft: Bool = false,
        mergeable: String? = nil,
        checks: PullRequest.Checks = .passing,
        baseBranch: String = ""
    ) -> PullRequest {
        PullRequest(
            number: number,
            title: "Group occurrences by fingerprint",
            url: "https://github.com/akira-io/ember/pull/\(number)",
            state: state,
            isDraft: isDraft,
            mergeable: mergeable,
            checks: checks,
            checksSummary: "12 checks passed",
            branch: "claude/group-occurrences",
            baseBranch: baseBranch
        )
    }

    private func workspace(
        in store: Store,
        name: String = "group occurrences",
        branch: String = "claude/group-occurrences"
    ) async throws -> Workspace {
        let repo = try await store.upsert(
            Repo(name: "ember", path: TestScratch.unique("ember"), defaultBranch: "main")
        )
        let path = TestScratch.unique("worktree")
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return try await store.upsert(Workspace(
            repoID: repo.id, name: name, branch: branch, path: path, baseBranch: "main"
        ))
    }

    private func answer(_ result: BridgeToolResult) throws -> JSONValue {
        try #require(JSONValue.parse(result.text))
    }

    @Test("only the owner sees it")
    func roleGate() {
        let toolbox = BridgeToolbox(handlers: [tool()])

        #expect(toolbox.tools(for: .workspace).isEmpty)
        #expect(toolbox.tools(for: .owner).map(\.name) == ["workspace_merge"])
        #expect(toolbox.handler(named: "workspace_merge", for: .workspace) == nil)
    }

    @Test("it is not in the standard toolbox, because it needs a seam into the app")
    func isNotStandard() {
        #expect(!BridgeToolbox.standard.tools(for: .owner).map(\.name).contains("workspace_merge"))
    }

    @Test("it takes no free text, so it cannot be used to say something else to an agent")
    func noFreeText() throws {
        let properties = try #require(tool().tool.inputSchema["properties"]?.objectValue)

        #expect(Set(properties.keys) == ["workspace", "method"])
        #expect(properties["method"]?["enum"]?.arrayValue?.compactMap(\.stringValue)
            == GitHub.MergeMethod.allCases.map(\.rawValue))
    }

    @Test("it will not merge without being told which workspace")
    func needsAWorkspace() async throws {
        let store = try makeTestStore("merge-no-workspace")

        let result = await tool().call(request([:]), as: .owner, store: store)

        #expect(result.isError)
        #expect(result.text.contains("workspace_merge needs the workspace"))
        #expect(result.text.contains("workspace_list"))
    }

    @Test("a merge method Unified Dev does not have is refused by name rather than merged some other way")
    func unknownMethod() async throws {
        let store = try makeTestStore("merge-bad-method")
        let target = try await workspace(in: store)
        let sent = Sent()

        let result = await tool(sent: sent).call(
            request(["workspace": .string(target.id.rawValue), "method": .string("fast-forward")]),
            as: .owner,
            store: store
        )

        #expect(result.isError)
        #expect(result.text.contains("'fast-forward'"))
        #expect(result.text.contains("'squash'"))
        #expect(sent.count == 0)
    }

    @Test("a name where an id belongs is answered with the id")
    func nameInsteadOfID() async throws {
        let store = try makeTestStore("merge-name")
        let target = try await workspace(in: store)

        let result = await tool().call(
            request(["workspace": .string("group occurrences")]), as: .owner, store: store
        )

        #expect(result.isError)
        #expect(result.text.contains("is the NAME of a workspace"))
        #expect(result.text.contains(target.id.rawValue))
    }

    @Test("two workspaces sharing a name are why this takes an id, and the refusal says so")
    func ambiguousName() async throws {
        let store = try makeTestStore("merge-ambiguous")
        _ = try await workspace(in: store, name: "retry", branch: "a")
        _ = try await workspace(in: store, name: "retry", branch: "b")

        let result = await tool().call(
            request(["workspace": .string("retry")]), as: .owner, store: store
        )

        #expect(result.isError)
        #expect(result.text.contains("2 workspaces are called 'retry'"))
    }

    @Test("an id that means nothing at all points at workspace_list")
    func unknownID() async throws {
        let store = try makeTestStore("merge-unknown")

        let result = await tool().call(
            request(["workspace": .string("nope")]), as: .owner, store: store
        )

        #expect(result.isError)
        #expect(result.text.contains("Unified Dev has no workspace with the id 'nope'"))
        #expect(result.text.contains("workspace_list"))
    }

    @Test("an archived workspace has no worktree to merge from and no agent to ask")
    func archived() async throws {
        let store = try makeTestStore("merge-archived")
        var target = try await workspace(in: store)
        target.state = .archived
        _ = try await store.upsert(target)
        let sent = Sent()

        let result = await tool(sent: sent).call(
            request(["workspace": .string(target.id.rawValue)]), as: .owner, store: store
        )

        #expect(result.isError)
        #expect(result.text.contains("that workspace is archived"))
        #expect(result.text.contains("Retrying will not help"))
        #expect(sent.count == 0)
    }

    @Test("an active workspace whose worktree has gone is a thing to report, not to retry")
    func worktreeGone() async throws {
        let store = try makeTestStore("merge-no-worktree")
        let repo = try await store.upsert(
            Repo(name: "ember", path: TestScratch.unique("ember"), defaultBranch: "main")
        )
        let target = try await store.upsert(Workspace(
            repoID: repo.id,
            name: "gone",
            branch: "b",
            path: TestScratch.unique("never-made"),
            baseBranch: "main"
        ))

        let result = await tool().call(
            request(["workspace": .string(target.id.rawValue)]), as: .owner, store: store
        )

        #expect(result.isError)
        #expect(result.text.contains("worktree is no longer on disk"))
        #expect(result.text.contains("Retrying will not help"))
    }

    @Test("a workspace mid turn is told to wait, and nothing is sent")
    func midTurn() async throws {
        let store = try makeTestStore("merge-mid-turn")
        let target = try await workspace(in: store)
        var session = Session(workspaceID: target.id, title: "First chat")
        session.apply(.turnStarted)
        _ = try await store.upsert(session)
        let sent = Sent()

        let result = await tool(sent: sent).call(
            request(["workspace": .string(target.id.rawValue)]), as: .owner, store: store
        )

        #expect(result.isError)
        #expect(result.text.contains("in the middle of a turn"))
        #expect(result.text.contains("workspace_list"))
        #expect(sent.count == 0)
    }

    @Test("an agent stopped on a permission question is not written into")
    func awaitingQuestion() async throws {
        let store = try makeTestStore("merge-question")
        let target = try await workspace(in: store)
        var session = Session(workspaceID: target.id, title: "First chat")
        session.apply(.turnStarted)
        session.apply(.blocked)
        _ = try await store.upsert(session)
        let sent = Sent()

        let result = await tool(sent: sent).call(
            request(["workspace": .string(target.id.rawValue)]), as: .owner, store: store
        )

        #expect(result.isError)
        #expect(result.text.contains("stopped on a permission question"))
        #expect(sent.count == 0)
    }

    @Test("a worktree still being set up is not merged from")
    func settingUp() async throws {
        let store = try makeTestStore("merge-setup")
        var target = try await workspace(in: store)
        target.apply(.runStarted)
        _ = try await store.upsert(target)

        let result = await tool().call(
            request(["workspace": .string(target.id.rawValue)]), as: .owner, store: store
        )

        #expect(result.isError)
        #expect(result.text.contains("setup script is still running"))
    }

    @Test("a failed setup is not a hold, so the merge is asked for anyway")
    func setupFailed() async throws {
        let store = try makeTestStore("merge-setup-failed")
        var target = try await workspace(in: store)
        target.apply(.runStarted)
        target.apply(.runFinished(succeeded: false, log: "npm install exploded"))
        _ = try await store.upsert(target)

        let sent = Sent()
        let result = await tool(sent: sent).call(
            request(["workspace": .string(target.id.rawValue)]), as: .owner, store: store
        )

        #expect(!result.isError)
        #expect(sent.count == 1)
    }

    @Test("gh missing is said as gh missing, not as a pull request that is not there")
    func ghMissing() async throws {
        let store = try makeTestStore("merge-gh-missing")
        let target = try await workspace(in: store)

        let result = await tool(reading: .unavailable(.notInstalled)).call(
            request(["workspace": .string(target.id.rawValue)]), as: .owner, store: store
        )

        #expect(result.isError)
        #expect(result.text.contains("`gh` is not installed"))
        #expect(result.text.contains("Retrying will not help"))
    }

    @Test("signing gh in is the owner's to do")
    func ghSignedOut() async throws {
        let store = try makeTestStore("merge-gh-signed-out")
        let target = try await workspace(in: store)

        let result = await tool(reading: .unavailable(.signedOut)).call(
            request(["workspace": .string(target.id.rawValue)]), as: .owner, store: store
        )

        #expect(result.isError)
        #expect(result.text.contains("not signed in to GitHub"))
        #expect(result.text.contains("the owner's to do"))
    }

    @Test("a gh call that did not come back is the one thing worth asking again about")
    func ghSilent() async throws {
        let store = try makeTestStore("merge-gh-silent")
        let target = try await workspace(in: store)

        let result = await tool(reading: .failed("gh timed out after 20s")).call(
            request(["workspace": .string(target.id.rawValue)]), as: .owner, store: store
        )

        #expect(result.isError)
        #expect(result.text.contains("gh timed out after 20s"))
        #expect(result.text.contains("asking again in a minute"))
    }

    @Test("gh's own words reach the caller, and the command line Unified Dev built does not")
    func ghsWordsWithoutTheCommandLine() {
        let error = ShellError(
            command: "gh pr view b --json number,title,url,state,isDraft,mergeable",
            status: 1,
            stderr: "no git remotes found\n"
        )

        let plain = WorkspaceMergeTool.plainly(error, on: .gitHub)

        #expect(plain == "no git remotes found.")
        #expect(!plain.contains("--json"))
        #expect(!WorkspaceMergeTrouble.forgeSilent(plain, on: .gitHub).sentence.contains("--json"))
        #expect(WorkspaceMergeTrouble.forgeSilent(plain, on: .gitHub).sentence.contains("found. Nothing was sent"))
        #expect(WorkspaceMergeTrouble.forgeSilent("gh gave up", on: .gitHub).sentence.contains("up. Nothing was sent"))
    }

    @Test("no pull request says not to open one")
    func noPullRequest() async throws {
        let store = try makeTestStore("merge-no-pr")
        let target = try await workspace(in: store)

        let result = await tool(reading: .noPullRequest).call(
            request(["workspace": .string(target.id.rawValue)]), as: .owner, store: store
        )

        #expect(result.isError)
        #expect(result.text.contains("GitHub has no pull request for its branch"))
        #expect(result.text.contains("Do not open one to make this call succeed"))
    }

    @Test("a Bitbucket workspace's refusals name bkt and Bitbucket, never gh", arguments: [
        WorkspacePullRequestReading.unavailable(.notInstalled),
        .unavailable(.signedOut),
        .failed("bkt timed out after 20s"),
        .noPullRequest,
    ])
    func bitbucketRefusalsNameBkt(reading: WorkspacePullRequestReading) async throws {
        let store = try makeTestStore("merge-bitbucket-refusal")
        let target = try await workspace(in: store)

        let result = await tool(reading: reading, forge: .bitbucket).call(
            request(["workspace": .string(target.id.rawValue)]), as: .owner, store: store
        )

        let body = result.text.replacingOccurrences(of: WorkspaceMergeTrouble.notYours, with: "")
        #expect(result.isError)
        #expect(body.contains("Bitbucket"))
        #expect(!body.contains("GitHub"))
        #expect(!body.contains("`gh`"))
        #expect(!body.contains(" gh "))
    }

    @Test("on Bitbucket, a pull request the host will not take and work it has not got name Bitbucket")
    func bitbucketBlockedAndLocalWork() async throws {
        let store = try makeTestStore("merge-bitbucket-blocked")
        let target = try await workspace(in: store)
        let request = request(["workspace": .string(target.id.rawValue)])

        let draft = await tool(reading: .found(Self.open(isDraft: true), local: nil), forge: .bitbucket)
            .call(request, as: .owner, store: store)
        let local = await tool(
            reading: .found(Self.open(), local: LocalWork(modifiedFiles: 1)), forge: .bitbucket
        ).call(request, as: .owner, store: store)

        #expect(draft.text.contains("Bitbucket reports it as"))
        #expect(draft.text.contains("skip a build"))
        #expect(local.text.contains("work Bitbucket has not got"))
        #expect(!draft.text.contains("GitHub") && !local.text.contains("GitHub"))
    }

    @Test("on Bitbucket the answer says the agent runs bkt pr merge and Bitbucket may refuse")
    func bitbucketAnswer() async throws {
        let store = try makeTestStore("merge-bitbucket-answer")
        let target = try await workspace(in: store)

        let result = await tool(forge: .bitbucket).call(
            request(["workspace": .string(target.id.rawValue)]), as: .owner, store: store
        )

        let note = try answer(result)["note"]?.stringValue ?? ""
        #expect(note.contains("`bkt pr merge`"))
        #expect(note.contains("Bitbucket is allowed to refuse"))
        #expect(!note.contains("gh pr merge"))
    }

    @Test("the default host is read from the workspace's base remote")
    func defaultHost() async throws {
        let store = try makeTestStore("merge-default-host")
        let target = try await workspace(in: store)

        let host = await Forge.$remoteOverride.withValue({ _ in "git@bitbucket.org:debtges/ledger.git" }) {
            await WorkspaceMergeTool.hostOf(target)
        }

        #expect(host == .bitbucket)
    }

    @Test("bkt missing is named as bkt, and bkt signed out as not signed in to Bitbucket")
    func bitbucketAccessWording() {
        let missing = WorkspaceMergeTrouble.forgeUnavailable(.notInstalled, on: .bitbucket).sentence
        let signedOut = WorkspaceMergeTrouble.forgeUnavailable(.signedOut, on: .bitbucket).sentence

        #expect(missing.contains("`bkt` is not installed"))
        #expect(signedOut.contains("`bkt` is installed but not signed in to Bitbucket"))
        #expect(WorkspaceMergeTrouble.forgeUnavailable(.notInstalled, on: .gitHub).sentence.contains("`gh` is not installed"))
    }

    @Test("bkt exiting without a word is reported as bkt")
    func bktSilentExit() {
        let error = ShellError(command: "bkt api /x", status: 3, stderr: "  ")

        #expect(WorkspaceMergeTool.plainly(error, on: .bitbucket) == "bkt exited 3 without saying why.")
        #expect(WorkspaceMergeTool.plainly(error, on: .gitHub) == "gh exited 3 without saying why.")
    }

    @Test("a pull request GitHub will not take is refused in the gate's own words", arguments: [
        (Self.open(state: "MERGED"), "This pull request is already merged."),
        (Self.open(state: "CLOSED"), "This pull request was closed without merging."),
        (Self.open(mergeable: "CONFLICTING"), "Resolve the conflicts with the base branch first."),
        (Self.open(isDraft: true), "This pull request is still a draft."),
    ])
    func blocked(pullRequest: PullRequest, reason: String) async throws {
        let store = try makeTestStore("merge-blocked")
        let target = try await workspace(in: store)
        let sent = Sent()

        let result = await tool(reading: .found(pullRequest, local: nil), sent: sent).call(
            request(["workspace": .string(target.id.rawValue)]), as: .owner, store: store
        )

        #expect(result.isError)
        #expect(result.text.contains(reason))
        #expect(result.text.contains(pullRequest.status.text))
        #expect(result.text.contains("Do not mark the pull request ready"))
        #expect(sent.count == 0)
    }

    @Test("failing checks do not block it, exactly as they do not block the button")
    func failingChecksRideAlong() async throws {
        let store = try makeTestStore("merge-failing-checks")
        let target = try await workspace(in: store)
        let sent = Sent()

        let result = await tool(
            reading: .found(Self.open(checks: .failing), local: nil), sent: sent
        ).call(request(["workspace": .string(target.id.rawValue)]), as: .owner, store: store)

        #expect(!result.isError)
        #expect(sent.count == 1)
    }

    @Test("uncommitted work refuses rather than merging over it")
    func uncommittedWork() async throws {
        let store = try makeTestStore("merge-uncommitted")
        let target = try await workspace(in: store)
        let sent = Sent()
        let local = LocalWork(modifiedFiles: 2, untrackedFiles: 1)

        let result = await tool(reading: .found(Self.open(), local: local), sent: sent).call(
            request(["workspace": .string(target.id.rawValue)]), as: .owner, store: store
        )

        #expect(result.isError)
        #expect(result.text.contains("3 files to commit"))
        #expect(result.text.contains("commit and push it first"))
        #expect(result.text.contains("dialogue the owner has to accept"))
        #expect(sent.count == 0)
    }

    @Test("committed work that was never pushed refuses too, because the merge would miss it")
    func unpushedWork() async throws {
        let store = try makeTestStore("merge-unpushed")
        let target = try await workspace(in: store)
        let sent = Sent()
        let local = LocalWork(unpushedCommits: 2)

        let result = await tool(reading: .found(Self.open(), local: local), sent: sent).call(
            request(["workspace": .string(target.id.rawValue)]), as: .owner, store: store
        )

        #expect(result.isError)
        #expect(result.text.contains("2 commits to push"))
        #expect(result.text.contains("push it first"))
        #expect(sent.count == 0)
    }

    @Test("a clean worktree is merged from without comment")
    func cleanWorktree() async throws {
        let store = try makeTestStore("merge-clean")
        let target = try await workspace(in: store)
        let sent = Sent()

        let result = await tool(reading: .found(Self.open(), local: LocalWork()), sent: sent).call(
            request(["workspace": .string(target.id.rawValue)]), as: .owner, store: store
        )

        #expect(!result.isError)
        #expect(sent.count == 1)
    }

    @Test("every refusal says not to run the merge some other way")
    func everyRefusalSaysNotToDoItYourself() async throws {
        let troubles: [WorkspaceMergeTrouble] = [
            .unknownWorkspace(id: "x", alias: .none),
            .unknownWorkspace(id: "x", alias: .one(name: "n", id: "i")),
            .unknownWorkspace(id: "x", alias: .several(name: "n", count: 3)),
            .archived(workspace: "w"),
            .worktreeGone(workspace: "w"),
            .forgeUnavailable(.notInstalled, on: .gitHub),
            .forgeUnavailable(.signedOut, on: .bitbucket),
            .forgeSilent("gh fell over", on: .gitHub),
            .noPullRequest(workspace: "w", branch: "b", on: .gitHub),
            .blocked(workspace: "w", number: 1, headline: "Draft", reason: "It is a draft.", on: .bitbucket),
            .localWork(workspace: "w", number: 1, detail: "1 file to commit", needsCommit: true, on: .gitHub),
            .wouldQueue(workspace: "w", hold: .setup),
            .wouldQueue(workspace: "w", hold: .question),
            .wouldQueue(workspace: "w", hold: .turn),
            .wouldQueue(workspace: "w", hold: .none),
            .appRefused("It is still working."),
        ]

        for trouble in troubles {
            #expect(trouble.sentence.contains("Do not run `gh pr merge` yourself"))
            #expect(!trouble.sentence.contains("gh pr merge <"))
        }
    }

    @Test("the answer says a turn has begun and never that anything is merged")
    func theAnswer() async throws {
        let store = try makeTestStore("merge-answer")
        let target = try await workspace(in: store)
        let sent = Sent()

        let result = await tool(handoff: .turnBegun(chat: "Merge"), sent: sent).call(
            request(["workspace": .string(target.id.rawValue)]), as: .owner, store: store
        )

        #expect(!result.isError)
        let json = try answer(result)
        #expect(json["state"]?.stringValue == "turn_started")
        #expect(json["workspace_id"]?.stringValue == target.id.rawValue)
        #expect(json["workspace"]?.stringValue == "group occurrences")
        #expect(json["chat"]?.stringValue == "Merge")
        #expect(json["pull_request"]?.intValue == 42)
        #expect(json["base_branch"]?.stringValue == "main")
        #expect(json["method"]?.stringValue == "merge commit")

        let note = try #require(json["note"]?.stringValue)
        #expect(note.hasPrefix("Nothing is merged."))
        #expect(note.contains("A turn has begun in 'group occurrences'"))
        #expect(note.contains("in the chat 'Merge'"))
        #expect(note.contains("workspace_list with include_github"))
        #expect(note.contains("GitHub is allowed to refuse"))
        #expect(note.contains("fix a conflict or a failed check and push it to the pull request's branch before merging again, three times at most"))
        #expect(note.contains("stop and report any other refusal rather than force it"))
        #expect(!json["state"]!.stringValue!.contains("merge"))
    }

    @Test("the answer names the base the pull request targets, not the workspace's")
    func theAnswerNamesThePullRequestsBase() async throws {
        let store = try makeTestStore("merge-answer-base")
        let target = try await workspace(in: store)

        let result = await tool(
            reading: .found(Self.open(baseBranch: "develop"), local: nil),
            handoff: .turnBegun(chat: "Merge")
        ).call(request(["workspace": .string(target.id.rawValue)]), as: .owner, store: store)

        let json = try answer(result)
        #expect(target.baseBranch == "main")
        #expect(json["base_branch"]?.stringValue == "develop")
    }

    @Test("each method asked for is carried through unaltered")
    func methods() async throws {
        let store = try makeTestStore("merge-methods")
        let target = try await workspace(in: store)

        for method in GitHub.MergeMethod.allCases {
            let sent = Sent()
            var arguments: [String: JSONValue] = ["workspace": .string(target.id.rawValue)]
            arguments["method"] = .string(method.rawValue)

            let result = await tool(sent: sent).call(request(arguments), as: .owner, store: store)

            #expect(!result.isError)
            #expect(sent.last?.method == method)
            #expect(try answer(result)["method"]?.stringValue == method.phrase)
        }

    }

    @Test("a method asked for wins over the project's own choice")
    func askedMethodWinsOverTheProject() async throws {
        let store = try makeTestStore("merge-method-asked")
        let target = try await workspace(in: store)
        await MergeMethodChoice.save(.squash, repoID: target.repoID, to: store)
        let sent = Sent()

        _ = await tool(sent: sent).call(
            request(["workspace": .string(target.id.rawValue), "method": .string("rebase")]),
            as: .owner, store: store
        )

        #expect(sent.last?.method == .rebase)
    }

    @Test("left unsaid, the method is the one the project's Merge button shows")
    func omittedMethodFollowsTheProject() async throws {
        let store = try makeTestStore("merge-method-default")
        let target = try await workspace(in: store)
        let arguments: [String: JSONValue] = ["workspace": .string(target.id.rawValue)]

        let unset = Sent()
        _ = await tool(sent: unset).call(request(arguments), as: .owner, store: store)
        #expect(unset.last?.method == .merge)

        await MergeMethodChoice.saveAppDefault(.rebase, to: store)
        let appWide = Sent()
        _ = await tool(sent: appWide).call(request(arguments), as: .owner, store: store)
        #expect(appWide.last?.method == .rebase)

        await MergeMethodChoice.save(.squash, repoID: target.repoID, to: store)
        let projectOwn = Sent()
        _ = await tool(sent: projectOwn).call(request(arguments), as: .owner, store: store)
        #expect(projectOwn.last?.method == .squash)
    }

    @Test("the workspace and the pull request reach the app exactly as Unified Dev read them")
    func handsOverWhatItRead() async throws {
        let store = try makeTestStore("merge-handover")
        let target = try await workspace(in: store)
        let sent = Sent()
        let pullRequest = Self.open(number: 71)

        _ = await tool(reading: .found(pullRequest, local: nil), sent: sent).call(
            request(["workspace": .string(target.id.rawValue)]), as: .owner, store: store
        )

        let handed = try #require(sent.last)
        #expect(handed.workspace.id == target.id)
        #expect(handed.workspace.name == target.name)
        #expect(handed.workspace.branch == target.branch)
        #expect(handed.workspace.baseBranch == target.baseBranch)
        #expect(handed.workspace.path == target.path)
        #expect(handed.pullRequest == pullRequest)
    }

    @Test("what crosses the seam renders the merge prompt the button renders")
    func rendersTheButtonsPrompt() async throws {
        let store = try makeTestStore("merge-prompt")
        let target = try await workspace(in: store)
        let sent = Sent()
        let pullRequest = Self.open(number: 71)

        _ = await tool(reading: .found(pullRequest, local: nil), sent: sent).call(
            request([
                "workspace": .string(target.id.rawValue), "method": .string("squash"),
            ]),
            as: .owner,
            store: store
        )

        let handed = try #require(sent.last)
        let context = MergePromptContext(
            workspace: handed.workspace, pullRequest: handed.pullRequest, method: handed.method
        )
        let render = context.render(
            template: PromptRegistry.definition(for: .mergePullRequest).defaultTemplate
        )

        #expect(render.missing.isEmpty)
        #expect(render.text.contains("#71"))
        #expect(render.text.contains("into main"))
        #expect(render.text.contains("squash merge"))
        #expect(render.text.contains("`--squash`"))
        #expect(render.text.contains("claude/group-occurrences"))
    }

    @Test("the app refusing after all is relayed rather than reported as a turn")
    func appRefused() async throws {
        let store = try makeTestStore("merge-app-refused")
        let target = try await workspace(in: store)

        let result = await tool(
            handoff: .refused("group occurrences is still working. Wait for the turn to finish.")
        ).call(request(["workspace": .string(target.id.rawValue)]), as: .owner, store: store)

        #expect(result.isError)
        #expect(result.text.contains("Unified Dev did not send the merge request."))
        #expect(result.text.contains("is still working"))
    }
}
