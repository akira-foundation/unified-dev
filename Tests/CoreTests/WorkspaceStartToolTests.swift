import Foundation
import Testing
@testable import Core

@Suite("workspace_start", .tags(.persistence), .scratchDirectory)
struct WorkspaceStartToolTests {
    private final class Recorder: @unchecked Sendable {
        var orders: [AgentWorkspaceOrder] = []
        var identities: [BridgeIdentity] = []
        var projects: [Repo] = []
        var origins: [WorkspaceOrigin] = []
        var failure: (any Error)?

        var spawnIDs: [String] { origins.compactMap(\.spawnToolUseID) }

        func tool() -> WorkspaceStartTool {
            WorkspaceStartTool { [self] order, project, identity, origin in
                try await record(order, project: project, identity: identity, origin: origin)
            }
        }

        func record(
            _ order: AgentWorkspaceOrder,
            project: Repo,
            identity: BridgeIdentity,
            origin: WorkspaceOrigin
        ) async throws -> StartedWorkspaceSummary {
            orders.append(order)
            identities.append(identity)
            projects.append(project)
            origins.append(origin)
            if let failure { throw failure }
            return StartedWorkspaceSummary(
                workspaceID: WorkspaceID(rawValue: "w-new"),
                name: order.name ?? "Named by Unified Dev",
                branch: "claude/named-by-unifieddev",
                path: "/tmp/worktrees/w-new"
            )
        }
    }

    private struct Fixture {
        let store: Store
        let identity: BridgeIdentity
        let workspace: Workspace
    }

