import Foundation

public enum WorkspacePullRequestReading: Sendable, Equatable {
    case found(PullRequest, local: LocalWork?)
    case noPullRequest
    case unavailable(GitHubAccess)
    case failed(String)
}

public enum WorkspaceMergeHandoff: Sendable, Equatable {
    case turnBegun(chat: String)
    case refused(String)
}

public typealias WorkspaceMergeRequesting =
    @Sendable (Workspace, PullRequest, GitHub.MergeMethod) async -> WorkspaceMergeHandoff

public struct WorkspaceMergeTool: BridgeToolHandling {
    public typealias Reading = @Sendable (Workspace) async -> WorkspacePullRequestReading
    public typealias Hosting = @Sendable (Workspace) async -> ForgeKind

    private let merge: WorkspaceMergeRequesting
    private let read: Reading
    private let host: Hosting

    public init(
        read: @escaping Reading = WorkspaceMergeTool.ask,
        host: @escaping Hosting = { await Forge.kind(forDirectory: $0.path) },
        merge: @escaping WorkspaceMergeRequesting
    ) {
        self.read = read
        self.host = host
        self.merge = merge
    }

    public let roles: Set<BridgeRole> = [.owner]

    public let tool = BridgeTool(
        name: "workspace_merge",
        description: """
            Ask a workspace's own agent to merge its pull request.

            This does not merge anything. It composes the request Unified Dev's own Merge button \
            composes, with the project's merge instructions attached, and sends it into that \
            workspace's chat as an ordinary message. The agent runs `gh pr merge` there, or \
            `bkt pr merge` for a repository on Bitbucket, in front of the owner, under whatever \
            permission mode they set. If the host refuses for a conflict or a failed check, the \
            agent fixes it, pushes to the pull request's branch \
            and merges again, three times at most; any other refusal it reports.

            So it returns once the turn has begun, and the merging happens inside that turn, after \
            this call is over. Nothing has landed on GitHub when this answers, and the merge may \
            still not happen. Do not report a pull request as merged on the strength of this call. \
            Call workspace_list with include_github afterwards and read the state.

            It refuses a pull request GitHub will not take, a worktree holding work GitHub has not \
            got, and a workspace whose agent is busy. When it refuses, do not run `gh pr merge` \
            or `bkt pr merge` yourself and do not ask another agent to. Merging publishes to a \
            server other people share, and Unified Dev only does it where the owner can watch it \
            happen.

            Name the workspace by the id workspace_list reports, not by its name. It merges with the \
            method the project's Merge button shows unless you say otherwise.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "workspace": .object([
                    "type": .string("string"),
                    "description": .string(
                        "The workspace whose pull request to merge, by the id workspace_list "
                            + "reports. Not its name: two workspaces may share one."
                    ),
                ]),
                "method": .object([
                    "type": .string("string"),
                    "enum": .array(GitHub.MergeMethod.allCases.map { .string($0.rawValue) }),
                    "description": .string(
                        "How to merge it. Leave it out for the method the project's own Merge "
                            + "button shows, which is a merge commit unless the owner chose another."
                    ),
                ]),
            ]),
            "required": .array([.string("workspace")]),
        ])
    )

    public func call(
        _ request: MCPRequest,
        as identity: BridgeIdentity,
        store: Store
    ) async -> BridgeToolResult {
        guard let given = request.stringParam("workspace")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !given.isEmpty
        else {
            return .failure(
                "workspace_merge needs the workspace whose pull request to merge. Call "
                    + "workspace_list and pass the id it reports as 'id'."
            )
        }

        var asked: GitHub.MergeMethod?
        if let raw = request.stringParam("method") {
            guard let chosen = GitHub.MergeMethod(rawValue: raw) else {
                return .failure(
                    "Unified Dev does not know a merge method called '\(raw)'. It merges by "
                        + GitHub.MergeMethod.allCases.map { "'\($0.rawValue)'" }
                        .joined(separator: ", ")
                        + ". Leave the argument out for the project's own merge method."
                )
            }
            asked = chosen
        }

        let workspace: Workspace
        do {
            guard let found = try await BridgeProfileScope.workspace(
                id: WorkspaceID(given), for: identity, store: store
            ) else {
                return .failure(WorkspaceMergeTrouble.unknownWorkspace(
                    id: given, alias: try await alias(for: given, as: identity, store: store)
                ).sentence)
            }
            workspace = found
        } catch {
            return .failure("Unified Dev could not read that workspace: \(error.readableMessage)")
        }

        guard workspace.state != .archived else {
            return .failure(WorkspaceMergeTrouble.archived(workspace: workspace.name).sentence)
        }
        guard FileManager.default.fileExists(atPath: workspace.path) else {
            return .failure(WorkspaceMergeTrouble.worktreeGone(workspace: workspace.name).sentence)
        }

        do {
            if let hold = try await hold(on: workspace, store: store) {
                return .failure(
                    WorkspaceMergeTrouble.wouldQueue(workspace: workspace.name, hold: hold).sentence
                )
            }
        } catch {
            return .failure("Unified Dev could not read that workspace's chats: \(error.readableMessage)")
        }

        let forge = await host(workspace)
        let pullRequest: PullRequest
        let local: LocalWork?
        switch await read(workspace) {
        case .unavailable(let access):
            return .failure(WorkspaceMergeTrouble.forgeUnavailable(access, on: forge).sentence)
        case .failed(let message):
            return .failure(WorkspaceMergeTrouble.forgeSilent(message, on: forge).sentence)
        case .noPullRequest:
            return .failure(WorkspaceMergeTrouble.noPullRequest(
                workspace: workspace.name, branch: workspace.branch, on: forge
            ).sentence)
        case let .found(found, foundLocal):
            pullRequest = found
            local = foundLocal
        }

        let status = pullRequest.status(local: local)

        guard status.canMerge else {
            return .failure(WorkspaceMergeTrouble.blocked(
                workspace: workspace.name,
                number: pullRequest.number,
                headline: status.text,
                reason: status.blockedReason ?? "\(forge.displayName) will not take it in this state.",
                on: forge
            ).sentence)
        }

        if status.remedy != .merge, let local {
            return .failure(WorkspaceMergeTrouble.localWork(
                workspace: workspace.name,
                number: pullRequest.number,
                detail: PullRequest.localDetail(local),
                needsCommit: status.remedy == .commitAndPush,
                on: forge
            ).sentence)
        }

        let method: GitHub.MergeMethod
        if let asked {
            method = asked
        } else {
            method = await MergeMethodChoice.load(repoID: workspace.repoID, from: store)
        }

        switch await merge(workspace, pullRequest, method) {
        case .refused(let sentence):
            return .failure(WorkspaceMergeTrouble.appRefused(sentence).sentence)
        case .turnBegun(let chat):
            return .json(answer(
                workspace: workspace,
                pullRequest: pullRequest,
                method: method,
                chat: chat
            ))
        }
    }

    private func answer(
        workspace: Workspace,
        pullRequest: PullRequest,
        method: GitHub.MergeMethod,
        chat: String
    ) -> JSONValue {
        .object([
            "state": .string("turn_started"),
            "workspace_id": .string(workspace.id.rawValue),
            "workspace": .string(workspace.name),
            "chat": .string(chat),
            "pull_request": .integer(pullRequest.number),
            "url": .string(pullRequest.url),
            "base_branch": .string(pullRequest.targetBranch(or: workspace.baseBranch)),
            "method": .string(method.phrase),
            "note": .string(note(
                workspace: workspace, pullRequest: pullRequest, chat: chat
            )),
        ])
    }

    private func note(workspace: Workspace, pullRequest: PullRequest, chat: String) -> String {
        let forge = pullRequest.forge
        return """
        Nothing is merged. A turn has begun in '\(workspace.name)', in the chat '\(chat)': its \
        agent has been asked to merge #\(pullRequest.number) and it runs `\(forge.cli) pr merge` itself, \
        where the owner can watch it and answer anything it asks. Unified Dev does not wait for that \
        turn and there is no way to wait for it from here, so do not sit idle. The merge may still \
        not happen: \(forge.displayName) is allowed to refuse. The agent is told to fix a conflict or a failed \
        check and push it to the pull request's branch before merging again, three times at \
        most, and to stop and report any other refusal rather than force it. To find out what became of it, call workspace_list with \
        include_github and read the pull request's state.
        """
    }

    private func alias(
        for given: String, as identity: BridgeIdentity, store: Store
    ) async throws -> WorkspaceMergeTrouble.Alias {
        let all = try await BridgeProfileScope.workspaces(for: identity, store: store, includeArchived: true)
        let matches = all.filter {
            $0.name.caseInsensitiveCompare(given) == .orderedSame
                || $0.branch.caseInsensitiveCompare(given) == .orderedSame
        }
        guard let first = matches.first else { return .none }
        guard matches.count == 1 else {
            return .several(name: first.name, count: matches.count)
        }
        return .one(name: first.name, id: first.id.rawValue)
    }

    private func hold(on workspace: Workspace, store: Store) async throws -> DeliveryHold? {
        let sessions = try await store.sessions(workspaceID: workspace.id)
        let isRunningSetup = workspace.setupState == .running

        var held = DeliveryHold.of(
            isRunningSetup: isRunningSetup,
            isTurnRunning: false,
            isAwaitingQuestion: false
        )

        for session in sessions where held == .none {
            held = DeliveryHold.of(
                isRunningSetup: isRunningSetup,
                isTurnRunning: session.state == .running,
                isAwaitingQuestion: session.state == .waiting
            )
        }

        return held == .none ? nil : held
    }

    public static let ask: Reading = { workspace in
        if await Forge.kind(forDirectory: workspace.path) == .bitbucket { return await askBitbucket(workspace) }
        do {
            guard let pullRequest = try await GitHub.pullRequest(
                forBranch: workspace.branch, worktree: workspace.path
            ) else {
                let access = await GitHub.access(directory: workspace.path)
                return access == .ready ? .noPullRequest : .unavailable(access)
            }
            let local = try? await Git.localWork(worktree: workspace.path)
            return .found(pullRequest, local: local)
        } catch {
            let access = await GitHub.access(directory: workspace.path)
            return access == .ready ? .failed(plainly(error, on: .gitHub)) : .unavailable(access)
        }
    }

    static func askBitbucket(_ workspace: Workspace) async -> WorkspacePullRequestReading {
        do {
            guard let pullRequest = try await Bitbucket.snapshot(for: workspace, maxAge: .zero)?.pullRequest else {
                let access = await Bitbucket.access(directory: workspace.path)
                return access == .ready ? .noPullRequest : .unavailable(access)
            }
            let local = try? await Git.localWork(worktree: workspace.path)
            return .found(pullRequest, local: local)
        } catch {
            let access = await Bitbucket.access(directory: workspace.path)
            return access == .ready ? .failed(plainly(error, on: .bitbucket)) : .unavailable(access)
        }
    }

    static func plainly(_ error: any Error, on forge: ForgeKind) -> String {
        guard let shell = error as? ShellError else { return error.readableMessage }
        let stderr = shell.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stderr.isEmpty else { return "\(forge.cli) exited \(shell.status) without saying why." }
        return stderr.hasSuffix(".") ? stderr : stderr + "."
    }
}
