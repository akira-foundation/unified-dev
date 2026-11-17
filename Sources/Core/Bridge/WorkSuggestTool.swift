import Foundation

public struct WorkSuggestTool: BridgeToolHandling {
    public static let name = "work_suggest"
    public static let titleLimit = 80
    public static let whyLimit = 400
    public static let promptLimit = WorkspaceSayTool.maximumLength

    public init() {}

    public let roles: Set<BridgeRole> = [.workspace, .owner]

    public let tool = BridgeTool(
        name: WorkSuggestTool.name,
        description: """
            Suggest a piece of work to the owner instead of starting it. Unified Dev puts a card in \
            this chat, below your message, with your title, your reason and the whole prompt, and \
            the owner decides with one click whether it starts and where: as a new workspace of its \
            own, or here, as a subagent of this chat. Nothing starts until the owner presses a button.

            Use it for work you found outside what you were asked to do: a defect in another part \
            of the code, a fix that belongs in another repository, a follow-up that deserves its \
            own pull request. Call workspace_start or agent_start yourself only when the owner has \
            asked you to start the work.

            'title' names the work in a few words. 'why' is one sentence saying why you are \
            suggesting it now. 'prompt' is everything the agent that does it gets: it cannot see \
            this conversation, so write it as if to somebody who has just opened the project, and \
            say what finished looks like.

            'project' is optional. Leave it out for the project this chat is in. Otherwise name a \
            project Unified Dev has, by its name or its path; give the absolute path of a repository \
            on this Mac that is not in Unified Dev yet; or give owner/repository for one that is only \
            on GitHub. The card says which, and one that is only on GitHub cannot be started from \
            the card yet.

            A workspace holds \(WorkSuggestion.undecidedLimit) suggestions waiting for the owner at \
            once. It answers at once with the suggestion's id: keep it, because work_withdraw takes \
            it if the suggestion stops making sense. Do not wait for the owner's decision: carry on \
            with your own work.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "title": .object([
                    "type": .string("string"),
                    "description": .string("The work, named in a few words for the card."),
                ]),
                "why": .object([
                    "type": .string("string"),
                    "description": .string("One sentence: why you are suggesting it now."),
                ]),
                "prompt": .object([
                    "type": .string("string"),
                    "description": .string(
                        "Everything the agent that does it gets, written for someone who cannot "
                            + "see this conversation. Say what finished looks like."
                    ),
                ]),
                "project": .object([
                    "type": .string("string"),
                    "description": .string(
                        "Where the work goes. Leave it out for this chat's project. Otherwise a "
                            + "project's name or path, the absolute path of a repository on this Mac, "
                            + "or owner/repository on GitHub."
                    ),
                ]),
            ]),
            "required": .array([.string("title"), .string("why"), .string("prompt")]),
        ])
    )

    public func call(
        _ request: MCPRequest,
        as identity: BridgeIdentity,
        store: Store
    ) async -> BridgeToolResult {
        guard let sessionID = identity.sessionID else {
            return .failure(WorkSuggestTrouble.noChat(tool: Self.name).sentence)
        }

        let fields: Fields
        switch Fields.read(request) {
        case .failure(let trouble): return .failure(trouble.sentence)
        case .success(let read): fields = read
        }

        do {
            let projects = try await BridgeProfileScope.repos(for: identity, store: store)
            var callerProject: RepoID?
            if let workspaceID = identity.workspaceID {
                guard let caller = try await store.workspace(id: workspaceID) else {
                    return .failure(WorkSuggestTrouble.callerHasGone.sentence)
                }
                callerProject = caller.repoID
            }

            let target: WorkSuggestion.Target
            switch WorkSuggestionTarget.read(
                request.stringParam("project"), callerProject: callerProject, projects: projects
            ) {
            case .failure(let trouble): return .failure(trouble.sentence)
            case .success(let read):
                target = await WorkSuggestionTarget.resolving(read, callerProject: callerProject, projects: projects)
            }

            let suggestion = WorkSuggestion(
                workspaceID: identity.workspaceID, sessionID: sessionID,
                title: fields.title, why: fields.why, prompt: fields.prompt, target: target
            )
            switch try await store.addWorkSuggestion(suggestion) {
            case .full(let undecided): return .failure(WorkSuggestTrouble.full(undecided: undecided).sentence)
            case .added(let added): return .json(Self.answer(for: added, projects: projects))
            }
        } catch {
            return .failure(WorkSuggestTrouble.unexplained(tool: Self.name, error.readableMessage).sentence)
        }
    }

    struct Fields {
        let title: String
        let why: String
        let prompt: String

        static func read(_ request: MCPRequest) -> Result<Fields, WorkSuggestTrouble> {
            var values: [String] = []
            let limits = [
                ("title", WorkSuggestTool.titleLimit),
                ("why", WorkSuggestTool.whyLimit),
                ("prompt", WorkSuggestTool.promptLimit),
            ]
            for (field, limit) in limits {
                guard let value = AgentStartTool.text(request.stringParam(field)) else {
                    return .failure(.missing(field: field))
                }
                guard !HiddenText.hides(value) else { return .failure(.hiddenCharacters(field: field)) }
                guard value.unicodeScalars.count <= limit else { return .failure(.tooLong(field: field, limit: limit)) }
                values.append(value)
            }
            return .success(Fields(title: WorkspaceMessage.oneLine(values[0]), why: values[1], prompt: values[2]))
        }
    }

    static func answer(for suggestion: WorkSuggestion, projects: [Repo]) -> JSONValue {
        .object([
            "suggestion_id": .string(suggestion.id.rawValue),
            "state": .string("waiting_for_the_owner"),
            "where": .string(place(of: suggestion.target, projects: projects)),
            "note": .string(
                "Nothing has started. The owner sees a card below your message and decides whether it "
                    + "starts and where. Carry on with your own work, and withdraw it with work_withdraw "
                    + "and this id if it stops making sense."
            ),
        ])
    }

    static func place(of target: WorkSuggestion.Target, projects: [Repo]) -> String {
        switch target {
        case .sameProject:
            "The project this chat is in."
        case .project(let id):
            "The project '\(projects.first { $0.id == id }?.name ?? id.rawValue)'."
        case .folder(let path):
            "The repository at \(path), which Unified Dev does not have yet. The owner can add it from the card."
        case .remote(let slug):
            "\(slug) on GitHub, which has to be cloned and added before it can start. The card says so and offers no start."
        case .orchestrator(let id):
            "The orchestrator of '\(projects.first { $0.id == id }?.name ?? id.rawValue)', started on the owner's click."
        }
    }
}