    private func fixture(origin: WorkspaceOrigin = .user, label: String = "start") async throws -> Fixture {
        let store = try makeTestStore(label)
        let repo = try await store.upsert(Repo(name: "ember", path: "/tmp/ember", defaultBranch: "main"))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id,
            name: "group occurrences",
            branch: "claude/group-occurrences",
            path: "/tmp/ember-group",
            baseBranch: "main",
            origin: origin
        ))
        let session = try await store.upsert(Session(workspaceID: workspace.id, title: "First chat"))

        return Fixture(
            store: store,
            identity: BridgeIdentity(
                sessionID: session.id,
                workspaceID: workspace.id,
                role: .workspace
            ),
            workspace: workspace
        )
    }

    private func request(_ arguments: [String: JSONValue]) -> MCPRequest {
        MCPRequest(id: .number(1), method: "workspace_start", params: .object(arguments))
    }

    @Test("both roles see it")
    func roleGate() {
        let tool = Recorder().tool()

        #expect(tool.roles == [.workspace, .owner])
        #expect(BridgeToolbox(handlers: [tool]).tools(for: .workspace).map(\.name) == ["workspace_start"])
        #expect(BridgeToolbox(handlers: [tool]).tools(for: .owner).map(\.name) == ["workspace_start"])
    }

    @Test("a workspace started by an agent is refused even when it calls directly")
    func noGrandchildren() async throws {
        let fixture = try await self.fixture(
            origin: .agent(parentWorkspaceID: WorkspaceID(rawValue: "w-parent"), spawnToolUseID: "t1"),
            label: "start-child"
        )
        let recorder = Recorder()

        let result = await recorder.tool().call(
            request(["prompt": .string("do a thing")]), as: fixture.identity, store: fixture.store
        )

        #expect(result.isError)
        #expect(result.text.contains("itself started by an agent"))
        #expect(recorder.orders.isEmpty)
    }

    @Test("a prompt is all it needs, and the order carries who asked")
    func startsWithAPrompt() async throws {
        let fixture = try await fixture()
        let recorder = Recorder()

        let result = await recorder.tool().call(
            request(["prompt": .string("Port the importer to the new API")]),
            as: fixture.identity,
            store: fixture.store
        )

        #expect(!result.isError)
        #expect(recorder.orders.count == 1)
        #expect(recorder.orders[0].prompt == "Port the importer to the new API")
        #expect(recorder.identities[0].workspaceID == fixture.workspace.id)
    }

    @Test("the optional arguments travel, and blank ones do not")
    func optionalArguments() async throws {
        let fixture = try await fixture()
        let recorder = Recorder()

        _ = await recorder.tool().call(
            request([
                "prompt": .string("do a thing"),
                "name": .string("Sentry importer"),
                "base_branch": .string("develop"),
                "agent": .string("codex"),
                "model": .string("gpt-5.6-sol"),
            ]),
            as: fixture.identity,
            store: fixture.store
        )

        let order = try #require(recorder.orders.first)
        #expect(order.name == "Sentry importer")
        #expect(order.baseBranch == "develop")
        #expect(order.agent == .codex)
        #expect(order.model == "gpt-5.6-sol")

        _ = await recorder.tool().call(
            request(["prompt": .string("do a thing"), "name": .string("   ")]),
            as: fixture.identity,
            store: fixture.store
        )

        #expect(recorder.orders[1].name == nil)
    }

    @Test("no agent named means the caller's own, decided by the app rather than guessed here")
    func agentDefaultsToTheCallers() async throws {
        let fixture = try await fixture()
        let recorder = Recorder()

        _ = await recorder.tool().call(
            request(["prompt": .string("do a thing")]), as: fixture.identity, store: fixture.store
        )

        #expect(recorder.orders[0].agent == nil)
    }

    private func gitFixture(label: String) async throws -> (fixture: Fixture, repo: TempRepo) {
        let repo = try await TempRepo()
        try await Shell.check("git", ["branch", "freek/figma"], cwd: repo.path)

        let store = try makeTestStore(label)
        let project = try await store.upsert(
            Repo(name: "ember", path: repo.path, defaultBranch: "main")
        )
        let workspace = try await store.upsert(Workspace(
            repoID: project.id,
            name: "group occurrences",
            branch: "claude/group-occurrences",
            path: "/tmp/ember-group",
            baseBranch: "main"
        ))
        let session = try await store.upsert(Session(workspaceID: workspace.id, title: "First chat"))

        return (
            Fixture(
                store: store,
                identity: BridgeIdentity(
                    sessionID: session.id, workspaceID: workspace.id, role: .workspace
                ),
                workspace: workspace
            ),
            repo
        )
    }

    @Test("a call naming an existing branch starts on that branch", .tags(.git, .subprocess))
    func startsOnAnExistingBranch() async throws {
        let (fixture, repo) = try await gitFixture(label: "start-existing")
        defer { repo.cleanUp() }
        let recorder = Recorder()

        let result = await recorder.tool().call(
            request([
                "prompt": .string("Read what is on this branch and fix the failing test"),
                "existing_branch": .string("freek/figma"),
            ]),
            as: fixture.identity,
            store: fixture.store
        )

        #expect(!result.isError)
        let order = try #require(recorder.orders.first)
        #expect(order.source.tab == .existingBranch)
        #expect(order.source.checkout == .branch(ExistingBranch(name: "freek/figma", isLocal: true)))
        #expect(order.source.baseBranch == nil)
    }

    @Test("a call naming a pull request preserves the pull request checkout")
    func startsOnAPullRequest() async throws {
        let fixture = try await fixture(label: "start-pull-request")
        let recorder = Recorder()
        let pullRequest = PullRequestListing(
            number: 66,
            title: "Add name suffix",
            headRefName: "name-suffix",
            baseRefName: "main"
        )
        let tool = WorkspaceStartTool(
            start: { order, project, identity, origin in
                try await recorder.record(
                    order, project: project, identity: identity, origin: origin
                )
            },
            resolvePullRequest: { reference, path in
                #expect(reference == "#66")
                #expect(path == "/tmp/ember")
                return .checkout(.pullRequest(pullRequest))
            }
        )

        let result = await tool.call(
            request([
                "prompt": .string("Review the existing pull request"),
                "pull_request": .string("#66"),
            ]),
            as: fixture.identity,
            store: fixture.store
        )

        #expect(!result.isError)
        #expect(recorder.orders.first?.source == .pullRequest(pullRequest))
    }

    @Test("a call naming neither still cuts a new branch, as it always did", .tags(.git, .subprocess))
    func defaultsToANewBranch() async throws {
        let (fixture, repo) = try await gitFixture(label: "start-default")
        defer { repo.cleanUp() }
        let recorder = Recorder()

        _ = await recorder.tool().call(
            request(["prompt": .string("do a thing")]), as: fixture.identity, store: fixture.store
        )

        let order = try #require(recorder.orders.first)
        #expect(order.source == .newBranch(from: nil))
        #expect(order.source.checkout == nil)
    }

    @Test("a branch that is not in the project is refused, with what is", .tags(.git, .subprocess))
    func refusesABranchThatIsNotThere() async throws {
        let (fixture, repo) = try await gitFixture(label: "start-missing-branch")
        defer { repo.cleanUp() }
        let recorder = Recorder()

        let result = await recorder.tool().call(
            request([
                "prompt": .string("do a thing"),
                "existing_branch": .string("freek/figmaa"),
            ]),
            as: fixture.identity,
            store: fixture.store
        )

        #expect(result.isError)
        #expect(result.text.contains("no branch called 'freek/figmaa'"))
        #expect(result.text.contains("'freek/figma'"))
        #expect(recorder.orders.isEmpty)
    }

    @Test("the branch the project itself is on is refused, by its path", .tags(.git, .subprocess))
    func refusesTheProjectsOwnBranch() async throws {
        let (fixture, repo) = try await gitFixture(label: "start-held-branch")
        defer { repo.cleanUp() }
        let recorder = Recorder()

        let result = await recorder.tool().call(
            request(["prompt": .string("do a thing"), "existing_branch": .string("main")]),
            as: fixture.identity,
            store: fixture.store
        )

        #expect(result.isError)
        #expect(result.text.contains("the project itself is on"))
        #expect(result.text.contains("base_branch"))
        #expect(recorder.orders.isEmpty)
    }

    @Test("naming both branch arguments is refused before anything is looked up")
    func refusesBothBranchArguments() async throws {
        let fixture = try await fixture()
        let recorder = Recorder()

        let result = await recorder.tool().call(
            request([
                "prompt": .string("do a thing"),
                "base_branch": .string("main"),
                "existing_branch": .string("freek/figma"),
            ]),
            as: fixture.identity,
            store: fixture.store
        )

        #expect(result.isError)
        #expect(result.text.contains("base_branch"))
        #expect(result.text.contains("existing_branch"))
        #expect(recorder.orders.isEmpty)
    }

    @Test("a missing or empty prompt is refused before anything is created")
    func promptIsRequired() async throws {
        let fixture = try await fixture()
        let recorder = Recorder()

        for arguments in [[:], ["prompt": JSONValue.string("   ")]] {
            let result = await recorder.tool().call(
                request(arguments), as: fixture.identity, store: fixture.store
            )
            #expect(result.isError)
        }

        #expect(recorder.orders.isEmpty)
    }

    @Test("an agent Unified Dev cannot run is refused, and the refusal says which ones it can")
    func unrunnableAgent() async throws {
        let fixture = try await fixture()
        let recorder = Recorder()

        let result = await recorder.tool().call(
            request(["prompt": .string("do a thing"), "agent": .string("cursor")]),
            as: fixture.identity,
            store: fixture.store
        )

        #expect(result.isError)
        #expect(result.text.contains("claudeCode"))
        #expect(result.text.contains("codex"))
        #expect(recorder.orders.isEmpty)
    }

    @Test("a caller whose workspace has been archived away is told so rather than crashing")
    func callerIsGone() async throws {
        let fixture = try await fixture()
        let recorder = Recorder()

        let result = await recorder.tool().call(
            request(["prompt": .string("do a thing")]),
            as: BridgeIdentity(
                sessionID: fixture.identity.sessionID ?? SessionID(rawValue: "s-gone"),
                workspaceID: WorkspaceID(rawValue: "w-vanished"),
                role: .workspace
            ),
            store: fixture.store
        )

        #expect(result.isError)
        #expect(result.text.contains("no longer in Unified Dev's database"))
    }

    @Test("a caller that already holds the limit is refused")
    func limit() async throws {
        let fixture = try await fixture()
        let recorder = Recorder()

        for index in 0..<WorkspaceStartAllowance.maximumChildren {
            _ = try await fixture.store.upsert(Workspace(
                repoID: fixture.workspace.repoID,
                name: "child \(index)",
                branch: "claude/child-\(index)",
                path: "/tmp/child-\(index)",
                baseBranch: "main",
                origin: .agent(parentWorkspaceID: fixture.workspace.id, spawnToolUseID: "t\(index)")
            ))
        }

        let result = await recorder.tool().call(
            request(["prompt": .string("one more")]), as: fixture.identity, store: fixture.store
        )

        #expect(result.isError)
        #expect(result.text.contains("not archived"))
        #expect(recorder.orders.isEmpty)
    }

    @Test("a retry from a caller at its limit gets the workspace it already made, not a refusal")
    func retryAtTheLimitIsNotRefused() async throws {
        let fixture = try await fixture()
        let recorder = Recorder()
        let call = request(["prompt": .string("one more")])

        let order = AgentWorkspaceOrder(prompt: "one more")
        _ = try await fixture.store.upsert(Workspace(
            repoID: fixture.workspace.repoID,
            name: "the first answer",
            branch: "claude/one-more",
            path: "/tmp/one-more",
            baseBranch: "main",
            origin: .agent(
                parentWorkspaceID: fixture.workspace.id,
                spawnToolUseID: order.spawnID(parentWorkspaceID: fixture.workspace.id)
            )
        ))
        for index in 0..<WorkspaceStartAllowance.maximumChildren {
            _ = try await fixture.store.upsert(Workspace(
                repoID: fixture.workspace.repoID,
                name: "child \(index)",
                branch: "claude/child-\(index)",
                path: "/tmp/child-\(index)",
                baseBranch: "main",
                origin: .agent(parentWorkspaceID: fixture.workspace.id, spawnToolUseID: "t\(index)")
            ))
        }

        let result = await recorder.tool().call(call, as: fixture.identity, store: fixture.store)

        #expect(!result.isError)
        #expect(result.text.contains("already_started"))
        #expect(result.text.contains("the first answer"))
        #expect(recorder.orders.isEmpty)
    }

    @Test("archived children do not count against the limit, because it counts what is not archived")
    func archivedChildrenDoNotCount() async throws {
        let fixture = try await fixture()
        let recorder = Recorder()

        for index in 0..<WorkspaceStartAllowance.maximumChildren {
            var child = Workspace(
                repoID: fixture.workspace.repoID,
                name: "child \(index)",
                branch: "claude/child-\(index)",
                path: "/tmp/child-\(index)",
                baseBranch: "main",
                origin: .agent(parentWorkspaceID: fixture.workspace.id, spawnToolUseID: "t\(index)")
            )
            child.state = .archived
            _ = try await fixture.store.upsert(child)
        }

        let result = await recorder.tool().call(
            request(["prompt": .string("one more")]), as: fixture.identity, store: fixture.store
        )

        #expect(!result.isError)
    }

    @Test("the answer names the workspace and says the work has not happened yet")
    func answerDoesNotClaimCompletion() async throws {
        let fixture = try await fixture()
        let recorder = Recorder()

        let result = await recorder.tool().call(
            request(["prompt": .string("do a thing"), "name": .string("Sentry importer")]),
            as: fixture.identity,
            store: fixture.store
        )

        #expect(!result.isError)
        #expect(result.text.contains("w-new"))
        #expect(result.text.contains("Sentry importer"))
        #expect(result.text.contains("starting"))
        #expect(result.text.contains("cannot wait for it"))
    }

    @Test("a failure to start is told to the model rather than to the transport")
    func startFailureIsAResult() async throws {
        let fixture = try await fixture()
        let recorder = Recorder()
        recorder.failure = AgentRunnerError.previousRunStillExiting

        let result = await recorder.tool().call(
            request(["prompt": .string("do a thing")]), as: fixture.identity, store: fixture.store
        )

        #expect(result.isError)
        #expect(result.text.contains("could not start"))
    }

    @Test("a start that failed in a repository with no commits says so through the tool")
    func startFailureIsDiagnosed() async throws {
        let repoPath = TestScratch.unique("unifieddev-git")
        try FileManager.default.createDirectory(atPath: repoPath, withIntermediateDirectories: true)
        try await Shell.check("git", ["init", "-q", "-b", "main"], cwd: repoPath)

        let store = try makeTestStore("diagnosed")
        let repo = try await store.upsert(Repo(name: "ember", path: repoPath, defaultBranch: "main"))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id,
            name: "group occurrences",
            branch: "claude/group-occurrences",
            path: repoPath,
            baseBranch: "main"
        ))
        let session = try await store.upsert(Session(workspaceID: workspace.id, title: "First chat"))

        let recorder = Recorder()
        recorder.failure = ShellError(
            command: "git worktree add -b do-thing -- \(repoPath)/do-thing main",
            status: 128,
            stderr: "fatal: invalid reference: main"
        )

        let result = await recorder.tool().call(
            request(["prompt": .string("do a thing")]),
            as: BridgeIdentity(sessionID: session.id, workspaceID: workspace.id, role: .workspace),
            store: store
        )

        #expect(result.isError)
        #expect(result.text.contains("'ember' has no commits yet"))
        #expect(!result.text.contains("invalid reference"))
        #expect(!result.text.contains("worktree add"))
    }

    @Test("the description tells the model the three things it would otherwise assume")
    func descriptionSaysWhatMatters() {
        let description = Recorder().tool().tool.description

        #expect(description.contains("not when its work is done"))
        #expect(description.contains("cannot see this conversation"))
        #expect(description.contains(WorkspaceSourceTab.newBranch.title))
        #expect(description.contains(WorkspaceSourceTab.existingBranch.title))
        #expect(description.contains(WorkspaceSourceTab.existingBranch.explanation))
        #expect(description.contains("existing_branch"))
        #expect(description.contains("real money"))
        #expect(!description.lowercased().contains("subagent"))
    }
}

