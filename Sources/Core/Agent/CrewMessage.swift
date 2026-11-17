import Foundation

public struct CrewMessage: Sendable, Equatable, Codable {
    public enum Event: String, Sendable, Codable {
        case brief
        case said
        case stopped
        case failed
        case relayed
        case cancelled
        case workspaceDone = "workspace_done"
        case workspaceStarted = "workspace_started"
        case appRequest = "app_request"
    }

    public enum Sender: String, Sendable, Codable {
        case orchestrator
        case subagent
        case unifieddev
        case otherWorkspace = "other_workspace"
    }

    public var event: Event
    public var sender: Sender
    public var from: String
    public var text: String
    public var sent: String
    public var route: WorkspaceMessageEnd?

    public init(
        event: Event, sender: Sender, from: String, text: String, sent: String,
        route: WorkspaceMessageEnd? = nil
    ) {
        self.event = event
        self.sender = sender
        self.from = from
        self.text = text
        self.sent = sent
        self.route = route
    }

    public static func said(from name: String, text: String, sender: Sender) -> CrewMessage {
        CrewMessage(
            event: .said,
            sender: sender,
            from: name,
            text: text,
            sent: BridgeUntrustedText.wrapSaying(text, from: sender == .subagent
                ? "your subagent \"\(name)\""
                : "the agent that started you, \"\(name)\"")
        )
    }

    public static func brief(from orchestrator: String, task: String) -> CrewMessage {
        CrewMessage(
            event: .brief, sender: .orchestrator, from: orchestrator, text: task, sent: task
        )
    }

    public static func stopped(name: String, lastMessage: String?) -> CrewMessage {
        let sentence = Crew.stoppedSentence(name: name, lastMessage: lastMessage)
        return CrewMessage(
            event: .stopped, sender: .unifieddev, from: name,
            text: Crew.stoppedSummary(name: name), sent: sentence
        )
    }

    public static func stoppedByOwner(name: String) -> CrewMessage {
        CrewMessage(
            event: .stopped, sender: .unifieddev, from: name,
            text: Crew.stoppedByOwnerSummary(name: name),
            sent: Crew.stoppedByOwnerSentence(name: name)
        )
    }

    public static func failed(name: String, reason: String) -> CrewMessage {
        let sentence = Crew.failedSentence(name: name, reason: reason)
        return CrewMessage(
            event: .failed, sender: .unifieddev, from: name,
            text: Crew.failedSummary(name: name, reason: reason), sent: sentence
        )
    }

    public static func cancelled(to named: String, text: String, acrossProfilesID: WorkspaceID? = nil) -> CrewMessage {
        let workspace = acrossProfilesID?.rawValue ?? WorkspaceMessage.oneLine(named)
        let excerpt = text.count > 120 ? String(text.prefix(120)) + "…" : text
        return CrewMessage(
            event: .cancelled, sender: .unifieddev, from: workspace,
            text: "The owner cancelled your message to \(workspace)",
            sent: """
                The owner cancelled the message you sent to the workspace "\(workspace)" with \
                workspace_say before it was delivered, so its agent never saw it. It began: \
                '\(excerpt)'. Do not send it again unless the owner asks you to.
                """
        )
    }

    public static func appRequest(_ text: String) -> CrewMessage {
        CrewMessage(event: .appRequest, sender: .unifieddev, from: "Unified Dev", text: "", sent: text)
    }

    public static let type = "crew"

    public func payload() throws -> Data {
        try JSONEncoder().encode(Stored(self))
    }

    public static func decode(_ payload: Data) -> CrewMessage? {
        guard let stored = try? JSONDecoder().decode(Stored.self, from: payload),
              stored.type == Self.type else { return nil }
        return stored.message
    }

    private struct Stored: Codable {
        var type: String
        var event: Event
        var sender: Sender
        var from: String
        var text: String
        var sent: String
        var route: WorkspaceMessageEnd?

        init(_ message: CrewMessage) {
            type = CrewMessage.type
            event = message.event
            sender = message.sender
            from = message.from
            text = message.text
            sent = message.sent
            route = message.route
        }

        var message: CrewMessage {
            CrewMessage(event: event, sender: sender, from: from, text: text, sent: sent, route: route)
        }
    }
}
