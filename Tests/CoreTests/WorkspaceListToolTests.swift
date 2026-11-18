import Foundation
import Testing
@testable import Core

@Suite("workspace_list", .tags(.persistence), .scratchDirectory)
struct WorkspaceListToolTests {
    private func request(_ arguments: [String: JSONValue] = [:]) -> MCPRequest {
        MCPRequest(id: .number(1), method: "workspace_list", params: .object(arguments))
    }

    private func answer(_ result: BridgeToolResult) throws -> JSONValue {
        try #require(JSONValue.parse(result.text))
    }

    private func workspaces(_ result: BridgeToolResult) throws -> [JSONValue] {
        try #require(answer(result)["workspaces"]?.arrayValue)
    }

    private func named(_ name: String, in result: BridgeToolResult) throws -> JSONValue {
        try #require(workspaces(result).first { $0["name"]?.stringValue == name })
    }

    @Test("the owner sees it, and a workspace sees it only from a chat that may leave its profile")
    func roleGate() async throws {
        let store = try makeTestStore("workspace-list-gate")
        let toolbox = BridgeToolbox(handlers: [WorkspaceListTool()])
        let repo = try await store.upsert(Repo(name: "r", path: TestScratch.unique("gate")))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "w", branch: "b", path: TestScratch.unique("gate-tree"), baseBranch: "main"
        ))
        let chat = try await store.upsert(Session(workspaceID: workspace.id, title: "c", permissionMode: .acceptEdits))
        let agent = BridgeIdentity(sessionID: chat.id, workspaceID: workspace.id, role: .workspace, launchedAsking: true)
        let unasked = BridgeIdentity(sessionID: chat.id, workspaceID: workspace.id, role: .workspace)

        #expect(await toolbox.tools(for: unasked, store: store).isEmpty)
        #expect(await toolbox.tools(for: .owner, store: store).map(\.name) == ["workspace_list"])
        #expect(await toolbox.handler(named: "workspace_list", for: unasked, store: store) == nil)
        #expect(await toolbox.tools(for: agent, store: store).map(\.name) == ["workspace_list"])
    }

    @Test("it is served by a Unified Dev with no app behind it, because it needs no seam into one")
    func isInTheStandardToolbox() {
        #expect(BridgeToolbox.standard.tools(for: .owner).map(\.name).contains("workspace_list"))
    }

    @Test("an empty Unified Dev says so rather than answering with nothing")
    func emptyUnifiedDev() async throws {
        let store = try makeTestStore("list-empty")

        let result = await WorkspaceListTool().call(request(), as: .owner, store: store)

        #expect(!result.isError)
        #expect(try workspaces(result).isEmpty)
        #expect(result.text.contains("There are no workspaces here."))
    }

    @Test("a workspace answers with the columns a caller can act on")
    func theFields() async throws {
        let store = try makeTestStore("list-fields")
        let repo = try await store.upsert(
            Repo(name: "ember", path: "/tmp/ember", defaultBranch: "main")
        )
        var workspace = Workspace(
            repoID: repo.id,
            name: "group occurrences",
            branch: "claude/group-occurrences",
            path: "/tmp/worktrees/group-occurrences",
            baseBranch: "main",
            additions: 41,
            deletions: 7,
            changedFiles: 3
        )
        workspace.unread = true
        _ = try await store.upsert(workspace)

        let result = await WorkspaceListTool().call(request(), as: .owner, store: store)
        let row = try named("group occurrences", in: result)

        #expect(row["id"]?.stringValue == workspace.id.rawValue)
        #expect(row["branch"]?.stringValue == "claude/group-occurrences")
        #expect(row["base_branch"]?.stringValue == "main")
        #expect(row["path"]?.stringValue == "/tmp/worktrees/group-occurrences")
        #expect(row["state"]?.stringValue == "active")
        #expect(row["setup_state"]?.stringValue == "pending")
        #expect(row["unread"]?.boolValue == true)
        #expect(row["diff"]?["additions"]?.intValue == 41)
        #expect(row["diff"]?["deletions"]?.intValue == 7)
        #expect(row["diff"]?["changed_files"]?.intValue == 3)
        #expect(row["project"]?["name"]?.stringValue == "ember")
        #expect(row["project"]?["id"]?.stringValue == repo.id.rawValue)
        #expect(row["created_by"]?.stringValue == "owner")
        #expect(row["created_at"]?.stringValue?.isEmpty == false)
    }

    @Test("workspaces in different states are told apart, in the sidebar's own vocabulary")
    func statesAreToldApart() async throws {
        let store = try makeTestStore("list-states")
        let repo = try await store.upsert(
            Repo(name: "ember", path: "/tmp/ember", defaultBranch: "main")
        )

        _ = try await store.upsert(Workspace(
            repoID: repo.id, name: "idle", branch: "b1", path: "/tmp/w1", baseBranch: "main"
        ))

        var changed = Workspace(
            repoID: repo.id, name: "changed", branch: "b2", path: "/tmp/w2", baseBranch: "main",
            additions: 12, deletions: 1, changedFiles: 2
        )
        changed.apply(.runFinished(succeeded: true, log: "ok"))
        _ = try await store.upsert(changed)

        var settingUp = Workspace(
            repoID: repo.id, name: "setting up", branch: "b3", path: "/tmp/w3", baseBranch: "main"
        )
        settingUp.apply(.runStarted)
        _ = try await store.upsert(settingUp)

        let busy = try await store.upsert(Workspace(
            repoID: repo.id, name: "busy", branch: "b4", path: "/tmp/w4", baseBranch: "main"
        ))
        var running = Session(workspaceID: busy.id, title: "First chat")
        running.apply(.turnStarted)
        _ = try await store.upsert(running)

        let blocked = try await store.upsert(Workspace(
            repoID: repo.id, name: "blocked", branch: "b5", path: "/tmp/w5", baseBranch: "main"
        ))
        var waiting = Session(workspaceID: blocked.id, title: "First chat")
        waiting.apply(.turnStarted)
        waiting.apply(.blocked)
        _ = try await store.upsert(waiting)

        let result = await WorkspaceListTool().call(request(), as: .owner, store: store)

        #expect(try named("idle", in: result)["status"]?.stringValue == WorkspaceStatus.clean.rawValue)
        #expect(try named("changed", in: result)["status"]?.stringValue == WorkspaceStatus.changed.rawValue)
        #expect(try named("setting up", in: result)["status"]?.stringValue == WorkspaceStatus.settingUp.rawValue)
        #expect(try named("busy", in: result)["status"]?.stringValue == WorkspaceStatus.running.rawValue)
        #expect(try named("busy", in: result)["agent_running"]?.boolValue == true)
        #expect(try named("blocked", in: result)["status"]?.stringValue == WorkspaceStatus.awaitingPermission.rawValue)
        #expect(try named("blocked", in: result)["awaiting_permission"]?.boolValue == true)
        #expect(try named("blocked", in: result)["status_label"]?.stringValue == WorkspaceStatus.awaitingPermission.label)
        #expect(try named("idle", in: result)["agent_running"]?.boolValue == false)
    }

    @Test("a queued message carries the hold's own sentence for why it is not moving")
    func theHoldIsQuoted() async throws {
        let store = try makeTestStore("list-hold")
        let repo = try await store.upsert(
            Repo(name: "ember", path: "/tmp/ember", defaultBranch: "main")
        )
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id,
            name: "busy",
            branch: "b",
            path: "/tmp/w",
            baseBranch: "main",
            setupState: .running
        ))
        var session = Session(workspaceID: workspace.id, title: "First chat")
        session.apply(.turnStarted)
        _ = try await store.upsert(session)
        _ = try await store.enqueueDelivery(
            Delivery(targetSessionID: session.id, body: "and one more thing")
        )

        let result = await WorkspaceListTool().call(request(), as: .owner, store: store)
        let row = try named("busy", in: result)
        let chat = try #require(row["sessions"]?[0])

        #expect(row["queued_messages"]?.intValue == 1)
        #expect(chat["queued_messages"]?.intValue == 1)

        _ = try await store.enqueueDelivery(Delivery(targetSessionID: session.id, kind: .canvasComment, body: "look"))
        let withComment = try named("busy", in: await WorkspaceListTool().call(request(), as: .owner, store: store))
        #expect(withComment["queued_messages"]?.intValue == 1)
        #expect(withComment["sessions"]?[0]?["queued_messages"]?.intValue == 1)
        #expect(chat["hold_note"]?.stringValue == DeliveryHold.setup.sentence(on: .claudeCode))
        #expect(chat["state"]?.stringValue == "running")
        #expect(chat["title"]?.stringValue == "First chat")
        #expect(chat["agent"]?.stringValue == AgentKind.claudeCode.rawValue)
    }

    @Test("a running turn holds nothing to say on a backend that takes a message mid turn")
    func aRunningTurnSaysNothing() async throws {
        let store = try makeTestStore("list-hold-mid-turn")
        let repo = try await store.upsert(
            Repo(name: "ember", path: "/tmp/ember", defaultBranch: "main")
        )
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "busy", branch: "b", path: "/tmp/w", baseBranch: "main"
        ))
        var session = Session(workspaceID: workspace.id, title: "First chat")
        session.apply(.turnStarted)
        _ = try await store.upsert(session)

        let result = await WorkspaceListTool().call(request(), as: .owner, store: store)
        let row = try named("busy", in: result)
        let chat = try #require(row["sessions"]?[0])

        #expect(chat["state"]?.stringValue == "running")
        #expect(chat["hold_note"] == nil)
        #expect(AgentKind.claudeCode.acceptsMidTurnMessage)
    }

    @Test("an unanswered question is named, with the tool and the summary the CLI sent")
    func theQuestionIsNamed() async throws {
        let store = try makeTestStore("list-question")
        let repo = try await store.upsert(
            Repo(name: "ember", path: "/tmp/ember", defaultBranch: "main")
        )
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "blocked", branch: "b", path: "/tmp/w", baseBranch: "main"
        ))
        var session = Session(workspaceID: workspace.id, title: "First chat")
        session.apply(.turnStarted)
        session.apply(.blocked)
        _ = try await store.upsert(session)
        let ask = try #require(PermissionAsk.decode(payload: Data(PermissionAskTests.realAsk.utf8)))
        try await store.appendPermissionAsk(sessionID: session.id, ask: ask)

        let result = await WorkspaceListTool().call(request(), as: .owner, store: store)
        let question = try #require(named("blocked", in: result)["sessions"]?[0]?["questions"]?[0])

        #expect(question["tool"]?.stringValue == ask.label)
        #expect(question["summary"]?.stringValue == ask.summary)
    }

    @Test("each row says whether it is the project's orchestrator")
    func orchestratorIsReported() async throws {
        let store = try makeTestStore("list-orchestrator")
        let repo = try await store.upsert(Repo(name: "ember", path: "/tmp/ember", defaultBranch: "main"))
        let lead = try await store.upsert(Workspace(
            repoID: repo.id, name: "lead", branch: "b1", path: "/tmp/w1", baseBranch: "main"
        ))
        _ = try await store.upsert(Workspace(
            repoID: repo.id, name: "worker", branch: "b2", path: "/tmp/w2", baseBranch: "main"
        ))
        try await store.setOrchestrator(true, workspaceID: lead.id)

        let result = await WorkspaceListTool().call(request(), as: .owner, store: store)

        #expect(try named("lead", in: result)["orchestrator"]?.boolValue == true)
        #expect(try named("worker", in: result)["orchestrator"]?.boolValue == false)
    }

    @Test("who asked for it is told the same way whoami tells it")
    func parentageIsReported() async throws {
        let store = try makeTestStore("list-parentage")
        let repo = try await store.upsert(
            Repo(name: "ember", path: "/tmp/ember", defaultBranch: "main")
        )
        let parent = try await store.upsert(Workspace(
            repoID: repo.id, name: "parent", branch: "b1", path: "/tmp/w1", baseBranch: "main"
        ))
        _ = try await store.upsert(Workspace(
            repoID: repo.id, name: "child", branch: "b2", path: "/tmp/w2", baseBranch: "main",
            origin: .agent(parentWorkspaceID: parent.id, spawnToolUseID: "toolu_01")
        ))
        _ = try await store.upsert(Workspace(
            repoID: repo.id, name: "from a client", branch: "b3", path: "/tmp/w3", baseBranch: "main",
            origin: .ownerClient(spawnToolUseID: "toolu_02")
        ))

        let result = await WorkspaceListTool().call(request(), as: .owner, store: store)

        #expect(try named("parent", in: result)["created_by"]?.stringValue == "owner")
        #expect(try named("from a client", in: result)["created_by"]?.stringValue == "owner")
        let child = try named("child", in: result)
        #expect(child["created_by"]?["agent_in_workspace"]?.stringValue == parent.id.rawValue)
        #expect(child["created_by"]?["spawn_tool_use_id"]?.stringValue == "toolu_01")
    }

    @Test("the default answer says neither host was asked")
    func theDefaultSaysItDidNotLook() async throws {
        let store = try makeTestStore("list-nogithub")
        let repo = try await store.upsert(
            Repo(name: "ember", path: "/tmp/ember", defaultBranch: "main")
        )
        _ = try await store.upsert(Workspace(
            repoID: repo.id, name: "w", branch: "b", path: "/tmp/w", baseBranch: "main"
        ))

        let result = await WorkspaceListTool().call(request(), as: .owner, store: store)

        #expect(result.text.contains("Neither GitHub nor Bitbucket was asked"))
        #expect(result.text.contains("include_github"))
        #expect(try named("w", in: result)["pull_request"] == nil)
    }

    @Test("the description says what the default price does not buy")
    func theDescriptionSaysWhatItDoesNotInclude() {
        let description = WorkspaceListTool().tool.description

        #expect(description.contains("neither GitHub nor Bitbucket is consulted"))
        #expect(description.contains("do not report that a workspace has no pull request"))
        #expect(description.contains("slow on a long list"))
        #expect(description.contains("Read only"))
    }

    @Test("archived workspaces are out by default and in when asked for")
    func archived() async throws {
        let store = try makeTestStore("list-archived")
        let repo = try await store.upsert(
            Repo(name: "ember", path: "/tmp/ember", defaultBranch: "main")
        )
        _ = try await store.upsert(Workspace(
            repoID: repo.id, name: "live", branch: "b1", path: "/tmp/w1", baseBranch: "main"
        ))
        var gone = Workspace(
            repoID: repo.id, name: "gone", branch: "b2", path: "/tmp/w2", baseBranch: "main"
        )
        gone.archive()
        _ = try await store.upsert(gone)

        let byDefault = await WorkspaceListTool().call(request(), as: .owner, store: store)
        let withArchived = await WorkspaceListTool().call(
            request(["include_archived": .bool(true)]), as: .owner, store: store
        )

        #expect(try workspaces(byDefault).count == 1)
        #expect(byDefault.text.contains("Archived workspaces are not in this list."))
        #expect(try workspaces(withArchived).count == 2)
        #expect(try named("gone", in: withArchived)["state"]?.stringValue == "archived")
    }

    @Test("a named project narrows it, and the name is resolved the way every other tool does")
    func narrowingByProject() async throws {
        let store = try makeTestStore("list-project")
        let ember = try await store.upsert(
            Repo(name: "ember", path: "/tmp/ember", defaultBranch: "main")
        )
        let unifieddev = try await store.upsert(
            Repo(name: "unifieddev", path: "/tmp/unifieddev", defaultBranch: "main")
        )
        _ = try await store.upsert(Workspace(
            repoID: ember.id, name: "in ember", branch: "b1", path: "/tmp/w1", baseBranch: "main"
        ))
        _ = try await store.upsert(Workspace(
            repoID: unifieddev.id, name: "in unifieddev", branch: "b2", path: "/tmp/w2", baseBranch: "main"
        ))

        let byName = await WorkspaceListTool().call(
            request(["project": .string("EMBER")]), as: .owner, store: store
        )
        let byPath = await WorkspaceListTool().call(
            request(["project": .string("/tmp/unifieddev/")]), as: .owner, store: store
        )

        #expect(try workspaces(byName).map { $0["name"]?.stringValue } == ["in ember"])
        #expect(try workspaces(byPath).map { $0["name"]?.stringValue } == ["in unifieddev"])
    }

    @Test("a project Unified Dev does not have is refused, and told what it does have")
    func unknownProject() async throws {
        let store = try makeTestStore("list-unknown")
        _ = try await store.upsert(Repo(name: "ember", path: "/tmp/ember", defaultBranch: "main"))

        let result = await WorkspaceListTool().call(
            request(["project": .string("flair")]), as: .owner, store: store
        )

        #expect(result.isError)
        #expect(result.text.contains("'ember'"))
    }

    @Test("a project with nothing in it says so rather than answering with an empty list alone")
    func emptyProject() async throws {
        let store = try makeTestStore("list-empty-project")
        _ = try await store.upsert(Repo(name: "ember", path: "/tmp/ember", defaultBranch: "main"))

        let result = await WorkspaceListTool().call(
            request(["project": .string("ember")]), as: .owner, store: store
        )

        #expect(!result.isError)
        #expect(result.text.contains("no workspaces in 'ember'"))
    }
}