@Suite("workspace_start: not twice", .tags(.persistence), .scratchDirectory)
struct WorkspaceStartDedupTests {
    private final class Counter: @unchecked Sendable {
        private(set) var value = 0
        func bump() { value += 1 }
    }

    private func order(prompt: String = "Import the webhooks", name: String? = nil) -> AgentWorkspaceOrder {
        AgentWorkspaceOrder(prompt: prompt, name: name)
    }

    private let parent = WorkspaceID(rawValue: "w-parent")

    @Test("the same call names itself the same way twice")
    func stableAcrossCalls() {
        #expect(order().spawnID(parentWorkspaceID: parent) == order().spawnID(parentWorkspaceID: parent))
    }

    @Test("a different call, or a different parent, is a different spawn")
    func differsWhereItShould() {
        let base = order().spawnID(parentWorkspaceID: parent)

        #expect(order(prompt: "Something else").spawnID(parentWorkspaceID: parent) != base)
        #expect(order(name: "Named").spawnID(parentWorkspaceID: parent) != base)
        #expect(order().spawnID(parentWorkspaceID: WorkspaceID(rawValue: "w-other")) != base)
        #expect(
            AgentWorkspaceOrder(prompt: "Import the webhooks", model: "gpt-5.6-sol")
                .spawnID(parentWorkspaceID: parent) != base
        )
    }

    @Test("it is short enough to read in a log")
    func shortEnough() {
        let id = order().spawnID(parentWorkspaceID: parent)

        #expect(id.count == 16)
        #expect(id.filter(\.isHexDigit).count == id.count)
    }

    @Test("a repeat of a call answers with the workspace the first one made, and cuts nothing")
    func repeatIsRecognised() async throws {
        let store = try makeTestStore("start-dedup")
        let repo = try await store.upsert(Repo(name: "ember", path: "/tmp/ember", defaultBranch: "main"))
        let caller = try await store.upsert(Workspace(
            repoID: repo.id, name: "parent", branch: "main-work", path: "/tmp/parent",
            baseBranch: "main", origin: .user
        ))
        let session = try await store.upsert(Session(workspaceID: caller.id, title: "chat"))
        let identity = BridgeIdentity(sessionID: session.id, workspaceID: caller.id, role: .workspace)

        let starts = Counter()
        let tool = WorkspaceStartTool { _, _, _, origin in
            starts.bump()
            _ = try await store.upsert(Workspace(
                repoID: repo.id,
                name: "the child",
                branch: "claude/the-child",
                path: "/tmp/child",
                baseBranch: "main",
                origin: origin
            ))
            return StartedWorkspaceSummary(
                workspaceID: WorkspaceID(rawValue: "w-child"), name: "the child",
                branch: "claude/the-child", path: "/tmp/child"
            )
        }

        let request = MCPRequest(
            id: .number(1), method: "workspace_start",
            params: .object(["prompt": .string("Import the webhooks")])
        )

        let first = await tool.call(request, as: identity, store: store)
        let second = await tool.call(request, as: identity, store: store)

        #expect(!first.isError)
        #expect(!second.isError)
        #expect(starts.value == 1)
        #expect(second.text.contains("already_started"))
        #expect(second.text.contains("Nothing new was created"))
    }
}

