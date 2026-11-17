import Foundation

public enum HandoffMark: Codable, Sendable, Equatable {
    case continued(agent: AgentKind, model: String, from: AgentKind, account: String? = nil)
    case resuming

    public var sentence: String {
        switch self {
        case .continued(let agent, let model, let from, let account):
            if from == agent, let account, !account.isEmpty {
                "Continued with \(agent.label) under \(account) · \(model)"
            } else {
                "Continued with \(agent.label) · \(model)"
            }
        case .resuming: "Resuming the interrupted task"
        }
    }

    public var withoutAccount: HandoffMark {
        guard case .continued(let agent, let model, let from, _) = self else { return self }
        return .continued(agent: agent, model: model, from: from)
    }

    public var payload: Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    public static func decode(_ payload: Data) -> HandoffMark? {
        try? JSONDecoder().decode(HandoffMark.self, from: payload)
    }

    static func lastLeavingAgent(in rows: [Message]) -> AgentKind? {
        for row in rows.reversed() where row.kind == .handoff {
            if case .continued(_, _, let from, _)? = decode(row.payload) { return from }
        }
        return nil
    }
}
