import Foundation

public struct WorkspaceListTool: BridgeToolHandling {
    public init() {}

    public let roles: Set<BridgeRole> = [.workspace, .owner]

    public func isServed(to identity: BridgeIdentity, store: Store) async -> Bool {
        guard identity.role == .workspace else { return true }
        return (try? await BridgeProfileReach.mayLeaveOwnProfile(identity, for: .talk, store: store)) ?? false
    }

    public let tool = BridgeTool(
        name: "workspace_list",
        description: """
            The workspaces Unified Dev has: what each one is, what state it is in, and where its \
            worktree is on disk. This is how you find out what became of a workspace you \
            started, since workspace_start answers before any work happens and nothing waits \
            for it.

            Only the workspaces in the caller's profile are listed, unless profile names another \
            this connection can reach. A workspace that is not its project's orchestrator is shown \
            the orchestrators alone, by id, name and project, since another profile is reached \
            through them.

            Each one carries its id, name, branch, base branch and worktree path, its project, \
            whether it is active or archived, how far its setup script got, whether an agent is \
            running in it, whether one has stopped on a permission question and what it asked, \
            whether there is output nobody has read, the size of its diff, who asked for it, its \
            chats with their cost and context size, and any messages queued for those chats with \
            the reason the queue is not moving.

            The worktree path is the most useful thing here. It is an ordinary git checkout, so \
            read the diff, the log and the files in it with your own tools rather than asking \
            Unified Dev for them. For a workspace in another profile, use chat_read and \
            workspace_diff instead, whose answers are marked as coming from outside.

            agent_running is about right now, and a workspace with nothing running is still a \
            workspace: most of them sit idle most of the time, waiting to be read and merged. \
            project_list counts these same rows, so its workspaces for a project is how many \
            appear here for it and its agents_running is how many of those are marked \
            agent_running. If the two ever look as though they disagree, one of them is being \
            read as the other's number.

            By default it reads Unified Dev's database and nothing else, and at that price neither \
            GitHub nor Bitbucket is consulted at all: there is no pull request, no checks, and the status can never \
            say merged, closed, draft or anything about checks. A default call has not looked, so \
            do not report that a workspace has no pull request on the strength of one. Pass \
            include_github to ask, which costs one gh call and one git call per workspace, or \
            several bkt calls for a repository on Bitbucket, and is slow on a long list.

            The diff counts and the states come from Unified Dev's database, which a running Unified Dev \
            refreshes every few seconds. With Unified Dev closed they are as old as the last time it \
            was open. Read only. It changes nothing and starts nothing.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                BridgeProfileReach.argument: BridgeProfileReach.listSchemaProperty,
                "project": .object([
                    "type": .string("string"),
                    "description": .string(
                        "Narrow it to one project, by the name or the path project_list reports. "
                            + "Leave it out for every project."
                    ),
                ]),
                "include_archived": .object([
                    "type": .string("boolean"),
                    "description": .string(
                        "Include workspaces that have been archived. They have no worktree left "
                            + "on disk. Off by default."
                    ),
                ]),
                "include_github": .object([
                    "type": .string("boolean"),
                    "description": .string(
                        "Include pull request and check state. Costs one gh call and one git call "
                            + "per workspace, or several bkt calls on Bitbucket, so it is slow on a "
                            + "long list. Off by default."
                    ),
                ]),
            ]),
            "required": .array([]),
        ])
    )

    public func call(
        _ request: MCPRequest,
        as identity: BridgeIdentity,
        store: Store
    ) async -> BridgeToolResult {
        let includeArchived = request.param("include_archived")?.boolValue ?? false
        let includeGitHub = request.param("include_github")?.boolValue ?? false

        do {
            let choice: BridgeProfileChoice
            switch try await BridgeProfileReach.choice(request, allowsEvery: true, for: .talk, as: identity, store: store) {
            case .failure(let trouble): return .failure(trouble.sentence)
            case .success(let resolved): choice = resolved
            }
            let reached = choice.profiles
            if includeGitHub, case .every = choice {
                return .failure(
                    "include_github cannot be used with profile 'all', because it starts a gh or bkt and "
                        + "a git process per workspace. Name one profile to ask the host about it."
                )
            }
            let every = try await store.repos()
            let projects = reached.isEmpty
                ? try await BridgeProfileScope.repos(for: identity, store: store)
                : reached.flatMap { ProfileScope.repos(every, in: $0.id) }
            var project: Repo?

            if let named = named(request) {
                let outcome = BridgeProjectLookup.find(named, in: projects)
                if let refusal = BridgeProjectLookup.refusal(
                    for: named, outcome: outcome, projects: projects
                ) {
                    return .failure(reached.isEmpty ? refusal : Self.noProjectThere(named))
                }
                guard case .found(let found) = outcome else {
                    return .failure("Unified Dev has no project called '\(named)'.")
                }
                project = found
            }

            let census = reached.isEmpty
                ? try await BridgeWorkspaceCensus.read(for: identity, from: store)
                : try await BridgeWorkspaceCensus.read(in: reached, from: store)
            let caller = try await BridgeProfileReach.caller(of: identity, store: store)
            let briefly = caller == .workspace
            let workspaces = census.listing(repoID: project?.id, includeArchived: includeArchived)
                .filter { BridgeProfileReach.lists($0, to: caller) }

            let names = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
            var rows: [JSONValue] = []
            for workspace in workspaces {
                let listed = briefly
                    ? WorkspaceListBriefRow.row(workspace, project: names[workspace.repoID])
                    : await row(
                        for: workspace,
                        project: names[workspace.repoID],
                        census: census,
                        includeGitHub: includeGitHub,
                        store: store
                    )
                let owner = reached.first { $0.id == names[workspace.repoID]?.profileID }
                rows.append(owner.map { BridgeProfileReach.tagged(listed, profile: $0) } ?? listed)
            }

            let answer: JSONValue = .object([
                "workspaces": .array(rows),
                "count": .integer(rows.count),
                "note": .string(note(
                    count: rows.count,
                    project: project,
                    includeArchived: includeArchived,
                    includeGitHub: includeGitHub
                )),
            ])
            guard !reached.isEmpty || identity.role == .workspace else { return .json(answer) }
            return BridgeWorkspaceQuote.answer(answer, preamble: BridgeWorkspaceQuote.lists("workspaces"))
        } catch {
            return .failure("Unified Dev could not read its workspaces: \(error.readableMessage)")
        }
    }

    private static func noProjectThere(_ named: String) -> String {
        "No project called '\(WorkspaceMessage.oneLine(named))' can be listed there, or the name is shared. "
            + "Call project_list with the same profile for its ids."
    }

    private func note(
        count: Int,
        project: Repo?,
        includeArchived: Bool,
        includeGitHub: Bool
    ) -> String {
        var sentences: [String] = []

        if count == 0 {
            sentences.append(
                project.map { "Unified Dev has no workspaces in '\($0.name)'." }
                    ?? "There are no workspaces here."
            )
            if !includeArchived {
                sentences.append("Archived ones were not counted. Pass include_archived to see them.")
            }
        } else if !includeArchived {
            sentences.append("Archived workspaces are not in this list.")
        }

        sentences.append(
            includeGitHub
                ? "GitHub, or Bitbucket for a repository hosted there, was asked about every "
                    + "workspace with a worktree still on disk. A workspace with no pull_request "
                    + "has no pull request for its branch, or gh, or bkt on Bitbucket, is not "
                    + "installed or not signed in."
                : "Neither GitHub nor Bitbucket was asked, so nothing here says anything about pull "
                    + "requests or checks, and status cannot report either. Pass include_github to ask."
        )

        return sentences.joined(separator: " ")
    }

    private func named(_ request: MCPRequest) -> String? {
        guard let text = request.stringParam("project") else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func row(
        for workspace: Workspace,
        project: Repo?,
        census: BridgeWorkspaceCensus,
        includeGitHub: Bool,
        store: Store
    ) async -> JSONValue {
        let sessions = (try? await store.sessions(workspaceID: workspace.id)) ?? []
        let isRunning = census.isRunning(workspace.id)
        let isAwaiting = census.isAwaitingPermission(workspace.id)

        let pullRequest = includeGitHub
            ? await self.pullRequest(for: workspace, store: store)
            : nil
        let status = WorkspaceStatus.resolve(
            workspace: workspace,
            isRunning: isRunning,
            pullRequest: pullRequest,
            isAwaitingPermission: isAwaiting
        )

        var sessionRows: [JSONValue] = []
        var queued = 0
        for session in sessions {
            let asks = (try? await store.pendingPermissionAsks(sessionID: session.id)) ?? []
            let pending = Delivery.messages(in: (try? await store.pendingDeliveries(sessionID: session.id)) ?? [])
            queued += pending.count
            sessionRows.append(self.row(
                for: session, in: workspace, asks: asks, pending: pending.count
            ))
        }

        var answer: [String: JSONValue] = [
            "id": .string(workspace.id.rawValue),
            "name": .string(workspace.name),
            "branch": .string(workspace.branch),
            "base_branch": .string(workspace.baseBranch),
            "path": .string(workspace.path),
            "state": .string(workspace.state.rawValue),
            "setup_state": .string(workspace.setupState.rawValue),
            "status": .string(status.rawValue),
            "status_label": .string(status.label),
            "agent_running": .bool(isRunning),
            "awaiting_permission": .bool(isAwaiting),
            "unread": .bool(workspace.unread),
            "diff": .object([
                "additions": .integer(workspace.additions),
                "deletions": .integer(workspace.deletions),
                "changed_files": .integer(workspace.changedFiles),
            ]),
            "sessions": .array(sessionRows),
            "queued_messages": .integer(queued),
            "created_at": .string(workspace.createdAt.formatted(.iso8601)),
            "last_activity_at": .string(workspace.lastActivityAt.formatted(.iso8601)),
        ]

        if let project {
            answer["project"] = .object([
                "id": .string(project.id.rawValue),
                "name": .string(project.name),
                "path": .string(project.path),
            ])
        }

        answer["orchestrator"] = .bool(workspace.isOrchestrator)

        switch workspace.origin {
        case .user, .ownerClient:
            answer["created_by"] = .string("owner")
        case .agent(let parentWorkspaceID, let spawnToolUseID):
            answer["created_by"] = .object([
                "agent_in_workspace": .string(parentWorkspaceID.rawValue),
                "spawn_tool_use_id": .string(spawnToolUseID),
            ])
        }

        if let pullRequest {
            answer["pull_request"] = await self.row(
                for: pullRequest, in: workspace
            )
        }

        return .object(answer)
    }

    private func row(
        for session: Session,
        in workspace: Workspace,
        asks: [PendingPermissionAsk],
        pending: Int
    ) -> JSONValue {
        let hold = DeliveryHold.of(
            isRunningSetup: workspace.setupState == .running,
            isTurnRunning: session.state == .running,
            isAwaitingQuestion: session.state == .waiting
        )

        var answer: [String: JSONValue] = [
            "id": .string(session.id.rawValue),
            "title": .string(session.title),
            "agent": .string(session.agentKind.rawValue),
            "state": .string(session.state.rawValue),
            "cost_usd": .number(session.costUSD),
            "context_tokens": .integer(session.contextTokens),
            "queued_messages": .integer(pending),
        ]

        if let note = hold.sentence(on: session.agentKind) {
            answer["hold_note"] = .string(note)
        }

        if !asks.isEmpty {
            answer["questions"] = .array(asks.map {
                .object([
                    "tool": .string($0.ask.label),
                    "summary": .string($0.ask.summary),
                ])
            })
        }

        return .object(answer)
    }

    private func pullRequest(for workspace: Workspace, store: Store) async -> PullRequest? {
        guard FileManager.default.fileExists(atPath: workspace.path) else { return nil }
        let found = try? await ForgePullRequests.pullRequest(for: workspace, maxAge: .seconds(60))
        await PullRequestNumber.record(found, for: workspace, in: store)
        return found
    }

    private func row(for pullRequest: PullRequest, in workspace: Workspace) async -> JSONValue {
        let local = try? await Git.localWork(worktree: workspace.path)
        let status = pullRequest.status(local: local)

        var answer: [String: JSONValue] = [
            "number": .integer(pullRequest.number),
            "url": .string(pullRequest.url),
            "state": .string(pullRequest.state),
            "draft": .bool(pullRequest.isDraft),
            "checks": .string(pullRequest.checks.rawValue),
            "checks_summary": .string(pullRequest.checksSummary),
            "headline": .string(status.text),
            "can_merge": .bool(status.canMerge),
            "blocked_reason": status.blockedReason.map(JSONValue.string) ?? .null,
            "remedy": .string(remedy(status.remedy)),
        ]

        if let detail = status.detail, !detail.isEmpty {
            answer["detail"] = .string(detail)
        }

        if let local {
            answer["local"] = .object([
                "files_to_commit": .integer(local.modifiedFiles + local.untrackedFiles),
                "commits_to_push": .integer(local.hasUnpushed ? local.unpushedCommits : 0),
            ])
        }

        return .object(answer)
    }

    private func remedy(_ remedy: PullRequestStatus.Remedy) -> String {
        switch remedy {
        case .merge: "merge"
        case .markReadyForReview: "markReadyForReview"
        case .push: "push"
        case .commitAndPush: "commitAndPush"
        case .fixConflicts: "fixConflicts"
        }
    }
}
