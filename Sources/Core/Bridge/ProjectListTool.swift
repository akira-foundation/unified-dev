import Foundation

public struct ProjectListTool: BridgeToolHandling {
    public init() {}

    public let roles: Set<BridgeRole> = [.workspace, .owner]

    public let tool = BridgeTool(
        name: "project_list",
        description: """
            The projects Unified Dev knows about: the name and the path of each git repository \
            registered in the sidebar, its default branch, how many workspaces it has, how many \
            of those have an agent working or stopped on a question, whether it is still where \
            Unified Dev recorded it, and whether the owner has hidden it from the sidebar.

            Those are three different numbers and none of them stands in for another. \
            workspaces counts the worktrees the project has that nobody has archived, whether or \
            not anything is happening in them, and it is what the sidebar draws under the \
            project. agents_running counts how many of those have an agent mid turn right now, \
            and awaiting_permission how many have one stopped on a permission question. A \
            project with workspaces and agents_running 0 has worktrees sitting idle, which is not \
            the same as having none, and a project with workspaces 0 has none at all.

            workspace_list, for a caller that has it, names those same workspaces one by one and \
            is counted from the same rows, so this project's workspaces is how many it lists for \
            the project and its agents_running is how many of them it marks agent_running.

            Call it before naming a project in any other tool, workspace_start included, because \
            Unified Dev will only act on repositories it already has and this is the list of them. Every project here can be \
            worked in, hidden or not: hidden is a view preference of the owner's sidebar and \
            says nothing about whether the project is finished with. Reads \
            nothing but Unified Dev's own database, changes nothing and costs nothing.

            Only the projects in the caller's profile are listed, unless profile names another \
            this connection can reach.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([BridgeProfileReach.argument: BridgeProfileReach.listSchemaProperty]),
            "required": .array([]),
        ])
    )

    public func call(
        _ request: MCPRequest,
        as identity: BridgeIdentity,
        store: Store
    ) async -> BridgeToolResult {
        do {
            switch try await BridgeProfileReach.choice(request, allowsEvery: true, for: .talk, as: identity, store: store) {
            case .failure(let trouble): return .failure(trouble.sentence)
            case .success(.own): break
            case .success(let choice): return try await across(choice.profiles, store: store)
            }
            let projects = try await BridgeProfileScope.repos(for: identity, store: store)
            guard !projects.isEmpty else {
                let register = identity.role == .owner
                    ? "Register an existing git repository with project_add."
                    : "Only the owner can register one."
                return .json(.object([
                    "projects": .array([]),
                    "note": .string("This profile has no projects yet. " + register),
                ]))
            }

            let census = try await BridgeWorkspaceCensus.read(for: identity, from: store)

            var rows: [JSONValue] = []
            for project in projects {
                rows.append(Self.row(project, census: census))
            }

            let hidden = ProjectVisibility.hiddenCount(projects)
            guard hidden > 0 else { return .json(.object(["projects": .array(rows)])) }
            let wayBack = identity.role == .owner
                ? "and project_unhide puts one back in the list."
                : "and the owner can put one back in the list."
            return .json(.object([
                "projects": .array(rows),
                "hidden_projects": .integer(hidden),
                "note": .string(
                    "\(hidden == 1 ? "One project is" : "\(hidden) projects are") hidden from "
                        + "Unified Dev's sidebar. That is a view preference and nothing else: they are "
                        + "still projects, their workspaces still run, " + wayBack
                ),
            ]))
        } catch {
            return .failure("Unified Dev could not read its projects: \(error.readableMessage)")
        }
    }

    private func across(_ profiles: [Profile], store: Store) async throws -> BridgeToolResult {
        let census = try await BridgeWorkspaceCensus.read(in: profiles, from: store)
        let every = try await store.repos()
        var rows: [JSONValue] = []
        for profile in profiles {
            for project in ProfileScope.repos(every, in: profile.id) {
                rows.append(BridgeProfileReach.tagged(Self.row(project, census: census), profile: profile))
            }
        }
        return BridgeWorkspaceQuote.answer(
            .object(["projects": .array(rows)]), preamble: BridgeWorkspaceQuote.lists("projects")
        )
    }

    private static func row(_ project: Repo, census: BridgeWorkspaceCensus) -> JSONValue {
        let counts = census.counts(repoID: project.id)
        return .object([
            "id": .string(project.id.rawValue),
            "name": .string(project.name),
            "path": .string(project.path),
            "default_branch": .string(project.defaultBranch),
            "workspaces": .integer(counts.workspaces),
            "agents_running": .integer(counts.agentsRunning),
            "awaiting_permission": .integer(counts.awaitingPermission),
            "on_disk": .bool(FileManager.default.fileExists(atPath: project.path)),
            "hidden": .bool(project.hidden),
        ])
    }
}
