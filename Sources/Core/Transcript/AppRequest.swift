import Foundation

public enum AppRequest {
    public enum Source: Sendable, CaseIterable {
        case pullRequestBar
        case inspectorToolbar
        case agentThroughBridge

        public var hidesTurn: Bool {
            switch self {
            case .pullRequestBar: true
            case .inspectorToolbar, .agentThroughBridge: false
            }
        }
    }

    public static let unconfirmedSentence =
        "Unified Dev could not confirm that its request reached the agent. Send it again only if the agent did not answer."

    public static let mergeWaitsForTheTurn =
        "The agent is still working here, so the merge was not queued out of sight. Merge again when it finishes."

    public static func mergeRefusal(from source: Source, agentIsBusy: Bool) -> String? {
        source.hidesTurn && agentIsBusy ? mergeWaitsForTheTurn : nil
    }

    public static let sentBy = "unified_dev"

    private static let eventMarker = Data("\"app_request\"".utf8)

    public static func delivery(
        to sessionID: SessionID, text: String, interactionMode: InteractionMode?
    ) -> Delivery {
        var delivery = Delivery(targetSessionID: sessionID, kind: .report, crew: .appRequest(text))
        delivery.interactionMode = interactionMode
        return delivery
    }

    public static func isHidden(kind: MessageKind, payload: Data) -> Bool {
        sentText(kind: kind, payload: payload) != nil
    }

    public static func isHidden(_ delivery: Delivery) -> Bool {
        delivery.crewMessage?.event == .appRequest
    }

    public static func isStuck(_ delivery: Delivery) -> Bool {
        delivery.state == .uncertain || (delivery.state == .pending && delivery.deliveredSeq != nil)
    }

    public static func sentText(kind: MessageKind, payload: Data) -> String? {
        guard kind == .crew, payload.range(of: eventMarker) != nil,
              let crew = CrewMessage.decode(payload), crew.event == .appRequest else { return nil }
        return crew.sent
    }
}
