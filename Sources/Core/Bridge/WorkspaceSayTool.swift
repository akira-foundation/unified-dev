import Foundation

public enum WorkspaceMessageDeliveryOutcome: Sendable, Equatable {
    case sent(WorkspaceMessage)
    case refused(String)
}

public typealias WorkspaceMessageDelivering =
    @Sendable (WorkspaceMessage) async -> WorkspaceMessageDeliveryOutcome

public struct WorkspaceSayTool: BridgeToolHandling {
    public static let name = "workspace_say"

    public static let maximumLength = 20_000

    private let deliver: WorkspaceMessageDelivering

    public init(_ deliver: @escaping WorkspaceMessageDelivering) {
        self.deliver = deliver
    }

    public let roles: Set<BridgeRole> = [.workspace, .owner]

    public let tool = BridgeTool(
        name: WorkspaceSayTool.name,
        description: """
            Send a message to the agent in another Unified Dev workspace. It lands in that workspace's \
            chat and starts a turn there, the way agent_say does for a subagent in your own \
            workspace, or waits for the turn that is running.

            Name the workspace by the id workspace_list or workspace_start reports, or by its name \
            when no other workspace shares it. To answer a message that reached you from another \
            workspace, pass the id it names: your answer goes to the chat there that most recently \
            wrote to you.

            The message arrives with the owner's authority, headed with the workspace, project and \
            chat it came from, so the agent there may act on it as though the owner had typed it: \
            "fix the bug, merge the pull request, tag a release, then tell me the version with \
            workspace_say" is a message it will carry out. Write it as a message to that agent. It \
            cannot see this conversation.

            The owner can cancel it while it is still waiting in that chat's queue. Once the agent \
            there has started reading it, it can no longer be taken back. Either way, Unified Dev \
            tells you here.

            It returns once the message is in that chat. It does not wait for an answer and there \
            is no way to wait for one from here, so say what you sent and get on with your own \
            work. An answer arrives in this chat as a message of its own.

            Unified Dev refuses a message identical to one you sent the same workspace in the last \
            \(WorkspaceSayThrottle.windowMinutes) minutes, and more than \
            \(WorkspaceSayThrottle.limit) messages to the same workspace in that time. Do not \
            thank or acknowledge an answer with another message: that starts a turn there for \
            nothing.

            Pass notify_when_done: true to have Unified Dev tell this chat once, by itself, when \
            the turn your message causes there comes to rest: finished (with that agent's last \
            message), failed (with the reason), or blocked waiting on the owner for a permission \
            prompt or a question. With it, there is no need to ask the other agent to report back \
            when it is done.

            Pass profile to send it to another profile, once the owner has opened it. A workspace \
            on Claude Code launched in Accept edits can write to a project's orchestrator there, by its workspace id or by passing project \
            instead of workspace; only a project's orchestrator and the owner's own clients can write \
            to its other workspaces. Such a message arrives marked as coming from outside, without \
            the owner's authority, and the agent there is told to ask the owner before acting on it. \
            When the project has no orchestrator, the owner gets a card asking to start one, and the \
            message is delivered to it once they do. Pass notify_when_done to hear how the turn ended.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "workspace": .object([
                    "type": .string("string"),
                    "description": .string(
                        "The workspace to send it to, by the id workspace_list reports, or by its "
                            + "name when no other workspace shares it. To answer a message, the "
                            + "id it names."
                    ),
                ]),
                "project": .object([
                    "type": .string("string"),
                    "description": .string(
                        "Instead of workspace: the project whose orchestrator should receive it, by the id "
                            + "or name project_list reports."
                    ),
                ]),
                BridgeProfileReach.argument: BridgeProfileReach.schemaProperty,
                "message": .object([
                    "type": .string("string"),
                    "description": .string(
                        "What to say, written to that agent. It cannot see this conversation."
                    ),
                ]),
                WorkspaceDoneWatch.argument: .object([
                    "type": .string("boolean"),
                    "description": .string(
                        "Have Unified Dev tell this chat once when the turn this message causes "
                            + "there comes to rest: finished, failed, or waiting on the owner. "
                            + "Defaults to false."
                    ),
                ]),
            ]),
            "required": .array([.string("message")]),
        ])
    )

    public func call(
        _ request: MCPRequest,
        as identity: BridgeIdentity,
        store: Store
    ) async -> BridgeToolResult {
        guard let text = AgentStartTool.text(request.stringParam("message")) else {
            return .failure(WorkspaceSayTrouble.noMessage.sentence)
        }
        guard text.count <= Self.maximumLength else {
            return .failure(WorkspaceSayTrouble.tooLong(count: text.count).sentence)
        }
        let given = AgentStartTool.text(request.stringParam("workspace"))
        let project = AgentStartTool.text(request.stringParam("project"))
        guard given != nil || project != nil else { return .failure(WorkspaceSayTrouble.noWorkspace.sentence) }

        do {
            let sender = try await Sender.resolve(identity, store: store)
            if identity.workspaceID != nil, sender.workspace == nil {
                return .failure(WorkspaceSayTrouble.callerHasGone.sentence)
            }
            let choice: BridgeProfileChoice
            switch try await BridgeProfileReach.choice(request, allowsEvery: false, for: .talk, as: identity, store: store) {
            case .failure(let trouble): return .failure(WorkspaceSayTrouble.appRefused(trouble.sentence).sentence)
            case .success(let resolved): choice = resolved
            }
            let target: Workspace
            switch try await WorkspaceSayDestination.resolve(
                workspace: given, project: project, in: choice, as: identity, store: store
            ) {
            case .failure(let trouble): return .failure(trouble.sentence)
            case .success(.noOrchestrator(let repo)):
                return try await WorkspaceSayDestination.awaitOrchestrator(repo, saying: text, as: identity, store: store)
            case .success(.workspace(let found)): target = found
            }

            if let source = sender.workspace, source.id == target.id {
                return .failure(WorkspaceSayTrouble.toItself.sentence)
            }

            if identity.role != .owner, let source = sender.workspace {
                let now = Date()
                let recent = try await store.workspaceMessages(
                    from: source.id, to: target.id, since: now.addingTimeInterval(-WorkspaceSayThrottle.window)
                )
                if let trouble = WorkspaceSayThrottle.refusal(
                    sending: text, to: Self.crossed(choice) ? target.id.rawValue : target.name, recent: recent, now: now
                ) {
                    return .failure(trouble.sentence)
                }
            }

            let wantsNotice = WorkspaceDoneWatch.isRequested(request.param(WorkspaceDoneWatch.argument))
            let crossedTo: String?
            let destination: Profile?
            if case .other(let profile) = choice { destination = profile } else { destination = nil }
            crossedTo = destination?.name
            let message = try await WorkspaceMessageComposer.compose(
                text, to: target, crossingTo: destination, notify: wantsNotice, as: identity, store: store
            )

            switch await deliver(message) {
            case .refused(let sentence):
                let said = crossedTo == nil ? sentence : "Unified Dev could not put it in that workspace's chat."
                return .failure(WorkspaceSayTrouble.appRefused(said).sentence)
            case .sent(let sent):
                let answer = Self.answer(sent, noticeRequested: wantsNotice, crossedTo: crossedTo)
                guard crossedTo != nil else { return .json(answer) }
                return BridgeWorkspaceQuote.answer(answer, preamble: BridgeWorkspaceQuote.lists("where a message went"))
            }
        } catch {
            return .failure(WorkspaceSayTrouble.unexplained(error.readableMessage).sentence)
        }
    }

    struct Sender {
        var workspace: Workspace?
        var project: Repo?
        var session: Session?

        var end: WorkspaceMessageEnd {
            guard let workspace else { return .ownerClient }
            return WorkspaceMessageEnd(
                workspaceID: workspace.id,
                workspace: workspace.name,
                project: project?.name ?? "",
                sessionID: session?.id,
                chat: session?.title ?? ""
            )
        }

        static func resolve(_ identity: BridgeIdentity, store: Store) async throws -> Sender {
            var sender = Sender()
            if let workspaceID = identity.workspaceID {
                sender.workspace = try await store.workspace(id: workspaceID)
            }
            if let repoID = sender.workspace?.repoID {
                sender.project = try await store.repo(id: repoID)
            }
            if let sessionID = identity.sessionID {
                sender.session = try await store.session(id: sessionID)
            }
            return sender
        }
    }

    private static func crossed(_ choice: BridgeProfileChoice) -> Bool {
        if case .other = choice { return true }
        return false
    }

    static func target(
        named given: String, as identity: BridgeIdentity, store: Store, in choice: BridgeProfileChoice = .own
    ) async throws -> Result<Workspace, WorkspaceSayTrouble> {
        let lookup: BridgeWorkspaceLookup.ActiveTarget
        if case .other(let profile) = choice {
            lookup = try await BridgeWorkspaceLookup.activeTarget(given, in: profile, store: store)
        } else {
            lookup = try await BridgeWorkspaceLookup.activeTarget(given, as: identity, store: store)
        }
        switch lookup {
        case .found(let workspace): return .success(workspace)
        case .ambiguous(let ids): return .failure(.ambiguous(given: given, ids: ids))
        case .archived(let name): return .failure(.archived(name: name))
        case .unknown(let known): return .failure(.unknown(given: given, known: known))
        }
    }

    enum Key {
        static let state = "state"
        static let messageID = "message_id"
        static let workspaceID = "workspace_id"
        static let workspace = "workspace"
        static let project = "project"
        static let chat = "chat"
        static let note = "note"
        static let notifyWhenDone = WorkspaceDoneWatch.argument
        static let profile = BridgeProfileReach.argument
    }

    static func answer(
        _ message: WorkspaceMessage, noticeRequested: Bool = false, crossedTo profile: String? = nil
    ) -> JSONValue {
        let reply = message.source.workspaceID == nil
            ? "This connection is not a workspace, so the agent there cannot answer you with "
                + "workspace_say. Call workspace_list to see what became of it."
            : profile != nil
            ? "It can answer with workspace_say while both profiles stay open, an orchestrator always and "
                + "another workspace only when you are an orchestrator. Use notify_when_done to hear how its "
                + "turn ended."
            : "If it answers, it answers with workspace_say, and its message lands in this chat, "
                + "unless a message from another chat in this workspace reaches it first."
        let chat = message.target.chat
        let authority = profile.map { " in the profile '\($0)', marked as coming from outside and without the owner's authority" }
            ?? ", with the owner's authority"
        var fields: [String: JSONValue] = [
            Key.state: .string(message.state.rawValue),
            Key.messageID: .string(message.id.rawValue),
            Key.workspaceID: message.target.workspaceID.map { .string($0.rawValue) } ?? .null,
            Key.workspace: .string(message.target.workspace),
            Key.project: .string(message.target.project),
            Key.chat: .string(chat),
            Key.notifyWhenDone: .bool(message.notifyWhenDone),
            Key.note: .string(
                "Sent to the chat '\(chat)' in '\(message.target.workspace)'\(authority). "
                    + "It starts a turn there, or waits for the one that is running, "
                    + "and the owner can cancel it until the agent there starts reading it. Unified "
                    + "Dev does not wait for an answer, so get on with your own work. " + reply
                    + noticeLine(for: message, requested: noticeRequested)
            ),
        ]
        if let profile { fields[Key.profile] = .string(profile) }
        return .object(fields)
    }

    private static func noticeLine(for message: WorkspaceMessage, requested: Bool) -> String {
        if message.notifyWhenDone {
            return " Unified Dev will tell this chat once, by itself, when the turn this message "
                + "causes there comes to rest: finished, failed, or waiting on the owner."
        }
        guard requested else { return "" }
        return " notify_when_done was ignored: this connection is not a chat in a Unified Dev "
            + "workspace, so there is nowhere to deliver the notice."
    }
}