@Suite("Unified Dev's own tools")
struct BridgeToolApprovalTests {
    @Test("Unified Dev answers for the tools it wrote")
    func ownToolsAreApproved() {
        #expect(BridgeToolApproval.isSelfApproved(toolName: "mcp__unifieddev-workspace-bridge__whoami"))
        #expect(BridgeToolApproval.isSelfApproved(toolName: "mcp__unifieddev-workspace-bridge__workspace_start"))
    }

    @Test("it answers for nothing else, whoever is asking")
    func everythingElseStillAsks() {
        for name in ["Bash", "Write", "Edit", "WebFetch", "mcp__figma__create_new_file"] {
            #expect(!BridgeToolApproval.isSelfApproved(toolName: name))
        }
    }

    @Test("a lookalike server name is not Unified Dev")
    func lookalikesAreRefused() {
        #expect(!BridgeToolApproval.isSelfApproved(toolName: "mcp__unifieddev-workspace-bridge-evil__workspace_start"))
        #expect(!BridgeToolApproval.isSelfApproved(toolName: "mcp__other__workspace_start"))
        #expect(!BridgeToolApproval.isSelfApproved(toolName: "workspace_start"))
    }

    @Test("a tool of ours that is not on the list still asks")
    func newToolsAreNotAutomaticallyIn() {
        #expect(!BridgeToolApproval.isSelfApproved(toolName: "mcp__unifieddev-workspace-bridge__workspace_archive"))
    }

    @Test("the prefix follows the server's name rather than repeating it")
    func prefixIsComposed() {
        #expect(BridgeToolApproval.toolPrefix == "mcp__\(BridgeRegistration.serverName)__")
    }

    @Test("every self-approved name is one of the bridge's own tools")
    func selfApprovedAreOurs() {
        for name in BridgeToolApproval.selfApproved {
            #expect(BridgeToolApproval.isSelfApproved(toolName: BridgeToolApproval.toolPrefix + name))
        }
    }
}
