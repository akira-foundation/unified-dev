import Foundation

public struct AgentSessionSettlement: Sendable, Equatable {
    public enum Purpose: Sendable, Equatable {
        case sending
        case answering
    }

    public let recordedAccount: AgentAccountID?
    public let switchTarget: SessionSegmentTarget?
    public var leavesARemovedAccount = false

    public static let nothing = AgentSessionSettlement(recordedAccount: nil, switchTarget: nil)

    public static let lostAccountKeyPrefix = "chat.lostAccount."

    public static func lostAccountKey(sessionID: SessionID) -> String {
        lostAccountKeyPrefix + sessionID.rawValue
    }

    public var changesNothing: Bool { self == .nothing }

    public static func decide(
        session: Session,
        account: AgentAccountHome?,
        purpose: Purpose,
        lostItsAccount: Bool = false
    ) -> AgentSessionSettlement {
        guard purpose == .sending, let account, session.accountID != account.id else { return .nothing }
        let hasHistory = !(session.agentSessionID ?? "").isEmpty
        let target = SessionSegmentTarget(
            agentKind: session.agentKind, accountID: account.id, model: session.model, effort: session.effort
        )
        if session.accountID != nil {
            return AgentSessionSettlement(recordedAccount: nil, switchTarget: target)
        }
        if lostItsAccount {
            return AgentSessionSettlement(recordedAccount: nil, switchTarget: target, leavesARemovedAccount: true)
        }
        return hasHistory ? .nothing : AgentSessionSettlement(recordedAccount: account.id, switchTarget: nil)
    }

    public func notice(on account: AgentAccountHome?, among standings: [AgentAccountStanding], besides other: String?) -> String? {
        guard switchTarget != nil, let account else { return other }
        let name = AgentAccountNames.spoken(of: account, among: standings)
        let moved = leavesARemovedAccount
            ? "The account this chat ran under was removed, so it moved to \(name) and its history went with it."
            : "This chat moved to \(name), the account it is set to run under, and its history went with it."
        return [moved, other].compactMap(\.self).joined(separator: " ")
    }

    public static func resumable(session: Session, account: AgentAccountHome?) -> String? {
        guard let account, let owner = session.accountID, owner != account.id else {
            return session.agentSessionID
        }
        return nil
    }

    public static let noSegment =
        "Unified Dev could not find this chat's saved state, so it did not start the agent."

    public static let chatMoved = writeFailure("the chat moved to another account while it was starting.")

    public static func resolutionFailure(_ detail: String) -> String {
        "Unified Dev could not work out which account to run under: \(detail)"
    }

    public static func resolutionFailure(_ error: Error) -> String {
        if let refusal = error as? AgentAccountRefusal { return refusal.description }
        return resolutionFailure(error.readableMessage)
    }

    public static func writeFailure(_ detail: String) -> String {
        "Unified Dev could not record which account this chat runs under, so it did not start the agent: \(detail)"
    }
}
